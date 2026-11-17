use crate::recording_audio::Options as AudioOptions;
use crate::recording_compose::compose;
use crate::util::*;
use anyhow::{Context, Result, bail};
use image::{
    RgbImage,
    imageops::{self, FilterType},
};
use serde_json::{Value, json};
use std::{
    fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::Command,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
const RECORD: &str = "dotfiles-hyprland-record.service";
#[derive(Debug, PartialEq, Eq)]
struct RecordingOptions {
    audio: AudioOptions,
    fps: u32,
}
impl RecordingOptions {
    fn parse(args: &[String]) -> Result<Self> {
        let mut fps = 60;
        let mut audio = vec![];
        let mut args = args.iter();
        while let Some(flag) = args.next() {
            if flag == "--fps" {
                fps = args
                    .next()
                    .context("Missing recording frame rate")?
                    .parse()?;
                if ![60, 120, 144, 165].contains(&fps) {
                    bail!("Recording frame rate must be 60, 120, 144, or 165");
                }
            } else {
                audio.push(flag.clone());
            }
        }
        Ok(Self {
            audio: AudioOptions::parse(&audio)?,
            fps,
        })
    }
    fn flags(&self) -> Vec<String> {
        let mut flags = vec!["--fps".into(), self.fps.to_string()];
        flags.extend(self.audio.flags().into_iter().map(String::from));
        flags
    }
}
fn preferences_path() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland/capture.json")
}
fn preferences() -> Value {
    read_json(&preferences_path())
        .ok()
        .filter(Value::is_object)
        .unwrap_or(json!({}))
}
fn recording() -> bool {
    Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", RECORD])
        .status()
        .is_ok_and(|s| s.success())
}
fn output_path(kind: &str) -> Result<PathBuf> {
    let image = kind == "image";
    let base = run(&["xdg-user-dir", if image { "PICTURES" } else { "VIDEOS" }])
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(|s| PathBuf::from(s.trim()))
        .unwrap_or_else(|| home().join(if image { "Pictures" } else { "Videos" }));
    let dir = base.join(if image { "Screenshots" } else { "Recordings" });
    fs::create_dir_all(&dir)?;
    Ok(dir.join(format!(
        "{}.{}",
        chrono::Local::now().format("capture-%Y%m%d-%H%M%S-%6f"),
        if image { "png" } else { "mp4" }
    )))
}
pub fn intersection(rect: &Value, out: &Value) -> Value {
    let x = n(rect, "x").max(n(out, "x"));
    let y = n(rect, "y").max(n(out, "y"));
    let right = (n(rect, "x") + n(rect, "width")).min(n(out, "x") + n(out, "width"));
    let bottom = (n(rect, "y") + n(rect, "height")).min(n(out, "y") + n(out, "height"));
    json!({"x":x,"y":y,"width":(right-x).max(0.),"height":(bottom-y).max(0.)})
}
fn selected<'a>(rect: &Value, outputs: &'a Value) -> Vec<(&'a Value, Value)> {
    rows(outputs)
        .iter()
        .filter_map(|o| {
            let p = intersection(rect, o);
            if n(&p, "width") > 0. && n(&p, "height") > 0. {
                Some((o, p))
            } else {
                None
            }
        })
        .collect()
}
pub fn frozen_image(outputs: &Value, rect: &Value, cursor: bool) -> Result<RgbImage> {
    let parts = selected(rect, outputs);
    let scale = parts
        .iter()
        .map(|(o, _)| o["scale"].as_f64().unwrap_or(1.))
        .fold(1., f64::max);
    let width = (n(rect, "width") * scale).round_ties_even() as u32;
    let height = (n(rect, "height") * scale).round_ties_even() as u32;
    if width == 0 || height == 0 || u64::from(width) * u64::from(height) > 256_000_000 {
        bail!("Capture dimensions exceed the image limit");
    }
    let mut canvas = RgbImage::new(width, height);
    for (o, p) in parts {
        let source = url::Url::parse(s(o, if cursor { "cursor" } else { "plain" }))?
            .to_file_path()
            .map_err(|_| anyhow::anyhow!("Expected a local capture image"))?;
        let image = image::open(source)?.to_rgb8();
        let sx = image.width() as f64 / n(o, "width");
        let sy = image.height() as f64 / n(o, "height");
        let x = ((n(&p, "x") - n(o, "x")) * sx).round_ties_even().max(0.) as u32;
        let y = ((n(&p, "y") - n(o, "y")) * sy).round_ties_even().max(0.) as u32;
        let right = ((n(&p, "x") + n(&p, "width") - n(o, "x")) * sx)
            .round_ties_even()
            .min(image.width() as f64) as u32;
        let bottom = ((n(&p, "y") + n(&p, "height") - n(o, "y")) * sy)
            .round_ties_even()
            .min(image.height() as f64) as u32;
        if right <= x || bottom <= y {
            continue;
        }
        let crop = imageops::crop_imm(&image, x, y, right - x, bottom - y).to_image();
        let crop = imageops::resize(
            &crop,
            (n(&p, "width") * scale).round_ties_even().max(1.) as u32,
            (n(&p, "height") * scale).round_ties_even().max(1.) as u32,
            FilterType::Lanczos3,
        );
        imageops::replace(
            &mut canvas,
            &crop,
            ((n(&p, "x") - n(rect, "x")) * scale).round_ties_even() as i64,
            ((n(&p, "y") - n(rect, "y")) * scale).round_ties_even() as i64,
        );
    }
    Ok(canvas)
}
fn capture_outputs(monitors: &Value, directory: &Path) -> Result<Value> {
    let mut outputs = vec![];
    let mut jobs = vec![];
    for (i, m) in rows(monitors).iter().enumerate() {
        if m["disabled"] == true {
            continue;
        }
        let scale = m["scale"]
            .as_f64()
            .filter(|&s| s > 0.)
            .context("Invalid monitor scale")?;
        let (mut w, mut h) = (n(m, "width"), n(m, "height"));
        if m["transform"].as_u64().unwrap_or(0) % 2 == 1 {
            std::mem::swap(&mut w, &mut h);
        }
        let plain = directory.join(format!("screen-{i}.ppm"));
        let cursor = directory.join(format!("screen-{i}-cursor.ppm"));
        for (path, with_cursor) in [(&plain, false), (&cursor, true)] {
            let mut c = command(&["grim", "-t", "ppm"]);
            if with_cursor {
                c.arg("-c");
            }
            c.args(["-o", s(m, "name")]).arg(path);
            jobs.push(c);
        }
        outputs.push(json!({"name":m["name"],"x":m["x"],"y":m["y"],"width":w/scale,"height":h/scale,"scale":scale,"focused":m["focused"],"plain":url::Url::from_file_path(plain).unwrap().as_str(),"cursor":url::Url::from_file_path(cursor).unwrap().as_str()}));
    }
    // At most four grim processes, matching the original capture batch.
    while !jobs.is_empty() {
        let batch: Vec<_> = jobs.drain(..jobs.len().min(4)).collect();
        let handles: Vec<_> = batch
            .into_iter()
            .map(|c| std::thread::spawn(|| output(c, None, Duration::from_secs(10))))
            .collect();
        for h in handles {
            h.join()
                .map_err(|_| anyhow::anyhow!("Capture worker failed"))??;
        }
    }
    Ok(json!(outputs))
}
fn capture_ipc(args: &[&str]) -> Result<String> {
    let mut c = command(&[
        "quickshell",
        "ipc",
        "--path",
        &root().join("tools/capture-daemon.qml").to_string_lossy(),
        "call",
        "capture",
    ]);
    c.args(args);
    output(c, None, Duration::from_secs(2))
}
fn open_warm(directory: &Path) -> Result<bool> {
    let pid = match UnixStream::connect(runtime()?.join("dotfiles-capture.sock")) {
        Ok(mut client) => {
            client.set_read_timeout(Some(Duration::from_secs(2)))?;
            client.set_write_timeout(Some(Duration::from_secs(2)))?;
            writeln!(client, "{}", json!({"action":"open","directory":directory}))?;
            let mut bytes = vec![];
            let mut b = [0; 1024];
            loop {
                let n = client.read(&mut b)?;
                if n == 0 || bytes.len() > 65536 {
                    bail!("Capture UI did not acknowledge the session");
                }
                bytes.extend_from_slice(&b[..n]);
                if bytes.contains(&b'\n') {
                    break;
                }
            }
            let line = bytes.split(|&b| b == b'\n').next().unwrap();
            let reply: Value = serde_json::from_slice(line)?;
            if reply["accepted"] != true {
                bail!("The capture UI is already busy");
            }
            reply["pid"]
                .as_i64()
                .filter(|&pid| pid > 0 && pid <= i32::MAX as i64)
                .context("Invalid capture UI process ID")? as i32
        }
        Err(e)
            if matches!(
                e.kind(),
                std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
            ) =>
        {
            let pid = run(&[
                "systemctl",
                "--user",
                "show",
                "dotfiles-hyprland-capture.service",
                "--property=MainPID",
                "--value",
            ])
            .ok()
            .and_then(|s| s.trim().parse::<i32>().ok())
            .unwrap_or(0);
            if pid <= 0
                || capture_ipc(&["open", &directory.to_string_lossy()])
                    .ok()
                    .is_none_or(|s| s.trim() != "true")
            {
                return Ok(false);
            }
            pid
        }
        Err(e) => return Err(e.into()),
    };
    let mut polls = 0;
    while !directory.join("result.json").is_file() {
        if unsafe { libc::kill(pid, 0) } != 0
            && std::io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH)
        {
            bail!("The capture UI stopped before finishing");
        }
        std::thread::sleep(Duration::from_millis(25));
        polls += 1;
        if polls % 40 == 0
            && capture_ipc(&["status"])
                .ok()
                .and_then(|s| serde_json::from_str::<Value>(&s).ok())
                .is_some_and(|s| s["active"] == false)
        {
            return Ok(true);
        }
    }
    Ok(true)
}
fn select(mode: &str) -> Result<()> {
    if !["region", "window", "record"].contains(&mode) {
        bail!("Invalid capture mode");
    }
    if mode == "record" && recording() {
        let _ = capture_ipc(&["recordingStopped"]);
        run(&["systemctl", "--user", "stop", RECORD])?;
        return Ok(());
    }
    let Some(_lock) = try_lock(&runtime()?.join("dotfiles-capture.lock"))? else {
        return Ok(());
    };
    let monitors = json(&["hyprctl", "monitors", "-j"])?;
    let window = if mode == "window" {
        json(&["hyprctl", "activewindow", "-j"])?
    } else {
        Value::Null
    };
    let dir = tempfile::Builder::new()
        .prefix("dotfiles-capture-")
        .tempdir_in(runtime()?)?;
    let outputs = capture_outputs(&monitors, dir.path())?;
    if rows(&outputs).is_empty() {
        bail!("No active displays are available");
    }
    let preferences = preferences();
    if mode == "window" {
        let rect = json!({"x":window["at"][0],"y":window["at"][1],"width":window["size"][0],"height":window["size"][1]});
        let parts = selected(&rect, &outputs);
        if parts.is_empty() {
            bail!("The active window is outside the visible displays");
        }
        let left = parts
            .iter()
            .map(|(_, p)| n(p, "x"))
            .fold(f64::INFINITY, f64::min);
        let top = parts
            .iter()
            .map(|(_, p)| n(p, "y"))
            .fold(f64::INFINITY, f64::min);
        let right = parts
            .iter()
            .map(|(_, p)| n(p, "x") + n(p, "width"))
            .fold(f64::NEG_INFINITY, f64::max);
        let bottom = parts
            .iter()
            .map(|(_, p)| n(p, "y") + n(p, "height"))
            .fold(f64::NEG_INFINITY, f64::max);
        let image = frozen_image(
            &outputs,
            &json!({"x":left,"y":top,"width":right-left,"height":bottom-top}),
            preferences["cursor"] == true,
        )?;
        let path = output_path("image")?;
        image.save(&path)?;
        status(
            command(&["wl-copy", "--type", "image/png"]),
            Some(fs::read(path)?),
            Duration::from_secs(5),
        )?;
        return Ok(());
    }
    let data = json!({"mode":mode,"outputs":outputs,"render":dir.path().join("render.png"),"selection":null,"preferences":preferences});
    atomic_json(&dir.path().join("session.json"), &data)?;
    if open_warm(dir.path())? {
        return Ok(());
    }
    let mut c = command(&[
        "quickshell",
        "--path",
        &root().join("tools/capture.qml").to_string_lossy(),
    ]);
    c.env("DOTFILES_CAPTURE_SESSION", dir.path());
    if !c.status()?.success() {
        bail!("Capture UI failed");
    }
    Ok(())
}
fn session(args: &[String]) -> Result<(PathBuf, Value, Vec<String>)> {
    let mut args = args.to_vec();
    let dir = if args.first().is_some_and(|a| a == "--session") {
        let dir = PathBuf::from(arg(&args, 1)?);
        args.drain(..2);
        dir
    } else {
        std::env::var_os("DOTFILES_CAPTURE_SESSION")
            .map(PathBuf::from)
            .context("No capture session")?
    };
    let dir = dir.canonicalize()?;
    let data = read_json(&dir.join("session.json"))?;
    Ok((dir, data, args))
}
fn export(dir: &Path, data: &Value) -> Result<()> {
    let path = PathBuf::from(s(data, "render"));
    if path.parent() != Some(dir) || path.is_symlink() || !path.is_file() {
        bail!("The selected image could not be rendered");
    }
    let image = fs::read(path)?;
    if !image.starts_with(b"\x89PNG\r\n\x1a\n") {
        bail!("The rendered image is not a PNG");
    }
    let target = output_path("image")?;
    atomic(&target, &image)?;
    status(
        command(&["wl-copy", "--type", "image/png"]),
        Some(image),
        Duration::from_secs(5),
    )?;
    println!("{}", target.display());
    Ok(())
}
fn record(dir: &Path, data: &Value, args: &[String]) -> Result<()> {
    let name = arg(args, 1)?;
    let mut x = arg(args, 2)?.parse::<i64>()?;
    let mut y = arg(args, 3)?.parse::<i64>()?;
    let mut w = arg(args, 4)?.parse::<i64>()?;
    let mut h = arg(args, 5)?.parse::<i64>()?;
    let cursor = arg(args, 6)? == "yes";
    let options = RecordingOptions::parse(&args[7..])?;
    if name != "desktop" {
        let monitor = rows(&data["outputs"])
            .iter()
            .find(|o| s(o, "name") == name)
            .context("Monitor is no longer available")?;
        w = w.min(n(monitor, "width") as i64 - x);
        h = h.min(n(monitor, "height") as i64 - y);
        x += n(monitor, "x") as i64;
        y += n(monitor, "y") as i64;
    }
    w = w / 2 * 2;
    h = h / 2 * 2;
    if w < 2 || h < 2 {
        bail!("Select a larger recording area");
    }
    let rect = json!({"x":x,"y":y,"width":w,"height":h});
    let parts = selected(&rect, &data["outputs"]);
    if parts.is_empty() {
        bail!("Recording area is outside the visible displays");
    }
    let target = output_path("video")?;
    let mut c = command(&["systemd-run", "--user", "--wait", "--collect", "--quiet"]);
    c.arg(format!("--unit={RECORD}")).args([
        "--property=PartOf=graphical-session.target",
        "--property=KillSignal=SIGINT",
        // The worker finalizes the join after SIGINT; allow its bounded
        // duration-based composition budget plus shutdown/probing headroom.
        "--property=TimeoutStopSec=4200",
        "--property=KillMode=mixed",
        "--property=SuccessExitStatus=SIGINT",
        "--property=UMask=0077",
    ]);
    for key in [
        "WAYLAND_DISPLAY",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "XDG_CURRENT_DESKTOP",
        "PULSE_SERVER",
        "PULSE_COOKIE",
        "PULSE_RUNTIME_PATH",
        "PIPEWIRE_REMOTE",
        "PIPEWIRE_RUNTIME_DIR",
    ] {
        if let Ok(value) = std::env::var(key) {
            c.arg(format!("--setenv={key}={value}"));
        }
    }
    if parts.len() == 1
        && ["x", "y", "width", "height"]
            .iter()
            .all(|k| n(&parts[0].1, k) == n(&rect, k))
    {
        c.args([
            "--",
            "/usr/bin/wl-screenrec",
            "--geometry",
            &format!("{x},{y} {w}x{h}"),
            "--filename",
        ])
        .arg(&target)
        .args(["--max-fps", &options.fps.to_string()]);
        if !cursor {
            c.arg("--no-cursor");
        }
        options.audio.resolve()?.apply(&mut c);
    } else {
        c.arg("--")
            .arg(std::env::current_exe()?)
            .args(["capture", "--session"])
            .arg(dir)
            .args([
                "record-worker",
                &rect.to_string(),
                if cursor { "yes" } else { "no" },
            ])
            .arg(&target)
            .args(options.flags());
    }
    if !c.status()?.success() {
        bail!("Recorder failed; inspect its user-service journal");
    }
    if target.metadata()?.len() == 0 {
        bail!("Recorder produced no video");
    }
    println!("{}", target.display());
    Ok(())
}
fn record_worker(
    data: &Value,
    rect: &Value,
    cursor: bool,
    target: &Path,
    options: RecordingOptions,
) -> Result<()> {
    use wait_timeout::ChildExt;
    let parts = selected(rect, &data["outputs"]);
    if parts.is_empty() {
        bail!("Recording area is outside the visible displays");
    }
    let input = options.audio.resolve()?;
    let dir = tempfile::Builder::new()
        .prefix("capture-parts-")
        .tempdir_in(target.parent().context("Missing output directory")?)?
        .keep();
    let stop = Arc::new(AtomicBool::new(false));
    let mut handlers = vec![];
    for signal in [libc::SIGINT, libc::SIGTERM] {
        handlers.push(signal_hook::flag::register(signal, stop.clone())?);
    }
    let mut children = vec![];
    let mut clips = vec![];
    let started = Instant::now();
    let outcome = (|| -> Result<()> {
        for (i, (monitor, _)) in parts.into_iter().enumerate() {
            if stop.load(Ordering::Relaxed) {
                break;
            }
            let path = dir.join(format!("output-{i}.mkv"));
            let mut c = command(&[
                "/usr/bin/wl-screenrec",
                "--output",
                s(monitor, "name"),
                "--filename",
            ]);
            c.arg(&path).args(["--max-fps", &options.fps.to_string()]);
            if !cursor {
                c.arg("--no-cursor");
            }
            if i == 0 {
                input.apply(&mut c);
            }
            let offset = started.elapsed().as_secs_f64();
            children.push(c.spawn()?);
            clips.push((path, monitor.clone(), offset));
        }
        while !stop.load(Ordering::Relaxed) {
            for c in &mut children {
                if c.try_wait()?.is_some() {
                    bail!("A display recorder stopped unexpectedly");
                }
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        Ok(())
    })();
    for c in &mut children {
        if c.try_wait().ok().flatten().is_none() {
            unsafe {
                libc::kill(c.id() as i32, libc::SIGINT);
            }
        }
    }
    for c in &mut children {
        if c.wait_timeout(Duration::from_secs(15))
            .ok()
            .flatten()
            .is_none()
        {
            let _ = c.kill();
        }
        let _ = c.wait();
    }
    for h in handlers {
        signal_hook::low_level::unregister(h);
    }
    let outcome = outcome.and_then(|_| {
        if clips.is_empty()
            || clips
                .iter()
                .any(|(p, _, _)| p.metadata().map_or(true, |m| m.len() == 0))
        {
            bail!("A display recorder produced no video");
        }
        compose(&clips, rect, target, options.audio.enabled(), options.fps)
    });
    if outcome.is_ok() {
        fs::remove_dir_all(&dir)?;
    } else {
        eprintln!(
            "Uncombined display recordings retained in {}",
            dir.display()
        );
    }
    outcome
}
pub fn main(args: &[String]) -> Result<()> {
    if args.first().is_some_and(|s| s == "audio-input") {
        return emit(&AudioOptions::parse(&args[1..])?.resolve()?.description());
    }
    if args.first().is_some_and(|s| s == "select") {
        return select(arg(args, 1)?);
    }
    if args.first().is_some_and(|s| s == "preferences") {
        let data: Value = serde_json::from_str(arg(args, 1)?)?;
        if !data.is_object() {
            bail!("Expected capture preferences object");
        }
        return atomic_json(&preferences_path(), &data);
    }
    if args.first().is_some_and(|s| s == "stop") {
        run(&["systemctl", "--user", "stop", RECORD])?;
        return Ok(());
    }
    let (dir, data, args) = session(args)?;
    match arg(&args, 0)? {
        "info" => emit(&data),
        "export" => export(&dir, &data),
        "record" => record(&dir, &data, &args),
        "record-worker" => record_worker(
            &data,
            &serde_json::from_str(arg(&args, 1)?)?,
            arg(&args, 2)? == "yes",
            Path::new(arg(&args, 3)?),
            RecordingOptions::parse(&args[4..])?,
        ),
        x => bail!("Unknown capture action: {x}"),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recording_rates_are_validated_and_forwarded_with_audio() {
        assert_eq!(RecordingOptions::parse(&[]).unwrap().fps, 60);
        for fps in [60, 120, 144, 165] {
            let options = RecordingOptions::parse(&[
                "--mic".into(),
                "--fps".into(),
                fps.to_string(),
                "--speakers".into(),
            ])
            .unwrap();
            assert_eq!(options.fps, fps);
            assert!(options.audio.speakers && options.audio.microphone);
            assert_eq!(RecordingOptions::parse(&options.flags()).unwrap(), options);
        }
        for flags in [
            vec!["--fps"],
            vec!["--fps", "0"],
            vec!["--fps", "240"],
            vec!["--fps", "oops"],
            vec!["--unknown"],
        ] {
            assert!(
                RecordingOptions::parse(&flags.into_iter().map(String::from).collect::<Vec<_>>())
                    .is_err()
            );
        }
    }
    #[test]
    #[ignore = "requires FFmpeg with libx264; run on the recording host"]
    fn spanning_video_retains_one_audio_track_and_can_stay_silent() {
        let dir = tempfile::tempdir().unwrap();
        let first = dir.path().join("first.mkv");
        let second = dir.path().join("second.mkv");
        for (path, sound) in [(&first, true), (&second, false)] {
            let mut encoder = command(&[
                "ffmpeg",
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "color=red:s=32x32:r=60",
            ]);
            if sound {
                encoder.args(["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000"]);
            }
            encoder.args(["-t", "0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p"]);
            if sound {
                encoder.args(["-c:a", "pcm_s16le"]);
            }
            encoder.arg(path);
            output(encoder, None, Duration::from_secs(15)).unwrap();
        }
        let clips = vec![
            (
                first,
                json!({"x":-32,"y":0,"width":32,"height":32,"scale":1}),
                0.08,
            ),
            (
                second,
                json!({"x":0,"y":0,"width":32,"height":32,"scale":1}),
                0.02,
            ),
        ];
        let rect = json!({"x":-32,"y":0,"width":64,"height":32});
        for (audio, fps) in [(true, 60), (false, 60), (true, 165), (false, 165)] {
            let target = dir.path().join(format!("combined-{audio}-{fps}.mp4"));
            compose(&clips, &rect, &target, audio, fps).unwrap();
            let probe = json(&[
                "ffprobe",
                "-v",
                "error",
                "-show_streams",
                "-of",
                "json",
                &target.to_string_lossy(),
            ])
            .unwrap();
            let streams = probe["streams"].as_array().unwrap();
            assert_eq!(
                streams
                    .iter()
                    .filter(|s| s["codec_type"] == "audio")
                    .count(),
                usize::from(audio)
            );
            let video = streams.iter().find(|s| s["codec_type"] == "video").unwrap();
            assert_eq!(video["r_frame_rate"], format!("{fps}/1"));
            assert_eq!(
                (video["width"].as_u64(), video["height"].as_u64()),
                (Some(64), Some(32))
            );
            if audio {
                let track = streams.iter().find(|s| s["codec_type"] == "audio").unwrap();
                let start = track["start_time"]
                    .as_str()
                    .unwrap()
                    .parse::<f64>()
                    .unwrap();
                assert!(
                    (0.04..0.09).contains(&start),
                    "Audio lost its display start offset: {start}"
                );
                assert!(track["duration"].as_str().unwrap().parse::<f64>().unwrap() > 0.4);
            }
        }
    }
    #[test]
    fn mixed_scale_composition_preserves_gaps() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("left.png");
        RgbImage::from_pixel(20, 20, image::Rgb([255, 0, 0]))
            .save(&p)
            .unwrap();
        let outputs = json!([{"x":-10,"y":0,"width":10,"height":10,"scale":2,"plain":url::Url::from_file_path(&p).unwrap().as_str()}]);
        let image = frozen_image(
            &outputs,
            &json!({"x":-10,"y":0,"width":20,"height":10}),
            false,
        )
        .unwrap();
        assert_eq!(image.dimensions(), (40, 20));
        assert_eq!(image.get_pixel(0, 0).0, [255, 0, 0]);
        assert_eq!(image.get_pixel(39, 0).0, [0, 0, 0]);
    }
}

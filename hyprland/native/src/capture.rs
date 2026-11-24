use crate::recording_audio::Options as AudioOptions;
use crate::recording_compose::compose;
use crate::util::*;
use anyhow::{Context, Result, bail};
use image::{ImageFormat, Rgb, RgbImage, imageops};
use serde_json::{Value, json};
use std::{
    fs,
    io::{Cursor, Read, Write},
    os::unix::{net::UnixStream, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
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
fn frame_window(window: &RgbImage) -> Result<RgbImage> {
    const PADDING: u32 = 24;
    const RADIUS: u32 = 10;
    let (w, h) = window.dimensions();
    let width = w.checked_add(2 * PADDING).context("Window is too wide")?;
    let height = h.checked_add(2 * PADDING).context("Window is too tall")?;
    if w == 0 || h == 0 || u64::from(width) * u64::from(height) > 256_000_000 {
        bail!("Capture dimensions exceed the image limit");
    }
    let mut framed = RgbImage::from_pixel(width, height, Rgb([255; 3]));
    imageops::replace(&mut framed, window, PADDING.into(), PADDING.into());

    // Blend the four corner arcs into the white frame at pixel centers.
    let radius = RADIUS.min(w / 2).min(h / 2);
    for y in 0..radius {
        for x in 0..radius {
            let dx = (radius - x) as f32 - 0.5;
            let dy = (radius - y) as f32 - 0.5;
            let coverage = (radius as f32 + 0.5 - dx.hypot(dy)).clamp(0., 1.);
            for (cx, cy) in [
                (x, y),
                (w - 1 - x, y),
                (x, h - 1 - y),
                (w - 1 - x, h - 1 - y),
            ] {
                let pixel = framed.get_pixel_mut(PADDING + cx, PADDING + cy);
                for channel in &mut pixel.0 {
                    *channel = (255. - f32::from(255 - *channel) * coverage).round() as u8;
                }
            }
        }
    }
    Ok(framed)
}
fn capture_window(directory: &Path, cursor: bool) -> Result<()> {
    let active = json(&["hyprctl", "activewindow", "-j"])?;
    let id = active["stableId"]
        .as_str()
        .filter(|id| !id.is_empty())
        .context("No active window is available to capture")?;
    let source = directory.join("window.ppm");
    let mut grim = command(&["grim", "-T", id, "-t", "ppm"]);
    if cursor {
        grim.arg("-c");
    }
    grim.arg(&source);
    output(grim, None, Duration::from_secs(10)).context("Could not capture the active window")?;
    let window = image::open(source)?.into_rgb8();
    let mut png = Cursor::new(Vec::new());
    frame_window(&window)?.write_to(&mut png, ImageFormat::Png)?;
    save_screenshot(png.into_inner())
}
fn capture_outputs(monitors: &Value, directory: &Path, with_cursor: bool) -> Result<Value> {
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
        let mut capture = command(&["grim", "-t", "ppm", "-o", s(m, "name")]);
        capture.arg(&plain);
        jobs.push(capture);
        let mut output = json!({"name":m["name"],"x":m["x"],"y":m["y"],"width":w/scale,"height":h/scale,"scale":scale,"focused":m["focused"],"plain":url::Url::from_file_path(plain).unwrap().as_str()});
        if with_cursor {
            let mut capture = command(&["grim", "-c", "-t", "ppm", "-o", s(m, "name")]);
            capture.arg(&cursor);
            jobs.push(capture);
            output["cursor"] = json!(url::Url::from_file_path(cursor).unwrap().as_str());
        }
        outputs.push(output);
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
fn cancel_capture_ui(pid: u32, directory: &Path) {
    let cmd = command(&[
        "quickshell",
        "ipc",
        "--pid",
        &pid.to_string(),
        "call",
        "capture",
        "cancelSession",
        &directory.to_string_lossy(),
    ]);
    let _ = output(cmd, None, Duration::from_secs(2));
}
fn open_warm(directory: &Path, stop: Option<&AtomicBool>) -> Result<bool> {
    // Keep the connection open until completion so the warm UI can release
    // its surfaces if this caller exits or loses the acknowledgement.
    let mut client = match UnixStream::connect(runtime()?.join("dotfiles-capture.sock")) {
        Ok(client) => client,
        Err(e)
            if matches!(
                e.kind(),
                std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
            ) =>
        {
            return Ok(false);
        }
        Err(e) => return Err(e.into()),
    };
    let pid = {
        client.set_read_timeout(Some(Duration::from_secs(2)))?;
        client.set_write_timeout(Some(Duration::from_secs(2)))?;
        writeln!(
            client,
            "{}",
            json!({"action":"open","directory":directory,"keepAlive":true})
        )?;
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
    };
    let mut polls = 0;
    while !directory.join("result.json").is_file() {
        if stop.is_some_and(|stop| stop.load(Ordering::Relaxed)) {
            return Ok(true);
        }
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
    if !["region", "window", "record", "color"].contains(&mode) {
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
    let dir = tempfile::Builder::new()
        .prefix("dotfiles-capture-")
        .tempdir_in(runtime()?)?;
    if mode == "window" {
        return capture_window(dir.path(), preferences()["cursor"] == true);
    }
    let picker = mode == "color";
    let monitors = json(&["hyprctl", "monitors", "-j"])?;
    let outputs = capture_outputs(&monitors, dir.path(), !picker)?;
    if rows(&outputs).is_empty() {
        bail!("No active displays are available");
    }
    if picker {
        atomic_json(
            &dir.path().join("session.json"),
            &json!({"outputs": outputs}),
        )?;
        run_capture_ui(dir.path(), "color-picker.qml", None)?;
        return copy_picked_color(dir.path(), &outputs);
    }
    let data = json!({"mode":mode,"outputs":outputs,"render":dir.path().join("render.png"),"selection":null,"preferences":preferences()});
    atomic_json(&dir.path().join("session.json"), &data)?;
    if !open_warm(dir.path(), None)? {
        run_capture_ui(dir.path(), "capture.qml", None)?;
    }
    let result = dir.path().join("result.json");
    if result.is_file() {
        let result = read_json(&result)?;
        if let Some(error) = result["error"].as_str() {
            bail!("{error}");
        }
    }
    Ok(())
}
fn run_capture_ui(directory: &Path, config: &str, stop: Option<&AtomicBool>) -> Result<()> {
    let mut c = command(&[
        "quickshell",
        "--path",
        &root().join("tools").join(config).to_string_lossy(),
    ]);
    c.env("DOTFILES_CAPTURE_SESSION", directory);
    let parent = std::process::id() as libc::pid_t;
    // Standalone windows must also disappear if their caller exits. Checking
    // the parent after arming the signal covers an exit during the fork.
    unsafe {
        c.pre_exec(move || {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
                return Err(std::io::Error::last_os_error());
            }
            if libc::getppid() != parent {
                return Err(std::io::Error::from_raw_os_error(libc::ESRCH));
            }
            Ok(())
        });
    }
    let status = if let Some(stop) = stop {
        use wait_timeout::ChildExt;
        // The portal picker reserves stdout for its selection response.
        let mut child = c.stdout(Stdio::from(std::io::stderr())).spawn()?;
        loop {
            if stop.load(Ordering::Relaxed) {
                cancel_capture_ui(child.id(), directory);
                if child.wait_timeout(Duration::from_secs(1))?.is_none() {
                    let _ = child.kill();
                    child.wait()?;
                    let cmd = command(&[
                        "quickshell",
                        "ipc",
                        "--path",
                        &root().join("shell/shell.qml").to_string_lossy(),
                        "call",
                        "shell",
                        "capture",
                        "false",
                    ]);
                    let _ = output(cmd, None, Duration::from_secs(2));
                }
                return Ok(());
            }
            if let Some(status) = child.wait_timeout(Duration::from_millis(25))? {
                break status;
            }
        }
    } else {
        c.status()?
    };
    if !status.success() {
        bail!("Capture UI failed");
    }
    Ok(())
}
pub fn select_share_region(
    source: &Value,
    stop: &AtomicBool,
    preview: bool,
) -> Result<Option<[i64; 4]>> {
    if source["kind"] != "screen" {
        bail!("Regions can only be selected on a monitor");
    }
    let Some(_lock) = try_lock(&runtime()?.join("dotfiles-capture.lock"))? else {
        bail!("Another capture selector is open");
    };
    let dir = tempfile::Builder::new()
        .prefix("dotfiles-capture-")
        .tempdir_in(runtime()?)?;
    let monitors = json(&["hyprctl", "monitors", "-j"])?;
    let enabled: Vec<_> = rows(&monitors)
        .iter()
        .filter(|monitor| monitor["disabled"] != true)
        .collect();
    let selected = enabled
        .iter()
        .copied()
        .find(|monitor| monitor["name"] == source["output"]);
    // Gallery samples can name outputs that aren't attached to this machine.
    let monitor = if preview {
        selected
            .or_else(|| {
                enabled
                    .iter()
                    .copied()
                    .find(|monitor| monitor["focused"] == true)
            })
            .or_else(|| enabled.first().copied())
    } else {
        selected
    }
    .context("The selected monitor is unavailable")?;
    let outputs = capture_outputs(&json!([monitor]), dir.path(), false)?;
    if stop.load(Ordering::Relaxed) {
        return Ok(None);
    }
    atomic_json(
        &dir.path().join("session.json"),
        &json!({"mode":"share","outputs":outputs}),
    )?;
    if !open_warm(dir.path(), Some(stop))? {
        run_capture_ui(dir.path(), "capture.qml", Some(stop))?;
    }
    if stop.load(Ordering::Relaxed) {
        return Ok(None);
    }
    let result = read_json(&dir.path().join("result.json"))?;
    if let Some(error) = result["error"].as_str() {
        bail!("{error}");
    }
    if result["selection"].is_null() {
        return Ok(None);
    }
    share_region_coordinates(
        &result["selection"],
        &outputs[0],
        (!preview).then_some(source),
    )
    .map(Some)
}
fn share_region_coordinates(
    selection: &Value,
    output: &Value,
    source: Option<&Value>,
) -> Result<[i64; 4]> {
    let axis = |origin, length| -> Result<(i64, i64)> {
        let start = selection[origin]
            .as_f64()
            .context("Missing selection origin")?;
        let extent = selection[length]
            .as_f64()
            .context("Missing selection size")?;
        let output_start = n(output, origin);
        let output_extent = n(output, length);
        let limit = match source {
            Some(source) => source[length].as_i64().context("Missing monitor size")?,
            None => output_extent.round() as i64,
        };
        // The portal takes monitor-local logical coordinates, as does the
        // screenshot overlay. Permit only rounding of fractional output sizes.
        if limit <= 0 || (output_extent - limit as f64).abs() > 1. {
            bail!("The monitor size changed while selecting the sharing region");
        }
        let position = |logical: f64| ((logical - output_start).floor() as i64).clamp(0, limit);
        let left = position(start);
        let right = position(start + extent);
        if right <= left {
            bail!("The selected region is empty");
        }
        Ok((left, right - left))
    };
    let (x, width) = axis("x", "width")?;
    let (y, height) = axis("y", "height")?;
    Ok([x, y, width, height])
}
fn copy_picked_color(directory: &Path, outputs: &Value) -> Result<()> {
    let result = match fs::read(directory.join("result.json")) {
        Ok(result) => serde_json::from_slice::<Value>(&result)?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let output = rows(outputs)
        .iter()
        .find(|output| output["name"] == result["output"])
        .context("The selected display is unavailable")?;
    let path = url::Url::parse(s(output, "plain"))?
        .to_file_path()
        .map_err(|_| anyhow::anyhow!("Invalid display capture path"))?;
    let image = image::open(path)?.into_rgb8();
    let coordinate = |key| result[key].as_u64().and_then(|n| u32::try_from(n).ok());
    let pixel = coordinate("x")
        .zip(coordinate("y"))
        .and_then(|(x, y)| image.get_pixel_checked(x, y))
        .context("The selected pixel is outside the display capture")?;
    let [r, g, b] = pixel.0;
    status(
        command(&["wl-copy", "--type", "text/plain"]),
        Some(format!("#{r:02X}{g:02X}{b:02X}").into_bytes()),
        Duration::from_secs(5),
    )
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
    save_screenshot(image)
}
fn save_screenshot(image: Vec<u8>) -> Result<()> {
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

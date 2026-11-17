//! Join display recordings on VA-API surfaces; retain software recovery for unsupported devices.
use crate::{capture::intersection, util::*};
use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::{Duration, Instant},
};

struct Clip {
    path: PathBuf,
    crop: String,
    size: String,
    position: String,
    offset: f64,
}
struct Plan {
    clips: Vec<Clip>,
    width: u64,
    height: u64,
    duration: f64,
    fps: u32,
    audio: bool,
}
#[derive(Clone, Copy)]
enum Backend<'a> {
    Vaapi { device: &'a Path, encoder: &'a str },
    Software,
}
impl Plan {
    fn new(clips: &[(PathBuf, Value, f64)], rect: &Value, audio: bool, fps: u32) -> Result<Self> {
        if clips.is_empty() || fps == 0 {
            bail!("No display clips or invalid frame rate");
        }
        let scale = clips
            .iter()
            .map(|(_, o, _)| o["scale"].as_f64().unwrap_or(1.))
            .fold(1., f64::max);
        let mut plan = Self {
            clips: vec![],
            width: (n(rect, "width") * scale).round_ties_even() as u64 / 2 * 2,
            height: (n(rect, "height") * scale).round_ties_even() as u64 / 2 * 2,
            duration: 0.,
            fps,
            audio,
        };
        if plan.width < 2 || plan.height < 2 {
            bail!("Invalid composition dimensions");
        }
        for (path, source, offset) in clips {
            let metadata = json(&[
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=width,height:format=duration",
                "-of",
                "json",
                &path.to_string_lossy(),
            ])?;
            let stream = &metadata["streams"][0];
            let part = intersection(rect, source);
            let sx = n(stream, "width") / n(source, "width");
            let sy = n(stream, "height") / n(source, "height");
            let left = ((n(&part, "x") - n(source, "x")) * sx).round_ties_even();
            let top = ((n(&part, "y") - n(source, "y")) * sy).round_ties_even();
            let width = n(stream, "width")
                .min(((n(&part, "x") + n(&part, "width") - n(source, "x")) * sx).round_ties_even())
                - left;
            let height = n(stream, "height").min(
                ((n(&part, "y") + n(&part, "height") - n(source, "y")) * sy).round_ties_even(),
            ) - top;
            let tw = (n(&part, "width") * scale).round_ties_even().max(1.);
            let th = (n(&part, "height") * scale).round_ties_even().max(1.);
            let dx = ((n(&part, "x") - n(rect, "x")) * scale).round_ties_even();
            let dy = ((n(&part, "y") - n(rect, "y")) * scale).round_ties_even();
            let duration = metadata["format"]["duration"]
                .as_str()
                .context("Missing clip duration")?
                .parse::<f64>()?;
            if !duration.is_finite()
                || duration <= 0.
                || !offset.is_finite()
                || *offset < 0.
                || width <= 0.
                || height <= 0.
            {
                bail!("Invalid display clip geometry or timing");
            }
            plan.duration = plan.duration.max(duration + offset);
            plan.clips.push(Clip {
                path: path.clone(),
                crop: format!("{width}:{height}:{left}:{top}:exact=1"),
                size: format!("{tw}:{th}"),
                position: format!("{dx}:{dy}"),
                offset: *offset,
            });
        }
        Ok(plan)
    }
    fn command(&self, target: &Path, backend: Backend<'_>) -> Command {
        let mut c = command(&[
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-filter_complex_threads",
            "1",
        ]);
        let hardware = matches!(backend, Backend::Vaapi { .. });
        if let Backend::Vaapi { device, .. } = backend {
            c.arg("-init_hw_device")
                .arg(format!("vaapi=gpu:{}", device.display()))
                .args(["-filter_hw_device", "gpu"]);
        }
        // A tiny black source is uploaded and expanded by the GPU. No full-size
        // CPU canvas, RGB conversion, or GPU readback is needed in the VA-API path.
        let mut filters = vec![if hardware {
            format!(
                "color=c=black:s=16x16:r={},format=nv12,hwupload,scale_vaapi={}:{}:format=nv12[base]",
                self.fps, self.width, self.height
            )
        } else {
            format!(
                "color=c=black:s={}x{}:r={}[base]",
                self.width, self.height, self.fps
            )
        }];
        for (i, clip) in self.clips.iter().enumerate() {
            if hardware {
                c.args([
                    "-hwaccel",
                    "vaapi",
                    "-hwaccel_device",
                    "gpu",
                    "-hwaccel_output_format",
                    "vaapi",
                ]);
            } else {
                c.args(["-threads", "2"]);
            }
            c.arg("-i").arg(&clip.path);
            // crop on a hardware frame changes metadata only; scale_vaapi
            // applies that source rectangle while scaling the GPU surface.
            let scale = if hardware {
                format!("scale_vaapi={}:format=nv12", clip.size)
            } else {
                format!("scale={}", clip.size)
            };
            filters.push(format!(
                "[{i}:v]crop={},{scale},setsar=1,setpts=PTS-STARTPTS+{}/TB[s{i}]",
                clip.crop, clip.offset
            ));
            let previous = if i == 0 {
                "base".into()
            } else {
                format!("v{}", i - 1)
            };
            let overlay = if hardware { "overlay_vaapi" } else { "overlay" };
            let format = if hardware { "" } else { ":format=rgb" };
            filters.push(format!(
                "[{previous}][s{i}]{overlay}={}:eof_action=pass:repeatlast=0{format}[v{i}]",
                clip.position
            ));
        }
        if self.audio {
            filters.push(format!(
                "[0:a]asetpts=PTS-STARTPTS+{}/TB[audio]",
                self.clips[0].offset
            ));
        }
        c.args([
            "-filter_complex",
            &filters.join(";"),
            "-map",
            &format!("[v{}]", self.clips.len() - 1),
            "-t",
            &self.duration.to_string(),
        ]);
        match backend {
            Backend::Vaapi { encoder, .. } => {
                c.args(["-c:v", encoder, "-qp", "18"]);
            }
            Backend::Software => {
                c.args([
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
                    "-threads", "4",
                ]);
            }
        }
        c.args(["-movflags", "+faststart"]);
        if self.audio {
            c.args(["-map", "[audio]", "-c:a", "aac", "-b:a", "192k"]);
        } else {
            c.arg("-an");
        }
        c.arg(target);
        c
    }
    fn budget(&self) -> Duration {
        Duration::from_secs(
            ((self.duration.ceil() as u64)
                .saturating_mul(4)
                .saturating_add(60))
            .clamp(300, 3600),
        )
    }
    fn encode(&self, target: &Path, backend: Backend<'_>, timeout: Duration) -> Result<()> {
        output(self.command(target, backend), None, timeout)?;
        if target.metadata()?.len() == 0 {
            bail!("Composition produced no video");
        }
        Ok(())
    }
    fn publish(&self, target: &Path, devices: &[PathBuf]) -> Result<()> {
        let started = Instant::now();
        let remaining = || {
            self.budget()
                .checked_sub(started.elapsed())
                .context("Display composition deadline exceeded")
        };
        let staged = tempfile::Builder::new()
            .prefix(".capture-join-")
            .suffix(".mp4")
            .tempfile_in(target.parent().context("Missing recording directory")?)?;
        for device in devices {
            // Radeon H.264 encoders commonly stop at 4096 pixels; HEVC can
            // accommodate wider desktops. Other devices can reject either codec.
            let codecs = if self.width > 4096 || self.height > 4096 {
                ["hevc_vaapi", "h264_vaapi"]
            } else {
                ["h264_vaapi", "hevc_vaapi"]
            };
            for encoder in codecs {
                match self.encode(
                    staged.path(),
                    Backend::Vaapi { device, encoder },
                    remaining()?,
                ) {
                    Ok(()) => {
                        eprintln!("Display composition used {encoder} on {}", device.display());
                        return publish(staged, target);
                    }
                    Err(error) => eprintln!(
                        "GPU composition unavailable ({}, {encoder}): {error:#}",
                        device.display()
                    ),
                }
            }
        }
        eprintln!("Using software display composition (four encoder threads)");
        self.encode(staged.path(), Backend::Software, remaining()?)?;
        publish(staged, target)
    }
}
fn publish(staged: tempfile::NamedTempFile, target: &Path) -> Result<()> {
    staged.as_file().sync_all()?;
    staged.persist(target)?;
    Ok(())
}
fn devices() -> Vec<PathBuf> {
    let mut devices: Vec<_> = fs::read_dir("/dev/dri")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| entry.file_name().to_string_lossy().starts_with("renderD"))
        .map(|entry| entry.path())
        .collect();
    devices.sort();
    devices
}
pub fn compose(
    clips: &[(PathBuf, Value, f64)],
    rect: &Value,
    target: &Path,
    audio: bool,
    fps: u32,
) -> Result<()> {
    Plan::new(clips, rect, audio, fps)?.publish(target, &devices())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fixture(path: &Path, source: &str, duration: f64, audio: bool) {
        let mut c = command(&[
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            source,
        ]);
        if audio {
            c.args(["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000"]);
        }
        c.args([
            "-t",
            &duration.to_string(),
            "-c:v",
            "libx264",
            "-threads",
            "2",
            "-preset",
            "veryfast",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
        ]);
        if audio {
            c.args(["-c:a", "pcm_s16le"]);
        }
        c.arg(path);
        output(c, None, Duration::from_secs(30)).unwrap();
    }
    fn frame(path: &Path, time: f64) -> Vec<u8> {
        let result = command(&[
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            &time.to_string(),
            "-i",
            &path.to_string_lossy(),
            "-frames:v",
            "1",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ])
        .output()
        .unwrap();
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        result.stdout
    }
    fn assert_color(frame: &[u8], width: usize, x: usize, y: usize, expected: [u8; 3]) {
        let index = (y * width + x) * 3;
        let actual = &frame[index..index + 3];
        assert!(
            actual.iter().zip(expected).all(|(a, b)| a.abs_diff(b) < 25),
            "Pixel {x},{y}: {actual:?}, expected {expected:?}"
        );
    }
    fn cpu_seconds() -> f64 {
        let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
        assert_eq!(
            unsafe { libc::getrusage(libc::RUSAGE_CHILDREN, usage.as_mut_ptr()) },
            0
        );
        let usage = unsafe { usage.assume_init() };
        (usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) as f64
            + (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) as f64 / 1e6
    }
    #[test]
    #[ignore = "requires host VA-API, libx264, and DOTFILES_TEST_VAAPI_DEVICE; synthetic files only"]
    fn gpu_join_preserves_geometry_timing_audio_and_recovers() {
        let device = PathBuf::from(
            std::env::var("DOTFILES_TEST_VAAPI_DEVICE")
                .expect("Set the test render node explicitly"),
        );
        let mut dir = tempfile::Builder::new()
            .prefix("record-gpu-test-")
            .tempdir_in(
                std::env::var("DOTFILES_TEST_CACHE")
                    .unwrap_or_else(|_| std::env::temp_dir().to_string_lossy().into()),
            )
            .unwrap();
        if std::env::var_os("DOTFILES_TEST_KEEP").is_some() {
            dir.disable_cleanup(true);
            eprintln!("Synthetic GPU fixtures: {}", dir.path().display());
        }
        let first = dir.path().join("left.mkv");
        let second = dir.path().join("right.mkv");
        fixture(
            &first,
            "color=red:s=256x256:r=60,drawbox=x=0:y=0:w=64:h=ih:c=blue:t=fill,drawbox=x=0:y=0:w=iw:h=32:c=yellow:t=fill",
            0.65,
            true,
        );
        fixture(
            &second,
            "color=green:s=512x384:r=60,drawbox=x=0:y=0:w=64:h=ih:c=magenta:t=fill",
            0.35,
            false,
        );
        let clips = vec![
            (
                first,
                json!({"x":-256,"y":0,"width":256,"height":256,"scale":1}),
                0.08,
            ),
            (
                second,
                json!({"x":64,"y":96,"width":256,"height":192,"scale":2}),
                0.16,
            ),
        ];
        let rect = json!({"x":-192,"y":32,"width":480,"height":224});
        let mut plan = Plan::new(&clips, &rect, true, 60).unwrap();
        for (fps, encoder, audio) in [
            (60, "h264_vaapi", true),
            (120, "h264_vaapi", false),
            (144, "h264_vaapi", true),
            (165, "h264_vaapi", true),
            (60, "hevc_vaapi", true),
        ] {
            plan.fps = fps;
            plan.audio = audio;
            let target = dir.path().join(format!("gpu-{fps}-{encoder}.mp4"));
            plan.encode(
                &target,
                Backend::Vaapi {
                    device: &device,
                    encoder,
                },
                plan.budget(),
            )
            .unwrap();
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
            let video = streams.iter().find(|s| s["codec_type"] == "video").unwrap();
            assert_eq!(
                (video["width"].as_u64(), video["height"].as_u64()),
                (Some(960), Some(448))
            );
            assert_eq!(video["r_frame_rate"], format!("{fps}/1"));
            assert_eq!(
                streams
                    .iter()
                    .filter(|s| s["codec_type"] == "audio")
                    .count(),
                usize::from(audio)
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
                    "Incorrect audio start {start}"
                );
            }
            let pixels = frame(&target, 0.3);
            assert_color(&pixels, 960, 100, 100, [255, 0, 0]); // Cropped-away blue/yellow must not leak.
            assert_color(&pixels, 960, 450, 200, [0, 0, 0]); // Physical gap.
            assert_color(&pixels, 960, 550, 200, [255, 0, 255]);
            assert_color(&pixels, 960, 700, 200, [0, 128, 0]);
            assert_color(&pixels, 960, 700, 60, [0, 0, 0]); // Staggered display's top gap.
            let early = frame(&target, 0.02);
            assert_color(&early, 960, 100, 100, [0, 0, 0]);
            let between = frame(&target, 0.12);
            assert_color(&between, 960, 100, 100, [255, 0, 0]);
            assert_color(&between, 960, 700, 200, [0, 0, 0]);
            let late = frame(&target, 0.61);
            assert_color(&late, 960, 100, 100, [255, 0, 0]);
            assert_color(&late, 960, 700, 200, [0, 0, 0]); // Ended input must not freeze its final frame.
            eprintln!(
                "GPU PASS {fps} FPS {encoder}: crops, scales, gaps, offsets, EOF, audio={audio}"
            );
        }
        plan.audio = true;
        plan.fps = 60;
        plan.width = 5120;
        let wide = dir.path().join("wide.mp4");
        plan.publish(&wide, std::slice::from_ref(&device)).unwrap();
        let probe = json(&[
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name,width",
            "-of",
            "json",
            &wide.to_string_lossy(),
        ])
        .unwrap();
        assert_eq!(probe["streams"][0]["codec_name"], "hevc");
        assert_eq!(probe["streams"][0]["width"], 5120);
        assert_color(&frame(&wide, 0.3), 5120, 100, 100, [255, 0, 0]);
        eprintln!("GPU PASS 5120-pixel join uses HEVC");
        plan.width = 960;
        let recovered = dir.path().join("fallback.mp4");
        plan.publish(&recovered, &[PathBuf::from("/dev/dri/dotfiles-missing")])
            .unwrap();
        assert_color(&frame(&recovered, 0.3), 960, 100, 100, [255, 0, 0]);
        let old = fs::read(&recovered).unwrap();
        plan.clips[0].path = dir.path().join("missing.mkv");
        assert!(plan.publish(&recovered, &[]).is_err());
        assert_eq!(
            fs::read(&recovered).unwrap(),
            old,
            "Failed composition replaced a complete file"
        );
        assert!(!fs::read_dir(dir.path()).unwrap().any(|p| {
            p.unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".capture-join-")
        }));

        // A short, real encoder comparison; no screenshots or physical inputs.
        let left = dir.path().join("bench-left.mkv");
        let right = dir.path().join("bench-right.mkv");
        fixture(&left, "testsrc2=s=1920x1080:r=60", 2., false);
        fixture(&right, "testsrc2=s=2560x1440:r=60", 2., false);
        let bench = Plan::new(
            &[
                (
                    left,
                    json!({"x":0,"y":0,"width":1920,"height":1080,"scale":1}),
                    0.,
                ),
                (
                    right,
                    json!({"x":1920,"y":0,"width":1920,"height":1080,"scale":1.3333333333333333}),
                    0.,
                ),
            ],
            &json!({"x":0,"y":0,"width":2880,"height":1080}),
            false,
            60,
        )
        .unwrap();
        for backend in [
            Backend::Vaapi {
                device: &device,
                encoder: "h264_vaapi",
            },
            Backend::Software,
        ] {
            let target = dir.path().join("benchmark.mp4");
            let cpu = cpu_seconds();
            let started = Instant::now();
            bench.encode(&target, backend, bench.budget()).unwrap();
            eprintln!(
                "BENCH {} 3840x1440 60fps 2s: wall={:.3}s cpu={:.3}s",
                if matches!(backend, Backend::Software) {
                    "CPU"
                } else {
                    "VAAPI"
                },
                started.elapsed().as_secs_f64(),
                cpu_seconds() - cpu
            );
        }
    }
}

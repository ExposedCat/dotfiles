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

//! Stereo band levels of the default speaker output for the pill's music effect.
//!
//! Reads the default sink monitor through `parec` and prints one JSON line per
//! hop: `{"l":[..],"r":[..],"beat":0..1}`, where `beat` is the strength of a
//! kick that started in this hop. Bands run from bass to treble. All
//! bands and both channels share one adaptive ceiling, so the spectrum shape
//! and panning stay visible.
use anyhow::{Context, Result};
use serde_json::json;
use std::{
    io::{Read, Write},
    os::unix::process::CommandExt,
    process::{Command, Stdio},
};

const RATE: f32 = 48_000.0;
const HOP: usize = 1_600; // 30 updates per second.
const CENTRES: [f32; 6] = [60.0, 150.0, 400.0, 1_000.0, 2_500.0, 6_000.0];
// Music loses energy toward treble faster than the widening bands gain it.
const TILT_DB: [f32; 6] = [0.0, 0.0, 0.0, 2.0, 5.0, 8.0];
const RANGE_DB: f32 = 30.0;
const CEILING_FALL_DB: f32 = 0.12;
const SILENCE_DB: f32 = -70.0;

#[derive(Clone, Copy, Default)]
struct Biquad {
    b0: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,
}
impl Biquad {
    /// RBJ band-pass with 0 dB peak gain.
    fn band_pass(centre: f32, q: f32) -> Self {
        let w = 2.0 * std::f32::consts::PI * centre / RATE;
        let alpha = w.sin() / (2.0 * q);
        let a0 = 1.0 + alpha;
        Self {
            b0: alpha / a0,
            b2: -alpha / a0,
            a1: -2.0 * w.cos() / a0,
            a2: (1.0 - alpha) / a0,
            ..Self::default()
        }
    }
    fn step(&mut self, x: f32) -> f32 {
        let y = self.b0 * x + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        y
    }
}

struct Analyzer {
    filters: [[Biquad; CENTRES.len()]; 2],
    energy: [[f32; CENTRES.len()]; 2],
    ceiling: f32,
    bass_average: f32,
    since_beat: u32,
}
impl Analyzer {
    fn new() -> Self {
        let bank = CENTRES.map(|c| Biquad::band_pass(c, 2.0));
        Self {
            filters: [bank, bank],
            energy: [[0.0; CENTRES.len()]; 2],
            ceiling: SILENCE_DB + RANGE_DB,
            bass_average: 0.0,
            since_beat: 0,
        }
    }
    fn push(&mut self, left: f32, right: f32) {
        for (channel, sample) in [left, right].into_iter().enumerate() {
            for (band, filter) in self.filters[channel].iter_mut().enumerate() {
                let y = filter.step(sample);
                self.energy[channel][band] += y * y;
            }
        }
    }
    /// Normalized levels for the finished hop, then reset the accumulators.
    fn finish(&mut self) -> ([f32; CENTRES.len()], [f32; CENTRES.len()], f32) {
        let db = |e: f32| 10.0 * (e / HOP as f32 + 1e-12).log10();
        let mut decibels = [[0.0; CENTRES.len()]; 2];
        for channel in 0..2 {
            for band in 0..CENTRES.len() {
                decibels[channel][band] = db(self.energy[channel][band]) + TILT_DB[band];
            }
        }
        let loudest = decibels.iter().flatten().copied().fold(f32::MIN, f32::max);
        self.ceiling = loudest.max(self.ceiling - CEILING_FALL_DB).max(SILENCE_DB + RANGE_DB);
        let floor = self.ceiling - RANGE_DB;
        let levels = decibels.map(|channel| channel.map(|value| ((value - floor) / RANGE_DB).clamp(0.0, 1.0).powi(2)));
        let bass = (self.energy[0][0] + self.energy[1][0] + self.energy[0][1] + self.energy[1][1]) / HOP as f32;
        self.since_beat += 1;
        let ratio = bass / self.bass_average.max(1e-12);
        let beat = if bass > 1e-7 && ratio > 1.6 && self.since_beat >= 6 {
            self.since_beat = 0;
            // Sharper jumps and louder bass make stronger kicks.
            let jump = ((ratio - 1.6) / 2.4).clamp(0.0, 1.0);
            let loudness = levels.iter().map(|channel| channel[0].max(channel[1])).fold(0.0, f32::max);
            ((0.4 + 0.6 * jump) * (0.3 + 0.7 * loudness)).clamp(0.0, 1.0)
        } else {
            0.0
        };
        self.bass_average += (bass - self.bass_average) * 0.08;
        self.energy = [[0.0; CENTRES.len()]; 2];
        (levels[0], levels[1], beat)
    }
}

fn round(values: [f32; CENTRES.len()]) -> Vec<f32> {
    values.iter().map(|v| (v * 1000.0).round() / 1000.0).collect()
}

pub fn run() -> Result<()> {
    let mut command = Command::new("parec");
    command
        .args([
            "--device=@DEFAULT_MONITOR@",
            "--raw",
            "--format=float32le",
            "--channels=2",
            "--rate=48000",
            "--latency-msec=30",
            "--client-name=Pill music effect",
            "--stream-name=Pill music effect",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped());
    // The capture stream must end with this helper.
    unsafe {
        command.pre_exec(|| {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = command.spawn().context("Could not start parec")?;
    let mut input = child.stdout.take().context("parec has no output")?;
    let out = std::io::stdout();
    let mut analyzer = Analyzer::new();
    let mut buffer = vec![0u8; HOP * 8];
    let result = (|| -> Result<()> {
        loop {
            input.read_exact(&mut buffer).context("The speaker monitor stream ended")?;
            for frame in buffer.as_chunks::<8>().0 {
                let left = f32::from_le_bytes([frame[0], frame[1], frame[2], frame[3]]);
                let right = f32::from_le_bytes([frame[4], frame[5], frame[6], frame[7]]);
                analyzer.push(left, right);
            }
            let (left, right, beat) = analyzer.finish();
            let mut out = out.lock();
            // A closed pipe means the shell stopped listening.
            serde_json::to_writer(&mut out, &json!({"l": round(left), "r": round(right), "beat": (beat * 100.0).round() / 100.0}))?;
            writeln!(out)?;
            out.flush()?;
        }
    })();
    let _ = child.kill();
    let _ = child.wait();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed(analyzer: &mut Analyzer, frequency: f32, left_gain: f32, right_gain: f32) -> ([f32; 6], [f32; 6], f32) {
        let mut last = Default::default();
        for hop in 0..20 {
            for i in 0..HOP {
                let t = (hop * HOP + i) as f32 / RATE;
                let s = (2.0 * std::f32::consts::PI * frequency * t).sin() * 0.5;
                analyzer.push(s * left_gain, s * right_gain);
            }
            last = analyzer.finish();
        }
        last
    }

    #[test]
    fn tone_lights_its_own_band() {
        let (left, right, _) = feed(&mut Analyzer::new(), 1_000.0, 1.0, 1.0);
        assert!(left[3] > 0.9, "{left:?}");
        assert!(left[0] < 0.2 && left[5] < 0.5, "{left:?}");
        assert!((left[3] - right[3]).abs() < 0.01);
    }

    #[test]
    fn panning_keeps_channels_apart() {
        let (left, right, _) = feed(&mut Analyzer::new(), 150.0, 0.1, 1.0);
        assert!(right[1] > 0.9, "{right:?}");
        assert!(left[1] < right[1] - 0.3, "{left:?} {right:?}");
    }

    #[test]
    fn silence_stays_dark() {
        let (left, right, beat) = feed(&mut Analyzer::new(), 100.0, 0.0, 0.0);
        assert!(left.iter().chain(&right).all(|v| *v == 0.0));
        assert_eq!(beat, 0.0);
    }

    #[test]
    fn kicks_are_detected_with_strength() {
        let mut analyzer = Analyzer::new();
        let mut kicks = vec![];
        // A 60 Hz kick for 100 ms every half second over quiet treble.
        for hop in 0..90 {
            for i in 0..HOP {
                let t = (hop * HOP + i) as f32 / RATE;
                let kick = if t % 0.5 < 0.1 { (2.0 * std::f32::consts::PI * 60.0 * t).sin() * 0.8 } else { 0.0 };
                let hat = (2.0 * std::f32::consts::PI * 6_000.0 * t).sin() * 0.02;
                analyzer.push(kick + hat, kick + hat);
            }
            let (_, _, beat) = analyzer.finish();
            if beat > 0.0 {
                kicks.push((hop, beat));
            }
        }
        assert!(kicks.len() >= 5, "{kicks:?}");
        assert!(kicks.iter().all(|(_, beat)| *beat > 0.3), "{kicks:?}");
    }
}

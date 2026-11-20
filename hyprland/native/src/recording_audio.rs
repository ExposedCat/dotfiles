//! Resolve selected PulseAudio/PipeWire-Pulse sources without changing the audio graph.
//! wl-screenrec accepts one FFmpeg input; lavfi mixes two live Pulse sources when needed.
use crate::util::*;
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::process::Command;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Options {
    pub speakers: bool,
    pub microphone: bool,
}
impl Options {
    pub fn parse(args: &[String]) -> Result<Self> {
        let mut options = Self::default();
        for flag in args {
            match flag.as_str() {
                "--speakers" => options.speakers = true,
                "--mic" => options.microphone = true,
                other => bail!("Unknown recording audio option: {other}"),
            }
        }
        Ok(options)
    }
    pub fn flags(self) -> Vec<&'static str> {
        let mut flags = vec![];
        if self.speakers {
            flags.push("--speakers");
        }
        if self.microphone {
            flags.push("--mic");
        }
        flags
    }
    pub fn enabled(self) -> bool {
        self.speakers || self.microphone
    }
    pub fn resolve(self) -> Result<Input> {
        if !self.enabled() {
            return Ok(Input::Silent);
        }
        let sources = json(&["pactl", "--format=json", "list", "sources"])
            .context("Could not inspect recording audio sources")?;
        let speaker = if self.speakers {
            let sink = run(&["pactl", "get-default-sink"])?;
            let monitor = format!("{}.monitor", sink.trim());
            Some(
                rows(&sources)
                    .iter()
                    .find(|source| s(source, "name") == monitor)
                    .context("The default speaker output has no recording monitor")?["name"]
                    .as_str()
                    .unwrap()
                    .to_string(),
            )
        } else {
            None
        };
        let mic = if self.microphone {
            let source = run(&["pactl", "get-default-source"])?;
            Some(
                rows(&sources)
                    .iter()
                    .find(|candidate| s(candidate, "name") == source.trim())
                    .context("The default microphone is unavailable")?["name"]
                    .as_str()
                    .unwrap()
                    .to_string(),
            )
        } else {
            None
        };
        Ok(match (speaker, mic) {
            (Some(speaker), Some(mic)) => Input::Mix { speaker, mic },
            (Some(source), None) | (None, Some(source)) => Input::Pulse(source),
            _ => Input::Silent,
        })
    }
}
#[derive(Debug, PartialEq, Eq)]
pub enum Input {
    Silent,
    Pulse(String),
    Mix { speaker: String, mic: String },
}
impl Input {
    pub fn device(&self) -> Option<(&'static str, String)> {
        match self {
            Self::Silent => None,
            Self::Pulse(source) => Some(("pulse", source.clone())),
            Self::Mix { speaker, mic } => Some(("lavfi", mix_graph(speaker, mic))),
        }
    }
    pub fn apply(&self, command: &mut Command) {
        if let Some((backend, device)) = self.device() {
            command.args([
                "--audio",
                "--audio-backend",
                backend,
                "--audio-device",
                &device,
            ]);
        }
    }
    pub fn description(&self) -> Value {
        self.device()
            .map(|(backend, device)| json!({"backend":backend,"device":device}))
            .unwrap_or(json!({"backend":"none","device":""}))
    }
}
// FFmpeg has separate option-value and graph-token escaping layers. Arguments go
// directly to exec, so there is deliberately no shell-escaping layer.
fn filter_value(value: &str) -> String {
    fn escape(value: &str, special: &str) -> String {
        value
            .chars()
            .flat_map(|c| {
                if special.contains(c) || c.is_ascii_whitespace() {
                    vec!['\\', c]
                } else {
                    vec![c]
                }
            })
            .collect()
    }
    escape(&escape(value, "\\':"), "\\'[],;")
}
fn mix_graph(speaker: &str, mic: &str) -> String {
    format!(
        "amovie=filename={}:format_name=pulse:dec_threads=1,aresample=48000,asetpts=PTS-STARTPTS[speakers];amovie=filename={}:format_name=pulse:dec_threads=1,aresample=48000,asetpts=PTS-STARTPTS[mic];[speakers][mic]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[out0]",
        filter_value(speaker),
        filter_value(mic)
    )
}

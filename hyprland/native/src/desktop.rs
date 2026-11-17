use crate::{shell, util::*};
use anyhow::{Context, Result, bail};
use gio::prelude::*;
use glib::variant::ToVariant;
use serde_json::{Value, json};
use std::{
    env,
    process::{Command, Stdio},
    time::Duration,
};
const PREFIX: &str = "dotfiles-hyprland-";
const BACKGROUND: &[&str] = &[
    "agents",
    "automount",
    "clipboard-text",
    "clipboard-image",
    "shell",
    "capture",
    "idle",
];
fn active(name: &str) -> bool {
    Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", &format!("{PREFIX}{name}")])
        .status()
        .is_ok_and(|s| s.success())
}
fn service(name: &str, args: &[String], restart: bool) -> Result<()> {
    if active(name) {
        return Ok(());
    }
    let mut c = command(&["systemd-run", "--user", "--quiet", "--collect"]);
    c.arg(format!("--unit={PREFIX}{name}")).args([
        "--property=PartOf=graphical-session.target",
        "--property=After=graphical-session.target",
        "--property=Requisite=graphical-session.target",
        "--property=UMask=0077",
    ]);
    for key in [
        "WAYLAND_DISPLAY",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "XDG_CURRENT_DESKTOP",
        "XDG_SESSION_ID",
        "XDG_SEAT",
        "XDG_VTNR",
        "XDG_CACHE_HOME",
    ] {
        if let Ok(value) = env::var(key) {
            c.arg(format!("--setenv={key}={value}"));
        }
    }
    c.arg(format!(
        "--setenv=XDG_CONFIG_HOME={}",
        xdg("XDG_CONFIG_HOME", ".config").display()
    ))
    .arg(format!(
        "--setenv=XDG_STATE_HOME={}",
        xdg("XDG_STATE_HOME", ".local/state").display()
    ));
    if restart {
        c.args(["--property=Restart=on-failure", "--property=RestartSec=2"]);
    }
    c.arg("--").args(args);
    output(c, None, Duration::from_secs(30))?;
    Ok(())
}
fn strings(args: &[&str]) -> Vec<String> {
    args.iter().map(|s| s.to_string()).collect()
}
pub fn session_start(refresh: bool) -> Result<()> {
    if !env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .split(':')
        .any(|s| s == "Hyprland")
    {
        bail!("Desktop services must be started inside the Hyprland session");
    }
    let _lock = Lock::acquire(&runtime()?.join("dotfiles-hyprland-services.lock"), false)?;
    if refresh && active("automount") {
        run(&[
            "systemctl",
            "--user",
            "restart",
            &format!("{PREFIX}automount"),
        ])?;
    } else {
        service(
            "automount",
            &strings(&[
                &root().join("bin/dotfiles-desktop").to_string_lossy(),
                "desktop",
                "automount",
            ]),
            true,
        )?;
    }
    for kind in ["text", "image"] {
        service(
            &format!("clipboard-{kind}"),
            &strings(&[
                "/usr/bin/wl-paste",
                "--type",
                kind,
                "--watch",
                "/usr/bin/cliphist",
                "store",
            ]),
            true,
        )?;
    }
    if active("idle") {
        run(&["systemctl", "--user", "stop", &format!("{PREFIX}idle")])?;
    }
    std::fs::create_dir_all(xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland"))?;
    for (name, path, field) in [
        ("shell", "shell/shell.qml", "polkit"),
        ("capture", "tools/capture-daemon.qml", "ready"),
    ] {
        if root().join(path).is_file() {
            if refresh && active(name) {
                run(&["systemctl", "--user", "restart", &format!("{PREFIX}{name}")])?;
            } else {
                service(
                    name,
                    &strings(&[
                        "/usr/bin/quickshell",
                        "--no-duplicate",
                        "--path",
                        &root().join(path).to_string_lossy(),
                    ]),
                    true,
                )?;
            }
            wait_shell(path, name, field)?;
        } else if active(name) {
            run(&["systemctl", "--user", "stop", &format!("{PREFIX}{name}")])?;
        }
    }
    let agents_loaded = Command::new("systemctl")
        .args([
            "--user",
            "show",
            "--property=LoadState",
            "--value",
            &format!("{PREFIX}agents.service"),
        ])
        .output()
        .is_ok_and(|out| out.status.success() && out.stdout == b"loaded\n");
    if refresh && agents_loaded {
        run(&["systemctl", "--user", "restart", &format!("{PREFIX}agents")])?;
    } else {
        service(
            "agents",
            &strings(&[
                &root().join("bin/dotfiles-desktop").to_string_lossy(),
                "desktop",
                "agents",
            ]),
            true,
        )?;
    }
    Ok(())
}
fn wait_shell(path: &str, target: &str, field: &str) -> Result<()> {
    for _ in 0..30 {
        let value = output(
            command(&[
                "/usr/bin/quickshell",
                "ipc",
                "--path",
                &root().join(path).to_string_lossy(),
                "call",
                target,
                "status",
            ]),
            None,
            Duration::from_secs(1),
        );
        if let Ok(value) = value
            && let Ok(value) = serde_json::from_str::<Value>(&value)
            && value.get(field).is_some()
            && (field != "ready" || value[field] == true)
        {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    bail!("Desktop {target} did not become ready; inspect its systemd journal")
}
pub fn apps() -> Vec<Value> {
    let mut apps:Vec<_>=gio::AppInfo::all().into_iter().filter(|a|a.should_show()).filter_map(|app|{let desktop=app.downcast_ref::<gio_unix::DesktopAppInfo>()?;Some(json!({"id":app.id().map(|s|s.to_string()),"name":app.display_name().as_str(),"description":app.description().unwrap_or_default().as_str(),"keywords":desktop.keywords().iter().map(|s|s.to_string()).collect::<Vec<_>>(),"icon":app.icon().and_then(|i|i.to_string()).unwrap_or_default().as_str()}))}).collect();
    apps.sort_by_key(|a| s(a, "name").to_lowercase());
    apps
}
pub fn launch(identity: &str) -> Result<()> {
    let app = gio_unix::DesktopAppInfo::new(identity)
        .filter(|a| a.should_show())
        .context("This application is no longer available")?;
    status(
        command(&[
            "uwsm",
            "app",
            "--",
            &app.filename()
                .context("Missing desktop filename")?
                .to_string_lossy(),
        ]),
        None,
        Duration::from_secs(10),
    )?;
    Ok(())
}
fn ipc(args: &[&str]) -> Result<()> {
    let mut cmd = command(&[
        "quickshell",
        "ipc",
        "--path",
        &root().join("shell/shell.qml").to_string_lossy(),
        "call",
        "shell",
    ]);
    cmd.args(args);
    output(cmd, None, Duration::from_secs(3))?;
    Ok(())
}
fn media(method: &str) -> Result<()> {
    if !["PlayPause", "Next", "Previous"].contains(&method) {
        bail!("Unknown media action");
    }
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)?;
    let names = bus
        .call_sync(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "ListNames",
            None,
            None,
            gio::DBusCallFlags::NONE,
            1500,
            gio::Cancellable::NONE,
        )?
        .child_value(0)
        .get::<Vec<String>>()
        .context("Invalid bus names")?;
    let mut players = vec![];
    for name in names
        .into_iter()
        .filter(|n| n.starts_with("org.mpris.MediaPlayer2."))
    {
        if let Ok(result) = bus.call_sync(
            Some(&name),
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties",
            "Get",
            Some(&("org.mpris.MediaPlayer2.Player", "PlaybackStatus").to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            1500,
            gio::Cancellable::NONE,
        ) {
            let status = result
                .child_value(0)
                .as_variant()
                .and_then(|v| v.get::<String>())
                .unwrap_or_default();
            players.push((status != "Playing", name));
        }
    }
    players.sort();
    for (_, name) in players {
        if bus
            .call_sync(
                Some(&name),
                "/org/mpris/MediaPlayer2",
                "org.mpris.MediaPlayer2.Player",
                method,
                None,
                None,
                gio::DBusCallFlags::NONE,
                1500,
                gio::Cancellable::NONE,
            )
            .is_ok()
        {
            break;
        }
    }
    Ok(())
}
fn brightness(direction: &str) -> Result<()> {
    if !["up", "down"].contains(&direction) {
        bail!("Expected up or down");
    }
    let monitors = shell::monitors()?;
    let m = rows(&monitors)
        .iter()
        .find(|m| m["focused"] == true)
        .context("No focused monitor")?;
    let serial = s(m, "serial");
    if serial.is_empty() {
        bail!("Focused monitor has no serial for DDC selection");
    }
    let Some(_lock) = try_lock(&runtime()?.join("dotfiles-monitor-brightness.lock"))? else {
        return Ok(());
    };
    output(
        command(&[
            "ddcutil",
            "--sn",
            serial,
            "--noverify",
            "setvcp",
            "10",
            if direction == "up" { "+" } else { "-" },
            "5",
        ]),
        None,
        Duration::from_secs(5),
    )?;
    let (c, max) = shell::ddc_read(serial)?;
    let _ = ipc(&["brightness", s(m, "name"), &c.to_string(), &max.to_string()]);
    Ok(())
}
pub fn main(args: &[String]) -> Result<()> {
    let mut args = args.to_vec();
    if args.len() > 2 && args[1] == "--" {
        args.remove(1);
    }
    let args = &args;
    match arg(args, 0)? {
        "agents" => crate::agents::run(args.iter().any(|s| s == "--test-bus")),
        "automount" => crate::automount::run(args.iter().any(|s| s == "--check")),
        "session-start" => session_start(args.iter().any(|s| s == "--refresh")),
        "session-stop" => {
            let mut c = command(&["systemctl", "--user", "stop"]);
            c.args(BACKGROUND.iter().map(|s| format!("{PREFIX}{s}.service")));
            output(c, None, Duration::from_secs(30))?;
            Ok(())
        }
        "apps-list" => emit(&json!(apps())),
        "app-launch" => launch(arg(args, 1)?),
        "clipboard" => {
            use std::os::unix::process::CommandExt;
            Err(command(&[
                "quickshell",
                "--no-duplicate",
                "--path",
                &root().join("tools/clipboard.qml").to_string_lossy(),
            ])
            .exec()
            .into())
        }
        "clipboard-list" => {
            let out = Command::new("cliphist").arg("list").output()?;
            if !out.status.success()
                && !String::from_utf8_lossy(&out.stderr)
                    .to_lowercase()
                    .contains("no such file")
            {
                bail!("{}", String::from_utf8_lossy(&out.stderr));
            }
            let rows: Vec<_> = String::from_utf8_lossy(&out.stdout)
                .lines()
                .filter_map(|l| {
                    let (id, preview) = l.split_once('\t')?;
                    if !id.is_empty() && id.bytes().all(|n| n.is_ascii_digit()) {
                        Some(json!({"id":id,"preview":preview}))
                    } else {
                        None
                    }
                })
                .collect();
            emit(&json!(rows))
        }
        "clipboard-copy" => {
            use std::io::Write;
            let id = arg(args, 1)?;
            if id.is_empty() || !id.bytes().all(|n| n.is_ascii_digit()) {
                bail!("Clipboard entry IDs must be numbers");
            }
            let mut child = command(&["cliphist", "decode"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()?;
            child.stdin.take().unwrap().write_all(id.as_bytes())?;
            let output = child.wait_with_output()?;
            if !output.status.success() {
                bail!("Cannot decode clipboard entry");
            }
            status(
                command(&["wl-copy"]),
                Some(output.stdout),
                Duration::from_secs(5),
            )?;
            Ok(())
        }
        "copy-text" => {
            status(
                command(&["wl-copy"]),
                Some(arg(args, 1)?.as_bytes().to_vec()),
                Duration::from_secs(5),
            )?;
            Ok(())
        }
        "launcher" => ipc(&["toggle", "launcher"]),
        "shell" => ipc(&["toggle", arg(args, 1)?]),
        "pill" => ipc(&[
            "gesture",
            arg(args, 1)?,
            args.get(2).map(String::as_str).unwrap_or(""),
        ]),
        "media" => media(arg(args, 1)?),
        "brightness" => brightness(arg(args, 1)?),
        "lock" => service(
            "lock",
            &strings(&["/usr/bin/hyprlock", "--no-fade-in"]),
            false,
        ),
        "screenshot" => crate::capture::main(&["select".into(), arg(args, 1)?.into()]),
        "record" => crate::capture::main(&["select".into(), "record".into()]),
        x => bail!("Unknown desktop action: {x}"),
    }
}

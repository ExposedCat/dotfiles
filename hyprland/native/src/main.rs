mod agenda;
mod agents;
mod automount;
mod calculator;
mod capture;
mod caret;
mod clipboard;
mod dates;
mod desktop;
mod launcher;
mod maintenance;
mod portals;
mod portals_extra;
mod portals_remote;
mod recording_audio;
mod recording_compose;
mod release;
mod shell;
mod sources;
mod util;
mod visualizer;

use anyhow::{Result, bail};
fn main() {
    unsafe {
        libc::umask(0o077);
    }
    if let Err(error) = dispatch() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}
fn dispatch() -> Result<()> {
    let args: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| {
            a.into_string().map_err(|_| {
                anyhow::anyhow!("Command arguments must be UTF-8; use percent-encoded file URIs")
            })
        })
        .collect::<Result<_>>()?;
    let basename = std::env::args_os().next().and_then(|s| {
        std::path::PathBuf::from(s)
            .file_name()
            .map(|s| s.to_owned())
    });
    match basename.as_deref().and_then(|s| s.to_str()) {
        Some("share-picker") => {
            let mut command = vec!["share".into()];
            command.extend(args);
            return portals::main(&command);
        }
        Some("brevlada-email") => return portals::email(&args),
        _ => {}
    }
    let (kind, args) = args.split_first().ok_or_else(|| {
        anyhow::anyhow!(
            "Expected desktop, shell, launcher, agenda, capture, portal, email or manage"
        )
    })?;
    match kind.as_str() {
        "desktop" => desktop::main(args),
        "shell" => shell::main(args),
        "launcher" => launcher::main(args),
        "agenda" => agenda::main(args),
        "capture" => capture::main(args),
        "portal" => portals::main(args),
        "email" => portals::email(args),
        "manage" => maintenance::main(args),
        "--help" | "-h" => {
            println!(
                "dotfiles-desktop\n\nCommands:\n  desktop    Session, shortcuts, apps and clipboard\n  shell      System data and explicit desktop actions\n  launcher   Persistent JSON-lines search worker\n  agenda     Calendar and world clocks\n  capture    Screenshots and recording\n  portal     D-Bus backend, picker and dialog responses\n  email      Brevlada links and attachment forwarding\n  manage     Install, check, rollback and portal builds"
            );
            Ok(())
        }
        "--version" => {
            println!("dotfiles-desktop {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        _ => bail!("Unknown command: {kind}"),
    }
}

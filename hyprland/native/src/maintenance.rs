use crate::{release, util::*};
use anyhow::{Context, Result, bail};
use serde_json::json;
use std::{
    fs,
    os::unix::fs::{PermissionsExt, symlink},
    path::{Path, PathBuf},
    time::Duration,
};
const LEGACY: &[&str] = &[
    "tools/desktop.py",
    "tools/capture.py",
    "shell/shell.py",
    "shell/agenda.py",
    "shell/appearance.py",
    "shell/brightness.py",
    "shell/internet_speed.py",
    "shell/launcher.py",
    "shell/launcher_sources.py",
    "shell/system_stats.py",
    "portals/backend.py",
    "portals/common.py",
    "portals/frontend.py",
    "portals/pill.py",
];
fn copy_tree(source: &Path, target: &Path) -> Result<()> {
    fs::create_dir_all(target)?;
    for item in fs::read_dir(source)? {
        let item = item?;
        let from = item.path();
        let to = target.join(item.file_name());
        let kind = item.file_type()?;
        if kind.is_symlink() {
            symlink(fs::read_link(from)?, to)?;
        } else if kind.is_dir() {
            copy_tree(&from, &to)?;
        } else if kind.is_file() {
            fs::copy(from, to)?;
        }
    }
    Ok(())
}
fn linked(path: &Path) -> bool {
    path.ancestors().any(Path::is_symlink)
}
fn files(source: &Path) -> Result<Vec<PathBuf>> {
    fn collect(root: &Path, all: &mut Vec<PathBuf>) -> Result<()> {
        for entry in fs::read_dir(root)? {
            let e = entry?;
            if e.file_type()?.is_dir() {
                collect(&e.path(), all)?;
            } else if e.file_type()?.is_file()
                && ["lua", "conf", "qml", "js", "svg", "txt"].contains(
                    &e.path()
                        .extension()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .as_ref(),
                )
            {
                all.push(e.path());
            }
        }
        Ok(())
    }
    let mut all = vec![];
    collect(source, &mut all)?;
    all.sort();
    Ok(all)
}
fn verify_hypr(directory: &Path) -> Result<()> {
    let private = tempfile::Builder::new()
        .prefix("hyprland-verify-")
        .tempdir()?;
    let mut c = command(&[
        "Hyprland",
        "--verify-config",
        "-c",
        &directory.join("hyprland.lua").to_string_lossy(),
    ]);
    for key in [
        "DISPLAY",
        "WAYLAND_DISPLAY",
        "WAYLAND_SOCKET",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "DBUS_SESSION_BUS_ADDRESS",
    ] {
        c.env_remove(key);
    }
    c.env("XDG_RUNTIME_DIR", private.path());
    let text = output(c, None, Duration::from_secs(30))?;
    if !text.contains("config ok") {
        bail!("Hyprland configuration validation failed: {text}");
    }
    Ok(())
}
fn reload_hypr() -> Result<()> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return Ok(());
    }
    run(&["hyprctl", "reload"])?;
    let errors = run(&["hyprctl", "configerrors"])?;
    if !errors.trim().is_empty() {
        bail!("Live configuration errors: {errors}");
    }
    let helper = root().join("bin/dotfiles-desktop");
    if helper.is_file() {
        run(&[
            &helper.to_string_lossy(),
            "desktop",
            "session-start",
            "--refresh",
        ])?;
    } else if root().join("tools/desktop.py").is_file() {
        // Only a pre-migration rollback uses the old entry point.
        run(&[
            "/usr/bin/python3",
            &root().join("tools/desktop.py").to_string_lossy(),
            "session-start",
            "--refresh",
        ])?;
    } else {
        let mut c = command(&["systemctl", "--user", "stop"]);
        for n in [
            "agents",
            "automount",
            "shell",
            "capture",
            "clipboard-text",
            "clipboard-image",
            "idle",
        ] {
            c.arg(format!("dotfiles-hyprland-{n}.service"));
        }
        let _ = output(c, None, Duration::from_secs(30));
    }
    Ok(())
}
fn snapshot(backups: &Path, kind: &str) -> Result<PathBuf> {
    let backup = backups.join(chrono::Utc::now().format("%Y%m%dT%H%M%S.%6fZ").to_string());
    fs::create_dir_all(&backup)?;
    if root().exists() {
        copy_tree(&root(), &backup.join("hypr"))?;
    }
    atomic_json(
        &backup.join("metadata.json"),
        &json!({"kind":kind,"present":root().exists()}),
    )?;
    println!("Backup: {}", backup.display());
    Ok(backup)
}
fn apply(stage: Option<&Path>) -> Result<()> {
    let target = root();
    let parent = target.parent().context("Missing config parent")?;
    let temp = tempfile::Builder::new()
        .prefix(".hypr-previous-")
        .tempdir_in(parent)?;
    let previous = temp.path().join("hypr");
    if target.exists() {
        fs::rename(&target, &previous)?;
    }
    let result = (|| -> Result<()> {
        if let Some(stage) = stage {
            fs::rename(stage, &target)?;
        }
        reload_hypr()
    })();
    if let Err(error) = result {
        if target.exists() {
            fs::remove_dir_all(&target)?;
        }
        if previous.exists() {
            fs::rename(&previous, &target)?;
        }
        if let Err(e) = reload_hypr() {
            eprintln!("Original files restored; reload needs attention: {e:#}");
        }
        return Err(error);
    }
    Ok(())
}
fn differences(source: &Path, binary: &Path) -> Result<Vec<String>> {
    let mut diff = vec![];
    for p in files(source)? {
        let relative = p.strip_prefix(source)?;
        if fs::read(root().join(relative)).ok() != Some(fs::read(&p)?) {
            diff.push(relative.to_string_lossy().into_owned());
        }
    }
    if release::digest(&root().join("bin/dotfiles-desktop")).ok() != Some(release::digest(binary)?)
    {
        diff.push("bin/dotfiles-desktop".into());
    }
    for path in LEGACY {
        if root().join(path).exists() {
            diff.push((*path).into());
        }
    }
    Ok(diff)
}
fn hyprland(repo: &Path, args: &[String]) -> Result<()> {
    let action = arg(args, 0)?;
    let source = repo.join("hyprland/config");
    let backups = xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland/backups");
    let _lock = Lock::acquire(&backups.parent().unwrap().join("manage.lock"), false)?;
    if root().is_symlink() {
        bail!("Hyprland config must be a regular directory");
    }
    let binary = std::env::current_exe()?;
    match action {
        "install" => {
            verify_hypr(&source)?;
            if root().exists() && differences(&source, &binary)?.is_empty() {
                println!("Hyprland configuration and native helpers already match.");
                return Ok(());
            }
            let target = root();
            let parent = target.parent().context("Missing config parent")?;
            fs::create_dir_all(parent)?;
            let temp = tempfile::Builder::new()
                .prefix(".hypr-install-")
                .tempdir_in(parent)?;
            let stage = temp.path().join("hypr");
            if target.exists() {
                copy_tree(&target, &stage)?;
            } else {
                fs::create_dir(&stage)?;
            }
            for p in files(&source)? {
                let dest = stage.join(p.strip_prefix(&source)?);
                if linked(dest.parent().unwrap()) {
                    bail!("Linked configuration directory: {}", dest.display());
                }
                fs::create_dir_all(dest.parent().unwrap())?;
                if dest.is_symlink() {
                    fs::remove_file(&dest)?;
                }
                fs::copy(p, dest)?;
            }
            for legacy in LEGACY {
                let dest = stage.join(legacy);
                if dest.is_file() || dest.is_symlink() {
                    fs::remove_file(dest)?;
                }
            }
            let bin = stage.join("bin/dotfiles-desktop");
            if linked(bin.parent().unwrap()) {
                bail!("Linked binary directory");
            }
            fs::create_dir_all(bin.parent().unwrap())?;
            if bin.is_symlink() {
                fs::remove_file(&bin)?;
            }
            fs::copy(&binary, &bin)?;
            fs::set_permissions(&bin, fs::Permissions::from_mode(0o755))?;
            verify_hypr(&stage)?;
            snapshot(&backups, "install")?;
            apply(Some(&stage))?;
            println!("Hyprland configuration and Rust helpers installed and validated.");
        }
        "check" => {
            verify_hypr(&source)?;
            let diff = differences(&source, &binary)?;
            if !diff.is_empty() {
                bail!("Installed files differ: {}", diff.join(", "));
            }
            verify_hypr(&root())?;
            if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
                let errors = run(&["hyprctl", "configerrors"])?;
                if !errors.trim().is_empty() {
                    bail!("{errors}");
                }
            }
            println!(
                "Repository, installed configuration and native executable match; validation passed."
            );
        }
        "backups" => {
            if backups.exists() {
                let mut paths: Vec<_> = fs::read_dir(&backups)?
                    .filter_map(|r| r.ok().map(|r| r.path()))
                    .collect();
                paths.sort();
                for path in paths {
                    if let Ok(data) = read_json(&path.join("metadata.json")) {
                        println!(
                            "{} {}",
                            path.file_name().unwrap().to_string_lossy(),
                            s(&data, "kind")
                        );
                    }
                }
            }
        }
        "rollback" => {
            let backup = if let Some(id) = args.get(1) {
                if Path::new(id).components().count() != 1
                    || !matches!(
                        Path::new(id).components().next(),
                        Some(std::path::Component::Normal(_))
                    )
                {
                    bail!("Invalid backup ID");
                }
                backups.join(id)
            } else {
                let mut paths: Vec<_> = fs::read_dir(&backups)?
                    .filter_map(|r| r.ok().map(|r| r.path()))
                    .filter(|p| {
                        read_json(&p.join("metadata.json")).is_ok_and(|d| d["kind"] == "install")
                    })
                    .collect();
                paths.sort();
                paths.pop().context("No pre-install backup is available")?
            };
            let metadata = read_json(&backup.join("metadata.json"))?;
            let present = metadata["present"] == true;
            if !present && std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
                bail!("This backup predates the config; restore outside the running session");
            }
            let target = root();
            fs::create_dir_all(target.parent().unwrap())?;
            let tmp = tempfile::tempdir_in(target.parent().unwrap())?;
            let stage = tmp.path().join("hypr");
            if present {
                copy_tree(&backup.join("hypr"), &stage)?;
                verify_hypr(&stage)?;
            }
            snapshot(&backups, "rollback")?;
            apply(if present { Some(&stage) } else { None })?;
            println!("Restored backup: {}", backup.display());
        }
        _ => bail!("Expected install, check, rollback or backups"),
    }
    Ok(())
}
const BUS: &str = "org.freedesktop.impl.portal.desktop.dotfiles";
const SERVICE: &str = "dotfiles-portal.service";
fn managed(text: &str, block: &str, marker: &str) -> Result<String> {
    let start = format!("BEGIN {marker}");
    let end = format!("END {marker}");
    if text.contains(&start) {
        if !text.contains(&end) {
            bail!("Incomplete managed block: {marker}");
        }
        let re = regex::Regex::new(&format!(
            r"(?ms)^[^\n]*{}\n.*?^[^\n]*{}[^\n]*",
            regex::escape(&start),
            regex::escape(&end)
        ))?;
        Ok(re.replace(text, regex::NoExpand(block)).into())
    } else {
        Ok(format!("{}\n\n{block}\n", text.trim_end()))
    }
}
fn contents(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}
fn mime_defaults(text: &str) -> String {
    let mut section = "";
    let mut lines = vec![];
    for line in text.lines() {
        if line.starts_with('[') {
            section = line.trim();
        }
        let mut line = line.to_string();
        if let Some((key, value)) = line.split_once('=') {
            if section == "[Default Applications]"
                && ["x-scheme-handler/mailto", "inode/directory"].contains(&key)
            {
                continue;
            }
            if key == "application/octet-stream" {
                let handlers: Vec<_> = value
                    .split(';')
                    .filter(|s| !s.is_empty() && *s != "dev-code.desktop")
                    .collect();
                if handlers.is_empty() {
                    continue;
                }
                line = format!("{key}={};", handlers.join(";"));
            }
        }
        lines.push(line);
    }
    let index = if let Some(i) = lines.iter().position(|s| s == "[Default Applications]") {
        i + 1
    } else {
        lines.push(String::new());
        lines.push("[Default Applications]".into());
        lines.len()
    };
    lines.splice(
        index..index,
        [
            "x-scheme-handler/mailto=com.chipichapa.Brevlada.desktop".into(),
            "inode/directory=org.gnome.Nautilus.desktop".into(),
        ],
    );
    format!("{}\n", lines.join("\n").trim_end())
}
type Payloads = std::collections::BTreeMap<PathBuf, (Vec<u8>, u32)>;
fn payloads(repo: &Path) -> Result<Payloads> {
    let config = xdg("XDG_CONFIG_HOME", ".config");
    let data = xdg("XDG_DATA_HOME", ".local/share");
    let source = repo.join("xdg-desktop-portal");
    let mut result = Payloads::new();
    for (file, target) in [
        (
            source.join("hyprland-portals.conf"),
            config.join("xdg-desktop-portal/hyprland-portals.conf"),
        ),
        (
            source.join("dotfiles.portal"),
            data.join("xdg-desktop-portal/portals/dotfiles.portal"),
        ),
        (
            repo.join("hyprland/config/portal.qml"),
            root().join("portal.qml"),
        ),
    ] {
        result.insert(target, (fs::read(file)?, 0o644));
    }
    let binary = root().join("bin/dotfiles-desktop");
    let command = format!("\"{}\" portal backend", binary.display());
    let unit = format!(
        "[Unit]\nDescription=Desktop portal dialogs\nPartOf=graphical-session.target\nAfter=graphical-session.target\n\n[Service]\nType=dbus\nBusName={BUS}\nExecStart={command}\nRestart=on-failure\nSlice=session.slice\n"
    );
    let activation =
        format!("[D-BUS Service]\nName={BUS}\nExec={command}\nSystemdService={SERVICE}\n");
    result.insert(
        config.join("systemd/user").join(SERVICE),
        (unit.into_bytes(), 0o644),
    );
    result.insert(
        data.join("dbus-1/services").join(format!("{BUS}.service")),
        (activation.into_bytes(), 0o644),
    );
    let override_ = format!(
        "[Service]\nExecStart=\nExecStart=\"{}\"\n",
        release::target(repo)?.display()
    );
    result.insert(
        config.join("systemd/user/xdg-desktop-portal.service.d/90-peer-disconnect.conf"),
        (override_.into_bytes(), 0o644),
    );
    let desktop = format!(
        "[Desktop Entry]\nType=Application\nName=Brevlada\nGenericName=Email Client\nExec=\"{}\" email %U\nIcon=com.chipichapa.Brevlada\nTerminal=false\nCategories=GNOME;GTK;Network;Email;\nMimeType=x-scheme-handler/mailto;\nStartupNotify=true\nDBusActivatable=false\n",
        binary.display()
    );
    result.insert(
        data.join("applications/com.chipichapa.Brevlada.desktop"),
        (desktop.into_bytes(), 0o644),
    );
    let mime = config.join("mimeapps.list");
    result.insert(
        mime.clone(),
        (mime_defaults(&contents(&mime)).into_bytes(), 0o644),
    );
    let picker = root().join("portals/share-picker");
    // Multicall native entry points: no interpreter on either integration path.
    let runtime_bytes = fs::read(&binary)?;
    result.insert(picker.clone(), (runtime_bytes.clone(), 0o755));
    result.insert(
        home().join(".local/libexec/dotfiles/brevlada-email"),
        (runtime_bytes, 0o755),
    );
    let xdph = root().join("xdph.conf");
    let block = format!(
        "# BEGIN dotfiles-share-picker\nscreencopy {{\n    custom_picker_binary = {}\n}}\n# END dotfiles-share-picker",
        picker.display()
    );
    result.insert(
        xdph.clone(),
        (
            managed(&contents(&xdph), &block, "dotfiles-share-picker")?.into_bytes(),
            0o644,
        ),
    );
    let rules = root().join("modules/rules.lua");
    if !rules.is_file() {
        bail!("Install the Hyprland dotfiles before the portal dialogs");
    }
    let block = "-- BEGIN dotfiles-portals\nhl.window_rule({\n    name = \"desktop-portal-dialogs\",\n    match = { class = \"org.quickshell\", title = \"^Desktop portal:.*$\" },\n    float = true,\n    center = true,\n    no_anim = true,\n})\n-- END dotfiles-portals";
    result.insert(
        rules.clone(),
        (
            managed(&contents(&rules), block, "dotfiles-portals")?.into_bytes(),
            0o644,
        ),
    );
    Ok(result)
}
fn backend_check() -> Result<()> {
    run(&[
        "systemctl",
        "--user",
        "start",
        "xdg-desktop-portal-gnome.service",
    ])?;
    for (bus, interface) in [
        ("org.freedesktop.impl.portal.desktop.gnome", "FileChooser"),
        (BUS, "AppChooser"),
        (BUS, "Access"),
    ] {
        run(&[
            "busctl",
            "--user",
            "introspect",
            bus,
            "/org/freedesktop/portal/desktop",
            &format!("org.freedesktop.impl.portal.{interface}"),
        ])?;
    }
    Ok(())
}
fn frontend_running(repo: &Path) -> bool {
    let Ok(pid) = run(&[
        "systemctl",
        "--user",
        "show",
        "xdg-desktop-portal.service",
        "-p",
        "MainPID",
        "--value",
    ]) else {
        return false;
    };
    pid.trim().parse::<u32>().is_ok_and(|p| {
        p > 0
            && release::target(repo)
                .ok()
                .and_then(|t| release::digest(&t).ok())
                .zip(release::digest(&PathBuf::from(format!("/proc/{p}/exe"))).ok())
                .is_some_and(|(a, b)| a == b)
    })
}
fn frontend_check(repo: &Path) -> Result<()> {
    release::verify(repo)?;
    if !frontend_running(repo) {
        bail!("Running portal differs from the local release; rerun manage install");
    }
    Ok(())
}
fn refresh(repo: &Path) -> Result<()> {
    run(&["systemctl", "--user", "daemon-reload"])?;
    run(&["systemctl", "--user", "restart", SERVICE])?;
    backend_check()?;
    run(&[
        "systemctl",
        "--user",
        "restart",
        "xdg-desktop-portal-hyprland.service",
    ])?;
    run(&[
        "systemctl",
        "--user",
        "restart",
        "xdg-desktop-portal.service",
    ])?;
    frontend_check(repo)?;
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
        run(&["hyprctl", "reload"])?;
        let errors = run(&["hyprctl", "configerrors"])?;
        if !errors.trim().is_empty() {
            bail!("{errors}");
        }
    }
    Ok(())
}
fn portals(repo: &Path, args: &[String]) -> Result<()> {
    let state = xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/xdg-desktop-portal");
    let _lock = Lock::acquire(&state.join("manage.lock"), false)?;
    let action = arg(args, 0)?;
    if action == "dump" {
        fs::copy(
            xdg("XDG_CONFIG_HOME", ".config").join("xdg-desktop-portal/hyprland-portals.conf"),
            repo.join("xdg-desktop-portal/hyprland-portals.conf"),
        )?;
        return Ok(());
    }
    let files = payloads(repo)?;
    let changed: Vec<_> = files
        .iter()
        .filter(|(p, (data, mode))| {
            fs::read(p).ok().as_ref() != Some(data)
                || p.metadata()
                    .is_ok_and(|m| m.permissions().mode() & 0o777 != *mode)
        })
        .collect();
    if action == "check" {
        frontend_check(repo)?;
        if !changed.is_empty() {
            bail!(
                "Installed portal files differ: {}",
                changed
                    .iter()
                    .map(|(p, _)| p.to_string_lossy())
                    .collect::<Vec<_>>()
                    .join(", ")
            );
        }
        backend_check()?;
        run(&[
            "systemctl",
            "--user",
            "is-active",
            "xdg-desktop-portal.service",
            SERVICE,
        ])?;
        println!("Custom portals, file chooser and sharing configuration verified.");
        return Ok(());
    }
    if action != "install" {
        bail!("Expected install, check or dump");
    }
    if !root().join("bin/dotfiles-desktop").is_file() {
        bail!("Install the Hyprland configuration and native executable first");
    }
    for binary in ["quickshell", "nautilus", "busctl"] {
        if !exists(binary) {
            bail!("Missing dependency: {binary}");
        }
    }
    let needs_build = release::verify(repo).is_err();
    if changed.is_empty() && !needs_build && frontend_running(repo) {
        backend_check()?;
        println!("Portal dialogs and routing already match.");
        return Ok(());
    }
    let tree = run(&[
        "busctl",
        "--user",
        "tree",
        "--list",
        "org.freedesktop.impl.portal.desktop.hyprland",
    ])?;
    if tree.contains("/org/freedesktop/portal/desktop/session/") {
        bail!("A portal session is active. Finish sharing or input capture before installing");
    }
    let tree = run(&["busctl", "--user", "tree", "--list", BUS]).unwrap_or_default();
    if tree.contains("/org/freedesktop/portal/desktop/request/") {
        bail!("A portal dialog is open; finish it before installing");
    }
    if needs_build {
        release::main(repo, &[])?;
    }
    release::verify(repo)?;
    let backup = state.join(chrono::Utc::now().format("%Y%m%dT%H%M%S.%6fZ").to_string());
    fs::create_dir_all(&backup)?;
    let mut metadata = vec![];
    for (i, (path, _)) in changed.iter().enumerate() {
        if linked(path) {
            bail!("Refusing linked target: {}", path.display());
        }
        let present = path.exists();
        if present {
            fs::copy(path, backup.join(i.to_string()))?;
        }
        metadata.push(json!({"target":path,"saved":i.to_string(),"present":present,"mode":path.metadata().ok().map(|m|m.permissions().mode()&0o777)}));
    }
    atomic_json(&backup.join("files.json"), &json!(metadata))?;
    let outcome = (|| -> Result<()> {
        for (path, (data, mode)) in &changed {
            atomic(path, data)?;
            fs::set_permissions(path, fs::Permissions::from_mode(*mode))?;
        }
        refresh(repo)?;
        run(&[
            "update-desktop-database",
            &xdg("XDG_DATA_HOME", ".local/share")
                .join("applications")
                .to_string_lossy(),
        ])?;
        Ok(())
    })();
    if let Err(error) = outcome {
        for entry in &metadata {
            let path = PathBuf::from(s(entry, "target"));
            if entry["present"] == true {
                fs::copy(backup.join(s(entry, "saved")), &path)?;
                if let Some(mode) = entry["mode"].as_u64() {
                    fs::set_permissions(path, fs::Permissions::from_mode(mode as u32))?;
                }
            } else {
                let _ = fs::remove_file(path);
            }
        }
        let _ = run(&["systemctl", "--user", "daemon-reload"]);
        let _ = run(&["systemctl", "--user", "stop", SERVICE]);
        for unit in [
            "xdg-desktop-portal-hyprland.service",
            "xdg-desktop-portal.service",
        ] {
            let _ = run(&["systemctl", "--user", "restart", unit]);
        }
        if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
            let _ = run(&["hyprctl", "reload"]);
        }
        return Err(error);
    }
    println!(
        "Installed native portal backend, dialogs and sharing picker. Backup: {}",
        backup.display()
    );
    Ok(())
}
pub fn main(args: &[String]) -> Result<()> {
    let kind = arg(args, 0)?;
    let repo = Path::new(arg(args, 1)?).canonicalize()?;
    if !repo.join("hyprland/config/hyprland.lua").is_file() {
        bail!("Not a dotfiles checkout");
    }
    match kind {
        "hyprland" => hyprland(&repo, &args[2..]),
        "portals" => portals(&repo, &args[2..]),
        "frontend" => release::main(&repo, &args[2..]),
        _ => bail!("Unknown maintenance command"),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn routing_preserves_other_preferences() {
        let text = "[Default Applications]\napplication/octet-stream=dev-code.desktop;reader.desktop;\ntext/plain=editor.desktop;\nx-scheme-handler/mailto=old.desktop;\n";
        let result = mime_defaults(text);
        assert!(result.contains("text/plain=editor.desktop"));
        assert!(result.contains("application/octet-stream=reader.desktop;"));
        assert!(!result.contains("old.desktop"));
        assert_eq!(result, mime_defaults(&result));
    }
    #[test]
    fn managed_blocks_are_idempotent_and_literal() {
        let block = "# BEGIN fixture\npath=$HOME\\thing\n# END fixture";
        let result = managed("unrelated", block, "fixture").unwrap();
        assert_eq!(result, managed(&result, block, "fixture").unwrap());
        assert!(managed("# BEGIN fixture\ntruncated", block, "fixture").is_err());
    }
    #[test]
    fn copy_preserves_user_symlinks_without_following_them() {
        let d = tempfile::tempdir().unwrap();
        let source = d.path().join("source");
        fs::create_dir(&source).unwrap();
        symlink("/outside", source.join("unrelated")).unwrap();
        copy_tree(&source, &d.path().join("stage")).unwrap();
        assert_eq!(
            fs::read_link(d.path().join("stage/unrelated")).unwrap(),
            PathBuf::from("/outside")
        );
    }
}

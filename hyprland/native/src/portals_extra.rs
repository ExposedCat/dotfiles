use crate::{
    portals::{Dialog, PATH, REQUEST, app_metadata, is_portal_frontend},
    util::*,
};
use anyhow::{Context, Result, bail};
use glib::{Variant, variant::ToVariant};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    env, fs,
    io::{BufRead, BufReader},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    rc::Rc,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const XML: &str = r#"<node>
  <interface name="org.freedesktop.impl.portal.Background">
    <method name="GetAppState">
      <arg type="a{sv}" name="apps" direction="out"/>
    </method>
    <method name="NotifyBackground">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="name" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="EnableAutostart">
      <arg type="s" name="app_id" direction="in"/>
      <arg type="b" name="enable" direction="in"/>
      <arg type="as" name="commandline" direction="in"/>
      <arg type="u" name="flags" direction="in"/>
      <arg type="b" name="result" direction="out"/>
    </method>
    <signal name="RunningApplicationsChanged"/>
  </interface>
  <interface name="org.freedesktop.impl.portal.Wallpaper">
    <method name="SetWallpaperURI">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="uri" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.impl.portal.Usb">
    <property name="version" type="u" access="read"/>
    <method name="AcquireDevices">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="a(sa{sv}a{sv})" name="devices" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
  </interface>
</node>"#;

type Options = HashMap<String, Variant>;
type UsbDeviceArg = (String, Options, Options);

enum PendingKind {
    NotifyBackground,
    Wallpaper {
        path: PathBuf,
        default_target: String,
    },
    Usb {
        devices: Vec<(String, Options)>,
    },
}

struct Pending {
    sender: String,
    invocation: gio::DBusMethodInvocation,
    kind: PendingKind,
    dialog: Dialog,
    registration: gio::RegistrationId,
}

struct ExtraState {
    bus: gio::DBusConnection,
    pending: HashMap<String, Pending>,
    testing: bool,
}

impl ExtraState {
    fn finish(&mut self, handle: &str, result: Value) {
        let Some(p) = self.pending.remove(handle) else {
            return;
        };
        let _ = self.bus.unregister_object(p.registration);
        let code = match result["response"].as_u64() {
            Some(n @ 0..=2) => n as u32,
            _ => 2,
        };
        match p.kind {
            PendingKind::NotifyBackground => {
                // 0 = Forbid, 1 = Allow, 2 = Allow this instance (ignore)
                let choice: u32 = match code {
                    0 => 1,
                    1 => 0,
                    _ => 2,
                };
                let mut results = HashMap::new();
                results.insert("result".to_string(), choice.to_variant());
                p.invocation
                    .return_value(Some(&(0u32, results).to_variant()));
            }
            PendingKind::Wallpaper {
                path,
                default_target,
            } => {
                if code != 0 {
                    p.invocation.return_value(Some(&(code,).to_variant()));
                    return;
                }
                let target = result["choices"]
                    .get("target")
                    .and_then(Value::as_str)
                    .filter(|t| matches!(*t, "background" | "lockscreen" | "both"))
                    .unwrap_or(&default_target);
                let out_code = match apply_wallpaper(&path, target) {
                    Ok(()) => 0u32,
                    Err(err) => {
                        eprintln!("Wallpaper portal apply failed: {err:#}");
                        2u32
                    }
                };
                p.invocation.return_value(Some(&(out_code,).to_variant()));
            }
            PendingKind::Usb { devices } => {
                if code != 0 {
                    let empty: Options = HashMap::new();
                    p.invocation
                        .return_value(Some(&(code, empty).to_variant()));
                    return;
                }
                let selected = result["choices"].as_object();
                let granted: Vec<(String, Options)> = devices
                    .into_iter()
                    .filter(|(id, _)| {
                        selected
                            .and_then(|map| map.get(id))
                            .and_then(Value::as_str)
                            == Some("true")
                    })
                    .collect();
                let mut results = HashMap::new();
                results.insert("devices".to_string(), granted.to_variant());
                p.invocation
                    .return_value(Some(&(0u32, results).to_variant()));
            }
        }
    }
}

pub fn register(
    bus: &gio::DBusConnection,
    testing: bool,
    stop: &Arc<AtomicBool>,
) -> Result<(Vec<gio::RegistrationId>, gio::SignalSubscription)> {
    let state = Rc::new(RefCell::new(ExtraState {
        bus: bus.clone(),
        pending: HashMap::new(),
        testing,
    }));
    let mut registrations = Vec::new();
    for interface in gio::DBusNodeInfo::for_xml(XML)?.interfaces() {
        let state = state.clone();
        let id = bus
            .register_object(PATH, interface)
            .property(|_, _, _, _, _| 1u32.to_variant())
            .method_call(move |_, sender, _, interface, method, params, invocation| {
                handle_call(
                    &state,
                    sender,
                    interface.unwrap_or(""),
                    method,
                    params,
                    invocation,
                )
            })
            .build()?;
        registrations.push(id);
    }

    let disconnected = state.clone();
    let owner_sub = bus.subscribe_to_signal(
        Some("org.freedesktop.DBus"),
        Some("org.freedesktop.DBus"),
        Some("NameOwnerChanged"),
        Some("/org/freedesktop/DBus"),
        None,
        gio::DBusSignalFlags::NONE,
        move |signal| {
            if let Some((name, old, new)) = signal.parameters.get::<(String, String, String)>()
                && !old.is_empty()
                && new.is_empty()
            {
                let mut s = disconnected.borrow_mut();
                let handles: Vec<_> = s
                    .pending
                    .iter()
                    .filter(|(_, p)| p.sender == name)
                    .map(|(h, _)| h.clone())
                    .collect();
                for h in handles {
                    s.finish(&h, json!({"response": 2}));
                }
            }
        },
    );

    if !testing {
        spawn_hyprland_window_watcher(bus.clone(), stop.clone());
    }
    Ok((registrations, owner_sub))
}

fn handle_call(
    state: &Rc<RefCell<ExtraState>>,
    sender: Option<&str>,
    interface: &str,
    method: &str,
    params: Variant,
    invocation: gio::DBusMethodInvocation,
) {
    let sender = sender.unwrap_or("");
    {
        let s = state.borrow();
        if !is_portal_frontend(&s.bus, sender, s.testing) {
            invocation.return_dbus_error(
                "org.freedesktop.DBus.Error.AccessDenied",
                "Only the portal frontend may invoke backend methods.",
            );
            return;
        }
    }
    let result = match (interface, method) {
        ("org.freedesktop.impl.portal.Background", "GetAppState") => {
            let apps = collect_app_state();
            invocation.clone().return_value(Some(&(apps,).to_variant()));
            Ok(())
        }
        ("org.freedesktop.impl.portal.Background", "EnableAutostart") => {
            handle_enable_autostart(params, &invocation)
        }
        ("org.freedesktop.impl.portal.Background", "NotifyBackground") => {
            handle_notify_background(state, sender, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Wallpaper", "SetWallpaperURI") => {
            handle_set_wallpaper_uri(state, sender, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Usb", "AcquireDevices") => {
            handle_acquire_devices(state, sender, params, &invocation)
        }
        _ => Err(anyhow::anyhow!(
            "Unknown portal method: {interface}.{method}"
        )),
    };
    if let Err(error) = result {
        invocation.return_dbus_error("org.freedesktop.portal.Error.Failed", &error.to_string());
    }
}

fn unescape_systemd_unit(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && i + 3 < bytes.len()
            && bytes[i + 1] == b'x'
            && let Ok(hex) = std::str::from_utf8(&bytes[i + 2..i + 4])
            && let Ok(byte) = u8::from_str_radix(hex, 16)
        {
            out.push(byte);
            i += 4;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn flatpak_id_from_cgroup(cgroup: &str) -> Option<String> {
    for line in cgroup.lines() {
        for segment in line.split('/') {
            if let Some(rest) = segment.strip_prefix("app-flatpak-")
                && let Some(stem) = rest.strip_suffix(".scope")
                && let Some((app, suffix)) = stem.rsplit_once('-')
                && !app.is_empty()
                && suffix.chars().all(|c| c.is_ascii_digit())
            {
                return Some(unescape_systemd_unit(app));
            }
        }
    }
    None
}

fn flatpak_id_for_pid(pid: i64) -> Option<String> {
    if pid <= 0 {
        return None;
    }
    if let Ok(env_bytes) = fs::read(format!("/proc/{pid}/environ")) {
        for entry in env_bytes.split(|&b| b == 0) {
            if let Some(val) = entry.strip_prefix(b"FLATPAK_ID=")
                && let Ok(id) = std::str::from_utf8(val)
                && !id.is_empty()
            {
                return Some(id.to_string());
            }
        }
    }
    if let Ok(cgroup) = fs::read_to_string(format!("/proc/{pid}/cgroup"))
        && let Some(id) = flatpak_id_from_cgroup(&cgroup)
    {
        return Some(id);
    }
    None
}

fn app_state_from_hyprland(clients: &Value, active: Option<&Value>) -> HashMap<String, u32> {
    let active_addr = active
        .and_then(|v| v["address"].as_str())
        .filter(|a| !a.is_empty());
    let mut states: HashMap<String, u32> = HashMap::new();
    for client in rows(clients) {
        if client["mapped"] == false || client["hidden"] == true {
            continue;
        }
        let pid = client["pid"].as_i64().unwrap_or(0);
        let addr = client["address"].as_str().unwrap_or("");
        let level = if active_addr.is_some_and(|a| a == addr) {
            2u32
        } else {
            1u32
        };
        let mut ids = Vec::new();
        if let Some(fp) = flatpak_id_for_pid(pid) {
            ids.push(fp);
        }
        for field in ["class", "initialClass"] {
            let value = s(client, field);
            if !value.is_empty() && !ids.iter().any(|existing| existing == value) {
                ids.push(value.to_string());
            }
        }
        for id in ids {
            let entry = states.entry(id).or_insert(0);
            if level > *entry {
                *entry = level;
            }
        }
    }
    states
}

fn collect_app_state() -> HashMap<String, Variant> {
    if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return HashMap::new();
    }
    let Ok(clients) = json(&["hyprctl", "-j", "clients"]) else {
        return HashMap::new();
    };
    let active = json(&["hyprctl", "-j", "activewindow"]).ok();
    app_state_from_hyprland(&clients, active.as_ref())
        .into_iter()
        .map(|(id, level)| (id, level.to_variant()))
        .collect()
}

fn spawn_hyprland_window_watcher(bus: gio::DBusConnection, stop: Arc<AtomicBool>) {
    let Ok(signature) = env::var("HYPRLAND_INSTANCE_SIGNATURE") else {
        return;
    };
    let Ok(rt) = runtime() else {
        return;
    };
    let socket_path = rt.join("hypr").join(signature).join(".socket2.sock");
    std::thread::spawn(move || {
        let mut last_emit = Instant::now() - Duration::from_secs(1);
        while !stop.load(Ordering::Relaxed) {
            let Ok(stream) = UnixStream::connect(&socket_path) else {
                std::thread::sleep(Duration::from_secs(2));
                continue;
            };
            let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            while !stop.load(Ordering::Relaxed) {
                line.clear();
                match reader.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        let relevant = line.starts_with("openwindow>>")
                            || line.starts_with("closewindow>>")
                            || line.starts_with("activewindow>>")
                            || line.starts_with("activewindowv2>>")
                            || line.starts_with("movewindow>>")
                            || line.starts_with("changefloatingmode>>");
                        if relevant && last_emit.elapsed() >= Duration::from_millis(150) {
                            last_emit = Instant::now();
                            let bus = bus.clone();
                            glib::MainContext::default().invoke(move || {
                                let _ = bus.emit_signal(
                                    None,
                                    PATH,
                                    "org.freedesktop.impl.portal.Background",
                                    "RunningApplicationsChanged",
                                    None,
                                );
                            });
                        }
                    }
                    Err(err)
                        if matches!(
                            err.kind(),
                            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                        ) => {}
                    Err(_) => break,
                }
            }
            std::thread::sleep(Duration::from_millis(500));
        }
    });
}

fn valid_app_id(app_id: &str) -> bool {
    !app_id.is_empty()
        && !app_id.contains('/')
        && !app_id.contains('\\')
        && !app_id.contains('\0')
        && !app_id.contains("..")
}

fn escape_desktop_arg(arg: &str) -> String {
    let escaped = arg
        .replace('%', "%%")
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('`', "\\`")
        .replace('$', "\\$");
    if arg.is_empty()
        || arg
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, '"' | '\'' | '\\' | '$' | '`' | ';'))
    {
        format!("\"{escaped}\"")
    } else {
        escaped
    }
}

fn handle_enable_autostart(
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let app_id = params
        .child_value(0)
        .get::<String>()
        .context("Invalid app_id")?;
    let enable = params
        .child_value(1)
        .get::<bool>()
        .context("Invalid enable flag")?;
    let commandline = params
        .child_value(2)
        .get::<Vec<String>>()
        .context("Invalid commandline")?;
    let flags = params
        .child_value(3)
        .get::<u32>()
        .context("Invalid flags")?;
    if !valid_app_id(&app_id) {
        bail!("Invalid application ID");
    }
    let dir = xdg("XDG_CONFIG_HOME", ".config").join("autostart");
    let path = dir.join(format!("{app_id}.desktop"));
    if !enable {
        match fs::remove_file(&path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => return Err(err.into()),
        }
        invocation.clone().return_value(Some(&(false,).to_variant()));
        return Ok(());
    }
    if commandline.is_empty() {
        bail!("Autostart commandline is empty");
    }
    let meta = app_metadata(&app_id);
    let name = s(&meta, "name");
    let exec = commandline
        .iter()
        .map(|part| escape_desktop_arg(part))
        .collect::<Vec<_>>()
        .join(" ");
    let mut desktop = format!(
        "[Desktop Entry]\nType=Application\nName={}\nExec={exec}\nX-XDP-Autostart={app_id}\n",
        if name.is_empty() { &app_id } else { name }
    );
    if flags & 1 != 0 {
        desktop.push_str("DBusActivatable=true\n");
    }
    atomic(&path, desktop.as_bytes())?;
    invocation.clone().return_value(Some(&(true,).to_variant()));
    Ok(())
}

fn open_pending_dialog(
    state: &Rc<RefCell<ExtraState>>,
    sender: &str,
    handle: String,
    data: Value,
    kind: PendingKind,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    if state.borrow().pending.contains_key(&handle) {
        bail!("Request already exists");
    }
    if state.borrow().pending.len() >= 16 {
        bail!("Too many pending requests");
    }
    let dialog = Dialog::open(&data)?;
    let close_state = state.clone();
    let registration = state
        .borrow()
        .bus
        .register_object(
            &handle,
            &gio::DBusNodeInfo::for_xml(REQUEST)?.interfaces()[0],
        )
        .method_call(move |_, caller, path, _, _, _, call| {
            let mut s = close_state.borrow_mut();
            if s.pending
                .get(path)
                .is_some_and(|p| Some(p.sender.as_str()) != caller)
            {
                call.return_dbus_error(
                    "org.freedesktop.DBus.Error.AccessDenied",
                    "Request belongs to another caller.",
                );
                return;
            }
            s.finish(path, json!({"response": 2}));
            call.return_value(None);
        })
        .build()?;
    state.borrow_mut().pending.insert(
        handle.clone(),
        Pending {
            sender: sender.into(),
            invocation: invocation.clone(),
            kind,
            dialog,
            registration,
        },
    );
    let poll_state = state.clone();
    glib::timeout_add_local(Duration::from_millis(16), move || {
        let mut s = poll_state.borrow_mut();
        let result = match s.pending.get_mut(&handle) {
            None => return glib::ControlFlow::Break,
            Some(p) => match p.dialog.poll() {
                Ok(false) => return glib::ControlFlow::Continue,
                Ok(true) => p.dialog.result(),
                Err(err) => {
                    eprintln!("Portal request: {err}");
                    json!({"response": 2})
                }
            },
        };
        s.finish(&handle, result);
        glib::ControlFlow::Break
    });
    Ok(())
}

fn handle_notify_background(
    state: &Rc<RefCell<ExtraState>>,
    sender: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let handle = params
        .child_value(0)
        .str()
        .context("Invalid handle")?
        .to_string();
    let app_id = params
        .child_value(1)
        .get::<String>()
        .context("Invalid app_id")?;
    let name = params.child_value(2).get::<String>().unwrap_or_default();
    let app = app_metadata(&app_id);
    let display = if !name.is_empty() {
        name
    } else {
        s(&app, "name").to_string()
    };
    let data = json!({
        "kind": "access",
        "app": app,
        "parent": "",
        "activationToken": "",
        "title": format!("{display} is running in the background"),
        "subtitle": format!("Allow {display} to continue running without any open windows?"),
        "body": "You can change background permissions later.",
        "choices": [],
        "grantLabel": "Allow",
        "denyLabel": "Forbid",
    });
    open_pending_dialog(
        state,
        sender,
        handle,
        data,
        PendingKind::NotifyBackground,
        invocation,
    )
}

fn wallpaper_state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland")
}

fn validate_image(path: &Path) -> Result<(u32, u32, String)> {
    let reader = image::ImageReader::open(path)
        .with_context(|| format!("Cannot open image: {}", path.display()))?
        .with_guessed_format()
        .context("Cannot detect image format")?;
    let format = reader.format().context("Unsupported image format")?;
    let ext = format
        .extensions_str()
        .first()
        .copied()
        .unwrap_or("img")
        .to_string();
    let (w, h) = reader
        .into_dimensions()
        .context("Invalid image dimensions")?;
    if w == 0 || h == 0 {
        bail!("Image has zero dimensions");
    }
    Ok((w, h, ext))
}

fn apply_wallpaper(source: &Path, target: &str) -> Result<()> {
    let (_, _, ext) = validate_image(source)?;
    let bytes = fs::read(source)?;
    let dir = wallpaper_state_dir();
    fs::create_dir_all(&dir)?;
    let state_path = dir.join("wallpaper.json");
    let mut state = read_json(&state_path).unwrap_or_else(|_| json!({}));
    if !state.is_object() {
        state = json!({});
    }
    let updated = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    if matches!(target, "background" | "both") {
        let dest = dir.join(format!("wallpaper-{updated}.{ext}"));
        atomic(&dest, &bytes)?;
        if let Some(old) = state["background"].as_str()
            && old != dest.to_string_lossy()
        {
            let _ = fs::remove_file(old);
        }
        state["background"] = json!(dest.to_string_lossy());
    }
    if matches!(target, "lockscreen" | "both") {
        let dest = dir.join(format!("lockscreen-wallpaper-{updated}.{ext}"));
        atomic(&dest, &bytes)?;
        if let Some(old) = state["lockscreen"].as_str()
            && old != dest.to_string_lossy()
        {
            let _ = fs::remove_file(old);
        }
        state["lockscreen"] = json!(dest.to_string_lossy());
        let lock_conf = format!(
            "background {{\n    monitor =\n    path = {}\n    color = rgb(1e1e2e)\n}}\n",
            dest.display()
        );
        atomic(&dir.join("hyprlock-wallpaper.conf"), lock_conf.as_bytes())?;
    }
    state["updated"] = json!(updated);
    atomic_json(&state_path, &state)?;
    Ok(())
}

fn handle_set_wallpaper_uri(
    state: &Rc<RefCell<ExtraState>>,
    sender: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let handle = params
        .child_value(0)
        .str()
        .context("Invalid handle")?
        .to_string();
    let app_id = params
        .child_value(1)
        .get::<String>()
        .context("Invalid app_id")?;
    let parent = params.child_value(2).get::<String>().unwrap_or_default();
    let uri = params
        .child_value(3)
        .get::<String>()
        .context("Invalid URI")?;
    let options = params
        .child_value(4)
        .get::<Options>()
        .context("Invalid options")?;

    let url = url::Url::parse(&uri).context("Invalid wallpaper URI")?;
    let path = url
        .to_file_path()
        .map_err(|_| anyhow::anyhow!("Wallpaper URI must point to a local file"))?;
    let (width, height, _) = validate_image(&path)?;

    let show_preview = options
        .get("show-preview")
        .and_then(|v| v.get::<bool>())
        .unwrap_or(false);
    let set_on = options
        .get("set-on")
        .and_then(|v| v.get::<String>())
        .filter(|s| matches!(s.as_str(), "background" | "lockscreen" | "both"))
        .unwrap_or_else(|| "both".to_string());

    if !show_preview {
        apply_wallpaper(&path, &set_on)?;
        invocation.clone().return_value(Some(&(0u32,).to_variant()));
        return Ok(());
    }

    let app = app_metadata(&app_id);
    let filename = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string());
    let data = json!({
        "kind": "access",
        "app": app,
        "parent": parent,
        "activationToken": "",
        "title": "Set wallpaper?",
        "subtitle": format!("{filename} ({width} × {height})"),
        "body": "Choose where to apply this image.",
        "choices": [{
            "id": "target",
            "name": "Apply to",
            "values": [
                {"id": "background", "name": "Desktop"},
                {"id": "lockscreen", "name": "Lock screen"},
                {"id": "both", "name": "Both"}
            ],
            "selected": set_on
        }],
        "grantLabel": "Set wallpaper",
        "denyLabel": "Cancel",
    });
    open_pending_dialog(
        state,
        sender,
        handle,
        data,
        PendingKind::Wallpaper {
            path,
            default_target: set_on,
        },
        invocation,
    )
}

fn usb_device_label(id: &str, info: &Options, access: &Options) -> String {
    let props = info
        .get("properties")
        .and_then(|v| v.get::<Options>());
    let get = |key: &str| {
        props
            .as_ref()
            .and_then(|p| p.get(key))
            .or_else(|| info.get(key))
            .and_then(|v| v.get::<String>())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    };
    let vendor = get("ID_VENDOR_FROM_DATABASE")
        .or_else(|| get("ID_VENDOR"))
        .or_else(|| get("vendor"));
    let model = get("ID_MODEL_FROM_DATABASE")
        .or_else(|| get("ID_MODEL"))
        .or_else(|| get("model"));
    let base = match (vendor, model) {
        (Some(v), Some(m)) if m.to_lowercase().starts_with(&v.to_lowercase()) => m,
        (Some(v), Some(m)) => format!("{v} {m}"),
        (None, Some(m)) => m,
        (Some(v), None) => format!("{v} ({id})"),
        (None, None) => get("device-file").unwrap_or_else(|| id.to_string()),
    };
    let writable = access
        .get("writable")
        .and_then(|v| v.get::<bool>())
        .unwrap_or(false);
    if writable {
        format!("{base} (read/write)")
    } else {
        base
    }
}

fn handle_acquire_devices(
    state: &Rc<RefCell<ExtraState>>,
    sender: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let handle = params
        .child_value(0)
        .str()
        .context("Invalid handle")?
        .to_string();
    let parent = params.child_value(1).get::<String>().unwrap_or_default();
    let app_id = params
        .child_value(2)
        .get::<String>()
        .context("Invalid app_id")?;
    let devices = params
        .child_value(3)
        .get::<Vec<UsbDeviceArg>>()
        .context("Invalid USB devices")?;
    if devices.is_empty() {
        bail!("No USB devices requested");
    }

    let app = app_metadata(&app_id);
    let display = s(&app, "name").to_string();
    let mut choices = Vec::with_capacity(devices.len());
    let mut requested = Vec::with_capacity(devices.len());
    for (id, info, access) in devices {
        let label = usb_device_label(&id, &info, &access);
        choices.push(json!({
            "id": id,
            "name": label,
            "values": [],
            "selected": "true"
        }));
        requested.push((id, access));
    }
    let data = json!({
        "kind": "access",
        "app": app,
        "parent": parent,
        "activationToken": "",
        "title": format!("Allow {display} USB access?"),
        "subtitle": "Select which USB devices this application may access.",
        "body": "",
        "choices": choices,
        "grantLabel": "Allow",
        "denyLabel": "Deny",
    });
    open_pending_dialog(
        state,
        sender,
        handle,
        data,
        PendingKind::Usb { devices: requested },
        invocation,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_flatpak_id_from_cgroup_scope() {
        let cgroup = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.chipichapa.Brevlada-2732752513.scope\n";
        assert_eq!(
            flatpak_id_from_cgroup(cgroup).as_deref(),
            Some("com.chipichapa.Brevlada")
        );
        let escaped = "0::/user.slice/app-flatpak-org.gnome.my\\x2dapp-12345.scope\n";
        assert_eq!(
            flatpak_id_from_cgroup(escaped).as_deref(),
            Some("org.gnome.my-app")
        );
    }

    #[test]
    fn maps_hyprland_clients_to_active_and_running_states() {
        let clients = json!([
            {"address": "0x1", "mapped": true, "hidden": false, "pid": 0, "class": "com.chipichapa.Brevlada", "initialClass": "com.chipichapa.Brevlada"},
            {"address": "0x2", "mapped": true, "hidden": false, "pid": 0, "class": "firefox", "initialClass": "firefox"},
            {"address": "0x3", "mapped": false, "hidden": false, "pid": 0, "class": "hidden.app", "initialClass": "hidden.app"}
        ]);
        let active = json!({"address": "0x1", "class": "com.chipichapa.Brevlada"});
        let states = app_state_from_hyprland(&clients, Some(&active));
        assert_eq!(states.get("com.chipichapa.Brevlada"), Some(&2));
        assert_eq!(states.get("firefox"), Some(&1));
        assert!(!states.contains_key("hidden.app"));
    }

    #[test]
    fn formats_usb_device_labels() {
        let mut props: Options = HashMap::new();
        props.insert("ID_VENDOR_FROM_DATABASE".into(), "Yubico".to_variant());
        props.insert("ID_MODEL_FROM_DATABASE".into(), "YubiKey 5".to_variant());
        let mut info = HashMap::new();
        info.insert("properties".into(), props.to_variant());
        let mut access = HashMap::new();
        access.insert("writable".into(), true.to_variant());
        assert_eq!(
            usb_device_label("dev1", &info, &access),
            "Yubico YubiKey 5 (read/write)"
        );
    }
}

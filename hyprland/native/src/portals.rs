use crate::util::*;
use anyhow::{Context, Result, bail};
use gio::prelude::*;
use glib::{Variant, variant::ToVariant};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    env,
    io::{Read, Write},
    os::unix::net::UnixStream,
    process::{Child, Stdio},
    rc::Rc,
    time::Duration,
};
const BUS: &str = "org.freedesktop.impl.portal.desktop.dotfiles";
const PATH: &str = "/org/freedesktop/portal/desktop";
const XML: &str = r#"<node><interface name="org.freedesktop.impl.portal.AppChooser"><property name="version" type="u" access="read"/><method name="ChooseApplication"><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="u" direction="out"/><arg type="a{sv}" direction="out"/></method><method name="UpdateChoices"><arg type="o" direction="in"/><arg type="as" direction="in"/></method></interface><interface name="org.freedesktop.impl.portal.Access"><property name="version" type="u" access="read"/><method name="AccessDialog"><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="u" direction="out"/><arg type="a{sv}" direction="out"/></method></interface></node>"#;
const REQUEST: &str = r#"<node><interface name="org.freedesktop.impl.portal.Request"><method name="Close"/></interface></node>"#;
pub fn app_metadata(id: &str) -> Value {
    let desktop = if id.ends_with(".desktop") {
        id.to_string()
    } else {
        format!("{id}.desktop")
    };
    if let Some(app) = gio_unix::DesktopAppInfo::new(&desktop) {
        let icon = app
            .icon()
            .map(|i| {
                if let Some(themed) = i.downcast_ref::<gio::ThemedIcon>() {
                    themed
                        .names()
                        .first()
                        .map(ToString::to_string)
                        .unwrap_or_default()
                } else if let Some(file) = i.downcast_ref::<gio::FileIcon>() {
                    file.file()
                        .path()
                        .map(|p| p.to_string_lossy().into_owned())
                        .unwrap_or_default()
                } else {
                    String::new()
                }
            })
            .unwrap_or_default();
        json!({"id":desktop.strip_suffix(".desktop").unwrap_or(&desktop),"name":app.display_name().as_str(),"icon":icon,"description":app.description().unwrap_or_default().as_str()})
    } else {
        json!({"id":id,"name":if id.is_empty(){"Application"}else{id},"icon":"","description":""})
    }
}
fn app_choices(mut ids: Vec<String>) -> Vec<Value> {
    if ids.is_empty() {
        ids = gio::AppInfo::all()
            .iter()
            .filter(|a| a.should_show() && (a.supports_files() || a.supports_uris()))
            .filter_map(|a| a.id().map(|s| s.to_string()))
            .collect();
        ids.sort();
    }
    let mut seen = std::collections::HashSet::new();
    ids.into_iter()
        .filter(|s| seen.insert(s.clone()))
        .map(|id| {
            let mut app = app_metadata(&id);
            app["id"] = json!(id);
            app
        })
        .collect()
}
enum Transport {
    Pill(UnixStream, Vec<u8>),
    Window(Child),
}
pub struct Dialog {
    dir: tempfile::TempDir,
    transport: Transport,
}
impl Dialog {
    pub fn open(data: &Value) -> Result<Self> {
        let dir = tempfile::Builder::new()
            .prefix("dotfiles-portal-")
            .tempdir_in(runtime()?)?;
        atomic_json(&dir.path().join("request.json"), data)?;
        let socket = runtime()?.join("dotfiles-portal-shell.sock");
        let mut transport = None;
        if data["fixture"] != true {
            match UnixStream::connect(socket) {
                Ok(mut socket) => {
                    socket.set_read_timeout(Some(Duration::from_secs(2)))?;
                    socket.set_write_timeout(Some(Duration::from_secs(2)))?;
                    writeln!(
                        socket,
                        "{}",
                        json!({"action":"open","directory":dir.path()})
                    )?;
                    let mut bytes = Vec::new();
                    let mut chunk = [0; 4096];
                    let line = loop {
                        let n = socket
                            .read(&mut chunk)
                            .context("Pill acknowledgement timed out")?;
                        if n == 0 || bytes.len() > 65536 {
                            bail!("Pill did not acknowledge the portal request");
                        }
                        bytes.extend_from_slice(&chunk[..n]);
                        if let Some(at) = bytes.iter().position(|&b| b == b'\n') {
                            break at;
                        }
                    };
                    let reply: Value = serde_json::from_slice(&bytes[..line])?;
                    if reply["accepted"] == true {
                        socket.set_read_timeout(None)?;
                        socket.set_write_timeout(None)?;
                        socket.set_nonblocking(true)?;
                        transport = Some(Transport::Pill(socket, bytes[line + 1..].to_vec()));
                    } else if reply["accepted"] != false {
                        bail!("Invalid pill acknowledgement: {reply}");
                    }
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
                    ) => {}
                Err(e) => return Err(e.into()),
            }
        }
        let transport = match transport {
            Some(t) => t,
            None => {
                let mut c = command(&[
                    "/usr/bin/quickshell",
                    "--no-color",
                    "--path",
                    &root().join("portal.qml").to_string_lossy(),
                ]);
                c.env("DOTFILES_PORTAL_REQUEST", dir.path())
                    .stdout(Stdio::from(std::io::stderr()));
                if !s(data, "activationToken").is_empty() {
                    c.env("XDG_ACTIVATION_TOKEN", s(data, "activationToken"));
                }
                Transport::Window(c.spawn()?)
            }
        };
        Ok(Self { dir, transport })
    }
    pub fn update(&self, data: &Value) -> Result<()> {
        atomic_json(&self.dir.path().join("request.json"), data)
    }
    pub fn poll(&mut self) -> Result<bool> {
        match &mut self.transport {
            Transport::Window(c) => Ok(c.try_wait()?.is_some()),
            Transport::Pill(socket, buffer) => {
                if buffer.contains(&b'\n') {
                    return Ok(true);
                }
                let mut bytes = [0; 4096];
                match socket.read(&mut bytes) {
                    Ok(0) => Ok(true),
                    Ok(n) => {
                        buffer.extend_from_slice(&bytes[..n]);
                        if buffer.len() > 65536 {
                            bail!("Oversized pill response");
                        }
                        Ok(buffer.contains(&b'\n'))
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(false),
                    Err(_) => Ok(true),
                }
            }
        }
    }
    pub fn result(&self) -> Value {
        read_json(&self.dir.path().join("response.json"))
            .ok()
            .filter(Value::is_object)
            .unwrap_or(json!({"response":2}))
    }
    fn wait(&mut self) -> Result<Value> {
        let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let mut handlers = vec![];
        for signal in [libc::SIGTERM, libc::SIGINT] {
            handlers.push(signal_hook::flag::register(signal, stop.clone())?);
        }
        let result = (|| {
            while !self.poll()? {
                if stop.load(std::sync::atomic::Ordering::Relaxed) {
                    return Ok(json!({"response":2}));
                }
                std::thread::sleep(Duration::from_millis(8));
            }
            Ok(self.result())
        })();
        for handler in handlers {
            signal_hook::low_level::unregister(handler);
        }
        result
    }
}
impl Drop for Dialog {
    fn drop(&mut self) {
        match &mut self.transport {
            Transport::Pill(s, _) => {
                let _ = s.shutdown(std::net::Shutdown::Both);
            }
            Transport::Window(c) => {
                if c.try_wait().ok().flatten().is_none() {
                    unsafe {
                        libc::kill(c.id() as i32, libc::SIGTERM);
                    }
                    use wait_timeout::ChildExt;
                    if c.wait_timeout(Duration::from_secs(2))
                        .ok()
                        .flatten()
                        .is_none()
                    {
                        let _ = c.kill();
                    }
                    let _ = c.wait();
                }
            }
        }
    }
}
type Options = HashMap<String, Variant>;
fn opt(options: &Options, key: &str) -> String {
    options.get(key).and_then(|v| v.get()).unwrap_or_default()
}
fn access_choices(options: &Options) -> Result<Vec<Value>> {
    type Choices = Vec<(String, String, Vec<(String, String)>, String)>;
    let values = options
        .get("choices")
        .and_then(|v| v.get::<Choices>())
        .unwrap_or_default();
    let mut seen = std::collections::HashSet::new();
    let mut result = vec![];
    for (id, name, values, mut selected) in values {
        if !seen.insert(id.clone()) {
            bail!("Duplicate choice ID");
        }
        let allowed: Vec<_> = if values.is_empty() {
            vec!["false", "true"]
        } else {
            values.iter().map(|v| v.0.as_str()).collect()
        };
        if !allowed.contains(&selected.as_str()) {
            selected = allowed[0].into();
        }
        result.push(json!({"id":id,"name":name,"values":values.into_iter().map(|(id,name)|json!({"id":id,"name":name})).collect::<Vec<_>>(),"selected":selected}));
    }
    Ok(result)
}
fn label(s: &str) -> String {
    s.replace("__", "\0").replace('_', "").replace('\0', "_")
}
fn response_values(data: &Value, result: &Value) -> (u32, Options) {
    let mut values = HashMap::new();
    let response = match result["response"].as_u64() {
        Some(n @ 0..=2) => n as u32,
        _ => 2,
    };
    if response != 0 {
        return (response, values);
    }
    if data["kind"] == "apps" {
        let Some(choice) = result["choice"].as_str() else {
            return (2, values);
        };
        if !rows(&data["apps"]).iter().any(|a| a["id"] == choice) {
            return (2, values);
        }
        values.insert(
            "choice".into(),
            choice
                .strip_suffix(".desktop")
                .unwrap_or(choice)
                .to_variant(),
        );
    } else {
        let Some(selected) = result["choices"].as_object() else {
            return (2, values);
        };
        let mut pairs = vec![];
        for choice in rows(&data["choices"]) {
            let value = selected.get(s(choice, "id")).unwrap_or(&choice["selected"]);
            let allowed = if rows(&choice["values"]).is_empty() {
                value == "true" || value == "false"
            } else {
                rows(&choice["values"]).iter().any(|v| v["id"] == *value)
            };
            if !allowed {
                return (2, HashMap::new());
            }
            pairs.push((
                s(choice, "id").to_string(),
                value.as_str().unwrap_or_default().to_string(),
            ));
        }
        values.insert("choices".into(), pairs.to_variant());
    }
    (0, values)
}
struct Pending {
    sender: String,
    invocation: gio::DBusMethodInvocation,
    data: Value,
    dialog: Dialog,
    registration: gio::RegistrationId,
}
struct Backend {
    bus: gio::DBusConnection,
    pending: HashMap<String, Pending>,
    testing: bool,
}
impl Backend {
    fn finish(&mut self, handle: &str, result: Value) {
        if let Some(p) = self.pending.remove(handle) {
            let (code, values) = response_values(&p.data, &result);
            p.invocation
                .return_value(Some(&(code, values).to_variant()));
            let _ = self.bus.unregister_object(p.registration);
        }
    }
    fn authorized(&self, sender: &str) -> bool {
        self.testing
            || self
                .bus
                .call_sync(
                    Some("org.freedesktop.DBus"),
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "GetNameOwner",
                    Some(&("org.freedesktop.portal.Desktop",).to_variant()),
                    None,
                    gio::DBusCallFlags::NONE,
                    1500,
                    gio::Cancellable::NONE,
                )
                .ok()
                .and_then(|v| v.child_value(0).get::<String>())
                .is_some_and(|s| s == sender)
    }
}
fn begin_call(
    state: &Rc<RefCell<Backend>>,
    sender: &str,
    method: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let handle = params
        .child_value(0)
        .str()
        .context("Invalid handle")?
        .to_string();
    if method == "UpdateChoices" {
        let mut b = state.borrow_mut();
        if let Some(p) = b.pending.get_mut(&handle)
            && p.sender == sender
            && p.data["kind"] == "apps"
        {
            p.data["apps"] = json!(app_choices(
                params.child_value(1).get().context("Invalid choices")?
            ));
            p.dialog.update(&p.data)?;
        }
        invocation.clone().return_value(None);
        return Ok(());
    }
    if state.borrow().pending.contains_key(&handle) {
        bail!("Request already exists");
    }
    if state.borrow().pending.len() >= 16 {
        bail!("Too many pending requests");
    }
    let app = params
        .child_value(1)
        .get::<String>()
        .context("Invalid application")?;
    let parent = params.child_value(2).get::<String>().unwrap_or_default();
    let options = params
        .child_value(params.n_children() - 1)
        .get::<Options>()
        .context("Invalid options")?;
    let mut data = json!({"app":app_metadata(&app),"parent":parent,"activationToken":opt(&options,"activation_token")});
    if method == "ChooseApplication" {
        data["kind"] = json!("apps");
        data["title"] = json!("Open with");
        data["filename"] = json!(opt(&options, "filename"));
        data["contentType"] = json!(opt(&options, "content_type"));
        data["apps"] = json!(app_choices(
            params.child_value(3).get().context("Invalid choices")?
        ));
    } else if method == "AccessDialog" {
        data["kind"] = json!("access");
        for (i, key) in ["title", "subtitle", "body"].iter().enumerate() {
            data[*key] = json!(
                params
                    .child_value(i + 3)
                    .get::<String>()
                    .unwrap_or_default()
            );
        }
        data["choices"] = json!(access_choices(&options)?);
        data["denyLabel"] = json!(label(
            options
                .get("deny_label")
                .and_then(|v| v.str())
                .unwrap_or("Deny")
        ));
        data["grantLabel"] = json!(label(
            options
                .get("grant_label")
                .and_then(|v| v.str())
                .unwrap_or("Allow")
        ));
    } else {
        bail!("Unknown method");
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
        .method_call(move |_, sender, path, _, _, _, call| {
            let mut b = close_state.borrow_mut();
            if b.pending
                .get(path)
                .is_some_and(|p| Some(p.sender.as_str()) != sender)
            {
                call.return_dbus_error(
                    "org.freedesktop.DBus.Error.AccessDenied",
                    "Request belongs to another caller.",
                );
                return;
            }
            b.finish(path, json!({"response":2}));
            call.return_value(None);
        })
        .build()?;
    state.borrow_mut().pending.insert(
        handle.clone(),
        Pending {
            sender: sender.into(),
            invocation: invocation.clone(),
            data,
            dialog,
            registration,
        },
    );
    let poll_state = state.clone();
    glib::timeout_add_local(Duration::from_millis(16), move || {
        let mut b = poll_state.borrow_mut();
        let result = match b.pending.get_mut(&handle) {
            None => return glib::ControlFlow::Break,
            Some(p) => match p.dialog.poll() {
                Ok(false) => return glib::ControlFlow::Continue,
                Ok(true) => p.dialog.result(),
                Err(e) => {
                    eprintln!("Portal request: {e}");
                    json!({"response":2})
                }
            },
        };
        b.finish(&handle, result);
        glib::ControlFlow::Break
    });
    Ok(())
}
fn handle_call(
    state: &Rc<RefCell<Backend>>,
    sender: Option<&str>,
    method: &str,
    params: Variant,
    invocation: gio::DBusMethodInvocation,
) {
    let sender = sender.unwrap_or("");
    if !state.borrow().authorized(sender) {
        invocation.return_dbus_error(
            "org.freedesktop.DBus.Error.AccessDenied",
            "Only the portal frontend may request dialogs.",
        );
        return;
    }
    if let Err(error) = begin_call(state, sender, method, params, &invocation) {
        invocation.return_dbus_error("org.freedesktop.portal.Error.Failed", &error.to_string());
    }
}
fn backend(testing: bool) -> Result<()> {
    if testing && env::var_os("ISOLATED_GUI_SESSION").is_none() {
        bail!("Test backend requires isolated-gui");
    }
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)?;
    let state = Rc::new(RefCell::new(Backend {
        bus: bus.clone(),
        pending: HashMap::new(),
        testing,
    }));
    for interface in gio::DBusNodeInfo::for_xml(XML)?.interfaces() {
        let state = state.clone();
        bus.register_object(PATH, interface)
            .property(|_, _, _, interface, _| {
                if interface.ends_with("AppChooser") {
                    2u32.to_variant()
                } else {
                    1u32.to_variant()
                }
            })
            .method_call(move |_, sender, _, _, method, params, invocation| {
                handle_call(&state, sender, method, params, invocation)
            })
            .build()?;
    }
    let disconnected = state.clone();
    let _owner_subscription = bus.subscribe_to_signal(
        Some("org.freedesktop.DBus"),
        Some("org.freedesktop.DBus"),
        Some("NameOwnerChanged"),
        Some("/org/freedesktop/DBus"),
        None,
        gio::DBusSignalFlags::NONE,
        move |signal| {
            let params = signal.parameters;
            if let Some((name, old, new)) = params.get::<(String, String, String)>()
                && !old.is_empty()
                && new.is_empty()
            {
                let mut b = disconnected.borrow_mut();
                let handles: Vec<_> = b
                    .pending
                    .iter()
                    .filter(|(_, p)| p.sender == name)
                    .map(|(h, _)| h.clone())
                    .collect();
                for h in handles {
                    b.finish(&h, json!({"response":2}));
                }
            }
        },
    );
    let owned = bus.call_sync(
        Some("org.freedesktop.DBus"),
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "RequestName",
        Some(&(BUS, 4u32).to_variant()),
        None,
        gio::DBusCallFlags::NONE,
        2000,
        gio::Cancellable::NONE,
    )?;
    if owned.child_value(0).get::<u32>() != Some(1) {
        bail!("Portal backend already running");
    }
    let main_loop = glib::MainLoop::new(None, false);
    for signal in [libc::SIGINT, libc::SIGTERM] {
        let l = main_loop.clone();
        glib_unix::unix_signal_add_local(signal, move || {
            l.quit();
            glib::ControlFlow::Break
        });
    }
    main_loop.run();
    let mut b = state.borrow_mut();
    let handles: Vec<_> = b.pending.keys().cloned().collect();
    for h in handles {
        b.finish(&h, json!({"response":2}));
    }
    Ok(())
}
struct Fields {
    bytes: Vec<u8>,
    at: usize,
}
impl Fields {
    fn new(s: String) -> Self {
        Self {
            bytes: s.into_bytes(),
            at: 0,
        }
    }
    fn remaining(&self) -> bool {
        self.at < self.bytes.len()
    }
    fn until(&mut self, sep: &str) -> Result<String> {
        let bytes = &self.bytes[self.at..];
        let end = bytes
            .windows(sep.len())
            .position(|w| w == sep.as_bytes())
            .context("Truncated sharing source list")?;
        let s = std::str::from_utf8(&bytes[..end])?.into();
        self.at += end + sep.len();
        Ok(s)
    }
    fn name(&mut self) -> Result<String> {
        let len = self.until(":")?.parse::<usize>()?;
        let end = self
            .at
            .checked_add(len)
            .filter(|&n| n <= self.bytes.len())
            .context("Invalid source name length")?;
        let s = std::str::from_utf8(&self.bytes[self.at..end])?.into();
        self.at = end;
        Ok(s)
    }
    fn consume(&mut self, sep: &str) -> Result<()> {
        if !self.bytes[self.at..].starts_with(sep.as_bytes()) {
            bail!("Invalid source separator");
        }
        self.at += sep.len();
        Ok(())
    }
}
fn sharing_sources() -> Result<Value> {
    let mut data = sharing_sources_from(&env::vars().collect())?;
    workspace_previews(&mut data);
    Ok(data)
}
fn sharing_sources_from(environment: &HashMap<String, String>) -> Result<Value> {
    let get = |key| environment.get(key).cloned().unwrap_or_default();
    let (mut outputs, mut windows, mut workspaces) = (vec![], vec![], vec![]);
    let mut fields = Fields::new(get("XDPH_OUTPUT_SHARING_LIST"));
    while fields.remaining() {
        let name = fields.name()?;
        fields.consume(":")?;
        let x = fields.until(":")?.parse::<i64>()?;
        let y = fields.until(":")?.parse::<i64>()?;
        let w = fields.until(":")?.parse::<i64>()?;
        let h = fields.until(";")?.parse::<i64>()?;
        if w > 0 && h > 0 && !name.contains(['\r', '\n']) {
            outputs.push(json!({"id":format!("screen:{name}"),"name":name,"subtitle":format!("{w} × {h}"),"output":name,"x":x,"y":y,"width":w,"height":h,"kind":"screen"}));
        }
    }
    let mut fields = Fields::new(get("XDPH_WINDOW_SHARING_LIST"));
    while fields.remaining() {
        let id = fields.until("[HC>]")?;
        let app = fields.until("[HT>]")?;
        let title = fields.until("[HE>]")?;
        let address = fields.until("[HA>]")?;
        if id.parse::<u32>().is_ok_and(|id| id > 0) {
            windows.push(json!({"id":format!("window:{id}"),"name":if title.is_empty(){&app}else{&title},"subtitle":app,"appId":app,"address":address,"kind":"window"}));
        }
    }
    let v3 = environment.get("XDPH_WORKSPACE_SHARING_LIST_V3").cloned();
    let mut fields = Fields::new(
        v3.clone()
            .unwrap_or_else(|| get("XDPH_WORKSPACE_SHARING_LIST_V2")),
    );
    while fields.remaining() {
        let (id, name, monitors) = if v3.is_some() {
            let id = fields.until("[HN>]")?;
            let name = fields.name()?;
            fields.consume("[HM>]")?;
            let count = fields.until(":")?.parse::<usize>()?;
            if count > 128 {
                bail!("Invalid output count");
            }
            let monitors = (0..count)
                .map(|_| fields.name())
                .collect::<Result<Vec<_>>>()?;
            fields.consume("[HE>]")?;
            (id, name, monitors)
        } else {
            let name = fields.name()?;
            fields.consume(":")?;
            (fields.until(";")?, name, vec![])
        };
        if id.parse::<u64>().is_ok_and(|id| id > 0) {
            workspaces.push(json!({"id":format!("workspace-id:{id}"),"name":format!("Workspace {name}"),"workspaceName":name,"outputs":monitors,"subtitle":if monitors.is_empty(){"All windows in this workspace".into()}else{monitors.join(", ")},"kind":"workspace"}));
        }
    }
    let data = json!({"kind":"share","title":"Choose what to share","app":{"name":"Screen sharing"},"outputs":outputs,"windows":windows,"workspaces":workspaces});
    Ok(data)
}
fn workspace_previews(data: &mut Value) {
    if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return;
    }
    let (Ok(clients), Ok(monitors)) = (
        json(&["hyprctl", "-j", "clients"]),
        json(&["hyprctl", "-j", "monitors"]),
    ) else {
        return;
    };
    for ws in data["workspaces"].as_array_mut().unwrap() {
        let clients: Vec<_> = rows(&clients)
            .iter()
            .filter(|c| {
                c["mapped"] != false
                    && c["hidden"] != true
                    && c["workspace"]["name"] == ws["workspaceName"]
            })
            .collect();
        let mut displays: Vec<_> = rows(&monitors)
            .iter()
            .filter(|m| rows(&ws["outputs"]).contains(&m["name"]))
            .collect();
        if displays.is_empty() {
            displays = rows(&monitors)
                .iter()
                .filter(|m| clients.iter().any(|c| c["monitor"] == m["id"]))
                .collect();
        }
        ws["tiles"] = json!([]);
        if displays.is_empty() {
            continue;
        }
        let bounds: Vec<_> = displays
            .iter()
            .map(|m| {
                let scale = m["scale"].as_f64().unwrap_or(1.).max(0.01);
                let (mut w, mut h) = (n(m, "width") / scale, n(m, "height") / scale);
                if m["transform"].as_u64().unwrap_or(0) % 2 == 1 {
                    std::mem::swap(&mut w, &mut h);
                }
                (n(m, "x"), n(m, "y"), n(m, "x") + w, n(m, "y") + h)
            })
            .collect();
        let left = bounds.iter().map(|b| b.0).fold(f64::INFINITY, f64::min);
        let top = bounds.iter().map(|b| b.1).fold(f64::INFINITY, f64::min);
        let w = bounds.iter().map(|b| b.2).fold(f64::NEG_INFINITY, f64::max) - left;
        let h = bounds.iter().map(|b| b.3).fold(f64::NEG_INFINITY, f64::max) - top;
        if w <= 0. || h <= 0. {
            continue;
        }
        ws["aspect"] = json!(w / h);
        for c in clients {
            let x = c["at"][0].as_f64().unwrap_or(left);
            let y = c["at"][1].as_f64().unwrap_or(top);
            let x1 = ((x - left) / w).max(0.);
            let y1 = ((y - top) / h).max(0.);
            let x2 = ((x + n(&json!({"w":c["size"][0]}), "w") - left) / w).min(1.);
            let y2 = ((y + n(&json!({"h":c["size"][1]}), "h") - top) / h).min(1.);
            if x2 > x1 && y2 > y1 {
                ws["tiles"].as_array_mut().unwrap().push(json!({"x":x1,"y":y1,"width":x2-x1,"height":y2-y1,"kind":"window","appId":c["class"],"name":c["title"]}));
            }
        }
    }
}
fn share_result(data: &Value, result: &Value) -> Result<String> {
    if result["response"] != 0 {
        return Ok(String::new());
    }
    let id = result["choice"]
        .as_str()
        .context("Missing sharing choice")?;
    let source = ["outputs", "windows", "workspaces"]
        .iter()
        .flat_map(|k| rows(&data[*k]))
        .find(|s| s["id"] == id)
        .context("Unrecognized sharing source")?;
    let mut id = id.to_string();
    if !result["region"].is_null() {
        let r = rows(&result["region"]);
        if source["kind"] != "screen" || r.len() != 4 || r.iter().any(|n| n.as_i64().is_none()) {
            bail!("Invalid sharing region");
        }
        let (x, y, w, h) = (
            r[0].as_i64().unwrap(),
            r[1].as_i64().unwrap(),
            r[2].as_i64().unwrap(),
            r[3].as_i64().unwrap(),
        );
        if x < 0
            || y < 0
            || w < 1
            || h < 1
            || x.checked_add(w)
                .is_none_or(|v| v > source["width"].as_i64().unwrap_or(0))
            || y.checked_add(h)
                .is_none_or(|v| v > source["height"].as_i64().unwrap_or(0))
        {
            bail!("Sharing region outside monitor");
        }
        let output = s(source, "output");
        if output.contains('@') {
            bail!("Unsupported monitor name");
        }
        id = format!("region:{output}@{x},{y},{w},{h}");
    }
    Ok(format!(
        "[SELECTION]{}/{id}",
        if result["remember"] == true { "r" } else { "" }
    ))
}
pub fn main(args: &[String]) -> Result<()> {
    match arg(args, 0)? {
        "backend" => backend(args.iter().any(|s| s == "--test")),
        "respond" => {
            let directory = std::path::Path::new(arg(args, 1)?);
            let data: Value = serde_json::from_str(arg(args, 2)?)?;
            if !matches!(data["response"].as_u64(), Some(0..=2)) {
                bail!("Invalid response");
            }
            atomic_json(&directory.join("response.json"), &data)
        }
        "preview" => {
            let data = read_json(std::path::Path::new(arg(args, 1)?))?;
            let mut dialog = Dialog::open(&data)?;
            let result = dialog.wait()?;
            emit(&result)
        }
        "share" => {
            let mut data = sharing_sources()?;
            data["remember"] = json!(args.iter().any(|a| a == "--allow-token"));
            let mut dialog = Dialog::open(&data)?;
            let result = dialog.wait()?;
            let selected = share_result(&data, &result)?;
            if !selected.is_empty() {
                println!("{selected}");
            }
            Ok(())
        }
        x => bail!("Unknown portal command: {x}"),
    }
}
fn email_command(args: &[String]) -> Result<Vec<std::ffi::OsString>> {
    let (mut uris, mut files) = (vec![], vec![]);
    for arg in args {
        if !arg
            .get(..7)
            .is_some_and(|s| s.eq_ignore_ascii_case("mailto:"))
        {
            bail!("Expected an email link");
        }
        let (address, query) = arg.split_once('?').unwrap_or((arg, ""));
        let mut fields = vec![];
        for field in query.split('&').filter(|f| !f.is_empty()) {
            let (key, value) = field.split_once('=').unwrap_or((field, ""));
            let key = percent_encoding::percent_decode_str(key).decode_utf8()?;
            if !["attach", "attachment"].contains(&key.to_lowercase().as_str()) {
                fields.push(field);
                continue;
            }

            let decoded = if std::path::Path::new(value).is_absolute()
                && std::path::Path::new(value).is_file()
            {
                value.to_string()
            } else {
                percent_encoding::percent_decode_str(value)
                    .decode_utf8()?
                    .into_owned()
            };
            let path = if decoded.starts_with("file:") {
                url::Url::parse(&decoded)?
                    .to_file_path()
                    .map_err(|_| anyhow::anyhow!("Email attachments must be local files"))?
            } else {
                std::path::PathBuf::from(&decoded)
            };
            if !path.is_absolute() || !path.is_file() {
                bail!("Attachment is unavailable: {}", path.display());
            }
            files.push(path.into_os_string());
        }
        uris.push(format!(
            "{address}{}",
            if fields.is_empty() {
                String::new()
            } else {
                format!("?{}", fields.join("&"))
            }
        ));
    }
    let mut command: Vec<std::ffi::OsString> = [
        "/usr/bin/flatpak",
        "run",
        "--file-forwarding",
        "com.chipichapa.Brevlada",
    ]
    .iter()
    .map(std::ffi::OsString::from)
    .collect();
    if !uris.is_empty() {
        command.push("@@u".into());
        command.extend(uris.into_iter().map(Into::into));
        command.push("@@".into());
    }
    if !files.is_empty() {
        command.push("@@".into());
        command.extend(files);
        command.push("@@".into());
    }
    Ok(command)
}
pub fn email(args: &[String]) -> Result<()> {
    use std::os::unix::process::CommandExt;
    let args = email_command(args)?;
    let mut command = std::process::Command::new(&args[0]);
    command.args(&args[1..]);
    Err(command.exec().into())
}

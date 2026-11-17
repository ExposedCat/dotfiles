//! System agents; secrets only cross the private pill socket and Secret Service.
use crate::util::{Lock, output, runtime};
use anyhow::{Context, Result, bail};
use gio::prelude::*;
use glib::variant::ToVariant;
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    env, fs,
    io::{Read, Write},
    os::unix::{fs::MetadataExt, net::UnixStream},
    rc::Rc,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

type Dict = HashMap<String, glib::Variant>;
type Settings = HashMap<String, Dict>;
const BT_PATH: &str = "/org/dotfiles/BluetoothAgent";
const NM_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
const BT: &str = "org.bluez";
const NM: &str = "org.freedesktop.NetworkManager";
const BT_XML: &str = r#"<node><interface name="org.bluez.Agent1">
<method name="Release"/><method name="Cancel"/>
<method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
<method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
<method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
<method name="RequestAuthorization"><arg type="o" direction="in"/></method>
<method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>"#;
const NM_XML: &str = r#"<node><interface name="org.freedesktop.NetworkManager.SecretAgent">
<method name="GetSecrets"><arg type="a{sa{sv}}" direction="in"/><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="in"/><arg type="a{sa{sv}}" direction="out"/></method>
<method name="CancelGetSecrets"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="SaveSecrets"><arg type="a{sa{sv}}" direction="in"/><arg type="o" direction="in"/></method>
<method name="DeleteSecrets"><arg type="a{sa{sv}}" direction="in"/><arg type="o" direction="in"/></method>
</interface></node>"#;

struct Pending {
    invocation: Option<gio::DBusMethodInvocation>,
    group: String,
    key: String,
    cancel: Arc<AtomicBool>,
    view: Arc<Mutex<Value>>,
}
type Jobs = Rc<RefCell<HashMap<String, Pending>>>;
type Completion = (String, std::result::Result<Option<glib::Variant>, String>);

fn owner(bus: &gio::DBusConnection, name: &str) -> Option<String> {
    bus.call_sync(
        Some("org.freedesktop.DBus"),
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "GetNameOwner",
        Some(&(name,).to_variant()),
        None,
        gio::DBusCallFlags::NONE,
        1500,
        gio::Cancellable::NONE,
    )
    .ok()?
    .child_value(0)
    .get()
}

fn cancel(jobs: &Jobs, group: &str, key: Option<&str>) {
    for pending in jobs.borrow().values() {
        if pending.group == group && key.is_none_or(|key| key == pending.key) {
            pending.cancel.store(true, Ordering::Relaxed);
        }
    }
}

fn spawn<F>(
    jobs: &Jobs,
    tx: &mpsc::Sender<Completion>,
    invocation: Option<gio::DBusMethodInvocation>,
    group: &str,
    key: &str,
    mut data: Value,
    work: F,
) where
    F: FnOnce(Arc<Mutex<Value>>, Arc<AtomicBool>) -> Result<Option<glib::Variant>> + Send + 'static,
{
    if jobs.borrow().len() >= 16 {
        if let Some(call) = invocation {
            call.return_dbus_error(
                "org.freedesktop.DBus.Error.LimitsExceeded",
                "Too many authentication requests",
            );
        }
        return;
    }
    let id = glib::uuid_string_random().to_string();
    data["id"] = json!(id);
    let view = Arc::new(Mutex::new(data));
    let stop = Arc::new(AtomicBool::new(false));
    jobs.borrow_mut().insert(
        id.clone(),
        Pending {
            invocation,
            group: group.into(),
            key: key.into(),
            cancel: stop.clone(),
            view: view.clone(),
        },
    );
    let tx = tx.clone();
    thread::spawn(move || {
        let result = work(view, stop).map_err(|e| e.to_string());
        let _ = tx.send((id, result));
    });
}

fn prompt(view: &Arc<Mutex<Value>>, stop: &AtomicBool) -> Result<Value> {
    let path = runtime()?.join("dotfiles-credentials-shell.sock");
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        if stop.load(Ordering::Relaxed) || Instant::now() >= deadline {
            bail!("Cancelled");
        }
        let meta = fs::symlink_metadata(&path).context("Authentication pill is unavailable")?;
        if meta.uid() != unsafe { libc::getuid() }
            || !std::os::unix::fs::FileTypeExt::is_socket(&meta.file_type())
        {
            bail!("Invalid authentication endpoint");
        }
        let mut stream = UnixStream::connect(&path)?;
        let mut credentials: libc::ucred = unsafe { std::mem::zeroed() };
        let mut size = std::mem::size_of_val(&credentials) as libc::socklen_t;
        use std::os::fd::AsRawFd;
        if unsafe {
            libc::getsockopt(
                stream.as_raw_fd(),
                libc::SOL_SOCKET,
                libc::SO_PEERCRED,
                (&mut credentials as *mut libc::ucred).cast(),
                &mut size,
            )
        } != 0
            || credentials.uid != unsafe { libc::getuid() }
        {
            bail!("Authentication endpoint owner mismatch");
        }
        stream.set_write_timeout(Some(Duration::from_secs(2)))?;
        stream.set_read_timeout(Some(Duration::from_millis(150)))?;
        let mut last = view.lock().unwrap().clone();
        writeln!(stream, "{}", json!({"action":"open","data":last}))?;
        let mut bytes = Vec::new();
        let mut retry = false;
        loop {
            if stop.load(Ordering::Relaxed) || Instant::now() >= deadline {
                bail!("Cancelled");
            }
            let current = view.lock().unwrap().clone();
            if current != last {
                writeln!(stream, "{}", json!({"action":"update","data":current}))?;
                last = current;
            }
            let mut chunk = [0; 4096];
            match stream.read(&mut chunk) {
                Ok(0) => bail!("Authentication pill disconnected"),
                Ok(n) => bytes.extend_from_slice(&chunk[..n]),
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    continue;
                }
                Err(e) => return Err(e.into()),
            }
            if bytes.len() > 65536 {
                bail!("Authentication response is too large");
            }
            while let Some(at) = bytes.iter().position(|&b| b == b'\n') {
                let reply: Value = serde_json::from_slice(&bytes[..at])?;
                bytes.drain(..=at);
                if reply["accepted"] == false {
                    retry = true;
                    break;
                }
                if reply.get("response").is_some() {
                    if reply["id"] != last["id"] || reply["response"] != 0 {
                        bail!("Cancelled");
                    }
                    return Ok(reply);
                }
            }
            if retry {
                break;
            }
        }
        thread::sleep(Duration::from_millis(200));
    }
}

fn bt_call(
    bus: &gio::DBusConnection,
    jobs: &Jobs,
    tx: &mpsc::Sender<Completion>,
    method: &str,
    params: glib::Variant,
    call: gio::DBusMethodInvocation,
) -> Result<()> {
    if matches!(method, "Cancel" | "Release") {
        cancel(jobs, BT, None);
        call.return_value(None);
        return Ok(());
    }
    let device = params
        .child_value(0)
        .str()
        .context("Invalid device")?
        .to_owned();
    let label = bus
        .call_sync(
            Some(BT),
            &device,
            "org.freedesktop.DBus.Properties",
            "Get",
            Some(&("org.bluez.Device1", "Alias").to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            1500,
            gio::Cancellable::NONE,
        )
        .ok()
        .and_then(|v| v.child_value(0).as_variant())
        .and_then(|v| v.get::<String>())
        .unwrap_or_else(|| "Bluetooth device".into());
    let display = method.starts_with("Display");
    let mut data = json!({"kind":"bluetooth","title":"Pair Bluetooth device","subtitle":label,"body":"Confirm this pairing request.","confirmLabel":"Pair","fields":[]});
    match method {
        "RequestConfirmation" | "DisplayPasskey" => {
            data["code"] = json!(format!(
                "{:06}",
                params
                    .child_value(1)
                    .get::<u32>()
                    .context("Invalid passkey")?
            ));
            data["body"] = json!(if display {
                "Type this code on the other device, then press Enter."
            } else {
                "Make sure this code matches the one shown on your device."
            });
            if display {
                data["entered"] = json!(params.child_value(2).get::<u16>().unwrap_or(0));
            }
        }
        "DisplayPinCode" => {
            data["code"] = json!(
                params
                    .child_value(1)
                    .get::<String>()
                    .context("Invalid PIN")?
            );
            data["body"] = json!("Type this code on the other device, then press Enter.");
        }
        "RequestPinCode" | "RequestPasskey" => {
            let numeric = method == "RequestPasskey";
            data["body"] = json!("Enter the pairing code shown on your device.");
            data["fields"] = json!([{"key":"pin","label":if numeric {"Passkey"} else {"PIN code"},"secret":false,"minLength":1,"maxLength":if numeric {6} else {16},"validation":if numeric {"digits"} else {"text"}}]);
        }
        "RequestAuthorization" => {}
        "AuthorizeService" => {
            data["title"] = json!("Allow Bluetooth connection");
            data["body"] = json!("Allow this device to use the requested Bluetooth service?");
            data["confirmLabel"] = json!("Allow");
        }
        _ => bail!("Unknown Bluetooth agent method"),
    }
    if display {
        data["displayOnly"] = json!(true);
        for existing in jobs.borrow().values() {
            if existing.group == BT && existing.key == device && existing.invocation.is_none() {
                let mut view = existing.view.lock().unwrap();
                data["id"] = view["id"].clone();
                *view = data;
                call.return_value(None);
                return Ok(());
            }
        }
    }
    let invocation = if display {
        call.return_value(None);
        None
    } else {
        Some(call)
    };
    let method = method.to_owned();
    spawn(
        jobs,
        tx,
        invocation,
        BT,
        &device,
        data,
        move |view, stop| {
            let reply = prompt(&view, &stop)?;
            let pin = reply["values"]["pin"].as_str().unwrap_or_default();
            match method.as_str() {
                "RequestPinCode" if !pin.is_empty() && pin.chars().count() <= 16 => {
                    Ok(Some((pin,).to_variant()))
                }
                "RequestPasskey"
                    if !pin.is_empty()
                        && pin.bytes().all(|b| b.is_ascii_digit())
                        && pin.len() <= 6 =>
                {
                    Ok(Some((pin.parse::<u32>()?,).to_variant()))
                }
                "RequestPinCode" | "RequestPasskey" => bail!("Invalid pairing code"),
                _ => Ok(None),
            }
        },
    );
    Ok(())
}

fn text(settings: &Settings, section: &str, key: &str) -> String {
    settings
        .get(section)
        .and_then(|d| d.get(key))
        .and_then(|v| v.str())
        .unwrap_or_default()
        .to_owned()
}
fn secret_keys(settings: &Settings, section: &str, hints: &[String]) -> Vec<String> {
    if !hints.is_empty() {
        return hints
            .iter()
            .filter(|h| {
                !h.starts_with("x-vpn-")
                    && h.len() <= 128
                    && h.bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
            })
            .cloned()
            .collect();
    }
    match section {
        "802-11-wireless-security" => vec![if text(settings, section, "key-mgmt") == "none" {
            let index = settings
                .get(section)
                .and_then(|d| d.get("wep-tx-keyidx"))
                .and_then(|v| v.get::<u32>())
                .unwrap_or(0)
                .min(3);
            format!("wep-key{index}")
        } else {
            "psk".into()
        }],
        "802-1x" => vec![
            if text(settings, section, "private-key").is_empty() {
                "password"
            } else {
                "private-key-password"
            }
            .into(),
        ],
        "pppoe" | "gsm" | "cdma" => vec!["password".into()],
        "vpn" => vec!["password".into()],
        _ => vec![],
    }
}
fn keyring(
    uuid: &str,
    section: &str,
    key: &str,
    value: Option<&str>,
    delete: bool,
) -> Result<String> {
    if uuid.is_empty() {
        bail!("Connection UUID is missing");
    }
    let mut c = std::process::Command::new("/usr/bin/secret-tool");
    c.arg(if delete {
        "clear"
    } else if value.is_some() {
        "store"
    } else {
        "lookup"
    });
    if value.is_some() && !delete {
        c.arg("--label=Network connection credentials");
    }
    c.args(["connection-uuid", uuid, "setting-name", section]);
    if !key.is_empty() {
        c.args(["setting-key", key]);
    }
    output(
        c,
        value.map(|v| v.as_bytes().to_vec()),
        Duration::from_secs(5),
    )
}
fn owned_secret(settings: &Settings, section: &str, key: &str) -> bool {
    let flags = if section == "vpn" {
        settings
            .get(section)
            .and_then(|d| d.get("data"))
            .and_then(|v| v.get::<HashMap<String, String>>())
            .and_then(|d| {
                d.get(&format!("{key}-flags"))
                    .and_then(|v| v.parse::<u32>().ok())
            })
            .unwrap_or(0)
    } else {
        settings
            .get(section)
            .and_then(|d| d.get(&format!("{key}-flags")))
            .and_then(|v| v.get::<u32>())
            .unwrap_or(0)
    };
    flags & 1 != 0 && flags & 2 == 0
}
fn nm_result(section: &str, values: HashMap<String, String>) -> glib::Variant {
    let dict: Dict = if section == "vpn" {
        HashMap::from([("secrets".into(), values.to_variant())])
    } else {
        values
            .into_iter()
            .map(|(k, v)| (k, v.to_variant()))
            .collect()
    };
    (HashMap::from([(section.to_owned(), dict)]),).to_variant()
}
type VpnPlan = (Vec<Value>, HashMap<String, String>, String, String);
fn vpn_plan(settings: &Settings, hints: &[String], flags: u32) -> Result<VpnPlan> {
    let service = text(settings, "vpn", "service-type");
    for directory in [
        "/usr/lib/NetworkManager/VPN",
        "/usr/lib64/NetworkManager/VPN",
    ] {
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let config = glib::KeyFile::new();
            if config
                .load_from_file(entry.path(), glib::KeyFileFlags::NONE)
                .is_err()
                || config.string("VPN Connection", "service").ok().as_deref() != Some(&service)
            {
                continue;
            }
            if !config
                .boolean("GNOME", "supports-external-ui-mode")
                .unwrap_or(false)
            {
                continue;
            }
            let binary = config.string("GNOME", "auth-dialog")?;
            if !binary.starts_with("/usr/") || fs::metadata(binary.as_str())?.uid() != 0 {
                bail!("Invalid VPN authentication helper");
            }
            let mut command = std::process::Command::new(binary.as_str());
            command.args([
                "--external-ui-mode",
                "-u",
                &text(settings, "connection", "uuid"),
                "-n",
                &text(settings, "connection", "id"),
                "-s",
                &service,
            ]);
            if flags & 1 != 0 {
                command.arg("-i");
            }
            if flags & 2 != 0 {
                command.arg("-r");
            }
            if config.boolean("GNOME", "supports-hints").unwrap_or(false)
                || config
                    .boolean("VPN Connection", "supports-hints")
                    .unwrap_or(false)
            {
                for hint in hints {
                    command.args(["-t", hint]);
                }
            }
            let mut input = String::new();
            for (map, prefix) in [("data", "DATA"), ("secrets", "SECRET")] {
                for (key, value) in settings
                    .get("vpn")
                    .and_then(|d| d.get(map))
                    .and_then(|v| v.get::<HashMap<String, String>>())
                    .unwrap_or_default()
                {
                    if key.contains(['\n', '\r']) || value.contains(['\n', '\r']) {
                        bail!("Invalid VPN helper input");
                    }
                    input.push_str(&format!("{prefix}_KEY={key}\n{prefix}_VAL={value}\n\n"));
                }
            }
            input.push_str("DONE\n\n");
            let output = output(command, Some(input.into_bytes()), Duration::from_secs(10))?;
            let config = glib::KeyFile::new();
            config.load_from_data(&output, glib::KeyFileFlags::NONE)?;
            if config.integer("VPN Plugin UI", "Version")? != 2 {
                bail!("Unsupported VPN UI protocol");
            }
            let mut fields = vec![];
            let mut fixed = HashMap::new();
            for group in config
                .groups()
                .iter()
                .filter(|g| g.as_str() != "VPN Plugin UI")
            {
                let value = config
                    .string(group, "Value")
                    .unwrap_or_default()
                    .to_string();
                if config.boolean(group, "ShouldAsk").unwrap_or(false) {
                    fields.push(json!({"key":group.as_str(),"label":config.string(group,"Label").map(|v|v.to_string()).unwrap_or_else(|_|group.to_string()),"secret":config.boolean(group,"IsSecret").unwrap_or(true),"minLength":1,"maxLength":4096,"value":""}));
                } else if !value.is_empty() {
                    fixed.insert(group.to_string(), value);
                }
            }
            return Ok((
                fields,
                fixed,
                config.string("VPN Plugin UI", "Title")?.to_string(),
                config.string("VPN Plugin UI", "Description")?.to_string(),
            ));
        }
    }
    let keys = secret_keys(settings, "vpn", hints);
    if hints.is_empty() || keys.is_empty() {
        bail!("NoSecrets: VPN provider requires its own authentication application");
    }
    Ok((
        keys.iter()
            .map(|key| json!({"key":key,"label":match key.as_str() {"password"=>"Password", "otp"=>"One-time code", _=>key},"secret":true,"minLength":1,"maxLength":4096}))
            .collect(),
        HashMap::new(),
        "Connect to VPN".into(),
        String::new(),
    ))
}

fn nm_work(
    settings: Settings,
    section: String,
    hints: Vec<String>,
    flags: u32,
    view: Arc<Mutex<Value>>,
    stop: Arc<AtomicBool>,
) -> Result<Option<glib::Variant>> {
    let uuid = text(&settings, "connection", "uuid");
    let mut keys = secret_keys(&settings, &section, &hints);
    if keys.is_empty() {
        bail!("NoSecrets: Unsupported network setting");
    }
    let mut values = HashMap::new();
    let mut fields = Vec::new();
    if section == "vpn" {
        let (vpn_fields, fixed, title, body) = vpn_plan(&settings, &hints, flags)?;
        keys = vpn_fields
            .iter()
            .filter_map(|f| f["key"].as_str().map(str::to_owned))
            .collect();
        fields = vpn_fields;
        values = fixed;
        let mut data = view.lock().unwrap();
        data["title"] = json!(title);
        data["body"] = json!(body);
    }
    for key in &keys {
        if flags & 2 == 0 {
            let supplied = if section == "vpn" {
                settings
                    .get("vpn")
                    .and_then(|d| d.get("secrets"))
                    .and_then(|v| v.get::<HashMap<String, String>>())
                    .and_then(|d| d.get(key).cloned())
                    .unwrap_or_default()
            } else {
                text(&settings, &section, key)
            };
            let cached = if supplied.is_empty() {
                keyring(&uuid, &section, key, None, false)
                    .unwrap_or_default()
                    .trim_end_matches('\n')
                    .to_owned()
            } else {
                supplied
            };
            if !cached.is_empty() {
                values.insert(key.clone(), cached);
            }
        }
        if section != "vpn" {
            fields.push(json!({"key":key,"label":match key.as_str() {"psk"=>"Password", "pin"=>"SIM PIN", "private-key-password"=>"Private key password", "password"=>"Password", _=>key},"secret":true,"minLength":if key == "psk" && text(&settings,&section,"key-mgmt") != "sae" {8} else {1},"maxLength":if key == "psk" {64} else {4096}}));
        }
    }
    if keys.iter().all(|k| values.contains_key(k)) {
        return Ok(Some(nm_result(&section, values)));
    }
    if flags & 1 == 0 {
        bail!("NoSecrets: No saved credentials; interaction is disabled");
    }
    if matches!(section.as_str(), "802-1x" | "pppoe") {
        let key = if section == "pppoe" {
            "username"
        } else {
            "identity"
        };
        fields.insert(0, json!({"key":key,"label":"Username","secret":false,"value":text(&settings,&section,key),"minLength":1,"maxLength":256}));
    }
    {
        let mut data = view.lock().unwrap();
        data["fields"] = json!(fields);
        data["rememberAllowed"] = json!(keys.iter().any(|k| owned_secret(&settings, &section, k)));
    }
    let response = prompt(&view, &stop)?;
    if section != "vpn" {
        values.clear();
    }
    for field in &fields {
        let key = field["key"].as_str().unwrap();
        let value = response["values"][key]
            .as_str()
            .context("Missing credential")?;
        if value.is_empty() || value.len() > 4096 {
            bail!("Invalid credential");
        }
        if key == "psk"
            && text(&settings, &section, "key-mgmt") != "sae"
            && !(value.len() >= 8 && value.len() <= 63
                || value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit()))
        {
            bail!("Invalid Wi-Fi password length");
        }
        if response["remember"] == true && owned_secret(&settings, &section, key) {
            keyring(&uuid, &section, key, Some(value), false)
                .context("Could not save credentials to the keyring")?;
        }
        values.insert(key.to_owned(), value.to_owned());
    }
    Ok(Some(nm_result(&section, values)))
}

fn nm_call(
    jobs: &Jobs,
    tx: &mpsc::Sender<Completion>,
    method: &str,
    params: glib::Variant,
    call: gio::DBusMethodInvocation,
) -> Result<()> {
    if method == "CancelGetSecrets" {
        let key = format!(
            "{}|{}",
            params.child_value(0).str().unwrap_or_default(),
            params.child_value(1).str().unwrap_or_default()
        );
        cancel(jobs, NM, Some(&key));
        call.return_value(None);
        return Ok(());
    }
    let settings = params
        .child_value(0)
        .get::<Settings>()
        .context("Invalid connection settings")?;
    let path = params
        .child_value(1)
        .str()
        .context("Invalid connection path")?
        .to_owned();
    if matches!(method, "SaveSecrets" | "DeleteSecrets") {
        let delete = method == "DeleteSecrets";
        spawn(
            jobs,
            tx,
            Some(call),
            NM,
            &path,
            json!({}),
            move |_, stop| {
                let uuid = text(&settings, "connection", "uuid");
                for section in settings.keys().filter(|s| s.as_str() != "connection") {
                    if stop.load(Ordering::Relaxed) {
                        bail!("Cancelled");
                    }
                    if delete {
                        let _ = keyring(&uuid, section, "", None, true);
                        continue;
                    }
                    let keys = if section == "vpn" {
                        settings
                            .get(section)
                            .and_then(|d| d.get("secrets"))
                            .and_then(|v| v.get::<HashMap<String, String>>())
                            .unwrap_or_default()
                            .keys()
                            .cloned()
                            .collect()
                    } else {
                        secret_keys(&settings, section, &[])
                    };
                    for key in keys {
                        if !owned_secret(&settings, section, &key) {
                            continue;
                        }
                        let value = if section == "vpn" {
                            settings
                                .get(section)
                                .and_then(|d| d.get("secrets"))
                                .and_then(|v| v.get::<HashMap<String, String>>())
                                .and_then(|d| d.get(&key).cloned())
                                .unwrap_or_default()
                        } else {
                            text(&settings, section, &key)
                        };
                        if !value.is_empty() {
                            keyring(&uuid, section, &key, Some(&value), false)?;
                        }
                    }
                }
                Ok(None)
            },
        );
        return Ok(());
    }
    if method != "GetSecrets" {
        bail!("Unknown network agent method");
    }
    let section = params
        .child_value(2)
        .get::<String>()
        .context("Invalid setting name")?;
    let hints = params
        .child_value(3)
        .get::<Vec<String>>()
        .unwrap_or_default();
    let flags = params
        .child_value(4)
        .get::<u32>()
        .context("Invalid request flags")?;
    let key = format!("{path}|{section}");
    cancel(jobs, NM, Some(&key));
    let name = text(&settings, "connection", "id");
    let data = json!({"kind":"network","title":if section == "vpn" {"Connect to VPN"} else {"Connect to network"},"subtitle":name,"networkType":if section == "vpn" {"vpn"} else {"wifi"},"body":"","confirmLabel":"Connect","fields":[]});
    spawn(jobs, tx, Some(call), NM, &key, data, move |view, stop| {
        nm_work(settings, section, hints, flags, view, stop)
    });
    Ok(())
}

fn register(
    bus: &gio::DBusConnection,
    registered: &Rc<RefCell<HashMap<String, bool>>>,
    service: &str,
) {
    if registered.borrow().get(service) == Some(&true) || owner(bus, service).is_none() {
        return;
    }
    registered.borrow_mut().insert(service.into(), true);
    let (path, interface, method, params) = if service == BT {
        (
            "/org/bluez",
            "org.bluez.AgentManager1",
            "RegisterAgent",
            (
                glib::variant::ObjectPath::try_from(BT_PATH).unwrap(),
                "KeyboardDisplay",
            )
                .to_variant(),
        )
    } else {
        (
            "/org/freedesktop/NetworkManager/AgentManager",
            "org.freedesktop.NetworkManager.AgentManager",
            "RegisterWithCapabilities",
            ("org.dotfiles.NetworkAgent", 1u32).to_variant(),
        )
    };
    let bus2 = bus.clone();
    let registered = registered.clone();
    let service = service.to_owned();
    bus.call(
        Some(&service.clone()),
        path,
        interface,
        method,
        Some(&params),
        None,
        gio::DBusCallFlags::NONE,
        3000,
        gio::Cancellable::NONE,
        move |result| {
            if result.is_err() {
                registered.borrow_mut().insert(service.clone(), false);
                eprintln!("Could not register {service} credential agent");
                return;
            }
            eprintln!("Registered {service} credential agent");
            if service == BT {
                bus2.call(
                    Some(BT),
                    "/org/bluez",
                    "org.bluez.AgentManager1",
                    "RequestDefaultAgent",
                    Some(&(glib::variant::ObjectPath::try_from(BT_PATH).unwrap(),).to_variant()),
                    None,
                    gio::DBusCallFlags::NONE,
                    3000,
                    gio::Cancellable::NONE,
                    |r| {
                        if r.is_err() {
                            eprintln!("Bluetooth default-agent registration was rejected");
                        }
                    },
                );
            }
        },
    );
}

pub fn run(testing: bool) -> Result<()> {
    if testing
        && (env::var_os("ISOLATED_GUI_SESSION").is_none()
            || env::var("DBUS_SYSTEM_BUS_ADDRESS").ok()
                != env::var("DBUS_SESSION_BUS_ADDRESS").ok())
    {
        bail!("Test agents require the isolated desktop's private bus");
    }
    let _lock = Lock::acquire(&runtime()?.join("dotfiles-credentials-agent.lock"), true)?;
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)?;
    let session = if testing {
        None
    } else {
        Some(crate::automount::session_proxy()?)
    };
    let jobs: Jobs = Rc::new(RefCell::new(HashMap::new()));
    let (tx, rx) = mpsc::channel::<Completion>();
    let registered = Rc::new(RefCell::new(HashMap::new()));
    let mut registrations = vec![];
    for (service, path, xml) in [(BT, BT_PATH, BT_XML), (NM, NM_PATH, NM_XML)] {
        let jobs = jobs.clone();
        let tx = tx.clone();
        let session = session.clone();
        let interface = gio::DBusNodeInfo::for_xml(xml)?.interfaces()[0].clone();
        registrations.push(
            bus.register_object(path, &interface)
                .method_call(move |bus, sender, _, _, method, params, call| {
                    if sender != owner(&bus, service).as_deref() {
                        call.return_dbus_error(
                            "org.freedesktop.DBus.Error.AccessDenied",
                            "Only the registered system service may call this agent",
                        );
                        return;
                    }
                    if session.as_ref().is_some_and(|p| {
                        p.cached_property("Active").and_then(|v| v.get::<bool>()) != Some(true)
                            || p.cached_property("LockedHint")
                                .and_then(|v| v.get::<bool>())
                                != Some(false)
                    }) {
                        call.return_dbus_error(
                            "org.freedesktop.DBus.Error.AccessDenied",
                            "Graphical session is inactive or locked",
                        );
                        return;
                    }
                    let result = if service == BT {
                        bt_call(&bus, &jobs, &tx, method, params, call.clone())
                    } else {
                        nm_call(&jobs, &tx, method, params, call.clone())
                    };
                    if result.is_err() {
                        call.return_dbus_error(
                            "org.freedesktop.DBus.Error.InvalidArgs",
                            "Invalid authentication request",
                        );
                    }
                })
                .build()?,
        );
    }
    let observed_jobs = jobs.clone();
    let flags = registered.clone();
    let _owners = bus.subscribe_to_signal(
        Some("org.freedesktop.DBus"),
        Some("org.freedesktop.DBus"),
        Some("NameOwnerChanged"),
        Some("/org/freedesktop/DBus"),
        None,
        gio::DBusSignalFlags::NONE,
        move |s| {
            if let Some((name, old, _)) = s.parameters.get::<(String, String, String)>()
                && [BT, NM].contains(&name.as_str())
                && !old.is_empty()
            {
                cancel(&observed_jobs, &name, None);
                flags.borrow_mut().remove(&name);
            }
        },
    );
    let display_jobs = jobs.clone();
    let _paired = bus.subscribe_to_signal(
        Some(BT),
        Some("org.freedesktop.DBus.Properties"),
        Some("PropertiesChanged"),
        None,
        Some("org.bluez.Device1"),
        gio::DBusSignalFlags::NONE,
        move |signal| {
            if let Some((_, properties, _)) = signal.parameters.get::<(String, Dict, Vec<String>)>()
                && properties.get("Paired").and_then(|v| v.get::<bool>()) == Some(true)
            {
                for pending in display_jobs.borrow().values() {
                    if pending.group == BT
                        && pending.key == signal.object_path
                        && pending.invocation.is_none()
                    {
                        pending.cancel.store(true, Ordering::Relaxed);
                    }
                }
            }
        },
    );
    if let Some(session) = &session {
        let jobs = jobs.clone();
        session.connect_local("g-properties-changed", false, move |v| {
            let p = v[0].get::<gio::DBusProxy>().unwrap();
            if p.cached_property("Active").and_then(|v| v.get::<bool>()) != Some(true)
                || p.cached_property("LockedHint")
                    .and_then(|v| v.get::<bool>())
                    != Some(false)
            {
                cancel(&jobs, BT, None);
                cancel(&jobs, NM, None);
            }
            None
        });
    }
    let completion_jobs = jobs.clone();
    let completion_bus = bus.clone();
    glib::timeout_add_local(Duration::from_millis(40), move || {
        while let Ok((id, result)) = rx.try_recv() {
            if let Some(p) = completion_jobs.borrow_mut().remove(&id) {
                if let Some(call) = p.invocation {
                    match result {
                        Ok(value) if !p.cancel.load(Ordering::Relaxed) => {
                            call.return_value(value.as_ref())
                        }
                        result => {
                            let no_secrets = result
                                .as_ref()
                                .err()
                                .is_some_and(|s| s.starts_with("NoSecrets:"));
                            call.return_dbus_error(
                                if p.group == BT {
                                    "org.bluez.Error.Canceled"
                                } else if no_secrets {
                                    "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets"
                                } else {
                                    "org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled"
                                },
                                "Authentication request did not complete",
                            );
                        }
                    }
                } else if result.is_err() && !p.cancel.load(Ordering::Relaxed) {
                    completion_bus.call(
                        Some(BT),
                        &p.key,
                        "org.bluez.Device1",
                        "CancelPairing",
                        None,
                        None,
                        gio::DBusCallFlags::NONE,
                        2000,
                        gio::Cancellable::NONE,
                        |_| {},
                    );
                }
            }
        }
        glib::ControlFlow::Continue
    });
    register(&bus, &registered, BT);
    register(&bus, &registered, NM);
    let bus2 = bus.clone();
    let flags = registered.clone();
    glib::timeout_add_local(Duration::from_secs(5), move || {
        register(&bus2, &flags, BT);
        register(&bus2, &flags, NM);
        glib::ControlFlow::Continue
    });
    let main_loop = glib::MainLoop::new(None, false);
    for signal in [libc::SIGTERM, libc::SIGINT] {
        let l = main_loop.clone();
        glib_unix::unix_signal_add_local_once(signal, move || l.quit());
    }
    main_loop.run();
    cancel(&jobs, BT, None);
    cancel(&jobs, NM, None);
    for registration in registrations {
        let _ = bus.unregister_object(registration);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn vpn_reply_uses_the_required_nested_secret_map() {
        let v = nm_result("vpn", HashMap::from([("otp".into(), "fixture".into())]));
        let result = v.child_value(0).get::<Settings>().unwrap();
        assert_eq!(
            result["vpn"]["secrets"]
                .get::<HashMap<String, String>>()
                .unwrap()["otp"],
            "fixture"
        );
        assert_eq!(v.type_().as_str(), "(a{sa{sv}})");
    }
    #[test]
    fn service_messages_are_not_treated_as_secret_field_names() {
        let hints = vec![
            "password".into(),
            "x-vpn-message:Enter password".into(),
            "bad\nkey".into(),
        ];
        assert_eq!(
            secret_keys(&HashMap::new(), "vpn", &hints),
            vec!["password"]
        );
    }
    #[test]
    fn only_agent_owned_non_ephemeral_secrets_are_saved() {
        for (flags, save) in [(0u32, false), (1, true), (2, false), (3, false)] {
            let config = HashMap::from([(
                "802-1x".into(),
                HashMap::from([("password-flags".into(), flags.to_variant())]),
            )]);
            assert_eq!(owned_secret(&config, "802-1x", "password"), save);
        }
    }
    #[test]
    fn agent_interfaces_have_valid_introspection() {
        assert!(gio::DBusNodeInfo::for_xml(BT_XML).is_ok());
        assert!(gio::DBusNodeInfo::for_xml(NM_XML).is_ok());
    }
}

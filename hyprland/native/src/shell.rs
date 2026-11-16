use crate::util::*;
use anyhow::{Context, Result, bail};
use gio::prelude::*;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    fs,
    path::PathBuf,
    time::{Duration, Instant},
};

pub fn main(args: &[String]) -> Result<()> {
    match arg(args, 0)? {
        "session-info" => emit(&session_info()),
        "ethernet" => emit(&ethernet()),
        "stats-watch" => {
            let mut sampler = Sampler::new(PathBuf::from("/"));
            loop {
                let result = sampler
                    .sample()
                    .unwrap_or_else(|e| json!({"error":e.to_string()}));
                emit(&result)?;
                std::thread::sleep(Duration::from_secs(1));
            }
        }
        "appearance-watch" => {
            let settings = gio::Settings::new("org.gnome.desktop.interface");
            settings.connect_changed(Some("color-scheme"), |s, _| {
                let _ = emit(&appearance(s));
            });
            emit(&appearance(&settings))?;
            glib::MainLoop::new(None, false).run();
            Ok(())
        }
        "appearance-set" => set_appearance(arg(args, 1)?),
        "brightness-list" => emit(&brightness_list()?),
        "brightness-set" => emit(&brightness_set(arg(args, 1)?, arg(args, 2)?.parse()?)?),
        "speed-test" => speed_test(),
        "power" => {
            let command: &[&str] = match arg(args, 1)? {
                "lock" => &[
                    "systemd-run",
                    "--user",
                    "--collect",
                    "--quiet",
                    "--unit=dotfiles-hyprland-lock",
                    "--property=PartOf=graphical-session.target",
                    "/usr/bin/hyprlock",
                    "--no-fade-in",
                ],
                "logout" => &["uwsm", "stop"],
                "suspend" => &["systemctl", "suspend"],
                "reboot" => &["systemctl", "reboot"],
                "poweroff" => &["systemctl", "poweroff"],
                _ => bail!("Unknown power action"),
            };
            run(command)?;
            Ok(())
        }
        x => bail!("Unknown shell action: {x}"),
    }
}
fn appearance(settings: &gio::Settings) -> Value {
    json!({"dark":settings.string("color-scheme")=="prefer-dark"})
}
fn set_appearance(mode: &str) -> Result<()> {
    set_appearance_with(mode, &gio::Settings::new("org.gnome.desktop.interface"))
}
fn set_appearance_with(mode: &str, s: &gio::Settings) -> Result<()> {
    if !["light", "dark"].contains(&mode) {
        bail!("Expected light or dark");
    }
    let theme = s.string("gtk-theme");
    let family = match theme.as_str() {
        "Adwaita" | "Adwaita-dark" => Some(("Adwaita", "Adwaita-dark")),
        "adw-gtk3" | "adw-gtk3-dark" => Some(("adw-gtk3", "adw-gtk3-dark")),
        _ => None,
    };
    if !s.is_writable("color-scheme") || (family.is_some() && !s.is_writable("gtk-theme")) {
        bail!("System appearance settings are locked");
    }
    if let Some((light, dark)) = family {
        s.set_string("gtk-theme", if mode == "dark" { dark } else { light })?;
    }
    s.set_string(
        "color-scheme",
        if mode == "dark" {
            "prefer-dark"
        } else {
            "prefer-light"
        },
    )?;
    gio::Settings::sync();
    Ok(())
}
fn session_info() -> Value {
    let devices = json(&["hyprctl", "devices", "-j"]).unwrap_or(Value::Null);
    let keyboard = rows(&devices["keyboards"])
        .iter()
        .find(|k| k["main"] == true);
    json!({"layout":keyboard.and_then(|k|k["active_keymap"].as_str()).unwrap_or("English (US)"), "keyboard":keyboard.map(|k|s(k,"name")).unwrap_or("")})
}
fn ethernet() -> Value {
    let mut c = command(&[
        "/usr/bin/nmcli",
        "-t",
        "--escape",
        "no",
        "-f",
        "DEVICE,TYPE,STATE",
        "device",
        "status",
    ]);
    c.env("LC_ALL", "C");
    let Ok(output) = output(c, None, Duration::from_secs(3)) else {
        return json!({"devices":[],"unavailable":true});
    };
    ethernet_lines(&output)
}
fn ethernet_lines(output: &str) -> Value {
    let devices:Vec<_>=output.lines().filter_map(|line| {let fields:Vec<_>=line.splitn(3,':').collect(); if fields.len()!=3||fields[1]!="ethernet" {return None;}
        let connected=fields[2].starts_with("connected"); let speed=fs::read_to_string(PathBuf::from("/sys/class/net").join(fields[0]).join("speed")).ok().and_then(|s|s.trim().parse::<u64>().ok()).unwrap_or(0);
        let state=if connected {"Connected"}else{match fields[2]{"disconnected"=>"Disconnected","unavailable"=>"Cable unplugged","unmanaged"=>"Unmanaged",other=>other}};
        Some(json!({"name":fields[0],"state":state,"connected":connected,"speed":if connected{speed}else{0}}))}).collect();
    json!({"devices":devices,"unavailable":false})
}
pub struct Sampler {
    root: PathBuf,
    cpu: Option<(u64, u64)>,
    net: Option<(Instant, u64, u64)>,
}
impl Sampler {
    pub fn new(root: PathBuf) -> Self {
        Self {
            root,
            cpu: None,
            net: None,
        }
    }
    fn read(&self, path: &str) -> Result<String> {
        Ok(fs::read_to_string(
            self.root.join(path.trim_start_matches('/')),
        )?)
    }
    pub fn sample(&mut self) -> Result<Value> {
        let now = Instant::now();
        let values: Vec<u64> = self
            .read("proc/stat")?
            .lines()
            .next()
            .context("Empty CPU statistics")?
            .split_whitespace()
            .skip(1)
            .take(8)
            .map(str::parse)
            .collect::<std::result::Result<_, _>>()?;
        if values.len() < 4 {
            bail!("Truncated CPU statistics");
        }
        let total = values.iter().sum();
        let idle = values[3] + values.get(4).copied().unwrap_or(0);
        let cpu = self.cpu.and_then(|(t, i)| {
            let dt = u64::checked_sub(total, t)?;
            if dt == 0 {
                return None;
            }
            let di = idle.saturating_sub(i);
            Some((100. * dt.saturating_sub(di) as f64 / dt as f64).clamp(0., 100.))
        });
        self.cpu = Some((total, idle));
        let memory: HashMap<String, u64> = self
            .read("proc/meminfo")?
            .lines()
            .filter_map(|l| {
                let (k, v) = l.split_once(':')?;
                Some((
                    k.into(),
                    v.split_whitespace().next()?.parse::<u64>().ok()? * 1024,
                ))
            })
            .collect();
        let total = *memory
            .get("MemTotal")
            .filter(|&&n| n > 0)
            .context("Missing memory total")?;
        let used = total.saturating_sub(
            *memory
                .get("MemAvailable")
                .or(memory.get("MemFree"))
                .unwrap_or(&0),
        );
        let (mut rx, mut tx) = (0u64, 0u64);
        for line in self.read("proc/net/dev")?.lines().skip(2) {
            let Some((device, data)) = line.split_once(':') else {
                continue;
            };
            if device.trim() == "lo" {
                continue;
            }
            let data: Vec<_> = data.split_whitespace().collect();
            if data.len() >= 9 {
                rx = rx.saturating_add(data[0].parse()?);
                tx = tx.saturating_add(data[8].parse()?);
            }
        }
        let (down, up) = self
            .net
            .map(|(at, r, t)| {
                let dt = now.duration_since(at).as_secs_f64().max(f64::EPSILON);
                (
                    rx.saturating_sub(r) as f64 / dt,
                    tx.saturating_sub(t) as f64 / dt,
                )
            })
            .unwrap_or((0., 0.));
        self.net = Some((now, rx, tx));
        let disk = if self.root == std::path::Path::new("/") {
            home()
        } else {
            self.root.clone()
        };
        let name = std::ffi::CString::new(disk.as_os_str().as_encoded_bytes())?;
        let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
        if unsafe { libc::statvfs(name.as_ptr(), stat.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error().into());
        }
        let stat = unsafe { stat.assume_init() };
        let disk_total = stat.f_blocks * stat.f_frsize;
        let disk_used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize;
        let mut result = json!({"cpu":cpu,"memoryUsed":used,"memoryTotal":total,"memory":used as f64*100./total as f64,"swapUsed":memory.get("SwapTotal").unwrap_or(&0).saturating_sub(*memory.get("SwapFree").unwrap_or(&0)),"down":down,"up":up,"diskUsed":disk_used,"diskTotal":disk_total,"disk":if disk_total>0{disk_used as f64*100./disk_total as f64}else{0.},"diskPath":disk,"uptime":self.read("proc/uptime")?.split_whitespace().next().unwrap_or("0").parse::<f64>()?,"gpu":null,"gpuTemperature":null,"cpuTemperature":null,"vramUsed":null,"vramTotal":null});
        for sensor in entries(self.root.join("sys/class/hwmon")) {
            for label in entries(sensor) {
                if !label.to_string_lossy().ends_with("_label") {
                    continue;
                }
                let text = fs::read_to_string(&label).unwrap_or_default();
                if ["Tdie", "Tctl", "Package id 0"].contains(&text.trim())
                    && let Some(n) = number(&PathBuf::from(
                        label.to_string_lossy().replace("_label", "_input"),
                    ))
                {
                    result["cpuTemperature"] = json!(n / 1000.);
                    break;
                }
            }
            if !result["cpuTemperature"].is_null() {
                break;
            }
        }
        for card in entries(self.root.join("sys/class/drm")) {
            let name = card.file_name().unwrap().to_string_lossy();
            if !name.starts_with("card") || name.contains('-') {
                continue;
            }
            let device = card.join("device");
            if let Some(busy) = number(&device.join("gpu_busy_percent")) {
                result["gpu"] = json!(busy);
                result["vramUsed"] = json!(number(&device.join("mem_info_vram_used")));
                result["vramTotal"] = json!(number(&device.join("mem_info_vram_total")));
                for sensor in entries(device.join("hwmon")) {
                    if let Some(n) = number(&sensor.join("temp1_input")) {
                        result["gpuTemperature"] = json!(n / 1000.);
                    }
                }
                break;
            }
        }
        if result["gpu"].is_null()
            && self.root == std::path::Path::new("/")
            && exists("nvidia-smi")
            && let Ok(text) = output(
                command(&[
                    "nvidia-smi",
                    "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                    "--format=csv,noheader,nounits",
                ]),
                None,
                Duration::from_secs(1),
            )
        {
            let ns: Vec<f64> = text
                .lines()
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| s.trim().parse().ok())
                .collect();
            if ns.len() == 4 {
                result["gpu"] = json!(ns[0]);
                result["gpuTemperature"] = json!(ns[1]);
                result["vramUsed"] = json!(ns[2] * 1048576.);
                result["vramTotal"] = json!(ns[3] * 1048576.);
            }
        }
        Ok(result)
    }
}
fn entries(path: PathBuf) -> Vec<PathBuf> {
    let mut result: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(|r| r.ok().map(|r| r.path()))
        .collect();
    result.sort();
    result
}
fn number(path: &std::path::Path) -> Option<f64> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}
pub fn monitors() -> Result<Value> {
    json(&["hyprctl", "monitors", "-j"])
}
pub fn ddc_read(serial: &str) -> Result<(u32, u32)> {
    let text = output(
        command(&["ddcutil", "--sn", serial, "--terse", "getvcp", "10"]),
        None,
        Duration::from_secs(5),
    )?;
    for l in text.lines() {
        let p: Vec<_> = l.split_whitespace().collect();
        if p.len() == 5 && p[..3] == ["VCP", "10", "C"] {
            let c = p[3].parse()?;
            let m = p[4].parse()?;
            if m > 0 && c <= m {
                return Ok((c, m));
            }
        }
    }
    bail!("Monitor returned an invalid brightness level")
}
fn brightness_list() -> Result<Value> {
    let ms = monitors()?;
    let devices:Vec<_>=rows(&ms).iter().map(|m|{let mut row=json!({"name":m["name"],"description":m["description"].as_str().filter(|s|!s.is_empty()).unwrap_or(s(m,"name")),"supported":false,"level":0,"error":""});if !s(m,"serial").is_empty()&& let Ok((c,max))=ddc_read(s(m,"serial")){row["supported"]=json!(true);row["level"]=json!(c as f64/max as f64);return row;}row["error"]=json!("Brightness control is unavailable for this monitor.");row}).collect();
    Ok(json!({"devices":devices}))
}
fn brightness_set(name: &str, level: f64) -> Result<Value> {
    if !level.is_finite() || !(0.0..=1.0).contains(&level) {
        bail!("Brightness must be between 0 and 1");
    }
    let ms = monitors()?;
    let m = rows(&ms)
        .iter()
        .find(|m| s(m, "name") == name)
        .context("The selected monitor is no longer available")?;
    let serial = s(m, "serial");
    if serial.is_empty() {
        bail!("This monitor has no DDC serial");
    }
    let _lock = Lock::acquire(&runtime()?.join("dotfiles-monitor-brightness.lock"), false)?;
    let (_, max) = ddc_read(serial)?;
    output(
        command(&[
            "ddcutil",
            "--sn",
            serial,
            "--noverify",
            "setvcp",
            "10",
            &(level * max as f64).round_ties_even().to_string(),
        ]),
        None,
        Duration::from_secs(5),
    )?;
    let (c, max) = ddc_read(serial)?;
    Ok(json!({"name":name,"level":c as f64/max as f64,"current":c,"maximum":max}))
}

fn transfer(
    direction: &str,
    size: u64,
    payload: &std::path::Path,
    epoch: Instant,
) -> Result<(f64, f64, f64)> {
    let nonce = transfer_nonce();
    let mut c = command(&[
        "/usr/bin/curl",
        "--disable",
        "--silent",
        "--show-error",
        "--fail",
        "--connect-timeout",
        "5",
        "--max-time",
        "8",
        "--proto",
        "=https",
        "--header",
        "Cache-Control: no-store",
        "--header",
        "Accept-Encoding: identity",
        "--output",
        "/dev/null",
        "--write-out",
        "%{json}",
    ]);
    if direction == "download" {
        c.arg(format!(
            "https://speed.cloudflare.com/__down?bytes={size}&nonce={nonce}"
        ));
    } else {
        c.args(["--request", "POST", "--upload-file"])
            .arg(payload)
            .args([
                "--header",
                "Content-Type: application/octet-stream",
                "--header",
                "Expect:",
            ])
            .arg(format!("https://speed.cloudflare.com/__up?nonce={nonce}"));
    }
    // Curl bounds the request; retain useful partial downloads when its time budget expires.
    let result = c.output()?;
    let end = epoch.elapsed().as_secs_f64();
    let data: Value = serde_json::from_slice(&result.stdout)?;
    measurement(direction, size, result.status.code(), &data, end)
}
fn transfer_nonce() -> String {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    format!(
        "{:x}-{:x}-{:x}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    )
}
fn measurement(
    direction: &str,
    size: u64,
    exit_code: Option<i32>,
    data: &Value,
    end: f64,
) -> Result<(f64, f64, f64)> {
    let bytes = data[if direction == "download" {
        "size_download"
    } else {
        "size_upload"
    }]
    .as_f64()
    .context("Missing payload byte count")?;
    let total = data["time_total"]
        .as_f64()
        .context("Missing transfer duration")?;
    let ready = data[if direction == "download" {
        "time_starttransfer"
    } else {
        "time_pretransfer"
    }]
    .as_f64()
    .context("Missing transfer start time")?;
    let partial = direction == "download" && exit_code == Some(28) && bytes >= 65536.;
    if data["http_code"] != 200
        || bytes <= 0.
        || total <= ready
        || ready < 0.
        || ![bytes, total, ready].iter().all(|n| n.is_finite())
        || (!(exit_code == Some(0)) && !partial)
        || ((exit_code == Some(0)) && bytes != size as f64)
    {
        bail!("Invalid {direction} measurement");
    }
    Ok((bytes, end - total + ready, end))
}
fn measure_direction(direction: &str, path: &std::path::Path) -> Result<f64> {
    const PROBE: u64 = 256 * 1024;
    const MAX: u64 = 32 * 1024 * 1024;
    let prepare = |size| -> Result<()> {
        if direction == "upload" {
            fs::File::create(path)?.set_len(size)?;
        }
        Ok(())
    };
    let epoch = Instant::now();
    prepare(PROBE)?;
    let (b, s, e) = transfer(direction, PROBE, path, epoch)?;
    let mut size = ((b / (e - s) * 1.5 / 4.) as u64).clamp(PROBE, MAX);
    let mut rate = 0.;
    for _ in 0..3 {
        prepare(size)?;
        let samples = std::thread::scope(|scope| {
            let threads: Vec<_> = (0..4)
                .map(|_| scope.spawn(|| transfer(direction, size, path, epoch)))
                .collect();
            threads
                .into_iter()
                .map(|t| {
                    t.join()
                        .map_err(|_| anyhow::anyhow!("Speed worker panicked"))?
                })
                .collect::<Result<Vec<_>>>()
        })?;
        let bytes: f64 = samples.iter().map(|x| x.0).sum();
        let elapsed = samples
            .iter()
            .map(|x| x.2)
            .fold(f64::NEG_INFINITY, f64::max)
            - samples.iter().map(|x| x.1).fold(f64::INFINITY, f64::min);
        if elapsed <= 0. || !elapsed.is_finite() {
            bail!("No usable transfer measurement");
        }
        rate = bytes * 8. / elapsed / 1_000_000.;
        if elapsed >= 0.9 || size == MAX {
            break;
        }
        size = ((size as f64 * (1.5 / elapsed).max(2.)) as u64).min(MAX);
    }
    Ok(rate)
}
fn speed_test() -> Result<()> {
    let result = (|| -> Result<Value> {
        let tmp = tempfile::tempdir()?;
        let p = tmp.path().join("payload.bin");
        emit(&json!({"phase":"download"}))?;
        let down = measure_direction("download", &p)?;
        emit(&json!({"phase":"upload"}))?;
        let up = measure_direction("upload", &p)?;
        Ok(
            json!({"download":(down*10.).round()/10.,"upload":(up*10.).round()/10.,"measuredAt":chrono::Utc::now().timestamp_millis(),"provider":"Cloudflare"}),
        )
    })();
    match result {
        Ok(result) => {
            if let Err(e) = atomic_json(
                &xdg("XDG_CACHE_HOME", ".cache").join("dotfiles/hyprland/internet-speed.json"),
                &json!({"version":1,"result":result}),
            ) {
                eprintln!("Could not cache speed result: {e}");
            }
            emit(&json!({"result":result}))
        }
        Err(e) => {
            emit(&json!({"error":"Speed test failed. Try again."}))?;
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn write(root: &std::path::Path, path: &str, value: &str) {
        let path = root.join(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, value).unwrap();
    }
    #[test]
    fn appearance_uses_a_private_settings_backend() {
        let schema = gio::SettingsSchemaSource::default()
            .unwrap()
            .lookup("org.gnome.desktop.interface", true)
            .unwrap();
        let backend = gio::memory_settings_backend_new();
        let preferences = gio::Settings::new_full(&schema, Some(&backend), None);
        for (light, dark) in [
            ("adw-gtk3", "adw-gtk3-dark"),
            ("Adwaita", "Adwaita-dark"),
            ("Custom Theme", "Custom Theme"),
        ] {
            preferences.set_string("gtk-theme", light).unwrap();
            set_appearance_with("dark", &preferences).unwrap();
            assert_eq!(preferences.string("gtk-theme"), dark);
            assert_eq!(appearance(&preferences)["dark"], true);
            set_appearance_with("light", &preferences).unwrap();
            assert_eq!(preferences.string("gtk-theme"), light);
        }
    }
    #[test]
    fn ethernet_distinguishes_disconnected_and_external_links() {
        let value = ethernet_lines(
            "eth0:ethernet:disconnected\nwlan0:wifi:connected\neth1:ethernet:connected (externally)",
        );
        assert_eq!(rows(&value["devices"]).len(), 2);
        assert_eq!(value["devices"][0]["speed"], 0);
        assert_eq!(value["devices"][1]["connected"], true);
    }
    #[test]
    fn transfer_timing_checks_http_sizes_and_partial_downloads() {
        let data = json!({"http_code":200,"size_download":1_000_000,"size_upload":1_000_000,"time_total":2,"time_starttransfer":1.99,"time_pretransfer":1});
        let up = measurement("upload", 1_000_000, Some(0), &data, 10.).unwrap();
        assert_eq!(up.2 - up.1, 1.);
        assert!(measurement("download", 1_000_000, Some(22), &data, 10.).is_err());
        let mut partial = data.clone();
        partial["size_download"] = json!(100_000);
        partial["size_upload"] = json!(100_000);
        assert!(measurement("download", 1_000_000, Some(28), &partial, 10.).is_ok());
        assert!(measurement("upload", 1_000_000, Some(28), &partial, 10.).is_err());
        assert!(measurement("download", 1_000_000, Some(0), &partial, 10.).is_err());
        let mut invalid = data.clone();
        invalid["http_code"] = json!(429);
        assert!(measurement("download", 1_000_000, Some(0), &invalid, 10.).is_err());
        invalid = data.clone();
        invalid["time_total"] = json!(1);
        assert!(measurement("upload", 1_000_000, Some(0), &invalid, 10.).is_err());
        invalid = data.clone();
        invalid.as_object_mut().unwrap().remove("time_pretransfer");
        assert!(measurement("upload", 1_000_000, Some(0), &invalid, 10.).is_err());
        let first = transfer_nonce();
        let second = transfer_nonce();
        assert_ne!(first, second);
        assert!(first.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-'));
    }
    #[test]
    fn sampler_handles_counter_resets_and_missing_devices() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        write(root, "proc/stat", "cpu 100 0 100 800 0 0 0 0\n");
        write(
            root,
            "proc/meminfo",
            "MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 100 kB\nSwapFree: 75 kB\n",
        );
        write(root, "proc/uptime", "1234.5 999\n");
        write(
            root,
            "proc/net/dev",
            "header\nheader\nlo: 99999 0 0 0 0 0 0 0 99999\neth0: 1000 0 0 0 0 0 0 0 500\n",
        );
        let mut sampler = Sampler::new(root.into());
        let first = sampler.sample().unwrap();
        assert!(first["cpu"].is_null());
        assert_eq!(first["memory"], 60.);
        assert_eq!(first["swapUsed"], 25 * 1024);
        write(root, "proc/stat", "cpu 150 0 150 900 0 0 0 0\n");
        write(
            root,
            "proc/net/dev",
            "header\nheader\neth0: 0 0 0 0 0 0 0 0 0\n",
        );
        let sample = sampler.sample().unwrap();
        assert_eq!(sample["cpu"], 50.);
        assert_eq!(sample["down"], 0.);
        assert_eq!(sample["up"], 0.);
        assert!(sample["gpu"].is_null());
        write(root, "sys/class/drm/card1/device/gpu_busy_percent", "24");
        write(
            root,
            "sys/class/drm/card1/device/mem_info_vram_used",
            "4096",
        );
        write(
            root,
            "sys/class/drm/card1/device/mem_info_vram_total",
            "16384",
        );
        write(
            root,
            "sys/class/drm/card1/device/hwmon/hwmon3/temp1_input",
            "47000",
        );
        write(root, "sys/class/hwmon/hwmon1/temp2_label", "Tdie");
        write(root, "sys/class/hwmon/hwmon1/temp2_input", "55500");
        let sample = sampler.sample().unwrap();
        assert_eq!(sample["gpu"], 24.);
        assert_eq!(sample["gpuTemperature"], 47.);
        assert_eq!(sample["cpuTemperature"], 55.5);
        assert_eq!(sample["vramUsed"], 4096.);
    }
}

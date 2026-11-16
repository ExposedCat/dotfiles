//! Two bounded latest-request workers keep slow file searches off the local result path.
use crate::{
    calculator::Calculator,
    dates::Dates,
    sources::{self, Characters, Zen, item},
    util::*,
};
use anyhow::{Context, Result, bail};
use glib::variant::ToVariant;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    io::{self, BufRead},
    path::PathBuf,
    process::{Command, Stdio},
    sync::{Arc, Condvar, Mutex},
};
#[derive(Default)]
struct History {
    entries: HashMap<String, Value>,
    path: PathBuf,
}
impl History {
    fn load() -> Self {
        let path = xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland/launcher.json");
        let data = read_json(&path).unwrap_or(Value::Null);
        let entries = if data["version"] == 1 {
            serde_json::from_value(data["entries"].clone()).unwrap_or_default()
        } else {
            HashMap::new()
        };
        Self { path, entries }
    }
    fn save(&self) -> Result<()> {
        atomic_json(&self.path, &json!({"version":1,"entries":self.entries}))
    }
    fn record(&mut self, row: &Value, pin: bool) -> Result<()> {
        let id = s(row, "id").to_string();
        let mut saved = self.entries.get(&id).cloned().unwrap_or(json!({}));
        saved["item"] = row.clone();
        if pin {
            saved["favorite"] = json!(saved["favorite"] != true);
        } else {
            saved["last"] = json!(chrono::Utc::now().timestamp_millis() as f64 / 1000.);
            saved["count"] = json!(saved["count"].as_u64().unwrap_or(0).saturating_add(1));
        }
        self.entries.insert(id, saved);
        let mut ids: Vec<_> = self.entries.keys().cloned().collect();
        ids.sort_by(|a, b| {
            let a = &self.entries[a];
            let b = &self.entries[b];
            (b["favorite"] == true)
                .cmp(&(a["favorite"] == true))
                .then(n(b, "last").total_cmp(&n(a, "last")))
        });
        let keep: HashSet<_> = ids.into_iter().take(100).collect();
        self.entries.retain(|id, _| keep.contains(id));
        self.save()
    }
    fn decorate(&self, rows: Vec<Value>) -> Vec<Value> {
        rows.into_iter()
            .map(|mut r| {
                r["favorite"] = json!(
                    self.entries
                        .get(s(&r, "id"))
                        .is_some_and(|e| e["favorite"] == true)
                );
                r["recent"] = json!(self.entries.contains_key(s(&r, "id")));
                r
            })
            .collect()
    }
    fn search(&self, query: &str) -> Vec<Value> {
        let mut rows: Vec<_> = self
            .entries
            .values()
            .filter(|e| {
                let row = &e["item"];
                (query.is_empty()
                    || sources::score(s(row, "name"), query, s(row, "description")) < 4)
                    && (row["kind"] != "file" || std::path::Path::new(s(row, "path")).exists())
            })
            .collect();
        rows.sort_by(|a, b| {
            (b["favorite"] == true)
                .cmp(&(a["favorite"] == true))
                .then(n(b, "last").total_cmp(&n(a, "last")))
        });
        self.decorate(
            rows.into_iter()
                .take(24)
                .map(|e| e["item"].clone())
                .collect(),
        )
    }
}
struct Quick {
    calculator: Calculator,
    dates: Dates,
    characters: Characters,
    zen: Zen,
}
impl Quick {
    fn new() -> Result<Self> {
        Ok(Self {
            calculator: Calculator::new()?,
            dates: Dates::default(),
            characters: Characters::default(),
            zen: Zen::default(),
        })
    }
    fn search(&mut self, query: &str, history: &History) -> Result<(Vec<Value>, String)> {
        let query: String = query.trim().chars().take(512).collect();
        let query = query.as_str();
        if regex::Regex::new(r"(?i)^(?:u\+|0x)[0-9a-f]{2,6}$")?.is_match(query) {
            return Ok((
                history.decorate(self.characters.search(query, false)?),
                String::new(),
            ));
        }
        if query.is_empty() {
            let mut result = vec![];
            let mut refreshed: HashMap<String, Vec<Value>> = HashMap::new();
            for mut row in history.search("") {
                let text = s(&row, "query").to_string();
                if !text.is_empty()
                    && ["date", "currency", "calculation"].contains(&s(&row, "kind"))
                {
                    if !refreshed.contains_key(&text) {
                        let mut found = self.dates.search(&text).unwrap_or_default();
                        if found.is_empty() {
                            found = self.calculator.search(&text).unwrap_or_default();
                        }
                        refreshed.insert(text.clone(), found);
                    }
                    if let Some(current) = refreshed[&text].iter().find(|r| r["id"] == row["id"]) {
                        row = current.clone();
                        row["query"] = json!(text);
                    } else {
                        continue;
                    }
                }
                result.push(row);
            }
            return Ok((history.decorate(sources::collapse(result)), String::new()));
        }
        let explicit = regex::Regex::new(
            r"(?i)^(characters?|chars?|emoji|symbols?|bookmarks?|bm|web|files?|f)(?:\s+(.*))?$",
        )?
        .captures(query);
        let (prefix, text) = explicit
            .as_ref()
            .map(|c| {
                (
                    c[1].to_lowercase(),
                    c.get(2).map(|m| m.as_str().trim()).unwrap_or(""),
                )
            })
            .unwrap_or((String::new(), query));
        let mut notice = String::new();
        let mut rows = if ["file", "files", "f"].contains(&prefix.as_str())
            || query.starts_with('/')
            || query.starts_with("~/")
            || query.starts_with("file://")
        {
            vec![]
        } else if ["bookmark", "bookmarks", "bm", "web"].contains(&prefix.as_str()) {
            let result = self.zen.search(text, true);
            if !self.zen.available() {
                notice = "No Zen profile found".into();
            }
            match result {
                Ok(r) => r,
                Err(_) => {
                    notice = "Zen bookmarks are temporarily unavailable".into();
                    vec![]
                }
            }
        } else if !prefix.is_empty() {
            self.characters.search(
                if text.is_empty() {
                    if prefix == "emoji" { "smile" } else { "arrow" }
                } else {
                    text
                },
                true,
            )?
        } else {
            let mut results = match self.dates.search(query) {
                Ok(r) => r,
                Err(_) => {
                    notice =
                        "Use dates such as 2026-11-15 or 15 November 2026, and times such as 09:00"
                            .into();
                    vec![]
                }
            };
            if results.is_empty() && notice.is_empty() {
                match self.calculator.search(query) {
                    Ok(r) => results = r,
                    Err(_) => notice = "Calculation timed out".into(),
                }
            }
            if results.is_empty() && notice.is_empty() && query.chars().count() >= 2 {
                results.extend(self.characters.search(query, false).unwrap_or_default());
                results.extend(self.zen.search(query, false).unwrap_or_default());
                let mut saved = history.search(query);
                saved.extend(results);
                results = saved;
            }
            results
        };
        let mut seen = HashSet::new();
        rows.retain(|r| seen.insert(s(r, "id").to_string()));
        for row in &mut rows {
            if row.get("query").is_none() {
                row["query"] = json!(query);
            }
        }
        if explicit.is_none() {
            rows = sources::collapse(rows);
        }
        Ok((history.decorate(rows), notice))
    }
}
fn file_query(query: &str) -> Result<(String, bool)> {
    let query = query.trim();
    if let Some(c) = regex::Regex::new(r"(?i)^(?:files?|f)(?:\s+(.*))?$")?.captures(query) {
        return Ok((c.get(1).map(|m| m.as_str()).unwrap_or("").into(), true));
    }
    if query.starts_with('/') || query.starts_with("~/") || query.starts_with("file://") {
        return Ok((query.into(), true));
    }
    if query.chars().count()<3||regex::Regex::new(r"(?i)^(?:[\d=+(\-]|[\w√]+\s*\(|chars?\s|characters?\s|symbols?\s|emoji\s|bm\s|bookmarks?\s|web\s|time\s|days\s|hours\s|date\s|today\b|tomorrow\b|unix\s|timestamp\s)")?.is_match(query){return Ok((String::new(),false));}
    Ok((query.into(), false))
}
// Children detach from the launcher's lifetime but are reaped by a small wait thread.
pub fn detach(mut c: Command) -> Result<()> {
    use std::os::unix::process::CommandExt;
    c.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    unsafe {
        c.pre_exec(|| {
            if libc::setsid() < 0 {
                Err(std::io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    let mut child = c.spawn()?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
fn activate(row: &Value, action: &str, history: &mut History) -> Result<String> {
    if action == "favorite" {
        history.record(row, true)?;
        return Ok("Favorite updated".into());
    }
    if action == "forget" {
        history.entries.remove(s(row, "id"));
        history.save()?;
        return Ok("Removed from recent items".into());
    }
    if !["open", "copy", "copy-code", "reveal"].contains(&action) {
        bail!("Unknown launcher action");
    }
    let kind = s(row, "kind");
    let copied = action == "copy"
        || action == "copy-code"
        || ["character", "currency", "calculation", "arithmetic", "date"].contains(&kind);
    if copied {
        let mut value = row["value"]
            .as_str()
            .or(row["uri"].as_str())
            .unwrap_or(s(row, "name"))
            .to_string();
        if action == "copy-code" && kind == "character" {
            value = s(row, "value")
                .chars()
                .map(|c| format!("U+{:04X}", c as u32))
                .collect::<Vec<_>>()
                .join(" ");
        }
        if kind == "file" {
            value = s(row, "path").into();
        }
        status(
            command(&["wl-copy", "--", &value]),
            None,
            std::time::Duration::from_secs(2),
        )?;
    } else if kind == "file" {
        let uri = s(row, "uri");
        let url = url::Url::parse(uri)?;
        if url.scheme() != "file" || url.to_file_path().is_err() {
            bail!("Expected a local file");
        }
        if action == "reveal" {
            let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)?;
            bus.call_sync(
                Some("org.freedesktop.FileManager1"),
                "/org/freedesktop/FileManager1",
                "org.freedesktop.FileManager1",
                "ShowItems",
                Some(&(vec![uri], "").to_variant()),
                None,
                gio::DBusCallFlags::NONE,
                2000,
                gio::Cancellable::NONE,
            )?;
        } else {
            detach(command(&["gio", "open", uri]))?;
        }
    } else if ["web", "bookmark"].contains(&kind) {
        Zen::default().open(row)?;
    } else if kind == "app" {
        let mut c = Command::new(std::env::current_exe()?);
        c.args(["desktop", "app-launch", s(row, "appId")]);
        detach(c)?;
    } else {
        bail!("Unknown launcher result");
    }
    history.record(row, false)?;
    Ok(if copied { "Copied" } else { "Opened" }.into())
}
#[derive(Default)]
struct Queue {
    state: Mutex<(bool, Option<Value>)>,
    wake: Condvar,
}
impl Queue {
    fn push(&self, v: Value) {
        self.state.lock().unwrap().1 = Some(v);
        self.wake.notify_one();
    }
    fn next(&self) -> Option<Value> {
        let mut s = self.state.lock().unwrap();
        while !s.0 && s.1.is_none() {
            s = self.wake.wait(s).unwrap();
        }
        if s.0 { None } else { s.1.take() }
    }
    fn close(&self) {
        self.state.lock().unwrap().0 = true;
        self.wake.notify_one();
    }
}
struct State {
    history: History,
    registry: HashMap<String, Value>,
    latest: Value,
}
pub fn main(args: &[String]) -> Result<()> {
    if args.first().is_some_and(|s| s == "--query") {
        let mut quick = Quick::new()?;
        let (results, notice) = quick.search(arg(args, 1)?, &History::load())?;
        return emit(&json!({"results":results,"notice":notice}));
    }
    let quick = Quick::new()?;
    let available = quick.calculator.available();
    let state = Arc::new(Mutex::new(State {
        history: History::load(),
        registry: HashMap::new(),
        latest: Value::Null,
    }));
    let q = Arc::new(Queue::default());
    let f = Arc::new(Queue::default());
    let spawn = |queue: Arc<Queue>, state: Arc<Mutex<State>>, quick: Option<Quick>| {
        std::thread::spawn(move || {
            let files = quick.is_none();
            let mut quick = quick;
            while let Some(request) = queue.next() {
                let id = request["id"].clone();
                if state.lock().unwrap().latest != id {
                    continue;
                }
                let text = s(&request, "query");
                let outcome = if let Some(quick) = &mut quick {
                    quick.calculator.refresh();
                    let history = {
                        let s = state.lock().unwrap();
                        History {
                            entries: s.history.entries.clone(),
                            path: s.history.path.clone(),
                        }
                    };
                    quick.search(text, &history)
                } else {
                    file_query(text).and_then(|(text,explicit)|if text.is_empty(){Ok((vec![],if explicit{"Search indexed files by name or contents, or type a folder path".into()}else{String::new()}))}else{sources::files(&text,if explicit{24}else{8}).map(|r|(r,String::new()))})
                };
                let (rows, notice) = match outcome {
                    Ok(r) => r,
                    Err(e) => {
                        eprintln!("Launcher provider: {e:#}");
                        (
                            vec![],
                            if files {
                                "File search is unavailable"
                            } else {
                                "This provider is unavailable"
                            }
                            .into(),
                        )
                    }
                };
                let mut state = state.lock().unwrap();
                if state.latest != id {
                    continue;
                }
                let rows = state.history.decorate(rows);
                for row in &rows {
                    state.registry.insert(s(row, "id").into(), row.clone());
                }
                if emit(&json!({"id":id,"section":if files{"files"}else{"quick"},"results":rows,"notice":notice})).is_err(){break;}
            }
        })
    };
    let quick_thread = spawn(q.clone(), state.clone(), Some(quick));
    let file_thread = spawn(f.clone(), state.clone(), None);
    emit(&json!({"ready":true,"qalc":available}))?;
    for line in io::stdin().lock().lines() {
        let line = line?;
        if line.len() > 65536 {
            emit(&json!({"action":true,"error":"Request is too large"}))?;
            continue;
        }
        let outcome = (|| -> Result<()> {
            let request: Value = serde_json::from_str(&line)?;
            let op = request["op"].as_str().unwrap_or("query");
            if op == "query" {
                if request["id"].as_u64().is_none() {
                    bail!("Invalid query ID");
                }
                if s(&request, "query").len() > 4096 {
                    bail!("Query is too large");
                }
                {
                    let mut state = state.lock().unwrap();
                    state.latest = request["id"].clone();
                    state.registry.clear();
                }
                q.push(request.clone());
                f.push(request);
            } else if op == "action" {
                let mut state = state.lock().unwrap();
                let row = state
                    .registry
                    .get(s(&request, "resultId"))
                    .cloned()
                    .or_else(|| {
                        if !s(&request, "appId").is_empty() {
                            let mut row = item(
                                "app",
                                s(&request, "appId"),
                                request["name"].as_str().unwrap_or(s(&request, "appId")),
                                "",
                            );
                            row["appId"] = request["appId"].clone();
                            Some(row)
                        } else {
                            None
                        }
                    })
                    .context("Search again before using this result")?;
                let message = activate(&row, s(&request, "action"), &mut state.history)?;
                emit(
                    &json!({"action":true,"token":request["token"],"message":message,"resultId":row["id"],"favorite":state.history.entries.get(s(&row,"id")).is_some_and(|e|e["favorite"]==true)}),
                )?;
            } else {
                bail!("Unknown launcher operation");
            }
            Ok(())
        })();
        if let Err(e) = outcome {
            emit(&json!({"action":true,"error":e.to_string()}))?;
        }
    }
    q.close();
    f.close();
    quick_thread
        .join()
        .map_err(|_| anyhow::anyhow!("Local provider worker failed"))?;
    file_thread
        .join()
        .map_err(|_| anyhow::anyhow!("File provider worker failed"))?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn history_persists_and_validates_paths() {
        let d = tempfile::tempdir().unwrap();
        let mut h = History {
            path: d.path().join("history.json"),
            entries: HashMap::new(),
        };
        let mut r = item("character", "2014", "em dash", "");
        r["value"] = json!("—");
        h.record(&r, true).unwrap();
        h.record(&r, false).unwrap();
        let saved = read_json(&h.path).unwrap();
        assert_eq!(saved["entries"]["character:2014"]["favorite"], true);
        assert_eq!(h.search("").len(), 1);
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            h.path.metadata().unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
    #[test]
    fn queue_coalesces_obsolete_requests() {
        let q = Queue::default();
        q.push(json!({"id":1}));
        q.push(json!({"id":2}));
        assert_eq!(q.next().unwrap()["id"], 2);
        q.close();
        assert!(q.next().is_none());
    }
}

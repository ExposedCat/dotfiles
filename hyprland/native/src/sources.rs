//! Launcher adapters reuse desktop-owned catalogs and indexes. They never crawl home.
use crate::util::*;
use anyhow::{Context, Result, bail};
use glib::variant::ToVariant;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
pub fn item(kind: &str, id: &str, name: &str, description: &str) -> Value {
    json!({"id":format!("{kind}:{id}"),"kind":kind,"name":name,"description":description})
}
pub fn variants(text: &str) -> Vec<String> {
    let en = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    let ru = "ёйцукенгшщзхъфывапролджэячсмитьбю";
    let lower = text.to_lowercase();
    let (from, to) = if lower.chars().any(|c| ('а'..='я').contains(&c) || c == 'ё') {
        (ru, en)
    } else {
        (en, ru)
    };
    let map: HashMap<_, _> = from.chars().zip(to.chars()).collect();
    vec![
        lower.clone(),
        lower
            .chars()
            .map(|c| map.get(&c).copied().unwrap_or(c))
            .collect(),
    ]
}
fn score_queries(name: &str, queries: &[String], extra: &str) -> u32 {
    let name = name.to_lowercase();
    let extra = extra.to_lowercase();
    queries
        .iter()
        .map(|q| {
            if name == *q {
                0
            } else if name.starts_with(q) {
                1
            } else if q.split_whitespace().all(|w| name.contains(w)) {
                2
            } else if q
                .split_whitespace()
                .all(|w| name.contains(w) || extra.contains(w))
            {
                3
            } else {
                99
            }
        })
        .min()
        .unwrap_or(99)
}
pub fn score(name: &str, query: &str, extra: &str) -> u32 {
    score_queries(name, &variants(query), extra)
}
pub fn collapse(rows: Vec<Value>) -> Vec<Value> {
    let mut result: Vec<Value> = vec![];
    let mut positions = HashMap::new();
    for row in rows {
        let key = if row["kind"] == "character" {
            format!(
                "character:{}",
                s(&row, "value").replace(['\u{fe0e}', '\u{fe0f}'], "")
            )
        } else {
            s(&row, "id").into()
        };
        if let Some(&i) = positions.get(&key) {
            let old: &Value = &result[i];
            let favorite = row["favorite"] == true;
            let was = old["favorite"] == true;
            if (favorite && !was)
                || (favorite == was
                    && s(&row, "value").contains('\u{fe0f}')
                    && !s(old, "value").contains('\u{fe0f}'))
            {
                result[i] = row;
            }
        } else {
            positions.insert(key, result.len());
            result.push(row);
        }
    }
    result
}
#[derive(Default)]
pub struct Characters {
    records: Option<Vec<(String, String, String)>>,
}
impl Characters {
    fn load(&mut self) -> Result<()> {
        let signature = ["emoji-en.dict", "emoji-ru.dict", "unicode-names.dict"]
            .iter()
            .map(|name| {
                let path = PathBuf::from("/usr/share/ibus/dicts").join(name);
                let metadata = path.metadata()?;
                Ok(json!([
                    path,
                    metadata
                        .modified()?
                        .duration_since(std::time::UNIX_EPOCH)?
                        .as_nanos() as u64,
                    metadata.len()
                ]))
            })
            .collect::<Result<Vec<_>>>()?;
        let cache =
            xdg("XDG_CACHE_HOME", ".cache").join("dotfiles/hyprland/launcher-characters.json");
        if let Ok(cached) = read_json(&cache)
            && matches!(cached["version"].as_u64(), Some(2 | 3))
            && cached["sources"] == json!(signature)
            && let Ok(records) = serde_json::from_value(cached["records"].clone())
        {
            self.records = Some(records);
            return Ok(());
        }
        self.load_installed()?;
        if let Err(e) = atomic_json(
            &cache,
            &json!({"version":3,"sources":signature,"records":self.records}),
        ) {
            eprintln!("Could not cache character catalog: {e}");
        }
        Ok(())
    }
    fn load_installed(&mut self) -> Result<()> {
        // IBus owns Unicode/CLDR annotations, including sequences and Russian names.
        // The only unsafe code calls its public C ABI; returned list/object ownership
        // is consumed before the library is released.
        unsafe {
            let lib = library("libibus-1.0.so.5")?;
            let init: libloading::Symbol<unsafe extern "C" fn()> = lib.get(b"ibus_init")?;
            init();
            for name in [
                b"ibus_emoji_data_get_type".as_slice(),
                b"ibus_unicode_data_get_type".as_slice(),
            ] {
                let get: libloading::Symbol<unsafe extern "C" fn() -> glib::ffi::GType> =
                    lib.get(name)?;
                glib::gobject_ffi::g_type_ensure(get());
            }
            type Load = unsafe extern "C" fn(*const libc::c_char) -> *mut glib::ffi::GSList;
            type Text = unsafe extern "C" fn(*mut libc::c_void) -> *const libc::c_char;
            type Annotations = unsafe extern "C" fn(*mut libc::c_void) -> *mut glib::ffi::GSList;
            let load: libloading::Symbol<Load> = lib.get(b"ibus_emoji_data_load")?;
            let emoji: libloading::Symbol<Text> = lib.get(b"ibus_emoji_data_get_emoji")?;
            let description: libloading::Symbol<Text> =
                lib.get(b"ibus_emoji_data_get_description")?;
            let annotations: libloading::Symbol<Annotations> =
                lib.get(b"ibus_emoji_data_get_annotations")?;
            let mut records: HashMap<String, (String, String)> = HashMap::new();
            for locale in ["en", "ru"] {
                let path =
                    std::ffi::CString::new(format!("/usr/share/ibus/dicts/emoji-{locale}.dict"))?;
                let list = load(path.as_ptr());
                let mut cursor = list;
                while !cursor.is_null() {
                    let object = (*cursor).data;
                    if object.is_null() {
                        cursor = (*cursor).next;
                        continue;
                    }
                    let value = cstr(emoji(object));
                    let title = cstr(description(object));
                    if !value.is_empty() {
                        let row = records.entry(value.clone()).or_insert((
                            if title.is_empty() {
                                value
                            } else {
                                title.clone()
                            },
                            String::new(),
                        ));
                        row.1.push_str(&format!(" {title}"));
                        let mut names = annotations(object);
                        while !names.is_null() {
                            row.1.push(' ');
                            row.1.push_str(&cstr((*names).data.cast()));
                            names = (*names).next;
                        }
                    }
                    glib::gobject_ffi::g_object_unref(object.cast());
                    cursor = (*cursor).next;
                }
                glib::ffi::g_slist_free(list);
            }
            let load: libloading::Symbol<
                unsafe extern "C" fn(
                    *const libc::c_char,
                    *mut libc::c_void,
                ) -> *mut glib::ffi::GSList,
            > = lib.get(b"ibus_unicode_data_load")?;
            let code: libloading::Symbol<unsafe extern "C" fn(*mut libc::c_void) -> u32> =
                lib.get(b"ibus_unicode_data_get_code")?;
            let name: libloading::Symbol<Text> = lib.get(b"ibus_unicode_data_get_name")?;
            let alias: libloading::Symbol<Text> = lib.get(b"ibus_unicode_data_get_alias")?;
            let path = c"/usr/share/ibus/dicts/unicode-names.dict";
            let list = load(path.as_ptr(), std::ptr::null_mut());
            let mut cursor = list;
            while !cursor.is_null() {
                let object = (*cursor).data;
                if object.is_null() {
                    cursor = (*cursor).next;
                    continue;
                }
                let value = char::from_u32(code(object)).map(|c| c.to_string());
                if let Some(value) = value {
                    let title = cstr(name(object));
                    if !title.starts_with('<')
                        && !value.chars().any(|c| c.is_control() || c.is_whitespace())
                    {
                        records
                            .entry(value)
                            .or_insert((title.to_lowercase(), cstr(alias(object))));
                    }
                }
                glib::gobject_ffi::g_object_unref(object.cast());
                cursor = (*cursor).next;
            }
            glib::ffi::g_slist_free(list);
            for (value, name) in [
                ("¯\\_(ツ)_/¯", "shrug"),
                ("—", "em dash"),
                ("–", "en dash"),
                ("✓", "checkmark"),
                ("✗", "cross mark"),
                ("…", "ellipsis"),
            ] {
                records
                    .entry(value.into())
                    .or_insert((name.into(), String::new()))
                    .1
                    .push_str(&format!(" {name}"));
            }
            if records.is_empty() {
                bail!("The installed IBus character catalogs are unavailable");
            }
            self.records = Some(records.into_iter().map(|(v, (n, a))| (v, n, a)).collect());
        }
        Ok(())
    }
    pub fn search(&mut self, query: &str, explicit: bool) -> Result<Vec<Value>> {
        let code = regex::Regex::new(r"(?i)^(?:u\+|0x)([0-9a-f]{2,6})$")?;
        if let Some(code) = code.captures(query) {
            return Ok(u32::from_str_radix(&code[1], 16)
                .ok()
                .and_then(char::from_u32)
                .map(|c| {
                    vec![character(
                        &c.to_string(),
                        &unicode_names2::name(c)
                            .map(|n| n.to_string().to_lowercase())
                            .unwrap_or("Unnamed character".into()),
                    )]
                })
                .unwrap_or_default());
        }
        if explicit && query.chars().count() == 1 {
            let c = query.chars().next().unwrap();
            return Ok(vec![character(
                query,
                &unicode_names2::name(c)
                    .map(|n| n.to_string().to_lowercase())
                    .unwrap_or("Unnamed character".into()),
            )]);
        }
        if query.chars().count() < 2 {
            return Ok(vec![]);
        }
        if self.records.is_none() {
            self.load()?;
        }
        let queries = variants(query);
        let mut found: Vec<_> = self
            .records
            .as_ref()
            .unwrap()
            .iter()
            .filter_map(|(v, n, a)| {
                let rank = score_queries(n, &queries, a);
                if rank < if explicit { 4 } else { 3 } {
                    Some((rank, n.chars().count(), v, n))
                } else {
                    None
                }
            })
            .collect();
        found.sort();
        let mut rows = vec![];
        let mut seen = HashSet::new();
        if !explicit {
            let mut grouped: HashMap<String, (u32, usize, &String, &String)> = HashMap::new();
            for m in found {
                let key = m.2.replace(['\u{fe0e}', '\u{fe0f}'], "");
                if grouped.get(&key).is_none_or(|old| {
                    m.0 == old.0
                        && m.1 == old.1
                        && m.2.contains('\u{fe0f}')
                        && !old.2.contains('\u{fe0f}')
                }) {
                    grouped.entry(key).and_modify(|old| *old = m).or_insert(m);
                }
            }
            found = grouped.into_values().collect();
            found.sort();
        }
        for (_, _, v, n) in found {
            if seen.insert(v) {
                rows.push(character(v, n));
            }
            if rows.len() >= if explicit { 24 } else { 4 } {
                break;
            }
        }
        Ok(rows)
    }
}
unsafe fn cstr(p: *const libc::c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(p) }
            .to_string_lossy()
            .into_owned()
    }
}
fn character(value: &str, name: &str) -> Value {
    let id = value
        .chars()
        .map(|c| format!("{:X}", c as u32))
        .collect::<Vec<_>>()
        .join("-");
    let codes = value
        .chars()
        .map(|c| format!("U+{:04X}", c as u32))
        .collect::<Vec<_>>()
        .join(" ");
    let mut row = item("character", &id, name, &codes);
    row["value"] = json!(value);
    row["glyph"] = json!(if value.chars().any(char::is_control) {
        "␣"
    } else {
        value
    });
    row
}

#[derive(Default)]
pub struct Zen {
    profile: Option<PathBuf>,
    launch: Vec<String>,
    name: String,
    bookmarks: Vec<(String, String)>,
    updated: Option<Instant>,
    signature: Option<Vec<Option<(std::time::SystemTime, u64)>>>,
}
fn ini(path: &Path) -> Vec<(String, HashMap<String, String>)> {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut sections = vec![];
    for l in text.lines().map(str::trim) {
        if l.starts_with('[') && l.ends_with(']') {
            sections.push((l[1..l.len() - 1].into(), HashMap::new()));
        } else if let (Some((_, values)), Some((k, v))) = (sections.last_mut(), l.split_once('=')) {
            values.insert(k.trim().into(), v.trim().into());
        }
    }
    sections
}
impl Zen {
    pub fn available(&self) -> bool {
        self.profile.is_some()
    }
    fn discover(&mut self) {
        for (path, launch) in [
            (
                home().join(".var/app/app.zen_browser.zen/.zen"),
                vec!["flatpak", "run", "app.zen_browser.zen"],
            ),
            (home().join(".zen"), vec!["zen"]),
            (home().join(".config/zen"), vec!["zen"]),
        ] {
            let sections = ini(&path.join("profiles.ini"));
            let mut profiles = vec![];
            for (section, values) in &sections {
                if section.starts_with("Install") {
                    if let Some(default) = values.get("Default") {
                        profiles.insert(0, path.join(default));
                    }
                } else if section.starts_with("Profile")
                    && let Some(p) = values.get("Path")
                {
                    profiles.push(if values.get("IsRelative").is_none_or(|v| v == "1") {
                        path.join(p)
                    } else {
                        PathBuf::from(p)
                    });
                }
            }
            for p in profiles {
                if p.join("places.sqlite").is_file() && exists(launch[0]) {
                    self.name = sections
                        .iter()
                        .find_map(|(section, values)| {
                            if section.starts_with("Profile")
                                && values
                                    .get("Path")
                                    .is_some_and(|v| path.join(v) == p || *v == p)
                            {
                                values.get("Name").cloned()
                            } else {
                                None
                            }
                        })
                        .unwrap_or_default();
                    self.profile = Some(p);
                    self.launch = launch.iter().map(|s| s.to_string()).collect();
                    return;
                }
            }
        }
    }
    fn refresh(&mut self) -> Result<()> {
        if self.profile.is_none() {
            self.discover();
        }
        let Some(profile) = &self.profile else {
            return Ok(());
        };
        if self
            .updated
            .is_some_and(|t| t.elapsed() < Duration::from_secs(60))
        {
            return Ok(());
        }
        self.updated = Some(Instant::now());
        let db = profile.join("places.sqlite");
        let wal = profile.join("places.sqlite-wal");
        let signature = || {
            [&db, &wal]
                .into_iter()
                .map(|p| {
                    p.metadata()
                        .ok()
                        .and_then(|m| Some((m.modified().ok()?, m.len())))
                })
                .collect::<Vec<_>>()
        };
        let mut before = signature();
        if self.signature.as_ref() == Some(&before) {
            return Ok(());
        }
        for _ in 0..2 {
            let temp = tempfile::tempdir()?;
            for source in [&db, &wal] {
                if source.is_file() {
                    fs::copy(source, temp.path().join(source.file_name().unwrap()))?;
                }
            }
            let after = signature();
            if before != after {
                before = after;
                continue;
            }
            let connection = rusqlite::Connection::open(temp.path().join("places.sqlite"))?;
            connection.busy_timeout(Duration::from_millis(100))?;
            let mut statement=connection.prepare("SELECT COALESCE(b.title, p.title, p.url), p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.type=1")?;
            self.bookmarks = statement
                .query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?
                .filter_map(|r| r.ok())
                .filter(|(_, u)| u.starts_with("https://") || u.starts_with("http://"))
                .collect();
            self.signature = Some(before);
            return Ok(());
        }
        bail!("Zen bookmark snapshot changed while reading")
    }
    pub fn search(&mut self, query: &str, explicit: bool) -> Result<Vec<Value>> {
        self.refresh()?;
        if self.profile.is_none() {
            return Ok(vec![]);
        }
        let mut matches: Vec<_> = self
            .bookmarks
            .iter()
            .filter_map(|(t, u)| {
                let rank = score(t, query, u);
                if query.is_empty() && explicit || !query.is_empty() && rank < 4 {
                    Some((rank, t, u))
                } else {
                    None
                }
            })
            .collect();
        matches.sort();
        let mut results: Vec<_> = matches
            .into_iter()
            .take(if explicit { 20 } else { 4 })
            .map(|(_, t, u)| {
                let mut r = item("bookmark", u, t, u);
                r["uri"] = json!(u);
                r
            })
            .collect();
        if query.starts_with("https://") || query.starts_with("http://") {
            let mut r = item("bookmark", query, "Open in Zen", query);
            r["uri"] = json!(query);
            results.insert(0, r);
        }
        if explicit && !query.is_empty() {
            let mut r = item(
                "web",
                query,
                &format!("Search Zen for “{query}”"),
                "Use your Zen search engine",
            );
            r["value"] = json!(query);
            results.push(r);
        }
        Ok(results)
    }
    pub fn open(&mut self, row: &Value) -> Result<()> {
        if self.profile.is_none() {
            self.discover();
        }
        if self.profile.is_none() || self.name.is_empty() {
            bail!("Your Zen profile is unavailable");
        }
        let mut c = std::process::Command::new(&self.launch[0]);
        c.args(&self.launch[1..]).args(["-P", &self.name]);
        if row["kind"] == "web" {
            c.args(["--search", s(row, "value")]);
        } else {
            let uri = s(row, "uri");
            if !uri.starts_with("https://") && !uri.starts_with("http://") {
                bail!("Invalid browser URL");
            }
            c.args(["--new-tab", uri]);
        }
        crate::launcher::detach(c)
    }
}
fn file_row(path: &Path, name: &str, description: &str) -> Result<Value> {
    let uri = url::Url::from_file_path(path)
        .map_err(|_| anyhow::anyhow!("Expected an absolute file path"))?
        .to_string();
    let mut r = item("file", &uri, name, description);
    r["uri"] = json!(uri);
    r["path"] = json!(path);
    r["directory"] = json!(path.is_dir());
    r["icon"] = json!(if path.is_dir() {
        "folder"
    } else {
        "text-x-generic"
    });
    Ok(r)
}
pub fn files(query: &str, limit: usize) -> Result<Vec<Value>> {
    if query.starts_with('/') || query.starts_with("~/") || query.starts_with("file://") {
        let path = if query.starts_with("file://") {
            url::Url::parse(query)?
                .to_file_path()
                .map_err(|_| anyhow::anyhow!("Expected a local file"))?
        } else if let Some(relative) = query.strip_prefix("~/") {
            home().join(relative)
        } else {
            PathBuf::from(query)
        };
        let (parent, prefix) = if query.ends_with('/') {
            (path.as_path(), String::new())
        } else {
            (
                path.parent().context("Missing parent")?,
                path.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into_owned(),
            )
        };
        if !parent.is_dir() {
            return Ok(vec![]);
        }
        let mut matches: Vec<_> = fs::read_dir(parent)?
            .take(10000)
            .filter_map(|e| e.ok())
            .filter(|e| {
                let name = e.file_name().to_string_lossy().into_owned();
                (!name.starts_with('.') || prefix.starts_with('.'))
                    && name.to_lowercase().starts_with(&prefix.to_lowercase())
            })
            .map(|e| {
                (
                    !e.path().is_dir(),
                    e.file_name().to_string_lossy().to_lowercase(),
                    e.path(),
                )
            })
            .collect();
        matches.sort();
        return matches
            .iter()
            .take(limit)
            .map(|(_, _, p)| {
                file_row(
                    p,
                    &p.file_name().unwrap().to_string_lossy(),
                    &parent.to_string_lossy(),
                )
            })
            .collect();
    }
    if query.chars().count() < 3 {
        return Ok(vec![]);
    }
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)?;
    let call = |method, parameters: &glib::Variant| -> Result<glib::Variant> {
        Ok(bus
            .call_sync(
                Some("org.gnome.Nautilus"),
                "/org/gnome/Nautilus/SearchProvider",
                "org.gnome.Shell.SearchProvider2",
                method,
                Some(parameters),
                None,
                gio::DBusCallFlags::NONE,
                2200,
                gio::Cancellable::NONE,
            )?
            .child_value(0))
    };
    for text in variants(query) {
        let terms: Vec<_> = text.split_whitespace().collect();
        let ids = call("GetInitialResultSet", &(terms,).to_variant())?
            .get::<Vec<String>>()
            .context("Invalid file search results")?;
        if ids.is_empty() {
            continue;
        }
        let ids: Vec<_> = ids.into_iter().take(limit).collect();
        let metadata = call("GetResultMetas", &(ids,).to_variant())?
            .get::<Vec<HashMap<String, glib::Variant>>>()
            .context("Invalid file metadata")?;
        let mut result = vec![];
        for m in metadata {
            let Some(uri) = m.get("id").and_then(|v| v.str()) else {
                continue;
            };
            if !uri.starts_with("file://") {
                continue;
            }
            let Ok(path) = url::Url::parse(uri)?.to_file_path() else {
                continue;
            };
            if !path.exists() {
                continue;
            }
            let name = m
                .get("name")
                .and_then(|v| v.str())
                .map(String::from)
                .unwrap_or_else(|| {
                    path.file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into()
                });
            let desc = m
                .get("description")
                .and_then(|v| v.str())
                .map(String::from)
                .unwrap_or_else(|| {
                    path.parent()
                        .unwrap_or(Path::new("/"))
                        .to_string_lossy()
                        .into()
                });
            result.push(file_row(&path, &name, &desc)?);
        }
        if !result.is_empty() {
            return Ok(result.into_iter().take(limit).collect());
        }
    }
    Ok(vec![])
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn installed_catalog_handles_unicode_and_sequences() {
        let mut c = Characters::default();
        c.load_installed().unwrap();
        assert_eq!(c.search("em dash", true).unwrap()[0]["value"], "—");
        assert_eq!(
            c.search("greek small letter alpha", true).unwrap()[0]["value"],
            "α"
        );
        assert!(
            c.search("family", true)
                .unwrap()
                .iter()
                .any(|r| s(r, "value").chars().count() > 1)
        );
        assert!(!c.search("улыбка", true).unwrap().is_empty());
    }
    #[test]
    fn layout_recovery() {
        assert_eq!(variants("еудупкфь"), vec!["еудупкфь", "telegram"]);
        assert_eq!(score("Telegram", "еудупкфь", ""), 0);
        assert_eq!(score("привет", "ghbdtn", ""), 0);
    }
    #[test]
    fn bounded_path_completion() {
        let d = tempfile::tempdir().unwrap();
        fs::create_dir(d.path().join("Folder with spaces")).unwrap();
        fs::write(d.path().join("notes.txt"), "").unwrap();
        fs::write(d.path().join(".hidden"), "").unwrap();
        let found = files(&format!("{}/", d.path().display()), 24).unwrap();
        assert_eq!(found.len(), 2);
        assert_eq!(found[0]["name"], "Folder with spaces");
        assert!(s(&found[0], "uri").contains("Folder%20with%20spaces"));
    }
    #[test]
    fn presentation_favorites() {
        let mut a = item("character", "260E", "telephone", "");
        a["value"] = json!("☎");
        a["favorite"] = json!(true);
        let mut b = item("character", "260E-FE0F", "telephone", "");
        b["value"] = json!("☎️");
        assert_eq!(collapse(vec![a, b])[0]["value"], "☎");
    }
}

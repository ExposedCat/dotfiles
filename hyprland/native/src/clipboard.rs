use crate::util::*;
use anyhow::{Result, bail};
use html5ever::{
    buffer_queue::BufferQueue,
    tokenizer::{TagKind, Token, TokenSink, TokenSinkResult, Tokenizer},
};
use rusqlite::{Connection, params};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    cell::RefCell,
    collections::HashSet,
    fs,
    io::{Read, Seek, Write},
    os::{
        fd::{AsRawFd, RawFd},
        unix::fs::OpenOptionsExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
use wait_timeout::ChildExt;
use wl_clipboard_rs::{
    copy::{MimeSource, MimeType, Options, Source},
    paste::{self, Seat},
    utils::PASSWORD_MANAGER_HINT_MIME_TYPE,
    watch::{ClipboardEvent, ClipboardType, Offer, Watcher},
};

const HISTORY_LIMIT: usize = 100;
const ENTRY_BYTES: usize = 64 * 1024 * 1024;
const HISTORY_BYTES: usize = 256 * 1024 * 1024;
const PREVIEW_BYTES: usize = 8192;
const REMOTE_IMAGE_BYTES: usize = 16 * 1024 * 1024;
const HTML_PREVIEW_VERSION: u64 = 2;
const IMAGE_PREVIEW_VERSION: u64 = 2;
const HISTORY_MARKER: &str = "application/x-dotfiles-clipboard-history;owner=";
type Contents = Vec<(String, Vec<u8>)>;

fn database() -> Result<Connection> {
    let directory = xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland");
    fs::create_dir_all(&directory)?;
    let db = Connection::open(directory.join("clipboard.sqlite3"))?;
    db.busy_timeout(Duration::from_secs(4))?;
    db.execute_batch(
        "PRAGMA secure_delete = ON;
         PRAGMA foreign_keys = ON;
         CREATE TABLE IF NOT EXISTS entry (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             digest BLOB NOT NULL UNIQUE,
             bytes INTEGER NOT NULL,
             description TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS format (
             entry INTEGER NOT NULL REFERENCES entry(id) ON DELETE CASCADE,
             mime TEXT NOT NULL,
             data BLOB NOT NULL,
             PRIMARY KEY (entry, mime)
         );",
    )?;
    Ok(db)
}

fn history_lock() -> Result<Lock> {
    Lock::acquire(
        &xdg("XDG_STATE_HOME", ".local/state").join("dotfiles/hyprland/clipboard.lock"),
        false,
    )
}

fn base_mime(mime: &str) -> &str {
    mime.split(';').next().unwrap_or(mime)
}

fn plain(mime: &str) -> bool {
    matches!(
        base_mime(mime),
        "text/plain" | "UTF8_STRING" | "STRING" | "TEXT"
    )
}

fn media(mime: &str) -> bool {
    mime.starts_with("image/") || mime.starts_with("video/")
}

fn preferred_formats(mimes: &[String]) -> Vec<&str> {
    let best_plain = [
        "text/plain;charset=utf-8",
        "UTF8_STRING",
        "text/plain",
        "TEXT",
        "STRING",
    ]
    .iter()
    .find_map(|candidate| {
        mimes
            .iter()
            .find(|mime| mime.eq_ignore_ascii_case(candidate))
    });
    // Read compact alternatives first so that a large media payload cannot
    // crowd out the text, HTML or file list from the same selection.
    let mut formats: Vec<&str> = best_plain.into_iter().map(String::as_str).collect();
    formats.extend(
        mimes
            .iter()
            .map(String::as_str)
            .filter(|mime| {
                matches!(
                    base_mime(mime),
                    "text/html"
                        | "text/uri-list"
                        | "text/rtf"
                        | "application/rtf"
                        | "x-special/gnome-copied-files"
                        | "application/x-kde-cutselection"
                )
            })
            .take(12),
    );
    formats.extend(
        mimes
            .iter()
            .map(String::as_str)
            .filter(|mime| media(mime))
            .take(8),
    );
    formats
}

fn readable(fd: RawFd, deadline: Instant) -> std::io::Result<()> {
    let mut descriptor = libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    };
    loop {
        let timeout = deadline
            .saturating_duration_since(Instant::now())
            .as_millis();
        let ready = unsafe { libc::poll(&mut descriptor, 1, timeout as i32) };
        if ready > 0 {
            return Ok(());
        }
        if ready == 0 {
            return Err(std::io::ErrorKind::TimedOut.into());
        }
        let error = std::io::Error::last_os_error();
        if error.kind() != std::io::ErrorKind::Interrupted {
            return Err(error);
        }
    }
}

fn receive(offer: &mut Offer, mime: &str, limit: usize, deadline: Instant) -> Result<Vec<u8>> {
    let mut pipe = offer.receive(mime)?;
    let mut data = Vec::new();
    let mut buffer = [0; 32768];
    loop {
        readable(pipe.as_raw_fd(), deadline)?;
        let count = pipe.read(&mut buffer)?;
        if count == 0 {
            return Ok(data);
        }
        if data.len() + count > limit {
            bail!("Clipboard format exceeds the history size limit");
        }
        data.extend_from_slice(&buffer[..count]);
    }
}

pub fn watch() -> Result<()> {
    let mut watcher = Watcher::new(ClipboardType::Regular, Seat::Unspecified)?;
    let mut db = database()?;
    while let Some(event) = watcher.next_event()? {
        let ClipboardEvent::Changed {
            mime_types,
            mut offer,
            ..
        } = event
        else {
            continue;
        };
        if mime_types
            .iter()
            .any(|mime| mime.starts_with(HISTORY_MARKER) || mime == PASSWORD_MANAGER_HINT_MIME_TYPE)
        {
            continue;
        }
        let _lock = history_lock()?;
        let mut contents = Vec::new();
        let mut bytes = 0;
        let deadline = Instant::now() + Duration::from_secs(3);
        for mime in preferred_formats(&mime_types) {
            if bytes >= ENTRY_BYTES || Instant::now() >= deadline {
                break;
            }
            if let Ok(data) = receive(&mut offer, mime, ENTRY_BYTES - bytes, deadline)
                && !data.is_empty()
            {
                bytes += data.len();
                contents.push((mime.to_owned(), data));
            }
        }
        if !contents.is_empty() {
            contents.sort_by(|a, b| a.0.cmp(&b.0));
            store(&mut db, &contents, bytes)?;
        }
    }
    Ok(())
}

fn store(db: &mut Connection, contents: &Contents, bytes: usize) -> Result<()> {
    let mut digest = Sha256::new();
    for (mime, data) in contents {
        digest.update(mime.as_bytes());
        digest.update([0]);
        digest.update(data.len().to_le_bytes());
        digest.update(data);
    }
    let digest = digest.finalize();
    let transaction = db.transaction()?;
    transaction.execute("DELETE FROM entry WHERE digest = ?1", [digest.as_slice()])?;
    transaction.execute(
        "INSERT INTO entry (digest, bytes, description) VALUES (?1, ?2, ?3)",
        params![
            digest.as_slice(),
            bytes as i64,
            describe(contents).to_string()
        ],
    )?;
    let id = transaction.last_insert_rowid();
    for (mime, data) in contents {
        transaction.execute(
            "INSERT INTO format VALUES (?1, ?2, ?3)",
            params![id, mime, data],
        )?;
    }
    transaction.execute(
        "DELETE FROM entry WHERE id IN (
            SELECT id FROM (
                SELECT id, row_number() OVER (ORDER BY id DESC) AS position,
                    sum(bytes) OVER (ORDER BY id DESC) AS size
                FROM entry
            ) WHERE position > ?1 OR size > ?2
         )",
        params![HISTORY_LIMIT as i64, HISTORY_BYTES as i64],
    )?;
    transaction.commit()?;
    Ok(())
}

fn preview_text(data: &[u8]) -> String {
    String::from_utf8_lossy(&data[..data.len().min(PREVIEW_BYTES)]).into_owned()
}

fn color(text: &str) -> Option<String> {
    use std::sync::LazyLock;
    static CSS_COLOR: LazyLock<regex::Regex> = LazyLock::new(|| {
        regex::Regex::new(r"(?i)^(rgb|rgba|hsl|hsla)\(\s*([+-]?[\d.]+%?)(?:\s*,\s*|\s+)([+-]?[\d.]+%?)(?:\s*,\s*|\s+)([+-]?[\d.]+%?)(?:(?:\s*,\s*|\s*/\s*)([+-]?[\d.]+%?))?\s*\)$").unwrap()
    });
    let text = text.trim();
    if let Some(hex) = text.strip_prefix('#') {
        if ![3, 4, 6, 8].contains(&hex.len()) || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        let rgba = if hex.len() <= 4 {
            hex.chars()
                .flat_map(|digit| [digit, digit])
                .collect::<String>()
        } else {
            hex.to_owned()
        };
        // Qt's eight-digit notation puts alpha first; CSS puts it last.
        return Some(if rgba.len() == 8 {
            format!("#{}{}", &rgba[6..], &rgba[..6])
        } else {
            format!("#{rgba}")
        });
    }
    let parts = CSS_COLOR.captures(text)?;
    let number = |part: &str, scale: f64| -> Option<f64> {
        let value = part.trim_end_matches('%').parse::<f64>().ok()?;
        value.is_finite().then_some(if part.ends_with('%') {
            value / 100.
        } else {
            value / scale
        })
    };
    let alpha = parts
        .get(5)
        .map_or(Some(1.), |part| number(part.as_str(), 1.))?;
    let rgb = if parts[1].to_ascii_lowercase().starts_with("hsl") {
        let hue = parts[2].parse::<f64>().ok()?.rem_euclid(360.) / 30.;
        let saturation = number(&parts[3], 100.)?.clamp(0., 1.);
        let lightness = number(&parts[4], 100.)?.clamp(0., 1.);
        let channel = |shift: f64| {
            let k = (hue + shift).rem_euclid(12.);
            lightness
                - saturation * lightness.min(1. - lightness) * (k - 3.).min(9. - k).clamp(-1., 1.)
        };
        [channel(0.), channel(8.), channel(4.)]
    } else {
        [
            number(&parts[2], 255.)?,
            number(&parts[3], 255.)?,
            number(&parts[4], 255.)?,
        ]
    };
    let byte = |value: f64| (value.clamp(0., 1.) * 255.).round() as u8;
    Some(format!(
        "#{:02x}{:02x}{:02x}{:02x}",
        byte(alpha),
        byte(rgb[0]),
        byte(rgb[1]),
        byte(rgb[2])
    ))
}

fn safe_html(text: &str) -> String {
    let tags = [
        "a",
        "b",
        "blockquote",
        "br",
        "code",
        "dd",
        "div",
        "dl",
        "dt",
        "em",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "hr",
        "i",
        "li",
        "ol",
        "p",
        "pre",
        "s",
        "span",
        "strike",
        "strong",
        "sub",
        "sup",
        "table",
        "tbody",
        "td",
        "th",
        "thead",
        "tr",
        "u",
        "ul",
    ];
    ammonia::Builder::default()
        .tags(HashSet::from(tags))
        // Ammonia parses fragments, so an unrecognized <head> can be discarded
        // while its <title> text survives. The preview should show the body.
        .add_clean_content_tags(&["title"])
        .tag_attributes(Default::default())
        .generic_attributes(Default::default())
        .link_rel(None)
        .clean(text)
        .to_string()
}

struct ImageReference {
    url: url::Url,
    alt: String,
}

impl ImageReference {
    fn downloadable(&self) -> bool {
        matches!(self.url.scheme(), "http" | "https")
    }

    fn source(&self) -> String {
        if self.url.scheme() == "blob" {
            return url::Url::parse(self.url.path())
                .ok()
                .and_then(|origin| origin.host_str().map(str::to_owned))
                .unwrap_or_else(|| "Browser image".into());
        }
        self.url.host_str().unwrap_or_default().to_owned()
    }
}

#[derive(Default)]
enum ImageFragment {
    #[default]
    Empty,
    Image(ImageReference),
    Mixed,
}

struct ImageTokens(RefCell<ImageFragment>);

impl TokenSink for ImageTokens {
    type Handle = ();

    fn process_token(&self, token: Token, _: u64) -> TokenSinkResult<()> {
        use Token::*;
        let mut fragment = self.0.borrow_mut();
        match token {
            TagToken(tag) if &*tag.name == "img" && tag.kind == TagKind::StartTag => {
                let attr = |name| {
                    tag.attrs
                        .iter()
                        .find(|attr| &*attr.name.local == name)
                        .map(|attr| attr.value.trim())
                        .unwrap_or_default()
                };
                *fragment = if matches!(*fragment, ImageFragment::Empty)
                    && let Ok(url) = url::Url::parse(attr("src"))
                    && matches!(url.scheme(), "http" | "https" | "blob")
                    && url.username().is_empty()
                    && url.password().is_none()
                {
                    ImageFragment::Image(ImageReference {
                        url,
                        alt: attr("alt").to_owned(),
                    })
                } else {
                    ImageFragment::Mixed
                };
            }
            TagToken(tag)
                if matches!(
                    &*tag.name,
                    "html"
                        | "head"
                        | "body"
                        | "meta"
                        | "div"
                        | "p"
                        | "span"
                        | "a"
                        | "figure"
                        | "br"
                ) => {}
            CharacterTokens(text) if text.trim().is_empty() => {}
            CommentToken(_) | DoctypeToken(_) | EOFToken | ParseError(_) => {}
            _ => *fragment = ImageFragment::Mixed,
        }
        TokenSinkResult::Continue
    }
}

fn image_reference(contents: &Contents) -> Option<ImageReference> {
    let (_, data) = contents
        .iter()
        .find(|(mime, _)| base_mime(mime) == "text/html")
        .or_else(|| contents.iter().find(|(mime, _)| plain(mime)))?;
    image_reference_in_markup(data)
}

fn image_reference_in_markup(data: &[u8]) -> Option<ImageReference> {
    if data.len() > PREVIEW_BYTES {
        return None;
    }
    let text = std::str::from_utf8(data)
        .ok()?
        .trim_matches(['\u{feff}', '\0'])
        .trim();
    if !text.starts_with('<') {
        return None;
    }
    let input = BufferQueue::default();
    input.push_back(text.into());
    let parser = Tokenizer::new(ImageTokens(RefCell::default()), Default::default());
    let _ = parser.feed(&input);
    parser.end();
    match parser.sink.0.into_inner() {
        ImageFragment::Image(image) => Some(image),
        _ => None,
    }
}

fn remote_image(contents: &Contents) -> Option<ImageReference> {
    // Keep the browser's real bitmap or video when it supplied one.
    if contents
        .iter()
        .any(|(mime, _)| media(mime) || file_offer(mime))
    {
        return None;
    }
    image_reference(contents).filter(ImageReference::downloadable)
}

fn image_description(mime: Option<&str>, reference: Option<&ImageReference>, label: &str) -> Value {
    let kind = if mime.is_none() && reference.is_some_and(ImageReference::downloadable) {
        "remote-image"
    } else {
        "image"
    };
    let alt = reference
        .map(|image| image.alt.as_str())
        .filter(|alt| !alt.is_empty());
    json!({
        "kind":kind,
        "mime":mime,
        "preview":alt.unwrap_or(label).chars().take(600).collect::<String>(),
        "source":reference.map(ImageReference::source),
        "imagePreviewVersion":IMAGE_PREVIEW_VERSION,
    })
}

fn describe_text(text: &str) -> Value {
    let text = text.trim();
    let preview: String = text.chars().take(600).collect();
    if let Some(swatch) = color(text) {
        return json!({"kind":"color","preview":preview,"swatch":swatch});
    }
    if !text.contains(char::is_whitespace)
        && let Ok(url) = url::Url::parse(text)
        && matches!(url.scheme(), "https" | "http" | "mailto" | "ftp" | "file")
    {
        return json!({"kind":"link","preview":preview});
    }
    json!({"kind":"text","preview":preview})
}

fn files(text: &str) -> impl Iterator<Item = PathBuf> + '_ {
    text.lines()
        .filter(|line| !line.starts_with('#'))
        .filter_map(|line| url::Url::parse(line.trim()).ok())
        .filter_map(|url| url.to_file_path().ok())
}

fn file_description(mime: &str, data: &[u8]) -> Option<Value> {
    let text = preview_text(data);
    let mut files = files(&text);
    let first = files.next()?;
    let name = first
        .file_name()
        .unwrap_or(first.as_os_str())
        .to_string_lossy();
    let count = files.count();
    let label = if count == 0 {
        name.into_owned()
    } else {
        format!("{name} + {count}")
    };
    let kind = match (count, file_media_type(&first).as_deref()) {
        (0, Some(mime)) if mime.starts_with("image/") => "image",
        (0, Some(_)) => "video",
        _ => "files",
    };
    Some(json!({"kind":kind,"mime":mime,"preview":label}))
}

fn file_media_type(path: &Path) -> Option<String> {
    let (kind, _) = gio::content_type_guess(Some(path), None::<&[u8]>);
    let mime = gio::content_type_get_mime_type(&kind)?.to_string();
    media(&mime).then_some(mime)
}

fn file_offer(mime: &str) -> bool {
    matches!(
        base_mime(mime),
        "text/uri-list" | "x-special/gnome-copied-files"
    )
}

fn describe(contents: &Contents) -> Value {
    let find = |predicate: fn(&str) -> bool| {
        contents
            .iter()
            .find(|(mime, _)| predicate(mime))
            .map(|(_, data)| preview_text(data))
            .unwrap_or_default()
    };
    let text = find(plain);
    let file = contents
        .iter()
        .filter(|(mime, _)| file_offer(mime))
        .find_map(|(mime, data)| file_description(mime, data));
    let reference = image_reference(contents);
    if let Some((mime, _)) = contents
        .iter()
        .filter(|(mime, _)| media(mime))
        .max_by_key(|(mime, _)| (mime.starts_with("video/"), mime == "image/png"))
    {
        let label = file.as_ref().map(|file| s(file, "preview"));
        if mime.starts_with("video/") {
            return json!({"kind":"video","mime":mime,"preview":label.unwrap_or("Video")});
        }
        return image_description(Some(mime), reference.as_ref(), label.unwrap_or("Image"));
    }
    if let Some(file) = file {
        if s(&file, "kind") == "image" {
            return image_description(
                Some(s(&file, "mime")),
                reference.as_ref(),
                s(&file, "preview"),
            );
        }
        return file;
    }
    if let Some(reference) = reference {
        return image_description(None, Some(&reference), "Image");
    }
    let mut description = describe_text(&text);
    let html = find(|mime| base_mime(mime) == "text/html");
    if !html.is_empty() && description["kind"] == "text" {
        let rendered = safe_html(&html);
        if !rendered.trim().is_empty() {
            description["kind"] = json!("html");
            description["html"] = json!(rendered);
            description["htmlPreviewVersion"] = json!(HTML_PREVIEW_VERSION);
        }
    }
    description
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|n| n.is_ascii_digit())
}

fn legacy_ids() -> Result<Vec<(String, String)>> {
    if !exists("cliphist") {
        return Ok(Vec::new());
    }
    let out = Command::new("cliphist").arg("list").output()?;
    if !out.status.success()
        && !String::from_utf8_lossy(&out.stderr)
            .to_lowercase()
            .contains("no such file")
    {
        bail!("{}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|line| {
            let (id, preview) = line.split_once('\t')?;
            valid_id(id).then(|| (id.to_owned(), preview.to_owned()))
        })
        .collect())
}

fn legacy_contents(id: &str) -> Result<Vec<u8>> {
    if !valid_id(id) {
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
    Ok(output.stdout)
}

fn content_type(data: &[u8]) -> String {
    let (kind, _) = gio::content_type_guess(None::<&Path>, Some(data));
    gio::content_type_get_mime_type(&kind)
        .map(|mime| mime.to_string())
        .unwrap_or_else(|| "application/octet-stream".into())
}

pub fn list() -> Result<()> {
    let db = database()?;
    let mut stmt = db.prepare("SELECT id, description FROM entry ORDER BY id DESC LIMIT ?1")?;
    let mut formats =
        db.prepare("SELECT mime, substr(data, 1, ?2) FROM format WHERE entry = ?1")?;
    let mut entries: Vec<Value> = Vec::new();
    for item in stmt.query_map([HISTORY_LIMIT as i64], |row| {
        Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
    })? {
        let (id, description) = item?;
        let mut description: Value = serde_json::from_str(&description)?;
        let preview = s(&description, "preview").trim_start();
        let kind = s(&description, "kind");
        if (kind == "html"
            && description["htmlPreviewVersion"].as_u64() != Some(HTML_PREVIEW_VERSION))
            || (matches!(kind, "image" | "remote-image")
                && description["imagePreviewVersion"].as_u64() != Some(IMAGE_PREVIEW_VERSION))
            || (kind == "text" && (preview.starts_with('<') || preview.is_empty()))
        {
            // Regenerate old descriptions from the source formats. Read an
            // extra byte so remote-image recognition can reject partial HTML.
            let data: Contents = formats
                .query_map(params![id, PREVIEW_BYTES as i64 + 1], |row| {
                    Ok((row.get(0)?, row.get(1)?))
                })?
                .collect::<rusqlite::Result<_>>()?;
            description = describe(&data);
        }
        description["id"] = json!(id.to_string());
        entries.push(description);
    }
    let mut seen: HashSet<String> = entries
        .iter()
        .filter(|row| matches!(s(row, "kind"), "text" | "link" | "color" | "html"))
        .map(|row| s(row, "preview").to_owned())
        .collect();
    for (id, preview) in legacy_ids()?.into_iter() {
        if entries.len() == HISTORY_LIMIT {
            break;
        }
        let mut description = if preview.starts_with("[[ binary data") {
            json!({"kind":"legacy-media","preview":"Image"})
        } else if preview
            .trim_start_matches('\u{feff}')
            .trim_start()
            .starts_with('<')
            && let Ok(data) = legacy_contents(&id)
            && let Some(reference) = image_reference_in_markup(&data)
        {
            // Cliphist's short preview can end before the image tag or its URL.
            image_description(None, Some(&reference), "Image")
        } else {
            let description = describe_text(&preview);
            if !seen.insert(s(&description, "preview").to_owned()) {
                continue;
            }
            description
        };
        description["id"] = json!(format!("legacy-{id}"));
        entries.push(description);
    }
    emit(&json!(entries))
}

pub fn clear() -> Result<()> {
    let _lock = history_lock()?;
    if !legacy_ids()?.is_empty() {
        run(&["cliphist", "wipe"])?;
    }
    database()?.execute("DELETE FROM entry", [])?;
    Ok(())
}

pub fn legacy_copy(id: &str) -> Result<()> {
    status(
        command(&["wl-copy"]),
        Some(legacy_contents(id)?),
        Duration::from_secs(5),
    )
}

fn contents(id: &str) -> Result<Contents> {
    if let Some(id) = id.strip_prefix("legacy-") {
        let data = legacy_contents(id)?;
        let mime = content_type(&data);
        return Ok(vec![(mime, data)]);
    }
    let db = database()?;
    let mut stmt = db.prepare("SELECT mime, data FROM format WHERE entry = ?1")?;
    Ok(stmt
        .query_map([id.parse::<i64>()?], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<rusqlite::Result<_>>()?)
}

pub fn serve(id: &str) -> Result<()> {
    let mut data = contents(id)?;
    if data.is_empty() {
        bail!("Clipboard entry is no longer in history");
    }
    if let Some(image) = remote_image(&data) {
        // Offer the image together with a usable URL for text-only apps and
        // for pastes where the download fails.
        data = download_image(&image.url).unwrap_or_default();
        data.push((
            "text/plain;charset=utf-8".into(),
            image.url.as_str().as_bytes().to_vec(),
        ));
    }
    let plain_index = data.iter().position(|(mime, _)| plain(mime));
    if let Some(index) = plain_index {
        data.swap(0, index);
    }
    data.push((
        format!("{HISTORY_MARKER}{}", std::process::id()),
        b"history".to_vec(),
    ));
    let sources = data
        .into_iter()
        .map(|(mime, data)| MimeSource {
            mime_type: MimeType::Specific(mime),
            source: Source::Bytes(data.into_boxed_slice()),
        })
        .collect();
    let mut options = Options::new();
    options
        .foreground(true)
        .omit_additional_text_mime_types(plain_index.is_none());
    let prepared = options.prepare_copy_multi(sources)?;
    std::io::stdout().write_all(b"1")?;
    std::io::stdout().flush()?;
    prepared.serve()?;
    Ok(())
}

fn valid_address(address: &str) -> bool {
    address.strip_prefix("0x").is_some_and(|value| {
        value.len() <= 16
            && u64::from_str_radix(value, 16).is_ok_and(|number| number != 0)
            && value.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

fn active_window() -> Result<Value> {
    Ok(serde_json::from_str(&output(
        command(&["hyprctl", "-j", "activewindow"]),
        None,
        Duration::from_secs(1),
    )?)?)
}

pub fn paste(id: &str, address: &str) -> Result<()> {
    let window = active_window()?;
    if !valid_address(address) || s(&window, "address") != address {
        bail!("The original paste target has lost focus");
    }
    let mut owner = Command::new(std::env::current_exe()?)
        .args(["desktop", "clipboard-serve", id])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let mut ready = owner.stdout.take().unwrap();
    let result = (|| {
        readable(ready.as_raw_fd(), Instant::now() + Duration::from_secs(8))?;
        ready.read_exact(&mut [0])?;
        // prepare_copy_multi queues the ownership change. Confirm it has
        // reached the compositor before asking the target to read it.
        let marker = format!("{HISTORY_MARKER}{}", owner.id());
        let deadline = Instant::now() + Duration::from_millis(700);
        loop {
            if paste::get_mime_types(paste::ClipboardType::Regular, Seat::Unspecified)
                .is_ok_and(|mimes| mimes.contains(&marker))
            {
                break;
            }
            if Instant::now() >= deadline || owner.try_wait()?.is_some() {
                bail!("Could not offer clipboard history entry");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        if s(&active_window()?, "address") != address {
            bail!("The original paste target has lost focus");
        }
        let class = s(&window, "class").to_ascii_lowercase();
        let terminal = [
            "alacritty",
            "contour",
            "cosmic-term",
            "foot",
            "ghostty",
            "gnome-terminal",
            "kitty",
            "konsole",
            "kgx",
            "ptyxis",
            "tabby",
            "terminator",
            "wezterm",
            "xfce4-terminal",
        ]
        .iter()
        .any(|name| {
            class == *name
                || class.ends_with(&format!(".{name}"))
                || class.ends_with(&format!(".{name}-server"))
        });
        let mods = if terminal { "CTRL SHIFT" } else { "CTRL" };
        // The activation comes from a popup, so there is no compositor bind
        // release to supply the key-up event.
        let target =
            format!("window = \"address:{address}\", mods = \"{mods}\", key = \"code:55\"");
        let lua = format!(
            "hl.dispatch(hl.dsp.send_key_state({{ {target}, state = \"down\" }})); hl.dispatch(hl.dsp.send_key_state({{ {target}, state = \"up\" }}))"
        );
        let result = output(
            command(&["hyprctl", "eval", &lua]),
            None,
            Duration::from_secs(2),
        )?;
        if result.trim() != "ok" {
            bail!("Could not send paste shortcut: {}", result.trim());
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = owner.kill();
        let _ = owner.wait();
    }
    result
}

pub fn preview(id: &str, requested: &str) -> Result<()> {
    if requested == "remote-image" {
        let Some(image) = remote_image(&contents(id)?) else {
            return emit(&json!(""));
        };
        let Ok(data) = fetch_image(&image.url) else {
            return emit(&json!(""));
        };
        return emit_thumbnail(&data, true);
    }
    let (mime, data) = if let Some(id) = id.strip_prefix("legacy-") {
        let data = legacy_contents(id)?;
        (content_type(&data), data)
    } else {
        database()?.query_row(
            "SELECT mime, data FROM format WHERE entry = ?1 AND mime = ?2",
            params![id.parse::<i64>()?, requested],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?
    };
    let (frame, cover) = if file_offer(&mime) {
        let Some(frame) = media_file_frame(&preview_text(&data))? else {
            return emit(&json!(""));
        };
        frame
    } else if !media(&mime) || data.len() > ENTRY_BYTES {
        return emit(&json!(""));
    } else if needs_media_decoder(&mime) {
        let mut source = tempfile::tempfile()?;
        source.write_all(&data)?;
        source.rewind()?;
        (media_frame(source, &mime)?, mime.starts_with("image/"))
    } else {
        (data, mime.starts_with("image/"))
    };
    emit_thumbnail(&frame, cover)
}

fn emit_thumbnail(data: &[u8], cover: bool) -> Result<()> {
    // Decode and resize raster previews out of process from the shell.
    let image = decode_raster(data)?;
    let thumbnail = if cover {
        // Crop before resizing so that tall, narrow pictures keep detail
        // across the row without allocating a giant upscaled intermediate.
        // The padded preview is 368 × 150 logical pixels, rendered at up to 2×.
        const COVER_WIDTH: u32 = 736;
        const COVER_HEIGHT: u32 = 300;
        let width = image.width();
        let height = image.height();
        let crop_width = width.min((height * COVER_WIDTH / COVER_HEIGHT).max(1));
        let crop_height = height.min((width * COVER_HEIGHT / COVER_WIDTH).max(1));
        image
            .crop_imm(
                (width - crop_width) / 2,
                (height - crop_height) / 2,
                crop_width,
                crop_height,
            )
            .thumbnail(COVER_WIDTH, COVER_HEIGHT)
    } else {
        image.thumbnail(560, 208)
    };
    emit(&json!(format!(
        "data:image/png;base64,{}",
        glib::base64_encode(&encode_png(&thumbnail)?)
    )))
}

fn fetch_image(url: &url::Url) -> Result<Vec<u8>> {
    let file = tempfile::NamedTempFile::new()?;
    let mut curl = command(&[
        "/usr/bin/curl",
        "--disable",
        "--globoff",
        "--fail",
        "--location",
        "--max-redirs",
        "3",
        "--proto",
        "=http,https",
        "--proto-redir",
        "=http,https",
        "--disallow-username-in-url",
        "--max-time",
        "5",
        "--max-filesize",
        &REMOTE_IMAGE_BYTES.to_string(),
        "--output",
    ]);
    curl.arg(file.path()).args(["--", url.as_str()]);
    status(curl, None, Duration::from_secs(6))?;
    let mut data = Vec::new();
    file.take(REMOTE_IMAGE_BYTES as u64 + 1)
        .read_to_end(&mut data)?;
    if data.len() > REMOTE_IMAGE_BYTES {
        bail!("Remote image is too large");
    }
    Ok(data)
}

fn download_image(url: &url::Url) -> Result<Contents> {
    let data = fetch_image(url)?;
    let format = image::guess_format(&data)?;
    let image = decode_raster(&data)?;
    let mut sources = vec![(format.to_mime_type().to_owned(), data)];
    if format != image::ImageFormat::Png {
        let png = encode_png(&image)?;
        if png.len() <= ENTRY_BYTES {
            sources.push(("image/png".into(), png));
        }
    }
    Ok(sources)
}

fn decode_raster(frame: &[u8]) -> Result<image::DynamicImage> {
    let mut image = image::ImageReader::new(std::io::Cursor::new(frame)).with_guessed_format()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(96 * 1024 * 1024);
    image.limits(limits);
    Ok(image.decode()?)
}

fn encode_png(image: &image::DynamicImage) -> Result<Vec<u8>> {
    let mut png = std::io::Cursor::new(Vec::new());
    image.write_to(&mut png, image::ImageFormat::Png)?;
    Ok(png.into_inner())
}

fn media_file_frame(text: &str) -> Result<Option<(Vec<u8>, bool)>> {
    let Some(path) = files(text).next() else {
        return Ok(None);
    };
    let Some(mime) = file_media_type(&path) else {
        return Ok(None);
    };
    let file = fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_NOFOLLOW)
        .open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Ok(None);
    }
    if needs_media_decoder(&mime) {
        return Ok(Some((
            media_frame(file, &mime)?,
            mime.starts_with("image/"),
        )));
    }
    if metadata.len() > ENTRY_BYTES as u64 {
        return Ok(None);
    }
    let mut data = Vec::new();
    file.take(ENTRY_BYTES as u64 + 1).read_to_end(&mut data)?;
    Ok((data.len() <= ENTRY_BYTES).then_some((data, true)))
}

fn needs_media_decoder(mime: &str) -> bool {
    mime.starts_with("video/") || base_mime(mime) == "image/svg+xml"
}

fn media_frame(source: fs::File, mime: &str) -> Result<Vec<u8>> {
    let directory = tempfile::tempdir()?;
    let frame = directory.path().join("frame.png");
    let mut decoder = Command::new("ffmpeg");
    decoder.args([
        "-nostdin",
        "-v",
        "error",
        "-max_alloc",
        "67108864",
        "-protocol_whitelist",
        "file",
    ]);
    if base_mime(mime) == "image/svg+xml" {
        decoder.args(["-f", "svg_pipe"]);
    } else {
        decoder.args([
            "-format_whitelist",
            "mov,matroska,webm,avi,mpeg,mpegts,ogg,flv",
        ]);
    }
    // A seekable descriptor lets us read a local video's first frame without
    // copying an entire file into history or resolving a second pathname.
    let mut child = decoder
        .args([
            "-threads",
            "1",
            "-i",
            "/proc/self/fd/0",
            "-map",
            "0:v:0",
            "-an",
            "-frames:v",
            "1",
            "-vf",
            "scale=560:208:force_original_aspect_ratio=decrease",
            "-threads",
            "1",
            "-update",
            "1",
        ])
        .arg(&frame)
        .stdin(Stdio::from(source))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    match child.wait_timeout(Duration::from_secs(4))? {
        Some(exit) if exit.success() => Ok(fs::read(frame)?),
        Some(_) => bail!("Could not render media thumbnail"),
        None => {
            let _ = child.kill();
            let _ = child.wait();
            bail!("Media thumbnail timed out");
        }
    }
}

pub fn location() -> Result<Value> {
    let window = active_window()?;
    let address = s(&window, "address");
    if !valid_address(address) {
        bail!("Focus a window before opening clipboard history");
    }
    let cursor: Value = serde_json::from_str(&output(
        command(&["hyprctl", "-j", "cursorpos"]),
        None,
        Duration::from_secs(1),
    )?)?;
    let window_x = window["at"][0].as_f64().unwrap_or(0.);
    let window_y = window["at"][1].as_f64().unwrap_or(0.);
    let width = window["size"][0].as_f64().unwrap_or(0.);
    let height = window["size"][1].as_f64().unwrap_or(0.);
    let pointer = (
        n(&cursor, "x").clamp(window_x, window_x + width.max(0.)),
        n(&cursor, "y").clamp(window_y, window_y + height.max(0.)),
    );
    let (x, top, bottom) =
        crate::caret::position(&window).unwrap_or((pointer.0, pointer.1, pointer.1));
    Ok(json!({"address":address,"x":x,"top":top,"bottom":bottom,"monitor":window["monitor"]}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rich_preview_preserves_formatting_without_active_content() {
        let mimes = [
            "TEXT",
            "text/plain;charset=utf-8",
            "text/html",
            "text/uri-list",
        ];
        let mimes = mimes.map(str::to_owned);
        assert_eq!(
            preferred_formats(&mimes),
            ["text/plain;charset=utf-8", "text/html", "text/uri-list"]
        );
        let description = describe(&vec![
            ("text/plain".into(), b"Example".to_vec()),
            (
                "text/html".into(),
                b"<b>Example</b><img src='file:///tmp/example'><script>hidden</script>".to_vec(),
            ),
        ]);
        assert_eq!(description["kind"], "html");
        assert_eq!(description["html"], "<b>Example</b>");
    }

    #[test]
    fn document_title_does_not_repeat_the_visible_body() {
        let html = b"<html><head><title>Repeated heading</title><style>p { color: red }</style></head><body><article><p><b>Repeated heading</b></p><p>Repeated heading</p></article></body></html>";
        let description = describe(&vec![("text/html".into(), html.to_vec())]);
        assert_eq!(
            description["html"],
            "<p><b>Repeated heading</b></p><p>Repeated heading</p>"
        );
    }

    #[test]
    fn describes_color_links_and_copied_video_files() {
        assert_eq!(describe_text("#0ab8")["swatch"], "#8800aabb");
        assert_eq!(
            describe_text("hsl(120 100% 50% / 50%)")["swatch"],
            "#8000ff00"
        );
        assert_eq!(describe_text("https://example.test/page")["kind"], "link");
        let file = file_description("text/uri-list", b"file:///tmp/My%20Video.mp4").unwrap();
        assert_eq!(file["kind"], "video");
        assert_eq!(file["preview"], "My Video.mp4");
    }

    #[test]
    fn recognizes_standalone_browser_images_in_plain_text_and_html() {
        let markup = br#"<meta http-equiv="content-type" content="text/html; charset=utf-8"><IMG alt="Example &amp; thumbnail" src="https://example.test/preview?x=1&amp;y=2">"#;
        for mime in ["text/plain;charset=utf-8", "text/html"] {
            let contents = vec![(mime.into(), markup.to_vec())];
            let image = remote_image(&contents).unwrap();
            assert_eq!(image.url.as_str(), "https://example.test/preview?x=1&y=2");
            assert_eq!(describe(&contents)["preview"], "Example & thumbnail");
            assert_eq!(describe(&contents)["source"], "example.test");
            let mut with_bitmap = contents;
            with_bitmap.push(("image/png".into(), vec![1]));
            assert!(remote_image(&with_bitmap).is_none());
            assert_eq!(describe(&with_bitmap)["kind"], "image");
            assert_eq!(describe(&with_bitmap)["mime"], "image/png");
            assert_eq!(describe(&with_bitmap)["source"], "example.test");
        }
        for markup in [
            r#"<p>Caption <img src="https://example.test/image"></p>"#,
            r#"<img src="https://example.test/one"><img src="https://example.test/two">"#,
            r#"<img src="file:///tmp/example.png">"#,
        ] {
            assert!(
                remote_image(&vec![("text/html".into(), markup.as_bytes().to_vec())]).is_none()
            );
        }
        let browser_image = vec![(
            "text/html".into(),
            br#"<img src="blob:https://example.test/1">"#.to_vec(),
        )];
        assert!(remote_image(&browser_image).is_none());
        assert_eq!(describe(&browser_image)["kind"], "image");
        assert_eq!(describe(&browser_image)["source"], "example.test");
    }
}

"""Adapters for desktop-owned launcher data; no second file/browser index."""

import configparser
from contextlib import closing
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
import time
from urllib.parse import unquote, urlparse


def variants(text):
    """Physical US/Russian key positions, preserving the original query first."""
    en = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
    ru = "ёйцукенгшщзхъфывапролджэячсмитьбю"
    lower = text.casefold()
    result = [lower]
    if re.search('[а-яё]', lower):
        result.append(lower.translate(str.maketrans(ru, en)))
    elif re.search('[a-z]', lower):
        result.append(lower.translate(str.maketrans(en, ru)))
    return result


def match_score(name, query, extra="", queries=None):
    name = name.casefold()
    best = 99
    for q in queries or variants(query):
        if name == q:
            best = min(best, 0)
        elif name.startswith(q):
            best = min(best, 1)
        elif all(word in name for word in q.split()):
            best = min(best, 2)
        elif all(word in (name + " " + extra.casefold()) for word in q.split()):
            best = min(best, 3)
    return best


def item(kind, identity, name, description="", **data):
    return dict(id=kind + ":" + identity, kind=kind, name=name,
                description=description, **data)


def presentation_key(value):
    return value.replace("\ufe0e", "").replace("\ufe0f", "")


def collapse_character_presentations(rows):
    """Keep one ordinary search row per character, preserving saved choices."""
    result, positions = [], {}
    for row in rows:
        key = presentation_key(row["value"]) if row["kind"] == "character" else row["id"]
        key = (row["kind"], key)
        if key not in positions:
            positions[key] = len(result)
            result.append(row)
            continue
        old = result[positions[key]]
        if (row.get("favorite", False) > old.get("favorite", False)
            or row.get("favorite", False) == old.get("favorite", False)
            and "\ufe0f" in row.get("value", "") and "\ufe0f" not in old.get("value", "")):
            result[positions[key]] = row
    return result


class Characters:
    def __init__(self, cache=None):
        self.records = None
        self.cache = Path(cache) if cache else Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles/hyprland/launcher-characters.json"

    def load(self):
        # Reuse the installed IBus/CLDR catalog, including multi-codepoint emoji
        # and Russian annotations. No network download or private copy needed.
        sources = [Path(f"/usr/share/ibus/dicts/{name}") for name in ("emoji-en.dict", "emoji-ru.dict", "unicode-names.dict")]
        signature = [(str(p), p.stat().st_mtime_ns, p.stat().st_size) for p in sources]
        signature = json.loads(json.dumps(signature))
        try:
            cached = json.loads(self.cache.read_text())
            if cached.get("version") == 2 and cached.get("sources") == signature:
                self.records = cached["records"]
                return
        except (OSError, ValueError, KeyError):
            pass
        import gi
        gi.require_version("IBus", "1.0")
        from gi.repository import IBus
        records = {}
        for locale in ("en", "ru"):
            for entry in IBus.EmojiData.load(f"/usr/share/ibus/dicts/emoji-{locale}.dict") or []:
                value = entry.get_emoji()
                title = entry.get_description() or value
                if value not in records:
                    records[value] = [value, title, ""]
                records[value][2] += " " + title + " " + " ".join(entry.get_annotations() or [])
        for entry in IBus.UnicodeData.load("/usr/share/ibus/dicts/unicode-names.dict") or []:
            code = entry.get_code()
            if len(code) == 1:
                value = code
            elif re.fullmatch(r"\\[uU][0-9a-fA-F]{4,8}", code):
                value = chr(int(code[2:], 16))
            else:
                continue
            name = entry.get_name()
            if name.startswith("<") or not value.isprintable() or value.isspace():
                continue
            records.setdefault(value, [value, name.lower(), entry.get_alias() or ""])
        for value, name in [("¯\\_(ツ)_/¯", "shrug"), ("—", "em dash"), ("–", "en dash"),
                            ("✓", "checkmark"), ("✗", "cross mark"), ("…", "ellipsis")]:
            records.setdefault(value, [value, name, ""])[2] += " " + name
        self.records = list(records.values())
        self.cache.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = self.cache.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": 2, "sources": signature, "records": self.records}, ensure_ascii=False))
        temporary.chmod(0o600)
        temporary.replace(self.cache)

    def search(self, query, explicit=False):
        import unicodedata
        code = re.fullmatch(r"(?:u\+|0x)([0-9a-f]{2,6})", query, re.I)
        if code or explicit and len(query) == 1:
            n = int(code[1], 16) if code else ord(query)
            if n > 0x10FFFF or 0xD800 <= n <= 0xDFFF:
                return []
            value = chr(n)
            return [item("character", f"{n:X}", unicodedata.name(value, "Unnamed character").lower(),
                         f"U+{n:04X}", value=value, glyph=value if value.isprintable() else "␣")]
        if len(query) < 2:
            return []
        if self.records is None:
            self.load()
        matches = []
        queries = variants(query)
        for value, name, aliases in self.records:
            score = match_score(name, query, aliases, queries)
            # Global search is conservative; an explicit character search also
            # matches aliases and annotation keywords.
            if score < (4 if explicit else 3):
                matches.append((score, len(name), value, name))
        matches.sort()
        if not explicit:
            grouped = {}
            for match in matches:
                key = presentation_key(match[2])
                old = grouped.get(key)
                if old is None or match[:2] == old[:2] and "\ufe0f" in match[2] and "\ufe0f" not in old[2]:
                    grouped[key] = match
            matches = sorted(grouped.values())
        return [item("character", "-".join(f"{ord(c):X}" for c in value), name,
                     " ".join(f"U+{ord(c):04X}" for c in value), value=value, glyph=value)
                for _, _, value, name in matches[:24 if explicit else 4]]


def decode_mozlz4(path):
    data = path.read_bytes()
    if len(data) < 12 or data[:8] != b"mozLz40\0":
        raise ValueError("Invalid Mozilla LZ4 file")
    size = int.from_bytes(data[8:12], "little")
    if size > 16 * 1024 * 1024:
        raise ValueError("Search configuration is too large")
    library = ctypes.CDLL(ctypes.util.find_library("lz4"))
    library.LZ4_decompress_safe.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    target = ctypes.create_string_buffer(size)
    count = library.LZ4_decompress_safe(data[12:], target, len(data) - 12, size)
    if count != size:
        raise ValueError("Invalid Mozilla LZ4 payload")
    return json.loads(target.raw)


class Zen:
    def __init__(self, home=None):
        self.home = Path(home or Path.home())
        self.profile = None
        self.launch = []
        self.bookmarks = []
        self.updated = 0
        self.signature = None

    def discover(self):
        roots = [(self.home / ".var/app/app.zen_browser.zen/.zen", ["flatpak", "run", "app.zen_browser.zen"]),
                 (self.home / ".zen", ["zen"]), (self.home / ".config/zen", ["zen"])]
        for root, command in roots:
            config = configparser.ConfigParser()
            config.read(root / "profiles.ini")
            profiles = []
            for section in config.sections():
                if section.startswith("Install") and config.get(section, "Default", fallback=""):
                    profiles.insert(0, root / config[section]["Default"])
                elif section.startswith("Profile") and config.get(section, "Path", fallback=""):
                    path = Path(config[section]["Path"])
                    path = root / path if config.get(section, "IsRelative", fallback="1") == "1" else path
                    profiles.append(path)
            for path in profiles:
                if (path / "places.sqlite").is_file() and shutil.which(command[0]):
                    self.profile, self.launch = path, command
                    return

    def refresh(self):
        if self.profile is None:
            self.discover()
        if not self.profile or time.monotonic() - self.updated < 60:
            return
        self.updated = time.monotonic()
        database = self.profile / "places.sqlite"
        wal = self.profile / "places.sqlite-wal"
        signature = [(p.stat().st_mtime_ns, p.stat().st_size) if p.exists() else None for p in (database, wal)]
        if signature == self.signature:
            return
        # Zen can hold an exclusive SQLite lock. Snapshot DB + WAL into a
        # private directory; recovery and all writes happen only to this copy.
        # Retry a changed snapshot rather than accepting a partial WAL.
        for _ in range(2):
            with tempfile.TemporaryDirectory(prefix="dotfiles-zen-") as temporary:
                for source in (database, wal):
                    if source.exists():
                        shutil.copyfile(source, Path(temporary) / source.name)
                after = [(p.stat().st_mtime_ns, p.stat().st_size) if p.exists() else None for p in (database, wal)]
                if signature != after:
                    signature = after
                    continue
                with closing(sqlite3.connect(Path(temporary) / database.name, timeout=0.1)) as connection:
                    rows = connection.execute("""SELECT COALESCE(b.title, p.title, p.url), p.url
                        FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.type=1""").fetchall()
                self.bookmarks = [(title, url) for title, url in rows if urlparse(url).scheme in ("https", "http")]
                self.signature = signature
                return

    def search(self, query, explicit=False):
        self.refresh()
        if not self.profile:
            return []
        rows = []
        for title, url in self.bookmarks:
            score = match_score(title, query, url)
            if not query and explicit or query and score < 4:
                rows.append((score, title, url))
        rows.sort()
        results = [item("bookmark", url, title, url, uri=url) for _, title, url in rows[:20 if explicit else 4]]
        if urlparse(query).scheme in ("https", "http"):
            results.insert(0, item("bookmark", query, "Open in Zen", query, uri=query))
        # Pass search text to Zen itself. It uses the profile's configured
        # engine, including POST engines and browser-managed search parameters.
        if explicit and query:
            results.append(item("web", query, "Search Zen for “" + query + "”", "Use your Zen search engine", value=query))
        return results

    def open(self, result):
        import subprocess
        if self.profile is None:
            self.discover()
        if not self.profile:
            raise RuntimeError("Your Zen profile is unavailable")
        # A Flatpak profile path is different inside its sandbox. Profiles are
        # shared by name, so use the profile's recorded name with -P.
        config = configparser.ConfigParser()
        config.read(self.profile.parent / "profiles.ini")
        name = next((config[s].get("Name") for s in config.sections()
                     if s.startswith("Profile") and config[s].get("Path") == self.profile.name), None)
        if not name:
            raise RuntimeError("Could not identify the Zen profile")
        command = self.launch + ["-P", name]
        if result["kind"] == "web":
            command += ["--search", result["value"]]
        else:
            command += ["--new-tab", result["uri"]]
        subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


class Files:
    def __init__(self, bus=None):
        self.bus = bus

    def search(self, query, limit=12):
        if query.startswith(("/", "~/", "file://")):
            return self.browse(query, limit), ""
        if len(query) < 3:
            return [], "Type at least three characters to search files"
        from gi.repository import Gio, GLib
        if self.bus is None:
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        def call(method, signature, values):
            return self.bus.call_sync("org.gnome.Nautilus", "/org/gnome/Nautilus/SearchProvider",
                                      "org.gnome.Shell.SearchProvider2", method,
                                      GLib.Variant(signature, values), None,
                                      Gio.DBusCallFlags.NONE, 2200, None).unpack()[0]
        results = []
        for text in variants(query):
            identifiers = call("GetInitialResultSet", "(as)", (text.split(),))
            if not identifiers:
                continue
            for meta in call("GetResultMetas", "(as)", (identifiers[:limit],)):
                uri = meta["id"]
                if not uri.startswith("file://"):
                    continue
                path = Path(unquote(urlparse(uri).path))
                if not path.exists():
                    continue
                results.append(item("file", uri, meta.get("name", path.name),
                                    meta.get("description", str(path.parent)), uri=uri, path=str(path),
                                    directory=path.is_dir(), icon="folder" if path.is_dir() else "text-x-generic"))
            if results:
                break
        return results[:limit], ""

    def browse(self, query, limit):
        if query.startswith("file://"):
            query = unquote(urlparse(query).path)
        path = Path(query).expanduser()
        parent, prefix = (path, "") if query.endswith("/") else (path.parent, path.name)
        if not parent.is_dir():
            return []
        matches = []
        # Directory completion only; never recursively crawl the user's home.
        with os.scandir(parent) as entries:
            for n, entry in enumerate(entries):
                if n >= 10000:
                    break
                if entry.name.startswith(".") and not prefix.startswith("."):
                    continue
                if prefix and not entry.name.casefold().startswith(prefix.casefold()):
                    continue
                matches.append((not entry.is_dir(), entry.name.casefold(), entry.path))
        matches.sort()
        return [item("file", Path(p).as_uri(), Path(p).name, str(parent), uri=Path(p).as_uri(),
                     path=p, directory=not directory, icon="folder" if not directory else "text-x-generic")
                for directory, _, p in matches[:limit]]

#!/usr/bin/env python3
"""Persistent, bounded launcher providers. JSON lines in/out; UI stays in QML."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import warnings
import xml.etree.ElementTree as ET
from urllib.parse import urlparse
from zoneinfo import ZoneInfo, available_timezones

from launcher_sources import Characters, Files, Zen, item, match_score, collapse_character_presentations


STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/hyprland/launcher.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles/hyprland/qalculate"


class History:
    def __init__(self, path=STATE):
        self.path = Path(path)
        self.entries = {}
        try:
            data = json.loads(self.path.read_text())
            if data.get("version") == 1:
                self.entries = data.get("entries", {})
        except (OSError, ValueError):
            pass

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": 1, "entries": self.entries}, ensure_ascii=False))
        temporary.chmod(0o600)
        temporary.replace(self.path)

    def record(self, result, pin=False):
        saved = self.entries.get(result["id"], {})
        saved.update(item=result)
        if pin:
            saved["favorite"] = not saved.get("favorite", False)
        else:
            saved.update(last=time.time(), count=saved.get("count", 0) + 1)
        self.entries[result["id"]] = saved
        keep = sorted(self.entries, key=lambda key: (self.entries[key].get("favorite", False),
                      self.entries[key].get("last", 0)), reverse=True)[:100]
        self.entries = {key: self.entries[key] for key in keep}
        self.save()

    def decorate(self, results):
        return [dict(result, favorite=self.entries.get(result["id"], {}).get("favorite", False),
                     recent=result["id"] in self.entries) for result in results]

    def search(self, query):
        rows = sorted(self.entries.values(), key=lambda e: (not e.get("favorite", False), -e.get("last", 0)))
        return self.decorate([e["item"] for e in rows if (not query or match_score(
            e["item"]["name"], query, e["item"].get("description", "")) < 4)
            and (e["item"]["kind"] != "file" or Path(e["item"].get("path", "")).exists())][:24])


class Calculator:
    def __init__(self, cache=CACHE):
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.executable = shutil.which("qalc")
        self.command = [self.executable] if self.executable else []
        # Silverblue may stage a package without being able to apply it live.
        # A user-local copy of the unmodified RPM payload works immediately.
        portable = Path.home() / ".local/lib/dotfiles/qalculate"
        if not self.command and (portable / "qalc").is_file() and shutil.which("bwrap"):
            self.executable = str(portable / "qalc")
            self.command = ["bwrap", "--ro-bind", "/", "/", "--tmpfs", "/usr/share", "--ro-bind",
                            str(portable / "share"), "/usr/share/qalculate", "--bind", str(self.cache), str(self.cache),
                            "--setenv", "LD_LIBRARY_PATH", str(portable), "--", self.executable]
        self.env = dict(os.environ, LC_ALL="C.UTF-8", QALCULATE_USER_DIR=str(self.cache))
        self.refreshing = False
        self.currencies = set()
        self.currency_names = {}
        self.functions = None
        for data in (Path("/usr/share/qalculate/currencies.xml"), portable / "share/currencies.xml"):
            if data.is_file():
                self.currencies.update(re.findall(r"\b[A-Z]{3}\b", data.read_text()))
                for names in ET.parse(data).iter("names"):
                    if not names.attrib and names.text:
                        aliases = [name.rsplit(":", 1)[-1] for name in names.text.split(",")]
                        code = next((name for name in aliases if name in self.currencies), "")
                        if code:
                            self.currency_names.update((name, code) for name in aliases)
                break
        names = "|".join(re.escape(name) for name in sorted(self.currency_names, key=len, reverse=True))
        self.currency_token = re.compile(rf"(?<![A-Za-z_])(?:{names})(?![A-Za-z_])", re.I)
        number = r"[+−-]?\d+(?:\.\d+)?(?:E[+−-]?\d+)?"
        self.scalar = re.compile(rf"{number}(?:\s*/\s*{number})?\Z")
        # Inspect the engine's formatted quantity, including its unit. Ratios,
        # inverse currencies, and squared currencies must not become money.
        self.money = re.compile(rf"(?:[+−-]?(?P<prefix>{names})\s*{number}|{number}\s*(?P<suffix>{names}))\Z")

    def infer_currency(self, expression, value):
        # Qalculate deliberately keeps money + scalars unevaluated. Only adapt
        # that case; its parser still handles all arithmetic and unit algebra.
        terms = re.split(r"\s+[+−-]\s+", value)
        if (len(terms) < 2 or not any(self.money.fullmatch(term) for term in terms)
                or not any(self.scalar.fullmatch(term) for term in terms)
                or not all(self.money.fullmatch(term) or self.scalar.fullmatch(term) for term in terms)):
            return expression
        conversion = re.search(r"\s+(?:to|in)\s+[^()]+$|\s*(?:->|→)\s*[^()]+$", expression, re.I)
        suffix = expression[conversion.start():] if conversion else ""
        body = expression[:conversion.start()] if conversion else expression
        # Keep Qalculate's forgiving-parenthesis behavior while locating sums.
        balance, missing = 0, 0
        for char in body:
            if char == "(":
                balance += 1
            elif char == ")":
                if balance:
                    balance -= 1
                else:
                    missing += 1
        body = "(" * missing + body + ")" * balance
        codes = {name.casefold(): code for name, code in self.currency_names.items()}
        currencies = [(m.start(), m.end(), codes[m[0].casefold()]) for m in self.currency_token.finditer(body)]
        if not currencies:
            return expression
        pairs, stack = {}, []
        for pos, char in enumerate(body):
            if char == "(":
                stack.append(pos)
            elif char == ")":
                pairs[stack.pop()] = pos
        numbers = list(re.finditer(r"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+−-]?\d+)?", body))
        def walk(start, end):
            while start < end and body[start].isspace(): start += 1
            while end > start and body[end - 1].isspace(): end -= 1
            if start >= end:
                return ""
            if pairs.get(start) == end - 1:
                return "(" + walk(start + 1, end - 1) + ")"
            splits, pos = [], start
            while pos < end:
                if pos in pairs:
                    pos = pairs[pos] + 1
                    continue
                previous = body[start:pos].rstrip()
                if (body[pos] in "+−-" and previous and previous[-1] not in "+−-*/^,;(<>="
                        and not any(m.start() < pos < m.end() for m in numbers)):
                    splits.append(pos)
                pos += 1
            if splits:
                parts = []
                for left, right in zip([start] + [p + 1 for p in splits], splits + [end]):
                    has_currency = any(left <= a < right for a, _, _ in currencies)
                    if (has_currency or not any(start <= a < end for a, _, _ in currencies)
                            or any(sign in body[left:right] for sign in "%‰‱")):
                        parts.append(walk(left, right))
                    else:
                        before = [code for _, b, code in currencies if b <= left]
                        after = [code for a, _, code in currencies if a >= right]
                        code = before[-1] if before else after[0]
                        parts.append(f"({body[left:right].strip()}) {code}")
                return "".join(part + (" " + body[splits[i]] + " " if i < len(splits) else "")
                               for i, part in enumerate(parts))
            # Products and quotients keep scalar factors/divisors. Only inspect
            # their nested groups for sums containing explicit money amounts.
            parts, pos = [], start
            while pos < end:
                if pos in pairs:
                    close = pairs[pos]
                    parts.append("(" + walk(pos + 1, close) + ")")
                    pos = close + 1
                else:
                    parts.append(body[pos]); pos += 1
            return "".join(parts)
        return walk(0, len(body)) + suffix

    def rate_date(self):
        for root in (self.cache, Path("/usr/share/qalculate")):
            for path in (root / "eurofxref-daily.xml", root / "eurofxref-daily.xml.download"):
                try:
                    match = re.search(r"time=['\"]([0-9-]+)", path.read_text())
                    if match:
                        return match[1]
                except OSError:
                    pass
        return "unknown"

    def refresh(self):
        if not self.executable or self.refreshing:
            return
        marker = self.cache / "last-refresh"
        if marker.exists() and time.time() - marker.stat().st_mtime < 86400:
            return
        self.refreshing = True
        def update():
            try:
                result = subprocess.run(self.command + ["-e", "-t", "-s", "save config no"],
                                        input="", text=True, capture_output=True, env=self.env, timeout=12)
                if result.returncode == 0:
                    marker.touch(mode=0o600)
            except (OSError, subprocess.SubprocessError):
                pass
            finally:
                self.refreshing = False
        threading.Thread(target=update, daemon=True).start()

    def evaluate(self, expression):
        if not self.executable:
            return ""
        result = subprocess.run(self.command + ["--defaults", "-t", "-m", "300", "-s", "save config no",
                                 "-s", "save definitions no", "-s", "update exchange rates 0",
                                 "-s", "max decimals 6", "-s", "show ending zeroes no", "--", expression],
                                env=self.env, capture_output=True, text=True, timeout=1.2)
        output = result.stdout.strip()
        if result.returncode or not output or "error:" in output.lower() or len(output) > 240 or "\n" in output:
            return ""
        return output

    def search(self, query):
        # Recognize amount/source/[to]/target without feeding arbitrary words
        # into Qalculate's permissive symbolic parser.
        currency = re.fullmatch(r"([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([a-z]{3})(?:\s+(?:to\s+)?([a-z]{3}))?", query, re.I)
        if currency:
            amount, source, target = currency.groups()
            source = source.upper()
            targets = [target.upper()] if target else [c for c in ("CZK", "USD", "EUR") if c != source]
            if source not in self.currencies or any(c not in self.currencies for c in targets):
                return []
            results = []
            for destination in targets:
                expression = f"{amount} {source} to {destination}"
                value = self.evaluate(expression)
                if value and not any(word in value for word in ("unknown", "aborted", "undefined")):
                    results.append(item("currency", expression, value,
                                        f"{amount} {source} → {destination} · Rates {self.rate_date()}", value=value, rateDate=self.rate_date()))
            return results
        expression = query.removeprefix("=").strip()
        if not expression or re.search(r"[+*/^,−-]\s*$", expression):
            return []
        function = re.match(r"^([\w√]+)\s*\(", expression)
        if function and self.functions is None and self.executable:
            listed = subprocess.run(self.command + ["--list-functions"], env=self.env,
                                    capture_output=True, text=True, timeout=1.2)
            self.functions = set(re.findall(r"[\w√]+", listed.stdout.split("\n\n", 1)[0]))
        likely_math = (re.match(r"^[+−-]?(?:\d|\.\d|\()", expression)
                       or (function and function[1] in (self.functions or set()))
                       or re.match(r"^(?:pi|π|e|tau)\s*[-+*/^]", expression))
        if not query.startswith("=") and (not likely_math or re.fullmatch(r"[+−-]?\d+(?:\.\d+)?", expression)):
            return []
        # Preserve the short target syntax after compound arithmetic too.
        expression = re.sub(r"\b([a-z]{3})\s+([a-z]{3})$", lambda m:
                            f"{m[1]} to {m[2]}" if all(code.upper() in self.currencies for code in m.groups()) else m[0],
                            expression, flags=re.I)
        expression = re.sub(r"\bin\s+([a-z]{3})$", lambda m:
                            f"to {m[1]}" if m[1].upper() in self.currencies else m[0], expression, flags=re.I)
        value = self.evaluate(expression)
        if not value:
            return []
        inferred = self.infer_currency(expression, value)
        if inferred != expression:
            expression = inferred
            value = self.evaluate(expression)
            if not value:
                return []
        monetary = self.money.fullmatch(value) if self.currency_names else None
        def row(text, output):
            return item("currency" if monetary else "calculation", text, output, text,
                        value=output, **({"rateDate": self.rate_date()} if monetary else {}))
        results = [row(query, value)]
        if monetary and not re.search(r"\s+(?:to|in)\s+|->|→", expression, re.I):
            source = self.currency_names[monetary["prefix"] or monetary["suffix"]]
            for destination in ("CZK", "USD", "EUR"):
                if destination == source:
                    continue
                conversion = f"{expression} to {destination}"
                converted = self.evaluate(conversion)
                if converted and converted != value:
                    results.append(row(conversion, converted))
        return results


class Dates:
    def __init__(self, now=None):
        self.now = now or (lambda: datetime.now().astimezone())
        self.zones = None

    def parse(self, text):
        from dateutil.parser import parse, UnknownTimezoneWarning
        text = text.strip().strip('"\'')
        now = self.now()
        if text.casefold() == "now":
            return now
        if text.casefold() in ("today", "tomorrow", "yesterday"):
            return now.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(
                days={"today": 0, "tomorrow": 1, "yesterday": -1}[text.casefold()])
        named_zone = re.search(r"\s+([A-Za-z_]+/[A-Za-z_/]+)$", text)
        if named_zone:
            text = text[:named_zone.start()]
        with warnings.catch_warnings():
            warnings.simplefilter("error", UnknownTimezoneWarning)
            try:
                parsed = parse(text, default=now.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=None), fuzzy=False)
            except UnknownTimezoneWarning as error:
                raise ValueError("Use an IANA timezone such as Europe/Prague or an explicit UTC offset") from error
        if named_zone:
            parsed = parsed.replace(tzinfo=ZoneInfo(named_zone[1]))
        if parsed.tzinfo is None:
            # astimezone() attaches the system's correct offset for this date,
            # rather than reusing today's fixed UTC offset across DST changes.
            parsed = parsed.astimezone()
        return parsed

    def result(self, query, value, description):
        return [item("date", query, value, description, value=value)]

    def search(self, query):
        difference = re.fullmatch(r"(days|time|hours)\s+between\s+(.+?)\s+and\s+(.+)", query, re.I)
        if difference:
            unit, first, second = difference.groups()
            a, b = self.parse(first), self.parse(second)
            clock_only = r"\s*\d{1,2}(?::\d\d)?\s*(?:am|pm)?\s*"
            if b < a and re.fullmatch(clock_only, first, re.I) and re.fullmatch(clock_only, second, re.I):
                b += timedelta(days=1)
            seconds = b.timestamp() - a.timestamp()
            if unit.casefold() == "days":
                days = (b.date() - a.date()).days
                return self.result(query, f"{days:,} " + ("day" if abs(days) == 1 else "days"), f"{a.date()} → {b.date()} · Calendar days, end date excluded")
            hours = seconds / 3600
            minutes = abs(round(seconds / 60))
            value = ("−" if seconds < 0 else "") + f"{minutes // 60:,} hours, {minutes % 60} minutes"
            return self.result(query, value, f"{a.isoformat(' ', timespec='minutes')} → {b.isoformat(' ', timespec='minutes')} · {hours:g} hours")
        addition = re.fullmatch(r"(today|tomorrow|yesterday|\d{4}-\d\d-\d\d)\s*([+-])\s*(\d+)\s*(days?|weeks?|months?|years?)", query, re.I)
        if addition:
            from dateutil.relativedelta import relativedelta
            start, sign, amount, unit = addition.groups()
            delta = int(amount) * (1 if sign == "+" else -1)
            result = self.parse(start) + relativedelta(**{unit.rstrip("s").lower() + "s": delta})
            return self.result(query, result.strftime("%Y-%m-%d"), result.strftime("%A, %d %B %Y"))
        stamp = re.fullmatch(r"(?:unix|timestamp)\s+(-?\d{1,13}|now)", query, re.I)
        if stamp:
            if stamp[1].lower() == "now":
                return self.result(query, str(int(self.now().timestamp())), "Unix timestamp · seconds")
            number = int(stamp[1])
            date = datetime.fromtimestamp(number / 1000 if len(stamp[1].lstrip('-')) == 13 else number, timezone.utc)
            return self.result(query, date.isoformat(), "UTC · Unix timestamp")
        zone = re.fullmatch(r"(?:time|date)\s+(.+)", query, re.I)
        if zone and not zone[1].lower().startswith("between"):
            query_zone = zone[1].replace(" ", "_").casefold()
            if self.zones is None:
                self.zones = sorted(available_timezones())
            aliases = {"utc": "UTC", "gmt": "Etc/GMT", "local": None}
            names = [aliases[query_zone]] if query_zone in aliases else [z for z in self.zones if
                     z.casefold() == query_zone or z.rsplit("/", 1)[-1].casefold() == query_zone][:5]
            return [item("date", query + str(name), self.now().astimezone(ZoneInfo(name) if name else None).strftime("%H:%M"),
                         (name or "Local time") + " · " + self.now().astimezone(ZoneInfo(name) if name else None).strftime("%A, %d %B %Y · %Z"),
                         value=self.now().astimezone(ZoneInfo(name) if name else None).isoformat(timespec="minutes")) for name in names]
        if query.casefold() in ("today", "tomorrow", "yesterday"):
            date = self.parse(query)
            return self.result(query, date.strftime("%Y-%m-%d"), date.strftime("%A, %d %B %Y"))
        return []


class Providers:
    def __init__(self, history=None):
        self.history = history or History()
        self.calculator = Calculator()
        self.dates = Dates()
        self.characters = Characters()
        self.zen = Zen()
        self.files = Files()

    def quick(self, query):
        query = query.strip()[:512]
        if re.fullmatch(r"(?:u\+|0x)[0-9a-f]{2,6}", query, re.I):
            return self.history.decorate(self.characters.search(query)), ""
        if not query:
            results, refreshed = [], {}
            for saved in self.history.search(""):
                text = saved.get("query", "")
                if text and saved["kind"] in ("date", "currency", "calculation"):
                    try:
                        if text not in refreshed:
                            refreshed[text] = self.dates.search(text) or self.calculator.search(text)
                        current = next((r for r in refreshed[text] if r["id"] == saved["id"]), None)
                        if current:
                            saved = dict(current, query=text)
                    except (ValueError, OSError, subprocess.SubprocessError):
                        continue
                results.append(saved)
            return self.history.decorate(collapse_character_presentations(results)), ""
        explicit = re.fullmatch(r"(characters?|chars?|emoji|symbols?|bookmarks?|bm|web|files?|f)(?:\s+(.*))?", query, re.I)
        prefix, text = (explicit[1].lower(), (explicit[2] or "").strip()) if explicit else ("", query)
        results, notice = [], ""
        if prefix in ("file", "files", "f") or query.startswith(("/", "~/", "file://")):
            return [], ""
        if prefix in ("bookmark", "bookmarks", "bm", "web"):
            try:
                results = self.zen.search(text, True)
                if not self.zen.profile:
                    notice = "No Zen profile found"
            except (OSError, ValueError, sqlite3.Error):
                notice = "Zen bookmarks are temporarily unavailable"
        elif prefix:
            if not text:
                text = "smile" if prefix == "emoji" else "arrow"
            results = self.characters.search(text, True)
        else:
            try:
                results = self.dates.search(query)
            except (ValueError, OverflowError, OSError):
                notice = "Use dates such as 2026-11-15 or 15 November 2026, and times such as 09:00"
            if not results and not notice:
                try:
                    results = self.calculator.search(query)
                except (OSError, subprocess.SubprocessError):
                    notice = "Calculation timed out"
            if not results and not notice and len(query) >= 2:
                results += self.characters.search(query)
                try:
                    results += self.zen.search(query)
                except (OSError, ValueError, sqlite3.Error):
                    pass
                saved = self.history.search(query)
                results = saved + results
        unique = {r["id"]: r for r in reversed(results)}
        results = [dict(row, query=row.get("query", query)) for row in reversed(list(unique.values()))]
        if not explicit:
            results = collapse_character_presentations(results)
        return self.history.decorate(results), notice

    def file_query(self, query):
        query = query.strip()
        explicit = re.fullmatch(r"(?:files?|f)(?:\s+(.*))?", query, re.I)
        if explicit:
            return explicit[1] or "", True
        if query.startswith(("/", "~/", "file://")):
            return query, True
        if len(query) < 3 or re.match(r"^(?:[\d=+(\-]|[\w√]+\s*\(|chars?\s|characters?\s|symbols?\s|emoji\s|bm\s|bookmarks?\s|web\s|time\s|days\s|hours\s|date\s|today\b|tomorrow\b|unix\s|timestamp\s)", query, re.I):
            return "", False
        return query, False

    def activate(self, result, action):
        kind = result.get("kind")
        if action == "favorite":
            self.history.record(result, pin=True)
            return "Favorite updated"
        if action == "forget":
            self.history.entries.pop(result["id"], None)
            self.history.save()
            return "Removed from recent items"
        if action in ("copy", "copy-code") or kind in ("character", "currency", "calculation", "arithmetic", "date"):
            value = result.get("value", result.get("uri", result.get("name", "")))
            if action == "copy-code" and kind == "character":
                value = " ".join(f"U+{ord(c):04X}" for c in result["value"])
            if kind == "file":
                value = result["path"]
            subprocess.run(["wl-copy", "--", value], check=True, timeout=2)
        elif kind == "file":
            uri = result["uri"]
            if urlparse(uri).scheme != "file":
                raise ValueError("Expected a local file")
            if action == "reveal":
                from gi.repository import Gio, GLib
                bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
                bus.call_sync("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                              "org.freedesktop.FileManager1", "ShowItems", GLib.Variant("(ass)", ([uri], "")),
                              None, Gio.DBusCallFlags.NONE, 2000, None)
            else:
                subprocess.Popen(["gio", "open", uri], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
        elif kind in ("web", "bookmark"):
            self.zen.open(result)
        elif kind == "app":
            subprocess.Popen([sys.executable, str(Path(__file__).parent.parent / "tools/desktop.py"), "app-launch", result["appId"]],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            raise ValueError("Unknown launcher action")
        self.history.record(result)
        return "Copied" if action == "copy" or kind in ("character", "currency", "calculation", "arithmetic", "date") else "Opened"


def serve():
    providers = Providers()
    lock = threading.Lock()
    latest = [0]
    registry = {}
    def send(data):
        with lock:
            print(json.dumps(data, ensure_ascii=False), flush=True)
    def query(request, include_files=False):
        identity = request["id"]
        if identity != latest[0]:
            return
        text = request.get("query", "")
        section = "files" if include_files else "quick"
        notice, results = "", []
        try:
            if include_files:
                term, explicit = providers.file_query(text)
                if term:
                    results, notice = providers.files.search(term, 24 if explicit else 8)
                    results = providers.history.decorate(results)
                elif explicit:
                    notice = "Search indexed files by name or contents, or type a folder path"
            else:
                providers.calculator.refresh()
                results, notice = providers.quick(text)
        except Exception as error:
            notice = "File search is unavailable" if include_files else "This provider is unavailable"
            print(f"Launcher {section}: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        if identity == latest[0]:
            with lock:
                registry.update({result["id"]: result for result in results})
            send(dict(id=identity, section=section, results=results, notice=notice))
    # Dedicated single-thread queues prevent a slow file provider from blocking
    # local results. Obsolete queued requests are discarded before doing work.
    with ThreadPoolExecutor(max_workers=1) as quick, ThreadPoolExecutor(max_workers=1) as files:
        send({"ready": True, "qalc": bool(providers.calculator.executable)})
        for line in sys.stdin:
            try:
                request = json.loads(line)
                if request.get("op", "query") == "query":
                    latest[0] = request["id"]
                    with lock:
                        registry.clear()
                    quick.submit(query, request)
                    files.submit(query, request, True)
                elif request["op"] == "action":
                    result = registry.get(request["resultId"])
                    # App results are owned by the existing Gio app index.
                    if result is None and request.get("appId"):
                        result = item("app", request["appId"], request.get("name", request["appId"]), appId=request["appId"])
                    if result is None:
                        raise ValueError("Search again before using this result")
                    message = providers.activate(result, request["action"])
                    send(dict(action=True, token=request.get("token"), message=message, resultId=result["id"],
                              favorite=providers.history.entries.get(result["id"], {}).get("favorite", False)))
            except Exception as error:
                send(dict(action=True, error=str(error)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query")
    args = parser.parse_args()
    os.umask(0o077)
    if args.query is not None:
        providers = Providers()
        results, notice = providers.quick(args.query)
        print(json.dumps(dict(results=results, notice=notice), ensure_ascii=False))
    else:
        serve()


if __name__ == "__main__":
    main()

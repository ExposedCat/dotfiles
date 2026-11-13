#!/usr/bin/env python3
"""Read the existing GNOME calendar selection and saved world clocks."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, time, timedelta
import argparse
import json
import subprocess
import threading
from zoneinfo import ZoneInfo


def world_clocks():
    import gi
    gi.require_version("GWeather", "4.0")
    from gi.repository import Gio, GLib, GWeather
    schemas = Gio.SettingsSchemaSource.get_default()
    if schemas.lookup("org.gnome.clocks", True):
        locations = Gio.Settings.new("org.gnome.clocks").get_value("world-clocks")
    else:
        # GNOME Clocks is installed as a Flatpak on this desktop. This command
        # reads its settings only; it does not launch a Clocks window.
        try:
            raw = subprocess.check_output(
                ["/usr/bin/flatpak", "run", "--command=gsettings", "org.gnome.clocks",
                 "get", "org.gnome.clocks", "world-clocks"], text=True, stderr=subprocess.DEVNULL, timeout=4)
            locations = GLib.Variant.parse(GLib.VariantType.new("aa{sv}"), raw, None, None)
        except (OSError, subprocess.SubprocessError, GLib.Error):
            return []
    world = GWeather.Location.get_world()
    clocks = []
    for index in range(locations.n_children()):
        item = locations.get_child_value(index)
        value = item.lookup_value("location", None)
        location = world.deserialize(value) if value else None
        if location and location.get_timezone_str():
            timezone = location.get_timezone_str()
            clocks.append({"name": location.get_name(), "timezone": timezone,
                           "offset": int(datetime.now(ZoneInfo(timezone)).utcoffset().total_seconds())})
    return clocks


def calendar_events(source, start, end):
    from gi.repository import ECal, Gio, GLib, ICalGLib
    cancel = Gio.Cancellable()
    timeout = threading.Timer(8, cancel.cancel)
    timeout.daemon = True
    timeout.start()
    try:
        client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 1, cancel)
        zone = ICalGLib.Timezone.get_builtin_timezone(GLib.TimeZone.new_local().get_identifier())
        if zone:
            client.set_default_timezone(zone)
        entries = []

        def instance(component, begin, finish, *unused):
            if component.get_status() == ICalGLib.PropertyStatus.CANCELLED:
                return True
            begin_epoch = begin.as_timet_with_zone(begin.get_timezone() or zone)
            finish_epoch = finish.as_timet_with_zone(finish.get_timezone() or zone)
            entries.append({"id": str(component.get_uid()) + ":" + str(begin_epoch),
                            "title": (component.get_summary() or "Untitled event")[:500],
                            "start": begin_epoch * 1000, "end": finish_epoch * 1000,
                            "allDay": begin.is_date(), "calendar": source.get_display_name(), "calendarId": source.get_uid()})
            return True

        client.generate_instances_sync(start, end, cancel, instance, None)
        return entries, False
    except GLib.Error:
        return [], True
    finally:
        timeout.cancel()


def day_bounds(selected_day):
    """Local midnights, including 23- and 25-hour DST days."""
    start = datetime.combine(selected_day, time.min)
    end = datetime.combine(selected_day + timedelta(days=1), time.min)
    return int(start.timestamp()), int(end.timestamp())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", type=date.fromisoformat, default=date.today())
    args = parser.parse_args()
    import gi
    gi.require_version("EDataServer", "1.2")
    gi.require_version("ECal", "2.0")
    gi.require_version("ICalGLib", "3.0")
    from gi.repository import EDataServer

    def emit(**data):
        print(json.dumps(data), flush=True)

    try:
        clocks = world_clocks()
    except (ImportError, ValueError):
        clocks = []
    registry = EDataServer.SourceRegistry.new_sync(None)
    sources = [source for source in registry.list_sources("Calendar")
               if registry.check_enabled(source) and source.get_extension("Calendar").get_selected()]
    emit(clocks=clocks, configured=bool(sources), loading=bool(sources))
    start, end = day_bounds(args.date)
    events = {}
    failed = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(calendar_events, source, start, end): source for source in sources}
        for future in as_completed(futures):
            entries, error = future.result()
            if error:
                failed.append(futures[future].get_uid())
            for entry in entries:
                events[entry["calendarId"] + ":" + entry["id"]] = entry
    emit(events=sorted(events.values(), key=lambda e: (not e["allDay"], e["start"], e["title"])),
         loading=False, unavailable=bool(failed), failedCalendars=failed)


if __name__ == "__main__":
    main()

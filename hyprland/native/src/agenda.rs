//! Thin bindings to the same EDS/libical/GWeather C APIs used by the previous helper.
//! Keep all raw pointers in this module; the UI receives only owned JSON values.
use crate::util::*;
use anyhow::{Context, Result, bail};
use chrono::{Local, NaiveDate, NaiveTime, Offset, TimeZone};
use gio::prelude::*;
use glib::translate::*;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char, c_void},
    sync::Arc,
    time::Duration,
};
type Ptr = *mut c_void;
type Error = *mut *mut glib::ffi::GError;
type Text = unsafe extern "C" fn(Ptr) -> *const c_char;
type Pointer = unsafe extern "C" fn(Ptr) -> Ptr;
type Boolean = unsafe extern "C" fn(Ptr) -> i32;
type Callback = unsafe extern "C" fn(Ptr, Ptr, Ptr, Ptr, Ptr, Error) -> i32;
struct Eds {
    _libs: Vec<libloading::Library>,
    registry: unsafe extern "C" fn(Ptr, Error) -> Ptr,
    sources: unsafe extern "C" fn(Ptr, *const c_char) -> *mut glib::ffi::GList,
    enabled: unsafe extern "C" fn(Ptr, Ptr) -> i32,
    extension: unsafe extern "C" fn(Ptr, *const c_char) -> Ptr,
    selected: Boolean,
    name: Text,
    uid: Text,
    connect: unsafe extern "C" fn(Ptr, i32, u32, Ptr, Error) -> Ptr,
    zone: unsafe extern "C" fn(*const c_char) -> Ptr,
    set_zone: unsafe extern "C" fn(Ptr, Ptr),
    generate: unsafe extern "C" fn(Ptr, libc::time_t, libc::time_t, Ptr, Callback, Ptr),
    status: unsafe extern "C" fn(Ptr) -> i32,
    summary: Text,
    component_uid: Text,
    time_zone: Pointer,
    epoch: unsafe extern "C" fn(Ptr, Ptr) -> libc::time_t,
    is_date: Boolean,
}
impl Eds {
    fn load() -> Result<Self> {
        unsafe {
            let server = library("libedataserver-1.2.so.28")
                .or_else(|_| library("libedataserver-1.2.so.27"))?;
            let cal = library("libecal-2.0.so.3")?;
            let ical = library("libical-glib.so.3")?;
            Ok(Self {
                registry: *server.get(b"e_source_registry_new_sync")?,
                sources: *server.get(b"e_source_registry_list_sources")?,
                enabled: *server.get(b"e_source_registry_check_enabled")?,
                extension: *server.get(b"e_source_get_extension")?,
                selected: *server.get(b"e_source_selectable_get_selected")?,
                name: *server.get(b"e_source_get_display_name")?,
                uid: *server.get(b"e_source_get_uid")?,
                connect: *cal.get(b"e_cal_client_connect_sync")?,
                set_zone: *cal.get(b"e_cal_client_set_default_timezone")?,
                generate: *cal.get(b"e_cal_client_generate_instances_sync")?,
                zone: *ical.get(b"i_cal_timezone_get_builtin_timezone")?,
                status: *ical.get(b"i_cal_component_get_status")?,
                summary: *ical.get(b"i_cal_component_get_summary")?,
                component_uid: *ical.get(b"i_cal_component_get_uid")?,
                time_zone: *ical.get(b"i_cal_time_get_timezone")?,
                epoch: *ical.get(b"i_cal_time_as_timet_with_zone")?,
                is_date: *ical.get(b"i_cal_time_is_date")?,
                _libs: vec![server, cal, ical],
            })
        }
    }
}
unsafe fn text(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
    }
}
struct Object(Ptr);
impl Drop for Object {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                glib::gobject_ffi::g_object_unref(self.0.cast());
            }
        }
    }
}
fn ffi_error(error: *mut glib::ffi::GError) -> anyhow::Error {
    if error.is_null() {
        anyhow::anyhow!("Calendar operation failed")
    } else {
        let e: glib::Error = unsafe { from_glib_full(error) };
        e.into()
    }
}
struct Instances<'a> {
    api: &'a Eds,
    zone: Ptr,
    calendar: String,
    uid: String,
    events: Vec<Value>,
}
unsafe extern "C" fn instance(
    component: Ptr,
    start: Ptr,
    end: Ptr,
    data: Ptr,
    _cancel: Ptr,
    _error: Error,
) -> i32 {
    // Never unwind across a C callback boundary.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let state = &mut *(data as *mut Instances<'_>);
        let api = state.api;
        if (api.status)(component) == 10905 {
            return;
        }
        let zone = (api.time_zone)(start);
        let zone = if zone.is_null() { state.zone } else { zone };
        let begin = (api.epoch)(start, zone);
        let end_zone = (api.time_zone)(end);
        let finish = (api.epoch)(
            end,
            if end_zone.is_null() {
                state.zone
            } else {
                end_zone
            },
        );
        let title = text((api.summary)(component));
        state.events.push(json!({"id":format!("{}:{begin}",text((api.component_uid)(component))),"title":if title.is_empty(){"Untitled event".into()}else{title.chars().take(500).collect::<String>()},"start":begin.saturating_mul(1000),"end":finish.saturating_mul(1000),"allDay":(api.is_date)(start)!=0,"calendar":state.calendar,"calendarId":state.uid}));
    }));
    if result.is_ok() { 1 } else { 0 }
}
fn events(api: &Eds, source: usize, start: i64, end: i64) -> Result<Vec<Value>> {
    let cancel = gio::Cancellable::new();
    let (tx, rx) = std::sync::mpsc::channel();
    let canceller = cancel.clone();
    let timer = std::thread::spawn(move || {
        if rx.recv_timeout(Duration::from_secs(8)).is_err() {
            canceller.cancel();
        }
    });
    let outcome = (|| unsafe {
        let source = source as Ptr;
        let mut error = std::ptr::null_mut();
        let client = Object((api.connect)(
            source,
            0,
            1,
            cancel.as_ptr() as Ptr,
            &mut error,
        ));
        if client.0.is_null() {
            return Err(ffi_error(error));
        }
        let id = glib::TimeZone::local().identifier();
        let id = CString::new(id.as_str())?;
        let zone = (api.zone)(id.as_ptr());
        if !zone.is_null() {
            (api.set_zone)(client.0, zone);
        }
        let mut data = Instances {
            api,
            zone,
            calendar: text((api.name)(source)),
            uid: text((api.uid)(source)),
            events: vec![],
        };
        (api.generate)(
            client.0,
            start,
            end,
            cancel.as_ptr() as Ptr,
            instance,
            &mut data as *mut _ as Ptr,
        );
        if cancel.is_cancelled() {
            bail!("Calendar request timed out");
        }
        Ok(data.events)
    })();
    let _ = tx.send(());
    let _ = timer.join();
    outcome
}
fn clocks() -> Result<Vec<Value>> {
    let schemas = gio::SettingsSchemaSource::default().context("No GSettings schemas")?;
    let locations = if schemas.lookup("org.gnome.clocks", true).is_some() {
        gio::Settings::new("org.gnome.clocks").value("world-clocks")
    } else {
        let text = output(
            command(&[
                "/usr/bin/flatpak",
                "run",
                "--command=gsettings",
                "org.gnome.clocks",
                "get",
                "org.gnome.clocks",
                "world-clocks",
            ]),
            None,
            Duration::from_secs(4),
        )?;
        glib::Variant::parse(Some(glib::VariantTy::new("aa{sv}")?), &text)?
    };
    unsafe {
        let lib = library("libgweather-4.so.0")?;
        let world: libloading::Symbol<unsafe extern "C" fn() -> Ptr> =
            lib.get(b"gweather_location_get_world")?;
        let deserialize: libloading::Symbol<
            unsafe extern "C" fn(Ptr, *mut glib::ffi::GVariant) -> Ptr,
        > = lib.get(b"gweather_location_deserialize")?;
        let name: libloading::Symbol<Text> = lib.get(b"gweather_location_get_name")?;
        let zone: libloading::Symbol<Text> = lib.get(b"gweather_location_get_timezone_str")?;
        let world = Object(world());
        let mut result = vec![];
        for i in 0..locations.n_children() {
            let values = locations
                .child_value(i)
                .get::<HashMap<String, glib::Variant>>()
                .unwrap_or_default();
            if let Some(value) = values.get("location") {
                let location = Object(deserialize(world.0, value.to_glib_none().0));
                if location.0.is_null() {
                    continue;
                }
                let zone = text(zone(location.0));
                if let Ok(tz) = zone.parse::<chrono_tz::Tz>() {
                    let now = chrono::Utc::now().with_timezone(&tz);
                    result.push(json!({"name":text(name(location.0)),"timezone":zone,"offset":now.offset().fix().local_minus_utc()}));
                }
            }
        }
        Ok(result)
    }
}
pub fn main(args: &[String]) -> Result<()> {
    if args.first().is_some_and(|arg| arg == "--check-libraries") {
        let _api = Eds::load()?;
        let _weather = library("libgweather-4.so.0")?;
        return emit(&json!({"available":true}));
    }
    let selected = if args.first().is_some_and(|a| a == "--date") {
        NaiveDate::parse_from_str(arg(args, 1)?, "%Y-%m-%d")?
    } else {
        Local::now().date_naive()
    };
    let start = Local
        .from_local_datetime(&selected.and_time(NaiveTime::MIN))
        .earliest()
        .context("Invalid local midnight")?
        .timestamp();
    let end = Local
        .from_local_datetime(
            &selected
                .succ_opt()
                .context("Date is out of range")?
                .and_time(NaiveTime::MIN),
        )
        .earliest()
        .context("Invalid local midnight")?
        .timestamp();
    let clocks = clocks().unwrap_or_default();
    let api = Arc::new(Eds::load()?);
    let registry = unsafe {
        let mut error = std::ptr::null_mut();
        let object = Object((api.registry)(std::ptr::null_mut(), &mut error));
        if object.0.is_null() {
            return Err(ffi_error(error));
        }
        object
    };
    let mut sources = vec![];
    unsafe {
        let list = (api.sources)(registry.0, c"Calendar".as_ptr());
        let mut node = list;
        while !node.is_null() {
            let source = Object((*node).data);
            let extension = (api.extension)(source.0, c"Calendar".as_ptr());
            if (api.enabled)(registry.0, source.0) != 0
                && !extension.is_null()
                && (api.selected)(extension) != 0
            {
                sources.push(source);
            }
            node = (*node).next;
        }
        glib::ffi::g_list_free(list);
    }
    emit(&json!({"clocks":clocks,"configured":!sources.is_empty(),"loading":!sources.is_empty()}))?;
    let mut all = HashMap::new();
    let mut failed = vec![];
    for batch in sources.chunks(6) {
        let results = std::thread::scope(|scope| {
            let jobs: Vec<_> = batch
                .iter()
                .map(|source| {
                    let pointer = source.0 as usize;
                    let api = api.clone();
                    scope.spawn(move || events(&api, pointer, start, end))
                })
                .collect();
            jobs.into_iter()
                .map(|j| {
                    j.join()
                        .map_err(|_| anyhow::anyhow!("Calendar worker failed"))?
                })
                .collect::<Vec<_>>()
        });
        for (source, result) in batch.iter().zip(results) {
            match result {
                Ok(entries) => {
                    for entry in entries {
                        all.insert(
                            format!("{}:{}", s(&entry, "calendarId"), s(&entry, "id")),
                            entry,
                        );
                    }
                }
                Err(e) => {
                    eprintln!("Calendar: {e:#}");
                    failed.push(unsafe { text((api.uid)(source.0)) });
                }
            }
        }
    }
    let mut events: Vec<_> = all.into_values().collect();
    events.sort_by(|a, b| {
        (b["allDay"] == true)
            .cmp(&(a["allDay"] == true))
            .then(n(a, "start").total_cmp(&n(b, "start")))
            .then(s(a, "title").cmp(s(b, "title")))
    });
    emit(
        &json!({"events":events,"loading":false,"unavailable":!failed.is_empty(),"failedCalendars":failed}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn real_libical_callback_owns_strings_and_preserves_dates() {
        unsafe {
            let api = Eds::load().unwrap();
            let lib = library("libical-glib.so.3").unwrap();
            let component: libloading::Symbol<unsafe extern "C" fn(*const c_char) -> Ptr> =
                lib.get(b"i_cal_component_new_from_string").unwrap();
            let time: libloading::Symbol<unsafe extern "C" fn(*const c_char) -> Ptr> =
                lib.get(b"i_cal_time_new_from_string").unwrap();
            let component=Object(component(c"BEGIN:VEVENT\r\nUID:fixture\r\nSUMMARY:Native calendar fixture\r\nDTSTART:20261116T090000Z\r\nDTEND:20261116T100000Z\r\nEND:VEVENT\r\n".as_ptr()));
            assert!(!component.0.is_null());
            let start = Object(time(c"20261116T090000Z".as_ptr()));
            let end = Object(time(c"20261116T100000Z".as_ptr()));
            let mut data = Instances {
                api: &api,
                zone: (api.zone)(c"UTC".as_ptr()),
                calendar: "Fixture".into(),
                uid: "fixture-source".into(),
                events: vec![],
            };
            assert_eq!(
                instance(
                    component.0,
                    start.0,
                    end.0,
                    &mut data as *mut _ as Ptr,
                    std::ptr::null_mut(),
                    std::ptr::null_mut()
                ),
                1
            );
            assert_eq!(data.events[0]["title"], "Native calendar fixture");
            assert_eq!(data.events[0]["calendarId"], "fixture-source");
            assert_eq!(
                data.events[0]["end"].as_i64().unwrap() - data.events[0]["start"].as_i64().unwrap(),
                3_600_000
            );
            assert_eq!(data.events[0]["allDay"], false);
        }
    }
}

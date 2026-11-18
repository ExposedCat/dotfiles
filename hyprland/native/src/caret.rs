use gio::{DBusCallFlags, DBusConnection, DBusConnectionFlags};
use glib::variant::{ObjectPath, ToVariant};
use serde_json::Value;
use std::{
    collections::{HashSet, VecDeque},
    time::{Duration, Instant},
};

const ROOT: &str = "/org/a11y/atspi/accessible/root";
const ACCESSIBLE: &str = "org.a11y.atspi.Accessible";
const TEXT: &str = "org.a11y.atspi.Text";
const COMPONENT: &str = "org.a11y.atspi.Component";
const FOCUSED: u32 = 1 << 12;
const SHOWING: u32 = 1 << 25;
const SCREEN: u32 = 0;
const WINDOW: u32 = 1;
type Node = (String, ObjectPath);
type Rect = (i32, i32, i32, i32);

struct Lookup {
    bus: DBusConnection,
    deadline: Instant,
}

impl Lookup {
    fn call(
        &self,
        node: &Node,
        interface: &str,
        method: &str,
        args: Option<&glib::Variant>,
    ) -> Option<glib::Variant> {
        let remaining = self.deadline.checked_duration_since(Instant::now())?;
        self.bus
            .call_sync(
                Some(&node.0),
                node.1.as_str(),
                interface,
                method,
                args,
                None,
                DBusCallFlags::NONE,
                remaining.as_millis().clamp(1, 85) as i32,
                gio::Cancellable::NONE,
            )
            .ok()
    }

    fn children(&self, node: &Node) -> Vec<Node> {
        self.call(node, ACCESSIBLE, "GetChildren", None)
            .and_then(|result| result.get::<(Vec<Node>,)>())
            .map(|tuple| tuple.0)
            .unwrap_or_default()
    }

    fn pid(&self, name: &str) -> Option<u64> {
        let dbus = (
            "org.freedesktop.DBus".into(),
            ObjectPath::try_from("/org/freedesktop/DBus").ok()?,
        );
        let result = self.call(
            &dbus,
            "org.freedesktop.DBus",
            "GetConnectionUnixProcessID",
            Some(&(name,).to_variant()),
        )?;
        Some(u64::from(result.get::<(u32,)>()?.0))
    }

    fn extents(&self, node: &Node, offset: i32, coords: u32) -> Option<Rect> {
        let character = |offset| {
            let result = self.call(
                node,
                TEXT,
                "GetCharacterExtents",
                Some(&(offset, coords).to_variant()),
            )?;
            result
                .get::<Rect>()
                .filter(|rect| rect.3 > 0 && rect.2 >= 0)
        };
        if let Some(rect) = character(offset) {
            return Some(rect);
        }
        // At end-of-text some toolkits only expose the preceding glyph.
        if offset > 0
            && let Some((x, y, width, height)) = character(offset - 1)
        {
            return Some((x.saturating_add(width), y, 0, height));
        }
        // Empty editors generally only expose their component rectangle.
        let result = self.call(node, COMPONENT, "GetExtents", Some(&(coords,).to_variant()))?;
        let ((x, y, _, height),) = result.get::<(Rect,)>()?;
        (height > 0).then_some((
            x.saturating_add(6),
            y.saturating_add(3),
            0,
            (height - 6).clamp(1, 24),
        ))
    }

    fn caret(&self, node: &Node, window: &Value) -> Option<(f64, f64, f64)> {
        let result = self.call(
            node,
            "org.freedesktop.DBus.Properties",
            "Get",
            Some(&(TEXT, "CaretOffset").to_variant()),
        )?;
        let offset = result.get::<(glib::Variant,)>()?.0.get::<i32>()?;
        if offset < 0 {
            return None;
        }
        let x = window["at"][0].as_f64()?;
        let y = window["at"][1].as_f64()?;
        let width = window["size"][0].as_f64()?;
        let height = window["size"][1].as_f64()?;
        let screen = self.extents(node, offset, SCREEN);
        let local = self.extents(node, offset, WINDOW);
        let valid = |x0: f64, y0: f64| {
            x0 >= x - 4. && x0 <= x + width + 4. && y0 >= y - 4. && y0 <= y + height + 4.
        };
        // GTK on Wayland may return window-relative values for both queries.
        if let Some((left, top, _, line)) = screen
            && (screen != local || window["xwayland"] == true)
            && valid(f64::from(left), f64::from(top))
        {
            return Some((left.into(), top.into(), f64::from(top) + f64::from(line)));
        }
        let (left, top, _, line) = local?;
        let (left, top) = (x + f64::from(left), y + f64::from(top));
        valid(left, top).then_some((left, top, top + f64::from(line)))
    }
}

pub fn position(window: &Value) -> Option<(f64, f64, f64)> {
    let pid = window["pid"].as_u64()?;
    let session = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE).ok()?;
    let result = session
        .call_sync(
            Some("org.a11y.Bus"),
            "/org/a11y/bus",
            "org.a11y.Bus",
            "GetAddress",
            None,
            None,
            DBusCallFlags::NONE,
            100,
            gio::Cancellable::NONE,
        )
        .ok()?;
    let (address,) = result.get::<(String,)>()?;
    let bus = DBusConnection::for_address_sync(
        &address,
        DBusConnectionFlags::AUTHENTICATION_CLIENT | DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
        None,
        gio::Cancellable::NONE,
    )
    .ok()?;
    let lookup = Lookup {
        bus,
        deadline: Instant::now() + Duration::from_millis(300),
    };
    let registry = (
        "org.a11y.atspi.Registry".into(),
        ObjectPath::try_from(ROOT).ok()?,
    );
    let apps = lookup.children(&registry);
    let mut queue: VecDeque<_> = apps
        .into_iter()
        .filter(|app| lookup.pid(&app.0) == Some(pid))
        .map(|app| (app, 0))
        .collect();
    let mut visited = HashSet::new();
    while let Some((node, depth)) = queue.pop_front() {
        if Instant::now() >= lookup.deadline || visited.len() >= 400 {
            break;
        }
        if !visited.insert(node.clone()) {
            continue;
        }
        let states = lookup
            .call(&node, ACCESSIBLE, "GetState", None)
            .and_then(|reply| reply.get::<(Vec<u32>,)>())
            .and_then(|reply| reply.0.first().copied())
            .unwrap_or(0);
        if states & FOCUSED != 0
            && let Some(position) = lookup.caret(&node, window)
        {
            return Some(position);
        }
        if depth < 2 || states & SHOWING != 0 {
            for child in lookup.children(&node) {
                if child.0 == node.0 {
                    queue.push_back((child, depth + 1));
                }
            }
        }
    }
    None
}

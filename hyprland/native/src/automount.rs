//! GNOME-style media policy, using the same GIO/GVfs volume monitor.
use crate::util::{Lock, emit, runtime};
use anyhow::{Context, Result, bail};
use gio::prelude::*;
use glib::variant::ToVariant;
use serde_json::json;
use std::{
    cell::{Cell, RefCell},
    collections::{HashMap, HashSet},
    env,
    rc::Rc,
    time::Duration,
};

#[derive(Clone, Copy)]
struct Policy {
    enabled: bool,
    active: bool,
    locked: bool,
}

#[derive(Clone, Copy)]
struct VolumeState {
    local: bool,
    automatic: bool,
    mountable: bool,
    mounted: bool,
    handled: bool,
}

fn skip_reason(policy: Policy, volume: VolumeState) -> Option<&'static str> {
    if !policy.enabled {
        Some("disabled")
    } else if !policy.active || policy.locked {
        Some("session-inactive-or-locked")
    } else if volume.mounted || volume.handled {
        Some("mounted-or-handled")
    } else if !volume.local || !volume.automatic || !volume.mountable {
        Some("not-an-automountable-local-volume")
    } else {
        None
    }
}

struct Automounter {
    monitor: gio::VolumeMonitor,
    settings: gio::Settings,
    session: gio::DBusProxy,
    pending: RefCell<HashMap<String, gio::Cancellable>>,
    handled: RefCell<HashSet<String>>,
}

impl Automounter {
    fn policy(&self) -> Policy {
        Policy {
            enabled: self.settings.boolean("automount"),
            active: self
                .session
                .cached_property("Active")
                .and_then(|v| v.get())
                .unwrap_or(false),
            // Fail closed if logind cannot report the lock state.
            locked: self
                .session
                .cached_property("LockedHint")
                .and_then(|v| v.get())
                .unwrap_or(true),
        }
    }

    fn device(volume: &gio::Volume) -> Option<String> {
        volume.identifier("unix-device").map(|v| v.to_string())
    }

    fn state(&self, volume: &gio::Volume) -> VolumeState {
        let device = Self::device(volume);
        VolumeState {
            local: volume.identifier("class").as_deref() == Some("device")
                && device.as_deref().is_some_and(|d| d.starts_with("/dev/")),
            automatic: volume.should_automount(),
            mountable: volume.can_mount(),
            mounted: volume.get_mount().is_some(),
            handled: device.is_some_and(|d| self.handled.borrow().contains(&d)),
        }
    }

    fn scan(self: &Rc<Self>) {
        for volume in self.monitor.volumes() {
            self.mount(&volume, false);
        }
    }

    fn mount(self: &Rc<Self>, volume: &gio::Volume, hotplug: bool) {
        let Some(device) = Self::device(volume) else {
            return;
        };
        // Remember mounted/attempted volumes until they are physically removed.
        // An explicit unmount must survive later unlock/session notifications.
        if volume.get_mount().is_some() {
            self.handled.borrow_mut().insert(device);
            return;
        }
        if skip_reason(self.policy(), self.state(volume)).is_some() {
            return;
        }
        self.handled.borrow_mut().insert(device.clone());
        let cancellable = gio::Cancellable::new();
        self.pending
            .borrow_mut()
            .insert(device.clone(), cancellable.clone());
        let timeout_cancel = cancellable.clone();
        glib::timeout_add_local_once(Duration::from_secs(30), move || timeout_cancel.cancel());
        let this = self.clone();
        let mounted_volume = volume.clone();
        let completion_cancel = cancellable.clone();
        // No password dialogs or software autorun from a background service.
        // Encrypted drives can be explicitly unlocked in Files.
        volume.mount(
            gio::MountMountFlags::NONE,
            gio::MountOperation::NONE,
            Some(&cancellable),
            move |result| {
                if this.pending.borrow().get(&device) == Some(&completion_cancel) {
                    this.pending.borrow_mut().remove(&device);
                }
                match result {
                    Ok(()) => {
                        eprintln!("Automounted {} ({device})", mounted_volume.name());
                        let policy = this.policy();
                        if hotplug
                            && policy.active
                            && !policy.locked
                            && this.settings.boolean("automount-open")
                            && !this.settings.boolean("autorun-never")
                            && let Some(mount) = mounted_volume.get_mount()
                        {
                            gio::AppInfo::launch_default_for_uri_async(
                                &mount.root().uri(),
                                gio::AppLaunchContext::NONE,
                                gio::Cancellable::NONE,
                                |result| {
                                    if let Err(e) = result {
                                        eprintln!("Opening mounted drive: {e}");
                                    }
                                },
                            );
                        }
                    }
                    Err(e) => eprintln!(
                        "Could not automount {} ({device}): {e}; open Files to mount or unlock it",
                        mounted_volume.name()
                    ),
                }
            },
        );
    }
}

pub(crate) fn session_proxy() -> Result<gio::DBusProxy> {
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)?;
    // User services can outlive the launching shell and do not always inherit
    // XDG_SESSION_ID. logind's Display identifies this user's graphical session.
    let id = if let Ok(id) = env::var("XDG_SESSION_ID") {
        id
    } else {
        let user = bus.call_sync(
            Some("org.freedesktop.login1"),
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "GetUser",
            Some(&(unsafe { libc::getuid() },).to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            3000,
            gio::Cancellable::NONE,
        )?;
        let path = user.child_value(0);
        let display = bus.call_sync(
            Some("org.freedesktop.login1"),
            path.str().context("Invalid logind user path")?,
            "org.freedesktop.DBus.Properties",
            "Get",
            Some(&("org.freedesktop.login1.User", "Display").to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            3000,
            gio::Cancellable::NONE,
        )?;
        let display = display
            .child_value(0)
            .as_variant()
            .context("Missing logind display session")?;
        display
            .child_value(0)
            .get::<String>()
            .filter(|s| !s.is_empty())
            .context("No graphical session is associated with this user")?
    };
    let reply = bus.call_sync(
        Some("org.freedesktop.login1"),
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "GetSession",
        Some(&(id,).to_variant()),
        None,
        gio::DBusCallFlags::NONE,
        3000,
        gio::Cancellable::NONE,
    )?;
    let path = reply
        .child_value(0)
        .str()
        .context("Invalid logind session path")?
        .to_owned();
    Ok(gio::DBusProxy::new_sync(
        &bus,
        gio::DBusProxyFlags::DO_NOT_AUTO_START,
        None,
        Some("org.freedesktop.login1"),
        &path,
        "org.freedesktop.login1.Session",
        gio::Cancellable::NONE,
    )?)
}

pub fn run(check: bool) -> Result<()> {
    if !check
        && !env::var("XDG_CURRENT_DESKTOP")
            .unwrap_or_default()
            .split(':')
            .any(|s| s == "Hyprland")
    {
        bail!("Automount must run inside the Hyprland graphical session");
    }
    let state = Rc::new(Automounter {
        monitor: gio::VolumeMonitor::get(),
        settings: gio::Settings::new("org.gnome.desktop.media-handling"),
        session: session_proxy()?,
        pending: RefCell::new(HashMap::new()),
        handled: RefCell::new(HashSet::new()),
    });
    if check {
        let policy = state.policy();
        return emit(
            &json!({"automount":policy.enabled,"active":policy.active,"locked":policy.locked,
            "volumes":state.monitor.volumes().iter().map(|volume| json!({
                "name":volume.name().as_str(),"device":Automounter::device(volume),
                "mounted":volume.get_mount().is_some(),
                "skip":skip_reason(policy,state.state(volume))
            })).collect::<Vec<_>>()}),
        );
    }
    let _lock = Lock::acquire(&runtime()?.join("dotfiles-hyprland-automount.lock"), true)?;
    let this = state.clone();
    state
        .monitor
        .connect_volume_added(move |_, volume| this.mount(volume, true));
    let this = state.clone();
    state.monitor.connect_volume_removed(move |_, volume| {
        if let Some(device) = Automounter::device(volume) {
            this.handled.borrow_mut().remove(&device);
            if let Some(cancel) = this.pending.borrow_mut().remove(&device) {
                cancel.cancel();
            }
        }
    });
    let this = state.clone();
    state
        .settings
        .connect_changed(Some("automount"), move |_, _| {
            if this.policy().enabled {
                this.scan();
            } else {
                for cancel in this.pending.borrow().values() {
                    cancel.cancel();
                }
            }
        });
    let this = state.clone();
    let initial = state.policy();
    let was_ready = Cell::new(initial.active && !initial.locked);
    state
        .session
        .connect_local("g-properties-changed", false, move |_| {
            let policy = this.policy();
            let resumed = !was_ready.replace(policy.active && !policy.locked);
            if !policy.active || policy.locked {
                for cancel in this.pending.borrow().values() {
                    cancel.cancel();
                }
            } else if resumed {
                this.scan();
            }
            None
        });
    state.scan();
    eprintln!("Removable-volume automount ready; following GNOME media-handling settings");
    let main_loop = glib::MainLoop::new(None, false);
    for signal in [libc::SIGTERM, libc::SIGINT] {
        let main_loop = main_loop.clone();
        glib_unix::unix_signal_add_local_once(signal, move || main_loop.quit());
    }
    main_loop.run();
    for cancel in state.pending.borrow().values() {
        cancel.cancel();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    const POLICY: Policy = Policy {
        enabled: true,
        active: true,
        locked: false,
    };
    const USB: VolumeState = VolumeState {
        local: true,
        automatic: true,
        mountable: true,
        mounted: false,
        handled: false,
    };

    #[test]
    fn usb_mounts_but_internal_and_network_volumes_do_not() {
        assert!(skip_reason(POLICY, USB).is_none());
        assert!(
            skip_reason(
                POLICY,
                VolumeState {
                    automatic: false,
                    ..USB
                }
            )
            .is_some()
        );
        assert!(
            skip_reason(
                POLICY,
                VolumeState {
                    local: false,
                    ..USB
                }
            )
            .is_some()
        );
    }
    #[test]
    fn disabled_locked_and_inactive_sessions_do_not_mount() {
        for policy in [
            Policy {
                enabled: false,
                ..POLICY
            },
            Policy {
                active: false,
                ..POLICY
            },
            Policy {
                locked: true,
                ..POLICY
            },
        ] {
            assert!(skip_reason(policy, USB).is_some());
        }
    }
    #[test]
    fn mounted_handled_and_unmountable_volumes_are_left_alone() {
        for volume in [
            VolumeState {
                mounted: true,
                ..USB
            },
            VolumeState {
                handled: true,
                ..USB
            },
            VolumeState {
                mountable: false,
                ..USB
            },
        ] {
            assert!(skip_reason(POLICY, volume).is_some());
        }
    }
}

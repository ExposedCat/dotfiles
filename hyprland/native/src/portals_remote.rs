use crate::{
    portals::{Dialog, PATH, REQUEST, app_metadata, is_portal_frontend},
    util::*,
};
use anyhow::{Context, Result, bail};
use glib::{Variant, variant::ToVariant};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    env,
    ffi::{CStr, CString, c_char, c_int, c_void},
    fs::File,
    io::{Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd},
        unix::net::UnixStream,
    },
    ptr,
    rc::Rc,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use wl_clipboard_rs::{
    copy::{MimeSource, MimeType as CopyMimeType, Options as CopyOptions, Source},
    paste::{self, ClipboardType as PasteClipboardType, MimeType as PasteMimeType, Seat},
    watch::{ClipboardEvent, ClipboardType as WatchClipboardType, Watcher},
};

const DEVICE_KEYBOARD: u32 = 1;
const DEVICE_POINTER: u32 = 2;
const AVAILABLE_DEVICES: u32 = DEVICE_KEYBOARD | DEVICE_POINTER;
const MAX_CLIPBOARD_BYTES: usize = 64 * 1024 * 1024;
const MAX_MIME_TYPES: usize = 16;

const XML: &str = r#"<node>
  <interface name="org.freedesktop.impl.portal.RemoteDesktop">
    <property name="AvailableDeviceTypes" type="u" access="read"/>
    <property name="version" type="u" access="read"/>
    <method name="CreateSession">
      <arg type="o" name="handle" direction="in"/>
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="SelectDevices">
      <arg type="o" name="handle" direction="in"/>
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="Start">
      <arg type="o" name="handle" direction="in"/>
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="NotifyPointerMotion">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="d" name="dx" direction="in"/>
      <arg type="d" name="dy" direction="in"/>
    </method>
    <method name="NotifyPointerMotionAbsolute">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="stream" direction="in"/>
      <arg type="d" name="x" direction="in"/>
      <arg type="d" name="y" direction="in"/>
    </method>
    <method name="NotifyPointerButton">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="i" name="button" direction="in"/>
      <arg type="u" name="state" direction="in"/>
    </method>
    <method name="NotifyPointerAxis">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="d" name="dx" direction="in"/>
      <arg type="d" name="dy" direction="in"/>
    </method>
    <method name="NotifyPointerAxisDiscrete">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="axis" direction="in"/>
      <arg type="i" name="steps" direction="in"/>
    </method>
    <method name="NotifyKeyboardKeycode">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="i" name="keycode" direction="in"/>
      <arg type="u" name="state" direction="in"/>
    </method>
    <method name="NotifyKeyboardKeysym">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="i" name="keysym" direction="in"/>
      <arg type="u" name="state" direction="in"/>
    </method>
    <method name="NotifyTouchDown">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="stream" direction="in"/>
      <arg type="u" name="slot" direction="in"/>
      <arg type="d" name="x" direction="in"/>
      <arg type="d" name="y" direction="in"/>
    </method>
    <method name="NotifyTouchMotion">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="stream" direction="in"/>
      <arg type="u" name="slot" direction="in"/>
      <arg type="d" name="x" direction="in"/>
      <arg type="d" name="y" direction="in"/>
    </method>
    <method name="NotifyTouchUp">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="slot" direction="in"/>
    </method>
    <method name="ConnectToEIS">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="h" name="fd" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.impl.portal.Clipboard">
    <property name="version" type="u" access="read"/>
    <method name="RequestClipboard">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
    </method>
    <method name="SetSelection">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
    </method>
    <method name="SelectionWrite">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="u" name="serial" direction="in"/>
      <arg type="h" name="fd" direction="out"/>
    </method>
    <method name="SelectionWriteDone">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="u" name="serial" direction="in"/>
      <arg type="b" name="success" direction="in"/>
    </method>
    <method name="SelectionRead">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="mime_type" direction="in"/>
      <arg type="h" name="fd" direction="out"/>
    </method>
    <signal name="SelectionOwnerChanged">
      <arg type="o" name="session_handle" direction="out"/>
      <arg type="a{sv}" name="options" direction="out"/>
    </signal>
    <signal name="SelectionTransfer">
      <arg type="o" name="session_handle" direction="out"/>
      <arg type="s" name="mime_type" direction="out"/>
      <arg type="u" name="serial" direction="out"/>
    </signal>
  </interface>
</node>"#;

const SESSION_XML: &str = r#"<node>
  <interface name="org.freedesktop.impl.portal.Session">
    <property name="version" type="u" access="read"/>
    <method name="Close"/>
    <signal name="Closed"/>
  </interface>
</node>"#;

type Options = HashMap<String, Variant>;

struct XkbState {
    _lib: libloading::Library,
    ctx: *mut c_void,
    keymap: *mut c_void,
    state: *mut c_void,
    keymap_string: Vec<u8>,
    update_key: unsafe extern "C" fn(*mut c_void, u32, u32) -> u32,
    serialize_mods: unsafe extern "C" fn(*mut c_void, u32) -> u32,
    serialize_layout: unsafe extern "C" fn(*mut c_void, u32) -> u32,
    keymap_min_keycode: unsafe extern "C" fn(*mut c_void) -> u32,
    keymap_max_keycode: unsafe extern "C" fn(*mut c_void) -> u32,
    keymap_key_get_syms_by_level:
        unsafe extern "C" fn(*mut c_void, u32, u32, u32, *mut *const u32) -> c_int,
    state_unref: unsafe extern "C" fn(*mut c_void),
    keymap_unref: unsafe extern "C" fn(*mut c_void),
    context_unref: unsafe extern "C" fn(*mut c_void),
}

impl XkbState {
    fn new() -> Result<Self> {
        let lib = library("libxkbcommon.so.0")?;
        unsafe {
            let context_new: libloading::Symbol<unsafe extern "C" fn(u32) -> *mut c_void> =
                lib.get(b"xkb_context_new\0")?;
            let keymap_new: libloading::Symbol<
                unsafe extern "C" fn(*mut c_void, *const c_void, u32) -> *mut c_void,
            > = lib.get(b"xkb_keymap_new_from_names\0")?;
            let keymap_str: libloading::Symbol<
                unsafe extern "C" fn(*mut c_void, u32) -> *mut c_char,
            > = lib.get(b"xkb_keymap_get_as_string\0")?;
            let state_new: libloading::Symbol<unsafe extern "C" fn(*mut c_void) -> *mut c_void> =
                lib.get(b"xkb_state_new\0")?;
            let update_key = *lib.get::<unsafe extern "C" fn(*mut c_void, u32, u32) -> u32>(
                b"xkb_state_update_key\0",
            )?;
            let serialize_mods = *lib
                .get::<unsafe extern "C" fn(*mut c_void, u32) -> u32>(
                    b"xkb_state_serialize_mods\0",
                )?;
            let serialize_layout = *lib
                .get::<unsafe extern "C" fn(*mut c_void, u32) -> u32>(
                    b"xkb_state_serialize_layout\0",
                )?;
            let keymap_min_keycode = *lib
                .get::<unsafe extern "C" fn(*mut c_void) -> u32>(b"xkb_keymap_min_keycode\0")?;
            let keymap_max_keycode = *lib
                .get::<unsafe extern "C" fn(*mut c_void) -> u32>(b"xkb_keymap_max_keycode\0")?;
            let keymap_key_get_syms_by_level = *lib.get::<unsafe extern "C" fn(
                *mut c_void,
                u32,
                u32,
                u32,
                *mut *const u32,
            ) -> c_int>(
                b"xkb_keymap_key_get_syms_by_level\0",
            )?;
            let state_unref =
                *lib.get::<unsafe extern "C" fn(*mut c_void)>(b"xkb_state_unref\0")?;
            let keymap_unref =
                *lib.get::<unsafe extern "C" fn(*mut c_void)>(b"xkb_keymap_unref\0")?;
            let context_unref =
                *lib.get::<unsafe extern "C" fn(*mut c_void)>(b"xkb_context_unref\0")?;

            let ctx = context_new(0);
            if ctx.is_null() {
                bail!("xkb_context_new failed");
            }
            let keymap = keymap_new(ctx, ptr::null(), 0);
            if keymap.is_null() {
                context_unref(ctx);
                bail!("xkb_keymap_new_from_names failed");
            }
            let raw = keymap_str(keymap, 1);
            if raw.is_null() {
                keymap_unref(keymap);
                context_unref(ctx);
                bail!("xkb_keymap_get_as_string failed");
            }
            let mut keymap_string = CStr::from_ptr(raw).to_bytes_with_nul().to_vec();
            libc::free(raw as *mut c_void);
            if keymap_string.is_empty() {
                keymap_string.push(0);
            }
            let state = state_new(keymap);
            if state.is_null() {
                keymap_unref(keymap);
                context_unref(ctx);
                bail!("xkb_state_new failed");
            }
            Ok(Self {
                _lib: lib,
                ctx,
                keymap,
                state,
                keymap_string,
                update_key,
                serialize_mods,
                serialize_layout,
                keymap_min_keycode,
                keymap_max_keycode,
                keymap_key_get_syms_by_level,
                state_unref,
                keymap_unref,
                context_unref,
            })
        }
    }

    fn update_evdev(&mut self, evdev_keycode: u32, pressed: bool) -> (u32, u32, u32, u32) {
        unsafe {
            // XKB keycodes are evdev + 8; direction 0 = UP, 1 = DOWN.
            (self.update_key)(self.state, evdev_keycode + 8, u32::from(pressed));
            let depressed = (self.serialize_mods)(self.state, 1); // XKB_STATE_MODS_DEPRESSED
            let latched = (self.serialize_mods)(self.state, 2); // XKB_STATE_MODS_LATCHED
            let locked = (self.serialize_mods)(self.state, 4); // XKB_STATE_MODS_LOCKED
            let group = (self.serialize_layout)(self.state, 64); // XKB_STATE_LAYOUT_EFFECTIVE
            (depressed, latched, locked, group)
        }
    }

    fn lookup_keysym(&self, keysym: u32) -> Option<(u32, bool)> {
        unsafe {
            let min = (self.keymap_min_keycode)(self.keymap);
            let max = (self.keymap_max_keycode)(self.keymap);
            for level in [0u32, 1u32] {
                for kc in min..=max {
                    let mut syms: *const u32 = ptr::null();
                    let count =
                        (self.keymap_key_get_syms_by_level)(self.keymap, kc, 0, level, &mut syms);
                    if count > 0 && !syms.is_null() {
                        let slice = std::slice::from_raw_parts(syms, count as usize);
                        if slice.contains(&keysym) && kc >= 8 {
                            return Some((kc - 8, level == 1));
                        }
                    }
                }
            }
            None
        }
    }
}

impl Drop for XkbState {
    fn drop(&mut self) {
        unsafe {
            (self.state_unref)(self.state);
            (self.keymap_unref)(self.keymap);
            (self.context_unref)(self.ctx);
        }
    }
}

struct WaylandVirtualInput {
    stream: UnixStream,
    started: Instant,
    pointer_id: Option<u32>,
    keyboard_id: Option<u32>,
    xkb: Option<XkbState>,
}

fn wl_fixed(v: f64) -> u32 {
    (v * 256.0).round().clamp(i32::MIN as f64, i32::MAX as f64) as i32 as u32
}

fn wl_msg(obj: u32, op: u16, words: &[u32]) -> Vec<u32> {
    let size = ((2 + words.len()) * 4) as u32;
    let mut out = Vec::with_capacity(2 + words.len());
    out.push(obj);
    out.push((size << 16) | (op as u32));
    out.extend_from_slice(words);
    out
}

fn wl_string_words(s: &str) -> Vec<u32> {
    let mut bytes = s.as_bytes().to_vec();
    bytes.push(0);
    let len = bytes.len() as u32;
    while bytes.len() % 4 != 0 {
        bytes.push(0);
    }
    let mut words = Vec::with_capacity(1 + bytes.len() / 4);
    words.push(len);
    for chunk in bytes.chunks_exact(4) {
        words.push(u32::from_ne_bytes(chunk.try_into().unwrap()));
    }
    words
}

fn words_as_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for w in words {
        bytes.extend_from_slice(&w.to_ne_bytes());
    }
    bytes
}

fn send_with_fd(stream: &UnixStream, payload: &[u8], fd: i32) -> Result<()> {
    let iov = libc::iovec {
        iov_base: payload.as_ptr() as *mut c_void,
        iov_len: payload.len(),
    };
    let mut cmsg_buf = vec![0u8; unsafe { libc::CMSG_SPACE(std::mem::size_of::<c_int>() as u32) } as usize];
    let mut msg: libc::msghdr = unsafe { std::mem::zeroed() };
    msg.msg_iov = &iov as *const libc::iovec as *mut libc::iovec;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsg_buf.as_mut_ptr() as *mut c_void;
    msg.msg_controllen = cmsg_buf.len();
    unsafe {
        let cmsg = libc::CMSG_FIRSTHDR(&msg);
        (*cmsg).cmsg_level = libc::SOL_SOCKET;
        (*cmsg).cmsg_type = libc::SCM_RIGHTS;
        (*cmsg).cmsg_len = libc::CMSG_LEN(std::mem::size_of::<c_int>() as u32) as usize;
        ptr::copy_nonoverlapping(&fd, libc::CMSG_DATA(cmsg) as *mut c_int, 1);
        let n = libc::sendmsg(stream.as_raw_fd(), &msg, libc::MSG_NOSIGNAL);
        if n < 0 {
            return Err(std::io::Error::last_os_error().into());
        }
    }
    Ok(())
}

fn create_memfd(name: &str, data: &[u8]) -> Result<OwnedFd> {
    let cname = CString::new(name)?;
    let fd = unsafe { libc::memfd_create(cname.as_ptr(), libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    let mut file = unsafe { File::from_raw_fd(fd) };
    file.write_all(data)?;
    Ok(file.into())
}

impl WaylandVirtualInput {
    fn connect(want_keyboard: bool, want_pointer: bool) -> Result<Self> {
        let display = env::var("WAYLAND_DISPLAY").context("WAYLAND_DISPLAY is not set")?;
        let sock_path = if display.starts_with('/') {
            std::path::PathBuf::from(display)
        } else {
            runtime()?.join(display)
        };
        let mut stream = UnixStream::connect(&sock_path)
            .with_context(|| format!("Cannot connect to Wayland display {}", sock_path.display()))?;
        stream.set_read_timeout(Some(Duration::from_secs(2)))?;
        stream.set_write_timeout(Some(Duration::from_secs(2)))?;

        let registry_id = 2u32;
        let sync_id = 3u32;
        let mut init_words = Vec::new();
        init_words.extend(wl_msg(1, 1, &[registry_id])); // wl_display.get_registry
        init_words.extend(wl_msg(1, 0, &[sync_id])); // wl_display.sync
        stream.write_all(&words_as_bytes(&init_words))?;

        let mut seat_global = None;
        let mut vp_global = None;
        let mut vk_global = None;
        let mut buf = Vec::new();
        let mut chunk = [0u8; 8192];
        let mut done = false;
        while !done {
            let n = stream.read(&mut chunk)?;
            if n == 0 {
                bail!("Wayland compositor closed connection during registry discovery");
            }
            buf.extend_from_slice(&chunk[..n]);
            let mut off = 0;
            while buf.len() - off >= 8 {
                let obj = u32::from_ne_bytes(buf[off..off + 4].try_into().unwrap());
                let sz_op = u32::from_ne_bytes(buf[off + 4..off + 8].try_into().unwrap());
                let sz = (sz_op >> 16) as usize;
                let op = (sz_op & 0xffff) as u16;
                if sz < 8 || buf.len() - off < sz {
                    break;
                }
                if obj == registry_id && op == 0 && sz >= 20 {
                    let name = u32::from_ne_bytes(buf[off + 8..off + 12].try_into().unwrap());
                    let slen =
                        u32::from_ne_bytes(buf[off + 12..off + 16].try_into().unwrap()) as usize;
                    if slen > 0 && off + 16 + slen <= off + sz {
                        let iface = std::str::from_utf8(&buf[off + 16..off + 16 + slen - 1])
                            .unwrap_or("");
                        let ver_off = off + 16 + ((slen + 3) & !3);
                        if ver_off + 4 <= off + sz {
                            let ver =
                                u32::from_ne_bytes(buf[ver_off..ver_off + 4].try_into().unwrap());
                            match iface {
                                "wl_seat" => seat_global = Some((name, ver.min(7))),
                                "zwlr_virtual_pointer_manager_v1" => {
                                    vp_global = Some((name, ver.min(2)))
                                }
                                "zwp_virtual_keyboard_manager_v1" => {
                                    vk_global = Some((name, ver.min(1)))
                                }
                                _ => {}
                            }
                        }
                    }
                } else if obj == sync_id && op == 0 {
                    done = true;
                }
                off += sz;
            }
            buf.drain(..off);
        }

        let mut next_id = 4u32;
        let mut alloc = || {
            let id = next_id;
            next_id += 1;
            id
        };
        let mut bind_words = Vec::new();
        let bind = |buf: &mut Vec<u32>, name: u32, iface: &str, ver: u32, new_id: u32| {
            let mut args = vec![name];
            args.extend(wl_string_words(iface));
            args.push(ver);
            args.push(new_id);
            buf.extend(wl_msg(registry_id, 0, &args));
        };

        let seat_id = seat_global.map(|(name, ver)| {
            let id = alloc();
            bind(&mut bind_words, name, "wl_seat", ver, id);
            id
        });
        let pointer_id = if want_pointer {
            vp_global.map(|(name, ver)| {
                let mgr = alloc();
                bind(
                    &mut bind_words,
                    name,
                    "zwlr_virtual_pointer_manager_v1",
                    ver,
                    mgr,
                );
                let ptr_id = alloc();
                bind_words.extend(wl_msg(mgr, 0, &[0, ptr_id])); // create_virtual_pointer(null, id)
                ptr_id
            })
        } else {
            None
        };

        let mut xkb = None;
        let keyboard_id = if want_keyboard {
            if let (Some(seat), Some((name, ver))) = (seat_id, vk_global) {
                let mgr = alloc();
                bind(
                    &mut bind_words,
                    name,
                    "zwp_virtual_keyboard_manager_v1",
                    ver,
                    mgr,
                );
                let kb_id = alloc();
                bind_words.extend(wl_msg(mgr, 0, &[seat, kb_id])); // create_virtual_keyboard(seat, id)
                xkb = XkbState::new().ok();
                Some(kb_id)
            } else {
                None
            }
        } else {
            None
        };

        if !bind_words.is_empty() {
            stream.write_all(&words_as_bytes(&bind_words))?;
        }
        if let (Some(kb_id), Some(xkb_state)) = (keyboard_id, xkb.as_ref()) {
            let memfd = create_memfd("dotfiles-portal-keymap", &xkb_state.keymap_string)?;
            let keymap_msg = wl_msg(kb_id, 0, &[1, xkb_state.keymap_string.len() as u32]);
            send_with_fd(&stream, &words_as_bytes(&keymap_msg), memfd.as_raw_fd())?;
        }
        let _ = stream.set_nonblocking(true);

        Ok(Self {
            stream,
            started: Instant::now(),
            pointer_id,
            keyboard_id,
            xkb,
        })
    }

    fn time_ms(&self) -> u32 {
        self.started.elapsed().as_millis() as u32
    }

    fn send(&mut self, words: &[u32]) {
        let mut drain = [0u8; 512];
        let _ = self.stream.read(&mut drain);
        let _ = self.stream.write_all(&words_as_bytes(words));
    }

    fn motion(&mut self, dx: f64, dy: f64) {
        if let Some(id) = self.pointer_id {
            let t = self.time_ms();
            let mut w = wl_msg(id, 0, &[t, wl_fixed(dx), wl_fixed(dy)]);
            w.extend(wl_msg(id, 4, &[])); // frame
            self.send(&w);
        }
    }

    fn motion_absolute(&mut self, x: f64, y: f64, extent_x: u32, extent_y: u32) {
        if let Some(id) = self.pointer_id {
            let t = self.time_ms();
            let px = x.max(0.0).round() as u32;
            let py = y.max(0.0).round() as u32;
            let mut w = wl_msg(id, 1, &[t, px, py, extent_x.max(1), extent_y.max(1)]);
            w.extend(wl_msg(id, 4, &[]));
            self.send(&w);
        }
    }

    fn button(&mut self, button: u32, state: u32) {
        if let Some(id) = self.pointer_id {
            let t = self.time_ms();
            let mut w = wl_msg(id, 2, &[t, button, state]);
            w.extend(wl_msg(id, 4, &[]));
            self.send(&w);
        }
    }

    fn axis(&mut self, dx: f64, dy: f64) {
        if let Some(id) = self.pointer_id {
            let t = self.time_ms();
            let mut w = Vec::new();
            if dy.abs() > f64::EPSILON {
                w.extend(wl_msg(id, 3, &[t, 0, wl_fixed(dy)]));
            }
            if dx.abs() > f64::EPSILON {
                w.extend(wl_msg(id, 3, &[t, 1, wl_fixed(dx)]));
            }
            if !w.is_empty() {
                w.extend(wl_msg(id, 4, &[]));
                self.send(&w);
            }
        }
    }

    fn axis_discrete(&mut self, axis: u32, steps: i32) {
        if let Some(id) = self.pointer_id {
            let t = self.time_ms();
            let mut w = wl_msg(
                id,
                7,
                &[t, axis, wl_fixed(steps as f64 * 15.0), steps as u32],
            );
            w.extend(wl_msg(id, 4, &[]));
            self.send(&w);
        }
    }

    fn keycode(&mut self, keycode: u32, state: u32) {
        if let Some(id) = self.keyboard_id {
            let t = self.time_ms();
            let mut w = wl_msg(id, 1, &[t, keycode, state]);
            if let Some(xkb) = self.xkb.as_mut() {
                let (dep, lat, loc, grp) = xkb.update_evdev(keycode, state != 0);
                w.extend(wl_msg(id, 2, &[dep, lat, loc, grp]));
            }
            self.send(&w);
        }
    }

    fn keysym(&mut self, keysym: u32, state: u32) {
        let Some((keycode, needs_shift)) = self.xkb.as_ref().and_then(|x| x.lookup_keysym(keysym))
        else {
            return;
        };
        const KEY_LEFTSHIFT: u32 = 42;
        if needs_shift && state != 0 {
            self.keycode(KEY_LEFTSHIFT, 1);
        }
        self.keycode(keycode, state);
        if needs_shift && state == 0 {
            self.keycode(KEY_LEFTSHIFT, 0);
        }
    }
}

struct TransferEntry {
    mime_type: String,
    data: Arc<Mutex<Option<Vec<u8>>>>,
    done: bool,
    success: bool,
}

struct SelectionBatch {
    serials: Vec<u32>,
}

struct RemoteSession {
    sender: String,
    session_reg: gio::RegistrationId,
    requested_devices: u32,
    granted_devices: u32,
    clipboard_requested: bool,
    clipboard_enabled: bool,
    started: bool,
    input: Option<WaylandVirtualInput>,
    watcher_stop: Option<Arc<AtomicBool>>,
    next_serial: u32,
    transfers: HashMap<u32, TransferEntry>,
    active_batch: Option<SelectionBatch>,
}

struct PendingStart {
    sender: String,
    session_handle: String,
    invocation: gio::DBusMethodInvocation,
    requested_devices: u32,
    clipboard_requested: bool,
    dialog: Dialog,
    registration: gio::RegistrationId,
}

struct RemoteState {
    bus: gio::DBusConnection,
    sessions: HashMap<String, RemoteSession>,
    pending: HashMap<String, PendingStart>,
    testing: bool,
}

impl RemoteState {
    fn close_session(&mut self, handle: &str) {
        if let Some(mut session) = self.sessions.remove(handle) {
            if let Some(stop) = session.watcher_stop.take() {
                stop.store(true, Ordering::Relaxed);
            }
            let _ = self.bus.emit_signal(
                None,
                handle,
                "org.freedesktop.impl.portal.Session",
                "Closed",
                None,
            );
            let _ = self.bus.unregister_object(session.session_reg);
        }
    }

    fn finish_start(&mut self, req_handle: &str, result: Value) {
        let Some(p) = self.pending.remove(req_handle) else {
            return;
        };
        let _ = self.bus.unregister_object(p.registration);
        let code = match result["response"].as_u64() {
            Some(n @ 0..=2) => n as u32,
            _ => 2,
        };
        if code != 0 {
            self.close_session(&p.session_handle);
            let empty: Options = HashMap::new();
            p.invocation
                .return_value(Some(&(code, empty).to_variant()));
            return;
        }
        let choices = result["choices"].as_object();
        let mut granted = 0u32;
        if p.requested_devices & DEVICE_KEYBOARD != 0
            && choices
                .and_then(|c| c.get("keyboard"))
                .and_then(Value::as_str)
                .unwrap_or("true")
                == "true"
        {
            granted |= DEVICE_KEYBOARD;
        }
        if p.requested_devices & DEVICE_POINTER != 0
            && choices
                .and_then(|c| c.get("pointer"))
                .and_then(Value::as_str)
                .unwrap_or("true")
                == "true"
        {
            granted |= DEVICE_POINTER;
        }
        let clipboard_enabled = p.clipboard_requested
            && choices
                .and_then(|c| c.get("clipboard"))
                .and_then(Value::as_str)
                .unwrap_or("true")
                == "true";

        let Some(session) = self.sessions.get_mut(&p.session_handle) else {
            let empty: Options = HashMap::new();
            p.invocation
                .return_value(Some(&(2u32, empty).to_variant()));
            return;
        };
        session.granted_devices = granted;
        session.clipboard_enabled = clipboard_enabled;
        session.started = true;
        if granted != 0 && !self.testing {
            match WaylandVirtualInput::connect(
                granted & DEVICE_KEYBOARD != 0,
                granted & DEVICE_POINTER != 0,
            ) {
                Ok(input) => session.input = Some(input),
                Err(err) => eprintln!("RemoteDesktop virtual input unavailable: {err:#}"),
            }
        }
        if clipboard_enabled && !self.testing {
            let stop = Arc::new(AtomicBool::new(false));
            spawn_clipboard_watcher(self.bus.clone(), p.session_handle.clone(), stop.clone());
            session.watcher_stop = Some(stop);
        }

        let mut results: Options = HashMap::new();
        results.insert("devices".to_string(), granted.to_variant());
        results.insert(
            "clipboard_enabled".to_string(),
            clipboard_enabled.to_variant(),
        );
        p.invocation
            .return_value(Some(&(0u32, results).to_variant()));
    }
}

fn spawn_clipboard_watcher(
    bus: gio::DBusConnection,
    session_handle: String,
    stop: Arc<AtomicBool>,
) {
    std::thread::spawn(move || {
        let Ok(mut watcher) = Watcher::new(WatchClipboardType::Regular, Seat::Unspecified) else {
            return;
        };
        while !stop.load(Ordering::Relaxed) {
            match watcher.next_event() {
                Ok(Some(ClipboardEvent::Changed { mime_types, .. })) => {
                    if stop.load(Ordering::Relaxed) {
                        break;
                    }
                    let mut mimes: Vec<String> = mime_types
                        .into_iter()
                        .filter(|m| !m.starts_with("application/x-dotfiles-"))
                        .collect();
                    mimes.sort();
                    let bus = bus.clone();
                    let handle = session_handle.clone();
                    glib::MainContext::default().invoke(move || {
                        let mut opts: Options = HashMap::new();
                        opts.insert("mime_types".to_string(), mimes.to_variant());
                        opts.insert("session_is_owner".to_string(), false.to_variant());
                        if let Ok(path) = glib::variant::ObjectPath::try_from(handle.as_str()) {
                            let _ = bus.emit_signal(
                                None,
                                PATH,
                                "org.freedesktop.impl.portal.Clipboard",
                                "SelectionOwnerChanged",
                                Some(&(path, opts).to_variant()),
                            );
                        }
                    });
                }
                Ok(Some(ClipboardEvent::Cleared { .. })) => {
                    if stop.load(Ordering::Relaxed) {
                        break;
                    }
                    let bus = bus.clone();
                    let handle = session_handle.clone();
                    glib::MainContext::default().invoke(move || {
                        let mut opts: Options = HashMap::new();
                        let empty: Vec<String> = Vec::new();
                        opts.insert("mime_types".to_string(), empty.to_variant());
                        opts.insert("session_is_owner".to_string(), false.to_variant());
                        if let Ok(path) = glib::variant::ObjectPath::try_from(handle.as_str()) {
                            let _ = bus.emit_signal(
                                None,
                                PATH,
                                "org.freedesktop.impl.portal.Clipboard",
                                "SelectionOwnerChanged",
                                Some(&(path, opts).to_variant()),
                            );
                        }
                    });
                }
                Ok(None) | Err(_) => break,
            }
        }
    });
}

fn make_pipe() -> Result<(OwnedFd, OwnedFd)> {
    let mut fds = [0 as c_int; 2];
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    unsafe { Ok((OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1]))) }
}

fn screen_extent() -> (u32, u32) {
    let Ok(monitors) = json(&["hyprctl", "-j", "monitors"]) else {
        return (1920, 1080);
    };
    let mut max_w = 1920u32;
    let mut max_h = 1080u32;
    for m in rows(&monitors) {
        let w = m["width"].as_u64().unwrap_or(0) as u32;
        let h = m["height"].as_u64().unwrap_or(0) as u32;
        if w > max_w {
            max_w = w;
        }
        if h > max_h {
            max_h = h;
        }
    }
    (max_w, max_h)
}

pub fn register(
    bus: &gio::DBusConnection,
    testing: bool,
) -> Result<(Vec<gio::RegistrationId>, gio::SignalSubscription)> {
    let state = Rc::new(RefCell::new(RemoteState {
        bus: bus.clone(),
        sessions: HashMap::new(),
        pending: HashMap::new(),
        testing,
    }));
    let mut registrations = Vec::new();
    for interface in gio::DBusNodeInfo::for_xml(XML)?.interfaces() {
        let state = state.clone();
        let id = bus
            .register_object(PATH, interface)
            .property(|_, _, _, interface, prop| {
                if prop == "AvailableDeviceTypes" {
                    AVAILABLE_DEVICES.to_variant()
                } else if interface.ends_with("RemoteDesktop") {
                    2u32.to_variant()
                } else {
                    1u32.to_variant()
                }
            })
            .method_call(move |_, sender, _, interface, method, params, invocation| {
                handle_call(
                    &state,
                    sender,
                    interface.unwrap_or(""),
                    method,
                    params,
                    invocation,
                )
            })
            .build()?;
        registrations.push(id);
    }

    let disconnected = state.clone();
    let owner_sub = bus.subscribe_to_signal(
        Some("org.freedesktop.DBus"),
        Some("org.freedesktop.DBus"),
        Some("NameOwnerChanged"),
        Some("/org/freedesktop/DBus"),
        None,
        gio::DBusSignalFlags::NONE,
        move |signal| {
            if let Some((name, old, new)) = signal.parameters.get::<(String, String, String)>()
                && !old.is_empty()
                && new.is_empty()
            {
                let mut s = disconnected.borrow_mut();
                let reqs: Vec<_> = s
                    .pending
                    .iter()
                    .filter(|(_, p)| p.sender == name)
                    .map(|(h, _)| h.clone())
                    .collect();
                for h in reqs {
                    s.finish_start(&h, json!({"response": 2}));
                }
                let sess: Vec<_> = s
                    .sessions
                    .iter()
                    .filter(|(_, sess)| sess.sender == name)
                    .map(|(h, _)| h.clone())
                    .collect();
                for h in sess {
                    s.close_session(&h);
                }
            }
        },
    );

    Ok((registrations, owner_sub))
}

fn handle_call(
    state: &Rc<RefCell<RemoteState>>,
    sender: Option<&str>,
    interface: &str,
    method: &str,
    params: Variant,
    invocation: gio::DBusMethodInvocation,
) {
    let sender = sender.unwrap_or("");
    {
        let s = state.borrow();
        if !is_portal_frontend(&s.bus, sender, s.testing) {
            invocation.return_dbus_error(
                "org.freedesktop.DBus.Error.AccessDenied",
                "Only the portal frontend may invoke backend methods.",
            );
            return;
        }
    }
    let result = match (interface, method) {
        ("org.freedesktop.impl.portal.RemoteDesktop", "CreateSession") => {
            handle_create_session(state, sender, params, &invocation)
        }
        ("org.freedesktop.impl.portal.RemoteDesktop", "SelectDevices") => {
            handle_select_devices(state, params, &invocation)
        }
        ("org.freedesktop.impl.portal.RemoteDesktop", "Start") => {
            handle_start(state, sender, params, &invocation)
        }
        ("org.freedesktop.impl.portal.RemoteDesktop", "ConnectToEIS") => {
            invocation.clone().return_dbus_error(
                "org.freedesktop.portal.Error.NotSupported",
                "Use Notify* methods for input injection on this backend.",
            );
            Ok(())
        }
        ("org.freedesktop.impl.portal.RemoteDesktop", m) if m.starts_with("Notify") => {
            handle_notify(state, m, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Clipboard", "RequestClipboard") => {
            handle_request_clipboard(state, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Clipboard", "SetSelection") => {
            handle_set_selection(state, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Clipboard", "SelectionWrite") => {
            handle_selection_write(state, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Clipboard", "SelectionWriteDone") => {
            handle_selection_write_done(state, params, &invocation)
        }
        ("org.freedesktop.impl.portal.Clipboard", "SelectionRead") => {
            handle_selection_read(state, params, &invocation)
        }
        _ => Err(anyhow::anyhow!(
            "Unknown portal method: {interface}.{method}"
        )),
    };
    if let Err(error) = result {
        invocation.return_dbus_error("org.freedesktop.portal.Error.Failed", &error.to_string());
    }
}

fn handle_create_session(
    state: &Rc<RefCell<RemoteState>>,
    sender: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(1)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    if state.borrow().sessions.contains_key(&session_handle) {
        bail!("Session already exists");
    }
    if state.borrow().sessions.len() >= 16 {
        bail!("Too many remote desktop sessions");
    }
    let close_state = state.clone();
    let session_reg = state
        .borrow()
        .bus
        .register_object(
            &session_handle,
            &gio::DBusNodeInfo::for_xml(SESSION_XML)?.interfaces()[0],
        )
        .property(|_, _, _, _, _| 1u32.to_variant())
        .method_call(move |_, _, path, _, _, _, call| {
            close_state.borrow_mut().close_session(path);
            call.return_value(None);
        })
        .build()?;
    state.borrow_mut().sessions.insert(
        session_handle.clone(),
        RemoteSession {
            sender: sender.into(),
            session_reg,
            requested_devices: AVAILABLE_DEVICES,
            granted_devices: 0,
            clipboard_requested: false,
            clipboard_enabled: false,
            started: false,
            input: None,
            watcher_stop: None,
            next_serial: 1,
            transfers: HashMap::new(),
            active_batch: None,
        },
    );
    let mut results: Options = HashMap::new();
    results.insert("session".to_string(), session_handle.to_variant());
    invocation
        .clone()
        .return_value(Some(&(0u32, results).to_variant()));
    Ok(())
}

fn handle_select_devices(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(1)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let options = params
        .child_value(3)
        .get::<Options>()
        .context("Invalid options")?;
    let types = options
        .get("types")
        .and_then(|v| v.get::<u32>())
        .unwrap_or(AVAILABLE_DEVICES)
        & AVAILABLE_DEVICES;
    let mut s = state.borrow_mut();
    let session = s
        .sessions
        .get_mut(&session_handle)
        .context("Unknown remote desktop session")?;
    session.requested_devices = types;
    let empty: Options = HashMap::new();
    invocation
        .clone()
        .return_value(Some(&(0u32, empty).to_variant()));
    Ok(())
}

fn handle_start(
    state: &Rc<RefCell<RemoteState>>,
    sender: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let handle = params
        .child_value(0)
        .str()
        .context("Invalid handle")?
        .to_string();
    let session_handle = params
        .child_value(1)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let app_id = params
        .child_value(2)
        .get::<String>()
        .context("Invalid app_id")?;
    let parent = params.child_value(3).get::<String>().unwrap_or_default();

    let (requested_devices, clipboard_requested) = {
        let s = state.borrow();
        if s.pending.contains_key(&handle) {
            bail!("Request already exists");
        }
        let session = s
            .sessions
            .get(&session_handle)
            .context("Unknown remote desktop session")?;
        (session.requested_devices, session.clipboard_requested)
    };

    let app = app_metadata(&app_id);
    let display = s(&app, "name").to_string();
    let mut choices = Vec::new();
    if requested_devices & DEVICE_KEYBOARD != 0 {
        choices.push(json!({"id": "keyboard", "name": "Keyboard input", "values": [], "selected": "true"}));
    }
    if requested_devices & DEVICE_POINTER != 0 {
        choices.push(json!({"id": "pointer", "name": "Pointer input", "values": [], "selected": "true"}));
    }
    if clipboard_requested {
        choices.push(json!({"id": "clipboard", "name": "Clipboard access", "values": [], "selected": "true"}));
    }
    let data = json!({
        "kind": "access",
        "app": app,
        "parent": parent,
        "activationToken": "",
        "title": format!("Allow {display} to control your desktop?"),
        "subtitle": "Select what this remote desktop session may access.",
        "body": "",
        "choices": choices,
        "grantLabel": "Allow",
        "denyLabel": "Deny",
    });
    let dialog = Dialog::open(&data)?;
    let close_state = state.clone();
    let registration = state
        .borrow()
        .bus
        .register_object(
            &handle,
            &gio::DBusNodeInfo::for_xml(REQUEST)?.interfaces()[0],
        )
        .method_call(move |_, caller, path, _, _, _, call| {
            let mut s = close_state.borrow_mut();
            if s.pending
                .get(path)
                .is_some_and(|p| Some(p.sender.as_str()) != caller)
            {
                call.return_dbus_error(
                    "org.freedesktop.DBus.Error.AccessDenied",
                    "Request belongs to another caller.",
                );
                return;
            }
            s.finish_start(path, json!({"response": 2}));
            call.return_value(None);
        })
        .build()?;
    state.borrow_mut().pending.insert(
        handle.clone(),
        PendingStart {
            sender: sender.into(),
            session_handle,
            invocation: invocation.clone(),
            requested_devices,
            clipboard_requested,
            dialog,
            registration,
        },
    );
    let poll_state = state.clone();
    glib::timeout_add_local(Duration::from_millis(16), move || {
        let mut s = poll_state.borrow_mut();
        let result = match s.pending.get_mut(&handle) {
            None => return glib::ControlFlow::Break,
            Some(p) => match p.dialog.poll() {
                Ok(false) => return glib::ControlFlow::Continue,
                Ok(true) => p.dialog.result(),
                Err(err) => {
                    eprintln!("RemoteDesktop dialog: {err}");
                    json!({"response": 2})
                }
            },
        };
        s.finish_start(&handle, result);
        glib::ControlFlow::Break
    });
    Ok(())
}

fn handle_notify(
    state: &Rc<RefCell<RemoteState>>,
    method: &str,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let mut s = state.borrow_mut();
    let session = s
        .sessions
        .get_mut(&session_handle)
        .context("Unknown remote desktop session")?;
    if !session.started {
        bail!("Remote desktop session not started");
    }
    if let Some(input) = session.input.as_mut() {
        match method {
            "NotifyPointerMotion" if session.granted_devices & DEVICE_POINTER != 0 => {
                let dx = params.child_value(2).get::<f64>().unwrap_or(0.0);
                let dy = params.child_value(3).get::<f64>().unwrap_or(0.0);
                input.motion(dx, dy);
            }
            "NotifyPointerMotionAbsolute" if session.granted_devices & DEVICE_POINTER != 0 => {
                let x = params.child_value(3).get::<f64>().unwrap_or(0.0);
                let y = params.child_value(4).get::<f64>().unwrap_or(0.0);
                let (ew, eh) = screen_extent();
                input.motion_absolute(x, y, ew, eh);
            }
            "NotifyPointerButton" if session.granted_devices & DEVICE_POINTER != 0 => {
                let button = params.child_value(2).get::<i32>().unwrap_or(0) as u32;
                let st = params.child_value(3).get::<u32>().unwrap_or(0);
                input.button(button, st);
            }
            "NotifyPointerAxis" if session.granted_devices & DEVICE_POINTER != 0 => {
                let dx = params.child_value(2).get::<f64>().unwrap_or(0.0);
                let dy = params.child_value(3).get::<f64>().unwrap_or(0.0);
                input.axis(dx, dy);
            }
            "NotifyPointerAxisDiscrete" if session.granted_devices & DEVICE_POINTER != 0 => {
                let axis = params.child_value(2).get::<u32>().unwrap_or(0);
                let steps = params.child_value(3).get::<i32>().unwrap_or(0);
                input.axis_discrete(axis, steps);
            }
            "NotifyKeyboardKeycode" if session.granted_devices & DEVICE_KEYBOARD != 0 => {
                let kc = params.child_value(2).get::<i32>().unwrap_or(0) as u32;
                let st = params.child_value(3).get::<u32>().unwrap_or(0);
                input.keycode(kc, st);
            }
            "NotifyKeyboardKeysym" if session.granted_devices & DEVICE_KEYBOARD != 0 => {
                let ks = params.child_value(2).get::<i32>().unwrap_or(0) as u32;
                let st = params.child_value(3).get::<u32>().unwrap_or(0);
                input.keysym(ks, st);
            }
            _ => {}
        }
    }
    invocation.clone().return_value(None);
    Ok(())
}

fn handle_request_clipboard(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let mut s = state.borrow_mut();
    let session = s
        .sessions
        .get_mut(&session_handle)
        .context("Unknown clipboard session")?;
    session.clipboard_requested = true;
    invocation.clone().return_value(None);
    Ok(())
}

fn handle_set_selection(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let options = params
        .child_value(1)
        .get::<Options>()
        .context("Invalid options")?;
    let mime_types: Vec<String> = options
        .get("mime_types")
        .and_then(|v| v.get::<Vec<String>>())
        .unwrap_or_default()
        .into_iter()
        .filter(|m| !m.is_empty() && m.len() < 256)
        .take(MAX_MIME_TYPES)
        .collect();

    let (bus, transfers_to_emit) = {
        let mut s = state.borrow_mut();
        let bus = s.bus.clone();
        let session = s
            .sessions
            .get_mut(&session_handle)
            .context("Unknown clipboard session")?;
        if !session.clipboard_enabled {
            bail!("Clipboard not enabled for session");
        }
        session.transfers.clear();
        let mut seen = HashSet::new();
        let mut batch_serials = Vec::new();
        let mut emit = Vec::new();
        for mime in mime_types {
            if !seen.insert(mime.clone()) {
                continue;
            }
            let serial = session.next_serial;
            session.next_serial = session.next_serial.wrapping_add(1).max(1);
            session.transfers.insert(
                serial,
                TransferEntry {
                    mime_type: mime.clone(),
                    data: Arc::new(Mutex::new(None)),
                    done: false,
                    success: false,
                },
            );
            batch_serials.push(serial);
            emit.push((mime, serial));
        }
        session.active_batch = if batch_serials.is_empty() {
            None
        } else {
            Some(SelectionBatch {
                serials: batch_serials,
            })
        };
        (bus, emit)
    };

    invocation.clone().return_value(None);
    if let Ok(path) = glib::variant::ObjectPath::try_from(session_handle.as_str()) {
        for (mime, serial) in transfers_to_emit {
            let _ = bus.emit_signal(
                None,
                PATH,
                "org.freedesktop.impl.portal.Clipboard",
                "SelectionTransfer",
                Some(&(path.clone(), mime, serial).to_variant()),
            );
        }
    }
    Ok(())
}

fn handle_selection_write(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let serial = params
        .child_value(1)
        .get::<u32>()
        .context("Invalid serial")?;
    let slot = {
        let s = state.borrow();
        let session = s
            .sessions
            .get(&session_handle)
            .context("Unknown clipboard session")?;
        if !session.clipboard_enabled {
            bail!("Clipboard not enabled");
        }
        session
            .transfers
            .get(&serial)
            .context("Unknown selection transfer serial")?
            .data
            .clone()
    };
    let (read_fd, write_fd) = make_pipe()?;
    std::thread::spawn(move || {
        let mut reader = File::from(read_fd);
        let mut buf = Vec::new();
        let mut chunk = [0u8; 8192];
        while let Ok(n) = reader.read(&mut chunk) {
            if n == 0 {
                break;
            }
            if buf.len() + n > MAX_CLIPBOARD_BYTES {
                return;
            }
            buf.extend_from_slice(&chunk[..n]);
        }
        if let Ok(mut guard) = slot.lock() {
            *guard = Some(buf);
        }
    });
    let fd_list = gio::UnixFDList::from_array([write_fd.into_raw_fd()]);
    invocation.clone().return_value_with_unix_fd_list(
        Some(&(glib::variant::Handle(0),).to_variant()),
        Some(&fd_list),
    );
    Ok(())
}

fn handle_selection_write_done(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let serial = params
        .child_value(1)
        .get::<u32>()
        .context("Invalid serial")?;
    let success = params
        .child_value(2)
        .get::<bool>()
        .context("Invalid success flag")?;

    let publish = {
        let mut s = state.borrow_mut();
        let session = s
            .sessions
            .get_mut(&session_handle)
            .context("Unknown clipboard session")?;
        if let Some(entry) = session.transfers.get_mut(&serial) {
            entry.done = true;
            entry.success = success;
        }
        let all_done = session
            .active_batch
            .as_ref()
            .is_some_and(|b| b.serials.iter().all(|id| session.transfers.get(id).is_none_or(|e| e.done)));
        if all_done {
            let batch = session.active_batch.take().unwrap();
            let mut items = Vec::new();
            for id in batch.serials {
                if let Some(entry) = session.transfers.remove(&id)
                    && entry.success
                    && let Ok(mut guard) = entry.data.lock()
                    && let Some(bytes) = guard.take()
                {
                    items.push((entry.mime_type, bytes));
                }
            }
            Some(items)
        } else {
            None
        }
    };

    if let Some(items) = publish
        && !items.is_empty()
    {
        std::thread::spawn(move || {
            let sources: Vec<MimeSource> = items
                .into_iter()
                .map(|(mime, data)| MimeSource {
                    source: Source::Bytes(data.into()),
                    mime_type: CopyMimeType::Specific(mime),
                })
                .collect();
            let opts = CopyOptions::new();
            if let Err(err) = opts.copy_multi(sources) {
                eprintln!("Clipboard portal SetSelection failed: {err}");
            }
        });
    }

    invocation.clone().return_value(None);
    Ok(())
}

fn handle_selection_read(
    state: &Rc<RefCell<RemoteState>>,
    params: Variant,
    invocation: &gio::DBusMethodInvocation,
) -> Result<()> {
    let session_handle = params
        .child_value(0)
        .str()
        .context("Invalid session_handle")?
        .to_string();
    let mime_type = params
        .child_value(1)
        .get::<String>()
        .context("Invalid mime_type")?;
    {
        let s = state.borrow();
        let session = s
            .sessions
            .get(&session_handle)
            .context("Unknown clipboard session")?;
        if !session.clipboard_enabled {
            bail!("Clipboard not enabled");
        }
    }
    let (read_fd, write_fd) = make_pipe()?;
    std::thread::spawn(move || {
        let mut writer = File::from(write_fd);
        if let Ok((mut pipe, _)) = paste::get_contents(
            PasteClipboardType::Regular,
            Seat::Unspecified,
            PasteMimeType::Specific(&mime_type),
        ) {
            let mut buf = [0u8; 16384];
            let mut total = 0usize;
            while let Ok(n) = pipe.read(&mut buf) {
                if n == 0 || total + n > MAX_CLIPBOARD_BYTES {
                    break;
                }
                if writer.write_all(&buf[..n]).is_err() {
                    break;
                }
                total += n;
            }
        }
    });
    let fd_list = gio::UnixFDList::from_array([read_fd.into_raw_fd()]);
    invocation.clone().return_value_with_unix_fd_list(
        Some(&(glib::variant::Handle(0),).to_variant()),
        Some(&fd_list),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wayland_wire_encoding_pads_strings_to_four_bytes() {
        let words = wl_string_words("wl_seat");
        assert_eq!(words[0], 8);
        assert_eq!(words.len(), 3);
        let msg = wl_msg(1, 0, &[3]);
        assert_eq!(msg[0], 1);
        assert_eq!(msg[1], (12 << 16) | 0);
        assert_eq!(msg[2], 3);
    }

    #[test]
    fn fixed_point_conversion_handles_negative_and_fractional_deltas() {
        assert_eq!(wl_fixed(1.5) as i32, 384);
        assert_eq!(wl_fixed(-2.25) as i32, -576);
    }
}

use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::{
    env, fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};
use wait_timeout::ChildExt;

pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .expect("HOME must be set")
}
pub fn xdg(key: &str, fallback: &str) -> PathBuf {
    env::var_os(key)
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}
pub fn root() -> PathBuf {
    env::var_os("DOTFILES_HYPR_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| xdg("XDG_CONFIG_HOME", ".config").join("hypr"))
}
pub fn runtime() -> Result<PathBuf> {
    Ok(env::var_os("XDG_RUNTIME_DIR")
        .context("XDG_RUNTIME_DIR is not set")?
        .into())
}
pub fn arg(args: &[String], n: usize) -> Result<&str> {
    args.get(n)
        .map(String::as_str)
        .context("Missing command argument")
}
pub fn command(args: &[&str]) -> Command {
    let mut c = Command::new(args[0]);
    c.args(&args[1..]);
    c
}
pub fn run(args: &[&str]) -> Result<String> {
    output(command(args), None, Duration::from_secs(30))
}
pub fn output(mut cmd: Command, input: Option<Vec<u8>>, timeout: Duration) -> Result<String> {
    let label = format!("{cmd:?}");
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    if input.is_some() {
        cmd.stdin(Stdio::piped());
    }
    let mut child = cmd.spawn().with_context(|| label.clone())?;
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let read = |mut stream: Box<dyn Read + Send>| {
        std::thread::spawn(move || {
            let mut bytes = Vec::new();
            stream.read_to_end(&mut bytes).map(|_| bytes)
        })
    };
    let out = read(Box::new(stdout));
    let err = read(Box::new(stderr));
    let writer = input.map(|data| {
        let mut stream = child.stdin.take().unwrap();
        std::thread::spawn(move || stream.write_all(&data))
    });
    let status = match child.wait_timeout(timeout)? {
        Some(s) => s,
        None => {
            let _ = child.kill();
            let _ = child.wait();
            bail!("Command timed out: {label}");
        }
    };
    if let Some(w) = writer {
        w.join()
            .map_err(|_| anyhow::anyhow!("Input writer panicked"))??;
    }
    let bytes = out
        .join()
        .map_err(|_| anyhow::anyhow!("Output reader panicked"))??;
    let errors = err
        .join()
        .map_err(|_| anyhow::anyhow!("Error reader panicked"))??;
    if !status.success() {
        bail!("{label}: {}", String::from_utf8_lossy(&errors).trim());
    }
    String::from_utf8(bytes).context("Command returned invalid UTF-8")
}
pub fn json(args: &[&str]) -> Result<Value> {
    Ok(serde_json::from_str(&run(args)?)?)
}
pub fn read_json(path: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
pub fn atomic(path: &Path, data: &[u8]) -> Result<()> {
    let parent = path.parent().context("No parent directory")?;
    fs::create_dir_all(parent)?;
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    tmp.write_all(data)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path).map_err(|e| e.error)?;
    Ok(())
}
pub fn atomic_json(path: &Path, data: &Value) -> Result<()> {
    atomic(path, &serde_json::to_vec(data)?)
}
pub fn emit(data: &Value) -> Result<()> {
    let out = std::io::stdout();
    let mut out = out.lock();
    serde_json::to_writer(&mut out, data)?;
    writeln!(out)?;
    out.flush()?;
    Ok(())
}
pub fn s<'a>(v: &'a Value, key: &str) -> &'a str {
    v[key].as_str().unwrap_or("")
}
pub fn n(v: &Value, key: &str) -> f64 {
    v[key].as_f64().unwrap_or(0.)
}
pub fn rows(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}
pub fn exists(name: &str) -> bool {
    env::var_os("PATH").is_some_and(|p| env::split_paths(&p).any(|p| p.join(name).is_file()))
}
pub struct Lock(fs::File);
impl Lock {
    pub fn acquire(path: &Path, nonblocking: bool) -> Result<Self> {
        use std::os::fd::AsRawFd;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let f = fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path)?;
        let result = unsafe {
            libc::flock(
                f.as_raw_fd(),
                libc::LOCK_EX | if nonblocking { libc::LOCK_NB } else { 0 },
            )
        };
        if result != 0 {
            return Err(std::io::Error::last_os_error().into());
        }
        Ok(Self(f))
    }
}
pub fn try_lock(path: &Path) -> Result<Option<Lock>> {
    match Lock::acquire(path, true) {
        Ok(lock) => Ok(Some(lock)),
        Err(error)
            if error
                .downcast_ref::<std::io::Error>()
                .is_some_and(|e| e.kind() == std::io::ErrorKind::WouldBlock) =>
        {
            Ok(None)
        }
        Err(error) => Err(error),
    }
}
impl Drop for Lock {
    fn drop(&mut self) {
        use std::os::fd::AsRawFd;
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

/// GObject type registrations contain C function pointers for the process lifetime.
/// Pin optional desktop libraries so dlclose cannot invalidate those pointers.
pub fn library(name: &str) -> Result<libloading::Library> {
    Ok(unsafe {
        libloading::os::unix::Library::open(Some(name), libc::RTLD_NOW | libc::RTLD_NODELETE)
    }?
    .into())
}

/// Commands such as wl-copy fork a long-lived owner that inherits open pipes.
/// Do not collect their output: completion follows the original process, not EOF
/// from every descendant. stdin is still byte-exact and the parent has a deadline.
pub fn status(mut cmd: Command, input: Option<Vec<u8>>, timeout: Duration) -> Result<()> {
    let label = format!("{cmd:?}");
    cmd.stdout(Stdio::null())
        .stderr(Stdio::null())
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    let mut child = cmd.spawn().with_context(|| label.clone())?;
    let writer = input.map(|data| {
        let mut stream = child.stdin.take().unwrap();
        std::thread::spawn(move || stream.write_all(&data))
    });
    let status = match child.wait_timeout(timeout)? {
        Some(status) => status,
        None => {
            let _ = child.kill();
            let _ = child.wait();
            bail!("Command timed out: {label}");
        }
    };
    if let Some(writer) = writer {
        writer
            .join()
            .map_err(|_| anyhow::anyhow!("Input writer panicked"))??;
    }
    if !status.success() {
        bail!("{label}: {status}");
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn background_owner_does_not_hold_command_completion() {
        let started = std::time::Instant::now();
        status(
            command(&["/bin/sh", "-c", "sleep 1 & exit 0"]),
            None,
            Duration::from_secs(2),
        )
        .unwrap();
        assert!(started.elapsed() < Duration::from_millis(700));
    }
}

use crate::util::*;
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    time::Duration,
};
const OPTIONS: &[&str] = &[
    "--prefix=/usr",
    "--libexecdir=libexec",
    "--sysconfdir=/etc",
    "--buildtype=release",
    "-Dtests=disabled",
    "-Ddocumentation=disabled",
    "-Dman-pages=disabled",
];
pub fn digest(path: &Path) -> Result<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(path)?)))
}
fn python_json(value: &Value) -> String {
    match value {
        Value::Array(rows) => format!(
            "[{}]",
            rows.iter().map(python_json).collect::<Vec<_>>().join(", ")
        ),
        Value::Object(rows) => format!(
            "{{{}}}",
            rows.iter()
                .map(|(k, v)| format!("{}: {}", serde_json::to_string(k).unwrap(), python_json(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        _ => value.to_string(),
    }
}
pub fn recipe(repo: &Path) -> Result<Value> {
    let source = repo.join("xdg-desktop-portal");
    let release = read_json(&source.join("frontend-release.json"))?;
    let mut patches = serde_json::Map::new();
    for p in rows(&release["patches"]) {
        let name = p.as_str().context("Invalid patch filename")?;
        if Path::new(name)
            .components()
            .any(|c| !matches!(c, std::path::Component::Normal(_)))
        {
            bail!("Invalid patch path");
        }
        patches.insert(name.into(), json!(digest(&source.join(name))?));
    }
    Ok(json!({"schema":1,"release":release,"options":OPTIONS,"patches":patches}))
}
pub fn fingerprint(repo: &Path) -> Result<String> {
    Ok(format!("{:x}", Sha256::digest(python_json(&recipe(repo)?))))
}
pub fn target(repo: &Path) -> Result<PathBuf> {
    let fingerprint = fingerprint(repo)?;
    let recipe = recipe(repo)?;
    Ok(home()
        .join(".local/libexec/dotfiles/portal-releases")
        .join(format!(
            "{}-{}",
            s(&recipe["release"], "version"),
            &fingerprint[..12]
        ))
        .join("xdg-desktop-portal"))
}
pub fn verify(repo: &Path) -> Result<()> {
    let binary = target(repo)?;
    let receipt = read_json(&binary.with_file_name("release.json"))?;
    if receipt["recipe"] != recipe(repo)? || receipt["fingerprint"] != fingerprint(repo)? {
        bail!("Local portal recipe differs");
    }
    if receipt["binary_sha256"] != digest(&binary)?
        || binary.metadata()?.permissions().mode() & 0o111 == 0
    {
        bail!("Local portal checksum or permissions differ");
    }
    let version = run(&[&binary.to_string_lossy(), "--version"])?;
    if version.trim()
        != format!(
            "xdg-desktop-portal {}",
            s(&recipe(repo)?["release"], "version")
        )
    {
        bail!("Local portal version differs");
    }
    Ok(())
}
fn git(source: &Path, args: &[&str]) -> Result<String> {
    let mut c = command(&["git", "-C", &source.to_string_lossy()]);
    c.args(args);
    output(c, None, Duration::from_secs(300))
}
fn source_diff(source: &Path) -> Result<String> {
    if !git(source, &["ls-files", "--others", "--exclude-standard"])?
        .trim()
        .is_empty()
    {
        bail!("Preserving untracked portal source files");
    }
    Ok(format!(
        "{:x}",
        Sha256::digest(git(source, &["diff", "--binary", "HEAD"])?)
    ))
}
fn prepare(repo: &Path, directory: &Path) -> Result<PathBuf> {
    let source = directory.join("source");
    let marker = directory.join("source.json");
    let recipe = recipe(repo)?;
    let release = &recipe["release"];
    if !source.exists() {
        run(&["git", "init", &source.to_string_lossy()])?;
        git(
            &source,
            &[
                "fetch",
                "--depth=1",
                s(release, "url"),
                s(release, "revision"),
            ],
        )?;
        git(&source, &["checkout", "--detach", "FETCH_HEAD"])?;
    }
    if git(&source, &["rev-parse", "HEAD"])?.trim() != s(release, "revision") {
        bail!("Preserving portal source with an unexpected revision");
    }
    if marker.exists() {
        if read_json(&marker)?
            != json!({"fingerprint":fingerprint(repo)?,"diff_sha256":source_diff(&source)?})
        {
            bail!("Preserving modified portal build source");
        }
        return Ok(source);
    }
    if !git(&source, &["status", "--porcelain"])?.trim().is_empty() {
        bail!("Preserving modified portal source without a build receipt");
    }
    for patch in rows(&release["patches"]) {
        git(
            &source,
            &[
                "apply",
                &repo
                    .join("xdg-desktop-portal")
                    .join(patch.as_str().unwrap())
                    .to_string_lossy(),
            ],
        )?;
    }
    let meson = source.join("meson.build");
    let original = format!("version: '{}'", s(release, "upstream_version"));
    let text = fs::read_to_string(&meson)?;
    if text.matches(&original).count() != 1 {
        bail!("Unexpected Meson version declaration");
    }
    atomic(
        &meson,
        text.replace(&original, &format!("version: '{}'", s(release, "version")))
            .as_bytes(),
    )?;
    atomic_json(
        &marker,
        &json!({"fingerprint":fingerprint(repo)?,"diff_sha256":source_diff(&source)?}),
    )?;
    Ok(source)
}
pub fn build(repo: &Path) -> Result<()> {
    let directory = home()
        .join(".cache/dotfiles-build/xdg-desktop-portal")
        .join(fingerprint(repo)?);
    fs::create_dir_all(&directory)?;
    let _lock = Lock::acquire(&directory.join("build.lock"), false)?;
    let source = prepare(repo, &directory)?;
    let build = directory.join("build");
    let mut c = command(&["meson", "setup"]);
    if build.join("build.ninja").exists() {
        c.arg("--reconfigure");
    }
    c.arg(&build).arg(source).args(OPTIONS);
    output(c, None, Duration::from_secs(300))?;
    output(
        command(&[
            "ninja",
            "-C",
            &build.to_string_lossy(),
            "src/xdg-desktop-portal",
        ]),
        None,
        Duration::from_secs(600),
    )?;
    let built = build.join("src/xdg-desktop-portal");
    let binary = target(repo)?;
    let expected = format!(
        "xdg-desktop-portal {}",
        s(&recipe(repo)?["release"], "version")
    );
    if run(&[&built.to_string_lossy(), "--version"])?.trim() != expected {
        bail!("Built portal reports an unexpected version");
    }
    atomic(&binary, &fs::read(&built)?)?;
    fs::set_permissions(&binary, fs::Permissions::from_mode(0o755))?;
    atomic_json(
        &binary.with_file_name("release.json"),
        &json!({"recipe":recipe(repo)?,"fingerprint":fingerprint(repo)?,"binary_sha256":digest(&binary)?}),
    )?;
    verify(repo)?;
    println!("Verified {expected}: {}", binary.display());
    Ok(())
}
pub fn main(repo: &Path, args: &[String]) -> Result<()> {
    if args.iter().any(|a| a == "--check") {
        verify(repo)?;
        println!("Local portal release verified: {}", target(repo)?.display());
        Ok(())
    } else if !Path::new("/run/.containerenv").exists() && !Path::new("/.dockerenv").exists() {
        let mut c = command(&[
            "podman",
            "exec",
            "--user",
            &unsafe { libc::getuid() }.to_string(),
            "dev",
        ]);
        c.arg(std::env::current_exe()?)
            .args(["manage", "frontend"])
            .arg(repo);
        if !c.status()?.success() {
            bail!("Portal build failed in the development container");
        }
        Ok(())
    } else {
        build(repo)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_recipe_compatible_with_existing_receipts() {
        let v = json!({"b":[1,"x"],"a":{"v":true}});
        assert_eq!(python_json(&v), r#"{"a": {"v": true}, "b": [1, "x"]}"#);
        let repo = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap();
        assert_eq!(&fingerprint(repo).unwrap()[..12], "a6a7a62c3367");
    }
}

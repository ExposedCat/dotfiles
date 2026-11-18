#!/usr/bin/env python3
"""Build pinned local applications and install them on the desktop host."""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


RECIPE = Path(__file__).resolve().parent
SOURCES = json.loads((RECIPE / "sources.json").read_text())
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "dotfiles/apps"
OPENLOGI_TARGET = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles-build/openlogi/target"
BAZECOR_ID = "com.dygma.bazecor"
BAZECOR_REF = BAZECOR_ID + "//stable"
FLATPAK_BUILD = "/usr/local/libexec/dev-container/flatpak-build"
FLATHUB_REPO = "https://dl.flathub.org/repo/flathub.flatpakrepo"
IN_CONTAINER = Path("/run/.containerenv").exists() or Path("/.dockerenv").exists()
HOST = ["distrobox-host-exec"] if IN_CONTAINER else []


def run(*args, cwd=None, capture=False):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def host(*args, **kwargs):
    return run(*HOST, *args, **kwargs)


def dev(*args, cwd):
    if IN_CONTAINER:
        return run(*args, cwd=cwd)
    return host("podman", "exec", "--user", str(os.getuid()), "--workdir", cwd,
                os.environ.get("DOTFILES_BUILD_CONTAINER", "dev"), *args)


def checkout(name):
    source = SOURCES[name]
    revision = source["revision"]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise RuntimeError(f"{name}: source revision has not been finalized")
    directory = STATE / name / "source"
    directory.parent.mkdir(parents=True, exist_ok=True)
    if not directory.exists():
        run("git", "clone", source["url"], directory)
    if run("git", "status", "--porcelain", cwd=directory, capture=True):
        raise RuntimeError(f"Preserving modified build source: {directory}")
    if run("git", "remote", "get-url", "origin", cwd=directory, capture=True) != source["url"]:
        raise RuntimeError(f"Unexpected source remote: {directory}")
    run("git", "fetch", "--depth=1", "origin", revision, cwd=directory)
    run("git", "checkout", "--detach", revision, cwd=directory)
    return directory


def build_key(name):
    digest = hashlib.sha256(json.dumps(SOURCES[name], sort_keys=True).encode())
    paths = [RECIPE / "manage.py"]
    if name == "papers":
        paths.append(RECIPE / "papers.json")
    elif name == "wl-screenrec":
        paths.extend(sorted((RECIPE / "wl-screenrec").iterdir()))
    if name in ("papers", "bazecor"):
        paths.append(RECIPE.parent / "containers/dev/flatpak-build")
    for path in paths:
        digest.update(path.read_bytes())
    return digest.hexdigest()


def build(name):
    state = STATE / name
    state.mkdir(parents=True, exist_ok=True)
    marker = state / "built.json"
    key = build_key(name)
    if marker.exists():
        saved = json.loads(marker.read_text())
        artifact = Path(saved["artifact"])
        if saved["key"] == key and artifact.exists():
            print(f"{name}: using cached local build {artifact}", flush=True)
            return artifact
    source = checkout(name)
    print(f"Building {name} at {SOURCES[name]['revision']}", flush=True)
    if name == "papers":
        host("flatpak", "--user", "remote-add", "--if-not-exists", "flathub",
             FLATHUB_REPO)
        manifest = json.loads((RECIPE / "papers.json").read_text())
        manifest["modules"][-1]["sources"][0]["commit"] = SOURCES[name]["revision"]
        manifest_path = state / "papers.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        dev(FLATPAK_BUILD, "flatpak-builder", "--user", "--install-deps-from=flathub",
            "--force-clean", "--default-branch=stable",
            f"--repo={state / 'repo'}", state / "build", manifest_path, cwd=state)
        artifact = state / "repo"
    elif name == "bazecor":
        host("flatpak", "--user", "remote-add", "--if-not-exists", "flathub", FLATHUB_REPO)
        with tempfile.TemporaryDirectory(prefix=".flatpak-", dir=state) as directory:
            staging = Path(directory)
            build_source = staging / "source"
            temporary = staging / "tmp"
            temporary.mkdir()
            run("git", "clone", "--quiet", "--shared", source, build_source)
            dev("corepack", "yarn", "install", "--frozen-lockfile", cwd=build_source)
            dev(FLATPAK_BUILD, "env", f"TMPDIR={temporary}",
                f"DOTFILES_FLATPAK_RUNTIME_REPO={FLATHUB_REPO}", "DEBUG=@malept/flatpak-bundler",
                "corepack", "yarn", "make-flatpak", cwd=build_source)
            bundles = list((build_source / "out/make").rglob("*.flatpak"))
            if len(bundles) != 1:
                raise RuntimeError(f"Expected one Bazecor Flatpak bundle, found {bundles}")
            artifact = state / f"bazecor-{key[:12]}.flatpak"
            bundles[0].replace(artifact)
    elif name == "openlogi":
        toolchain = SOURCES[name]["toolchain"]
        dev("rustup", "toolchain", "install", toolchain, "--profile", "minimal", cwd=source)
        dev("env", "CARGO_PROFILE_RELEASE_DEBUG=0", "CARGO_BUILD_JOBS=4",
            "CARGO_PROFILE_RELEASE_LTO=false", "CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16",
            f"CARGO_TARGET_DIR={OPENLOGI_TARGET}",
            "cargo", f"+{toolchain}", "build", "--release", "--locked",
            "-p", "openlogi", "-p", "openlogi-agent", "--bin", "openlogi-agent",
            "--bin", "openlogi", "-p", "openlogi-desktop", "--bin", "openlogi-desktop", cwd=source)
        artifact = state / ("openlogi-" + SOURCES[name]["revision"][:12])
        (artifact / "bin").mkdir(parents=True, exist_ok=True)
        for binary in ("openlogi", "openlogi-agent", "openlogi-desktop"):
            shutil.copy2(OPENLOGI_TARGET / "release" / binary, artifact / "bin" / binary)
            dependencies = host("ldd", artifact / "bin" / binary, capture=True)
            if "not found" in dependencies:
                raise RuntimeError(f"Missing host libraries for {binary}:\n{dependencies}")
    else:
        if host("rpm", "--eval", "%{fedora} %{_arch}", capture=True) != "45 x86_64":
            raise RuntimeError("wl-screenrec RPM recipe targets Fedora 45 x86_64")
        rpmbuild = state / "rpmbuild"
        for directory in ("SOURCES", "SPECS", "RPMS", "BUILD", "BUILDROOT"):
            (rpmbuild / directory).mkdir(parents=True, exist_ok=True)
        archive = rpmbuild / "SOURCES/wl-screenrec-0.3.1.tar.gz"
        run("git", "archive", "--format=tar.gz", "--prefix=wl-screenrec-0.3.1/",
            f"--output={archive}", "HEAD", cwd=source)
        shutil.copy2(RECIPE / "wl-screenrec/wl-screenrec.spec", rpmbuild / "SPECS/wl-screenrec.spec")
        image = "localhost/dotfiles-wl-screenrec:45"
        host("podman", "build", "-t", image, "-f", RECIPE / "wl-screenrec/Containerfile",
             RECIPE / "wl-screenrec")
        host("podman", "run", "--rm", "-v", f"{rpmbuild}:/build:Z", image,
             "rpmbuild", "-bb", "/build/SPECS/wl-screenrec.spec",
             "--define", "_topdir /build", "--define", "dist .fc45")
        artifact = rpmbuild / "RPMS/x86_64/wl-screenrec-0.3.1-1.local.fc45.x86_64.rpm"
        # Local RPMs are unsigned; verify their digests rather than a missing signature.
        host("rpm", "-K", "--nosignature", artifact)
    marker.write_text(json.dumps({"key": key, "source": SOURCES[name],
                                  "artifact": str(artifact)}, indent=2) + "\n")
    return artifact


def replace_link(link, target):
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name(link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(link)


def install_device_rules(name):
    source = STATE / name / "source"
    if name == "openlogi":
        rules = source / "packaging/linux/udev/70-openlogi.rules"
    else:
        text = (source / "src/main/utils/udev.ts").read_text()
        match = re.search(r"const udevRulesToWrite = `\\\n(.*?)`;", text, re.S)
        if match is None:
            raise RuntimeError("Cannot extract Bazecor's upstream device rules")
        rules = STATE / name / "60-dygma.rules"
        rules.write_text(match[1])
    installed = subprocess.run([*HOST, "cat", "/etc/udev/rules.d/" + rules.name],
                               text=True, capture_output=True)
    needs_install = installed.returncode != 0 or installed.stdout.strip() != rules.read_text().strip()
    if name == "openlogi":
        logid = subprocess.run([*HOST, "systemctl", "is-enabled", "logid.service"],
                              text=True, capture_output=True)
        needs_install |= logid.stdout.strip() not in ("", "masked", "not-found")
    if needs_install:
        host("pkexec", "bash", RECIPE / "install-device-rules", rules)


def migrate_bazecor_profile():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    source = config / "Bazecor"
    target = Path.home() / ".var/app" / BAZECOR_ID / "config/Bazecor"
    if not source.is_dir() or target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".migrate-", dir=target.parent) as directory:
        profile = Path(directory) / "Bazecor"
        shutil.copytree(source, profile, symlinks=True, ignore=shutil.ignore_patterns(
            "Singleton*", "Cache", "Code Cache", "GPUCache", "Dawn*Cache", "Crashpad", "logs",
        ))
        if not target.exists():
            profile.rename(target)


def bazecor_bundle_commit(artifact):
    return host("/usr/bin/python3", "-c", """
import sys
import gi
gi.require_version("Flatpak", "1.0")
from gi.repository import Flatpak, Gio
bundle = Flatpak.BundleRef.new(Gio.File.new_for_path(sys.argv[1]))
print(bundle.get_commit())
""", artifact, capture=True)


def installed_bazecor_commit():
    result = subprocess.run([*HOST, "flatpak", "--user", "info", "--show-commit", BAZECOR_REF],
                            text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else None


def archive_bazecor_appimage(applications):
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    legacy = (
        (applications / "bazecor.desktop", "bazecor.desktop"),
        (Path.home() / "AppImages/bazecor.appimage", "bazecor.appimage"),
        (Path.home() / ".local/libexec/dotfiles-bazecor.py", "dotfiles-bazecor.py"),
        (Path.home() / ".local/share/icons/hicolor/512x512/apps/bazecor.png", "bazecor.png"),
        (cache / "dotfiles/bazecor", "extracted-cache"),
    )
    existing = [(path, name) for path, name in legacy if path.exists()]
    if not existing:
        return
    backup = STATE / "bazecor" / datetime.now(timezone.utc).strftime("appimage-%Y%m%dT%H%M%S.%fZ")
    backup.mkdir(mode=0o700)
    for path, name in existing:
        shutil.move(path, backup / name)
    print(f"Previous Bazecor launcher and AppImage backed up to {backup}", flush=True)


def install(name, artifact):
    applications = Path.home() / ".local/share/applications"
    applications.mkdir(parents=True, exist_ok=True)
    installed = {"source": SOURCES[name], "artifact": str(artifact)}
    if name == "papers":
        origin = "papers-local"
        remotes = host("flatpak", "--user", "remotes", "--columns=name", capture=True).splitlines()
        if origin in remotes:
            host("flatpak", "--user", "remote-modify", f"--url={artifact.as_uri()}", origin)
        else:
            host("flatpak", "--user", "remote-add", "--no-gpg-verify", origin, artifact)
        host("flatpak", "--user", "install", "--noninteractive", "--or-update",
             origin, "org.gnome.Papers//stable")
        installed_origin = host("flatpak", "--user", "info", "--show-origin",
                                "org.gnome.Papers//stable", capture=True)
        if installed_origin != origin:
            raise RuntimeError("Papers fork was not installed; preserving the system copy")
        # Keep application data. Remove the system copy only after the fork is installed.
        system_apps = host("flatpak", "--system", "list", "--app", "--columns=application",
                           capture=True).splitlines()
        if "org.gnome.Papers" in system_apps:
            host("flatpak", "--system", "uninstall", "--noninteractive", "org.gnome.Papers")
        host("xdg-mime", "default", "org.gnome.Papers.desktop", "application/pdf")
    elif name == "bazecor":
        install_device_rules(name)
        commit = bazecor_bundle_commit(artifact)
        if installed_bazecor_commit() != commit:
            host("flatpak", "--user", "install", "--noninteractive", "--or-update", "--bundle", artifact)
            if installed_bazecor_commit() != commit:
                raise RuntimeError("Installed Bazecor Flatpak differs from the local bundle")
        installed["commit"] = commit
        location = host("flatpak", "--user", "info", "--show-location", BAZECOR_REF, capture=True)
        entry = Path(location) / "export/share/applications" / (BAZECOR_ID + ".desktop")
        if not entry.is_file():
            raise RuntimeError("Bazecor Flatpak did not export an application-menu entry")
        migrate_bazecor_profile()
        archive_bazecor_appimage(applications)
    elif name == "openlogi":
        install_device_rules(name)
        config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "openlogi/config.toml"
        if config.exists():
            backup = STATE / name / ("config-before-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + ".toml")
            shutil.copy2(config, backup)
            backup.chmod(0o600)
        opt = Path.home() / ".local/opt/openlogi"
        destination = opt / artifact.name
        if not destination.exists():
            shutil.copytree(artifact, destination)
        replace_link(opt / "current", destination)
        for binary in ("openlogi", "openlogi-agent", "openlogi-desktop"):
            replace_link(Path.home() / ".local/bin" / binary, opt / "current/bin" / binary)
        desktop = applications / "openlogi.desktop"
        entry = (STATE / name / "source/packaging/linux/desktop/openlogi.desktop").read_text()
        desktop.write_text(entry.replace("Exec=openlogi-desktop", f"Exec={opt}/current/bin/openlogi-desktop"))
        icon = Path.home() / ".local/share/icons/hicolor/128x128/apps/openlogi.png"
        icon.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(STATE / name / "source/design/icon/openlogi-128.png", icon)
        unit = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "systemd/user/openlogi-agent.service"
        unit.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(RECIPE / "openlogi-agent.service", unit)
        host("systemctl", "--user", "daemon-reload")
        host("systemctl", "--user", "reenable", "openlogi-agent.service")
        session = subprocess.run([*HOST, "systemctl", "--user", "is-active", "--quiet",
                                  "graphical-session.target"])
        if session.returncode == 0:
            host("systemctl", "--user", "restart", "openlogi-agent.service")
    else:
        nevra = host("rpm", "-qp", "--qf", "%{NEVRA}", artifact, capture=True)
        installed_rpm = subprocess.run([*HOST, "rpm", "-q", "--qf", "%{NEVRA}", "wl-screenrec"],
                                       capture_output=True, text=True)
        if installed_rpm.returncode == 0 and installed_rpm.stdout == nevra:
            print(f"Already installed: {nevra}")
        else:
            host("rpm-ostree", "install", "--idempotent", artifact)
            print("wl-screenrec staged; reboot normally to activate the RPM.")
    (STATE / name / "installed.json").write_text(json.dumps(installed, indent=2) + "\n")


def check(name):
    marker = STATE / name / "installed.json"
    if name == "wl-screenrec":
        marker = STATE / name / "built.json"
    saved = json.loads(marker.read_text())
    if saved["source"] != SOURCES[name] or not Path(saved["artifact"]).exists():
        raise RuntimeError(f"{name}: installed/built revision differs from sources.json")
    if name == "papers":
        if host("flatpak", "--user", "info", "--show-origin", "org.gnome.Papers//stable",
                capture=True) != "papers-local":
            raise RuntimeError("Papers is not installed from the local fork repository")
        location = host("flatpak", "--user", "info", "--show-location", "org.gnome.Papers//stable", capture=True)
        manifest = json.loads((Path(location) / "files/manifest.json").read_text())
        if manifest["modules"][-1]["sources"][0]["commit"] != SOURCES[name]["revision"]:
            raise RuntimeError("Installed Papers manifest has a different source revision")
    elif name == "bazecor":
        if not saved.get("commit") or saved["commit"] != installed_bazecor_commit():
            raise RuntimeError("Installed Bazecor Flatpak differs from the local build")
    elif name == "openlogi":
        current = Path.home() / ".local/opt/openlogi/current"
        if current.resolve().name != "openlogi-" + SOURCES[name]["revision"][:12]:
            raise RuntimeError("OpenLogi points at a different build")
        host("systemctl", "--user", "is-enabled", "--quiet", "openlogi-agent.service")
        session = subprocess.run([*HOST, "systemctl", "--user", "is-active", "--quiet", "graphical-session.target"])
        if session.returncode == 0:
            host("systemctl", "--user", "is-active", "--quiet", "openlogi-agent.service")
    else:
        host("rpm", "-K", "--nosignature", saved["artifact"])
        requires = host("rpm", "-qp", "--requires", saved["artifact"], capture=True)
        if "libavcodec.so.63" not in requires:
            raise RuntimeError("wl-screenrec RPM was not linked against FFmpeg 9")
    print(f"{name}: pinned revision verified", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "install", "check"))
    parser.add_argument("app", choices=(*SOURCES, "all"), default="all", nargs="?")
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    for name in SOURCES if args.app == "all" else (args.app,):
        (STATE / name).mkdir(parents=True, exist_ok=True)
        with (STATE / name / "manage.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.action == "check":
                check(name)
                continue
            artifact = build(name)
            if args.action == "install":
                install(name, artifact)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))

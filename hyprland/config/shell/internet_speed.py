#!/usr/bin/env python3
"""On-demand Internet bandwidth measurement against Cloudflare's public test API."""

from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid


STREAMS = 4
PROBE_BYTES = 256 * 1024
MAX_BYTES = 32 * 1024 * 1024
TARGET_SECONDS = 1.5
TRANSFER_TIMEOUT = 8


class SpeedTestError(RuntimeError):
    pass


def transfer(direction, size, upload_path=None):
    """Measure synthetic payload bytes and the time spent transferring them."""
    command = [
        "/usr/bin/curl", "--disable", "--silent", "--show-error", "--fail",
        "--connect-timeout", "5", "--max-time", str(TRANSFER_TIMEOUT),
        "--proto", "=https", "--header", "Cache-Control: no-store",
        "--header", "Accept-Encoding: identity", "--output", os.devnull,
        "--write-out", "%{json}",
    ]
    nonce = uuid.uuid4().hex
    if direction == "download":
        command.append(f"https://speed.cloudflare.com/__down?bytes={size}&nonce={nonce}")
    else:
        command += ["--request", "POST", "--upload-file", str(upload_path),
                    "--header", "Content-Type: application/octet-stream", "--header", "Expect:",
                    f"https://speed.cloudflare.com/__up?nonce={nonce}"]
    response = subprocess.run(command, capture_output=True, text=True, timeout=TRANSFER_TIMEOUT + 3)
    finished = time.monotonic()
    try:
        data = json.loads(response.stdout)
        transferred = float(data["size_download" if direction == "download" else "size_upload"])
        total = float(data["time_total"])
        # Upload time_starttransfer is the response AFTER sending the payload;
        # subtracting it would incorrectly report an almost infinite upload rate.
        ready = float(data["time_starttransfer" if direction == "download" else "time_pretransfer"])
        valid = (int(data["http_code"]) == 200 and transferred > 0 and total > ready >= 0
                 and all(math.isfinite(v) for v in (transferred, total, ready)))
        # A bounded download may time out after delivering useful payload. An
        # upload must finish and receive the server's successful acknowledgement.
        partial_download = direction == "download" and response.returncode == 28 and transferred >= 65536
        if not valid or (response.returncode != 0 and not partial_download):
            raise SpeedTestError(f"{direction} request failed (curl {response.returncode}, HTTP {data.get('http_code')})")
        if response.returncode == 0 and int(transferred) != size:
            raise SpeedTestError(f"{direction} returned an unexpected payload size")
        return {"bytes": transferred, "start": finished - total + ready, "end": finished}
    except (KeyError, TypeError, ValueError) as error:
        raise SpeedTestError(f"Invalid {direction} measurement") from error


def aggregate(samples):
    elapsed = max(s["end"] for s in samples) - min(s["start"] for s in samples)
    count = sum(s["bytes"] for s in samples)
    if elapsed <= 0 or count <= 0 or not math.isfinite(elapsed):
        raise SpeedTestError("No usable transfer measurement")
    return {"mbps": count * 8 / elapsed / 1_000_000, "seconds": elapsed}


def measure_direction(direction, upload_path=None):
    def prepare(size):
        if direction == "upload":
            # A sparse zero-filled file supplies synthetic data without buffering
            # four large request bodies in Python or reading any user files.
            with upload_path.open("wb") as payload:
                payload.truncate(size)

    prepare(PROBE_BYTES)
    probe = aggregate([transfer(direction, PROBE_BYTES, upload_path)])
    size = min(MAX_BYTES, max(PROBE_BYTES, int(probe["mbps"] * 1_000_000 / 8 * TARGET_SECONDS / STREAMS)))
    for _ in range(3):
        prepare(size)
        with ThreadPoolExecutor(max_workers=STREAMS) as pool:
            futures = [pool.submit(transfer, direction, size, upload_path) for _ in range(STREAMS)]
            sample = aggregate([future.result() for future in futures])
        if sample["seconds"] >= 0.9 or size == MAX_BYTES:
            break
        size = min(MAX_BYTES, int(size * max(2, TARGET_SECONDS / sample["seconds"])))
    return sample["mbps"]


def measure(progress):
    with tempfile.TemporaryDirectory(prefix="internet-speed-") as temporary:
        progress({"phase": "download"})
        download = measure_direction("download")
        progress({"phase": "upload"})
        upload = measure_direction("upload", Path(temporary) / "payload.bin")
    return {"download": round(download, 1), "upload": round(upload, 1),
            "measuredAt": int(time.time() * 1000), "provider": "Cloudflare"}


def cache_path():
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles/hyprland/internet-speed.json"


def save_result(result, path=None):
    path = path or cache_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".internet-speed-", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump({"version": 1, "result": result}, stream)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def run_cli():
    def emit(data):
        print(json.dumps(data), flush=True)
    try:
        result = measure(emit)
        try:
            save_result(result)
        except OSError as error:
            print(f"Could not cache speed result: {error}", file=sys.stderr)
        emit({"result": result})
        return 0
    except (SpeedTestError, OSError, subprocess.SubprocessError) as error:
        print(f"Internet speed test: {error}", file=sys.stderr)
        emit({"error": "Speed test failed. Try again."})
        return 1


if __name__ == "__main__":
    raise SystemExit(run_cli())

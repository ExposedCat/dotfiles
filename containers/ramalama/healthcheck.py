#!/usr/bin/env python3
"""Healthcheck for the ramalama service.

Healthy while the container is making progress, not only when it is serving:
  - llama-server answers /health with 200            -> ready
  - llama-server answers /health with 503            -> loading the model
  - a *.partial file in the model store keeps growing -> downloading the model
Anything else (port closed and no download activity) is unhealthy.
"""

import os
import sys
import time
import urllib.error
import urllib.request

URL = "http://127.0.0.1:8080/health"
STORE = "/models"
# A download counts as alive if its .partial file was written to recently.
DOWNLOAD_STALE_SECONDS = 120


def server_status():
    try:
        with urllib.request.urlopen(URL, timeout=5) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except OSError:
        return None


def active_download():
    now = time.time()
    for root, _dirs, files in os.walk(STORE):
        for name in files:
            if not name.endswith(".partial"):
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
            except OSError:
                continue
            if now - st.st_mtime < DOWNLOAD_STALE_SECONDS:
                return path, st.st_size
    return None


status = server_status()
if status == 200:
    print("ready")
    sys.exit(0)
if status == 503:
    print("loading model")
    sys.exit(0)

download = active_download()
if download:
    path, size = download
    print(f"downloading {os.path.basename(os.path.dirname(os.path.dirname(path)))}: {size / 1e9:.1f} GB")
    sys.exit(0)

print(f"not serving (http status: {status}) and no active download")
sys.exit(1)

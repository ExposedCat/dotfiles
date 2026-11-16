"""Test-only adapters for the compiled runtime; no production Python dependency."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

NAME = 'org.freedesktop.impl.portal.desktop.dotfiles'
PATH = '/org/freedesktop/portal/desktop'
PREFIX = 'org.freedesktop.impl.portal.'
BINARY = Path(os.environ.get('DOTFILES_DESKTOP_BINARY', Path.home() / '.config/hypr/bin/dotfiles-desktop'))


def atomic_json(path, data):
    temporary = path.with_suffix('.test-tmp')
    temporary.write_text(json.dumps(data))
    temporary.replace(path)


class Dialog:
    """Exercise the real Rust CLI and its real transport, including cancellation."""
    def __init__(self, data):
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        self.temporary = tempfile.TemporaryDirectory(prefix='native-fixture-', dir=runtime)
        source = Path(self.temporary.name) / 'input.json'
        atomic_json(source, data)
        previous = set(runtime.glob('dotfiles-portal-*'))
        self.process = subprocess.Popen([str(BINARY), 'portal', 'preview', str(source)],
                                        stdout=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 3
        while True:
            candidates = set(runtime.glob('dotfiles-portal-*')) - previous
            if candidates:
                self.directory = candidates.pop()
                break
            if self.process.poll() is not None or time.monotonic() > deadline:
                self.close()
                raise RuntimeError('Native portal did not create its request')
            time.sleep(.005)
        self.cached_result = None

    def update(self, data):
        atomic_json(self.directory / 'request.json', data)

    def result(self):
        if self.cached_result is None:
            assert self.process.poll() is not None, 'Portal response is not ready'
            self.cached_result = json.loads(self.process.stdout.read())
        return self.cached_result

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=3)
        if self.process.stdout:
            self.process.stdout.close()
        self.temporary.cleanup()


def share_result(result, sources):
    # Protocol expectation, kept deliberately independent of the Rust validator.
    if result.get('response') != 0:
        return ''
    identity = result['choice']
    region = result.get('region')
    if region:
        source = next(row for group in sources for row in group if row['id'] == identity)
        identity = 'region:' + source['output'] + '@' + ','.join(map(str, region))
    return '[SELECTION]' + ('r' if result.get('remember') else '') + '/' + identity

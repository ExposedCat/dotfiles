"""Run a finite QML integration fixture on a nested private Wayland compositor."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Run through isolated-gui; this test creates windows')
fixture=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='native-ui-',dir=os.environ['XDG_RUNTIME_DIR']) as temporary:
    directory=Path(temporary)
    runtime=Path(os.environ['XDG_RUNTIME_DIR'])
    (directory/'sway.conf').write_text('output * mode 1200x800\nseat * hide_cursor 10000\n')
    env=dict(os.environ,WLR_BACKENDS='x11',WLR_RENDERER='pixman',WLR_LIBINPUT_NO_DEVICES='1')
    with (directory/'sway.log').open('w') as log:
        compositor=subprocess.Popen(['/usr/bin/sway','--unsupported-gpu','-c',str(directory/'sway.conf')],env=env,stdout=log,stderr=log)
        try:
            deadline=time.monotonic()+8
            while True:
                display=next((p for p in runtime.glob('wayland-*') if p.is_socket()),None)
                if display:break
                if time.monotonic()>deadline or compositor.poll() is not None:
                    raise RuntimeError('No private Wayland compositor')
                time.sleep(.025)
            env.update(QT_QPA_PLATFORM='wayland',WAYLAND_DISPLAY=display.name,
                       XDG_STATE_HOME=str(directory/'state'),XDG_CACHE_HOME=str(directory/'cache'),
                       XDG_CONFIG_HOME=str(directory/'config'))
            result=subprocess.run(['/usr/bin/quickshell','--no-color','--path',str(fixture)],env=env,
                                  text=True,capture_output=True,timeout=35)
            print(result.stdout+result.stderr,flush=True)
            assert result.returncode==0 and 'BACKEND UI PASS:' in result.stdout+result.stderr,result
        finally:
            compositor.terminate();compositor.wait(timeout=5)

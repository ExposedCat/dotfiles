#!/usr/bin/env python3
"""Real two-output selection and off-window composition; isolated-gui only."""
import json
import os
from pathlib import Path
import subprocess
import socket
import struct
import tempfile
import time

assert 'agent-desktops' in os.environ.get('XDG_RUNTIME_DIR', ''), 'Use isolated-gui'
SOURCE = Path(__file__).resolve().parents[1] / 'config/tools'
QML = Path(__file__).with_name('capture-input.qml')

def wait_for(check, message, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.04)
    raise AssertionError(message)

class VirtualPointer:
    """Small test client for wlr-virtual-pointer-v1 on the private compositor."""
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(3)
        self.socket.connect(str(path))
        self.buffer = b""
        self.globals = {}
        self.serial = 3
        self.send(1, 1, struct.pack("=I", 2))  # wl_display.get_registry
        self.sync()
        name = self.globals["zwlr_virtual_pointer_manager_v1"]
        interface = b"zwlr_virtual_pointer_manager_v1\0"
        encoded = struct.pack("=II", name, len(interface)) + interface + b"\0" * (-len(interface) % 4)
        self.send(2, 0, encoded + struct.pack("=II", 1, 4))
        self.send(4, 0, struct.pack("=II", 0, 5))
        self.serial = 6
        self.sync()
    def send(self, obj, opcode, data=b""):
        self.socket.sendall(struct.pack("=II", obj, ((len(data)+8)<<16)|opcode)+data)
    def sync(self):
        callback = self.serial; self.serial += 1
        self.send(1, 0, struct.pack("=I", callback))
        while True:
            while len(self.buffer) < 8:
                data = self.socket.recv(65536)
                if not data: raise RuntimeError("Private compositor closed the virtual-pointer client")
                self.buffer += data
            obj, header = struct.unpack_from("=II", self.buffer)
            size, opcode = header >> 16, header & 65535
            while len(self.buffer) < size:
                data = self.socket.recv(65536)
                if not data: raise RuntimeError("Private compositor closed the virtual-pointer client")
                self.buffer += data
            payload, self.buffer = self.buffer[8:size], self.buffer[size:]
            if obj == 2 and opcode == 0:
                name, length = struct.unpack_from("=II", payload)
                self.globals[payload[8:8+length-1].decode()] = name
            if obj == callback:
                break
    def cursor(self, command):
        now = int(time.monotonic()*1000) & 0xffffffff
        parts = command.split()
        if parts[0] == "set":
            self.send(5, 1, struct.pack("=IIIII", now, int(parts[1])+800, int(parts[2]), 1600, 700))
        else:
            self.send(5, 2, struct.pack("=III", now, 273 if parts[1] == "button3" else 272, int(parts[0] == "press")))
        self.send(5, 4)
        self.sync()
        time.sleep(.1)

with tempfile.TemporaryDirectory(prefix='capture-multi-', dir=os.environ['XDG_RUNTIME_DIR']) as temporary:
    root = Path(temporary)
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    (root/'sway.conf').write_text('output HEADLESS-1 mode 800x600 pos -800 0\noutput HEADLESS-2 mode 1600x1200 scale 2 pos 0 100\ndefault_floating_border none\n')
    env = dict(os.environ, WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')
    log = (root/'qml.log').open('w')
    compositor = subprocess.Popen(['/usr/bin/sway', '--unsupported-gpu', '-c', str(root/'sway.conf')], env=env, stdout=log, stderr=log)
    shell = None
    try:
        display_socket = wait_for(lambda: next((p for p in runtime.glob('wayland-*') if p.is_socket()), None), 'No Wayland display')
        sway = wait_for(lambda: next(runtime.glob('sway-ipc.*.sock'), None), 'No Sway IPC')
        env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=display_socket.name, SWAYSOCK=str(sway),
                   DOTFILES_CAPTURE_SOURCE=str(SOURCE), DOTFILES_CAPTURE_SESSION=str(root),
                   DOTFILES_SHELL_FIXTURE=str(root/'empty.json'), XDG_STATE_HOME=str(root/'state'),
                   XDG_CACHE_HOME=str(root/'cache'), XDG_CONFIG_HOME=str(root/'config'))
        (root/'empty.json').write_text('{}');(root/'config').mkdir();(root/'pictures').mkdir()
        (root/'config/user-dirs.dirs').write_text(f'XDG_PICTURES_DIR="{root}/pictures"\n')
        outputs = []
        for name, x, y, scale, color in [('HEADLESS-1',-800,0,1,b'\xff\x00\x00'),('HEADLESS-2',0,100,2,b'\x00\xff\x00')]:
            image = root/(name+'.ppm');w,h=800*scale,600*scale
            image.write_bytes(f'P6\n{w} {h}\n255\n'.encode()+color*(w*h))
            outputs.append(dict(name=name,x=x,y=y,width=800,height=600,scale=scale,focused=x<0,plain=image.as_uri(),cursor=image.as_uri()))
        data = dict(mode='region',render=str(root/'render.png'),selection=None,outputs=outputs)
        (root/'session.json').write_text(json.dumps(data))
        shell = subprocess.Popen(['/usr/bin/quickshell','--path',str(QML)],env=env,stdout=log,stderr=log)
        def ipc(method, *args):
            r=subprocess.run(['/usr/bin/quickshell','ipc','--path',str(QML),'call','captureInputTest',method,*args],env=env,capture_output=True,text=True,timeout=2)
            return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None
        def state():return ipc('state')
        pointer = VirtualPointer(display_socket)
        cursor = pointer.cursor
        wait_for(lambda:state(),'No test shell')
        assert ipc('open') is True
        wait_for(lambda:len(state()['frames'])==2,'Both surfaces did not render')
        cursor('set -100 200');cursor('press button1');cursor('set 200 400');cursor('release button1')
        selected=state()
        assert selected['selection']==dict(x=-100,y=200,width=300,height=200),selected
        assert selected['current']=='HEADLESS-2',selected
        assert selected['tool']=='',selected
        def drag(start, end, button='button1'):
            cursor(f'set {start[0]} {start[1]}');cursor('press '+button)
            cursor(f'set {end[0]} {end[1]}')
            cursor('release '+button)
        def chooseTool(name):
            point=ipc('toolbarPoint',name)
            drag((round(point['x']),round(point['y'])),(round(point['x']),round(point['y'])))
            return True
        def expect(rect):
            assert state()['selection']==rect,state()
        # No tool: drag inside to move; retain dimensions and clamp at desktop edges.
        drag((-50,250),(0,280))
        expect(dict(x=-50,y=230,width=300,height=200))
        drag((-25,260),(790,690))
        expect(dict(x=500,y=500,width=300,height=200))
        # Annotation tools toggle on/off; outside drags always reselect.
        assert chooseTool('arrow') is True
        assert state()['tool']=='arrow',state()
        drag((300,150),(550,320))
        expect(dict(x=300,y=150,width=250,height=170))
        assert state()['strokes']==[],state()
        # RMB overrides the selected tool even inside the existing selection.
        drag((350,180),(460,270),'button3')
        expect(dict(x=350,y=180,width=110,height=90))
        assert state()['tool']=='arrow' and state()['strokes']==[],state()
        drag((360,190),(420,240))
        expect(dict(x=350,y=180,width=110,height=90))
        assert len(state()['strokes'])==1 and state()['strokes'][0]['type']=='arrow',state()
        assert chooseTool('arrow') is True
        assert state()['tool']=='',state()
        drag((370,200),(400,220))
        expect(dict(x=380,y=200,width=110,height=90))
        drag((-200,150),(-100,180))
        expect(dict(x=-200,y=150,width=100,height=30))
        # Restore a region spanning the seam, then test RMB over a text editor.
        drag((-100,200),(200,400),'button3')
        assert chooseTool('text') is True
        drag((-50,250),(-50,250))
        assert state()['editing'],state()
        drag((-40,260),(-10,350),'button3')
        expect(dict(x=-40,y=260,width=30,height=90))
        assert not state()['editing'] and state()['sceneFocused'],state()
        assert chooseTool('text') is True
        # RMB can also begin directly on the toolbar's buttons.
        point=ipc('toolbarPoint','pen')
        drag((round(point['x']),round(point['y'])),(-200,500),'button3')
        expect(dict(x=min(round(point['x']),-200),y=min(round(point['y']),500),
                    width=abs(round(point['x'])+200),height=abs(round(point['y'])-500)))
        drag((-100,200),(200,400),'button3')
        expect(selected['selection'])
        ipc('toggleCursor');ipc('paintAcross')
        # Capture the selector before export, wholly inside the private compositor.
        screenshot=Path(os.environ.get('DOTFILES_CAPTURE_PREVIEW',str(root/'preview.png')))
        subprocess.run(['/usr/bin/grim',str(screenshot)],env=env,check=True)
        ipc('finishSelection')
        wait_for(lambda:not state()['active'],'Cross-output export did not finish')
        files=list((root/'pictures/Screenshots').glob('*.png'));assert len(files)==1,files
        # ImageMagick is local to the isolated container; no desktop access.
        size=subprocess.check_output(['/usr/bin/magick','identify','-format','%wx%h',str(files[0])],text=True)
        assert size=='600x400',size
        pixels=subprocess.check_output(['/usr/bin/magick',str(files[0]),'-depth','8','rgb:-'])
        def pixel(x,y):return tuple(pixels[(y*600+x)*3:(y*600+x)*3+3])
        assert pixel(100,200)==(255,0,0),pixel(100,200)
        assert pixel(400,200)==(0,255,0),pixel(400,200)
        assert pixel(200,20)==(255,255,255),pixel(200,20) # Annotation crosses the monitor seam.
        prefs=root/'state/dotfiles/hyprland/capture.json'
        wait_for(prefs.is_file,'Preferences were not saved')
        saved=json.loads(prefs.read_text());assert saved['cursor'] and saved['region']==selected['selection'],saved
        # Real shader export: dense content must become heavily blurred, with
        # rounded corners and the same annotation order as the visible preview.
        checkers=[]
        for output in outputs:
            scale=output['scale'];w,h=800*scale,600*scale
            image=root/('checker-'+output['name']+'.ppm')
            rows=[]
            for y in range(h):
                a=b'\xff\xff\xff' if (y//(4*scale))%2 else b'\x00\x00\x00'
                b=b'\x00\x00\x00' if (y//(4*scale))%2 else b'\xff\xff\xff'
                rows.append((a*(4*scale)+b*(4*scale))*(w//(8*scale)))
            image.write_bytes(f'P6\n{w} {h}\n255\n'.encode()+b''.join(rows))
            checkers.append(dict(output,plain=image.as_uri(),cursor=image.as_uri()))
        blur_data=dict(data,outputs=checkers,selection=selected['selection'])
        (root/'session.json').write_text(json.dumps(blur_data))
        assert ipc('open') is True
        wait_for(lambda:len(state()['frames'])==2,'Blur surfaces did not render')
        # White annotations make stroke order measurable in the final PNG.
        ipc('whiteInk')
        chooseTool('box');drag((-60,270),(140,330))
        chooseTool('blur');drag((-80,220),(180,380))
        assert state()['strokes'][-1]['type']=='blur',state()
        # A second patch exercises nested blur layers without losing the first.
        drag((-25,290),(100,350))
        assert len(state()['strokes'])==3 and state()['strokes'][-1]['type']=='blur',state()
        chooseTool('pen');drag((-50,360),(150,360))
        time.sleep(.3)
        if os.environ.get('DOTFILES_BLUR_PREVIEW'):
            subprocess.run(['/usr/bin/grim',os.environ['DOTFILES_BLUR_PREVIEW']],env=env,check=True)
        ipc('finishSelection');wait_for(lambda:not state()['active'],'Blur export did not finish')
        files=list((root/'pictures/Screenshots').glob('*.png'));assert len(files)==2,files
        blurred=max(files,key=lambda f:f.stat().st_mtime_ns)
        pixels=subprocess.check_output(['/usr/bin/magick',str(blurred),'-depth','8','rgb:-'])
        for point in [(200,140),(200,200),(60,60)]:
            value=pixel(*point)
            assert all(70 < channel < 215 for channel in value),('Blur missing or too weak',point,value)
        assert min(pixel(200,320))>230,('Later annotation was blurred',pixel(200,320))
        assert min(pixel(43,43))>230,('Blur corner is not rounded',pixel(43,43))
        assert max(pixel(10,20))<25,('Outside pixels changed',pixel(10,20))
        if os.environ.get('DOTFILES_BLUR_EXPORT'):
            Path(os.environ['DOTFILES_BLUR_EXPORT']).write_bytes(blurred.read_bytes())
        # Removing a blur must restore original pixels, not leave a cached mask.
        assert ipc('open') is True
        wait_for(lambda:len(state()['frames'])==2,'Undo surfaces did not render')
        chooseTool('blur');drag((-80,220),(180,380));ipc('undoStroke')
        assert state()['strokes']==[],state()
        time.sleep(.2);ipc('finishSelection')
        wait_for(lambda:not state()['active'],'Undo export did not finish')
        restored=max((root/'pictures/Screenshots').glob('*.png'),key=lambda f:f.stat().st_mtime_ns)
        pixels=subprocess.check_output(['/usr/bin/magick',str(restored),'-depth','8','rgb:-'])
        assert min(pixel(200,200))>230 or max(pixel(200,200))<25,('Undo did not restore detail',pixel(200,200))

        data['preferences']=saved;(root/'session.json').write_text(json.dumps(data))
        assert ipc('open') is True
        wait_for(lambda:state()['active'],'Restored selector did not open')
        assert state()['selection']==selected['selection'] and state()['cursor'],state()
        # Cancel through the real controller IPC without any external service.
        subprocess.run(['/usr/bin/quickshell','ipc','--path',str(QML),'call','capture','cancel'],env=env,check=True)
        wait_for(lambda:not state()['active'],'Cancel did not finish')
        data['mode']='record'
        data['preferences']['record']=dict(x=-200,y=250,width=400,height=160)
        (root/'session.json').write_text(json.dumps(data))
        assert ipc('open') is True
        wait_for(lambda:state()['active'],'Recording test selector did not open')
        assert state()['selection']==data['preferences']['record'],state()
        assert state()['preferences']['region']==selected['selection'],state()
        args=ipc('prepareRecord')
        index=args.index('record')
        assert args[index+1:index+7]==['desktop','-200','250','400','160','yes'],args
        assert state()['recordPending'] and not state()['recording'],state()
        ipc('abortRecord');wait_for(lambda:not state()['active'],'Recording test did not cancel')
        # Dismissal waits for an in-progress RMB drag to release its grab.
        assert ipc('open') is True
        wait_for(lambda:state()['active'],'Drag-cancel selector did not open')
        cursor('set -150 280');cursor('press button3')
        assert state()['dragging'],state()
        subprocess.run(['/usr/bin/quickshell','ipc','--path',str(QML),'call','capture','cancel'],env=env,check=True)
        assert state()['active'] and state()['closePending'],state()
        cursor('set 50 380');cursor('release button3')
        wait_for(lambda:not state()['active'],'Pending cancel did not finish on mouse release')
        assert not state()['dragging'],state()
        print('CAPTURE MULTISCREEN PASS: tool toggling, inside movement, bounds, outside/RMB reselection, text/toolbar RMB, cross-output drag, negative coordinates, staggered mixed-scale displays, seam-spanning annotations, exact export, rounded heavy blur, annotation order, blur undo, and persisted cursor/region')
    except Exception:
        log.flush();print((root/'qml.log').read_text());raise
    finally:
        if shell:shell.terminate();shell.wait(timeout=5)
        compositor.terminate();compositor.wait(timeout=5)
        log.close()

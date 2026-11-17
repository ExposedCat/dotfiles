"""Real FFmpeg/Pulse inputs on a private, hardware-free PipeWire graph."""
import array
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time

if not os.environ.get('ISOLATED_GUI_SESSION'):
    raise SystemExit('Use isolated-gui; this test owns a private audio session')
binary=os.environ['DOTFILES_DESKTOP_BINARY']
with tempfile.TemporaryDirectory(prefix='recording-audio-',dir=os.environ['XDG_RUNTIME_DIR']) as temporary:
    root=Path(temporary)
    runtime=Path(os.environ['XDG_RUNTIME_DIR'])  # Keep Unix socket paths below 108 bytes.
    config=root/'config/wireplumber/wireplumber.conf.d';config.mkdir(parents=True)
    (config/'recording-test.conf').write_text('''wireplumber.profiles = {
      recording-test = {
        inherits = [ base ]
        metadata.sm-settings = required
        metadata.sm-objects = required
        policy.standard = required
        hardware.audio = disabled
        hardware.bluetooth = disabled
        hardware.video-capture = disabled
        monitor.alsa = disabled
        monitor.bluez = disabled
        monitor.bluez-midi = disabled
        monitor.alsa-midi = disabled
        monitor.v4l2 = disabled
        monitor.libcamera = disabled
      }
    }\n''')
    env=dict(os.environ,PIPEWIRE_RUNTIME_DIR=str(runtime),PIPEWIRE_REMOTE='pipewire-0',
             PULSE_SERVER=f'unix:{runtime}/pulse/native',PULSE_RUNTIME_PATH=str(runtime/'pulse'),
             XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'))
    processes=[];logs=[]
    def launch(name,args):
        log=(root/(name+'.log')).open('w');logs.append(log)
        child=subprocess.Popen(args,env=env,stdout=log,stderr=log);processes.append(child);return child
    def run(args,**kwargs):
        result=subprocess.run(args,env=env,capture_output=True,timeout=15,**kwargs)
        if result.returncode:
            raise AssertionError((args,result.stderr))
        return result
    def wait_for(check,message):
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            if check():return
            if any(p.poll() is not None for p in processes):break
            time.sleep(.05)
        raise AssertionError(message)
    def tone_amplitude(samples,frequency):
        # Measure coherent tone energy without a NumPy dependency.
        omega=2*math.pi*frequency/48000
        real=sum(x*math.cos(omega*i) for i,x in enumerate(samples))
        imag=sum(x*math.sin(omega*i) for i,x in enumerate(samples))
        return 2*math.hypot(real,imag)/len(samples)
    try:
        launch('pipewire',['/usr/bin/pipewire'])
        wait_for(lambda:(runtime/'pipewire-0').is_socket(),'No private PipeWire socket')
        launch('pulse',['/usr/bin/pipewire-pulse'])
        wait_for(lambda:(runtime/'pulse/native').is_socket(),'No private Pulse socket')
        launch('policy',['/usr/bin/wireplumber','--profile','recording-test'])
        for name in ('speakers_fixture','mic_fixture'):
            run(['/usr/bin/pactl','load-module','module-null-sink',f'sink_name={name}'])
        wait_for(lambda: all(name in run(['/usr/bin/pactl','list','short','sinks'],text=True).stdout for name in ('speakers_fixture','mic_fixture')),'Private sinks did not appear')
        wait_for(lambda: subprocess.run(['/usr/bin/pactl','set-default-sink','speakers_fixture'],env=env,capture_output=True).returncode==0,'Private policy metadata did not become ready')
        run(['/usr/bin/pactl','set-default-source','mic_fixture.monitor'])
        nodes=json.loads(run(['/usr/bin/pw-dump'],text=True).stdout)
        assert not any(str(n.get('info',{}).get('props',{}).get('node.name','')).startswith(('alsa_','bluez_')) for n in nodes),'Hardware monitor unexpectedly enabled'
        for name,frequency in [('speakers_fixture',440),('mic_fixture',880)]:
            launch(name,['/usr/bin/ffmpeg','-nostdin','-hide_banner','-loglevel','error','-re','-f','lavfi','-i',f'sine=frequency={frequency}:sample_rate=48000','-ac','2','-f','pulse','-device',name,name])
        time.sleep(.6)
        silent=json.loads(run([binary,'capture','audio-input'],text=True).stdout)
        assert silent['backend']=='none',silent
        for flags,expected in [(['--speakers'],(True,False)),(['--mic'],(False,True)),(['--speakers','--mic'],(True,True))]:
            source=json.loads(run([binary,'capture','audio-input',*flags],text=True).stdout)
            captured=run(['/usr/bin/ffmpeg','-nostdin','-hide_banner','-loglevel','error','-f',source['backend'],'-i',source['device'],'-t','1.2','-ac','1','-ar','48000','-f','f32le','-']).stdout
            samples=array.array('f');samples.frombytes(captured);samples=samples[-24000:]
            assert len(samples)==24000,'Audio input delivered no usable samples'
            amps=[tone_amplitude(samples,f) for f in (440,880)]
            for amplitude,present in zip(amps,expected):
                assert (amplitude>.01) if present else (amplitude<.002),(flags,amps,expected)
            print('PASS:',flags,'isolated 440/880 Hz amplitudes',*[round(a,4) for a in amps],flush=True)
        print('RECORDING AUDIO PASS: silent default, independent speaker/mic inputs and real two-source mixing',flush=True)
    except Exception:
        for log in logs:log.flush()
        for path in root.glob('*.log'):print(path.name,path.read_text()[-2000:])
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:process.terminate()
        for process in reversed(processes):
            try:process.wait(timeout=4)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        for log in logs:log.close()

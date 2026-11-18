"""Run the actual Rust executable with private files and fake external commands."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BINARY = Path(os.environ.get('DOTFILES_DESKTOP_BINARY', Path.home()/'.config/hypr/bin/dotfiles-desktop'))


class NativeContracts(unittest.TestCase):
    def setUp(self):
        if not BINARY.is_file():
            self.fail('Build native helpers and set DOTFILES_DESKTOP_BINARY before running this suite')
        self.temporary = tempfile.TemporaryDirectory(prefix='native-contract-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.repo = self.directory/'repo'
        self.source = self.repo/'hyprland/config'
        self.source.mkdir(parents=True)
        (self.source/'hyprland.lua').write_text('new configuration')
        self.config = self.directory/'config/hypr'
        self.config.mkdir(parents=True)
        (self.config/'hyprland.lua').write_text('original configuration')
        (self.config/'unrelated.conf').write_text('user configuration')
        self.bin = self.directory/'bin'
        self.bin.mkdir()
        self.env = {k:v for k,v in os.environ.items() if k not in ('HYPRLAND_INSTANCE_SIGNATURE','WAYLAND_DISPLAY','DISPLAY')}
        self.env.update(DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/native-contract-bus", DOTFILES_HYPR_ROOT=str(self.config), XDG_CONFIG_HOME=str(self.directory/'config'),
                        XDG_STATE_HOME=str(self.directory/'state'), XDG_CACHE_HOME=str(self.directory/'cache'),
                        XDG_DATA_HOME=str(self.directory/'data'), PATH=str(self.bin)+':'+os.environ['PATH'])
        self.fake('Hyprland', 'import pathlib,sys\ns=pathlib.Path(sys.argv[-1]).read_text()\nprint("invalid" if "invalid" in s else "config ok")\nsys.exit(1 if "invalid" in s else 0)\n')

    def fake(self, name, body):
        path = self.bin/name
        path.write_text('#!/usr/bin/python3\n'+body)
        path.chmod(0o700)

    def run_native(self, *args, check=True, data=None, raw=False):
        result = subprocess.run([str(BINARY), *map(str,args)], env=self.env, input=data,
                                capture_output=True, text=not raw, timeout=10)
        if check:
            self.assertEqual(result.returncode,0,result.stderr)
        return result

    def manage(self, action, check=True):
        return self.run_native('manage','hyprland',self.repo,action,check=check)

    def backups(self):
        return sorted((self.directory/'state/dotfiles/hyprland/backups').glob('*/metadata.json'))

    def test_install_check_noop_and_complete_rollback(self):
        self.manage('install')
        self.assertEqual((self.config/'hyprland.lua').read_text(),'new configuration')
        self.assertEqual((self.config/'unrelated.conf').read_text(),'user configuration')
        self.assertEqual((self.config/'bin/dotfiles-desktop').read_bytes(),BINARY.read_bytes())
        self.manage('check'); self.manage('install')
        self.assertEqual(len(self.backups()),1)
        (self.config/'unrelated.conf').write_text('later user change')
        self.manage('rollback')
        self.assertEqual((self.config/'hyprland.lua').read_text(),'original configuration')
        self.assertEqual((self.config/'unrelated.conf').read_text(),'user configuration')
        self.assertFalse((self.config/'bin/dotfiles-desktop').exists())
        self.assertEqual(len(self.backups()),2)

    def test_invalid_source_does_not_touch_installation(self):
        (self.source/'hyprland.lua').write_text('invalid configuration')
        self.assertNotEqual(self.manage('install',check=False).returncode,0)
        self.assertEqual((self.config/'hyprland.lua').read_text(),'original configuration')
        self.assertEqual(self.backups(),[])

    def test_managed_symlink_directory_cannot_escape_staging(self):
        outside=self.directory/'outside';outside.mkdir()
        (outside/'test.lua').write_text('preserve')
        (self.source/'modules').mkdir();(self.source/'modules/test.lua').write_text('new')
        (self.config/'modules').symlink_to(outside,target_is_directory=True)
        self.assertNotEqual(self.manage('install',check=False).returncode,0)
        self.assertEqual((outside/'test.lua').read_text(),'preserve')
        self.assertEqual((self.config/'hyprland.lua').read_text(),'original configuration')

    def test_failed_live_reload_restores_original_config(self):
        self.env['HYPRLAND_INSTANCE_SIGNATURE']='private-fixture'
        self.fake('hyprctl','import sys\nsys.exit(1)\n')
        self.assertNotEqual(self.manage('install',check=False).returncode,0)
        self.assertEqual((self.config/'hyprland.lua').read_text(),'original configuration')
        self.assertFalse((self.config/'bin/dotfiles-desktop').exists())

    def test_retired_python_removed_and_unrelated_python_preserved(self):
        (self.config/'tools').mkdir();(self.config/'tools/desktop.py').write_text('retired')
        (self.config/'tools/user-script.py').write_text('preserve')
        self.manage('install')
        self.assertFalse((self.config/'tools/desktop.py').exists())
        self.assertEqual((self.config/'tools/user-script.py').read_text(),'preserve')

    def test_clipboard_binary_content_and_command_literals(self):
        payload=b'\x00\xffimage\n\t\x89PNG\n'
        source=self.directory/'payload';source.write_bytes(payload)
        copied=self.directory/'copied'
        self.fake('cliphist',f'import pathlib,sys\nassert sys.stdin.buffer.read()==b"42"\nsys.stdout.buffer.write(pathlib.Path({str(source)!r}).read_bytes())\n')
        self.fake('wl-copy',f'import pathlib,sys,json\npathlib.Path({str(copied)!r}).write_bytes(sys.stdin.buffer.read())\npathlib.Path({str(copied)+"-args"!r}).write_text(json.dumps(sys.argv[1:]))\n')
        self.run_native('desktop','clipboard-copy','42')
        self.assertEqual(copied.read_bytes(),payload)
        text='$(touch /tmp/not-an-executable)\n-1e+20'
        self.run_native('desktop','copy-text',text)
        self.assertEqual(copied.read_text(),text)
        self.run_native('desktop','copy-text','--','-1e+20')
        self.assertEqual(copied.read_text(),'-1e+20')
        self.assertNotEqual(self.run_native('desktop','clipboard-copy','$(bad)',check=False).returncode,0)

    def test_legacy_image_uses_decoded_markup_instead_of_truncated_preview(self):
        markup = '<meta charset="UTF-8"><img src="https://example.test/image.png" alt="Example photo">'
        summary = markup[:40]
        self.fake('cliphist', f'''import sys
if sys.argv[1:] == ["list"]:
    print("42\\t" + {summary!r})
else:
    assert sys.argv[1:] == ["decode"] and sys.stdin.read() == "42"
    sys.stdout.write({markup!r})
''')
        (entry,) = json.loads(self.run_native('desktop', 'clipboard-list').stdout)
        self.assertEqual(entry['id'], 'legacy-42')
        self.assertEqual(entry['kind'], 'remote-image')
        self.assertEqual(entry['source'], 'example.test')
        self.assertEqual(entry['preview'], 'Example photo')

    def test_shortcuts_use_persistent_shell_and_keep_timestamp(self):
        log=self.directory/'ipc'
        self.fake('quickshell',f'import pathlib,json,sys\npathlib.Path({str(log)!r}).write_text(json.dumps(sys.argv[1:]))\n')
        self.run_native('desktop','pill','hide','12345')
        self.assertEqual(json.loads(log.read_text())[-3:],['gesture','hide','12345'])
        self.run_native('desktop','launcher')
        self.assertEqual(json.loads(log.read_text())[-2:],['toggle','launcher'])

    def test_session_info_defaults_and_keyboard(self):
        self.fake('hyprctl','print(\'{"keyboards":[{"main":true,"name":"fixture","active_keymap":"Russian"}]}\')\n')
        self.assertEqual(json.loads(self.run_native('shell','session-info').stdout),{'layout':'Russian','keyboard':'fixture'})
        self.fake('hyprctl','import sys\nsys.exit(1)\n')
        self.assertEqual(json.loads(self.run_native('shell','session-info').stdout),{'layout':'English (US)','keyboard':''})

    def test_brightness_invalid_level_fails_before_hardware_access(self):
        for level in ('-0.1','1.1','NaN','inf'):
            with self.subTest(level=level):
                self.assertNotEqual(self.run_native('shell','brightness-set','fixture',level,check=False).returncode,0)

    def test_capture_preferences_atomic_private_and_validated(self):
        value={'cursor':True,'regions':{'DP-1':[1,2,30,40]}}
        self.run_native('capture','preferences',json.dumps(value))
        path=self.directory/'state/dotfiles/hyprland/capture.json'
        self.assertEqual(json.loads(path.read_text()),value)
        self.assertEqual(path.stat().st_mode&0o777,0o600)
        self.assertNotEqual(self.run_native('capture','preferences','[]',check=False).returncode,0)
        self.assertEqual(json.loads(path.read_text()),value)


if __name__=='__main__':
    unittest.main()

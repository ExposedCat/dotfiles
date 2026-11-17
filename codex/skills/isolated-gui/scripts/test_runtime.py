"""Safety contracts for the GUI helper; no real desktop or socket is touched."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from runtime import Session, owned_directory

class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.session=Session.__new__(Session)
        self.session.path=Path(self.folder.name)
        self.session.state_path=self.session.path/'state.json'
        (self.session.path/'tmp'/'.X11-unix').mkdir(parents=True)
        self.session.state={'isolation_version':2,'display':':100','authority':str(self.session.path/'Xauthority'),'bus':'unix:path='+str(self.session.path/'bus'),'token':'private','render':'software','host_x11':{'/tmp/.X11-unix/X0':[1,123,49590]}}
    def tearDown(self):self.folder.cleanup()
    def test_every_command_uses_private_tmp(self):
        with patch('runtime.binary',side_effect=lambda n:'/usr/bin/'+n):args=self.session.command(['/usr/bin/example','argument'])
        self.assertIn('bwrap',args[0]);i=args.index(str(self.session.path/'tmp'))
        self.assertEqual(args[i-1],'--bind');self.assertEqual(args[i+1],'/tmp')
        self.assertEqual(args[-3:],['--','/usr/bin/example','argument'])
    def test_legacy_session_cannot_run_commands(self):
        self.session.state['isolation_version']=1
        with self.assertRaises(RuntimeError):self.session.command(['/usr/bin/example'])
    def test_isolation_environment_cannot_be_overridden(self):
        for key in ['DISPLAY','WAYLAND_DISPLAY','DBUS_SESSION_BUS_ADDRESS','XDG_RUNTIME_DIR','TMPDIR','QT_QPA_PLATFORM']:
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.session.environment([key+'=foreign'])
    def test_host_socket_replacement_is_rejected_without_repair(self):
        with patch('runtime.x11_snapshot',return_value={'/tmp/.X11-unix/X0':[1,456,49590]}):
            with self.assertRaisesRegex(RuntimeError,'Host X11 endpoint changed'):self.session.check_host_sockets()
        self.assertEqual(self.session.state['host_x11']['/tmp/.X11-unix/X0'],[1,123,49590])
    def test_new_host_endpoints_are_not_treated_as_owned(self):
        current={'/tmp/.X11-unix/X0':[1,123,49590],'/tmp/.X11-unix/X9':[1,999,49590]}
        with patch('runtime.x11_snapshot',return_value=current):self.session.check_host_sockets()
    def test_foreign_abstract_listener_is_rejected(self):
        with patch('runtime.socket.socket',return_value=Mock()):
            with self.assertRaisesRegex(RuntimeError,'foreign abstract'):self.session.check_abstract_socket()
    def test_absent_abstract_listener_is_safe(self):
        sock=Mock();sock.connect.side_effect=FileNotFoundError()
        with patch('runtime.socket.socket',return_value=sock):self.session.check_abstract_socket()
        sock.close.assert_called_once()


    def test_tmp_symlink_is_rejected(self):
        private = self.session.path / 'tmp'
        (private / '.X11-unix').rmdir()
        private.rmdir()
        target = self.session.path / 'foreign-tmp'
        target.mkdir()
        private.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'cannot be a symlink'):
            self.session.command(['/usr/bin/example'])

    def test_socket_directory_symlink_is_rejected(self):
        sockets = self.session.path / 'tmp' / '.X11-unix'
        sockets.rmdir()
        target = self.session.path / 'foreign-sockets'
        target.mkdir()
        sockets.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'cannot be a symlink'):
            self.session.command(['/usr/bin/example'])

    def test_session_symlink_is_rejected_before_chmod(self):
        target = self.session.path / 'foreign-session'
        target.mkdir(mode=0o750)
        link = self.session.path / 'session-alias'
        link.symlink_to(target, target_is_directory=True)
        before = target.stat().st_mode
        with self.assertRaisesRegex(RuntimeError, 'cannot be a symlink'):
            owned_directory(link, mode=0o700, create=True)
        self.assertEqual(target.stat().st_mode, before)

    def test_shared_tmp_is_rejected(self):
        # Exercise the real guard with a fixture, never chmod or mount host /tmp.
        with patch.object(Path, 'samefile', return_value=True):
            with self.assertRaisesRegex(RuntimeError, 'aliases the shared'):
                self.session.private_tmp()

    def test_preflight_failure_never_launches_a_server(self):
        self.session.name = 'preflight-failure'
        self.session.state = None
        with patch('runtime.binary', side_effect=lambda n: '/usr/bin/' + n), \
             patch.object(self.session, 'verify_mount_isolation', side_effect=RuntimeError('preflight failed')), \
             patch.object(self.session, 'spawn') as spawn:
            with self.assertRaisesRegex(RuntimeError, 'preflight failed'):
                self.session.start('800x600', 'software')
        spawn.assert_not_called()
        self.assertEqual(self.session.state['services'], {})

    def test_runtime_symlink_is_rejected_without_touching_bus(self):
        self.session.state = None
        target = self.session.path / 'foreign-runtime'
        target.mkdir(mode=0o750)
        bus = target / 'bus'
        bus.write_text('foreign bus fixture')
        (self.session.path / 'runtime').symlink_to(target, target_is_directory=True)
        before = target.stat().st_mode
        with patch('runtime.binary', side_effect=lambda n: '/usr/bin/' + n), \
             patch.object(self.session, 'spawn') as spawn:
            with self.assertRaisesRegex(RuntimeError, 'cannot be a symlink'):
                self.session.start('800x600', 'software')
        spawn.assert_not_called()
        self.assertEqual(bus.read_text(), 'foreign bus fixture')
        self.assertEqual(target.stat().st_mode, before)

    def test_bubblewrap_failure_has_no_unwrapped_fallback(self):
        import subprocess
        with patch('runtime.binary', side_effect=lambda n: '/usr/bin/' + n), \
             patch('runtime.subprocess.run', side_effect=subprocess.CalledProcessError(1, 'bwrap')) as run:
            with self.assertRaisesRegex(RuntimeError, 'refusing to start Xvfb'):
                self.session.verify_mount_isolation()
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], '/usr/bin/bwrap')

    def test_host_socket_removal_is_rejected_without_repair(self):
        before = dict(self.session.state['host_x11'])
        with patch('runtime.x11_snapshot', return_value={}):
            with self.assertRaisesRegex(RuntimeError, 'Host X11 endpoint changed'):
                self.session.check_host_sockets()
        self.assertEqual(self.session.state['host_x11'], before)

if __name__=='__main__':unittest.main()

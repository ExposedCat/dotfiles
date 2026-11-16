"""Safety contracts for the GUI helper; no real desktop or socket is touched."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from runtime import Session

class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.session=Session.__new__(Session)
        self.session.path=Path(self.folder.name)
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

if __name__=='__main__':unittest.main()

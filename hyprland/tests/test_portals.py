"""Validate portal decisions, source parsing, and preservation of local config."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).parents[2]
sys.path.insert(0, str(ROOT / 'hyprland/config/portals'))
import common
import backend
spec = importlib.util.spec_from_file_location('portal_manage', ROOT / 'xdg-desktop-portal/manage.py')
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


class SharingTests(unittest.TestCase):
    def sources(self):
        return common.share_sources({
            'XDPH_OUTPUT_SHARING_LIST': '4:DP-3:0:0:2560:1440;',
            'XDPH_WINDOW_SHARING_LIST': '42[HC>]firefox[HT>]Document[HE>]1234[HA>]',
            'XDPH_WORKSPACE_SHARING_LIST_V3': '9[HN>]6:Раб[HM>]1:4:DP-3[HE>]',
        })

    def test_sources_keep_protocol_ids_separate_from_labels(self):
        screens, windows, workspaces = self.sources()
        self.assertEqual(screens[0]['width'], 2560)
        self.assertEqual(windows[0]['id'], 'window:42')
        self.assertEqual(workspaces[0]['name'], 'Workspace Раб')
        self.assertEqual(workspaces[0]['id'], 'workspace-id:9')

    def test_utf8_byte_lengths_and_delimiters_in_workspace_name(self):
        name = 'Работа: [HE>]'
        raw = f'9[HN>]{len(name.encode())}:{name}[HM>]0:[HE>]'
        result = common.share_sources({'XDPH_WORKSPACE_SHARING_LIST_V3': raw})
        self.assertEqual(result[2][0]['name'], 'Workspace ' + name)

    def test_version2_workspace_source(self):
        result = common.share_sources({'XDPH_WORKSPACE_SHARING_LIST_V2': '4:Work:17;'})
        self.assertEqual(result[2][0]['id'], 'workspace-id:17')

    def test_truncated_sources_are_rejected(self):
        for raw in ('99:DP-3:0:0:20:20;', '4:DP-3:0:0:20:', '-1:x:0:0:20:20;'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                common.share_sources({'XDPH_OUTPUT_SHARING_LIST': raw})

    def test_sharing_needs_an_explicit_valid_source(self):
        self.assertEqual(common.share_result({'response': 1}, self.sources()), '')
        with self.assertRaises(ValueError):
            common.share_result({'response': 0, 'choice': 'screen:unlisted'}, self.sources())

    def test_share_protocol_and_remember_flag(self):
        self.assertEqual(common.share_result({'response': 0, 'choice': 'window:42', 'remember': False}, self.sources()), '[SELECTION]/window:42')
        self.assertEqual(common.share_result({'response': 0, 'choice': 'workspace-id:9', 'remember': True}, self.sources()), '[SELECTION]r/workspace-id:9')

    def test_region_stays_inside_selected_monitor(self):
        result = {'response': 0, 'choice': 'screen:DP-3', 'region': [10, 20, 640, 480]}
        self.assertEqual(common.share_result(result, self.sources()), '[SELECTION]/region:DP-3@10,20,640,480')
        for region in ([-1, 0, 10, 10], [0, 0, 0, 10], [2500, 0, 100, 100], [0, 0, 1.0, 2], [0, 0, 1]):
            with self.subTest(region=region), self.assertRaises(ValueError):
                common.share_result(dict(result, region=region), self.sources())

    def test_workspace_preview_uses_name_and_keeps_portal_identity(self):
        sources = self.sources()
        monitor = {'id': 2, 'name': 'DP-3', 'x': -2560, 'y': 0, 'width': 5120, 'height': 2880, 'scale': 2}
        client = {'workspace': {'name': 'Раб', 'id': 700}, 'monitor': 2, 'at': [-2560, 0],
                  'size': [1280, 1440], 'class': 'editor', 'title': 'Notes'}
        other = dict(client, workspace={'name': 'Other'})
        hidden = dict(client, hidden=True)
        common.workspace_previews(sources, [client, other, hidden], [monitor])
        workspace = sources[2][0]
        self.assertEqual(workspace['id'], 'workspace-id:9')
        self.assertEqual(len(workspace['tiles']), 1)
        self.assertEqual(workspace['tiles'][0]['x'], 0)
        self.assertEqual(workspace['tiles'][0]['width'], 0.5)
        self.assertEqual(workspace['tiles'][0]['height'], 1)
        self.assertEqual(common.share_result({'response': 0, 'choice': workspace['id']}, sources), '[SELECTION]/workspace-id:9')

    def test_workspace_preview_clips_offscreen_windows(self):
        sources = self.sources()
        monitor = {'id': 0, 'name': 'DP-3', 'x': 0, 'y': 0, 'width': 2560, 'height': 1440}
        client = {'workspace': {'name': 'Раб'}, 'at': [-100, 0], 'size': [200, 1440]}
        common.workspace_previews(sources, [client], [monitor])
        tile = sources[2][0]['tiles'][0]
        self.assertEqual(tile['x'], 0)
        self.assertEqual(tile['width'], 100 / 2560)

    def test_empty_workspace_has_no_invented_windows(self):
        sources = self.sources()
        common.workspace_previews(sources, [], [])
        self.assertEqual(sources[2][0]['tiles'], [])


class DecisionTests(unittest.TestCase):
    def test_unknown_app_cannot_be_returned(self):
        data = {'kind': 'apps', 'apps': [{'id': 'firefox.desktop'}]}
        self.assertEqual(backend.response_values(data, {'response': 0, 'choice': 'other'})[0], 2)
        response, values = backend.response_values(data, {'response': 0, 'choice': 'firefox.desktop'})
        self.assertEqual(response, 0)
        self.assertEqual(values['choice'].unpack(), 'firefox')

    def test_app_choices_preserve_frontend_ids(self):
        choices = common.app_choices(['not.installed', 'not.installed', 'other.desktop'])
        self.assertEqual([c['id'] for c in choices], ['not.installed', 'other.desktop'])

    def test_cancel_never_returns_a_grant_or_choice(self):
        self.assertEqual(backend.response_values({'kind': 'access'}, {'response': 1, 'choices': {'remember': 'true'}}), (1, {}))
        self.assertEqual(backend.response_values({'kind': 'apps'}, {}), (2, {}))
        self.assertEqual(backend.response_values({'kind': 'apps'}, {'response': False}), (2, {}))

    def test_permission_choices_validate_returned_ids(self):
        choices = backend.access_choices({'choices': [('remember', 'Remember', [], 'false'), ('quality', 'Quality', [('low', 'Low'), ('high', 'High')], 'high')]})
        data = {'kind': 'access', 'choices': choices}
        response, values = backend.response_values(data, {'response': 0, 'choices': {'remember': 'true', 'quality': 'low'}})
        self.assertEqual(response, 0)
        self.assertEqual(values['choices'].unpack(), [('remember', 'true'), ('quality', 'low')])
        self.assertEqual(backend.response_values(data, {'response': 0, 'choices': {'quality': 'unknown'}})[0], 2)
        self.assertEqual(backend.response_values(data, {'response': 0, 'choices': []})[0], 2)

    def test_only_request_owner_can_close_it(self):
        service = backend.Backend.__new__(backend.Backend)
        service.pending = {'/request': {'sender': ':1.5'}}
        service.finish = Mock()
        invocation = Mock()
        service.close_request(None, ':1.6', '/request', '', '', None, invocation)
        service.finish.assert_not_called()
        invocation.return_dbus_error.assert_called_once()

    def test_caller_disappearance_cancels_only_its_requests(self):
        service = backend.Backend.__new__(backend.Backend)
        service.pending = {'/first': {'sender': ':1.5'}, '/second': {'sender': ':1.6'}}
        service.finish = Mock()
        service.owner_changed(None, '', '', '', '', backend.GLib.Variant('(sss)', (':1.5', ':1.5', '')))
        service.finish.assert_called_once_with('/first', {'response': 2})


class InstallerTests(unittest.TestCase):
    def test_managed_update_preserves_surrounding_rules(self):
        before = 'custom rule\n\n-- BEGIN dotfiles-portals\nold\n-- END dotfiles-portals\nmore custom rules\n'
        after = manage.managed_block(before, manage.RULE, 'dotfiles-portals')
        self.assertTrue(after.startswith('custom rule\n\n'))
        self.assertTrue(after.endswith('\nmore custom rules\n'))
        self.assertEqual(after.count('BEGIN dotfiles-portals'), 1)
        self.assertEqual(manage.managed_block(after, manage.RULE, 'dotfiles-portals'), after)

    def test_incomplete_managed_block_is_not_overwritten(self):
        with self.assertRaises(RuntimeError):
            manage.managed_block('-- BEGIN dotfiles-portals\nlocal settings', manage.RULE, 'dotfiles-portals')


if __name__ == '__main__':
    unittest.main()

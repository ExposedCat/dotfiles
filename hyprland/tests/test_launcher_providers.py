"""Provider contracts using real parsers/catalogs and isolated source fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from contextlib import closing
from unittest.mock import patch

SOURCE = Path(__file__).parents[1] / 'config/shell'
sys.path.insert(0, str(SOURCE))
import launcher
from launcher_sources import Characters, Files, Zen, item, match_score, variants, collapse_character_presentations


class CalculatorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.calc = launcher.Calculator(Path(self.temporary.name))
        if not self.calc.executable:
            self.skipTest('Qalculate is not available')

    def test_currency_forms_and_suggestions(self):
        for query in ('100 usd eur', '100 usd to eur'):
            rows = self.calc.search(query)
            self.assertEqual(len(rows), 1, query)
            self.assertEqual(rows[0]['id'], 'currency:100 USD to EUR')
            self.assertRegex(rows[0]['name'], r'\d')
            self.assertIn('Rates ', rows[0]['description'])
        self.assertEqual([r['id'] for r in self.calc.search('100 usd')],
                         ['currency:100 USD to CZK', 'currency:100 USD to EUR'])
        self.assertEqual([r['id'] for r in self.calc.search('100 czk')],
                         ['currency:100 CZK to USD', 'currency:100 CZK to EUR'])
        self.assertEqual(self.calc.search('100 xyz eur'), [])
        self.assertEqual(self.calc.search('100 usd xyz'), [])

    def test_units_are_evaluated_by_qalculate(self):
        self.assertIn('152.4', self.calc.search('5 ft to cm')[0]['name'])
        self.assertIn('176.666', self.calc.search('350 fahrenheit to celsius')[0]['name'])
        self.assertEqual(self.calc.search('terminal'), [])

    def test_math_uses_qalculate_functions_and_forgiving_parentheses(self):
        for query, expected in [('12 * (3 + 4)', '84'), ('-2^2', '−4'), ('2^3^2', '512'),
                                ('2 + 2) * 3', '12'), ('2 * (3 + 4', '14'),
                                ('sqrt(81)', '9'), ('sin(pi/2)', '1'), ('0.1 + 0.2', '0.3')]:
            rows = self.calc.search(query)
            self.assertEqual(rows[0]['value'], expected, query)
            self.assertEqual(rows[0]['kind'], 'calculation', query)
        for query in ('foo(2)', 'Telegram', '42', '2 +', ''):
            self.assertEqual(self.calc.search(query), [], query)

    def test_currency_arithmetic_and_short_targets(self):
        for query, expected in [('25 * 2 eur', '€50'), ('25 eur / 4', '€6.25')]:
            rows = self.calc.search(query)
            self.assertEqual(rows[0]['value'], expected)
            self.assertEqual(len(rows), 3)
            self.assertTrue(all(row['kind'] == 'currency' and row['rateDate'] for row in rows))
            self.assertTrue(any('CZK' in row['id'] for row in rows))
            self.assertTrue(any('USD' in row['id'] for row in rows))
        self.assertEqual(self.calc.search('25 eur / 4 to usd')[0]['value'],
                         self.calc.search('25 eur / 4 in usd')[0]['value'])
        for query in ('25 * 2 eur czk', '25 * 2 eur to czk', '25 eur / 4 to usd'):
            self.assertEqual(len(self.calc.search(query)), 1, query)
        for query in ('25 eur / (4 eur)', '1 / eur', '25 eur * 4 eur'):
            rows = self.calc.search(query)
            self.assertEqual(len(rows), 1, query)
            self.assertEqual(rows[0]['kind'], 'calculation', query)

    def test_unlabelled_additive_amounts_use_left_currency_then_right(self):
        for query, explicit in [
            ('2 + 15 eur)', '17 eur'),
            ('2 + 15 usd + 10 eur', '17 usd + 10 eur'),
            ('15 eur + 2 + 10 usd + 3', '17 eur + 13 usd'),
            ('2 + 15 eur + 4 + 10 usd', '21 eur + 10 usd'),
            ('15 eur + (2 + 3 usd)', '17 eur + 3 usd'),
            ('2 + 15 eur to usd', '17 eur to usd'),
            ('15 eur - 2', '13 eur'),
            ('2 - 15 eur', '-13 eur'),
            ('(15 eur - 2) / 4', '3.25 eur'),
            ('2 + 15 eur) * 3', '51 eur'),
            ('2 + 15 eur / (2 + 3)', '5 eur'),
            ('(2 + 3) * 15 eur', '75 eur'),
            ('2 * 3 + 15 eur', '21 eur'),
            ('2 + 15 eur + 10%', '18.7 eur'),
            ('1e-3 + 15 eur', '15.001 eur'),
        ]:
            with self.subTest(query=query):
                rows = self.calc.search(query)
                self.assertEqual(rows[0]['value'], self.calc.evaluate(explicit))
                self.assertEqual(rows[0]['kind'], 'currency')
        for query in ('2 kg + 15 eur', '2 + 15 eur^2', '1 / eur'):
            self.assertEqual(self.calc.search(query)[0]['value'], self.calc.evaluate(query), query)


class DateTests(unittest.TestCase):
    def setUp(self):
        self.dates = launcher.Dates(lambda: datetime(2026, 11, 15, 12, 30, tzinfo=timezone.utc))

    def value(self, query):
        return self.dates.search(query)[0]['value']

    def test_calendar_days_leap_days_and_named_dates(self):
        self.assertEqual(self.value('days between 2026-01-01 and 2026-02-01'), '31 days')
        self.assertEqual(self.value('days between 28 February 2024 and 1 March 2024'), '2 days')
        self.assertEqual(self.value('days between 2026-02-01 and 2026-01-01'), '-31 days')
        self.assertEqual(self.value('days between today and tomorrow'), '1 day')
        with self.assertRaises(ValueError):
            self.dates.search('days between 2026-02-30 and 2026-03-01')

    def test_elapsed_time_uses_offsets_instead_of_calendar_days(self):
        self.assertEqual(self.value('time between 09:00 and 17:30'), '8 hours, 30 minutes')
        self.assertEqual(self.value('time between 23:00 and 01:00'), '2 hours, 0 minutes')
        self.assertEqual(self.value('time between 2026-03-29T01:00+01:00 and 2026-03-29T04:00+02:00'), '2 hours, 0 minutes')

    def test_date_arithmetic_timezones_and_timestamps(self):
        self.assertEqual(self.value('today + 90 days'), '2027-02-13')
        self.assertEqual(self.value('2024-01-31 + 1 month'), '2024-02-29')
        self.assertEqual(self.value('unix 0'), '1970-01-01T00:00:00+00:00')
        self.assertEqual(self.value('timestamp now'), '1794745800')
        self.assertIn('21:30', self.value('time Tokyo'))


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.characters = Characters()
        cls.characters.load()

    def test_real_unicode_and_multi_codepoint_emoji(self):
        self.assertEqual(self.characters.search('em dash', True)[0]['value'], '—')
        self.assertEqual(self.characters.search('U+2192')[0]['value'], '→')
        self.assertEqual(self.characters.search('greek small letter alpha', True)[0]['value'], 'α')
        self.assertEqual(self.characters.search('U+110000'), [])
        self.assertTrue(any(len(r['value']) > 1 for r in self.characters.search('family', True)))
        self.assertTrue(self.characters.search('улыбка', True))
        self.assertTrue(self.characters.search('shrug', True))

    def test_physical_layout_recovery_preserves_the_original(self):
        self.assertEqual(variants('еудупкфь'), ['еудупкфь', 'telegram'])
        self.assertEqual(match_score('Telegram', 'еудупкфь'), 0)
        self.assertEqual(match_score('привет', 'ghbdtn'), 0)

    def test_global_search_collapses_text_and_emoji_presentations(self):
        def telephone(rows):
            return [r for r in rows if r['value'].replace('\ufe0f', '').replace('\ufe0e', '') == '☎']
        self.assertEqual(len(telephone(self.characters.search('telephone'))), 1)
        self.assertGreaterEqual(len(telephone(self.characters.search('telephone', True))), 2)
        self.assertEqual(self.characters.search('U+260E')[0]['value'], '☎')
        base = item('character', '260E', 'telephone', value='☎', favorite=True)
        emoji = item('character', '260E-FE0F', 'telephone', value='☎️')
        self.assertEqual(collapse_character_presentations([base, emoji])[0]['value'], '☎')
        self.assertEqual(len(collapse_character_presentations([base, emoji])), 1)


class FileTests(unittest.TestCase):
    def test_path_completion_is_bounded_and_includes_folders(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Folder with spaces').mkdir()
            (root / 'notes.txt').write_text('notes')
            (root / '.hidden').write_text('hidden')
            files = Files()
            rows, notice = files.search(str(root) + '/')
            self.assertEqual([r['name'] for r in rows], ['Folder with spaces', 'notes.txt'])
            self.assertTrue(rows[0]['directory'])
            self.assertIn('Folder%20with%20spaces', rows[0]['uri'])
            self.assertEqual(files.search(str(root) + '/no')[0][0]['name'], 'notes.txt')

    def test_gnome_search_provider_interface_and_metadata(self):
        from gi.repository import GLib
        with tempfile.NamedTemporaryFile(prefix='launcher invoice ', suffix='.pdf') as fixture:
            uri = Path(fixture.name).as_uri()
            calls = []
            class Bus:
                def call_sync(self, bus, path, interface, method, args, *rest):
                    calls.append((bus, path, interface, method, args.unpack()))
                    if method == 'GetInitialResultSet':
                        return GLib.Variant('(as)', ([uri],))
                    return GLib.Variant('(aa{sv})', ([{'id': GLib.Variant('s', uri), 'name': GLib.Variant('s', 'Invoice'),
                                                     'description': GLib.Variant('s', 'Documents')}],))
            rows, notice = Files(Bus()).search('invoice')
            self.assertEqual(rows[0]['name'], 'Invoice')
            self.assertEqual(rows[0]['path'], fixture.name)
            self.assertEqual(calls[0][:4], ('org.gnome.Nautilus', '/org/gnome/Nautilus/SearchProvider',
                                           'org.gnome.Shell.SearchProvider2', 'GetInitialResultSet'))
            self.assertEqual(calls[0][4], (['invoice'],))
            self.assertEqual(calls[1][3], 'GetResultMetas')


class ZenTests(unittest.TestCase):
    def test_snapshot_and_open_use_the_install_default_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / '.var/app/app.zen_browser.zen/.zen'
            root.mkdir(parents=True)
            profile = root / 'active'
            profile.mkdir()
            (root / 'profiles.ini').write_text('[Profile0]\nName=Active Profile\nPath=active\nIsRelative=1\n'
                                              '[InstallABC]\nDefault=active\n')
            database = profile / 'places.sqlite'
            with closing(sqlite3.connect(database)) as c:
                c.executescript("CREATE TABLE moz_places(id INTEGER, title TEXT, url TEXT);"
                                "CREATE TABLE moz_bookmarks(type INTEGER, fk INTEGER, title TEXT);"
                                "INSERT INTO moz_places VALUES(1,'Example','https://example.com');"
                                "INSERT INTO moz_bookmarks VALUES(1,1,'Reference');")
            before = database.read_bytes()
            zen = Zen(temporary)
            with patch('launcher_sources.shutil.which', return_value='/usr/bin/flatpak'):
                rows = zen.search('reference')
            self.assertEqual(zen.profile, profile)
            self.assertEqual(rows[0]['uri'], 'https://example.com')
            self.assertEqual(database.read_bytes(), before)
            with patch('subprocess.Popen') as popen:
                zen.open(rows[0])
                self.assertEqual(popen.call_args.args[0], ['flatpak', 'run', 'app.zen_browser.zen', '-P', 'Active Profile', '--new-tab', 'https://example.com'])
                zen.open(zen.search('query', True)[-1])
                self.assertEqual(popen.call_args.args[0][-2:], ['--search', 'query'])


class HistoryTests(unittest.TestCase):
    def test_favorites_and_recent_items_survive_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'launcher.json'
            h = launcher.History(path)
            a = item('character', '2014', 'em dash', value='—')
            b = item('bookmark', 'https://example.com', 'Example', uri='https://example.com')
            h.record(a, pin=True); h.record(b)
            loaded = launcher.History(path)
            self.assertEqual(loaded.search('')[0]['id'], a['id'])
            self.assertTrue(loaded.search('')[0]['favorite'])
            loaded.record(a, pin=True)
            self.assertFalse(loaded.search('em dash')[0]['favorite'])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_actions_do_not_turn_result_data_into_commands(self):
        providers = launcher.Providers.__new__(launcher.Providers)
        with tempfile.TemporaryDirectory() as temporary:
            providers.history = launcher.History(Path(temporary) / 'history.json')
            with patch('subprocess.run') as run:
                providers.activate(item('character', 'test', 'test', value='$(touch /tmp/not-a-command)'), 'copy')
                self.assertEqual(run.call_args.args[0], ['wl-copy', '--', '$(touch /tmp/not-a-command)'])


if __name__ == '__main__':
    unittest.main()

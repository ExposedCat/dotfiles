"""Calendar queries honor the selected local day, including DST boundaries."""

from datetime import date, datetime
import importlib.util
import os
from pathlib import Path
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("hyprland_agenda", Path(__file__).parents[1] / "config/shell/agenda.py")
agenda = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agenda)


class CalendarRangeTests(unittest.TestCase):
    def bounds(self, selected):
        try:
            with patch.dict(os.environ, TZ="Europe/Berlin"):
                time.tzset()
                start, end = agenda.day_bounds(selected)
                self.assertEqual(datetime.fromtimestamp(start).date(), selected)
                self.assertEqual(datetime.fromtimestamp(start).hour, 0)
                self.assertEqual(datetime.fromtimestamp(end).hour, 0)
                return end - start
        finally:
            time.tzset()

    def test_arbitrary_selected_day_is_queried(self):
        self.assertEqual(self.bounds(date(2027, 2, 16)), 24 * 3600)

    def test_spring_day_has_23_hours(self):
        self.assertEqual(self.bounds(date(2026, 3, 29)), 23 * 3600)

    def test_autumn_day_has_25_hours(self):
        self.assertEqual(self.bounds(date(2026, 10, 25)), 25 * 3600)


if __name__ == "__main__":
    unittest.main()

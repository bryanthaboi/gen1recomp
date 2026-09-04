#!/usr/bin/env python3
"""RBY UI strings that must remain visible to the modkit catalog harvest."""

from pathlib import Path
from unittest import TestCase, main

import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
import modkit  # noqa: E402


class RbyTranslationHarvestTest(TestCase):
    def test_rby_ui_literals_are_harvested(self):
        harvested = {literal for literal, _location in
                     modkit.harvest_engine_strings(str(REPO))}
        expected = {
            '"FLY TO?"',
            '"ITEMS"',
            '"HEAL"',
            '"WITHDRAW"',
            '"DEPOSIT"',
            '"The party is full!"',
            '"MONEY/¥%d"',
            '"TIME/%3d:%02d"',
            '"No.%03d"',
            '"IDNo.%05d"',
            '"BILL\'S PC"',
            '"%s\'s PC"',
            '"AREA UNKNOWN"',
            '"%s\'s NEST"',
            '"To %s"',
            '"Congrats! This"',
            '"diploma certifies"',
            '"that you have"',
            '"completed your"',
            '"POKéDEX."',
            '"POKéMON BLUE"',
            '"POKéMON YELLOW"',
            '"PIKACHU\'S BEACH"',
        }
        self.assertEqual(expected - harvested, set())

    def test_dynamic_consumers_translate_at_draw_time(self):
        expected_calls = {
            "src/ui/Credits.lua": "Strings(line.text)",
            "src/ui/TownMap.lua": "Strings(loc.name)",
            "src/ui/TitleState.lua": "Strings(self.title.copyrightText)",
        }
        for relative, call in expected_calls.items():
            source = (REPO / relative).read_text(encoding="utf-8")
            self.assertIn(call, source, relative)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Gen 2 battle keys that must remain visible to modkit's string harvest."""

from pathlib import Path
from unittest import TestCase, main

import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
import modkit  # noqa: E402


class Gen2BattleTranslationHarvestTest(TestCase):
    def test_battle_templates_and_labels_are_harvested(self):
        harvested = {
            literal
            for literal, _location in modkit.harvest_engine_strings(str(REPO))
        }
        expected = {
            '"%s must recharge!"',
            '"A critical hit!"',
            '"But it failed!"',
            '"%s\'s attack missed!"',
            '"%s\'s %s was disabled!"',
            '"%s TRANSFORMED into %s!"',
            '"%s used %s!"',
            '"%s is confused!"',
            '"%s fell asleep!"',
            '"%s was poisoned!"',
            '"%s was badly poisoned!"',
            '"%s is paralyzed! It may be unable to move!"',
            '"%s was burned!"',
            '"%s was frozen solid!"',
            '"%s is hurt by poison!"',
            '"%s is hurt by its burn!"',
            '"It started to rain!"',
            '"The rain stopped."',
            '"The sandstorm rages."',
            '"%s gained %d EXP. Points!"',
            '"Can\'t escape!"',
            '"FIGHT"',
            '"<PK><MN>"',
            '"PACK"',
            '"RUN"',
            '"PARKBALL\\xc3\\x97%02d"',
            '"YES"',
            '"NO"',
            '"Gotcha! %s was caught!"',
            '"Wild %s appeared!"',
            '"%s sent out %s!"',
        }
        self.assertEqual(expected - harvested, set())

    def test_no_runtime_name_is_used_as_a_catalog_key(self):
        battle = (REPO / "src/battle/gen2/Battle.lua").read_text(
            encoding="utf-8"
        )
        screen = (REPO / "src/ui/gen2/BattleState.lua").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('Strings(name ..', battle)
        self.assertNotIn('Strings(self:monName', battle)
        self.assertNotIn('Strings(self:name', screen)


if __name__ == "__main__":
    main()

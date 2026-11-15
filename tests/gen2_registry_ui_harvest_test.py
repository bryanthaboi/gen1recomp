#!/usr/bin/env python3
"""Gen 2 registry-adjacent UI keys that must stay in the string catalog."""

from pathlib import Path
from unittest import TestCase, main

import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
import modkit  # noqa: E402


def lua_literal(source):
    return '"' + source.replace("\\", "\\\\").replace('"', '\\"') + '"'


class Gen2RegistryUiHarvestTest(TestCase):
    def test_registry_ui_labels_are_harvested(self):
        harvested = {
            literal
            for literal, _location in modkit.harvest_engine_strings(str(REPO))
        }
        expected_sources = {
            # Summary labels and full egg prose keys.
            "PP", "№.",
            # Pokedex display records.
            "HT", "WT",
        }
        expected = {lua_literal(source) for source in expected_sources}
        self.assertEqual(expected - harvested, set())

    def test_dynamic_clock_and_raw_display_bypasses_do_not_return(self):
        party = (REPO / "src/ui/gen2/PartyMenu.lua").read_text(encoding="utf-8")
        summary = (REPO / "src/ui/gen2/SummaryMenu.lua").read_text(
            encoding="utf-8"
        )
        dex = (REPO / "src/ui/gen2/PokedexMenu.lua").read_text(encoding="utf-8")
        for relative in ("src/ui/gen2/Pokegear.lua", "src/ui/gen2/MainMenu.lua"):
            clock = (REPO / relative).read_text(encoding="utf-8")
            self.assertNotIn('Strings(hour < 12 and "AM" or "PM")', clock)

        self.assertNotIn('return "ABLE"', party)
        self.assertNotIn('return "NOT ABLE"', party)
        self.assertNotIn('return "FNT"', party)
        self.assertNotIn('put(out, "POKéRUS"', summary)
        self.assertNotIn('put(out, "ATTK/"', summary)
        self.assertNotIn('self:text(" PAGE AREA CRY PRNT"', dex)
        self.assertNotIn('self:text("lb"', dex)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""ROM-free regression tests for the manifest generator's version pin and
its documented, deliberate overrides. No pokered checkout or ROM needed."""

from pathlib import Path
from unittest import TestCase, main, mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import make_rom_manifest  # noqa: E402


class CheckPokeredRevisionTest(TestCase):
    def test_matching_revision_is_silent(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            make_rom_manifest.check_pokered_revision("/pokered", "abc")

    def test_mismatched_revision_raises(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            with self.assertRaises(SystemExit):
                make_rom_manifest.check_pokered_revision("/pokered", "def")

    def test_allow_mismatch_bypasses_the_raise(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            make_rom_manifest.check_pokered_revision(
                "/pokered", "def", allow_mismatch=True)

    def test_unresolvable_checkout_is_silent(self):
        # _checkout_revision returns None for a non-git directory; nothing
        # to compare against, so this must not block generation.
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value=None):
            make_rom_manifest.check_pokered_revision("/pokered", "abc")


class ApplyKnownNonreproducibleOverridesTest(TestCase):
    def fixtures(self):
        texts = {"trainerHeaders": {}}
        field_data = {
            "seafoam": {
                "SEAFOAM_ISLANDS_B3F": {
                    "pluggedByHolesOn": {
                        "holes": [{"showObject": "X"}, {"showObject": "Y"}],
                    },
                },
            },
            "tradeArt": {"bubble": "assets/generated/trade/bubble.png"},
        }
        return texts, field_data

    def test_mtmoonb2f_super_nerd_slot_is_pinned(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertEqual(texts["trainerHeaders"]["MtMoonB2F"][1], {
            "after": "_MtMoonB2FSuperNerdTheresAPokemonLabText",
            "battle": "_MtMoonB2FSuperNerdTheyreBothMineText",
            "event": "EVENT_BEAT_MT_MOON_3_SUPER_NERD",
            "won": "_MtMoonB2FSuperNerdOkIllShareText",
        })

    def test_mtmoonb2f_survives_a_populated_map_entry(self):
        # A fresh extraction already fills in the map's other slots (2-5);
        # the override must add slot 1 alongside them, not replace them.
        texts, field_data = self.fixtures()
        texts["trainerHeaders"]["MtMoonB2F"] = {2: {"event": "EVENT_OTHER"}}
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertIn(1, texts["trainerHeaders"]["MtMoonB2F"])
        self.assertEqual(
            texts["trainerHeaders"]["MtMoonB2F"][2], {"event": "EVENT_OTHER"})

    def test_seafoam_boulder_toggle_ids_are_pinned(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        holes = field_data["seafoam"]["SEAFOAM_ISLANDS_B3F"][
            "pluggedByHolesOn"]["holes"]
        self.assertEqual(holes[0]["showObject"],
                          "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_5")
        self.assertEqual(holes[1]["showObject"],
                          "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_6")

    def test_trade_art_is_dropped(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertNotIn("tradeArt", field_data)

    def test_missing_trade_art_does_not_raise(self):
        texts, field_data = self.fixtures()
        del field_data["tradeArt"]
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)


if __name__ == "__main__":
    main()

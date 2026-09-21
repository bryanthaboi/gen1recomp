#!/usr/bin/env python3
"""Focused translation-harvest gate for the Gen 2 UI owned by this slice."""

import ast
import pathlib
import re
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.modkit import STRINGS_CALL, harvest_engine_strings  # noqa: E402


OWNED = [
    "OptionsMenu", "GenderSelect", "TrainerCard", "CenterPcMenu", "PcMenu",
    "ItemPcMenu", "InitClock", "CardFlip", "MailMenu", "PackMenu",
    "PrizeMenu", "SlotMachine", "ContestMenu", "TradeMenu", "MartMenu",
    "MailboxMenu", "StartMenu", "DayCareMenu", "HeldItemMenu",
    "BoxMenu", "EvolutionAnim", "BankOfMom", "NamePick", "MoveDeleter",
    "MailCompose",
]

REQUIRED = {
    # Shared finite UI.
    "YES", "NO", "CANCEL", "COIN", "Boy", "Girl",
    # Options helper-produced values and templates.
    "AUTO", "HIGH", "BALANCED", "LOW", "FIT", "OUT%d", "IN%d", "%dX",
    "GEN 2", "DMG", "CLASSIC", "PALETTE", "SKIN", "STRONG", "ADAPTIVE",
    "DISPLAY", "DISPLAY (%dHZ)", "GREEN", "MONO", "1X", "2X", "3X",
    # Center PC labels, prompts and flows.
    "BILL's PC", "%s's PC", "PROF.OAK's PC", "HALL OF FAME", "TURN OFF",
    "Bzzzzt! You must\nhave a #MON to\nuse this!",
    "{PLAYER} turned on\nthe PC.",
    "The link to PROF.\nOAK's PC closed.", "…\nLink closed…",
    "BILL's PC\naccessed.\n\n#MON Storage\nSystem opened.",
    "Accessed own PC.\n\nItem Storage\nSystem opened.",
    "PROF.OAK's PC\naccessed.\n\n#DEX Rating\nSystem opened.",
    "Want to get your\n#DEX rated?", "Access whose PC?",
    # Item PC menu and all item-operation messages.
    "WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "MAIL BOX", "LOG OFF",
    "DECORATION", "There's no room\nfor more items.",
    "Withdrew %d\n%s(S).", "How many do you\nwant to withdraw?",
    "There's no room to\nstore items.", "Deposited %d\n%s(S).",
    "No items here!", "How many do you\nwant to deposit?",
    "That's too impor-\ntant to toss out!", "Toss out how many\n%s(S)?",
    "Throw away %d\n%s(S)?", "Discarded\n%s(S).",
    "What do you want\nto do?",
    # Contest comparison labels and prompt.
    " STOCK <PK><MN> ", " THIS <PK><MN> ", "HEALTH", "Switch #MON?",
    "Caught %s!", "You already caught\na %s.",
    # Mart's direct top-level labels.
    "BUY", "SELL", "QUIT",
    # Trainer Card's badge-name labels.
    "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER",
    "RISING", "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH",
    "VOLCANO", "EARTH",
    # START descriptions are complete reflowable keys, not two frozen rows.
    "POKéMON\ndatabase", "Party <PK><MN>\nstatus", "Contains\nitems",
    "Trainer's\nkey device", "Your own\nstatus", "Save your\nprogress",
    "Change\nsettings", "Installed\nadd-ons", "Return to\nthe title",
    "Return to the\ntitle screen?",
    # Bill's storage list, including complete prompts and refusals.
    "MOVE", "STATS", "RELEASE", "PARTY <PK><MN>", "BOX%d",
    "Choose a <PK><MN>.", "What's up?", "Move to where?",
    "It's your last <PK><MN>!", "No more usable <PK><MN>!",
    "Remove MAIL.", "There's no room!", "Saving… Leave ON!",
    "No releasing EGGS!", "Release <PK><MN>?",
    "Released <PK><MN>.\fBye,\n%s!",
    "Got %s!", "Stored %s!",
    "There is no POKéMON there.", "The BOX is full.",
    "You can't deposit\nthe last POKéMON!",
    "You can't take\nany more POKéMON.",
    # Other newly covered screens.
    "What? %s\nis evolving!", "Huh? %s\nstopped evolving!",
    "Congratulations!\nYour %s", "evolved into\n%s!",
    "%s learned\n%s!", "%s wants to\nlearn %s!",
    "SAVED", "HELD", "NAME", "NEW NAME", "PP", "lower", "UPPER",
    "DEL", "END",
    # Game Corner engine text.
    "Play with\n3 coins?", "Choose a\ncard.", "Place\nyour bet",
    "Play\nagain?", "The cards\nshuffled.", "Bet how many\ncoins?",
    "Darn… Ran out of\ncoins…", "    lined up!\nWon %d coins!",
    # PACK messages are whole templates so translations can reflow them.
    "Throw away how\nmany?", "Where should this\nbe moved to?",
    "You don't have a\n#MON!", "An EGG can't hold\nan item.",
    "OAK: {PLAYER}!\nThis isn't the\vtime to use that!",
    "The REPEL used\nearlier is still\vin effect.", "Coins:\n%d",
    "You now have\n%d points.", "{PLAYER} used the\n%s.",
    "There was a trophy\ninside!\f{PLAYER} sent the\ntrophy home.",
    "Throw away %d\n%s(S)?", "Threw away\n%s(S).",
    "%s can't learn %s!", "%s already knows %s!",
    "Registered the\n%s.", "You can't register\nthat item.",
    # Prize-counter pages and stable dynamic templates.
    "Welcome!\fWe exchange your\ncoins for fabulous\fprizes!",
    "Which prize would\nyou like?", "OK, so you wanted\na %s?",
    "You don't have\nenough coins.", "You have no room\nfor it.",
    "Welcome!\fWe exchange your\ngame coins for\ffabulous prizes!",
    "%s.\nIs that right?", "Sorry! You need\nmore coins.",
    "Welcome to the\nGAME CORNER.", "Do you need some\ngame coins?",
    "Thank you!\nHere are 50 coins.", "Whoops! Your COIN\nCASE is full.",
    # The Game Corner's two refusals (src/script/gen2/Specials.lua): both are
    # looked up at runtime, so they only reach a catalog while their literals
    # stay visible to the harvester rather than hiding behind a local.
    "You have no coins.", "You don't have a\nCOIN CASE.",
    # The Bug-Catching Contest confirmation, one key rather than the two
    # half-sentences it used to be drawn as.
    "Would you like to\nend the Contest?",
    # and its status box above the menu. "None" carries a context there, since
    # the bare key is also the import wizard's "no limit" label.
    "CAUGHT", "LEVEL", "BALLS:",
}


def lua_literal(token):
    """Decode the quoted subset accepted by modkit's STRINGS_CALL."""
    return ast.literal_eval(token)


class Gen2UiTranslationHarvestTest(unittest.TestCase):
    def test_required_player_facing_keys_are_harvested(self):
        harvested = {lua_literal(token) for token, _ in harvest_engine_strings(ROOT)}
        self.assertEqual([], sorted(REQUIRED - harvested))

    def test_every_declared_owned_key_reaches_modkit(self):
        harvested = {lua_literal(token) for token, _ in harvest_engine_strings(ROOT)}
        declared = set()
        for module in OWNED:
            body = (ROOT / "src" / "ui" / "gen2" / f"{module}.lua").read_text()
            declared.update(lua_literal(match.group(1))
                            for match in STRINGS_CALL.finditer(body))
        self.assertEqual([], sorted(declared - harvested))

    def test_no_direct_finite_label_bypasses_strings(self):
        raw_print = re.compile(
            r'Chrome\.(?:print|printThrough)\(\s*["\'](?:YES|NO|CANCEL|COIN)["\']')
        raw_label = re.compile(r'\blabel\s*=\s*["\']')
        failures = []
        for module in OWNED:
            path = ROOT / "src" / "ui" / "gen2" / f"{module}.lua"
            for number, line in enumerate(path.read_text().splitlines(), 1):
                code = line.split("--", 1)[0]
                if raw_print.search(code) or raw_label.search(code):
                    failures.append(f"{path.relative_to(ROOT)}:{number}: {code.strip()}")
        self.assertEqual([], failures)

    def test_pc_messages_are_not_reintroduced_as_raw_line_arrays(self):
        bypass = re.compile(
            r'(?:self:(?:say|drawBottomLines)|prompt\s*=)\s*\(?' r'\s*\{\s*\{?\s*["\']')
        failures = []
        for module in ("CenterPcMenu", "ItemPcMenu"):
            path = ROOT / "src" / "ui" / "gen2" / f"{module}.lua"
            for number, line in enumerate(path.read_text().splitlines(), 1):
                code = line.split("--", 1)[0]
                if bypass.search(code):
                    failures.append(f"{path.relative_to(ROOT)}:{number}: {code.strip()}")
        self.assertEqual([], failures)

    def test_reviewed_modules_have_no_raw_player_facing_sinks(self):
        modules = {
            "BoxMenu", "EvolutionAnim", "BankOfMom", "NamePick",
            "MoveDeleter", "MailCompose", "PrizeMenu", "CardFlip",
            "SlotMachine", "PackMenu", "StartMenu",
        }
        direct_print = re.compile(
            r'Chrome\.(?:print|printThrough)\(\s*["\'][A-Za-z]')
        raw_message = re.compile(
            r'(?:self\.(?:lines|message)\s*=|self:(?:say|ask|showMessage)\()'
            r'\s*\{\s*["\']')
        raw_named_rows = re.compile(
            r'\b(?:desc|prompt|intro|which|playAgain|notEnough|betHowMany|'
            r'ranOut|shuffled)\s*=\s*\{\s*["\']')
        failures = []
        for module in modules:
            path = ROOT / "src" / "ui" / "gen2" / f"{module}.lua"
            lines = path.read_text().splitlines()
            for number, line in enumerate(lines, 1):
                code = line.split("--", 1)[0]
                if direct_print.search(code) or raw_message.search(code):
                    failures.append(
                        f"{path.relative_to(ROOT)}:{number}: {code.strip()}")
                if raw_named_rows.search(code):
                    nearby = "\n".join(lines[number - 1:number + 3])
                    if "source = Strings.source" not in nearby:
                        failures.append(
                            f"{path.relative_to(ROOT)}:{number}: {code.strip()}")
        self.assertEqual([], failures)


if __name__ == "__main__":
    unittest.main()

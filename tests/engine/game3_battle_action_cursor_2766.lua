package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_map_sections").install()
local Ui = require("src.core.game3.battle.ui")
local function press(key)
  Ui.handleInput({ wasPressed = function(_, k) return k == key end })
end
local function check(ok, label)
  assert(ok, "FAIL cursor2766 " .. label)
  print("PASS cursor2766 " .. label)
end
local st = { player = { mon = {} } }
Ui.reset({ headless = true })
Ui.bindState(st)
Ui.openMenu()
check(Ui._menuIndex == 1, "initial_Fight")
press("right")
Ui.openMenu()
check(Ui._menuIndex == 2, "single_navigation_reopen_Bag")
press("down")
Ui.openMenu()
check(Ui._menuIndex == 4, "single_navigation_reopen_Run")
st.player = { mon = {} }
Ui.openMenu()
check(Ui._menuIndex == 1, "single_new_battler_Fight")
st.double = true
st.battlers = { [0] = st.player, [2] = { mon = {} } }
Ui.openMenu(0)
press("right")
Ui.openMenu(2)
press("down")
Ui.openMenu(0)
check(Ui._menuIndex == 2, "double_slot0_Bag")
Ui.openMenu(2)
check(Ui._menuIndex == 3, "double_slot2_Pokemon")
st.battlers[0] = { mon = {} }
Ui.openMenu(0)
check(Ui._menuIndex == 1, "double_slot0_canonical_replacement_Fight")
Ui.openMenu(2)
check(Ui._menuIndex == 3, "double_partner_cursor_unchanged")
st.battlers[2] = { mon = {} }
Ui.openMenu(2)
check(Ui._menuIndex == 1, "double_slot2_replacement_Fight")
st.double, st.battlers, st.safari = false, nil, true
Ui.openMenu()
press("right")
Ui.openMenu()
check(Ui._menuIndex == 2, "Safari_cursor_persists")
st.safari, st.oldManTutorial = false, true
Ui.openMenu()
local command = Ui.takeCommand()
check(Ui._mode == "none" and command and command.kind == "bag", "OldMan_scripted_Bag")
Ui.reset({ headless = true })
check(next(Ui._actionCursor) == nil and next(Ui._actionCursorBattler) == nil,
  "new_battle_clears_owners_and_cursors")
print("PASS cursor2766_ROM_free")


package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Vm = require("src.core.game3.scripting.vm")
local TextIR = require("src.core.game3.scripting.text_ir")
local session, finishShowMon, sound
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.field_move_show_mon"] = {
  start = function(_, _, fn) finishShowMon = fn end,
}
package.loaded["src.core.game3.audio"] = { playSe = function(id) sound = id end }
local level, radius = 4, nil
local View = {
  getFlashLevel = function() return level end,
  radiusForLevel = function(v) return 120 - v * 20 end,
  setFlashRadius = function(v) radius = v end,
  setFlashLevel = function(v) level, radius = v, nil end,
}
package.loaded["src.core.game3.field_view"] = View
local Moves = require("src.core.game3.field_moves")
local Field = require("src.core.game3.field")
local Fx = require("src.core.game3.field_effects")
local Text = require("src.core.game3.rom_text")
local function rejection(ctx, label)
  local ok, res = pcall(Moves.flashFromMenu, ctx)
  T.check(ok and res.ok == false and res.text == "CACHED REJECTION", label)
end
for _, version in ipairs({ "ruby", "sapphire", "emerald", "firered", "leafgreen" }) do
  GameVersion.set(version)
  session = { version = version, flags = {}, vars = {} }
  Field._session = session
  Field._locks = {}
  Space.store = Flags.newStore({ flags = session.flags })
  session.flags = Space.store.flags
  local rs = version == "ruby" or version == "sapphire"
  local label = rs and "gUnknown_081B694A" or "EventScript_UseFlash"
  local key = "fixture_flash"
  Space.bundle = { text = {
    [rs and "OtherText_CantUseThatHere" or "gText_InUseAlready_PM"] = TextIR.fromAscii("CACHED REJECTION"),
  }, labels = { [label] = key }, scripts = {
    [key] = { { op = "animateflash", 1 }, { op = "setflashlevel", 1 }, { op = "end" } },
  } }
  Space.vm = Vm.new({ scripts = Space.bundle.scripts, store = Space.store })
  Flags.setFlag(Space.store, nil, Moves.badgeFlag("FLASH"), true)
  local ctx = { session = session, store = Space.store, isCave = true }
  local payload = Moves.flashFromMenu(ctx)
  T.check(payload.ok and payload.action == "flash", version .. " first_use_available")
  level, radius, sound = 4, nil, nil
  Fx._anims = {}
  Field.executeFieldMove(payload)
  T.check(Field.locked and finishShowMon ~= nil and #Fx._anims == 0,
    version .. " show_mon_precedes_flash")
  T.check(not Flags.getFlag(Space.store, nil, payload.flag), version .. " flag_waits_for_show_mon")
  finishShowMon()
  T.eq(sound, payload.se, version .. " flash_sound_preserved")
  T.check(Flags.getFlag(Space.store, nil, payload.flag) and Field.locked,
    version .. " active_flag_and_animation_lock")
  Fx.step()
  Space.vm:tick()
  T.check(Field.locked and radius ~= nil, version .. " lock_waits_for_radius_animation")
  for _ = 1, 600 do Fx.step(); Space.vm:tick() end
  local rse = Profile.of(version).family == "rse"
  T.eq(level, rse and 1 or 0, version .. " first_use_cart_level")
  T.check(not Field.locked and not Space.vm:isRunning(), version .. " animation_end_unlocks_field")
  rejection(ctx, version .. " repeated_flash_cached_prompt")
  local game = { session = session, data = { maps = {
    floor = { mapType = 4, cave = 1 }, lit = { mapType = 4, cave = 0 },
    outdoors = { mapType = 1, cave = 0 },
  } } }
  Field.clearTempFieldEventData(game, "floor")
  rejection(ctx, version .. " dark_floor_retains_flash")
  Field.clearTempFieldEventData(game, "lit")
  rejection(ctx, version .. " lit_underground_retains_flash")
  Field.clearTempFieldEventData(game, "outdoors")
  T.check(not Flags.getFlag(Space.store, nil, payload.flag) and Moves.flashFromMenu(ctx).ok,
    version .. " outdoors_enables_next_cave_flash")
  if rs then
    T.raises(function() Text.ir("uncached_prompt") end, "is not in the script cache",
      version .. " missing_rom_text_stays_strict")
    Space.bundle.scripts[key] = { { op = "animateflash", 2 }, { op = "setflashlevel", 2 }, { op = "end" } }
    level, radius = 4, nil
    Fx._anims = {}
    Field.executeFieldMove(payload)
    finishShowMon()
    for _ = 1, 600 do Fx.step(); Space.vm:tick() end
    T.eq(level, 2, version .. " extracted_script_controls_level")
    Space.bundle.labels[label] = nil
    Field.executeFieldMove(payload)
    T.raises(finishShowMon, "ROM Flash script is not in the script cache",
      version .. " missing_rom_script_stays_strict")
    Field._locks = {}
  end
end
T.finish("game3_rs_flash_2762")

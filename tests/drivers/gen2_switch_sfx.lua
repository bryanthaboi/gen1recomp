-- ../pokecrystal/engine/pokemon/switchpartymons.asm:13
-- ../pokecrystal/home/audio.asm:220
local U = require("tests.drivers.util")

return function(game)
  local fails = 0
  local function ok(cond, msg)
    if cond then print("[switch-sfx] ok   " .. msg)
    else fails = fails + 1 print("[switch-sfx] FAIL " .. msg) end
    return cond
  end

  local shotDir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-switch-sfx"
  local function tap(btn) U.tap(game, btn) U.wait(3) end
  local function top() return game.stack:top() end
  local function waitFor(id, limit)
    for _ = 1, limit or 120 do
      local state = top()
      if (state and state.screenId or nil) == id then return true end
      U.wait(1)
    end
    return false
  end

  U.wait(45)
  ok(game.world and game.world.map, "gen 2 world booted")

  local Mon = require("src.battle.gen2.Mon")
  local save = game.save
  save.party = {
    Mon.new(game.data, "CYNDAQUIL", 12),
    Mon.new(game.data, "TOTODILE", 10),
  }

  local Sound = require("src.core.Sound")
  local sfx = game.data.audio and game.data.audio.sfx
  ok(sfx and sfx[Sound.resolve(game.data, "Sfx_SwitchPokemon")] ~= nil,
    "the cache carries Sfx_SwitchPokemon")

  tap("start")
  local menu = top()
  ok(menu and menu.screenId == "Gen2StartMenu", "START opened the menu")
  for _ = 1, 10 do
    if menu.list:current().value == "pokemon" then break end
    tap("down")
  end
  ok(menu.list:current().value == "pokemon", "the cursor found POKéMON")
  tap("a")

  waitFor("Gen2PartyMenu", 90)
  local party = top()
  if not ok(party and party.screenId == "Gen2PartyMenu",
      "POKéMON opened the list") then
    error("gen2 switch sfx: no party list, cannot continue")
  end

  tap("a")
  ok(party.submenu ~= nil, "a opened the submenu")
  for _ = 1, 4 do
    if party.submenu
      and party.submenu.items[party.submenu.index].id == "SWITCH" then break end
    tap("down")
  end
  ok(party.submenu
    and party.submenu.items[party.submenu.index].id == "SWITCH",
    "the cursor found SWITCH")
  tap("a")
  ok(party.submenu == nil and party.switchFrom == 1, "SWITCH holds the slot")
  tap("down")

  local rang = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    rang[#rang + 1] = name
    return realPlay(data, name, ...)
  end
  U.tap(game, "a")
  U.wait(1)
  ok(save.party[1].species == "TOTODILE"
    and save.party[2].species == "CYNDAQUIL", "the party reordered")
  ok(party.switchFrom == nil, "and the hold released")
  U.shot(game, shotDir .. "/switched.png")
  local beeps = 0
  for _ = 1, 180 do
    beeps = 0
    for _, name in ipairs(rang) do
      if name == "Sfx_SwitchPokemon" then beeps = beeps + 1 end
    end
    if beeps >= 2 and party.repeatSfx == nil then break end
    U.wait(1)
  end
  Sound.play = realPlay
  ok(beeps == 2, ("SFX_SWITCH_POKEMON rang twice (got %d)"):format(beeps))
  ok(party.repeatSfx == nil, "and nothing is left pending")

  rang = {}
  Sound.play = function(data, name, ...)
    rang[#rang + 1] = name
    return realPlay(data, name, ...)
  end
  tap("a")
  tap("down")
  ok(party.submenu
    and party.submenu.items[party.submenu.index].id == "SWITCH",
    "SWITCH again")
  tap("a")
  rang = {}
  tap("a")
  U.wait(60)
  Sound.play = realPlay
  local skipped = 0
  for _, name in ipairs(rang) do
    if name == "Sfx_SwitchPokemon" then skipped = skipped + 1 end
  end
  ok(skipped == 0, "the same slot rings nothing")
  ok(party.switchFrom == nil, "and the hold released")

  tap("b")
  tap("b")

  if fails > 0 then
    print("[driver] FAIL gen2 switch sfx")
    error(("gen2 switch sfx: %d assertion(s) failed"):format(fails))
  end
  print("[driver] PASS gen2 switch sfx: the switch cue rings twice")
end

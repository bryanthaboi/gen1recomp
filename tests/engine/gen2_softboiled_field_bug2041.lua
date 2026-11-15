-- ../pokecrystal/engine/pokemon/mon_menu.asm:724 MonMenu_Softboiled_MilkDrink

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FieldMoves = require("src.world.gen2.FieldMoves")
local PartyMenu = require("src.ui.gen2.PartyMenu")

local function mon(maxHp, hp, extra)
  local m = { species = "CHANSEY", nickname = "CHANSEY",
              stats = { hp = maxHp }, hp = hp }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- ../pokecrystal/data/mon_menu.asm MonMenuOptions
do
  local missing = {}
  for _, id in ipairs(PartyMenu.FIELD_MOVES) do
    if not FieldMoves.FROM_MENU[id] then missing[#missing + 1] = id end
  end
  eq(table.concat(missing, ","), "",
    "every MonMenuOptions row has a from-menu routine")
  check(FieldMoves.FROM_MENU.SOFTBOILED, "SOFTBOILED has one")
  check(FieldMoves.FROM_MENU.MILK_DRINK, "MILK_DRINK shares it")
end

-- ../pokecrystal/engine/events/overworld.asm:1317 TryRockSmashFromMenu
do
  local rock = { def = { index = 2, movement = 0x18 } }
  local nothing = FieldMoves.fromMenu("ROCK_SMASH", {})
  check(not nothing.ok, "nothing faced is .no_rock")
  eq(nothing.text, FieldMoves.TEXT.CANT_USE_HERE, "with FieldMoveFailed's line")

  local person = FieldMoves.fromMenu("ROCK_SMASH",
    { facingObject = { def = { index = 1, movement = 0x06 } } })
  check(not person.ok, "a standing NPC is not SPRITEMOVEDATA_SMASHABLE_ROCK")

  local ok = FieldMoves.fromMenu("ROCK_SMASH", { facingObject = rock })
  check(ok.ok, "the rock in front of the player is")
  eq(ok.action, "rocksmash", "and the menu queues the smash")
  eq(ok.lastTalked, 3, "hLastTalked is the object const, index + 1")
end

-- ../pokecrystal/engine/events/overworld.asm:1357 RockSmashFromMenuScript
do
  local std = { scripts = { SmashRockScript = { key = "40:4158" } } }
  local scripts = {
    ["40:4158"] = { { op = "farsjump", script = "03:4f60" } },
    ["03:4f60"] = {
      { op = "callasm" },
      { op = "ifequal", script = "03:4f72", value = 1 },
      { op = "opentext" },
      { op = "writetext", text = "03:4f7a" },
      { op = "yesorno" },
      { op = "iftrue", script = "03:4f35" },
      { op = "closetext" },
      { op = "end" },
    },
  }
  eq(FieldMoves.rockSmashScriptKey(std, scripts), "03:4f35",
    "AskRockSmashScript's iftrue target is RockSmashScript")
  eq(FieldMoves.rockSmashScriptKey(std, {}), nil, "an absent chain is nil")

  local script = FieldMoves.rockSmashFromMenuScript(std, scripts,
    function(name) return name == "UpdateTimePals" and 7 or nil end)
  eq(#script, 3, "refreshmap, special UpdateTimePals, then the fallthrough")
  eq(script[1].op, "refreshmap", "refreshmap first")
  eq(script[2].id, 7, "UpdateTimePals resolved through the cache's order")
  eq(script[3].op, "sjump", "and RockSmashScript is entered without the ask")
  eq(script[3].script, "03:4f35", "at the key the chain resolved")
  eq(FieldMoves.rockSmashFromMenuScript(std, {}, function() return 7 end), nil,
    "no key, no queued script")
end

-- ../pokecrystal/engine/pokemon/mon_menu.asm:744 .CheckMonHasEnoughHP
do
  local refused = FieldMoves.softboiledFromMenu({ mon = mon(100, 20) })
  check(not refused.ok, "exactly a fifth left is refused")
  eq(refused.text, FieldMoves.TEXT.NOT_ENOUGH_HP, "with _PokemonNotEnoughHPText")

  local ok = FieldMoves.softboiledFromMenu({ mon = mon(100, 21) })
  check(ok.ok, "one HP more is allowed")
  eq(ok.cost, 20, "and the transfer is the USER's maxHP/5")
  check(ok.inMenu, "the $3 return keeps the party list up")
  eq(ok.action, "softboiled", "the action names itself")
end

-- ../pokecrystal/engine/items/item_effects.asm:2043 .cant_use
do
  local user = mon(100, 60)
  eq(FieldMoves.softboiledTargetOk(user, user), false, "the user is no target")
  eq(FieldMoves.softboiledTargetOk(user, mon(50, 50)), false,
    "nor is a full-health mon")
  eq(FieldMoves.softboiledTargetOk(user, mon(50, 0)), false,
    "nor a fainted one")
  eq(FieldMoves.softboiledTargetOk(user, mon(50, 10, { isEgg = true })), false,
    "nor an EGG")
  eq(FieldMoves.softboiledTargetOk(user, mon(50, 10)), true,
    "a hurt teammate is")
end

-- ../pokecrystal/engine/items/item_effects.asm:1997 RemoveHP / :2005 RestoreHealth
do
  local user, target = mon(100, 60), mon(50, 10)
  local before, after = FieldMoves.softboiledTransfer(user, target, 20)
  eq(before, 10, "the recipient's HP before")
  eq(after, 30, "and after the user's fifth landed")
  eq(user.hp, 40, "the user paid its own fifth")

  local capped = mon(50, 45)
  local b2, a2 = FieldMoves.softboiledTransfer(user, capped, 20)
  eq(b2, 45, "a nearly full mon still takes it")
  eq(a2, 50, "capped at max HP")

  local refused = FieldMoves.softboiledTransfer(user, user, 20)
  eq(refused, nil, "a refused transfer spends nothing")
  eq(user.hp, 20, "so the user's HP is untouched by it")
end

-- ../pokecrystal/engine/items/item_effects.asm:1999 HealHP_SFX_GFX
do
  local input = { pressed = {} }
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end

  local party = {
    mon(100, 60),
    mon(50, 10, { species = "GEODUDE", nickname = "GEODUDE" }),
  }
  local game = { data = { gen2MenuGfx = {},
    text = require("tests.fixture_data.gen2_rom_text_s7_e") }, input = input,
    save = { party = party } }
  local menu = PartyMenu.new(game, { party = party, prompt = "useItem" })
  menu:beginSoftboiled(1, 20)
  menu.index = 2
  menu:finishSoftboiled()

  eq(menu.itemResult.slot, 1, "the user's own bar drops first")
  eq(menu:shownHpFor(1, party[1]), 60, "starting at its pre-cost HP")
  eq(menu:shownHpFor(2, party[2]), 10,
    "with the recipient still frozen at its own")
  eq(menu.itemResult.text, nil, "and nothing printed over it")

  for _ = 1, 60 do
    if menu.itemResult and menu.itemResult.slot == 2 then break end
    menu:update(1 / 60)
  end
  eq(menu.itemResult.slot, 2, "then the recipient's climb takes over")
  eq(menu.itemResult.shown, 10, "from its pre-heal HP")
  eq(menu:shownHpFor(1, party[1]), 40, "the user reads the paid-down HP now")
  eq(menu.itemResult.text, "GEODUDE\nrecovered 20HP!",
    "and _RecoveredSomeHPText arrives with the climb")
end

T.finish("gen2 softboiled field bug2041")

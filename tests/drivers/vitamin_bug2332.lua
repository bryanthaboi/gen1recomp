-- engine/items/item_effects.asm:1310-1317
-- data/text/text_6.asm:71-77
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Bag = require("src.inventory.Bag")
  local Sound = require("src.core.Sound")
  local PartyMenu = require("src.ui.PartyMenu")
  local TextBox = require("src.render.TextBox")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  local failed = false

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  local function stackHas(pred)
    for _, s in ipairs(game.stack.states or {}) do
      if pred(s) then return true end
    end
    return false
  end
  local function isBox(s) return getmetatable(s) == TextBox end
  local function isParty(s) return getmetatable(s) == PartyMenu end

  if (game.save.options and game.save.options.sfxVol or 1) == 0 then
    U.log("WARNING: sfxVol is 0, so nothing here can be heard.")
  end

  local mon = Pokemon.new(game.data, "NIDORINO", 20)
  game.save.party = { mon }
  game.save.player.name = "bryan"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local heard
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    if name == "Heal_Ailment" and not heard then
      heard = { boxUp = stackHas(isBox), partyUp = stackHas(isParty) }
    end
    return realPlay(data, name, ...)
  end

  local function useVitamin(id, statName, tag, shotOpen, shotDone)
    heard = nil
    while #game.stack.states > 1 do
      game.stack:pop()
    end
    game.save.inventory = {}
    Bag.add(game.save, id, 1, game.data)
    Screens.push(game, "BagMenu", {})
    U.wait(12)
    U.tap(game, "a")
    U.wait(12)
    U.tap(game, "a")
    U.wait(12)
    U.tap(game, "a")
    local box
    for _ = 1, 30 do
      local top = game.stack:top()
      if isBox(top) then box = top break end
      U.wait(1)
    end
    if not check(tag .. " rose box opened", box ~= nil) then return end
    local typedAtOpen = box.charIndex or 0
    check(tag .. " Heal_Ailment fired before the rose box existed",
          heard ~= nil and heard.boxUp == false)
    check(tag .. " Heal_Ailment fired over the party menu",
          heard ~= nil and heard.partyUp == true)
    check(tag .. " rose box was still typing when first seen (char "
          .. tostring(typedAtOpen) .. ")", not box.done and typedAtOpen <= 2)
    U.wait(2)
    U.shot(game, SHOT_DIR .. "/" .. shotOpen)
    for _ = 1, 240 do
      if box.done then break end
      U.wait(1)
    end
    local page = box.pages and box.pages[1] or {}
    check(tag .. " line 1 is NIDORINO's", page[1] == "NIDORINO's")
    check(tag .. " line 2 is " .. statName .. " rose.",
          page[2] == statName .. " rose.")
    check(tag .. " party menu is still drawn under the message",
          stackHas(isParty))
    U.shot(game, SHOT_DIR .. "/" .. shotDone)
    U.log(tag, "typed:", tostring(page[1]), "/", tostring(page[2]))
    U.tap(game, "a")
    U.wait(20)
  end

  useVitamin("CALCIUM", "SPECIAL", "CALCIUM",
             "2332_01_calcium_jingle_box_opening.png",
             "2332_02_calcium_special_rose_typed.png")
  check("CALCIUM raised SPECIAL stat exp",
        (mon.statExp and mon.statExp.special or 0) == 2560)
  useVitamin("HP_UP", "HEALTH", "HP_UP",
             "2332_03_hp_up_jingle_box_opening.png",
             "2332_04_hp_up_health_rose_typed.png")
  check("HP_UP raised HP stat exp",
        (mon.statExp and mon.statExp.hp or 0) == 2560)

  Sound.play = realPlay
  U.log("the cure jingle should start as the box opens and play while")
  U.log("NIDORINO's / SPECIAL rose. types, not after the last letter.")
  U.log(failed and "FAIL vitamin_bug2332" or "PASS vitamin_bug2332")
  love.event.quit(failed and 1 or 0)
end

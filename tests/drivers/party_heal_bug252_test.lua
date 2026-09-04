-- Driver: watch a POTION fill the party menu's HP bar (#252).
-- pokered engine/items/item_effects.asm .doneHealing runs UpdateHPBar2 with
-- the party menu still drawn; status cures branch off and never touch the bar.
-- Not under POKEPORT_SPEED: SFX_HEAL_HP rides the real-time audio clock.
--   POKEPORT_DRIVER=tests/drivers/party_heal_bug252_test.lua \
--     POKEPORT_IDENTITY=bug252 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local ItemEffects = require("src.inventory.ItemEffects")
  local PartyMenu = require("src.ui.PartyMenu")
  local TextBox = require("src.render.TextBox")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function isPicker(s)
    return s ~= nil and (s.screenId == "PartyMenu" or getmetatable(s) == PartyMenu)
  end
  local function isBox(s) return getmetatable(s) == TextBox end
  -- engine/menus/start_sub_menus.asm:414-416
  local function isFlash(s)
    return type(s) == "table" and s.t ~= nil and s.frames ~= nil
  end
  local function inStack(pred)
    for _, s in ipairs(game.stack.states or {}) do
      if pred(s) then return true end
    end
    return false
  end

  -- ---- preconditions ------------------------------------------------------
  -- A lost item id, a healsHP gate that dropped an item, or a use() that stops
  -- handing back the pre-heal HP all read as "the animation is broken".
  U.log("======== #252 party-menu HP fill: machine checks ========")
  check("ItemEffects.healsHP exists", type(ItemEffects.healsHP) == "function")
  check("PartyMenu:animateTo exists", type(PartyMenu.animateTo) == "function")
  check("PartyMenu:close exists", type(PartyMenu.close) == "function")
  if type(ItemEffects.healsHP) == "function" then
    -- .doneHealing is reached by exactly the .healHP items; FULL_HEAL and the
    -- single-status cures jump to the no-bar branch
    for _, id in ipairs({ "POTION", "SUPER_POTION", "HYPER_POTION",
                          "MAX_POTION", "FULL_RESTORE", "REVIVE",
                          "MAX_REVIVE" }) do
      check(id .. " takes the .healHP (animated) path",
            ItemEffects.healsHP(id) == true)
    end
    for _, id in ipairs({ "ANTIDOTE", "PARLYZ_HEAL", "AWAKENING", "BURN_HEAL",
                          "ICE_HEAL", "FULL_HEAL", "ETHER" }) do
      check(id .. " does NOT animate the bar (status cure / PP)",
            ItemEffects.healsHP(id) ~= true)
    end
  end
  for _, id in ipairs({ "POTION", "MAX_POTION", "REVIVE", "ANTIDOTE" }) do
    check(id .. " resolves in the item table", game.data.items[id] ~= nil)
  end

  -- use() must hand back the PRE-heal HP so the fill has a start (wHPBarOldHP)
  do
    local scratch = Pokemon.new(game.data, "BULBASAUR", 20)
    scratch.hp = 3
    local scratchSave = { party = { scratch }, inventory = {}, flags = {},
                          pokedex = { seen = {}, owned = {} } }
    local result, msgs, extra = ItemEffects.use(game.data, scratchSave,
                                                "POTION", scratch)
    check("POTION on a hurt mon reports consumed", result == "consumed")
    check("...and hands back extra.healedFrom = the pre-heal HP",
          type(extra) == "table" and extra.healedFrom == 3)
    check("...with the restored-HP message",
          type(msgs) == "table" and type(msgs[1]) == "string"
          and msgs[1]:find("recovered", 1, true) ~= nil)
    local _, _, cureExtra = ItemEffects.use(game.data, scratchSave,
                                            "ANTIDOTE", scratch)
    check("ANTIDOTE hands back no healedFrom (no fill)",
          cureExtra == nil or cureExtra.healedFrom == nil)
  end

  -- ---- the fixture --------------------------------------------------------
  -- CHARIZARD L50 sits near 150 max HP, so a MAX_POTION from 1 HP is the full
  -- 96-frame fill across the whole 48-pixel bar.
  local lead = Pokemon.new(game.data, "CHARIZARD", 50)
  local fainted = Pokemon.new(game.data, "PIKACHU", 30)
  local poisoned = Pokemon.new(game.data, "SNORLAX", 40)
  lead.hp = 1
  fainted.hp = 0
  poisoned.status = "PSN"
  game.save.party = { lead, fainted, poisoned }
  game.save.player.name = "RED"
  for _, row in ipairs({ { "MAX_POTION", 9 }, { "POTION", 9 },
                         { "REVIVE", 9 }, { "ANTIDOTE", 9 } }) do
    Bag.add(game.save, row[1], row[2])
  end
  U.log(("lead: %s %d/%d HP"):format(lead.species, lead.hp, lead.stats.hp))

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  -- ---- menu navigation ---------------------------------------------------
  local function cursorTo(menu, want)
    for _ = 1, 40 do
      if not menu or menu.index == want then return menu and menu.index == want end
      U.tap(game, menu.index < want and "down" or "up")
      U.wait(3)
    end
    return menu.index == want
  end

  -- START -> ITEM -> <id> -> USE, leaving the party picker open.  Returns the
  -- picker, or nil plus a reason.
  local function openPickerFor(id)
    U.tap(game, "start")
    U.wait(10)
    local menu = top()
    if not (menu and menu.screenId == "StartMenu") then
      return nil, "start menu never opened"
    end
    -- the ITEM row shifts with POKéDEX / LINK / MODS, so never hardcode it
    local itemRow
    for i, it in ipairs(menu.items or {}) do
      if it.label == "ITEM" then itemRow = i break end
    end
    if not itemRow or not cursorTo(menu, itemRow) then return nil, "no ITEM row" end
    U.tap(game, "a")
    U.wait(10)

    local bag = top()
    if not (bag and bag.screenId == "BagMenu") then return nil, "bag never opened" end
    local bagRow
    for i, r in ipairs(bag.items or {}) do
      if r.value == id then bagRow = i break end
    end
    if not bagRow or not cursorTo(bag, bagRow) then return nil, id .. " not in bag" end
    U.tap(game, "a")
    U.wait(10)

    -- outside battle every usable item offers USE / TOSS first; USE is row 1
    local ut = top()
    if ut and ut.items and ut.items[1] and ut.items[1].label == "USE" then
      if not cursorTo(ut, 1) then return nil, "USE row unreachable" end
      U.tap(game, "a")
      U.wait(10)
    end
    local picker = top()
    if not isPicker(picker) then return nil, "party picker never opened" end
    return picker
  end

  local function backToOverworld()
    for _ = 1, 30 do
      if top() == game.overworld then return true end
      U.tap(game, "b")
      U.wait(6)
    end
    return top() == game.overworld
  end

  -- ======== scripted run: MAX_POTION on the 1 HP lead ======================
  U.log("======== #252 scripted run: MAX POTION on a 1 HP CHARIZARD ========")
  local picker, why = openPickerFor("MAX_POTION")
  check("party picker opened for MAX POTION" .. (why and (" (" .. why .. ")") or ""),
        picker ~= nil)

  if picker then
    check("cursor sits on the hurt lead", cursorTo(picker, 1))
    U.shot(game, DIR .. "/bug252_picker_before.png")

    local hpBefore = lead.hp
    U.tap(game, "a") -- choose the lead

    -- THE DEFECT: the picker used to pop here, before the item had even run.
    check("the party menu is STILL the top state after the A press",
          isPicker(top()))
    check("the fill is running (picker.heal is set)",
          type(picker.heal) == "table")
    -- engine/items/item_effects.asm:1209
    check("the cursor is still drawn while the bar fills",
          picker.cursorsErased ~= true)
    if type(picker.heal) == "table" then
      check("the fill starts from the pre-heal HP (wHPBarOldHP)",
            math.floor(picker.heal.shown + 0.5) == hpBefore)
    end

    -- Sample the climb and prove input is ignored for its duration
    -- (UpdateHPBar2 blocks).  U.frame() is the real yield count: the taps below
    -- each burn a frame, so an iteration counter would under-report.
    local startFrame, samples, blocked = U.frame(), {}, true
    local iter, shot1, shot2 = 0, false, false
    for _ = 1, 400 do
      if not picker.heal then break end
      local shown = picker.heal.shown
      samples[#samples + 1] = shown
      local frac = shown / math.max(1, lead.stats.hp)
      if not shot1 and frac > 0.33 then
        shot1 = true
        U.shot(game, DIR .. "/bug252_fill_third.png")
      elseif not shot2 and frac > 0.66 then
        shot2 = true
        U.shot(game, DIR .. "/bug252_fill_two_thirds.png")
      else
        -- mash B and A: neither may do anything while the bar is filling
        U.tap(game, (iter % 2 == 0) and "b" or "a")
      end
      if picker.heal and not isPicker(top()) then blocked = false end
      iter = iter + 1
      U.wait(1)
    end
    local frames = U.frame() - startFrame
    U.log(("fill ran ~%d frames (%.2f s at 60 Hz)"):format(frames, frames / 60))
    check("the fill took more than half a second (it animates, not snaps)",
          frames > 30)
    check("the fill is not absurdly long (< 3 s)", frames < 180)
    check("A and B did nothing while the bar filled", blocked)
    local rose = #samples >= 2 and samples[#samples] > samples[1]
    check("the drawn HP climbed over those frames", rose)
    if #samples >= 2 then
      U.log(("shown HP walked %.1f -> %.1f of %d")
              :format(samples[1], samples[#samples], lead.stats.hp))
    end
    check("the mon really is at full HP now", lead.hp == lead.stats.hp)

    -- .showHealingItemMessage: the message prints with the menu still drawn
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    check("the message box opened", isBox(top()))
    check("...over the STILL-drawn party menu", inStack(isPicker))
    -- engine/items/item_effects.asm:1232 (#2062)
    check("...with the menu cursor erased", picker.cursorsErased == true)
    U.wait(60) -- let the line type out, so the shot shows the text not an empty box
    U.shot(game, DIR .. "/bug252_message_over_party.png")

    -- TextBox pops BEFORE it fires onDone, which is what makes
    -- PartyMenu:close's identity check land on the picker
    for _ = 1, 30 do
      if not inStack(isPicker) then break end
      U.tap(game, "a")
      U.wait(8)
    end
    check("the picker is gone once the message is dismissed", not inStack(isPicker))
    local flashed = isFlash(top())
    check("the return to the bag whites out (#2125)", flashed)
    if flashed then U.shot(game, DIR .. "/bug2125_white.png") end
    for _ = 1, 40 do
      if not isFlash(top()) then break end
      U.wait(1)
    end
    local back = top()
    check("and we are back on the ITEM list", back ~= nil and back.screenId == "BagMenu")
    U.shot(game, DIR .. "/bug252_back_on_bag.png")
  end
  backToOverworld()

  -- ======== contrast: ANTIDOTE must NOT animate ===========================
  U.log("======== #252 contrast: ANTIDOTE (no bar fill at all) ========")
  local cure = openPickerFor("ANTIDOTE")
  if check("party picker opened for ANTIDOTE", cure ~= nil) then
    check("keepOpen is off for a status cure", cure.keepOpen ~= true)
    cursorTo(cure, 3) -- the poisoned SNORLAX
    U.tap(game, "a")
    U.wait(6)
    check("no fill was started for a status cure", cure.heal == nil)
    check("the picker popped itself, like every non-medicine item",
          not inStack(isPicker))
    U.shot(game, DIR .. "/bug252_antidote_message.png")
    check("PSN was cured", poisoned.status == nil)
  end
  backToOverworld()

  -- ---- verdict, then re-arm and hand off ----------------------------------
  U.log(("======== machine checks: %d passed, %d failed ========"):format(pass, fail))

  lead.hp = 1
  fainted.hp = 0
  poisoned.status = "PSN"
  local rearmed = openPickerFor("MAX_POTION")
  if rearmed then cursorTo(rearmed, 1) end

  U.log("The bag, USE and the party picker are re-opened with the cursor on a")
  U.log("1 HP CHARIZARD and a MAX POTION chosen. Press A, watch slot 1's bar:")
  U.log("the list stays up, the bar lengthens over ~1.5s with the number, and")
  U.log("buttons do nothing until it lands. #252 was the list snapping shut.")
  U.log("Spare items are in the bag if you want to run it again.")

  while true do
    coroutine.yield()
  end
end

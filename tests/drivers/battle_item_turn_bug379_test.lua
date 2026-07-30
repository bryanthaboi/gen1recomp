-- Driver: a POTION used in battle prints, moves the HUD bar and spends the
-- turn (#379).  pokered engine/items/item_effects.asm:1-3 leaves
-- wActionResultOrTookBattleTurn at its success value, and ItemUseMedicine only
-- clears it on .healingItemNoEffect (:1241), so a medicine that lands costs
-- the turn; the party-menu bar fill is the field case (#252).  Data half:
-- tests/parity_battle_item_turn.lua.  Never under POKEPORT_SPEED: fast-forward
-- desynchronizes SFX_HEAL_HP from the bar.
--   POKEPORT_DRIVER=tests/drivers/battle_item_turn_bug379_test.lua POKEPORT_IDENTITY=bug379 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local BattleState = require("src.battle.BattleState")
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
  local function isBag(s) return s ~= nil and s.screenId == "BagMenu" end
  local function inStack(pred)
    for _, s in ipairs(game.stack.states or {}) do
      if pred(s) then return true end
    end
    return false
  end
  local function boxText(s)
    local out = {}
    for _, page in ipairs(s.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " ")
  end

  -- ---- preconditions -----------------------------------------------------
  U.log("#379 in-battle medicine: machine checks")
  check("POTION takes the HP-medicine path", ItemEffects.healsHP("POTION") == true)
  check("ANTIDOTE does not (status cure, always spent the turn)",
        ItemEffects.healsHP("ANTIDOTE") ~= true)
  for _, id in ipairs({ "POTION", "SUPER_POTION", "ANTIDOTE" }) do
    check(id .. " resolves in the item table", game.data.items[id] ~= nil)
  end
  check("SFX_HEAL_HP is in the generated audio",
        game.data.audio and game.data.audio.sfx
        and game.data.audio.sfx.Heal_HP ~= nil)
  check("BattleState:itemUsed exists (queues the foe's turn)",
        type(BattleState.itemUsed) == "function")

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the heal chime will be SILENT, raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- expect the heal chime under the bar drain")
  end

  -- use() must hand back the pre-heal HP; without it neither bar has a start
  do
    local scratch = Pokemon.new(game.data, "BULBASAUR", 20)
    scratch.hp = 4
    local scratchSave = { party = { scratch }, inventory = {}, flags = {},
                          pokedex = { seen = {}, owned = {} } }
    local result, msgs, extra = ItemEffects.use(game.data, scratchSave,
                                                "POTION", scratch)
    check("POTION on a hurt mon reports consumed", result == "consumed")
    check("...and hands back the pre-heal HP",
          type(extra) == "table" and extra.healedFrom == 4)
    check("...with the restored-HP message",
          type(msgs) == "table" and type(msgs[1]) == "string"
          and msgs[1]:find("restored", 1, true) ~= nil)
  end

  -- ---- fixture -----------------------------------------------------------
  local lead = Pokemon.new(game.data, "CHARIZARD", 50)
  local second = Pokemon.new(game.data, "PIKACHU", 30)
  lead.hp = 12
  game.save.party = { lead, second }
  game.save.player.name = "RED"
  for _, id in ipairs({ "POTION", "SUPER_POTION", "ANTIDOTE" }) do
    Bag.add(game.save, id, 9)
  end

  -- ROUTE_1 is open field with tall grass either side of the path
  -- (data/generated/maps.lua ROUTE_1); the cell comes off the loaded map so a
  -- map edit degrades to somewhere else in the grass instead of a wall.
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  local map = ow.map
  local gx, gy
  if not map:isWalkableCell(5, 5) then
    for cy = 0, map.heightCells - 1 do
      for cx = 0, map.widthCells - 1 do
        if map:isGrassCell(cx, cy) and map:isWalkableCell(cx, cy) then
          gx, gy = cx, cy
          break
        end
      end
      if gx then break end
    end
    if gx then
      U.teleport(game, "ROUTE_1", gx, gy, "down")
      U.wait(10)
      ow = game.overworld
    end
  end
  check("player is standing on a walkable ROUTE_1 cell",
        ow.map:isWalkableCell(ow.player.cellX, ow.player.cellY))

  -- ---- navigation --------------------------------------------------------
  local function mashUntil(cond, max)
    for _ = 1, max or 120 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return cond()
  end

  -- FIGHT PKMN / ITEM RUN (BattleState.menuIndex): down from FIGHT is ITEM
  local function openBagFrom(battle)
    for _ = 1, 30 do
      if battle.menuIndex == 3 then break end
      U.tap(game, battle.menuIndex > 2 and "up" or "down")
      U.wait(4)
    end
    if battle.menuIndex ~= 3 then return nil, "ITEM cell unreachable" end
    U.tap(game, "a")
    U.wait(20)
    local bag = top()
    if not isBag(bag) then return nil, "bag never opened" end
    return bag
  end

  local function cursorTo(menu, want)
    for _ = 1, 40 do
      if not menu or menu.index == want then return menu and menu.index == want end
      U.tap(game, menu.index < want and "down" or "up")
      U.wait(3)
    end
    return menu.index == want
  end

  local function chooseItem(bag, id)
    local row
    for i, r in ipairs(bag.items or {}) do
      if r.value == id then row = i break end
    end
    if not row or not cursorTo(bag, row) then return false end
    U.tap(game, "a") -- in battle A uses it straight away, no USE / TOSS
    U.wait(16)
    return true
  end

  local function newFight()
    local battle = BattleState.newWild(game, "PIDGEY", 8)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    mashUntil(function() return battle.phase == "menu" end)
    return battle
  end

  -- ======== scripted run: POTION on the hurt lead ==========================
  U.log("#379 scripted run: POTION on a 12 HP CHARIZARD, mid-battle")
  local battle = newFight()
  check("the wild battle reached its FIGHT menu", battle.phase == "menu")

  local turns, ends = 0, 0
  local realAction, realEnd = battle.executeAction, battle.endOfTurn
  battle.executeAction = function(self, ...)
    turns = turns + 1
    return realAction(self, ...)
  end
  battle.endOfTurn = function(self, ...)
    ends = ends + 1
    return realEnd(self, ...)
  end

  local bag, why = openBagFrom(battle)
  check("ITEM opened the bag" .. (why and (" (" .. why .. ")") or ""), bag ~= nil)
  if bag then
    U.shot(game, DIR .. "/bug379_bag_in_battle.png")
    check("POTION chosen from the bag", chooseItem(bag, "POTION"))
    local picker = top()
    check("the party picker opened to pick a target", isPicker(picker))
    if isPicker(picker) then
      check("keepOpen is off in battle (the fill is the field case, #252)",
            picker.keepOpen ~= true)
      cursorTo(picker, 1)
      U.tap(game, "a")
      U.wait(10)

      check("the mon was healed", lead.hp > 12)
      check("no party-menu bar fill was started in battle", picker.heal == nil)
      check("the picker popped itself", not inStack(isPicker))
      check("the bag list closed underneath it", not inStack(isBag))

      -- THE DEFECT: the animate branch swallowed this message, and with it the
      -- itemUsed tail that spends the turn
      for _ = 1, 60 do
        if isBox(top()) then break end
        U.wait(1)
      end
      local box = top()
      check("the restored-HP message printed (#379)", isBox(box))
      if isBox(box) then
        U.wait(50)
        local said = boxText(box)
        U.log("box reads:", said)
        check("...and it is the restored-HP line",
              said:find("restored", 1, true) ~= nil)
        U.shot(game, DIR .. "/bug379_message_in_battle.png")
      end

      -- the turn: drain, the foe's move, end-of-turn, back to the menu
      for _ = 1, 400 do
        if battle.phase == "menu" and #battle.queue == 0 then break end
        U.tap(game, "a")
        U.wait(4)
      end
      check("the foe took its turn after the item (#379)", turns >= 1)
      check("end-of-turn effects ran (#379)", ends >= 1)
      check("and the FIGHT menu came back", battle.phase == "menu")
      U.shot(game, DIR .. "/bug379_back_on_menu.png")
    end
  end

  -- ======== control: a refused POTION is free =============================
  U.log("#379 control: a POTION on a full-HP mon is refused, turn NOT spent")
  lead.hp = lead.stats.hp
  local freeTurns = 0
  battle.executeAction = function(self, ...)
    freeTurns = freeTurns + 1
    return realAction(self, ...)
  end
  local held = game.save.inventory.POTION or 0
  local bag2 = openBagFrom(battle)
  if check("the bag reopened for the refusal", bag2 ~= nil) then
    chooseItem(bag2, "POTION")
    local picker = top()
    if isPicker(picker) then
      cursorTo(picker, 1)
      U.tap(game, "a")
      U.wait(12)
    end
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    local box = top()
    if check("the refusal printed", isBox(box)) then
      U.wait(40)
      check("...as \"It won't have any effect.\"",
            boxText(box):find("effect", 1, true) ~= nil)
      U.shot(game, DIR .. "/bug379_refused.png")
    end
    check("a refused item costs no turn (item_effects.asm:1241)", freeTurns == 0)
    check("and the POTION was not consumed",
          (game.save.inventory.POTION or 0) == held)
  end

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- re-arm and hand the pad over --------------------------------------
  for _ = 1, 200 do
    if battle.phase == "menu" and #battle.queue == 0 then break end
    U.tap(game, "a")
    U.wait(4)
  end
  lead.hp = 12
  local handoff = openBagFrom(battle)
  if handoff then
    for i, r in ipairs(handoff.items or {}) do
      if r.value == "POTION" then cursorTo(handoff, i) break end
    end
  end

  U.log("The ITEMS list is open mid-battle with the cursor on POTION. Press A,")
  U.log("pick CHARIZARD: the picker and the list both close, \"CHARIZARD's HP was")
  U.log("restored!\" prints with the heal chime, the HUD bar climbs, then PIDGEY")
  U.log("attacks before FIGHT comes back. #379 was no message and a free heal.")

  while true do
    coroutine.yield()
  end
end

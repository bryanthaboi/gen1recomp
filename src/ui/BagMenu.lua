-- The bag: lists inventory, uses items via ItemEffects.
-- opts.battle = BattleState when opened mid-battle (balls throwable,
-- using an item consumes the turn).

local ItemEffects = require("src.inventory.ItemEffects")
local ListMenu = require("src.ui.ListMenu")
local Runtime = require("src.mods.Runtime")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")

local BagMenu = {}

local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")

-- (engine/menus/start_sub_menus.asm:414-416, home/list_menu.asm:56-82)
local BAG_RETURN_WHITE = 19

-- acquisition order like wBagItems (Bag.order), not alphabetical
local function buildItems(game)
  local items = {}
  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items[id]
    -- PrintListMenuEntries skips the quantity for anything IsKeyItem_ owns:
    -- the KeyItemFlags bitfield plus the HMs (item_effects.asm:2616-2641)
    local unsellable = (def and def.keyItem) or id:find("^HM_") ~= nil
    table.insert(items, {
      value = id,
      label = def and def.name or id,
      count = (not unsellable) and game.save.inventory[id] or nil,
    })
  end
  -- the $ff terminator's row: CANCEL is selectable and exits like B
  -- (home/list_menu.asm:105-110, 523-528) #1685
  items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
  return items
end

local function consume(game, id, list)
  Bag.remove(game.save, id, 1)
  -- engine/items/inventory.asm:131-136
  if not game.save.inventory[id] then
    game.bagSavedMenuItem, game.bagListScrollOffset = 0, 0
    if list then list.index, list.scroll = 1, 0 end
  end
end

local function save_name(game)
  return game.save.player.name
end

local function showMessages(game, msgs, onDone, opts)
  if not msgs or #msgs == 0 then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, table.concat(msgs, "\f"), onDone, opts))
end

-- PrintItemUseTextAndRemoveItem: used-line TextBox carries Heal_Ailment, then
-- optional afterMessages (X Stat effect line) before onDone (#1635).
local function showUseMessages(game, msgs, onDone, extra)
  local opts = (extra and extra.useJingle)
    and TextBox.soundOpts(game, "Heal_Ailment") or nil
  local after = extra and extra.afterMessages
  if after and #after > 0 then
    showMessages(game, msgs, function()
      showMessages(game, after, onDone)
    end, opts)
  else
    showMessages(game, msgs, onDone, opts)
  end
end

-- run the use-flow for an item on a chosen target.  `picker` is the party
-- menu when it was opened with keepOpen (HP medicine only): it is still on
-- the stack, so every exit that prints has to close it afterwards.  For
-- every other item the picker popped itself first and closePicker's identity
-- check makes it a no-op (#252).
--
-- Every result string used to fall through to this one unconditional
-- function with no seam around it: a mod could not suppress a message,
-- delay it behind a screen of its own, or replace the outcome for one item
-- id.  The "item.use" hook wraps the whole dispatch (not a name per
-- result -- a mod deciding what a Poké Doll or a stone does needs the
-- SAME reach a vanilla `if result == ...` branch has, not a narrower one),
-- the way "battle.overlay" and "ui.party.submenu" already wrap a
-- screen's own default behavior elsewhere in src/ui.
local function vanillaUseOn(game, battle, id, target, list, moveIndex, picker)
  local result, payload, extra = ItemEffects.use(game.data, game.save, id, target,
                                                 battle, moveIndex, game.overworld)
  -- engine/menus/start_sub_menus.asm:410-416, home/list_menu.asm:56-82
  -- engine/items/item_effects.asm:1244
  local function closePicker()
    if not picker then return end
    picker:close()
    if battle then return end
    local Transition = require("src.render.Transition")
    game.stack:push(Transition.whiteFlash(game, BAG_RETURN_WHITE))
  end

  -- .useItem_closeMenu ends at CloseStartMenu, so the START menu kept open
  -- behind the bag comes down with it (start_sub_menus.asm:400-407) #1745
  local function closeBag()
    list:close()
    if list.closeStartMenu then list.closeStartMenu() end
  end

  -- field POKé FLUTE: play the tune, then the no-effect text
  if result == "flute_field" then
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload)
    return
  end

  if result == "flute_wake_pikachu" then
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload, function()
      game.overworld.pikachuPewterSleepScene = nil
    end)
    return
  end

  -- field POKé FLUTE next to a not-yet-beaten Snorlax: "had effect" text,
  -- then the woke-up/battle sequence (data/scripts/story.lua snorlaxWake)
  if result == "flute_wake" then
    closeBag()
    -- engine/items/item_effects.asm:1794 (#1880)
    local opts = TextBox.soundOpts(game, "Pokeflute",
      { auto = { wait = false, delay = 0, promptFirst = true } })
    showMessages(game, payload, function()
      local ow = game.overworld
      local mod = ow and require("data.scripts.init").get(extra.mapId)
      if ow and mod and mod.snorlaxWake then
        ow.runner:run(mod.snorlaxWake.script, { npc = extra.npc })
      end
    end, opts)
    return
  end

  if result == "consumed_escape" then -- Poké Doll
    consume(game, id, list)
    list:close()
    showUseMessages(game, payload, function()
      -- ItemUsePokeDoll sets wEscapedFromBattle and never touches
      -- wBattleResult, so a script that reads the result afterwards sees
      -- 0 -- "defeated". The ghost MAROWAK's script keys on exactly that
      -- (the Poke Doll trick); the flag lets it tell this escape from an
      -- ordinary RUN, which writes $2.
      battle.pokeDollEscape = true
      battle.result = "run"
      battle.afterQueue = "finish"
      battle.phase = "messages"
    end, extra)
    return
  end

  if result == "bicycle" then
    -- StartMenu_Item .useOrTossItem (engine/menus/start_sub_menus.asm):
    -- while BIT_ALWAYS_ON_BIKE of wStatusFlags6 is set -- the Cycling Road,
    -- armed by the forced-bike tiles and cleared by the Route 16/18 gate
    -- scripts -- the BICYCLE refuses with _CannotGetOffHereText and jumps
    -- back to ItemMenuLoop, so the bag stays open and no dismount happens
    -- (#513).  The gate sits ahead of UseItem, before ItemUseBicycle ever
    -- runs, which is why it precedes the mount/dismount here.
    if game.save.forcedBike then
      showMessages(game, { Strings("You can't get off\nhere.") })
      return
    end
    local ow = game.overworld
    local Music = require("src.core.Music")
    -- IsBikeRidingAllowed (home/overworld.asm): the tilesets of
    -- bike_riding_tilesets.asm, plus Route 23 / Indigo Plateau by
    -- map id.  Reads the extracted allowlist when present.
    local function bikeAllowed()
      if not ow then return false end
      local br = game.data.field.bikeRiding
        or { tilesets = { "OVERWORLD", "FOREST", "UNDERGROUND",
                          "SHIP_PORT", "CAVERN" },
             maps = { "ROUTE_23", "INDIGO_PLATEAU" } }
      for _, m in ipairs(br.maps or {}) do
        if ow.map.id == m then return true end
      end
      for _, t in ipairs(br.tilesets or {}) do
        if ow.map.def.tileset == t then return true end
      end
      return false
    end
    if game.save.onBike then
      closeBag()
      game.save.onBike = false
      Music.playMap(game.data, ow and ow.map.id, false)
      showMessages(game, { Strings("%s got off\nthe BICYCLE.", save_name(game)) })
    elseif bikeAllowed() then
      closeBag()
      game.save.onBike = true
      Music.playMap(game.data, ow.map.id, true)
      showMessages(game, { Strings("%s got on\nthe BICYCLE!", save_name(game)) })
    else
      -- NoCyclingAllowedHere -> ItemUseFailed zeroes the result byte and
      -- .useItem_closeMenu loops back (item_effects.asm:2305-2319)
      showMessages(game, { Strings("No cycling\nallowed here.") })
    end
    return
  end

  if result == "fish" then
    local ow = game.overworld
    local p = ow and ow.player
    if ow and p and ow:facingIsShoreOrWater() then
      closeBag()
      ow:goFishing(id)
      return
    end
    -- FishingInit's `ret c` -> ItemUseNotTime -> ItemUseFailed, so a rod
    -- away from water leaves the bag up (item_effects.asm:1893-1901)
    showMessages(game, { Strings("No good! It's not\neven near water.") })
    return
  end

  if result == "ball" then
    if not battle then
      showMessages(game, { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                              game.save.player.name) })
      return
    end
    consume(game, id, list)
    list:close()
    battle:throwBall(id)
    return
  end

  if result == "learn" or result == "learnkept" then
    local moveId = payload
    local mdef = game.data.moves[moveId]
    local function teach()
      -- PIKAHAPPY_USEDTMHM on a successful teach (item_effects.asm:2500)
      local function taught()
        require("src.world.PikachuFollower")
          .modifyHappiness(game.save, "USEDTMHM", target)
      end
      if #target.moves < 4 then
        table.insert(target.moves, { id = moveId, pp = mdef.pp })
        -- LearnedMove1Text: text_far, sound_get_item_1, text_promptbutton
        -- (learn_move.asm), so the jingle rides the box
        showMessages(game, { Strings("%s learned\n%s!", target.nickname or
          game.data.pokemon[target.species].name, mdef.name) }, closePicker,
          TextBox.soundOpts(game, "Get_Item1"))
        if result == "learn" then consume(game, id, list) end
        list.items = buildItems(game)
        list.index = math.min(list.index, math.max(1, #list.items))
        taught()
      else
        require("src.ui.Screens").push(game, "MoveLearnMenu", target, moveId,
          function(learned)
            if learned and result == "learn" then consume(game, id, list) end
            if learned then
              list.items = buildItems(game)
              list.index = math.min(list.index, math.max(1, #list.items))
            end
            if learned then taught() end
            closePicker()
          end)
      end
    end
    teach()
    return
  end

  -- the TOWN MAP screen (engine/menus/town_map.asm)
  if result == "townmap" then
    local ok = pcall(function()
      require("src.ui.Screens").push(game, "TownMap")
    end)
    if not ok then
      showMessages(game, { Strings("The TOWN MAP is\nunreadable here.") })
    end
    return
  end

  -- ITEMFINDER (engine/items/itemfinder.asm): responds if the current
  -- map still has an unfound hidden item
  if result == "itemfinder" then
    local ow = game.overworld
    local t = game.data.text
    if ow and ow:hasHiddenItemLeft() then
      showMessages(game, { t._ItemfinderFoundItemText
        or Strings("Yes! ITEMFINDER\nindicates there's\nan item nearby.") })
    else
      showMessages(game, { t._ItemfinderFoundNothingText
        or Strings("Nope! ITEMFINDER\nisn't responding.") })
    end
    return
  end

  -- POKé FLUTE in battle: not consumed, but uses the turn
  -- engine/items/item_effects.asm:1706 ItemUsePokeFlute .inBattle (#1938)
  if result == "flute" then
    list:close()
    local head, tail = { payload[1] }, {}
    for i = 2, #payload do tail[#tail + 1] = payload[i] end
    local alarm = battle.lowHealthAlarmActive and battle:lowHealthAlarmActive()
    local opts = nil
    if not alarm then
      opts = TextBox.soundOpts(game, "Pokeflute",
        { auto = { wait = false, delay = 0, promptFirst = true } })
    end
    showMessages(game, head, function()
      showMessages(game, tail, function() battle:itemUsed({}) end)
    end, opts)
    return
  end

  if result == "escape_rope" then
    -- ItemUseEscapeRope: only inside the dungeon tilesets
    -- (escape_rope_tilesets.asm), never in Agatha's room, and it sets
    -- BIT_ESCAPE_WARP so special_warps.asm warps to wLastBlackoutMap
    -- -- the last Pokémon Center town, same as Dig/Teleport (NOT the
    -- spot you entered the dungeon from)
    local ESCAPE_ROPE_TILESETS = { FOREST = true, CEMETERY = true,
                                   CAVERN = true, FACILITY = true,
                                   INTERIOR = true }
    local ow = game.overworld
    if ow and ESCAPE_ROPE_TILESETS[ow.map.def.tileset]
       and ow.map.id ~= "AGATHAS_ROOM" then
      closeBag()
      consume(game, id, list)
      -- LeaveMapAnim spin-up + SFX_TELEPORT_EXIT_1, a fade, then land OUTSIDE
      -- the last Pokémon Center town door like Fly (#196), via the shared
      -- departure helper -- the same path Dig/Teleport take from the party menu
      ow:beginTeleportOut()
    else
      showMessages(game, { Strings(
        "OAK: %s!\nThis isn't the\ntime to use that!",
        game.save.player.name) })
    end
    return
  end

  if result == "kept" then
    if battle then
        list:close()
        showMessages(game, payload, function()
            battle:itemUsed({})
        end)
    else
        showMessages(game, payload, closePicker)
    end
    return
  end

  if result == "consumed" then
    consume(game, id, list)
    -- refresh counts in the list
    for i, it in ipairs(list.items) do
      if it.value == id then
        local left = game.save.inventory[id]
        if left then it.count = left else table.remove(list.items, i) end
        break
      end
    end
    list.index = math.min(list.index, math.max(1, #list.items))
    if extra and extra.evolveTo then
      -- engine/menus/start_sub_menus.asm:408 .useItem_partyMenu
      local Evolution = require("src.pokemon.Evolution")
      -- item_effects.asm ItemUseEvoStone sets wForceEvolution before
      -- TryEvolvingMon, so a stone evolution's B press is read and
      -- discarded (EvolutionState.lua's cancelable check).  via = "ITEM"
      -- is what makes that non-cancelable here, same as the RARE_CANDY
      -- call below; without it the stone (already consumed above) could
      -- be cancelled out from under the player (#883)
      -- returns to StartMenu_Item (engine/items/item_effects.asm:772-793,
      -- engine/menus/start_sub_menus.asm:419) #2070
      Evolution.evolve(game, target, extra.evolveTo, closePicker, "ITEM")
      return
    end
    -- RARE CANDY: after the level text, the stat window, any level-up
    -- moves and a level evolution follow (item_effects.asm .useRareCandy
    -- runs PrintStatsBox, LearnMoveFromLevelUp and TryEvolvingMon)
    if extra and extra.leveledTo and target then
      -- ...but the bag stays open underneath it all: RARE_CANDY is in
      -- pokered's UsableItems_PartyMenu (data/items/use_party.asm), and
      -- .useItem_partyMenu jumps back to StartMenu_Item once UseItem
      -- returns, cursor still on the candy (start_sub_menus.asm) -- so
      -- mashing A burns through a stack of them (#796)
      -- RareCandyText carries sound_get_item_1
      -- (engine/menus/party_menu.asm:289-293)
      -- pokered engine/items/item_effects.asm:1392-1394
      if picker and picker.eraseCursors then picker:eraseCursors() end
      if picker and picker.setMessage then picker:setMessage(payload[1]) end
      showMessages(game, payload, function()
        local StatBox = require("src.battle.BattleState").StatBox
        local statBox
        -- ../pokered/engine/pokemon/evos_moves.asm:126-128
        local function dropStatBox()
          if statBox and game.stack:top() == statBox then game.stack:pop() end
          statBox = nil
        end
        statBox = StatBox.new(game, target, function()
          local Experience = require("src.battle.Experience")
          local def = game.data.pokemon[target.species]
          local moves = Experience.movesLearnedAt(def, extra.leveledTo)
          local i = 0
          local function nextStep()
            i = i + 1
            local moveId = moves[i]
            if not moveId then
              local Evolution = require("src.pokemon.Evolution")
              local evoTo, evo = Evolution.pendingFor(game, target,
                                                     { kind = "levelup" })
              -- the party menu stays up through TryEvolvingMon and only
              -- comes down at RemoveUsedItem (item_effects.asm:1392-1418)
              if evoTo then
                Evolution.evolve(game, target, evoTo, function()
                  dropStatBox()
                  closePicker()
                end, evo and evo.method)
              else
                dropStatBox()
                closePicker()
              end
              return
            end
            for _, mv in ipairs(target.moves) do
              if mv.id == moveId then return nextStep() end
            end
            local mdef = game.data.moves[moveId]
            if #target.moves < 4 then
              table.insert(target.moves, { id = moveId, pp = mdef.pp })
              local name = target.nickname or def.name
              showMessages(game, { Strings("%s learned\n%s!", name, mdef.name) },
                           nextStep, TextBox.soundOpts(game, "Get_Item1"))
            else
              require("src.ui.Screens").push(game, "MoveLearnMenu",
                                             target, moveId, nextStep)
            end
          end
          nextStep()
        end, true)
        game.stack:push(statBox)
      end, TextBox.soundOpts(game, "Get_Item1"))
      return
    end
    -- engine/items/item_effects.asm:1189
    if picker and picker.keepOpen and extra and extra.healedFrom and target then
      picker:animateTo(target, extra.healedFrom, function()
        -- engine/items/item_effects.asm:1232
        picker:eraseCursors()
        showMessages(game, payload, function()
          closePicker()
          if battle then
            list:close()
            battle:itemUsed({}, { barShown = true })
          end
        end)
      end)
      return
    end
    if battle then
      closePicker()
      list:close()
      showUseMessages(game, payload, function() battle:itemUsed({}) end, extra)
    else
      showUseMessages(game, payload, closePicker, extra)
    end
    return
  end

  -- .chooseMon loops on a refusal, so the TM/HM picker stays up for another
  -- pick (engine/items/item_effects.asm:2234, :2237) (#1686)
  local machineDef = game.data.items[id]
  if picker and picker.keepOpen and machineDef and machineDef.machine then
    showMessages(game, payload)
    return
  end
  -- .healingItemNoEffect prints over the still-drawn party menu too, so the
  -- refusal closes the picker the same way (#252)
  showMessages(game, payload, closePicker) -- failed
end

local function useOn(game, battle, id, target, list, moveIndex, picker)
  return Runtime.call("item.use", vanillaUseOn,
    game, battle, id, target, list, moveIndex, picker)
end

local function pickTargetAndUse(game, battle, id, list)
  -- pick a target from the party
  -- the ETHERs and PP UP open the move menu after picking a mon
  -- (ItemUsePPRestore / ItemUsePPUp); the ELIXERs hit every move
  local wantsMove = id == "ETHER" or id == "MAX_ETHER" or id == "PP_UP"
  local def = game.data.items[id]
  local opts = {
    pickOnly = true,
    -- USE_ITEM_PARTY_MENU / EVO_STONE_PARTY_MENU, not the trade and daycare
    -- NORMAL_PARTY_MENU (item_effects.asm:813, :768). #1610
    itemUse = true,
    battle = battle,
    -- HP medicine animates with the picker up (#252), RARE CANDY prints over
    -- the party menu (item_effects.asm:1392-1418); TM/HM stays up through
    -- `predef LearnMove` (item_effects.asm:2238) (#1686)
    -- engine/items/item_effects.asm:805 ItemUseMedicine, :1244 .done (#1946)
    -- engine/items/item_effects.asm:1959
    keepOpen = ItemEffects.healsHP(id) or wantsMove
      or ((not battle)
          and (ItemEffects.keepsPartyMenuOpen(id) or (def and def.machine ~= nil))),
    onSwitch = function(mon, picker)
      if not wantsMove then
        useOn(game, battle, id, mon, list, nil, picker)
        return
      end
      -- engine/items/item_effects.asm:1973
      local prompt = (id == "PP_UP")
        and romText(game.data, "_RaisePPWhichTechniqueText",
                    "Raise PP of which\ntechnique?")
        or romText(game.data, "_RestorePPWhichTechniqueText",
                   "Restore PP of\nwhich technique?")
      require("src.ui.Screens").push(game, "MoveSelectMenu", mon, prompt,
        function(moveIndex)
          useOn(game, battle, id, mon, list, moveIndex, picker)
        end)
    end,
  }
  -- TM/HM: open the party menu in Gen 1's TM/HM display mode so each mon
  -- shows ABLE / NOT ABLE from its learnset and the prompt reads "Use TM on
  -- which POKeMON?" (engine/items/item_effects.asm ItemUseTMHM ->
  -- party_menu.asm TM/HM type). #210  Stones get the same ABLE / NOT ABLE
  -- column: ItemUseEvoStone sets EVO_STONE_PARTY_MENU (party_menu.asm:114).
  if def and def.machine then
    opts.tmhm = { move = def.machine.move, kind = def.machine.kind }
  elseif ItemEffects.isStone(id) then
    opts.evoStone = id
  end
  require("src.ui.Screens").push(game, "PartyMenu", opts)
end

local function useItem(game, battle, id, list)
  local def = game.data.items[id]
  -- ItemUseTMHM checks wIsInBattle before BootedUpTMText
  if battle and def and def.machine then
    local _, payload = ItemEffects.use(game.data, game.save, id, nil, battle)
    showMessages(game, payload)
    return
  end
  if ItemEffects.needsTarget(id, def, game.data) and not ItemEffects.isBall(id) then
    -- TMs/HMs boot up and announce their move before the target picker
    -- (ItemUseTMHM: BootedUpTMText / BootedUpHMText + TeachMachineMoveText)
    if def and def.machine then
      local moveDef = game.data.moves[def.machine.move]
      local moveName = moveDef and moveDef.name or def.machine.move
      local booted = def.machine.kind == "HM"
        and romText(game.data, "_BootedUpHMText", "Booted up an HM!")
        or romText(game.data, "_BootedUpTMText", "Booted up a TM!")
      -- engine/items/item_effects.asm:2177 (#1686)
      showMessages(game, { booted,
        romText(game.data, "_TeachMachineMoveText",
          "It contained\n%s!\fTeach %s\nto a POKéMON?", moveName, moveName) },
        nil, { choice = function(yes)
          if yes then pickTargetAndUse(game, battle, id, list) end
        end })
      return
    end
    pickTargetAndUse(game, battle, id, list)
  else
    useOn(game, battle, id, nil, list)
  end
end

function BagMenu.new(game, opts)
  opts = opts or {}
  local battle = opts.battle
  local list
  list = ListMenu.new(game, Strings.source("ITEMS"), buildItems(game), {
    kind = "bag",
    -- StartMenu_Item zeroes wPrintItemPrices and draws no money box: the
    -- LIST_MENU_BOX floats over the map (engine/menus/start_sub_menus.asm)
    itemBox = true,
    -- B returns to the start menu when the bag was opened from it
    onCancel = opts.onCancel,
    -- SELECT reorders items like the original bag (swap_items.asm)
    onSelectKey = function(item, l)
      -- attempts to swap the CANCEL row are ignored (swap_items.asm:19-22)
      if not item or item.cancel then return end
      if not l.swapIndex then
        l.swapIndex = l.index
        return
      end
      local order = Bag.order(game.save)
      order[l.swapIndex], order[l.index] = order[l.index], order[l.swapIndex]
      l.swapIndex = nil
      require("src.core.Sound").play(game.data, "Swap")
      l.items = buildItems(game)
    end,
    onChoose = function(item)
      -- A on CANCEL leaves the list exactly like B (home/list_menu.asm:105-110)
      if item and item.cancel then
        list:close()
        if opts.onCancel then opts.onCancel() end
        return
      end
      local id = item.value
      local def = game.data.items[id]
      if list.swapIndex then -- A also completes a pending swap
        local order = Bag.order(game.save)
        order[list.swapIndex], order[list.index] = order[list.index], order[list.swapIndex]
        list.swapIndex = nil
        require("src.core.Sound").play(game.data, "Swap")
        list.items = buildItems(game)
        return
      end
      if battle then -- no tossing mid-battle
        useItem(game, battle, id, list)
        return
      end
      -- the BICYCLE never gets the option box: StartMenu_Item jumps straight
      -- to .useOrTossItem (start_sub_menus.asm:340-342) #1705
      if id == "BICYCLE" then
        useItem(game, battle, id, list)
        return
      end
      -- USE / TOSS submenu (the original's item options).
      -- data/text_boxes.asm USE_TOSS_MENU_TEMPLATE: box (13,10)-(19,14),
      -- text at (15,11); start_sub_menus.asm then sets wTopMenuItemY/X to
      -- 11/14 for the cursor.  Menu's own geometry reproduces all of that
      -- from the box alone, so this needs opts rather than a change to the
      -- shared Menu.  The old 12/10/8/6 box was a column too wide and a row
      -- too tall, which left the labels stranded near its top edge (#284).
      -- (engine/menus/start_sub_menus.asm:330-337; home/window.asm:193-206)
      list.hollowIndex = list.index
      local Menu = require("src.ui.Menu")
      game.stack:push(Menu.new(game, {
        { label = Strings("USE"), onSelect = function()
            useItem(game, battle, id, list)
          end },
        { label = Strings("TOSS"), onSelect = function()
            -- KeyItemFlags + HMs decide tossability (not price:
            -- MOON STONE is price 0 but tossable)
            if not def or def.keyItem or id:find("^HM_") then
              showMessages(game, { Strings("That's too impor-\ntant to toss!") })
              return
            end
            local QuantityBox = require("src.ui.QuantityBox")
            game.stack:push(QuantityBox.new(game, {
              max = game.save.inventory[id] or 1,
              onDone = function(qty)
                if not qty then return end
                local ChoiceBox = require("src.ui.ChoiceBox")
                game.stack:push(ChoiceBox.new(game, function(yes)
                  if not yes then return end
                  Bag.remove(game.save, id, qty)
                  list.items = buildItems(game)
                  list.index = math.min(list.index, math.max(1, #list.items))
                  showMessages(game, { Strings("Threw away\n%s.", def and def.name or id) })
                end))
              end,
            }))
          end },
      }, { tx = 13, ty = 10, tw = 7, th = 5 }))
    end,
  })
  -- reopen on the saved cursor: engine/battle/core.asm:2230-2234 and
  -- engine/menus/start_sub_menus.asm:319-323 #1732
  local n, rows = #list.items, list.cursorRows or list.rows
  if n > 0 then
    local saved = game.bagListScrollOffset or 0
    local index = math.min(saved + (game.bagSavedMenuItem or 0) + 1, n)
    local scroll = math.min(saved, index - 1, math.max(0, n - rows))
    list.index, list.scroll = index, math.max(0, scroll, index - rows)
  end
  local baseUpdate = list.update
  list.update = function(self, dt)
    baseUpdate(self, dt)
    game.bagListScrollOffset = self.scroll
    game.bagSavedMenuItem = self.index - self.scroll - 1
  end
  list.closeStartMenu = opts.onClose
  -- the item box overlaps the kept-open START menu box, so neither docks to
  -- a screen edge on its own (start_sub_menus.asm:302-329) #1745
  list.holdsUIAnchors = true
  return list
end

return BagMenu

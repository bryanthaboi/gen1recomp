-- Ear check for the PC, bump, door/stairs and battle menu SFX (#960, #961, #1044, #1045).
--   POKEPORT_DRIVER=tests/drivers/menu_sfx_bug960_bug961_bug1044_bug1045_test.lua POKEPORT_IDENTITY=sfx960 POKEPORT_TOUCH=0 POKEPORT_VERSION=red SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BattleState = require("src.battle.BattleState")
  local Boxes = require("src.pokemon.Boxes")
  local Menu = require("src.ui.Menu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")
  local Strings = require("src.core.Strings")
  local Timing = require("src.core.Timing")

  local FADE = Timing.WARP_FADE_OUT

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- every cue this run makes, forwarded so playback is untouched; the frame
  local cues = {}
  local realPlay = Sound.play
  Sound.play = function(data, name)
    cues[#cues + 1] = { name = name, frame = U.frame() }
    return realPlay(data, name)
  end
  local function since(mark)
    local names = {}
    for i = mark + 1, #cues do names[#names + 1] = cues[i].name end
    return #names > 0 and table.concat(names, ", ") or "nothing"
  end
  local function heard(mark, want)
    for i = mark + 1, #cues do
      if cues[i].name == want then return cues[i] end
    end
    return nil
  end
  local function countOf(mark, want)
    local n = 0
    for i = mark + 1, #cues do if cues[i].name == want then n = n + 1 end end
    return n
  end

  -- ---- what the ear cannot check -----------------------------------------
  local opts = game.save.options or {}
  local sfxVol, musicVol = opts.sfxVol or 0, opts.musicVol or 0
  if sfxVol == 0 then
    U.log("FAIL SFX volume is 0. Every line below is about a sound that is or")
    U.log("     is not there, and at 0 none of them are. Set SFX to 7 in OPTION")
    U.log("     and start over, or this run proves nothing at all.")
  end
  check(("sfx volume %d/7, music volume %d/7"):format(sfxVol, musicVol),
        sfxVol > 0)

  -- an unresolved key is silent in exactly the way these bugs were
  local sfx = (game.data.audio or {}).sfx or {}
  for _, key in ipairs({ "Turn_On_PC", "Turn_Off_PC", "Enter_PC", "Collision",
                         "Save", "Go_Inside", "Go_Outside", "Press_AB" }) do
    check("sfx " .. key .. " is in the generated audio", sfx[key] ~= nil)
  end

  -- positions come from data/events/hidden_events.asm and data/maps/objects/*.asm
  local extras = game.data.field.hiddenExtras or {}
  local pcTiles = extras.pcTiles or {}
  local bedroomPC = (pcTiles.REDS_HOUSE_2F or {})[1]
  local centerPC = (pcTiles.VIRIDIAN_POKECENTER or {})[1]
  check("REDS_HOUSE_2F carries the OpenRedsPC tile", bedroomPC ~= nil)
  check("VIRIDIAN_POKECENTER carries a PC tile", centerPC ~= nil)

  local function warpTo(mapId, destMap)
    for _, w in ipairs((game.data.maps[mapId] or {}).warps or {}) do
      if w.destMap == destMap then return w end
    end
    return nil
  end
  local houseDoor = warpTo("PALLET_TOWN", "REDS_HOUSE_1F")
  local houseExit = warpTo("REDS_HOUSE_1F", "LAST_MAP")
  local houseStairs = warpTo("REDS_HOUSE_1F", "REDS_HOUSE_2F")
  local centerDoor = warpTo("VIRIDIAN_CITY", "VIRIDIAN_POKECENTER")
  check("PALLET_TOWN has the door into REDS_HOUSE_1F", houseDoor ~= nil)
  check("REDS_HOUSE_1F has an exit mat and the stairs up",
        houseExit ~= nil and houseStairs ~= nil)
  check("VIRIDIAN_CITY has the door into its POKéMON CENTER", centerDoor ~= nil)

  -- ---- helpers ------------------------------------------------------------
  local DIRS = { up = { 0, -1 }, down = { 0, 1 },
                 left = { -1, 0 }, right = { 1, 0 } }
  local ORDER = { "down", "up", "left", "right" }

  local function pressStep(dir)
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    U.wait(1)
  end

  local function stand(mapId, x, y, facing)
    U.teleport(game, mapId, x, y, facing)
    U.wait(15)
    return game.overworld
  end

  -- the cell you stand on to face (cx, cy) from `dir`, i.e. one step back
  local function cellBehind(cx, cy, dir)
    local d = DIRS[dir]
    return cx - d[1], cy - d[2]
  end

  -- first walkable free neighbour of (cx, cy), plus the facing that looks at
  local function approach(ow, cx, cy)
    for _, dir in ipairs(ORDER) do
      local sx, sy = cellBehind(cx, cy, dir)
      if ow.map:isWalkableCell(sx, sy) and not ow:npcAtCell(sx, sy) then
        return sx, sy, dir
      end
    end
  end

  -- any free walkable cell on the map with a solid one next to it, so the
  local function findWall(ow)
    local map = ow.map
    for cy = 0, map.heightCells - 1 do
      for cx = 0, map.widthCells - 1 do
        if map:isWalkableCell(cx, cy) and not map:warpAtCell(cx, cy)
           and not ow:npcAtCell(cx, cy) then
          for _, d in ipairs(ORDER) do
            local dd = DIRS[d]
            if not map:isWalkableCell(cx + dd[1], cy + dd[2]) then
              return cx, cy, d
            end
          end
        end
      end
    end
  end

  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
  end

  -- PlayMapChangeSound (home/overworld.asm:690) plays before GBFadeOutToBlack,
  local function takeDoor(dir, want, label)
    local mark = #cues
    local from = game.overworld.map.id
    local cue, switched
    for _ = 1, 300 do
      if cue or switched then
        game.input.state[dir] = false
        U.wait(1)
      else
        pressStep(dir)
      end
      cue = cue or heard(mark, want)
      local ow = game.overworld
      if not switched and ow and ow.map.id ~= from then switched = U.frame() end
      if cue and switched then break end
    end
    game.input.state[dir] = false
    U.wait(50) -- PlayerStepOutFromDoor walks off the mat before anything else
    if not (cue and switched) then
      check(("%s: %s played and the map changed"):format(label, want), false)
      U.log("   cues on the way through:", since(mark))
      return
    end
    check(("%s: %s fired %d frames before the map switched (the fade is %d)")
            :format(label, want, switched - cue.frame, FADE),
          switched - cue.frame >= FADE - 8)
  end

  -- CollisionCheckOnLand (home/overworld.asm): a sprite in the way takes the
  local function bumpInto(dir, label)
    local mark = #cues
    for _ = 1, 10 do pressStep(dir) end
    game.input.state[dir] = false
    U.wait(24) -- past the 16-frame bumpCooldown, so the next bump is its own
    check(label .. " rings Collision", heard(mark, "Collision") ~= nil)
  end

  local function topIs(class)
    local top = game.stack:top()
    return top ~= nil and getmetatable(top) == class
  end
  local function rowIndex(menu, label)
    for i, item in ipairs(menu.items or {}) do
      if item.label == label then return i end
    end
  end
  -- rows come and go with save state and the ui.pc.items hook, so pick each
  local function choose(menu, label)
    local i = rowIndex(menu, label)
    if not i then
      check("the menu has a " .. label .. " row", false)
      return false
    end
    menu.index = i
    menu:clampScroll()
    U.wait(2)
    U.tap(game, "a")
    U.wait(26)
    return true
  end
  local function mash(cond, tries)
    for _ = 1, tries or 40 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    return cond()
  end

  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 20) }
  game.save.party[1].moves = {
    { id = "TACKLE", pp = 35, maxPP = 35 },
    { id = "VINE_WHIP", pp = 10, maxPP = 10 },
  }
  Boxes.ensure(game.save)
  game.save.currentBox = 1

  -- ---- the door into the house, from outside (#961) -----------------------
  if houseDoor then
    local sx, sy = cellBehind(houseDoor.x, houseDoor.y, "up")
    stand("PALLET_TOWN", sx, sy, "up")
    takeDoor("up", "Go_Inside", "walking into RED's house")
  end

  -- walking into MOM, and into a wall (#960); teleport is only a fallback
  local ow = game.overworld
  if ow.map.id ~= "REDS_HOUSE_1F" and houseExit then
    ow = stand("REDS_HOUSE_1F", houseExit.x, houseExit.y, "up")
  end
  local mom = npcNamed(ow, "REDSHOUSE1F_MOM")
  check("MOM is loaded on REDS_HOUSE_1F", mom ~= nil)
  if mom then
    local sx, sy, dir = approach(ow, mom.cellX, mom.cellY)
    if sx then
      ow = stand("REDS_HOUSE_1F", sx, sy, dir)
      -- the teleport rebuilt the npc list, so pin her on the state we bump
      local pinned = npcNamed(ow, "REDSHOUSE1F_MOM")
      if pinned then pinned.frozen = true end
      U.shot(game, DIR .. "/bug960_mom.png")
      bumpInto(dir, "walking into MOM")
    else
      check("MOM has a free cell to be walked into from", false)
    end
    -- the control: a wall bump was audible before #960 too, so silence here
    local wx, wy, wdir = findWall(game.overworld)
    if wdir then
      ow = stand("REDS_HOUSE_1F", wx, wy, wdir)
      bumpInto(wdir, "walking into the wall to the " .. wdir)
    else
      check("REDS_HOUSE_1F has a wall to bump into", false)
    end
  end

  -- ---- the stairs up (#961) -----------------------------------------------
  if houseStairs then
    local sx, sy = cellBehind(houseStairs.x, houseStairs.y, "up")
    stand("REDS_HOUSE_1F", sx, sy, "up")
    -- home/overworld.asm:689-703
    takeDoor("up", "Go_Outside", "taking the stairs up")
  end

  -- ---- the bedroom PC (#960) ---------------------------------------------
  if bedroomPC then
    -- OpenRedsPC's hidden_event is gated on SPRITE_FACING_UP, so the cell
    local sx, sy = cellBehind(bedroomPC.x, bedroomPC.y, "up")
    ow = stand("REDS_HOUSE_2F", sx, sy, "up")
    check("the cell below the bedroom PC is walkable",
          ow.map:isWalkableCell(sx, sy))
    local mark = #cues
    U.tap(game, "a")
    U.wait(26)
    check("A on the bedroom PC opens a menu", topIs(Menu))
    check("...and turns it on with Turn_On_PC", heard(mark, "Turn_On_PC") ~= nil)
    U.shot(game, DIR .. "/bug960_bedroom_pc.png")
    if topIs(Menu) then
      mark = #cues
      choose(game.stack:top(), Strings("LOG OFF"))
      check("LOG OFF on the bedroom PC rings Turn_Off_PC (#960)",
            heard(mark, "Turn_Off_PC") ~= nil)
      U.log("   cues:", since(mark))
      check("...and the PC closed", game.stack:top() == game.overworld)
    end
    -- B out of the same menu is ExitPlayerPC's other entry and rings it too
    U.tap(game, "a")
    U.wait(26)
    if topIs(Menu) then
      local mark2 = #cues
      U.tap(game, "b")
      U.wait(26)
      check("backing out of the bedroom PC with B rings it as well",
            heard(mark2, "Turn_Off_PC") ~= nil)
    end
  end

  -- ---- back out of the house, to the street (#961) ------------------------
  if houseExit then
    local sx, sy = cellBehind(houseExit.x, houseExit.y, "down")
    ow = stand("REDS_HOUSE_1F", sx, sy, "down")
    if not ow.map:isWalkableCell(sx, sy) then
      U.log(("(%d, %d) is blocked; using the other half of the mat")
              :format(sx, sy))
      ow = stand("REDS_HOUSE_1F", sx + 1, sy, "down")
    end
    takeDoor("down", "Go_Outside", "stepping out onto the street")
  end

  -- ---- into the POKéMON CENTER, for the PC main menu -----------------------
  if centerDoor then
    local sx, sy = cellBehind(centerDoor.x, centerDoor.y, "up")
    stand("VIRIDIAN_CITY", sx, sy, "up")
    takeDoor("up", "Go_Inside", "walking into the POKéMON CENTER")
  end

  -- ---- the PC main menu: Enter_PC, and the silence under it (#960) --------
  if centerPC then
    local sx, sy = cellBehind(centerPC.x, centerPC.y, "up")
    ow = stand("VIRIDIAN_POKECENTER", sx, sy, "up")
    for _, n in ipairs(ow.npcs or {}) do n.frozen = true end -- the GENTLEMAN walks
    local mark = #cues
    U.tap(game, "a")
    U.wait(26)
    check("A on the Center PC opens the PC main menu", topIs(Menu))
    check("...with Turn_On_PC", heard(mark, "Turn_On_PC") ~= nil)

    local mine = (game.save.player.name or "RED") .. "'s PC"
    if topIs(Menu) then
      mark = #cues
      choose(game.stack:top(), mine)
      check(mine .. " rings Enter_PC (#960)", heard(mark, "Enter_PC") ~= nil)
      check("...and the item PC opened", topIs(Menu))
      -- BIT_USING_GENERIC_PC: reached this way, ExitPlayerPC is silent and
      mark = #cues
      U.tap(game, "b")
      U.wait(26)
      check("backing out of it again is silent, as the ROM is",
            heard(mark, "Turn_Off_PC") == nil)
      U.log("   cues:", since(mark))
    end

    -- ---- CHANGE BOX (#1044) ----------------------------------------------
    -- the box PC reads SOMEONE'S PC until EVENT_MET_BILL (pokemon_pc.asm)
    local flags = game.save.flags or {}
    local boxPC = (flags.EVENT_MET_BILL or flags.EVENT_GOT_SS_TICKET)
                  and "BILL'S PC" or Strings("SOMEONE'S PC")
    if topIs(Menu) then
      mark = #cues
      choose(game.stack:top(), boxPC)
      check(boxPC .. " rings Enter_PC too", heard(mark, "Enter_PC") ~= nil)
      check("...and the box menu opened", topIs(Menu))
    end
    if topIs(Menu) and rowIndex(game.stack:top(), Strings("CHANGE BOX")) then
      choose(game.stack:top(), Strings("CHANGE BOX"))
      U.shot(game, DIR .. "/bug1044_change_box.png")
      local before = game.save.currentBox
      U.tap(game, "down") -- BOX 1 is the current one, so move off it
      U.wait(8)
      mark = #cues
      -- A picks the box, then the "data will be saved" prompt and its YES
      U.tap(game, "a")
      U.wait(20)
      mash(function() return game.save.currentBox ~= before end, 40)
      U.wait(60) -- the 15-frame answer hold, then the write
      check(("CHANGE BOX switched box %s -> %s")
              :format(tostring(before), tostring(game.save.currentBox)),
            game.save.currentBox ~= before)
      check("...and rang the SAVE jingle (#1044)", heard(mark, "Save") ~= nil)
      U.log("   cues:", since(mark))
    end

    -- ---- LOG OFF from the main menu --------------------------------------
    for _ = 1, 6 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(20)
    end
    U.tap(game, "a")
    U.wait(26)
    if topIs(Menu) and rowIndex(game.stack:top(), Strings("LOG OFF")) then
      local mark2 = #cues
      choose(game.stack:top(), Strings("LOG OFF"))
      check("LOG OFF on the PC main menu rings Turn_Off_PC",
            heard(mark2, "Turn_Off_PC") ~= nil)
    end
    for _ = 1, 8 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(20)
    end
  end

  -- the battle menu click (#1045) already landed in HEAD 12c2677; confirmation only
  ow = stand("ROUTE_1", 5, 5, "down")
  if not ow.map:isWalkableCell(5, 5) then
    local fx, fy
    for cy = 0, ow.map.heightCells - 1 do
      for cx = 0, ow.map.widthCells - 1 do
        if ow.map:isWalkableCell(cx, cy) then fx, fy = cx, cy break end
      end
      if fx then break end
    end
    if fx then ow = stand("ROUTE_1", fx, fy, "down") end
  end
  local battle = BattleState.newWild(game, "SNORLAX", 50)
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  -- SPLASH so the foe's turn can never end the run under the menu presses
  battle.enemy.mon.moves = { { id = "SPLASH", pp = 40, maxPP = 40 } }
  battle.enemy.curMoves = battle.enemy.mon.moves
  ow:pushBattle(battle)
  U.wait(220) -- the send-out intro runs before the menu is reachable
  mash(function() return battle.phase == "menu" end, 60)
  check("the wild SNORLAX battle reached its FIGHT menu",
        battle.phase == "menu")

  -- one press, then long enough for the click to be its own sound
  local function click(btn, label, want)
    local mark = #cues
    U.tap(game, btn)
    U.wait(28)
    local n = countOf(mark, "Press_AB")
    check(("%s: %s gave %d click%s, expected %d")
            :format(label, btn:upper(), n, n == 1 and "" or "s", want),
          n == want)
  end
  if battle.phase == "menu" then
    click("a", "A on FIGHT (#1045a)", 1)
    check("...and the move list opened", battle.phase == "moveSelect")
    U.shot(game, DIR .. "/bug1045_move_list.png")
    click("b", "B out of the move list (#1045c)", 1)
    check("...and the FIGHT menu came back", battle.phase == "menu")
    click("a", "A on FIGHT again", 1)
    click("a", "A on a move (#1045b)", 1)
    mash(function() return battle.phase == "menu" end, 120)
    if battle.phase == "menu" then
      battle.menuIndex = 4 -- RUN shares the FIGHT/PKMN/ITEM call site
      U.wait(4)
      click("a", "A on RUN", 1)
    end
  end
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- over to you --------------------------------------------------------
  if centerPC then
    local sx, sy = cellBehind(centerPC.x, centerPC.y, "up")
    ow = stand("VIRIDIAN_POKECENTER", sx, sy, "up")
    for _, n in ipairs(ow.npcs or {}) do n.frozen = true end
  end
  U.log("Everything above has been pressed once already; you are parked at the")
  U.log("Viridian POKéMON CENTER PC to do it again by ear.")
  U.log("A opens the PC main menu. RED's PC clicks in on the two-note ENTER PC")
  U.log("chirp and LOG OFF closes with the descending power-down. B out of RED's")
  U.log("PC is silent on purpose; a power-down there is the near miss, not a pass.")
  U.log("SOMEONE'S PC, CHANGE BOX, any other box, YES: the SAVE jingle rings")
  U.log("after the box has changed, the same jingle the SAVE menu plays. A")
  U.log("jingle before the switch, or none at all, is #1044 back.")
  U.log("The bedroom PC upstairs at home is the other half of #960: it beeps on,")
  U.log("and LOG OFF or B rings the power-down there. That one is not silent.")
  U.log("The COOLTRAINER at (4,3) and the NURSE at (3,1) are pinned; walk into")
  U.log("either and it thuds like a wall. Walking into a wall is the control --")
  U.log("it always thudded, so a silent wall means the device, not the fix.")
  U.log(("Walk out over the exit mat at the bottom of the room: the door sound")
        .. (" starts as the screen begins to darken, %d frames ahead of")
             :format(FADE))
  U.log("Viridian City. One that lands on the new map, or after it, is #961.")
  U.log("In any battle, A on FIGHT/PKMN/ITEM/RUN, A on a move and B out of the")
  U.log("move list all click. Silence on any of the three is #1045.")
  U.log("Shots: " .. DIR .. "/bug960_*.png, bug1044_*.png, bug1045_*.png")

  -- keeps naming cues with their frame after the hand-off, so a door sound
  local reported = #cues
  while true do
    if #cues > reported then
      for i = reported + 1, #cues do
        U.log("cue", cues[i].name, "frame", cues[i].frame)
      end
      reported = #cues
    end
    coroutine.yield()
  end
end

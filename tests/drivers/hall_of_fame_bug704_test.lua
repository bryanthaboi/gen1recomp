-- Driver: the Hall of Fame induction, end to end (#704, #697, #637).
-- Runs the tail of ChampionsRoomRivalDefeatedScript (scripts/ChampionsRoom.asm)
-- from just after the rival battle, so the walk out after Oak, the LEVEL/TYPE
-- box (engine/movie/hall_of_fame.asm HoFDisplayMonInfo) and the pic's true
-- color exemption all play at real speed.  Do NOT add POKEPORT_SPEED: it
-- scales the logic clock only, and the cries here run off the audio clock.
--   POKEPORT_DRIVER=tests/drivers/hall_of_fame_bug704_test.lua \
--     POKEPORT_IDENTITY=hof704 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Sprites = require("src.pokemon.Sprites")
  local PaletteFX = require("src.render.PaletteFX")
  local Renderer = require("src.render.Renderer")
  local BattleState = require("src.battle.BattleState")
  local SummaryMenu = require("src.ui.SummaryMenu")
  local Font = require("src.render.Font")
  local HallOfFame = require("src.ui.HallOfFame")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- HoFLoadMonPlayerPicTileIDs rests the front pic at hlcoord 12,5
  local PIC_X, PIC_Y = 96, 40

  -- ---------------------------------------------------------------
  -- setup
  -- ---------------------------------------------------------------
  local options = game.save.options
  options.battleLayout = "wide" -- #637 is reported with BATTLE LAYOUT = WIDE
  -- CHARIZARD is dual type (FIRE/FLYING) so TYPE2/ is drawn; SNORLAX is
  -- single type so the run also shows the row EraseType2Text blanks.
  local SPECIES = { "CHARIZARD", "SNORLAX", "PIKACHU" }
  game.save.party = {}
  for i, name in ipairs(SPECIES) do
    game.save.party[i] = Pokemon.new(game.data, name, 100 - (i - 1) * 27)
  end
  game.save.player.name = "BRYAN"
  game.save.money = 54321
  game.save.playTime = 9 * 3600 + 42 * 60
  -- DisplayDexRating tiers off owned; give it something past the first row
  game.save.pokedex = game.save.pokedex or { seen = {}, owned = {} }
  for i = 1, 60 do
    game.save.pokedex.seen[i] = true
    if i <= 47 then game.save.pokedex.owned[i] = true end
  end

  -- A stock ROM import carries no full-color art, so def.trueColor is false
  -- for every species and the #637 exemption never engages.  Flip it on for
  -- this party the way an art-pack mod does (mods/examples/example_shiny_
  -- palette patches the same field), or there is nothing to look at.
  for _, name in ipairs(SPECIES) do
    local def = game.data.pokemon[name]
    if def then def.trueColor = true end
  end

  if (options.sfxVol or 0) == 0 then
    U.log("WARNING sfxVol is 0: the cries are muted, so the run is silent")
  end
  if (options.musicVol or 0) == 0 then
    U.log("WARNING musicVol is 0: Music_HallOfFame will not be audible")
  end
  U.log("colors option is", tostring(options.colors),
        "-- the pic exemption only shows while the palette shader is on")

  -- ---------------------------------------------------------------
  -- machine checks: everything an eye cannot tell from the bug
  -- ---------------------------------------------------------------
  for _, name in ipairs(SPECIES) do
    local path, trueColor = Sprites.path(game.data, name, "front",
                                         { kind = "hof" })
    check(name .. " has a front pic for the hof screen",
          type(path) == "string" and path ~= "")
    check(name .. " reports the full-color flag through Sprites.path",
          trueColor == true)
  end

  -- #704: the walk-out rows.  Read the live registry rather than the module,
  -- so a mod's map_scripts contribution is what gets inspected.
  local mapScripts = require("data.scripts.init")
  local champ = mapScripts.get("CHAMPIONS_ROOM")
  local rows = champ and champ.talk and champ.talk.TEXT_CHAMPIONSROOM_RIVAL
  check("CHAMPIONS_ROOM keeps its rival script", type(rows) == "table")
  rows = rows or {}

  local iWalk, iWarp
  for i, row in ipairs(rows) do
    if row[1] == "move_player" and row[2] == "up" and not iWarp then
      iWalk = i
    elseif row[1] == "warp" and row[2] == "HALL_OF_FAME" then
      iWarp = iWarp or i
    end
  end
  check("the script walks the player up before it warps (#704)",
        iWalk ~= nil and iWarp ~= nil and iWalk < iWarp)

  -- #637, the other half: a classic state drawn inside a wide battle reports
  -- its rects in 160px coordinates, and Game:draw shifts them with the
  -- translate it centred the state under.
  check("PaletteFX takes a mark offset", type(PaletteFX.setMarkOffset) == "function")
  if type(PaletteFX.setMarkOffset) == "function" then
    PaletteFX.setPass("ui")
    PaletteFX.setMarkOffset(72) -- (304 - 160) / 2
    PaletteFX.markTrueColor(8, 24, 56, 56)
    local probe = PaletteFX.trueColorRects("ui")
    local last = probe[#probe]
    check("a ui mark moves with the centring translate",
          last ~= nil and last.x == 80)
    PaletteFX.setMarkOffset(0)
    PaletteFX.clearTrueColor()
  end

  -- ---------------------------------------------------------------
  -- the wide-battle STATS screen (#637, second screen in the issue)
  -- ---------------------------------------------------------------
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(30)
  local battle = BattleState.newWild(game, "PIDGEY", 3, { onFinish = function() end })
  game.overworld:pushBattle(battle)
  U.wait(300)
  check("the wide battle took the 304x144 surface",
        Renderer.uiWidth == 304 and Renderer.uiHeight == 144)
  game.stack:push(SummaryMenu.new(game, game.save.party[1]))
  U.wait(8)
  check("stats screenshot", U.shot(game, DIR .. "/hof637_wide_stats.png"))
  local statRect
  for _, r in ipairs(PaletteFX.trueColorRects("ui")) do
    if r.colors == false and r.w > 32 then statRect = r end
  end
  -- StatusScreen draws the pic at x = 8; centred in the wide surface that is 80
  check("the STATS pic is exempted at its centred x (#637)",
        statRect ~= nil and statRect.x == 80)
  game.stack:pop() -- summary
  game.stack:pop() -- battle
  U.wait(20)
  check("the Game Boy surface came back",
        Renderer.uiWidth == 160 and Renderer.uiHeight == 144)

  -- ---------------------------------------------------------------
  -- the champion's room walk-out
  -- ---------------------------------------------------------------
  -- pokered data/maps/objects/ChampionsRoom.asm: the rival stands at (4,2),
  -- both HALL_OF_FAME warps are on row 0, and ChampionsRoomPlayerEntersScript
  -- leaves the player at (4,3).  Start there, facing the rival.
  local STAND = { x = 4, y = 3 }
  U.teleport(game, "CHAMPIONS_ROOM", STAND.x, STAND.y, "up")
  U.wait(20)
  local ow = game.overworld
  local rival
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == "CHAMPIONSROOM_RIVAL" then rival = npc end
  end
  check("the rival object is on the map", rival ~= nil)
  if ow.player.cellY ~= STAND.y then
    -- a map edit moved the entrance walk's landing cell: stand anywhere the
    -- warp row is still straight above, rather than face a wall
    U.log("player did not land on (4,3); it is at",
          ow.player.cellX, ow.player.cellY)
  end

  -- Run the script from the row after the rival battle, so no one has to win
  -- OPP_RIVAL3 to see the cutscene.  Rows before that point are the only ones
  -- carrying jump targets, so the slice needs no reindexing -- assert that.
  local from
  for i, row in ipairs(rows) do
    if row[1] == "show_text"
       and row[2] == "_ChampionsRoomRivalAfterBattleText" then
      from = i
      break
    end
  end
  check("found the post-battle row to start from", from ~= nil)
  local slice, jumpy = {}, false
  for i = from or 1, #rows do
    local row = rows[i]
    if row[1] == "jump" or row[1] == "jump_if_true"
       or row[1] == "jump_if_false" then
      jumpy = true
    end
    slice[#slice + 1] = row
  end
  check("the tail of the script has no jump targets to reindex", not jumpy)

  if failures > 0 then
    U.log("stopping before the cutscene:", failures,
          "check(s) failed above, so what you would see means nothing")
    while true do coroutine.yield() end
  end

  ow:queueScript(slice, { npc = rival })

  local startY = ow.player.cellY
  local minY, walkShot, sharedCell = startY, false, false
  local hof
  for i = 1, 5000 do
    local top = game.stack:top()
    if getmetatable(top) == HallOfFame or (top and top.drawMonInfo) then
      hof = top
      break
    end
    local w = game.overworld
    if w and w.map and w.map.id == "CHAMPIONS_ROOM" then
      local x, y = w.player.cellX, w.player.cellY
      if y < minY then minY = y end
      if x == rival.cellX and y == rival.cellY then sharedCell = true end
      if y <= 2 and not walkShot then
        walkShot = U.shot(game, DIR .. "/hof704_follows_oak.png")
      end
    end
    if i % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  check("the player walked out of the room before the warp (#704)",
        minY < startY)
  check("the player routed around the rival", not sharedCell)
  check("walk-out screenshot", walkShot)
  check("the induction started", hof ~= nil)
  if not hof then
    while true do coroutine.yield() end
  end

  -- ---------------------------------------------------------------
  -- the induction screen
  -- ---------------------------------------------------------------
  -- mid scroll: .ScrollPic nudges hSCX 4px a frame, and the exemption has to
  -- travel with the pic instead of sitting at its resting column (#637)
  -- #847: HoFShowMonOrPlayer sweeps the BACK pic across the screen (low, at
  -- y=88) before the front pic scrolls in.  Catch it mid-sweep, wait the
  -- sweep out, then catch the front pic partway through its own scroll.
  for _ = 1, 300 do
    if hof.phase ~= "back" or (hof.scrollX or 0) <= 56 then break end
    U.wait(1)
  end
  check("back-pic sweep screenshot", U.shot(game, DIR .. "/hof847_back.png"))
  for _ = 1, 300 do
    if hof.phase ~= "back" then break end
    U.wait(1)
  end
  for _ = 1, 200 do
    if (hof.scrollX or PIC_X) > 8 then break end
    U.wait(1)
  end
  check("scrolling-in screenshot", U.shot(game, DIR .. "/hof637_scroll.png"))

  for _ = 1, 300 do
    if (hof.scrollX or 0) >= PIC_X and hof.phase == "mons" then break end
    U.wait(1)
  end

  -- read back where the labels actually land: on screen a row collision and
  -- a missing label look the same once the box is drawn over them
  local realDraw = Font.draw
  local seen = {}
  Font.draw = function(text, x, y, ...)
    seen[#seen + 1] = { tostring(text), x, y }
    return realDraw(text, x, y, ...)
  end
  U.wait(4)
  Font.draw = realDraw

  local function rowOf(needle)
    for _, d in ipairs(seen) do
      if d[1]:find(needle, 1, true) then return d[3] end
    end
    return nil
  end
  local yLevel, yLevelVal = rowOf("LEVEL"), rowOf("100")
  local yType1, yType1Val = rowOf("TYPE1"), rowOf("FIRE")
  local yType2, yType2Val = rowOf("TYPE2"), rowOf("FLYING")
  U.log("label rows:", tostring(yLevel), tostring(yType1), tostring(yType2),
        "value rows:", tostring(yLevelVal), tostring(yType1Val),
        tostring(yType2Val))
  check("all six LEVEL/TYPE cells were drawn",
        yLevel and yLevelVal and yType1 and yType1Val and yType2 and yType2Val)
  check("no label shares a row with a value (#697)",
        yLevel ~= yLevelVal and yType1 ~= yType1Val and yType2 ~= yType2Val
        and yType1 ~= yLevelVal and yType2 ~= yType1Val)
  check("the labels sit on rows 6/8/10 like PlaceNextChar's double spacing",
        yLevel == 6 * 8 and yType1 == 8 * 8 and yType2 == 10 * 8)

  local picRect
  for _, r in ipairs(PaletteFX.trueColorRects("ui")) do
    if r.colors == false and r.y == PIC_Y then picRect = r end
  end
  check("the settled pic is exempted from the whole-screen palette (#637)",
        picRect ~= nil and picRect.x == PIC_X)
  check("settled screenshot", U.shot(game, DIR .. "/hof697_mon_info.png"))

  U.log(failures == 0 and "all checks passed" or ("FAILURES: " .. failures))
  U.log("walked you into the hall of fame (#704, #697, #637).")
  U.log("the player should have followed oak up and out of the champion's")
  U.log("room before the fade, the TYPE1/TYPE2 rows should sit under LEVEL")
  U.log("rather than on top of the level and type values, and each pic")
  U.log("should keep its own colors while the rest of the screen carries")
  U.log("the mon's tint, from the first scrolled-in pixel to the fade.")
  U.log("the near miss to watch for: the pic goes right but a column at its")
  U.log("left edge stays tinted while it slides in.")
  U.log("the other two party members and the player stats page follow on")
  U.log("their own; re-run the command to watch the whole thing again.")

  while true do
    coroutine.yield()
  end
end

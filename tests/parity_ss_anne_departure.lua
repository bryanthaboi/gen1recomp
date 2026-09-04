-- Parity: the S.S. Anne rival goodbye and her departure from the dock
-- (#360).  scripts/SSAnne2F.asm SSAnne2FRivalAfterBattleScript prints
-- TEXT_SSANNE2F_RIVAL_CUT_MASTER and walks him out DOWNWARD, keyed on the
-- player's X; scripts/VermilionDock.asm VermilionDockSSAnneLeavesScript
-- delays 120, blows SFX_SS_ANNE_HORN, shifts her eight columns west, then
-- VermilionDock_EraseSSAnne blows the horn again and delays 120 more.
--
--   luajit tests/parity_ss_anne_departure.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity ss anne departure")
local check, eq = S.check, S.eq

-- restored at the bottom for the suites run after this file
local realMusic = package.loaded["src.core.Music"]
local realTextBox = package.loaded["src.render.TextBox"]
local realPicBox = package.loaded["src.ui.PicBox"]
local music = { played = {} }
package.loaded["src.core.Music"] = {
  play = function(_, id) music.played[#music.played + 1] = id end,
  playOnce = function() return true end,
  stop = function() music.played[#music.played + 1] = "stop" end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text) return { text = text } end,
}
package.loaded["src.ui.PicBox"] = { new = function() return {} end }

local story3 = dofile("data/scripts/story3.lua")
local story5 = dofile("data/scripts/story5.lua")
local text = dofile("data/generated/text.lua")
local audio = dofile("data/generated/audio.lua")
local maps = dofile("data/generated/maps.lua")

local function dirsEqual(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

local function rowsOfKind(rows, kind)
  local out = {}
  for _, r in ipairs(rows) do
    if r[1] == kind then out[#out + 1] = r end
  end
  return out
end

-- ------------------------------------------------------------- rival exit
-- SSAnne2F.asm .RivalDownFourMovement (player on 37) and
-- .RivalWalkAroundPlayerMovement, which falls through into those same four
-- DOWNs (player on 36).
local RIGHT_OF_HIM = { "down", "down", "down", "down" }
local AROUND_HIM = { "right", "down", "down", "down", "down", "down" }

local function ambush(x)
  local rows
  local ow = {
    runner = {
      isRunning = function() return false end,
      run = function(_, r) rows = r end,
    },
    player = { facing = "down" },
  }
  local game = { save = { flags = {} }, data = {} }
  check(story5.SS_ANNE_2F.onStep(game, ow, x, 8),
        ("SS Anne 2F ambush fires at (%d,8)"):format(x))
  check(rows ~= nil, "the ambush queued rows")
  return rows, ow
end

do
  check(type(text._SSAnne2FRivalCutMasterText) == "string",
        "_SSAnne2FRivalCutMasterText is in the cache")
  check(text._SSAnne2FRivalCutMasterText:find("CUT", 1, true) ~= nil,
        "the goodbye line is the CUT master one")

  for _, case in ipairs({ { 37, RIGHT_OF_HIM }, { 36, AROUND_HIM } }) do
    local x, dirs = case[1], case[2]
    local rows, ow = ambush(x)
    -- scripts/SSAnne2F.asm:93
    eq(ow.player.facing, "down",
       ("x=%d the trigger leaves the player's facing alone"):format(x))
    local function rowIndex(kind)
      for i, r in ipairs(rows) do if r[1] == kind then return i end end
    end
    local turns = rowsOfKind(rows, "face_player_dir")
    if x == 37 then
      -- scripts/SSAnne2F.asm:73-77
      eq(#turns, 1, "x=37 turns the player as a script row")
      eq(turns[1][2], "left", "and it turns him LEFT")
      local at, moved, spoke =
        rowIndex("face_player_dir"), rowIndex("move_npc_to"), rowIndex("show_text")
      check(moved and at and spoke and moved < at and at < spoke,
            "the turn lands after the rival's walk and before the dialogue")
    else
      eq(#turns, 0, "x=36 never touches the player's facing")
    end
    local said = {}
    for _, r in ipairs(rowsOfKind(rows, "show_text")) do
      said[#said + 1] = r[2]
    end
    -- SSAnne2FRivalText's text_asm arms SaveEndBattleTextPointers, so the
    -- defeat line prints in battle, not on the map (scripts/SSAnne2F.asm:199)
    local order = {
      "_SSAnne2FRivalText",
      "_SSAnne2FRivalCutMasterText",
    }
    local pi = 1
    for _, id in ipairs(said) do
      if pi <= #order and id == order[pi] then pi = pi + 1 end
    end
    eq(pi, #order + 1,
       ("x=%d text order: greeting, then CUT master"):format(x))
    local armed = rowsOfKind(rows, "save_end_battle_text")[1]
    check(armed ~= nil and armed[2] == "_SSAnne2FRivalDefeatedText",
       ("x=%d arms the defeat line for the battle screen (#1688)"):format(x))

    local walk = rowsOfKind(rows, "walk_npc")[1]
    check(walk ~= nil, ("x=%d exit is a walk_npc list"):format(x))
    check(dirsEqual(walk and walk[3], dirs),
          ("x=%d exit walk matches the pokered movement data"):format(x))
    -- the port used to send him back to his (36,4) spawn by the
    -- captain's-room stairs instead of out of the room
    for _, r in ipairs(rowsOfKind(rows, "move_npc_to")) do
      check(not (r[3] == 36 and r[4] == 4),
            ("x=%d rival must not retreat to the spawn (36,4)"):format(x))
    end
    -- jump_if_false on a lost battle has to clear the whole tail
    local jump = rowsOfKind(rows, "jump_if_false")[1]
    local target = jump and jump[2]
    if type(target) == "string" then
      for i, r in ipairs(rows) do
        if r[1] == "label" and r[2] == target then target = i break end
      end
    end
    while type(target) == "number" and rows[target]
          and rows[target][1] == "label" do
      target = target + 1
    end
    eq(target, #rows, "a lost battle jumps past the exit walk")
  end
end

-- --------------------------------------------------------------- the ship
-- data/maps/objects/VermilionDock.asm: the SS_ANNE_1F gangway warp is
-- (14,2), i.e. block (7,1), and hlowcoord 5, 2 is the hull's own block box.
local DOCK_HULL = { x0 = 5, x1 = 8, y0 = 1, y1 = 2 }
local WATER = { [1] = true, [13] = true }

local function dockBlock(bx, by)
  local def = maps.VERMILION_DOCK
  return def.blocks[by * def.width + bx + 1]
end

local function sail(cellX, cellY)
  local rows = nil
  local ow = {
    player = { cellX = cellX, cellY = cellY },
    queueScript = function(_, r) rows = r end,
  }
  local game = {
    save = { flags = { EVENT_GOT_HM01 = true } },
    data = { text = text },
  }
  story3.VERMILION_DOCK.onEnter(game, ow)
  check(rows ~= nil, "stepping off the gangway queues the departure")
  check(game.save.flags.EVENT_SS_ANNE_LEFT == true, "EVENT_SS_ANNE_LEFT set")
  return rows
end

local function kindIndex(rows, kind, from)
  for i = from or 1, #rows do
    if rows[i][1] == kind then return i end
  end
end

do
  -- the hull ids the slide reuses are the map's own blocks, so a data
  -- rebuild that renumbered the tileset would be caught here
  eq(dockBlock(DOCK_HULL.x0, 1), 4, "bow upper-half block id")
  eq(dockBlock(DOCK_HULL.x1, 2), 11, "stern lower-half block id")
  check(WATER[dockBlock(2, 1)] and WATER[dockBlock(2, 2)],
        "the water she sails into is blocks 1 (upper) and 13 (lower)")
  eq(audio.mapSongs.VERMILION_CITY, "Music_Vermilion",
     "the city has its own theme for PlayDefaultMusic to switch to")
  check(audio.songs.Music_Vermilion ~= nil, "and that song is in the cache")

  local rows = sail(14, 2)

  local horns = 0
  for _, r in ipairs(rowsOfKind(rows, "play_sound")) do
    if r[2] == "SS_Anne_Horn" then horns = horns + 1 end
  end
  eq(horns, 2, "the horn blows twice: leaving, then once she is gone")

  local waits = rowsOfKind(rows, "wait")
  eq(waits[1][2], 120, "120 frames before the first horn")
  eq(waits[#waits][2], 120, "EraseSSAnne's 120 frames before the walk out")

  -- scripts/VermilionDock.asm:50 zeroes wSpritePlayerStateData1ImageIndex and
  -- :77 freezes sprite updates: he faces DOWN until he walks out (#1689)
  eq(rows[1][1], "face_player_dir", "he is turned before the first delay")
  eq(rows[1][2], "down", "and he is turned to face DOWN")

  -- she used to be shuffled west one whole 32px block per beat, which read as
  -- teleporting; .shift_columns_up is a 1px-per-8-frames slide (#1689)
  eq(#rowsOfKind(rows, "replace_block"), 0,
     "no block shuffle: the hull slides, it does not jump")
  eq(#rowsOfKind(rows, "ss_anne_departs"), 1, "one blocking sail-away beat")

  local horn1 = kindIndex(rows, "play_sound")
  local sailIdx = kindIndex(rows, "ss_anne_departs")
  local horn2 = kindIndex(rows, "play_sound", (horn1 or 0) + 1)
  check(horn1 and sailIdx and horn2 and horn1 < sailIdx and sailIdx < horn2,
        "horn, then she sails, then the horn again")
  check(kindIndex(rows, "warp") > sailIdx,
        "the walk out only starts once she has gone")
end

do
  -- fix 3: opts.keep on play_music sets keepMusicOnce, which
  -- OverworldController:setMap consumes to SKIP the destination map's
  -- theme -- the dock's Music_Surfing must not ride into Vermilion City
  local rows = sail(14, 2)
  for _, r in ipairs(rowsOfKind(rows, "play_music")) do
    check(not (r[3] and r[3].keep),
          "no keepMusicOnce override on the way into the city")
  end
  local warp = rowsOfKind(rows, "warp")[1]
  check(warp ~= nil and warp[2] == "VERMILION_CITY", "the cutscene warps into town")
  check(not (warp[6] and warp[6].keepMusic), "the warp itself keeps no music")
  eq(music.played[#music.played], "Music_Surfing", "the sail-away plays surf")
end

do
  -- coming back later: no ghost hull, just the sailor's line and a bounce
  -- back into the city
  local set, rebuilt, pushed, warped = {}, false, nil, nil
  local ow = {
    player = { cellX = 14, cellY = 2 },
    map = {
      setBlock = function(_, bx, by, block) set[bx .. "," .. by] = block end,
      renderer = { rebuild = function() rebuilt = true end },
    },
    startWarpTo = function(_, m) warped = m end,
  }
  local game = {
    save = { flags = { EVENT_SS_ANNE_LEFT = true } },
    data = { text = text },
    stack = { push = function(_, s) pushed = s end },
  }
  story3.VERMILION_DOCK.onEnter(game, ow)
  for bx = DOCK_HULL.x0, DOCK_HULL.x1 do
    for by = DOCK_HULL.y0, DOCK_HULL.y1 do
      check(WATER[set[bx .. "," .. by]],
            ("re-entry: (%d,%d) is water, not a ghost hull"):format(bx, by))
    end
  end
  check(rebuilt, "re-entry rebuilds the tile renderer")
  check(pushed ~= nil and type(pushed.text) == "string",
        "re-entry shows the ship-set-sail line")
  pushed.text = pushed.text or ""
  eq(pushed.text, text._VermilionCitySailor1ShipSetSailText,
     "and it is the sailor's own line")
end

package.loaded["src.core.Music"] = realMusic
package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.PicBox"] = realPicBox

S.finish()

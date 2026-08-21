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
local audioChunk = loadfile("data/generated/audio.lua")
local audio = audioChunk and audioChunk() or nil
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
  return rows
end

do
  check(type(text._SSAnne2FRivalCutMasterText) == "string",
        "_SSAnne2FRivalCutMasterText is in the cache")
  check(text._SSAnne2FRivalCutMasterText:find("CUT", 1, true) ~= nil,
        "the goodbye line is the CUT master one")

  for _, case in ipairs({ { 37, RIGHT_OF_HIM }, { 36, AROUND_HIM } }) do
    local x, dirs = case[1], case[2]
    local rows = ambush(x)
    local said = {}
    for _, r in ipairs(rowsOfKind(rows, "show_text")) do
      said[#said + 1] = r[2]
    end
    local order = {
      "_SSAnne2FRivalText",
      "_SSAnne2FRivalDefeatedText",
      "_SSAnne2FRivalCutMasterText",
    }
    local pi = 1
    for _, id in ipairs(said) do
      if pi <= #order and id == order[pi] then pi = pi + 1 end
    end
    eq(pi, #order + 1,
       ("x=%d text order: greeting, defeated, CUT master"):format(x))

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
    eq(jump and jump[2], #rows, "a lost battle jumps past the exit walk")
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
  local rows, puffs = nil, 0
  local ow = {
    player = { cellX = cellX, cellY = cellY },
    startDustAnim = function(_, _, _, done)
      puffs = puffs + 1
      if done then done() end
    end,
    queueScript = function(_, r) rows = r end,
  }
  local game = {
    save = { flags = { EVENT_GOT_HM01 = true } },
    data = { text = text },
  }
  story3.VERMILION_DOCK.onEnter(game, ow)
  check(rows ~= nil, "stepping off the gangway queues the departure")
  check(game.save.flags.EVENT_SS_ANNE_LEFT == true, "EVENT_SS_ANNE_LEFT set")
  eq(puffs, 3, "three funnel smoke puffs (LoadSmokeTileFourTimes)")
  return rows
end

do
  -- the hull ids the slide reuses are the map's own blocks, so a data
  -- rebuild that renumbered the tileset would be caught here
  eq(dockBlock(DOCK_HULL.x0, 1), 4, "bow upper-half block id")
  eq(dockBlock(DOCK_HULL.x1, 2), 11, "stern lower-half block id")
  check(WATER[dockBlock(2, 1)] and WATER[dockBlock(2, 2)],
        "the water she sails into is blocks 1 (upper) and 13 (lower)")
  if audio then
    eq(audio.mapSongs.VERMILION_CITY, "Music_Vermilion",
       "the city has its own theme for PlayDefaultMusic to switch to")
    check(audio.songs.Music_Vermilion ~= nil, "and that song is in the cache")
  end

  local rows = sail(14, 2)

  local horns = 0
  for _, r in ipairs(rowsOfKind(rows, "play_sound")) do
    if r[2] == "SS_Anne_Horn" then horns = horns + 1 end
  end
  eq(horns, 2, "the horn blows twice: leaving, then once she is gone")

  local waits = rowsOfKind(rows, "wait")
  eq(waits[1][2], 120, "120 frames before the first horn")
  eq(waits[#waits][2], 120, "EraseSSAnne's 120 frames before the walk out")
  local slide = 0
  for _, w in ipairs(waits) do
    if w[2] == 20 then slide = slide + 1 end
  end
  eq(slide, 8, "eight column shifts, .shift_columns_up's ld e, $8")

  -- the bug was the whole hull blinking to water in a single frame with no
  -- travel at all: her bow block has to be written one column further west
  -- each step, and the water has to close in astern behind her
  local bow, wake = {}, {}
  for _, r in ipairs(rowsOfKind(rows, "replace_block")) do
    if r[3] == 1 and r[4] == dockBlock(DOCK_HULL.x0, 1) then
      bow[#bow + 1] = r[2]
    elseif r[3] == 1 and r[4] == 1 then
      wake[#wake + 1] = r[2]
    end
  end
  check(dirsEqual(bow, { 4, 3, 2, 1 }), "the bow sails west a column a step")
  check(dirsEqual(wake, { 8, 7, 6, 5, 4, 3, 2, 1 }),
        "water closes in astern, stern column first")

  for _, r in ipairs(rowsOfKind(rows, "replace_block")) do
    check(r[2] >= 1 and r[2] <= DOCK_HULL.x1,
          "the slide stays inside the dock's water, off the pier column 0")
  end

  -- scripts/VermilionDock.asm:182-203: the tile fill covers the whole ship,
  -- the gangway block under the player included (#1211)
  local final = {}
  for _, r in ipairs(rowsOfKind(rows, "replace_block")) do
    final[r[2] .. "," .. r[3]] = r[4]
  end
  for bx = DOCK_HULL.x0, DOCK_HULL.x1 do
    for by = DOCK_HULL.y0, DOCK_HULL.y1 do
      check(WATER[final[bx .. "," .. by]],
            ("hull block (%d,%d) ends as open water"):format(bx, by))
    end
  end

  -- and she has to have travelled: the westmost water column of the map
  -- carried hull blocks partway through
  local sawWest = false
  for _, r in ipairs(rowsOfKind(rows, "replace_block")) do
    if r[2] == 1 and not WATER[r[4]] then sawWest = true end
  end
  check(sawWest, "the hull reaches the west edge of the water before it goes")
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

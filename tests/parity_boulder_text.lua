-- Parity test: talking to a Strength boulder prints _BoulderText (#318).
-- Self-contained: run via `luajit tests/parity_boulder_text.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- In pokered every boulder's map text is the same wrapper: the local label
-- (e.g. WardensHouseBoulderText) is `text_far _BoulderText`, the shared
-- "This requires STRENGTH to move!" line.  Our extractor records only the
-- local label ("BoulderText") with no resolved string, so resolveText came
-- up empty and talking to a boulder answered with silence -- the same
-- wrapper family as the bench guys (#248), but here the far target's name
-- coincides with the local one, so the engine resolves it directly.
--
-- The invariant asserted here: every SPRITE_BOULDER object, on any map,
-- shows the shared STRENGTH line when talked to.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity boulder text")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")
local OW = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()

-- every boulder object in the generated data rides the BoulderText wrapper,
-- so one engine path covers them all
do
  local boulders, wrappers = 0, 0
  for mapId, mapDef in pairs(Data.maps) do
    for _, obj in ipairs(mapDef.objects or {}) do
      if obj.sprite == "SPRITE_BOULDER" then
        boulders = boulders + 1
        local entry = Data:textEntry(mapDef.label, obj.text)
        if entry and entry.label == "BoulderText" then
          wrappers = wrappers + 1
        end
      end
    end
  end
  check(boulders > 0, "generated data has boulder objects")
  eq(wrappers, boulders, "every boulder object points at the BoulderText wrapper")
  check(Data.text._BoulderText ~= nil, "_BoulderText itself resolves to a string")
end

-- talking to a boulder shows the shared STRENGTH line, like the ROM
local function boulderTalkText(mapId, bx, by)
  while Game.stack:top() do Game.stack:pop() end
  Game.save = SaveData.newGame()
  Game.stack:push(OW, mapId, bx, by + 1, "up") -- stand south of it, face up
  local ow = Game.stack:top()
  local boulder
  for _, n in ipairs(ow.npcs) do
    if n.def and n.def.sprite == "SPRITE_BOULDER"
       and n.cellX == bx and n.cellY == by then
      boulder = n
      break
    end
  end
  if not boulder then return nil, "no boulder npc at target cell" end
  ow:talkTo(boulder)
  local top = Game.stack:top()
  if getmetatable(top) ~= TextBox then return nil, "no TextBox pushed" end
  local lines = {}
  for _, page in ipairs(top.pages) do
    for _, line in ipairs(page) do lines[#lines + 1] = line end
  end
  return table.concat(lines, " ")
end

do
  -- WARDENS_HOUSE boulder at (8,4) (data/maps/objects/WardensHouse.asm)
  local text, err = boulderTalkText("WARDENS_HOUSE", 8, 4)
  check(text ~= nil, "Warden's House boulder shows a text box (" ..
        tostring(err) .. ")")
  check(text ~= nil and text:find("STRENGTH", 1, true) ~= nil,
        "Warden's House boulder says the STRENGTH line (#318), got: " ..
        tostring(text))
  while Game.stack:top() do Game.stack:pop() end

  -- VICTORY_ROAD_1F boulder at (2,10): the switch boulders use the same
  -- wrapper, so they answer identically (the switch logic is push-time)
  local text2, err2 = boulderTalkText("VICTORY_ROAD_1F", 2, 10)
  check(text2 ~= nil, "Victory Road boulder shows a text box (" ..
        tostring(err2) .. ")")
  check(text2 ~= nil and text2:find("STRENGTH", 1, true) ~= nil,
        "Victory Road boulder says the STRENGTH line (#318), got: " ..
        tostring(text2))
end

S.finish()

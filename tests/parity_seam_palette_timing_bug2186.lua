-- home/overworld.asm:675
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local PaletteFX = require("src.render.PaletteFX")
local Zoom = require("src.render.Zoom")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("seam palette timing #2186")
local check, eq = S.check, S.eq

local savedZoom, savedMode = Zoom.offset, PaletteFX.mode

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW
PaletteFX.setMode("gbc")

local function key(colors)
  if not colors then return "nil" end
  local out = {}
  for i, c in ipairs(colors) do
    out[i] = table.concat(c, ",")
  end
  return table.concat(out, "|")
end

local function landStep(ow)
  for _ = 1, 40 do
    ow:update(1 / 60)
    if not ow.player.moving then return true end
  end
  return false
end

while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "PALLET_TOWN", 10, 0, "up")
local ow = Game.stack:top()
local north = ow.map:connection("north")
check(north and north.map == "ROUTE_1", "Pallet north connects to ROUTE_1")

Zoom.offset = 0
local palletName = ow:paletteNameFor(ow.map)
local pallet = key(PaletteFX.pal(Data, palletName))
eq(#ow:sgbWorldZones(), 1, "FIT at Pallet is one whole-screen world zone")

check(ow:crossConnection("up", north) == true, "Pallet -> Route 1 crosses")
eq(ow.map.id, "ROUTE_1", "map data swapped to ROUTE_1 at the seam")
local routeName = ow:paletteNameFor(ow.map)
local route = key(PaletteFX.pal(Data, routeName))
check(route ~= pallet, "Route 1 and Pallet wear different palettes")
check(ow.player.moving, "seam step is in progress")

local zones = ow:sgbWorldZones()
eq(#zones, 1, "seam step is still one whole-screen world zone")
eq(key(zones[1].colors), pallet, "world keeps Pallet's palette while the seam step walks")
eq(key(ow:sgbPalettes()[1].colors), pallet, "UI pass keeps Pallet's palette while the seam step walks")

ow:update(1 / 60)
check(ow.player.moving, "one frame in, the seam step is still walking")
eq(key(ow:sgbWorldZones()[1].colors), pallet, "mid-step world zone is still Pallet")

check(landStep(ow), "seam step lands")
eq(ow.seamPalette, nil, "held palette cleared once the step lands")
zones = ow:sgbWorldZones()
eq(#zones, 1, "landed on Route 1: one whole-screen zone")
eq(key(zones[1].colors), route, "world flips to Route 1's palette on landing")
eq(key(ow:sgbPalettes()[1].colors), route, "UI pass flips to Route 1's palette on landing")

Zoom.offset = -1
local south = ow.map:connection("south")
check(south and south.map == "PALLET_TOWN", "Route 1 south connects to Pallet")
ow.player.facing = "down"
check(ow:crossConnection("down", south) == true, "Route 1 -> Pallet crosses in survey zoom")
zones = ow:sgbWorldZones()
eq(key(zones[1].colors), pallet, "survey zoom base zone is the destination map immediately")
check(#zones > 1, "survey zoom keeps per-map neighbor zones")
check(landStep(ow), "survey seam step lands")

Zoom.offset = 0
north = ow.map:connection("north")
check(ow:crossConnection("up", north) == true, "Pallet -> Route 1 crosses again")
check(ow.seamPalette ~= nil, "outgoing palette held for the seam step")
ow:setMap("REDS_HOUSE_1F", 3, 7, "up")
eq(ow.seamPalette, nil, "a warp mid-step drops the held palette")

Zoom.offset = savedZoom
PaletteFX.setMode(savedMode)
S.finish()

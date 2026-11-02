package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Assets = require("src.render.Assets")
local SpriteRenderer = require("src.render.SpriteRenderer")
local GbcPalette = require("src.render.GbcPalette")

local reads = {}
local realImageData = Assets.imageData
Assets.imageData = function(path, ...)
  reads[#reads + 1] = path
  return realImageData(path, ...)
end
local function readCount() return #reads end

local SHEET = "assets/generated/sprites/youngster.png"
local OTHER = "assets/generated/sprites/lass.png"
local colors = { { 248, 248, 248 }, { 200, 120, 80 }, { 120, 60, 40 },
                 { 0, 0, 0 } }

check(SpriteRenderer.queueWarm(SHEET, colors, "warmtest:1"),
  "a sheet and palette not baked yet is queued")
check(not SpriteRenderer.queueWarm(SHEET, colors, "warmtest:1"),
  "the same bake is queued once")
check(SpriteRenderer.queueWarm(OTHER, colors, "warmtest:1"),
  "a second sheet is queued")
check(not SpriteRenderer.queueWarm(SHEET, colors, nil),
  "a bake with no cache group is refused")
eq(SpriteRenderer.warmPending(), 2, "two bakes wait")

eq(SpriteRenderer.pumpWarm(1), 1, "one pump bakes one sheet")
eq(readCount(), 1, "reading its pixels once")
eq(SpriteRenderer.pumpWarm(1), 1, "the next pump bakes the next")
eq(SpriteRenderer.warmPending(), 0, "and the queue is empty")
local before = readCount()
SpriteRenderer.obpImage(SHEET, colors, "warmtest:1")
SpriteRenderer.obpImage(OTHER, colors, "warmtest:1")
eq(readCount(), before, "a draw after the warm reads no pixels")
check(not SpriteRenderer.queueWarm(SHEET, colors, "warmtest:1"),
  "a baked sheet is never queued again")

local def = { image = "assets/generated/sprites/gen2_teacher.png", frames = 6,
              walker = true }
local objColors = { { 248, 248, 248 }, { 248, 200, 80 }, { 160, 80, 40 },
                    { 0, 0, 0 } }
check(SpriteRenderer.queueWarmGen2(def, objColors, "gen2:DAY:3"),
  "a Gen 2 object palette is queued")
SpriteRenderer.pumpWarm(1)
local sprite = SpriteRenderer.new(def, "R29_obj_1")
sprite:setObjPalette(objColors, "gen2:DAY:3")
before = readCount()
SpriteRenderer.obpImage(def.image, sprite:gen2Obp())
eq(readCount(), before,
  "the Gen 2 warm bakes the exact key the sprite draws with")
local savedMode = GbcPalette.mode
GbcPalette.mode = savedMode == "dmg" and "gbc" or "dmg"
SpriteRenderer.obpImage(def.image, sprite:gen2Obp())
eq(readCount(), before + 1, "a COLOR mode change is a different bake")
GbcPalette.mode = savedMode

local npcDef = { image = "assets/generated/sprites/bug_catcher.png",
                 frames = 6, walker = true }
check(SpriteRenderer.queueWarmSprite(npcDef, "VIRIDIAN_CITY_obj_2"),
  "a Gen 1 object is queued under the live COLORS mode")
SpriteRenderer.pumpWarm(1)
local npc = SpriteRenderer.new(npcDef, "VIRIDIAN_CITY_obj_2")
before = readCount()
npc:resolveImage()
eq(readCount(), before, "and its draw finds the warmed bake")

check(not SpriteRenderer.queueWarmSprite({ image = "x.png", trueColor = true,
  gbaArt = true }, "s"), "true-colour art is never warmed")

local realReady = Assets.decodeReady
Assets.decodeReady = function() return false end
SpriteRenderer.queueWarm(SHEET, colors, "warmtest:late")
for _ = 1, 10 do SpriteRenderer.pumpWarm(1) end
eq(SpriteRenderer.warmPending(), 1, "a bake waits for its background decode")
for _ = 1, 300 do SpriteRenderer.pumpWarm(1) end
eq(SpriteRenderer.warmPending(), 0, "and is dropped if the decode never lands")
before = readCount()
SpriteRenderer.obpImage(SHEET, colors, "warmtest:late")
eq(readCount(), before + 1, "leaving the draw path to bake it as before")
SpriteRenderer.queueWarm(OTHER, colors, "warmtest:now", "now")
eq(SpriteRenderer.pumpWarm(1), 1,
  "a sheet for a map already in view bakes on the next pump")
Assets.decodeReady = realReady

SpriteRenderer.queueWarm(OTHER, colors, "warmtest:flush")
Assets.invalidate()
eq(SpriteRenderer.warmPending(), 0, "an asset flush drops queued bakes")

Assets.imageData = realImageData
T.finish("sprite warm queue")

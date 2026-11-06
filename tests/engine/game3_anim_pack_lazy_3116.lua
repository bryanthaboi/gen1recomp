package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

require("src.core.GameVersion").set("emerald")

local ROOT = "data/generated/gba/pokemon/battle_anims/"
local PACK = [[
return {
  tags = {
    GOLD_STARS = { file = "tags/gold_stars.png", pal = { 0, 1 } },
    IMPACT = { file = "tags/impact.png", idxFile = "tags/impact_idx.png", pal = { 0, 2 } },
    SPARK = { file = "tags/spark.png" },
  },
  moves = { [1] = { { op = "end" } } },
}
]]

local reads = {}
local function count(prefix)
  local n = 0
  for _, rel in ipairs(reads) do
    if prefix == nil or rel:sub(1, #prefix) == prefix then n = n + 1 end
  end
  return n
end

local cache = {}
function cache:read(rel)
  reads[#reads + 1] = rel
  if rel == ROOT .. "pack.lua" then return PACK end
  if rel:sub(1, #ROOT) == ROOT and rel:find("%.png$") then return "\137PNG\r\n\26\n" end
  return nil
end
package.loaded["src.core.game3.dataset"] = { cache = function() return cache end }

local images = 0
local newImage = love.graphics.newImage
love.graphics.newImage = function(...)
  images = images + 1
  return newImage(...)
end

local Anim = require("src.core.game3.battle.anim")
local AnimPal = require("src.core.game3.battle.anim_pal")
Anim._pack, Anim._packLoaded = nil, false

local script = Anim.scriptForMove(1)
eq(script and script[1] and script[1].op, "end", "scriptForMove reads the move script from the pack")
eq(count(), 1, "first anim reads only pack.lua")
eq(count(ROOT .. "tags/"), 0, "first anim decodes no tag sheet")
eq(images, 0, "first anim creates no tag image")

local tags = Anim._pack.tags
eq(tags.IMPACT.pal[2], 2, "raw tag fields stay readable without a load")
eq(count(ROOT .. "tags/"), 0, "reading pal does not load the sheet")

local img = tags.IMPACT.image
check(img ~= nil, "IMPACT image hydrates on first read")
eq(count(ROOT .. "tags/"), 2, "IMPACT reads its sheet and idx sheet only")
eq(images, 2, "IMPACT creates its rgba and idx images only")
eq(tags.IMPACT.w, 8, "IMPACT width set")
eq(tags.IMPACT.h, 8, "IMPACT height set")
check(tags.IMPACT.idxImage, "IMPACT idx image set")
local reg = AnimPal.idxOf[img]
check(reg and reg.img == tags.IMPACT.idxImage and reg.tag == "IMPACT", "IMPACT idx sheet registered with AnimPal")
eq(img.minFilter, "nearest", "IMPACT image filter nearest")

local before, imgsBefore = #reads, images
local again = tags.IMPACT.image
check(again == img, "second read returns the same image")
eq(#reads - before, 0, "second read hits no cache")
eq(images - imgsBefore, 0, "second read creates no image")

local sw = tags.SPARK.w
eq(sw, 8, "reading w alone hydrates SPARK")
eq(count(ROOT .. "tags/spark"), 1, "SPARK reads only its sheet")
eq(count(ROOT .. "tags/gold"), 0, "GOLD_STARS still untouched")
eq(tags.SPARK.idxImage, nil, "SPARK without idxFile has no idx image")

local preB = #reads
Anim.scriptForMove(1)
check(Anim.preloadPack() == Anim._pack, "preloadPack returns the loaded pack")
eq(#reads - preB, 0, "pack loads once")

local Warm = require("src.core.game3.warm")
Warm.reset()
local Prewarm = require("src.core.game3.prewarm")
Prewarm.battle({ party = {} }, nil)
check(Warm.pending("battle:anim_pack"), "battle prewarm queues the anim pack")
Warm.reset()

local want = { SE_SHINY = true, SE_BALL_TRAY_ENTER = true, SE_BALL_TRAY_BALL = true, SE_BALL_TRAY_EXIT = true }
for _, name in ipairs(Prewarm.BATTLE_SE) do want[name] = nil end
eq(next(want), nil, "battle SE prewarm covers shiny and ball tray SEs")

Anim._pack, Anim._packLoaded = nil, false
package.loaded["src.core.game3.dataset"] = { cache = function()
  return { read = function() return nil end }
end }
local ok1 = pcall(Anim.preloadPack)
check(not ok1, "preloadPack raises on a cache without pack.lua")
eq(Anim._packLoaded, false, "failed preload leaves the pack unloaded")

T.finish("game3 anim pack lazy tags")

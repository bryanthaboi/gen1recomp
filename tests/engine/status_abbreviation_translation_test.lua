-- SummaryMenu.lua:148 and PartyMenu.lua:824 used to draw mon.status as a
-- bare literal ("PSN", "PAR", "BRN", "FRZ", "SLP"), invisible to any
-- translation a mod supplies. Unlike the strings catalog, a mod translates
-- status abbreviations through the statuses content registry
-- (mod.content.statuses:patch(id, { label = value }), label only), the
-- same registry src/battle/BattleState.lua:statusLabel already reads in
-- battle. This test drives both screens' status draw with a mod-patched
-- registry and checks the patched label reaches Font.draw, not the raw
-- status id.
--
-- It also guards a second bug found alongside the first: Status.RECORDS'
-- five vanilla entries used to set hudLabel to the same literal as label
-- ("FRZ", hudLabel = "FRZ", ...). Since Status.hudLabelFor (and
-- BattleState:statusLabel before it) reads "hudLabel or label", and
-- Registry:patch only overrides the fields a mod actually passes, a
-- real label-only patch left the untouched vanilla hudLabel shadowing it
-- forever -- the translation was stored but never displayed anywhere,
-- in or out of battle.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = love or {}
love.graphics = {
  setColor = function() end,
  rectangle = function() end,
  draw = function() end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
}

package.loaded["src.render.Font"] = {
  draw = function() end,
  drawCode = function() end,
  drawBox = function() end,
}
package.loaded["src.render.HudTiles"] = {
  statusTile = function() end,
  tile = function() end,
  drawHPBar = function() end,
}
package.loaded["src.render.PaletteFX"] = {
  shader = function() return nil end,
  pal = function() return nil end,
  markTrueColor = function() end,
}
package.loaded["src.ui.Theme"] = { cursor = 0, cursorHollow = 0 }
package.loaded["src.render.Assets"] = {}
package.loaded["src.world.FieldDefaults"] = {}
package.loaded["src.world.Map"] = {}
package.loaded["src.mods.Runtime"] = { wantsHook = function() return false end }
package.loaded["src.ui.Screens"] = {}
package.loaded["src.core.Logger"] = { warn = function() end }

local Status = require("src.battle.Status")

-- a mod's registered status translation, same shape mod.content.statuses:
-- patch(id, { label = ..., hudLabel = ... }) merges into Data.statuses
local function moddedStatuses()
  local statuses = {}
  for id, record in pairs(Status.RECORDS) do statuses[id] = record end
  statuses.PSN = { id = "PSN", label = "PSN", hudLabel = "TOX" }
  return statuses
end

local Font = package.loaded["src.render.Font"]
local drawn
local origDraw = Font.draw
Font.draw = function(text, x, y)
  drawn[#drawn + 1] = { text = text, x = x, y = y }
  return origDraw(text, x, y)
end

local function mkDef()
  return { name = "BULBASAUR", dex = 1, types = { "GRASS" } }
end

local function mkMon(status)
  return {
    nickname = "SAUR", species = "BULBASAUR", level = 5,
    hp = 10, stats = { hp = 10, attack = 5, defense = 5, speed = 5, special = 5 },
    status = status,
  }
end

-- ---- SummaryMenu: page 1's STATUS/ line (~line 148-151) ----
do
  local SummaryMenu = assert(loadfile("src/ui/SummaryMenu.lua"))()
  local game = {
    data = { pokemon = { BULBASAUR = mkDef() }, statuses = moddedStatuses() },
    save = { player = { id = 1, name = "RED" } },
  }
  local menu = setmetatable(
    { game = game, mon = mkMon("PSN"), page = 1 }, SummaryMenu)
  drawn = {}
  menu:draw()
  local statusDraw
  for _, d in ipairs(drawn) do
    if d.x == 128 and d.y == 48 then statusDraw = d end
  end
  T.check(statusDraw ~= nil, "SummaryMenu draws a status label at (128,48)")
  T.eq(statusDraw.text, "TOX",
    "SummaryMenu draws the mod-patched hudLabel, not the raw status id")
end

-- vanilla (no mod): falls back to the plain id, same as before the fix
do
  local SummaryMenu = assert(loadfile("src/ui/SummaryMenu.lua"))()
  local game = {
    data = { pokemon = { BULBASAUR = mkDef() }, statuses = nil },
    save = { player = { id = 1, name = "RED" } },
  }
  local menu = setmetatable(
    { game = game, mon = mkMon("PSN"), page = 1 }, SummaryMenu)
  drawn = {}
  menu:draw()
  local statusDraw
  for _, d in ipairs(drawn) do
    if d.x == 128 and d.y == 48 then statusDraw = d end
  end
  T.eq(statusDraw.text, "PSN",
    "SummaryMenu still shows the vanilla PSN label with no mod loaded")
end

-- ---- PartyMenu: the roster row's status column (~line 824-827) ----
do
  local PartyMenu = assert(loadfile("src/ui/PartyMenu.lua"))()
  PartyMenu.drawIcon = function() end
  local game = {
    data = { pokemon = { BULBASAUR = mkDef() }, statuses = moddedStatuses(),
      text = {} },
    save = { party = { mkMon("PSN") } },
  }
  local list = setmetatable({ game = game, index = 1 }, PartyMenu)
  drawn = {}
  list:draw()
  local statusDraw
  for _, d in ipairs(drawn) do
    if d.x == 136 then statusDraw = d end
  end
  T.check(statusDraw ~= nil, "PartyMenu draws a status label at x=136")
  T.eq(statusDraw.text, "TOX",
    "PartyMenu draws the mod-patched hudLabel, not the raw status id")
end

-- ---- real Registry:patch, not a hand-built table: a label-only patch (the
-- shape a translation mod would send for every one of the 5 vanilla
-- statuses) must reach the HUD despite the vanilla record already
-- defining hudLabel ----
do
  local Registry = require("src.mods.Registry")
  local reg = Registry.new("statuses", { semantics = "record", target = "statuses" })
  reg.base = function() return Status.RECORDS end
  local LABEL_ONLY_PATCH = { SLP = "SOM", FRZ = "GEL", PSN = "PSN", BRN = "BRU", PAR = "PAR" }
  for id, translated in pairs(LABEL_ONLY_PATCH) do
    reg:patch(id, { label = translated }, "mod")
  end
  local merged = {}
  for id in pairs(Status.RECORDS) do merged[id] = reg:get(id) end
  for id, translated in pairs(LABEL_ONLY_PATCH) do
    T.eq(Status.hudLabelFor(merged, id), translated,
      "a label-only mod patch on " .. id .. " reaches the HUD label")
  end
end

T.finish("status_abbreviation_translation_test")

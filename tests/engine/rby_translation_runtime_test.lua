-- Runtime coverage for the RBY translation seams backed by dynamic ROM data.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local drawn = {}
package.loaded["src.render.Font"] = {
  draw = function(text, x, y)
    drawn[#drawn + 1] = { text = text, x = x, y = y }
  end,
  drawBox = function() end,
  drawCode = function() end,
  width = function(text) return #text * 8 end,
  split = function(text)
    local spans = {}
    for i = 1, #text do spans[i] = { from = i, to = i, code = text:byte(i) } end
    return spans
  end,
  spansFitting = function(spans, pixels)
    return math.min(#spans, math.floor(pixels / 8))
  end,
}
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
}
local pushed
package.loaded["src.render.TextBox"] = {
  new = function(_, text) return { text = text } end,
}

local Strings = require("src.core.Strings")
Strings.load({ strings = {
  ["PALLET TOWN"] = "BOURG PALETTE",
  ["To %s"] = "Vers %s",
  ["FLY TO?"] = "VOLER VERS?",
  ["VOLER VERS?"] = "DOUBLE LOOKUP",
  ["ITEMS"] = "OBJETS",
  ["OBJETS"] = "DOUBLE LOOKUP",
  ["DIRECTOR"] = "RÉALISATEUR",
  ["T H E  E N D"] = "F I N",
  ["No.%03d"] = "N°%03d",
  ["IDNo.%05d"] = "ID n°%05d",
  ["POKéMON BLUE"] = "BLEU",
  ["PIKACHU'S BEACH"] = "PLAGE",
  ["BILL'S PC"] = "PC DE LÉO",
  ["%s's PC"] = "PC DE %s",
  ["PC DE RED"] = "DOUBLE LOOKUP",
} })

-- TownMap keeps the English source for ROUTE classification and translates
-- only the rendered banner, including the fly prefix.
local TownMap = require("src.ui.TownMap")
local map = setmetatable({ fly = false }, TownMap)
T.eq(map:bannerText({ name = "PALLET TOWN" }), "BOURG PALETTE",
  "town names pass through Strings at draw time")
map.fly = true
T.eq(map:bannerText({ name = "PALLET TOWN" }), "Vers BOURG PALETTE",
  "the composed fly banner translates its prefix and destination")

-- Exercise the actual grid/fly draw path: the old fixed "To" at x=0 plus
-- destination at x=24 overlapped as soon as the prefix was wider than two
-- glyphs.  It is now one reorderable format lookup and one draw call.
local grid = setmetatable({
  game = { data = { pokemon = {} } },
  mode = "grid",
  bg = { map = {} },
  locs = { { name = "PALLET TOWN", x = 1, y = 1 } },
  sel = 1,
  fly = true,
  blink = 0,
  drawFlyArrows = function() end,
}, TownMap)
drawn = {}
grid:draw()
local banner = {}
for _, entry in ipairs(drawn) do
  if entry.y == 0 then banner[#banner + 1] = entry end
end
T.eq(#banner, 1, "grid/fly draws one composed destination banner")
T.eq(banner[1] and banner[1].text, "Vers BOURG PALETTE",
  "grid/fly uses the reorderable To %s translation")
T.eq(banner[1] and banner[1].x, 0,
  "the composed grid/fly banner starts at the strip's left edge")
T.check(banner[1] and banner[1].x + package.loaded["src.render.Font"]
    .width(banner[1].text) <= 144,
  "the grid/fly banner does not overlap its arrow tiles")

-- The standalone FlyMenu has the same dynamic map-name path as TownMap.
local realMap = package.loaded["src.world.Map"]
package.loaded["src.ui.ListMenu"] = {
  new = function(_, title, items, opts)
    return {
      title = title, kind = (opts and opts.kind) or title, items = items,
      rows = 6, index = 1, scroll = 0, update = function() end,
    }
  end,
}
package.loaded["src.world.Map"] = { isFlyTown = function() return true end }
local FlyMenu = assert(loadfile("src/ui/FlyMenu.lua"))()
local fly = FlyMenu.new({
  data = {
    field = { flyOrder = { "PALLET_TOWN" } },
    maps = { PALLET_TOWN = {} },
  },
  save = { visited = { PALLET_TOWN = true } },
})
T.eq(fly.title, "FLY TO?",
  "FlyMenu preserves the source title for ListMenu hooks")
T.eq(fly.kind, "FLY TO?",
  "FlyMenu preserves the source kind derived by ListMenu")
T.eq(Strings(fly.title), "VOLER VERS?",
  "ListMenu's draw-time lookup translates once, not twice")
T.eq(fly.items[1] and fly.items[1].label, "BOURG PALETTE",
  "FlyMenu translates dynamic destination names")

local BagMenu = assert(loadfile("src/ui/BagMenu.lua"))()
local bag = BagMenu.new({
  data = { items = {} },
  save = { inventory = {}, bagOrder = {} },
})
T.eq(bag.title, "ITEMS", "BagMenu preserves its source title")
T.eq(bag.kind, "bag", "BagMenu preserves its stable explicit kind")
T.eq(Strings(bag.title), "OBJETS",
  "BagMenu's draw-time lookup translates once, not twice")
package.loaded["src.world.Map"] = realMap

-- Credits lines come from field.credits and therefore need a runtime lookup.
local Credits = require("src.ui.Credits")
local credits = setmetatable({}, Credits)
drawn = {}
credits:drawPage({ lines = { { text = "DIRECTOR", column = 3 } } }, 0, 1)
T.eq(drawn[1] and drawn[1].text, "RÉALISATEUR",
  "extracted credits text passes through Strings before drawing")
credits.theEnd = { display = "T H E  E N D" }
credits.endImg = nil
drawn = {}
credits:drawTheEnd()
T.eq(drawn[1] and drawn[1].text, "F I N",
  "the extracted THE END fallback is translated")
T.eq(drawn[1] and drawn[1].x, 60,
  "the translated THE END fallback is centered from Font.width")

-- Text-only title fallbacks are centered from their translated pixel width,
-- rather than from the English source's hard-coded tile count.
local TitleState = assert(loadfile("src/ui/TitleState.lua"))()
local title = setmetatable({
  game = {}, menuOpen = false, scy = 0, yellowLayout = false,
  phase = "loop", logo = nil, yellow = false, blue = true, version = nil,
  player = nil, playerQuads = nil, scrollPhase = "hold", monOffset = 0,
  currentSprite = function() return nil end,
  drawCopyright = function() end,
}, TitleState)
drawn = {}
title:draw()
T.eq(drawn[1] and drawn[1].text, "BLEU",
  "the translated title fallback is drawn")
T.eq(drawn[1] and drawn[1].x, 64,
  "the translated title fallback is centered from Font.width")

local SurfingMinigame = assert(loadfile("src/ui/SurfingMinigame.lua"))()
local surfing = setmetatable({
  titleBg = nil, introPikaX = 0,
  drawIntroPikachu = function() end,
}, SurfingMinigame)
drawn = {}
surfing:drawTitleScreen()
T.eq(drawn[1] and drawn[1].text, "PLAGE",
  "the translated beach title fallback is drawn")
T.eq(drawn[1] and drawn[1].x, 60,
  "the translated beach title fallback is centered from Font.width")

-- The trade info formats keep their numeric padding after translation.
local TradeAnim = require("src.ui.TradeAnim")
local trade = setmetatable({ game = { data = { pokemon = {
  PIKACHU = { name = "PIKACHU", dex = 25 },
} } } }, TradeAnim)
drawn = {}
trade:drawMonInfo({ species = "PIKACHU" }, "RED", 42, 0)
T.eq(drawn[1] and drawn[1].text, "N°025",
  "translated Pokédex number format keeps zero padding")
T.eq(drawn[4] and drawn[4].text, "ID n°00042",
  "translated trainer ID format keeps zero padding")

-- Oak's demo step must resolve the ROM label, not translate the label name.
local OakSpeech = require("src.ui.OakSpeech")
local oakGame = {
  data = { text = { _OakSpeechText2A = "MONDE TRADUIT" } },
  stack = { push = function(_, state) pushed = state end },
}
local oak = setmetatable({
  game = oakGame,
  demoSpecies = "NIDORINO",
  demoPic = {},
  demoTrueColor = false,
  revealPic = function(_, _, done) done() end,
  advance = function() end,
}, OakSpeech)
pushed = nil
oak:runStep({ kind = "demo" })
T.eq(pushed and pushed.text, "MONDE TRADUIT",
  "Oak demo resolves _OakSpeechText2A through game.data.text")

-- ui.pc.items must inspect stable English labels even with a live catalog;
-- only the final Menu rows are localized.  This is also the runtime coverage
-- for the dynamic player's-PC format.
local function setUpvalue(fn, name, value)
  local i = 1
  while true do
    local found = debug.getupvalue(fn, i)
    if not found then return false end
    if found == name then debug.setupvalue(fn, i, value); return true end
    i = i + 1
  end
end

local Overworld = require("src.world.OverworldController")
local hookLabels, menuItems
local pcGame = {
  data = { text = {} },
  save = {
    flags = { EVENT_MET_BILL = true },
    player = { name = "RED" }, hallOfFame = {},
  },
  stack = { push = function() end },
}
local pcRuntime = {
  call = function(name, _, _, items)
    T.eq(name, "ui.pc.items", "the PC rows use the documented hook")
    hookLabels = {}
    for i, item in ipairs(items) do hookLabels[i] = item.label end
    return items
  end,
}
package.loaded["src.ui.Menu"] = {
  new = function(_, items) menuItems = items; return { items = items } end,
}
T.check(setUpvalue(Overworld.openPC, "Game", pcGame),
  "openPC Game upvalue is injectable")
T.check(setUpvalue(Overworld.openPC, "Runtime", pcRuntime),
  "openPC Runtime upvalue is injectable")
T.check(setUpvalue(Overworld.openPC, "TextBox", {
  new = function(_, text, onDone) return { text = text, onDone = onDone } end,
}), "openPC TextBox upvalue is injectable")
local pc = setmetatable({}, { __index = Overworld })
pc:openPC()
T.eq(hookLabels[1], "BILL'S PC",
  "ui.pc.items sees the stable box-PC source label")
T.eq(hookLabels[2], "RED's PC",
  "ui.pc.items sees the stable player-PC source label")
T.eq(menuItems[1].label, "PC DE LÉO",
  "the retained box-PC row is translated after the hook")
T.eq(menuItems[2].label, "PC DE RED",
  "the dynamic player-PC format is translated exactly once after the hook")

-- Keep a ROM-free guard in the normal engine tier as well as the Python test
-- that runs modkit's actual harvester.  These literals must stay at static
-- call sites; wrapping only a variable would work at runtime but disappear
-- from a freshly generated translation worksheet.
local function source(path)
  local file = assert(io.open(path, "r"))
  local body = file:read("*a")
  file:close()
  return body
end

local harvestCalls = {
  ["src/ui/BagMenu.lua"] = {
    'Strings.source("ITEMS")',
  },
  ["src/ui/BoxMenu.lua"] = {
    'Strings("WITHDRAW")', 'Strings("DEPOSIT")',
    'Strings("The party is full!")',
  },
  ["src/ui/Diploma.lua"] = {
    'Strings.source("Congrats! This")',
    'Strings.source("diploma certifies")',
  },
  ["src/ui/FlyMenu.lua"] = { 'Strings.source("FLY TO?")' },
  ["src/ui/TradeAnim.lua"] = {
    'Strings("No.%03d",', 'Strings("IDNo.%05d",',
  },
  ["src/ui/TrainerCard.lua"] = {
    'Strings("MONEY/¥%d",', 'Strings("TIME/%3d:%02d",',
  },
  ["src/world/OverworldController.lua"] = {
    'Strings("BILL\'S PC")', 'Strings("%s\'s PC",', 'Strings("HEAL")',
  },
}
for path, calls in pairs(harvestCalls) do
  local body = source(path)
  for _, call in ipairs(calls) do
    T.check(body:find(call, 1, true) ~= nil,
      path .. " keeps harvestable " .. call)
  end
end

Strings.load(nil)
T.finish()

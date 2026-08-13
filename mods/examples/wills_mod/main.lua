-- Generated self-contained release entry: installed mods do not extend Lua package.path.

local Names = {}

local overrides = {
  MT_MOON = "MT. MOON",
  DIGLETTS_CAVE = "DIGLETT's CAVE",
  POKEMON_TOWER = "POKéMON TOWER",
  POKEMON_MANSION = "POKéMON MANSION",
  POKEMON_LEAGUE = "POKéMON LEAGUE",
}

function Names.map(mapId)
  local base, suffix = mapId:match("^(.-)(_B?%d+F)$")
  if base then
    return (overrides[base] or base:gsub("_", " ")) .. suffix:gsub("_", " ")
  end
  return overrides[mapId] or mapId:gsub("_", " ")
end

local Model = {}

local function hasSlots(group)
  return type(group) == "table"
    and type(group.slots) == "table"
    and #group.slots > 0
    and (group.rate or 0) > 0
end

local function floorKey(mapId)
  local floor = mapId:match("_(%d+)F$")
  if floor then return tonumber(floor) end
  local basement = mapId:match("_B(%d+)F$")
  if basement then return 100 + tonumber(basement) end
  return 50
end

local function methodsFor(data, definition)
  local methods = {}
  if hasSlots(definition.grass) then
    methods.land = Model.summarizeMethod(definition.grass, data.pokemon,
      definition.grass.buckets or (data.constants or {}).encounterBuckets)
  end
  if hasSlots(definition.water) then
    methods.water = Model.summarizeMethod(definition.water, data.pokemon,
      definition.water.buckets or (data.constants or {}).encounterBuckets)
  end
  return methods
end

function Model.mapSummary(data, mapId)
  if not mapId then return nil end
  local definition = ((data or {}).encounters or {})[mapId]
  if not definition then return nil end
  local methods = methodsFor(data, definition)
  if not (methods.land or methods.water) then return nil end
  return methods
end

function Model.summarizeMethod(method, pokemon, buckets)
  local rate = method.rate or 0
  local total = (buckets and buckets[#buckets]) or 256
  if total <= 0 then total = 256 end
  local bySpecies, species = {}, {}

  for index, slot in ipairs(method.slots or {}) do
    local previous = (buckets and buckets[index - 1]) or ((index - 1) * total / #(method.slots or {}))
    local cumulative = (buckets and buckets[index]) or (index * total / #(method.slots or {}))
    local conditionalOdds = math.max(0, cumulative - previous) / total
    local speciesId, level = slot.species, slot.level
    if speciesId and level then
      local row = bySpecies[speciesId]
      if not row then
        local info = (pokemon or {})[speciesId] or {}
        row = {
          speciesId = speciesId,
          name = info.name or speciesId,
          minLevel = level,
          maxLevel = level,
          levels = {},
          levelsByValue = {},
        }
        bySpecies[speciesId] = row
        species[#species + 1] = row
      end
      row.minLevel = math.min(row.minLevel, level)
      row.maxLevel = math.max(row.maxLevel, level)
      local levelRow = row.levelsByValue[level]
      if not levelRow then
        levelRow = { level = level, slotCount = 0, conditionalOdds = 0, perStepOdds = 0 }
        row.levelsByValue[level] = levelRow
        row.levels[#row.levels + 1] = levelRow
      end
      levelRow.slotCount = levelRow.slotCount + 1
      levelRow.conditionalOdds = levelRow.conditionalOdds + conditionalOdds
      levelRow.perStepOdds = levelRow.conditionalOdds * rate / 256
    end
  end

  for _, row in ipairs(species) do
    row.levelsByValue = nil
    table.sort(row.levels, function(a, b) return a.level < b.level end)
  end
  table.sort(species, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.speciesId < b.speciesId
  end)
  return { rate = rate, species = species }
end

function Model.buildAreas(data)
  local areasByKey, areas = {}, {}
  local encounters = data.encounters or {}
  local locations = ((data.townMap or {}).locations) or {}

  for mapId, definition in pairs(encounters) do
    if hasSlots(definition.grass) or hasSlots(definition.water) then
      local location = locations[mapId]
      local areaName = location and location.name or "OTHER AREAS"
      local key = location
        and table.concat({ location.x or -1, location.y or -1, areaName }, ":")
        or "OTHER:" .. mapId
      local area = areasByKey[key]
      if not area then
        area = { name = areaName, x = location and location.x, y = location and location.y, sources = {} }
        areasByKey[key] = area
        areas[#areas + 1] = area
      end
      local methods = methodsFor(data, definition)
      area.sources[#area.sources + 1] = {
        mapId = mapId,
        label = Names.map(mapId),
        encounters = definition,
        methods = methods,
      }
    end
  end

  for _, area in ipairs(areas) do
    table.sort(area.sources, function(a, b)
      local aFloor, bFloor = floorKey(a.mapId), floorKey(b.mapId)
      if aFloor ~= bFloor then return aFloor < bFloor end
      return a.mapId < b.mapId
    end)
  end
  table.sort(areas, function(a, b)
    if a.y and b.y and a.y ~= b.y then return a.y < b.y end
    if a.x and b.x and a.x ~= b.x then return a.x < b.x end
    return a.name < b.name
  end)

  return areas
end

local Screens = {}

local function guideData(game)
  local data = (game and game.data) or {}
  return {
    encounters = data.encounters or {},
    townMap = (data.field or {}).townMap or {},
    pokemon = data.pokemon or {},
    constants = data.constants or {},
  }
end

local function levelRange(species)
  if species.minLevel == species.maxLevel then return "Lv. " .. species.minLevel end
  return "Lv. " .. species.minLevel .. "-" .. species.maxLevel
end

local function percent(value)
  return string.format("%.2f%%", (value or 0) * 100)
end

function Screens.newAreas(mod, game)
  local areas = Model.buildAreas(guideData(game))
  local items = {}
  for _, area in ipairs(areas) do
    items[#items + 1] = {
      label = area.name,
      right = #area.sources .. " MAPS",
      value = area,
    }
  end
  return mod.ui.ListMenu.new(game, "ENCOUNTERS", items, {
    pageJump = true,
    onChoose = function(item)
      mod.ui.push(game, "EncounterGuideArea", item.value)
    end,
  })
end

function Screens.newArea(mod, game, area)
  local items = {}
  for _, source in ipairs((area or {}).sources or {}) do
    local methods = {}
    if source.methods.land then methods[#methods + 1] = "LAND" end
    if source.methods.water then methods[#methods + 1] = "WATER" end
    items[#items + 1] = {
      label = "-- " .. source.label,
      right = table.concat(methods, "/"),
      value = source,
    }
  end
  return mod.ui.ListMenu.new(game, (area or {}).name or "AREA", items, {
    pageJump = true,
    onChoose = function(item)
      mod.ui.push(game, "EncounterGuideSource", item.value)
    end,
  })
end

function Screens.newSource(mod, game, source)
  local items = {}
  for _, row in ipairs({ { key = "land", label = "LAND" }, { key = "water", label = "WATER" } }) do
    local summary = source and source.methods and source.methods[row.key]
    if summary then
      items[#items + 1] = {
        label = row.label,
        right = summary.rate .. "/256",
        value = row.key,
      }
    end
  end
  return mod.ui.ListMenu.new(game, (source and source.label) or "SOURCE", items, {
    onChoose = function(item)
      mod.ui.push(game, "EncounterGuideMethod", source, item.value)
    end,
  })
end

function Screens.newMethod(mod, game, source, methodName)
  local summary = source and source.methods and source.methods[methodName] or { species = {} }
  local owned = (((game or {}).save or {}).pokedex or {}).owned or {}
  local items = {}
  for _, species in ipairs(summary.species or {}) do
    items[#items + 1] = {
      label = species.name,
      right = levelRange(species),
      value = species,
      ball = owned[species.speciesId] == true,
    }
  end
  local title = ((source and source.label) or "SOURCE") .. " " .. (methodName == "water" and "WATER" or "LAND")
  return mod.ui.ListMenu.new(game, title, items, {
    pageJump = true,
    onChoose = function(item)
      mod.ui.push(game, "EncounterGuideSpecies", source, methodName, item.value)
    end,
  })
end

function Screens.newSpecies(mod, game, source, methodName, species)
  local items = {}
  for _, level in ipairs((species or {}).levels or {}) do
    items[#items + 1] = {
      label = "Lv. " .. level.level,
      right = percent(level.perStepOdds),
      value = level,
    }
  end
  return mod.ui.ListMenu.new(game, (species and species.name) or "POKéMON", items, {
    footer = ((source and source.label) or "SOURCE") .. " " .. (methodName == "water" and "WATER" or "LAND"),
  })
end

local MapScreen = {}
MapScreen.__index = MapScreen
MapScreen.isOpaque = true

local function loadBackground(graphics, game)
  local townMap = (((game or {}).data or {}).field or {}).townMap or {}
  local definition = townMap.background
  if not (definition and definition.map and definition.tiles and definition.tiles.path) then return nil end

  local ok, image = pcall(graphics.newImage, definition.tiles.path)
  if not ok then return nil end
  local width, height = image:getDimensions()
  local quads = {}
  for index = 0, (width / 8) * (height / 8) - 1 do
    quads[index] = graphics.newQuad(
      (index % (width / 8)) * 8,
      math.floor(index / (width / 8)) * 8,
      8, 8, width, height
    )
  end

  local cursor
  if definition.cursor and definition.cursor.path then
    local cursorOk, cursorImage = pcall(graphics.newImage, definition.cursor.path)
    if cursorOk then cursor = cursorImage end
  end
  return { image = image, quads = quads, map = definition.map, cursor = cursor }
end

function MapScreen.playerPosition(game, currentMapId)
  if not currentMapId then return nil end
  local townMap = (((game or {}).data or {}).field or {}).townMap or {}
  local location = (townMap.locations or {})[currentMapId]
  if location and location.x ~= nil and location.y ~= nil then
    return { x = location.x, y = location.y }
  end
  return nil
end

function MapScreen.new(mod, game, areas, deps)
  deps = deps or {}
  local self = setmetatable({}, MapScreen)
  self.mod = mod
  self.game = game
  self.graphics = deps.graphics or love.graphics
  self.font = deps.font or mod.ui.Font
  self.locations = {}
  for _, area in ipairs(areas or {}) do
    if area.x ~= nil and area.y ~= nil then self.locations[#self.locations + 1] = area end
  end
  self.selected = 1
  local currentMapId = game.overworld and game.overworld.map and game.overworld.map.id
  local townMap = (((game or {}).data or {}).field or {}).townMap or {}
  local current = currentMapId and (townMap.locations or {})[currentMapId]
  if current then
    for index, location in ipairs(self.locations) do
      if location.x == current.x and location.y == current.y then
        self.selected = index
        break
      end
    end
  end
  self.player = MapScreen.playerPosition(game, currentMapId)
  self.blink = 0
  self.background = loadBackground(self.graphics, game)
  return self
end

function MapScreen:move(dx, dy)
  local current = self.locations[self.selected]
  if not current then return end
  local best, bestScore
  for index, location in ipairs(self.locations) do
    if index ~= self.selected then
      local deltaX, deltaY = location.x - current.x, location.y - current.y
      local forward = deltaX * dx + deltaY * dy
      if forward > 0 then
        local sideways = math.abs(deltaX * dy) + math.abs(deltaY * dx)
        local score = forward + sideways * 3
        if not best or score < bestScore then
          best, bestScore = index, score
        end
      end
    end
  end
  if best then self.selected = best end
end

function MapScreen:update(dt)
  self.blink = (self.blink + 1) % 32
  local input = self.game.input
  if input:wasPressed("b") then
    self.game.stack:pop()
    return
  elseif input:wasPressed("select") then
    self.mod.ui.push(self.game, "EncounterGuideAreas")
    return
  elseif input:wasPressed("up") then self:move(0, -1)
  elseif input:wasPressed("down") then self:move(0, 1)
  elseif input:wasPressed("left") then self:move(-1, 0)
  elseif input:wasPressed("right") then self:move(1, 0)
  elseif input:wasPressed("a") then
    local location = self.locations[self.selected]
    if location then self.mod.ui.push(self.game, "EncounterGuideArea", location) end
  end
end

function MapScreen:draw()
  local graphics = self.graphics
  graphics.setColor(1, 1, 1, 1)
  graphics.rectangle("fill", 0, 0, 160, 144)

  if self.background then
    for index, tile in ipairs(self.background.map) do
      local column = (index - 1) % 20
      local row = math.floor((index - 1) / 20)
      graphics.draw(self.background.image, self.background.quads[tile], column * 8, row * 8)
    end
  end

  local location = self.locations[self.selected]
  graphics.setColor(0, 0, 0, 1)
  for _, marker in ipairs(self.locations) do
    local markerX, markerY = marker.x * 8 + 16, marker.y * 8 + 8
    graphics.rectangle("fill", markerX + 2, markerY + 2, 4, 4)
  end

  if self.player and self.blink < 16 then
    local playerX, playerY = self.player.x * 8 + 16, self.player.y * 8 + 8
    graphics.setColor(0, 0, 0, 1)
    graphics.rectangle("fill", playerX + 1, playerY + 1, 6, 6)
    graphics.setColor(1, 1, 1, 1)
    graphics.rectangle("fill", playerX + 2, playerY + 2, 4, 4)
  end

  if location then
    local x, y = location.x * 8 + 16, location.y * 8 + 8
    if self.background and self.background.cursor then
      graphics.draw(self.background.cursor, x - 4, y - 4)
    else
      graphics.setColor(0, 0, 0, 1)
      graphics.rectangle("line", x + 0.5, y + 0.5, 7, 7)
    end
    graphics.setColor(1, 1, 1, 1)
    graphics.rectangle("fill", 0, 0, 160, 8)
    graphics.setColor(0, 0, 0, 1)
    self.font.draw(location.name, 8, 0)
  end
  graphics.setColor(1, 1, 1, 1)
  graphics.rectangle("fill", 0, 136, 160, 8)
  graphics.setColor(0, 0, 0, 1)
  self.font.draw("A:OPEN  SELECT:LIST", 4, 136)
  graphics.setColor(1, 1, 1, 1)
end

local Hud = {}
Hud.__index = Hud

local MAX_LINES = 6
local MODES = { "auto", "always", "off" }
local SIZES = { small = 1, medium = 1.5, large = 2 }
local BALL_SPACE = 15 -- blank glyph (8) + gap (3) + half the ball (4)

local function isHeader(record)
  return record.text == "LAND" or record.text == "WATER"
end

local function levelRange(species)
  if species.minLevel == species.maxLevel then return tostring(species.minLevel) end
  return species.minLevel .. "-" .. species.maxLevel
end

local function speciesRecords(summary, owned)
  local records = {}
  for _, species in ipairs((summary or {}).species or {}) do
    records[#records + 1] = {
      text = species.name .. " " .. levelRange(species),
      owned = owned[species.speciesId] == true,
    }
  end
  return records
end

-- Pure formatting: honest LAND/WATER labels, exact level ranges, capped box.
-- method "land"|"water" filters to one table (the AUTO tile mode) and drops
-- the header; nil shows both with headers.
function Hud.linesFor(data, mapId, summarize, method)
  local summary = (summarize or Model.mapSummary)(data, mapId)
  if not summary then return nil end
  local owned = (data or {}).owned or {}
  local lines = {}
  if (method == nil or method == "land") and summary.land then
    if method == nil and summary.water then lines[#lines + 1] = { text = "LAND", owned = false } end
    for _, record in ipairs(speciesRecords(summary.land, owned)) do lines[#lines + 1] = record end
  end
  if (method == nil or method == "water") and summary.water then
    if method == nil then lines[#lines + 1] = { text = "WATER", owned = false } end
    for _, record in ipairs(speciesRecords(summary.water, owned)) do lines[#lines + 1] = record end
  end
  if #lines == 0 then return nil end
  if #lines > MAX_LINES then
    local kept = {}
    local index = 1
    while #kept < MAX_LINES - 1 and index <= #lines do
      local record = lines[index]
      if isHeader(record) and #kept + 3 > MAX_LINES then break end
      kept[#kept + 1] = record
      index = index + 1
    end
    local hidden = 0
    for j = index, #lines do
      if not isHeader(lines[j]) then hidden = hidden + 1 end
    end
    if hidden > 0 then kept[#kept + 1] = { text = "+" .. hidden .. " MORE", owned = false } end
    lines = kept
  end
  return lines
end

-- The HUD exists only while the overworld is the top state: walking and
-- dialogue yes; menus, battles, and the title screen no.
function Hud.activeMapId(game)
  local stack = game and game.stack
  local states = stack and stack.states
  local top = states and states[#states]
  if not (top and top.isOverworld) then return nil end
  local overworld = game and game.overworld
  return overworld and overworld.map and overworld.map.id
end

-- Which encounter table the tile under the player offers, or nil.
-- Uses the live Map's own checks so it can never drift from the engine.
function Hud.tileAt(game, x, y)
  local overworld = game and game.overworld
  local map = overworld and overworld.map
  if not map or not map.isGrassCell or not map.isWaterCell then return nil end
  if map:isGrassCell(x, y) then return "land" end
  if map:isWaterCell(x, y) then return "water" end
  return nil
end

function Hud.new(mod, game, deps)
  deps = deps or {}
  local self = setmetatable({}, Hud)
  self.mod = mod
  self.game = game
  self.graphics = deps.graphics or love.graphics
  self.font = deps.font or mod.ui.Font
  self.window = deps.window or love.graphics.getDimensions
  self.tile = deps.tile
  self.keyDown = deps.keyDown
  self.summarize = deps.summarize
  self.cache = { key = nil, lines = nil }
  self.keyHeld = false
  return self
end

function Hud:currentMode()
  local options = (self.game and self.game.save and self.game.save.options) or {}
  local mode = options.encounterGuideHud
  for _, candidate in ipairs(MODES) do
    if mode == candidate then return mode end
  end
  return "auto"
end

function Hud:size()
  local options = (self.game and self.game.save and self.game.save.options) or {}
  local size = options.encounterGuideSize
  if SIZES[size] then return size end
  return "small"
end

function Hud:sizeFactor()
  return SIZES[self:size()] or 1
end

-- H cycles AUTO -> ALWAYS -> OFF with edge detection; the mode persists to
-- save.options so the options menu and the key stay in sync.
function Hud:handleToggle()
  local keyDown = self.keyDown or love.keyboard.isDown
  local held = keyDown ~= nil and keyDown("h") or false
  if held and not self.keyHeld then
    self.keyHeld = true
    local current = self:currentMode()
    local index = 1
    for i, candidate in ipairs(MODES) do
      if candidate == current then index = i break end
    end
    local nextMode = MODES[index % #MODES + 1]
    local options = (self.game.save or {}).options
    if options then options.encounterGuideHud = nextMode end
    self.cache.key = nil
  end
  if not held then self.keyHeld = false end
end

function Hud:tileAtPlayer()
  local overworld = (self.game or {}).overworld
  local player = overworld and overworld.player
  local x, y = player and player.cellX, player and player.cellY
  if not x or not y then return nil end
  return (self.tile or Hud.tileAt)(self.game, x, y)
end

function Hud:refresh()
  local mapId = Hud.activeMapId(self.game)
  if not mapId then
    self.cache.key, self.cache.lines = nil, nil
    return
  end
  local mode = self:currentMode()
  local method
  if mode == "off" then
    method = "none"
  elseif mode == "auto" then
    method = self:tileAtPlayer() or "none"
  end
  local key = tostring(mapId) .. ":" .. tostring(method or "both")
  if self.cache.key == key then return end
  local game = self.game
  local data = {
    encounters = (game.data or {}).encounters or {},
    townMap = ((game.data or {}).field or {}).townMap or {},
    pokemon = (game.data or {}).pokemon or {},
    constants = (game.data or {}).constants or {},
    owned = ((game.save or {}).pokedex or {}).owned or {},
  }
  self.cache.key = key
  if method == "none" then
    self.cache.lines = nil
    return
  end
  self.cache.lines = Hud.linesFor(data, mapId, self.summarize, method)
end

function Hud:draw(viewport)
  self:handleToggle()
  self:refresh()
  local lines = self.cache.lines
  if not lines or #lines == 0 then return end
  self:drawBox(lines)
end

-- Screen-space overlay: reset the transform like the engine's own touch
-- overlay (a render pipeline such as a voxel mod can leave its camera
-- transform active at render.hud time) and anchor to the window's top-right.
-- The SMALL geometry is the base unit; MEDIUM/LARGE scale the whole box.
function Hud:drawBox(lines)
  local graphics = self.graphics
  local font = self.font
  local maxWidth, anyOwned = 0, false
  for _, record in ipairs(lines) do
    local width = font.width(record.text)
    if width > maxWidth then maxWidth = width end
    if record.owned then anyOwned = true end
  end
  if anyOwned then maxWidth = maxWidth + BALL_SPACE end
  local boxWidth = maxWidth + 4
  local boxHeight = #lines * 8 + 4
  local windowWidth, windowHeight = self.window()
  local factor = self:sizeFactor()
  graphics.push("all")
  graphics.origin()
  graphics.scale(factor, factor)
  local originX = windowWidth / factor - boxWidth - 2
  local originY = 2
  graphics.setColor(1, 1, 1, 1)
  graphics.rectangle("fill", originX, originY, boxWidth, boxHeight)
  graphics.setColor(0, 0, 0, 1)
  graphics.rectangle("line", originX + 0.5, originY + 0.5, boxWidth - 1, boxHeight - 1)
  for index, record in ipairs(lines) do
    local x = originX + 2
    local y = originY + 2 + (index - 1) * 8
    font.draw(record.text, x, y)
    if record.owned then
      -- the same owned-ball marker the engine's ListMenu draws
      local bx = x + font.width(record.text) + 8 + 3
      local by = y + 3
      graphics.setColor(0, 0, 0, 1)
      graphics.circle("fill", bx, by, 3.5)
      graphics.setColor(1, 1, 1, 1)
      graphics.rectangle("fill", bx - 3.5, by - 0.5, 7, 1)
      graphics.circle("fill", bx, by, 1.2)
      graphics.setColor(0, 0, 0, 1)
    end
  end
  graphics.pop("all")
  graphics.setColor(1, 1, 1, 1)
end

local SCREENS = {
  map = "EncounterGuideMap",
  areas = "EncounterGuideAreas",
  area = "EncounterGuideArea",
  source = "EncounterGuideSource",
  method = "EncounterGuideMethod",
  species = "EncounterGuideSpecies",
}
local entryHud

return function(mod)
  mod.content.screens:register(SCREENS.map, {
    new = function(game)
      local areas = Model.buildAreas(guideData(game))
      local screen = MapScreen.new(mod, game, areas)
      if #screen.locations == 0 then return Screens.newAreas(mod, game) end
      return screen
    end,
  })
  mod.content.screens:register(SCREENS.areas, {
    new = function(game)
      return Screens.newAreas(mod, game)
    end,
  })
  mod.content.screens:register(SCREENS.area, {
    new = function(game, area)
      return Screens.newArea(mod, game, area)
    end,
  })
  mod.content.screens:register(SCREENS.source, {
    new = function(game, source)
      return Screens.newSource(mod, game, source)
    end,
  })
  mod.content.screens:register(SCREENS.method, {
    new = function(game, source, methodName)
      return Screens.newMethod(mod, game, source, methodName)
    end,
  })
  mod.content.screens:register(SCREENS.species, {
    new = function(game, source, methodName, species)
      return Screens.newSpecies(mod, game, source, methodName, species)
    end,
  })

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "PKMN MAP",
      onSelect = function() mod.ui.push(game, SCREENS.map) end,
    })
  end)

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    if next then next(game, viewport) end
    if not entryHud then entryHud = Hud.new(mod, game, {}) end
    entryHud:draw(viewport)
  end)

  local HUD_MODES = { "auto", "always", "off" }
  local HUD_SIZES = { "small", "medium", "large" }
  local function optionLabel(option, candidates, fallback)
    for _, candidate in ipairs(candidates) do
      if option == candidate then return candidate:upper() end
    end
    return fallback
  end
  local function cycleOption(options, key, candidates, dir)
    local current = options[key]
    local index = 1
    for i, candidate in ipairs(candidates) do
      if candidate == current then index = i break end
    end
    options[key] = candidates[((index - 1 + dir) % #candidates) + 1]
    return true
  end
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = {
      id = "encounterGuideHud",
      label = "ENC. GUIDE HUD",
      value = function(g)
        return optionLabel(((g.save or {}).options or {}).encounterGuideHud, HUD_MODES, "AUTO")
      end,
      step = function(g, dir)
        local options = (g.save or {}).options
        if not options then return false end
        return cycleOption(options, "encounterGuideHud", HUD_MODES, dir)
      end,
    }
    out[#out + 1] = {
      id = "encounterGuideSize",
      label = "ENC. GUIDE SIZE",
      value = function(g)
        return optionLabel(((g.save or {}).options or {}).encounterGuideSize, HUD_SIZES, "SMALL")
      end,
      step = function(g, dir)
        local options = (g.save or {}).options
        if not options then return false end
        return cycleOption(options, "encounterGuideSize", HUD_SIZES, dir)
      end,
    }
    return out
  end)
end

-- game3 Pokédex UI: 1:1 Authentic Pokémon FireRed / LeafGreen Pokédex System.
-- Implements:
-- 1. Table of Contents (Mode Select) with orange section headers, Seen/Owned counts, and Category Icons.
-- 2. Pokémon List (9 visible rows, №xxx, Pokéball badge, Species Name / -----, Type badges).
-- 3. Detailed Data Screen (Top white card with specs, footprint, front pic; Bottom parchment card with 3-line flavor text; [START]CRY and {A}NEXT DATA).
-- 4. Habitat Category Screen (Warm beige background, pulsing circular spotlight disc behind mon sprite, mini-page card with scanlines, side page flip arrows).
-- 5. Area Map Screen (Kanto/Sevii Town Maps with blinking route markers or AREA UNKNOWN badge).
-- 6. Size Comparison Screen (Trainer vs Mon scaling).
-- 7. Caught Registration Screen.

local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")
local Types = require("src.core.game3.battle.types")
local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local PokedexData = require("src.core.game3.pokedex_data")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local Strings = require("src.core.Strings")

local Pokedex = {}

Pokedex.open = false
Pokedex.screen = "mode_select" -- "mode_select" | "category_grid" | "ordered_list" | "action_popup" | "data" | "area" | "size" | "registration"
Pokedex.subScreenPrev = "mode_select"

-- Mode select state
Pokedex.modeCursor = 1
Pokedex.modeScroll = 0
Pokedex.MODES = {}

-- Habitat grid state
Pokedex.currentCategory = "grassland"
Pokedex.categoryPage = 1
Pokedex.categorySlot = 1
Pokedex.spotlightTimer = 0

-- Ordered list state
Pokedex.currentOrder = "numerical_kanto"
Pokedex.listCursor = 1
Pokedex.listScroll = 0

-- Context action menu state
Pokedex.actionCursor = 1
Pokedex.selectedSpecies = 1

-- Data screen state
Pokedex.dataPage = 1 -- 1: FR desc, 2: LG desc

-- Area map screen state
Pokedex.areaMapKey = "kanto"
Pokedex.areaPulseTimer = 0

-- Compatibility aliases
Pokedex.cursor = 1
Pokedex.mode = "kanto"
Pokedex.page = "list"

-- Session & Dex references
Pokedex._dex = nil
Pokedex._session = nil
Pokedex._onClose = nil
Pokedex._regSpecies = nil

local LIST_VISIBLE = 9

--- Authentic pret sCategoryPageIconCoords layout mapping:
--- 1..4 mons on page: pic coords (top-left of 64x64 front sprite), circle coords (center of 32px radius spotlight), card coords (top-left of 64x38 mini card)
local CATEGORY_PAGE_COORDS = {
  [1] = {
    { pic = { x = 88, y = 24 }, circle = { x = 120, y = 56 }, card = { x = 88, y = 88 } },
  },
  [2] = {
    { pic = { x = 24, y = 24 }, circle = { x = 56, y = 56 }, card = { x = 88, y = 24 } },
    { pic = { x = 144, y = 72 }, circle = { x = 176, y = 104 }, card = { x = 80, y = 88 } },
  },
  [3] = {
    { pic = { x = 8, y = 16 }, circle = { x = 40, y = 48 }, card = { x = 72, y = 16 } },
    { pic = { x = 88, y = 72 }, circle = { x = 120, y = 104 }, card = { x = 24, y = 88 } },
    { pic = { x = 168, y = 24 }, circle = { x = 200, y = 56 }, card = { x = 168, y = 88 } },
  },
  [4] = {
    { pic = { x = 0, y = 16 }, circle = { x = 32, y = 48 }, card = { x = 48, y = 24 } },
    { pic = { x = 56, y = 80 }, circle = { x = 88, y = 112 }, card = { x = 0, y = 96 } },
    { pic = { x = 120, y = 80 }, circle = { x = 152, y = 112 }, card = { x = 176, y = 88 } },
    { pic = { x = 176, y = 16 }, circle = { x = 208, y = 48 }, card = { x = 120, y = 32 } },
  },
}

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if type(id) == "number" then
      Audio.playSe(id)
    elseif SE and SE[id] then
      Audio.playSe(SE[id])
    end
  end)
end

local function play_cry(speciesId)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playCry then
      Audio.playCry(speciesId)
    end
  end)
end

local function species_label(sp)
  return (Pokemon.name and Pokemon.name(sp)) or Strings("POKéMON %d", sp)
end

local function build_modes(session, dex)
  local isNat = PokedexData.isNationalUnlocked(session, dex)
  local modes = {
    -- Section: POKéMON LIST
    { isHeader = true, label = Strings("POKéMON LIST") },
  }

  if isNat then
    table.insert(modes, { id = "numerical_kanto", type = "order", label = Strings("NUMERICAL MODE: KANTO"), icon = "numerical", unlocked = true })
    table.insert(modes, { id = "numerical_national", type = "order", label = Strings("NUMERICAL MODE: NATIONAL"), icon = "numerical", unlocked = true })
  else
    table.insert(modes, { id = "numerical_kanto", type = "order", label = Strings("NUMERICAL MODE"), icon = "numerical", unlocked = true })
  end

  -- Section: POKéMON HABITATS
  table.insert(modes, { isHeader = true, label = Strings("POKéMON HABITATS") })
  local habitats = {
    { id = "grassland", label = Strings("Grassland POKéMON"), icon = "grassland" },
    { id = "forest", label = Strings("Forest POKéMON"), icon = "forest" },
    { id = "waters_edge", label = Strings("Water's-edge POKéMON"), icon = "waters_edge" },
    { id = "sea", label = Strings("Sea POKéMON"), icon = "sea" },
    { id = "cave", label = Strings("Cave POKéMON"), icon = "cave" },
    { id = "mountain", label = Strings("Mountain POKéMON"), icon = "mountain" },
    { id = "rough_terrain", label = Strings("Rough-terrain POKéMON"), icon = "rough_terrain" },
    { id = "urban", label = Strings("Urban POKéMON"), icon = "urban" },
    { id = "rare", label = Strings("Rare POKéMON"), icon = "rare" },
  }
  for _, h in ipairs(habitats) do
    local isUnlocked = PokedexData.isCategoryUnlocked(dex, h.id)
    table.insert(modes, {
      id = h.id,
      type = "habitat",
      label = h.label,
      icon = h.icon,
      unlocked = isUnlocked,
    })
  end

  if isNat then
    table.insert(modes, { isHeader = true, label = Strings("SEARCH") })
    table.insert(modes, { id = "atoz", type = "order", label = Strings("A TO Z MODE"), icon = "atoz", unlocked = true })
    table.insert(modes, { id = "type", type = "order", label = Strings("TYPE MODE"), icon = "type", unlocked = true })
    table.insert(modes, { id = "lightest", type = "order", label = Strings("LIGHTEST MODE"), icon = "lightest", unlocked = true })
    table.insert(modes, { id = "smallest", type = "order", label = Strings("SMALLEST MODE"), icon = "smallest", unlocked = true })
  end

  table.insert(modes, { isHeader = true, label = Strings("OTHER") })
  table.insert(modes, { id = "cancel", type = "cancel", label = Strings("CANCEL"), icon = "cancel", unlocked = true })

  return modes
end

function Pokedex.maxSpecies()
  if Pokedex.mode == "national" or Pokedex.currentOrder == "numerical_national" then
    return Dex.NATIONAL_MAX or 386
  end
  return Dex.KANTO_MAX or 151
end

function Pokedex.show(dex, opts)
  opts = opts or {}
  Pokedex.open = true
  Pokedex._dex = dex or (opts.session and opts.session.dex) or Dex.new()
  Pokedex._session = opts.session
  Pokedex._onClose = opts.onClose
  Pokedex._regSpecies = nil

  PokedexData.init()
  PokedexChrome.install()
  if not Pokemon._names then Pokemon.install(nil) end

  Pokedex.MODES = build_modes(opts.session, Pokedex._dex)
  Pokedex.modeCursor = 2 -- Start at NUMERICAL MODE (index 1 is header)
  Pokedex.modeScroll = 0
  Pokedex.listCursor = 1
  Pokedex.cursor = 1
  Pokedex.listScroll = 0

  if opts.mode then
    local m = opts.mode:lower()
    if m == "regional" or m == "kanto" then
      Pokedex.mode = "kanto"
      Pokedex.currentOrder = "numerical_kanto"
      Pokedex.screen = "ordered_list"
      Pokedex.page = "list"
    elseif m == "national" then
      Pokedex.mode = "national"
      Pokedex.currentOrder = "numerical_national"
      Pokedex.screen = "ordered_list"
      Pokedex.page = "list"
    else
      Pokedex.mode = "kanto"
      Pokedex.screen = "mode_select"
      Pokedex.page = "list"
    end
  else
    Pokedex.mode = "kanto"
    Pokedex.screen = "mode_select"
    Pokedex.page = "list"
  end

  Stack.push("pokedex", Pokedex, { hideBelow = true })
  se("SE_PIN")
end

function Pokedex.showRegistration(speciesId, opts)
  opts = opts or {}
  Pokedex.open = true
  Pokedex._regSpecies = tonumber(speciesId) or 1
  Pokedex.selectedSpecies = Pokedex._regSpecies
  Pokedex._session = opts.session
  Pokedex._dex = (opts.session and opts.session.dex) or Dex.new()
  Pokedex._onClose = opts.onDone or opts.onClose

  PokedexData.init()
  PokedexChrome.install()
  if not Pokemon._names then Pokemon.install(nil) end

  Pokedex.mode = "registration"
  Pokedex.page = "entry"
  Pokedex.screen = "registration"
  Pokedex.dataPage = 1

  Stack.push("pokedex", Pokedex, { hideBelow = true })
  play_cry(Pokedex._regSpecies)
end

function Pokedex.close()
  Pokedex.open = false
  Stack.pop("pokedex")
  local cb = Pokedex._onClose
  Pokedex._onClose = nil
  Pokedex._regSpecies = nil
  se("SE_FLEE")
  if cb then cb() end
end

function Pokedex.isOpen()
  return Pokedex.open
end

-- =========================================================================
-- Input Handling
-- =========================================================================

local function handle_mode_select_input(input)
  local total = #Pokedex.MODES
  if input:wasPressed("up") then
    local cur = Pokedex.modeCursor
    local prev = cur - 1
    while prev >= 1 and Pokedex.MODES[prev].isHeader do
      prev = prev - 1
    end
    if prev >= 1 then
      Pokedex.modeCursor = prev
      if Pokedex.modeCursor < Pokedex.modeScroll + 1 then
        Pokedex.modeScroll = Pokedex.modeCursor - 1
      elseif Pokedex.modeCursor > Pokedex.modeScroll + 9 then
        Pokedex.modeScroll = Pokedex.modeCursor - 9
      end
      se("SE_SELECT")
    end
  elseif input:wasPressed("down") then
    local cur = Pokedex.modeCursor
    local nextIdx = cur + 1
    while nextIdx <= total and Pokedex.MODES[nextIdx].isHeader do
      nextIdx = nextIdx + 1
    end
    if nextIdx <= total then
      Pokedex.modeCursor = nextIdx
      if Pokedex.modeCursor > Pokedex.modeScroll + 9 then
        Pokedex.modeScroll = Pokedex.modeCursor - 9
      elseif Pokedex.modeCursor < Pokedex.modeScroll + 1 then
        Pokedex.modeScroll = Pokedex.modeCursor - 1
      end
      se("SE_SELECT")
    end
  elseif input:wasPressed("a") then
    local m = Pokedex.MODES[Pokedex.modeCursor]
    if not m or m.isHeader then return end
    if m.type == "habitat" then
      if m.unlocked then
        Pokedex.currentCategory = m.id
        Pokedex.categoryPage = 1
        Pokedex.categorySlot = 1
        Pokedex.screen = "category_grid"
        se("SE_SELECT")
      end
    elseif m.type == "order" then
      Pokedex.currentOrder = m.id
      Pokedex.listCursor = 1
      Pokedex.cursor = 1
      Pokedex.listScroll = 0
      Pokedex.screen = "ordered_list"
      se("SE_SELECT")
    elseif m.type == "cancel" then
      Pokedex.close()
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    Pokedex.close()
  end
end

local function handle_category_grid_input(input)
  local dex = Pokedex._dex
  local pages = PokedexData.getUnlockedCategoryPages(Pokedex.currentCategory, dex)
  local maxPages = math.max(1, #pages)
  Pokedex.categoryPage = math.max(1, math.min(Pokedex.categoryPage, maxPages))
  local curMons = (pages[Pokedex.categoryPage] and pages[Pokedex.categoryPage].mons) or {}
  local numMons = math.max(1, #curMons)
  Pokedex.categorySlot = math.max(1, math.min(Pokedex.categorySlot, numMons))

  if input:wasPressed("left") or input:wasPressed("l") then
    if input:wasPressed("l") or Pokedex.categorySlot == 1 then
      if Pokedex.categoryPage > 1 then
        Pokedex.categoryPage = Pokedex.categoryPage - 1
        local newMons = (pages[Pokedex.categoryPage] and pages[Pokedex.categoryPage].mons) or {}
        Pokedex.categorySlot = math.max(1, #newMons)
        se("SE_PAGE")
      elseif maxPages > 1 and input:wasPressed("l") then
        Pokedex.categoryPage = maxPages
        local newMons = (pages[Pokedex.categoryPage] and pages[Pokedex.categoryPage].mons) or {}
        Pokedex.categorySlot = 1
        se("SE_PAGE")
      end
    else
      Pokedex.categorySlot = Pokedex.categorySlot - 1
      se("SE_SELECT")
    end
  elseif input:wasPressed("right") or input:wasPressed("r") then
    if input:wasPressed("r") or Pokedex.categorySlot == numMons then
      if Pokedex.categoryPage < maxPages then
        Pokedex.categoryPage = Pokedex.categoryPage + 1
        Pokedex.categorySlot = 1
        se("SE_PAGE")
      elseif maxPages > 1 and input:wasPressed("r") then
        Pokedex.categoryPage = 1
        Pokedex.categorySlot = 1
        se("SE_PAGE")
      end
    else
      Pokedex.categorySlot = Pokedex.categorySlot + 1
      se("SE_SELECT")
    end
  elseif input:wasPressed("up") then
    if Pokedex.categorySlot > 1 then
      Pokedex.categorySlot = Pokedex.categorySlot - 1
      se("SE_SELECT")
    end
  elseif input:wasPressed("down") then
    if Pokedex.categorySlot < numMons then
      Pokedex.categorySlot = Pokedex.categorySlot + 1
      se("SE_SELECT")
    end
  elseif input:wasPressed("a") then
    local sp = curMons[Pokedex.categorySlot]
    if sp and Dex.isSeen(dex, sp) then
      Pokedex.selectedSpecies = sp
      Pokedex.dataPage = 1
      Pokedex.page = "entry"
      Pokedex.subScreenPrev = "category_grid"
      Pokedex.screen = "data"
      se("SE_SELECT")
      play_cry(sp)
    else
      se("SE_HAZARD")
    end
  elseif input:wasPressed("select") then
    local sp = curMons[Pokedex.categorySlot]
    if sp and Dex.isSeen(dex, sp) then
      play_cry(sp)
    end
  elseif input:wasPressed("b") then
    Pokedex.screen = "mode_select"
    se("SE_SELECT")
  end
end

local function find_adjacent_seen(orderKey, startIdx, delta)
  local list = PokedexData.getOrderList(orderKey, Pokedex._dex)
  local total = #list
  local cur = startIdx + delta
  while cur >= 1 and cur <= total do
    local sp = list[cur]
    if Dex.isSeen(Pokedex._dex, sp) then
      return cur, sp
    end
    cur = cur + delta
  end
  return startIdx, list[startIdx]
end

local function handle_ordered_list_input(input)
  local list = PokedexData.getOrderList(Pokedex.currentOrder, Pokedex._dex)
  local total = #list

  if input:wasPressed("up") then
    if Pokedex.listCursor > 1 then
      Pokedex.listCursor = Pokedex.listCursor - 1
      Pokedex.cursor = Pokedex.listCursor
      if Pokedex.listCursor <= Pokedex.listScroll then
        Pokedex.listScroll = Pokedex.listCursor - 1
      end
      se("SE_SELECT")
    end
  elseif input:wasPressed("down") then
    if Pokedex.listCursor < total then
      Pokedex.listCursor = Pokedex.listCursor + 1
      Pokedex.cursor = Pokedex.listCursor
      if Pokedex.listCursor > Pokedex.listScroll + LIST_VISIBLE then
        Pokedex.listScroll = Pokedex.listCursor - LIST_VISIBLE
      end
      se("SE_SELECT")
    end
  elseif input:wasPressed("left") or input:wasPressed("l") then
    if Pokedex.currentOrder == "numerical_national" then
      Pokedex.currentOrder = "numerical_kanto"
      Pokedex.mode = "kanto"
      local kantoList = PokedexData.getOrderList("numerical_kanto", Pokedex._dex)
      Pokedex.listCursor = math.min(#kantoList, Pokedex.listCursor)
      Pokedex.cursor = Pokedex.listCursor
      se("SE_SELECT")
    else
      Pokedex.listCursor = math.max(1, Pokedex.listCursor - 10)
      Pokedex.cursor = Pokedex.listCursor
      Pokedex.listScroll = math.max(0, Pokedex.listCursor - 1)
      se("SE_PAGE")
    end
  elseif input:wasPressed("right") or input:wasPressed("r") then
    if Pokedex.currentOrder == "numerical_kanto" and Pokedex.mode == "kanto" then
      Pokedex.currentOrder = "numerical_national"
      Pokedex.mode = "national"
      se("SE_SELECT")
    else
      Pokedex.listCursor = math.min(total, Pokedex.listCursor + 10)
      Pokedex.cursor = Pokedex.listCursor
      if Pokedex.listCursor > Pokedex.listScroll + LIST_VISIBLE then
        Pokedex.listScroll = math.max(0, Pokedex.listCursor - LIST_VISIBLE)
      end
      se("SE_PAGE")
    end
  elseif input:wasPressed("a") then
    local sp = list[Pokedex.listCursor]
    if sp and Dex.isSeen(Pokedex._dex, sp) then
      Pokedex.selectedSpecies = sp
      Pokedex.dataPage = 1
      Pokedex.page = "entry"
      Pokedex.screen = "data"
      Pokedex.subScreenPrev = "ordered_list"
      se("SE_SELECT")
      play_cry(sp)
    else
      se("SE_HAZARD")
    end
  elseif input:wasPressed("select") then
    local sp = list[Pokedex.listCursor]
    if sp and Dex.isSeen(Pokedex._dex, sp) then
      play_cry(sp)
    end
  elseif input:wasPressed("b") then
    Pokedex.screen = "mode_select"
    se("SE_SELECT")
  end
end

local function handle_action_popup_input(input)
  local isCaught = Dex.isCaught(Pokedex._dex, Pokedex.selectedSpecies)
  local actions = {
    { id = "data", label = "DATA" },
    { id = "cry", label = "CRY" },
    { id = "area", label = "AREA" },
  }
  if isCaught then
    table.insert(actions, { id = "size", label = "SIZE" })
  end
  table.insert(actions, { id = "cancel", label = "CANCEL" })

  local n = #actions
  if input:wasPressed("up") then
    Pokedex.actionCursor = ((Pokedex.actionCursor - 2 + n) % n) + 1
    se("SE_SELECT")
  elseif input:wasPressed("down") then
    Pokedex.actionCursor = (Pokedex.actionCursor % n) + 1
    se("SE_SELECT")
  elseif input:wasPressed("a") then
    local act = actions[Pokedex.actionCursor]
    if act.id == "data" then
      Pokedex.dataPage = 1
      Pokedex.page = "entry"
      Pokedex.screen = "data"
      se("SE_SELECT")
    elseif act.id == "cry" then
      play_cry(Pokedex.selectedSpecies)
    elseif act.id == "area" then
      Pokedex.areaMapKey = "kanto"
      Pokedex.screen = "area"
      se("SE_SELECT")
    elseif act.id == "size" then
      Pokedex.screen = "size"
      se("SE_SELECT")
    elseif act.id == "cancel" then
      Pokedex.page = "list"
      Pokedex.screen = Pokedex.subScreenPrev
      se("SE_SELECT")
    end
  elseif input:wasPressed("b") then
    Pokedex.page = "list"
    Pokedex.screen = Pokedex.subScreenPrev
    se("SE_SELECT")
  end
end

local function handle_data_input(input)
  if input:wasPressed("a") then
    if Pokedex.screen == "registration" then
      Pokedex.isOpen_ = false
      if Pokedex._onDone then Pokedex._onDone() end
    elseif Pokedex.dataPage == 1 then
      Pokedex.dataPage = 2
      se("SE_SELECT")
    else
      -- On page 2, A is CANCEL (returns to list/grid)
      Pokedex.page = "list"
      Pokedex.screen = Pokedex.subScreenPrev
      se("SE_SELECT")
    end
  elseif input:wasPressed("b") then
    if Pokedex.dataPage == 2 then
      -- On page 2, B is PREVIOUS DATA (returns to page 1)
      Pokedex.dataPage = 1
      se("SE_SELECT")
    else
      -- On page 1, B is CANCEL (returns to list/grid)
      Pokedex.page = "list"
      Pokedex.screen = Pokedex.subScreenPrev
      se("SE_SELECT")
    end
  elseif input:wasPressed("up") then
    local newIdx, newSp = find_adjacent_seen(Pokedex.currentOrder, Pokedex.listCursor, -1)
    if newIdx ~= Pokedex.listCursor then
      Pokedex.listCursor = newIdx
      Pokedex.cursor = newIdx
      Pokedex.selectedSpecies = newSp
      Pokedex.dataPage = 1
      se("SE_SELECT")
      play_cry(newSp)
    end
  elseif input:wasPressed("down") then
    local newIdx, newSp = find_adjacent_seen(Pokedex.currentOrder, Pokedex.listCursor, 1)
    if newIdx ~= Pokedex.listCursor then
      Pokedex.listCursor = newIdx
      Pokedex.cursor = newIdx
      Pokedex.selectedSpecies = newSp
      Pokedex.dataPage = 1
      se("SE_SELECT")
      play_cry(newSp)
    end
  elseif input:wasPressed("select") or input:wasPressed("start") then
    local sp = Pokedex._regSpecies or Pokedex.selectedSpecies
    play_cry(sp)
  end
end

local function handle_area_input(input)
  if input:wasPressed("left") or input:wasPressed("l") then
    Pokedex.areaMapKey = "kanto"
    se("SE_SELECT")
  elseif input:wasPressed("right") or input:wasPressed("r") then
    local seviiMaps = { "one_island", "two_island", "three_island", "four_island", "five_island", "six_island", "seven_island" }
    local curIdx = 0
    for i, k in ipairs(seviiMaps) do
      if Pokedex.areaMapKey == k then curIdx = i; break end
    end
    local nextIdx = (curIdx % #seviiMaps) + 1
    Pokedex.areaMapKey = seviiMaps[nextIdx]
    se("SE_SELECT")
  elseif input:wasPressed("select") or input:wasPressed("start") then
    play_cry(Pokedex.selectedSpecies)
  elseif input:wasPressed("a") or input:wasPressed("b") then
    Pokedex.screen = Pokedex.subScreenPrev
    se("SE_SELECT")
  end
end

local function handle_size_input(input)
  if input:wasPressed("select") or input:wasPressed("start") then
    play_cry(Pokedex.selectedSpecies)
  elseif input:wasPressed("a") or input:wasPressed("b") then
    Pokedex.screen = Pokedex.subScreenPrev
    se("SE_SELECT")
  end
end

local function handle_registration_input(input)
  if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
    Pokedex.close()
  end
end

function Pokedex.handleInput(input)
  if not input then return end

  if Pokedex.screen == "mode_select" then
    handle_mode_select_input(input)
  elseif Pokedex.screen == "category_grid" then
    handle_category_grid_input(input)
  elseif Pokedex.screen == "ordered_list" then
    handle_ordered_list_input(input)
  elseif Pokedex.screen == "action_popup" then
    handle_action_popup_input(input)
  elseif Pokedex.screen == "data" then
    handle_data_input(input)
  elseif Pokedex.screen == "area" then
    handle_area_input(input)
  elseif Pokedex.screen == "size" then
    handle_size_input(input)
  elseif Pokedex.screen == "registration" then
    handle_registration_input(input)
  end
end

-- =========================================================================
-- Render Passes (Authentic FRLG Layout & Styling)
-- =========================================================================

--- 1. Table of Contents (Mode Select) Screen
local function draw_mode_select()
  local dex = Pokedex._dex
  PokedexChrome.drawPaperBg()

  -- Top Header Bar: POKéDEX   TABLE OF CONTENTS (centered, y=2)
  PokedexChrome.drawHeader(Strings("POKéDEX   TABLE OF CONTENTS"), nil, 2)

  -- Left Column: 9 visible rows inside window (x=8, y=16..144, 14px pitch)
  local maxVisible = 9
  local startIdx = Pokedex.modeScroll + 1
  local endIdx = math.min(#Pokedex.MODES, Pokedex.modeScroll + maxVisible)

  for i = startIdx, endIdx do
    local r = i - startIdx
    local y = 18 + r * 14
    local m = Pokedex.MODES[i]

    if m.isHeader then
      -- Section Header in bold vibrant orange with warm red shadow (GBA colors 15 & 14)
      FrlgFont.draw(m.label, 8, y, {
        colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
      })
    else
      -- Cursor arrow
      if i == Pokedex.modeCursor then
        love.graphics.setColor(0x18/255, 0x18/255, 0x18/255, 1)
        love.graphics.polygon("fill",
          12, y + 2,
          17, y + 6,
          12, y + 10
        )
      end

      -- Text colors: Unlocked (black) vs Locked (faint light grey)
      local txtColors
      if m.unlocked == false then
        txtColors = { fg = { 0xB8/255, 0xC0/255, 0xC8/255, 1 }, shadow = { 0xE0/255, 0xE8/255, 0xF0/255, 1 } }
      else
        txtColors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
      end

      FrlgFont.draw(m.label, 20, y, { colors = txtColors })
    end
  end

  -- Right Column: Seen & Owned Stats
  local isNat = PokedexData.isNationalUnlocked(Pokedex._session, dex)
  if isNat then
    local kantoSeen = Dex.countSeen(dex, "kanto")
    local natSeen = Dex.countSeen(dex, "national")
    local kantoOwn = Dex.countCaught(dex, "kanto")
    local natOwn = Dex.countCaught(dex, "national")

    FrlgFont.draw(Strings("Seen:"), 168, 18, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(Strings("KANTO"), 176, 29, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", kantoSeen), 212, 29, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })
    FrlgFont.draw(Strings("NATIONAL"), 176, 40, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", natSeen), 212, 40, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })

    FrlgFont.draw(Strings("Owned:"), 168, 53, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(Strings("KANTO"), 176, 64, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", kantoOwn), 212, 64, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })
    FrlgFont.draw(Strings("NATIONAL"), 176, 75, {
      small = true,
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", natOwn), 212, 75, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })
  else
    local kantoSeen = Dex.countSeen(dex, "kanto")
    local kantoOwn = Dex.countCaught(dex, "kanto")

    FrlgFont.draw(Strings("Seen:"), 168, 25, {
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", kantoSeen), 212, 37, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })

    FrlgFont.draw(Strings("Owned:"), 168, 53, {
      colors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }
    })
    FrlgFont.draw(string.format("%3d", kantoOwn), 212, 65, {
      colors = { fg = { 255/255, 139/255, 57/255, 1 }, shadow = { 205/255, 65/255, 57/255, 1 } }
    })
  end

  -- Category Preview Icon at x=168, y=88 (64x48)
  local selMode = Pokedex.MODES[Pokedex.modeCursor]
  if selMode and selMode.icon then
    PokedexChrome.drawCategoryIcon(selMode.icon, 168, 88)
  end

  -- Bouncing Down Arrow beneath the oval
  PokedexChrome.drawDownArrow(195, 134)

  -- Bottom Bar Controls: {DPAD_UPDOWN}PICK   {A_BUTTON}OK
  PokedexChrome.drawControlInfo(Strings("{DPAD_UPDOWN}PICK {A_BUTTON}OK"), 236, 146)
end

--- 2. Pokémon List Screen (9 Rows)
local function draw_ordered_list()
  local dex = Pokedex._dex
  PokedexChrome.drawPaperBg()

  -- Top Header Bar: POKéMON LIST (centered, y=2)
  PokedexChrome.drawHeader(Strings("POKéMON LIST"), nil, 2)

  local list = PokedexData.getOrderList(Pokedex.currentOrder, dex)
  local total = #list
  local textColors = { fg = { 0x18/255, 0x18/255, 0x18/255, 1 }, shadow = { 0xD0/255, 0xD0/255, 0xD0/255, 1 } }

  -- 9 visible rows (y = 18 + (i - 1) * 14)
  for i = 1, LIST_VISIBLE do
    local idx = Pokedex.listScroll + i
    if idx > total then break end

    local rowY = 18 + (i - 1) * 14
    local sp = list[idx]
    local seen = Dex.isSeen(dex, sp)
    local caught = Dex.isCaught(dex, sp)

    if idx == Pokedex.listCursor then
      -- Black cursor triangle at x=20
      love.graphics.setColor(0x18/255, 0x18/255, 0x18/255, 1)
      love.graphics.polygon("fill",
        20, rowY + 3,
        25, rowY + 7,
        20, rowY + 11
      )
    end

    -- Number: №001 (FONT_SMALL at x=28)
    local natId = Pokemon.nationalPokedexNumber and Pokemon.nationalPokedexNumber(sp) or sp
    local num = (Pokedex.currentOrder == "numerical_kanto") and sp or natId
    local numStr = string.format("№%03d", num)
    FrlgFont.draw(numStr, 28, rowY + 1, {
      small = true,
      colors = textColors,
    })

    -- Caught Poké Ball icon at x=56
    if caught then
      PokedexChrome.drawCaughtMarker(56, rowY + 1)
    end

    -- Name / dashes at x=72 (FONT_NORMAL)
    local nameStr = seen and species_label(sp) or "------"
    FrlgFont.draw(nameStr, 72, rowY, {
      colors = textColors,
    })

    -- Type badges on right side if caught (Type 1 at x=136, Type 2 at x=168)
    if caught then
      local t = Pokemon.types and Pokemon.types(sp)
      local t1Name = t and t[1] and Types.name(t[1])
      local t2Name = t and t[2] and t[2] ~= t[1] and Types.name(t[2])
      if t1Name then
        PokedexChrome.drawTypeBadge(t1Name, 136, rowY + 1)
      end
      if t2Name then
        PokedexChrome.drawTypeBadge(t2Name, 168, rowY + 1)
      end
    end
  end

  -- Scroll Down Arrow at x=200, y=141
  if Pokedex.listScroll + LIST_VISIBLE < total then
    PokedexChrome.drawDownArrow(200, 141)
  end
  if Pokedex.listScroll > 0 then
    PokedexChrome.drawUpArrow(200, 19)
  end

  -- Bottom Bar Controls: {DPAD_UPDOWN}PICK   {A_BUTTON}OK   {B_BUTTON}CANCEL
  PokedexChrome.drawControlInfo(Strings("{DPAD_UPDOWN}PICK {A_BUTTON}OK {B_BUTTON}CANCEL"), 236, 146)
end

--- 3. Detailed Data Entry Screen (Page 1: Specs & Flavor Text, Page 2: Size Chart & Area Map)
local function draw_data_screen()
  local dex = Pokedex._dex
  local sp = Pokedex._regSpecies or Pokedex.selectedSpecies
  local natId = Pokemon.nationalPokedexNumber and Pokemon.nationalPokedexNumber(sp) or sp
  local dispNum = (Pokedex.currentOrder == "numerical_kanto") and sp or natId
  local name = species_label(sp)
  local entry = PokedexChrome.getEntry(sp)
  local isCaught = Dex.isCaught(dex, sp)
  local isPage2 = (Pokedex.dataPage == 2)

  -- Authentic pret Pokédex card text colors
  local upperColors = {
    fg = { 0, 0, 0, 1 },
    shadow = { 230 / 255, 222 / 255, 197 / 255, 1 },
  }
  local lowerColors = {
    fg = { 0, 0, 0, 1 },
    shadow = { 197 / 255, 180 / 255, 139 / 255, 1 },
  }

  if not isPage2 then
    -- ================= PAGE 1: SPECS & FLAVOR TEXT =================
    -- 1. Card Background Chassis (240x160 FRLG exact tilemap card)
    PokedexChrome.drawDataCardBg()

    -- 2. Top Header Bar
    if Pokedex.subScreenPrev == "category_grid" then
      local catTitles = {
        grassland = Strings("Grassland POKéMON"),
        forest = Strings("Forest POKéMON"),
        waters_edge = Strings("Water's-edge POKéMON"),
        sea = Strings("Sea POKéMON"),
        cave = Strings("Cave POKéMON"),
        mountain = Strings("Mountain POKéMON"),
        rough_terrain = Strings("Rough-terrain POKéMON"),
        urban = Strings("Urban POKéMON"),
        rare = Strings("Rare POKéMON"),
      }
      local title = catTitles[Pokedex.currentCategory] or Strings("Grassland POKéMON")
      PokedexChrome.drawHeader(title, 8, 2)
      PokedexChrome.drawHeader(Strings("PAGE 1/ 2"), 176, 2)
    else
      PokedexChrome.drawHeader(Strings("POKéMON LIST"), nil, 2)
    end

    -- 3. Top Specs Window (sWindowTemplate_DexEntry_SpeciesStats at x=16, y=24)
    -- Line 1 (y = 32): Dex No in FONT_SMALL at x=16; Species Name in FONT_NORMAL at x=44
    local noStr = string.format("№%03d", dispNum)
    FrlgFont.draw(noStr, 16, 32, { small = true, colors = upperColors })
    FrlgFont.draw(name, 44, 32, { small = false, colors = upperColors })

    -- Line 2 (y = 48): Category in FONT_SMALL at x=16
    local catStr = isCaught and (entry.categoryName or "POKéMON") or Strings("??????????? POKéMON")
    FrlgFont.draw(catStr, 16, 48, { small = true, colors = upperColors })

    -- Line 3 (y = 60): HT in FONT_SMALL at x=16; Height value at x=46
    FrlgFont.draw(Strings("HT"), 16, 60, { small = true, colors = upperColors })
    local htStr = isCaught and (entry.heightFormatted or " ??'??\"") or " ??'??\""
    FrlgFont.draw(htStr, 46, 60, { small = true, colors = upperColors })

    -- Line 4 (y = 72): WT in FONT_SMALL at x=16; Weight value at x=46
    FrlgFont.draw(Strings("WT"), 16, 72, { small = true, colors = upperColors })
    local wtStr = isCaught and (entry.weightFormatted or Strings(" ???? ? lbs.")) or Strings(" ???? ? lbs.")
    FrlgFont.draw(wtStr, 46, 72, { small = true, colors = upperColors })

    -- Footprint (16x16) at screen x=104, y=64 (window x=88, y=40)
    if isCaught then
      PokedexChrome.drawFootprint(sp, 104, 64)
    end

    -- Front Sprite (64x64) at screen x=152, y=24 (sWindowTemplate_DexEntry_MonPic at x=152, y=24)
    local pic = Pokemon.frontPic and Pokemon.frontPic(sp)
    if pic and pic.image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(pic.image, 152, 24)
    end

    -- 4. Bottom Flavor Text Window (sWindowTemplate_DexEntry_FlavorText at x=0, y=88, w=240, h=56)
    if isCaught then
      local desc = entry.description
      if desc and #desc > 0 then
        local maxW = FrlgFont.measure(desc)
        local startX = math.max(0, math.floor((240 - maxW) / 2))
        FrlgFont.draw(desc, startX, 96, {
          colors = lowerColors,
          linePitch = 14,
          maxWidth = 240,
        })
      end
    end

    -- 5. Bottom Bar Controls
    PokedexChrome.drawControlInfoLeft(Strings("{START_BUTTON}CRY"), 8, 146)
    if Pokedex.screen == "registration" then
      PokedexChrome.drawControlInfo(Strings("{A_BUTTON}OK"), 236, 146)
    else
      PokedexChrome.drawControlInfo(Strings("{A_BUTTON}NEXT DATA {B_BUTTON}CANCEL"), 236, 146)
    end

  else
    -- ================= PAGE 2: SIZE CHART & AREA MAP =================
    -- 1. Area Card Background Chassis (240x160 white card with inset size box)
    PokedexChrome.drawAreaCardBg()

    -- 2. Top Header Bar
    if Pokedex.subScreenPrev == "category_grid" then
      local catTitles = {
        grassland = Strings("Grassland POKéMON"),
        forest = Strings("Forest POKéMON"),
        waters_edge = Strings("Water's-edge POKéMON"),
        sea = Strings("Sea POKéMON"),
        cave = Strings("Cave POKéMON"),
        mountain = Strings("Mountain POKéMON"),
        rough_terrain = Strings("Rough-terrain POKéMON"),
        urban = Strings("Urban POKéMON"),
        rare = Strings("Rare POKéMON"),
      }
      local title = catTitles[Pokedex.currentCategory] or Strings("Grassland POKéMON")
      PokedexChrome.drawHeader(title, 8, 2)
      PokedexChrome.drawHeader(Strings("PAGE 2/ 2"), 176, 2)
    else
      PokedexChrome.drawHeader(Strings("POKéMON LIST"), nil, 2)
    end

    -- 3. Top Left: Mon Icon (32x32) at (14, 20)
    local icon = Pokemon.icon and Pokemon.icon(sp)
    if icon and icon.image then
      local q = icon.quads and icon.quads[0]
      love.graphics.setColor(1, 1, 1, 1)
      if q then
        love.graphics.draw(icon.image, q, 14, 20)
      else
        love.graphics.draw(icon.image, 14, 20)
      end
    end

    -- Top Left: Dex No & Species Name
    local noStr = string.format("№%03d", dispNum)
    FrlgFont.draw(noStr, 48, 16, { small = true, colors = upperColors })
    FrlgFont.draw(name, 51, 28, { small = false, colors = upperColors })

    -- Top Left: Type Badges (at x=48, y=42)
    if isCaught then
      local t = Pokemon.types and Pokemon.types(sp)
      local t1 = t and t[1]
      local t2 = t and t[2]
      if t1 then
        PokedexChrome.drawTypeBadge(t1, 48, 42)
      end
      if t2 and t2 ~= t1 then
        PokedexChrome.drawTypeBadge(t2, 80, 42)
      end
    end

    -- 4. Left Bottom: SIZE Title & Size Comparison Silhouettes
    local sizeW = FrlgFont.measure(Strings("SIZE"), { small = true })
    FrlgFont.draw(Strings("SIZE"), 16 + math.floor((80 - sizeW) / 2), 54, { small = true, colors = upperColors })

    if isCaught then
      -- Trainer Silhouette (64x64) at x=48, y=72
      local trainerImg = PokedexChrome.getTrainerPic("male")
      if trainerImg then
        PokedexChrome.drawSilhouette(trainerImg, 48, 72 + (entry.trainerOffset or 0))
      end

      -- Pokémon Silhouette (64x64 scaled by 256 / pokemonScale)
      local pic = Pokemon.frontPic and Pokemon.frontPic(sp)
      if pic and pic.image then
        local rawScale = entry.pokemonScale or 256
        if rawScale <= 0 then rawScale = 256 end
        local pScale = 256 / rawScale
        local originX = 32
        local originY = 32
        local drawX = 40
        local drawY = 104 + (entry.pokemonOffset or 0)
        PokedexChrome.drawSilhouette(pic.image, drawX, drawY, pScale, pScale, originX, originY)
      end
    end

    -- 5. Right: AREA Title & Region Map
    local areaW = FrlgFont.measure(Strings("AREA"), { small = true })
    FrlgFont.draw(Strings("AREA"), 136 + math.floor((96 - areaW) / 2), 54, { small = true, colors = upperColors })

    local mapX, mapY = 136, 64
    PokedexChrome.drawMap("kanto", mapX, mapY)

    -- Route Area Markers
    local areas = PokedexData.getWildAreasForSpecies(sp)

    if #areas > 0 then
      for _, aKey in ipairs(areas) do
        if PokedexData.getAreaMapKey(aKey) == "kanto" then
          local m = PokedexData.getAreaMarker(aKey)
          if m then
            PokedexChrome.drawAreaMarker(m.shape, mapX + (m.x - 32), mapY + m.y)
          end
        end
      end
    else
      -- Area Unknown Wide Ellipse
      local ellipseImg = PokedexChrome.getImage("blit_wide_ellipse")
      if ellipseImg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(ellipseImg, mapX + 4, mapY + 28)
      end
      local unkW = FrlgFont.measure(Strings("AREA UNKNOWN"), { small = true })
      FrlgFont.draw(Strings("AREA UNKNOWN"), mapX + math.floor((96 - unkW) / 2), mapY + 30, {
        small = true,
        colors = upperColors,
      })
    end

    -- 6. Bottom Bar Controls on Page 2
    PokedexChrome.drawControlInfoLeft(Strings("{START_BUTTON}CRY"), 8, 146)
    PokedexChrome.drawControlInfo(Strings("{A_BUTTON}CANCEL {B_BUTTON}PREVIOUS DATA"), 236, 146)
  end
end

--- 4. Habitat Category Screen (Pulsing Spotlight Disc & Mini Card)
local function draw_habitat_grid()
  local dex = Pokedex._dex

  -- Solid warm beige background (#E8E0CE)
  love.graphics.setColor(232/255, 224/255, 206/255, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)

  -- Top & Bottom Khaki Bars (seamlessly meeting background)
  love.graphics.setColor(213/255, 197/255, 164/255, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.rectangle("fill", 0, 144, 240, 16)

  local catKey = Pokedex.currentCategory
  local catTitles = {
    grassland = Strings("Grassland POKéMON"),
    forest = Strings("Forest POKéMON"),
    waters_edge = Strings("Water's-edge POKéMON"),
    sea = Strings("Sea POKéMON"),
    cave = Strings("Cave POKéMON"),
    mountain = Strings("Mountain POKéMON"),
    rough_terrain = Strings("Rough-terrain POKéMON"),
    urban = Strings("Urban POKéMON"),
    rare = Strings("Rare POKéMON"),
  }
  local title = catTitles[catKey] or Strings("Grassland POKéMON")
  local pages = PokedexData.getUnlockedCategoryPages(catKey, dex)
  local maxPages = math.max(1, #pages)
  Pokedex.categoryPage = math.max(1, math.min(Pokedex.categoryPage, maxPages))
  local curMons = (pages[Pokedex.categoryPage] and pages[Pokedex.categoryPage].mons) or {}
  local numMons = #curMons
  if numMons == 0 then numMons = 1 end
  Pokedex.categorySlot = math.max(1, math.min(Pokedex.categorySlot, numMons))

  -- Header Bar (y=2)
  PokedexChrome.drawHeader(title, 8, 2)
  PokedexChrome.drawHeader(Strings("PAGE %d/ %d", Pokedex.categoryPage, maxPages), 176, 2)

  Pokedex.spotlightTimer = Pokedex.spotlightTimer + 0.05

  local layout = CATEGORY_PAGE_COORDS[numMons] or CATEGORY_PAGE_COORDS[1]

  for slot = 1, numMons do
    local sp = curMons[slot]
    local coords = layout[slot]
    if sp and coords then
      local isSelected = (slot == Pokedex.categorySlot)
      local seen = Dex.isSeen(dex, sp)
      local caught = Dex.isCaught(dex, sp)

      -- Pulsing Spotlight Disc behind mon sprite (selected pulses, unselected stays idle)
      PokedexChrome.drawHabitatSpotlight(coords.circle.x, coords.circle.y, 32, Pokedex.spotlightTimer, isSelected)

      -- Pokémon Front Sprite
      if seen then
        local pic = Pokemon.frontPic and Pokemon.frontPic(sp)
        if pic and pic.image then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(pic.image, coords.pic.x, coords.pic.y)
        end
      else
        FrlgFont.draw("?", coords.pic.x + 26, coords.pic.y + 24, { color = { 0.4, 0.4, 0.4, 1 } })
      end

      -- Mini Page Card
      PokedexChrome.drawMiniCard(sp, coords.card.x, coords.card.y, caught, seen, isSelected)
    end
  end

  -- Side Page Flip Arrows
  if Pokedex.categoryPage < maxPages then
    PokedexChrome.drawSideArrow("right", 222, 74)
  end
  if Pokedex.categoryPage > 1 then
    PokedexChrome.drawSideArrow("left", 10, 74)
  end

  -- Bottom Bar Controls: {DPAD_LEFTRIGHT}PICK+FLIP PAGE   {A_BUTTON}CHECK   {B_BUTTON}CANCEL
  PokedexChrome.drawControlInfo(Strings("{DPAD_LEFTRIGHT}PICK+FLIP PAGE {A_BUTTON}CHECK {B_BUTTON}CANCEL"), 236, 146)
end

--- 5. Area Map Screen
local function draw_area_screen()
  local dex = Pokedex._dex
  PokedexChrome.drawPaperBg()

  local sp = Pokedex.selectedSpecies
  local name = species_label(sp)
  local isCaught = Dex.isCaught(dex, sp)
  local areas = PokedexData.getWildAreasForSpecies(sp)

  -- Header (centered, y=2)
  PokedexChrome.drawHeader(Strings("AREA: %s", name), nil, 2)

  -- Left Column: Mon Icon & Types & Name
  local icon = Pokemon.icon and Pokemon.icon(sp)
  if icon and icon.image then
    local q = icon.quads and icon.quads[0]
    love.graphics.setColor(1, 1, 1, 1)
    if q then
      love.graphics.draw(icon.image, q, 14, 28)
    else
      love.graphics.draw(icon.image, 14, 28)
    end
  end
  FrlgFont.draw(name, 48, 34, { color = { 0.1, 0.1, 0.1, 1 } })

  -- Type Badges
  local t = Pokemon.types and Pokemon.types(sp)
  local t1Name = t and t[1] and Types.name(t[1])
  local t2Name = t and t[2] and t[2] ~= t[1] and Types.name(t[2])
  if t1Name then
    PokedexChrome.drawTypeBadge(t1Name, 14, 58)
  end
  if t2Name then
    PokedexChrome.drawTypeBadge(t2Name, 48, 58)
  end

  -- Left Size Silhouette Preview (if caught)
  if isCaught then
    local entry = PokedexChrome.getEntry(sp)
    love.graphics.setColor(0.25, 0.25, 0.30, 0.85)
    local pScale = (entry.pokemonScale or 256) / 256 * 0.45
    local pic = Pokemon.frontPic and Pokemon.frontPic(sp)
    if pic and pic.image then
      love.graphics.draw(pic.image, 14, 80 + (entry.pokemonOffset or 0), 0, pScale, pScale)
    end
    -- Trainer Silhouette
    love.graphics.setColor(0.4, 0.4, 0.45, 0.85)
    love.graphics.rectangle("fill", 58, 86, 12, 38, 2, 2)
    FrlgFont.draw("1.4m", 72, 98, { color = { 0.4, 0.4, 0.4, 1 } })
  end

  -- Right Map Panel
  local mapX, mapY = 136, 64
  local curMap = Pokedex.areaMapKey or "kanto"
  PokedexChrome.drawMap(curMap, mapX, mapY)

  -- Route Markers
  if #areas > 0 then
    for _, aKey in ipairs(areas) do
      if PokedexData.getAreaMapKey(aKey) == curMap then
        local m = PokedexData.getAreaMarker(aKey)
        if m then
          local xOff = (curMap == "kanto") and (m.x - 32) or m.x
          PokedexChrome.drawAreaMarker(m.shape, mapX + xOff, mapY + m.y)
        end
      end
    end
  else
    -- Area Unknown badge
    love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", 120, 72, 94, 18, 4, 4)
    FrlgFont.draw(Strings("AREA UNKNOWN"), 128, 76, { color = { 1, 0.9, 0.3, 1 } })
  end

  -- Footer
  PokedexChrome.drawControlInfoLeft(Strings("{START_BUTTON}CRY"), 8, 146)
  PokedexChrome.drawControlInfo(Strings("{DPAD_LEFTRIGHT}MAP {B_BUTTON}CANCEL"), 236, 146)
end

--- 6. Size Comparison Screen
local function draw_size_screen()
  PokedexChrome.drawPaperBg()

  local sp = Pokedex.selectedSpecies
  local name = species_label(sp)
  local entry = PokedexChrome.getEntry(sp)

  -- Header (centered, y=2)
  PokedexChrome.drawHeader(Strings("SIZE COMPARISON: %s", name), nil, 2)

  -- Left: Trainer Specs
  FrlgFont.draw(Strings("TRAINER"), 16, 32, { color = { 0.2, 0.4, 0.8, 1 } })
  FrlgFont.draw(Strings("HT  4'07\""), 16, 48, { color = { 0.2, 0.2, 0.2, 1 } })
  FrlgFont.draw(Strings("WT 114.6 lbs."), 16, 62, { color = { 0.2, 0.2, 0.2, 1 } })

  -- Trainer Graphic
  love.graphics.setColor(0.3, 0.35, 0.4, 1)
  love.graphics.rectangle("fill", 32, 80, 20, 52, 3, 3)

  -- Right: Mon Specs & Scaled Graphic
  FrlgFont.draw(name, 114, 32, { color = { 0.8, 0.3, 0.2, 1 } })
  FrlgFont.draw(Strings("HT  %s", (entry.heightFormatted or "--'--\"")), 114, 48, { color = { 0.2, 0.2, 0.2, 1 } })
  FrlgFont.draw(Strings("WT  %s", (entry.weightFormatted or Strings("---.- lbs."))), 114, 62, { color = { 0.2, 0.2, 0.2, 1 } })

  local pScale = (entry.pokemonScale or 256) / 256 * 0.75
  local pic = Pokemon.frontPic and Pokemon.frontPic(sp)
  if pic and pic.image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(pic.image, 140, 72 + (entry.pokemonOffset or 0), 0, pScale, pScale)
  end

  -- Footer
  PokedexChrome.drawControlInfoLeft(Strings("{START_BUTTON}CRY"), 8, 146)
  PokedexChrome.drawControlInfo(Strings("{B_BUTTON}CANCEL"), 236, 146)
end

--- 7. Action Popup Menu Modal
local function draw_action_popup()
  if Pokedex.subScreenPrev == "category_grid" then
    draw_habitat_grid()
  else
    draw_ordered_list()
  end

  local isCaught = Dex.isCaught(Pokedex._dex, Pokedex.selectedSpecies)
  local actions = {
    { id = "data", label = Strings("DATA") },
    { id = "cry", label = Strings("CRY") },
    { id = "area", label = Strings("AREA") },
  }
  if isCaught then
    table.insert(actions, { id = "size", label = Strings("SIZE") })
  end
  table.insert(actions, { id = "cancel", label = Strings("CANCEL") })

  PokedexChrome.drawActionMenu(actions, Pokedex.actionCursor, 160, 48)
end

function Pokedex.draw()
  if not Pokedex.open then return end

  if Pokedex.screen == "mode_select" then
    draw_mode_select()
  elseif Pokedex.screen == "category_grid" then
    draw_habitat_grid()
  elseif Pokedex.screen == "ordered_list" then
    draw_ordered_list()
  elseif Pokedex.screen == "action_popup" then
    draw_action_popup()
  elseif Pokedex.screen == "data" or Pokedex.screen == "registration" then
    draw_data_screen()
  elseif Pokedex.screen == "area" then
    draw_area_screen()
  elseif Pokedex.screen == "size" then
    draw_size_screen()
  end
end

return Pokedex

-- Pokémon Summary Screen Menu for Game3.
-- 1:1 replication of Pokémon FireRed summary screen:
-- Pages: INFO (0), SKILLS (1), MOVES (2), MOVES_INFO (3), EGG (4).
-- Features: Animated page slide (with anchored foreground), full move swapping (anti-PP swap trap),
-- dynamic trainer memo diffing, and ROM-baked chrome graphics.

local Display = require("src.core.game3.display")
local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local Dex = require("src.core.game3.dex")
local PokedexData = require("src.core.game3.pokedex_data")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local SummaryData = require("src.core.game3.summary_data")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local ItemsData = require("src.core.game3.items_data")

local SummaryMenu = {}

-- pokefirered/src/pokemon_summary_screen.c:2139
function SummaryMenu.heldItemText(mon)
  local raw = mon and (mon.item or mon.heldItem)
  local held = ItemsData.toNumericId(raw) or tonumber(raw) or 0
  if held == 0 then return RomText.plain("gText_PokeSum_Item_None") end
  return ItemsData.displayName(held)
end

SummaryMenu.open = false
SummaryMenu._party = nil
SummaryMenu._cursor = 1
SummaryMenu._page = 0
SummaryMenu._moveCursor = 1
SummaryMenu._swapSlot = nil
SummaryMenu._onClose = nil
SummaryMenu._playerState = nil
SummaryMenu._slide = {
  active = false,
  direction = 0,
  timer = 0,
  duration = 0.12,
  prevPage = 0,
}

local PAGE_INFO = 0
local PAGE_SKILLS = 1
local PAGE_MOVES = 2
local PAGE_MOVES_INFO = 3
local PAGE_EGG = 4

local STAT_COLORS = {
  NORMAL = FrlgFont.COLOR.NORMAL,
  UP = { fg = { 210 / 255, 60 / 255, 60 / 255, 1 }, shadow = { 240 / 255, 200 / 255, 200 / 255, 1 } },
  DOWN = { fg = { 60 / 255, 90 / 255, 210 / 255, 1 }, shadow = { 200 / 255, 210 / 255, 240 / 255, 1 } },
}

local function current_mon()
  if not SummaryMenu._party then return nil end
  return SummaryMenu._party[SummaryMenu._cursor]
end

local function party_count()
  return #(SummaryMenu._party or {})
end

-- pokefirered/src/pokemon_summary_screen.c:5180
local function play_mon_cry()
  local mon = current_mon()
  if not mon or Pokemon.isEgg(mon) then return end
  local species = Pokemon.speciesOf(mon)
  if not species then return end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playCry then
    Audio.playCry(species)
  end
end

local function moves_for_mon(mon)
  if not mon then return {} end
  local out = {}
  local rawMoves = mon.moves or {}
  local rawPp = mon.pp or {}

  for i = 1, 4 do
    local entry = rawMoves[i]
    local moveId, pp, maxPp, mdef
    if type(entry) == "table" then
      moveId = entry.id or entry.move or entry.moveId or entry.num or entry.name or entry[1]
      pp = entry.pp
    else
      moveId = entry
      pp = rawPp[i]
    end

    if moveId and (type(moveId) ~= "number" or moveId > 0) and moveId ~= "" and moveId ~= "-------" then
      mdef = Pokemon.battleMove(moveId)
      maxPp = tonumber(mon.maxPp and mon.maxPp[i]) or (mdef and mdef.pp) or 5
      if not pp then pp = maxPp end
      local name = Pokemon.moveName(moveId)
      if not name or name == "" or name:match("^MOVE ") then
        name = (mdef and mdef.name) or name or Strings("MOVE %s", tostring(moveId))
      end
      local mType = (mdef and (mdef.type or mdef.kind)) or "NORMAL"
      local power = (mdef and mdef.power and mdef.power > 0) and tostring(mdef.power) or "---"
      local acc = (mdef and mdef.accuracy and mdef.accuracy > 0) and tostring(mdef.accuracy) or "---"
      out[i] = {
        id = moveId,
        name = name,
        pp = pp,
        maxPp = maxPp,
        type = mType,
        power = power,
        accuracy = acc,
      }
    end
  end

  if SummaryMenu._mode == "select_move" and SummaryMenu._moveToLearn then
    local newId = tonumber(SummaryMenu._moveToLearn) or SummaryMenu._moveToLearn
    local mdef = Pokemon.battleMove(newId)
    local name = Pokemon.moveName(newId)
    if not name or name == "" or name:match("^MOVE ") then
      name = (mdef and mdef.name) or name or Strings("MOVE %s", tostring(newId))
    end
    local maxPp = (mdef and mdef.pp) or 5
    local mType = (mdef and (mdef.type or mdef.kind)) or "NORMAL"
    local power = (mdef and mdef.power and mdef.power > 0) and tostring(mdef.power) or "---"
    local acc = (mdef and mdef.accuracy and mdef.accuracy > 0) and tostring(mdef.accuracy) or "---"
    out[5] = {
      id = newId,
      name = name,
      pp = maxPp,
      maxPp = maxPp,
      type = mType,
      power = power,
      accuracy = acc,
    }
  end

  return out
end

function SummaryMenu.isOpen()
  return SummaryMenu.open
end

function SummaryMenu.openMenu(party, startIndex, opts)
  opts = opts or {}
  SummaryMenu.open = true
  SummaryMenu._party = party or {}
  SummaryMenu._cursor = startIndex or 1
  local session = opts.playerState or opts.session
    or (package.loaded["src.core.game3.runtime"] and package.loaded["src.core.game3.runtime"].getSession and package.loaded["src.core.game3.runtime"].getSession())
  SummaryMenu._playerState = session
  SummaryMenu._context = opts.context or "party"
  SummaryMenu._onClose = opts.onClose
  SummaryMenu._mode = opts.mode -- "select_move" | "party" | nil
  SummaryMenu._enemyParty = opts.enemyParty and true or false
  SummaryMenu._owner = opts.owner
  SummaryMenu._moveToLearn = opts.moveToLearn or opts.moveId
  SummaryMenu._forgetMove = opts.forgetMove == true
  SummaryMenu._onSelectMove = opts.onSelectMove
  SummaryMenu._hmNotice = false
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
  SummaryMenu._slide.active = false

  local mon = current_mon()
  if mon and Pokemon.isEgg(mon) then
    SummaryMenu._page = PAGE_EGG
  elseif SummaryMenu._mode == "select_move" then
    SummaryMenu._page = PAGE_MOVES_INFO
  else
    SummaryMenu._page = tonumber(opts.page) or PAGE_INFO
  end

  SummaryChrome.install(opts.cache)
  Stack.push("summary", SummaryMenu, { hideBelow = true })
  -- pokefirered/src/pokemon_summary_screen.c:1111
  play_mon_cry()
end

function SummaryMenu.close()
  SummaryMenu.open = false
  SummaryMenu._slide.active = false
  SummaryMenu._swapSlot = nil
  SummaryMenu._mode = nil
  SummaryMenu._moveToLearn = nil
  SummaryMenu._forgetMove = false
  local selectCb = SummaryMenu._onSelectMove
  SummaryMenu._onSelectMove = nil
  Stack.pop("summary")
  if SummaryMenu._onClose then
    local cb = SummaryMenu._onClose
    SummaryMenu._onClose = nil
    cb()
  end
  if selectCb then
    selectCb(nil)
  end
end

local function change_mon(delta)
  local n = party_count()
  if n <= 1 then return end
  local nextCursor = ((SummaryMenu._cursor - 1 + delta) % n) + 1
  SummaryMenu._cursor = nextCursor
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
  local mon = current_mon()
  if mon and Pokemon.isEgg(mon) then
    SummaryMenu._page = PAGE_EGG
  elseif SummaryMenu._page == PAGE_EGG then
    SummaryMenu._page = PAGE_INFO
  end
  -- pokefirered/src/pokemon_summary_screen.c:5153
  play_mon_cry()
end

local function start_page_slide(newPage, dir)
  if SummaryMenu._page == newPage then return end
  SummaryMenu._slide.active = true
  SummaryMenu._slide.direction = dir
  SummaryMenu._slide.timer = 0
  SummaryMenu._slide.prevPage = SummaryMenu._page
  SummaryMenu._page = newPage
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
end

function SummaryMenu.update(dt)
  dt = tonumber(dt) or (1 / 60)
  if SummaryMenu._slide.active then
    SummaryMenu._slide.timer = SummaryMenu._slide.timer + dt
    if SummaryMenu._slide.timer >= SummaryMenu._slide.duration then
      SummaryMenu._slide.active = false
    end
  end
end

-- pokefirered/src/pokemon_summary_screen.c:3796
local function select_move_step(moves, cur, dir)
  if dir < 0 then
    if cur <= 1 then return 5 end
    for i = cur - 1, 1, -1 do
      if moves[i] then return i end
    end
    return cur
  end
  if cur >= 5 then return 1 end
  for i = cur + 1, 4 do
    if moves[i] then return i end
  end
  return 5
end

function SummaryMenu.handleInput(input)
  if not input then return end
  if SummaryMenu._slide.active then
    if SummaryMenu._slide.timer >= SummaryMenu._slide.duration then
      SummaryMenu._slide.active = false
    else
      return
    end
  end

  local mon = current_mon()
  if not mon then
    if input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("start") then
      SummaryMenu.close()
    end
    return
  end

  -- Select move mode for move replacement (1:1 pret ShowSelectMovePokemonSummaryScreen)
  if SummaryMenu._mode == "select_move" then
    local moves = moves_for_mon(mon)

    if input:wasPressed("up") then
      SummaryMenu._moveCursor = select_move_step(moves, SummaryMenu._moveCursor, -1)
      SummaryMenu._hmNotice = false
      pcall(function() require("src.core.game3.audio").playSe(5) end)
    elseif input:wasPressed("down") then
      SummaryMenu._moveCursor = select_move_step(moves, SummaryMenu._moveCursor, 1)
      SummaryMenu._hmNotice = false
      pcall(function() require("src.core.game3.audio").playSe(5) end)
    elseif input:wasPressed("a") then
      if SummaryMenu._moveCursor <= 4 then
        local chosenMove = moves[SummaryMenu._moveCursor]
        local moveId = chosenMove and chosenMove.id
        -- pokefirered/src/pokemon_summary_screen.c:3772
        if moveId and Pokemon.isHmMove(moveId) and not SummaryMenu._forgetMove then
          pcall(function() require("src.core.game3.audio").playSe(26) end)
          -- pokefirered/src/pokemon_summary_screen.c:3864
          SummaryMenu._hmNotice = true
        else
          pcall(function() require("src.core.game3.audio").playSe(5) end)
          local slotIdx = SummaryMenu._moveCursor - 1 -- 0-indexed (0..3)
          local cb = SummaryMenu._onSelectMove
          SummaryMenu._onSelectMove = nil
          SummaryMenu.close()
          if cb then cb(slotIdx) end
        end
      else
        -- Selected 5th slot (the move to learn / cancel)
        pcall(function() require("src.core.game3.audio").playSe(5) end)
        local cb = SummaryMenu._onSelectMove
        SummaryMenu._onSelectMove = nil
        SummaryMenu.close()
        if cb then cb(nil) end
      end
    elseif input:wasPressed("b") then
      -- pokefirered/src/pokemon_summary_screen.c:3868
      local cb = SummaryMenu._onSelectMove
      SummaryMenu._onSelectMove = nil
      SummaryMenu.close()
      if cb then cb(nil) end
    end
    return
  end

  -- Egg page navigation
  if SummaryMenu._page == PAGE_EGG then
    if input:wasPressed("up") then
      change_mon(-1)
    elseif input:wasPressed("down") then
      change_mon(1)
    elseif input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("start") then
      SummaryMenu.close()
    end
    return
  end

  -- Move detail & swap mode
  if SummaryMenu._page == PAGE_MOVES_INFO then
    local moves = moves_for_mon(mon)
    local nMoves = #moves
    if nMoves < 1 then nMoves = 1 end

    if input:wasPressed("up") then
      SummaryMenu._moveCursor = ((SummaryMenu._moveCursor - 2) % nMoves) + 1
    elseif input:wasPressed("down") then
      SummaryMenu._moveCursor = (SummaryMenu._moveCursor % nMoves) + 1
    elseif input:wasPressed("a") then
      if SummaryMenu._swapSlot == nil then
        -- pokefirered/src/pokemon_summary_screen.c:3604
        local Battle = package.loaded["src.core.game3.battle"]
        local inBattle = Battle and Battle.isActive and Battle.isActive()
        if not (SummaryMenu._enemyParty or inBattle or SummaryMenu._mode == "trade") then
          -- Begin move swap
          SummaryMenu._swapSlot = SummaryMenu._moveCursor
        end
      else
        -- Complete atomic move swap
        local slotA = SummaryMenu._swapSlot
        local slotB = SummaryMenu._moveCursor
        SummaryMenu._swapSlot = nil
        Pokemon.swapMoves(mon, slotA, slotB)
      end
    elseif input:wasPressed("b") then
      if SummaryMenu._swapSlot ~= nil then
        -- Cancel swapping
        SummaryMenu._swapSlot = nil
      else
        -- Return to regular moves page
        SummaryMenu._page = PAGE_MOVES
      end
    end
    return
  end

  -- Standard 3-page summary
  if input:wasPressed("left") then
    if SummaryMenu._page == PAGE_INFO then
      start_page_slide(PAGE_MOVES, -1)
    elseif SummaryMenu._page == PAGE_SKILLS then
      start_page_slide(PAGE_INFO, -1)
    elseif SummaryMenu._page == PAGE_MOVES then
      start_page_slide(PAGE_SKILLS, -1)
    end
  elseif input:wasPressed("right") then
    if SummaryMenu._page == PAGE_INFO then
      start_page_slide(PAGE_SKILLS, 1)
    elseif SummaryMenu._page == PAGE_SKILLS then
      start_page_slide(PAGE_MOVES, 1)
    elseif SummaryMenu._page == PAGE_MOVES then
      start_page_slide(PAGE_INFO, 1)
    end
  elseif input:wasPressed("up") then
    change_mon(-1)
  elseif input:wasPressed("down") then
    change_mon(1)
  elseif input:wasPressed("a") then
    if SummaryMenu._page == PAGE_MOVES then
      SummaryMenu._page = PAGE_MOVES_INFO
      SummaryMenu._moveCursor = 1
      SummaryMenu._swapSlot = nil
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    SummaryMenu.close()
  end
end

local function draw_text(str, x, y, maxW, colorKey)
  local colors = STAT_COLORS[colorKey] or FrlgFont.COLOR.NORMAL
  FrlgFont.draw(tostring(str or ""), x, y, {
    maxWidth = maxW,
    colors = colors,
  })
end

local function coords()
  local m = SummaryChrome.manifest()
  return (m and m.coords) or {}
end

local function move_slots()
  local m = SummaryChrome.manifest()
  return (m and m.moveSlots) or {}
end

local function moves_info_coords()
  local m = SummaryChrome.manifest()
  return (m and m.movesInfo) or {}
end

local function cxy(key, fx, fy)
  local c = coords()[key]
  if c then return c.x or fx or 0, c.y or fy or 0 end
  return fx or 0, fy or 0
end

local function species_name(mon)
  local species = Pokemon.speciesOf(mon)
  if Pokemon.name then
    local n = Pokemon.name(species)
    if n and n ~= "" then return n end
  end
  return Pokemon.displayName(mon)
end

-- pokefirered/src/pokemon.c:5834, :5210-5216
function SummaryMenu.dexNumber(species, session)
  local sp = tonumber(species) or 0
  local nat = (sp ~= 0 and Pokemon.national and Pokemon.national(sp)) or 0
  if nat > (Dex.KANTO_MAX or 151) and not PokedexData.isNationalUnlocked(session) then
    return nil
  end
  return nat
end

-- pokefirered/src/pokemon_summary_screen.c:2088
function SummaryMenu.dexNoText(mon, session)
  local nat = SummaryMenu.dexNumber(Pokemon.speciesOf(mon), session)
  if not nat then return RomText.plain("gText_PokeSum_DexNoUnknown") end
  return string.format("%03d", nat)
end

-- pokefirered/src/pokemon_summary_screen.c:4736
function SummaryMenu.showsPokerusIcon(mon)
  if not mon then return false end
  return not Pokemon.hasPokerus(mon) and Pokemon.hasHadPokerus(mon)
end

local function draw_header(mon)
  local c = coords()
  local species = Pokemon.speciesOf(mon)
  local isMovesPage = (SummaryMenu._page == PAGE_MOVES or SummaryMenu._page == PAGE_MOVES_INFO)

  -- Nickname + level + gender live in the left LVL_NICK strip (not the right pane).
  local nick = Pokemon.displayName(mon)
  local nx, ny = cxy("name", 40, 18)
  draw_text(nick, nx, ny, 64, "NORMAL")

  -- In pret pokefirered (pokemon_summary_screen.c:2430), Level is NOT printed on PAGE_MOVES_INFO
  if SummaryMenu._page ~= PAGE_MOVES_INFO then
    local lv = tonumber(mon.level) or 1
    local lx, ly = cxy("level", 4, 18)
    -- src/pokemon_summary_screen.c:2137
    draw_text(RomText.plain("gText_Lv") .. lv, lx, ly, 36, "NORMAL")
  end

  local gender = SummaryData.gender(mon)
  local gx, gy = cxy("gender", 105, 18)
  if gender == "M" then
    FrlgFont.draw("♂", gx, gy, { colors = FrlgFont.COLOR.MALE, small = false })
  elseif gender == "F" then
    FrlgFont.draw("♀", gx, gy, { colors = FrlgFont.COLOR.FEMALE, small = false })
  end

  if SummaryData.isShiny(mon) then
    local sx, sy = 8, isMovesPage and 24 or 40
    SummaryChrome.drawShinyStar(sx, sy)
  end

  local ailment = SummaryData.statusAilment(mon)
  if ailment > 0 then
    local ax, ay = 16, isMovesPage and 44 or 38
    SummaryChrome.drawStatusIcon(ax, ay, ailment)
  end

  -- pokefirered/src/pokemon_summary_screen.c:4716
  if SummaryMenu.showsPokerusIcon(mon) then
    SummaryChrome.drawPokerus(110, 88)
  end

  -- In pret pokefirered (pokemon_summary_screen.c:1635, 1681, 1979-1984, 4139-4175):
  -- On PAGE_MOVES (Known Moves) and PAGE_MOVES_INFO (Move Details), the large 64x64 front pic is HIDDEN.
  -- Instead, the 32x32 party mon icon is displayed below the level/name plate at (24, 34).
  if isMovesPage then
    local icon = Pokemon.monIcon(mon)
    if icon and icon.image and love and love.graphics then
      local iw = icon.w or 32
      local ih = icon.h or 32
      love.graphics.setColor(1, 1, 1, 1)
      local q = icon.quads and icon.quads[0]
      if q then
        love.graphics.draw(icon.image, q, 24 - iw / 2, 34 - ih / 2)
      else
        love.graphics.draw(icon.image, 24 - iw / 2, 34 - ih / 2)
      end
    end
  else
    local pic = c.monPic or { x = 60, y = 65 }
    local cx, cy = pic.x or 60, pic.y or 65
    local front = Pokemon.monFrontPic(mon)
    if front and front.image and love and love.graphics then
      local iw = front.w or 64
      local ih = front.h or 64
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(front.image, cx - iw / 2, cy - ih / 2)
    else
      local icon = Pokemon.monIcon(mon)
      if icon and icon.image and love and love.graphics then
        local iw = icon.w or 32
        local ih = icon.h or 32
        love.graphics.setColor(1, 1, 1, 1)
        local q = icon.quads and icon.quads[0]
        if q then
          love.graphics.draw(icon.image, q, cx - iw / 2, cy - ih / 2)
        else
          love.graphics.draw(icon.image, cx - iw / 2, cy - ih / 2)
        end
      end
    end
  end
end


local function draw_page_info(mon)
  local species = Pokemon.speciesOf(mon)
  local t1 = mon.type1 or (Pokemon.types and Pokemon.types(species) and Pokemon.types(species)[1]) or "NORMAL"
  local t2 = mon.type2 or (Pokemon.types and Pokemon.types(species) and Pokemon.types(species)[2])

  local dx, dy = cxy("dexNo", 167, 21)
  draw_text(SummaryMenu.dexNoText(mon, SummaryMenu._playerState), dx, dy, 40, "NORMAL")

  local sx, sy = cxy("species", 167, 35)
  draw_text(species_name(mon), sx, sy, 64, "NORMAL")

  local t1x, t1y = cxy("type1", 167, 51)
  SummaryChrome.drawTypeBadge(t1, t1x, t1y)
  if t2 and t2 ~= t1 and t2 ~= "" then
    local t2x, t2y = cxy("type2", 203, 51)
    SummaryChrome.drawTypeBadge(t2, t2x, t2y)
  end

  local pState = SummaryMenu._playerState
    or (package.loaded["src.core.game3.runtime"] and package.loaded["src.core.game3.runtime"].getSession and package.loaded["src.core.game3.runtime"].getSession())
  local otName = mon.otName or mon.ot or mon.originalTrainer or (pState and (pState.name or pState.playerName)) or "RED"
  local ox, oy = cxy("otName", 167, 65)
  draw_text(otName, ox, oy, 60, "NORMAL")

  local otId = tonumber(mon.otId or mon.ot_id or mon.trainerId or (pState and (pState.trainerId or pState.id or pState.playerId))) or 0
  local ix, iy = cxy("otId", 167, 80)
  draw_text(string.format("%05d", bit.band(otId, 0xFFFF)), ix, iy, 48, "NORMAL")

  local itx, ity = cxy("item", 167, 95)
  draw_text(SummaryMenu.heldItemText(mon), itx, ity, 64, "NORMAL")

  local memo = coords().memo or { x = 8, y = 115, w = 224 }
  local memoLines = SummaryData.formatTrainerMemo(mon, SummaryMenu._playerState,
    { enemyParty = SummaryMenu._enemyParty, owner = SummaryMenu._owner })
  local memoY = memo.y or 115
  for _, line in ipairs(memoLines) do
    draw_text(line, memo.x or 8, memoY, memo.w or 224, "NORMAL")
    memoY = memoY + 14
  end
end

local function draw_page_skills(mon)
  local curHp = tonumber(mon.hp or mon.currentHp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local hx, hy = cxy("hpText", 174, 20)
  draw_text(string.format("%d/%d", curHp, maxHp), hx, hy, 56, "NORMAL")

  local bar = coords().hpBar or { x = 168, y = 32 }
  SummaryChrome.drawHpBar(bar.x or 168, bar.y or 32, curHp, maxHp)

  local natureId = SummaryData.nature(mon)
  local stats = {
    { key = "atk", val = mon.attack or mon.atk or 0, coord = "atk", fy = 38 },
    { key = "def", val = mon.defense or mon.def or 0, coord = "def", fy = 51 },
    { key = "spAtk", val = mon.spAtk or mon.spatk or 0, coord = "spAtk", fy = 64 },
    { key = "spDef", val = mon.spDef or mon.spdef or 0, coord = "spDef", fy = 77 },
    { key = "spd", val = mon.speed or mon.spe or 0, coord = "spd", fy = 90 },
  }

  for _, st in ipairs(stats) do
    local mod = SummaryData.natureStatModifier(natureId, st.key)
    local color = "NORMAL"
    if mod > 1.0 then color = "UP"
    elseif mod < 1.0 then color = "DOWN" end
    local x, y = cxy(st.coord, 210, st.fy)
    draw_text(string.format("%d", tonumber(st.val) or 0), x, y, 32, color)
  end

  local lx, ly = cxy("expPointsLabel", 74, 103)
  draw_text(RomText.plain("gText_PokeSum_ExpPoints"), lx, ly, 96, "NORMAL")
  local nlx, nly = cxy("nextLvLabel", 74, 116)
  draw_text(RomText.plain("gText_PokeSum_NextLv"), nlx, nly, 96, "NORMAL")

  local prog = SummaryData.expProgress(mon)
  local ex, ey = cxy("expTotal", 175, 103)
  draw_text(string.format("%d", prog.totalExp), ex, ey, 56, "NORMAL")
  local nx, ny = cxy("expNext", 175, 116)
  draw_text(string.format("%d", prog.expNeeded), nx, ny, 56, "NORMAL")

  local expBar = coords().expBar or { x = 152, y = 128 }
  SummaryChrome.drawExpBar(expBar.x or 152, expBar.y or 128, prog.progressPercent)

  -- Party stores ability as numeric id (e.g. 65 = OVERGROW); resolve to name.
  local abilityId = tonumber(mon.abilityId) or tonumber(mon.ability)
  local ability = mon.abilityName
  if type(mon.ability) == "string" and mon.ability ~= "" and not tonumber(mon.ability) then
    ability = mon.ability
  end
  if (not ability or ability == "") and abilityId and abilityId > 0 then
    ability = Pokemon.abilityName(abilityId)
  end
  if not ability or ability == "" then
    local aid = Pokemon.abilityId and Pokemon.abilityId(Pokemon.speciesOf(mon), mon.personality or 0)
    if aid and aid > 0 then
      abilityId = aid
      ability = Pokemon.abilityName(aid)
    end
  end
  ability = ability or "—"
  local ax, ay = cxy("abilityName", 74, 129)
  -- No registry renames abilities; a translation reaches the name through Strings().
  draw_text(Strings(tostring(ability)), ax, ay, 80, "NORMAL")
  local desc = SummaryData.abilityDescription(abilityId, tostring(ability))
  local ad = coords().abilityDesc or { x = 10, y = 143, w = 232 }
  draw_text(desc, ad.x or 10, ad.y or 143, ad.w or 232, "NORMAL")
end


-- pret prints each move name at x 3 of POKESUM_WIN_MOVES_3, a 10-tile window
-- starting at tile 20 (pokemon_summary_screen.c:857, :2543), so a name has up
-- to that window's right edge -- the edge of the screen -- which is 77 px from
-- the usual pen at 163.  The cart's own names reach 72 px (SKY UPPERCUT,
-- FRENZY PLANT), and a translated one can use the rest.
local MOVE_NAME_RIGHT = (20 + 10) * 8

local function draw_page_moves(mon, isDetail)
  local moves = moves_for_mon(mon)
  local slots = move_slots()
  local maxSlot = (SummaryMenu._mode == "select_move") and 5 or 4

  for i = 1, maxSlot do
    local slot = slots[i] or {
      nameX = 163, nameY = 21 + (i - 1) * 28,
      typeX = 123, typeY = 21 + (i - 1) * 28,
      ppX = 196, ppY = 32 + (i - 1) * 28,
    }
    local m = moves[i]
    if m then
      SummaryChrome.drawTypeBadge(m.type, slot.typeX, slot.typeY)
      draw_text(m.name, slot.nameX, slot.nameY, MOVE_NAME_RIGHT - slot.nameX, "NORMAL")
      draw_text(string.format("%d/%d", m.pp, m.maxPp), slot.ppX, slot.ppY, 40, "NORMAL")
    elseif i == 5 and SummaryMenu._forgetMove then
      -- pokefirered/src/pokemon_summary_screen.c:2526
      draw_text(RomText.plain("gFameCheckerText_Cancel"), slot.nameX, slot.nameY, MOVE_NAME_RIGHT - slot.nameX, "NORMAL")
    else
      draw_text("-", slot.typeX + 8, slot.typeY + 2, 16, "NORMAL")
      draw_text("----------", slot.nameX, slot.nameY, 64, "NORMAL")
    end
  end

  if isDetail then
    local curY = 18 + (SummaryMenu._moveCursor - 1) * 28
    SummaryChrome.drawMoveSelectionCursor(120, curY, false)
    if SummaryMenu._swapSlot then
      local swapY = 18 + (SummaryMenu._swapSlot - 1) * 28
      SummaryChrome.drawMoveSelectionCursor(120, swapY, true)
    end

    local selMove = moves[SummaryMenu._moveCursor]
    if SummaryMenu._hmNotice then
      local descBox = moves_info_coords().desc or { x = 7, y = 98, w = 112 }
      -- pokefirered/src/strings.c:844
      draw_text(RomText.plain("gText_PokeSum_HmMovesCantBeForgotten"), descBox.x, descBox.y, descBox.w or 112, "NORMAL")
    elseif selMove then
      local mi = moves_info_coords()
      local power = mi.power or { x = 57, y = 57 }
      local accuracy = mi.accuracy or { x = 57, y = 71 }
      local descBox = mi.desc or { x = 7, y = 98, w = 112 }
      draw_text(selMove.power, power.x, power.y, 32, "NORMAL")
      draw_text(selMove.accuracy, accuracy.x, accuracy.y, 32, "NORMAL")
      local desc = SummaryData.moveDescription(selMove.id, selMove.name)
      draw_text(desc, descBox.x, descBox.y, descBox.w or 112, "NORMAL")
    end
  end
end

local function draw_page_egg(mon)
  -- pokefirered/src/pokemon_summary_screen.c:4016 MON_DATA_SPECIES_OR_EGG
  local species = Pokemon.speciesOrEgg(mon)
  local nx, ny = cxy("name", 40, 18)
  draw_text(RomText.plain("gText_EggNickname"), nx, ny, 64, "NORMAL")

  local pic = coords().monPic or { x = 60, y = 65 }
  local cx, cy = pic.x or 60, pic.y or 65
  local front = Pokemon.frontPic(species)
  if front and front.image and love and love.graphics then
    local iw = front.w or 64
    local ih = front.h or 64
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(front.image, cx - iw / 2, cy - ih / 2)
  end


  local memo = coords().memo or { x = 8, y = 115, w = 224 }
  local memoLines = SummaryData.formatTrainerMemo(mon, SummaryMenu._playerState,
    { enemyParty = SummaryMenu._enemyParty, owner = SummaryMenu._owner })
  local memoY = memo.y or 80
  for _, line in ipairs(memoLines) do
    draw_text(line, memo.x or 8, memoY, memo.w or 224, "NORMAL")
    memoY = memoY + 28
  end
end

-- src/pokemon_summary_screen.c:2934
local PAGE_TITLES = RomText.lazy({
  [PAGE_INFO] = "gText_PokeSum_PageName_PokemonInfo",
  [PAGE_SKILLS] = "gText_PokeSum_PageName_PokemonSkills",
  [PAGE_MOVES] = "gText_PokeSum_PageName_KnownMoves",
  [PAGE_MOVES_INFO] = "gText_PokeSum_PageName_KnownMoves",
  [PAGE_EGG] = "gText_PokeSum_PageName_PokemonInfo",
})

local function summary_in_battle()
  local Battle = package.loaded["src.core.game3.battle"]
  return (Battle and Battle.isActive and Battle.isActive()) and true or false
end

local function get_controls_str(page, isEgg)
  if SummaryMenu._mode == "select_move" then
    -- src/pokemon_summary_screen.c:2954
    if summary_in_battle() then
      return RomText.plain("gText_PokeSum_Controls_Pick")
    end
    return RomText.plain("gText_PokeSum_Controls_PickSwitch")
  end
  if isEgg then
    return RomText.plain("gText_PokeSum_Controls_Cancel")
  end
  if page == PAGE_INFO then
    return RomText.plain("gText_PokeSum_Controls_PageCancel")
  elseif page == PAGE_SKILLS then
    return RomText.plain("gText_PokeSum_Controls_Page")
  elseif page == PAGE_MOVES then
    return RomText.plain("gText_PokeSum_Controls_PageDetail")
  elseif page == PAGE_MOVES_INFO then
    -- src/pokemon_summary_screen.c:1365
    if summary_in_battle() or SummaryMenu._mode == "trade" then
      return RomText.plain("gText_PokeSum_Controls_Pick")
    end
    return RomText.plain("gText_PokeSum_Controls_PickSwitch")
  end
  return RomText.plain("gText_PokeSum_Controls_Page")
end

SummaryMenu.controlsString = get_controls_str

local function draw_top_bar_text(page, isEgg)
  local title = PAGE_TITLES[page]
  FrlgFont.draw(title, 4, 1, {
    colors = FrlgFont.COLOR.WHITE,
    small = false,
  })

  local ctrl = get_controls_str(page, isEgg)
  PokedexChrome.drawControlInfo(ctrl, 236, 1)
end

function SummaryMenu.draw()
  if not SummaryMenu.open then return end
  local mon = current_mon()
  if not mon then return end

  -- 1. BACKGROUND LAYER (Transforms during page slide transitions)
  if SummaryMenu._slide.active then
    local p = SummaryMenu._slide.timer / SummaryMenu._slide.duration
    p = math.max(0.0, math.min(1.0, p))
    local dir = SummaryMenu._slide.direction
    local curOffset = math.floor(240 * (1.0 - p) * dir)
    local prevOffset = math.floor(-240 * p * dir)

    SummaryChrome.drawPageBg(SummaryMenu._slide.prevPage, prevOffset)
    SummaryChrome.drawPageBg(SummaryMenu._page, curOffset)
  else
    SummaryChrome.drawPageBg(SummaryMenu._page, 0)
  end

  -- 2. OVERLAY LAYER (Foreground elements anchored to screen coordinates)
  draw_top_bar_text(SummaryMenu._page, Pokemon.isEgg(mon))
  if SummaryMenu._page == PAGE_EGG then
    draw_page_egg(mon)
  else
    draw_header(mon)
    if SummaryMenu._page == PAGE_INFO then
      draw_page_info(mon)
    elseif SummaryMenu._page == PAGE_SKILLS then
      draw_page_skills(mon)
    elseif SummaryMenu._page == PAGE_MOVES then
      draw_page_moves(mon, false)
    elseif SummaryMenu._page == PAGE_MOVES_INFO then
      draw_page_moves(mon, true)
    end
  end
end

return SummaryMenu

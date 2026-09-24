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
  kind = "page",
  direction = 0,
  frame = 0,
  prevPage = 0,
  queued = nil,
}
SummaryMenu._tick = 0
SummaryMenu._bounce = { dy = 0, dx = 0, delay = 0, anim = 0, count = 2, vigor = 0, egg = false }
SummaryMenu._blink = { frame = 0, hidden = false }

local PAGE_INFO = 0
local PAGE_SKILLS = 1
local PAGE_MOVES = 2
local PAGE_MOVES_INFO = 3
local PAGE_EGG = 4

SummaryMenu.PAGE_INFO = PAGE_INFO
SummaryMenu.PAGE_SKILLS = PAGE_SKILLS
SummaryMenu.PAGE_MOVES = PAGE_MOVES
SummaryMenu.PAGE_MOVES_INFO = PAGE_MOVES_INFO
SummaryMenu.PAGE_EGG = PAGE_EGG

-- pokefirered/src/pokemon_summary_screen.c:3058
local SLIDE_STEP = 60
local SLIDE_FRAMES = 240 / SLIDE_STEP

-- pokefirered/src/pokemon_summary_screen.c:1233
local FLIP_TIMING = {
  page = { delay = 6, header = 6, text = 14, done = 15 },
  -- pokefirered/src/pokemon_summary_screen.c:1332
  detail = { delay = 8, hide = 4, bg = 7, header = 7, list5 = 9, bottom = 13, show = 15, name = 16, done = 17 },
  -- pokefirered/src/pokemon_summary_screen.c:1443
  back = { delay = 7, list5 = 5, bottom = 5, header = 7, hide = 8, name = 13, bg = 14, show = 14, done = 15 },
}
SummaryMenu.FLIP_TIMING = FLIP_TIMING

-- pokefirered/src/pokemon_summary_screen.c:3956
local EGG_SHAKE_DELAY = { [0] = 120, [1] = 90, [2] = 60 }

local STAT_COLORS = {
  NORMAL = FrlgFont.COLOR.NORMAL,
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

-- pokefirered/src/pokemon_summary_screen.c:2297
local function power_accuracy(mdef)
  local none = RomText.plain("gText_ThreeHyphens")
  local power = (mdef and mdef.power and mdef.power > 1) and tostring(mdef.power) or none
  local acc = (mdef and mdef.accuracy and mdef.accuracy > 0) and tostring(mdef.accuracy) or none
  return power, acc
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
      local power, acc = power_accuracy(mdef)
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
    local power, acc = power_accuracy(mdef)
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
  -- pokefirered/src/pokemon_summary_screen.c:1046
  SummaryMenu._slide.queued = nil
  SummaryMenu._tick = 0

  local mon = current_mon()
  if mon and Pokemon.isEgg(mon) then
    SummaryMenu._page = PAGE_EGG
  elseif SummaryMenu._mode == "select_move" then
    SummaryMenu._page = PAGE_MOVES_INFO
  else
    SummaryMenu._page = tonumber(opts.page) or PAGE_INFO
  end

  SummaryChrome.install(opts.cache)
  SummaryMenu.resetPicBounce()
  Stack.push("summary", SummaryMenu, { hideBelow = true, fullscreen = true })
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
  SummaryMenu.resetPicBounce()
  -- pokefirered/src/pokemon_summary_screen.c:5153
  play_mon_cry()
end

local function start_slide(kind, newPage, dir)
  if SummaryMenu._page == newPage then return end
  SummaryMenu._slide.active = true
  SummaryMenu._slide.kind = kind
  SummaryMenu._slide.direction = dir
  SummaryMenu._slide.frame = 0
  SummaryMenu._slide.prevPage = SummaryMenu._page
  SummaryMenu._page = newPage
  SummaryMenu._swapSlot = nil
end

local function ailment_blocks_bounce(ailment)
  return ailment ~= 0 and ailment ~= 6
end

-- pokefirered/src/pokemon_summary_screen.c:4048
function SummaryMenu.resetPicBounce()
  local b = SummaryMenu._bounce
  b.dy, b.dx, b.delay, b.anim, b.count, b.vigor, b.egg = 0, 0, 0, 0, 2, 0, false
  local mon = current_mon()
  if not mon then return end
  if Pokemon.isEgg(mon) then
    local cycles = SummaryData.eggCycles(mon)
    b.egg = true
    -- pokefirered/src/pokemon_summary_screen.c:4054
    if cycles <= 5 then b.vigor = 2
    elseif cycles <= 10 then b.vigor = 1 end
    b.count = 0
    return
  end
  if ailment_blocks_bounce(SummaryData.statusAilment(mon)) then return end
  local curHp = tonumber(mon.hp or mon.currentHp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 0
  if curHp == maxHp then b.vigor = 4
  elseif maxHp * 0.8 <= curHp then b.vigor = 3
  elseif maxHp * 0.6 <= curHp then b.vigor = 2
  else b.vigor = 1 end
  b.count = 0
end

-- pokefirered/src/pokemon_summary_screen.c:3916
local function step_pic_bounce()
  local b = SummaryMenu._bounce
  if b.count >= 2 then return end
  local m = SummaryChrome.manifest()
  local deltas = m and m.monPicBounce and m.monPicBounce[b.vigor]
  if not deltas or #deltas == 0 then return end
  local ready = b.delay >= 2
  b.delay = b.delay + 1
  if not ready then return end
  b.anim = b.anim + 1
  b.dy = b.dy + (deltas[b.anim] or 0)
  if b.anim >= #deltas then
    b.anim = 0
    b.count = b.count + 1
  end
  b.delay = 0
end

-- pokefirered/src/pokemon_summary_screen.c:3956
local function step_egg_shake()
  local b = SummaryMenu._bounce
  if b.count >= 2 then return end
  local deltas = SummaryChrome.manifest().eggPicShake[b.vigor + 1]
  local ready = b.delay >= EGG_SHAKE_DELAY[b.vigor]
  b.delay = b.delay + 1
  if not ready then return end
  b.anim = b.anim + 1
  b.dx = b.dx + (deltas[b.anim] or 0)
  if b.anim >= #deltas then
    b.anim = 0
    b.delay = 0
    b.count = b.count + 1
  end
end

-- pokefirered/src/pokemon_summary_screen.c:4247
local function step_swap_blink()
  local bl = SummaryMenu._blink
  if not SummaryMenu._swapSlot then
    bl.frame, bl.hidden = 0, false
    return
  end
  bl.frame = bl.frame + 1
  if bl.frame > 60 then
    bl.hidden = not bl.hidden
    bl.frame = 0
  end
end

local function step_frame()
  local s = SummaryMenu._slide
  if s.active then
    s.frame = s.frame + 1
    if s.frame >= FLIP_TIMING[s.kind].done then s.active = false end
  end
  if SummaryMenu._bounce.egg then step_egg_shake() else step_pic_bounce() end
  step_swap_blink()
end

function SummaryMenu.update(dt)
  dt = tonumber(dt) or (1 / 60)
  SummaryMenu._tick = (SummaryMenu._tick or 0) + dt * 60
  while SummaryMenu._tick >= 0.999 do
    SummaryMenu._tick = SummaryMenu._tick - 1
    step_frame()
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

-- pokefirered/src/pokemon_summary_screen.c:3506
function SummaryMenu.detailCursorStep(moves, pos, dir, swapping)
  local function has(i) return i <= 3 and moves[i + 1] ~= nil end
  if dir < 0 then
    if pos > 0 then
      for i = pos, 1, -1 do
        if has(i - 1) then return i - 1 end
      end
      return pos
    end
    if swapping then
      for i = 4, 1, -1 do
        if has(i - 1) then return i - 1 end
      end
    end
    return 4
  end
  if pos < 4 then
    local last = 4
    if swapping then
      if pos == 3 then return 0 end
      last = 3
    end
    local i = pos
    while i < last do
      if has(i + 1) then return i + 1 end
      i = i + 1
    end
    return swapping and 0 or i
  end
  return 0
end

local function lr_mode()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if type(session) ~= "table" then return false end
  return require("src.core.game3.options").lrMode(session)
end

-- pokefirered/src/pokemon_summary_screen.c:1064
local function page_flip_input(input, dir)
  local s = SummaryMenu._slide
  if s.queued == dir then
    s.queued = nil
    return true
  end
  -- pokefirered/src/pokemon_summary_screen.c:1056
  if s.active and s.direction ~= dir then return false end
  if dir > 0 then
    return input:wasPressed("right") or (lr_mode() and input:wasPressed("r")) and true or false
  end
  return input:wasPressed("left") or (lr_mode() and input:wasPressed("l")) and true or false
end

function SummaryMenu.handleInput(input)
  if not input then return end
  local slide = SummaryMenu._slide
  if slide.active then
    -- pokefirered/src/pokemon_summary_screen.c:1132
    if slide.kind == "page" then
      if page_flip_input(input, 1) then
        slide.queued = 1
      elseif page_flip_input(input, -1) then
        slide.queued = -1
      end
    end
    return
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
    local swapping = SummaryMenu._swapSlot ~= nil
    local pos = SummaryMenu._moveCursor - 1

    if input:wasPressed("up") then
      SummaryMenu._moveCursor = SummaryMenu.detailCursorStep(moves, pos, -1, swapping) + 1
      pcall(function() require("src.core.game3.audio").playSe(5) end)
    elseif input:wasPressed("down") then
      SummaryMenu._moveCursor = SummaryMenu.detailCursorStep(moves, pos, 1, swapping) + 1
      pcall(function() require("src.core.game3.audio").playSe(5) end)
    elseif input:wasPressed("a") then
      pcall(function() require("src.core.game3.audio").playSe(5) end)
      if pos == 4 then
        -- pokefirered/src/pokemon_summary_screen.c:3589
        SummaryMenu._moveCursor = 1
        start_slide("back", PAGE_MOVES, -1)
      elseif not swapping then
        -- pokefirered/src/pokemon_summary_screen.c:3604
        local Battle = package.loaded["src.core.game3.battle"]
        local inBattle = Battle and Battle.isActive and Battle.isActive()
        if not (SummaryMenu._enemyParty or inBattle or SummaryMenu._mode == "trade") then
          SummaryMenu._swapSlot = SummaryMenu._moveCursor
          SummaryMenu._blink.frame, SummaryMenu._blink.hidden = 0, false
        end
      else
        local slotA = SummaryMenu._swapSlot
        local slotB = SummaryMenu._moveCursor
        SummaryMenu._swapSlot = nil
        if slotA ~= slotB then Pokemon.swapMoves(mon, slotA, slotB) end
      end
    elseif input:wasPressed("b") then
      if swapping then
        SummaryMenu._swapSlot = nil
      else
        -- pokefirered/src/pokemon_summary_screen.c:3640
        if pos == 4 then SummaryMenu._moveCursor = 1 end
        start_slide("back", PAGE_MOVES, -1)
      end
    end
    return
  end

  -- pokefirered/src/pokemon_summary_screen.c:1126
  if page_flip_input(input, 1) then
    if SummaryMenu._page < PAGE_MOVES then
      pcall(function() require("src.core.game3.audio").playSe(5) end)
      start_slide("page", SummaryMenu._page + 1, 1)
    end
  elseif page_flip_input(input, -1) then
    if SummaryMenu._page > PAGE_INFO then
      pcall(function() require("src.core.game3.audio").playSe(5) end)
      start_slide("page", SummaryMenu._page - 1, -1)
    end
  elseif input:wasPressed("up") then
    change_mon(-1)
  elseif input:wasPressed("down") then
    change_mon(1)
  elseif input:wasPressed("a") then
    -- pokefirered/src/pokemon_summary_screen.c:1178
    if SummaryMenu._page == PAGE_INFO then
      pcall(function() require("src.core.game3.audio").playSe(5) end)
      SummaryMenu.close()
    elseif SummaryMenu._page == PAGE_MOVES then
      pcall(function() require("src.core.game3.audio").playSe(5) end)
      start_slide("detail", PAGE_MOVES_INFO, 1)
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    SummaryMenu.close()
  end
end

local function draw_text(str, x, y, maxW, colorKey)
  local colors = (type(colorKey) == "table" and colorKey) or STAT_COLORS[colorKey] or FrlgFont.COLOR.NORMAL
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

-- pokefirered/src/pokemon_summary_screen.c:4108
function SummaryMenu.ballIdOf(mon)
  local BallOpen = require("src.core.game3.battle.ball_open")
  if not mon or Pokemon.isEgg(mon) then return BallOpen.ballIdForItem(0) end
  return BallOpen.ballIdForItem(mon.pokeball)
end

local function draw_ball_icon(mon)
  if not (love and love.graphics) then return end
  local Ui = require("src.core.game3.battle.ui")
  local img, quad = Ui.ballQuad(SummaryMenu.ballIdOf(mon), 0)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, 106 - 8, 88 - 8)
end

local function mon_no_flip(mon)
  local m = SummaryChrome.manifest()
  local nf = m and m.noFlip
  return (nf and nf[tonumber(Pokemon.speciesOf(mon)) or -1]) and true or false
end

local function draw_flipped(img, quad, x, y, w, flip)
  if flip then
    if quad then love.graphics.draw(img, quad, x + w, y, 0, -1, 1)
    else love.graphics.draw(img, x + w, y, 0, -1, 1) end
  elseif quad then
    love.graphics.draw(img, quad, x, y)
  else
    love.graphics.draw(img, x, y)
  end
end

-- pokefirered/src/pokemon_summary_screen.c:1615
function SummaryMenu.leftPaneSprites(page, mode)
  local function at(key, fx, fy)
    local x, y = cxy(key, fx, fy)
    return { x = x, y = y }
  end
  if page == PAGE_MOVES_INFO then
    return {
      icon = at("monIcon", 8, 16),
      -- pokefirered/src/pokemon_summary_screen.c:1976
      status = (mode == "select_move") and at("statusMovesInfo", 0, 41) or nil,
      shiny = at("shinyStarMovesInfo", 4, 20),
      pokerus = at("pokerus", 110, 88),
    }
  end
  return {
    pic = at("monPic", 60, 65),
    ball = at("ball", 106, 88),
    markings = at("markings", 4, 87),
    status = at("status", 0, 34),
    shiny = at("shinyStar", 102, 36),
    pokerus = at("pokerus", 110, 88),
  }
end

local function draw_left_sprites(mon, page)
  if not (love and love.graphics) then return end
  local s = SummaryMenu.leftPaneSprites(page, SummaryMenu._mode)
  local flip = not mon_no_flip(mon)

  if s.pic then
    local front = Pokemon.monFrontPic(mon)
    if front and front.image then
      local iw, ih = front.w or 64, front.h or 64
      love.graphics.setColor(1, 1, 1, 1)
      -- pokefirered/src/pokemon_summary_screen.c:4037
      draw_flipped(front.image, nil, s.pic.x - iw / 2, s.pic.y - ih / 2 + SummaryMenu._bounce.dy, iw, flip)
    end
  end
  if s.icon then
    local icon = Pokemon.monIcon(mon)
    if icon and icon.image then
      love.graphics.setColor(1, 1, 1, 1)
      -- pokefirered/src/pokemon_summary_screen.c:4164
      draw_flipped(icon.image, icon.quads and icon.quads[0], s.icon.x, s.icon.y, icon.w or 32, flip)
    end
  end
  if s.ball then
    draw_ball_icon(mon)
  end
  if s.markings then
    -- pokefirered/src/pokemon_summary_screen.c:4900
    SummaryChrome.drawMarkings(mon.markings, s.markings.x, s.markings.y)
  end
  local ailment = SummaryData.statusAilment(mon)
  if s.status and ailment > 0 then
    SummaryChrome.drawStatusIcon(s.status.x, s.status.y, ailment)
  end
  if s.shiny and SummaryData.isShiny(mon) then
    SummaryChrome.drawShinyStar(s.shiny.x, s.shiny.y)
  end
  -- pokefirered/src/pokemon_summary_screen.c:4736
  if s.pokerus and SummaryMenu.showsPokerusIcon(mon) then
    SummaryChrome.drawPokerus(s.pokerus.x, s.pokerus.y)
  end
end

local function draw_header(mon, showLevel, dx)
  dx = dx or 0
  if dx >= 240 then return end
  -- Nickname + level + gender live in the left LVL_NICK strip (not the right pane).
  local nick = Pokemon.displayName(mon)
  local nx, ny = cxy("name", 40, 18)
  draw_text(nick, nx + dx, ny, 64, "NORMAL")

  -- pokefirered/src/pokemon_summary_screen.c:2430
  if showLevel then
    local lv = tonumber(mon.level) or 1
    local lx, ly = cxy("level", 4, 18)
    -- src/pokemon_summary_screen.c:2137
    draw_text(RomText.plain("gText_Lv") .. lv, lx + dx, ly, 36, "NORMAL")
  end

  local gender = SummaryData.gender(mon)
  local gx, gy = cxy("gender", 105, 18)
  gx = gx + dx
  if gender == "M" then
    FrlgFont.draw("♂", gx, gy, { colors = FrlgFont.COLOR.MALE, small = false })
  elseif gender == "F" then
    FrlgFont.draw("♀", gx, gy, { colors = FrlgFont.COLOR.FEMALE, small = false })
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

-- pokefirered/src/pokemon_summary_screen.c:2148
function SummaryMenu.rightAlign(str, width)
  return width - #tostring(str) * 6
end

local function draw_skill_bars(mon, dx)
  local curHp = tonumber(mon.hp or mon.currentHp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local bar = coords().hpBar or { x = 168, y = 32 }
  SummaryChrome.drawHpBar((bar.x or 168) + dx, bar.y or 32, curHp, maxHp)
  local prog = SummaryData.expProgress(mon)
  local expBar = coords().expBar or { x = 152, y = 128 }
  SummaryChrome.drawExpBar((expBar.x or 152) + dx, expBar.y or 128, prog.progressPercent)
end

local function draw_page_skills(mon)
  local curHp = tonumber(mon.hp or mon.currentHp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local hx, hy = cxy("hpText", 174, 20)
  local hpStr = string.format("%d/%d", curHp, maxHp)
  -- pokefirered/src/pokemon_summary_screen.c:2170
  draw_text(hpStr, hx + SummaryMenu.rightAlign(hpStr, 63), hy, 63, "NORMAL")

  draw_skill_bars(mon, 0)

  local stats = {
    { val = mon.attack or mon.atk or 0, coord = "atk", fy = 38 },
    { val = mon.defense or mon.def or 0, coord = "def", fy = 51 },
    { val = mon.spAtk or mon.spatk or 0, coord = "spAtk", fy = 64 },
    { val = mon.spDef or mon.spdef or 0, coord = "spDef", fy = 77 },
    { val = mon.speed or mon.spe or 0, coord = "spd", fy = 90 },
  }

  for _, st in ipairs(stats) do
    local x, y = cxy(st.coord, 210, st.fy)
    local str = string.format("%d", tonumber(st.val) or 0)
    -- pokefirered/src/pokemon_summary_screen.c:2502
    draw_text(str, x + SummaryMenu.rightAlign(str, 27), y, 27, "NORMAL")
  end

  local lx, ly = cxy("expPointsLabel", 74, 103)
  draw_text(RomText.plain("gText_PokeSum_ExpPoints"), lx, ly, 96, "NORMAL")
  local nlx, nly = cxy("nextLvLabel", 74, 116)
  draw_text(RomText.plain("gText_PokeSum_NextLv"), nlx, nly, 96, "NORMAL")

  local prog = SummaryData.expProgress(mon)
  local ex, ey = cxy("expTotal", 175, 103)
  local expStr = string.format("%d", prog.totalExp)
  -- pokefirered/src/pokemon_summary_screen.c:2507
  draw_text(expStr, ex + SummaryMenu.rightAlign(expStr, 63), ey, 63, "NORMAL")
  local nx, ny = cxy("expNext", 175, 116)
  local nextStr = string.format("%d", prog.expNeeded)
  draw_text(nextStr, nx + SummaryMenu.rightAlign(nextStr, 63), ny, 63, "NORMAL")

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

-- pokefirered/src/pokemon_summary_screen.c:2532
function SummaryMenu.ppColorIndex(cur, max, hasMove)
  cur, max = tonumber(cur) or 0, tonumber(max) or 0
  if not hasMove or cur == max then return 0 end
  if cur == 0 then return 3 end
  if max == 3 then
    if cur == 2 then return 2 elseif cur == 1 then return 1 end
    return 0
  elseif max == 2 then
    return (cur == 1) and 1 or 0
  end
  if cur <= math.floor(max / 4) then return 2 end
  if cur <= math.floor(max / 2) then return 1 end
  return 0
end

local moveColorCache = setmetatable({}, { __mode = "k" })

-- pokefirered/src/pokemon_summary_screen.c:645
local function move_text_colors(idx)
  local m = SummaryChrome.manifest()
  local src = m and m.moveTextColors
  local c = src and src[idx]
  if not c then return "NORMAL" end
  local cache = moveColorCache[src]
  if not cache then cache = {} moveColorCache[src] = cache end
  if not cache[idx] then
    local function rgb(t) return { (t[1] or 0) / 255, (t[2] or 0) / 255, (t[3] or 0) / 255, 1 } end
    cache[idx] = { fg = rgb(c.fg), shadow = rgb(c.shadow), bg = FrlgFont.STDPAL[0] }
  end
  return cache[idx]
end

local function draw_move_row(slot, m)
  local colorIdx = SummaryMenu.ppColorIndex(m and m.pp, m and m.maxPp, m ~= nil)
  local colors = move_text_colors(colorIdx)
  if m then
    SummaryChrome.drawTypeBadge(m.type, slot.typeX, slot.typeY)
  end
  -- pokefirered/src/pokemon_summary_screen.c:2543
  draw_text(m and m.name or RomText.plain("gText_PokeSum_OneHyphen"), slot.nameX, slot.nameY,
    MOVE_NAME_RIGHT - slot.nameX, move_text_colors(0))
  draw_text(RomText.plain("gText_PokeSum_PP"), slot.ppX, slot.ppY, 16, colors)
  if not m then
    -- pokefirered/src/pokemon_summary_screen.c:2263
    draw_text(RomText.plain("gText_PokeSum_TwoHyphens"), slot.ppX + 9, slot.ppY, 24, colors)
    return
  end
  local cur, max = tostring(m.pp), tostring(m.maxPp)
  -- pokefirered/src/pokemon_summary_screen.c:2571
  draw_text(cur, slot.ppX + 10 + SummaryMenu.rightAlign(cur, 12), slot.ppY, 24, colors)
  draw_text(RomText.plain("gText_Slash"), slot.ppX + 22, slot.ppY, 8, colors)
  draw_text(max, slot.ppX + 28 + SummaryMenu.rightAlign(max, 12), slot.ppY, 24, colors)
end

local function draw_page_moves(mon, isDetail, parts)
  local moves = moves_for_mon(mon)
  local slots = move_slots()
  parts = parts or (isDetail and { rows5 = true, cursor = true, types = true, bottom = true }) or {}

  for i = 1, (parts.rows5 and 5 or 4) do
    local slot = slots[i] or {
      nameX = 163, nameY = 21 + (i - 1) * 28,
      typeX = 123, typeY = 21 + (i - 1) * 28,
      ppX = 196, ppY = 32 + (i - 1) * 28,
    }
    if i <= 4 then
      draw_move_row(slot, moves[i])
    elseif SummaryMenu._mode == "select_move" and not SummaryMenu._forgetMove then
      draw_move_row(slot, moves[5])
    else
      -- pokefirered/src/pokemon_summary_screen.c:2526
      draw_text(RomText.plain("gFameCheckerText_Cancel"), slot.nameX, slot.nameY, MOVE_NAME_RIGHT - slot.nameX, move_text_colors(0))
    end
  end

  if parts.cursor then
    if not (SummaryMenu._swapSlot and SummaryMenu._blink.hidden) then
      local curY = 18 + (SummaryMenu._moveCursor - 1) * 28
      SummaryChrome.drawMoveSelectionCursor(120, curY, false)
    end
    if SummaryMenu._swapSlot then
      local swapY = 18 + (SummaryMenu._swapSlot - 1) * 28
      SummaryChrome.drawMoveSelectionCursor(120, swapY, true)
    end
  end

  if parts.types then
    local species = Pokemon.speciesOf(mon)
    local types = Pokemon.types and Pokemon.types(species) or {}
    local t1 = mon.type1 or types[1] or "NORMAL"
    local t2 = mon.type2 or types[2]
    -- pokefirered/src/pokemon_summary_screen.c:3375
    local ax, ay = cxy("movesInfoType1", 48, 35)
    SummaryChrome.drawTypeBadge(t1, ax, ay)
    if t2 and t2 ~= t1 and t2 ~= "" then
      local bx, by = cxy("movesInfoType2", 84, 35)
      SummaryChrome.drawTypeBadge(t2, bx, by)
    end
  end

  if parts.bottom then
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
      -- pokefirered/src/pokemon_summary_screen.c:2297
      draw_text(selMove.power, power.x + SummaryMenu.rightAlign(selMove.power, 18), power.y, 32, "NORMAL")
      draw_text(selMove.accuracy, accuracy.x + SummaryMenu.rightAlign(selMove.accuracy, 18), accuracy.y, 32, "NORMAL")
      local desc = SummaryData.moveDescription(selMove.id, selMove.name)
      draw_text(desc, descBox.x, descBox.y, descBox.w or 112, "NORMAL")
    end
  end
end

local function draw_page_egg(mon)
  -- pokefirered/src/pokemon_summary_screen.c:4016 MON_DATA_SPECIES_OR_EGG
  local species = Pokemon.speciesOrEgg(mon)
  -- pokefirered/src/pokemon_summary_screen.c:2467
  local sx, sy = cxy("species", 167, 35)
  draw_text(RomText.plain("gText_EggNickname"), sx, sy, 64, "NORMAL")
  -- pokefirered/src/pokemon_summary_screen.c:2495
  draw_text(SummaryData.eggHatchText(mon), 120 + 7, 16 + 45, 113, "NORMAL")

  local pic = coords().monPic or { x = 60, y = 65 }
  local cx, cy = pic.x or 60, pic.y or 65
  local front = Pokemon.frontPic(species)
  if front and front.image and love and love.graphics then
    local iw = front.w or 64
    local ih = front.h or 64
    love.graphics.setColor(1, 1, 1, 1)
    local nf = SummaryChrome.manifest() and SummaryChrome.manifest().noFlip
    -- pokefirered/src/pokemon_summary_screen.c:4037
    draw_flipped(front.image, nil, cx - iw / 2 + SummaryMenu._bounce.dx, cy - ih / 2, iw,
      not (nf and nf[tonumber(species) or -1]))
  end
  draw_ball_icon(mon)

  local memo = coords().memo or { x = 8, y = 115, w = 224 }
  local memoLines = SummaryData.formatTrainerMemo(mon, SummaryMenu._playerState,
    { enemyParty = SummaryMenu._enemyParty, owner = SummaryMenu._owner })
  local memoY = memo.y or 115
  for _, line in ipairs(memoLines) do
    draw_text(line, memo.x or 8, memoY, memo.w or 224, "NORMAL")
    memoY = memoY + 14
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

local function draw_top_bar_text(page, isEgg, dx)
  dx = dx or 0
  if dx >= 240 then return end
  local title = PAGE_TITLES[page]
  FrlgFont.draw(title, 4 + dx, 1, {
    colors = FrlgFont.COLOR.WHITE,
    small = false,
  })

  local ctrl = get_controls_str(page, isEgg)
  PokedexChrome.drawControlInfo(ctrl, 236 + dx, 1)
end

local PAGE_LAYERS = {
  [PAGE_INFO] = { bg3 = "info", progress = "info", layer = "info" },
  [PAGE_SKILLS] = { bg3 = "info", progress = "skills", layer = "skills" },
  [PAGE_MOVES] = { bg3 = "info", progress = "moves", layer = "moves" },
  [PAGE_MOVES_INFO] = { bg3 = "moves", progress = "moves_info", layer = "moves_info" },
  [PAGE_EGG] = { bg3 = "info", progress = "egg", layer = "egg" },
}

-- pokefirered/src/pokemon_summary_screen.c:3091
function SummaryMenu.slideOffset(frame, incoming)
  local hofs = math.min(math.max(frame or 0, 0), SLIDE_FRAMES) * SLIDE_STEP
  return incoming and (240 - hofs) or hofs
end

-- pokefirered/src/pokemon_summary_screen.c:1929
local function draw_page_bg(page, shiny)
  local L = PAGE_LAYERS[page] or PAGE_LAYERS[PAGE_INFO]
  local progress = L.progress
  if page == PAGE_MOVES_INFO and SummaryMenu._mode == "select_move" then
    progress = "moves_info_select"
  end
  SummaryChrome.drawBg3(L.bg3, shiny)
  SummaryChrome.drawProgress(progress, shiny)
  if page == PAGE_MOVES_INFO then
    SummaryChrome.drawLayer("moves", 0, shiny)
  end
  SummaryChrome.drawLayer(L.layer, 0, shiny)
end

local function draw_page_text(mon, page)
  if page == PAGE_INFO then
    draw_page_info(mon)
  elseif page == PAGE_SKILLS then
    draw_page_skills(mon)
  elseif page == PAGE_MOVES then
    draw_page_moves(mon, false)
  elseif page == PAGE_MOVES_INFO then
    draw_page_moves(mon, true)
  end
end

function SummaryMenu.flipStep()
  local s = SummaryMenu._slide
  local T = FLIP_TIMING[s.kind] or FLIP_TIMING.page
  return math.min(math.max((s.frame or 0) - T.delay, 0), SLIDE_FRAMES)
end

-- pokefirered/src/pokemon_summary_screen.c:1233
local function draw_page_flip(mon, shiny)
  local s = SummaryMenu._slide
  local T = FLIP_TIMING.page
  local from, to = s.prevPage, SummaryMenu._page
  local toL, fromL = PAGE_LAYERS[to], PAGE_LAYERS[from]
  local step = SummaryMenu.flipStep()
  local swapped = s.frame >= T.header
  SummaryChrome.drawBg3("info", shiny)
  SummaryChrome.drawProgress((swapped and toL or fromL).progress, shiny)
  local toX = 0
  if s.direction > 0 then
    SummaryChrome.drawLayer(toL.layer, 0, shiny)
    -- pokefirered/src/pokemon_summary_screen.c:1665
    if to == PAGE_SKILLS then draw_skill_bars(mon, 0) end
    SummaryChrome.drawLayer(fromL.layer, SummaryMenu.slideOffset(step, false), shiny)
  else
    SummaryChrome.drawLayer(fromL.layer, 0, shiny)
    toX = SummaryMenu.slideOffset(step, true)
    SummaryChrome.drawLayer(toL.layer, toX, shiny)
    -- pokefirered/src/pokemon_summary_screen.c:3027
    if to == PAGE_SKILLS then draw_skill_bars(mon, toX) end
  end
  -- pokefirered/src/pokemon_summary_screen.c:3171
  if swapped then
    draw_top_bar_text(to, false, toX)
    draw_header(mon, true, toX)
  else
    draw_top_bar_text(from, false, 0)
    draw_header(mon, true, 0)
  end
  draw_left_sprites(mon, to)
  -- pokefirered/src/pokemon_summary_screen.c:1310
  if s.frame >= T.text then draw_page_text(mon, to) end
end

-- pokefirered/src/pokemon_summary_screen.c:1332
local function draw_detail_flip(mon, shiny)
  local s = SummaryMenu._slide
  local T = FLIP_TIMING[s.kind]
  local f = s.frame
  local incoming = s.kind == "detail"
  local detailBg
  if incoming then detailBg = f >= T.bg else detailBg = f < T.bg end
  SummaryChrome.drawBg3(detailBg and "moves" or "info", shiny)
  SummaryChrome.drawProgress(detailBg and "moves_info" or "moves", shiny)
  SummaryChrome.drawLayer("moves", 0, shiny)
  local layerX = SummaryMenu.slideOffset(SummaryMenu.flipStep(), incoming)
  if layerX < 240 then SummaryChrome.drawLayer("moves_info", layerX, shiny) end

  if f < T.header then
    draw_top_bar_text(s.prevPage, false, 0)
    draw_header(mon, s.prevPage ~= PAGE_MOVES_INFO, 0)
  else
    draw_top_bar_text(SummaryMenu._page, false, incoming and layerX or 0)
    -- pokefirered/src/pokemon_summary_screen.c:1412
    if f >= T.name then draw_header(mon, SummaryMenu._page ~= PAGE_MOVES_INFO, 0) end
  end

  local before, after = f < T.hide, f >= T.show
  if before then
    draw_left_sprites(mon, s.prevPage)
  elseif after then
    draw_left_sprites(mon, SummaryMenu._page)
  end

  if incoming then
    draw_page_moves(mon, true, { rows5 = f >= T.list5, cursor = after, types = f >= T.name, bottom = f >= T.bottom })
  else
    draw_page_moves(mon, true, { rows5 = f < T.list5, cursor = before, types = before, bottom = f < T.bottom })
  end
end

function SummaryMenu.draw()
  if not SummaryMenu.open then return end
  local mon = current_mon()
  if not mon then return end

  local page = SummaryMenu._page
  local isEgg = Pokemon.isEgg(mon)
  -- pokefirered/src/pokemon_summary_screen.c:2009
  local shiny = (not isEgg) and SummaryData.isShiny(mon)
  local s = SummaryMenu._slide

  if s.active and page ~= PAGE_EGG then
    if s.kind == "page" then
      draw_page_flip(mon, shiny)
    else
      draw_detail_flip(mon, shiny)
    end
    return
  end

  draw_page_bg(page, shiny)
  draw_top_bar_text(page, isEgg)
  if page == PAGE_EGG then
    draw_page_egg(mon)
    return
  end
  draw_header(mon, page ~= PAGE_MOVES_INFO)
  draw_left_sprites(mon, page)
  draw_page_text(mon, page)
end

return SummaryMenu

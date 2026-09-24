-- pokefirered/src/battle_records.c:83 ShowBattleRecords

local Display = require("src.core.game3.display")
local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local Tower = require("src.core.game3.trainer_tower")

local Records = {}

Records.ID = "trainer_tower_records"

-- pokefirered/src/battle_records.c:41
Records.WINDOW = { left = 2, top = 1, width = 27, height = 18 }
-- pokefirered/src/trainer_tower.c:312
Records.BOARD_WINDOW = { left = 3, top = 1, width = 27, height = 18 }
-- pokefirered/src/trainer_tower.c:921
Records.BOARD_WINDOW_ID = 1
-- pokefirered/include/global.h:238
Records.LINK_ROWS = 5
-- pokefirered/include/constants/songs.h:9
local SE_SELECT = 5

Records.CACHE_BG = "data/generated/gba/trainer_tower/records_bg.rgba"
Records.CACHE_MANIFEST = "data/generated/gba/trainer_tower/manifest.lua"
Records.BG_W, Records.BG_H = Display.W, Display.H

-- pokefirered/src/battle_message.c:1364
Records.MODE_TEXT = RomText.lazy({
  "gTrainerTowerChallengeTypeTexts[0]",
  "gTrainerTowerChallengeTypeTexts[1]",
  "gTrainerTowerChallengeTypeTexts[2]",
  "gTrainerTowerChallengeTypeTexts[3]",
})

Records.open = false
Records._kind = "tower"
Records._phase = "idle"
Records._rows = {}
Records._session = nil
Records._onDone = nil
Records._logged = {}
Records._templates = {}
Records._title = nil
Records._titleX = 0
Records._total = nil

local function log(key, msg)
  if Records._logged[key] then return end
  Records._logged[key] = true
  print("[game3/tower_records] " .. tostring(msg))
end

local function fade()
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  if ok and type(Fade) == "table" and Fade.MODE then return Fade end
  return nil
end

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okC, cache = pcall(Dataset.cache)
    if okC and cache and cache.read then
      local okR, d = pcall(cache.read, cache, rel)
      if okR and type(d) == "string" and #d > 0 then return d end
    end
  end
  local okF, CacheFs = pcall(require, "src.import.CacheFs")
  if okF and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if type(love) == "table" and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if type(d) == "string" and #d > 0 then return d end
  end
  return nil
end

local function bg_size()
  local src = read_bytes(Records.CACHE_MANIFEST)
  if type(src) ~= "string" or #src == 0 then return Records.BG_W, Records.BG_H end
  local chunk = (load or loadstring)(src, "@" .. Records.CACHE_MANIFEST, "t", {})
  local ok, pack = pcall(chunk)
  local row = ok and type(pack) == "table" and (pack.recordsBg or (pack.frames and pack.frames.recordsBg))
  if type(row) == "table" then
    return tonumber(row.width) or Records.BG_W, tonumber(row.height) or Records.BG_H
  end
  return Records.BG_W, Records.BG_H
end

local function background()
  if Records._bg ~= nil then return Records._bg or nil end
  if not (type(love) == "table" and love.image and love.graphics) then
    Records._bg = false
    return nil
  end
  local rgba = read_bytes(Records.CACHE_BG)
  local w, h = bg_size()
  if type(rgba) == "string" and #rgba >= w * h * 4 then
    local okD, data = pcall(love.image.newImageData, w, h, "rgba8", rgba)
    if okD and data then
      local okI, image = pcall(love.graphics.newImage, data)
      if okI and image then
        if image.setFilter then image:setFilter("nearest", "nearest") end
        Records._bg = image
        return image
      end
    end
  end
  log("no-bg", "no " .. Records.CACHE_BG .. " in cache; plain window chrome")
  Records._bg = false
  return nil
end

function Records.resetArt()
  Records._bg = nil
  Records._logged = {}
  Records._templates = {}
end

function Records.template()
  local kind = Records._kind
  local cached = Records._templates[kind]
  if cached then return cached end
  local w = (kind == "board") and Records.BOARD_WINDOW or Records.WINDOW
  cached = Window.template(w.left, w.top, w.width, w.height)
  Records._templates[kind] = cached
  return cached
end

-- pokefirered/src/trainer_tower.c:872 PRINT_TOWER_TIME
function Records.timeText(frames)
  local minutes, seconds, centiseconds = Tower.formatTime(frames)
  -- pokefirered/src/battle_message.c:1354 gText_XMinYZSec
  return RomText.plain("gText_XMinYZSec", { stringVars = { minutes, seconds, centiseconds } })
end

-- pokefirered/src/trainer_tower.c:1054 PrintTrainerTowerRecords
local function tower_rows(session)
  Tower.validateRecord(session)
  local rows = {}
  for i = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    local best = Tower.bestTime(session, i)
    rows[i + 1] = {
      label = Records.MODE_TEXT[i + 1],
      time = Records.timeText(best),
      frames = best,
    }
  end
  return rows
end

-- pokefirered/src/trainer_tower.c:899 ShowResultsBoard
local function board_rows(session)
  Tower.validateRecord(session)
  local best = Tower.bestTime(session)
  local rows = {}
  for i = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    -- pokefirered/src/trainer_tower.c:915 gTrainerTowerChallengeTypeTexts[i - 1]
    local name = Records.MODE_TEXT[i]
    rows[i + 1] = {
      label = name or "",
      time = Records.timeText(best),
      frames = best,
    }
  end
  return rows
end

local function record_number(value)
  value = math.floor(tonumber(value) or 0)
  if value < 0 then value = 0 end
  -- pokefirered/src/battle_records.c:462
  if value > 9999 then value = 9999 end
  return value
end

-- pokefirered/src/battle_records.c:541 PrintBattleRecords
local function link_rows(session)
  local stored = (type(session) == "table" and session.linkBattleRecords) or {}
  local rows = {}
  for i = 1, Records.LINK_ROWS do
    local entry = type(stored[i]) == "table" and stored[i] or nil
    local wins = record_number(entry and entry.wins)
    local losses = record_number(entry and entry.losses)
    local draws = record_number(entry and entry.draws)
    if entry and (wins > 0 or losses > 0 or draws > 0) then
      rows[i] = {
        name = tostring(entry.name or ""),
        wins = string.format("%4d", wins),
        losses = string.format("%4d", losses),
        draws = string.format("%4d", draws),
      }
    else
      -- pokefirered/src/strings.c:599, :600
      local dashes4 = RomText.plain("gString_BattleRecords_4Dashes")
      rows[i] = { name = RomText.plain("gString_BattleRecords_7Dashes"), wins = dashes4, losses = dashes4, draws = dashes4 }
    end
  end
  return rows
end

function Records.rows()
  return Records._rows
end

function Records.kind()
  return Records._kind
end

function Records.isOpen()
  return Records.open
end

-- pokefirered/src/battle_records.c:130
local function fade_in()
  local Fade = fade()
  if not Fade then return end
  local covered = (tonumber(Fade.t) or 0) > 0 or (Fade.isActive and Fade.isActive())
  if not covered then return end
  Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
end

function Records.show(opts)
  opts = opts or {}
  Records._session = opts.session or Tower.sessionOf()
  Records._kind = opts.kind or "tower"
  Records._onDone = opts.onDone
  Records._title, Records._total = nil, nil
  if Records._kind == "link" then
    Records._rows = link_rows(Records._session)
    -- pokefirered/src/strings.c:596
    local name = (type(Records._session) == "table" and Records._session.name) or ""
    Records._title = RomText.plain("gString_BattleRecords_PlayersBattleResults", { playerName = tostring(name) })
    Records._titleX = math.floor((0xD0 - (FrlgFont.measure(Records._title) or 0)) / 2)
    -- pokefirered/src/strings.c:597
    Records._total = Records.totalText(Records._session)
  elseif Records._kind == "board" then
    Records._rows = board_rows(Records._session)
  else
    Records._rows = tower_rows(Records._session)
  end
  Records.open = true
  if Records._kind == "board" then
    Records._phase = "wait"
    Stack.push(Records.ID, Records, { hideBelow = false, drawUnder = true })
  else
    Records._phase = "in"
    Stack.push(Records.ID, Records, { hideBelow = true, fullscreen = true })
    fade_in()
  end
  return Records
end

local function finish()
  Records.open = false
  Records._phase = "idle"
  Stack.pop(Records.ID)
  local cb = Records._onDone
  Records._onDone = nil
  -- pokefirered/src/battle_records.c:189 CB2_ReturnToFieldContinueScriptPlayMapMusic
  local Fade = fade()
  if Fade and (tonumber(Fade.t) or 0) > 0 then
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
  if cb then cb() end
end

-- pokefirered/src/battle_records.c:179 Task_FadeOut
function Records.close()
  if not Records.open then return false end
  if Records._kind == "board" then
    finish()
    return true
  end
  if Records._phase == "out" then return false end
  Records._phase = "out"
  local Fade = fade()
  if not Fade then
    finish()
    return true
  end
  Fade.begin(Fade.MODE.TO_BLACK, 1, function()
    if Records._phase == "out" then finish() end
  end)
  return true
end

function Records.update(_dt)
  if not Records.open then return end
  if Records._phase ~= "in" then return end
  local Fade = fade()
  if not Fade or not (Fade.isActive and Fade.isActive()) then
    -- pokefirered/src/battle_records.c:162 Task_WaitFadeIn
    Records._phase = "wait"
  end
end

-- pokefirered/src/battle_records.c:168 Task_WaitButton
function Records.handleInput(input)
  if not Records.open or not input then return end
  if Records._phase ~= "wait" or Records._kind == "board" then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    se(SE_SELECT)
    Records.close()
  end
end

local function print_at(text, px, py)
  Window.printPx(text, px, py, { colors = FrlgFont.COLOR.NORMAL })
end

function Records.draw()
  if not Records.open then return end
  local tpl = Records.template()
  local ox = (tpl.left or 0) * Display.TILE
  local oy = (tpl.top or 0) * Display.TILE
  if Records._kind == "board" then
    Window.fixedStdFrame(tpl)
  else
    local img = background()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
    love.graphics.setColor(1, 1, 1, 1)
    if img then
      -- pokefirered/src/battle_records.c:205 ResetGpu
      love.graphics.draw(img, 0, 0)
    else
      Window.fixedStdFrame(tpl)
    end
  end

  if Records._kind == "link" then
    -- pokefirered/src/strings.c:596
    print_at(Records._title or "", ox + Records._titleX, oy + 4)
    -- pokefirered/src/strings.c:597
    print_at(Records._total or "", ox + 12, oy + 24)
    -- pokefirered/src/strings.c:598
    local headers, xs = Records.columnHeaders()
    for i = 1, #headers do
      print_at(headers[i], ox + 0x54 + xs[i], oy + 0x30)
    end
    for i, row in ipairs(Records._rows) do
      local y = oy + 0x3D + 14 * (i - 1)
      print_at(row.name, ox, y)
      print_at(row.wins, ox + 0x54, y)
      print_at(row.losses, ox + 0x84, y)
      print_at(row.draws, ox + 0xB4, y)
    end
    return
  end

  -- pokefirered/src/battle_message.c:1352 gText_TimeBoard
  print_at(RomText.plain("gText_TimeBoard"), ox + 0x4A, oy)
  for i, row in ipairs(Records._rows) do
    if Records._kind == "board" then
      -- pokefirered/src/trainer_tower.c:915
      print_at(row.label, ox + 0x18, oy + 36 + 20 * (i - 1))
      print_at(row.time, ox + 0x60, oy + 46 + 20 * (i - 1))
    else
      -- pokefirered/src/trainer_tower.c:1068
      local y = oy + 0x24 + 0x14 * (i - 1)
      print_at(row.label, ox + 0x18, y)
      print_at(row.time, ox + 0x60, y)
    end
  end
end

-- pokefirered/src/strings.c:598 gString_BattleRecords_ColumnHeaders
function Records.columnHeaders()
  local out, xs = {}, { 0 }
  for _, seg in ipairs(RomText.ir("gString_BattleRecords_ColumnHeaders")) do
    if seg.t == "text" then
      out[#out + 1] = Strings(seg.s)
    elseif seg.t == "ext" and seg.cmd == 0x13 then
      xs[#out + 1] = seg.args[1]
    end
  end
  return out, xs
end

-- pokefirered/src/battle_records.c:452 PrintTotalRecord
function Records.totalText(session)
  session = session or Records._session
  -- battle_records.c:355, include/constants/game_stat.h:27-29
  local gs = type(session) == "table" and session.gameStats or {}
  local wins = record_number(gs[23] or gs.linkBattleWins
    or (type(session) == "table" and session.linkBattleWins))
  local losses = record_number(gs[24] or gs.linkBattleLosses
    or (type(session) == "table" and session.linkBattleLosses))
  local draws = record_number(gs[25] or gs.linkBattleDraws
    or (type(session) == "table" and session.linkBattleDraws))
  -- pokefirered/src/battle_records.c:473
  return RomText.plain("gString_BattleRecords_TotalRecord", { stringVars = {
    string.format("%-4d", wins), string.format("%-4d", losses), string.format("%-4d", draws) } })
end

return Records

-- Stat growth / level-up window (pokefirered Cmd_drawlvlupbox / DrawLevelUpWindowPg1 & Pg2).
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")

local StatGrowth = {}

StatGrowth._open = false
StatGrowth._mon = nil
StatGrowth._oldStats = nil
StatGrowth._newStats = nil
StatGrowth._page = 1
StatGrowth._onDone = nil
StatGrowth._pos = nil

local STAT_NAMES = { "MAX. HP", "ATTACK", "DEFENSE", "SP. ATK", "SP. DEF", "SPEED" }

local function play_select_se()
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if Audio and Audio.playSe then
      Audio.playSe((SE and SE.SE_SELECT) or 5)
    end
  end)
end

function StatGrowth.open(mon, oldStats, newStats, onDone, opts)
  opts = opts or {}
  StatGrowth._open = true
  StatGrowth._mon = mon
  StatGrowth._oldStats = oldStats or {}
  StatGrowth._newStats = newStats or {}
  StatGrowth._page = 1
  StatGrowth._onDone = onDone
  StatGrowth._pos = opts.pos or { x = 19, y = 1, w = 10, h = 11 }
end

function StatGrowth.isOpen()
  return StatGrowth._open
end

--- opts.silent drops the window without firing its onDone callback, for callers
--- tearing down a step that no longer exists (#2324).
function StatGrowth.close(opts)
  local wasOpen = StatGrowth._open
  StatGrowth._open = false
  StatGrowth._mon = nil
  StatGrowth._oldStats = nil
  StatGrowth._newStats = nil
  StatGrowth._page = 1
  local cb = StatGrowth._onDone
  StatGrowth._onDone = nil
  if wasOpen and cb and not (opts and opts.silent) then cb() end
end

function StatGrowth.handleInput(input)
  if not StatGrowth._open or not input then return false end
  if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
    if StatGrowth._page == 1 then
      play_select_se()
      StatGrowth._page = 2
      return true
    else
      play_select_se()
      StatGrowth.close()
      return true
    end
  end
  return false
end

function StatGrowth.draw()
  if not StatGrowth._open or not (love and love.graphics) then return end
  local pos = StatGrowth._pos or { x = 19, y = 1, w = 10, h = 11 }
  local winX = pos.x or 19
  local winY = pos.y or 1
  local winW = pos.w or 10
  local winH = pos.h or 11

  Window.stdFrame(Window.template(winX, winY, winW, winH))

  local oldS = StatGrowth._oldStats or {}
  local newS = StatGrowth._newStats or {}
  local oldList = { oldS.maxHp or 0, oldS.atk or 0, oldS.def or 0, oldS.spa or 0, oldS.spd or 0, oldS.spe or 0 }
  local newList = { newS.maxHp or 0, newS.atk or 0, newS.def or 0, newS.spa or 0, newS.spd or 0, newS.spe or 0 }
  local isPage1 = (StatGrowth._page == 1)

  for idx = 1, 6 do
    local rowY = winY * 8 + 2 + (idx - 1) * 14
    FrlgFont.draw(Strings(STAT_NAMES[idx]), winX * 8 + 2, rowY, { colors = FrlgFont.COLOR.NORMAL })
    if isPage1 then
      local diff = newList[idx] - oldList[idx]
      local sign = (diff >= 0) and "+" or "-"
      local diffStr = string.format("%s%2d", sign, math.abs(diff))
      FrlgFont.draw(diffStr, winX * 8 + 52, rowY, { colors = FrlgFont.COLOR.NORMAL })
    else
      local valStr = string.format("%3d", newList[idx])
      FrlgFont.draw(valStr, winX * 8 + 52, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end
end

return StatGrowth

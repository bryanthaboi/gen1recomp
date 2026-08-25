-- Fast-forward multiplier for game logic.
--
-- Speeding up means running the 1/60 fixed step N times per real frame
-- (Game:update), so everything driven by the step -- movement, text,
-- battle timing, scripts -- advances N times faster while staying
-- deterministic. Audio deliberately does NOT scale: Music.update drives
-- fade counters and ChipAudio synthesis off its own real-time 60Hz
-- accumulator in Game:update, so music and sfx play at normal pitch and
-- tempo at every speed.
--
-- Vsync still caps how much work a real frame can do, so 10X is a target
-- rather than a promise on a slow machine -- the logic simply runs as many
-- steps as the frame budget allows.

local GameSpeed = {}

-- 20X exists for the bot runs (tests/drivers/route.lua): a full-route
-- attempt is long enough that the iteration loop, not the engine, is the
-- bottleneck. Vsync caps how much a real frame can do, so past 10X the
-- multiplier is increasingly a ceiling rather than a rate.
GameSpeed.LEVELS = { 1, 2, 3, 4, 10, 20, 30, 50, 75, 100, 200 }
GameSpeed.DEFAULT = 1

function GameSpeed.levelLabel(v)
  v = tonumber(v) or GameSpeed.DEFAULT
  if v == 1 then return "NORMAL" end
  return tostring(v) .. "X"
end

-- nearest valid level for an arbitrary value (a hand-edited options.lua or
-- a --speed argument), so a bad number degrades to something sane
-- A cart may narrow the levels a player can reach (CartManifest's `speeds`).
-- nil restores the full ladder; a one-entry list pins the speed outright.
local allowed

function GameSpeed.setAllowed(levels)
  if type(levels) ~= "table" or #levels == 0 then allowed = nil; return end
  local valid, seen = {}, {}
  for _, want in ipairs(GameSpeed.LEVELS) do
    for _, have in ipairs(levels) do
      if have == want and not seen[want] then
        seen[want] = true
        valid[#valid + 1] = want
      end
    end
  end
  allowed = (#valid > 0) and valid or nil
end

function GameSpeed.allowed()
  return allowed or GameSpeed.LEVELS
end

function GameSpeed.isLocked()
  return allowed ~= nil and #allowed <= 1
end

function GameSpeed.clamp(v)
  v = tonumber(v)
  local levels = GameSpeed.allowed()
  if not v then return levels[1] or GameSpeed.DEFAULT end
  local best, bestDiff = levels[1] or GameSpeed.DEFAULT, math.huge
  for _, level in ipairs(levels) do
    local diff = math.abs(level - v)
    if diff < bestDiff then best, bestDiff = level, diff end
  end
  return best
end

-- cycle to the next/previous level, wrapping (the options row idiom)
function GameSpeed.cycle(v, dir)
  local levels = GameSpeed.allowed()
  local cur = 1
  for i, level in ipairs(levels) do
    if level == GameSpeed.clamp(v) then cur = i break end
  end
  local nextIdx = (cur - 1 + (dir or 1)) % #levels + 1
  return levels[nextIdx]
end

-- Per-category speed (RFC 0007): overworld walking, battle turns and menu
-- navigation each cycle their own multiplier instead of one global "speed"
-- value. This list is the single source of truth for which categories
-- exist and the order the Options rows/save.options keys follow;
-- Game.lua's stack-walk (Game.speedCategoryInStack) decides WHICH category
-- is active on a given frame, this module only knows the category names.
GameSpeed.CATEGORIES = { "overworld", "battle", "menu" }

-- the save.options field name a category's multiplier lives under, e.g.
-- "overworld" -> "speedOverworld". Centralized so Game.lua, OptionsMenu.lua,
-- LauncherSettings.lua and the SaveData migration never hand-spell the key.
function GameSpeed.optionKey(category)
  return "speed" .. category:sub(1, 1):upper() .. category:sub(2)
end

return GameSpeed

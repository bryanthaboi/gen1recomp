local R = require("src.core.game3.minigames.dodrio_berry_picking.rules")
local Sim = require("src.core.game3.minigames.dodrio_berry_picking.sim")

local G = {}

G.id = "pick"
G.MIN = 3
G.MAX = 5
-- pokefirered/src/dodrio_berry_picking.c:912
G.OWN_COUNTDOWN = true
-- pokefirered/src/dodrio_berry_picking.c:4839
G.DROPPED_TEXT = "gText_SomeoneDroppedOut"
G.Rules = R
G.Sim = Sim
G.audio = nil

G.PRIZE_RECEIVED, G.PRIZE_FILLED_BAG, G.PRIZE_NO_ROOM, G.NO_PRIZE =
  R.PRIZE_RECEIVED, R.PRIZE_FILLED_BAG, R.PRIZE_NO_ROOM, R.NO_PRIZE

function G.loadArt(cache)
  local Art = require("src.ui.game3.minigames.dodrio_berry_picking.art")
  return Art.load(cache)
end

function G.new(ctx)
  return Sim.new(ctx, G)
end

local function session()
  return require("src.core.game3.minigames.common").gameSession()
end

function G.defaultHooksFor()
  return {
    updateRecords = function(score, picked, inRow)
      return require("src.ui.game3.minigame_records").updateDodrio(session(), score, picked, inRow)
    end,
    canAdd = function(item, qty)
      local s = session()
      if type(s) ~= "table" or s.bag == nil then return false end
      return require("src.core.game3.bag").canAdd(s.bag, item, qty)
    end,
    addItem = function(item, qty)
      local s = session()
      if type(s) ~= "table" or s.bag == nil then return false end
      return (require("src.core.game3.bag").add(s.bag, item, qty))
    end,
    save = function()
      local rt = package.loaded["src.core.game3.runtime"]
      local game = type(rt) == "table" and rt._game or nil
      if game and type(game.saveGame) == "function" then
        local ok, written = pcall(game.saveGame, game)
        if not ok or written == false then print("[minigame] dodrio save failed: " .. tostring(written)) end
      end
    end,
  }
end

G.hooksFor = G.defaultHooksFor

local function mine(result, mySeat)
  for _, row in ipairs(type(result) == "table" and type(result.results) == "table" and result.results or {}) do
    if tonumber(row.seat) == tonumber(mySeat) then return row end
  end
  return nil
end

-- pokefirered/src/dodrio_berry_picking.c:2633
function G.applyResults(sess, result, mySeat)
  if type(sess) ~= "table" then return false end
  local row = mine(result, mySeat)
  if not row then return false end
  local stats = type(row.stats) == "table" and row.stats or {}
  local r = { [0] = tonumber(stats.b) or 0, tonumber(stats.g) or 0, tonumber(stats.o) or 0, tonumber(stats.m) or 0 }
  local Records = require("src.ui.game3.minigame_records")
  local T = Sim.tables(nil)
  Records.updateDodrio(sess, math.min(R.score(T, r), R.MAX_SCORE), R.berriesPicked(r), tonumber(stats.r) or 0)
  return true
end

return G

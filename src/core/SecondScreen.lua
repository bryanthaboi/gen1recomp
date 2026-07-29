-- Live state for an Android second-screen companion.
--
-- LOVE owns the game display and Android owns the companion display, so the
-- smallest honest seam between them is a tiny JSON snapshot in the game's
-- save directory.  The snapshot is deliberately presentation-only: it reads
-- the live game, never mutates it, and the Android side keeps its previous
-- good frame if it catches this file between writes.

local Badges = require("src.inventory.Badges")
local DiscordPresence = require("src.core.DiscordPresence")
local Growth = require("src.pokemon.Growth")
local Json = require("src.link.Json")

local SecondScreen = {
  INTERVAL = 0.3,
  FILE = "companion-state.json",
  elapsed = 0,
  last = nil,
}

local function clamp(n, lo, hi)
  n = tonumber(n) or 0
  return math.max(lo, math.min(hi, n))
end

local function monSnapshot(game, mon)
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  local level = math.max(1, math.floor(tonumber(mon.level) or 1))
  local exp = math.max(0, math.floor(tonumber(mon.exp) or 0))
  local growthRate = def and def.growthRate
  local rates = game.data and game.data.growth_rates
  local floor = Growth.expForLevel(growthRate, level, rates)
  local ceiling = level >= 100 and floor
    or Growth.expForLevel(growthRate, level + 1, rates)
  local span = math.max(1, ceiling - floor)
  local maxHP = math.max(1, math.floor(tonumber(mon.stats and mon.stats.hp) or 1))

  return {
    name = mon.nickname or (def and def.name) or tostring(mon.species or "?"),
    species = mon.species,
    level = level,
    hp = clamp(math.floor(tonumber(mon.hp) or 0), 0, maxHP),
    maxHp = maxHP,
    status = mon.status or "",
    exp = exp,
    expIntoLevel = clamp(exp - floor, 0, span),
    expForLevel = span,
    expToNext = level >= 100 and 0 or math.max(0, ceiling - exp),
  }
end

local function battleSnapshot(game)
  local states = game.stack and game.stack.states or {}
  for i = #states, 1, -1 do
    local state = states[i]
    if type(state) == "table" and state.enemy and state.player
       and state.enemy.mon and state.player.mon then
      local enemy = state.enemy
      return {
        kind = state.kind or (state.trainer and "trainer" or "wild"),
        enemy = monSnapshot(game, enemy.mon),
        trainer = state.trainer and state.trainer.name or nil,
      }
    end
  end
  return nil
end

function SecondScreen.snapshot(game)
  local save = game and game.save or {}
  local player = save.player or {}
  local overworld = game and game.overworld
  local map = overworld and overworld.map
  local battle = battleSnapshot(game)
  local inWorld = false
  for _, state in ipairs(game and game.stack and game.stack.states or {}) do
    if state == overworld then inWorld = true break end
  end
  local mapId = (inWorld or battle) and ((map and map.id) or player.map) or nil
  local party = {}
  for i, mon in ipairs(save.party or {}) do
    if i > 6 then break end
    party[#party + 1] = monSnapshot(game, mon)
  end

  local badges = {}
  for _, entry in ipairs(Badges.list(game and game.data)) do
    badges[#badges + 1] = {
      name = entry.name or tostring(entry.id or ""):gsub("BADGE$", ""),
      earned = (save.inventory
        and save.inventory[Badges.itemFor(entry)] ~= nil) and true or false,
    }
  end

  local x = inWorld and overworld and overworld.player
    and overworld.player.cellX or player.x
  local y = inWorld and overworld and overworld.player
    and overworld.player.cellY or player.y
  local context = battle and "battle" or (inWorld and "exploring" or "menu")

  return {
    revision = 1,
    version = save.version or "red",
    playerName = player.name or "TRAINER",
    location = DiscordPresence.locationName(game, mapId) or "Main Menu",
    mapId = mapId or "",
    x = math.floor(tonumber(x) or 0),
    y = math.floor(tonumber(y) or 0),
    context = context,
    contextLabel = battle and "Battle" or (inWorld and "Exploring" or "Menu"),
    money = math.max(0, math.floor(tonumber(save.money) or 0)),
    badges = badges,
    party = party,
    battle = battle,
  }
end

local function android()
  return love and love.system and love.system.getOS
     and love.system.getOS() == "Android"
end

function SecondScreen.update(dt, game)
  if not android() then return end
  SecondScreen.elapsed = SecondScreen.elapsed + (tonumber(dt) or 0)
  if SecondScreen.elapsed < SecondScreen.INTERVAL then return end
  SecondScreen.elapsed = SecondScreen.elapsed % SecondScreen.INTERVAL

  local ok, encoded = pcall(Json.encode, SecondScreen.snapshot(game))
  if not ok or encoded == SecondScreen.last then return end
  local wrote = love.filesystem.write(SecondScreen.FILE, encoded)
  if wrote then SecondScreen.last = encoded end
end

return SecondScreen

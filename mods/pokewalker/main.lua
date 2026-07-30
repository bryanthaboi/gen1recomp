-- Pokéwalker: Apple Health steps become party EXP (iOS builds).
--
-- The Swift side (mobile/ios/native/GRHealthBridge.swift) owns HealthKit:
-- love.system.syncHealthSteps() requests read access on first use, counts
-- steps since the last sync anchor, and drops steps_pending.json in the
-- save dir.  This mod consumes that file at quiet moments (save loaded, map
-- transitions, battle end), converts steps to EXP, and applies level-ups
-- with the same stat math the engine uses.
--
-- Opt-in: everything is inert until SYNC STEPS is enabled in this mod's
-- options (the HealthKit permission sheet appears on first enable).  On
-- non-iOS platforms love.system.syncHealthSteps does not exist and the mod
-- stays dormant.
--
-- Known v1 limits (documented in README.md): level-ups applied here do not
-- prompt for new moves (like over-leveling past a learnset entry with rare
-- candies) and do not trigger level evolutions until the next battle candy
-- or level gained in battle.

local PENDING = "steps_pending.json"

return function(mod)
  mod.options:define({
    { key = "enabled", label = "SYNC STEPS", type = "toggle", default = false },
    { key = "rate", label = "STEPS PER EXP", type = "choice", default = "20",
      choices = { { "10", "10" }, { "20", "20" }, { "50", "50" } } },
    { key = "target", label = "GIVE EXP TO", type = "choice", default = "lead",
      choices = { { "LEAD MON", "lead" }, { "WHOLE PARTY", "party" } } },
  })

  local Json = require("src.link.Json")
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local game

  local function active()
    return love.system.syncHealthSteps ~= nil and mod.options:get("enabled")
  end

  -- Ask the native side to refresh steps_pending.json.  Async: results are
  -- picked up by a later consume() (next map change / battle end).
  local function requestSync()
    if active() then love.system.syncHealthSteps() end
  end

  -- Add EXP to one mon, bumping levels with the engine's own stat math
  -- (mirrors the rare-candy path in src/inventory/ItemEffects.lua).
  -- Returns the EXP actually absorbed and any levels gained.
  local function applyToMon(mon, xp, data)
    local def = data.pokemon[mon.species]
    if not def or not mon.level then return 0, {} end
    local cap = (data.constants and data.constants.levelCap) or 100
    if mon.level >= cap then return 0, {} end
    local maxExp = Growth.expForLevel(def.growthRate, cap, data.growth_rates)
    local before = mon.exp or 0
    mon.exp = math.min(maxExp, before + xp)
    local absorbed = mon.exp - before
    if absorbed <= 0 then return 0, {} end
    local levels = {}
    local newLevel = Growth.levelForExp(def.growthRate, mon.exp, cap,
                                        data.growth_rates)
    while mon.level < newLevel do
      mon.level = mon.level + 1
      local old = mon.stats
      mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
      mon.hp = math.min(mon.stats.hp,
                        (mon.hp or 0) + (mon.stats.hp - (old and old.hp or 0)))
      levels[#levels + 1] = mon.level
    end
    return absorbed, levels
  end

  -- A short walk-report textbox, shown only when the overworld is idle;
  -- when a script is already running the report is silently skipped (the
  -- EXP is applied regardless, and the log has the numbers).
  local function report(steps, total, leveled)
    local msg = ("You walked %d steps!\nYour party gained %d EXP."):format(steps, total)
    if #leveled > 0 then
      msg = msg .. ("\n%s grew to L%d!"):format(leveled[1].name, leveled[1].level)
    end
    -- The report is decoration: it must never break the credit.  mod.world
    -- materializes lazily (and can itself error in headless contexts), so
    -- the access lives inside the pcall too.
    pcall(function()
      local world = mod.world
      if world then world:queueScript({ { "show_text", msg } }) end
    end)
  end

  local function consume()
    if not (game and active()) then return end
    local raw = love.filesystem.read(PENDING)
    if not raw then return end
    local decoded = Json.decode(raw)
    local steps = decoded and tonumber(decoded.steps) or 0
    love.filesystem.remove(PENDING)
    if steps <= 0 then return end

    local party = game.save and game.save.party
    if not party or #party == 0 then return end
    local rate = tonumber(mod.options:get("rate")) or 20
    local xp = math.floor(steps / rate)
    if xp <= 0 then return end

    local total, leveled = 0, {}
    local targets = {}
    if mod.options:get("target") == "party" then
      for _, mon in ipairs(party) do targets[#targets + 1] = mon end
    else
      targets[1] = party[1]
    end
    local share = math.max(1, math.floor(xp / #targets))
    for _, mon in ipairs(targets) do
      local absorbed, levels = applyToMon(mon, share, game.data)
      total = total + absorbed
      for _, level in ipairs(levels) do
        leveled[#leveled + 1] =
          { name = mon.nickname or mon.species, level = level }
      end
    end
    if total <= 0 then return end
    mod.log:info("credited %d steps -> %d EXP (%d level-ups)",
                 steps, total, #leveled)
    report(steps, total, leveled)
  end

  -- game.ready is the sanctioned way to obtain the Game object; the party
  -- only exists once a save is loaded or created.
  mod.events:on("game.ready", function(payload)
    game = payload.game
    requestSync()
  end)
  mod.events:on("save.loaded", function()
    requestSync()
    consume()
  end)
  mod.events:on("save.created", function() requestSync() end)
  -- Quiet moments where a walk report can safely appear.
  mod.events:on("map.entered", function() consume() end)
  mod.events:on("battle.ended", function() consume() end)
  -- Flipping SYNC STEPS on triggers the HealthKit permission sheet
  -- immediately rather than on the next boot.
  mod.events:on("mod.options_changed", function() requestSync() end)
end

local Records = require("src.mods.UnifiedRecords")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")

local UnifiedCallbacks = {}
local unpack = table.unpack or unpack
local wrappedSelections = setmetatable({}, { __mode = "k" })
local function pack(...) return { n = select("#", ...), ... } end
local function shallow(value)
  local out = {}
  for k, v in pairs(value or {}) do out[k] = v end
  return out
end

local catalogs = { events = {}, hooks = {} }
local function names(surface, introduction, list)
  for name in list:gmatch("%S+") do catalogs[surface][name] = introduction end
end
names("events", 1, [[
  mods.loaded assets.transformed game.ready save.created save.loading save.loaded
  save.writing checkpoint.restored screen.pushed screen.popped flag.changed
  music.started music.stopped sound.played discord.join_requested
  map.entered map.exited map.reloaded player.warped world.stepped
  world.block_replaced world.object_toggled world.npc_spawned world.interacted
  world.trainer_engaged world.blacked_out world.boulder_moved
  battle.started battle.ended battle.turn_started battle.turn_ended
  battle.move_used battle.damage_dealt battle.status_inflicted battle.fainted
  battle.battler_switched battle.exp_gained battle.ball_thrown pokemon.caught
  pokemon.level_up pokemon.move_learned pokemon.evolved pokemon.before_give
  intro.oak_speech.started intro.oak_speech.step intro.oak_speech.answered
  intro.oak_speech.finished
]])
names("events", 1, [[
  world.live_maps_preparing world.live_maps_updated world.tod_changed
  link.connected link.ended link.battle_ended link.desync pokemon.received
  trade.completed
]])
names("events", 1, "script.started script.ended mod.options_changed")
names("events", 2, [[
  intro.boot.copyright intro.boot.gamefreak intro.boot.title intro.boot.movie
  intro.boot.movie_ended clock.day_changed phone.call_received radio.channel
  breeding.egg_created egg.hatched happiness.changed pokerus.infected
  mail.written mail.read roamer.moved roamer.encountered unown.unlocked
  apricorn.converted bug_contest.scored
]])
names("hooks", 1, [[
  core.update core.quit_to_launcher core.logic_speed input.step input.key
  input.gamepad input.wheel input.pointer render.hud render.viewport render.window
  zoom.range screen.render_visible save.write save.new_game
  music.select music.volume pokemon.sprite pokemon.icon
  movement.collision warp.destination world.follower.spawn world.talk
  encounter.table encounter.roll encounter.species trainer.party evolution.check
  battle.accuracy battle.damage battle.crit battle.charge_required battle.run
  battle.turn_order battle.enemy_action battle.low_health_alarm catch.rate
  exp.gain item.use script.command ui.start_menu.items
]])
names("hooks", 1, [[
  render.zones render.compose render.output_enabled render.output render.letterbox
  player.sprite movement.speed world.tod map.palette fieldmove.eligibility
  encounter.fishing link.fingerprint ui.title_menu.items ui.pc.items ui.list_menu
  ui.options.rows ui.naming.grid ui.party.submenu ui.party.grid_navigation
  intro.oak_speech.build battle.status_hud_visible battle.move_grid_navigation
  battle.overlay battle.exp_award battle.bottom_ui_visible battle.catch_exp
]])
names("hooks", 1, [[
  trainer.before_battle battle.caught_marker_visible battle.menu_auxiliary
  battle.field_residual pokemon.level_visible
]])
names("hooks", 1, "battle.style catch.nickname catch.party_full transition.style")
names("hooks", 2, [[
  shiny.roll gender.roll held_item.trigger breeding.compatibility phone.contact_list
  battle.enemy_switch_or_item
]])

local GEN2_VERSIONS = "gold silver crystal"
local GEN3_VERSIONS = "firered leafgreen ruby sapphire emerald"
local native = { events = {}, hooks = {} }
local function nativeTo(surface, versions, list)
  for name in list:gmatch("%S+") do
    local set = native[surface][name] or {}
    for version in versions:gmatch("%S+") do set[version] = true end
    native[surface][name] = set
  end
end
nativeTo("events", GEN2_VERSIONS, [[
  intro.boot.copyright intro.boot.gamefreak intro.boot.title intro.boot.movie
  intro.boot.movie_ended clock.day_changed phone.call_received radio.channel
  mail.written mail.read unown.unlocked apricorn.converted bug_contest.scored
]])
nativeTo("events", GEN2_VERSIONS .. " " .. GEN3_VERSIONS, [[
  breeding.egg_created egg.hatched happiness.changed pokerus.infected
  roamer.moved roamer.encountered
]])
nativeTo("hooks", GEN2_VERSIONS, "phone.contact_list")
nativeTo("hooks", GEN2_VERSIONS .. " " .. GEN3_VERSIONS, [[
  shiny.roll gender.roll held_item.trigger breeding.compatibility battle.enemy_switch_or_item
]])

local sitesByGeneration = { events = {}, hooks = {} }
local function sites(surface, generations, list)
  for name in list:gmatch("%S+") do
    local set = {}
    for gen in generations:gmatch("%d") do set[tonumber(gen)] = true end
    sitesByGeneration[surface][name] = set
  end
end
sites("events", "123", [[
  assets.transformed battle.ball_thrown battle.battler_switched
  battle.damage_dealt battle.ended battle.exp_gained battle.fainted
  battle.move_used battle.started battle.status_inflicted
  battle.turn_ended battle.turn_started checkpoint.restored
  discord.join_requested flag.changed game.ready
  intro.oak_speech.answered intro.oak_speech.finished
  intro.oak_speech.started intro.oak_speech.step link.battle_ended
  link.connected link.desync link.ended map.entered map.exited
  map.reloaded mod.options_changed mods.loaded music.started
  music.stopped player.warped pokemon.caught pokemon.evolved
  pokemon.level_up pokemon.move_learned pokemon.received save.created
  save.loaded save.loading save.writing screen.popped screen.pushed
  script.ended script.started sound.played trade.completed
  world.blacked_out world.block_replaced world.boulder_moved
  world.interacted world.npc_spawned world.object_toggled world.stepped
  world.trainer_engaged
]])
sites("events", "12", [[
  world.live_maps_preparing world.live_maps_updated world.tod_changed
]])
sites("events", "13", [[
  pokemon.before_give
]])
sites("events", "23", [[
  breeding.egg_created egg.hatched happiness.changed pokerus.infected
  roamer.encountered roamer.moved
]])
sites("events", "2", [[
  apricorn.converted bug_contest.scored clock.day_changed
  intro.boot.copyright intro.boot.gamefreak intro.boot.movie
  intro.boot.movie_ended intro.boot.title mail.read mail.written
  phone.call_received radio.channel unown.unlocked
]])
sites("hooks", "123", [[
  battle.accuracy battle.bottom_ui_visible battle.catch_exp
  battle.caught_marker_visible battle.charge_required battle.crit
  battle.damage battle.enemy_action battle.exp_award
  battle.field_residual battle.low_health_alarm battle.menu_auxiliary
  battle.move_grid_navigation battle.overlay battle.run
  battle.status_hud_visible battle.turn_order catch.nickname catch.rate
  core.logic_speed core.quit_to_launcher core.update encounter.fishing
  encounter.roll encounter.species encounter.table evolution.check
  exp.gain fieldmove.eligibility input.gamepad input.key input.pointer
  input.step input.wheel link.fingerprint movement.collision
  movement.speed music.select music.volume pokemon.icon
  pokemon.level_visible pokemon.sprite render.compose render.hud
  render.letterbox render.output render.output_enabled render.viewport
  render.window render.zones save.new_game save.write
  screen.render_visible script.command trainer.before_battle
  trainer.party ui.list_menu ui.naming.grid ui.options.rows
  ui.party.grid_navigation ui.party.submenu ui.start_menu.items
  warp.destination world.follower.spawn zoom.range
]])
sites("hooks", "12", [[
  intro.oak_speech.build map.palette player.sprite transition.style
  ui.pc.items ui.title_menu.items world.tod
]])
sites("hooks", "13", [[
  item.use world.talk
]])
sites("hooks", "23", [[
  battle.enemy_switch_or_item breeding.compatibility gender.roll
  held_item.trigger shiny.roll
]])
sites("hooks", "1", [[
  battle.style catch.party_full
]])
sites("hooks", "2", [[
  phone.contact_list
]])

function UnifiedCallbacks.catalog()
  return { events = shallow(catalogs.events), hooks = shallow(catalogs.hooks) }
end

function UnifiedCallbacks.nativeVersions(surface, name)
  local set = native[surface] and native[surface][name]
  local introduction = catalogs[surface] and catalogs[surface][name]
  if not introduction then return nil end
  local out = {}
  for _, version in ipairs(GameVersion.ORDER) do
    local gens = sitesByGeneration[surface][name]
    if set then
      if set[version] then out[#out + 1] = version end
    elseif gens and gens[GameVersion.generation(version)] then
      out[#out + 1] = version
    end
  end
  return out
end

local function userEvent(name)
  return type(name) == "string" and name:match("^mod%.[%w_%-]+%..+") ~= nil
end

function UnifiedCallbacks.supports(surface, name, generation, version)
  if not catalogs[surface] then return false, "unsupported callback surface: " .. tostring(surface) end
  if generation ~= 1 and generation ~= 2 and generation ~= 3 then
    return false, "unsupported generation: " .. tostring(generation)
  end
  if version ~= nil then
    if not GameVersion.VERSIONS[version] then return false, "unknown game version: " .. tostring(version) end
    if GameVersion.generation(version) ~= generation then return false, "game version/generation mismatch" end
  end
  if surface == "events" and userEvent(name) then return true end
  local gens = sitesByGeneration[surface][name]
  if catalogs[surface][name] and gens and gens[generation] then
    local set = native[surface][name]
    if not set then return true end
    if version ~= nil then
      if set[version] then return true end
      return false, ("%s callback %s is not native to %s"):format(surface, name, version)
    end
    for candidate in pairs(set) do
      if GameVersion.generation(candidate) == generation then return true end
    end
    return false, ("%s callback %s is not native to Gen %d"):format(surface, name, generation)
  end
  if catalogs[surface][name] then
    return false, ("%s callback %s has no call site in Gen %d"):format(surface, name, generation)
  end
  return false, ("unsupported %s callback %s in Gen %d"):format(surface, tostring(name), generation)
end

local function recordData(value, depth)
  if type(value) ~= "table" then
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return value end
    return nil
  end
  if depth == 0 then return nil end
  local out = {}
  for k, v in pairs(value) do
    if type(k) == "string" or type(k) == "number" then
      out[k] = recordData(v, depth - 1)
    end
  end
  return out
end

local MON_FIELDS = [[species speciesId speciesNumbering item heldItem nickname name
  level hp maxHp maxhp status isEgg egg stats moves pp maxPp ppBonusesPacked
  attack atk defense def speed spe special specialAttack specialDefense spAtk spDef spa spd]]
local function safeMon(raw)
  local out = {}
  for key, value in pairs(raw) do
    local kind = type(value)
    if (type(key) == "string" or type(key) == "number")
        and (kind == "number" or kind == "string" or kind == "boolean") then out[key] = value end
  end
  for key in (MON_FIELDS .. " ivs evs dvs statExp ppBonuses cartExtra caughtData originalTrainer contest ribbons"):gmatch("%S+") do
    out[key] = recordData(raw[key], 3)
  end
  return out
end
local function equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local RECORD_KEYS = {
  mon = "mon", pokemon = "mon", user = "battler", target = "battler",
  attacker = "battler", defender = "battler", battler = "battler",
  egg = "mon", mother = "mon", father = "mon", mon1 = "mon", mon2 = "mon",
  party = "party", slot = "context",
  move = "move", defeatedDef = "species",
}
local IDS = { species = "species", fromSpecies = "species", toSpecies = "species",
  moveId = "move", playerMove = "move", enemyMove = "move", item = "item",
  itemId = "item", ball = "item" }

local function resultRole(name)
  if name == "trainer.party" then return "party" end
  if name == "fieldmove.eligibility" then return "mon" end
  if name == "encounter.roll" or name == "encounter.species"
      or name == "encounter.fishing" then return "encounter" end
end

local function boundary(loader, name, fishing)
  local generation, version = loader.generation, loader.version
  local game = loader:_game()
  local data = game and game.data or {}
  local bindings, mons = {}, {}

  local function id(value, kind)
    if value == nil or value == false or value == 0 then return value end
    return Records.id(value, kind, generation, data)
  end
  local function nativeId(value, kind, original, numeric)
    if value == id(original, kind) then return original end
    if numeric and generation == 3 then original = nil end
    local result, reason = Records.nativeId(value, kind, generation, data, original)
    if result == nil then error(reason, 0) end
    return result
  end

  local function idRole(key)
    if key == "source" and name == "battle.status_inflicted" and generation == 1 then return "move" end
    if key == "evolveTo" and name == "trade.completed" then return "species" end
    return IDS[key]
  end
  local function recordRole(key)
    if name == "trade.completed" and (key == "sent" or key == "received") then return "mon" end
    if name == "link.battle_ended" and (key == "myParty" or key == "theirParty") then return "party" end
    if name == "battle.exp_award" then
      if key == "alive" then return "party" end
      if key == "loser" then return "battler" end
    end
    if name == "encounter.fishing" then
      if key == "old" or key == "good" or key == "super" then return "candidates" end
      if key == "day" or key == "nite" then return "encounter" end
    end
    if key == "dvs" and (name == "shiny.roll" or name == "gender.roll") then return "context" end
    if key == "def" then
      if name == "held_item.trigger" then return "item" end
      if name == "catch.rate" or name == "shiny.roll" or name == "gender.roll" then return "species" end
      return nil
    end
    return RECORD_KEYS[key]
  end

  local view, restoreValue
  local helpers = {}
  local staged, snapshots
  local function stage(raw)
    if not staged[raw] then staged[raw] = shallow(raw) end
    return staged[raw]
  end
  local function remember(entry, before)
    if entry then snapshots[entry] = before end
  end
  local function transaction(fn)
    staged, snapshots = {}, {}
    local results = pack(pcall(fn))
    local pending, before = staged, snapshots
    staged, snapshots = nil, nil
    if not results[1] then error(results[2], 0) end
    for raw, fields in pairs(pending) do
      for key in pairs(raw) do if fields[key] == nil then raw[key] = nil end end
      for key, value in pairs(fields) do if raw[key] ~= value then raw[key] = value end end
    end
    for entry, snapshot in pairs(before) do entry.before = snapshot end
    return unpack(results, 2, results.n)
  end
  local function bind(out, raw, kind)
    local entry = { raw = raw, kind = kind, before = shallow(out) }
    if kind == "mon" or kind == "species" or kind == "move" or kind == "item" then
      entry.before = recordData(out, 5)
    end
    bindings[out] = entry
    return out
  end
  local function monView(raw)
    if mons[raw] then return mons[raw] end
    local out = bind(Records.mon(safeMon(raw), generation, data, version), raw, "mon")
    mons[raw] = out
    return out
  end
  view = function(raw, kind, depth)
    if type(raw) ~= "table" then return raw end
    depth = depth or 0
    if kind == "battler" then
      if not (raw.mon or raw.species or raw.speciesId) then return raw end
      local out = { mon = monView(raw.mon or raw), id = raw.id,
        side = raw.side or (raw.isPlayer == true and "player" or raw.isPlayer == false and "enemy" or nil) }
      for k, v in pairs(out.mon) do if k ~= "native" then out[k] = v end end
      return bind(out, raw, "battler")
    elseif kind == "mon" then return monView(raw)
    elseif kind == "party" or kind == "candidates" then
      if kind == "candidates" and generation == 2
          and (raw.old ~= nil or raw.good ~= nil or raw.super ~= nil) then
        return view(raw, "context", depth)
      end
      if name == "trainer.party" then mons = {} end
      local out = {}
      local role = kind == "party" and "mon" or "encounter"
      for i, record in ipairs(raw) do out[i] = view(record, role) end
      return bind(out, raw, kind)
    elseif kind == "move" or kind == "species" or kind == "item" then
      local out = {}
      for k, v in pairs(raw) do if type(v) ~= "table" and type(v) ~= "function" then out[k] = v end end
      out.id = id(raw.id or raw.numId or raw.species or raw.speciesId, kind)
      if kind == "species" then
        out.baseStats = Records.mon({ stats = raw.baseStats }, generation, data, version).stats
        out.types = recordData(raw.types, 1)
        out.baseExp = raw.baseExp or raw.expYield
        out.expYield = nil
      elseif kind == "move" and generation == 2 then
        out.secondaryChance, out.effectChance = raw.effectChance, nil
      end
      out.native = {}
      for k, v in pairs(raw) do
        if type(v) ~= "table" and type(v) ~= "function" then out.native[k] = v end
      end
      return bind(out, raw, kind)
    end
    local out = shallow(raw)
    out.loader = nil
    if name == "mods.loaded" and raw.loader == loader then
      out.loader = { exports = shallow(loader.exports) }
    end
    for key, value in pairs(raw) do
      local role = recordRole(key)
      if kind == "exp_award" and key == "applyShare" and type(value) == "function" then
        local operation = value
        local function applyShare(mon, ...)
          local entry = bindings[mon]
          local native = entry and entry.kind == "mon" and entry.raw or mon
          transaction(function()
            restoreValue(out, raw, "exp_award")
            for original, public in pairs(mons) do restoreValue(public, original, "mon") end
          end)
          local results = pack(pcall(operation, native, ...))
          for original, public in pairs(mons) do
            local current = Records.mon(safeMon(original), generation, data, version)
            for field in pairs(public) do public[field] = nil end
            for field, fieldValue in pairs(current) do public[field] = fieldValue end
            bindings[public].before = recordData(public, 5)
          end
          if not results[1] then error(results[2], 0) end
          return unpack(results, 2, results.n)
        end
        helpers[applyShare] = operation
        out[key] = applyShare
      elseif role and type(value) == "table" then out[key] = view(value, role, depth + 1)
      elseif idRole(key) and type(value) ~= "table" then out[key] = id(value, idRole(key))
      elseif (key == "opts" or key == "ctx") and type(value) == "table" and depth < 2 then
        out[key] = view(value, "context", depth + 1)
      elseif key == "learnable" and name == "pokemon.level_up" and type(value) == "table" then
        out[key] = {}
        for i, move in ipairs(value) do out[key][i] = id(move, "move") end
      end
    end
    return bind(out, raw, (kind == "encounter" or kind == "exp_award") and kind or "context")
  end

  restoreValue = function(value, original, kind)
    if type(value) ~= "table" then return value end
    local entry = bindings[value]
    if entry then original, kind = entry.raw, entry.kind end
    if kind == "candidates" and generation == 2
        and (value.old ~= nil or value.good ~= nil or value.super ~= nil) then kind = "context" end
    original = original or {}
    local raw = original
    original = stage(raw)
    local before = entry and (snapshots[entry] or entry.before) or {}
    if kind == "mon" then
      local changes = {}
      if entry then
        for k, v in pairs(value) do
          if k ~= "native" and not equal(v, before[k]) then changes[k] = v end
        end
        for _, k in ipairs({ "item", "status" }) do
          if value[k] == nil and before[k] ~= nil then changes[k] = false end
        end
      else
        for k, v in pairs(value) do if k ~= "native" then changes[k] = v end end
      end
      if next(changes) == nil then return raw end
      local safe = safeMon(original)
      local previous = shallow(safe)
      local ok, reason = Records.applyMon(safe, changes, generation, data, version)
      if not ok then error(reason, 0) end
      if generation == 3 and name == "trainer.party" then
        if changes.species then
          local species = nativeId(changes.species, "species", original.species or original.speciesId, true)
          safe[safe.species ~= nil and "species" or "speciesId"] = species
          if safe.species ~= nil and safe.speciesId ~= nil then safe.speciesId = species end
        end
        if changes.item and changes.item ~= false then
          safe[safe.item ~= nil and "item" or "heldItem"] =
            nativeId(changes.item, "item", original.item or original.heldItem, true)
        end
        if changes.moves then
          for i, move in ipairs(changes.moves) do
            local prior = before.moves and before.moves[i]
            if not prior or move.id ~= prior.id then
              local num, why = Records.nativeId(move.id, "move", generation, data)
              if num == nil then error(why, 0) end
              local row = safe.moves[i]
              if type(row) == "table" then
                local key = row.id ~= nil and "id" or row.move ~= nil and "move"
                  or row.num ~= nil and "num" or row.moveId ~= nil and "moveId"
                  or row.name ~= nil and "name" or row[1] ~= nil and 1 or "id"
                row[key] = num
              else safe.moves[i] = num end
            end
          end
        end
      end
      for key in MON_FIELDS:gmatch("%S+") do
        if not equal(safe[key], previous[key]) then original[key] = safe[key] end
      end
      remember(entry, recordData(value, 5))
      return raw
    elseif kind == "battler" then
      local canonical = value.mon or {}
      for k, v in pairs(value) do
        if k ~= "mon" and k ~= "id" and k ~= "side" and k ~= "native"
            and (not entry or v ~= before[k]) then canonical[k] = v end
      end
      if entry then
        for _, key in ipairs({ "item", "status" }) do
          if value[key] == nil and before[key] ~= nil then canonical[key] = false end
        end
      end
      restoreValue(canonical, original.mon or raw, "mon")
      remember(entry, shallow(value))
      return raw
    elseif kind == "party" or kind == "candidates" then
      local out = {}
      local unchanged = #value == #original
      local role = kind == "party" and "mon" or "encounter"
      for i, record in ipairs(value) do
        local prior = original[i]
        if fishing and kind == "candidates" and not bindings[record] then prior = nil end
        out[i] = restoreValue(record, prior, role)
        if out[i] ~= original[i] then unchanged = false end
      end
      if unchanged then return raw end
      return out
    end
    local keys = shallow(before)
    for k in pairs(value) do keys[k] = true end
    for key in pairs(keys) do
      local v, old = value[key], original[key]
      if key ~= "native" and key ~= "loader" then
        if kind == "exp_award" and key == "applyShare" and type(v) == "function" then
          original[key] = helpers[v] or v
        elseif type(v) == "table" and bindings[v] then
          original[key] = restoreValue(v, old)
        elseif idRole(key) and (not entry or v ~= before[key]) then
          original[key] = nativeId(v, idRole(key), old, kind == "encounter")
          if kind == "encounter" and key == "species" and original.speciesId ~= nil then
            original.speciesId = nativeId(v, "species", original.speciesId, true)
          end
        elseif kind == "species" and key == "baseStats" then
          if not equal(v, before[key]) then
            local native = { stats = recordData(original.baseStats or {}, 1) }
            local ok, reason = Records.applyMon(native, { stats = v }, generation, data, version)
            if not ok then error(reason, 0) end
            original.baseStats = native.stats
          end
        elseif kind == "species" and key == "baseExp" then
          if v ~= before[key] then original[original.expYield ~= nil and "expYield" or key] = v end
        elseif kind == "move" and key == "secondaryChance" and generation == 2 then
          if v ~= before[key] then original.effectChance = v end
        elseif (kind == "move" or kind == "species" or kind == "item") and key == "id" then
          if v ~= before[key] then original[key] = nativeId(v, kind, old) end
        elseif v ~= before[key] then
          local role = recordRole(key)
          if role and type(v) == "table" then original[key] = restoreValue(v, old, role)
          else original[key] = v end
        end
      end
    end
    remember(entry, (kind == "context" or kind == "encounter" or kind == "exp_award")
      and shallow(value) or recordData(value, 5))
    return raw
  end

  local function roles()
    if name == "battle.exp_award" then return { "exp_award" } end
    if name == "battle.turn_order" then return { "battler", "move", "battler", "move", "context" } end
    if name == "catch.rate" then return { "itemId", "mon", "species", "context" } end
    if name == "trainer.party" then return { false, false, "party" } end
    if name == "fieldmove.eligibility" then return { "moveId", "context" } end
    if name == "encounter.fishing" then return { false, false, "candidates" } end
    if name == "encounter.species" then return { "encounter", "context" } end
    if name == "pokemon.level_visible" or name == "catch.nickname" then return { "mon", "context" } end
    if name == "evolution.check" then return { false, "mon", "context", "context" } end
    if name == "item.use" then return { false, "mon", "itemId", false } end
    if name == "ui.party.submenu" then return { false, false, "mon", "context" } end
    if name == "battle.enemy_action" or name == "battle.enemy_switch_or_item"
        or name == "battle.overlay" or name == "battle.status_hud_visible"
        or name == "battle.bottom_ui_visible"
        or name == "battle.move_grid_navigation" then return { false } end
    if name:match("^ui%.") or name == "core.update" or name == "core.logic_speed"
        or name:match("^input%.") or name == "render.hud" or name == "render.zones"
        or name == "render.window" or name == "render.compose" or name == "save.write"
        or name == "world.follower.spawn" or name == "world.talk" then return { false, false } end
    return {}
  end
  local positions = roles()
  local function arguments(args)
    local out = { n = args.n }
    for i = 1, args.n do
      local role = positions[i]
      if role == false then out[i] = args[i]
      elseif role == "itemId" then out[i] = id(args[i], "item")
      elseif role == "moveId" then out[i] = id(args[i], "move")
      else out[i] = view(args[i], role or "context") end
    end
    return out
  end
  local function restoreArguments(args, originals)
    local out = { n = args.n }
    for i = 1, args.n do
      local role = positions[i]
      if role == false then out[i] = args[i]
      elseif role == "itemId" then out[i] = nativeId(args[i], "item", originals[i])
      elseif role == "moveId" then out[i] = nativeId(args[i], "move", originals[i], true)
      else out[i] = restoreValue(args[i], originals[i], role or "context") end
    end
    return out
  end
  local function restore(value, original, kind)
    return transaction(function() return restoreValue(value, original, kind) end)
  end
  local function rawArguments(args, originals, results)
    return transaction(function()
      local out = restoreArguments(args, originals)
      local role = resultRole(name)
      if results and role and type(results[1]) == "table" then
        results[1] = restoreValue(results[1], nil, role)
      end
      return out
    end)
  end
  return view, restore, arguments, rawArguments
end

local function fishingArguments(loader, name, originals)
  if loader.generation ~= 2 or name ~= "encounter.fishing"
      or type(originals[3]) ~= "table" then return originals end
  local rods = { OLD_ROD = "old", GOOD_ROD = "good", SUPER_ROD = "super" }
  local rod = rods[originals[1]] or originals[1] or "old"
  local group, args = originals[3], shallow(originals)
  local selected, pool = group[rod], nil
  if type(selected) == "table" then
    pool = {}
    for i, row in ipairs(selected) do
      pool[i] = shallow(row)
      for _, key in ipairs({ "day", "nite" }) do
        if type(row[key]) == "table" then pool[i][key] = shallow(row[key]) end
      end
    end
  end
  args[3] = pool
  return args, function(native)
    if native.n == 3 and originals.n > 3 then
      native.n = originals.n
      for i = 4, originals.n do native[i] = originals[i] end
    end
    local candidates = native[3]
    if equal(candidates, selected) then
      native[3] = group
      return native
    end
    if type(candidates) ~= "table" then
      native[3] = nil
      return native
    end
    local rows, unchanged, valid, previous = {}, true, true, 0
    unchanged = #candidates == #(selected or {})
    for i, row in ipairs(candidates) do
      rows[i] = shallow(row)
      local chance = row.chance
      if row ~= (pool and pool[i]) or chance ~= (selected and selected[i] and selected[i].chance) then
        unchanged = false
      end
      if type(chance) ~= "number" or chance ~= chance or chance % 1 ~= 0
          or chance < previous or chance > 256 then
        valid = false
      else previous = chance end
    end
    valid = valid and previous == 256
    if not unchanged and not valid then
      for i, row in ipairs(rows) do row.chance = math.floor(i * 256 / #rows) end
    end
    local changed = shallow(group)
    changed[rod] = rows
    native[3] = changed
    return native
  end
end

local function menuSelections(loader, modId, name, originals)
  if name ~= "ui.start_menu.items" and name ~= "ui.party.submenu" then return end
  local nativeSelections = {}
  for _, row in pairs(type(originals[2]) == "table" and originals[2] or {}) do
    if type(row) == "table" and type(row.onSelect) == "function" then
      nativeSelections[row.onSelect] = true
    end
  end
  local provider, game = loader._game, originals[1]
  local currentGame = loader:_game()
  local save, session = game and game.save, game and game.session
  local generation, version = loader.generation, loader.version
  local hooks, runtimeHooks = loader.hooks, Runtime.hooks
  local epoch = hooks.ownerEpoch and hooks:ownerEpoch(modId)
  local native = generation == 3 and package.loaded["src.core.game3.runtime"]
  local nativeSession = native and native.getSession and native.getSession()
  return function(rows)
    if type(rows) ~= "table" then return rows end
    local out = rows
    for key, row in pairs(rows) do
      local callback = type(row) == "table" and row.onSelect
      if type(callback) == "function" and not nativeSelections[callback]
          and not wrappedSelections[callback] then
        local wrapped = function(mon, callbackGame)
          local previous = Runtime.currentMod
          local results = pack(pcall(function()
            if loader._game ~= provider or loader:_game() ~= currentGame
                or loader.generation ~= generation or loader.version ~= version
                or loader.hooks ~= hooks or Runtime.hooks ~= runtimeHooks
                or hooks.ownerEpoch and hooks:ownerEpoch(modId) ~= epoch
                or (game and (game.save ~= save or game.session ~= session)) then return end
            if native and (package.loaded["src.core.game3.runtime"] ~= native
                or native.getSession and native.getSession() ~= nativeSession) then return end
            if name == "ui.party.submenu" and callbackGame ~= game then return end
            Runtime.currentMod = modId
            if name == "ui.start_menu.items" then return callback() end
            local view, restore = boundary(loader, name)
            local public = view(mon, "mon")
            local selected = pack(callback(public, game))
            restore(public, mon, "mon")
            return unpack(selected, 1, selected.n)
          end))
          Runtime.currentMod = previous
          if not results[1] then
            Runtime.reportError(modId, name .. " onSelect: " .. tostring(results[2]))
            return
          end
          return unpack(results, 2, results.n)
        end
        wrappedSelections[wrapped] = true
        if out == rows then out = shallow(rows) end
        out[key] = shallow(row)
        out[key].onSelect = wrapped
      end
    end
    return out
  end
end

function UnifiedCallbacks.new(loader, modId)
  local prefix = "mod." .. modId .. "."
  local function check(surface, name)
    if catalogs[surface][name] or (surface == "events" and userEvent(name)) then return end
    local ok, reason = UnifiedCallbacks.supports(surface, name, loader.generation, loader.version)
    if not ok then error(reason, 0) end
  end
  local function subscribe(once, name, callback, priority)
    check("events", name)
    assert(type(callback) == "function", "event callback must be a function")
    local wrapped = callback
    if not userEvent(name) then
      wrapped = function(payload)
        local view, restore = boundary(loader, name)
        local public = view(payload, "context")
        local results = pack(callback(public))
        if name == "pokemon.before_give" then restore(public, payload, "context") end
        return unpack(results, 1, results.n)
      end
    end
    if once then return loader.events:once(name, wrapped, priority, modId) end
    return loader.events:on(name, wrapped, priority, modId)
  end
  return {
    events = {
      on = function(_, name, callback, priority) return subscribe(false, name, callback, priority) end,
      once = function(_, name, callback, priority) return subscribe(true, name, callback, priority) end,
      emit = function(_, name, payload)
        if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix or #name <= #prefix then
          error(("[%s] mods may only emit %s* events"):format(modId, prefix), 0)
        end
        return loader.events:emit(name, payload)
      end,
    },
    hooks = {
      wrap = function(_, name, callback, priority)
        check("hooks", name)
        assert(type(callback) == "function", "hook callback must be a function")
        return loader.hooks:wrap(name, function(nextFn, ...)
          local originals = pack(...)
          local selections = menuSelections(loader, modId, name, originals)
          local restoreFishing
          originals, restoreFishing = fishingArguments(loader, name, originals)
          local view, _, arguments, rawArguments = boundary(loader, name, name == "encounter.fishing")
          local public = arguments(originals)
          local downstream, downstreamPublic, called
          local function nextPublic(...)
            if not called then
              local supplied = select("#", ...) > 0 and pack(...) or public
              local native = rawArguments(supplied, originals)
              if restoreFishing then native = restoreFishing(native) end
              called = true
              downstream = pack(pcall(nextFn, unpack(native, 1, native.n)))
              if downstream[1] then
                downstreamPublic = pack(unpack(downstream, 2, downstream.n))
                local role = resultRole(name)
                if role and type(downstreamPublic[1]) == "table" then
                  downstreamPublic[1] = view(downstreamPublic[1], role)
                end
              end
            end
            if not downstream[1] then error(downstream[2], 0) end
            return unpack(downstreamPublic, 1, downstreamPublic.n)
          end
          local results = pack(callback(nextPublic, unpack(public, 1, public.n)))
          rawArguments(public, originals, results)
          if selections then results[1] = selections(results[1]) end
          return unpack(results, 1, results.n)
        end, priority, modId)
      end,
    },
  }
end

return UnifiedCallbacks

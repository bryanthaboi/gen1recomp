package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
local Collision = require("src.core.game3.collision")
local MB = require("src.core.game3.mb")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
require("src.core.game3.save_sections").of("emerald")
require("src.core.game3.save_sections").of("ruby")
local s
local function stub(name, value) package.loaded["src.core.game3." .. name] = value end
stub("runtime", { isActive = function() return true end, getSession = function() return s end })
stub("scripting.space", { bundle = {}, ensureBundle = function() end, activate = function() end,
  runEnterScripts = function() end, runOnWarpIntoMap = function() end })
stub("ghosts", { capture = function() end, adopt = function() end,
  visibleIds = function() return {} end, openFadeWindow = function() end })
stub("field", { lock = function() end, unlock = function() end, clearMetatiles = function() end })
stub("audio", { setSavedSong = function() end, canOverrideMapMusic = function() return false end,
  stopSurfMusic = function() end, bikeMusic = function() end })
stub("encounters", { resetRateModifiers = function() end })
stub("field_effects", { leaveTallGrass = function() end, tallGrassAt = function() end })
stub("field_view", { setCameraPanning = function() end })
stub("field_modules", { enabled = function() return false end })
stub("rse.init", { call = function() end })
stub("rs.rematch", { enabled = function() return false end })
stub("rse.rematch", { tryUpdateRandomTrainerRematchesForMap = function() end })
stub("time_events", { run = function() end })
stub("objects", { loadMap = function() end, restoreSnapshot = function() end, beginFadeIn = function() end })
local Player = require("src.core.game3.player")
local Map = require("src.core.game3.map")
local Sprites = require("src.core.game3.ow_sprites")
local Flags = require("src.core.game3.scripting.flags")
local game = { save = { position = {} }, data = { maps = {} } }
local mid, def
local behavior, elevation, coll
local function terrain(beh, elev, collision)
  behavior, elevation, coll = beh, elev, collision
  Interaction.behaviors[def.pair] = { [0] = beh }
end
local function setup(version)
  GameVersion.set(version)
  s = { version = version, flags = {}, vars = {}, party = {}, name = "SURFER" }
  mid = require("src.core.game3.profile").of(version).map.enginePrefix .. "AVATAR_TEST"
  s.map, s.x, s.y, s.facing = mid, 0, 0, "right"
  def = { width = 2, height = 2, mapType = 4, objects = {}, connections = {}, bikingAllowed = 1, pair = "avatar_test" }
  local layout = { width = 2, height = 2, pair = def.pair }
  function layout:collAt() return coll end
  function layout:elevAt() return elevation end
  function layout:midAt() return 0 end
  function layout:collArray() return { coll, coll, coll, coll } end
  def.midLayout = layout
  game.data.maps, game.session = { [mid] = def }, s
  terrain(MB.OCEAN_WATER, 1, 0x29)
  Player.reset(0, 0, "right")
end
local function load(opts)
  opts = opts or {}
  opts.x, opts.y, opts.facing = 0, 0, opts.facing or "right"
  check(Map.load(nil, game, mid, opts) ~= nil, "real Map.load completes")
end
local function roundtrip(surfing, underwater, elev)
  s.surfing, s.underwater, s.biking, s.elevation = surfing, underwater, false, elev
  local disk = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  s = Schema.fromSaveTable(disk)
  game.session = s
  Player.syncFromSession(s)
  load({ enterVia = "continue", initialLoad = true })
end
for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  for gender = 0, 1 do
    setup(version)
    s.gender = gender
    roundtrip(true, false, 1)
    check(Player.surfing and not Player.underwater and not Player.biking,
      version .. " native_codec_final_reset_restores_surf gender=" .. gender)
    eq(Sprites.avatarState(Player), "SURFING", version .. " saved Surf graphics")
    check(not Player.surfHopping and not Player.dismounting, version .. " Continue has no Surf animation")
    roundtrip(false, false, 4)
    check(not Player.surfing and not Player.underwater, version .. " explicit_on_foot_water_continue")
    eq(Player.elevation, 4, version .. " saved upper elevation")
  end
  setup(version)
  s.surfing, s.underwater = nil, nil
  s = Schema.fromSaveTable(SaveData.decode(SaveData.encode(Schema.toSaveTable(s))))
  eq(s.surfing, nil, version .. " legacy absence retained")
  Player.syncFromSession(s)
  load({ enterVia = "continue", initialLoad = true })
  check(Player.surfing, version .. " legacy_surfable_continue")
  Player.surfing, Player.underwater = true, false
  load({ seamless = true })
  check(Player.surfing, version .. " seamless preserves Surf")
  terrain(MB.NORMAL, 3, 0)
  load()
  check(not Player.surfing and not Player.underwater, version .. " ordinary_land_clears_avatar")
  terrain(MB.OCEAN_WATER, 1, 0x29)
  load()
  check(Player.surfing, version .. " ordinary_surfable_entry")
  local cruise = Flags.forVersion(version).IDS.FLAG_SYS_CRUISE_MODE
  Flags.setFlag(s, nil, cruise, true)
  def.mapType = 6
  load()
  check(not Player.surfing and not Player.underwater, version .. " cruise wins over water")
  eq(Player.facing, "right", version .. " cruise direction")
  Flags.setFlag(s, nil, cruise, false)
  if version == "firered" or version == "leafgreen" then
    mid = "FR_SEAFOAM_ISLANDS_B3F"
    s.map = mid
    game.data.maps[mid] = def
    load()
    check(not Player.surfing, version .. " seafoam_ordinary_on_foot")
    roundtrip(true, false, 1)
    check(Player.surfing, version .. " seafoam_saved_surf_continue")
  else
    def.mapType = 5
    load()
    check(Player.underwater and not Player.surfing, version .. " underwater_entry")
    roundtrip(false, true, 1)
    check(Player.underwater and not Player.surfing, version .. " native_underwater_continue")
    def.mapType = 4
    load()
    check(Player.surfing and not Player.underwater, version .. " dive_surface_entry")
    terrain(MB.BRIDGE_OVER_OCEAN, 4, 0)
    s.surfing, s.underwater, s.elevation = nil, nil, nil
    s = Schema.fromSaveTable(Schema.toSaveTable(s))
    Player.syncFromSession(s)
    load({ enterVia = "continue" })
    check(not Player.surfing, version .. " legacy_upper_bridge_on_foot")
  end
  setup(version)
  s.surfing, s.underwater = true, false
  s.specialSaveWarpFlags = 1
  s.continueGameWarp = { map = mid, x = 0, y = 0 }
  s = Schema.fromSaveTable(Schema.toSaveTable(s))
  terrain(MB.NORMAL, 3, 0)
  Player.syncFromSession(s)
  load({ enterVia = "continue" })
  check(not Player.surfing, version .. " special_continue_relocation_clears_saved_surf")
end
Player.underwater = true
Player.reset(0, 0, "right")
check(not Player.underwater, "reset clears stale underwater")
local ModRuntime = require("src.mods.Runtime")
local wants, emit = ModRuntime.wants, ModRuntime.emit
local expected, label, observed, nativeShape
local function synchronized()
  eq(s.surfing, expected.surfing, label .. " session Surf")
  eq(game.save.surfing, expected.surfing, label .. " host Surf")
  eq(s.biking, expected.biking, label .. " session bike")
  eq(game.save.biking, expected.biking, label .. " host bike")
  if nativeShape then
    eq(game.save.position, nil, label .. " native save stays flat")
  else
    eq(game.save.position.biking, expected.biking, label .. " host position bike")
  end
  eq(s.underwater, false, label .. " session underwater")
  eq(game.save.elevation, Player.elevation, label .. " host elevation")
  if not nativeShape then eq(game.save.position.x, Player.cellX, label .. " host x") end
  eq(s.x, Player.cellX, label .. " session x")
end
ModRuntime.wants = function(name) return name == "world.stepped" end
ModRuntime.emit = function(name)
  eq(name, "world.stepped", label .. " observer event")
  observed = observed + 1
  synchronized()
end
local function completed(surfing, biking, name)
  expected, label, observed = { surfing = surfing, biking = biking }, name, 0
  local callback = 0
  Player._onStepDone = function()
    callback = callback + 1
    synchronized()
  end
  local frames = Player.stepFrames
  for _ = 1, frames do Player.tick(game) end
  check(not Player.moving and Player.surfing == surfing and Player.biking == biking, label .. " live completed mode")
  eq(observed, 1, label .. " observer runs once")
  eq(callback, 1, label .. " callback runs once")
  synchronized()
end
for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  local road = Flags.forVersion(version).IDS.FLAG_SYS_ON_CYCLING_ROAD
  for _, native in ipairs({ false, true }) do
    nativeShape = native
    for _, cycling in ipairs(road and { false, true } or { false }) do
      setup(version)
      terrain(MB.NORMAL, 3, 0)
      load()
      game.save = native and Schema.toSaveTable(s) or { position = {} }
      terrain(MB.OCEAN_WATER, 1, 0x29)
      Collision.bindMap(game, mid, def)
      check(Player.startSurfing(game), version .. " mount starts")
      local suffix = " native=" .. tostring(native) .. " cycling=" .. tostring(cycling)
      completed(true, false, version .. " completed_mount_sync" .. suffix)
      if native then game.save = Schema.toSaveTable(s) end
      terrain(MB.NORMAL, 3, 0)
      Collision.bindMap(game, mid, def)
      if road then Flags.setFlag(s, nil, road, cycling) end
      check(Player.forcedStep("left"), version .. " dismount starts")
      check(Player.dismounting, version .. " dismount transition selected")
      completed(false, cycling, version .. (cycling and " cycling_remount_sync" or " completed_dismount_sync") .. suffix)
    end
  end
end
ModRuntime.wants, ModRuntime.emit = wants, emit
T.finish("game3_avatar_restore_2759_2761")

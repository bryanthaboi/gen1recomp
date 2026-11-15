local Std = require("src.core.game3.scripting.stdscripts")
local Rse = require("src.core.game3.rse.init")

local PcRse = {}

local VAR_0x8004 = 0x8004
local VAR_RESULT = 0x800D
-- pokeemerald/include/constants/script_menu.h:4
local MULTI_B_PRESSED = 127
-- pokeemerald/include/constants/field_specials.h:25
local PC_LOCATION_OTHER = 0
local PC_LOCATION_BRENDANS_HOUSE = 1
local PC_LOCATION_MAYS_HOUSE = 2

local function natives()
  return require("src.core.game3.scripting.natives")
end

local function isRse()
  return Rse.isRse(Rse.session())
end

local function metatile(name)
  local Constants = require("src.core.game3.constants")
  local C = Constants.of(require("src.core.game3.profile").forSession(Rse.session()).id)
  return C:require("metatile_labels", name)
end

-- pokeemerald/src/field_specials.c:1046
local PC_TILES = {
  [PC_LOCATION_OTHER] = { on = "METATILE_Building_PC_On", off = "METATILE_Building_PC_Off" },
  [PC_LOCATION_BRENDANS_HOUSE] = { on = "METATILE_BrendansMaysHouse_BrendanPC_On", off = "METATILE_BrendansMaysHouse_BrendanPC_Off" },
  [PC_LOCATION_MAYS_HOUSE] = { on = "METATILE_BrendansMaysHouse_MayPC_On", off = "METATILE_BrendansMaysHouse_MayPC_Off" },
}
PcRse.PC_TILES = PC_TILES

-- pokeemerald/src/field_specials.c:1016
local function pcTarget()
  local P = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local dx, dy = 0, 0
  if P.facing == "up" then
    dx, dy = 0, -1
  elseif P.facing == "left" then
    dx, dy = -1, -1
  elseif P.facing == "right" then
    dx, dy = 1, -1
  end
  return (tonumber(P.cellX) or 0) + dx, (tonumber(P.cellY) or 0) + dy
end

function PcRse.setPcMetatile(ctx, on)
  local loc = Rse.specialVar(ctx, VAR_0x8004)
  local row = PC_TILES[loc]
  if not row then return nil end
  local mid = metatile(on and row.on or row.off)
  local x, y = pcTarget()
  local PcAnim = require("src.core.game3.pc_anim")
  if PcAnim._set then
    PcAnim._set(x, y, mid, true)
  else
    require("src.core.game3.field").setMetatile(x, y, mid, true)
  end
  return mid, x, y
end

local function openPc(ctx, adapters, pcOpts, after)
  if not (adapters and adapters.openPc) then return false end
  return natives().yieldHost(ctx, adapters, function(done)
    adapters.openPc(function(result)
      if after then after(result) end
      done()
    end, pcOpts)
  end)
end

PcRse.BY_NAME = {
  -- pokeemerald/src/script_menu.c:314
  ScriptMenu_CreatePCMultichoice = function(ctx, adapters)
    Rse.setSpecialVar(ctx, VAR_RESULT, 0xFF)
    return openPc(ctx, adapters, { mode = "select" }, function(result)
      local v = tonumber(result)
      if v == nil then v = MULTI_B_PRESSED end
      Rse.setSpecialVar(ctx, VAR_RESULT, v)
    end)
  end,
  -- pokeemerald/src/player_pc.c:373
  BedroomPC = function(ctx, adapters)
    if not isRse() then return natives().CORE.BedroomPC(ctx, adapters) end
    return openPc(ctx, adapters, { mode = "player", bedroom = true }, function()
      -- pokeemerald/src/player_pc.c:478
      PcRse.bedroomTurnOff(ctx)
    end)
  end,
  -- pokeemerald/src/hof_pc.c:14
  AccessHallOfFamePC = function(ctx, adapters)
    if not (adapters and adapters.hallOfFamePc) then return false end
    return natives().yieldHost(ctx, adapters, function(done)
      adapters.hallOfFamePc(function()
        -- pokeemerald/src/hof_pc.c:30
        adapters.openPc(function(result)
          local v = tonumber(result)
          if v == nil then v = MULTI_B_PRESSED end
          Rse.setSpecialVar(ctx, VAR_RESULT, v)
          done()
        end, { mode = "select", reshow = true })
      end)
    end)
  end,
  -- pokeemerald/src/field_specials.c:986
  DoPCTurnOnEffect = function(ctx)
    PcRse.setPcMetatile(ctx, true)
    return false
  end,
  -- pokeemerald/src/field_specials.c:1073
  DoPCTurnOffEffect = function(ctx)
    PcRse.setPcMetatile(ctx, false)
    return false
  end,
  -- pokeemerald/src/post_battle_event_funcs.c:12
  GameClear = function(ctx)
    local sess = Rse.session()
    local Storage = require("src.core.game3.storage")
    for _, mon in ipairs(sess and sess.party or {}) do Storage.fullHealMon(mon, sess) end
    local hasRecords = Rse.flag("FLAG_SYS_GAME_CLEAR", sess)
    if not hasRecords then Rse.setFlag("FLAG_SYS_GAME_CLEAR", true, sess) end
    if sess then PcRse.gameClearState(sess) end
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade.clear then Fade.clear() end
    require("src.ui.game3.hall_of_fame").start({
      session = sess,
      warp = false,
      credits = true,
      hasRecords = hasRecords,
      onDone = function()
        -- pokeemerald/src/credits.c:694
        local rt = package.loaded["src.core.game3.runtime"]
        local game = rt and rt._game
        if game then game.softResetRequested = true end
      end,
    })
    natives().awaitState(ctx, function() return false end)
    return false
  end,
  -- pokeemerald/src/field_specials.c:3017
  GetPCBoxToSendMon = function(ctx, adapters)
    if not isRse() then
      local Q = require("src.core.game3.scripting.natives_queries")
      return Q.BY_NAME.GetPCBoxToSendMon(ctx, adapters)
    end
    return false, Rse.var("VAR_PC_BOX_TO_SEND_MON")
  end,
}

-- pokeemerald/include/constants/game_stat.h:5
local GAME_STAT_FIRST_HOF_PLAY_TIME = 1
local GAME_STAT_RECEIVED_RIBBONS = 42
-- pokeemerald/include/save_location.h:5
local CONTINUE_GAME_WARP = 0x01

-- pokeemerald/src/post_battle_event_funcs.c:33
function PcRse.gameClearState(sess)
  local Bit = require("bit")
  sess.gameStats = type(sess.gameStats) == "table" and sess.gameStats or {}
  if (tonumber(sess.gameStats[GAME_STAT_FIRST_HOF_PLAY_TIME]) or 0) == 0 then
    local pt = sess.playtime or sess.playTime or {}
    sess.gameStats[GAME_STAT_FIRST_HOF_PLAY_TIME] = Bit.bor(Bit.lshift(tonumber(pt.hours) or 0, 16),
      Bit.lshift(tonumber(pt.minutes) or 0, 8), tonumber(pt.seconds) or 0)
  end
  -- pokeemerald/src/load_save.c:144
  sess.specialSaveWarpFlags = Bit.bor(tonumber(sess.specialSaveWarpFlags) or 0, CONTINUE_GAME_WARP)
  -- pokeemerald/src/post_battle_event_funcs.c:38
  local male = (tonumber(sess.gender) or 0) == 0
  local Constants = require("src.core.game3.constants")
  local C = Constants.of(Constants.versionOf(sess))
  local heal = C:require("heal_locations", male and "HEAL_LOCATION_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"
    or "HEAL_LOCATION_LITTLEROOT_TOWN_MAYS_HOUSE_2F")
  -- pokeemerald/src/overworld.c:728
  local loc = require("src.core.game3.heal_locations").get(heal)
  if loc then sess.continueGameWarp = { map = loc.map, x = loc.x, y = loc.y } end
  -- pokeemerald/src/post_battle_event_funcs.c:45
  local Pokemon = require("src.core.game3.pokemon")
  local Ribbons = require("src.core.game3.rse.ribbons")
  local gave, best, bestCount = false, nil, 0
  for i = 1, 6 do
    local mon = type(sess.party) == "table" and sess.party[i] or nil
    if type(mon) == "table" and (tonumber(mon.species) or 0) ~= 0 and not Pokemon.isEgg(mon)
        and Ribbons.get(mon, "champion") == 0 then
      Ribbons.set(mon, "champion", 1)
      gave = true
      local n = Ribbons.count(mon)
      if n > bestCount then best, bestCount = mon, n end
    end
  end
  -- pokeemerald/src/post_battle_event_funcs.c:78
  if gave and best and bestCount > Ribbons.NUM_CUTIES_RIBBONS then
    require("src.core.game3.rse.init").call("tv", "tryPutSpotTheCutiesOnAir", "GameClear", nil, best, "champion")
  end
  if gave then
    -- pokeemerald/src/post_battle_event_funcs.c:65
    sess.gameStats[GAME_STAT_RECEIVED_RIBBONS] = math.min(0xFFFFFF, (tonumber(sess.gameStats[GAME_STAT_RECEIVED_RIBBONS]) or 0) + 1)
    Rse.setFlag("FLAG_SYS_RIBBON_GET", true, sess)
  end
end

-- pokeemerald/data/maps/LittlerootTown_BrendansHouse_2F/scripts.inc:240
function PcRse.bedroomTurnOff(ctx)
  local male = (tonumber(Rse.session() and Rse.session().gender) or 0) == 0
  Rse.setSpecialVar(ctx, VAR_0x8004, male and PC_LOCATION_BRENDANS_HOUSE or PC_LOCATION_MAYS_HOUSE)
  local SE = require("src.core.game3.se_ids")
  pcall(function() require("src.core.game3.audio").playSe(SE.SE_PC_OFF) end)
  PcRse.setPcMetatile(ctx, false)
end

if not Rse._systems.decorations then
  Rse.register("decorations", require("src.core.game3.rse.decoration_inventory"))
end

Std.legacyHandlers(PcRse)

return PcRse

local FldeffMisc = {}

local CELL = 16

local function FE()
  return package.loaded["src.core.game3.field_effects"] or require("src.core.game3.field_effects")
end

local function Rse()
  return require("src.core.game3.field_effects_rse")
end

local function Player()
  return package.loaded["src.core.game3.player"] or require("src.core.game3.player")
end

local function session()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function vmCtx()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.vm and Space.vm.ctx or nil
end

local function playSe(name)
  local SE = require("src.core.game3.se_ids")
  local id = SE[name]
  if not id then return end
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.playSe then Audio.playSe(id) end
end
FldeffMisc.playSe = playSe

local function C()
  local Constants = require("src.core.game3.constants")
  return Constants.of(Constants.versionOf(session()))
end

local function metatile(name)
  local policy = require("src.core.game3.profile").forSession(session()).secretBase
  if policy and policy.metatiles and policy.metatiles[name] then return policy.metatiles[name] end
  return C():require("metatile_labels", name)
end
FldeffMisc.metatile = metatile

local function setMetatile(x, y, name, impassable)
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.setMetatile then Field.setMetatile(x, y, metatile(name), impassable == true) end
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function facingCell()
  local P = Player()
  local d = DELTA[P.facing or "down"] or DELTA.down
  return P.cellX + d[1], P.cellY + d[2]
end
FldeffMisc.facingCell = facingCell

FldeffMisc._active = {}

local function begin(name)
  local ctx = vmCtx()
  local token = {}
  FldeffMisc._active[name] = token
  if ctx then
    ctx.stateWait = function() return FldeffMisc._active[name] ~= token end
  end
  return token
end

local function finish(name, token)
  if token == nil or FldeffMisc._active[name] == token then FldeffMisc._active[name] = nil end
end

function FldeffMisc.isActive(name)
  return FldeffMisc._active[name] ~= nil
end

local function partyMon(idx)
  local s = session()
  local party = s and s.party
  return party and party[(tonumber(idx) or 0) + 1] or (party and party[1])
end

-- pokeemerald/src/field_effect.c:2570
local function showMon(onDone, opts)
  local mon = partyMon(FE().fieldEffectArgument(0, 0))
  local ok, ShowMon = pcall(require, "src.core.game3.field_move_show_mon")
  if ok and ShowMon and ShowMon.start and mon then
    ShowMon.start(mon, { pose = not (opts and opts.noPose), noDuck = opts and opts.noDuck }, onDone)
  else
    onDone()
  end
end
FldeffMisc.showMon = showMon

local function fieldMove(name, se, after)
  return function()
    local token = begin(name)
    showMon(function()
      if se then playSe(se) end
      if after then after() end
      finish(name, token)
    end)
    return true
  end
end

-- pokeemerald/src/fldeff_misc.c:547
local function secretPower(useName, sheet, se, toggleAt)
  return function()
    local token = begin(useName)
    showMon(function()
          local fx, fy = facingCell()
      local anim = 1
      if sheet == "secret_power_tree" then
        local MB = require("src.core.game3.mb")
        local Collision = package.loaded["src.core.game3.collision"]
        local b = Collision and Collision.behavior and Collision.behavior(fx, fy)
        -- pokeemerald/src/fldeff_misc.c:672
        if b == MB.id("SECRET_BASE_SPOT_TREE_RIGHT") then anim = 3 end
      end
      playSe(se)
      local toggled = false
      Rse().spawn(sheet, {
        anim = anim, layer = "front", x = fx * CELL + 8, y = fy * CELL + 8,
        stopOnEnd = false,
        onStep = function(e)
          if not toggled and e.timer >= toggleAt then
            toggled = true
            require("src.core.game3.rse.init").call("secretBase", "toggleEntrance", "ToggleSecretBaseEntranceMetatile",
              nil, fx, fy)
          end
          return e.timer >= 40
        end,
        onDone = function() finish(useName, token) end,
      })
    end)
    return true
  end
end

-- pokeemerald/src/field_effect.c:3118
function FldeffMisc.npcFlyOut()
  local name = "FLDEFF_NPCFLY_OUT"
  local sheet = FE().loadSheet("bird")
  local P = Player()
  local token = {}
  FldeffMisc._active[name] = token
  playSe("SE_M_FLY")
  local SINE = require("src.core.game3.trig").SINE
  local rec = Rse().spawn("bird", {
    layer = "front", stopOnEnd = false, effectName = name,
    onStep = function(e)
      local d = e.d or 0
      local ox = P and P.px - 112 or 0
      local oy = P and P.py - 72 or 0
      e.x = ox + 120 + math.floor(140 * SINE[(d + 64) % 256 + 1] / 256)
      e.y = oy + math.floor(72 * SINE[d % 256 + 1] / 256)
      e.d = d + 4
      return d >= 0x80
    end,
    onDone = function() finish(name, token) end,
  })
  if not (sheet and rec) then finish(name, token) end
  return true
end

-- pokeemerald/src/fldeff_misc.c:788
function FldeffMisc.pcTurnOn(effectName)
  local name = effectName or "FLDEFF_PCTURN_ON"
  local token = begin(name)
  local x, y = facingCell()
  local Task = require("src.core.game3.task")
  local state = 0
  Task.spawn(function()
    if state == 4 or state == 12 then
      setMetatile(x, y, "METATILE_SecretBase_PC_On")
    elseif state == 8 or state == 16 then
      setMetatile(x, y, "METATILE_SecretBase_PC")
    elseif state == 20 then
      setMetatile(x, y, "METATILE_SecretBase_PC_On")
      finish(name, token)
      return true
    end
    state = state + 1
    return false
  end)
  return true
end

-- pokeemerald/src/fldeff_misc.c:835
function FldeffMisc.pcTurnOff(currentSecretBase)
  local x, y = facingCell()
  playSe("SE_PC_OFF")
  setMetatile(x, y, currentSecretBase and "METATILE_SecretBase_RegisterPC" or "METATILE_SecretBase_PC", true)
end

-- pokeemerald/src/fldeff_misc.c:1033
function FldeffMisc.sandPillar()
  local name = "FLDEFF_SAND_PILLAR"
  local token = begin(name)
  local P = Player()
  local x, y = facingCell()
  local lock = package.loaded["src.core.game3.field"]
  if lock then lock.locked = true end
  -- pokeemerald/src/fldeff_misc.c:1043
  local off = ({ down = { 8, 32 }, up = { 8, 0 }, left = { -8, 16 }, right = { 24, 16 } })[P.facing or "down"]
  local sx = P.px + off[1]
  local sy = P.py - 16 + off[2]
  local stage = 0
  Rse().spawn("sand_pillar", {
    layer = P.facing == "down" and "front" or "actor", x = sx, y = sy, stopOnEnd = false,
    effectName = name,
    onStep = function(e)
      if stage == 0 and e.a.ended then
        -- pokeemerald/src/fldeff_misc.c:1081
        playSe("SE_M_ROCK_THROW")
        local top = FldeffMisc.metatileAt(x, y - 1)
        if top == metatile("METATILE_SecretBase_SandOrnament_TopWall") then
          setMetatile(x, y - 1, "METATILE_SecretBase_Wall_TopMid", true)
        else
          setMetatile(x, y - 1, "METATILE_SecretBase_SandOrnament_BrokenTop")
        end
        setMetatile(x, y, "METATILE_SecretBase_Ground")
        stage, e.wait = 1, 0
        return false
      elseif stage == 1 then
        e.wait = e.wait + 1
        if e.wait >= 18 then
          setMetatile(x, y, "METATILE_SecretBase_SandOrnament_BrokenBase", true)
          return true
        end
      end
      return false
    end,
    onDone = function()
      if lock then lock.locked = false end
      finish(name, token)
    end,
  })
  return true
end

function FldeffMisc.metatileAt(x, y)
  local Collision = package.loaded["src.core.game3.collision"]
  local def = Collision and Collision._mapDef
  local layout = def and def.midLayout
  if not (layout and layout.midAt) then return nil end
  return layout:midAt(x, y)
end

-- pokeemerald/src/fldeff_misc.c:850
function FldeffMisc.popBalloon(metatileId, x, y)
  local Task = require("src.core.game3.task")
  local t, step = 0, 1
  local sounds = {
    [metatile("METATILE_SecretBase_RedBalloon")] = "SE_BALLOON_RED",
    [metatile("METATILE_SecretBase_BlueBalloon")] = "SE_BALLOON_BLUE",
    [metatile("METATILE_SecretBase_YellowBalloon")] = "SE_BALLOON_YELLOW",
    [metatile("METATILE_SecretBase_MudBall")] = "SE_MUD_BALL",
  }
  Task.spawn(function()
    if t == 6 then t = 0 else t = t + 1 end
    if t == 0 then
      if step == 2 and sounds[metatileId] then playSe(sounds[metatileId]) end
      local Field = package.loaded["src.core.game3.field"]
      if Field and Field.setMetatile then Field.setMetatile(x, y, metatileId + step, false) end
      if step == 3 then return true end
      step = step + 1
    end
    return false
  end)
end

-- pokeemerald/src/fldeff_misc.c:936
function FldeffMisc.shatterBreakableDoor(x, y)
  local function shatter()
    playSe("SE_BREAKABLE_DOOR")
    setMetatile(x, y, "METATILE_SecretBase_BreakableDoor_BottomOpen")
    setMetatile(x, y - 1, "METATILE_SecretBase_BreakableDoor_TopOpen")
  end
  local dir = Player().facing
  if dir == "down" then
    shatter()
  elseif dir == "up" then
    local n = 0
    require("src.core.game3.task").spawn(function()
      if n == 7 then
        shatter()
        return true
      end
      n = n + 1
      return false
    end)
  end
end

-- pokeemerald/src/fldeff_misc.c:954
local NOTES = {
  METATILE_SecretBase_NoteMat_C_Low = "SE_NOTE_C", METATILE_SecretBase_NoteMat_D = "SE_NOTE_D",
  METATILE_SecretBase_NoteMat_E = "SE_NOTE_E", METATILE_SecretBase_NoteMat_F = "SE_NOTE_F",
  METATILE_SecretBase_NoteMat_G = "SE_NOTE_G", METATILE_SecretBase_NoteMat_A = "SE_NOTE_A",
  METATILE_SecretBase_NoteMat_B = "SE_NOTE_B", METATILE_SecretBase_NoteMat_C_High = "SE_NOTE_C_HIGH",
}

function FldeffMisc.musicNoteMat(metatileId)
  local n = 0
  require("src.core.game3.task").spawn(function()
    if n == 7 then
      for label, se in pairs(NOTES) do
        if metatile(label) == metatileId then playSe(se) end
      end
      return true
    end
    n = n + 1
    return false
  end)
end

-- pokeemerald/src/fldeff_misc.c:1014
function FldeffMisc.glitterMatSparkle()
  local P = Player()
  Rse().spawnAt("sparkle", P.cellX, P.cellY, 8, 4, {
    layer = "front", stopOnEnd = false,
    onStep = function(e)
      if e.timer == 8 then playSe("SE_M_HEAL_BELL") end
      return e.timer >= 32
    end,
  })
end

-- pokeemerald/src/field_effect.c:1066
function FldeffMisc.hallOfFameRecord()
  local name = "FLDEFF_HALL_OF_FAME_RECORD"
  local token = {}
  FldeffMisc._active[name] = token
  local s = session()
  local n = 0
  for _, mon in pairs(s and s.party or {}) do if mon then n = n + 1 end end
  local P = Player()
  local ox, oy = P and P.px - 112 or 0, P and P.py - 72 or 0
  local balls = {}
  -- pokeemerald/src/field_effect.c:597
  local OFFS = { { 0, 0 }, { 6, 0 }, { 0, 4 }, { 6, 4 }, { 0, 8 }, { 6, 8 } }
  local Task = require("src.core.game3.task")
  local t = 0
  Task.spawn(function()
    t = t + 1
    local placed = math.min(n, math.floor((t - 1) / 25) + 1)
    for i = #balls + 1, placed do
      -- pokeemerald/src/field_effect.c:1156
      playSe("SE_BALL")
      local o = OFFS[i] or OFFS[1]
      balls[i] = Rse().spawn("pokeball_glow", { layer = "front", x = ox + 117 + o[1], y = oy + 52 + o[2],
        stopOnEnd = false, keep = function() return FldeffMisc._active[name] == token end })
    end
    if t == n * 25 + 32 then
      for _, b in ipairs(balls) do if b then b.a = Rse().anim(Rse().animCmds("pokeball_glow", 2)) end end
    end
    if t >= n * 25 + 150 then
      finish(name, token)
      return true
    end
    return false
  end)
  return true
end

-- pokeemerald/src/field_effect.c:1902
local function useDive()
  local name = "FLDEFF_USE_DIVE"
  local token = begin(name)
  showMon(function()
    require("src.core.game3.rse.init").call("dive", "start", "FldEff_UseDive", nil,
      FE().fieldEffectArgument(1, 0))
    finish(name, token)
  end)
  return true
end

-- pokeemerald/src/field_effect.c:2985
local function useSurf()
  local Field = package.loaded["src.core.game3.field"]
  if Field then Field.locked = true end
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.startSurfMusic then Audio.startSurfMusic() end
  showMon(function()
    local rt = package.loaded["src.core.game3.runtime"]
    Player().startSurfing(rt and rt._game, function()
      if Field then Field.locked = false end
    end)
  end, { noDuck = true })
  return true
end

-- pokeemerald/src/field_effect.c:1828
local function useWaterfall()
  showMon(function()
    local Field = package.loaded["src.core.game3.field"]
    if Field and Field.rideWaterfall then Field.rideWaterfall("up", 0) end
  end, { noPose = true })
  return true
end

-- pokeemerald/src/field_effect_helpers.c:1417
local function sparkle()
  local fe = FE()
  local name = "FLDEFF_SPARKLE"
  local token = {}
  FldeffMisc._active[name] = token
  Rse().startSparkle(fe.fieldEffectArgument(0, 0), fe.fieldEffectArgument(1, 0), function() finish(name, token) end)
  return true
end

FldeffMisc.HANDLERS = {
  -- pokeemerald/src/fldeff_cut.c:640
  FLDEFF_USE_CUT_ON_TREE = fieldMove("FLDEFF_USE_CUT_ON_TREE", "SE_M_CUT"),
  -- pokeemerald/src/fldeff_rocksmash.c:161
  FLDEFF_USE_ROCK_SMASH = fieldMove("FLDEFF_USE_ROCK_SMASH", "SE_M_ROCK_THROW"),
  -- pokeemerald/src/fldeff_strength.c:46
  FLDEFF_USE_STRENGTH = fieldMove("FLDEFF_USE_STRENGTH", nil),
  FLDEFF_USE_SURF = useSurf,
  FLDEFF_USE_WATERFALL = useWaterfall,
  FLDEFF_USE_DIVE = useDive,
  -- pokeemerald/src/fldeff_misc.c:602
  FLDEFF_USE_SECRET_POWER_CAVE = secretPower("FLDEFF_USE_SECRET_POWER_CAVE", "secret_power_cave", "SE_M_ROCK_THROW", 20),
  -- pokeemerald/src/fldeff_misc.c:652
  FLDEFF_USE_SECRET_POWER_TREE = secretPower("FLDEFF_USE_SECRET_POWER_TREE", "secret_power_tree", "SE_M_SCRATCH", 40),
  -- pokeemerald/src/fldeff_misc.c:726
  FLDEFF_USE_SECRET_POWER_SHRUB = secretPower("FLDEFF_USE_SECRET_POWER_SHRUB", "secret_power_shrub",
    "SE_M_POISON_POWDER", 20),
  FLDEFF_NPCFLY_OUT = function() return FldeffMisc.npcFlyOut() end,
  FLDEFF_PCTURN_ON = function() return FldeffMisc.pcTurnOn() end,
  FLDEFF_SECRET_BASE_PC_TURN_ON = function() return FldeffMisc.pcTurnOn("FLDEFF_SECRET_BASE_PC_TURN_ON") end,
  FLDEFF_SAND_PILLAR = function() return FldeffMisc.sandPillar() end,
  FLDEFF_HALL_OF_FAME_RECORD = function() return FldeffMisc.hallOfFameRecord() end,
  FLDEFF_SPARKLE = sparkle,
  -- pokeemerald/src/field_effect_helpers.c:892
  FLDEFF_WATER_SURFACING = function()
    local fe = FE()
    return Rse().startWaterSurfacing(fe.fieldEffectArgument(0, 0), fe.fieldEffectArgument(1, 0)) ~= nil
  end,
  -- pokeemerald/src/field_effect.c:3081
  FLDEFF_RAYQUAZA_SPOTLIGHT = function()
    return require("src.core.game3.special_scene_rse").startRayquazaSpotlight() ~= nil
  end,
}

function FldeffMisc.reset()
  FldeffMisc._active = {}
end

return FldeffMisc

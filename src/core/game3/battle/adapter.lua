-- Owned adapter for game3 battle (api-shaped, no host).

local State = require("src.core.game3.battle.state")
local Rules = require("src.core.game3.battle.rules")
local ModRuntime = require("src.mods.Runtime")

local Adapter = {}

local function norm_status(s)
  if not s or s == 0 then return nil end
  s = tostring(s):upper()
  if s == "BURN" then return "BRN" end
  if s == "POISON" then return "PSN" end
  if s == "TOXIC" then return "TOX" end
  if s == "SLEEP" or s == "SLP" then return "SLP" end
  if s == "PARALYSIS" or s == "PAR" then return "PAR" end
  if s == "FREEZE" or s == "FRZ" then return "FRZ" end
  if s == "0" or s == "" or s == "NONE" then return nil end
  return s
end
Adapter.normStatus = norm_status

-- pokefirered/include/constants/abilities.h:4
local ABILITY_BY_ID = {
  [1] = "STENCH", [2] = "DRIZZLE", [3] = "SPEED_BOOST", [4] = "BATTLE_ARMOR", [5] = "STURDY",
  [6] = "DAMP", [7] = "LIMBER", [8] = "SAND_VEIL", [9] = "STATIC", [10] = "VOLT_ABSORB",
  [11] = "WATER_ABSORB", [12] = "OBLIVIOUS", [13] = "CLOUD_NINE", [14] = "COMPOUND_EYES",
  [15] = "INSOMNIA", [16] = "COLOR_CHANGE", [17] = "IMMUNITY", [18] = "FLASH_FIRE",
  [19] = "SHIELD_DUST", [20] = "OWN_TEMPO", [21] = "SUCTION_CUPS", [22] = "INTIMIDATE",
  [23] = "SHADOW_TAG", [24] = "ROUGH_SKIN", [25] = "WONDER_GUARD", [26] = "LEVITATE",
  [27] = "EFFECT_SPORE", [28] = "SYNCHRONIZE", [29] = "CLEAR_BODY", [30] = "NATURAL_CURE",
  [31] = "LIGHTNING_ROD", [32] = "SERENE_GRACE", [33] = "SWIFT_SWIM", [34] = "CHLOROPHYLL",
  [35] = "ILLUMINATE", [36] = "TRACE", [37] = "HUGE_POWER", [38] = "POISON_POINT",
  [39] = "INNER_FOCUS", [40] = "MAGMA_ARMOR", [41] = "WATER_VEIL", [42] = "MAGNET_PULL",
  [43] = "SOUNDPROOF", [44] = "RAIN_DISH", [45] = "SAND_STREAM", [46] = "PRESSURE",
  [47] = "THICK_FAT", [48] = "EARLY_BIRD", [49] = "FLAME_BODY", [50] = "RUN_AWAY",
  [51] = "KEEN_EYE", [52] = "HYPER_CUTTER", [53] = "PICKUP", [54] = "TRUANT", [55] = "HUSTLE",
  [56] = "CUTE_CHARM", [57] = "PLUS", [58] = "MINUS", [59] = "FORECAST", [60] = "STICKY_HOLD",
  [61] = "SHED_SKIN", [62] = "GUTS", [63] = "MARVEL_SCALE", [64] = "LIQUID_OOZE",
  [65] = "OVERGROW", [66] = "BLAZE", [67] = "TORRENT", [68] = "SWARM", [69] = "ROCK_HEAD",
  [70] = "DROUGHT", [71] = "ARENA_TRAP", [72] = "VITAL_SPIRIT", [73] = "WHITE_SMOKE",
  [74] = "PURE_POWER", [75] = "SHELL_ARMOR", [76] = "CACOPHONY", [77] = "AIR_LOCK",
}
Adapter.ABILITY_BY_ID = ABILITY_BY_ID

local function side_of(battler)
  if type(battler) == "table" then return battler.side end
  if type(battler) == "string" then return battler end
  if type(battler) == "number" then return State.sideOf(battler) end
  return nil
end

local function id_of(battler)
  if battler == nil then return nil end
  return State.idOf(battler)
end
Adapter.idOf = id_of

-- src/battle_message.c:1523
function Adapter.fill(st, extra)
  local f = {}
  if st then
    f.trainer = not st.wild
    f.link = st.link or nil
    f.double = st.double or nil
    f.unionRoom = st.unionRoom or nil
    f.linkOpponent = (st.link and not st.unionRoom) or nil
    f.ghost = st.ghostBattle or nil
    f.ghostUnveiled = st.ghostUnveiled or nil
    f.legendary = st.legendary or nil
    f.oldMan = st.oldManTutorial or nil
    f.playerName = st.playerName
    f.linkPlayerName = st.playerName
    f.linkOpponent1Name = st.peerName
    f.trainer1Class = (st.trainerClassName ~= nil and st.trainerClassName ~= "") and st.trainerClassName
      or st.trainerClass
    f.trainer1Name = st.trainerName
    if st.unionRoom then
      -- src/battle_message.c:2039
      f.trainer1Class = require("src.core.game3.link.battle").unionRoomTrainerClass()
      -- src/battle_message.c:2058
      f.trainer1Name = st.peerName
    end
    if st.multi and st.linkNames then
      -- pokefirered/src/battle_message.c:1910
      local own = tonumber(st.linkOwn) or 0
      local names = st.linkNames
      local seat = st.linkSeatOf and st.linkSeatOf[own]
      local opp = seat and st.linkLocalOf and st.linkLocalOf[State.OPPOSITE(seat)] or State.OPPOSITE(own)
      f.multi = true
      f.linkPlayerName = names[own] or st.playerName
      f.linkPartnerName = names[(own + 2) % 4]
      f.linkOpponent1Name = names[opp]
      f.linkOpponent2Name = names[(opp + 2) % 4]
      f.linkPlayerMon1 = State.battler(st, own)
      f.linkPlayerMon2 = State.battler(st, (own + 2) % 4)
      f.linkOpponentMon1 = State.battler(st, opp)
      f.linkOpponentMon2 = State.battler(st, (opp + 2) % 4)
    end
  end
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

function Adapter.new(battleState, sayFn)
  local a = {
    _st = battleState,
    _say = sayFn or function() end,
    _events = {},
  }

  function a:pushEvent(ev)
    self._events[#self._events + 1] = ev
    return ev
  end
  function a:events() return self._events end
  function a:eventMark() return #self._events end
  function a:eventsSince(mark)
    local out = {}
    for i = (mark or 0) + 1, #self._events do out[#out + 1] = self._events[i] end
    return out
  end

  function a:playAnim(kind, name, attacker, target, arg)
    return self:pushEvent({
      kind = "anim",
      anim = kind,
      name = name,
      attacker = side_of(attacker),
      target = side_of(target),
      attackerId = id_of(attacker),
      targetId = id_of(target),
      arg = arg,
    })
  end

  function a:statusAnim(battler, status)
    local names = {
      PSN = "POISON", TOX = "POISON", BRN = "BURN", SLP = "SLEEP",
      PAR = "PARALYSIS", FRZ = "FREEZE",
    }
    local n = names[norm_status(status or self:status(battler)) or ""]
    if n then self:playAnim("status", n, battler, battler) end
  end

  function a:mon(battler) return battler and battler.mon end
  function a:hp(battler) return battler and battler.mon and tonumber(battler.mon.hp) or 0 end
  function a:maxHp(battler) return battler and battler.mon and tonumber(battler.mon.maxHp) or 0 end
  function a:status(battler)
    return battler and norm_status(battler.status or (battler.mon and battler.mon.status))
  end
  function a:hasStatus(battler, ...)
    local cur = self:status(battler)
    if not cur then return false end
    for i = 1, select("#", ...) do
      if cur == norm_status(select(i, ...)) then return true end
    end
    return false
  end

  function a:hasType(battler, typeId)
    if not battler then return false end
    return battler.type1 == typeId or battler.type2 == typeId
  end

  function a:uproarActive()
    for _, b in ipairs(self:activeBattlers()) do
      if (b.expUproarTurns or 0) > 0 and not self:isFainted(b) then return b end
    end
    return nil
  end

  -- pokefirered/src/battle_script_commands.c:2150
  function a:canApplyStatus(battler, status, source, opts)
    opts = opts or {}
    if not battler then return false, "none" end
    status = norm_status(status)
    if self:status(battler) then return false, "status" end
    local side = self:ownSide(battler)
    if not opts.ignoreSafeguard and source ~= battler and side and (side.expSafeguardTurns or 0) > 0 then
      return false, "safeguard"
    end
    local ab = self:abilityOf(battler)
    if status == "PSN" or status == "TOX" then
      if self:hasType(battler, 3) or self:hasType(battler, 8) then return false, "type" end
      if ab == "IMMUNITY" then return false, "ability" end
    elseif status == "BRN" then
      if self:hasType(battler, 10) then return false, "type" end
      if ab == "WATER_VEIL" then return false, "ability" end
    elseif status == "FRZ" then
      if self:hasType(battler, 15) then return false, "type" end
      if Rules.weather.effective(self._st, self) == "SUN" then return false, "sun" end
      if ab == "MAGMA_ARMOR" then return false, "ability" end
    elseif status == "PAR" then
      if ab == "LIMBER" then return false, "ability" end
    elseif status == "SLP" then
      if ab ~= "SOUNDPROOF" and self:uproarActive() then return false, "uproar" end
      if ab == "INSOMNIA" or ab == "VITAL_SPIRIT" then return false, "ability" end
    end
    return true
  end

  function a:rollSleepTurns()
    local ok, v = pcall(self:rng(), 0, 3)
    if not (ok and type(v) == "number") then
      v = require("src.core.game3.battle.link_guard").fallback("adapter.sleep", 0, 3)
    end
    return (math.floor(v) % 4) + 2
  end

  function a:applyStatus(battler, status, source, opts)
    opts = opts or {}
    if not battler then return false end
    status = norm_status(status)
    if not opts.force then
      local ok = self:canApplyStatus(battler, status, source, opts)
      if not ok then return false end
    elseif self:status(battler) then
      return false
    end
    battler.status = status
    if battler.mon then battler.mon.status = status end
    if status == "TOX" then battler.toxicCounter = 0 end
    if status == "SLP" then
      -- pokefirered/src/battle_script_commands.c:2356
      battler.sleepTurns = tonumber(opts.turns) or self:rollSleepTurns()
      local Engine = package.loaded["src.core.game3.battle.engine"]
      if Engine and Engine.cancelMultiTurnMoves then Engine.cancelMultiTurnMoves(battler) end
    elseif status == "FRZ" then
      local Engine = package.loaded["src.core.game3.battle.engine"]
      if Engine and Engine.cancelMultiTurnMoves then Engine.cancelMultiTurnMoves(battler) end
    end
    -- pokefirered/src/battle_script_commands.c:2110
    if ModRuntime.wants("battle.status_inflicted") then
      ModRuntime.emit("battle.status_inflicted", {
        battle = self._st, target = battler, status = status, source = source,
        side = battler.side, battlerId = id_of(battler),
        sourceId = type(source) == "table" and id_of(source) or nil,
      })
    end
    return true
  end
  function a:clearStatus(battler)
    if not battler then return end
    battler.status = nil
    battler.toxicCounter = nil
    battler.sleepTurns = nil
    if battler.mon then battler.mon.status = nil end
  end
  function a:stages(battler) return battler and battler.stages end
  function a:changeStages(battler, changes)
    local result = {}
    if not battler or not battler.stages or type(changes) ~= "table" then return result end
    for k, d in pairs(changes) do
      local cur = battler.stages[k] or 0
      local nxt = cur + (tonumber(d) or 0)
      if nxt < -6 then nxt = -6 elseif nxt > 6 then nxt = 6 end
      battler.stages[k] = nxt
      result[k] = { delta = nxt - cur, limited = (nxt - cur) == 0 }
    end
    return result
  end

  function a:recordHp(battler, from, to, kind)
    if not battler or from == to then return end
    return self:pushEvent({
      kind = kind or "hp",
      side = battler.side,
      battler = id_of(battler),
      from = from,
      to = to,
      maxHp = self:maxHp(battler),
    })
  end

  function a:applyHpLoss(battler, amount, opts)
    if not battler or not battler.mon then return 0 end
    local before = self:hp(battler)
    local lost = State.applyHpLoss(battler, amount)
    self:recordHp(battler, before, self:hp(battler), opts and opts.hit and "hit" or "hp")
    return lost
  end
  function a:heal(battler, amount)
    if not battler or not battler.mon then return 0 end
    local before = self:hp(battler)
    local gained = State.heal(battler, amount)
    self:recordHp(battler, before, self:hp(battler), "hp")
    return gained
  end
  function a:setHp(battler, value)
    if not battler or not battler.mon then return end
    local before = self:hp(battler)
    local maxHp = self:maxHp(battler)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then value = 0 end
    if maxHp > 0 and value > maxHp then value = maxHp end
    battler.mon.hp = value
    if value <= 0 then battler.fainted = true else battler.fainted = false end
    self:recordHp(battler, before, value, "hp")
  end
  function a:isFainted(battler) return State.isFainted(battler) end
  function a:emitFaint(battler)
    if battler then
      battler.fainted = true
      if battler.mon then battler.mon.hp = 0 end
      -- pokefirered/src/battle_script_commands.c:2878
      if battler.side == "player" and battler.mon and not battler._faintFriendship then
        battler._faintFriendship = true
        local Pokemon = require("src.core.game3.pokemon")
        local foeLevel = 0
        for _, foe in ipairs(State.foes(self._st, battler)) do
          local lv = tonumber(foe.mon and foe.mon.level) or 0
          if lv > foeLevel then foeLevel = lv end
        end
        Pokemon.adjustFriendshipOnBattleFaint(battler.mon, tonumber(battler.mon.level),
          foeLevel, { mapSec = Pokemon.currentMapSec(self._st.session) })
      end
      -- pokefirered/src/battle_script_commands.c:2831
      if ModRuntime.wants("battle.fainted") and battler._modFainted ~= (battler.mon or true) then
        battler._modFainted = battler.mon or true
        ModRuntime.emit("battle.fainted", {
          battle = self._st, battler = battler, side = self:ownSide(battler),
          sideName = battler.side, battlerId = id_of(battler),
        })
      end
    end
  end
  function a:displayName(battler) return State.displayName(battler) end
  function a:say(text, id)
    text = tostring(text or "")
    self:pushEvent({ kind = "msg", text = text, id = id })
    self._say(text)
  end
  function a:sayText(id, fill)
    local BattleText = require("src.core.game3.battle.battle_text")
    fill = Adapter.fill(self._st, fill)
    local text = BattleText.get(id, fill)
    self:pushEvent({ kind = "msg", text = text, id = (BattleText.key(id, fill)) })
    self._say(text)
    return text
  end
  -- src/battle_message.c:336
  function a:sayFail() self:sayText("STRINGID_BUTITFAILED") end
  function a:rng()
    return self._st.rng or require("src.core.game3.battle.link_guard").source("adapter.rng", math.random)
  end
  function a:roll(lo, hi)
    local ok, v = pcall(self:rng(), lo, hi)
    if ok and type(v) == "number" then return v end
    return require("src.core.game3.battle.link_guard").fallback("adapter.roll", lo, hi)
  end
  function a:activeBattlers() return State.present(self._st) end
  function a:foeOf(battler)
    if not battler then return nil end
    local st = self._st
    if not st.double then
      if battler.side == "player" then return st.enemy end
      return st.player
    end
    local opp = State.OPPOSITE(State.idOf(battler))
    if State.isPresent(st, opp) then return State.battler(st, opp) end
    local alt = State.PARTNER(opp)
    if State.isPresent(st, alt) then return State.battler(st, alt) end
    return State.battler(st, opp)
  end
  function a:foesOf(battler) return State.foes(self._st, battler) end
  function a:partnerOf(battler) return State.partner(self._st, battler) end
  function a:ownSide(battler)
    if not battler then return nil end
    if battler.side == "player" then return self._st.playerSide end
    return self._st.enemySide
  end
  function a:foeSide(battler)
    if not battler then return nil end
    if battler.side == "player" then return self._st.enemySide end
    return self._st.playerSide
  end
  function a:findHazard(side, id)
    if not side or not side.hazards then return nil end
    for _, h in ipairs(side.hazards) do
      if h.id == id then return h end
    end
    return nil
  end
  function a:isBattleDecided()
    return self._st.over == true
  end
  function a:hasSubstitute(battler)
    return battler and (battler.substituteHP or 0) > 0
  end
  function a:abilityOf(battler)
    if not battler then return nil end
    if battler.expTracedAbility then return battler.expTracedAbility end
    if battler.expAbilitySuppressed then return nil end
    local id = battler.ability
    if not id and battler.mon then
      id = battler.mon.ability or battler.mon.abilityId
    end
    if type(id) == "string" and id ~= "" then
      return (id:upper():gsub("%s+", "_"))
    end
    id = tonumber(id)
    if id and id > 0 then
      if ABILITY_BY_ID[id] then return ABILITY_BY_ID[id] end
      local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
      if ok and Pokemon and Pokemon.abilityName then
        local n = Pokemon.abilityName(id)
        if n and n ~= "" and not n:match("^ABILITY") then
          return (tostring(n):upper():gsub("%s+", "_"))
        end
      end
    end
    return nil
  end
  function a:lastMoveOf(battler)
    return battler and (battler.lastMoveId or battler.lastMove)
  end
  function a:partyMons(battler)
    if not battler then return {} end
    if battler.side == "player" then return self._st.playerParty or {} end
    return self._st.foeParty or {}
  end
  -- pokefirered/src/battle_script_commands.c:2413
  function a:applyConfusion(battler, turns, _source)
    if not battler then return false end
    if (battler.confusionTurns or 0) > 0 then return false end
    local t = tonumber(turns)
    if not t then t = self:roll(0, 3) % 4 + 2 end
    battler.confusionTurns = t
    return true
  end
  function a:useMove(user, moveId, target, opts)
    local Engine = require("src.core.game3.battle.engine")
    return Engine.resolveMove(user, target, moveId, opts and opts.slot, self, self._st, {})
  end

  function a:setWeather(kind, turns)
    self._st.weather = kind
    self._st.weatherTurns = turns or 5
  end

  function a:tickWeather()
    local Residuals = require("src.core.game3.battle.residual_handlers")
    if Residuals.tickWeather then Residuals.tickWeather(self) end
  end

  return a
end

return Adapter

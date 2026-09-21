local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_vs_seeker"

-- pokefirered/include/constants/items.h:434
local ITEM_VS_SEEKER = 362
local LASS_MEGAN, LASS_MEGAN_2 = 130, 648
local TWINS_ELI_ANNE, TWINS_ELI_ANNE_2 = 484, 533
local IVYSAUR, WARTORTLE = 2, 8
local CLEFAIRY, JIGGLYPUFF = 35, 39
local FLAG_GOT_VS_SEEKER, FLAG_CELADON, FLAG_FUCHSIA = 0x292, 0x896, 0x897
local FLAG_CHARGING = 0x801
local EMOTE_EXCL, EMOTE_DOUBLE = 0, 6

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_vs_seeker")
    love.event.quit(0)
  else
    print("FAIL game3_vs_seeker failures=" .. failures)
    love.event.quit(1)
  end
end

local function raise_hand(mt)
  mt = tonumber(mt) or 0
  return mt >= 0x4D and mt <= 0x4F
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local FieldEffects = require("src.core.game3.field_effects")
  local ItemUse = require("src.core.game3.item_use")
  local StepEvents = require("src.core.game3.step_events")
  local Rng = require("src.core.game3.rng")
  local VsSeeker = require("src.core.game3.vs_seeker")
  local Battle = require("src.core.game3.battle")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  session.party = {}
  Party.giveMon(session, IVYSAUR, 45)
  Party.giveMon(session, WARTORTLE, 45)
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_VS_SEEKER, 1)

  local function setFlag(id, on) Flags.setFlag(Space.store, nil, id, on ~= false) end
  local function getFlag(id) return Flags.getFlag(Space.store, nil, id) end
  setFlag(FLAG_GOT_VS_SEEKER)
  setFlag(FLAG_CELADON)
  setFlag(FLAG_FUCHSIA)

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("Route8")) or "FR_ROUTE_8"
  Map.load(nil, game, mapId, { x = 40, y = 6, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 40, 6, "up"
  U.wait(90)
  session = Runtime.getSession()

  setFlag(Flags.trainerFlagId(LASS_MEGAN))
  setFlag(Flags.trainerFlagId(TWINS_ELI_ANNE))

  local function find_trainers(tid)
    local found = {}
    for _, lid in ipairs(Objects.listActive()) do
      local eo = Objects.find(lid)
      if eo and TrainerSight.getTrainerId(eo) == tid then found[#found + 1] = eo end
    end
    table.sort(found, function(a, b) return (a.cellX or 0) < (b.cellX or 0) end)
    return found[1], found[2]
  end

  local function stand_facing(tid)
    local eo = find_trainers(tid)
    if not eo then return nil end
    local tx, ty = eo.cellX, eo.cellY
    local cands = { { 1, 0, "left" }, { 0, 1, "up" }, { -1, 0, "right" }, { 0, -1, "down" } }
    for _, c in ipairs(cands) do
      local x, y = tx + c[1], ty + c[2]
      if Collision.canEnter(game, x, y, {}) and not Objects.at(x, y) then
        Map.load(nil, game, mapId, { x = x, y = y, facing = c[3] })
        game.session.x, game.session.y, game.session.facing = x, y, c[3]
        U.wait(45)
        return find_trainers(tid)
      end
    end
    return nil
  end

  local function accept_seed()
    for seed = 1, 65535 do
      Rng.SeedRng(seed)
      if Rng.Random() % 100 >= 30 then return seed end
    end
    return 1
  end
  local forcedSeed = nil
  local origCompute = VsSeeker.computeResponse
  VsSeeker.computeResponse = function(...)
    if forcedSeed then Rng.SeedRng(forcedSeed) end
    return origCompute(...)
  end

  local function use_seeker(label, shotName)
    local ok, kind, text = ItemUse.useField(session, session.bag, ITEM_VS_SEEKER)
    result(ok and kind == "vs_seeker", label .. ": VS SEEKER accepted on Route 8 (" .. tostring(text) .. ")")
    local seen = {}
    local done, response = false, nil
    forcedSeed = accept_seed()
    VsSeeker.use(session, game, function(_, resp)
      done = true
      response = resp
    end)
    local shot = false
    for i = 1, 600 do
      for _, a in ipairs(FieldEffects._anims or {}) do
        if a.kind == "emote" and a.targetObj and a.targetObj.localId then
          seen[a.targetObj.localId] = a.baseFrame
        end
      end
      if not shot and i == VsSeeker.EFFECT_FRAMES + 20 and shotName then
        shot = true
        result(U.shot(game, DIR .. "/" .. shotName), "screenshot " .. shotName)
      end
      if done then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(1)
    end
    forcedSeed = nil
    result(done, label .. ": VS SEEKER sequence finished")
    return response, seen
  end

  local function diag(label)
    local Hud = package.loaded["src.ui.game3.hud"]
    local Stack = package.loaded["src.ui.game3.stack"]
    local Choice = package.loaded["src.ui.game3.choice"]
    local Field = package.loaded["src.core.game3.field"]
    local Fade = package.loaded["src.ui.game3.fade"]
    local BT = package.loaded["src.core.game3.battle_transition"]
    local ctx = Space.vm and Space.vm.ctx or {}
    local layers = {}
    for _, l in ipairs(Stack and Stack._layers or {}) do layers[#layers + 1] = tostring(l.id) end
    print(string.format("DIAG %s phase=%s rt=%s vm=%s/%s pc=%s:%s msg=%s stay=%s waiting=%s page=%s/%s waitBtn=%s stack=[%s] choice=%s locked=%s running=%s fade=%s bt=%s battle=%s steps=%s",
      label, tostring(game.phase), tostring(Runtime.isActive and Runtime.isActive()),
      tostring(ctx.status), tostring(ctx.mode), tostring(ctx.pc and ctx.pc.listKey), tostring(ctx.pc and ctx.pc.index),
      tostring(Message.isOpen and Message.isOpen()), tostring(Message._stay), tostring(Message._waiting),
      tostring(Message._page), tostring(Message._pages and #Message._pages),
      tostring(Hud and Hud._waitButton ~= nil), table.concat(layers, ","), tostring(Choice and Choice.active),
      tostring(Field and Field.locked), tostring(Field and Field.running),
      tostring(Fade and Fade.isActive and Fade.isActive()), tostring(BT and BT.isActive and BT.isActive()),
      tostring(Battle.isActive()), tostring(StepEvents.busy())))
  end

  local function wants_a()
    local Hud = package.loaded["src.ui.game3.hud"]
    return (Message.isOpen and Message.isOpen()) or (Hud and Hud._waitButton ~= nil)
  end

  local function talk_until_battle()
    local sawMsg = false
    local openFor = 0
    U.tap(game, "a")
    for _ = 1, 600 do
      if Battle.isActive() then break end
      if wants_a() then
        sawMsg = true
        openFor = openFor + 1
        if openFor == 100 then diag("waiting on A for 100 taps") end
        U.tap(game, "a")
      else
        openFor = 0
        if sawMsg and not (Space.vm and Space.vm:isRunning()) then break end
      end
      U.wait(3)
    end
    return sawMsg
  end

  local function settle()
    for _ = 1, 600 do
      local busy = (Space.vm and Space.vm:isRunning()) or wants_a()
        or Battle.isActive() or StepEvents.busy()
      if not busy then break end
      if wants_a() then U.tap(game, "a") end
      U.wait(3)
    end
    U.wait(30)
  end

  local s = VsSeeker.state(session)

  local megan = stand_facing(LASS_MEGAN)
  if not result(megan ~= nil, "found LASS MEGAN and stood next to her") then return finish() end
  local meganLid = megan.localId
  s.steps = 99
  local _, uncharged = VsSeeker.use(session, game)
  result(uncharged == VsSeeker.NOT_CHARGED and s.steps == 99, "99 steps: not charged, no drain")
  settle()
  s.steps = 100
  local response, seen = use_seeker("single", "00_response.png")
  megan = Objects.find(meganLid)
  result(response == VsSeeker.RESPONSE_FOUND_REMATCHES, "response is FOUND_REMATCHES")
  result(VsSeeker.getRematch(s, meganLid) == 2, "Megan stamped with rematch column 2 (got " .. VsSeeker.getRematch(s, meganLid) .. ")")
  result(getFlag(FLAG_CHARGING), "FLAG_SYS_VS_SEEKER_CHARGING set")
  result(s.steps == 0 and s.charging == 0, "battery drained, charging counter reset")
  result(megan and raise_hand(megan.movementType), "Megan raised her hand (movementType=" .. tostring(megan and megan.movementType) .. ")")
  result(seen[meganLid] == EMOTE_DOUBLE, "Megan showed !!")
  local sawExcl = false
  for lid, base in pairs(seen) do
    if lid ~= meganLid and base == EMOTE_EXCL then sawExcl = true end
  end
  result(sawExcl, "an unfought trainer in range showed !")
  settle()

  talk_until_battle()
  if not result(Battle.isActive(), "talking to Megan started the rematch") then return finish() end
  local st = Battle._st
  result(st and st.double ~= true, "Megan rematch is a single battle")
  result(st and st.trainerId == LASS_MEGAN_2, "tier check: CELADON set picks LASS_MEGAN_2 (got " .. tostring(st and st.trainerId) .. ")")
  U.wait(30)
  Battle.abort("win")
  local sawPost = false
  for _ = 1, 200 do
    if Message.isOpen and Message.isOpen() and not Battle.isActive() then sawPost = true end
    if not (Space.vm and Space.vm:isRunning()) and not Battle.isActive() then break end
    U.wait(3)
  end
  U.wait(60)
  result(not sawPost and not (Message.isOpen and Message.isOpen()), "rematch script ends without the post-battle msgbox")
  result(getFlag(Flags.trainerFlagId(LASS_MEGAN_2)), "FLAG for LASS_MEGAN_2 set after the win")
  result(VsSeeker.getRematch(s, meganLid) == 0, "Megan rematch state cleared")
  megan = Objects.find(meganLid)
  result(megan and not raise_hand(megan.movementType), "Megan stopped raising her hand")
  result(U.shot(game, DIR .. "/01_single_after.png"), "screenshot 01_single_after.png")
  settle()

  talk_until_battle()
  result(not Battle.isActive(), "talking again without a VS SEEKER response gives no battle")
  settle()

  local eli, anne = find_trainers(TWINS_ELI_ANNE)
  if not result(eli ~= nil and anne ~= nil, "found both twins") then return finish() end
  local eliLid, anneLid = eli.localId, anne.localId
  local ex, ey = eli.cellX, eli.cellY + 1
  Map.load(nil, game, mapId, { x = ex, y = ey, facing = "up" })
  game.session.x, game.session.y, game.session.facing = ex, ey, "up"
  U.wait(45)
  s.steps = 100
  response, seen = use_seeker("double", "02_double_response.png")
  result(response == VsSeeker.RESPONSE_FOUND_REMATCHES, "twins response is FOUND_REMATCHES")
  result(VsSeeker.getRematch(s, eliLid) == 3 and VsSeeker.getRematch(s, anneLid) == 3, "both twins stamped with column 3")
  result(seen[eliLid] == EMOTE_DOUBLE and seen[anneLid] == EMOTE_DOUBLE, "both twins showed !!")
  settle()

  talk_until_battle()
  if not result(Battle.isActive(), "talking to Eli started the double rematch") then return finish() end
  st = Battle._st
  result(st and st.double == true, "twins rematch is a double battle")
  result(st and st.battlersCount == 4, "battlersCount is 4")
  result(st and st.trainerId == TWINS_ELI_ANNE_2, "foe is TWINS_ELI_ANNE_2 (got " .. tostring(st and st.trainerId) .. ")")
  local fp = st and st.foeParty or {}
  result(fp[1] and fp[2] and fp[1].species == CLEFAIRY and fp[2].species == JIGGLYPUFF
    and fp[1].level == 28 and fp[2].level == 28, "foe party is Clefairy L28 + Jigglypuff L28")
  U.wait(30)
  Battle.abort("win")
  for _ = 1, 200 do
    if not (Space.vm and Space.vm:isRunning()) and not Battle.isActive() then break end
    U.wait(3)
  end
  U.wait(60)
  result(getFlag(Flags.trainerFlagId(TWINS_ELI_ANNE_2)), "FLAG for TWINS_ELI_ANNE_2 set after the win")
  result(VsSeeker.getRematch(s, eliLid) == 0 and VsSeeker.getRematch(s, anneLid) == 0, "both twin rematch states cleared")
  anne = Objects.find(anneLid)
  eli = Objects.find(eliLid)
  result(anne and anne.movementType == 8, "Anne set to FACE_DOWN (got " .. tostring(anne and anne.movementType) .. ")")
  result(eli and not raise_hand(eli.movementType), "Eli stopped raising her hand")
  result(U.shot(game, DIR .. "/03_double_after.png"), "screenshot 03_double_after.png")
  settle()

  megan = stand_facing(LASS_MEGAN)
  if not result(megan ~= nil, "back next to Megan") then return finish() end
  s.steps = 100
  response = use_seeker("charge", nil)
  megan = Objects.find(meganLid)
  result(VsSeeker.getRematch(s, meganLid) == 4 and megan and raise_hand(megan.movementType),
    "Megan wants the next tier (column 4) and raises her hand")
  settle()
  s.charging = 99
  StepEvents.onStepTaken(session, game)
  for _ = 1, 120 do
    if not StepEvents.busy() then break end
    U.wait(1)
  end
  megan = Objects.find(meganLid)
  result(not getFlag(FLAG_CHARGING) and s.charging == 0, "100 charging steps clear the charging flag")
  result(VsSeeker.getRematch(s, meganLid) == 0, "charging done clears the rematch states")
  result(megan and megan.movementType >= 7 and megan.movementType <= 10,
    "raise-hand replaced by a random face type (got " .. tostring(megan and megan.movementType) .. ")")
  result(U.shot(game, DIR .. "/04_charge_reset.png"), "screenshot 04_charge_reset.png")

  VsSeeker.computeResponse = origCompute
  finish()
end

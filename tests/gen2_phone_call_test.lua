-- The random incoming call's overworld wiring, and the ring chrome around
-- every call that lands: CheckTimeEvents' `farcall CheckPhoneCall` arm,
-- Script_ReceivePhoneCall as PhoneRing.script's rows, GetCallerLocation's two
-- chatter specials (RandomPhoneMon / RandomPhoneWildMon), Mom's shopping call
-- riding the same chrome, and the Pokegear's outgoing callee script.
--
-- tests/gen2_phone_test.lua owns the MODEL (the gate, the timer, the contact
-- list); this suite owns the CALL SITES, driven through the real World
-- methods and a real Vm over the extracted cache.  Cache blocks SKIP without
-- one, the same bargain that suite strikes.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 phone call")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local CallAsm = require("src.script.gen2.CallAsm")
local Events = require("src.world.gen2.Events")
local Phone = require("src.core.gen2.Phone")
local PhoneRing = require("src.core.gen2.PhoneRing")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

local function newSave()
  return Save.normalize({})
end

-- The ring's `waitsfx` rows and the Phone_Wait20Frames `pause` between its
-- two passes park the coroutine on Vm:update, the way DelayFrames parks the
-- cart's, so a call only runs to completion when something drives the frames
-- the overworld would drive.
local function pump(vm, frames)
  for _ = 1, frames or 600 do
    if not vm:running() then return end
    vm:update()
  end
end

-- ------------------------------------------------- Script_ReceivePhoneCall
--
-- engine/phone/phone.asm: reanchormap, RingTwice_StartCall, the caller's own
-- script, waitbutton, HangUp, closetext, InitCallReceiveDelay, end.  The row
-- list has to keep that order or the countdown restarts before the call has
-- even been answered.
--
-- RingTwice_StartCall (:458-469) is `call .Ring` falling through into .Ring,
-- and each pass opens on Phone_StartRinging's `call WaitSFX` (:564-567), so
-- the ring is two waitsfx/callasm pairs spaced by the three
-- Phone_Wait20Frames between the passes (:576-580).  This assertion used to
-- pin one ungated ring, which is the shape that let the $6a SFX_CALL be
-- dropped by the PlaySFX priority gate; it now pins the cart's.
do
  local PHONE = require("tests.fixtures.gen2_phone_events")
  PHONE.install()
  local call = Phone.loadCallerScript(15, "incoming", "caller")
  local rows = PhoneRing.script(call, "JOEY", "YOUNGSTER")
  local ops = {}
  for _, row in ipairs(rows) do ops[#ops + 1] = row.op end
  eq(table.concat(ops, " "),
    "reanchormap waitsfx callasm pause waitsfx callasm rawtext farscall "
    .. "waitbutton hangup closetext callasm end",
    "Script_ReceivePhoneCall's rows in the cart's order")
  eq(rows[3].label, "RingTwice_StartCall", "the ring rings first")
  eq(rows[6].label, "RingTwice_StartCall", "and rings a second time")
  eq(rows[4].frames, 60, "three Phone_Wait20Frames apart")
  eq(rows[12].label, "InitCallReceiveDelay", "and the countdown restarts last")
  eq(rows[8].script, PHONE.events.phoneScripts.JoeyPhoneCallerScript.script,
    "around the caller's own bank $41 script")
  check(rows[7].text:find("RING!", 1, true) ~= nil, "the ring page rings")
  check(rows[7].text:find("JOEY: YOUNGSTER", 1, true) ~= nil,
    "and carries the caller-ID line")
  eq(PhoneRing.callerId("MOM"), "MOM:",
    "a non-trainer caller is the name and the colon alone")

  -- Script_SpecialElmCall's siblings `pause 30` before the ring; the
  -- descriptor carries that as `delay` and the wrapper honours it.
  local special = { delay = 30, scriptKey = "41:41e1" }
  local wrapped = PhoneRing.script(special, "PROF.ELM")
  eq(wrapped[1].op, "pause", "a special call pauses before ringing")
  eq(wrapped[1].frames, 30, "for the cart's thirty frames")
end

-- ------------------------------------------------- the two chrome callasms
do
  check(CallAsm.STUBS.RingTwice_StartCall == nil,
    "RingTwice_StartCall is ported, not stubbed")
  check(CallAsm.STUBS.InitCallReceiveDelay == nil,
    "and so is InitCallReceiveDelay")
  eq(CallAsm.nameFor(nil, 0x24, 0x4277), "RingTwice_StartCall",
    "the cart address for the ring still dispatches")
  eq(CallAsm.nameFor(nil, 0x04, 0x5800), "InitCallReceiveDelay",
    "and the cart address for the countdown restart")

  local rang = {}
  CallAsm.run({ playSfxNamed = function(_, name) rang[#rang + 1] = name end },
    "RingTwice_StartCall")
  eq(rang[1], "Sfx_Call", "the ring is SFX_CALL")

  -- InitCallReceiveDelay: zero the cycle counter, park the countdown back on
  -- twenty minutes.  Wound on first so the reset is visible.
  local save = newSave()
  Phone.initReceiveDelay(save, { clock = { day = 0, hour = 9, minute = 0 } })
  Phone.checkReceiveCallTimer(save,
    { clock = { day = 0, hour = 9, minute = 20 } })
  eq(save.phone.timeCycles, 1, "the timer was wound before the reset")
  local ctx = {
    game = { save = save },
    stepContext = function()
      return { phone = { clock = { day = 0, hour = 9, minute = 20 } } }
    end,
  }
  CallAsm.run(ctx, "InitCallReceiveDelay")
  eq(save.phone.timeCycles, 0, "InitCallReceiveDelay zeroes the cycles")
  eq(save.phone.delayMins, 20, "and restarts the countdown at twenty")
end

-- ------------------------------------------------- CheckTimeEvents' arm
--
-- The call site itself, driven through the real World:checkTimeEvents and
-- World:stepContext on a stub self: the `.do_daily` arm has to consult the
-- gate every overworld frame, hand it the tile underfoot, and route a landed
-- call into receivePhoneCall.
do
  local save = newSave()
  Phone.addContact(save, 15) -- Joey, ROUTE_30
  local received = {}
  local coll = 0x00
  local fake = {
    game = { save = save, clock = { day = 0, hour = 9, minute = 0 } },
    maps = {},
    daytime = "DAY",
    playerState = "walk",
    map = {
      def = { id = "ROUTE_31", environment = "ROUTE", phoneService = true },
      cellCollision = function() return coll end,
    },
    player = { cellX = 4, cellY = 4 },
    stepContext = World.stepContext,
    checkTimeEvents = World.checkTimeEvents,
    receivePhoneCall = function(_, call)
      received[#received + 1] = call
      return true
    end,
  }
  -- Pin the gate's two Random draws (the coin flip and ChooseRandomCaller)
  -- to the passing arm; everything else stays on the ambient stream.
  local ambient = math.random
  math.random = function(a, b)
    if a == 0 and b == 255 then return 0 end
    return ambient(a, b)
  end

  eq(fake:checkTimeEvents(), false, "minute zero stamps the countdown")
  fake.game.clock.minute = 19
  eq(fake:checkTimeEvents(), false, "nineteen minutes is not enough")
  eq(#received, 0, "so nobody has rung")
  fake.game.clock.minute = 20
  eq(fake:checkTimeEvents(), true, "the twentieth minute lands the call")
  eq(#received, 1, "through receivePhoneCall")
  eq(received[1] and received[1].contact, 15, "from the contact in the book")
  eq(received[1] and received[1].direction, "incoming", "as an incoming call")
  eq(save.phone.delayMins, 10, "and the consumed timer wound on to ten")

  -- CheckStandingOnEntrance: a door tile refuses the call BEFORE the timer
  -- check, so the countdown is untouched while the player stands on it.
  coll = 0x71 -- COLL_DOOR
  fake.game.clock.minute = 40
  eq(fake:checkTimeEvents(), false, "standing on a door never rings")
  eq(#received, 1, "no second call landed")
  eq(save.phone.delayMins, 10, "and the countdown was not consumed")
  coll = 0x00
  eq(fake:checkTimeEvents(), true, "stepping off the door frees the line")
  eq(#received, 2, "and the held call lands")

  math.random = ambient
end

-- ------------------------------------------------- Mom's ring
--
-- MomTriesToBuySomething's .Script is `callasm .ASMFunction / farsjump
-- Script_ReceivePhoneCall`, so the queued shopping pages have to arrive
-- wrapped in the same chrome with PHONE_MOM on the line.
do
  local save = Save.normalize({ mom = { savedMoney = 10000, active = true,
    savingMoney = true }, party = {} })
  local vm = {}
  local fake = {
    game = { save = save,
      data = { text = require("tests.fixture_data.gen2_rom_text_s7_g").text() } },
    events = Events.new(),
    vm = vm,
    momTriesToBuy = World.momTriesToBuy,
  }
  local purchase = fake:momTriesToBuy()
  check(purchase ~= nil, "a full ladder rung buys something")
  local rows = fake.queuedScript
  check(type(rows) == "table", "and queues the call for the overworld")
  eq(rows[1] and rows[1].op, "reanchormap", "wrapped in the ring chrome")
  eq(rows[3] and rows[3].label, "RingTwice_StartCall", "which rings")
  check(rows[7].text:find("MOM:", 1, true) ~= nil, "as MOM")
  local inner = rows[8] and rows[8].script
  check(type(inner) == "table", "around her queued pages")
  eq(inner[1] and inner[1].op, "rawtext", "which are the shopping lines")
  eq(inner[#inner].op, "end", "and end like any caller script")
  eq(vm.curPhoneCaller, Phone.PHONECONTACT_MOM,
    "with wCurCaller parked on PHONE_MOM")

  -- The farscall's operand is the inline row list, the shape runList takes
  -- for a script wCallerContact would have pointed at: the whole queued call
  -- has to run to completion through a real Vm.
  local pages = {}
  local runner = Vm.new({}, {}, Events.new(), {
    showText = function(body, onDone)
      pages[#pages + 1] = body
      onDone()
    end,
    specials = { data = function()
      return { text = require("tests.fixture_data.gen2_rom_text_s7_f1").text() }
    end },
  })
  check(runner:start(rows), "the queued call runs whole")
  pump(runner)
  check(not runner:running(), "to completion")
  check(pages[1]:find("MOM:", 1, true) ~= nil, "ringing as MOM")
  check(table.concat(pages, "|"):find("Click!", 1, true) ~= nil,
    "and hanging up on the Click!")

  -- wCurCaller is shared state and may still hold an earlier trainer contact
  -- before the deferred Mom call starts.  The queued call must restore its
  -- own caller instead of showing that stale trainer above Mom's text.
  vm.curPhoneCaller = 15
  local startedAs
  vm.start = function(self)
    startedAs = self.curPhoneCaller
    return true
  end
  fake.busy = function() return false end
  fake.runQueuedScript = World.runQueuedScript
  check(fake:runQueuedScript(), "the deferred Mom call starts")
  eq(startedAs, Phone.PHONECONTACT_MOM,
    "and restores MOM after a trainer overwrote wCurCaller")
end

-- ------------------------------------------------- against the cache
--
-- A REAL caller script through a real Vm inside the wrapper: Joey's
-- (41:4368), whose .WantsBattle arm is the whole rematch mechanic.
do
  local cacheDir = os.getenv("GOLD_CACHE")
  if not cacheDir then
    local home = os.getenv("HOME") or ""
    cacheDir = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local generated = cacheDir .. "/data/generated/"
  local scriptsFile = loadfile(generated .. "scripts.lua")
  if not scriptsFile then
    check(true, "cache absent; VM-side blocks skipped (SKIP)")
  else
    local scripts = scriptsFile()
    local text = assert(loadfile(generated .. "text.lua"))()
    local constants = assert(loadfile(generated .. "constants.lua"))()
    local trainers = assert(loadfile(generated .. "trainers.lua"))()
    local encounters = assert(loadfile(generated .. "encounters.lua"))()
    local pokemon = assert(loadfile(generated .. "pokemon.lua"))()
    local romText = assert(loadfile(generated .. "rom_text.lua"))()
    local TrainerHouse = require("src.world.gen2.TrainerHouse")

    local function newCallVm(save, world)
      local pages = {}
      local vm
      vm = Vm.new(scripts, text, Events.new(), {
        showText = function(body, onDone)
          pages[#pages + 1] = body
          onDone()
        end,
        specialOrder = constants.specialOrder,
        getTrainerName = function(group, index)
          return TrainerHouse.name(trainers, save, group, index)
        end,
        playSound = function(id) world.sfx[#world.sfx + 1] = id end,
        callAsm = function(label, bank, addr)
          return CallAsm.dispatch(world, label, bank, addr)
        end,
        specials = {
          world = world,
          save = function() return save end,
          data = function() return { pokemon = pokemon, trainers = trainers,
            text = romText } end,
        },
      })
      return vm, pages
    end

    local function newWorld(save)
      return {
        game = { save = save },
        encounters = encounters,
        daytime = "DAY",
        sfx = {},
        playSfxNamed = function(self, name) self.sfx[#self.sfx + 1] = name end,
        stepContext = function()
          return { phone = { clock = { day = 0, hour = 9, minute = 40 } } }
        end,
      }
    end

    -- The rematch arm: ENGINE_FLYPOINT_GOLDENROD set (checkflag 69 in the
    -- extracted body) and PhoneScript_Random2 landing 0 takes .WantsBattle,
    -- whose `setevent EVENT_JOEY_READY_FOR_REMATCH` (628) is the only writer
    -- of that flag in the whole game.
    local save = newSave()
    Phone.initReceiveDelay(save, { clock = { day = 0, hour = 9, minute = 0 } })
    local world = newWorld(save)
    local vm, pages = newCallVm(save, world)
    vm.engineFlags[69] = true
    local ambient = math.random
    math.random = function(a) return a == 0 and 0 or 0 end
    vm.curPhoneCaller = 15
    local call = Phone.loadCallerScript(15, "incoming", "caller")
    check(vm:start(PhoneRing.script(call, "JOEY", "YOUNGSTER")),
      "the wrapped caller script runs")
    pump(vm)
    math.random = ambient
    check(not vm:running(), "to completion")
    check(pages[1]:find("RING!", 1, true) ~= nil, "opening on the ring page")
    local said = table.concat(pages, "|")
    check(said:find("It's me, JOEY", 1, true) ~= nil,
      "the greeting names the caller off gettrainername")
    check(vm.events:get(628),
      "and .WantsBattle armed EVENT_JOEY_READY_FOR_REMATCH")
    check(said:find("Click!", 1, true) ~= nil, "the hang-up clicks")
    eq(world.sfx[1], "Sfx_Call", "the ring SFX played")
    -- RingTwice_StartCall rings twice (engine/phone/phone.asm:458-469).
    eq(world.sfx[2], "Sfx_Call", "and rang a second time")
    eq(save.phone.delayMins, 20,
      "and InitCallReceiveDelay restarted the countdown")
    local unknown = {}
    for op in pairs(vm.unknownOps) do unknown[#unknown + 1] = op end
    eq(table.concat(unknown, ","), "", "no opcode fell through")

    -- The chatter: the shared PhoneScript_Generic body (41:48f0) opens on
    -- `special RandomPhoneMon` and its "My {STRBUF}'s really energetic" line
    -- reads the buffer that special filled from the CALLER'S party; the
    -- `special RandomPhoneWildMon` body it chains into (41:4920) then names
    -- a wild mon off the caller's own route.
    local save2 = newSave()
    local world2 = newWorld(save2)
    local vm2, pages2 = newCallVm(save2, world2)
    vm2.curPhoneCaller = 15
    -- Every Random2 lands 1 (the chat arms); Specials.random holds its own
    -- reference to the roll, so it gets its own stub: the LAST slot of both
    -- the party and the four commonest wilds.
    math.random = function(a, b) return b or a end
    local oldSpecialsRoll = Specials.random
    Specials.random = function(n) return n end
    check(vm2:start("41:48f0"), "the generic chat body runs")
    Specials.random = oldSpecialsRoll
    math.random = ambient
    check(table.concat(pages2, "|"):find("My RATTATA", 1, true) ~= nil,
      "RandomPhoneMon named a mon out of JOEY's own party")
    local day4 = encounters.grass.ROUTE_30.slots.DAY[4]
    eq(vm2.stringBuffer, pokemon[day4.species].name,
      "and RandomPhoneWildMon followed with a wild one off ROUTE 30")

    -- RandomPhoneWildMon: one of the four commonest DAY slots on the
    -- caller's map (Joey: ROUTE_30), named into the buffer.
    local save3 = newSave()
    local world3 = newWorld(save3)
    local vm3 = newCallVm(save3, world3)
    vm3.curPhoneCaller = 15
    local oldRoll = Specials.random
    Specials.random = function() return 1 end
    check(vm3:start({ { op = "special", id = 91 }, { op = "end" } }),
      "RandomPhoneWildMon dispatches by its cache id")
    Specials.random = oldRoll
    local day = encounters.grass.ROUTE_30.slots.DAY
    eq(vm3.stringBuffer, pokemon[day[1].species].name,
      "and names the commonest wild mon on the caller's own route")

    -- The Pokegear's outgoing half: Game2:runPokegearCall runs the contact's
    -- SCRIPT1 through the same VM, with wCurCaller parked first.
    local Game2 = require("src.core.Game2")
    local save4 = newSave()
    Phone.addContact(save4, 15)
    local world4 = newWorld(save4)
    local vm4, pages4 = newCallVm(save4, world4)
    world4.vm = vm4
    local gold = setmetatable({ world = world4 }, Game2)
    local out = Phone.call(save4, 15,
      { map = { id = "ROUTE_31", phoneService = true }, timeOfDay = "DAY" })
    eq(out.script, "JoeyPhoneCalleeScript", "the descriptor names SCRIPT1")
    check(gold:runPokegearCall(out), "and runPokegearCall runs it")
    check(#pages4 > 0, "so the callee actually talks")
    check(table.concat(pages4, "|"):find("JOEY", 1, true) ~= nil,
      "as himself")
    eq(vm4.curPhoneCaller, 15, "with wCurCaller parked for the specials")
    eq(out.ranScript, true, "and the descriptor records the run")
    check(not gold:runPokegearCall({ kind = "outofarea" }),
      "an out-of-area answer keeps the card's own line instead")
  end
end

S.finish()

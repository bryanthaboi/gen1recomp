#!/usr/bin/env luajit
-- pokefirered/src/battle_script_commands.c:9617

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function()
  return { setFilter = function() end, getDimensions = function() return 8, 8 end }
end
_G.love = { graphics = gfx }

local Storage = require("src.core.game3.storage")
local Flags = require("src.core.game3.scripting.flags")
local Dex = require("src.core.game3.dex")
local Runtime = require("src.core.game3.runtime")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Naming = require("src.ui.game3.naming")

-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037

local function mon(species, name)
  return {
    species = species, speciesId = species, name = name or "RATTATA",
    level = 5, hp = 20, maxHp = 20, nickname = "",
  }
end

local function new_session(partyCount)
  local session = { name = "RED", party = {}, store = Flags.newStore(), dex = Dex.new() }
  for _ = 1, partyCount do session.party[#session.party + 1] = mon(19) end
  Storage.ensure(session)
  session.storage.currentBox = 1
  Flags.setVar(session.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
  Runtime.session = session
  return session
end

local function headless_catch(session)
  local caught = mon(129, "MAGIKARP")
  local st = {
    wild = true,
    enemy = { species = 129, level = 5, hp = 10, maxHp = 10, mon = caught },
    player = { mon = session.party[1] },
    playerName = "RED",
  }
  local msgs = {}
  -- pokefirered/src/battle_script_commands.c:9617
  local done = CatchSeq.begin(st, 4, true, 4, {
    session = session,
    headless = true,
    pushMsg = function(text) msgs[#msgs + 1] = tostring(text) end,
  })
  return done, msgs
end

print("[test] 1. a headless catch with a full party records the PC transfer")
local s1 = new_session(6)
local done1, msgs1 = headless_catch(s1)
check(done1 == true, "the headless arm finished the sequence in one call")
local res1 = CatchSeq.catchResult()
check(res1 ~= nil, "CatchSeq.catchResult() is set after a headless catch")
eq(res1 and res1.location, "pc", "and it says the mon went to the PC")
check(table.concat(msgs1, " | "):find("transferred to", 1, true) ~= nil,
  "the transfer line was pushed too (" .. table.concat(msgs1, " | ") .. ")")

print("[test] 2. the naming screen's fallback can now read it (naming_screen.c:696)")
Naming.open({
  template = "CAUGHT_MON",
  maxLen = 10,
  species = 129,
  seed = "MAGIKARP",
  onDone = function() end,
})
Naming._state.name = "HEADLESS"
local key = nil
local input = { wasPressed = function(_, k) return key == k end }
local function press(k)
  key = k
  Naming.update(input, 1 / 60)
  key = nil
end
press("start")
press("a")
check(Naming._state ~= nil and Naming._state.pcPages ~= nil,
  "the screen found the headless catch result and printed the transfer line")
press("a")
press("a")
check(not Naming.isOpen(), "and it closed after the message")

print("[test] 3. a headless catch with room keeps the mon in the party")
local s2 = new_session(3)
local done2 = headless_catch(s2)
check(done2 == true, "the headless arm finished again")
local res2 = CatchSeq.catchResult()
check(res2 ~= nil, "a party catch records a result as well")
eq(res2 and res2.location, "party", "and it says the mon joined the party")
eq(#s2.party, 4, "the party grew by one")

print("[test] 4. a headless miss records no catch at all")
local s3 = new_session(3)
local caught = mon(129, "MAGIKARP")
CatchSeq.begin({
  wild = true,
  enemy = { species = 129, level = 5, hp = 10, maxHp = 10, mon = caught },
  player = { mon = s3.party[1] },
  playerName = "RED",
}, 4, false, 2, { session = s3, headless = true, pushMsg = function() end })
eq(CatchSeq.catchResult(), nil, "a broken-free ball leaves catchResult() nil")
eq(#s3.party, 3, "and the party is unchanged")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)

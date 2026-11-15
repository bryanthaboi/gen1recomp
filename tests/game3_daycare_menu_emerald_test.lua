#!/usr/bin/env luajit
-- pokeemerald/data/scripts/day_care.inc:160

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("src.core.game3.se_ids").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/scripts/events.lua") then
  print("[skip] game3_daycare_menu_emerald_test: no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"))
  os.exit(0)
end
Dataset.mountExtractRoots()

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  version = "emerald", store = store, map = "EM_ROUTE117_POKEMON_DAY_CARE", party = {},
  name = "MAY", trainerId = 4242, secretId = 7, vars = {}, flags = {}, modData = {},
  dex = { seen = {}, owned = {}, caught = {} }, money = 99999,
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Daycare = require("src.core.game3.daycare")
local Natives = require("src.core.game3.scripting.natives")
Natives.ensureBound(session)
local Flags = require("src.core.game3.scripting.flags")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Party = require("src.core.game3.party")
local RomText = require("src.core.game3.rom_text")
local DaycareMenu = require("src.ui.game3.daycare_menu")
local Stack = require("src.ui.game3.stack")
local MonOps = require("tools.save-editor.MonOps")

local VAR_RESULT, VAR_0x8004, VAR_0x8005 = 0x800D, 0x8004, 0x8005
local DAYCARE_TWO_MONS = 3

local function newCtx() return { specialVars = {}, stringVars = { [1] = "", [2] = "", [3] = "", [4] = "" } } end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end
local function getVar(ctx, id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function call(name, ctx)
  local h = Natives.handlerFor(name)
  check(h ~= nil, "Emerald binds " .. name)
  if not h then finish() end
  return xpcall(function() return h(ctx, nil) end, debug.traceback)
end

local DITTO, COMBUSKEN = 132, 281

print("[test] 1. two boarded mons, one of them a save-editor DITTO")
local ditto = MonOps.create({}, DITTO, 30, 3)
ditto.otId, ditto.otName = 4242, "MAY"
check(type(ditto.moves[1]) == "table", "the save editor stores moves as tables")
local okC, _, combusken = Party.giveMon(session, COMBUSKEN, 16)
check(okC, "built a COMBUSKEN")
session.party[#session.party + 1] = ditto
for _ = 1, 2 do
  local ctx = newCtx()
  setVar(ctx, VAR_0x8004, 0)
  local ok, err = call("StoreSelectedPokemonInDaycare", ctx)
  check(ok, "StoreSelectedPokemonInDaycare ran " .. tostring(ok or err))
end
local dc = Daycare.stateOf(session)
eq(Daycare.count(dc), 2, "both mons are boarded")
local ctx = newCtx()
call("GetDaycareState", ctx)
eq(getVar(ctx, VAR_RESULT), DAYCARE_TWO_MONS, "GetDaycareState is DAYCARE_TWO_MONS")

print("[test] 2. ShowDaycareLevelMenu opens on Emerald")
ctx = newCtx()
setVar(ctx, VAR_RESULT, 99)
local ok, err = call("ShowDaycareLevelMenu", ctx)
check(ok, "ShowDaycareLevelMenu does not raise " .. tostring(ok or err))
check(DaycareMenu.isOpen(), "the level menu is open")
check(Stack.has("daycare_level_menu"), "and on the stack")
local rows = DaycareMenu.rowList or {}
eq(rows[3] and rows[3].text, RomText.plain("gText_Exit"), "row 3 is pokeemerald's gText_Exit")
eq(rows[3] and rows[3].text, "EXIT", "which reads EXIT")
eq(rows[3] and rows[3].value, DaycareMenu.DAYCARE_LEVEL_MENU_EXIT, "and returns DAYCARE_LEVEL_MENU_EXIT")
eq(rows[1] and rows[1].text, Pokemon.name(COMBUSKEN), "row 1 is the COMBUSKEN")
eq(rows[2] and rows[2].text, Pokemon.name(DITTO), "row 2 is the DITTO")

print("[test] 3. the window is pokeemerald's sDaycareLevelMenuWindowTemplate")
local L = DaycareMenu.layout()
eq(L.left, 15, "tilemapLeft 15")
eq(L.top, 1, "tilemapTop 1")
eq(L.width, 14, "14 tiles wide")
eq(L.height, 6, "6 tiles tall")
eq(L.rowPitch, 16, "rows advance by FONT_NORMAL's 16px height")
eq(L.textY, 1, "upText_Y is 1")
eq(DaycareMenu.levelX(rows[1], L) + DaycareMenu.textWidth(rows[1].level), 112,
  "the level text ends at x 112")

print("[test] 4. A picks the first mon and the withdraw finishes")
DaycareMenu.handleInput({ wasPressed = function(_, k) return k == "a" end })
eq(getVar(ctx, VAR_RESULT), 0, "A on the first row returns 0")
check(not DaycareMenu.isOpen(), "the menu closed")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
ok, err = call("GetDaycareCostAndPrepareString", ctx)
check(ok, "GetDaycareCostAndPrepareString ran " .. tostring(ok or err))
eq(getVar(ctx, VAR_0x8005), 100, "no steps walked costs 100")
local before = #session.party
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
ok, err = call("TakePokemonFromDaycare", ctx)
check(ok, "TakePokemonFromDaycare ran " .. tostring(ok or err))
eq(#session.party, before + 1, "the party gained the mon")
eq(session.party[#session.party].species, COMBUSKEN, "and it is the COMBUSKEN")
eq(Daycare.count(dc), 1, "one mon is left boarded")

print("[test] 5. a table-shaped moveset keeps its moves through teachMove")
local probe = MonOps.create({}, DITTO, 30, 3)
local ids = {}
for i = 1, 4 do ids[i] = Pokemon.moveIdAt(probe, i) end
check(ids[1] and ids[1] > 0, "the editor DITTO knows a move")
local learned = Daycare.teachMove(probe, 33)
check(learned, "teachMove taught TACKLE")
local kept = {}
for i = 1, 4 do kept[i] = Pokemon.moveIdAt(probe, i) end
eq(kept[1], ids[1], "the old first move is still slot 1")
local n = 0
for i = 1, 4 do if (kept[i] or 0) > 0 then n = n + 1 end end
local had = 0
for i = 1, 4 do if (ids[i] or 0) > 0 then had = had + 1 end end
eq(n, math.min(4, had + 1), "no existing move was dropped")
check(type(probe.moves[1]) == "table", "the moves keep the editor's table shape")

finish()

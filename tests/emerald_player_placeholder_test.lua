package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function loadRel(rel)
  local src = cache and cache.read and cache:read(rel)
  if type(src) ~= "string" then return nil end
  local chunk = load(src, "@" .. rel, "t", { setmetatable = setmetatable, pairs = pairs, ipairs = ipairs })
  local ok, v = pcall(chunk)
  return ok and v or nil
end
local manifest = loadRel("data/generated/gba/pokemon/battle/manifest.lua")
local text = manifest and manifest.layout == "rse" and loadRel("data/generated/gba/scripts/text.lua")
if type(text) ~= "table" then
  print("emerald_player_placeholder_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local TextIR = require("src.core.game3.scripting.text_ir")
local Trainers = require("src.core.game3.scripting.trainers")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local Message = require("src.ui.game3.message")
local BattleText = require("src.core.game3.battle.battle_text")

local placeholders = loadRel("data/generated/gba/text/placeholders.lua")
local liveProvider = TextIR._provider
TextIR.setContextProvider(function(kind, dialect, ctx)
  if kind == "placeholders" then return placeholders end
  return liveProvider(kind, dialect, ctx)
end)

local sess = { version = "emerald", name = "QUINCY", gender = 0, trainerId = 1, money = 0, party = {} }
local prevSession, prevVm = Runtime.session, Space.vm
Runtime.session = sess
Space.vm = {
  ctx = { stringVars = { "ZIGZAGOON", "SECOND", "" } },
  adapters = {},
  getText = function(_, key) return text[key] end,
}

local function shown(t, opts)
  Message.show(t, opts or { frame = "battle", battle = true })
  local s = table.concat(Message._pages or {}, " ")
  Message.close()
  return (s:gsub("[\n\f\v]", " "))
end

local function has(s, needle) return type(s) == "string" and s:find(needle, 1, true) ~= nil end

local WALLACE = C.trainers and C.trainers.TRAINER_WALLACE or 335
local baked = Trainers.get(WALLACE).dialogs.defeat
check(has(baked, "Kudos to you, PLAYER!"), "cache dialogs.defeat is the flattened import string")

local d = Trainers.dialogs(WALLACE)
eq(type(d.defeat), "table", "Wallace defeat resolves to IR through the live script text")
local wallace = shown(d.defeat)
check(has(wallace, "Kudos to you, QUINCY!"), "Wallace defeat names the player: " .. wallace)
check(not has(wallace, "PLAYER"), "Wallace defeat has no literal PLAYER")
check(has(shown(Trainers.info(WALLACE).dialogs.intro), "QUINCY"), "Wallace intro via Trainers.info names the player")

for _, tid in ipairs({ 269, 519, 520, 529, 664, 804 }) do
  local dl = Trainers.dialogs(tid)
  for _, field in ipairs({ "intro", "defeat" }) do
    local ir = dl[field]
    if type(ir) == "table" then
      local s = shown(ir)
      local wantsPlayer = false
      for _, seg in ipairs(ir) do if seg.t == "player" then wantsPlayer = true end end
      if wantsPlayer then
        check(has(s, "QUINCY") and not has(s, "PLAYER"), ("trainer %d %s names the player: %s"):format(tid, field, s))
      end
    end
  end
end

check(has(TextIR.toPlain(d.defeat), "QUINCY"), "toPlain without ctx falls back to the live player")
check(has(TextIR.toPlain(d.defeat, { playerName = "ZED" }), "ZED"), "explicit ctx playerName still wins")

local rivalIr, strIr
for _, ir in pairs(text) do
  if type(ir) == "table" then
    for _, seg in ipairs(ir) do
      if not rivalIr and seg.t == "rival" then rivalIr = ir end
      if not strIr and seg.t == "strvar" and seg.n == 1 then strIr = ir end
    end
  end
  if rivalIr and strIr then break end
end
if rivalIr then
  check(has(shown(rivalIr), "MAY"), "{RIVAL} is MAY for a male player")
  sess.gender = 1
  check(has(shown(rivalIr), "BRENDAN"), "{RIVAL} is BRENDAN for a female player")
  sess.gender = 0
end
if strIr then
  check(has(shown(strIr), "ZIGZAGOON"), "{STR_VAR_1} reads the live script string var")
end

local vs = shown(BattleText.get("STRINGID_PLAYERGOTMONEY", { playerName = "QUINCY", buff1 = "9900" }))
check(has(vs, "QUINCY") and has(vs, "9900"), "battle prize string names the player: " .. vs)
local money = shown(require("src.core.game3.battle.prize").moneyMessage(sess.name, 9900))
check(has(money, "QUINCY got"), "prize money message names the player: " .. money)

Space.vm = nil
eq(Trainers.dialogs(WALLACE).defeat, baked, "without a script vm the cache string is returned unchanged")

Runtime.session, Space.vm = prevSession, prevVm
TextIR.setContextProvider(liveProvider)
T.finish("emerald_player_placeholder_test")

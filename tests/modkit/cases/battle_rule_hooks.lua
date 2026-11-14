-- A sandboxed mod can decide two battle rules the OPTION screen and the cart
-- otherwise decide for the player -- whether a faint offers a free switch
-- (battle.style) and whether a catch asks for a nickname (catch.nickname) --
-- using only public mod surfaces, and neither hook touches the player's
-- saved preference.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local TextBox = require("src.render.TextBox")

local FIXTURE = {
  ["mods/rules_probe/manifest.json"] = [[{
    "id": "rules_probe",
    "name": "Rules Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/rules_probe/main.lua"] = [[
    local mod = ...
    mod.exports.style = "set"
    mod.exports.nickname = false
    mod.hooks:wrap("battle.style", function(next, battle)
      mod.exports.styleCalls = (mod.exports.styleCalls or 0) + 1
      mod.exports.styleBattle = battle
      if mod.exports.style ~= nil then return mod.exports.style end
      return next(battle)
    end)
    mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
      mod.exports.nameCalls = (mod.exports.nameCalls or 0) + 1
      mod.exports.nameCtx = ctx
      if mod.exports.nickname ~= nil then return mod.exports.nickname end
      return next(mon, ctx)
    end)
  ]],
}

local function fixtureBattle(style)
  local data = { pokemon = {}, text = {} }
  return setmetatable({
    game = { save = { options = { battleStyle = style } },
             stack = { push = function() end }, data = data },
    data = data,
    queue = {}, nextInsert = 0,
  }, { __index = BattleState })
end

-- does the queued UI, if any, put the yes/no prompt on screen?
local function promptQueued(battle)
  for _, item in ipairs(battle.queue) do
    if item.ui then
      local state = item.ui()
      if getmetatable(state) == TextBox and state.choice then return true end
    end
  end
  return false
end

-- ------- no mod: the OPTION row and the cart's AskName decide

local vanilla = T.sdk.loadNone({})
T.eq(fixtureBattle("shift"):battleStyle(), "shift", "no mod: SHIFT row reads shift")
T.eq(fixtureBattle("set"):battleStyle(), "set", "no mod: SET row reads set")
T.eq(fixtureBattle("SET"):battleStyle(), "set", "no mod: the row is case-insensitive")
T.eq(fixtureBattle(nil):battleStyle(), "shift", "no mod: a missing row is the cart default")

local plain = fixtureBattle("shift")
local mon = { species = "RATTATA" }
T.eq(plain:offerNickname(mon, "RATTATA"), true, "no mod: a catch queues the prompt")
T.eq(promptQueued(plain), true, "no mod: and it is the yes/no box")
T.eq(mon.nickname, nil, "no mod: nothing is named behind the player's back")
vanilla.release()

-- ------- a mod answers both

local run = T.sdk.loadMods({ "mods/rules_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0, "the rules probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.rules_probe

local forced = fixtureBattle("shift")
T.eq(forced:battleStyle(), "set", "\"set\" wins over a SHIFT row")
T.eq(forced.game.save.options.battleStyle, "shift", "without writing the row")
T.eq(probe.styleCalls, 1, "the hook ran once")
T.check(probe.styleBattle == forced, "and was handed the battle")
probe.style = "shift"
T.eq(fixtureBattle("set"):battleStyle(), "shift", "\"shift\" wins over a SET row")
probe.style = "banana"
T.eq(fixtureBattle("set"):battleStyle(), "set",
  "an answer that is neither reads as the row")
probe.style = nil
T.eq(fixtureBattle("set"):battleStyle(), "set", "falling through reads the row")

local skipped = fixtureBattle("shift")
local kept = { species = "RATTATA" }
T.eq(skipped:offerNickname(kept, "RATTATA"), false, "false: no prompt is queued")
T.eq(#skipped.queue, 0, "nothing at all is queued")
T.eq(kept.nickname, nil, "and the species name is kept")
T.eq(probe.nameCalls, 1, "the hook ran once")
T.check(probe.nameCtx and probe.nameCtx.battle == skipped, "with the battle in ctx")
T.eq(probe.nameCtx and probe.nameCtx.name, "RATTATA", "and the display name")

probe.nickname = "SPIKE"
local named = { species = "RATTATA" }
T.eq(fixtureBattle("shift"):offerNickname(named, "RATTATA"), false,
  "a string: no prompt either")
T.eq(named.nickname, "SPIKE", "and it is the nickname")

probe.nickname = "TOOLONGFORTHEGRID"
local clipped = { species = "RATTATA" }
fixtureBattle("shift"):offerNickname(clipped, "RATTATA")
T.eq(clipped.nickname, "TOOLONGFOR", "a long string is clipped to the grid's ten")

local E, MALE = "\195\169", "\226\153\130"
local function caughtAs(nickname)
  probe.nickname = nickname
  local mon = { species = "RATTATA" }
  fixtureBattle("shift"):offerNickname(mon, "RATTATA")
  return mon.nickname
end
T.eq(caughtAs(E:rep(10)), E:rep(10), "ten multibyte characters all fit the grid")
T.eq(caughtAs("A" .. E:rep(12)), "A" .. E:rep(9), "the clip counts characters, not bytes")
T.eq(caughtAs(MALE:rep(4)), MALE:rep(4), "four signs are under the limit")
T.eq(caughtAs("NIDO" .. MALE .. "KING" .. MALE .. "X"), "NIDO" .. MALE .. "KING" .. MALE,
  "a grid-legal ten with two signs")
T.eq(caughtAs("SPI\nKE"), "SPIKE", "control characters never reach the name")

probe.nickname = ""
local blank = { species = "RATTATA" }
T.eq(fixtureBattle("shift"):offerNickname(blank, "RATTATA"), false,
  "an empty string still declines the prompt")
T.eq(blank.nickname, nil, "and names nothing, like the grid's own empty entry")

probe.nickname = nil
local asked = fixtureBattle("shift")
T.eq(asked:offerNickname({ species = "RATTATA" }, "RATTATA"), true,
  "falling through asks as usual")
T.eq(promptQueued(asked), true, "with the real prompt")

require("src.render.Font").load({ font = { charmap = {
  { seq = "<PK>", code = 0xE1 }, { seq = "<MN>", code = 0xE2 },
} } })
T.eq(caughtAs(("<PK><MN>"):rep(6)), ("<PK><MN>"):rep(5), "a charmap token is one glyph")

run.release()
T.finish("battle rule hooks")

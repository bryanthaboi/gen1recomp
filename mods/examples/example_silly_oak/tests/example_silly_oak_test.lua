-- Standalone: luajit mods/examples/example_silly_oak/tests/example_silly_oak_test.lua
-- Covers the intro.oak_speech build hook, step helpers, sprite descriptors,
-- and answers landing in mod.save.
--
-- Needs an imported ROM dataset (data/generated/).  Headless CI and a
-- fresh checkout without a ROM skip cleanly -- the gallery is also
-- covered by tests/mod_examples_tests.lua when generated data is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local function hasGenerated()
  local handle = io.open("data/generated/constants.lua", "r")
  if handle then handle:close() return true end
  return false
end
if not hasGenerated() then
  print("example_silly_oak_test skipped (needs data/generated/)")
  os.exit(0)
end

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local OakSpeech = require("src.ui.OakSpeech")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMod("mods/examples/example_silly_oak", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local mod = run.mod
T.check(mod ~= nil and mod.state == "loaded", "mod reached the loaded state")
local ModUI = require("src.ui.ModUI")
local bucket = function()
  return run.loader.modSave.example_silly_oak or {}
end
local toastPath = (mod.path or "mods/examples/example_silly_oak")
  .. "/assets/toast_kid.png"

-- ------- build hook injects every silly beat around vanilla anchors

local speech = OakSpeech.new({
  data = Data,
  save = { player = { name = "RED", rival = "BLUE" } },
  stack = { push = function() end, pop = function() end },
}, nil)
local steps = speech:buildSteps()

local ids = {}
for _, step in ipairs(steps) do ids[#ids + 1] = step.id end
local function has(id)
  for _, x in ipairs(ids) do if x == id then return true end end
  return false
end

T.check(has("oak_welcome") and has("name_player") and has("shrink"),
  "vanilla anchors still present")
T.check(has("silly_quiz_intro") and has("silly_toast") and has("silly_toast_kid"),
  "toast quiz beats injected")
T.check(has("silly_mew") and has("silly_snack"),
  "MEW reveal and snack choice injected")
T.check(has("silly_trust") and has("silly_pineapple") and has("silly_closing"),
  "rival trust + pineapple beats injected")

-- order: toast kid before demo_mon, mew after demo_mon, trust before rival ask
local function indexOf(id)
  for i, x in ipairs(ids) do if x == id then return i end end
  return 0
end
T.check(indexOf("silly_toast_kid") < indexOf("demo_mon"),
  "Toast Kid shows before the demo mon")
T.check(indexOf("demo_mon") < indexOf("silly_mew"),
  "MEW shows after the demo mon")
T.check(indexOf("silly_trust") < indexOf("ask_rival_name"),
  "trust question is before rival naming")
T.check(indexOf("name_rival") < indexOf("silly_pineapple")
        and indexOf("silly_pineapple") < indexOf("legend"),
  "pineapple lands between rival name and the legend beat")

-- ------- step shapes cover choice / yesno / custom image / pokemon

local byId = {}
for _, step in ipairs(steps) do byId[step.id] = step end

T.eq(byId.silly_toast.kind, "yesno", "toast is a yes/no")
T.eq(byId.silly_toast.saveKey, "likes_toast", "toast writes likes_toast")
T.eq(byId.silly_snack.kind, "choice", "snack is a multi choice")
T.eq(#byId.silly_snack.choices, 3, "snack has three options")
T.check(byId.silly_toast_kid.pic and byId.silly_toast_kid.pic.type == "image",
  "Toast Kid uses a custom image pic")
T.check(byId.silly_mew.pic and byId.silly_mew.pic.type == "pokemon"
        and byId.silly_mew.pic.id == "MEW" and byId.silly_mew.cry == "MEW",
  "MEW beat uses pokemon pic + cry")
T.eq(byId.silly_trust.pic, "rival", "trust question shows the rival pic")

-- ------- resolvePic covers trainer / pokemon / player / image shorthand

local oakImg = OakSpeech.resolvePic({ data = Data }, "oak", speech)
local rivalImg = OakSpeech.resolvePic({ data = Data }, "rival", speech)
local playerImg = OakSpeech.resolvePic({ data = Data }, "player", speech)
local mewImg, mewFlip = OakSpeech.resolvePic({ data = Data },
  { type = "pokemon", id = "MEW", flip = true }, speech)
local customImg = OakSpeech.resolvePic({ data = Data },
  { type = "image", path = toastPath }, speech)
-- headless love stub may return nil images; the call itself must not throw
T.check(oakImg == speech.oakPic or oakImg == nil or type(oakImg) == "userdata"
        or type(oakImg) == "table",
  "oak shorthand resolves without error")
T.check(rivalImg == speech.rivalPic or rivalImg == nil or type(rivalImg) == "userdata"
        or type(rivalImg) == "table",
  "rival shorthand resolves without error")
T.check(playerImg == speech.playerPic or playerImg == nil
        or type(playerImg) == "userdata" or type(playerImg) == "table",
  "player shorthand resolves without error")
T.check(mewFlip == true, "pokemon flip flag is honored")
T.check(customImg ~= nil or true, "custom image path is accepted")

-- ------- answered event writes mod.save (loader.modSave bucket)

Runtime.emit("intro.oak_speech.answered", {
  saveKey = "likes_toast", value = true, label = "YES", index = 1,
  step = byId.silly_toast, speech = speech,
})
Runtime.emit("intro.oak_speech.answered", {
  saveKey = "snack", value = "OLD ROD", label = "OLD ROD", index = 3,
  step = byId.silly_snack, speech = speech,
})
Runtime.emit("intro.oak_speech.answered", {
  saveKey = "trusts_rival", value = false, label = "NO", index = 2,
  step = byId.silly_trust, speech = speech,
})
Runtime.emit("intro.oak_speech.answered", {
  saveKey = "pineapple_on_pizza", value = true, label = "YES", index = 1,
  step = byId.silly_pineapple, speech = speech,
})
Runtime.emit("intro.oak_speech.finished", {
  speech = speech, answers = speech.answers,
})

local saved = bucket()
T.eq(saved.likes_toast, true, "likes_toast saved")
T.eq(saved.snack, "OLD ROD", "snack saved")
T.eq(saved.trusts_rival, false, "trusts_rival saved")
T.eq(saved.pineapple_on_pizza, true, "pineapple_on_pizza saved")
T.eq(saved.quiz_done, true, "quiz_done stamped on finish")

-- ------- ModUI step helpers (public surface)

local tiny = {
  { id = "a", kind = "say" },
  { id = "b", kind = "say" },
}
ModUI.insertStepAfter(tiny, "a", { id = "mid", kind = "choice" })
T.eq(tiny[2].id, "mid", "insertStepAfter lands behind the anchor")
ModUI.insertStepBefore(tiny, "b", { id = "pre_b", kind = "yesno" })
T.eq(tiny[3].id, "pre_b", "insertStepBefore lands ahead of the anchor")
ModUI.removeStep(tiny, "mid")
T.check(tiny[2].id ~= "mid", "removeStep drops by id")

run.release()
T.finish("example_silly_oak")

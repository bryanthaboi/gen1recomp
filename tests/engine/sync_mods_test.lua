package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SyncMods = require("src.sync.SyncMods")

local function row(id, version, enabled, github)
  return { id = id, version = version, github = github,
           enabledByVersion = enabled }
end

local function deps(installed, indexes, catalog, modOptions)
  local calls = { installed = {}, enabled = {}, indexes = {}, options = {} }
  return calls, {
    modOptions = function() return modOptions or {} end,
    setOptions = function(id, values)
      calls.options[id] = values
      return true
    end,
    installed = function() return installed end,
    indexes = function() return indexes or {} end,
    addIndex = function(url)
      calls.indexes[#calls.indexes + 1] = url
      return { feed = url }
    end,
    findEntry = function(id) return (catalog or {})[id] end,
    install = function(entry)
      calls.installed[#calls.installed + 1] = entry.id
      return true
    end,
    setEnabled = function(id, enabled, version)
      calls.enabled[#calls.enabled + 1] = id .. ":" .. tostring(version)
      return true
    end,
  }
end

do
  local _, d = deps({
    row("zeta", "1.0.0", { red = true, blue = false, yellow = false, gold = false }),
    row("alpha", "2.1.0", { red = true, gold = true }, "someone/alpha"),
  }, { { url = "https://mods.example/index.json",
        feed = "https://mods.example/index.json" } })

  local manifest = SyncMods.build(d)
  T.eq(manifest.rev, SyncMods.REV, "the manifest carries its shape revision")
  T.eq(#manifest.indexes, 1, "the player's index list rides along")
  T.eq(manifest.indexes[1], "https://mods.example/index.json",
    "as the url they typed")
  T.eq(#manifest.mods, 2, "every installed mod is listed")
  T.eq(manifest.mods[1].id, "alpha", "sorted by id so the manifest is stable")
  T.eq(manifest.mods[1].source, "github:someone/alpha",
    "a github mod records where it came from")
  T.eq(manifest.mods[2].source, "local",
    "a hand-installed mod is marked local rather than invented")
  T.eq(#manifest.mods[1].enabledFor, 2, "alpha is on for two games")
  T.eq(manifest.mods[1].enabledFor[1], "red", "in GameVersion order")
  T.eq(manifest.mods[1].enabledFor[2], "gold", "red then gold")
  T.eq(#manifest.mods[2].enabledFor, 1, "zeta is on for one")
end

do
  local manifest = {
    rev = 1,
    indexes = { "https://mods.example/index.json", "https://other.example/i.json" },
    mods = {
      { id = "alpha", version = "2.1.0", enabledFor = { "red", "gold" } },
      { id = "beta", version = "1.0.0", enabledFor = { "red" } },
      { id = "ghost", version = "0.1.0", source = "local", enabledFor = { "red" } },
    },
  }
  local _, d = deps(
    { row("alpha", "2.1.0", { red = true }) },
    { { url = "https://mods.example/index.json",
        feed = "https://mods.example/index.json" } },
    { beta = { id = "beta" } })

  local plan = SyncMods.plan(manifest, d)
  T.eq(#plan.indexes, 1, "only the index this device is missing is planned")
  T.eq(plan.indexes[1], "https://other.example/i.json", "the new one")
  T.eq(#plan.toInstall, 1, "one mod can be fetched from an index")
  T.eq(plan.toInstall[1].id, "beta", "the one the catalog knows")
  T.eq(#plan.missing, 1, "the mod nobody publishes is reported, not invented")
  T.eq(plan.missing[1].id, "ghost", "by id")
  T.eq(#plan.toEnable, 2, "every game answer that differs is planned")
  for _, want in ipairs(plan.toEnable) do
    T.check(want.id ~= "ghost",
      "a mod that cannot be installed is never enabled")
  end
  T.eq(SyncMods.planEmpty(plan), false, "a plan with work is not empty")

  local same = SyncMods.plan({ rev = 1, indexes = {}, mods = {
    { id = "alpha", version = "2.1.0", enabledFor = { "red" } } } }, d)
  T.eq(SyncMods.planEmpty(same), true, "a matching device plans nothing")
end

do
  local calls, d = deps({}, {}, { beta = { id = "beta" } })
  local plan = {
    indexes = { "https://other.example/i.json" },
    toInstall = { { id = "beta", entry = { id = "beta" } } },
    toEnable = { { id = "beta", version = "red" } },
    missing = { { id = "ghost" } },
  }
  local seen = {}
  local ok = SyncMods.apply(plan, function(done, total, label)
    seen[#seen + 1] = ("%d/%d %s"):format(done, total, label)
  end, d)
  T.eq(ok, true, "applying a plan reports success")
  T.eq(calls.indexes[1], "https://other.example/i.json", "the index is added")
  T.eq(calls.installed[1], "beta", "the mod is installed through the launcher path")
  T.eq(calls.enabled[1], "beta:red", "and enabled for the game that wanted it")
  T.eq(#seen, 3, "progress is reported once per step")
  T.eq(seen[3], "3/3 beta", "counting up to the total")
end

do
  local _, d = deps({}, {}, {})
  d.install = function() return nil, "download failed" end
  local ok, err = SyncMods.apply({
    toInstall = { { id = "beta", entry = { id = "beta" } } } }, nil, d)
  T.eq(ok, false, "a failed install fails the apply")
  T.check(tostring(err):find("download failed", 1, true) ~= nil,
    "naming the mod and the reason")
end

do
  local calls, d = deps({}, {}, {})
  d.install = function() return nil, "download failed" end
  local ok = SyncMods.apply({
    toInstall = { { id = "beta", entry = { id = "beta" } } },
    toEnable = { { id = "beta", version = "red" } },
  }, nil, d)
  T.eq(ok, false, "the apply still reports the failure")
  T.eq(#calls.enabled, 0,
    "a mod whose install failed is not switched on regardless")
end

do
  local calls, d = deps({}, {}, {})
  local steps = SyncMods.steps({
    indexes = { "https://other.example/i.json" },
    toInstall = { { id = "beta", entry = { id = "beta" } } },
    toEnable = { { id = "beta", version = "red" } },
  }, d)
  T.eq(#steps, 3, "a plan splits into one step per unit of work")
  T.eq(steps[1].run(), true, "steps run one at a time")
  T.eq(#calls.indexes, 1, "so the caller can draw between them")
  T.eq(#calls.installed, 0, "without the rest of the plan having run yet")
end

do
  local live = {
    alpha = { speed = 3, name = "ASH", on = true, bad = {} },
    zeta = {},
  }
  local _, d = deps({
    row("alpha", "2.1.0", { red = true }),
    row("zeta", "1.0.0", { red = true }),
  }, {}, {}, live)

  local plain = SyncMods.build(d)
  T.eq(plain.mods[1].options, nil,
    "a mod list shares no options unless the player asks for it")
  T.eq(plain.hasOptions, nil, "and is not flagged as carrying any")

  local full = SyncMods.build(d, true)
  T.eq(full.hasOptions, true, "opting in flags the list as carrying options")
  T.eq(full.mods[1].options.speed, 3, "the player's own values ride along")
  T.eq(full.mods[1].options.name, "ASH", "text values too")
  T.eq(full.mods[1].options.on, true, "and toggles")
  T.eq(full.mods[1].options.bad, nil,
    "a nested table is never sent: only scalars cross the wire")
  T.eq(full.mods[2].options, nil, "a mod with nothing set sends no bucket")
end

do
  local wide = {}
  for i = 1, SyncMods.MAX_OPTION_KEYS + 20 do wide["k" .. i] = i end
  wide.huge = string.rep("x", SyncMods.MAX_OPTION_TEXT + 100)
  local _, d = deps({ row("alpha", "1.0.0", { red = true }) }, {}, {},
    { alpha = wide })
  local manifest = SyncMods.build(d, true)
  local n = 0
  for _ in pairs(manifest.mods[1].options) do n = n + 1 end
  T.eq(n, SyncMods.MAX_OPTION_KEYS, "an option bucket is capped")
  local kept = manifest.mods[1].options.huge
  T.check(kept == nil or #kept == SyncMods.MAX_OPTION_TEXT,
    "and a long string is clamped when it makes the cut")
end

do
  local manifest = { rev = 2, indexes = {}, hasOptions = true, mods = {
    { id = "alpha", version = "2.1.0", enabledFor = { "red" },
      options = { speed = 1, name = "MISTY" } },
    { id = "beta", version = "1.0.0", enabledFor = { "red" },
      options = { theme = "dark" } },
    { id = "same", version = "1.0.0", enabledFor = { "red" },
      options = { pitch = 5 } },
    { id = "ghost", version = "0.1.0", enabledFor = { "red" },
      options = { anything = 1 } },
  } }
  local calls, d = deps(
    { row("alpha", "2.1.0", { red = true }), row("same", "1.0.0", { red = true }) },
    {}, { beta = { id = "beta" } },
    { alpha = { speed = 3, name = "ASH" }, same = { pitch = 5 } })

  local plan = SyncMods.plan(manifest, d)
  T.eq(#plan.options, 2, "only mods this device can actually run are listed")
  T.eq(plan.options[1].id, "alpha", "the installed one whose values differ")
  T.eq(plan.options[2].id, "beta", "and the one this plan installs")
  for _, row in ipairs(plan.options) do
    T.check(row.id ~= "same", "a mod already set that way is not busywork")
    T.check(row.id ~= "ghost", "and a mod that cannot be installed is skipped")
  end
  T.eq(plan.applyOptions, nil, "nobody's options are imported unasked")
  T.eq(SyncMods.planHasOptions(plan), true, "the plan reports it has some")
  T.eq(SyncMods.optionsAnswered(plan), false, "and that the question is open")

  local steps = SyncMods.steps(plan, d)
  local labels = 0
  for _, step in ipairs(steps) do
    if step.label == "alpha" then labels = labels + 1 end
  end
  T.eq(labels, 0, "an unanswered plan writes no options")

  SyncMods.answerOptions(plan, false)
  T.eq(SyncMods.optionsAnswered(plan), true, "declining answers the question")
  SyncMods.apply(plan, nil, d)
  T.eq(next(calls.options), nil, "and keeps the options this device already had")

  SyncMods.answerOptions(plan, true)
  T.eq(plan.applyOptions, true, "accepting arms the option steps")
  SyncMods.apply(plan, nil, d)
  T.eq(calls.options.alpha.speed, 1, "the sharer's values are written")
  T.eq(calls.options.alpha.name, "MISTY", "every key they set")
  T.eq(calls.options.beta.theme, "dark", "including a mod installed by the plan")
end

do
  local manifest = { rev = 2, indexes = {}, mods = {
    { id = "alpha", version = "1.0.0", enabledFor = { "red" },
      options = { speed = 1 } } } }
  local calls, d = deps({ row("alpha", "1.0.0", { red = true }) }, {}, {},
    { alpha = { speed = 3 } })
  local plan = SyncMods.plan(manifest, d)
  T.eq(SyncMods.planEmpty(plan), true,
    "a list that only differs in options plans no mod work")
  SyncMods.answerOptions(plan, true)
  T.eq(SyncMods.planEmpty(plan), false,
    "until the options are accepted, and then there is work to do")
  d.install = function() return nil, "download failed" end
  SyncMods.apply(plan, nil, d)
  T.eq(calls.options.alpha.speed, 1, "which is just the option write")
end

do
  local manifest = { rev = 2, indexes = {}, mods = {
    { id = "beta", version = "1.0.0", enabledFor = { "red" },
      options = { speed = 1 } } } }
  local calls, d = deps({}, {}, { beta = { id = "beta" } })
  d.install = function() return nil, "download failed" end
  local plan = SyncMods.plan(manifest, d)
  SyncMods.answerOptions(plan, true)
  local ok = SyncMods.apply(plan, nil, d)
  T.eq(ok, false, "a failed install still fails the apply")
  T.eq(next(calls.options), nil,
    "and the options of a mod that never installed are not written")
end

T.finish("sync_mods")

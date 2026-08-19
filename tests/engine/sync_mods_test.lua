package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SyncMods = require("src.sync.SyncMods")

local function row(id, version, enabled, github)
  return { id = id, version = version, github = github,
           enabledByVersion = enabled }
end

local function deps(installed, indexes, catalog)
  local calls = { installed = {}, enabled = {}, indexes = {} }
  return calls, {
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

T.finish("sync_mods")

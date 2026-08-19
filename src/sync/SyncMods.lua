local SyncMods = {}

SyncMods.REV = 1

local function versions()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.ORDER then return GameVersion.ORDER end
  return { "red", "blue", "yellow", "gold" }
end

local function defaultDeps()
  return {
    installed = function()
      return require("src.mods.LauncherMods").list()
    end,
    indexes = function()
      return require("src.mods.ModIndex").sources()
    end,
    addIndex = function(url)
      return require("src.mods.ModIndex").addSource(url)
    end,
    findEntry = function(id)
      local ModIndex = require("src.mods.ModIndex")
      for _, source in ipairs(ModIndex.sources()) do
        local cached = ModIndex.readCache(source.feed)
        for _, entry in ipairs((cached and cached.mods) or {}) do
          if entry.id == id then return entry end
        end
      end
      return nil
    end,
    install = function(entry)
      return require("src.mods.LauncherMods").installFromIndex(entry)
    end,
    setEnabled = function(id, enabled, version)
      return require("src.mods.LauncherMods").setEnabled(id, enabled, version)
    end,
  }
end

local function deps(given)
  local out = defaultDeps()
  if type(given) == "table" then
    for k, v in pairs(given) do out[k] = v end
  end
  return out
end

local function sourceOf(row)
  local github = row.github
    or (type(row.manifest) == "table" and row.manifest.github)
  if type(github) == "string" and github ~= "" then
    return "github:" .. github
  end
  return "local"
end

function SyncMods.build(given)
  local d = deps(given)
  local manifest = { rev = SyncMods.REV, indexes = {}, mods = {} }
  for _, row in ipairs(d.indexes() or {}) do
    local url = row.url or row.feed
    if type(url) == "string" and url ~= "" then
      manifest.indexes[#manifest.indexes + 1] = url
    end
  end
  table.sort(manifest.indexes)
  for _, row in ipairs(d.installed() or {}) do
    if type(row) == "table" and type(row.id) == "string" then
      local enabledFor = {}
      local answers = row.enabledByVersion or {}
      for _, version in ipairs(versions()) do
        if answers[version] then enabledFor[#enabledFor + 1] = version end
      end
      manifest.mods[#manifest.mods + 1] = {
        id = row.id,
        version = row.version,
        source = sourceOf(row),
        enabledFor = enabledFor,
      }
    end
  end
  table.sort(manifest.mods, function(a, b) return a.id < b.id end)
  return manifest
end

function SyncMods.plan(manifest, given)
  local d = deps(given)
  local plan = { indexes = {}, toInstall = {}, toEnable = {}, missing = {} }
  if type(manifest) ~= "table" then return plan end

  local haveIndex = {}
  for _, row in ipairs(d.indexes() or {}) do
    if type(row.url) == "string" then haveIndex[row.url] = true end
    if type(row.feed) == "string" then haveIndex[row.feed] = true end
  end
  for _, url in ipairs(manifest.indexes or {}) do
    if type(url) == "string" and url ~= "" and not haveIndex[url] then
      plan.indexes[#plan.indexes + 1] = url
      haveIndex[url] = true
    end
  end

  local installed = {}
  for _, row in ipairs(d.installed() or {}) do
    if type(row) == "table" and type(row.id) == "string" then
      installed[row.id] = row
    end
  end

  for _, mod in ipairs(manifest.mods or {}) do
    if type(mod) == "table" and type(mod.id) == "string" then
      local here = installed[mod.id]
      local available = here ~= nil
      if not here then
        local entry = d.findEntry(mod.id)
        if entry then
          available = true
          plan.toInstall[#plan.toInstall + 1] =
            { id = mod.id, version = mod.version, entry = entry }
        else
          plan.missing[#plan.missing + 1] =
            { id = mod.id, version = mod.version, source = mod.source }
        end
      end
      if available then
        local answers = (here and here.enabledByVersion) or {}
        for _, version in ipairs(mod.enabledFor or {}) do
          if answers[version] ~= true then
            plan.toEnable[#plan.toEnable + 1] = { id = mod.id, version = version }
          end
        end
      end
    end
  end
  return plan
end

function SyncMods.planEmpty(plan)
  if type(plan) ~= "table" then return true end
  return #(plan.indexes or {}) == 0 and #(plan.toInstall or {}) == 0
    and #(plan.toEnable or {}) == 0
end

function SyncMods.steps(plan, given)
  local d = deps(given)
  local out = {}
  if type(plan) ~= "table" then return out end
  local broken = {}

  for _, url in ipairs(plan.indexes or {}) do
    out[#out + 1] = { label = url, run = function()
      local ok, err = d.addIndex(url)
      if not ok then return nil, tostring(err or url) end
      return true
    end }
  end
  for _, mod in ipairs(plan.toInstall or {}) do
    out[#out + 1] = { label = mod.id, run = function()
      local ok, err = d.install(mod.entry)
      if not ok then
        broken[mod.id] = true
        return nil, mod.id .. ": " .. tostring(err or "install failed")
      end
      return true
    end }
  end
  for _, want in ipairs(plan.toEnable or {}) do
    out[#out + 1] = { label = want.id, run = function()
      if broken[want.id] then return true end
      local ok, err = d.setEnabled(want.id, true, want.version)
      if ok == false then
        return nil, want.id .. ": " .. tostring(err or "could not enable")
      end
      return true
    end }
  end
  return out
end

function SyncMods.apply(plan, progress, given)
  if type(plan) ~= "table" then return false, "nothing to apply" end
  local steps = SyncMods.steps(plan, given)
  local failures = {}
  for i, step in ipairs(steps) do
    local ok, err = step.run()
    if not ok then failures[#failures + 1] = err end
    if progress then progress(i, #steps, step.label) end
  end
  if #failures > 0 then
    return false, table.concat(failures, "; ")
  end
  return true
end

return SyncMods

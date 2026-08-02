-- Mod profiles (#593): a named snapshot of one whole setup -- which mods are
-- enabled, each mod's own options, and which save slot every game version
-- plays -- plus the shareable .g1rmodlist file the manager writes and reads.
-- Pure data and filesystem: src/mods/ManagerState.lua owns the UI and the
-- staged toggles, and is the only caller.
--
-- Records live in options.modProfiles (src/core/SaveData.lua defaultOptions),
-- so a profile survives New Game exactly like the mod enable-state does:
--   { name    = "PROFILE 1",
--     enabled = { [modId] = true|false },     -- missing means enabled
--     options = { [modId] = { key = value } },-- mirrors options.modOptions
--     slots   = { red = "slot1", blue = "slot2", yellow = nil } }
-- Exports are SaveSerializer-encoded (data-only parse, an imported file can
-- never execute code) under profiles/<NAME>.g1rmodlist in the save dir, the
-- same shape SaveFileIO uses for exports/ (src/import/SaveFileIO.lua).

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local ModProfile = {}

ModProfile.EXT = ".g1rmodlist"
ModProfile.DIR = "profiles"
ModProfile.FORMAT = "g1rmodlist"
ModProfile.FORMAT_VERSION = 1

-- deterministic order; GameVersion.VERSIONS is a map, and a profile file has
-- to encode the same way twice for a diff to mean anything
local VERSION_ORDER = { "red", "blue", "yellow" }

local function fsOr(fs)
  return fs or (love and love.filesystem) or nil
end

-- Capture the live setup.  `available` is ManagerState.status.available (the
-- loader's status manifests, m.enabled = the desired set including staged
-- flips); `modOptions` is options.modOptions.
function ModProfile.capture(available, modOptions)
  local enabled, options = {}, {}
  for _, m in ipairs(available or {}) do
    enabled[m.id] = m.enabled and true or false
    local bucket = modOptions and modOptions[m.id]
    if type(bucket) == "table" then
      local copy = {}
      for k, v in pairs(bucket) do
        local t = type(v)
        if t == "string" or t == "number" or t == "boolean" then copy[k] = v end
      end
      options[m.id] = copy
    end
  end
  local slots = {}
  for _, id in ipairs(VERSION_ORDER) do
    local ok, slot = pcall(SaveData.activeSlot, id)
    if ok and slot then slots[id] = slot end
  end
  return { enabled = enabled, options = options, slots = slots }
end

-- The slot moves a profile may actually make: a slot id has to be registered
-- for that version already, because SaveData.setActiveSlot registers an
-- unknown id and would conjure a phantom slot the player never made.
function ModProfile.slotMoves(p)
  local moves = {}
  for _, version in ipairs(VERSION_ORDER) do
    local want = p.slots and p.slots[version]
    if want then
      local ok, list = pcall(SaveData.listSlots, version)
      if ok then
        for _, row in ipairs(list or {}) do
          if row.id == want then moves[#moves + 1] = { version, want } end
        end
      end
    end
  end
  return moves
end

-- ids the profile wants enabled that are not installed here.  Import cannot
-- fetch them (community-index install is deferred), so the manager reports
-- them rather than silently playing a different setup than the sharer's.
function ModProfile.missingIds(p, byId)
  local out = {}
  for id, on in pairs(p.enabled or {}) do
    if on and not (byId or {})[id] then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

function ModProfile.encode(p)
  return SaveSerializer.encode({
    format = ModProfile.FORMAT,
    formatVersion = ModProfile.FORMAT_VERSION,
    profile = { name = p.name, enabled = p.enabled,
                options = p.options, slots = p.slots },
  })
end

-- Shape-validate rather than trust: a shared file is untrusted input, and the
-- manager indexes p.enabled/p.options straight into its row models.
function ModProfile.decode(body)
  if type(body) ~= "string" then return nil, "EMPTY FILE" end
  local ok, data = pcall(SaveSerializer.decode, body)
  if not ok or type(data) ~= "table" then return nil, "BAD FILE" end
  if data.format ~= ModProfile.FORMAT then return nil, "NOT A MODLIST" end
  local raw = data.profile
  if type(raw) ~= "table" or type(raw.name) ~= "string" or raw.name == "" then
    return nil, "BAD FILE"
  end
  local p = { name = raw.name:sub(1, 10), enabled = {}, options = {}, slots = {} }
  for id, on in pairs(type(raw.enabled) == "table" and raw.enabled or {}) do
    if type(id) == "string" then p.enabled[id] = on and true or false end
  end
  for id, bucket in pairs(type(raw.options) == "table" and raw.options or {}) do
    if type(id) == "string" and type(bucket) == "table" then
      local copy = {}
      for k, v in pairs(bucket) do
        local t = type(v)
        if type(k) == "string" and (t == "string" or t == "number" or t == "boolean") then
          copy[k] = v
        end
      end
      p.options[id] = copy
    end
  end
  for version, slot in pairs(type(raw.slots) == "table" and raw.slots or {}) do
    if GameVersion.VERSIONS[version] and type(slot) == "string" then
      p.slots[version] = slot
    end
  end
  return p
end

-- profiles/<NAME>.g1rmodlist; letters, digits and dashes only so a shared
-- name can never escape the folder
local function fileFor(name)
  return ModProfile.DIR .. "/" ..
    tostring(name):upper():gsub("[^%w%-]", "_") .. ModProfile.EXT
end
ModProfile.fileFor = fileFor

function ModProfile.export(p, fs)
  fs = fsOr(fs)
  if not (fs and fs.write) then return false, "NO FILESYSTEM" end
  if fs.createDirectory then fs.createDirectory(ModProfile.DIR) end
  local rel = fileFor(p.name)
  local ok, err = fs.write(rel, ModProfile.encode(p))
  if not ok then return false, tostring(err) end
  local base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
  if base ~= "" then return true, base .. "/" .. rel end
  return true, rel
end

-- every .g1rmodlist sitting in profiles/, sorted, as relative paths
function ModProfile.files(fs)
  fs = fsOr(fs)
  local out = {}
  if not (fs and fs.getDirectoryItems) then return out end
  if fs.getInfo and not fs.getInfo(ModProfile.DIR) then return out end
  for _, name in ipairs(fs.getDirectoryItems(ModProfile.DIR) or {}) do
    if name:sub(-#ModProfile.EXT) == ModProfile.EXT then
      out[#out + 1] = ModProfile.DIR .. "/" .. name
    end
  end
  table.sort(out)
  return out
end

-- Read one export and land it in `profiles` (options.modProfiles) under a
-- non-colliding name, so importing twice never overwrites what the player
-- already tuned.  Returns the stored record, or nil + a short reason.
function ModProfile.import(path, profiles, fs)
  fs = fsOr(fs)
  if not (fs and fs.read) then return nil, "NO FILESYSTEM" end
  local p, err = ModProfile.decode(fs.read(path))
  if not p then return nil, err end
  local taken = {}
  for _, existing in ipairs(profiles) do taken[existing.name] = true end
  local name, n = p.name, 1
  while taken[name] do
    n = n + 1
    name = (p.name:sub(1, 8) .. n)
  end
  p.name = name
  profiles[#profiles + 1] = p
  return p
end

-- First run after this update: the setup the player already has becomes
-- PROFILE 1, then they can add more (#593).  Seeded once and remembered by
-- options.modProfilesSeeded, so deleting every profile does not resurrect it.
function ModProfile.ensureFirst(opts, available, modOptions)
  if opts.modProfilesSeeded then return nil end
  opts.modProfilesSeeded = true
  opts.modProfiles = opts.modProfiles or {}
  if #opts.modProfiles > 0 then return nil end
  local p = ModProfile.capture(available, modOptions)
  p.name = "PROFILE 1"
  opts.modProfiles[1] = p
  opts.activeProfile = p.name
  return p
end

return ModProfile

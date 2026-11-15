local T = require("tests.harness")
local Contract = require("src.import.CacheContract")
local Version = require("src.core.GameVersion")

local files = {}
local fs = { prefix = "caller/" }
function fs.exists(path) return files[fs.prefix .. path] ~= nil end
function fs.read(path) return files[fs.prefix .. path] end
function fs.write(path, value) files[fs.prefix .. path] = value; return true end
function fs.remove(path) files[fs.prefix .. path] = nil; return true end

for _, version in ipairs({ "crystal", "gold", "silver" }) do
  for _, path in ipairs(Contract.requiredFiles(version)) do
    files[Version.cachePrefix(version) .. path] = "fixture"
  end
end

for _, revision in ipairs(Version.revisions("crystal")) do
  files["crystal/" .. Contract.MARKER_PATH] = "rom-cache-v13-crystal5:" .. revision.sha1
  T.check(not Contract.isReady("crystal", fs), "old Crystal marker rejects category-less " .. revision.sha1)
  files["crystal/" .. Contract.MARKER_PATH] = Contract.markerFor("crystal", revision.sha1)
  T.check(Contract.isReady("crystal", fs), "complete new Crystal cache accepts " .. revision.sha1)
  local events = files["crystal/data/generated/events.lua"]
  files["crystal/data/generated/events.lua"] = nil
  T.check(not Contract.isReady("crystal", fs), "missing password producer prevents readiness")
  local published, err = Contract.publish("crystal", fs, revision.sha1)
  T.check(not published and tostring(err):find("events.lua", 1, true), "missing password producer prevents publication")
  T.check(files["crystal/" .. Contract.MARKER_PATH] == nil, "failed publication removes stale marker")
  files["crystal/data/generated/events.lua"] = events
  T.check(Contract.publish("crystal", fs, revision.sha1), "complete password producer publishes")
end

for _, version in ipairs({ "gold", "silver" }) do
  T.check(not Contract.formatFor(version):find("crystal", 1, true), version .. " marker has no Crystal password category")
  files[Version.cachePrefix(version) .. Contract.MARKER_PATH] = Contract.markerFor(version)
  T.check(Contract.isReady(version, fs), version .. " is ready with its events.lua")
  files[Version.cachePrefix(version) .. "data/generated/events.lua"] = nil
  T.check(not Contract.isReady(version, fs), version .. " without events.lua (MagikarpLengths) is not ready")
end
T.eq(fs.prefix, "caller/", "all publication probes restore filesystem prefix")
T.finish("Crystal Buena cache #2639")

-- RomManifest is the extraction worker's trust boundary: it must reject a
-- missing, malformed, or wrong-version manifest before any ROM is decoded.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("rom manifest")
local Json = require("src.link.Json")
local GameVersion = require("src.core.GameVersion")

love = love or require("tests.love_stub")
local oldRead = love.filesystem.read
local info = GameVersion.info("red")

local function loadWith(body, readErr)
  love.filesystem.read = function(path)
    T.eq(path, info.manifest, "decoder reads the selected version manifest")
    return body, readErr
  end
  package.loaded["src.import.RomManifest"] = nil
  return require("src.import.RomManifest")
end

local valid = { romSha1 = info.sha1, symbols = { Start = 256 } }
local manifest = loadWith(Json.encode(valid)).decode("red")
T.eq(manifest.romSha1, info.sha1, "matching manifest is accepted")
T.eq(manifest.symbols.Start, 256, "decoded manifest fields are preserved")

local missing = loadWith(nil, "not found")
local okMissing, missingErr = pcall(missing.decode, "red")
T.check(not okMissing and tostring(missingErr):find("metadata is missing", 1, true),
  "missing manifest is rejected with context")
T.check(tostring(missingErr):find("not found", 1, true),
  "missing-file error retains the filesystem cause")

local malformed = loadWith("{ definitely not json")
local okMalformed, malformedErr = pcall(malformed.decode, "red")
T.check(not okMalformed and tostring(malformedErr):find("metadata is invalid", 1, true),
  "malformed JSON is rejected before extraction")

local mismatch = loadWith(Json.encode({ romSha1 = "wrong-sha1" }))
local okMismatch, mismatchErr = pcall(mismatch.decode, "red")
T.check(not okMismatch and tostring(mismatchErr):find("version mismatch", 1, true),
  "a manifest for the wrong ROM version is rejected")

love.filesystem.read = oldRead
package.loaded["src.import.RomManifest"] = nil
T.finish()

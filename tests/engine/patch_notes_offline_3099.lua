package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Platform = require("src.core.Platform")
local PatchNotes = require("src.update.PatchNotes")

local savedVersion = package.loaded["src.core.Version"]
local savedHostShell = package.loaded["src.core.HostShell"]
local savedGetOS = love.system.getOS
local savedFiles, savedRepo = PatchNotes.FILES, PatchNotes.REPO_FILES

local REPO = os.tmpname()
do
  local f = assert(io.open(REPO, "wb"))
  f:write('{"apps":[{"versions":[{"version":"0.3.98","localizedDescription":"older notes"}]}]}')
  f:close()
end

local fetch = true
package.loaded["src.core.HostShell"] = { canFetch = function() return fetch end }
package.loaded["src.core.Version"] = { engine = "0.3.99" }
PatchNotes.REPO_FILES = { REPO }
PatchNotes.FILES = { "PATCH_NOTES.md" }
love.filesystem.remove("updates/notes_cache.json")
love.filesystem.remove("PATCH_NOTES.md")
local idle = { state = function() return { status = "idle" } end }

local function onOS(name)
  love.system.getOS = function() return name end
  Platform._resetForTests()
end

onOS("NX")
local body, ver = PatchNotes.body(idle)
eq(ver, "0.3.99", "A: the modal is titled with the installed version")
check(body ~= "Unable to fetch patch notes.",
  "A: a Switch build with nothing bundled does not claim a fetch failed")
check(body:find("cannot check GitHub", 1, true) ~= nil,
  "A: it says the platform cannot check GitHub")
check(body:find("github.com/bryanthaboi/gen1recomp/releases", 1, true) ~= nil,
  "A: and names where the release notes are")
check(body:find("older notes", 1, true) == nil,
  "A: the previous release's stashed notes are not shown under this version")

love.filesystem.write("PATCH_NOTES.md", "## Issues closed\n\n- #3099 switch notes")
body, ver = PatchNotes.body(idle)
eq(body, "## Issues closed\n\n- #3099 switch notes", "B: packed notes win on Switch")
eq(ver, "0.3.99", "B: under the installed version")
love.filesystem.remove("PATCH_NOTES.md")

love.filesystem.createDirectory("updates")
love.filesystem.write("updates/notes_cache.json", '{"0.3.98":"cached 0.3.98 notes"}')
love.filesystem.write("PATCH_NOTES.md", "bundled 0.3.99 notes")
body, ver = PatchNotes.body(idle)
eq(body, "bundled 0.3.99 notes", "D: notes packed with this install beat a cache stashed for an older release")
eq(ver, "0.3.99", "D: under the installed version")
love.filesystem.write("updates/notes_cache.json", '{"0.3.98":"cached 0.3.98 notes","0.3.99":"cached 0.3.99 notes"}')
body, ver = PatchNotes.body(idle)
eq(body, "cached 0.3.99 notes", "D: a cache entry for the installed version still wins")
eq(ver, "0.3.99", "D: under the installed version")
love.filesystem.remove("PATCH_NOTES.md")
love.filesystem.write("updates/notes_cache.json", '{"0.3.98":"cached 0.3.98 notes"}')
body, ver = PatchNotes.body(idle)
eq(body, "cached 0.3.98 notes", "D: with nothing packed the older cache is still the fallback")
eq(ver, "0.3.98", "D: titled with the cached version")
love.filesystem.remove("updates/notes_cache.json")

onOS("OS X")
fetch = true
body = PatchNotes.body(idle)
eq(body, "Unable to fetch patch notes.", "a desktop that can fetch keeps the fetch-failure line")
fetch = false
body = PatchNotes.body(idle)
check(body:find("cannot check GitHub", 1, true) ~= nil,
  "a desktop with no transport gets the offline line")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function jobBlock(yml, job)
  local start = yml:find("\n  " .. job:gsub("%-", "%%-") .. ":\n", 1)
  if not start then return nil end
  local stop = yml:find("\n  [%w_%-]+:\n", start + 1)
  return yml:sub(start, stop or #yml)
end

local release = read(".github/workflows/release.yml")
for _, job in ipairs({ "love-payload", "switch", "android", "ios", "ps4", "rg34xxsp", "linux-arm-sbc" }) do
  local blk = jobBlock(release, job)
  check(blk ~= nil, "C: release.yml has a " .. job .. " job")
  blk = blk or ""
  local needs = blk:match("\n    needs: ([^\n]+)") or ""
  check(needs:find("%f[%w]notes%f[^%w]") ~= nil, "C: " .. job .. " needs notes (got " .. needs .. ")")
  check(blk:find("!cancelled() && needs.version.result == 'success'", 1, true) ~= nil,
    "C: " .. job .. " still runs when notes is skipped but stops on a failed version")
  check(blk:find("name: gen1recomp-release-notes", 1, true) ~= nil,
    "C: " .. job .. " downloads the release notes artifact")
  check(blk:find("release-notes.md PATCH_NOTES.md", 1, true) ~= nil,
    "C: " .. job .. " stages them as PATCH_NOTES.md before packing")
end
local notesJob = jobBlock(release, "notes") or ""
check(notesJob:find("\n    if:", 1, true) == nil,
  "C: the notes job runs wherever the packing jobs do")

for _, script in ipairs({ "scripts/pack_love.sh", "scripts/build_ios.sh", "scripts/build_android.sh",
                          "build-rg34xxsp.sh", "build-linux-arm-sbc.sh" }) do
  check(read(script):find("PATCH_NOTES.md", 1, true) ~= nil, "C: " .. script .. " packs PATCH_NOTES.md")
end

os.remove(REPO)
PatchNotes.FILES, PatchNotes.REPO_FILES = savedFiles, savedRepo
package.loaded["src.core.Version"] = savedVersion
package.loaded["src.core.HostShell"] = savedHostShell
love.system.getOS = savedGetOS
Platform._resetForTests()

T.finish("patch notes offline (#3099)")

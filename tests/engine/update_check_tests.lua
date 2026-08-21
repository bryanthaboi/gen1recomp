-- Pure-surface coverage for src/update/Check.lua (the self-update release
-- check / payload download module).  The network, hashing and archive-probe
-- logic lives in src/update/check_worker.lua and needs love + curl; these are
-- the love-free extraction/parsing seams the worker and UI both trust.
--   luajit tests/engine/update_check_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Check = require("src.update.Check")
local Json = require("src.link.Json")

-- releaseUrl is the fixed public landing page the UI links on needs_full
eq(Check.releaseUrl(),
   "https://github.com/bryanthaboi/gen1recomp/releases/latest",
   "releaseUrl points at the repo's latest release")

-- parseRelease: a well-formed release with the .love payload and its sums
local body = Json.encode({
  tag_name = "v1.4.2",
  assets = {
    { name = "gen1recomp-1.4.2-macos.zip", browser_download_url = "http://x/mac", size = 10 },
    { name = "gen1recomp-1.4.2.love", browser_download_url = "http://x/love", size = 12345 },
    { name = "sha256sums.txt", browser_download_url = "http://x/sums", size = 99 },
  },
})
local rel = Check.parseRelease(body)
check(rel ~= nil, "parseRelease accepts a valid release")
eq(rel.version, "1.4.2", "leading v stripped from tag_name")
eq(rel.payloadName, "gen1recomp-1.4.2.love", "payload name derived from version")
eq(rel.payload.url, "http://x/love", "payload asset url picked")
eq(rel.payload.size, 12345, "payload asset size picked")
eq(rel.sums.url, "http://x/sums", "sums asset url picked")
eq(rel.notes, "", "missing release body becomes empty notes")

-- Native package assets are target-specific. This is intentionally separate
-- from the generic .love payload, which a new shell may be unable to host.
local android = Check.parseRelease(body, nil, { os = "Android", arch = "arm64" })
eq(android.fullName, "gen1recomp-1.4.2-android.apk", "Android package name derived")
eq(android.full, nil, "missing Android package is surfaced as nil")
eq(Check.fullAssetName("1.4.2", "Android", "arm64"),
  "gen1recomp-1.4.2-android.apk", "Android full asset mapping")
eq(Check.fullAssetName("1.4.2", "Linux", "aarch64"),
  "gen1recomp-1.4.2-linux-arm64.AppImage", "Linux ARM package mapping")
eq(Check.fullAssetName("1.4.2", "iOS", "arm64"),
  "gen1recomp++-1.4.2-ios.ipa", "iOS package mapping")
eq(Check.fullAssetName("not-a-version", "Android", "arm64"), nil,
  "invalid full-package version rejected")

local withNotes = Check.parseRelease(Json.encode({
  tag_name = "v1.4.2",
  body = "## Issues closed\n\n- #1 cart padding",
  assets = {},
}))
eq(withNotes.notes, "## Issues closed\n\n- #1 cart padding",
  "parseRelease keeps the GitHub release body")

-- a newer release that ships no .love yet: parses, but the payload/sums are nil
-- so the worker will route to needs_full rather than an in-place update
local noPayload = Check.parseRelease(Json.encode({ tag_name = "2.0.0", assets = {} }))
check(noPayload ~= nil, "parseRelease accepts a payload-less release")
eq(noPayload.version, "2.0.0", "version parsed without assets")
eq(noPayload.payload, nil, "no payload asset -> nil")
eq(noPayload.sums, nil, "no sums asset -> nil")

-- rejects: non-semver tag, and a document with no tag at all
local bad, badErr = Check.parseRelease(Json.encode({ tag_name = "nightly" }))
eq(bad, nil, "non-X.Y.Z tag rejected")
check(badErr ~= nil, "rejection carries an error string")
eq(Check.parseRelease(Json.encode({ foo = 1 })), nil, "missing tag_name rejected")

-- Network failures can return a plain-text or HTML body instead of JSON. The
-- launcher must describe that response rather than leaking the decoder's
-- low-level "unexpected character 'E'" assertion.
do
  local release, err = Check.parseRelease("Error: API rate limit exceeded")
  check(release == nil and tostring(err):find("not JSON", 1, true) ~= nil,
    "plain-text update failure is reported as non-JSON")
  release, err = Check.parseRelease("<!DOCTYPE html><html>502 Bad Gateway</html>")
  check(release == nil and tostring(err):find("HTML", 1, true) ~= nil,
    "HTML update failure is identified")
  check(tostring(err):find("unexpected character", 1, true) == nil,
    "decoder assertion is not exposed")
end

-- parseSums: shasum -a 256 format, tolerating the '*' binary marker, a './'
-- prefix and CRLF line endings; unrelated lines are skipped
local sums =
  "aaaa1111  gen1recomp-1.4.2.love\n" ..
  "BBBB2222 *./sha256sums.txt\r\n" ..
  "not a checksum line\n"
local map = Check.parseSums(sums)
eq(map["gen1recomp-1.4.2.love"], "aaaa1111", "bare-name sum parsed")
eq(map["sha256sums.txt"], "bbbb2222", "* marker and ./ prefix stripped, lowered")
eq(Check.parseSums(sums, "gen1recomp-1.4.2.love"), "aaaa1111", "targeted lookup returns the hash")
eq(Check.parseSums(sums, "missing.love"), nil, "targeted lookup misses cleanly")

-- pickAsset guards a non-table assets field
eq(Check.pickAsset(nil, "x"), nil, "pickAsset tolerates a nil asset list")

T.finish("update_check")

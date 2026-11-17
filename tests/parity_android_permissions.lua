-- #287: the Android build must ship android.permission.INTERNET, or every
-- link-play socket dies with EPERM before it reaches the network.  The
-- permission is declared in the tracked manifest and scripts/build_android.sh
-- rewrites that same file on every build, so both halves are asserted here
-- plus a replay of the real trim over the real manifest.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("android link permissions")
local check, eq = S.check, S.eq

local MANIFEST = "mobile/android/app/src/main/AndroidManifest.xml"
local SCRIPT = "scripts/build_android.sh"
local INTERNET = "android.permission.INTERNET"

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function writeFile(path, body)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(body)
  f:close()
  return true
end

local manifest = readFile(MANIFEST)
local script = readFile(SCRIPT)
check(type(manifest) == "string", MANIFEST .. " is readable")
check(type(script) == "string", SCRIPT .. " is readable")

-- ---------------------------------------------------------------- the two files
-- The trim is only dangerous because it edits the tracked manifest in place; if
-- that stops being true, everything below tests a file the build never touches.
if script then
  -- The script has grown other `local manifest=` locals (the Yellow ROM
  -- import manifest recovery), so scan every assignment for the one that
  -- names the Android manifest instead of trusting the first match.
  local target
  for candidate in script:gmatch('local manifest="([^"]+)"') do
    if candidate:find("AndroidManifest.xml", 1, true) then
      target = candidate
      break
    end
  end
  check(target ~= nil, "build_android.sh names the manifest it rewrites")
  check(target ~= nil
          and target:find("app/src/main/AndroidManifest.xml", 1, true) ~= nil,
        "the per-build permission trim rewrites the checked-in manifest, so"
        .. " both halves of #287 have to hold at once")
end

if manifest then
  check(manifest:find(INTERNET, 1, true) ~= nil,
        "the manifest declares INTERNET (link play cannot open a socket"
        .. " without it -- #287)")
  check(manifest:find("android.permission.VIBRATE", 1, true) ~= nil,
        "VIBRATE is still declared (love.system.vibrate)")
  check(manifest:find("android.permission.BLUETOOTH", 1, true) ~= nil,
        "BLUETOOTH is still declared (optional gamepads)")
end

-- Read the python tuple only, never the comment around it: that comment now
-- mentions INTERNET on purpose, and matching it would pass for the wrong reason.
if script then
  local tuple = script:match("for perm in %((.-)%):")
  check(tuple ~= nil, "build_android.sh still has a permission strip list")
  if tuple then
    check(tuple:find("INTERNET", 1, true) == nil,
          "the strip list no longer deletes INTERNET (#287)")
    check(tuple:find("RECORD_AUDIO", 1, true) ~= nil,
          "RECORD_AUDIO is still stripped (the game records no audio)")
    check(tuple:find("WRITE_EXTERNAL_STORAGE", 1, true) == nil,
          "the strip list keeps WRITE_EXTERNAL_STORAGE (Storage Folder on Android 10 and older)")
  end
end

-- ---------------------------------------------------------------- the real trim
-- Run the build's own python block over a copy of the real manifest and look at
-- what an APK would carry.  Skipped with a note, not a failure, where python3
-- is missing (the build needs python3 anyway).
local function haveCommand(name)
  local probe = io.popen("command -v " .. name .. " 2>/dev/null")
  if not probe then return false end
  local out = probe:read("*a")
  probe:close()
  return out ~= nil and out:match("%S") ~= nil
end

if manifest and script and haveCommand("python3") then
  local block = script:match("python3 %- \"%$manifest\" <<'PY'\n(.-)\nPY\n")
  check(block ~= nil, "the manifest trim is a python heredoc we can replay")
  if block then
    local tmpDir = (os.getenv("TMPDIR") or "/tmp"):gsub("[/\\]+$", "")
    local stamp = ("%d_%d"):format(os.time(), math.random(1, 999999))
    local pyPath = tmpDir .. "/pokeport_bug287_trim_" .. stamp .. ".py"
    local xmlPath = tmpDir .. "/pokeport_bug287_manifest_" .. stamp .. ".xml"
    local wrotePy = writeFile(pyPath, block .. "\n")
    local wroteXml = writeFile(xmlPath, manifest)
    check(wrotePy and wroteXml, "staged the trim and a manifest copy in " .. tmpDir)
    if wrotePy and wroteXml then
      os.execute(('python3 "%s" "%s"'):format(pyPath, xmlPath))
      local trimmed = readFile(xmlPath) or ""
      check(trimmed:find(INTERNET, 1, true) ~= nil,
            "INTERNET survives a real build's permission trim -- the APK can"
            .. " bind and connect (#287)")
      check(trimmed:find("RECORD_AUDIO", 1, true) == nil,
            "the trim still drops RECORD_AUDIO")
      check(trimmed:find("WRITE_EXTERNAL_STORAGE", 1, true) ~= nil,
            "the trim keeps WRITE_EXTERNAL_STORAGE (Storage Folder on Android 10 and older)")
      check(trimmed:find("android.permission.VIBRATE", 1, true) ~= nil,
            "the trim keeps VIBRATE")
      check(trimmed:find("android.permission.BLUETOOTH", 1, true) ~= nil,
            "the trim keeps BLUETOOTH")
      check(trimmed:find("usesCleartextTraffic", 1, true) == nil,
            "the trim still removes usesCleartextTraffic (it gates Android's"
            .. " own HTTP stacks, never the raw sockets link play uses)")
      -- a trim that kept INTERNET but broke the XML fails later, at merge time
      local parsed = os.execute(('python3 -c "import sys,xml.etree.ElementTree'
        .. ' as E; E.parse(sys.argv[1])" "%s" >/dev/null 2>&1'):format(xmlPath))
      check(parsed == 0 or parsed == true,
            "the trimmed manifest is still well-formed XML")
      os.remove(pyPath)
      os.remove(xmlPath)
    end
  end
else
  print("[#287] python3 not found: replaying the real trim was skipped,"
    .. " the static checks above still ran")
end

S.finish()

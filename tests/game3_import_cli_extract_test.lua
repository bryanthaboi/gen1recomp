package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("game3 cli_extract cache root")
local check = S.check

local function sh(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run(env, args)
  local cmd = "env -u POKEPORT_IDENTITY -u GBA_CACHE_ROOT -u XDG_DATA_HOME " .. env
    .. " luajit src/import/gba/cli_extract.lua " .. args .. " 2>&1; echo EXIT=$?"
  local pipe = io.popen(cmd)
  if not pipe then return "", nil end
  local out = pipe:read("*a") or ""
  pipe:close()
  return out, tonumber(out:match("EXIT=(%d+)%s*$"))
end

local probe = io.popen("luajit -v 2>&1")
local pv = probe and probe:read("*a") or ""
if probe then probe:close() end
if not pv:find("LuaJIT", 1, true) then
  check(true, "luajit not on PATH : SKIP")
  S.finish()
  return
end

local tmp = os.getenv("TMPDIR") or "/tmp/"
if tmp:sub(-1) ~= "/" then tmp = tmp .. "/" end
tmp = tmp .. "cli-extract-test-" .. tostring(os.time())
local home = tmp .. "/home"
local rom = tmp .. "/missing.gba"

local function cacheLine(out)
  return out:match("CacheFS:\t([^\n]*)")
end

local function saveDir(identity)
  local os_ = jit and jit.os or "Linux"
  if os_ == "OSX" then return home .. "/Library/Application Support/LOVE/" .. identity end
  if os_ == "Windows" then return (os.getenv("APPDATA") or (home .. "/AppData/Roaming")) .. "/LOVE/" .. identity end
  return home .. "/.local/share/love/" .. identity
end

do
  local out, code = run("HOME=" .. sh(home), "--items " .. sh(rom))
  S.eq(code, 2, "no cache root and no identity exits 2")
  check(out:find("usage:", 1, true) ~= nil, "no cache root prints usage")
  check(cacheLine(out) == nil, "no cache root never picks a CacheFS dir")
  check(not out:find("pokemon-love2d", 1, true), "no cache root never names the owner identity")
end

do
  local out, code = run("HOME=" .. sh(home), "--help")
  S.eq(code, 0, "--help exits 0")
  check(out:find("usage:", 1, true) ~= nil, "--help prints usage")
end

do
  local out = run("HOME=" .. sh(home) .. " POKEPORT_IDENTITY=cli-probe", "--items " .. sh(rom))
  S.eq(cacheLine(out), saveDir("cli-probe") .. "/firered/data/generated/gba",
    "POKEPORT_IDENTITY resolves to that identity's firered dir")
end

do
  local out = run("HOME=" .. sh(home) .. " POKEPORT_IDENTITY=cli-probe",
    "--cache " .. sh(tmp .. "/explicit") .. " --items " .. sh(rom))
  S.eq(cacheLine(out), tmp .. "/explicit/data/generated/gba", "--cache wins over POKEPORT_IDENTITY")
end

do
  local out = run("HOME=" .. sh(home) .. " GBA_CACHE_ROOT=" .. sh(tmp .. "/envroot"), "--pokemon " .. sh(rom))
  S.eq(cacheLine(out), tmp .. "/envroot/data/generated/gba", "GBA_CACHE_ROOT is honored")
end

do
  local f = assert(io.open("src/import/gba/cli_extract.lua", "rb"))
  local src = f:read("*a")
  f:close()
  check(not src:find("pokemon-love2d", 1, true), "cli_extract has no owner-identity default")
end

S.finish()

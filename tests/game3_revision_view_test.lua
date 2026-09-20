#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Base64 = require("src.core.Base64")
local RevisionView = require("src.import.gba.revision_view")
local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")

local REV1 = "dd5945db9b930750cb39d00c84da8571feebf417"
local BASE = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"

local function le32(v)
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

print("[test] 1. synthetic revision")
do
  local base = "AAAA" .. le32(0x08000010) .. "BBBBBBBB" .. "CCCC" .. le32(0x08000004) .. "DDDD" .. "EEEE"
  local rev = "AAAA" .. le32(0x08000014) .. "xxxx" .. "BBBBBBBB" .. "CCCC" .. le32(0x08000004) .. "EEEE"
  local spec = {
    segments = { { 0, 0 }, { 8, 4 }, { 28, 0 } },
    siteCount = 1,
    sites = Base64.encode(string.char(4)),
  }
  local view = RevisionView.build(rev, spec)
  eq(#view, #rev, "view keeps the ROM size")
  eq(view:sub(1, 24), base:sub(1, 24), "layout and moved pointer match the base")
  eq(view:sub(29), base:sub(29), "tail segment is unshifted")
end

print("[test] 2. identity")
eq(GameVersion.forSha1(REV1), "firered", "1.1 belongs to firered")
eq(GameVersion.revisionLabel("firered", REV1), "1.1", "1.1 label")
eq(GameVersion.revisionLabel("firered", BASE), "1.0", "1.0 label")
check(Versions.lookup(REV1) == Versions.lookup(BASE), "1.1 reuses the 1.0 pointer table")
check(RevisionView.forSha1(BASE) == nil, "1.0 needs no view")
eq(RevisionView.apply("rom", BASE), "rom", "1.0 data passes through")

print("[test] 3. generated table")
do
  local spec = RevisionView.forSha1(REV1)
  eq(spec.base, BASE, "table base")
  eq(spec.sha1, REV1, "table revision")
  local prev = -1
  local ordered = true
  for _, seg in ipairs(spec.segments) do
    if seg[1] <= prev then ordered = false end
    prev = seg[1]
  end
  check(ordered, "segments ascend")
  eq(spec.segments[#spec.segments][2], 0, "tail segment is unshifted")
end

print("[test] 4. pret builds")
do
  local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  local root = os.getenv("POKEFIRERED") or "../pokefirered"
  local a, b = slurp(root .. "/pokefirered.gba"), slurp(root .. "/pokefirered_rev1.gba")
  if not (a and b) then
    print("[skip] no pret builds under " .. root)
  else
    local view = RevisionView.apply(b, REV1)
    eq(#view, #a, "view size")
    local dataDiff = 0
    for i = 0x1E0000 + 1, #a do
      if a:byte(i) ~= view:byte(i) then dataDiff = dataDiff + 1 end
    end
    check(dataDiff <= 300, "data region matches 1.0 outside reworded text (" .. dataDiff .. " bytes)")
  end
end

if failed > 0 then
  print(failed .. " failed")
  os.exit(1)
end
print("all passed")

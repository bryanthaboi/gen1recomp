local Base64 = require("src.core.Base64")

local RevisionView = {}

local ROM_BASE = 0x08000000
local ROM_END = 0x09000000

local MODULES = {
  ["dd5945db9b930750cb39d00c84da8571feebf417"] = "src.import.gba.revisions.firered_1_1",
}

local byImports = setmetatable({}, { __mode = "k" })

function RevisionView.forSha1(sha1)
  if type(sha1) ~= "string" then return nil end
  local name = MODULES[sha1:lower()]
  if not name then return nil end
  return require(name)
end

local function toBase(segments, revOffset)
  local delta = 0
  for i = 1, #segments do
    local seg = segments[i]
    if seg[1] + seg[2] > revOffset then break end
    delta = seg[2]
  end
  return revOffset - delta
end

local function siteOffsets(rev)
  local blob = assert(Base64.decode(rev.sites))
  local out, n = {}, 0
  local pos, value, shift = 0, 0, 1
  for i = 1, #blob do
    local b = blob:byte(i)
    if b >= 0x80 then
      value = value + (b - 0x80) * shift
      shift = shift * 128
    else
      pos = pos + value + b * shift
      n = n + 1
      out[n] = pos
      value, shift = 0, 1
    end
  end
  assert(n == rev.siteCount, "revision site table is damaged")
  return out
end

function RevisionView.build(romData, rev)
  local segments = rev.segments
  local size = #romData
  local parts = {}
  for i = 1, #segments do
    local start, delta = segments[i][1], segments[i][2]
    local stop = segments[i + 1] and segments[i + 1][1] or size
    parts[i] = romData:sub(start + delta + 1, stop + delta)
  end
  local layout = table.concat(parts)
  assert(#layout == size, "revision layout does not cover the ROM")

  local out, n, cursor = {}, 0, 0
  local char, floor = string.char, math.floor
  for _, site in ipairs(siteOffsets(rev)) do
    local b0, b1, b2, b3 = layout:byte(site + 1, site + 4)
    local ptr = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    if ptr >= ROM_BASE and ptr < ROM_END then
      local fixed = toBase(segments, ptr - ROM_BASE)
      out[n + 1] = layout:sub(cursor + 1, site)
      out[n + 2] = char(fixed % 256, floor(fixed / 256) % 256, floor(fixed / 65536) % 256, 0x08)
      n = n + 2
      cursor = site + 4
    end
  end
  out[n + 1] = layout:sub(cursor + 1)
  return table.concat(out)
end

function RevisionView.apply(romData, sha1)
  local rev = RevisionView.forSha1(sha1)
  if not rev then return romData end
  return RevisionView.build(romData, rev)
end

function RevisionView.forImports(imports, importId, info)
  local rev = RevisionView.forSha1(info.md5)
  if not rev then return nil end
  local cached = byImports[imports]
  if cached then return cached end
  local chunk = 4 * 1024 * 1024
  local parts = {}
  for offset = 0, info.size - 1, chunk do
    local data, err = imports:read(importId, offset, math.min(chunk, info.size - offset))
    if not data then error(err or "rom read failed") end
    parts[#parts + 1] = data
  end
  local view = RevisionView.build(table.concat(parts), rev)
  byImports[imports] = view
  return view
end

return RevisionView

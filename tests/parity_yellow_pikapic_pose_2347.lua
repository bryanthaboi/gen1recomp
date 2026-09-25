package.path = "./?.lua;./?/init.lua;" .. package.path

local CacheContract = require("src.import.CacheContract")

local LABELS = {
  "e4841", "e4ce0", "e4e70", "e50af", "e52fe", "e5541", "e5794", "e59ed",
  "e5c4d", "e5e90", "e6020", "e61b0", "e63f7", "e6646", "e682f", "e69bf",
  "e6b4f", "e6cdf", "e6e6f", "e6fff", "e718f", "e731f", "e74af", "e763f",
  "e7863", "e79f3", "e7b83", "e7d13", "f0b64", "f0d82",
}

local function skip(why)
  print("[skip] parity_yellow_pikapic_pose_2347: " .. why)
  os.exit(0)
end

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local required = {}
for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES.yellow) do
  required[path] = true
end
local missingContract = {}
for _, label in ipairs(LABELS) do
  local path = "assets/generated/pikachu/gfx_" .. label .. ".png"
  if not required[path] then missingContract[#missingContract + 1] = path end
end
if #missingContract > 0 then
  error("VERSION_REQUIRED_FILES.yellow is missing " .. table.concat(missingContract, " "))
end

local function cacheRoot()
  local env = os.getenv("YELLOW_CACHE")
  if env and env ~= "" then return env end
  local home = os.getenv("HOME") or ""
  local identity = os.getenv("POKEPORT_IDENTITY")
  local names = {}
  if identity and identity ~= "" then names[#names + 1] = identity end
  names[#names + 1] = "pokemon-love2d"
  for _, name in ipairs(names) do
    for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
      local root = base .. "/" .. name .. "/yellow"
      local marker = readAll(root .. "/rom-cache.complete")
      if marker and marker:sub(1, #CacheContract.VERSION_FORMAT.yellow)
          == CacheContract.VERSION_FORMAT.yellow then
        return root
      end
    end
  end
end

local root = cacheRoot()
if not root then skip("no current Yellow cache") end
local PRET = "../pokeyellow/gfx/pikachu"
if not readAll(PRET .. "/unknown_e79f3.png") then skip("no ../pokeyellow checkout") end

local okFfi, ffi = pcall(require, "ffi")
if not okFfi then skip("no ffi") end
pcall(ffi.cdef, [[
int uncompress(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen);
]])
local zlib
for _, name in ipairs({ "z", "libz.so.1", "libz.1.dylib" }) do
  local ok, lib = pcall(ffi.load, name)
  if ok then zlib = lib break end
end
if not zlib then skip("no zlib") end

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function paeth(a, b, c)
  local p = a + b - c
  local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
  if pa <= pb and pa <= pc then return a end
  if pb <= pc then return b end
  return c
end

local function decodeShades(path)
  local data = assert(readAll(path), path)
  assert(data:sub(1, 8) == "\137PNG\r\n\26\n", path .. " is not a png")
  local pos, idat = 9, {}
  local width, height, depth, colorType, interlace
  while pos <= #data do
    local len = be32(data, pos)
    local kind = data:sub(pos + 4, pos + 7)
    local body = data:sub(pos + 8, pos + 7 + len)
    if kind == "IHDR" then
      width, height = be32(body, 1), be32(body, 5)
      depth, colorType, interlace = body:byte(9), body:byte(10), body:byte(13)
    elseif kind == "IDAT" then
      idat[#idat + 1] = body
    end
    pos = pos + 12 + len
  end
  assert(interlace == 0, path .. " is interlaced")
  local channels = ({ [0] = 1, [2] = 3, [4] = 2, [6] = 4 })[colorType]
  assert(channels and (colorType == 0 or depth == 8),
    ("%s: unsupported png type %d depth %d"):format(path, colorType, depth))
  local bitsPerPixel = channels * depth
  local stride = math.ceil(width * bitsPerPixel / 8)
  local bpp = math.max(1, bitsPerPixel / 8)
  local src = table.concat(idat)
  local outLen = height * (stride + 1)
  local out = ffi.new("uint8_t[?]", outLen)
  local destLen = ffi.new("unsigned long[1]", outLen)
  assert(zlib.uncompress(out, destLen, src, #src) == 0, path .. ": inflate failed")
  local rows, prev = {}, {}
  for x = 1, stride do prev[x] = 0 end
  for y = 0, height - 1 do
    local base = y * (stride + 1)
    local filter = out[base]
    local row = {}
    for x = 1, stride do
      local raw = out[base + x]
      local left = x > bpp and row[x - bpp] or 0
      local up = prev[x]
      local upLeft = x > bpp and prev[x - bpp] or 0
      local v
      if filter == 0 then v = raw
      elseif filter == 1 then v = raw + left
      elseif filter == 2 then v = raw + up
      elseif filter == 3 then v = raw + math.floor((left + up) / 2)
      elseif filter == 4 then v = raw + paeth(left, up, upLeft)
      else error(path .. ": bad filter " .. filter) end
      row[x] = v % 256
    end
    rows[y + 1] = row
    prev = row
  end
  local shades = {}
  local maxGray = 2 ^ depth - 1
  for y = 1, height do
    local row = rows[y]
    for x = 0, width - 1 do
      local gray, alpha
      if colorType == 0 then
        local bit = x * depth
        local byte = row[math.floor(bit / 8) + 1]
        local shift = 8 - depth - bit % 8
        gray = math.floor(byte / 2 ^ shift) % (maxGray + 1) / maxGray
        alpha = 1
      else
        local i = x * channels + 1
        gray = row[i] / 255
        alpha = (colorType == 4 and row[i + 1] or colorType == 6 and row[i + 3] or 255) / 255
      end
      shades[#shades + 1] = { 3 - math.floor(gray * 3 + 0.5), alpha }
    end
  end
  return shades, width, height
end

local failures = 0
for _, label in ipairs(LABELS) do
  local mine, w, h = decodeShades(root .. "/assets/generated/pikachu/gfx_" .. label .. ".png")
  local pret, pw, ph = decodeShades(PRET .. "/unknown_" .. label .. ".png")
  local diff, translucent = 0, 0
  for i = 1, #pret do
    if mine[i][1] ~= pret[i][1] then diff = diff + 1 end
    if mine[i][2] < 1 then translucent = translucent + 1 end
  end
  local ok = w == 40 and h == 40 and pw == 40 and ph == 40 and diff == 0 and translucent == 0
  print(("%s gfx_%s: %d shade diffs, %d non-opaque pixels"):format(
    ok and "PASS" or "FAIL", label, diff, translucent))
  if not ok then failures = failures + 1 end
end

if failures > 0 then
  error(("parity_yellow_pikapic_pose_2347: %d pose(s) differ from pret"):format(failures))
end
print("parity_yellow_pikapic_pose_2347: all 30 poses match pret")

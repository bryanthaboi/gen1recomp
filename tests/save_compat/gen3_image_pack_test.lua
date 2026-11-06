package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")
local Pack = require("src.save_convert.gen3_port.imagepack")
local Gen3Save = require("src.save_convert.Gen3Save")

local VERSIONS = { "firered", "leafgreen", "emerald" }
local fixtures = {}
for _, c in ipairs(G3.cases()) do fixtures[c.id] = c end

local seed = 0x1234567
local function rnd(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return math.floor(seed / 65536) % n
end

for _, n in ipairs({ 1, 2, 3, 4, 5, 127, 128, 4095, 4096, 4097, 32768, 70000 }) do
  for _, mode in ipairs({ "random", "zero", "ff", "period7", "mixed" }) do
    local parts = {}
    for i = 1, n do
      local v
      if mode == "random" then v = rnd(256)
      elseif mode == "zero" then v = 0
      elseif mode == "ff" then v = 255
      elseif mode == "period7" then v = i % 7
      else v = (i % 61 < 40) and 0 or rnd(256) end
      parts[i] = string.char(v)
    end
    local raw = table.concat(parts)
    local packed = Pack.pack(raw)
    check(packed ~= nil and Pack.isPacked(packed), ("%s/%d packs"):format(mode, n))
    eq(Pack.unpack(packed), raw, ("%s/%d round trips"):format(mode, n))
    eq(Pack.pack(raw), packed, ("%s/%d packs deterministically"):format(mode, n))
    check(not packed:find("[^%w+/=:]"), ("%s/%d is printable ASCII"):format(mode, n))
  end
end

eq(Pack.unpack("raw cart bytes"), "raw cart bytes", "a legacy raw image passes through unchanged")
eq(Pack.pack(""), nil, "an empty image does not pack")
eq(Pack.pack(string.rep("\0", 0x100001)), nil, "an oversized image does not pack")
local broken = {
  "PKCI1:", "PKCI1:5:", "PKCI1:5:AAAA", "PKCI1:0:", "PKCI1:999999999:AAAA", "PKCI1:4:!!!!", "PKCI1:4:AAA",
  "PKCI1:4:A=AA", "PKCI1:abc:AAAA", "PKCI1:4:AAAAAAAA", "PKCI1:1048577:AAAA",
}
for _, s in ipairs(broken) do
  local ok, r = pcall(Pack.unpack, s)
  check(ok and r == nil, "malformed packed image is refused without raising: " .. s)
end
do
  local src = string.rep("abcdefgh", 400)
  local packed = Pack.pack(src)
  local raised, accepted = 0, 0
  for pos = 7, #packed do
    for _, b in ipairs({ 0, 65, 255 }) do
      local bad = packed:sub(1, pos - 1) .. string.char(b) .. packed:sub(pos + 1)
      local ok, r = pcall(Pack.unpack, bad)
      if not ok then raised = raised + 1 end
      if ok and r ~= nil and r ~= src and #r ~= #src then accepted = accepted + 1 end
    end
  end
  eq(raised, 0, "single-byte corruption anywhere never raises")
  eq(accepted, 0, "corruption never yields a wrong-length image")
end

for _, v in ipairs(VERSIONS) do
  local codec = Gen3Save.forVersion(v)
  for _, name in ipairs({ "basic", "full_boxes", "max_stacks", "hall_of_fame", "eggs", "trailer" }) do
    local c = fixtures["g3." .. v .. "." .. name]
    local save = assert(K.import(3, v, c.bytes))
    local stored = save.modData.cartImage
    check(Pack.isPacked(stored), v .. " " .. name .. ": the slot stores the compact image")
    eq(codec.slotTemplate(save), c.bytes, v .. " " .. name .. ": the compact image restores every byte")
    if name == "basic" then
      check(#stored * 4 < #c.bytes, ("%s basic: compact image %d bytes vs %d raw"):format(v, #stored, #c.bytes))
    end
    local viaPacked = assert(K.export(3, v, save, nil))
    local viaRaw = assert(K.export(3, v, save, c.bytes))
    eq(viaPacked, viaRaw, v .. " " .. name .. ": exporting from the compact slot equals exporting from the raw file")
    local legacy = assert(K.import(3, v, c.bytes))
    legacy.modData.cartImage = c.bytes
    eq(assert(K.export(3, v, legacy, nil)), viaRaw, v .. " " .. name .. ": a legacy raw slot image still exports the same file")
    local entries = K.r1Diff(3, v, c.bytes, viaPacked)
    eq(#entries, 0, v .. " " .. name .. ": R1 logical round trip from the compact image")
  end
end

for _, v in ipairs(VERSIONS) do
  local c = fixtures["g3." .. v .. ".basic"]
  for _, bad in ipairs({ "PKCI1:131072:AAAA", "broken raw image", Pack.pack("broken image") }) do
    local save = assert(K.import(3, v, c.bytes))
    save.modData.cartImage = bad
    local out, err = K.export(3, v, save, nil)
    check(out ~= nil, v .. ": a damaged embedded image is rebuilt from the save")
    check(type(err) == "string" and err:find("preserved cartridge image", 1, true) ~= nil,
      v .. ": and the export says so")
    local recovered = assert(K.export(3, v, save, c.bytes))
    eq(#K.r1Diff(3, v, c.bytes, recovered), 0, v .. ": a compatible explicit image can recover the embedded image")
  end
  local fresh = assert(K.import(3, v, c.bytes))
  fresh.modData.cartImage = nil
  check(K.export(3, v, fresh) ~= nil, v .. ": a save with no preserved image still exports fresh")
  local retained = assert(K.import(3, v, c.bytes))
  eq(#K.r1Diff(3, v, c.bytes, assert(K.export(3, v, retained, "PKCI1:131072:AAAA"))), 0,
    v .. ": a valid embedded image can recover a damaged explicit image")
end

T.finish()

#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Ed25519 = require("src.core.crypto.ed25519")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function unhex(h)
  return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

local MSG1024 = table.concat({
  "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98",
  "fa6e264bf09efe12ee50f8f54e9f77b1e355f6c50544e23fb1433ddf73be84d8",
  "79de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d",
  "658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc",
  "1a858efcb8550ee3a5e1998bd177e93a7363c344fe6b199ee5d02e82d522c4fe",
  "ba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e",
  "06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbef",
  "efd75499da96bd68a8a97b928a8bbc103b6621fcde2beca1231d206be6cd9ec7",
  "aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1",
  "85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2",
  "d17ba70eb6248e594e1a2297acbbb39d502f1a8c6eb6f1ce22b3de1a1f40cc24",
  "554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270",
  "88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc",
  "2732e69485bbc9c90bfbd62481d9089beccf80cfe2df16a2cf65bd92dd597b07",
  "07e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba",
  "b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51a",
  "ddd3b75a2b1ae0784504df543af8969be3ea7082ff7fc9888c144da2af58429e",
  "c96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7",
  "51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c",
  "42f58c30c04aafdb038dda0847dd988dcda6f3bfd15c4b4c4525004aa06eeff8",
  "ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df",
  "f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08",
  "d78ff4ef5d63653a65040cf9bfd4aca7984a74d37145986780fc0b16ac451649",
  "de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4",
  "88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a3",
  "2ef5b52a1ecc820e308aa342721aac0943bf6686b64b2579376504ccc493d97e",
  "6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f",
  "b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b5",
  "0d334ba77c225bc307ba537152f3f1610e4eafe595f6d9d90d11faa933a15ef1",
  "369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d",
  "b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c",
  "0618983f8741c5ef68d3a101e8a3b8cac60c905c15fc910840b94c00a0b9d0",
})

local VECTORS = {
  {
    name = "RFC 8032 TEST 1",
    pub = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    msg = "",
    sig = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
      .. "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
  },
  {
    name = "RFC 8032 TEST 2",
    pub = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    msg = "72",
    sig = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
      .. "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
  },
  {
    name = "RFC 8032 TEST 3",
    pub = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    msg = "af82",
    sig = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac"
      .. "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
  },
  {
    name = "RFC 8032 TEST 1024",
    pub = "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
    msg = MSG1024,
    sig = "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350"
      .. "aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03",
  },
  {
    name = "RFC 8032 TEST SHA(abc)",
    pub = "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf",
    msg = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
      .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
    sig = "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b589"
      .. "09351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704",
  },
}

local function flipHex(hex, index)
  local c = tonumber(hex:sub(index, index), 16)
  return hex:sub(1, index - 1) .. string.format("%x", (c + 1) % 16) .. hex:sub(index + 1)
end

local function addL(sigHex)
  local L = { 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2,
    0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }
  local out, carry = {}, 0
  for i = 1, 32 do
    local s = tonumber(sigHex:sub(64 + 2 * i - 1, 64 + 2 * i), 16)
    local v = s + L[i] + carry
    out[i] = string.format("%02x", v % 256)
    carry = math.floor(v / 256)
  end
  return sigHex:sub(1, 64) .. table.concat(out), carry
end

print("[test] 1. RFC 8032 section 7.1 vectors verify")
for _, v in ipairs(VECTORS) do
  local t0 = os.clock()
  check(Ed25519.verify(v.pub, unhex(v.msg), v.sig), v.name .. " verifies")
  print(string.format("  %s took %.3fs", v.name, os.clock() - t0))
  check(Ed25519.verify(v.pub:upper(), unhex(v.msg), v.sig:upper()), v.name .. " verifies from upper-case hex")
end
check(#unhex(MSG1024) == 1023, "the TEST 1024 message is 1023 bytes")

print("[test] 2. Tampering is refused")
for _, v in ipairs(VECTORS) do
  local msg = unhex(v.msg)
  check(not Ed25519.verify(v.pub, msg .. "\0", v.sig), v.name .. ": one extra message byte fails")
  if #msg > 0 then
    local flipped = string.char((msg:byte(1) + 1) % 256) .. msg:sub(2)
    check(not Ed25519.verify(v.pub, flipped, v.sig), v.name .. ": a changed message byte fails")
  end
  check(not Ed25519.verify(v.pub, msg, flipHex(v.sig, 5)), v.name .. ": a changed R fails")
  check(not Ed25519.verify(v.pub, msg, flipHex(v.sig, 100)), v.name .. ": a changed S fails")
  check(not Ed25519.verify(flipHex(v.pub, 3), msg, v.sig), v.name .. ": a different public key fails")
end
check(not Ed25519.verify(VECTORS[2].pub, unhex(VECTORS[1].msg), VECTORS[1].sig),
  "a signature under another key fails")

print("[test] 3. Non-canonical S (S + L) is refused")
for _, v in ipairs(VECTORS) do
  local big, carry = addL(v.sig)
  if carry == 0 then
    check(not Ed25519.verify(v.pub, unhex(v.msg), big), v.name .. ": S + L fails")
  end
end
local maxS = VECTORS[1].sig:sub(1, 64) .. string.rep("ff", 32)
check(not Ed25519.verify(VECTORS[1].pub, "", maxS), "S = 2^256 - 1 fails")

print("[test] 4. Malformed input returns false, never an error")
local v1 = VECTORS[1]
local cases = {
  { v1.pub:sub(1, 62), "", v1.sig, "a short public key" },
  { v1.pub .. "00", "", v1.sig, "a long public key" },
  { v1.pub, "", v1.sig:sub(1, 126), "a short signature" },
  { v1.pub, "", v1.sig .. "00", "a long signature" },
  { "zz" .. v1.pub:sub(3), "", v1.sig, "a non-hex public key" },
  { v1.pub, "", "g" .. v1.sig:sub(2), "a non-hex signature" },
  { nil, "", v1.sig, "a nil public key" },
  { v1.pub, "", nil, "a nil signature" },
  { v1.pub, nil, v1.sig, "a nil message" },
  { 42, "", v1.sig, "a number public key" },
  { string.rep("ff", 31) .. "7f", "", v1.sig, "a public key with y >= p" },
  { "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", "", v1.sig, "y = p - 1 is a real point but the wrong key" },
  { string.rep("00", 32), "", v1.sig, "the all-zero public key" },
}
for _, c in ipairs(cases) do
  local ok, res = pcall(Ed25519.verify, c[1], c[2], c[3])
  check(ok and res == false, c[4] .. " returns false")
end

print("[test] 5. The gift key constant is a valid encoded point")
local okGift = pcall(Ed25519.verify,
  "2cecc61cc4d4ea70fc6802a66643e659a0f2c344eec6391ccf20b434ab280ffd", "", v1.sig)
check(okGift, "verifying against the gift key runs")

if failed == 0 then
  print("PASS crypto_ed25519")
else
  print("FAIL crypto_ed25519 failures=" .. failed)
  os.exit(1)
end

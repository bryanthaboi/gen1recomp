#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Sha512 = require("src.core.crypto.sha512")

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
  end
end

print("[test] 1. FIPS 180-4 example vectors")
eq(Sha512.hex(""),
  "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
  .. "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", "empty string")
eq(Sha512.hex("abc"),
  "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
  .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "abc")
eq(Sha512.hex("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
  .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
  "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018"
  .. "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909", "896-bit message")
eq(Sha512.hex(string.rep("a", 1000000)),
  "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973eb"
  .. "de0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b", "one million a")

print("[test] 2. Padding boundaries")
local seen = {}
for _, n in ipairs({ 111, 112, 127, 128, 239, 240 }) do
  local h = Sha512.hex(string.rep("x", n))
  eq(#h, 128, n .. " bytes hash to 64 bytes")
  eq(seen[h], nil, n .. " bytes hash differently from the others")
  seen[h] = true
end
eq(#Sha512.digest("abc"), 64, "digest is 64 raw bytes")

if failed == 0 then
  print("PASS crypto_sha512")
else
  print("FAIL crypto_sha512 failures=" .. failed)
  os.exit(1)
end

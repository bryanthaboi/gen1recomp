package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local okFfi, ffi = pcall(require, "ffi")

package.loaded["src.core.game3.bg_affine"] = nil
local savedFfi = package.loaded.ffi
package.loaded.ffi = nil
table.insert(package.loaders, 1, function(name)
  if name == "ffi" then error("module 'ffi' not found") end
end)
local ok, Affine = pcall(require, "src.core.game3.bg_affine")
table.remove(package.loaders, 1)
package.loaded.ffi = savedFfi

check(ok, "bg_affine loads on a runtime without ffi: " .. tostring(not ok and Affine or ""))

if ok then
  eq(Affine.f32(0.1), 0.100000001490116119384765625, "f32 rounds 0.1 to the nearest float")
  eq(Affine.f32(16777217), 16777216, "f32 ties to even at 2^24 + 1")
  eq(Affine.f32(16777219), 16777220, "f32 ties to even at 2^24 + 3")
  eq(Affine.f32(1e-46), 0, "f32 flushes below the smallest subnormal")
  eq(Affine.f32(1e39), math.huge, "f32 overflows to inf")
  if okFfi then
    local bad = 0
    math.randomseed(7)
    for _ = 1, 20000 do
      local x = (math.random() - 0.5) * 2 ^ math.random(-150, 130)
      if Affine.f32(x) ~= tonumber(ffi.new("float", x)) then bad = bad + 1 end
    end
    eq(bad, 0, "f32 matches a C float cast")
  end
  local r = Affine.objAffineSet(256, 256, 32 * 256)
  eq(r.a, 181, "ObjAffineSet a at 45 degrees")
  eq(r.b, -181, "ObjAffineSet b at 45 degrees")
end

T.finish()

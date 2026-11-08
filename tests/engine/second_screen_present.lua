package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local name = "src.render.SecondScreen"
local oldModule = package.loaded[name]
local oldFfi = package.loaded.ffi
local oldPreload = package.preload.ffi
local calls = {}
local null = {}

local C = {
  love_android_secondary_ready = function() return 0 end,
  love_android_push_secondary = function(ptr, w, h)
    calls.push = { ptr, w, h }
  end,
  love_android_secondary_enable = function(on) calls.enabled = on end,
  love_android_secondary_target = function(target) calls.target = target end,
  love_android_secondary_detected = function() return 1 end,
  love_android_present_secondary = function(ptr, w, h, background, cover)
    calls.present = { ptr, w, h, background, cover }
    return 1
  end,
  love_android_poll_secondary_touch = function() return null end,
}
local fakeFfi = {
  C = C,
  NULL = null,
  cdef = function() end,
  load = function() return C end,
  string = function(value) return value end,
}

package.loaded[name] = nil
package.loaded.ffi = nil
package.preload.ffi = function() return fakeFfi end

local SecondScreen = require(name)
local image = { getFFIPointer = function() return "pixels" end }
T.eq(SecondScreen.scalingAvailable(), false, "Lua updates cannot advertise scaling on an older APK")

T.eq(SecondScreen.available(), false,
  "an unbound presentation is not render-ready")
T.eq(SecondScreen.detected(), true,
  "physical display detection is independent of presentation readiness")
T.eq(SecondScreen.push(image, 160, 144, 0x112233, "secondary:cover"), true,
  "extended Android presentation accepts frame metadata")
T.same(calls.present, { "pixels", 160, 144, 0x112233, 1 },
  "cover and RGB background reach the native bridge")
T.eq(calls.target, 2, "secondary routing reaches the optional native bridge")
T.eq(SecondScreen.push(image, 160, 144, 0x112233, "handheld"), true,
  "handheld routing remains a contain presentation")
T.eq(calls.target, 1, "handheld routing reaches the optional native bridge")
T.eq(SecondScreen.push(image, 160, 144, 0x112233, "secondary"), true,
  "contain presentation remains available")
T.same(calls.present, { "pixels", 160, 144, 0x112233, 0 },
  "contain is the default native fit")
T.eq(SecondScreen.push(image, 160, 144, nil, "secondary:cover"), true,
  "a fit preference can request extended presentation by itself")
T.same(calls.present, { "pixels", 160, 144, 0, 1 },
  "preference-only presentation defaults to a black background")
T.eq(calls.target, 2, "a suffixed route keeps its target")
T.eq(SecondScreen.push(image, 160, 144), true,
  "the original push ABI remains available")
T.same(calls.push, { "pixels", 160, 144 },
  "legacy callers retain the original frame path")

C.love_android_present_secondary_scaled = function(ptr,w,h,background,policy)
  calls.scaled={ptr,w,h,background,policy};return 1
end
package.loaded[name]=nil
SecondScreen=require(name)
T.eq(SecondScreen.scalingAvailable(),true,"matching native bridge enables explicit scaling")
T.eq(SecondScreen.push(image,240,216,0x112233,"secondary:integer"),true,"integer frame is accepted")
T.same(calls.scaled,{"pixels",240,216,0x112233,2},"integer policy reaches the APK")
T.eq(calls.target,2,"integer suffix preserves the external destination")
T.eq(SecondScreen.push(image,240,216,0,"handheld:fit"),true,"fit frame is accepted")
T.eq(calls.scaled[5],1,"fit policy reaches the APK")
T.eq(calls.target,1,"fit suffix preserves the handheld destination")
calls.scaled=nil
T.eq(SecondScreen.push(image,240,216,0,"secondary:fit:unknown"),true,"unknown suffix remains a legacy request")
T.eq(calls.scaled,nil,"unknown suffix must not invoke the new scaling entry")
T.eq(calls.target,0,"unrecognized legacy routing stays automatic")

T.eq(SecondScreen.filteringAvailable(),false,"a scaling-only APK cannot advertise filters")
C.love_android_present_secondary_filtered=function(ptr,w,h,bg,policy,filter)
  calls.filtered={ptr,w,h,bg,policy,filter};return 1
end
package.loaded[name]=nil;SecondScreen=require(name)
T.eq(SecondScreen.filteringAvailable(),true,"matching native filter bridge is detected")
for filter,id in pairs({auto=0,nearest=1,bilinear=2,sharp=3}) do
  T.eq(SecondScreen.push(image,240,216,0x112233,"secondary:integer:"..filter),true,"filtered integer frame accepted")
  T.same(calls.filtered,{"pixels",240,216,0x112233,2,id},"filter reaches JNI without changing geometry or pixels")
  T.eq(calls.target,2,"filter suffix preserves display routing")
end
for _,preference in ipairs({"secondary", "handheld:cover", "secondary:private", "secondary:fit:unknown"}) do
  calls.scaled,calls.filtered=nil,nil
  T.eq(SecondScreen.push(image,240,216,0,preference),true,"legacy requests remain usable on the extended host")
  T.eq(calls.scaled,nil,"legacy request does not opt into explicit scaling")
  T.eq(calls.filtered,nil,"legacy request does not opt into GPU filtering")
end

package.loaded[name] = oldModule
package.loaded.ffi = oldFfi
package.preload.ffi = oldPreload

T.finish("Android secondary presentation facade")

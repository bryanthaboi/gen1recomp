-- Content gate: every shipped artifact carries ShaderFX's librashader bridge.
-- Self-contained: luajit tests/shaderfx_bridge_packaging_test.lua

local T = require("tests.harness")
local check = T.check

local function read(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("*a")
  f:close()
  return s
end

local function mustContain(body, needle, label)
  check(body:find(needle, 1, true) ~= nil,
    label .. " must contain " .. string.format("%q", needle))
end

local build = read("scripts/build.sh")
local release = read(".github/workflows/release.yml")
local flatpak = read("scripts/build_flatpak.sh")
local manifest = read("flatpak/com.theboisclub.gen1recomp.yml")
local arm64 = read("scripts/build_linux_arm64.sh")
local arm64_pack = read("scripts/linux-arm64/build_appimage.sh")
local verify = read("scripts/linux-arm64/verify_appimage.sh")
local rg34 = read("build-rg34xxsp.sh")
local sbc = read("build-linux-arm-sbc.sh")
local android = read("scripts/build_android.sh")

for _, call in ipairs({
  'bundle_shader_bridge "$out_app/Contents/MacOS" "liblibrashader_bridge.dylib" mac',
  'bundle_shader_bridge "$out_dir" "librashader_bridge.dll" win-x64',
  'bundle_shader_bridge "$appdir" "liblibrashader_bridge.so" linux-x64',
}) do
  mustContain(build, call, "build.sh")
end
mustContain(build, '$DIST/native/$plat/$name', "build.sh staged lookup")
mustContain(build, 'SHADERFX_BRIDGE_REQUIRED', "build.sh hard-fail switch")
mustContain(build, '[ "$plat" = "$(shader_bridge_host_plat)" ]', "build.sh host guard")

mustContain(release, "shaderfx-bridge:", "release.yml bridge job")
for _, plat in ipairs({ "win-x64", "mac", "linux-x64", "linux-arm64", "android" }) do
  mustContain(release, "plat: " .. plat, "release.yml matrix")
end
mustContain(release, "lipo -create", "release.yml universal macOS bridge")
mustContain(release, "cargo ndk -t arm64-v8a -t armeabi-v7a", "release.yml Android bridge build")
mustContain(release, "SHADERFX_BRIDGE_ANDROID_DIR", "release.yml stages the Android bridge")

local requiredIn = select(2, release:gsub('SHADERFX_BRIDGE_REQUIRED: "1"', ""))
check(requiredIn >= 7,
  'release.yml must set SHADERFX_BRIDGE_REQUIRED on every shipping job, found ' .. requiredIn)
mustContain(release, "librashader_bridge.dll", "release.yml Windows zip assertion")

mustContain(android, 'SHADERFX_BRIDGE_REQUIRED', "build_android.sh hard-fail switch")
mustContain(android, 'shader_bridge_absent', "build_android.sh routes every miss to the gate")
mustContain(android, 'lib/$abi/$SHADER_BRIDGE_LIB', "build_android.sh per-ABI APK assertion")
mustContain(android, 'shader_bridge_verify_apk "$apk"', "build_android.sh checks the built APK")
mustContain(android, 'apk_entries="$(unzip -Z1 "$apk")"', "build_android.sh lists the APK once")
check(android:find('unzip -l "$apk" | grep', 1, true) == nil,
  "build_android.sh must not pipe unzip into grep -q (pipefail SIGPIPEs unzip, #774)")
check(android:find('warn "$SHADER_BRIDGE_LIB not', 1, true) == nil,
  "build_android.sh must not warn-and-continue past a missing bridge")

mustContain(manifest, "# BRIDGE-BEGIN", "flatpak manifest markers")
mustContain(manifest, "/app/share/gen1recomp/liblibrashader_bridge.so", "flatpak install path")
mustContain(flatpak, "/# BRIDGE-BEGIN/,/# BRIDGE-END/d", "build_flatpak.sh strip")
mustContain(flatpak, "$BUILD_DIR/files/share/gen1recomp/$BRIDGE_LIB", "build_flatpak.sh verify")

mustContain(arm64, "SHADERFX_BRIDGE_LINUX_ARM64", "build_linux_arm64.sh override")
mustContain(arm64_pack, '$APPDIR/liblibrashader_bridge.so', "build_appimage.sh AppDir root")
mustContain(arm64_pack, '${SHADER_BRIDGE[@]+"${SHADER_BRIDGE[@]}"}', "build_appimage.sh contract scan")
mustContain(verify, "7f454c46", "verify_appimage.sh discovers ELF objects")
mustContain(verify, 'ctypes.CDLL', "verify_appimage.sh dlopen smoke")
for _, scanned in ipairs({ 'ldd "${scan[@]}"', 'for f in "${scan[@]}"', 'objdump -T "${scan[@]}"' }) do
  mustContain(verify, scanned, "verify_appimage.sh")
end

for _, pair in ipairs({ { rg34, "build-rg34xxsp.sh" }, { sbc, "build-linux-arm-sbc.sh" } }) do
  mustContain(pair[1], 'libs.aarch64/$BRIDGE_LIB', pair[2])
  mustContain(pair[1], "SHADERFX_BRIDGE_REQUIRED", pair[2])
end

check(release:find("ANDROID_NDK_LATEST_HOME", 1, true) == nil,
  "release.yml must not build the Android bridge with the runner's newest NDK")
mustContain(release, "mobile/android/app/build.gradle", "release.yml reads gradle's NDK pin")
mustContain(release, '"ndk;$ndk_ver"', "release.yml installs gradle's NDK")
mustContain(release, "bash scripts/android_bridge_link_check.sh", "release.yml link-checks the CI bridge")
mustContain(android, 'android_bridge_link_check.sh" "$bridge" "$libcxx"', "build_android.sh link check")
mustContain(android, '"lib/$abi/libc++_shared.so"', "build_android.sh checks against the APK's own libc++")
mustContain(android, 'shader_bridge_gradle_libcxx "$abi"', "build_android.sh checks prebuilt bridges before gradle")

local gradle = read("mobile/android/app/build.gradle")
local gradleNdk = gradle:match("ndkVersion%s+['\"]([%d%.]+)['\"]")
check(gradleNdk ~= nil, "mobile/android/app/build.gradle pins ndkVersion")
mustContain(android, 'NDK_VERSION="' .. tostring(gradleNdk) .. '"', "build_android.sh NDK_VERSION matches gradle")

local function sh(cmd)
  local a, b, c = os.execute(cmd)
  if type(a) == "number" then return a >= 256 and math.floor(a / 256) or a end
  if b == "exit" then return c end
  return a and 0 or 1
end

local tmp = os.tmpname()
os.remove(tmp)
check(sh("mkdir -p '" .. tmp .. "'") == 0, "temp dir for the link-check fixture")
local function put(name, body)
  local f = assert(io.open(tmp .. "/" .. name, "w"))
  f:write(body)
  f:close()
  return tmp .. "/" .. name
end
local fakeNm = put("llvm-nm", '#!/bin/sh\nfor a do last="$a"; done\ncat "$last"\n')
sh("chmod +x '" .. fakeNm .. "'")
local libcxx = put("libc++_shared.so",
  "0000000000001000 T _ZNSt6__ndk16chrono12system_clock3nowEv\n"
  .. "0000000000002000 T _Znwm@@LIBCXX_NDK\n")
local good = put("good.so",
  "                 U _Znwm\n"
  .. "                 U memcpy@LIBC\n"
  .. "                 w _ZWeakOnly\n"
  .. "                 U _ZNSt6__ndk16chrono12system_clock3nowEv\n")
local bad = put("bad.so", "                 U _Znwm\n                 U _ZTVNSt6__ndk117bad_function_callE\n")
local checker = "LLVM_NM='" .. fakeNm .. "' bash scripts/android_bridge_link_check.sh "
local out = tmp .. "/out.txt"
T.eq(sh(checker .. "'" .. good .. "' '" .. libcxx .. "' >'" .. out .. "' 2>&1"), 0,
  "link check passes a bridge whose C++ symbols libc++_shared.so defines")
T.eq(sh(checker .. "'" .. bad .. "' '" .. libcxx .. "' >'" .. out .. "' 2>&1"), 1,
  "link check fails a bridge that needs a symbol libc++_shared.so lacks")
local f = io.open(out, "r")
local body = f and f:read("*a") or ""
if f then f:close() end
mustContain(body, "_ZTVNSt6__ndk117bad_function_callE", "link check output names the missing symbol")
T.eq(sh(checker .. "'" .. bad .. "' '" .. tmp .. "/absent.so' >/dev/null 2>&1"), 1,
  "link check fails a bridge whose APK carries no libc++_shared.so")
sh("rm -rf '" .. tmp .. "'")

T.finish("shaderfx_bridge_packaging_test")

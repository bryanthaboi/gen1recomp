-- Launcher icons share assets/logo/gen1recomp_cover.png, and the shipped
-- Xbox love.dll offers .gba alongside .gb and .gbc.
local function read(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

local function check(value, message)
  if not value then error(message, 2) end
end

local ios = read("scripts/build_ios.sh")
check(ios:find('local source="$ROOT/assets/logo/gen1recomp_cover.png"', 1, true),
  "iOS app icon is resized from the cover")
check(not ios:find("assets/logo/logo.png", 1, true),
  "iOS app icon no longer pads the wordmark onto black")

local android = read("tools/generate_android_icons.py")
check(android:find("assets/logo/gen1recomp_cover.png", 1, true)
    and android:find("def create_adaptive_foreground", 1, true),
  "Android adaptive icon is generated from the cover")

local brand = read("tools/brand_platform_icons.py")
check(brand:find("assets/logo/gen1recomp_cover.png", 1, true)
    and brand:find('"icon.jpg"', 1, true)
    and brand:find("Square150x150Logo.png", 1, true)
    and brand:find("SplashScreen.png", 1, true),
  "Switch and Xbox tiles are generated from the cover")

local patch = read("ports/uwp/third_party/love/patches/gba-file-picker.patch")
check(patch:find('filters.Append(L".gba")', 1, true)
    and patch:find('destination = "picked_rom.gb"', 1, true),
  "UWP picker patch adds .gba and still stages the ROM for Lua")

local rebuild = read("scripts/xbox-uwp/rebuild_dependencies.ps1")
local manifest = read("ports/uwp/third_party/manifest.json")
check(manifest:find('"patch": "love/patches/gba-file-picker.patch"', 1, true),
  "UWP dependency manifest records the picker patch")
check(rebuild:find("$metadata.sources.love.patch", 1, true)
    and rebuild:find("git apply --unidiff-zero $lovePatch", 1, true),
  "UWP dependency rebuild applies the picker patch")

local function utf16z(text)
  local out = {}
  for i = 1, #text do
    out[#out + 1] = text:sub(i, i) .. "\0"
  end
  return table.concat(out) .. "\0\0"
end

local dll = read("ports/uwp/third_party/love/bin/love.dll")
check(dll:find(utf16z(".gb"), 1, true) and dll:find(utf16z(".gbc"), 1, true)
    and dll:find(utf16z(".gba"), 1, true),
  "shipped UWP love.dll offers .gb, .gbc, and .gba")

print("platform_icon_and_uwp_picker_test: ok")

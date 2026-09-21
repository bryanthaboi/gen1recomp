#!/usr/bin/env luajit
-- src/slot_machine.c:399, src/trade_scene.c:151, src/link_rfu_3.c:34

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

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local CacheContract = require("src.import.CacheContract")
local Versions = require("src.import.gba.versions")
local Slot = require("src.import.gba.slot_machine_extract")
local Trade = require("src.import.gba.trade_extract")
local LinkArt = require("src.import.gba.link_art_extract")

local SHEETS = {
  { "slot_machine/reel_icons.rgba", 32, 224 },
  { "slot_machine/clefairy.rgba", 32, 192 },
  { "slot_machine/digits.rgba", 8, 160 },
  { "slot_machine/bg.rgba", 240, 160 },
  { "slot_machine/payout_lights.rgba", 224, 48 },
  { "slot_machine/match_lines.rgba", 176, 104 },
  { "slot_machine/button_pressed.rgba", 16, 16 },
  { "slot_machine/combos_window.rgba", 240, 160 },
  { "trade/gba_screen.rgba", 240, 524 },
  { "trade/gba_screen_wireless.rgba", 240, 524 },
  { "trade/gba_screen_flash.rgba", 448, 32 },
  { "trade/cable_closeup.rgba", 240, 160 },
  { "trade/cable_end.rgba", 16, 32 },
  { "trade/link_mon_glow.rgba", 32, 32 },
  { "trade/link_mon_shadow.rgba", 16, 32 },
  { "trade/link_mon_shadow_small.rgba", 16, 32 },
  { "trade/ball.rgba", 16, 16 },
  { "trade/ball_spin.rgba", 16, 192 },
  { "union_room/wireless_icon.rgba", 16, 112 },
  { "union_room/chat_bg.rgba", 240, 160 },
  { "union_room/chat_panel.rgba", 240, 160 },
  { "union_room/chat_icons.rgba", 32, 64 },
  { "union_room/chat_selector_cursor.rgba", 64, 128 },
  { "union_room/chat_text_entry_cursor.rgba", 8, 16 },
  { "union_room/chat_char_select_cursor.rgba", 8, 16 },
  { "union_room/chat_r_button.rgba", 16, 16 },
  { "wireless_status/bg.rgba", 240, 160 },
}

print("[test] 1. the ROM offsets are the symbols pret links, not another screen's")
eq(Versions.SLOT_REEL_ICONS_PAL, 0x464974, "SLOT_REEL_ICONS_PAL is sReelIcons_Pal")
eq(Versions.SLOT_BG_GFX, 0x4659D0, "SLOT_BG_GFX is sBg_Tiles")
eq(Versions.SLOT_PAYOUT_LIGHTS_PAL, 0x4664DC, "SLOT_PAYOUT_LIGHTS_PAL is sBgPal_PayoutLight")
eq(Versions.TRADE_GBA_MAP_CABLE, 0x26AA5C, "TRADE_GBA_MAP_CABLE is sGbaMapCable")
eq(Versions.TRADE_GBA_GFX, 0xEAEA80, "TRADE_GBA_GFX is gTradeGba_Gfx")
eq(Versions.WIRELESS_STATUS_PALS, 0x46F4D0, "WIRELESS_STATUS_PALS is sPalettes")
eq(Versions.UR_CHAT_BG_TILEMAP, 0xEA1958, "UR_CHAT_BG_TILEMAP is gUnionRoomChat_Bg_Tilemap")
check(Versions.TRADE_GBA_MAP_CABLE ~= Versions.TRADE_GBA_MAP_WIRELESS,
  "the cable and wireless console tilemaps are two different tables")
-- src/slot_machine.c:429, :857, src/trade_scene.c:398
eq(Versions.SLOT_REEL_ICON_PAL_TAGS, 0x465608, "SLOT_REEL_ICON_PAL_TAGS is sReelIconPaletteTags")
eq(Versions.SLOT_REEL_BUTTON_MAP_IDXS, 0x466C40,
  "SLOT_REEL_BUTTON_MAP_IDXS is sReelButtonMapTileIdxs")
eq(Versions.TRADE_GBA_SCREEN_ANIM, 0x26CED8, "TRADE_GBA_SCREEN_ANIM is sAnim_GbaScreen_Long")

print("[test] 2. the cache contract requires every new key")
local required = CacheContract.requiredFiles("firered")
local have = {}
for _, path in ipairs(required) do have[path] = true end
local WANT = {
  "data/generated/gba/slot_machine/manifest.lua",
  "data/generated/gba/slot_machine/reel_icons.rgba",
  "data/generated/gba/slot_machine/bg.rgba",
  "data/generated/gba/slot_machine/payout_lights.rgba",
  "data/generated/gba/slot_machine/digits.rgba",
  "data/generated/gba/trade/manifest.lua",
  "data/generated/gba/trade/gba_screen.rgba",
  "data/generated/gba/trade/ball.rgba",
  "data/generated/gba/union_room/manifest.lua",
  "data/generated/gba/union_room/wireless_icon.rgba",
  "data/generated/gba/wireless_status/manifest.lua",
  "data/generated/gba/wireless_status/bg.rgba",
}
for _, path in ipairs(WANT) do
  check(have[path] == true, "the firered contract requires " .. path)
end
for _, path in ipairs(WANT) do
  local fs = {
    prefix = "",
    exists = function(candidate) return candidate ~= path end,
  }
  local complete, missing = CacheContract.allRequiredFilesExist("firered", fs)
  check(complete == false and missing == path,
    "a cache without " .. path .. " is incomplete (" .. tostring(missing) .. ")")
end

print("[test] 3. ready() refuses a half-written group")
local written = {}
local stub = {
  write = function(_, rel, bytes) written[rel] = bytes end,
  read = function(_, rel) return written[rel] end,
  exists = function(_, rel) return written[rel] ~= nil end,
}
check(Slot.ready(stub, "x") == false, "slot ready() is false with nothing written")
check(Trade.ready(stub, "x") == false, "trade ready() is false with nothing written")
check(LinkArt.ready(stub, "x") == false, "link art ready() is false with nothing written")
written["x/slot_machine/manifest.lua"] = "return { format_version = 1 }\n"
written["x/slot_machine/reel_icons.rgba"] = string.rep("\0", 32 * 224 * 4)
check(Slot.ready(stub, "x") == false, "slot ready() is false with the manifest but no bg")
written["x/slot_machine/bg.rgba"] = string.rep("\0", 240 * 160 * 4)
check(Slot.ready(stub, "x") == true, "slot ready() accepts a complete group")
written["x/slot_machine/reel_icons.rgba"] = string.rep("\0", 32 * 32 * 4)
check(Slot.ready(stub, "x") == false, "slot ready() refuses a short reel sheet")

print("[test] 4. a built cache carries every baked sheet at its manifest size")
local Cache = require("tests.game3_cache")
local root = Cache.root("slot_machine/manifest.lua")
if not root then
  print("[skip] baked Game Corner and trade art: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function loadManifest(rel)
  local src = readFile(rel)
  if not src then return nil end
  local chunk = (loadstring or load)(src)
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

local blobs = {}
for _, sheet in ipairs(SHEETS) do
  local rel, w, h = sheet[1], sheet[2], sheet[3]
  local blob = readFile(rel)
  blobs[rel] = blob
  eq(blob and #blob or nil, w * h * 4, rel .. " is " .. w .. "x" .. h)
end

local slotMan = loadManifest("slot_machine/manifest.lua")
check(type(slotMan) == "table", "slot_machine/manifest.lua loads")
if slotMan then
  eq(slotMan.reel_icons.frames, 7, "the manifest names seven reel icons")
  eq(slotMan.reel_icons.width, 32, "reel icon frames are 32 wide")
  eq(slotMan.digits.frames, 10, "the payout digits are ten frames")
  eq(slotMan.payout_lights.frames, 3, "the payout lamps carry three palette frames")
  eq(slotMan.bg.width, 240, "the machine frame is a full screen")
  eq(#slotMan.button_pressed.at, 3, "the manifest places three reel buttons")
  -- src/slot_machine.c:858
  eq(slotMan.button_pressed.at[1] and slotMan.button_pressed.at[1].x, 72,
    "the first reel button sits where the cart's tilemap index puts it")
  eq(slotMan.button_pressed.at[1] and slotMan.button_pressed.at[1].y, 136,
    "the first reel button row comes from the same index")
end

local tradeMan = loadManifest("trade/manifest.lua")
check(type(tradeMan) == "table", "trade/manifest.lua loads")
if tradeMan then
  eq(tradeMan.gba_screen.width, 240, "the console sheet is 240 wide")
  eq(tradeMan.gba_screen.center_y, 0x15C + 80,
    "the console sheet is centred on the bg1vofs the scene opens at")
  eq(tradeMan.gba_screen.height, (0x15C + 80 - 166) * 2,
    "the console sheet reaches the far end of the pan")
  eq(tradeMan.gba_screen_flash.frames, 7, "the screen flash is pret's seven-step anim")
  eq(tradeMan.ball_spin.frames, 12, "the ball spin is twelve frames")
end

local unionMan = loadManifest("union_room/manifest.lua")
check(type(unionMan) == "table", "union_room/manifest.lua loads")
if unionMan then
  eq(unionMan.wireless_icon.frames, 7, "the wireless indicator has seven frames")
  eq(unionMan.chat_selector_cursor.frames, 4, "the chat selector cursor has four frames")
end

local statusMan = loadManifest("wireless_status/manifest.lua")
check(type(statusMan) == "table", "wireless_status/manifest.lua loads")
if statusMan then
  eq(statusMan.palettes.banks, 16, "the status screen carries all sixteen palette banks")
end
local pals = readFile("wireless_status/palettes.pal")
eq(pals and #pals or nil, 16 * 16 * 3, "wireless_status/palettes.pal is 16 banks of 16 colours")

print("[test] 5. the sheets are the art, not a blank buffer")

local function pixel(blob, w, x, y)
  local o = (y * w + x) * 4
  return blob:byte(o + 1), blob:byte(o + 2), blob:byte(o + 3), blob:byte(o + 4)
end

local function opaqueCount(blob, from, to)
  local n = 0
  for i = from, to, 4 do
    if blob:byte(i) ~= 0 then n = n + 1 end
  end
  return n
end

local icons = blobs["slot_machine/reel_icons.rgba"]
if icons then
  local frameBytes = 32 * 32 * 4
  local prev
  local distinct = 0
  for f = 0, 6 do
    local frame = icons:sub(f * frameBytes + 1, (f + 1) * frameBytes)
    local ink = opaqueCount(frame, 4, #frame)
    check(ink > 200, "reel icon " .. f .. " is drawn (" .. ink .. " opaque pixels)")
    if frame ~= prev then distinct = distinct + 1 end
    prev = frame
  end
  eq(distinct, 7, "the seven reel icons are seven different pictures")
  -- src/slot_machine.c:529
  local function countColor(frame, r, g, b)
    local n = 0
    for i = 1, #frame, 4 do
      if frame:byte(i + 3) ~= 0 and frame:byte(i) == r
        and frame:byte(i + 1) == g and frame:byte(i + 2) == b then
        n = n + 1
      end
    end
    return n
  end
  local function frameAt(f) return icons:sub(f * frameBytes + 1, (f + 1) * frameBytes) end
  local seven, pikachu = frameAt(0), frameAt(2)
  local magnemite, shellder = frameAt(5), frameAt(6)
  check(countColor(seven, 255, 0, 0) > 100, "the 7 icon is painted in bank 2's red")
  check(countColor(pikachu, 255, 247, 0) > 100, "the Pikachu icon is painted in bank 0's yellow")
  eq(countColor(seven, 255, 247, 0), 0, "the 7 icon does not borrow Pikachu's bank")
  check(countColor(shellder, 206, 132, 255) > 20, "the Shellder icon is painted in bank 3")
  eq(countColor(magnemite, 206, 132, 255), 0, "the Magnemite icon does not borrow bank 3")
end

local bg = blobs["slot_machine/bg.rgba"]
if bg then
  local opaque = opaqueCount(bg, 4, #bg)
  eq(opaque, 240 * 160, "the machine frame is fully opaque")
  local reelR, reelG, reelB = pixel(bg, 240, 120, 80)
  check(reelR < 40 and reelG < 40 and reelB < 40,
    "the middle reel window is the black cut-out the sprites spin behind")
end

local lights = blobs["slot_machine/payout_lights.rgba"]
if lights then
  local frameBytes = 224 * 16 * 4
  local a = lights:sub(1, frameBytes)
  local b = lights:sub(frameBytes + 1, frameBytes * 2)
  local c = lights:sub(frameBytes * 2 + 1)
  check(a ~= b and b ~= c and a ~= c,
    "the three payout lamp frames are three different palettes of the same tiles")
end

local screen = blobs["trade/gba_screen.rgba"]
if screen then
  local mid = opaqueCount(screen:sub((262 - 8) * 240 * 4 + 1, (262 + 8) * 240 * 4), 4, 16 * 240 * 4)
  check(mid > 500, "the console sits at the centre of the console sheet (" .. mid .. ")")
  local top = opaqueCount(screen:sub(1, 8 * 240 * 4), 4, 8 * 240 * 4)
  check(top > 0 and top < 8 * 240, "the cable, not the console, is at the top (" .. top .. ")")
  local bottom = opaqueCount(screen:sub(500 * 240 * 4 + 1), 4, 24 * 240 * 4)
  eq(bottom, 0, "the sheet is padded past the end of the BG so its centre stays put")
end

local flash = blobs["trade/gba_screen_flash.rgba"]
if flash then
  local function column(x)
    local parts = {}
    for y = 0, 31 do
      local o = (y * 448 + x) * 4
      parts[#parts + 1] = flash:sub(o + 1, o + 4)
    end
    return table.concat(parts)
  end
  -- src/trade_scene.c:393
  check(column(32) == column(32 + 64 * 6), "flash frames 1 and 7 are the same cel")
  check(column(32 + 64) == column(32 + 64 * 5), "flash frames 2 and 6 are the same cel")
  check(column(32 + 64 * 2) ~= column(32 + 64 * 3), "flash frames 3 and 4 differ")
end

local glow = blobs["trade/link_mon_glow.rgba"]
if glow then
  local _, _, _, cornerA = pixel(glow, 32, 0, 0)
  local _, _, _, midA = pixel(glow, 32, 16, 16)
  eq(cornerA, 0, "the link mon glow is transparent outside its circle")
  eq(midA, 255, "the link mon glow is opaque at its centre")
end

local icon = blobs["union_room/wireless_icon.rgba"]
if icon then
  local frameBytes = 16 * 16 * 4
  local first = icon:sub(1, frameBytes)
  local last = icon:sub(frameBytes * 6 + 1)
  check(first ~= last, "the wireless indicator frames are not all one cel")
  check(opaqueCount(first, 4, frameBytes) > 20, "the wireless indicator frame 0 is drawn")
end

local status = blobs["wireless_status/bg.rgba"]
if status then
  eq(opaqueCount(status, 4, #status), 240 * 160, "the status screen background is opaque")
  local r, g, b = pixel(status, 240, 8, 8)
  check(r > 200 and g > 120 and b < 80,
    string.format("the status screen frame is the cart's orange (%d,%d,%d)", r, g, b))
end

finish()

#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

local function finish()
  if failed > 0 then
    print(failed .. " failure(s)")
    os.exit(1)
  end
  print("all passed")
  os.exit(0)
end

_G.love = _G.love or { graphics = {} }

local PartyMenu = require("src.ui.game3.party_menu")
local PartyChrome = require("src.ui.game3.party_chrome")
local PartyChromeExtract = require("src.import.gba.party_chrome_extract")

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end

check(call(PartyMenu.hpBarFraction, 1, 500, 48) == 1, "hp fraction: 1/500 rounds up to 1 px")
check(call(PartyMenu.hpBarFraction, 250, 500, 48) == 24, "hp fraction: half hp is 24 px")
check(call(PartyMenu.hpBarFraction, 500, 500, 48) == 48, "hp fraction: full hp is 48 px")
check(call(PartyMenu.hpBarFraction, 0, 500, 48) == 0, "hp fraction: 0 hp is 0 px")

check(call(PartyMenu.hpBarLevelName, 100, 100) == "green", "hp level: full is green")
check(call(PartyMenu.hpBarLevelName, 53, 100) == "green", "hp level: 25/48 px is green")
check(call(PartyMenu.hpBarLevelName, 50, 100) == "yellow", "hp level: 24/48 px is yellow")
check(call(PartyMenu.hpBarLevelName, 21, 100) == "yellow", "hp level: 10/48 px is yellow")
check(call(PartyMenu.hpBarLevelName, 20, 100) == "red", "hp level: 9/48 px is red")

local PAL = {}
for i = 0, 175 do PAL[i] = { i, 255 - i, i % 7 } end
PartyChrome._nativeDelegate = nil
PartyChrome._manifest = { palBuffer = PAL }
local function isPal(c, id)
  return type(c) == "table" and c[1] == PAL[id][1] / 255 and c[2] == PAL[id][2] / 255 and c[3] == PAL[id][3] / 255
end
local g = call(PartyMenu.hpBarColors, 100, 100, 3)
check(g and isPal(g.top, 58) and isPal(g.bottom, 57), "hp colors: green top row pal 58, lower rows pal 57")
check(g and isPal(g.emptyTop, 3 * 16 + 13) and isPal(g.emptyBottom, 3 * 16 + 2),
  "hp colors: empty part uses window palette 3 idx 13 / idx 2")
local y = call(PartyMenu.hpBarColors, 40, 100, 5)
check(y and isPal(y.top, 74) and isPal(y.bottom, 73) and isPal(y.emptyTop, 5 * 16 + 13),
  "hp colors: yellow top row pal 74, lower rows pal 73, window palette 5")
local r = call(PartyMenu.hpBarColors, 5, 100, 4)
check(r and isPal(r.top, 90) and isPal(r.bottom, 89), "hp colors: red top row pal 90, lower rows pal 89")

local tc = call(PartyChrome.textColors, 4)
check(tc and isPal(tc.fg, 4 * 16 + 3) and isPal(tc.shadow, 4 * 16 + 2),
  "slot text: fg is window palette idx 3, shadow idx 2 (sFontColorTable[0])")
local pmSrc = io.open("src/ui/game3/party_menu.lua", "rb")
local pmText = pmSrc and pmSrc:read("*a") or ""
if pmSrc then pmSrc:close() end
local partyPrint = pmText:match("local function party_print.-\nend") or ""
check(partyPrint:find("PartyChrome.textColors", 1, true) ~= nil and not partyPrint:find("COLOR.PARTY", 1, true),
  "slot text: party_print colours come from the party palette, not the standard text palette")

PartyChrome._manifest = { width = 240 }
local okMissing = pcall(PartyChrome.palColor or error, 57)
check(PartyChrome.palColor ~= nil and not okMissing, "party chrome: a manifest with no palBuffer errors instead of guessing")

local function asSession(version)
  PartyMenu._session = { version = version }
end
PartyMenu._layout = "single"
asSession("emerald")
local em1, em2 = call(PartyMenu.slotSprites, 1), call(PartyMenu.slotSprites, 2)
check(em1 and em1[5] == 50 and em1[6] == 52, "emerald status icon slot 1 at (50,52)")
check(em2 and em2[5] == 136 and em2[6] == 27, "emerald status icon slot 2 at (136,27)")
local emL, emR = call(PartyMenu.slotInfo, 1), call(PartyMenu.slotInfo, 2)
check(emL and emL.hp[2] == 37 and emL.hpMax[2] == 37, "emerald left box hp text at y 37")
check(emR and emR.level[1] == 30 and emR.gender[1] == 62, "emerald right box level x 30, gender x 62")
PartyMenu._layout = "double"
local emD = call(PartyMenu.slotSprites, 2)
check(emD and emD[5] == 50 and emD[6] == 92, "emerald double status icon slot 2 at (50,92)")
PartyMenu._layout = "single"
asSession("firered")
local fr1, fr2 = call(PartyMenu.slotSprites, 1), call(PartyMenu.slotSprites, 2)
check(fr1 and fr1[5] == 56 and fr2 and fr2[5] == 144, "firered status icon x 56 / 144")
local frL, frR = call(PartyMenu.slotInfo, 1), call(PartyMenu.slotInfo, 2)
check(frL and frL.hp[2] == 36 and frR and frR.level[1] == 32 and frR.gender[1] == 64,
  "firered box text keeps pokefirered rects")
PartyMenu._session = nil

local manifestReady = PartyChromeExtract.manifestReady
check(manifestReady ~= nil and not manifestReady("return {\n  width = 240,\n}\n"),
  "party chrome manifest without the party palette is not ready")
check(manifestReady ~= nil and manifestReady("return {\n  formatVersion = " .. PartyChromeExtract.FORMAT_VERSION
  .. ",\n  palBuffer = { [0] = { 0, 0, 0 }, },\n}\n"), "party chrome manifest with formatVersion and palBuffer is ready")

local SummaryExtract = require("src.import.gba.rse.summary_chrome_extract")
local hasButtons = false
for _, f in ipairs(SummaryExtract.REQUIRED) do
  if f == "rse/summary/buttons.png" then hasButtons = true end
end
check(hasButtons, "rse summary: buttons.png (sButtons_Gfx) is a required cache file")
local f = io.open("src/ui/game3/rse/summary_menu.lua", "rb")
local src = f and f:read("*a") or ""
if f then f:close() end
check(not src:find("drawKeypadIcon", 1, true) and src:find("m.buttons", 1, true) ~= nil,
  "rse summary: prompt icon is drawn from the cached A button, not a font keypad glyph")

local CacheBlob = require("src.import.CacheBlob")
local function readAt(root, rel)
  local fh = io.open(root .. "/" .. rel, "rb")
  if not fh then return nil end
  local data = CacheBlob.decode(root .. "/" .. rel, fh:read("*a"))
  fh:close()
  return data
end
local function rgbIs(c, rr, gg, bb) return c and c[1] == rr and c[2] == gg and c[3] == bb end
local function partyChecks(label, root)
  local body = readAt(root, "pokemon/party/manifest.lua")
  local m = body and load(body, "@manifest", "t", {})()
  local P = m and m.palBuffer
  check(P and rgbIs(P[57], 115, 255, 173) and rgbIs(P[58], 90, 214, 132), label .. ": green hp pal 57/58")
  check(P and rgbIs(P[73], 255, 230, 58) and rgbIs(P[74], 206, 173, 8), label .. ": yellow hp pal 73/74")
  check(P and rgbIs(P[89], 255, 115, 49) and rgbIs(P[90], 197, 58, 0), label .. ": red hp pal 89/90")
  check(P and rgbIs(P[3 * 16 + 13], 82, 82, 82) and rgbIs(P[3 * 16 + 2], 115, 115, 115), label .. ": empty bar idx 13 / 2")
  check(P and rgbIs(P[3 * 16 + 3], 255, 255, 255), label .. ": slot text fg idx 3 is white, shadow idx 2 is 115 gray")
  check(PartyChromeExtract.ready(require("tests.game3_cache").cache(), root), label .. ": party chrome ready at the current format")
end

local ranAny = false
local frRoot = require("tests.game3_cache").root()
if frRoot then
  ranAny = true
  partyChecks("firered cache", frRoot)
end

local emRoot = require("tests.game3_cache").root("emerald")
if emRoot then
  ranAny = true
  partyChecks("emerald cache", emRoot)
  local png = readAt(emRoot, "rse/summary/buttons.png")
  local function be32(s, at) local a, b, c, d = s:byte(at, at + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
  check(png and #png > 24 and be32(png, 17) == 16 and be32(png, 21) == 32, "emerald cache: summary buttons.png is the 16x32 A/B sheet")
end
if not ranAny then
  print("[skip] party chrome cache checks need a current FRLG or Emerald cache")
end
finish()

package.path = "./?.lua;./?/init.lua;" .. package.path
local CacheBlob = require("src.import.CacheBlob")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function cacheRoot()
  local explicit = os.getenv("POKEPORT_EMERALD_CACHE")
  if explicit and explicit ~= "" then return explicit end
  local identity = os.getenv("POKEPORT_IDENTITY")
  local home = os.getenv("HOME")
  if not (identity and identity ~= "" and home) then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
    local root = base .. identity .. "/emerald"
    local f = io.open(root .. "/data/generated/gba/chrome/manifest.lua", "rb")
    if f then
      f:close()
      return root
    end
  end
  return nil
end

local ROOT = cacheRoot() or require("tests.game3_cache").gameDir("emerald", "chrome/manifest.lua")
if not ROOT then
  print("emerald_text_chrome_test: skipped (set POKEPORT_IDENTITY to an identity with an Emerald cache)")
  os.exit(0)
end

local function read(rel)
  local f = io.open(ROOT .. "/" .. rel, "rb")
  if not f then return nil end
  local s = CacheBlob.decode(ROOT .. "/" .. rel, f:read("*a"))
  f:close()
  return s
end

local function loadLua(rel)
  local src = read(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local TextIR = require("src.core.game3.scripting.text_ir")
local prevVersion = GameVersion.get()
Profile.reset()
local em = Profile.of("emerald")
local font, frames = em.font, em.ui.frames

local metrics = loadLua(font.metrics)
check(type(metrics) == "table", "metrics.lua loads")
for name, face in pairs(font.faces) do
  eq(#(read(font.dir .. face.sheet .. "_fg.rgba") or ""), 256 * 512 * 4, name .. " fg sheet is 256x512 rgba")
  eq(#(read(font.dir .. face.sheet .. "_shadow.rgba") or ""), 256 * 512 * 4, name .. " shadow sheet is 256x512 rgba")
  local widths = loadLua(font.dir .. face.widths)
  check(type(widths) == "table" and widths[0] ~= nil and widths[511] ~= nil, name .. " widths cover 0..511")
  local m
  for _, row in pairs(metrics or {}) do
    if row.name == face.fontId then m = row end
  end
  check(m ~= nil and m.maxLetterHeight > 0, name .. " has sFontInfos metrics (" .. face.fontId .. ")")
end
-- pokeemerald/src/text.c:131
local normal
for _, row in pairs(metrics or {}) do
  if row.name == "FONT_NORMAL" then normal = row end
end
eq(normal and normal.maxLetterHeight, 16, "FONT_NORMAL is 16px tall")
eq(normal and normal.lineSpacing, 0, "FONT_NORMAL has no line spacing")
for name, jp in pairs(font.japanese) do
  eq(#(read(font.dir .. jp.sheet .. "_fg.rgba") or ""), 256 * 512 * 4, "japanese " .. name .. " sheet")
  if jp.widths then check(type(loadLua(font.dir .. jp.widths)) == "table", "japanese " .. name .. " widths") end
end
local pal = loadLua(font.palette.file)
local mb = pal and pal[font.palette.key]
check(type(mb) == "table" and #mb == 15, "message box palette has 16 colours")
eq(mb and table.concat(mb[2], ","), "99,99,99", "TEXT_COLOR_DARK_GRAY")
eq(mb and table.concat(mb[3], ","), "214,214,206", "TEXT_COLOR_LIGHT_GRAY")

local manifest = loadLua(frames.manifest)
eq(manifest and manifest.frames.user.count, frames.userCount, "cache user frame count equals WINDOW_FRAMES_COUNT")
for n = 0, frames.userCount - 1 do
  eq(#(read(string.format(frames.user, n)) or ""), 24 * 24 * 4, "user_frame_" .. n .. " is 24x24 rgba")
end
eq(read(string.format(frames.user, frames.userCount)), nil, "no user frame past the count")
local mbInfo = manifest and manifest.frames[frames.dialogue.manifestKey]
eq(mbInfo and (mbInfo.tilesW * mbInfo.tilesH), 14, "message box is 14 tiles")
eq(#(read(frames.dialogue.path) or ""), mbInfo.width * mbInfo.height * 4, "message_box.rgba size")
local arrow = manifest and manifest.fonts[frames.arrow.manifestKey]
eq(arrow and table.concat(arrow.yOffsets, ","), "0,1,2,1", "sDownArrowYCoords")
eq(arrow and arrow.frameH, 16, "down arrow blit is 16 rows")
eq(#(read(frames.arrow.path) or ""), arrow.width * arrow.height * 4, "down_arrow.rgba size")
eq(read("data/generated/gba/chrome/std_rgba.rgba"), nil, "no std frame on Emerald")
eq(read("data/generated/gba/chrome/signpost_rgba.rgba"), nil, "no signpost frame on Emerald")

local ph = loadLua(TextIR.DIALECTS.rse.placeholders)
check(type(ph) == "table", "placeholders.lua loads")
eq(ph and ph.byGender.RIVAL.male, "MAY", "male player's rival is MAY")
eq(ph and ph.byGender.RIVAL.female, "BRENDAN", "female player's rival is BRENDAN")
local ir = TextIR.decode({ 0xFD, 0x06, 0x00, 0xFD, 0x07, 0xFF }, { dialect = "rse" })
eq(TextIR.toPlain(ir, { dialect = "rse", placeholders = ph, playerGender = 1 }), "BRENDAN EMERALD",
  "FD 06 / FD 07 expand from the cached placeholders")

GameVersion.set(prevVersion)
Profile.reset()
T.finish("emerald_text_chrome_test")

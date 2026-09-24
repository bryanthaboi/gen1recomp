#!/usr/bin/env luajit
-- src/berry_crush.c:647, src/dodrio_berry_picking.c:3323, src/pokemon_jump.c:2901

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

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local GV = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local AssetPack = require("src.import.gba.asset_pack")
local CacheContract = require("src.import.CacheContract")

local EXTRACTORS = { "online_ui_extract", "berry_crush_extract", "dodrio_extract", "pokemon_jump_extract" }

local ADDRESSES = {
  { "SCROLL_ARROW_PAL", 0x463308, 0x462D28 },
  { "SCROLL_ARROW_GFX", 0x463328, 0x462D48 },
  { "SELECTOR_OUTLINE_GFX", 0x463398, 0x462DB8 },
  { "RED_ARROW_CURSOR_GFX", 0x4633D8, 0x462DF8 },
  { "SCROLL_INDICATOR_TEMPLATES", 0x46325C, 0x462C7C },
  { "MG_COUNTDOWN_PAL", 0x47A328, 0x479C04 },
  { "MG_COUNTDOWN_GFX", 0x47A348, 0x479C24 },
  { "MG_321START_PAL", 0x46AFE8, 0x46A8C4 },
  { "MG_321START_GFX", 0x46B008, 0x46A8E4 },
  { "MG_DIGITS_PAL", 0x479668, 0x478F44 },
  { "MG_DIGITS_GFX", 0x479688, 0x478F64 },
  { "WONDER_STAMP_SHADOW_PALS", 0x467DF4, 0x4676D0 },
  { "WONDER_STAMP_SHADOW_GFX", 0x467EF4, 0x4677D0 },
  { "MYSTERY_GIFT_BORDER_PAL", 0x466D10, 0x4665EC },
  { "MYSTERY_GIFT_BORDER_GFX", 0x466D30, 0x46660C },
  { "UR_OBJ_GFX_IDS", 0x4570D8, 0x456AF8 },
  { "UR_PLAYER_COORDS", 0x4570EC, 0x456B0C },
  { "UR_GROUP_OFFSETS", 0x45710C, 0x456B2C },
  { "UR_OPPOSITE_FACING", 0x457116, 0x456B36 },
  { "UR_MEMBER_FACING", 0x45711B, 0x456B3B },
  { "BC_CRUSHER_PAL", 0xEAFEA0, 0xEB0194 },
  { "BC_CRUSHER_GFX", 0xEAFFC0, 0xEB02B4 },
  { "BC_TEXT_WINDOWS_MAP", 0xEB0ADC, 0xEB0DD0 },
  { "BC_CORE_PAL", 0x46E470, 0x46DD4C },
  { "BC_EFFECT_PAL", 0x46E490, 0x46DD6C },
  { "BC_TIMER_PAL", 0x46E4B0, 0x46DD8C },
  { "BC_CORE_GFX", 0x46E4D0, 0x46DDAC },
  { "BC_IMPACT_GFX", 0x46E7FC, 0x46E0D8 },
  { "BC_SPARKLE_GFX", 0x46EB78, 0x46E454 },
  { "BC_TIMER_GFX", 0x46ECC4, 0x46E5A0 },
  { "BC_CRUSHER_TOP_MAP", 0x46ED90, 0x46E66C },
  { "BC_CONTAINER_CAP_MAP", 0x46EEC0, 0x46E79C },
  { "BC_BG_MAP", 0x46F058, 0x46E934 },
  { "BC_BERRY_DATA", 0x3DFC9C, 0x3DFAD8 },
  { "BC_SYNC_PRESS_BONUS", 0x46E2E8, 0x46DBC4 },
  { "BC_INTRO_OUTRO_VIBRATION", 0x46E2F0, 0x46DBCC },
  { "BC_VIBRATION", 0x46E314, 0x46DBF0 },
  { "BC_SPARKLE_THRESHOLDS", 0x46E3B4, 0x46DC90 },
  { "BC_BIG_SPARKLE_THRESHOLDS", 0x46E3C4, 0x46DCA0 },
  { "BC_RECEIVED_PLAYER_BITMASKS", 0x46E3C8, 0x46DCA4 },
  { "BC_BG_TEMPLATES", 0x46E3CC, 0x46DCA8 },
  { "BC_TEXT_COLORS", 0x46E3DC, 0x46DCB8 },
  { "BC_WIN_RANKINGS", 0x46E3F0, 0x46DCCC },
  { "BC_WIN_PLAYER_NAMES", 0x46E3F8, 0x46DCD4 },
  { "BC_WIN_RESULTS", 0x46E428, 0x46DD04 },
  { "BC_RESULTS_WINDOW_HEIGHTS", 0x46E448, 0x46DD24 },
  { "BC_PRESSING_SPEED_TABLE", 0x46E450, 0x46DD2C },
  { "BC_PLAYER_ID_TO_POS_ID", 0x46F280, 0x46EB5C },
  { "BC_PLAYER_COORDS", 0x46F294, 0x46EB70 },
  { "BC_IMPACT_COORDS", 0x46F2D0, 0x46EBAC },
  { "BC_SPARKLE_COORDS", 0x46F2D6, 0x46EBB2 },
  { "BC_DIGIT_TEMPLATES", 0x46F488, 0x46ED64 },
  { "DBP_BG_PAL", 0x4758A8, 0x475184 },
  { "DBP_DODRIO_PAL", 0x4758E8, 0x4751C4 },
  { "DBP_DODRIO_SHINY_PAL", 0x475908, 0x4751E4 },
  { "DBP_STATUS_PAL", 0x475928, 0x475204 },
  { "DBP_BERRIES_PAL", 0x475948, 0x475224 },
  { "DBP_BERRIES_GFX", 0x475968, 0x475244 },
  { "DBP_CLOUD_PAL", 0x475B1C, 0x4753F8 },
  { "DBP_BG_GFX", 0x475B3C, 0x475418 },
  { "DBP_TREE_BORDER_GFX", 0x4763CC, 0x475CA8 },
  { "DBP_STATUS_GFX", 0x477198, 0x476A74 },
  { "DBP_CLOUD_GFX", 0x47722C, 0x476B08 },
  { "DBP_DODRIO_GFX", 0x477374, 0x476C50 },
  { "DBP_BG_MAP", 0x478590, 0x477E6C },
  { "DBP_TREE_RIGHT_MAP", 0x4787FC, 0x4780D8 },
  { "DBP_TREE_LEFT_MAP", 0x478A4C, 0x478328 },
  { "DBP_ACTIVE_COLUMN_MAP", 0x471F50, 0x47182C },
  { "DBP_HEAD_TO_COLUMN_MAP", 0x472063, 0x47193F },
  { "DBP_NEIGHBOR_MAP", 0x4720AE, 0x47198A },
  { "DBP_PLAYER_ID_AT_COLUMN", 0x4720FC, 0x4719D8 },
  { "DBP_UNSHARED_COLUMNS", 0x472133, 0x471A0F },
  { "DBP_BERRY_FALL_DELAYS", 0x47553C, 0x474E18 },
  { "DBP_TREE_BORDER_X", 0x475548, 0x474E24 },
  { "DBP_DIFFICULTY_THRESHOLDS", 0x475550, 0x474E2C },
  { "DBP_PRIZE_BERRY_IDS", 0x475558, 0x474E34 },
  { "DBP_BERRY_SCORE_MULT", 0x4755D8, 0x474EB4 },
  { "DBP_WIN_RECORDS", 0x4755E0, 0x474EBC },
  { "DBP_RECORD_MAX_DIGITS", 0x4755F8, 0x474ED4 },
  { "DBP_RECORD_TEXT_Y", 0x4755FC, 0x474ED8 },
  { "DBP_RECORD_NUM_Y", 0x475602, 0x474EDE },
  { "DBP_BG_TEMPLATES", 0x47565C, 0x474F38 },
  { "DBP_WIN_RESULTS", 0x475674, 0x474F50 },
  { "DBP_WIN_PRIZE", 0x475684, 0x474F60 },
  { "DBP_WIN_PLAY_AGAIN", 0x47568C, 0x474F68 },
  { "DBP_WIN_DROPPED_OUT", 0x47569C, 0x474F78 },
  { "DBP_WIN_COMM_STANDBY", 0x4756A4, 0x474F80 },
  { "DBP_BERRY_ICON_X", 0x478DD4, 0x4786B0 },
  { "DBP_CLOUD_MOVE_DELAYS", 0x478E0C, 0x4786E8 },
  { "DBP_CLOUD_START", 0x478E0E, 0x4786EA },
  { "DBP_TEXT_COLORS", 0x478E38, 0x478714 },
  { "DBP_NAME_WIN_1P", 0x478E44, 0x478720 },
  { "DBP_NAME_WIN_2P", 0x478E48, 0x478724 },
  { "DBP_NAME_WIN_3P", 0x478E50, 0x47872C },
  { "DBP_NAME_WIN_4P", 0x478E5C, 0x478738 },
  { "DBP_NAME_WIN_5P", 0x478E6C, 0x478748 },
  { "DBP_RESULTS_X", 0x478EA8, 0x478784 },
  { "DBP_RESULTS_Y", 0x478EB0, 0x47878C },
  { "DBP_RANKING_Y", 0x478EBA, 0x478796 },
  { "PJ_INTERFACE_PAL", 0x46B794, 0x46B070 },
  { "PJ_BG_PAL", 0x46B7B4, 0x46B090 },
  { "PJ_BG_GFX", 0x46B7D4, 0x46B0B0 },
  { "PJ_BG_MAP", 0x46BA00, 0x46B2DC },
  { "PJ_VENUSAUR_PAL", 0x46BBB0, 0x46B48C },
  { "PJ_VENUSAUR_GFX", 0x46BBD0, 0x46B4AC },
  { "PJ_VENUSAUR_MAP", 0x46C520, 0x46BDFC },
  { "PJ_BONUSES_PAL", 0x46C8D8, 0x46C1B4 },
  { "PJ_BONUSES_GFX", 0x46C8F8, 0x46C1D4 },
  { "PJ_BONUSES_MAP", 0x46D3A8, 0x46CC84 },
  { "PJ_PAL1", 0x46D9E4, 0x46D2C0 },
  { "PJ_PAL2", 0x46DA04, 0x46D2E0 },
  { "PJ_VINE1_GFX", 0x46DA24, 0x46D300 },
  { "PJ_VINE2_GFX", 0x46DB44, 0x46D420 },
  { "PJ_VINE3_GFX", 0x46DD18, 0x46D5F4 },
  { "PJ_VINE4_GFX", 0x46DE48, 0x46D724 },
  { "PJ_STAR_GFX", 0x46DF44, 0x46D820 },
  { "PJ_MONS", 0x46B4BC, 0x46AD98 },
  { "PJ_VINE_BASE_SPEEDS", 0x46B694, 0x46AF70 },
  { "PJ_VINE_SPEED_DELAYS", 0x46B6A4, 0x46AF80 },
  { "PJ_SOUND_EFFECTS", 0x46B6AC, 0x46AF88 },
  { "PJ_JUMP_OFFSETS", 0x46B6B4, 0x46AF90 },
  { "PJ_SCORE_BONUSES", 0x46B744, 0x46B020 },
  { "PJ_PRIZE_ITEMS", 0x46B75C, 0x46B038 },
  { "PJ_PRIZE_QUANTITY", 0x46B76C, 0x46B048 },
  { "PJ_BG_TEMPLATES", 0x46D8D4, 0x46D1B0 },
  { "PJ_WINDOW_TEMPLATES", 0x46D8E4, 0x46D1C0 },
  { "PJ_VENUSAUR_STATES", 0x46D953, 0x46D22F },
  { "PJ_NAME_WIN_2P", 0x46D970, 0x46D24C },
  { "PJ_NAME_WIN_3P", 0x46D978, 0x46D254 },
  { "PJ_NAME_WIN_4P", 0x46D984, 0x46D260 },
  { "PJ_NAME_WIN_5P", 0x46D994, 0x46D270 },
  { "PJ_MON_X_2P", 0x46D9B8, 0x46D294 },
  { "PJ_MON_X_3P", 0x46D9BC, 0x46D298 },
  { "PJ_MON_X_4P", 0x46D9C2, 0x46D29E },
  { "PJ_MON_X_5P", 0x46D9CA, 0x46D2A6 },
  { "PJ_VINE_Y", 0x46E100, 0x46D9DC },
  { "PJ_VINE_X", 0x46E150, 0x46DA2C },
  { "PJ_WIN_RECORDS", 0x46E2CC, 0x46DBA8 },
}

check(Versions.CACHE_VERSION >= 122, "cache version carries the gen 3 online assets")

print("[test] 1. every new address is pret's symbol in both editions")
local bad = 0
for _, row in ipairs(ADDRESSES) do
  if Versions[row[1]] ~= row[2] then bad = bad + 1; print("  FireRed " .. row[1]) end
end
Versions.select("leafgreen")
for _, row in ipairs(ADDRESSES) do
  if Versions[row[1]] ~= row[3] then bad = bad + 1; print("  LeafGreen " .. row[1]) end
end
Versions.select("firered")
check(bad == 0, #ADDRESSES .. " addresses match pokefirered.elf and pokeleafgreen.elf")

print("[test] 2. the cache contract requires the new outputs for both editions")
local REQUIRED = {
  "data/generated/gba/chrome/manifest.lua",
  "data/generated/gba/chrome/scroll_arrows.rgba",
  "data/generated/gba/link/manifest.lua",
  "data/generated/gba/link/minigame_countdown_numbers.rgba",
  "data/generated/gba/link/countdown_321.rgba",
  "data/generated/gba/mystery_gift/manifest.lua",
  "data/generated/gba/mystery_gift/stamp_shadow_0.rgba",
  "data/generated/gba/mystery_gift/stamp_shadow_7.rgba",
  "data/generated/gba/union_room/avatars.lua",
  "data/generated/gba/chrome/fonts/latin_small_fg.rgba",
  "data/generated/gba/chrome/fonts/latin_small_shadow.rgba",
  "data/generated/gba/chrome/fonts/latin_small_widths.lua",
  "data/generated/gba/pokemon/party/slot_main_multi.rgba",
  "data/generated/gba/pokemon/party/slot_main_multi_selected.rgba",
  "data/generated/gba/pokemon/party/slot_wide_multi.rgba",
  "data/generated/gba/pokemon/party/slot_wide_multi_selected.rgba",
  "data/generated/gba/union_room/chat_text_entry_cursor.rgba",
  "data/generated/gba/union_room/chat_char_select_cursor.rgba",
  "data/generated/gba/union_room/chat_r_button.rgba",
}
local GAMES = {
  berry_crush = { "crusher", "crusher_base", "impact", "sparkle", "timer_digits", "bg", "container_cap",
    "crusher_top", "text_windows" },
  dodrio_berry_picking = { "berries", "bg", "cloud", "dodrio", "dodrio_shiny", "status", "tree_border_left",
    "tree_border_right" },
  pokemon_jump = { "bg", "bonuses", "star", "venusaur", "vine1", "vine2", "vine3", "vine4" },
}
for dir, keys in pairs(GAMES) do
  REQUIRED[#REQUIRED + 1] = "data/generated/gba/" .. dir .. "/manifest.lua"
  REQUIRED[#REQUIRED + 1] = "data/generated/gba/" .. dir .. "/tables.lua"
  for _, key in ipairs(keys) do
    REQUIRED[#REQUIRED + 1] = "data/generated/gba/" .. dir .. "/" .. key .. ".rgba"
  end
end
for _, version in ipairs({ "firered", "leafgreen" }) do
  local set = {}
  for _, p in ipairs(CacheContract.requiredFilesFor(version)) do set[p] = true end
  local missing = {}
  for _, p in ipairs(REQUIRED) do if not set[p] then missing[#missing + 1] = p end end
  check(#missing == 0, version .. " requires the online asset outputs " .. table.concat(missing, " "))
end

print("[test] 3. the bundled lock glyphs are 8x8 PNGs")
local function pngSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local head = f:read(24); f:close()
  if not head or head:sub(2, 4) ~= "PNG" then return nil end
  local function be(i) local a, b, c, d = head:byte(i, i + 3) return ((a * 256 + b) * 256 + c) * 256 + d end
  return be(17), be(21)
end
for _, g in ipairs({ { "lock8.png", 8 } }) do
  local w, h = pngSize("assets/game3/" .. g[1])
  check(w == g[2] and h == g[2], "assets/game3/" .. g[1] .. " is " .. g[2] .. "x" .. g[2])
end
for _, name in ipairs({ "lock.png", "lock8_white.png", "lock16.png", "lock16_white.png" }) do
  check(io.open("assets/game3/" .. name, "rb") == nil, "assets/game3/" .. name .. " is not bundled")
end

print("[test] 3b. colour 0 of any bank on an opaque layer shows the backdrop")
do
  local gfx = { _len = 64 }
  for i = 1, 32 do gfx[i] = 0 end
  for i = 33, 64 do gfx[i] = 0x11 end
  local banks = { [0] = { [0] = 0x001F, [1] = 0x03E0 }, [1] = { [0] = 0x7C00, [1] = 0x7FFF } }
  local map = { 0x00, 0x10, 0x01, 0x10, _len = 4 }
  local rgba = AssetPack.bg(gfx, banks, map, 2, 16, 8, { alpha0 = false, backdrop = banks[0][0] })
  check(rgba:sub(1, 4) == string.char(255, 0, 0, 255) and rgba:sub(33, 36) == string.char(255, 255, 255, 255),
    "bank 1 colour 0 bakes the BG palette 0 backdrop, colour 1 keeps bank 1")
end

print("[test] 4. the serializer round-trips sparse and nested tables")
local chunk = loadstring(AssetPack.serialize({ a = { 1, -2, 3 }, [2] = { x = 1 }, [5] = { 4 }, s = "q" }))
local t = chunk and chunk()
check(t and t.a[2] == -2 and t[2].x == 1 and t[5][1] == 4 and t.s == "q", "serialize keeps sparse integer keys")

local root = os.getenv("POKEFIRERED") or "../pokefirered"
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close()
  return d
end

local LZ = {
  { "BC_CRUSHER_GFX", "berry_crush/crusher.4bpp" },
  { "BC_CORE_GFX", "berry_crush/crusher_base.4bpp" },
  { "BC_IMPACT_GFX", "berry_crush/impact.4bpp" },
  { "BC_SPARKLE_GFX", "berry_crush/sparkle.4bpp" },
  { "BC_TIMER_GFX", "berry_crush/timer_digits.4bpp" },
  { "BC_CRUSHER_TOP_MAP", "berry_crush/crusher_top.bin" },
  { "BC_CONTAINER_CAP_MAP", "berry_crush/container_cap.bin" },
  { "BC_BG_MAP", "berry_crush/bg.bin" },
  { "BC_TEXT_WINDOWS_MAP", "berry_crush/text_windows.bin" },
  { "DBP_BERRIES_GFX", "dodrio_berry_picking/berries.4bpp" },
  { "DBP_BG_GFX", "dodrio_berry_picking/bg.4bpp" },
  { "DBP_TREE_BORDER_GFX", "dodrio_berry_picking/tree_border.4bpp" },
  { "DBP_STATUS_GFX", "dodrio_berry_picking/status.4bpp" },
  { "DBP_CLOUD_GFX", "dodrio_berry_picking/cloud.4bpp" },
  { "DBP_DODRIO_GFX", "dodrio_berry_picking/dodrio.4bpp" },
  { "DBP_BG_MAP", "dodrio_berry_picking/bg.bin" },
  { "DBP_TREE_RIGHT_MAP", "dodrio_berry_picking/tree_border_right.bin" },
  { "DBP_TREE_LEFT_MAP", "dodrio_berry_picking/tree_border_left.bin" },
  { "PJ_BG_GFX", "pokemon_jump/bg.4bpp" },
  { "PJ_BG_MAP", "pokemon_jump/bg.bin" },
  { "PJ_VENUSAUR_GFX", "pokemon_jump/venusaur.4bpp" },
  { "PJ_VENUSAUR_MAP", "pokemon_jump/venusaur.bin" },
  { "PJ_BONUSES_GFX", "pokemon_jump/bonuses.4bpp" },
  { "PJ_BONUSES_MAP", "pokemon_jump/bonuses.bin" },
  { "PJ_VINE1_GFX", "pokemon_jump/vine1.4bpp" },
  { "PJ_VINE2_GFX", "pokemon_jump/vine2.4bpp" },
  { "PJ_VINE3_GFX", "pokemon_jump/vine3.4bpp" },
  { "PJ_VINE4_GFX", "pokemon_jump/vine4.4bpp" },
  { "PJ_STAR_GFX", "pokemon_jump/star.4bpp" },
  { "SCROLL_ARROW_GFX", "interface/red_arrow_other.4bpp" },
  { "SELECTOR_OUTLINE_GFX", "interface/selector_outline.4bpp" },
  { "RED_ARROW_CURSOR_GFX", "interface/red_arrow.4bpp" },
  { "MG_COUNTDOWN_GFX", "misc/minigame_countdown.4bpp" },
  { "MG_321START_GFX", "link/321start.4bpp" },
  { "MG_DIGITS_GFX", "misc/minigame_digits.4bpp" },
  { "WONDER_STAMP_SHADOW_GFX", "wonder_card/stamp_shadow.4bpp" },
  { "MYSTERY_GIFT_BORDER_GFX", "interface/mystery_gift_textbox_border.4bpp" },
}
local PALS = {
  { "BC_CRUSHER_PAL", { "berry_crush/crusher.gbapal" } },
  { "BC_CORE_PAL", { "berry_crush/crusher_base.gbapal" } },
  { "BC_EFFECT_PAL", { "berry_crush/impact.gbapal" } },
  { "BC_TIMER_PAL", { "berry_crush/timer_digits.gbapal" } },
  { "DBP_BG_PAL", { "dodrio_berry_picking/bg.gbapal", "dodrio_berry_picking/tree_border.gbapal" } },
  { "DBP_DODRIO_PAL", { "dodrio_berry_picking/dodrio.gbapal" } },
  { "DBP_DODRIO_SHINY_PAL", { "dodrio_berry_picking/shiny.gbapal" } },
  { "DBP_STATUS_PAL", { "dodrio_berry_picking/status.gbapal" } },
  { "DBP_BERRIES_PAL", { "dodrio_berry_picking/berries.gbapal" } },
  { "DBP_CLOUD_PAL", { "dodrio_berry_picking/cloud.gbapal" } },
  { "PJ_INTERFACE_PAL", { "pokemon_jump/interface.gbapal" } },
  { "PJ_BG_PAL", { "pokemon_jump/bg.gbapal" } },
  { "PJ_VENUSAUR_PAL", { "pokemon_jump/venusaur.gbapal" } },
  { "PJ_BONUSES_PAL", { "pokemon_jump/bonuses.gbapal" } },
  { "PJ_PAL1", { "pokemon_jump/pal1.gbapal" } },
  { "PJ_PAL2", { "pokemon_jump/pal2.gbapal" } },
  { "SCROLL_ARROW_PAL", { "interface/red_arrow.gbapal" } },
  { "MG_COUNTDOWN_PAL", { "misc/minigame_countdown.gbapal" } },
  { "MG_321START_PAL", { "link/321start.gbapal" } },
  { "MG_DIGITS_PAL", { "misc/minigame_digits.gbapal" } },
  { "WONDER_STAMP_SHADOW_PALS", { "wonder_card/stamp_shadow_0.gbapal", "wonder_card/stamp_shadow_1.gbapal",
    "wonder_card/stamp_shadow_2.gbapal", "wonder_card/stamp_shadow_3.gbapal", "wonder_card/stamp_shadow_4.gbapal",
    "wonder_card/stamp_shadow_5.gbapal", "wonder_card/stamp_shadow_6.gbapal", "wonder_card/stamp_shadow_7.gbapal" } },
  { "MYSTERY_GIFT_BORDER_PAL", { "interface/mystery_gift_textbox_border.gbapal" } },
}

local ROMS = {
  { "pokefirered.gba", "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" },
  { "pokeleafgreen.gba", "574fa542ffebb14be69902d1d36f1ec0a4afd71e" },
  { "pokefirered_rev1.gba", "dd5945db9b930750cb39d00c84da8571feebf417" },
  { "pokeleafgreen_rev1.gba", "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e" },
}

local function stubCache()
  local written = {}
  return written, {
    write = function(_, rel, bytes) written[rel] = bytes; return true end,
    read = function(_, rel) return written[rel] end,
    exists = function(_, rel) return written[rel] ~= nil end,
  }
end

local function sizedEntries(written, dir, man, section)
  local badFiles = {}
  for key, row in pairs(man[section] or {}) do
    if type(row) == "table" and row.file and row.width and row.height then
      local blob = written[dir .. "/" .. row.file]
      if not blob or #blob ~= row.width * row.height * 4 then badFiles[#badFiles + 1] = key end
    end
  end
  return badFiles
end

local function pixelHas(blob, rgb)
  for i = 1, #blob, 4 do
    if blob:byte(i + 3) ~= 0 and blob:sub(i, i + 2) == rgb then return true end
  end
  return false
end

local function palIdRgb(pal, id)
  local lo, hi = pal:byte(id * 2 + 1, id * 2 + 2)
  local r, g, b = require("src.import.gba.bg_bake").bgr555ToRgb8((hi or 0) * 256 + (lo or 0))
  return string.char(r, g, b)
end

local deoxys = {}
local ranAny = false
for n, case in ipairs(ROMS) do
  local data = readFile(root .. "/" .. case[1])
  if not data then
    print("[skip] " .. case[1] .. " not built in " .. root)
  else
    ranAny = true
    print("[test] 5." .. n .. " " .. case[1] .. " extracts the online asset set byte-exact to pret")
    local rom = assert(require("src.import.gba.rom").open({
      info = function() return { size = #data, md5 = case[2] } end,
      read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
    }, GV.forSha1(case[2])))
    local lzBad = {}
    for _, row in ipairs(LZ) do
      local want = readFile(root .. "/graphics/" .. row[2])
      local got = AssetPack.bytes(AssetPack.lz(rom, Versions[row[1]]))
      if not want or got ~= want then lzBad[#lzBad + 1] = row[1] end
    end
    check(#lzBad == 0, #LZ .. " compressed sheets and tilemaps decode to pret's files " .. table.concat(lzBad, " "))
    local palBad = {}
    for _, row in ipairs(PALS) do
      local parts = {}
      for i, file in ipairs(row[2]) do parts[i] = readFile(root .. "/graphics/" .. file) or "" end
      local want = table.concat(parts)
      local got = AssetPack.bytes(AssetPack.raw(rom, Versions[row[1]], #want))
      if #want == 0 or got ~= want then palBad[#palBad + 1] = row[1] end
    end
    check(#palBad == 0, #PALS .. " palettes match pret's .gbapal files " .. table.concat(palBad, " "))

    local written, cache = stubCache()
    for _, name in ipairs(EXTRACTORS) do
      local M = require("src.import.gba." .. name)
      check(M.ready(cache, "x") == false, name .. ".ready() starts false")
      local ok, err = pcall(M.run, rom, cache, { cacheRoot = "x" })
      check(ok, name .. ".run() completes (" .. tostring(err) .. ")")
      check(M.ready(cache, "x") == true, name .. ".ready() is true after run()")
    end
    for dir, keys in pairs(GAMES) do
      local man = AssetPack.loadManifest(cache, "x/" .. dir .. "/manifest.lua")
      check(man ~= nil and man.format_version == 1, dir .. "/manifest.lua loads")
      if man then
        local bad = {}
        for _, key in ipairs(keys) do
          local row = man[key]
          local blob = row and written["x/" .. dir .. "/" .. key .. ".rgba"]
          if not (row and row.kind and row.file == key .. ".rgba" and blob and #blob == row.width * row.height * 4) then
            bad[#bad + 1] = key
          end
        end
        check(#bad == 0, dir .. " carries every interfaces.md 10.3 key at its manifest size " .. table.concat(bad, " "))
        local extra = sizedEntries(written, "x/" .. dir, { all = man }, "all")
        check(#extra == 0, dir .. " every other manifest entry matches its blob " .. table.concat(extra, " "))
        for _, row in pairs(man._palettes or {}) do
          local blob = written["x/" .. dir .. "/" .. row.file]
          check(blob and #blob == row.banks * 48, dir .. "/" .. row.file .. " holds " .. row.banks .. " banks")
        end
      end
    end
    for _, name in ipairs({ "text_chrome_extract", "mystery_gift_extract" }) do
      local ok, err = pcall(require("src.import.gba." .. name).run, rom, cache, { cacheRoot = "x" })
      check(ok, name .. ".run() completes with the new art (" .. tostring(err) .. ")")
    end
    do
      -- src/text.c:1380
      local fg = written["x/chrome/fonts/latin_small_fg.rgba"] or ""
      local sh = written["x/chrome/fonts/latin_small_shadow.rgba"] or ""
      check(#fg == 256 * 512 * 4 and #sh == 256 * 512 * 4, "latin_small sheets hold all 512 FONT_SMALL glyphs")
      local wchunk = loadstring(written["x/chrome/fonts/latin_small_widths.lua"] or "")
      local widths = wchunk and wchunk() or {}
      local count = 0
      for _ in pairs(widths) do count = count + 1 end
      check(count == 512 and widths[511] ~= nil, "latin_small_widths has 512 entries")
      local gid, lit = 0x1DD, false
      local ox, oy = (gid % 16) * 16, math.floor(gid / 16) * 16
      for y = oy, oy + 15 do
        for x = ox, ox + 15 do
          if fg:byte((y * 256 + x) * 4 + 4) == 255 then lit = true end
        end
      end
      check(lit, "latin_small glyph 0x1DD is drawn")
      local ls = ((AssetPack.loadManifest(cache, "x/chrome/manifest.lua") or {}).fonts or {}).latin_small or {}
      check(ls.width == 256 and ls.height == 512 and ls.glyphs == 512, "chrome manifest lists latin_small at 512 glyphs")
    end
    do
      local pwritten, pcache = stubCache()
      local ok, err = pcall(require("src.import.gba.pokemon_extract").run, rom, pcache,
        { cacheRoot = "x", numSpecies = 411 })
      check(ok, "pokemon_extract.run() completes (" .. tostring(err) .. ")")
      local mchunk = loadstring(pwritten["x/pokemon/meta.lua"] or "")
      local meta = mchunk and mchunk() or {}
      local ls = (meta[410] or {}).linkStats or {}
      -- src/data/pokemon/species_info.h:11199
      check(table.concat(ls, ",") == "50,150,50,150,150,50", "Deoxys meta carries the link battle linkStats")
      local schunk = loadstring(pwritten["x/pokemon/stats.lua"] or "")
      local s = (schunk and schunk() or {})[410] or {}
      deoxys[case[1]] = table.concat({ s.hp or 0, s.atk or 0, s.def or 0, s.spe or 0, s.spa or 0, s.spd or 0 }, ",")

      ok, err = pcall(require("src.import.gba.party_chrome_extract").run, rom, pcache, { cacheRoot = "x" })
      check(ok, "party_chrome_extract.run() completes (" .. tostring(err) .. ")")
      local pal = readFile(root .. "/graphics/party_menu/bg.gbapal") or ""
      local p = "x/pokemon/party/"
      -- src/party_menu.c:2273
      for _, row in ipairs({
        { "slot_main_multi", "slot_main", 80 * 56, { 68, 69, 70 }, { 52, 53, 54 } },
        { "slot_main_multi_selected", "slot_main_selected", 80 * 56, { 132, 133, 134 }, { 116, 117, 118 } },
        { "slot_wide_multi", "slot_wide", 144 * 24, { 68, 69, 70 }, { 52, 53, 54 } },
        { "slot_wide_multi_selected", "slot_wide_selected", 144 * 24, { 132, 133, 134 }, { 116, 117, 118 } },
      }) do
        local blob, plain = pwritten[p .. row[1] .. ".rgba"], pwritten[p .. row[2] .. ".rgba"]
        local tinted, used = blob ~= nil and plain ~= nil and #pal == 352, 0
        for i, id in ipairs(row[4]) do
          if tinted and pixelHas(plain, palIdRgb(pal, row[5][i])) then
            used = used + 1
            if not pixelHas(blob, palIdRgb(pal, id)) then tinted = false end
          end
        end
        check(blob and plain and #blob == row[3] * 4 and #plain == #blob and blob ~= plain and tinted and used >= 2,
          row[1] .. " is " .. row[2] .. " in the multi partner palette")
      end
    end
    for _, rel in ipairs({ "x/chrome/manifest.lua", "x/link/manifest.lua", "x/mystery_gift/manifest.lua" }) do
      local man = AssetPack.loadManifest(cache, rel)
      local d = rel:match("^(.*)/")
      local sizes = {}
      for key, row in pairs(man or {}) do
        if type(row) == "table" and row.file then
          local blob = written[d .. "/" .. row.file]
          if not blob or #blob ~= row.width * row.height * 4 then sizes[#sizes + 1] = key end
        end
      end
      check(man ~= nil and #sizes == 0, rel .. " entries match their blobs " .. table.concat(sizes, " "))
    end
    local chrome = AssetPack.loadManifest(cache, "x/chrome/manifest.lua") or {}
    local sa = chrome.scroll_arrows or {}
    check(sa.frames == 4 and sa.frame_w == 16 and sa.frame_h == 16 and sa.width == 16 and sa.height == 64
      and chrome.fonts ~= nil, "chrome manifest keeps its fonts and gains scroll_arrows")
    local gift = AssetPack.loadManifest(cache, "x/mystery_gift/manifest.lua") or {}
    check(gift.stamps and gift.stamps.variants == 8 and gift.stamps.width == 32 and gift.stamp_shadow_7
      and #(gift.entries or {}) == 16, "mystery gift manifest keeps its entries and gains stamps")
    local link = AssetPack.loadManifest(cache, "x/link/manifest.lua") or {}
    check(link.countdown_321 and link.countdown_321.frames == 6 and link.minigame_countdown_numbers,
      "link manifest carries countdown_321 and the live minigame countdown")

    local function tbl(rel)
      local man = AssetPack.loadManifest(cache, rel)
      return man or {}
    end
    local bc = tbl("x/berry_crush/tables.lua")
    -- src/berry.c:871
    check(bc.berry_data and #bc.berry_data == 43 and bc.berry_data[1].difficulty == 50
      and bc.berry_data[1].powder == 20 and bc.berry_data[43].powder == 200
      and bc.berry_data[42].powder == 750, "berry crush berry data is gBerryCrush_BerryData")
    -- src/berry_crush.c:428
    check(bc.sync_press_bonus and bc.sync_press_bonus[5] == 5 and bc.player_coords[2].impactXOffset == -28
      and bc.player_coords[4].windowGfxX == 20 and bc.pressing_speed_table[1] == 50000000,
      "berry crush press bonus, seat coords and speed table")
    check(bc.bg_templates and bc.bg_templates[2].screenSize == 2 and bc.bg_templates[2].mapBaseIndex == 13
      and bc.win_player_names[4].left == 21 and bc.win_player_names[1].baseBlock == 0x3ED,
      "berry crush bg and window templates")
    local dbp = tbl("x/dodrio_berry_picking/tables.lua")
    -- src/dodrio_berry_picking.c:644
    check(dbp.difficulty_thresholds and dbp.difficulty_thresholds[7] == 100 and dbp.tree_border_x[5] == 15
      and dbp.berry_fall_delays[1][1] == 40 and dbp.berry_score_multipliers[2] == 30
      and dbp.name_window_coords[5][4].left == 1 and dbp.active_column_map[5][1] ~= nil,
      "dodrio thresholds, fall delays, score multipliers and name windows")
    local pj = tbl("x/pokemon_jump/tables.lua")
    -- src/pokemon_jump.c:768
    check(pj.jump_mons and #pj.jump_mons == 100 and pj.jump_mons[1].species == 1 and pj.jump_mons[1].jumpType == 2
      and pj.vine_base_speeds[8] == 61 and pj.prize_quantity[5].score == 20000 and pj.vine_x[8] == 224
      and pj.mon_x_coords[5][5] == 184 and pj.player_name_window_coords[2][2][1] == 16
      and pj.score_bonuses[6] == 500 and pj.jump_offsets[1][1] == -3,
      "pokemon jump species, vine speeds, prizes and coords")
    local av = tbl("x/union_room/avatars.lua")
    -- src/union_room_player_avatar.c:33
    local gids = {}
    for _, g in ipairs((av.gfx_ids or {}).male or {}) do gids[#gids + 1] = g end
    for _, g in ipairs((av.gfx_ids or {}).female or {}) do gids[#gids + 1] = g end
    local inRange = #gids == 16
    for _, g in ipairs(gids) do if g >= Versions.NUM_OBJ_EVENT_GFX then inRange = false end end
    check(inRange and av.gfx_ids.male[1] == 41 and av.gfx_ids.female[8] == 29 and av.leader_coords[2][1] == 13,
      "union room avatars are 16 OW gids the ow/ extractor covers")
  end
end
if not ranAny then
  print("[skip] no pret build at " .. root .. "; ROM checks skipped")
end
if deoxys["pokefirered.gba"] and deoxys["pokeleafgreen.gba"] then
  check(deoxys["pokefirered.gba"] ~= deoxys["pokeleafgreen.gba"],
    "Deoxys base stats differ between FireRed and LeafGreen while linkStats match")
end

finish()

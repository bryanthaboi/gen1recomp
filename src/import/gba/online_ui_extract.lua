-- src/menu_indicators.c:258, src/minigame_countdown.c:213, src/union_room_player_avatar.c:33

local Versions = require("src.import.gba.versions")
local AssetPack = require("src.import.gba.asset_pack")

local OnlineUiExtract = {}

OnlineUiExtract.FORMAT_VERSION = 1
OnlineUiExtract.LINK_SUB = "link"
OnlineUiExtract.AVATARS = "union_room/avatars.lua"
OnlineUiExtract.STAMP_COUNT = 8

local SCREEN_W, SCREEN_H = 240, 160
local T = 8

local function need(buf, n, what)
  if AssetPack.len(buf) < n then
    error(string.format("online_ui: %s decompressed to %d bytes, want %d", what, AssetPack.len(buf), n))
  end
  return buf
end

local function sprite(key, fw, fh, frames, extra)
  local row = {
    file = key .. ".rgba", kind = "sprite", width = fw, height = fh * frames,
    frame_w = fw, frame_h = fh, frames = frames,
  }
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end

-- src/menu_indicators.c:99-121
function OnlineUiExtract.listChrome(rom, write, dir)
  local bank = AssetPack.banks(rom, Versions.SCROLL_ARROW_PAL, 1)[0]
  local arrows = need(AssetPack.lz(rom, Versions.SCROLL_ARROW_GFX), 0x100, "scroll arrows")
  write(dir .. "/scroll_arrows.rgba", AssetPack.frames(arrows, bank, {
    { tile = 0 }, { tile = 0, hflip = true }, { tile = 4 }, { tile = 4, vflip = true },
  }, 16, 16))
  local cursor = need(AssetPack.lz(rom, Versions.RED_ARROW_CURSOR_GFX), 0x80, "red arrow cursor")
  write(dir .. "/red_arrow_cursor.rgba", AssetPack.frame(cursor, bank, 0, 16, 16))
  local outline = need(AssetPack.lz(rom, Versions.SELECTOR_OUTLINE_GFX), 0x100, "selector outline")
  write(dir .. "/selector_outline.rgba", AssetPack.strip(outline, bank, 0, 1, 8, 8, 8))
  write(dir .. "/red_arrow.pal", AssetPack.palRgb({ [0] = bank }, 0, 1))

  local bounce = {}
  for i = 0, 3 do
    local off = Versions.SCROLL_INDICATOR_TEMPLATES + i * 4
    local b0 = rom:get(off)
    bounce[i + 1] = {
      animNum = b0 % 16, bounceDir = math.floor(b0 / 16),
      multiplier = rom:get(off + 1), frequency = AssetPack.read(rom, off + 2, "s16"),
    }
  end
  return {
    scroll_arrows = sprite("scroll_arrows", 16, 16, 4, {
      order = { "left", "right", "up", "down" }, palette = "red_arrow.pal", bounce = bounce,
    }),
    red_arrow_cursor = sprite("red_arrow_cursor", 16, 16, 1, { palette = "red_arrow.pal" }),
    selector_outline = sprite("selector_outline", 8, 8, 8, { palette = "red_arrow.pal" }),
  }
end

function OnlineUiExtract.manifestRows(rows)
  local body = AssetPack.serialize(rows)
  return (body:gsub("^return {\n", ""):gsub("\n}\n$", ""))
end

-- src/minigame_countdown.c:216, src/pokemon_jump.c:457, src/digit_obj_util.c:67
local function linkArt(rom, cache, root)
  local dir = root .. "/" .. OnlineUiExtract.LINK_SUB
  local cdBank = AssetPack.banks(rom, Versions.MG_COUNTDOWN_PAL, 1)[0]
  local cd = need(AssetPack.lz(rom, Versions.MG_COUNTDOWN_GFX), 0xE00, "minigame countdown")
  cache:write(dir .. "/minigame_countdown_numbers.rgba", AssetPack.strip(cd, cdBank, 0, 16, 32, 32, 3))
  cache:write(dir .. "/minigame_countdown_start.rgba", AssetPack.frames(cd, cdBank,
    { { tile = 48 }, { tile = 80 } }, 64, 32))
  cache:write(dir .. "/minigame_countdown.pal", AssetPack.palRgb({ [0] = cdBank }, 0, 1))

  local stBank = AssetPack.banks(rom, Versions.MG_321START_PAL, 1)[0]
  local st = need(AssetPack.lz(rom, Versions.MG_321START_GFX), 0xC00, "321start")
  cache:write(dir .. "/countdown_321.rgba", AssetPack.strip(st, stBank, 0, 16, 32, 32, 6))
  cache:write(dir .. "/countdown_321.pal", AssetPack.palRgb({ [0] = stBank }, 0, 1))

  local dgBank = AssetPack.banks(rom, Versions.MG_DIGITS_PAL, 1)[0]
  local dg = need(AssetPack.lz(rom, Versions.MG_DIGITS_GFX), 11 * 32, "minigame digits")
  cache:write(dir .. "/minigame_digits.rgba", AssetPack.strip(dg, dgBank, 0, 1, 8, 8, 11))
  cache:write(dir .. "/minigame_digits.pal", AssetPack.palRgb({ [0] = dgBank }, 0, 1))

  cache:write(dir .. "/manifest.lua", AssetPack.serialize({
    format_version = OnlineUiExtract.FORMAT_VERSION,
    minigame_countdown_numbers = sprite("minigame_countdown_numbers", 32, 32, 3, {
      order = { 3, 2, 1 }, palette = "minigame_countdown.pal",
    }),
    minigame_countdown_start = sprite("minigame_countdown_start", 64, 32, 2, {
      order = { "left", "right" }, palette = "minigame_countdown.pal",
    }),
    countdown_321 = sprite("countdown_321", 32, 32, 6, {
      order = { "three", "two", "one", "start_mid", "start_left", "start_right" }, palette = "countdown_321.pal",
    }),
    minigame_digits = sprite("minigame_digits", 8, 8, 11, { palette = "minigame_digits.pal" }),
  }))
end

-- src/mystery_gift_show_card.c:125, :481, src/mystery_gift_menu.c:492
function OnlineUiExtract.giftArt(rom, write, dir)
  local count = Versions.WONDER_STAMP_SHADOW_PAL_COUNT
  local banks = AssetPack.banks(rom, Versions.WONDER_STAMP_SHADOW_PALS, count)
  local shadow = need(AssetPack.lz(rom, Versions.WONDER_STAMP_SHADOW_GFX), 0x100, "stamp shadow")
  local rows = {
    stamps = {
      width = 32, height = 16, variants = count, key_prefix = "stamp_shadow_",
      slot_x = { 216, 184, 152, 120, 88, 56, 24 }, slot_y = 144, icon_y = 136,
    },
  }
  for i = 0, count - 1 do
    local key = "stamp_shadow_" .. i
    write(dir .. "/" .. key .. ".rgba", AssetPack.frame(shadow, banks[i], 0, 32, 16))
    rows[key] = sprite(key, 32, 16, 1, { palette = "stamp_shadow.pal", bank = i })
  end
  write(dir .. "/stamp_shadow.pal", AssetPack.palRgb(banks, 0, count))

  local borderBank = AssetPack.banks(rom, Versions.MYSTERY_GIFT_BORDER_PAL, 1)
  local border = need(AssetPack.lz(rom, Versions.MYSTERY_GIFT_BORDER_GFX), 0x100, "gift textbox border")
  write(dir .. "/border_tiles.rgba", AssetPack.strip(border, borderBank[0], 0, 1, 8, 8, 8))
  write(dir .. "/border.pal", AssetPack.palRgb(borderBank, 0, 1))
  rows.border_tiles = sprite("border_tiles", 8, 8, 8, { palette = "border.pal" })

  local map = { _len = 32 * 20 * 2 }
  for y = 0, 19 do
    for x = 0, 31 do
      local tile
      if y < 2 then
        tile = 3
      elseif ((y - 2) % 2) ~= (x % 2) then
        tile = 1
      else
        tile = 2
      end
      local i = (y * 32 + x) * 2
      map[i + 1] = tile
      map[i + 2] = 0
    end
  end
  write(dir .. "/menu_bg.rgba", AssetPack.bg(border, borderBank, map, 32, SCREEN_W, SCREEN_H, {}))
  rows.menu_bg = {
    file = "menu_bg.rgba", kind = "bg", width = SCREEN_W, height = SCREEN_H, top_rows = 2, tile = T,
  }
  return rows
end

-- src/union_room_player_avatar.c:33-95
local function avatars(rom, cache, root)
  local P = AssetPack
  local ids = P.grid(rom, Versions.UR_OBJ_GFX_IDS, "u8", { 2, 10 })
  local male, female = {}, {}
  for i = 1, 8 do male[i] = ids[1][i]; female[i] = ids[2][i] end
  cache:write(root .. "/" .. OnlineUiExtract.AVATARS, P.serialize({
    format_version = OnlineUiExtract.FORMAT_VERSION,
    gfx_ids = { male = male, female = female },
    leader_coords = P.grid(rom, Versions.UR_PLAYER_COORDS, "s16", { 8, 2 }),
    group_offsets = P.grid(rom, Versions.UR_GROUP_OFFSETS, "s8", { 5, 2 }),
    opposite_facing = P.array(rom, Versions.UR_OPPOSITE_FACING, "u8", 5),
    member_facing = P.array(rom, Versions.UR_MEMBER_FACING, "u8", 5),
  }))
  return male, female
end

function OnlineUiExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.cacheRoot or AssetPack.defaultRoot()
  linkArt(rom, cache, root)
  local male, female = avatars(rom, cache, root)
  print(string.format("[online_ui_extract] countdowns, digits, %d avatar gids -> %s", #male + #female, root))
  return { root = root }
end

function OnlineUiExtract.ready(cache, cacheRoot)
  local root = cacheRoot or AssetPack.defaultRoot()
  for _, rel in ipairs({ OnlineUiExtract.LINK_SUB .. "/manifest.lua", OnlineUiExtract.AVATARS }) do
    local man = AssetPack.loadManifest(cache, root .. "/" .. rel)
    if not man or man.format_version ~= OnlineUiExtract.FORMAT_VERSION then return false end
  end
  return AssetPack.sizedFile(cache, root .. "/link/countdown_321.rgba", 32 * 192 * 4)
end

return OnlineUiExtract

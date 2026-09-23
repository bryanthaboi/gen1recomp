-- src/trainer_card.c

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")

local TrainerCard = {}

TrainerCard.open = false
TrainerCard._session = nil
TrainerCard._onClose = nil
TrainerCard._card = nil

-- src/trainer_card.c:224 sTrainerCardWindowTemplates[1] tilemapLeft 1, tilemapTop 1
local WIN_X, WIN_Y = 8, 8

-- src/trainer_card.c:1145 x = -122 - 6 * StringLength(buffer)
local CHAR_ADVANCE = 6

local _badgesImg = nil
local _badgeQuads = nil
local _starImg = nil
local _stickersImg = nil
local _stickerQuads = nil
local _picRed = nil
local _picLeaf = nil
local _cards = nil
local _cardEdge = {}
local _screens = nil
local _assetsTried = false

local function read_cache_file(path)
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs then
    if CacheFs.readActive then
      local data = CacheFs.readActive(path)
      if data and #data > 0 then return data end
    end
    if CacheFs.read then
      local data = CacheFs.read(path)
      if data and #data > 0 then return data end
    end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(path)
    if d and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (path:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if d and #d > 0 then return d end
  end
  local f = io.open(path, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function load_rgba_image(candidates, w, h)
  if not (love and love.graphics) then return nil end
  for _, p in ipairs(candidates) do
    if p:sub(-5) == ".rgba" then
      local raw = read_cache_file(p)
      if raw and #raw >= w * h * 4 and love.image and love.image.newImageData then
        local ok, imgData = pcall(love.image.newImageData, w, h, "rgba8", raw)
        if ok and imgData then
          local img = love.graphics.newImage(imgData)
          if img.setFilter then img:setFilter("nearest", "nearest") end
          return img, raw
        end
      end
    else
      local bytes = read_cache_file(p)
      if bytes and #bytes > 0 and love.image and love.filesystem then
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(bytes, p:match("[^/]+$") or "img.png")
          local id = love.image.newImageData(fd)
          local image = love.graphics.newImage(id)
          if image.setFilter then image:setFilter("nearest", "nearest") end
          return image
        end)
        if ok and img then return img end
      end
      local ok, img = pcall(love.graphics.newImage, p)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
  end
  return nil
end

local function ensureAssets()
  if _assetsTried then return end
  _assetsTried = true
  _cards = {}
  _screens = {}

  _badgesImg = load_rgba_image({
    "trainer_card/badges.rgba",
    "data/generated/gba/trainer_card/badges.rgba",
    "trainer_card/badges.png",
    "data/generated/gba/trainer_card/badges.png",
  }, 128, 16)

  if _badgesImg and love and love.graphics and love.graphics.newQuad then
    _badgeQuads = {}
    local iw, ih = _badgesImg:getDimensions()
    for i = 0, 7 do
      _badgeQuads[i + 1] = love.graphics.newQuad(i * 16, 0, 16, 16, iw, ih)
    end
  end

  -- src/trainer_card.c:1553 FillBgTilemapBufferRect(3, 143, ...) tile 143 + sTrainerCardStar_Pal
  _starImg = load_rgba_image({
    "trainer_card/star.rgba",
    "data/generated/gba/trainer_card/star.rgba",
  }, 8, 8)

  -- src/trainer_card.c:1454 PrintStickersOnCard, 4 sticker tiles x 4 palette slots
  _stickersImg = load_rgba_image({
    "trainer_card/stickers.rgba",
    "data/generated/gba/trainer_card/stickers.rgba",
  }, 64, 64)

  if _stickersImg and love and love.graphics and love.graphics.newQuad then
    _stickerQuads = {}
    local iw, ih = _stickersImg:getDimensions()
    for pal = 1, 4 do
      _stickerQuads[pal] = {}
      for i = 1, 3 do
        _stickerQuads[pal][i] = love.graphics.newQuad((i - 1) * 16, (pal - 1) * 16, 16, 16, iw, ih)
      end
    end
  end

  _picRed = load_rgba_image({
    "trainers/front/135.rgba",
    "data/generated/gba/trainers/front/135.rgba",
    "trainer_card/red.png",
    "data/generated/gba/trainer_card/red.png",
    "data/generated/gba/trainers/front/135.png",
  }, 64, 64)

  _picLeaf = load_rgba_image({
    "trainers/front/136.rgba",
    "data/generated/gba/trainers/front/136.rgba",
    "trainer_card/leaf.png",
    "data/generated/gba/trainer_card/leaf.png",
    "data/generated/gba/trainers/front/136.png",
  }, 64, 64)
end

-- src/trainer_card.c:1482 sKantoTrainerCardPals[stars] picks the card colour
local function card_image(side, stars, female)
  ensureAssets()
  if not _cards then return nil end
  stars = math.max(0, math.min(4, tonumber(stars) or 0))
  local key = string.format("%s%d%s", side, stars, female and "f" or "m")
  if _cards[key] ~= nil then return _cards[key] or nil end

  local suffix = female and "_female" or ""
  local names = {
    string.format("trainer_card/%s_%d%s.rgba", side, stars, suffix),
    string.format("data/generated/gba/trainer_card/%s_%d%s.rgba", side, stars, suffix),
  }
  if female then
    names[#names + 1] = string.format("trainer_card/%s_%d.rgba", side, stars)
    names[#names + 1] = string.format("data/generated/gba/trainer_card/%s_%d.rgba", side, stars)
  end
  names[#names + 1] = "trainer_card/bg" .. suffix .. ".rgba"
  names[#names + 1] = "data/generated/gba/trainer_card/bg" .. suffix .. ".rgba"
  names[#names + 1] = "trainer_card/bg.rgba"
  names[#names + 1] = "data/generated/gba/trainer_card/bg.rgba"

  local img, raw = load_rgba_image(names, 240, 160)
  _cards[key] = img or false
  if raw and #raw >= 4 then
    _cardEdge[key] = {
      raw:byte(1) / 255,
      raw:byte(2) / 255,
      raw:byte(3) / 255,
    }
  end
  return img
end

-- src/trainer_card.c:1516 DrawCardScreenBackground keeps BG2 full size while BG0 flips
local function screen_image(stars, female)
  ensureAssets()
  if not _screens then return nil end
  stars = math.max(0, math.min(4, tonumber(stars) or 0))
  local key = string.format("%d%s", stars, female and "f" or "m")
  if _screens[key] ~= nil then return _screens[key] or nil end

  local suffix = female and "_female" or ""
  local names = {
    string.format("trainer_card/screen_%d%s.rgba", stars, suffix),
    string.format("data/generated/gba/trainer_card/screen_%d%s.rgba", stars, suffix),
  }
  if female then
    names[#names + 1] = string.format("trainer_card/screen_%d.rgba", stars)
    names[#names + 1] = string.format("data/generated/gba/trainer_card/screen_%d.rgba", stars)
  end
  local img = load_rgba_image(names, 240, 160)
  _screens[key] = img or false
  return img
end

-- pokefirered/include/constants/flags.h:1364-1371
local BADGE_FLAGS = { 0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827 }
local BADGE_NAMES = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }
do
  local okP, Profile = pcall(require, "src.core.game3.profile")
  if okP and Profile and Profile.active then
    local okA, row = pcall(Profile.active)
    local badges = okA and type(row) == "table" and row.badges
    if type(badges) == "table" and type(badges.flagBase) == "number"
        and type(badges.names) == "table" and badges.count == #badges.names then
      local flags = {}
      for i = 1, badges.count do flags[i] = badges.flagBase + i - 1 end
      BADGE_FLAGS, BADGE_NAMES = flags, badges.names
    end
  end
end

local FLAG_SYS_POKEDEX_GET = 0x829
local FLAG_SYS_NATIONAL_DEX = 0x840
-- src/trainer_card.c:899
local VAR_TRAINER_CARD_MON_ICON_TINT_IDX = 0x4042
local VAR_TRAINER_CARD_MON_ICON_1 = 0x4043
local VAR_HOF_BRAG_STATE = 0x4049
local VAR_EGG_BRAG_STATE = 0x404A
local VAR_LINK_WIN_BRAG_STATE = 0x404B

local function check_flags_table(flags, flagId, flagName)
  if not flags or type(flags) ~= "table" then return false end
  if flags[flagId] == true or (tonumber(flags[flagId]) or 0) > 0 then return true end
  if flags[tostring(flagId)] == true or (tonumber(flags[tostring(flagId)]) or 0) > 0 then return true end
  local hex = string.format("0x%X", flagId)
  if flags[hex] == true or (tonumber(flags[hex]) or 0) > 0 then return true end
  if flagName and (flags[flagName] == true or (tonumber(flags[flagName]) or 0) > 0) then return true end
  return false
end

local function is_badge_unlocked(session, badgeIndex)
  if not badgeIndex or badgeIndex < 1 or badgeIndex > 8 then return false end
  local flagId = BADGE_FLAGS[badgeIndex] or (0x820 + badgeIndex - 1)
  local bName = BADGE_NAMES[badgeIndex]
  local flagName = string.format("FLAG_BADGE0%d_GET", badgeIndex)

  if session then
    if session.badges then
      if type(session.badges) == "table" then
        if session.badges[badgeIndex] == true or (tonumber(session.badges[badgeIndex]) or 0) > 0 then
          return true
        end
        if bName and (session.badges[bName] == true or session.badges[bName:lower()] == true
            or session.badges[bName .. "_BADGE"] == true or session.badges[(bName .. "_BADGE"):lower()] == true
            or (tonumber(session.badges[bName]) or 0) > 0) then
          return true
        end
        if session.badges[flagId] == true or session.badges[tostring(flagId)] == true or session.badges[flagName] == true then
          return true
        end
      elseif type(session.badges) == "number" then
        local mask = bit and bit.lshift(1, badgeIndex - 1) or math.pow(2, badgeIndex - 1)
        if (bit and bit.band(session.badges, mask) ~= 0) or (math.floor(session.badges / mask) % 2 == 1) then
          return true
        end
      end
    end

    if session["badge" .. badgeIndex] == true or session["badge_" .. badgeIndex] == true then return true end
    if bName and (session[bName .. "_BADGE"] == true or session[(bName .. "_BADGE"):lower()] == true
        or session[bName] == true or session[bName:lower()] == true) then
      return true
    end

    if check_flags_table(session.flags, flagId, flagName) then return true end

    if session.store and check_flags_table(session.store.flags, flagId, flagName) then return true end

    local save = session.save or (session.game and session.game.save) or session
    if save and save.player and save.player.badges then
      local pb = save.player.badges
      if pb[badgeIndex] == true or pb[flagId] == true or (bName and pb[bName] == true) then
        return true
      end
    end
    if save and save.flags and check_flags_table(save.flags, flagId, flagName) then return true end
  end

  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = (Space and Space.getStore and Space.getStore()) or (Space and Space.store)
  if store and check_flags_table(store.flags, flagId, flagName) then return true end

  local okRt, Runtime = pcall(require, "src.core.game3.runtime")
  if okRt and Runtime and Runtime.getSession then
    local rtSess = Runtime.getSession()
    if rtSess and rtSess ~= session then
      if check_flags_table(rtSess.flags, flagId, flagName) then return true end
      if rtSess.store and check_flags_table(rtSess.store.flags, flagId, flagName) then return true end
    end
  end

  return false
end

local function script_store()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.getStore and Space.getStore()) or (Space and Space.store)
end

local function get_flag(session, flagId, flagName)
  if session and check_flags_table(session.flags, flagId, flagName) then return true end
  if session and session.store and check_flags_table(session.store.flags, flagId, flagName) then return true end
  local store = script_store()
  if store then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags and Flags.getFlag then
      local ok, v = pcall(Flags.getFlag, store, nil, flagId)
      if ok and v == true then return true end
    end
    if check_flags_table(store.flags, flagId, flagName) then return true end
  end
  return false
end

local function get_var(session, varId)
  local store = script_store()
  if store then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags and Flags.getVar then
      local ok, v = pcall(Flags.getVar, store, nil, varId)
      if ok then return tonumber(v) or 0 end
    end
    if type(store.vars) == "table" then return tonumber(store.vars[varId]) or 0 end
  end
  if session and type(session.vars) == "table" then
    local v = session.vars[varId]
    if v == nil then v = session.vars[tostring(varId)] end
    return tonumber(v) or 0
  end
  return 0
end

local function dex_caught(dex, sp)
  if not dex then return false end
  local okD, Dex = pcall(require, "src.core.game3.dex")
  if okD and Dex and Dex.isCaught then
    local ok, v = pcall(Dex.isCaught, dex, sp)
    if ok then return v == true end
  end
  return (dex.caught and dex.caught[sp]) == true
end

local function has_all_kanto(dex)
  if not dex then return false end
  for sp = 1, 150 do
    if not dex_caught(dex, sp) then return false end
  end
  return true
end

local function has_all_mons(dex)
  if not has_all_kanto(dex) then return false end
  for sp = 152, 248 do
    if not dex_caught(dex, sp) then return false end
  end
  for sp = 252, 384 do
    if not dex_caught(dex, sp) then return false end
  end
  return true
end

local function caught_mons_count(session, national)
  local dex = session and session.dex
  if not dex then return 0 end
  local okD, Dex = pcall(require, "src.core.game3.dex")
  if okD and Dex and Dex.countCaught then
    local ok, n = pcall(Dex.countCaught, dex, national and "national" or "kanto")
    if ok and n then return n end
  end
  local n = 0
  for _, on in pairs(dex.caught or {}) do
    if on then n = n + 1 end
  end
  return n
end

local function capped_stat(session, id, key, cap)
  local stats = session.gameStats
  local v
  if type(stats) == "table" then
    v = stats[id] or stats[key]
  else
    v = session[key]
  end
  return math.min(cap, math.max(0, math.floor(tonumber(v) or 0)))
end

-- src/trainer_card.c:858 TrainerCard_GenerateCardForLinkPlayer
local function gather(session)
  session = session or {}
  local c = {}
  c.female = (session.gender == "female" or session.gender == "F" or session.gender == 1
    or session.playerGender == "female" or session.playerGender == 1) and true or false
  c.playerName = tostring(session.name or session.playerName or "RED")
  c.trainerId = (tonumber(session.trainerId or session.id or session.playerTrainerId) or 0) % 65536

  local pt = session.playtime or session.playTime
  c.playTimeHours = math.min(999, math.max(0, math.floor(
    tonumber(session.playTimeHours or session.hours or (pt and pt.hours)) or 0)))
  c.playTimeMinutes = math.min(59, math.max(0, math.floor(
    tonumber(session.playTimeMinutes or session.minutes or (pt and pt.minutes)) or 0)))

  c.hofDebutHours = tonumber(session.hofDebutHours) or 0
  c.hofDebutMinutes = tonumber(session.hofDebutMinutes) or 0
  c.hofDebutSeconds = tonumber(session.hofDebutSeconds) or 0
  if c.hofDebutHours > 999 then
    c.hofDebutHours, c.hofDebutMinutes, c.hofDebutSeconds = 999, 59, 59
  end

  c.hasPokedex = get_flag(session, FLAG_SYS_POKEDEX_GET, "FLAG_SYS_POKEDEX_GET")
  local national = get_flag(session, FLAG_SYS_NATIONAL_DEX, "FLAG_SYS_NATIONAL_DEX")
  c.caughtMonsCount = caught_mons_count(session, national)

  c.money = math.max(0, math.floor(tonumber(session.money) or 0))
  -- src/trainer_card.c:822
  c.linkBattleWins = capped_stat(session, 23, "linkBattleWins", 9999)
  c.linkBattleLosses = capped_stat(session, 24, "linkBattleLosses", 9999)
  c.pokemonTrades = capped_stat(session, 21, "pokemonTrades", 0xFFFF)
  -- src/trainer_card.c:876
  c.berryCrushPoints = capped_stat(session, 51, "berryCrushPoints", 0xFFFF)
  c.unionRoomNum = capped_stat(session, 50, "unionRoomNum", 0xFFFF)

  c.hasHofResult = (c.hofDebutHours ~= 0 or c.hofDebutMinutes ~= 0 or c.hofDebutSeconds ~= 0)
  c.hasLinkResults = (c.linkBattleWins ~= 0 or c.linkBattleLosses ~= 0)
  c.hasTrades = (c.pokemonTrades ~= 0)

  local stars = 0
  if c.hasHofResult then stars = 1 end
  if has_all_kanto(session.dex) then stars = stars + 1 end
  if has_all_mons(session.dex) then stars = stars + 1 end
  local berries = tonumber(session.berriesPicked) or 0
  local jumps = tonumber(session.jumpsInRow) or 0
  if berries >= 200 and jumps >= 200 then stars = stars + 1 end
  c.stars = math.min(4, stars)

  -- src/trainer_card.c:899
  c.monIconTint = get_var(session, VAR_TRAINER_CARD_MON_ICON_TINT_IDX)

  c.monSpecies = {}
  for i = 1, 6 do
    c.monSpecies[i] = get_var(session, VAR_TRAINER_CARD_MON_ICON_1 + i - 1)
  end
  c.stickers = {
    get_var(session, VAR_HOF_BRAG_STATE),
    get_var(session, VAR_EGG_BRAG_STATE),
    get_var(session, VAR_LINK_WIN_BRAG_STATE),
  }

  c.badges = {}
  for i = 1, 8 do c.badges[i] = is_badge_unlocked(session, i) end
  return c
end

function TrainerCard.isBadgeUnlocked(badgeIndex)
  return is_badge_unlocked(TrainerCard._session, badgeIndex)
end

function TrainerCard.countBadges(session)
  local s = session or TrainerCard._session
  local n = 0
  for i = 1, 8 do
    if is_badge_unlocked(s, i) then n = n + 1 end
  end
  return n
end

TrainerCard.side = "front"

local function play_se(name)
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if not ok or not Audio then return end
  local fn = Audio.playSe or Audio.playSE
  if fn then pcall(fn, name) end
end

-- src/trainer_card.c:1700 Task_AnimateCardFlipDown +7 to 77, Task_AnimateCardFlipUp -5 to 0
local FLIP_TOP_MAX = 77
local FLIP_DOWN_STEP = 7
local FLIP_UP_STEP = 5

function TrainerCard.flip()
  TrainerCard.side = (TrainerCard.side == "back") and "front" or "back"
end

local function beginFlip()
  TrainerCard._flip = { phase = "down", top = 0 }
  play_se("SE_CARD_FLIP")
end

function TrainerCard.update(dt)
  local f = TrainerCard._flip
  if not f then return end
  if f.phase == "down" then
    f.top = f.top + FLIP_DOWN_STEP
    if f.top >= FLIP_TOP_MAX then
      f.top = FLIP_TOP_MAX
      f.phase = "up"
      TrainerCard.flip()
      play_se("SE_CARD_FLIPPING")
    end
  else
    f.top = f.top - FLIP_UP_STEP
    if f.top <= 0 then
      TrainerCard._flip = nil
      play_se("SE_CARD_OPEN")
    end
  end
end

local texts_cache = { c = false, colon = false, front = nil, back = nil }
local function front_texts_cached(c, colonInvisible)
  if texts_cache.front and texts_cache.c == c and texts_cache.colon == colonInvisible then
    return texts_cache.front
  end
  texts_cache.c, texts_cache.colon = c, colonInvisible
  texts_cache.front = TrainerCard.frontTexts(c, colonInvisible)
  return texts_cache.front
end
local function back_texts_cached(c)
  if texts_cache.back and texts_cache.c == c then return texts_cache.back end
  texts_cache.c = c
  texts_cache.back = TrainerCard.backTexts(c)
  return texts_cache.back
end

function TrainerCard.show(opts)
  opts = opts or {}
  TrainerCard.open = true
  TrainerCard.side = "front"
  TrainerCard._flip = nil
  TrainerCard._session = opts.session
  TrainerCard._card = gather(opts.session)
  texts_cache.c, texts_cache.colon, texts_cache.front, texts_cache.back = false, false, nil, nil
  TrainerCard._onClose = opts.onClose
  ensureAssets()
  Stack.push("trainer", TrainerCard, { hideBelow = true })
  play_se("SE_CARD_OPEN")
end

function TrainerCard.close()
  TrainerCard.open = false
  TrainerCard.side = "front"
  TrainerCard._flip = nil
  TrainerCard._session = nil
  TrainerCard._card = nil
  Stack.pop("trainer")
  local cb = TrainerCard._onClose
  TrainerCard._onClose = nil
  if cb then cb() end
end

function TrainerCard.isOpen()
  return TrainerCard.open
end

-- src/trainer_card.c:550 STATE_HANDLE_INPUT_FRONT / :587 STATE_HANDLE_INPUT_BACK
function TrainerCard.handleInput(inp)
  if not TrainerCard.open or not inp then return end
  if TrainerCard._flip then return end
  if TrainerCard.side == "front" then
    if inp:wasPressed("a") then
      beginFlip()
    elseif inp:wasPressed("b") then
      TrainerCard.close()
    end
  else
    if inp:wasPressed("b") then
      beginFlip()
    elseif inp:wasPressed("a") then
      TrainerCard.close()
    end
  end
end

local function right_align(n, width)
  local s = tostring(math.floor(n))
  while #s < width do s = " " .. s end
  return s
end

local function leading_zeros(n, width)
  return string.format("%0" .. width .. "d", math.floor(n))
end

local function str_length(s)
  local n = 0
  for _ in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
  return n
end

-- src/trainer_card.c:1046 PrintAllOnCardFront
function TrainerCard.frontTexts(c, colonInvisible)
  c = c or TrainerCard._card or gather(TrainerCard._session)
  local t = {}
  local function add(id, text, x, y, stat)
    t[#t + 1] = { id = id, text = text, x = WIN_X + x, y = WIN_Y + y, stat = stat or false }
  end

  add("name", RomText.plain("gText_TrainerCardName") .. c.playerName, 20, 29)
  add("id", RomText.plain("gText_TrainerCardIDNo") .. leading_zeros(c.trainerId, 5), 142, 10)

  add("money_label", RomText.plain("gText_TrainerCardMoney"), 20, 56)
  local moneyStr = RomText.plain("gText_TrainerCardYen") .. tostring(c.money)
  add("money", moneyStr, 134 - CHAR_ADVANCE * str_length(moneyStr), 56)

  if c.hasPokedex then
    add("dex_label", RomText.plain("gText_TrainerCardPokedex"), 20, 72)
    local dexStr = tostring(c.caughtMonsCount)
    add("dex", dexStr, 136 - CHAR_ADVANCE * str_length(dexStr), 72)
  end

  add("time_label", RomText.plain("gText_TrainerCardTime"), 20, 88)
  add("hours", right_align(c.playTimeHours, 3), 101, 88)
  if not colonInvisible then
    add("colon", RomText.plain("gText_Colon2"), 119, 88)
  end
  add("minutes", leading_zeros(c.playTimeMinutes, 2), 124, 88)
  return t
end

-- src/trainer_card.c:1076 PrintAllOnCardBack
function TrainerCard.backTexts(c)
  c = c or TrainerCard._card or gather(TrainerCard._session)
  local t = {}
  local function add(id, text, x, y, stat)
    t[#t + 1] = { id = id, text = text, x = WIN_X + x, y = WIN_Y + y, stat = stat or false }
  end

  add("name", c.playerName, 138, 11)

  if c.hasHofResult then
    add("hof_label", RomText.plain("gText_HallOfFameDebut"), 10, 35)
    add("hof", right_align(c.hofDebutHours, 3)
      .. ":" .. leading_zeros(c.hofDebutMinutes, 2)
      .. ":" .. leading_zeros(c.hofDebutSeconds, 2), 164, 35, true)
  end

  if c.hasLinkResults then
    add("link_label", RomText.plain("gText_LinkBattles"), 10, 51)
    add("link_w", "W:", 130, 51)
    add("link_wins", right_align(c.linkBattleWins, 4), 144, 51, true)
    add("link_l", "L:", 178, 51)
    add("link_losses", right_align(c.linkBattleLosses, 4), 192, 51, true)
  end

  if c.hasTrades then
    add("trades_label", RomText.plain("gText_PokemonTrades"), 10, 67)
    add("trades", right_align(c.pokemonTrades, 5), 186, 67, true)
  end

  if c.unionRoomNum ~= 0 then
    add("union_label", RomText.plain("gText_UnionRoomTradesBattles"), 10, 83)
    add("union", right_align(c.unionRoomNum, 5), 186, 83, true)
  end

  if c.berryCrushPoints ~= 0 then
    add("berry_label", RomText.plain("gText_BerryCrushes"), 10, 99)
    add("berry", right_align(c.berryCrushPoints, 5), 186, 99, true)
  end
  return t
end

TrainerCard.cardData = gather

local function draw_texts(list)
  for _, e in ipairs(list) do
    FrlgFont.draw(e.text, e.x, e.y, { colors = e.stat and FrlgFont.COLOR.STAT or FrlgFont.COLOR.NORMAL })
  end
end

local function draw_front(c)
  local pic = c.female and (_picLeaf or _picRed) or (_picRed or _picLeaf)
  if pic then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(pic, WIN_X + 144 + 13, WIN_Y + 32 + 4)
  end

  draw_texts(front_texts_cached(c, TrainerCard._colonInvisible))

  -- src/trainer_card.c:1553 stars at tile (15, 7), badges at tile (4 + 3i, 16)
  if _starImg then
    love.graphics.setColor(1, 1, 1, 1)
    for i = 0, c.stars - 1 do
      love.graphics.draw(_starImg, 120 + i * 8, 56)
    end
  end

  for i = 1, 8 do
    if c.badges[i] and _badgesImg and _badgeQuads and _badgeQuads[i] then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(_badgesImg, _badgeQuads[i], 32 + (i - 1) * 24, 128)
    end
  end
end

-- src/trainer_card.c:1411, include/constants/trainer_card.h
local MON_ICON_TINT_BLACK = 1
local MON_ICON_TINT_PINK = 2
local MON_ICON_TINT_SEPIA = 3

-- pokefirered/src/palette.c:832
local function tint_pixel(tint, r, g, b)
  local gray = 0.3 * r + 0.59 * g + 0.1133 * b
  local nr, ng, nb
  if tint == MON_ICON_TINT_BLACK then
    nr, ng, nb = 0, 0, 0
  elseif tint == MON_ICON_TINT_PINK then
    nr, ng, nb = 500 * gray / 256, 330 * gray / 256, 310 * gray / 256
  else
    nr, ng, nb = 1.2 * gray, gray, 0.94 * gray
  end
  if nr > 255 then nr = 255 end
  if ng > 255 then ng = 255 end
  if nb > 255 then nb = 255 end
  return math.floor(nr), math.floor(ng), math.floor(nb)
end

local _tintedIcons = {}

local function tinted_icon(icon, species, tint)
  if not icon or not icon.image or not tint then return icon end
  tint = math.floor(tint)
  if tint < MON_ICON_TINT_BLACK or tint > MON_ICON_TINT_SEPIA then return icon end
  local byTint = _tintedIcons[tint]
  if not byTint then
    byTint = {}
    _tintedIcons[tint] = byTint
  end
  local hit = byTint[species]
  if hit ~= nil then return hit or icon end

  local function fail()
    byTint[species] = false
    return icon
  end

  if not (love and love.image and love.image.newImageData and love.graphics) then return fail() end
  local okData, src = pcall(function() return icon.image:getData() end)
  if not okData or not src or not src.getPixel then return fail() end
  local w, h = src:getWidth(), src:getHeight()
  local okBuild, dst = pcall(function()
    local out = love.image.newImageData(w, h)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = src:getPixel(x, y)
        local nr, ng, nb = tint_pixel(tint, r * 255, g * 255, b * 255)
        out:setPixel(x, y, nr / 255, ng / 255, nb / 255, a)
      end
    end
    return out
  end)
  if not okBuild or not dst then return fail() end
  local okImg, img = pcall(love.graphics.newImage, dst)
  if not okImg or not img then return fail() end
  if img.setFilter then img:setFilter("nearest", "nearest") end

  byTint[species] = {
    image = img,
    w = icon.w,
    h = icon.h,
    sheetH = icon.sheetH,
    frames = icon.frames,
    quads = icon.quads,
  }
  return byTint[species]
end

local function draw_back(c)
  draw_texts(back_texts_cached(c))

  -- src/trainer_card.c:1414 WriteSequenceToBgTilemapBuffer(3, .., 4i + 3, 15, 4, 4, ..)
  local okPk, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okPk and Pokemon and Pokemon.icon then
    local tint = tonumber(c.monIconTint) or 0
    for i = 1, 6 do
      local sp = c.monSpecies[i]
      if sp and sp > 0 then
        local icon = tinted_icon(Pokemon.icon(sp), sp, tint)
        local q = icon and icon.quads and icon.quads[0]
        if icon and icon.image and q then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(icon.image, q, 24 + (i - 1) * 32, 120)
        end
      end
    end
  end

  -- src/trainer_card.c:1454 WriteSequenceToBgTilemapBuffer(3, .., 3i + 2, 2, 2, 2, ..)
  if _stickersImg and _stickerQuads then
    for i = 1, 3 do
      local sticker = c.stickers[i] or 0
      local quads = _stickerQuads[sticker]
      if sticker >= 1 and sticker <= 4 and quads and quads[i] then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_stickersImg, quads[i], 16 + (i - 1) * 24, 16)
      end
    end
  end
end

function TrainerCard.draw()
  if not TrainerCard.open then return end
  ensureAssets()
  local c = TrainerCard._card or gather(TrainerCard._session)

  -- src/trainer_card.c:1613 BlinkTimeColon toggles every 61 vblanks
  local colonOn = true
  if love and love.timer and love.timer.getTime then
    colonOn = (math.floor(love.timer.getTime() * 60 / 61) % 2 == 0)
  end
  TrainerCard._colonInvisible = not colonOn

  local side = TrainerCard.side
  local bg = card_image(side, c.stars, c.female)

  local f = TrainerCard._flip
  if f then
    local screen = screen_image(c.stars, c.female)
    love.graphics.setColor(1, 1, 1, 1)
    if screen then
      love.graphics.draw(screen, 0, 0)
    else
      local e = _cardEdge[string.format("%s%d%s", side, c.stars, c.female and "f" or "m")]
      love.graphics.setColor(e and e[1] or 0, e and e[2] or 0, e and e[3] or 0, 1)
      love.graphics.rectangle("fill", 0, 0, 240, 160)
      love.graphics.setColor(1, 1, 1, 1)
    end
    local scale = math.max(0, (160 - 2 * f.top) / 160)
    love.graphics.push()
    love.graphics.translate(0, 80)
    love.graphics.scale(1, scale)
    love.graphics.translate(0, -80)
  end

  love.graphics.setColor(1, 1, 1, 1)
  if bg then
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.85, 0.55, 0.35, 1)
    love.graphics.rectangle("fill", 16, 8, 208, 144)
    love.graphics.setColor(0.98, 0.92, 0.78, 1)
    love.graphics.rectangle("fill", 24, 16, 192, 128)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if side == "back" then
    draw_back(c)
  else
    draw_front(c)
  end

  if f then
    love.graphics.pop()
    -- src/trainer_card.c:1000 UpdateCardFlipRegs blendY = (cardTop + 40) / 10
    local blendY = math.floor((f.top + 40) / 10)
    if blendY > 4 then
      love.graphics.setColor(0, 0, 0, math.min(1, blendY / 16))
      love.graphics.rectangle("fill", 0, 0, 240, 160)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

return TrainerCard

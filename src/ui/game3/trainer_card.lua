-- FRLG Trainer Card front (pret trainer_card.c).
-- Displays player name, 5-digit IDNo, money, Pokédex count, playtime,
-- 64×64 trainer front pic (Red/Leaf), and 8 Kanto gym badges.

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")

local TrainerCard = {}

TrainerCard.open = false
TrainerCard._session = nil
TrainerCard._onClose = nil

-- Cached images
local _bgMale = nil
local _bgFemale = nil
local _badgesImg = nil
local _badgeQuads = nil
local _picRed = nil
local _picLeaf = nil
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
          return img
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

  _bgMale = load_rgba_image({
    "trainer_card/bg.rgba",
    "data/generated/gba/trainer_card/bg.rgba",
    "trainer_card/bg.png",
    "data/generated/gba/trainer_card/bg.png",
  }, 240, 160)

  _bgFemale = load_rgba_image({
    "trainer_card/bg_female.rgba",
    "data/generated/gba/trainer_card/bg_female.rgba",
    "trainer_card/bg_female.png",
    "data/generated/gba/trainer_card/bg_female.png",
  }, 240, 160)

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

local function count_caught(dex)
  if not dex then return 0 end
  local n = 0
  for sp, on in pairs(dex.caught or {}) do
    if on then n = n + 1 end
  end
  return n
end

local BADGE_FLAGS = { 0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827 }
local BADGE_NAMES = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }

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

  -- 1. Direct session badges table / number / boolean fields
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

    -- Direct session flags
    if check_flags_table(session.flags, flagId, flagName) then return true end

    -- Session store flags
    if session.store and check_flags_table(session.store.flags, flagId, flagName) then return true end

    -- Save / player badges
    local save = session.save or (session.game and session.game.save) or session
    if save and save.player and save.player.badges then
      local pb = save.player.badges
      if pb[badgeIndex] == true or pb[flagId] == true or (bName and pb[bName] == true) then
        return true
      end
    end
    if save and save.flags and check_flags_table(save.flags, flagId, flagName) then return true end
  end

  -- 2. Scripting Space store fallback
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = (Space and Space.getStore and Space.getStore()) or (Space and Space.store)
  if store and check_flags_table(store.flags, flagId, flagName) then return true end

  -- 3. Runtime active session fallback
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

function TrainerCard.flip()
  TrainerCard.side = (TrainerCard.side == "back") and "front" or "back"
end

function TrainerCard.show(opts)
  opts = opts or {}
  TrainerCard.open = true
  TrainerCard.side = "front"
  TrainerCard._session = opts.session
  TrainerCard._onClose = opts.onClose
  ensureAssets()
  Stack.push("trainer", TrainerCard, { hideBelow = true })
end

function TrainerCard.close()
  TrainerCard.open = false
  TrainerCard.side = "front"
  TrainerCard._session = nil
  Stack.pop("trainer")
  local cb = TrainerCard._onClose
  TrainerCard._onClose = nil
  if cb then cb() end
end

function TrainerCard.isOpen()
  return TrainerCard.open
end

function TrainerCard.handleInput(inp)
  if not TrainerCard.open or not inp then return end
  if inp:wasPressed("b") then
    TrainerCard.close()
    return
  end
  if inp:wasPressed("a") then
    TrainerCard.flip()
    local ok, Audio = pcall(require, "src.core.game3.audio")
    if ok and Audio and Audio.playSE then
      Audio.playSE(93)
    end
  end
end

function TrainerCard.draw()
  if not TrainerCard.open then return end
  ensureAssets()
  local session = TrainerCard._session or {}
  local isFemale = (session.gender == "female" or session.gender == 1 or session.playerGender == "female")
  local name = tostring(session.name or session.playerName or "RED")
  local rawId = tonumber(session.trainerId or session.id or session.playerTrainerId) or 0
  local idStr = string.format("%05d", rawId % 65536)

  -- 1. Card Background
  local bg = isFemale and (_bgFemale or _bgMale) or (_bgMale or _bgFemale)
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

  if TrainerCard.side == "back" then
    -- BACK SIDE RENDERING (pret trainer_card.c PrintAllOnCardBack)
    -- Header: NAME & IDNo.
    FrlgFont.draw(Strings("NAME:"), 28, 24, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(name, 68, 24, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(Strings("IDNo. %s", idStr), 150, 18, { colors = FrlgFont.COLOR.NORMAL })

    -- 1. HALL OF FAME DEBUT (pret y=35 in window -> screen y=43, label x=18, stat x=172)
    FrlgFont.draw(Strings("HOF DEBUT"), 28, 43, { colors = FrlgFont.COLOR.NORMAL })
    local hofStr = "---"
    if session.hofDebutTime then
      if type(session.hofDebutTime) == "table" then
        local h = session.hofDebutTime.hours or 0
        local m = session.hofDebutTime.minutes or 0
        local s = session.hofDebutTime.seconds or 0
        hofStr = string.format("%d:%02d:%02d", h, m, s)
      else
        hofStr = tostring(session.hofDebutTime)
      end
    elseif session.hofDebutHours or session.hofDebutMinutes then
      local h = tonumber(session.hofDebutHours) or 0
      local m = tonumber(session.hofDebutMinutes) or 0
      local s = tonumber(session.hofDebutSeconds) or 0
      hofStr = string.format("%d:%02d:%02d", h, m, s)
    elseif session.flags and session.flags[0x82C] then
      local pt = session.playtime or session.playTime
      local h = tonumber(session.playTimeHours or session.hours or (pt and pt.hours)) or 0
      local m = tonumber(session.playTimeMinutes or session.minutes or (pt and pt.minutes)) or 0
      hofStr = string.format("%d:%02d", h, m)
    end
    FrlgFont.draw(hofStr, 152, 43, { colors = (hofStr == "---") and FrlgFont.COLOR.NORMAL or FrlgFont.COLOR.STAT })

    -- 2. LINK BATTLES
    local wins = tonumber(session.linkBattleWins) or 0
    local losses = tonumber(session.linkBattleLosses) or 0
    FrlgFont.draw(Strings("LINK BATTLES"), 28, 62, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("W:", 136, 62, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("%d", wins), 152, 62, { colors = FrlgFont.COLOR.STAT })
    FrlgFont.draw("L:", 184, 62, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("%d", losses), 200, 62, { colors = FrlgFont.COLOR.STAT })

    -- 3. POKéMON TRADES
    local trades = tonumber(session.pokemonTrades or session.trades) or 0
    FrlgFont.draw(Strings("POKéMON TRADES"), 28, 80, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("%d", trades), 186, 80, { colors = FrlgFont.COLOR.STAT })

    -- 4. UNION ROOM
    local unionNum = tonumber(session.unionRoomNum or session.unionTrades) or 0
    FrlgFont.draw(Strings("UNION ROOM"), 28, 98, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("%d", unionNum), 186, 98, { colors = FrlgFont.COLOR.STAT })

    -- 5. Party Pokémon Slots / Stickers (Bottom Row)
    if session.party and #session.party > 0 then
      for i = 1, math.min(6, #session.party) do
        local mon = session.party[i]
        local mx = 28 + (i - 1) * 30
        local my = 120
        if mon and not (mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)) then
          local lvl = tonumber(mon.level) or 1
          FrlgFont.draw(string.format("L%d", lvl), mx, my, { colors = FrlgFont.COLOR.NORMAL })
        end
      end
    end
    return
  end

  -- FRONT SIDE RENDERING
  -- 2. Trainer Portrait (pret sTrainerPicOffsets: window (152, 40) + offset (13, 4) -> screen (165, 44))
  local pic = isFemale and (_picLeaf or _picRed) or (_picRed or _picLeaf)
  if pic then
    love.graphics.draw(pic, 165, 44)
  end

  -- 3. Card Labels & Values (pret trainer_card.c relative to window (8, 8))
  FrlgFont.draw(Strings("NAME:"), 28, 37, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(name, 68, 37, { colors = FrlgFont.COLOR.NORMAL })

  FrlgFont.draw(Strings("IDNo. %s", idStr), 150, 18, { colors = FrlgFont.COLOR.NORMAL })

  -- MONEY (pret x=20, y=56 in window -> screen (28, 64), right aligned at window x=134 -> screen x=142)
  local money = tonumber(session.money) or 0
  FrlgFont.draw(Strings("MONEY"), 28, 64, { colors = FrlgFont.COLOR.NORMAL })
  local moneyStr = string.format("¥%d", money)
  local moneyW = FrlgFont.measure(moneyStr)
  FrlgFont.draw(moneyStr, math.max(68, 142 - moneyW), 64, { colors = FrlgFont.COLOR.NORMAL })

  -- POKéDEX (pret x=20, y=72 in window -> screen (28, 80), right aligned at window x=136 -> screen x=144)
  local caught = count_caught(session.dex) or tonumber(session.caughtMonsCount) or 0
  FrlgFont.draw(Strings("POKéDEX"), 28, 80, { colors = FrlgFont.COLOR.NORMAL })
  local dexStr = string.format("%d", caught)
  local dexW = FrlgFont.measure(dexStr)
  FrlgFont.draw(dexStr, math.max(68, 144 - dexW), 80, { colors = FrlgFont.COLOR.NORMAL })

  -- TIME (pret x=20, y=88 in window -> screen (28, 96))
  local pt = session.playtime or session.playTime
  local hours = tonumber(session.playTimeHours or session.hours or (pt and pt.hours)) or 0
  local mins = tonumber(session.playTimeMinutes or session.minutes or (pt and pt.minutes)) or 0
  hours = math.min(999, math.max(0, math.floor(hours)))
  mins = math.min(59, math.max(0, math.floor(mins)))

  FrlgFont.draw(Strings("TIME"), 28, 96, { colors = FrlgFont.COLOR.NORMAL })

  -- Hours right-aligned to colon at window x=119 -> screen x=127
  local hoursStr = string.format("%d", hours)
  local hoursW = FrlgFont.measure(hoursStr)
  FrlgFont.draw(hoursStr, 127 - hoursW, 96, { colors = FrlgFont.COLOR.NORMAL })

  -- Blinking colon at screen x=127, y=96 (toggles every 30 frames / 0.5s)
  local colonOn = true
  if love and love.timer and love.timer.getTime then
    colonOn = (math.floor(love.timer.getTime() * 2) % 2 == 0)
  end
  if colonOn then
    FrlgFont.draw(":", 127, 96, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- Minutes (2 digits with leading zero) at window x=124 -> screen x=132
  local minsStr = string.format("%02d", mins)
  FrlgFont.draw(minsStr, 132, 96, { colors = FrlgFont.COLOR.NORMAL })

  -- 4. Badges (pret tile 16 -> y = 128, x = 32, 56, 80, 104, 128, 152, 176, 200)
  for i = 1, 8 do
    local bx = 32 + (i - 1) * 24
    local by = 128
    if is_badge_unlocked(session, i) then
      if _badgesImg and _badgeQuads and _badgeQuads[i] then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_badgesImg, _badgeQuads[i], bx, by)
      else
        -- Fallback badge representation in authentic Kanto colors
        local colors = {
          { 0.65, 0.65, 0.65 }, -- 1. Boulder (Gray)
          { 0.20, 0.60, 0.95 }, -- 2. Cascade (Blue teardrop)
          { 0.95, 0.85, 0.20 }, -- 3. Thunder (Yellow star)
          { 0.30, 0.85, 0.40 }, -- 4. Rainbow (Green flower)
          { 0.90, 0.30, 0.70 }, -- 5. Soul (Pink heart)
          { 0.80, 0.70, 0.30 }, -- 6. Marsh (Gold disc)
          { 0.95, 0.35, 0.20 }, -- 7. Volcano (Red flame)
          { 0.30, 0.75, 0.35 }, -- 8. Earth (Green feather)
        }
        local c = colors[i] or { 0.8, 0.8, 0.8 }
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.rectangle("fill", bx + 2, by + 2, 12, 12)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", bx + 2, by + 2, 12, 12)
      end
    end
  end
end

return TrainerCard

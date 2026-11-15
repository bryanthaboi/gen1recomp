-- pokefirered/src/mail.c:440 ReadMail

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local Mail = require("src.core.game3.mail")

local MailRead = {}

MailRead.open = false
MailRead.CACHE_SUB = "mail"

-- pokefirered/src/mail.c:114 sWindowTemplates
local MSG_X, MSG_Y = 3 * 8, 4 * 8
local NAME_X, NAME_Y = 15 * 8, 15 * 8
local ICON_POS
-- pokefirered/src/mail.c:594
local function icon_pos(design)
  if not ICON_POS then
    local C = require("src.core.game3.constants").of("firered")
    ICON_POS = {
      [Mail.designOf(C:require("items", "ITEM_BEAD_MAIL"))] = { 0x60, 0x80 },
      [Mail.designOf(C:require("items", "ITEM_DREAM_MAIL"))] = { 0x28, 0x80 },
    }
  end
  return ICON_POS[design]
end
-- pokefirered/include/constants/species.h:208, :421, :425
local SPECIES_UNOWN, NUM_SPECIES, SPECIES_UNOWN_B = 201, 412, 413
-- pokefirered/src/mail.c:653
local JAPANESE_NAME_BELOW = 6

local images = {}
local manifest

local function cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  return ((ok and Extract and Extract.CACHE_ROOT) or "data/generated/gba") .. "/" .. MailRead.CACHE_SUB
end

local function read(rel)
  local bytes = require("src.core.game3.dataset").cache():read(rel)
  if type(bytes) ~= "string" or #bytes == 0 then error(rel .. " is not in the cache", 0) end
  return bytes
end

local function load_manifest()
  if manifest then return manifest end
  local rel = cache_root() .. "/manifest.lua"
  manifest = assert(load(read(rel), "@" .. rel, "t", {}))()
  return manifest
end
MailRead.manifest = load_manifest

local function image(file)
  if images[file] then return images[file] end
  local m = load_manifest()
  local rel = cache_root() .. "/" .. file
  local bytes = read(rel)
  if #bytes ~= m.width * m.height * 4 then
    error(("%s is %d bytes, not %dx%d"):format(rel, #bytes, m.width, m.height), 0)
  end
  local img = love.graphics.newImage(love.image.newImageData(m.width, m.height, "rgba8", bytes))
  img:setFilter("nearest", "nearest")
  images[file] = img
  return img
end

local function rgb(c)
  return { (c % 32) / 31, (math.floor(c / 32) % 32) / 31, (math.floor(c / 1024) % 32) / 31, 1 }
end

-- pokefirered/src/easy_chat.c:188 ConvertEasyChatWordsToString
local function words_line(mail, first, count)
  local EasyChatText = require("src.core.game3.easy_chat_text")
  local out = {}
  for i = 0, count - 1 do
    local id = tonumber(mail.words and mail.words[first + i]) or Mail.EC_WORD_UNDEFINED
    if id ~= Mail.EC_WORD_UNDEFINED then
      out[#out + 1] = EasyChatText.word(id)
      if i < count - 1 then out[#out + 1] = " " end
    end
  end
  return table.concat(out)
end

-- pokefirered/src/mail.c:636 BufferMailMessage
function MailRead.lines(mail, design)
  local layout = load_manifest().layouts[design]
  local out, n = {}, 1
  for i, line in ipairs(layout.lines) do
    out[i] = words_line(mail, n, line.words)
    n = n + line.words
  end
  return out
end

local JAPANESE_OF
-- pokefirered/src/string_util.c:684 ConvertInternationalString
function MailRead.japaneseName(name)
  if not JAPANESE_OF then
    local byCode = {}
    for ch, code in pairs(FrlgFont.JAPANESE_GLYPHS) do
      if not byCode[code] or ch < byCode[code] then byCode[code] = ch end
    end
    JAPANESE_OF = {}
    for code, ch in pairs(require("src.core.game3.scripting.text_ir").CHARMAP or {}) do
      if type(ch) == "string" and #ch > 0 and byCode[code] and not JAPANESE_OF[ch] then
        JAPANESE_OF[ch] = byCode[code]
      end
    end
  end
  return (tostring(name or ""):gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
    return JAPANESE_OF[ch] or ch
  end))
end

-- pokefirered/src/mail.c:652
function MailRead.authorName(name)
  name = tostring(name or "")
  local n = 0
  for _ in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
  if n < JAPANESE_NAME_BELOW then return MailRead.japaneseName(name) end
  return name
end

function MailRead.designOf(mail)
  local m = load_manifest()
  local d = (tonumber(mail and mail.itemId) or 0) - m.firstMailItem
  -- pokefirered/src/mail.c:449
  if not m.designs[d] then return 0, false end
  return d, true
end

-- pokefirered/src/pokemon_icon.c:1088 MailSpeciesToIconSpecies
function MailRead.iconSpecies(mailSpecies)
  local species, letter = Mail.mailSpeciesToSpecies(mailSpecies)
  if species == SPECIES_UNOWN then
    if letter == 0 then return SPECIES_UNOWN end
    return SPECIES_UNOWN_B - 1 + letter
  end
  if (tonumber(mailSpecies) or 0) > SPECIES_UNOWN_B - 1 then return 0 end
  return tonumber(mailSpecies) or 0
end

-- pokefirered/src/mail.c:468
function MailRead.iconFor(mail, design)
  local species = Mail.mailSpeciesToSpecies(mail and mail.species)
  if not icon_pos(design) or species == 0 or species >= NUM_SPECIES then return nil end
  return MailRead.iconSpecies(mail.species), icon_pos(design)
end

function MailRead.read(mail, opts)
  opts = opts or {}
  MailRead.open = true
  MailRead._mail = mail
  MailRead._onClose = opts.onClose
  MailRead._session = opts.session
  local design, isMail = MailRead.designOf(mail)
  MailRead._design = design
  MailRead._hasText = isMail and opts.hasText ~= false
  MailRead._lines = MailRead._hasText and MailRead.lines(mail, design) or {}
  MailRead._author = MailRead.authorName(mail and mail.playerName)
  MailRead._icon, MailRead._iconPos = MailRead.iconFor(mail, design)
  local d = load_manifest().designs[design]
  -- pokefirered/src/mail.c:134 sTextColor
  MailRead._colors = { fg = rgb(d.textColor), shadow = rgb(d.textShadow), bg = { 0, 0, 0, 0 } }
  MailRead._fade = 16
  MailRead._fadeDir = -1
  Stack.push("frlg_mail", MailRead, { hideBelow = true, fullscreen = true })
end

function MailRead.isOpen()
  return MailRead.open
end

function MailRead.close()
  if not MailRead.open then return end
  MailRead.open = false
  Stack.pop("frlg_mail")
  local cb = MailRead._onClose
  MailRead._onClose = nil
  if cb then cb() end
end

function MailRead.reset()
  MailRead.open = false
  MailRead._onClose = nil
  Stack.pop("frlg_mail")
end

-- pokefirered/src/palette.c:162
local FADE_STEP = 2

function MailRead.update()
  if not MailRead.open or MailRead._fadeDir == 0 then return end
  MailRead._fade = MailRead._fade + MailRead._fadeDir * FADE_STEP
  if MailRead._fade <= 0 then
    MailRead._fade, MailRead._fadeDir = 0, 0
  elseif MailRead._fade >= 16 then
    MailRead.close()
  end
end

function MailRead.handleInput(input)
  if not MailRead.open or not input or MailRead._fadeDir ~= 0 then return end
  -- pokefirered/src/mail.c:707 ShowMailCB_WaitButton
  if input:wasPressed("a") or input:wasPressed("b") then
    MailRead._fadeDir = 1
  end
end

local function gender(sess)
  local g = sess and (sess.gender or sess.playerGender)
  return (g == 1 or g == "female" or g == "F") and 1 or 0
end

function MailRead.draw()
  if not MailRead.open then return end
  local m = load_manifest()
  local d = m.designs[MailRead._design]
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image(d.files[gender(MailRead._session) + 1]), 0, 0)
  local layout = m.layouts[MailRead._design]
  local colors = MailRead._colors
  if MailRead._hasText then
    local y = 0
    -- pokefirered/src/mail.c:659 AddMailMessagePrinters
    for i, line in ipairs(MailRead._lines) do
      if line ~= "" and line:sub(1, 1) ~= " " then
        FrlgFont.draw(line, MSG_X + layout.lines[i].xOffset + layout.messageLeft, MSG_Y + y + layout.messageTop,
          { colors = colors })
        y = y + layout.lines[i].height
      end
    end
    local from = RomText.plain("gText_From")
    local w = FrlgFont.measure(from)
    FrlgFont.draw(from, NAME_X + layout.nameX, NAME_Y + layout.nameY, { colors = colors })
    FrlgFont.draw(MailRead._author, NAME_X + layout.nameX + w, NAME_Y + layout.nameY, { colors = colors })
  end
  if MailRead._icon then
    local icon = require("src.core.game3.pokemon").iconDontHandleDeoxys(MailRead._icon)
    if not icon then error(("mon icon %d is not in the cache"):format(MailRead._icon), 0) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(icon.image, icon.quads[0], MailRead._iconPos[1] - icon.w / 2, MailRead._iconPos[2] - icon.h / 2)
  end
  if MailRead._fade > 0 then
    love.graphics.setColor(0, 0, 0, MailRead._fade / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function MailRead.invalidate()
  images, manifest = {}, nil
end

return MailRead

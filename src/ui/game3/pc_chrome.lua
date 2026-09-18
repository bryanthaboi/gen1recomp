-- FRLG Pokémon Storage System & PC Chrome helper.
-- Direct 1:1 rendering from ROM-extracted assets (pokefirered / FRLG).
-- Zero procedural approximations; loads pre-extracted textures from CacheFS.

local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local ItemsData = require("src.core.game3.items_data")

local PcChrome = {}

-- Cached texture images (loaded on demand / ensure)
PcChrome._initialized = false
PcChrome._cursorImg = nil
PcChrome._shadowImg = nil
PcChrome._arrowImg = nil
PcChrome._bgImg = nil
PcChrome._frameImg = nil
PcChrome._buttonPartyImg = nil
PcChrome._buttonCloseImg = nil
PcChrome._partyDrawerBgImg = nil
PcChrome._partySlotFilledImg = nil
PcChrome._partySlotEmptyImg = nil
PcChrome._waveformImg = nil
PcChrome._wallpapers = {}

PcChrome.WALLPAPER_NAMES = {
  [1]  = "forest",
  [2]  = "city",
  [3]  = "desert",
  [4]  = "savanna",
  [5]  = "crag",
  [6]  = "volcano",
  [7]  = "snow",
  [8]  = "cave",
  [9]  = "beach",
  [10] = "seafloor",
  [11] = "river",
  [12] = "sky",
  [13] = "stars",
  [14] = "pokecenter",
  [15] = "tiles",
  [16] = "simple",
}

local function load_texture(name)
  local candidates = {
    "pokemon/storage/" .. name,
    "data/generated/gba/pokemon/storage/" .. name,
    "src/import/gba/chrome/menus/storage/" .. name,
  }
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    for _, path in ipairs(candidates) do
      local bytes = CacheFs.readActive(path)
      if bytes and #bytes > 0 and love and love.image and love.graphics and love.filesystem then
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(bytes, name)
          local id = love.image.newImageData(fd)
          local image = love.graphics.newImage(id)
          if image.setFilter then image:setFilter("nearest", "nearest") end
          return image
        end)
        if ok and img then return img end
      end
    end
  end
  local okA, Assets = pcall(require, "src.render.Assets")
  for _, path in ipairs(candidates) do
    if okA and Assets and Assets.image then
      local ok, img = pcall(Assets.image, path)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
    if love and love.filesystem and love.filesystem.read then
      local bytes = love.filesystem.read(path)
      if bytes and #bytes > 0 and love.image and love.graphics then
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(bytes, name)
          local id = love.image.newImageData(fd)
          local image = love.graphics.newImage(id)
          if image.setFilter then image:setFilter("nearest", "nearest") end
          return image
        end)
        if ok and img then return img end
      end
    end
    if love and love.image and love.graphics and love.filesystem then
      local f = io.open(path, "rb")
      if f then
        local bytes = f:read("*a")
        f:close()
        if bytes and #bytes > 0 then
          local ok, img = pcall(function()
            local fd = love.filesystem.newFileData(bytes, name)
            local id = love.image.newImageData(fd)
            local image = love.graphics.newImage(id)
            if image.setFilter then image:setFilter("nearest", "nearest") end
            return image
          end)
          if ok and img then return img end
        end
      end
    end
    if love and love.graphics and love.graphics.newImage then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
  end
  return nil
end

function PcChrome.ensure()
  if PcChrome._initialized then return end
  PcChrome._initialized = true

  PcChrome._cursorImg = load_texture("cursor.png")
  PcChrome._shadowImg = load_texture("cursor_shadow.png")
  PcChrome._arrowImg = load_texture("box_scroll_arrow.png")
  PcChrome._bgImg = load_texture("scrolling_bg.png")
  PcChrome._frameImg = load_texture("interface_frame.png")
  PcChrome._buttonPartyImg = load_texture("button_party.png")
  PcChrome._buttonCloseImg = load_texture("button_close.png")
  PcChrome._partyDrawerBgImg = load_texture("party_drawer_bg.png")
  PcChrome._partySlotFilledImg = load_texture("party_slot_filled.png")
  PcChrome._partySlotEmptyImg = load_texture("party_slot_empty.png")
  PcChrome._waveformImg = load_texture("waveform.png")

  for id, name in ipairs(PcChrome.WALLPAPER_NAMES) do
    PcChrome._wallpapers[id] = load_texture("wallpapers/" .. name .. ".png")
  end
end

--- Draw authentic tiled scrolling background (BG3).
function PcChrome.drawBackground()
  PcChrome.ensure()
  love.graphics.setColor(1, 1, 1, 1)
  if PcChrome._bgImg then
    local bw, bh = PcChrome._bgImg:getDimensions()
    for bx = 0, 240, bw do
      for by = 0, 160, bh do
        love.graphics.draw(PcChrome._bgImg, bx, by)
      end
    end
  else
    love.graphics.setColor(248/255, 216/255, 208/255, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw animated waveforms beside PKMN DATA header
function PcChrome.drawWaveforms(active, frame)
  PcChrome.ensure()
  if not PcChrome._waveformImg then return end

  -- Left waveform: center (8, 9) -> top-left (0, 5)
  -- Right waveform: center (71, 9) -> top-left (63, 5)
  local leftFrameIdx = 0
  local rightFrameIdx = 4
  if active then
    local animSeq = { 0, 1, 2, 3 }
    local rightSeq = { 4, 5, 6, 5 }
    local idx = (math.floor((frame or 0) / 4) % 4) + 1
    leftFrameIdx = animSeq[idx]
    rightFrameIdx = rightSeq[idx]
  end

  local iw, ih = PcChrome._waveformImg:getDimensions()
  local leftQuad = love.graphics.newQuad(0, leftFrameIdx * 8, 16, 8, iw, ih)
  local rightQuad = love.graphics.newQuad(0, rightFrameIdx * 8, 16, 8, iw, ih)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(PcChrome._waveformImg, leftQuad, 0, 5)
  love.graphics.draw(PcChrome._waveformImg, rightQuad, 63, 5)
end

--- Draw the 160×144 ROM wallpaper (BG2) at (80, 16).
function PcChrome.drawWallpaper(wallpaperId)
  PcChrome.ensure()
  wallpaperId = math.max(1, math.min(16, tonumber(wallpaperId) or 1))
  local wpImg = PcChrome._wallpapers[wallpaperId] or PcChrome._wallpapers[1]
  if wpImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(wpImg, 80, 16)
  end
end

--- Draw the ROM interface frame (BG1) at (0, 0).
function PcChrome.drawInterfaceFrame()
  PcChrome.ensure()
  if PcChrome._frameImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(PcChrome._frameImg, 0, 0)
  end
end

--- Draw Left TV Monitor & Lower stats card contents.
function PcChrome.drawLeftDataPanel(hoveredMon, hoverFrame)
  PcChrome.ensure()

  -- Draw Waveforms (animated if hovering mon, idle flatline if not)
  PcChrome.drawWaveforms(hoveredMon ~= nil, hoverFrame)

  if not hoveredMon then return end

  -- 1. Front Sprite in TV Screen (X: 10..73, Y: 19..80, W: 64, H: 61)
  local sp = Pokemon.speciesOf(hoveredMon)
  local sprite = Pokemon.frontPic(sp)
  if sprite and sprite.image then
    love.graphics.setColor(1, 1, 1, 1)
    local sw, sh = sprite.image:getDimensions()
    local scale = math.min(54 / sw, 54 / sh)
    local sx = 10 + math.floor((64 - sw * scale) / 2)
    local sy = 19 + math.floor((61 - sh * scale) / 2)
    love.graphics.draw(sprite.image, sx, sy, 0, scale, scale)
  end

  -- 2. Lower Stats Card Text & Info (X: 0..80, Y: 88..160)
  -- Matches pret FRLG PrintDisplayMonInfo (Window 0: left=0, top=11 / Y=88)
  local sp = Pokemon.speciesOf(hoveredMon)
  local spName = (sp and Pokemon.name(sp)) or "----"
  local nick = hoveredMon.nickname
  if not nick or nick == "" then
    nick = (hoveredMon.name and hoveredMon.name ~= "" and hoveredMon.name) or spName
  end
  if not nick or nick == "" then
    nick = spName
  end
  local lvl = hoveredMon.level or 5
  local gender = hoveredMon.gender or (hoveredMon.personality and ((hoveredMon.personality % 256 < 127) and "F" or "M"))

  -- Line 1: Nickname or Species Name (FONT_NORMAL, Y: 88)
  FrlgFont.draw(nick:sub(1, 10), 6, 88, {
    small = false,
    colors = FrlgFont.COLOR.WHITE
  })

  -- Line 2: /Species Name (FONT_NORMAL, Y: 102)
  FrlgFont.draw("/" .. spName:sub(1, 10), 6, 102, {
    small = false,
    colors = FrlgFont.COLOR.WHITE
  })

  -- Line 3: Gender & Level (FONT_NORMAL, Y: 116)
  if gender == "M" or gender == "male" then
    FrlgFont.draw("♂", 6, 116, { small = false, colors = FrlgFont.COLOR.MALE })
    FrlgFont.draw("Lv" .. tostring(lvl), 18, 116, { small = false, colors = FrlgFont.COLOR.WHITE })
  elseif gender == "F" or gender == "female" then
    FrlgFont.draw("♀", 6, 116, { small = false, colors = FrlgFont.COLOR.FEMALE })
    FrlgFont.draw("Lv" .. tostring(lvl), 18, 116, { small = false, colors = FrlgFont.COLOR.WHITE })
  else
    FrlgFont.draw("Lv" .. tostring(lvl), 6, 116, { small = false, colors = FrlgFont.COLOR.WHITE })
  end

  -- Line 4: Held Item Name (if holding an item) (FONT_SMALL, Y: 132)
  local held = hoveredMon.heldItem or hoveredMon.item
  if held and held > 0 then
    local heldName = ItemsData.displayName(held)
    if heldName and heldName ~= "" and heldName ~= "NONE" then
      FrlgFont.draw(heldName:sub(1, 10), 6, 132, {
        small = true,
        colors = FrlgFont.COLOR.WHITE
      })
    end
  end

  -- Line 5: 4 Markings ● ■ ▲ ♥ (pret markingComboSprite centered at X: 40, Y: 148)
  local marks = hoveredMon.markings or 0
  local markSyms = { "●", "■", "▲", "♥" }
  for m = 1, 4 do
    local bitMask = math.pow(2, m - 1)
    local hasMark = (type(marks) == "number") and ((marks % (bitMask * 2)) >= bitMask)
    local mx = 23 + (m - 1) * 9
    if hasMark then
      FrlgFont.draw(markSyms[m], mx, 146, {
        small = true,
        colors = { fg = { 1, 1, 1, 1 }, shadow = { 40/255, 48/255, 60/255, 1 } }
      })
    else
      FrlgFont.draw(markSyms[m], mx, 146, {
        small = true,
        colors = { fg = { 72/255, 80/255, 96/255, 0.7 }, shadow = { 40/255, 44/255, 56/255, 0.5 } }
      })
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Top Right Buttons: PARTY POKéMON (X: 80, Y: 0) and CLOSE BOX (X: 168, Y: 0).
function PcChrome.drawTopButtons(activeButton)
  PcChrome.ensure()
  love.graphics.setColor(1, 1, 1, 1)

  if PcChrome._buttonPartyImg then
    love.graphics.draw(PcChrome._buttonPartyImg, 80, 0)
  end

  if PcChrome._buttonCloseImg then
    love.graphics.draw(PcChrome._buttonCloseImg, 168, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Box Title Banner: Left Arrow (88, 22), Box Name Text (centered at X: 160, Y: 20), Right Arrow (224, 22).
function PcChrome.drawBoxHeader(boxName, boxNum, isHovered)
  PcChrome.ensure()

  -- Left Arrow ◀ (X: 88, Y: 22, Frame 0: quad 0, 0, 8, 16)
  if PcChrome._arrowImg then
    local leftQuad = love.graphics.newQuad(0, 0, 8, 16, PcChrome._arrowImg:getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(PcChrome._arrowImg, leftQuad, 88, 22)
  end

  -- Box Name Text (drawn centered on the ROM wallpaper's capsule)
  local nameStr = tostring(boxName or ("BOX " .. tostring(boxNum or 1)))
  local nw = FrlgFont.measure(nameStr)
  local tx = math.floor(160 - nw / 2)
  FrlgFont.draw(nameStr, tx, 20, {
    colors = FrlgFont.COLOR.WHITE
  })

  -- Right Arrow ▶ (X: 224, Y: 22, Frame 1: quad 0, 16, 8, 16)
  if PcChrome._arrowImg then
    local rightQuad = love.graphics.newQuad(0, 16, 8, 16, PcChrome._arrowImg:getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(PcChrome._arrowImg, rightQuad, 224, 22)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Return authentic GBA hand cursor coordinates for party drawer slots (1..6 for mons, 7 for CANCEL).
function PcChrome.getPartyCursorCoords(partyCursor)
  partyCursor = partyCursor or 1
  if partyCursor == 1 then
    return 104, 52
  elseif partyCursor >= 2 and partyCursor <= 6 then
    return 152, (partyCursor - 2) * 24 + 4
  else -- CANCEL button (7)
    return 152, 132
  end
end

--- Draw the authentic Party Drawer overlay (96x160 panel, slot backgrounds, and Pokémon icons).
function PcChrome.drawPartyDrawer(party, partyCursor, hoverFrame, holdingSource)
  PcChrome.ensure()
  love.graphics.setColor(1, 1, 1, 1)

  -- 1. Base drawer background at (80, 0)
  if PcChrome._partyDrawerBgImg then
    love.graphics.draw(PcChrome._partyDrawerBgImg, 80, 0)
  end

  -- 2. Party Slots 2..6 (X: 136, Y: 8 + (p - 2) * 24)
  party = party or {}
  for p = 2, 6 do
    local isPickedUp = (holdingSource and holdingSource.loc == "party" and holdingSource.slot == p)
    local pMon = (not isPickedUp) and party[p]
    local sx = 136
    local sy = 8 + (p - 2) * 24
    if pMon then
      if PcChrome._partySlotFilledImg then
        love.graphics.draw(PcChrome._partySlotFilledImg, sx, sy)
      end
    else
      if PcChrome._partySlotEmptyImg then
        love.graphics.draw(PcChrome._partySlotEmptyImg, sx, sy)
      end
    end
  end

  -- 3. Party Pokémon Animated Mini-Icons
  -- Slot 1 (Lead): pret Center (104, 64) -> Top-Left (88, 48)
  local isLeadPickedUp = (holdingSource and holdingSource.loc == "party" and holdingSource.slot == 1)
  local leadMon = (not isLeadPickedUp) and party[1]
  if leadMon then
    local sp = Pokemon.speciesOf(leadMon)
    local icon = Pokemon.icon(sp)
    if icon and icon.image then
      local isHovered = (partyCursor == 1)
      local bounce = (isHovered and (hoverFrame % 2 == 1)) and -2 or 0
      local f = (isHovered and (hoverFrame % 2 == 1)) and 1 or 0
      local q = icon.quads and (icon.quads[f] or icon.quads[0])
      if q then
        love.graphics.draw(icon.image, q, 88, 48 + bounce)
      else
        love.graphics.draw(icon.image, 88, 48 + bounce)
      end
    end
  end

  -- Slots 2..6: pret Center (152, 16 + (p - 2) * 24) -> Top-Left (136, (p - 2) * 24)
  for p = 2, 6 do
    local isPickedUp = (holdingSource and holdingSource.loc == "party" and holdingSource.slot == p)
    local pMon = (not isPickedUp) and party[p]
    if pMon then
      local sp = Pokemon.speciesOf(pMon)
      local icon = Pokemon.icon(sp)
      if icon and icon.image then
        local isHovered = (partyCursor == p)
        local bounce = (isHovered and (hoverFrame % 2 == 1)) and -2 or 0
        local f = (isHovered and (hoverFrame % 2 == 1)) and 1 or 0
        local q = icon.quads and (icon.quads[f] or icon.quads[0])
        local iy = (p - 2) * 24
        if q then
          love.graphics.draw(icon.image, q, 136, iy + bounce)
        else
          love.graphics.draw(icon.image, 136, iy + bounce)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw Hand Cursor with authentic GBA positioning, optional drop shadow, and vertical flip.
function PcChrome.drawHandCursor(x, y, state, showShadow, vFlip)
  PcChrome.ensure()
  state = state or "idle"

  -- 1. Draw Oval Drop Shadow (GBA 16x16 sprite centered at x, y + 20)
  -- Only visible when hovering over an empty box slot
  if showShadow and PcChrome._shadowImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(PcChrome._shadowImg, x - 8, y + 12)
  end

  -- 2. Draw Hand Cursor Sprite (GBA 32x32 sprite centered at x, y)
  if PcChrome._cursorImg then
    local quadY = 0
    if state == "grab" then quadY = 64
    elseif state == "holding" then quadY = 96 end
    local quad = love.graphics.newQuad(0, quadY, 32, 32, PcChrome._cursorImg:getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    local sy = vFlip and -1 or 1
    love.graphics.draw(PcChrome._cursorImg, quad, x, y, 0, 1, sy, 16, 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PcChrome

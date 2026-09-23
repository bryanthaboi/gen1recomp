local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local Status = require("src.core.game3.link.status")

local LinkMenu = {}

LinkMenu.CACHE_DIR = "wireless_status"
LinkMenu.SCREEN_W = 240
LinkMenu.SCREEN_H = 160
-- pokefirered/src/wireless_communication_status_screen.c:251 CyclePalette
LinkMenu.CYCLE_FRAMES = 6
LinkMenu.ANIM_FIRST = 2
LinkMenu.ANIM_COUNT = 14
LinkMenu.CYCLE_COLORS = 8

-- pokefirered/src/wireless_communication_status_screen.c:91 sWindowTemplates
LinkMenu.TITLE_TEMPLATE = Window.template(3, 0, 24, 3)
LinkMenu.LIST_TEMPLATE = Window.template(3, 4, 22, 15)
LinkMenu.COUNT_TEMPLATE = Window.template(25, 4, 2, 15)

LinkMenu.open = false
LinkMenu.mode = nil
LinkMenu.stage = nil
LinkMenu.index = 1
LinkMenu.status = ""
LinkMenu.rows = {}
LinkMenu.palIdx = 0
LinkMenu._counter = 0
LinkMenu._rowsWait = 0
LinkMenu._addr = nil
LinkMenu._transport = nil
LinkMenu._role = nil
LinkMenu._art = nil
LinkMenu._artTried = false
LinkMenu._variants = {}
LinkMenu._onClose = nil

-- pokefirered/src/wireless_communication_status_screen.c:353 WCSS_AddTextPrinterParameterized
LinkMenu.COLOR = {
  NORMAL = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  TOTAL = { fg = FrlgFont.STDPAL[4], shadow = FrlgFont.STDPAL[5], bg = FrlgFont.STDPAL[0] },
  TITLE = { fg = FrlgFont.STDPAL[7], shadow = FrlgFont.STDPAL[6], bg = FrlgFont.STDPAL[0] },
}

LinkMenu.OPT = {}
for key, colors in pairs(LinkMenu.COLOR) do LinkMenu.OPT[key] = { colors = colors } end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okR, d = pcall(function() return Dataset.cache():read(rel) end)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, "data/generated/gba/" .. rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open("data/generated/gba/" .. rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function load_manifest()
  local src = read_bytes(LinkMenu.CACHE_DIR .. "/manifest.lua")
  if not src then return nil end
  local chunk = load(src, "@wireless_status/manifest.lua", "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

local function palette_banks(raw, banks)
  local out = {}
  for b = 0, banks - 1 do
    local bank = {}
    for c = 0, 15 do
      local off = (b * 16 + c) * 3
      bank[c] = {
        raw:byte(off + 1) or 0,
        raw:byte(off + 2) or 0,
        raw:byte(off + 3) or 0,
      }
    end
    out[b] = bank
  end
  return out
end

-- pokefirered/src/wireless_communication_status_screen.c:209 DecompressAndLoadBgGfxUsingHeap
function LinkMenu.loadArt()
  if LinkMenu._artTried then return LinkMenu._art end
  LinkMenu._artTried = true
  if not (love and love.graphics and love.image) then return nil end
  local manifest = load_manifest()
  local bg = manifest and manifest.bg
  local w, h = bg and tonumber(bg.width), bg and tonumber(bg.height)
  if not (w and h) then return nil end
  local rgba = read_bytes(LinkMenu.CACHE_DIR .. "/bg.rgba")
  if not rgba or #rgba ~= w * h * 4 then return nil end
  local okD, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okD and imageData) then return nil end
  local okI, image = pcall(love.graphics.newImage, imageData)
  if not okI then return nil end
  local pals = manifest.palettes or {}
  local banks = tonumber(pals.banks) or 16
  local raw = read_bytes(LinkMenu.CACHE_DIR .. "/palettes.pal")
  LinkMenu._art = {
    image = image,
    data = imageData,
    width = w,
    height = h,
    banks = raw and palette_banks(raw, banks) or nil,
    animFirst = tonumber(pals.anim_first) or LinkMenu.ANIM_FIRST,
    animCount = tonumber(pals.anim_count) or LinkMenu.ANIM_COUNT,
  }
  return LinkMenu._art
end

-- pokefirered/src/wireless_communication_status_screen.c:251 CyclePalette
function LinkMenu.variant(index)
  local art = LinkMenu._art
  if not (art and art.banks) then return art and art.image or nil end
  index = math.floor(tonumber(index) or 0)
  if index <= 0 then return art.image end
  local cached = LinkMenu._variants[index]
  if cached then return cached end
  local base = art.banks[0]
  local anim = art.banks[(art.animFirst + index - 1)]
  if not (base and anim) then return art.image end
  local map = {}
  for c = 0, LinkMenu.CYCLE_COLORS - 1 do
    local from, to = base[c], anim[c]
    if from and to then
      map[from[1] * 65536 + from[2] * 256 + from[3]] = to
    end
  end
  local okC, data = pcall(art.data.clone, art.data)
  if not (okC and data) then return art.image end
  data:mapPixel(function(_x, _y, r, g, b, a)
    local key = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256
      + math.floor(b * 255 + 0.5)
    local to = map[key]
    if not to then return r, g, b, a end
    return to[1] / 255, to[2] / 255, to[3] / 255, a
  end)
  local okI, image = pcall(love.graphics.newImage, data)
  if not okI then return art.image end
  LinkMenu._variants[index] = image
  return image
end

function LinkMenu.isOpen()
  return LinkMenu.open and true or false
end

-- pokefirered/src/cable_club.c:222 the counter waits until the other machine is on the cable
LinkMenu.CONNECT_TEMPLATE = Window.template(2, 2, 26, 12)
LinkMenu.ADDR_LENGTH = 15
LinkMenu.ADDR_CHARSET = "0123456789. "

local function addr_state(seed)
  local CodeEntry = require("src.link.CodeEntry")
  if type(seed) ~= "string" or not seed:match("^%d+%.%d+%.%d+%.%d+$") then
    seed = "192.168.0.1"
  end
  local state = CodeEntry.fromText(seed, {
    length = LinkMenu.ADDR_LENGTH, charset = LinkMenu.ADDR_CHARSET,
  })
  state.pos = math.max(1, math.min(LinkMenu.ADDR_LENGTH, #seed))
  return state
end

function LinkMenu.addrText(state)
  local CodeEntry = require("src.link.CodeEntry")
  local text = (CodeEntry.text(state):gsub(" ", ""))
  local octets = { text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
  if #octets ~= 4 then return nil end
  for _, o in ipairs(octets) do
    if #o > 3 or tonumber(o) > 255 then return nil end
  end
  return text
end

function LinkMenu.showConnect(opts)
  opts = opts or {}
  LinkMenu.open = true
  LinkMenu.mode = "connect"
  LinkMenu.stage = "menu"
  LinkMenu.index = 1
  LinkMenu.status = ""
  LinkMenu.rows = {}
  LinkMenu._onClose = opts.onClose
  LinkMenu._linkType = opts.linkType
  LinkMenu._addr = addr_state(nil)
  Stack.push("wireless_status", LinkMenu, { hideBelow = true })
  return true
end

local function connect(role, address)
  local Link = require("src.core.game3.link")
  local transport, why = Link.dial({ role = role, address = address })
  if not transport then
    LinkMenu.stage = "menu"
    LinkMenu.status = Strings("Link error: %s", tostring(why or "?"):sub(1, 28))
    return nil
  end
  LinkMenu._transport = transport
  LinkMenu._role = role
  return transport
end

LinkMenu.connect = connect

local function dropTransport(message)
  local transport = LinkMenu._transport
  LinkMenu._transport = nil
  if transport then pcall(function() transport:close() end) end
  require("src.core.game3.link").closeLink("connect_canceled")
  LinkMenu.stage = "menu"
  LinkMenu.status = message or ""
end

LinkMenu.dropTransport = dropTransport

-- pokefirered/src/cable_club.c:222 CreateLinkupTask
function LinkMenu.updateConnect()
  local Link = require("src.core.game3.link")
  local live = Link.link
  if live and live.isReady and live:isReady() then
    LinkMenu._transport = nil
    LinkMenu.close()
    return
  end
  if live and live.isOpen and not live:isOpen() then
    dropTransport(Strings("The link was broken."))
    return
  end
  local transport = LinkMenu._transport
  if not transport or live then return end
  transport:update()
  if transport.error then
    dropTransport(Strings("Link error: %s", tostring(transport.error):sub(1, 28)))
    return
  end
  if transport.closed then
    dropTransport(Strings("The link was broken."))
    return
  end
  if transport.paired then
    -- pokefirered/src/link.c:386 OpenLink
    LinkMenu._transport = nil
    Link.open({ transport = transport, role = LinkMenu._role,
      linkType = LinkMenu._linkType })
  end
end

function LinkMenu.connectInput(input)
  local CodeEntry = require("src.link.CodeEntry")
  if LinkMenu.stage == "menu" then
    if input:wasPressed("up") or input:wasPressed("down") then
      LinkMenu.index = LinkMenu.index == 1 and 2 or 1
    elseif input:wasPressed("b") then
      LinkMenu.close()
    elseif input:wasPressed("a") then
      LinkMenu.status = ""
      if LinkMenu.index == 1 then
        if connect("host", nil) then LinkMenu.stage = "hosting" end
      else
        LinkMenu.stage = "address"
      end
    end
    return
  end
  if LinkMenu.stage == "address" then
    if input:wasPressed("b") then
      LinkMenu.stage = "menu"
    elseif input:wasPressed("up") then CodeEntry.up(LinkMenu._addr)
    elseif input:wasPressed("down") then CodeEntry.down(LinkMenu._addr)
    elseif input:wasPressed("left") then CodeEntry.left(LinkMenu._addr)
    elseif input:wasPressed("right") then CodeEntry.right(LinkMenu._addr)
    elseif input:wasPressed("a") then
      local address = LinkMenu.addrText(LinkMenu._addr)
      if not address then
        LinkMenu.status = Strings("Not an IP address.")
        return
      end
      LinkMenu.status = ""
      local Net = require("src.link.Net")
      if connect("guest", address .. ":" .. tostring(Net.defaultPort())) then
        LinkMenu.stage = "joining"
      end
    end
    return
  end
  if input:wasPressed("b") then
    dropTransport("")
  end
end

-- pokefirered/src/wireless_communication_status_screen.c:195 ShowWirelessCommunicationScreen
function LinkMenu.show(opts)
  opts = opts or {}
  LinkMenu.open = true
  LinkMenu.mode = "status"
  LinkMenu.palIdx = 0
  LinkMenu._counter = 0
  LinkMenu._rowsWait = LinkMenu.ROWS_FRAMES
  LinkMenu._onClose = opts.onClose
  LinkMenu.rows = Status.rows()
  if love and love.graphics then LinkMenu.loadArt() end
  Stack.push("wireless_status", LinkMenu, { hideBelow = true })
  return true
end

function LinkMenu.close()
  if not LinkMenu.open then return false end
  LinkMenu.open = false
  Stack.pop("wireless_status")
  local cb = LinkMenu._onClose
  LinkMenu._onClose = nil
  if cb then cb() end
  return true
end

function LinkMenu.reset()
  LinkMenu.open = false
  LinkMenu.mode = nil
  LinkMenu.stage = nil
  LinkMenu.status = ""
  LinkMenu.rows = {}
  LinkMenu.palIdx = 0
  LinkMenu._counter = 0
  LinkMenu._rowsWait = 0
  LinkMenu._addr = nil
  LinkMenu._transport = nil
  LinkMenu._role = nil
  LinkMenu._onClose = nil
  LinkMenu._variants = {}
  LinkMenu._art = nil
  LinkMenu._artTried = false
  Stack.pop("wireless_status")
  return true
end

-- pokefirered/src/wireless_communication_status_screen.c:472 UpdateCommunicationCounts
LinkMenu.ROWS_FRAMES = 30

-- pokefirered/src/wireless_communication_status_screen.c:292 Task_WirelessCommunicationScreen
function LinkMenu.update(_dt)
  if not LinkMenu.open then return end
  if LinkMenu.mode == "connect" then return LinkMenu.updateConnect() end
  local wait = (LinkMenu._rowsWait or 0) - 1
  if wait > 0 then
    LinkMenu._rowsWait = wait
  else
    LinkMenu._rowsWait = LinkMenu.ROWS_FRAMES
    LinkMenu.rows = Status.rows()
  end
  LinkMenu._counter = LinkMenu._counter + 1
  if LinkMenu._counter > 5 then
    LinkMenu._counter = 0
    LinkMenu.palIdx = LinkMenu.palIdx + 1
    if LinkMenu.palIdx >= LinkMenu.ANIM_COUNT then LinkMenu.palIdx = 0 end
  end
end

function LinkMenu.handleInput(input)
  if not (input and LinkMenu.open) then return end
  if LinkMenu.mode == "connect" then return LinkMenu.connectInput(input) end
  if input:wasPressed("a") or input:wasPressed("b") then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    local okS, SE = pcall(require, "src.core.game3.se_ids")
    if okA and okS and Audio.playSe then pcall(Audio.playSe, SE.SE_SELECT) end
    LinkMenu.close()
  end
end

local function count_text(n)
  local value = math.floor(tonumber(n) or 0)
  if value < 10 then return " " .. tostring(value) end
  return tostring(value)
end

LinkMenu.countText = count_text

-- pokefirered/src/wireless_communication_status_screen.c:264 PrintHeaderTexts
-- pokefirered/src/cable_club.c:222 CreateLinkupTask
function LinkMenu.drawConnect()
  local tpl = LinkMenu.CONNECT_TEMPLATE
  Window.stdFrame(tpl)
  local Link = require("src.core.game3.link")
  local live = Link.link
  local tx, ty = Window.labelTx(tpl.left), tpl.top
  if LinkMenu.stage == "menu" then
    Window.print(Strings("LINK CABLE"), tx, ty)
    Window.print(Strings("HOST A GAME"), tx + 2, ty + 3)
    Window.print(Strings("JOIN A GAME"), tx + 2, ty + 5)
    Window.cursor(tpl.left, LinkMenu.index == 1 and ty + 3 or ty + 5)
  elseif LinkMenu.stage == "hosting" then
    Window.print(Strings("HOSTING"), tx, ty)
    Window.print(Strings("Friend joins at:"), tx, ty + 3)
    Window.print(tostring(LinkMenu._transport and LinkMenu._transport.address or "?"), tx, ty + 5)
    Window.print(Strings("Waiting..."), tx, ty + 8)
  elseif LinkMenu.stage == "address" then
    local CodeEntry = require("src.link.CodeEntry")
    Window.print(Strings("HOST ADDRESS"), tx, ty)
    local text = {}
    for i = 1, LinkMenu.ADDR_LENGTH do
      local ch = CodeEntry.charAt(LinkMenu._addr, i)
      text[i] = (i == LinkMenu._addr.pos and ch == " ") and "_" or ch
    end
    Window.print(table.concat(text), tx, ty + 3)
    Window.print(string.rep(" ", LinkMenu._addr.pos - 1) .. "^", tx, ty + 4)
  else
    Window.print(Strings("JOINING..."), tx, ty)
    Window.print(Strings("Waiting..."), tx, ty + 3)
  end
  if LinkMenu.status and LinkMenu.status ~= "" then
    Window.print(LinkMenu.status, tx, ty + 10)
  end
end

function LinkMenu.draw()
  if not (LinkMenu.open and love and love.graphics) then return end
  if LinkMenu.mode == "connect" then return LinkMenu.drawConnect() end
  local art = LinkMenu._art
  if art then
    local image = LinkMenu.variant(LinkMenu.palIdx)
    if image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, 0, 0)
    end
  else
    Window.stdFrame(LinkMenu.TITLE_TEMPLATE)
    Window.stdFrame(LinkMenu.LIST_TEMPLATE)
    Window.stdFrame(LinkMenu.COUNT_TEMPLATE)
  end

  local title = Status.HEADER[0]
  local titleW = FrlgFont.measure and FrlgFont.measure(title) or (#title * 5)
  Window.printPx(title, 24 + math.floor((192 - titleW) / 2), 6, LinkMenu.OPT.TITLE)
  for i, row in ipairs(LinkMenu.rows) do
    local y = 32 + 30 * (i - 1) + 10
    local opt = row.total and LinkMenu.OPT.TOTAL or LinkMenu.OPT.NORMAL
    Window.printPx(row.label, 24, y, opt)
    Window.printPx(count_text(row.count), 204, y, opt)
  end
end

return LinkMenu

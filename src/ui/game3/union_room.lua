local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local UnionRoomScreen = {}

-- pokefirered/src/data/union_room.h:56
UnionRoomScreen.LIST_TEMPLATE = Window.template(1, 3, 13, 10)
-- pokefirered/src/data/union_room.h:66
UnionRoomScreen.COUNT_TEMPLATE = Window.template(16, 3, 7, 4)
-- pokefirered/src/data/union_room.h:165
UnionRoomScreen.INVITE_TEMPLATE = Window.template(20, 6, 8, 7)

UnionRoomScreen.CACHE_DIR = "union_room"
-- pokefirered/src/link_rfu_3.c:949 CreateWirelessStatusIndicatorSprite
UnionRoomScreen.INDICATOR_X = 231
UnionRoomScreen.INDICATOR_Y = 8

UnionRoomScreen.open = false
UnionRoomScreen.mode = nil
UnionRoomScreen.items = {}
UnionRoomScreen.players = {}
UnionRoomScreen.lines = {}
UnionRoomScreen.cursor = 1
UnionRoomScreen._pollWait = 0
UnionRoomScreen._onSay = nil
UnionRoomScreen.capacity = nil
UnionRoomScreen.partner = nil
UnionRoomScreen._onChoose = nil
UnionRoomScreen._onCancel = nil
UnionRoomScreen._onConfirm = nil
UnionRoomScreen._onPoll = nil
UnionRoomScreen._chrome = nil
UnionRoomScreen._chromeTried = false

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
  local src = read_bytes(UnionRoomScreen.CACHE_DIR .. "/manifest.lua")
  if not src then return nil end
  local chunk = load(src, "@union_room/manifest.lua", "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

-- pokefirered/src/link_rfu_3.c:492 sWirelessStatusIndicatorSpriteSheet
function UnionRoomScreen.indicator()
  if UnionRoomScreen._chromeTried then return UnionRoomScreen._chrome end
  UnionRoomScreen._chromeTried = true
  if not (love and love.graphics and love.image) then return nil end
  local manifest = load_manifest()
  local entry = manifest and manifest.wireless_icon
  local w = entry and tonumber(entry.width)
  local frameH = entry and (tonumber(entry.frame_h) or tonumber(entry.height))
  if not (w and frameH) then return nil end
  local rgba = read_bytes(UnionRoomScreen.CACHE_DIR .. "/wireless_icon.rgba")
  if not rgba then return nil end
  local okD, imageData = pcall(love.image.newImageData, w, tonumber(entry.height), "rgba8", rgba)
  if not okD or not imageData then return nil end
  local okI, image = pcall(love.graphics.newImage, imageData)
  if not okI then return nil end
  UnionRoomScreen._chrome = image
  UnionRoomScreen._quad = love.graphics.newQuad(0, 0, w, frameH, image:getDimensions())
  return image
end

function UnionRoomScreen.isOpen()
  return UnionRoomScreen.open and true or false
end

local function push()
  UnionRoomScreen.open = true
  Stack.push("union_room", UnionRoomScreen, { hideBelow = false, drawUnder = true })
end

-- pokefirered/src/union_room.c:2896 UR_STATE_HANDLE_DO_SOMETHING_PROMPT_INPUT
function UnionRoomScreen.showActivities(items, opts)
  opts = opts or {}
  UnionRoomScreen.mode = "activity"
  UnionRoomScreen.items = items or {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.partner = opts.partner
  UnionRoomScreen._onChoose = opts.onChoose
  UnionRoomScreen._onCancel = opts.onCancel
  UnionRoomScreen._onConfirm = nil
  UnionRoomScreen._onPoll = nil
  UnionRoomScreen._onSay = nil
  push()
  return true
end

-- pokefirered/src/union_room.c:435 LL_STATE_PRINT_SEARCH_TEXT
function UnionRoomScreen.showPlayers(players, opts)
  opts = opts or {}
  UnionRoomScreen.mode = opts.mode or "board"
  UnionRoomScreen.players = players or {}
  UnionRoomScreen.items = {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.capacity = opts.capacity
  UnionRoomScreen._onConfirm = opts.onConfirm
  UnionRoomScreen._onCancel = opts.onCancel
  UnionRoomScreen._onPoll = opts.onPoll
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onSay = nil
  UnionRoomScreen._pollWait = 0
  push()
  return true
end

-- pokefirered/src/union_room_chat.c:318 EnterUnionRoomChat
function UnionRoomScreen.showChat(opts)
  opts = opts or {}
  UnionRoomScreen.mode = "chat"
  UnionRoomScreen.lines = opts.lines or {}
  UnionRoomScreen.items = {}
  UnionRoomScreen.players = {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen._onSay = opts.onSay
  UnionRoomScreen._onCancel = opts.onLeave
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onConfirm = nil
  UnionRoomScreen._onPoll = nil
  push()
  return true
end

function UnionRoomScreen.close()
  if not UnionRoomScreen.open then return false end
  UnionRoomScreen.open = false
  Stack.pop("union_room")
  return true
end

function UnionRoomScreen.reset()
  UnionRoomScreen.open = false
  UnionRoomScreen.mode = nil
  UnionRoomScreen.items = {}
  UnionRoomScreen.players = {}
  UnionRoomScreen.lines = {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.capacity = nil
  UnionRoomScreen.partner = nil
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onCancel = nil
  UnionRoomScreen._onConfirm = nil
  UnionRoomScreen._onPoll = nil
  UnionRoomScreen._onSay = nil
  UnionRoomScreen._pollWait = 0
  Stack.pop("union_room")
  return true
end

function UnionRoomScreen.rowCount()
  if UnionRoomScreen.mode == "activity" then return #UnionRoomScreen.items end
  return #UnionRoomScreen.players
end

function UnionRoomScreen.move(delta)
  local n = UnionRoomScreen.rowCount()
  if n < 1 then return false end
  local c = UnionRoomScreen.cursor + delta
  if c < 1 then c = n elseif c > n then c = 1 end
  UnionRoomScreen.cursor = c
  return true
end

function UnionRoomScreen.confirm()
  if UnionRoomScreen.mode == "activity" then
    local cb = UnionRoomScreen._onChoose
    local index = UnionRoomScreen.cursor
    UnionRoomScreen.close()
    if cb then cb(index) end
    return true
  end
  local row = UnionRoomScreen.players[UnionRoomScreen.cursor]
  local cb = UnionRoomScreen._onConfirm
  if not cb then
    UnionRoomScreen.close()
    return true
  end
  if UnionRoomScreen.mode == "leader" then
    local min = (UnionRoomScreen.capacity and UnionRoomScreen.capacity.min) or 0
    if #UnionRoomScreen.players < math.max(min, 1) then return false end
  elseif not row then
    return false
  end
  UnionRoomScreen.close()
  cb(row and row.slot or nil)
  return true
end

function UnionRoomScreen.cancel()
  local cb = UnionRoomScreen._onCancel
  UnionRoomScreen.close()
  if cb then cb() end
  return true
end

-- pokefirered/src/union_room.c:2795 HandleUnionRoomPlayerRefresh
UnionRoomScreen.POLL_FRAMES = 30

function UnionRoomScreen.update(_dt)
  if not UnionRoomScreen.open then return end
  local poll = UnionRoomScreen._onPoll
  if not poll then return end
  local wait = (UnionRoomScreen._pollWait or 0) - 1
  if wait > 0 then
    UnionRoomScreen._pollWait = wait
    return
  end
  UnionRoomScreen._pollWait = UnionRoomScreen.POLL_FRAMES
  local list = poll()
  if type(list) == "table" then
    UnionRoomScreen.players = list
    if UnionRoomScreen.cursor > #list then
      UnionRoomScreen.cursor = math.max(1, #list)
    end
  end
end

-- pokefirered/src/union_room_chat.c:279 gUnionRoomKeyboardText
local function compose_chat_line()
  local okN, Naming = pcall(require, "src.ui.game3.naming")
  if not (okN and Naming and Naming.open) then return false end
  if Naming.isOpen and Naming.isOpen() then return true end
  Naming.open({
    title = RomText.plain("gText_UR_Chat2"),
    maxLen = 20,
    onDone = function(text)
      local cb = UnionRoomScreen._onSay
      if cb and type(text) == "string" and text ~= "" then cb(text) end
    end,
  })
  return true
end

function UnionRoomScreen.handleInput(input)
  if not input then return end
  if UnionRoomScreen.mode == "chat" then
    if input:wasPressed("a") then
      compose_chat_line()
    elseif input:wasPressed("b") then
      UnionRoomScreen.cancel()
    end
    return
  end
  if input:wasPressed("up") then UnionRoomScreen.move(-1)
  elseif input:wasPressed("down") then UnionRoomScreen.move(1)
  elseif input:wasPressed("a") then UnionRoomScreen.confirm()
  elseif input:wasPressed("start") and UnionRoomScreen.mode == "leader" then
    UnionRoomScreen.confirm()
  elseif input:wasPressed("b") then UnionRoomScreen.cancel()
  end
end

-- pokefirered/src/data/union_room.h:175 sListMenuItems_InviteToActivity
UnionRoomScreen.LABELS = RomText.lazy({
  GREETINGS = "sListMenuItems_InviteToActivity[0]",
  BATTLE = "sListMenuItems_InviteToActivity[1]",
  CHAT = "sListMenuItems_InviteToActivity[2]",
  EXIT = "sListMenuItems_InviteToActivity[3]",
})

function UnionRoomScreen.labelFor(item)
  return UnionRoomScreen.LABELS[item and item.key] or ""
end

-- pokefirered/src/data/union_room.h:1 sLinkGroupActivityNameTexts
UnionRoomScreen.ACTIVITY_LABELS = RomText.lazy({
  [1] = "sLinkGroupActivityNameTexts[1]",
  [2] = "sLinkGroupActivityNameTexts[2]",
  [4] = "sLinkGroupActivityNameTexts[4]",
  [5] = "sLinkGroupActivityNameTexts[5]",
  [8] = "sLinkGroupActivityNameTexts[8]",
  [12] = "sLinkGroupActivityNameTexts[12]",
})

function UnionRoomScreen.activityLabel(activity)
  local id = (tonumber(activity) or 0) % 0x40
  return UnionRoomScreen.ACTIVITY_LABELS[id] or ""
end

local function draw_frame(tpl)
  Window.stdFrame(tpl)
end

-- pokefirered/src/link_rfu_3.c:949 CreateWirelessStatusIndicatorSprite
local function draw_indicator()
  local image = UnionRoomScreen.indicator()
  if not (image and UnionRoomScreen._quad) then return end
  local _, _, w, h = UnionRoomScreen._quad:getViewport()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, UnionRoomScreen._quad,
    UnionRoomScreen.INDICATOR_X - w / 2, UnionRoomScreen.INDICATOR_Y - h / 2)
end

function UnionRoomScreen.draw()
  if not UnionRoomScreen.open then return end
  if not (love and love.graphics) then return end
  if UnionRoomScreen.mode == "chat" then
    -- pokefirered/src/union_room_chat.c:70 registeredTexts
    local tpl = UnionRoomScreen.LIST_TEMPLATE
    draw_frame(tpl)
    local lines = UnionRoomScreen.lines or {}
    local first = math.max(1, #lines - 8)
    local row = 0
    for i = first, #lines do
      local line = lines[i]
      Window.print(tostring(line.name or "") .. ": " .. tostring(line.text or ""),
        Window.labelTx(tpl.left), Window.menuRowY(tpl.top, row + 1))
      row = row + 1
    end
    draw_indicator()
    return
  end
  if UnionRoomScreen.mode == "activity" then
    local tpl = UnionRoomScreen.INVITE_TEMPLATE
    draw_frame(tpl)
    for i, item in ipairs(UnionRoomScreen.items) do
      local ty = Window.menuRowY(tpl.top, i)
      if i == UnionRoomScreen.cursor then Window.cursor(tpl.left, ty) end
      Window.print(UnionRoomScreen.labelFor(item), Window.labelTx(tpl.left), ty)
    end
    return
  end

  local tpl = UnionRoomScreen.LIST_TEMPLATE
  draw_frame(tpl)
  if #UnionRoomScreen.players == 0 then
    Window.print(Strings("Searching..."), Window.labelTx(tpl.left), tpl.top)
  end
  for i, row in ipairs(UnionRoomScreen.players) do
    local ty = Window.menuRowY(tpl.top, i)
    if ty > tpl.top + tpl.height - 1 then break end
    if i == UnionRoomScreen.cursor then Window.cursor(tpl.left, ty) end
    Window.print(tostring(row.name or ""), Window.labelTx(tpl.left), ty)
  end

  draw_indicator()
  local count = UnionRoomScreen.COUNT_TEMPLATE
  draw_frame(count)
  -- pokefirered/src/strings.c:1057 gText_Var1Players
  Window.print(RomText.plain("gText_Var1Players", { stringVars = { tostring(#UnionRoomScreen.players + 1) } }),
    count.left, count.top)
  -- pokefirered/src/data/union_room.h:1 sLinkGroupActivityNameTexts
  local sel = UnionRoomScreen.players[UnionRoomScreen.cursor]
  local label = sel and UnionRoomScreen.activityLabel(sel.activity) or ""
  if label ~= "" then Window.print(label, count.left, count.top + 2) end
end

return UnionRoomScreen

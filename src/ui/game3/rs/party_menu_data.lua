local Data = {layout = "rs", manifest = "rse/menus", frontierPike = false}

Data.actionIds = {SUMMARY = 0, SWITCH = 1, ITEM = 2, CANCEL = 3, GIVE = 4,
  TAKE = 5, TAKE_MAIL = 6, MAIL = 7, READ = 8, ITEM_CANCEL = 9}
Data.extraLabels = {SHIFT = "OtherText_Shift", ["SEND OUT"] = "OtherText_SendOut",
  ENTER = "OtherText_Enter2", ["NO ENTRY"] = "OtherText_NoEntry", STORE = "OtherText_Store"}
Data.insets = {msgX = 0, msgY = 0, actX = 0, actY = 0, cursorX = 0}
Data.text = {level = "gOtherText_Lv"}
Data.buttons = {cancel = "gOtherText_CancelWithTerminator", confirm = "OtherText_Confirm"}

local function menuData()
  return assert(require("src.ui.game3.rse.scene_kit").manifest(Data.manifest).party)
end

-- pokeruby/src/pokemon_menu.c:126
Data.actionLabels = {"OtherText_Summary", "OtherText_Switch2", "OtherText_Item", "gOtherText_CancelNoTerminator",
  "OtherText_Give2", "OtherText_Take2", "OtherText_Take", "OtherText_Mail", "OtherText_Read2",
  "gOtherText_CancelNoTerminator"}

function Data.actionText(action, fields)
  local RomText = require("src.core.game3.rom_text")
  local nativeId = Data.actionIds[action]
  if nativeId then
    local label = Data.actionLabels[nativeId + 1]
    if RomText.has(label) then return RomText.plain(label) end
    return assert(menuData().cursorOptions[nativeId + 1])
  end
  if Data.extraLabels[action] then return RomText.plain(Data.extraLabels[action]) end
  assert(fields and fields.index[action] ~= nil, "unknown native RS party action: " .. tostring(action))
  local move = fields.moves and fields.moves[fields.index[action] + 1]
  return move and require("src.core.game3.pokemon").moveName(move) or action
end

function Data.buildActions(mon, party, fields)
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.isEgg(mon) then return {"SUMMARY", "SWITCH", "CANCEL"}, {} end
  local actions, names = {}, {}
  local FieldMoves = require("src.core.game3.field_moves")
  for i = 1, 4 do
    local move = mon and mon.moves and mon.moves[i]
    local id = move and FieldMoves.normalizeMoveId(move)
    local label = id and fields and fields.byMove[id]
    if label then actions[#actions + 1], names[label] = label, true end
  end
  actions[#actions + 1] = "SUMMARY"
  local second = party and party[2]
  local species = second and (second.species or second.speciesId)
  if species and species ~= 0 and species ~= "NONE" then actions[#actions + 1] = "SWITCH" end
  local item = mon and (mon.item or mon.heldItem)
  item = require("src.core.game3.items_data").toNumericId(item) or tonumber(item) or 0
  actions[#actions + 1] = require("src.core.game3.mail").isMailItem(item) and "MAIL" or "ITEM"
  actions[#actions + 1] = "CANCEL"
  return actions, names
end

function Data.submenuActions(kind)
  if kind == "MAIL" then return {"READ", "TAKE_MAIL", "CANCEL"} end
  return {"GIVE", "TAKE", "ITEM_CANCEL"}
end

function Data.submenuDirection(input, kind)
  local direction, count = nil, 0
  local buttons = {"up", "down", "left", "right", "a", "b", "start", "select"}
  for _, key in ipairs(buttons) do
    if input:wasPressed(key) then count = count + 1; direction = key end
  end
  if count == 1 and (direction == "up" or direction == "down") then return direction end
end

function Data.submenuStep(cursor, direction, count, kind)
  local nextCursor = cursor + (direction == "up" and -1 or 1)
  if kind == "MAIL" then return (nextCursor - 1) % count + 1 end
  return math.max(1, math.min(count, nextCursor))
end

local function text(key, vars)
  return require("src.core.game3.rom_text").box(key, {stringVars = vars, maxWidth = 216})
end

function Data.takeItem(session, bag, slot)
  local mon = assert(session.party[slot])
  local Items = require("src.core.game3.items_data")
  local item = Items.toNumericId(mon.item or mon.heldItem) or tonumber(mon.item or mon.heldItem) or 0
  local Bag = require("src.core.game3.bag")
  if item == 0 then return false, "none", text("gOtherText_NotHoldingAnything", {require("src.core.game3.pokemon").displayMonName(mon)}) end
  if not Bag.add(bag, item, 1) then return false, "bag_full", text("gOtherText_BagFullCannotRemoveItem") end
  if require("src.core.game3.mail").isMailItem(item) then
    require("src.core.game3.mail").takeMailFromMon(session, mon)
    mon.mail = 255
  end
  mon.item, mon.heldItem = 0, 0
  return true, "take", text("gOtherText_ReceivedTheThingFrom",
    {require("src.core.game3.pokemon").displayMonName(mon), Items.displayName(item)})
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

function Data.sendMailToMailbox(session, mon)
  local Mail = require("src.core.game3.mail")
  local pool, source = Mail.pool(session), Mail.slot(session, mon.mail)
  assert(source, "native RS party mail slot missing")
  for id = 6, 15 do
    if (tonumber(pool[id + 1].itemId) or 0) == 0 then
      pool[id + 1] = copy(source)
      source.itemId = 0
      mon.mail, mon.item, mon.heldItem = 255, 0, 0
      return id
    end
  end
  return 255
end

function Data.takeMail(ui)
  local session, mon = ui._session, ui._party[ui.cursor]
  local function done(key)
    ui.showMessage(text(key), function() ui.mode = "list" end)
  end
  local function discard(yes)
    if not yes then ui.mode = "list"; return end
    local item = tonumber(mon.item or mon.heldItem) or 0
    if not require("src.core.game3.bag").add(ui._bag, item, 1) then done("gOtherText_BagFullCannotRemoveItem"); return end
    require("src.core.game3.mail").takeMailFromMon(session, mon)
    mon.mail = 255
    done("gOtherText_MailTaken")
  end
  ui.showMessage(text("gOtherText_SendRemovedMailPrompt"), function()
    ui.showYesNo(text("gOtherText_SendRemovedMailPrompt"), function(yes)
      if yes then
        done(Data.sendMailToMailbox(session, mon) ~= 255 and "gOtherText_MailWasSent" or "gOtherText_MailboxIsFull")
      else
        ui.showMessage(text("gOtherText_MailRemovedMessageLost"), function()
          ui.showYesNo(text("gOtherText_MailRemovedMessageLost"), discard)
        end)
      end
    end)
  end)
end

function Data.readMail(ui)
  local record = assert(require("src.core.game3.mail").get(ui._session, ui._party[ui.cursor].mail), "native RS party mail missing")
  ui.mode = "mail_read"
  require("src.ui.game3.rs.mail_reader").read(record, {session = ui._session, onClose = function()
    ui.mode, ui.actionCursor = "action", 1
  end})
end

Data.descriptorOffsets = {NO_USE = 0, FIRST = 0x1C, SECOND = 0x2A, THIRD = 0x38,
  ABLE = 0x70, ABLE_3 = 0x70, NOT_ABLE = 0x7E, ABLE_2 = 0x8C, NOT_ABLE_2 = 0x9A, LEARNED = 0xA8}
function Data.description(id)
  local offset = Data.descriptorOffsets[id]
  if offset then return {nativeRsDescriptor = offset} end
end
function Data.drawDescription(desc, x, y)
  local Kit = require("src.ui.game3.rse.scene_kit")
  local man = Kit.manifest("rse/party")
  local image = assert(Kit.image(man.order.png))
  local quad = love.graphics.newQuad(0, math.floor(desc.nativeRsDescriptor / 7) * 8, 56, 16, image:getDimensions())
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, quad, x, y)
end

local function promptText(id, name)
  local RomText = require("src.core.game3.rom_text")
  local key = RomText.key("PartyMenuPromptTexts", id)
  if RomText.has(key) then return RomText.plain(key, {stringVars = {name or ""}}) end
  return assert(require("src.ui.game3.rse.scene_kit").manifest("rse/party").prompts[id + 1])
end

local function prompt(ui, anchor, id, width)
  local memo = ui._rsPrompt
  if not (memo and memo.anchor == anchor and memo.id == id) then
    local mon = id == 5 and ui._party and ui._party[ui.cursor]
    memo = {anchor = anchor, id = id, text = promptText(id, mon and require("src.core.game3.pokemon").displayName(mon))}
    ui._rsPrompt = memo
  end
  local Chrome = require("src.ui.game3.chrome")
  Chrome.stdFrame(1, 17, width, 2)
  require("src.ui.game3.frlg_font").draw(memo.text, 8, 136, require("src.ui.game3.rs.party_chrome").textOptions("menu"))
end

function Data.drawActions(ui, item)
  local actions = item and ui.ITEM_ACTIONS or ui.ACTIONS
  local count = #actions
  local width = item and (ui._submenuKind == "MAIL" and 9 or 6) or 10
  local left = item and (30 - (width + 1)) or 19
  local top = item and (20 - (count * 2 + 2)) or (18 - count * 2)
  local Font = require("src.ui.game3.frlg_font")
  prompt(ui, actions, item and ui._submenuKind ~= "MAIL" and 13 or 5, item and (ui._submenuKind == "MAIL" and 18 or 21) or 17)
  require("src.ui.game3.chrome").stdFrame(left + 1, top + 1, width - 1, count * 2)
  local texts = ui._actionTextsFor(actions)
  for i in ipairs(actions) do Font.draw(texts[i], (left + 1) * 8, (top + 1) * 8 + (i - 1) * 16,
    require("src.ui.game3.rs.party_chrome").textOptions("menu")) end
  local cursor = item and ui.itemActionCursor or ui.actionCursor
  require("src.ui.game3.rs.menu_cursor").draw((left + 1) * 8, (top + 1) * 8 + (cursor - 1) * 16, (width - 1) * 8)
end

function Data.drawPrompt(ui)
  local id = 0
  local mode = (ui.mode == "choose" and ui._promptMode) or ui.mode
  if mode == "switch" then id = 1
  elseif mode == "give" then id = 4
  elseif mode == "move_tutor" then id = 20
  elseif mode == "use" then id = require("src.core.game3.items_data").isTm(ui._item) and 2 or 3 end
  prompt(ui, ui.mode, id, 22)
end

function Data.yesNoLabels()
  local RomText = require("src.core.game3.rom_text")
  return {RomText.at("gMenuYesNoItems", 0), RomText.at("gMenuYesNoItems", 1)}
end
Data.yesNoWindow = {left = 24, top = 9, width = 5, height = 4}

Data.chrome = "src.ui.game3.rs.party_chrome"
Data.ownsPartySprites = true
function Data.drawParty(ui) require(Data.chrome).drawParty(ui) end
function Data.updateChrome(ui) require(Data.chrome).update(ui) end
function Data.inputAllowed() return require(Data.chrome).inputAllowed() end
function Data.afterDraw() require(Data.chrome).drawFade() end
function Data.menuTextOptions() return require(Data.chrome).textOptions("menu") end
function Data.drawMessage(value)
  require("src.ui.game3.chrome").stdFrame(4, 15, 22, 4)
  if value then
    local Font = require("src.ui.game3.frlg_font")
    local opts = Data.menuTextOptions()
    opts.maxWidth, opts.linePitch = 176, 16
    Font.draw(Font.wrap(value, 176, opts), 32, 120, opts)
  end
end

return Data

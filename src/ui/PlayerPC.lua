-- The player's item-storage PC (engine/menus/players_pc.asm):
-- WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / LOG OFF over
-- game.save.pcItems ({ ITEM_ID = count }; New Game seeds { POTION = 1 },
-- older saves may still be empty until first deposit).  Withdraw and
-- deposit ask "How many?" via the quantity selector (key items always
-- move one); toss discards after a YES/NO confirm.  Follows the
-- BoxMenu/BagMenu list idioms.

local Bag = require("src.inventory.Bag")
local ChoiceBox = require("src.ui.ChoiceBox")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local PlayerPC = { isMenu = true }

local function itemName(game, id)
  local def = game.data.items[id]
  return def and def.name or id
end

local function buildItems(game, rows)
  local items = {}
  for _, row in ipairs(rows) do
    local id = row.id
    if row.count ~= nil then
      local def = game.data.items[id]
      local keyItem = (def and def.keyItem) or id:find("^HM_") ~= nil
      table.insert(items, {
        value = id,
        label = itemName(game, id),
        count = not keyItem and row.count or nil,
        slot = row.slot,
        stack = row.count,
      })
    end
  end
  -- the $ff terminator's row (home/list_menu.asm:371-372, 523-528)
  items[#items + 1] = { cancel = true, label = romText(game.data, "CancelTextString", nil) }
  return items
end

-- A on CANCEL leaves the list exactly like B (home/list_menu.asm:105-110)
local function leftOnCancel(item, list)
  if item and item.cancel then
    list:close()
    return true
  end
  return false
end

-- Ask "How many?" (DepositHowManyText/WithdrawHowManyText →
-- DisplayChooseQuantityMenu) capped at the stack count.  Key items and
-- HMs always move one, with no prompt (IsKeyItem in players_pc.asm).
-- cb(qty) runs only on confirm.
local function askQuantity(game, list, count, id, howMany, cb)
  local def = game.data.items[id]
  list.pcQtyBox = nil
  if (def and def.keyItem) or id:find("^HM_") then
    cb(1)
    return
  end
  local prompt = list.footer
  list.footer = romText(game.data, howMany, nil)
  local QuantityBox = require("src.ui.QuantityBox")
  local box
  box = QuantityBox.new(game, {
    max = count,
    onDone = function(qty)
      if qty then
        -- engine/menus/players_pc.asm:136-137
        list.pcQtyBox = box
        cb(qty)
      else
        list.footer = prompt
      end
    end,
  })
  game.stack:push(box)
end

local function refreshRows(list, items)
  if #items < #list.items then
    list.index, list.scroll = 1, 0 -- engine/items/inventory.asm:131
  end
  list.items = items
  list.index = math.max(1, math.min(list.index, #list.items))
end

local function pcList(game, items, opts)
  local list = ListMenu.new(game, nil, items, opts)
  list.pcPrompt = list.footer
  list.pcCompletionBlink = 0
  local draw = list.draw
  list.draw = function(self)
    draw(self)
    if self.pcCompletion and self.pcQtyBox then self.pcQtyBox:draw() end
    if self.pcCompletion
       and self.pcCompletionBlink % 60 < 30 then
      Font.drawCode(Theme.moreArrow, 144, 128)
    end
  end
  local update = list.update
  list.update = function(self, dt)
    if self.pcCompletion then
      self.pcCompletionBlink = (self.pcCompletionBlink + 1) % 60
      local input = game.input
      if input:wasPressed("a") or input:wasPressed("b") then
        Sound.playPress(game.data)
        self.pcCompletion = nil
        self.pcQtyBox = nil
        local after = self.pcAfter
        self.pcAfter = nil
        if after then after() end
        self.footer = self.pcPrompt
      end
      return
    end
    update(self, dt)
  end
  function list:showCompletion(text, after)
    self.footer = text
    self.pcCompletion = true
    self.pcCompletionBlink = 0
    self.pcAfter = after
  end
  return list
end

local function withdraw(game)
  local pc = game.save.pcItems
  -- players_pc.asm:144-149: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText", nil), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, Bag.pcRows(game.save, game.data)), {
    kind = "pc_item_withdraw",
    messageBox = true,
    -- players_pc.asm:151-152 WhatToWithdrawText, printed before the list
    footer = romText(game.data, "_WhatToWithdrawText", nil),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      -- engine/menus/players_pc.asm:171
      askQuantity(game, list, item.stack or pc[item.value] or 1, item.value, "_WithdrawHowManyText", function(qty)
        if not Bag.add(game.save, item.value, qty, game.data) then
          list.footer = romText(game.data, "_CantCarryMoreText", nil)
          return
        end
        Bag.pcRemove(game.save, item.value, qty, game.data, item.slot)
        Sound.play(game.data, "Withdraw_Deposit")
        list:showCompletion(romText(game.data, "_WithdrewItemText", nil, itemName(game, item.value)),
          function() refreshRows(list, buildItems(game, Bag.pcRows(game.save, game.data))) end) -- engine/menus/players_pc.asm:191
      end)
    end,
  }))
end

-- wNumBoxItems capacity: 50 stacks (PC_ITEM_CAPACITY)
local function storeInPC(game, pc, id, qty)
  local cap = game.data.field.pcItemCap or 50
  return Bag.pcAdd(game.save, id, qty, game.data, cap)
end

local function deposit(game)
  local pc = game.save.pcItems
  local inv = game.save.inventory
  -- engine/menus/players_pc.asm:99 wListPointer = wNumBagItems, so deposit order == bag order
  local order = Bag.order(game.save, game.data)
  -- players_pc.asm:90-95: an empty bag never reaches the list
  if #order == 0 then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingToDepositText", nil), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, Bag.rows(game.save, game.data)), {
    kind = "pc_item_deposit",
    messageBox = true,
    -- players_pc.asm:97-98 WhatToDepositText, printed before the list
    footer = romText(game.data, "_WhatToDepositText", nil),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      -- engine/menus/players_pc.asm:117
      askQuantity(game, list, item.stack or inv[item.value] or 1, item.value, "_DepositHowManyText", function(qty)
        if not storeInPC(game, pc, item.value, qty) then
          list.footer = romText(game.data, "_NoRoomToStoreText", nil)
          return
        end
        Bag.remove(game.save, item.value, qty, game.data, item.slot)
        Sound.play(game.data, "Withdraw_Deposit")
        list:showCompletion(romText(game.data, "_ItemWasStoredText", nil, itemName(game, item.value)),
          function()
            refreshRows(list, buildItems(game, Bag.rows(game.save, game.data)))
          end) -- engine/menus/players_pc.asm:137
      end)
    end,
  }))
end

local function toss(game)
  local pc = game.save.pcItems
  -- players_pc.asm:196-201: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText", nil), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, Bag.pcRows(game.save, game.data)), {
    kind = "pc_item_toss",
    messageBox = true,
    -- players_pc.asm:205-206 WhatToTossText, printed before the list
    footer = romText(game.data, "_WhatToTossText", nil),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      local def = game.data.items[item.value]
      if (def and def.keyItem) or item.value:find("^HM_") then
        list.footer = romText(game.data, "_TooImportantToTossText", nil)
        return
      end
      local QuantityBox = require("src.ui.QuantityBox")
      game.stack:push(QuantityBox.new(game, {
        max = item.stack or pc[item.value] or 1,
        onDone = function(qty)
          if not qty then return end
          -- engine/items/item_effects.asm:2564
          list.footer = romText(game.data, "_IsItOKToTossItemText", nil, itemName(game, item.value))
          game.stack:push(ChoiceBox.new(game, function(yes)
            if yes then
              Bag.pcRemove(game.save, item.value, qty, game.data, item.slot)
              list:showCompletion(romText(game.data, "_ThrewAwayItemText", nil, itemName(game, item.value)),
                function() refreshRows(list, buildItems(game, Bag.pcRows(game.save, game.data))) end) -- engine/menus/players_pc.asm:240
            else
              list.footer = nil
            end
          end, { noSound = true }))
        end,
      }))
    end,
  }))
end

-- opts.direct marks the bedroom PC (OpenRedsPC), the one entry outside the main menu
function PlayerPC.new(game, opts)
  game.save.pcItems = game.save.pcItems or {}
  -- ExitPlayerPC (players_pc.asm) rings SFX_TURN_OFF_PC only while
  -- BIT_USING_GENERIC_PC is clear (#960)
  local logOff = function()
    if opts and opts.direct then Sound.play(game.data, "Turn_Off_PC") end
  end
  local rows = {
    -- keepOpen so B in the item lists returns here instead of dropping the
    -- whole PC session (players_pc.asm re-shows the PC menu); same pattern
    -- as BoxMenu's rows
    { label = Strings("WITHDRAW ITEM"), keepOpen = true, onSelect = function() withdraw(game) end },
    { label = Strings("DEPOSIT ITEM"), keepOpen = true, onSelect = function() deposit(game) end },
    { label = Strings("TOSS ITEM"), keepOpen = true, onSelect = function() toss(game) end },
    { label = Strings("LOG OFF"), onSelect = logOff },
  }
  -- silent PC session (BIT_NO_MENU_BUTTON_SOUND); players_pc.asm
  -- PlayersPCMenu TextBoxBorder (0,0) b=8 c=14 → 16x10
  local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = 10,
       noSound = true, onCancel = logOff })
  local prompt = TextBox.strip(romText(game.data, "_WhatDoYouWantText", nil))
  for _, row in ipairs(rows) do
    local onSelect = row.onSelect
    if row.keepOpen and onSelect then
      row.onSelect = function()
        menu.hollowIndex = menu.index -- engine/menus/players_pc.asm:55
        onSelect()
      end
    end
  end
  local baseUpdate = menu.update
  function menu:update(dt)
    if self.game.stack:top() == self then self.hollowIndex = nil end
    return baseUpdate(self, dt)
  end
  local baseDraw = menu.draw
  function menu:draw()
    baseDraw(self)
    Font.drawBox(0, 12, 20, 6) -- engine/menus/players_pc.asm:50
    love.graphics.setColor(0, 0, 0, 1)
    local y = 112
    for line in (prompt .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, y)
      y = y + 16
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  menu.isMenu = true
  return menu
end

return PlayerPC

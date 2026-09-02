-- The player's item-storage PC (engine/menus/players_pc.asm):
-- WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / LOG OFF over
-- game.save.pcItems ({ ITEM_ID = count }; New Game seeds { POTION = 1 },
-- older saves may still be empty until first deposit).  Withdraw and
-- deposit ask "How many?" via the quantity selector (key items always
-- move one); toss discards after a YES/NO confirm.  Follows the
-- BoxMenu/BagMenu list idioms.

local ChoiceBox = require("src.ui.ChoiceBox")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")

local PlayerPC = {}

local function itemName(game, id)
  local def = game.data.items[id]
  return def and def.name or id
end

local function buildItems(game, store, order)
  local items = {}
  local ids = order
  if not ids then
    ids = {}
    for id in pairs(store) do table.insert(ids, id) end
    table.sort(ids)
  end
  for _, id in ipairs(ids) do
    if store[id] then
      table.insert(items, {
        value = id,
        label = itemName(game, id),
        count = store[id],
      })
    end
  end
  -- the $ff terminator's row (home/list_menu.asm:371-372, 523-528)
  items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
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
local function askQuantity(game, list, count, id, cb)
  local def = game.data.items[id]
  if (def and def.keyItem) or id:find("^HM_") then
    cb(1)
    return
  end
  list.footer = Strings("How many?")
  local QuantityBox = require("src.ui.QuantityBox")
  game.stack:push(QuantityBox.new(game, {
    max = count,
    onDone = function(qty)
      if qty then cb(qty) else list.footer = nil end
    end,
  }))
end

-- refresh the chosen row's count from `store` (or drop the row)
local function refreshRow(list, store, id)
  for i, it in ipairs(list.items) do
    if it.value == id then
      if store[id] then
        it.count = store[id]
      else
        table.remove(list.items, i)
      end
      break
    end
  end
  list.index = math.max(1, math.min(list.index, #list.items))
end

local function withdraw(game)
  local pc = game.save.pcItems
  -- players_pc.asm:144-149: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText",
      "There is nothing\nstored."), nil, { noSound = true }))
    return
  end
  game.stack:push(ListMenu.new(game, nil, buildItems(game, pc), {
    kind = "pc_item_withdraw",
    messageBox = true,
    -- players_pc.asm:151-152 WhatToWithdrawText, printed before the list
    footer = romText(game.data, "_WhatToWithdrawText",
      "What do you want\nto withdraw?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      askQuantity(game, list, pc[item.value] or 1, item.value, function(qty)
        local Bag = require("src.inventory.Bag")
        if not Bag.add(game.save, item.value, qty, game.data) then
          list.footer = Strings("You can't carry\nany more items.")
          return
        end
        pc[item.value] = pc[item.value] - qty
        if pc[item.value] <= 0 then pc[item.value] = nil end
        refreshRow(list, pc, item.value)
        Sound.play(game.data, "Withdraw_Deposit")
        list.footer = Strings("Withdrew\n%s.", itemName(game, item.value))
      end)
    end,
  }))
end

-- wNumBoxItems capacity: 50 stacks (PC_ITEM_CAPACITY)
local function pcFull(game, pc, id)
  if pc[id] then return false end -- growing an existing stack is fine
  local cap = game.data.field.pcItemCap or 50
  local stacks = 0
  for _ in pairs(pc) do stacks = stacks + 1 end
  return stacks >= cap
end

local function deposit(game)
  local pc = game.save.pcItems
  local inv = game.save.inventory
  local Bag = require("src.inventory.Bag")
  -- engine/menus/players_pc.asm:99 wListPointer = wNumBagItems, so deposit order == bag order
  local order = Bag.order(game.save, game.data)
  -- players_pc.asm:90-95: an empty bag never reaches the list
  if #order == 0 then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingToDepositText",
      "You have nothing\nto deposit."), nil, { noSound = true }))
    return
  end
  game.stack:push(ListMenu.new(game, nil, buildItems(game, inv, order), {
    kind = "pc_item_deposit",
    messageBox = true,
    -- players_pc.asm:97-98 WhatToDepositText, printed before the list
    footer = romText(game.data, "_WhatToDepositText",
      "What do you want\nto deposit?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      askQuantity(game, list, inv[item.value] or 1, item.value, function(qty)
        if pcFull(game, pc, item.value) then
          list.footer = Strings("No room left to\nstore items.")
          return
        end
        require("src.inventory.Bag").remove(game.save, item.value, qty)
        pc[item.value] = (pc[item.value] or 0) + qty
        refreshRow(list, inv, item.value)
        Sound.play(game.data, "Withdraw_Deposit")
        list.footer = Strings("%s was\nstored via PC.", itemName(game, item.value))
      end)
    end,
  }))
end

local function toss(game)
  local pc = game.save.pcItems
  -- players_pc.asm:196-201: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText",
      "There is nothing\nstored."), nil, { noSound = true }))
    return
  end
  game.stack:push(ListMenu.new(game, nil, buildItems(game, pc), {
    kind = "pc_item_toss",
    messageBox = true,
    -- players_pc.asm:205-206 WhatToTossText, printed before the list
    footer = romText(game.data, "_WhatToTossText",
      "What do you want\nto toss away?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      local def = game.data.items[item.value]
      if (def and def.keyItem) or item.value:find("^HM_") then
        list.footer = Strings("That's too impor-\ntant to toss!")
        return
      end
      local QuantityBox = require("src.ui.QuantityBox")
      game.stack:push(QuantityBox.new(game, {
        max = pc[item.value] or 1,
        onDone = function(qty)
          if not qty then return end
          list.footer = Strings("Toss %s?", itemName(game, item.value))
          game.stack:push(ChoiceBox.new(game, function(yes)
            if yes then
              pc[item.value] = pc[item.value] - qty
              if pc[item.value] <= 0 then pc[item.value] = nil end
              refreshRow(list, pc, item.value)
              list.footer = Strings("Threw away %s.", itemName(game, item.value))
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
  return Menu.new(game, {
    -- keepOpen so B in the item lists returns here instead of dropping the
    -- whole PC session (players_pc.asm re-shows the PC menu); same pattern
    -- as BoxMenu's rows
    { label = Strings("WITHDRAW ITEM"), keepOpen = true, onSelect = function() withdraw(game) end },
    { label = Strings("DEPOSIT ITEM"), keepOpen = true, onSelect = function() deposit(game) end },
    { label = Strings("TOSS ITEM"), keepOpen = true, onSelect = function() toss(game) end },
    { label = Strings("LOG OFF"), onSelect = logOff },
    -- silent PC session (BIT_NO_MENU_BUTTON_SOUND); players_pc.asm
    -- PlayersPCMenu TextBoxBorder (0,0) b=8 c=14 → 16x10
  }, { tx = 0, ty = 0, tw = 16, th = 10, noSound = true, onCancel = logOff })
end

return PlayerPC

-- PC storage: 12 boxes of 20 (engine/pokemon/bills_pc.asm semantics via
-- src/pokemon/Boxes.lua): withdraw from / deposit to the current box,
-- plus CHANGE BOX.

local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local Party = require("src.pokemon.Party")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local BoxMenu = {}

local function monLabel(game, mon)
  local def = game.data.pokemon[mon.species]
  return Strings("%s :L%d", mon.nickname or def.name, mon.level)
end

local function monName(game, mon)
  local def = game.data.pokemon[mon.species]
  return mon.nickname or def.name
end

-- Per-mon submenu (bills_pc.asm DisplayDepositWithdrawMenu): the chosen
-- action + STATS + CANCEL.  STATS shows the status screen and returns
-- here; CANCEL/B goes back to the list.
local function monSubmenu(game, action, mon, onAction)
  game.stack:push(Menu.new(game, {
    { label = action, onSelect = onAction },
    {
      label = Strings("STATS"),
      keepOpen = true,
      onSelect = function()
        require("src.ui.Screens").push(game, "SummaryMenu", mon)
      end,
    },
    { label = Strings("CANCEL") },
  }, { tx = 9, ty = 10, tw = 11, th = 8, noSound = true }))
end

-- After a successful transfer: close the mon list (BoxMenu stays beneath
-- via keepOpen) and show the taken-out / stored text (jp BillsPCMenu).
local function afterTransfer(game, list, text)
  list:close()
  game.stack:push(TextBox.new(game, text))
end

local function withdraw(game)
  local box = Boxes.active(game.save)
  local t = game.data.text
  if #box == 0 then
    game.stack:push(TextBox.new(game, t._NoMonText
      or Strings("What? There are\nno POKéMON here!")))
    return
  end
  if #game.save.party >= Party.MAX then
    game.stack:push(TextBox.new(game, t._CantTakeMonText
      or Strings("You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst.")))
    return
  end
  local items = {}
  for i, mon in ipairs(box) do
    table.insert(items, { label = monLabel(game, mon), value = i })
  end
  game.stack:push(ListMenu.new(game,
    Strings("BOX %d (WITHDRAW)", game.save.currentBox), items, {
    onChoose = function(item, list)
      local mon = box[item.value]
      if not mon then return end
      monSubmenu(game, "WITHDRAW", mon, function()
        if #game.save.party >= Party.MAX then
          list.footer = "The party is full!"
          return
        end
        table.remove(box, item.value)
        table.insert(game.save.party, mon)
        local name = monName(game, mon)
        game.stringBuffer = name
        require("src.core.Sound").playCry(game.data, mon.species)
        afterTransfer(game, list, t._MonIsTakenOutText
          or Strings("%s is\ntaken out.\vGot %s.", name, name))
      end)
    end,
  }))
end

local function deposit(game)
  local t = game.data.text
  if #game.save.party <= 1 then
    game.stack:push(TextBox.new(game, t._CantDepositLastMonText
      or Strings("You can't deposit\nthe last POKéMON!")))
    return
  end
  local box = Boxes.active(game.save)
  if #box >= Boxes.CAPACITY then
    game.stack:push(TextBox.new(game, t._BoxFullText
      or Strings("Oops! This Box is\nfull of POKéMON.")))
    return
  end
  local items = {}
  for i, mon in ipairs(game.save.party) do
    table.insert(items, { label = monLabel(game, mon), value = i })
  end
  game.stack:push(ListMenu.new(game, "PARTY (DEPOSIT)", items, {
    onChoose = function(item, list)
      local mon = game.save.party[item.value]
      if not mon then return end
      monSubmenu(game, "DEPOSIT", mon, function()
        if #game.save.party <= 1 then
          list.footer = Strings("You need at least\none POKéMON!")
          return
        end
        local active = Boxes.active(game.save)
        if #active >= Boxes.CAPACITY then
          list.footer = Strings("BOX %d is full!", game.save.currentBox)
          return
        end
        table.remove(game.save.party, item.value)
        table.insert(active, mon)
        local name = monName(game, mon)
        game.stringBuffer = name
        game.boxNumString = tostring(game.save.currentBox)
        require("src.core.Sound").playCry(game.data, mon.species)
        afterTransfer(game, list, t._MonWasStoredText
          or Strings("%s was\nstored in Box %s.", name, game.boxNumString))
      end)
    end,
  }))
end

-- RELEASE POKéMON (bills_pc.asm BillsPCRelease): confirm, then "Bye [MON]!".
-- Index by list.index (not stale item.value) after removeCurrent (#171).
local function release(game)
  local box = Boxes.active(game.save)
  local t = game.data.text
  if #box == 0 then
    game.stack:push(TextBox.new(game, t._NoMonText
      or Strings("What? There are\nno POKéMON here!")))
    return
  end
  local items = {}
  for i, mon in ipairs(box) do
    table.insert(items, { label = monLabel(game, mon), value = i })
  end
  game.stack:push(ListMenu.new(game,
    Strings("BOX %d (RELEASE)", game.save.currentBox), items, {
    onChoose = function(_, list)
      local mon = box[list.index]
      if not mon then return end
      local name = monName(game, mon)
      local ChoiceBox = require("src.ui.ChoiceBox")
      game.stack:push(TextBox.new(game,
        Strings("Once released,\n%s is\ngone forever. OK?", name), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then return end
          table.remove(box, list.index)
          require("src.core.Sound").playCry(game.data, mon.species)
          game.stack:push(TextBox.new(game,
            Strings("%s was\nreleased outside.\fBye %s!", name, name)))
          list:removeCurrent()
        end, { defaultNo = true, noSound = true }))
      end))
    end,
  }))
end

local function changeBox(game)
  local boxes = Boxes.ensure(game.save)
  local items = {}
  for i = 1, Boxes.COUNT do
    local mark = i == game.save.currentBox and "*" or " "
    table.insert(items, {
      label = Strings("%sBOX %2d", mark, i),
      right = ("%d/%d"):format(#boxes[i], Boxes.CAPACITY),
      value = i,
    })
  end
  game.stack:push(ListMenu.new(game, "CHANGE BOX", items, {
    onChoose = function(item, list)
      -- the original asks BEFORE switching ("When you change a #MON
      -- BOX, data will be saved. OK?"); declining aborts the change
      local ChoiceBox = require("src.ui.ChoiceBox")
      game.stack:push(TextBox.new(game,
        Strings("When you change a\nPOKéMON BOX, data\nwill be saved. OK?"), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then return end
          game.save.currentBox = item.value
          if game.writeSave then game:writeSave() end
          list:close()
        end, { noSound = true }))
      end))
    end,
  }))
end

-- bills_pc.asm BillsPCMenu chrome: What? text box + BOX No. overlay
local function drawChrome(game)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("What?"), 8, 112)
  Font.drawBox(9, 14, 11, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("BOX No."), 80, 128)
  local n = game.save.currentBox or 1
  if n >= 10 then
    Font.draw(tostring(n), 136, 128)
  else
    Font.draw(tostring(n), 144, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function BoxMenu.new(game)
  Boxes.ensure(game.save)
  -- bills_pc.asm BillsPCMenu: TextBoxBorder at (0,0) with interior
  -- 12x10 → total 14x12.  "CHANGE BOX" / "WITHDRAW <PK><MN>" need the
  -- full interior (cursor col + label).  keepOpen so WITHDRAW/DEPOSIT/
  -- RELEASE/CHANGE BOX leave this menu underneath (jp BillsPCMenu).
  local menu = Menu.new(game, {
    { label = Strings("WITHDRAW <PK><MN>"), keepOpen = true,
      onSelect = function() withdraw(game) end },
    { label = Strings("DEPOSIT <PK><MN>"), keepOpen = true,
      onSelect = function() deposit(game) end },
    { label = Strings("RELEASE <PK><MN>"), keepOpen = true,
      onSelect = function() release(game) end },
    { label = Strings("CHANGE BOX"), keepOpen = true,
      onSelect = function() changeBox(game) end },
    { label = Strings("SEE YA!") },
    -- Bill's PC runs silent end to end (BIT_NO_MENU_BUTTON_SOUND,
    -- engine/menus/pokemon_pc.asm)
  }, { tx = 0, ty = 0, tw = 14, th = 12, noSound = true })
  local baseDraw = menu.draw
  function menu:draw()
    baseDraw(self)
    drawChrome(game)
  end
  return menu
end

return BoxMenu

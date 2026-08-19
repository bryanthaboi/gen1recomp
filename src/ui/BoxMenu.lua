-- PC storage: 12 boxes of 20 (engine/pokemon/bills_pc.asm semantics via
-- src/pokemon/Boxes.lua): withdraw from / deposit to the current box,
-- plus CHANGE BOX.

local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local Party = require("src.pokemon.Party")
local Stats = require("src.pokemon.Stats")
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
    noSound = true, -- PCMainMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    kind = "pc_box_withdraw",
    onChoose = function(item, list)
      local mon = box[item.value]
      if not mon then return end
      monSubmenu(game, "WITHDRAW", mon, function()
        if #game.save.party >= Party.MAX then
          list.footer = "The party is full!"
          return
        end
        -- add_mon.asm _MoveMon's tail ("returning mon to party, compute
        -- level and stats"): a box mon carries no stat block, because
        -- box_struct stops before MON_LEVEL/MON_STATS, so the party copy
        -- runs CalcStats.  Without it a mon decoded out of an imported .sav
        -- reaches the party menu with mon.stats nil and the HP bar draw
        -- nil-indexes it (#304, same family as #233).  Already-shaped mons
        -- (everything the engine itself put in a box) pass through.
        Stats.ensure(game.data.pokemon[mon.species], mon)
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
    noSound = true, -- PCMainMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    kind = "pc_box_deposit",
    onChoose = function(item, list)
      local mon = game.save.party[item.value]
      if not mon then return end
      local Follower = require("src.world.PikachuFollower")
      if Follower.isFollowingDisabled(game.overworld)
          and Follower.isStarterPikachu(game.save, mon) then
        game.stack:push(TextBox.new(game, t._SleepingPikachuText2
          or Strings("There isn't any\nresponse...")))
        return
      end
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
        -- PIKAHAPPY_DEPOSITED (engine/pokemon/bills_pc.asm:247)
        require("src.world.PikachuFollower")
          .modifyHappiness(game.save, "DEPOSITED", mon)
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
    noSound = true, -- PCMainMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    kind = "pc_box_release",
    onChoose = function(_, list)
      local mon = box[list.index]
      if not mon then return end
      local name = monName(game, mon)
      if require("src.core.GameVersion").isYellow()
         and mon.species == "PIKACHU"
         and mon.otId == game.save.player.id
         and mon.ot == game.save.player.name then
        require("src.core.Sound").playCry(game.data, mon.species)
        game.stack:push(TextBox.new(game,
          ((t._PikachuUnhappyText or Strings("%s looks\nunhappy about it!", name))
            :gsub("{RAM:wNameBuffer}", name))))
        return
      end
      game.stack:push(TextBox.new(game,
        Strings("Once released,\n%s is\ngone forever. OK?", name), nil, {
        defaultNo = true, noSound = true,
        choice = function(yes)
          if not yes then return end
          table.remove(box, list.index)
          require("src.core.Sound").playCry(game.data, mon.species)
          game.stack:push(TextBox.new(game,
            Strings("%s was\nreleased outside.\fBye %s!", name, name)))
          list:removeCurrent()
        end,
      }))
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
    noSound = true, -- PCMainMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    kind = "pc_box_change",
    onChoose = function(item, list)
      -- the original asks BEFORE switching ("When you change a #MON
      -- BOX, data will be saved. OK?"); declining aborts the change
      game.stack:push(TextBox.new(game,
        Strings("When you change a\nPOKéMON BOX, data\nwill be saved. OK?"), nil, {
        noSound = true,
        choice = function(yes)
          if not yes then return end
          game.save.currentBox = item.value
          if game.writeSave then game:writeSave() end
          -- ChangeBox (engine/menus/save.asm) rings SFX_SAVE after SaveGameData (#1044)
          require("src.core.Sound").play(game.data, "Save")
          list:close()
        end,
      }))
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

-- PrintPCBox (engine/printer/printer.asm): Yellow's box-list print job,
-- box number plus each stored mon's name, level and dex number; the PNG
-- under prints/ stands in for the printer paper.
local function printBox(game)
  local box = Boxes.active(game.save)
  local Printer = require("src.core.Printer")
  local TextBox = require("src.render.TextBox")
  local h = 32 + math.max(1, #box) * 10
  local saved, err = Printer.save("box_" .. (game.save.currentBox or 1),
    160, h, function()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, h)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(Strings("BOX No.%d", game.save.currentBox or 1), 8, 8)
      if #box == 0 then Font.draw(Strings("Empty."), 8, 24) end
      for i, mon in ipairs(box) do
        local def = game.data.pokemon[mon.species]
        Font.draw(mon.nickname or (def and def.name) or tostring(mon.species),
                  8, 14 + i * 10)
        Font.draw(Strings(":L%d No.%03d", mon.level or 0,
                          def and def.dex or 0), 88, 14 + i * 10)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  game.stack:push(TextBox.new(game, saved
    and Strings("Printed BOX %d!\fSaved as\n%s\vin the save\nfolder.",
                game.save.currentBox or 1, saved)
    or Strings("Printer error!\n%s", tostring(err))))
end

function BoxMenu.new(game)
  Boxes.ensure(game.save)
  -- bills_pc.asm BillsPCMenu: TextBoxBorder at (0,0) with interior
  -- 12x10 → total 14x12.  "CHANGE BOX" / "WITHDRAW <PK><MN>" need the
  -- full interior (cursor col + label).  keepOpen so WITHDRAW/DEPOSIT/
  -- RELEASE/CHANGE BOX leave this menu underneath (jp BillsPCMenu).
  local items = {
    { label = Strings("WITHDRAW <PK><MN>"), keepOpen = true,
      onSelect = function() withdraw(game) end },
    { label = Strings("DEPOSIT <PK><MN>"), keepOpen = true,
      onSelect = function() deposit(game) end },
    { label = Strings("RELEASE <PK><MN>"), keepOpen = true,
      onSelect = function() release(game) end },
    { label = Strings("CHANGE BOX"), keepOpen = true,
      onSelect = function() changeBox(game) end },
  }
  -- Yellow's PRINT BOX item (bills_pc.asm _YELLOW -> PrintPCBox): the
  -- Game Boy Printer box list becomes a PNG under prints/, like the
  -- Pokédex PRNT stand-in
  if require("src.core.GameVersion").isYellow() then
    items[#items + 1] = { label = Strings("PRINT BOX"), keepOpen = true,
      onSelect = function() printBox(game) end }
  end
  items[#items + 1] = { label = Strings("SEE YA!") }
  local menu = Menu.new(game, items,
    -- Bill's PC runs silent end to end (BIT_NO_MENU_BUTTON_SOUND,
    -- engine/menus/pokemon_pc.asm)
    { tx = 0, ty = 0, tw = 14, th = #items * 2 + 2, noSound = true })
  local baseDraw = menu.draw
  function menu:draw()
    baseDraw(self)
    drawChrome(game)
  end
  return menu
end

return BoxMenu

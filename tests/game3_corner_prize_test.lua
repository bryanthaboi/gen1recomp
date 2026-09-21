#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Prize = require("src.ui.game3.prize_corner")
local Corner = require("src.core.game3.scripting.natives_corner")
local Bag = require("src.core.game3.bag")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local PRET_STRINGS = "../pokefirered/src/strings.c"
local PRET_MENU = "../pokefirered/src/script_menu.c"
local PRET_SPECIALS = "../pokefirered/src/field_specials.c"
local PRET_PRIZE_ROOM = "../pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc"

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local strings = slurp(PRET_STRINGS)
local menu = slurp(PRET_MENU)
local prizeRoom = slurp(PRET_PRIZE_ROOM)

-- pokefirered/src/script_menu.c:520
local LIST_SYMBOL = {
  [Prize.LIST_POKEMON_PRIZES] = "sMultichoiceList_GameCornerPokemonPrizes",
  [Prize.LIST_COIN_PURCHASE] = "sMultichoiceList_GameCornerCoinPurchaseCounter",
  [Prize.LIST_TM_PRIZES] = "sMultichoiceList_GameCornerTMPrizes",
  [Prize.LIST_BATTLE_ITEM_PRIZES] = "sMultichoiceList_GameCornerBattleItemPrizes",
}

local function listSymbols(listId)
  if not menu then return nil end
  local decl = "static const struct MenuAction " .. LIST_SYMBOL[listId] .. "[] = {"
  local i = menu:find(decl, 1, true)
  if not i then return nil end
  local stop = menu:find("\n};", i, true)
  local body = menu:sub(i + #decl, stop)
  -- pokefirered/src/script_menu.c:318
  local lg = body:find("#elif defined(LEAFGREEN)", 1, true)
  local head = lg and body:sub(1, lg - 1) or body
  local tail = lg and body:sub((body:find("#endif", lg, true) or #body)) or ""
  local out = {}
  for sym in (head .. tail):gmatch("{%s*(g[%w_]+)%s*}") do out[#out + 1] = sym end
  return out
end

local function flatten(literal)
  local s = literal:gsub("{[^}]*}", " ")
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local INVENTED_SIX = {
  "WIDGET 1,234 COINS", "GIZMO 999 COINS", "DOODAD 12,345 COINS",
  "GADGET 40 COINS", "THINGUMMY 7 COINS", "LAST ROW",
}
local INVENTED_TWO = { "WIDGET 1,234 COINS", "LAST ROW" }

local function stringLiteral(sym)
  if not strings then return nil end
  local pat = "const u8 " .. sym .. "%[%] = _%(\"(.-)\"%);"
  return strings:match(pat)
end

print("[test] 1. Every Game Corner prize list is routed to the prize counter")
do
  eq(Prize.LIST_POKEMON_PRIZES, 14, "MULTICHOICE_GAME_CORNER_POKEMON_PRIZES")
  eq(Prize.LIST_COIN_PURCHASE, 27, "MULTICHOICE_GAME_CORNER_COIN_PURCHASE_COUNTER")
  eq(Prize.LIST_TM_PRIZES, 30, "MULTICHOICE_GAME_CORNER_TMPRIZES")
  eq(Prize.LIST_BATTLE_ITEM_PRIZES, 41, "MULTICHOICE_GAME_CORNER_BATTLE_ITEM_PRIZES")
  for _, id in ipairs({ 14, 27, 30, 41 }) do
    check(Prize.isPrizeList(id), "list " .. id .. " is a prize list")
  end
  check(not Prize.isPrizeList(5), "an ordinary list is left to the generic menu")
  check(not Prize.isPrizeList(nil), "a missing list id is not a prize list")
end

print("[test] 2. The column stops match pret's CLEAR_TO byte for byte")
if not (strings and menu) then
  print("[skip] no pret checkout at " .. PRET_STRINGS)
else
  for listId, columns in pairs(Prize.COLUMNS) do
    local syms = listSymbols(listId)
    check(syms ~= nil and #syms > 0, "pret declares " .. LIST_SYMBOL[listId])
    if syms then
      for i, sym in ipairs(syms) do
        local lit = stringLiteral(sym)
        check(lit ~= nil, sym .. " has a string literal")
        if lit then
          local stop = lit:match("{CLEAR_TO 0x(%x+)}")
          eq(columns[i], stop and tonumber(stop, 16) or nil,
            string.format("list %d row %d column stop (%s)", listId, i, sym))
        end
      end
      eq(#syms, #columns + 1, "list " .. listId .. " ends on a row with no price")
    end
  end
end

print("[test] 3. The name and the price split out of the flattened label")
if not (strings and menu) then
  print("[skip] no pret checkout at " .. PRET_STRINGS)
else
  for listId, columns in pairs(Prize.COLUMNS) do
    local syms = listSymbols(listId)
    if syms then
      local labels = {}
      for i, sym in ipairs(syms) do labels[i] = flatten(stringLiteral(sym) or "") end
      local rows = Prize.buildRows(listId, labels)
      eq(#rows, #syms, "list " .. listId .. " built every row")
      for i, sym in ipairs(syms) do
        local lit = stringLiteral(sym) or ""
        local priceSrc = lit:match("{CLEAR_TO 0x%x+}(.*)$")
        if priceSrc then
          local expect = flatten(priceSrc)
          eq(rows[i].amount, expect, string.format("list %d row %d price (%s)", listId, i, sym))
          local nameSrc = lit:match("^(.-){CLEAR_TO")
          eq(rows[i].name, flatten(nameSrc or ""), string.format("list %d row %d name (%s)", listId, i, sym))
          eq(rows[i].column, columns[i], string.format("list %d row %d keeps its stop", listId, i))
        else
          eq(rows[i].amount, nil, string.format("list %d row %d has no price (%s)", listId, i, sym))
          eq(rows[i].name, flatten(lit), string.format("list %d row %d is the whole label", listId, i))
        end
      end
    end
  end
end

print("[test] 4. The coin purchase counter prints its whole row in the small font")
if not strings then
  print("[skip] no pret checkout at " .. PRET_STRINGS)
else
  local lit = stringLiteral("gText_50Coins_1000")
  check(lit ~= nil, "pret declares gText_50Coins_1000")
  if lit then
    check(lit:find("{FONT_SMALL}", 1, true) < lit:find("{CLEAR_TO", 1, true),
      "the small font is selected before the column stop")
  end
  check(Prize.NAME_SMALL[Prize.LIST_COIN_PURCHASE] == true,
    "the coin counter name column uses the small font")
  check(Prize.NAME_SMALL[Prize.LIST_TM_PRIZES] == nil,
    "the TM prize name column uses the normal font")
end

print("[test] 5. Window size and position are pret's")
if not menu then
  print("[skip] no pret checkout at " .. PRET_MENU)
else
  local heights = {}
  local body = menu:match("static u8 GetMCWindowHeight%(u8 count%)%s*{(.-)\n}")
  check(body ~= nil, "pret declares GetMCWindowHeight")
  if body then
    for c, h in body:gmatch("case (%d+):%s*return (%d+);") do
      heights[tonumber(c)] = tonumber(h)
    end
    for c, h in pairs(heights) do
      eq(Prize.WINDOW_HEIGHT[c], h, "window height for " .. c .. " rows")
    end
  end

  local rows = Prize.buildRows(Prize.LIST_TM_PRIZES, INVENTED_SIX)
  local widest = 0
  for _, row in ipairs(rows) do
    local w = Prize.rowWidth(row)
    if w > widest then widest = w end
  end
  -- pokefirered/src/script_menu.c:736
  local expectWidth = math.floor((widest + 9) / 8) + 1
  local g = Prize.layout(Prize.LIST_TM_PRIZES, rows, 11, 0)
  eq(g.width, expectWidth, "the window is as wide as pret makes it")
  eq(g.height, Prize.WINDOW_HEIGHT[6], "six rows give pret's height")
  -- pokefirered/src/script_menu.c:1195
  eq(g.tileX, g.left + 1, "the window is one tile right of the script operand")
  eq(g.tileY, 1, "the window is one tile below the script operand")

  local wide = Prize.layout(Prize.LIST_TM_PRIZES, rows, 26, 0)
  check(wide.left + wide.width <= 28, "a window that would run off screen is pulled left")
  eq(wide.left, 28 - wide.width, "pret's clamp is 28 tiles")
end

print("[test] 6. Only a list of more than three rows wraps around")
if not menu then
  print("[skip] no pret checkout at " .. PRET_MENU)
else
  local at = menu:find("static void CreateMCMenuInputHandlerTask(u8 ignoreBpress, u8 count, u8 windowId, u8 mcId)\n{", 1, true)
  local body = at and menu:sub(at, menu:find("\n}", at, true))
  check(body ~= nil and body:find("if (count > 3)", 1, true) ~= nil
    and body:find("tWrapAround = TRUE", 1, true) ~= nil,
    "pret wraps only above three rows")
  check(Prize.wrapsAround(6), "the six row prize lists wrap")
  check(not Prize.wrapsAround(3), "the three row coin counter does not wrap")

  Prize.show({ listId = Prize.LIST_COIN_PURCHASE, left = 13, top = 0,
    labels = { "1,111 COINS \194\1652,222", "3,333 COINS \194\1654,444", "LAST ROW" } })
  eq(Prize.cursor, 1, "the coin counter opens on the first row")
  Prize.move(-1)
  eq(Prize.cursor, 1, "up on the first row of a short list does nothing")
  Prize.move(1)
  Prize.move(1)
  eq(Prize.cursor, 3, "the cursor walks down")
  Prize.move(1)
  eq(Prize.cursor, 3, "down on the last row of a short list does nothing")
  Prize.reset()

  Prize.show({ listId = Prize.LIST_TM_PRIZES, left = 11, top = 0, labels = INVENTED_SIX })
  Prize.move(-1)
  eq(Prize.cursor, 6, "a six row list wraps to the bottom")
  Prize.move(1)
  eq(Prize.cursor, 1, "and back to the top")
  Prize.reset()
end

print("[test] 7. The counter reports pret's selection and pret's cancel value")
do
  local picked
  Prize.show({ listId = Prize.LIST_POKEMON_PRIZES, left = 11, top = 0,
    labels = INVENTED_SIX,
    onChoose = function(sel) picked = sel end })
  check(Prize.isOpen(), "the counter is open")
  Prize.move(1)
  Prize.move(1)
  Prize.confirm()
  eq(picked, 2, "A reports the zero based row")
  check(not Prize.isOpen(), "the counter closed")

  picked = nil
  Prize.show({ listId = Prize.LIST_POKEMON_PRIZES, left = 11, top = 0,
    labels = INVENTED_TWO,
    onChoose = function(sel) picked = sel end })
  Prize.cancel()
  eq(picked, Prize.SCR_MENU_CANCEL, "B reports SCR_MENU_CANCEL")
  eq(Prize.SCR_MENU_CANCEL, 127, "SCR_MENU_CANCEL is 127")

  picked = nil
  Prize.show({ listId = Prize.LIST_POKEMON_PRIZES, left = 11, top = 0,
    labels = INVENTED_TWO, ignoreBPress = true,
    onChoose = function(sel) picked = sel end })
  Prize.cancel()
  eq(picked, nil, "B is ignored when the script asks for it")
  check(Prize.isOpen(), "the counter stays open")
  Prize.reset()
end

print("[test] 8. The prize list blocks the script through the multichoice opcode")
do
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local VAR_RESULT = 0x800D

  local store = Flags.newStore()
  local vm = Vm.new({
    store = store,
    scripts = {
      t = {
        { op = "multichoice", [1] = 11, [2] = 0, [3] = Prize.LIST_TM_PRIZES, [4] = 0 },
        { op = "copyvar", [1] = 0x4002, [2] = VAR_RESULT },
        { op = "setvar", [1] = 0x4001, [2] = 9 },
        { op = "end" },
      },
    },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  check(Prize.isOpen(), "the TM prize list opened the prize counter")
  eq(vm.ctx.status, "waiting", "the script is blocked on the list")
  eq(Flags.getVar(store, vm.ctx, 0x4001), 0, "the script has not run past the list")
  vm:tick()
  check(Prize.isOpen(), "the script stays blocked while the list is open")
  Prize.move(1)
  Prize.confirm()
  vm:tick()
  eq(Flags.getVar(store, vm.ctx, 0x4002), 1, "the chosen row landed in VAR_RESULT")
  eq(Flags.getVar(store, vm.ctx, 0x4001), 9, "the script resumed")
end

print("[test] 9. A purchase debits coins, and a short purse and a full bag refuse")
do
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local Runtime = require("src.core.game3.runtime")
  local ItemsData = require("src.core.game3.items_data")
  local VAR_RESULT = 0x800D
  local VAR_TEMP_1, VAR_TEMP_2, VAR_TEMP_3 = 0x4001, 0x4002, 0x4003
  -- pokefirered/include/constants/items.h:205
  local ITEM_SMOKE_BALL = 194
  local SMOKE_BALL_PRICE = 800

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:312
  local prizeScript = {
    TryGivePrize = {
      { op = "checkcoins", [1] = VAR_RESULT },
      { op = "compare_var_to_var", [1] = VAR_RESULT, [2] = VAR_TEMP_2 },
      { op = "goto_if", [1] = 0, [2] = "NotEnoughCoins" },
      { op = "checkitemspace", [1] = VAR_TEMP_1, [2] = 1 },
      { op = "compare_var_to_value", [1] = VAR_RESULT, [2] = 0 },
      { op = "goto_if", [1] = 1, [2] = "BagFull" },
      { op = "removecoins", [1] = VAR_TEMP_2 },
      { op = "additem", [1] = VAR_TEMP_1, [2] = 1 },
      { op = "setvar", [1] = VAR_TEMP_3, [2] = 1 },
      { op = "end" },
    },
    NotEnoughCoins = { { op = "setvar", [1] = VAR_TEMP_3, [2] = 2 }, { op = "end" } },
    -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:324
    BagFull = { { op = "setvar", [1] = VAR_TEMP_3, [2] = 3 }, { op = "end" } },
  }

  local prevSession = Runtime.session
  local function buy(session, item, price)
    Runtime.session = session
    local store = Flags.newStore()
    store.vars[VAR_TEMP_1] = item
    store.vars[VAR_TEMP_2] = price
    local vm = Vm.new({ store = store, scripts = prizeScript, adapters = Adapters.host(nil, nil, nil) })
    vm:start("TryGivePrize")
    for _ = 1, 12 do vm:tick() end
    return Flags.getVar(store, vm.ctx, VAR_TEMP_3)
  end

  local rich = { coins = SMOKE_BALL_PRICE, bag = Bag.new() }
  eq(buy(rich, ITEM_SMOKE_BALL, SMOKE_BALL_PRICE), 1, "the purchase runs to the end of the script")
  eq(Bag.Coins.get(rich), 0, "removecoins took exactly the price")
  eq(Bag.get(rich.bag, ITEM_SMOKE_BALL), 1, "the prize landed in the bag")

  local short = { coins = SMOKE_BALL_PRICE - 1, bag = Bag.new() }
  eq(buy(short, ITEM_SMOKE_BALL, SMOKE_BALL_PRICE), 2, "one coin short takes the NotEnoughCoins branch")
  eq(Bag.Coins.get(short), SMOKE_BALL_PRICE - 1, "a short purse loses no coins")
  eq(Bag.get(short.bag, ITEM_SMOKE_BALL), 0, "a short purse gets no prize")

  -- pokefirered/src/item.c:195 CheckBagHasSpace fails when every slot of the pocket is taken
  local full = { coins = SMOKE_BALL_PRICE, bag = Bag.new() }
  local id, added = 1, 0
  while added < (ItemsData.CAPACITY.ITEMS or 42) do
    if id ~= ITEM_SMOKE_BALL and ItemsData.pocketOf(id) == "ITEMS" then
      if Bag.add(full.bag, id, 1) then added = added + 1 end
    end
    id = id + 1
    if id > 400 then break end
  end
  eq(added, ItemsData.CAPACITY.ITEMS, "the ITEMS pocket is filled to pret's capacity")
  check(not Bag.canAdd(full.bag, ITEM_SMOKE_BALL, 1), "checkitemspace fails on a full pocket")
  eq(buy(full, ITEM_SMOKE_BALL, SMOKE_BALL_PRICE), 3, "a full bag takes the BagFull branch")
  eq(Bag.Coins.get(full), SMOKE_BALL_PRICE, "a full bag loses no coins")
  eq(Bag.get(full.bag, ITEM_SMOKE_BALL), 0, "a full bag gets no prize")
  Runtime.session = prevSession
end

print("[test] 10. Every prize price in the list matches the price the script takes")
if not (strings and menu and prizeRoom) then
  print("[skip] no pret checkout at " .. PRET_PRIZE_ROOM)
else
  local scriptPrices = {}
  for label, price in prizeRoom:gmatch("EventScript_(%w+)::%s*\n%s*%.ifdef FIRERED\n%s*setvar VAR_TEMP_1, [%w_]+\n%s*setvar VAR_TEMP_2, (%d+)") do
    scriptPrices[#scriptPrices + 1] = tonumber(price)
  end
  for label, price in prizeRoom:gmatch("EventScript_(%w+)::%s*\n%s*setvar VAR_TEMP_1, [%w_]+\n%s*setvar VAR_TEMP_2, (%d+)") do
    scriptPrices[#scriptPrices + 1] = tonumber(price)
  end
  local seen = {}
  for _, p in ipairs(scriptPrices) do seen[p] = true end
  check(next(seen) ~= nil, "the prize room script sets prices")

  for _, listId in ipairs({ Prize.LIST_POKEMON_PRIZES, Prize.LIST_TM_PRIZES, Prize.LIST_BATTLE_ITEM_PRIZES }) do
    local syms = listSymbols(listId)
    if syms then
      local labels = {}
      for i, sym in ipairs(syms) do labels[i] = flatten(stringLiteral(sym) or "") end
      local rows = Prize.buildRows(listId, labels)
      for i, row in ipairs(rows) do
        if row.amount then
          local digits = row.amount:gsub("[^%d]", "")
          check(seen[tonumber(digits)] == true,
            string.format("list %d row %d price %s is a price the script takes", listId, i, digits))
        end
      end
    end
  end
end

print("[test] 11. CheckAddCoins guards the coin case against overflow")
do
  eq(Corner.SPECIAL.CheckAddCoins, 0x15E, "CheckAddCoins is special 0x15E")
  eq(Corner.MAX_COINS, 9999, "MAX_COINS is 9999")
  eq(Corner.checkAddCoins(0, 10), 1, "an empty case takes ten coins")
  eq(Corner.checkAddCoins(9989, 10), 1, "a case that ends exactly full takes them")
  eq(Corner.checkAddCoins(9990, 10), 0, "one coin of overflow is refused")
  eq(Corner.checkAddCoins(9999, 1), 0, "a full case takes nothing")
  eq(Corner.checkAddCoins(9999, 0), 1, "adding nothing is always allowed")
end

print("[test] 12. CheckAddCoins is dispatched, and it reads pret's two vars")
do
  local Natives = require("src.core.game3.scripting.natives")
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local VAR_RESULT = 0x800D
  local VAR_0x8006 = 0x8006

  check(Natives.MODULES["natives_corner"] ~= nil, "natives_corner is loaded by the dispatcher")

  local store = Flags.newStore()
  local vm = Vm.new({
    store = store,
    scripts = {
      -- pokefirered/data/scripts/obtain_item.inc:197
      t = {
        { op = "setvar", [1] = VAR_RESULT, [2] = 9990 },
        { op = "setvar", [1] = VAR_0x8006, [2] = 10 },
        { op = "specialvar", [1] = VAR_RESULT, [2] = Corner.SPECIAL.CheckAddCoins },
        { op = "copyvar", [1] = 0x4003, [2] = VAR_RESULT },
        { op = "end" },
      },
      u = {
        { op = "setvar", [1] = VAR_RESULT, [2] = 40 },
        { op = "setvar", [1] = VAR_0x8006, [2] = 10 },
        { op = "specialvar", [1] = VAR_RESULT, [2] = Corner.SPECIAL.CheckAddCoins },
        { op = "copyvar", [1] = 0x4004, [2] = VAR_RESULT },
        { op = "end" },
      },
    },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  for _ = 1, 8 do vm:tick() end
  eq(Flags.getVar(store, vm.ctx, 0x4003), 0, "a case that would overflow answers FALSE")
  vm:start("u")
  for _ = 1, 8 do vm:tick() end
  eq(Flags.getVar(store, vm.ctx, 0x4004), 1, "a case with room answers TRUE")
end

print("[test] 13. The special id comes out of pret's def_special order")
if not slurp("../pokefirered/data/specials.inc") then
  print("[skip] no pret checkout at ../pokefirered/data/specials.inc")
else
  local src = slurp("../pokefirered/data/specials.inc")
  local index, found = 0, nil
  for line in src:gmatch("[^\n]+") do
    local name = line:match("^%s+def_special%s+([%w_]+)")
    if name then
      if name == "CheckAddCoins" then found = index end
      index = index + 1
    end
  end
  eq(found, Corner.SPECIAL.CheckAddCoins, "CheckAddCoins is at pret's def_special index")
  local body = slurp(PRET_SPECIALS)
  if body then
    local fn = body:match("bool8 CheckAddCoins%(void%)%s*{(.-)\n}")
    check(fn ~= nil and fn:find("gSpecialVar_Result + gSpecialVar_0x8006 > 9999", 1, true) ~= nil,
      "pret compares VAR_RESULT plus VAR_0x8006 against 9999")
  end
end

print("[test] 14. The TM clerk buffers a move name, not a move number")
do
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local Cache = require("tests.game3_cache")
  local root = Cache.mount("pokemon/move_names.lua")
  if not root then
    print("[skip] no extracted cache for move names: " .. tostring(Cache.reason))
  else
    local Pokemon = require("src.core.game3.pokemon")
    Pokemon.install(nil)
    -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:267
    local MOVE_ICE_BEAM = 58
    local expect = Pokemon.moveName(MOVE_ICE_BEAM)
    check(expect ~= nil and expect ~= tostring(MOVE_ICE_BEAM), "the cache knows move 58 as " .. tostring(expect))

    local store = Flags.newStore()
    local vm = Vm.new({
      store = store,
      scripts = {
        t = {
          { op = "buffermovename", [1] = 1, [2] = MOVE_ICE_BEAM },
          { op = "end" },
        },
      },
      adapters = Adapters.host(nil, nil, nil),
    })
    vm:start("t")
    local buffered = vm.ctx.stringVars and vm.ctx.stringVars[2]
    eq(buffered, expect, "STR_VAR_2 holds the move name")
    check(buffered ~= tostring(MOVE_ICE_BEAM), "STR_VAR_2 is not the raw move id")
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

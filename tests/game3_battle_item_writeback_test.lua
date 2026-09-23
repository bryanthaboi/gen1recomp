#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then print("[skip] game3_battle_item_writeback_test: " .. tostring(Cache.reason)) os.exit(0) end
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")
local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Party = require("src.core.game3.party")
local Prize = require("src.core.game3.battle.prize")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local function fresh(species, level)
  for i = #session.party, 1, -1 do session.party[i] = nil end
  Party.giveMon(session, species, level)
  return session.party[1]
end

local function step_until(pred, limit)
  Battle._auto = true
  Battle._headless = true
  for _ = 1, limit or 400 do
    if not Battle.isActive() or pred() then return end
    Battle.update(0, nil)
  end
end

print("[test] 1. consumed Oran Berry stays consumed after the battle")
do
  local mon = fresh(39, 50)
  mon.item, mon.heldItem = 139, 139
  local healed = {}
  for round = 1, 2 do
    mon.hp = math.floor(mon.maxHp / 2)
    local start = mon.hp
    local ok = BattleBridge.start(nil, game, { species = 129, level = 100, moves = { 150 }, pp = { 40 }, item = 0 },
      { wild = true, headless = true, fade = false })
    check(ok, "round " .. round .. " battle starts")
    step_until(function() return (Battle._st.player.mon.hp or 0) > start end, 20)
    healed[round] = (Battle._st.player.mon.hp or 0) > start
    BattleBridge.finishPending("win")
    if round == 1 then
      check(mon.item == nil and mon.heldItem == nil, "session mon no longer holds the berry")
    end
  end
  check(healed[1] == true, "berry heals in the first battle")
  check(healed[2] == false, "berry does not heal again in the second battle")
end

print("[test] 2. Thief keeps the stolen item")
do
  local mon = fresh(39, 50)
  mon.item, mon.heldItem = nil, nil
  mon.moves = { 168 }
  mon.pp = { 10 }
  local ok = BattleBridge.start(nil, game, { species = 129, level = 100, moves = { 150 }, pp = { 40 }, item = 13 },
    { wild = true, headless = true, fade = false })
  check(ok, "battle starts")
  step_until(function() return (tonumber(Battle._st.player.item) or 0) ~= 0 end, 400)
  check(tonumber(Battle._st.player.item) == 13, "Thief stole the foe's item in battle")
  BattleBridge.finishPending("win")
  check(mon.item == 13 and mon.heldItem == 13, "stolen item is on the session mon after the battle")
end

print("[test] 3. Pickup item survives writeback")
do
  local mon = fresh(52, 60)
  mon.item, mon.heldItem = nil, nil
  mon.abilityId = 53
  mon.moves = { 38 }
  mon.pp = { 15 }
  local realPickup = Prize.pickup
  Prize.pickup = function(party) return realPickup(party, function() return 0 end) end
  local ok = BattleBridge.start(nil, game, { species = 129, level = 2, moves = { 150 }, pp = { 40 }, item = 0 },
    { wild = true, headless = true, fade = false })
  check(ok, "battle starts")
  local res = Battle.runToEnd()
  Prize.pickup = realPickup
  if Battle.isActive() then BattleBridge.finishPending("win") end
  check(res == "win", "player wins")
  check(mon.item == 139 and mon.heldItem == 139, "Pickup item is on the session mon after the battle")
end

print("[test] 4. summary info page names the held item")
do
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local ItemsData = require("src.core.game3.items_data")
  local RomText = require("src.core.game3.rom_text")
  check(SummaryMenu.heldItemText({ item = 139 }) == ItemsData.displayName(139), "item 139 shows its name")
  check(SummaryMenu.heldItemText({ item = 139 }) ~= "139", "item name is not the raw id")
  check(SummaryMenu.heldItemText({}) == RomText.plain("gText_PokeSum_Item_None"), "no item shows NONE")
  check(SummaryMenu.heldItemText({ item = 0 }) == RomText.plain("gText_PokeSum_Item_None"), "item 0 shows NONE")
end

if failed > 0 then
  print(string.format("[result] %d failure(s)", failed))
  os.exit(1)
end
print("[result] all game3_battle_item_writeback tests passed")
os.exit(0)

local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = GameVersion.get()
local GEN = GameVersion.generation(VERSION)
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/api3_acceptance_" .. tostring(VERSION))
local NAME = "ZEBRA"

local failures = 0
local function check(ok, label, detail)
  ok = ok and true or false
  print((ok and "PASS " or "FAIL ") .. label .. ((not ok and detail ~= nil) and (" :: " .. tostring(detail)) or ""))
  if not ok then failures = failures + 1 end
  return ok
end

local function shot(game, file)
  return check(U.still(game, DIR .. "/" .. file), "shot " .. file)
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " api3_acceptance " .. tostring(VERSION) .. " failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  while true do U.wait(10) end
end

local function party(game)
  if GEN == 3 then return require("src.core.game3.runtime").getSession().party end
  return game.save.party
end

local function stat(mon, key)
  if GEN == 3 then return mon[key] end
  return mon.stats and mon.stats[key]
end

local function ownErrors(loader)
  local list = {}
  for _, e in ipairs(loader.errors) do
    local text = tostring(e)
    if text:find("api3acc", 1, true) or text:find("legacyacc", 1, true) then list[#list + 1] = text end
  end
  return list
end

local function bootToWorld(game)
  if GEN == 1 then
    check(U.newGame(game), "new game reaches the overworld")
    game.save.player.name = NAME
  elseif GEN == 2 then
    for _ = 1, 900 do
      if game.world and game.world.map then break end
      U.wait(1)
    end
    check(game.world and game.world.map ~= nil, "gen2 world booted")
    U.wait(30)
    game.save.player.name = NAME
  else
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    check(game.boot ~= nil, "gen3 boot reached")
    local ok, err = pcall(function()
      game:_handleBootAction({ action = "new_game", name = NAME, gender = 0 })
    end)
    check(ok, "gen3 new game", err)
    U.wait(60)
    local F = require("tests.drivers.em_fa_util")
    F.settle(game, 600)
    local frlg = VERSION == "firered" or VERSION == "leafgreen"
    local MapIds = require("src.core.game3.map_ids")
    local mapId = MapIds.forConst(frlg and "MAP_PALLET_TOWN" or "MAP_ROUTE101")
    local x, y = 8, 8
    if not frlg then x, y = 10, 12 end
    check(F.goTo(game, mapId, x, y, "down"), "gen3 placed on " .. mapId)
  end
  U.wait(20)
end

local out
local function mashUntil(game, done, limit)
  for i = 1, limit or 600 do
    if done() then return true end
    if os.getenv("ACC_DEBUG") and i % 100 == 1 then
      local ow = game.overworld
      local names = {}
      for _, st in ipairs(game.stack.states) do names[#names + 1] = tostring(st.screenId or st.text or st.ramp and "ramp" or "?") end
      print("[probe]", i, #game.stack.states, table.concat(names, ","), tostring(out and out.script and out.script.done), tostring(out and out.ended and out.ended.completed), tostring(#game.save.party))
    end
    U.tap(game, "a")
    U.wait(8)
  end
  return done()
end

local function describeTop(game)
  if GEN == 3 then
    local Message = require("src.ui.game3.message")
    local Space = require("src.core.game3.scripting.space")
    return ("msgOpen=%s vmRunning=%s"):format(tostring(Message.isOpen()), tostring(Space.vm and Space.vm:isRunning()))
  end
  local top = game.stack:top()
  local runner = top and top.runner
  return ("depth=%d top=%s isOverworld=%s runnerKeys=%s"):format(#game.stack.states, tostring(top and top.screenId),
    tostring(top and top.isOverworld), tostring(runner and runner.running))
end

local function unwindTo(game, base)
  for _ = 1, 12 do
    if game.stack:top() == base then return end
    game.stack:pop()
  end
end

local function routeUpdateThroughHooks(game)
  local ModRuntime = require("src.mods.Runtime")
  local raw = game.update
  local function vanilla(g, dt) raw(g, dt) end
  game.update = function(self, dt)
    return ModRuntime.call("core.update", vanilla, self, dt)
  end
end

return function(game)
  bootToWorld(game)
  routeUpdateThroughHooks(game)

  local loader = game.mods
  check(loader ~= nil, "game has a mod loader")
  out = loader and loader.exports and loader.exports.api3acc
  local legacy = loader and loader.exports and loader.exports.legacyacc
  if not (out and legacy) then
    check(false, "fixture mods installed in the identity", "exports api3acc=" .. tostring(out) .. " legacyacc=" .. tostring(legacy))
    for _, e in ipairs(loader and loader.errors or {}) do print("[driver] loader error: " .. tostring(e)) end
    return finish()
  end

  local loadedIds = {}
  for _, m in ipairs(loader.loaded) do loadedIds[m.manifest.id] = m end
  check(loadedIds.api3acc ~= nil and loadedIds.legacyacc ~= nil, "both fixture mods are in loader.loaded")
  local ours = ownErrors(loader)
  check(#ours == 0, "Loader.errors has nothing for the fixture mods", table.concat(ours, " | "))
  for _, e in ipairs(loader.errors) do print("[driver] loader error (all): " .. tostring(e)) end
  check(#out.errors == 0, "api3 mod registrations all accepted", table.concat(out.errors, " | "))
  check(out.patchedAttack == 190, "mod:content.pokemon:get sees the patched attack", out.patchedAttack)

  local want = {
    phone = GEN == 2, radio = GEN == 2, shiny = GEN >= 2, nickname = true, style = GEN == 1,
    speed = true, level = true, stepped = true, pokemon = true,
  }
  for key, expected in pairs(want) do
    check(out.supports[key] == expected, "mod:supports " .. key .. " == " .. tostring(expected) .. " on " .. VERSION,
      out.supports[key])
  end
  check(out.supports.phone == (VERSION == "gold" or VERSION == "silver" or VERSION == "crystal"),
    "phone.call_received is true only on Gold, Silver, Crystal")

  local before = out.counts.steps
  for _, dir in ipairs({ "down", "left", "right", "up", "down", "right", "left", "up" }) do
    U.hold(game, dir, 20)
    U.wait(4)
    if out.counts.steps >= before + 2 then break end
  end
  check(out.counts.steps > before, "world.stepped fired after walking", out.counts.steps - before)
  check(legacy.steps > 0, "legacy api 2 mod also saw world.stepped", legacy.steps)
  local override = game.speedOverride
  game.speedOverride = nil
  game:logicSpeed()
  game.speedOverride = override
  check(out.counts.speed > 0, "core.logic_speed hook ran", out.counts.speed)
  check(legacy.speed > 0, "legacy api 2 mod core.logic_speed hook ran", legacy.speed)

  local base = GEN ~= 3 and game.stack:top() or nil
  local count = #party(game)
  local function runScript(giftText)
    local ok, reason
    for _ = 1, 200 do
      ok, reason = out.runScript(giftText)
      if ok then break end
      U.wait(10)
    end
    check(ok == true, "queueScript accepts the portable rows (giftText=" .. tostring(giftText) .. ")", reason)
    if not ok then return false end
    U.wait(240)
    check(out.script.done == nil, "script is blocked on the text box")
    shot(game, giftText and "01_script_text_player_name.png" or "01b_script_text_player_name_no_gift_text.png")
    local giftShot = not giftText
    local finished = mashUntil(game, function()
      if not giftShot and #party(game) == count + 1 and not out.script.done then
        giftShot = true
        U.wait(90)
        shot(game, "01c_gift_received_text.png")
      end
      return out.script.done
    end, 900)
    local good = finished and out.script.ok == true
    check(good, "script ran text, fade out, fade in, gift to completion (giftText=" .. tostring(giftText) .. ")",
      tostring(out.script.reason) .. " | " .. describeTop(game))
    U.wait(30)
    if GEN ~= 3 then unwindTo(game, base) end
    return good
  end
  if not runScript(true) then
    if GEN ~= 3 then unwindTo(game, base) end
    runScript(false)
  end
  check(#party(game) == count + 1, "give_pokemon added a party member", #party(game) - count)

  local mon = party(game)[#party(game)]
  check(mon ~= nil, "gifted mon is last in the party")
  local attack = mon and stat(mon, "attack")
  check(type(attack) == "number" and attack >= 120, "gifted PIDGEY attack reflects the species patch", attack)

  local level0 = out.counts.level
  if GEN == 1 then
    local Screens = require("src.ui.Screens")
    Screens.push(game, "SummaryMenu", mon)
    U.wait(30)
    shot(game, "02_summary_patched_attack.png")
    unwindTo(game, base)
  elseif GEN == 2 then
    local SummaryMenu = require("src.ui.gen2.SummaryMenu")
    for page, label in ipairs({ "pink", "green", "blue" }) do
      game.stack:push(SummaryMenu.new(game, { party = game.save.party, index = #game.save.party, save = game.save,
        page = SummaryMenu[label:upper() .. "_PAGE"] }))
      U.wait(30)
      shot(game, ("02_summary_patched_attack_%d_%s.png"):format(page, label))
      unwindTo(game, base)
    end
  else
    local rse = VERSION == "ruby" or VERSION == "sapphire"
    local SummaryMenu = require(rse and "src.ui.game3.rs.summary_menu" or "src.ui.game3.summary_menu")
    local session = require("src.core.game3.runtime").getSession()
    SummaryMenu.openMenu(party(game), #party(game), { playerState = session })
    local function busy()
      return SummaryMenu._pageTask ~= nil or (SummaryMenu._slide and SummaryMenu._slide.active) or false
    end
    U.wait(60)
    for _ = 1, 120 do
      if not busy() then break end
      U.wait(1)
    end
    U.tap(game, "right")
    for _ = 1, 240 do
      U.wait(1)
      if not busy() and SummaryMenu._page == 1 then break end
    end
    check(SummaryMenu._page == 1, "summary is on the skills page", SummaryMenu._page)
    U.wait(20)
    shot(game, "02_summary_patched_attack.png")
    for _ = 1, 6 do
      U.tap(game, "b")
      U.wait(20)
    end
  end
  check(out.counts.level > level0, "pokemon.level_visible hook ran while the summary drew", out.counts.level - level0)

  local used0 = out.counts.used
  local itemOk, itemWhy
  if GEN == 1 then
    local Bag = require("src.inventory.Bag")
    Bag.add(game.save, "ACC_TONIC", 2, game.data)
    check((game.save.inventory.ACC_TONIC or 0) == 2, "mod item is in the bag")
    local Screens = require("src.ui.Screens")
    Screens.push(game, "BagMenu", {})
    U.wait(20)
    local list = game.stack:top()
    for i, row in ipairs(list.items or {}) do
      if row.value == "ACC_TONIC" then list.index = i end
    end
    shot(game, "03_bag_mod_item.png")
    itemOk = mashUntil(game, function() return out.counts.used > used0 end, 60)
    U.wait(60)
    for _ = 1, 8 do
      if game.stack:top() == base then break end
      U.tap(game, "b")
      U.wait(15)
    end
    unwindTo(game, base)
    itemWhy = game.save.inventory.ACC_TONIC
    check(itemOk and (game.save.inventory.ACC_TONIC or 0) == 1, "bag use ran the mod effect and consumed one", itemWhy)
  elseif GEN == 2 then
    game.save.inventory = game.save.inventory or {}
    game.save.inventory.ACC_TONIC = 2
    mon.hp = 1
    game:useFieldItem("ACC_TONIC")
    U.wait(20)
    itemOk = mashUntil(game, function() return out.counts.used > used0 end, 60)
    U.wait(60)
    for _ = 1, 8 do
      if game.stack:top() == base then break end
      U.tap(game, "b")
      U.wait(15)
    end
    unwindTo(game, base)
    check(itemOk and (game.save.inventory.ACC_TONIC or 0) == 1, "bag item use ran the mod effect and consumed one",
      game.save.inventory.ACC_TONIC)
  else
    local Bag = require("src.core.game3.bag")
    local ItemUse = require("src.core.game3.item_use")
    local session = require("src.core.game3.runtime").getSession()
    local index = out.itemIndex()
    check(type(index) == "number", "mod item has a native item index", index)
    Bag.add(session.bag, index, 2)
    check(Bag.get(session.bag, index) == 2, "mod item is in the bag")
    local ok2, kind, text = ItemUse.useField(session, session.bag, index, nil)
    check(ok2 and kind == "mod" and text == "ACC TONIC worked!", "ItemUse.useField ran the mod effect", tostring(kind) .. "/" .. tostring(text))
    check(out.counts.used > used0 and Bag.get(session.bag, index) == 1, "mod item consumed one")
  end

  local pushed0, popped0, enters0, exits0 = out.counts.pushed, out.counts.popped, out.counts.enters, out.counts.exits
  local depth = function()
    if GEN == 3 then return require("src.ui.game3.stack").depth() end
    return #game.stack.states
  end
  local depth0 = depth()
  local inst = out.openScreen(game)
  U.wait(20)
  check(inst ~= nil and out.counts.enters == enters0 + 1, "mod.ui.push entered the registered screen")
  check(depth() == depth0 + 1, "screen is on the stack", depth() - depth0)
  shot(game, "04_mod_screen.png")
  U.tap(game, "b")
  U.wait(20)
  check(out.counts.exits == exits0 + 1 and depth() == depth0, "B pops the mod screen and runs exit")
  check(out.counts.pushed > pushed0 and out.counts.popped > popped0, "screen.pushed and screen.popped were raised",
    (out.counts.pushed - pushed0) .. "/" .. (out.counts.popped - popped0))

  ours = ownErrors(loader)
  check(#ours == 0, "Loader.errors still has nothing for the fixture mods at the end", table.concat(ours, " | "))
  return finish()
end

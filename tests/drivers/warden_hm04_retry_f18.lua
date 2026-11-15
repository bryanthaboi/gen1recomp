-- scripts/WardensHouse.asm:12-57
--   tools/run_driver.sh red <identity> tests/drivers/warden_hm04_retry_f18.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Bag = require("src.inventory.Bag")
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local seen = {}
  local function watch()
    local top = game.stack:top()
    if top and top.pages then
      local lines = {}
      for _, page in ipairs(top.pages) do
        for _, l in ipairs(page) do lines[#lines + 1] = l end
      end
      seen[#seen + 1] = table.concat(lines, " ")
    end
  end
  local function saw(key)
    for _, s in ipairs(seen) do
      if s:find(key, 1, true) then return true end
    end
    return false
  end
  local function settle()
    local ow = game.overworld
    for _ = 1, 400 do
      watch()
      U.wait(2)
      if game.stack:top() == ow and not ow.runner:isRunning() and #seen > 0 then
        break
      end
      U.tap(game, "a")
    end
    U.wait(10)
  end
  local function talk()
    seen = {}
    U.teleport(game, "WARDENS_HOUSE", 2, 4, "up")
    U.wait(10)
    U.tap(game, "a")
    settle()
  end
  local function runRows(rows)
    seen = {}
    game.overworld.runner:run(rows)
    settle()
  end
  local function key(label)
    local s = game.data.text[label]
    s = s:gsub("{[^}]*}", ""):gsub("[\n\011\012]", " ")
    return (s:match("^%s*(%S+%s+%S+)") or s)
  end
  local fillers = { "POTION", "ANTIDOTE", "BURN_HEAL", "ICE_HEAL", "AWAKENING",
    "PARLYZ_HEAL", "FULL_RESTORE", "MAX_POTION", "HYPER_POTION", "SUPER_POTION",
    "FULL_HEAL", "REVIVE", "MAX_REVIVE", "ESCAPE_ROPE", "REPEL", "SUPER_REPEL",
    "MAX_REPEL", "X_ATTACK", "X_DEFEND", "X_SPEED" }
  local flags = game.save.flags
  flags.EVENT_GOT_HM04 = nil
  flags.EVENT_GAVE_GOLD_TEETH = true
  game.save.inventory = {}
  game.save.itemOrder = nil
  for _, id in ipairs(fillers) do Bag.add(game.save, id, 1, game.data) end
  check("bag refuses a 21st stack", not Bag.add(game.save, "NUGGET", 1, game.data))

  talk()
  check("full bag retry: Thanks text", saw(key("_WardensHouseWardenThanksText")))
  check("full bag retry: HM04 no-room text", saw(key("_WardensHouseWardenHM04NoRoomText")))
  check("full bag retry: no gibberish", not saw(key("_WardensHouseWardenGibberish1Text")))
  check("full bag retry: EVENT_GOT_HM04 still clear", not flags.EVENT_GOT_HM04)
  check("full bag retry: no HM04 in the bag", not game.save.inventory.HM_STRENGTH)

  flags.EVENT_GOT_HM04 = nil
  runRows({ { "give_item", "NUGGET", 1, false, "_WardensHouseWardenHM04NoRoomText" },
    { "set_flag", "EVENT_GOT_HM04" } })
  check("give_item full, label: that label prints", saw(key("_WardensHouseWardenHM04NoRoomText")))
  check("give_item full, label: script halts", not flags.EVENT_GOT_HM04)
  check("give_item full, label: no NUGGET", not game.save.inventory.NUGGET)

  runRows({ { "give_item", "NUGGET", 1, false }, { "set_flag", "EVENT_GOT_HM04" } })
  check("give_item full, nil: _NoMoreRoomForItemText prints", saw(key("_NoMoreRoomForItemText")))
  check("give_item full, nil: script halts", not flags.EVENT_GOT_HM04)

  runRows({ { "give_item", "NUGGET", 1, false, false }, { "set_flag", "EVENT_GOT_HM04" },
    { "show_text", "_WardensHouseWardenThanksText" } })
  check("give_item full, false: no no-room text", not saw(key("_NoMoreRoomForItemText")))
  check("give_item full, false: script continues", flags.EVENT_GOT_HM04 == true)
  check("give_item full, false: no NUGGET", not game.save.inventory.NUGGET)
  flags.EVENT_GOT_HM04 = nil

  Bag.remove(game.save, "X_SPEED", 1, game.data)
  talk()
  check("room retry: HM04 received", (game.save.inventory.HM_STRENGTH or 0) == 1)
  check("room retry: EVENT_GOT_HM04 set", flags.EVENT_GOT_HM04 == true)

  talk()
  check("after: HM04 explanation", saw(key("_WardensHouseWardenHM04ExplanationText")))

  flags.EVENT_GOT_HM04 = nil
  flags.EVENT_GAVE_GOLD_TEETH = nil
  game.save.inventory.HM_STRENGTH = nil
  talk()
  check("no teeth, no flag: gibberish", saw(key("_WardensHouseWardenGibberish1Text")))
  check("no teeth, no flag: nothing given", not game.save.inventory.HM_STRENGTH)

  U.log(ok and "PASS warden_hm04_retry_f18" or "FAIL warden_hm04_retry_f18")
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end

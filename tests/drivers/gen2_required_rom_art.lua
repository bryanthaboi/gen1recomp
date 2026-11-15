local U = require("tests.drivers.util")
local Screens = require("src.ui.Screens")

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-required-rom-art"
  local function draws(screen, label)
    local ok, err = pcall(screen.draw, screen)
    return check(ok, label .. " draws from the cache" .. (ok and "" or (": " .. tostring(err))))
  end
  local function pop(screen)
    if game.stack:top() == screen then game.stack:pop() end
  end

  U.wait(60)
  if not check(game.world and game.world.map and game.save and game.stack,
    "gen2 field booted") then
    return love.event.quit(1)
  end
  local Mon = require("src.battle.gen2.Mon")
  local Boxes = require("src.core.gen2.Boxes")

  local credits = Screens.push(game, "Gen2Credits", {})
  U.wait(5)
  credits.scene = 1
  credits.borderFrame = 1
  credits.lyOverride = 10
  credits.shown = { { theEnd = true, x = 6, y = credits.layout().theEndY, width = 8 } }
  draws(credits, "credits banner, border and THE END")
  check(U.still(game, dir .. "/01_credits_banner_border_theend.png"), "credits shot written")
  credits.onDone = nil
  pop(credits)

  local diploma = Screens.push(game, "Gen2Diploma", { playerName = "GOLD" })
  U.wait(5)
  draws(diploma, "diploma page")
  check(U.still(game, dir .. "/02_diploma_page.png"), "diploma shot written")
  pop(diploma)

  local holder = Mon.new(game.data, "SENTRET", 12)
  holder.item = "BERRY"
  holder.nickname = "HOLDER"
  local egg = Mon.new(game.data, "TOGEPI", 5)
  egg.isEgg = true
  egg.nickname = "EGG"
  egg.eggSteps = 1
  local box = Boxes.box(game.save, game.save.currentBox or 1)
  local savedBox = {}
  for i, mon in ipairs(box) do savedBox[i] = mon end
  for i = #box, 1, -1 do box[i] = nil end
  box[1], box[2] = egg, holder

  local pcEgg = Screens.push(game, "Gen2BoxMenu", { save = game.save, mode = "withdraw" })
  U.wait(5)
  pcEgg.index = 1
  draws(pcEgg, "bill's pc egg pic")
  check(U.still(game, dir .. "/03_billspc_egg_pic.png"), "bill's pc egg shot written")
  pcEgg.index = 2
  draws(pcEgg, "bill's pc held item icon")
  check(U.still(game, dir .. "/04_billspc_held_item_icon.png"), "bill's pc held item shot written")
  pop(pcEgg)

  local pcMove = Screens.push(game, "Gen2BoxMenu", { save = game.save, mode = "move" })
  U.wait(5)
  draws(pcMove, "bill's pc move arrows")
  check(U.still(game, dir .. "/05_billspc_move_box_arrows.png"), "bill's pc move shot written")
  pop(pcMove)

  for i = #box, 1, -1 do box[i] = nil end
  for i, mon in ipairs(savedBox) do box[i] = mon end

  local shiny = Mon.new(game.data, "SENTRET", 12)
  shiny.shiny = true
  local summaryParty = { shiny, egg }
  local summary = Screens.push(game, "Gen2SummaryMenu", { party = summaryParty, index = 1 })
  U.wait(20)
  draws(summary, "summary stats tiles")
  check(U.still(game, dir .. "/06_summary_stats_page_tiles.png"), "summary stats shot written")
  pop(summary)
  local eggSummary = Screens.push(game, "Gen2SummaryMenu", { party = summaryParty, index = 2 })
  U.wait(20)
  draws(eggSummary, "summary egg pic")
  check(U.still(game, dir .. "/07_summary_egg_pic.png"), "summary egg shot written")
  pop(eggSummary)

  local hatched = false
  local hatch = Screens.push(game, "Gen2EggHatchAnim", {
    mon = holder, species = "SENTRET", onDone = function() hatched = true end,
  })
  local cracked = false
  for _ = 1, 700 do
    U.wait(1)
    if not cracked and #hatch.sprites > 0 and hatch.sprites[1].kind == "crack" then
      cracked = true
      draws(hatch, "egg hatch crack")
      check(U.still(game, dir .. "/08_egg_hatch_crack_on_shell.png"), "egg hatch crack shot written")
    end
    if hatched or hatch.done then break end
  end
  check(cracked, "egg hatch reached a crack on the shell")
  check(hatched or hatch.done, "egg hatch ran to its end")
  pop(hatch)

  local Anim = require("src.core.gen2.TradeAnim")
  local trade = Screens.push(game, "Gen2TradeAnim", {
    row = { otName = "MIKE", otId = 1234 },
    given = Mon.new(game.data, "DROWZEE", 12), received = Mon.new(game.data, "MACHOP", 12),
    save = game.save, eventTables = game.data.events,
  })
  for index, beat in ipairs({ { "ball_rock", 9 }, { "bulge", 60 }, { "send_pan_b", 20 },
                              { "tube_out", 20 } }) do
    trade.frame = Anim.startOf(beat[1]) + beat[2] - 1
    trade:step()
    draws(trade, "trade " .. beat[1])
    check(U.still(game, ("%s/%02d_trade_%s.png"):format(dir, 10 + index, beat[1])),
      "trade " .. beat[1] .. " shot written")
  end
  trade.onDone = nil
  pop(trade)

  game.world:warpToMapId("GOLDENROD_GAME_CORNER", 5, 5, "down")
  U.wait(30)
  local coins = game.save.player.coins
  game.save.player.coins = 1000
  if check(game.world:gameCornerGame("slots"), "slot machine opens") then
    local slots = game.stack:top()
    U.wait(10)
    draws(slots, "slot machine reels")
    check(U.still(game, dir .. "/09_slots_reels_and_frame.png"), "slots shot written")
    slots.golemAnim = { state = "rolling", x = 60, y = 40, animFrame = 1 }
    slots.chanseyAnim = { state = "walking", x = 20, y = 44, animPose = 1,
      eggVisible = true, eggX = 40, eggY = 50 }
    draws(slots, "slot machine golem and chansey")
    check(U.still(game, dir .. "/10_slots_golem_chansey_actors.png"), "slots actors shot written")
    slots.golemAnim, slots.chanseyAnim = nil, nil
    pop(slots)
  end
  game.save.player.coins = coins

  love.event.quit(failed == 0 and 0 or 1)
end

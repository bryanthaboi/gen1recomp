-- pokefirered/src/pokemon_summary_screen.c:1615
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-24-26-01-followup/shots/game3_summary_pages_s3"

local failures = 0
local function pass(label, ok, detail)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label .. (detail and (" " .. tostring(detail)) or ""))
  end
end

local calls = {}
local function spy(mod, name)
  local real = mod[name]
  mod[name] = function(...)
    calls[#calls + 1] = { name = name, args = { ... } }
    return real(...)
  end
end
local function called(name, pred)
  for _, c in ipairs(calls) do
    if c.name == name and (not pred or pred(c.args)) then return true end
  end
  return false
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local SummaryChrome = require("src.ui.game3.summary_chrome")

  local session = Runtime.getSession()
  if not session then print("FAIL no session") love.event.quit(1) return end
  session.party = {}
  Party.giveMon(session, 25, 20)
  Party.giveMon(session, 1, 20)
  Party.giveMon(session, 4, 5)
  local mon = session.party[1]
  mon.isShiny = true
  mon.status = "PSN"
  mon.pokerus = 0x10
  mon.markings = 5
  mon.moves[4] = 0
  mon.pp[4] = 0
  mon.maxPp[4] = 0
  mon.pp[1] = 4
  mon.pp[2] = 14
  mon.pp[3] = 0
  mon.hp = math.max(1, math.floor((tonumber(mon.maxHp) or 40) / 2))
  local plain = session.party[2]
  plain.hp = plain.maxHp
  plain.status = nil
  session.party[3].isEgg = true
  session.party[3].friendship = 5

  Map.load(nil, game, "FR_PALLET_TOWN", { x = 10, y = 6, facing = "down" })
  Player.cellX, Player.cellY = 10, 6
  U.wait(60)

  for _, n in ipairs({ "drawBg3", "drawProgress", "drawLayer", "drawMarkings", "drawShinyStar",
                       "drawStatusIcon", "drawTypeBadge", "drawMoveSelectionCursor" }) do
    spy(SummaryChrome, n)
  end
  spy(Pokemon, "monFrontPic")
  spy(Pokemon, "monIcon")

  local function frame_calls()
    calls = {}
    for _ = 1, 4000 do
      U.wait(1)
      if called("drawBg3") then
        calls = {}
        break
      end
    end
    for _ = 1, 4000 do
      U.wait(1)
      if called("drawBg3") then return end
    end
  end
  local function shot(name) return U.still(game, DIR .. "/" .. name .. ".png") end
  local function settle()
    for _ = 1, 120 do
      if not SummaryMenu._slide.active then break end
      U.wait(1)
    end
    U.wait(4)
  end
  local function until_step(n)
    for _ = 1, 60 do
      if SummaryMenu._slide.active and SummaryMenu.flipStep() == n then return true end
      U.wait(1)
    end
    return false
  end

  SummaryMenu.openMenu(session.party, 1, {})
  settle()
  frame_calls()
  pass("s3 info shiny bg", called("drawBg3", function(a) return a[1] == "info" and a[2] == true end))
  pass("s3 info shiny star frame", called("drawShinyStar", function(a) return a[1] == 102 and a[2] == 36 end))
  pass("s3 info status TL", called("drawStatusIcon", function(a) return a[1] == 0 and a[2] == 34 end))
  pass("s3 info markings", called("drawMarkings", function(a) return a[1] == 5 and a[2] == 4 and a[3] == 87 end))
  shot("s3_info_shiny_psn_markings")

  U.tap(game, "left") U.wait(4)
  pass("s3 left on INFO does not wrap", SummaryMenu._page == SummaryMenu.PAGE_INFO and not SummaryMenu._slide.active)

  U.tap(game, "right")
  pass("s3 right from INFO starts a slide", SummaryMenu._slide.active and SummaryMenu._page == SummaryMenu.PAGE_SKILLS)
  local waited = 0
  while SummaryMenu._slide.active and SummaryMenu.flipStep() == 0 and waited < 30 do
    U.wait(1) waited = waited + 1
  end
  pass("s3r flip waits the cart's task frames before sliding", waited >= 5, waited)
  until_step(2)
  shot("s3_slide_info_out_to_skills")
  settle()
  shot("s3_skills_right_aligned")

  U.tap(game, "left") U.wait(3)
  U.tap(game, "right") U.wait(1)
  pass("s3r opposite press during a flip is dropped", SummaryMenu._slide.active and SummaryMenu._slide.queued == nil)
  settle()
  pass("s3r dropped press did not flip", SummaryMenu._page == SummaryMenu.PAGE_INFO)
  U.tap(game, "right") U.wait(3)
  U.tap(game, "right") U.wait(1)
  pass("s3r same-direction press during a flip is queued", SummaryMenu._slide.queued == 1)
  settle() settle()
  pass("s3r right-right from INFO lands on KNOWN MOVES", SummaryMenu._page == SummaryMenu.PAGE_MOVES, SummaryMenu._page)

  U.tap(game, "left")
  until_step(2)
  pass("s3r left flip header on incoming layer", SummaryMenu._page == SummaryMenu.PAGE_SKILLS
    and SummaryMenu._slide.frame >= SummaryMenu.FLIP_TIMING.page.header)
  shot("s3r_flip_left_header_rides_incoming_layer")
  settle()

  local Options = require("src.core.game3.options")
  local opts = Options.ensure(session)
  local savedMode = opts.buttonMode
  opts.buttonMode = 2
  U.tap(game, "r") U.wait(2)
  pass("s3r R does not flip in L=A mode", SummaryMenu._page == SummaryMenu.PAGE_SKILLS and not SummaryMenu._slide.active)
  opts.buttonMode = 1
  U.tap(game, "r")
  pass("s3r R flips in LR mode", SummaryMenu._page == SummaryMenu.PAGE_MOVES)
  settle()
  opts.buttonMode = savedMode
  frame_calls()
  pass("s3 known moves page", SummaryMenu._page == SummaryMenu.PAGE_MOVES)
  pass("s3 known moves picture frame bg3", called("drawBg3", function(a) return a[1] == "info" end)
    and not called("drawBg3", function(a) return a[1] == "moves" end))
  pass("s3 known moves draws front pic", called("monFrontPic"))
  pass("s3 known moves hides icon", not called("monIcon"))
  pass("s3 known moves status TL", called("drawStatusIcon", function(a) return a[1] == 0 and a[2] == 34 end))
  pass("s3 known moves shiny star", called("drawShinyStar", function(a) return a[1] == 102 and a[2] == 36 end))
  shot("s3_known_moves_lowpp_empty_slot")

  U.tap(game, "right") U.wait(4)
  pass("s3 right on MOVES does not wrap", SummaryMenu._page == SummaryMenu.PAGE_MOVES and not SummaryMenu._slide.active)

  U.tap(game, "a")
  pass("s3 A on MOVES slides detail in", SummaryMenu._slide.active and SummaryMenu._slide.kind == "detail")
  until_step(2)
  pass("s3r detail slide name strip blank", SummaryMenu._slide.frame < SummaryMenu.FLIP_TIMING.detail.name)
  shot("s3r_detail_slide_blank_name_strip")
  settle()
  frame_calls()
  pass("s3 detail page", SummaryMenu._page == SummaryMenu.PAGE_MOVES_INFO)
  pass("s3 detail keeps move list panel", called("drawLayer", function(a) return a[1] == "moves" end)
    and called("drawLayer", function(a) return a[1] == "moves_info" end))
  pass("s3 detail icon not pic", called("monIcon") and not called("monFrontPic"))
  pass("s3 detail hides status on A path", not called("drawStatusIcon"))
  pass("s3 detail shiny star TL", called("drawShinyStar", function(a) return a[1] == 4 and a[2] == 20 end))
  pass("s3 detail mon type badge", called("drawTypeBadge", function(a) return a[2] == 48 and a[3] == 35 end))
  shot("s3_move_detail")

  U.tap(game, "down") U.wait(2)
  U.tap(game, "a") U.wait(2)
  U.tap(game, "down") U.wait(2)
  pass("s3 swap started", SummaryMenu._swapSlot == 2 and SummaryMenu._moveCursor == 3)
  shot("s3_swap_cursor_shown")
  local flipped = false
  for _ = 1, 70 do
    U.wait(1)
    if SummaryMenu._blink.hidden then flipped = true break end
  end
  pass("s3 swap cursor blinks", flipped)
  if flipped then shot("s3_swap_cursor_blinked_off") end
  U.tap(game, "b") U.wait(2)
  pass("s3 B cancels swap", SummaryMenu._swapSlot == nil and SummaryMenu._page == SummaryMenu.PAGE_MOVES_INFO)

  U.tap(game, "b") settle()
  U.tap(game, "left") settle()
  U.tap(game, "right") settle()
  U.tap(game, "a") settle()
  pass("s3r move cursor kept across back-out and page flips", SummaryMenu._page == SummaryMenu.PAGE_MOVES_INFO
    and SummaryMenu._moveCursor == 3, SummaryMenu._moveCursor)

  U.tap(game, "down") U.wait(2)
  pass("s3 detail cursor skips the empty slot onto CANCEL", SummaryMenu._moveCursor == 5, SummaryMenu._moveCursor)
  shot("s3_detail_cancel_row")

  U.tap(game, "b")
  until_step(2)
  shot("s3_detail_slide_out")
  settle()
  pass("s3 B returns to known moves", SummaryMenu._page == SummaryMenu.PAGE_MOVES and not SummaryMenu._slide.active)
  pass("s3r B on CANCEL resets the move cursor", SummaryMenu._moveCursor == 1, SummaryMenu._moveCursor)

  U.tap(game, "left")
  until_step(3)
  shot("s3_slide_skills_in_from_moves")
  settle()
  U.tap(game, "left") settle()
  pass("s3 back on INFO", SummaryMenu._page == SummaryMenu.PAGE_INFO)
  U.tap(game, "a") U.wait(4)
  pass("s3 A on INFO closes", not SummaryMenu.isOpen())
  for _ = 1, 10 do if not SummaryMenu.isOpen() then break end U.tap(game, "b") U.wait(4) end

  SummaryMenu.openMenu(session.party, 1, { mode = "select_move", moveToLearn = 85, onSelectMove = function() end })
  settle()
  frame_calls()
  pass("s3 learn progress tiles", called("drawProgress", function(a) return a[1] == "moves_info_select" end))
  pass("s3 learn status TL", called("drawStatusIcon", function(a) return a[1] == 0 and a[2] == 41 end))
  shot("s3_learn_move_select")
  for _ = 1, 10 do if not SummaryMenu.isOpen() then break end U.tap(game, "b") U.wait(4) end

  SummaryMenu.openMenu(session.party, 1, { mode = "select_move", forgetMove = true, onSelectMove = function() end })
  settle()
  shot("s3_forget_move_select")
  for _ = 1, 10 do if not SummaryMenu.isOpen() then break end U.tap(game, "b") U.wait(4) end

  SummaryMenu.openMenu(session.party, 2, {})
  local peak = 0
  for _ = 1, 12 do
    U.wait(1)
    if SummaryMenu._bounce.dy < peak then peak = SummaryMenu._bounce.dy end
    if peak <= -8 then break end
  end
  pass("s3 full hp pic bounces", peak <= -8, peak)
  shot("s3_plain_pic_bounce_peak")
  U.wait(60)
  pass("s3 bounce settles", SummaryMenu._bounce.dy == 0 and SummaryMenu._bounce.count >= 2)
  frame_calls()
  pass("s3 plain bg not shiny", called("drawBg3", function(a) return a[2] == false end))
  shot("s3_plain_info_flipped_pic")
  local eps = SummaryChrome.manifest().eggPicShake
  pass("s3r egg shake tables from the cache", eps and #eps == 3 and #eps[3] == 15 and eps[3][7] == -2)
  U.tap(game, "down") settle()
  pass("s3 egg page", SummaryMenu._page == SummaryMenu.PAGE_EGG)
  pass("s3r egg shake vigor from friendship 5", SummaryMenu._bounce.egg and SummaryMenu._bounce.vigor == 2)
  shot("s3r_egg_state_box_text")
  local still, moved = true, false
  for i = 1, 90 do
    U.wait(1)
    if i < 50 and SummaryMenu._bounce.dx ~= 0 then still = false end
    if math.abs(SummaryMenu._bounce.dx) >= 2 then moved = true break end
  end
  pass("s3r egg holds still through the 60-frame delay", still)
  pass("s3r egg shakes", moved, SummaryMenu._bounce.dx)
  if moved then shot("s3r_egg_shake_midjiggle") end
  for _ = 1, 10 do if not SummaryMenu.isOpen() then break end U.tap(game, "b") U.wait(4) end

  SummaryMenu.openMenu(session.party, 1, {})
  settle()
  local statused = SummaryMenu._bounce.count >= 2 and SummaryMenu._bounce.dy == 0
  pass("s3 statused pic does not bounce", statused)
  for _ = 1, 10 do if not SummaryMenu.isOpen() then break end U.tap(game, "b") U.wait(4) end

  print(failures == 0 and "PASS game3_summary_pages_s3" or ("FAIL game3_summary_pages_s3 " .. failures))
  love.event.quit(failures == 0 and 0 or 1)
end

return run

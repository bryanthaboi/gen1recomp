-- #1693: the mon SUMMARY's lower half never took the selected page's colour.
-- StatsScreen_LoadGFX .LoadPals farcalls LoadStatsScreenPals with the page
-- index, and that writes one gfx/stats/stats.pal colour over colour 0 of BG
-- palette 0 AND BG palette 2 (engine/gfx/color.asm:373-393); WipeAttrmap
-- leaves rows 8-17 on palette 0 with the exp strip at (10,16) on palette 2
-- (engine/gfx/cgb_layouts.asm:219-229), so both writes land below the rule.
-- Never add POKEPORT_SPEED here: fast-forward scales the logic clock only, so
-- the cry and the page redraw stop landing in the order a reader is judging.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_stats_page_tint_bug1693_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-bug1693 \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
local U = require("tests.drivers.util")

local GbcPalette = require("src.render.GbcPalette")
local HpBar = require("src.battle.gen2.HpBar")
local Mon = require("src.battle.gen2.Mon")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

-- gfx/stats/stats.pal, 5-bit the way the ROM keeps it: pink, green, blue
local ROM_TINTS = { { 31, 19, 31 }, { 21, 31, 14 }, { 17, 31, 31 } }
local PAGE_NAMES = { "pink", "green", "blue" }

local function up(v) return math.floor(v * 255 / 31 + 0.5) end
local function pct(v) return math.floor(v + 0.5) end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1693"
  local fails = 0

  local function ok(cond, msg)
    if cond then U.log("PASS", msg) else fails = fails + 1 U.log("FAIL", msg) end
    return cond and true or false
  end
  local function tap(btn) U.tap(game, btn) U.wait(4) end
  local function top() return game.stack:top() end
  local function shot(name)
    return ok(U.shot(game, ("%s/%s.png"):format(out, name)),
      name .. " reached disk")
  end

  U.wait(45)
  if not ok(game.world and game.world.map ~= nil,
      "gold booted into the world") then
    error("gold stats tint: no world, nothing to open a summary over")
  end

  -- ---- the party the pink page needs ---------------------------------------
  -- Mon.new is the only Gen 2 party builder; a mon out of Gen 1's Pokemon.new
  -- comes back with no moves and no growth rate, so both bars would be empty.
  local save = game.save
  save.player.name = "GOLD"
  save.player.id = 12345
  save.party = {
    Mon.new(game.data, "CYNDAQUIL", 22),
    Mon.new(game.data, "TOTODILE", 18),
  }
  local lead = save.party[1]
  lead.item = "BERRY"
  lead.hp = math.max(1, math.floor((lead.maxHp or 1) * 0.45))
  local def = game.data.pokemon[lead.species]
  local rates = game.data.pokemon.growthRates
  local rate = rates and def and rates[def.growthRate]
  if rate then
    local base = Mon.experienceForLevel(rate, lead.level)
    local next_ = Mon.experienceForLevel(rate, lead.level + 1)
    lead.experience = base + math.floor((next_ - base) * 0.55)
  end
  ok(game.world.giveEgg and game.world:giveEgg(175, 5) and save.party[3]
    and save.party[3].isEgg == true, "slot 3 holds an egg")

  -- ---- everything the eye cannot check -------------------------------------
  for page = 1, 3 do
    local tint = SummaryMenu.PAGE_TINTS and SummaryMenu.PAGE_TINTS[page]
    ok(tint ~= nil and tint[1] == up(ROM_TINTS[page][1])
      and tint[2] == up(ROM_TINTS[page][2])
      and tint[3] == up(ROM_TINTS[page][3]),
      ("the %s tint is stats.pal's own colour"):format(PAGE_NAMES[page]))
    local probe = setmetatable({ page = page }, { __index = SummaryMenu })
    local lower = probe.lowerColors and probe:lowerColors()
    ok(lower ~= nil and lower[1] == tint and lower[4][1] == 0,
      ("the %s lower palette is that tint over black ink"):format(
        PAGE_NAMES[page]))
  end
  ok(GbcPalette.available(), "the GBC shade-remap shader compiled")

  -- COLOR is the port's own display row and DMG flattens every palette in the
  -- game, so a run started on it looks exactly like the bug.
  game.options = game.options or {}
  local startedOn = game.options.color or "gbc"
  local function setColor(mode)
    game.options.color = mode
    if game.save then game.save.options = game.options end
    GbcPalette.applyOptions(game.options)
    return GbcPalette.mode
  end
  if startedOn ~= "gbc" then
    U.log("COLOR was on " .. GbcPalette.modeLabel(startedOn) .. ", which would")
    U.log("grey every shot below for the wrong reason. forcing it to GBC.")
  end
  ok(setColor("gbc") == "gbc", "COLOR is GBC for the run")

  -- ---- the live screen, counted rather than admired ------------------------
  -- The summary draws at GB coordinates, so a 160x144 canvas at scale 1 makes
  -- a GB pixel a pixel and the tint countable.
  local function frameOf(screen)
    local G = love.graphics
    local canvas = G.newCanvas(160, 144)
    G.setCanvas(canvas)
    G.clear(0, 0, 0, 1)
    G.setColor(1, 1, 1, 1)
    screen:draw()
    G.setCanvas()
    G.setColor(1, 1, 1, 1)
    return canvas:newImageData()
  end

  local function near(a, b) return math.abs(a - b) <= 2 end

  -- Counted against stats.pal itself, not the port's table, so a run that has
  -- no PAGE_TINTS cannot agree with itself.
  local function tintFor(page)
    local rom = ROM_TINTS[page] or ROM_TINTS[1]
    return { up(rom[1]), up(rom[2]), up(rom[3]) }
  end

  local function scan(img, want, x0, y0, x1, y1)
    local hit, white, total = 0, 0, 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b = img:getPixel(x, y)
        r, g, b = r * 255, g * 255, b * 255
        total = total + 1
        if near(r, want[1]) and near(g, want[2]) and near(b, want[3]) then
          hit = hit + 1
        end
        if near(r, 255) and near(g, 255) and near(b, 255) then
          white = white + 1
        end
      end
    end
    return hit / total * 100, white / total * 100
  end

  -- StatsScreen_LoadGFX .ClearBox: hlcoord 0, 8 / lb bc, 10, 20
  local LOWER = { 0, 64, 159, 143 }
  local function report(label, hit, white)
    U.log(("  %-24s %3d%% tinted %3d%% white"):format(label, pct(hit),
      pct(white)))
  end

  local function zone(img, tint, label, rect, wantTint)
    local hit, white = scan(img, tint, rect[1], rect[2], rect[3], rect[4])
    report(label, hit, white)
    ok(hit >= wantTint, label .. " carries the page tint")
    ok(white <= 2, label .. " has no white left in it")
  end

  local function inspect(screen, name)
    local img = frameOf(screen)
    local tint = tintFor(screen.page)
    zone(img, tint, "rows 8-17", LOWER, 40)
    if screen.page == SummaryMenu.PINK_PAGE then
      -- DrawPlayerHP: "HP:" at (0,9), six bar cells from (2,9)
      zone(img, tint, "the HP bar's cells", { 16, 72, 63, 79 }, 8)
      -- LoadPinkPage's divider column, and FillInExpBar at (11,16)
      zone(img, tint, "the divider, column 9", { 72, 64, 79, 143 }, 20)
      zone(img, tint, "the exp bar", { 88, 128, 151, 135 }, 8)
    elseif screen.page == SummaryMenu.BLUE_PAGE then
      zone(img, tint, "the divider, column 10", { 80, 64, 87, 143 }, 20)
    end
    -- The upper half is on the mon palette, which the cart never tints.
    local _, white = scan(img, tint, 0, 0, 159, 55)
    ok(white >= 20, "the upper half stayed white")
    shot(name)
  end

  -- ---- walk in through the pad ---------------------------------------------
  tap("start")
  local menu = top()
  if not ok(menu and menu.screenId == "Gen2StartMenu",
      "START opened the menu") then
    error("gold stats tint: no start menu, cannot reach the summary")
  end
  for _ = 1, 10 do
    if menu.list:current().value == "pokemon" then break end
    tap("down")
  end
  ok(menu.list:current().value == "pokemon", "the cursor found the party row")
  tap("a")
  local party = top()
  if not ok(party and party.screenId == "Gen2PartyMenu",
      "that opened the party list") then
    error("gold stats tint: no party list, cannot reach the summary")
  end

  local function openStats()
    tap("a")
    ok(party.submenu ~= nil and party.submenu.items[1].id == "STATS",
      "the mon submenu leads with STATS")
    tap("a")
    local screen = top()
    ok(screen and screen.screenId == "Gen2SummaryMenu",
      "STATS opened the summary")
    return screen
  end

  local summary = openStats()
  ok(summary.hud and summary.hud:available(),
    "the HUD sheet is cached, so the bars are the cart's own tiles")
  ok(summary.statsTiles and summary:statsTiles() ~= nil,
    "menu_gfx.stats is cached, so the divider and caps are too")
  local fraction = HpBar.expFraction(summary.mon, summary:growth(),
    Mon.experienceForLevel)
  ok(fraction > 0.05 and fraction < 0.95,
    "the lead is part way to its next level, so the exp bar is half drawn")
  ok((summary.mon.hp or 0) > 0 and summary.mon.hp < (summary.mon.maxHp or 0),
    "and hurt, so the HP bar has empty cells as well as full ones")

  inspect(summary, "01-pink-page")
  tap("right")
  ok(summary.page == SummaryMenu.GREEN_PAGE, "right reached the green page")
  inspect(summary, "02-green-page")
  tap("right")
  ok(summary.page == SummaryMenu.BLUE_PAGE, "right reached the blue page")
  inspect(summary, "03-blue-page")
  tap("right")
  ok(summary.page == SummaryMenu.PINK_PAGE, "and wrapped back to pink")

  -- ---- the two screens that must stay white --------------------------------
  tap("b")
  ok(top() == party, "b came back to the list")
  tap("down")
  tap("down")
  ok(party.index == 3, "the cursor reached the egg")
  local egg = openStats()
  ok(egg.mon and egg.mon.isEgg == true, "on the egg")
  local eggTint, eggWhite = scan(frameOf(egg), tintFor(SummaryMenu.PINK_PAGE),
    LOWER[1], LOWER[2], LOWER[3], LOWER[4])
  report("the egg's rows 8-17", eggTint, eggWhite)
  -- EggStatsScreen never calls LoadStatsScreenPals (stats_screen.asm:786)
  ok(eggTint <= 1 and eggWhite >= 40, "the egg page stayed white")
  shot("04-egg-white")

  tap("b")
  tap("up")
  tap("up")
  ok(setColor("dmg") == "dmg", "COLOR switched to DMG")
  local dmg = openStats()
  local dmgTint, dmgWhite = scan(frameOf(dmg), tintFor(dmg.page),
    LOWER[1], LOWER[2], LOWER[3], LOWER[4])
  report("DMG's rows 8-17", dmgTint, dmgWhite)
  -- LoadStatsScreenPals opens `call CheckCGB / ret z` (color.asm:373-375)
  ok(dmgTint <= 1 and dmgWhite >= 40, "DMG flattened the tint back to white")
  shot("05-dmg-white")
  tap("b")
  ok(setColor("gbc") == "gbc", "COLOR is back on GBC for the handoff")

  -- ---- what a reader is looking at -----------------------------------------
  openStats()
  U.wait(4)

  if fails > 0 then
    U.log(("%d check(s) failed above. do not judge the colours -- the run is"):
      format(fails))
    U.log("not showing you what it claims to.")
  end
  U.log("shots are in " .. out .. ". the summary is open on the pink page and")
  U.log("left/right turn it: everything under the horizontal rule should be")
  U.log("washed pink, then green, then cyan, matching whichever page square is")
  U.log("the large one, while the pic, nickname and level stay white.")
  U.log("a partial fix leaves white in one of three places -- an 8px stripe")
  U.log("down the divider column, the bands above and below the HP bar's fill,")
  U.log("or the exp bar's interior inside its black frame.")

  while true do coroutine.yield() end
end

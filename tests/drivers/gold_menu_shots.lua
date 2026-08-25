-- Screenshots of every Gen 2 menu, for eyes that a test cannot replace.
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_menu_shots.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-menus   (default)
--
-- The driver boots straight into the world (Game2 skips the cinema under
-- POKEPORT_DRIVER), gives the save enough content that the screens have
-- something to draw, then pushes each one and captures it.
local U = require("tests.drivers.util")

local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local BoxMenu = require("src.ui.gen2.BoxMenu")
local PackMenu = require("src.ui.gen2.PackMenu")
local PcMenu = require("src.ui.gen2.PcMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Pokegear = require("src.ui.gen2.Pokegear")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local StartMenu = require("src.ui.gen2.StartMenu")
local TrainerCard = require("src.ui.gen2.TrainerCard")
local GoldSilverIntro = require("src.ui.gen2.GoldSilverIntro")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-menus"

  local function shot(name)
    U.wait(3)
    U.shot(game, ("%s/%s.png"):format(out, name))
  end

  -- Capture a state on its own, then take it back off the stack.
  local function show(name, state)
    game.stack:push(state)
    shot(name)
    game.stack:pop()
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  -- Give the save something to show: a party, a bag across pockets, badges,
  -- dex progress, a phone number and an unlocked Pokegear.
  local save = game.save
  local pokemon = game.data.pokemon or {}
  local function mon(species, level, hp)
    local def = pokemon[species]
    local maxHp = 20 + level
    return {
      species = species, name = def and def.name or species,
      nickname = def and def.name or species,
      level = level, hp = hp or maxHp, maxHp = maxHp,
    }
  end
  save.party = {
    mon("CYNDAQUIL", 12),
    mon("TOTODILE", 10, 9),
    mon("PIDGEY", 8, 2),
  }
  -- Bag ids are the CONSTANT names ItemAttributes is keyed by, not the printed
  -- name: a TM's id is what it teaches (TM_DYNAMICPUNCH prints as "TM01"), so
  -- seeding "TM01" here would leave the TM pocket empty and drop three unknown
  -- rows into the ITEMS pocket instead.  TOWN_MAP is not a bag item in Gold
  -- either (the map is a Pokegear card, and item 6 is one of the unused
  -- TERU-SAMA slots).
  save.inventory = {
    POTION = 5, SUPER_POTION = 2, ANTIDOTE = 1, FULL_HEAL = 1,
    REVIVE = 1, ETHER = 2, X_ATTACK = 1, REPEL = 3,
    POKE_BALL = 10, GREAT_BALL = 3, ULTRA_BALL = 1,
    BICYCLE = 1, ITEMFINDER = 1, OLD_ROD = 1, COIN_CASE = 1,
    SQUIRTBOTTLE = 1,
    TM_DYNAMICPUNCH = 1, TM_HEADBUTT = 1, TM_ROCK_SMASH = 1,
    HM_CUT = 1, HM_SURF = 1,
  }
  save.player.badges = { true, true }
  save.player.money = 3210
  save.player.id = 12345
  save.player.name = "GOLD"
  save.playTime = { hours = 4, minutes = 37, seconds = 0, frames = 0 }
  -- The unlocks the way the game writes them: ENGINE_RADIO_CARD 0,
  -- ENGINE_MAP_CARD 1, ENGINE_PHONE_CARD 2, ENGINE_POKEGEAR 4 and
  -- ENGINE_POKEDEX 11 through the same store `setflag` lands in.
  save.engineFlags = save.engineFlags or {}
  for _, flag in ipairs({ 0, 1, 2, 4, 11 }) do
    save.engineFlags[flag] = true
  end
  save.phoneContacts = { ELM = true, MOM = true }
  for _, species in ipairs({ "CYNDAQUIL", "TOTODILE", "CHIKORITA", "PIDGEY",
      "RATTATA", "SENTRET", "HOOTHOOT" }) do
    save.pokedex.seen[species] = true
  end
  for _, species in ipairs({ "CYNDAQUIL", "TOTODILE", "PIDGEY" }) do
    save.pokedex.caught[species] = true
  end

  -- The overworld itself, for reference.
  shot("00-overworld")

  -- Boot screens.
  show("01-mainmenu-newgame", MainMenu.new(game, {
    hasSave = false, save = false,
    clock = { hour = 10, minute = 5, weekday = 3 },
  }))
  show("02-mainmenu-continue", MainMenu.new(game, {
    hasSave = true, save = save,
    clock = { hour = 20, minute = 42, weekday = 6 },
  }))

  local sprites = game.data.gen2Sprites
  local chris = sprites and sprites.SPRITE_CHRIS
  local Palettes = require("src.world.gen2.Palettes")
  local naming = NamingScreen.new(game, {
    type = "player",
    menuGfx = game.data.gen2MenuGfx,
    iconPath = chris and chris.image or nil,
    iconColors = game.data.gen2Palettes
      and Palettes.spritePalette(game.data.gen2Palettes, "DAY", chris) or nil,
  })
  naming.text = "GOL"
  show("03-naming-upper", naming)
  naming.lower = true
  naming.row = 4
  naming.col = 3
  show("04-naming-lower-del", naming)

  -- The movie is a state machine, so a still is "run it to frame N": one from
  -- each act, picked where its cast is on screen.
  local intro = GoldSilverIntro.new(game, {})
  local function seek(target)
    while intro.frames < target and not intro.done do intro:step() end
    return intro
  end
  show("05-intro-water", seek(600))
  show("06-intro-grass", seek(1500))
  show("07-intro-fire", seek(2200))

  -- In-game menus.  The start menu is not opaque, so the overworld shows
  -- through it -- which is exactly how it looks in play.
  show("08-startmenu", StartMenu.new(game, { save = save }))
  -- QUIT's confirmation, which is the port's own row rather than the cart's
  -- EXIT: the yes/no defaults to NO so a stray A never throws away progress.
  local quitting = StartMenu.new(game, { save = save })
  quitting.phase = "confirm"
  quitting.confirmChoice = 2
  show("24-startmenu-quit", quitting)
  show("09-party", PartyMenu.new(game, { prompt = "choose" }))
  show("10-pack-items", PackMenu.new(game, { pocket = "ITEM" }))
  show("11-pack-tms", PackMenu.new(game, { pocket = "TM_HM" }))
  show("12-pokegear-clock", Pokegear.new(game, {
    clock = { hour = 14, minute = 8, weekday = 2 },
    currentLandmark = "LANDMARK_NEW_BARK_TOWN",
  }))

  local gear = Pokegear.new(game, {
    currentLandmark = "LANDMARK_NEW_BARK_TOWN",
  })
  gear.cardIndex = 2
  gear.mode = "card"
  show("13-pokegear-map", gear)
  -- The radio card, tuned and playing, and the phone mid-call.
  local radio = Pokegear.new(game, {})
  radio.mode = "card"
  for i, card in ipairs(radio.cards) do
    if card.id == "radio" then radio.cardIndex = i end
  end
  radio.station = 1
  radio.radioLine = 2
  show("13b-pokegear-radio", radio)
  local phone = Pokegear.new(game, {})
  phone.mode = "card"
  for i, card in ipairs(phone.cards) do
    if card.id == "phone" then phone.cardIndex = i end
  end
  phone:callContact((phone:phoneList() or {})[1])
  show("13c-pokegear-phone", phone)


  local card = TrainerCard.new(game, {})
  show("14-trainercard", card)
  card.page = 2
  show("15-trainercard-badges", card)

  show("16-pokedex", PokedexMenu.new(game, {}))
  local dex = PokedexMenu.new(game, {})
  dex.view = "entry"
  for i, row in ipairs(dex.rows) do
    if row.caught then dex.index = i break end
  end
  show("17-pokedex-entry", dex)
  -- The two screens SELECT and START open (Pokedex_InitOptionScreen /
  -- Pokedex_InitSearchScreen).
  local dexOption = PokedexMenu.new(game, {})
  dexOption.view = "option"
  show("17b-pokedex-option", dexOption)
  local dexSearch = PokedexMenu.new(game, {})
  dexSearch.view = "search"
  dexSearch.searchType = { 10, 0 } -- FIRE / -----
  show("17c-pokedex-search", dexSearch)

  show("18-options", OptionsMenu.new(game, { options = game.options }))
  -- ...and scrolled to the port's own display rows, which is what the ▼ on
  -- the first page points at.
  local scrolled = OptionsMenu.new(game, { options = game.options })
  scrolled.index = #OptionsMenu.ROWS
  scrolled:ensureVisible()
  show("25-options-display", scrolled)
  -- writer is stubbed so the shot never touches a real save file.
  show("19-save", SaveMenu.new(game, {
    save = save, existed = false,
    writer = function() return true end,
  }))

  -- The storage system: the PC's top menu, the box picker, and the withdraw
  -- and deposit lists.  Stock a box first so the list has rows and the left
  -- panel has a pic to draw.
  local Boxes = require("src.core.gen2.Boxes")
  local stored = Boxes.box(save, 1)
  for i, species in ipairs({ "GEODUDE", "ZUBAT", "RATTATA", "SENTRET" }) do
    stored[i] = mon(species, 10 + i)
  end
  Boxes.rename(save, 2, "GRASS")
  -- $5d for a held item, $5c for MAIL (engine/pokemon/bills_pc.asm:1079-1094).
  -- A boxed mon can never hold mail, so the letter goes on a party mon.
  stored[1].item = "BERRY"
  save.party[2].item = "FLOWER_MAIL"
  local Mail = require("src.core.gen2.Mail")
  Mail.set(save, 2, Mail.entry("FLOWER_MAIL", "HI THERE!",
    save.player.name or "GOLD", save.player.id or 0, save.party[2].species))

  local pc = PcMenu.new(game, { save = save })
  show("20-pc-menu", pc)
  pc.picking = true
  pc.pickIndex = 2
  show("21-pc-changebox", pc)

  -- Browsing paints the 7x7 block in BillsPCOrangePalette and only .PrepSubmenu
  -- swaps the mon's colours in (engine/pokemon/bills_pc.asm:305-309, :356-369,
  -- engine/gfx/cgb_layouts.asm:284-289); the icon is BG palette 0 either way.
  local wd = BoxMenu.new(game, { save = save, mode = "withdraw" })
  show("22-pc-withdraw", wd)
  wd.index = wd:total() -- CANCEL
  wd:ensureVisible()
  show("22b-pc-withdraw-cancel", wd)
  wd.index = 1
  wd:ensureVisible()
  wd.phase = "submenu"
  show("22c-pc-withdraw-submenu", wd)
  local dep = BoxMenu.new(game, { save = save, mode = "deposit" })
  show("23-pc-deposit", dep)
  dep.index = 2 -- the mon holding FLOWER MAIL
  show("23b-pc-deposit-mail", dep)

  -- Only the move list gets the box-name arrows, $5f left and $5e right
  -- (engine/pokemon/bills_pc.asm:957-963); 22 and 23 above are the controls.
  local mv = BoxMenu.new(game, { save = save, mode = "move" })
  show("23c-pc-move-arrows", mv)

  -- The two clock screens NEW GAME and Mom open (timeset.asm InitClock and
  -- SetDayOfWeek), each at its picker rather than at its opening page.
  local clock = InitClock.new(game, { save = save })
  clock.phase = "hour"
  show("26-initclock-hour", clock)
  clock.phase = "minute"
  clock.minute = 25
  show("27-initclock-minutes", clock)
  clock.phase = "confirm-hour"
  show("28-initclock-confirm", clock)
  local wheel = InitClock.new(game, { mode = "day", save = save })
  wheel.day = 2
  show("29-dayofweek", wheel)

  -- FLY's own picker (_FlyMap): the town map with the cursor on a visited
  -- flypoint, not the yes/no chain the port used to fall back to.
  local FieldMoves = require("src.world.gen2.FieldMoves")
  save.engineFlags = save.engineFlags or {}
  for _, row in ipairs(FieldMoves.FLYPOINTS) do
    save.engineFlags[row.flag] = true
  end
  local points = FieldMoves.flyPoints(save, game.data.gen2Landmarks, "johto")
  show("30-flymap", Pokegear.new(game, {
    save = save,
    currentLandmark = "LANDMARK_NEW_BARK_TOWN",
    fly = points,
    onFly = function() end,
    onClose = function() end,
  }))

  print("[driver] PASS gold menu shots in " .. out)
end

-- Eye/ear check on Prof. Oak rating the Pokedex in his lab (#600): with the
-- Pokedex in hand and 2+ species owned he must lead with the rating branch,
-- not the line he reads while handing the Pokedex over.  pokered
-- scripts/OaksLab.asm OaksLabOak1Text + engine/events/pokedex_rating.asm.
-- Do not set POKEPORT_SPEED: fast-forward scales the logic clock only, so
-- the rating jingle stops landing where the text does.
--   POKEPORT_DRIVER=tests/drivers/oak_dex_rating_bug600_test.lua POKEPORT_IDENTITY=bug600 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Commands = require("src.script.Commands")
  local TextBox = require("src.render.TextBox")
  local oaksLab = require("data.scripts.oaks_lab")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- pokered data/maps/objects/OaksLab.asm: OAKSLAB_OAK1 stands at (5, 2)
  -- facing DOWN behind the table, so the desk talk is from the cell below
  -- him; the leftover balls sit at (6, 3) / (7, 3) / (8, 3) with the row
  -- below them walkable (the rival walks it in OaksLabRivalTakePokeBall).
  local MAP = "OAKS_LAB"
  local OAK = "OAKSLAB_OAK1"
  local STAND = { x = 5, y = 3, facing = "up" }
  local BALL_STAND = { x = 8, y = 4 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function rowAt(rows, i)
    return rows and rows[i] or {}
  end

  -- ------------------------------------------------- script rows are there
  local oak1 = oaksLab.talk.TEXT_OAKSLAB_OAK1
  local firstRating, ratingLabel, dexRating, firstItemCheck
  for i, row in ipairs(oak1 or {}) do
    if row[1] == "check_dex_owned" and not firstRating then firstRating = i end
    if row[1] == "label" and row[2] == "dex_rating" then ratingLabel = i end
    if row[1] == "dex_rating" then dexRating = i end
    if row[1] == "check_item" and not firstItemCheck then firstItemCheck = i end
  end
  check("TEXT_OAKSLAB_OAK1 gates on 2+ owned species",
        firstRating ~= nil and rowAt(oak1, firstRating)[2] == 2)
  check("it has a dex_rating branch that ends in the rating predef",
        ratingLabel ~= nil and dexRating ~= nil and dexRating > ratingLabel)
  -- the branch has to be read before the POKe BALL / around-the-world forks
  -- or the old wrong line still wins
  check("the branch is read before the POKe BALL check",
        firstRating ~= nil and firstItemCheck ~= nil
        and firstRating < firstItemCheck)
  check("Commands has check_dex_owned and dex_rating",
        type(Commands.check_dex_owned) == "function"
        and type(Commands.dex_rating) == "function")

  -- the leftover-ball beat shares this file (#601 remnant, reported on #600)
  local ball = oaksLab.talk.TEXT_OAKSLAB_CHARMANDER_POKE_BALL
  local lastMon = rowAt(ball, 21)[2]
  check("the leftover ball reads the last-mon line",
        type(lastMon) == "string" and lastMon:find("last Pok", 1, true) ~= nil)
  check("and stops there instead of falling into the pre-pick line",
        rowAt(ball, 22)[1] == "jump" and rowAt(ball, 22)[2] == "end"
        and rowAt(ball, 23)[2] == "_OaksLabThoseArePokeBallsText")
  check("the pre-pick jump still lands on that line",
        rowAt(ball, 4)[1] == "jump_if_false" and rowAt(ball, 4)[2] == 23)

  -- -------------------------------------------------------- text and audio
  local t = game.data.text
  local COMING = "_OaksLabOak1HowIsYourPokedexComingText"
  local WRONG = "_OaksLabOak1PokemonAroundTheWorldText"
  check(COMING .. " resolves", type(t[COMING]) == "string" and t[COMING] ~= "")
  check("it is the how-is-it-coming line",
        type(t[COMING]) == "string" and t[COMING]:find("DEX", 1, true) ~= nil)
  check(WRONG .. " resolves too (the near miss to tell it from)",
        type(t[WRONG]) == "string" and t[WRONG] ~= "")
  check("_DexCompletionText resolves (the seen/owned tally)",
        type(t._DexCompletionText) == "string")
  local sfx = game.data.audio and game.data.audio.sfx
  check("Pokedex_Rating is in the sfx table",
        sfx ~= nil and sfx.Pokedex_Rating ~= nil)

  local opts = game.save.options or {}
  if (opts.sfxVol or 0) == 0 then
    U.log("SFX VOLUME IS 0. The jingle after the rating line is half of this")
    U.log("check. Raise SFX VOL in OPTION and rerun.")
  else
    check("sfx is audible (SFX VOL " .. tostring(opts.sfxVol) .. ")", true)
  end

  -- ------------------------------------------------------ save at the beat
  game.save.party = {
    Pokemon.new(game.data, "CHARMANDER", 8),
    Pokemon.new(game.data, "PIDGEY", 6),
  }
  if not game.save.player.name or game.save.player.name == "" then
    game.save.player.name = "RED"
  end
  local flags = game.save.flags
  flags.EVENT_GOT_POKEDEX = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  flags.EVENT_GOT_STARTER = true
  flags.EVENT_CHOSE_CHARMANDER = true
  flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  flags.EVENT_OAK_GOT_PARCEL = true
  -- deliberately left unset: with it the rating fires off the converted-save
  -- path instead, and the owned>=2 gate this issue is about goes untested
  flags.EVENT_PALLET_AFTER_GETTING_POKEBALLS = nil
  -- a driver save skips SaveData.new on some paths, so do not assume the dex
  local dex = game.save.pokedex or { seen = {}, owned = {} }
  game.save.pokedex = dex
  dex.owned = { CHARMANDER = true, PIDGEY = true, RATTATA = true }
  dex.seen = { CHARMANDER = true, PIDGEY = true, RATTATA = true,
               SPEAROW = true, WEEDLE = true }
  local owned = 0
  for _ in pairs(dex.owned) do owned = owned + 1 end
  check(("Pokedex in hand, %d species owned, no converted-save shortcut")
          :format(owned),
        flags.EVENT_GOT_POKEDEX == true and owned >= 2
        and flags.EVENT_PALLET_AFTER_GETTING_POKEBALLS == nil)
  -- the tier line is picked by decade in OverworldState:dexRating
  local tier = ("_DexRatingText_Own%dTo%d")
    :format(math.floor(owned / 10) * 10, math.floor(owned / 10) * 10 + 9)
  check(tier .. " resolves for that count", type(t[tier]) == "string")

  -- ----------------------------------------------------- park him at Oak's
  -- Oak1 is hidden until the parcel beat shows him (data/scripts/story2.lua
  -- swaps OAKSLAB_OAK2 for OAKSLAB_OAK1 via Commands.show_object), and that
  -- lives in save.objectToggles, not in the event flags seeded above; the
  -- rival is long gone by this beat for the same reason
  local toggles = game.save.objectToggles or {}
  game.save.objectToggles = toggles
  toggles[MAP] = toggles[MAP] or {}
  toggles[MAP][OAK] = true
  toggles[MAP].OAKSLAB_OAK2 = false
  toggles[MAP].OAKSLAB_RIVAL = false
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function oakNpc(ow)
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.name == OAK then return n end
    end
    return nil
  end

  local function facingOak()
    local ow = game.overworld
    local o = ow and oakNpc(ow)
    if not o then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == o
  end

  local ow = game.overworld
  local o = ow and oakNpc(ow)
  check("Oak is loaded on " .. MAP, o ~= nil)
  if o and not facingOak() then
    -- a map edit or a mod moved him: {dx, dy, facing} is the offset from Oak
    -- to the stand cell plus the direction that looks back at him
    for _, s in ipairs({ { 0, 1, "up" }, { 0, -1, "down" },
                         { 1, 0, "left" }, { -1, 0, "right" } }) do
      local cx, cy = o.cellX + s[1], o.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("desk cell (%d,%d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("standing below Oak at the desk", facingOak())

  -- press A here so the log can tell a missing branch from a press that never
  -- reached Oak; on screen those look the same
  U.tap(game, "a")
  U.wait(8)
  local top = game.stack:top()
  local isBox = getmetatable(top) == TextBox
  check("pressing A opened a text box", isBox)
  if isBox then
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    local joined = table.concat(shown, " / ")
    U.log("box reads:", joined)
    check("Oak opens on the rating branch, not the hand-over line",
          joined:find("DEX", 1, true) ~= nil
          and joined:find("wait for", 1, true) == nil)
  end
  U.wait(20)
  U.shot(game, DIR .. "/bug600_oak_rating.png")
  U.log("captured", DIR .. "/bug600_oak_rating.png")

  U.log("Oak has been talked to; that box on screen is the start of it. He")
  U.log("says \"Good to see you! How is your #DEX coming? Here, let me take a")
  U.log("look!\" and runs straight on into the seen/owned tally and PROF.OAK's")
  U.log("Rating with no press of yours in between, and the jingle sounds only")
  U.log("after the rating line has printed, not over it (#576). If he instead")
  U.log("says \"#MON around the world wait for you\" or \"Come see me")
  U.log("sometimes\", the branch never fired.")
  U.log("The pad is yours: A again re-runs it any time. For the other half,")
  U.log(("walk to (%d,%d) and press A up at the leftover ball: Oak turns to")
          :format(BALL_STAND.x, BALL_STAND.y))
  U.log("face you and says only \"That's PROF.OAK's last Pokemon!\", with no")
  U.log("second box about POKe BALLs after it.")
  U.log("To see the gate itself, console: game.save.pokedex.owned = { CHARMANDER")
  U.log("= true } and talk again -- one species owned is the around-the-world line.")

  while true do
    coroutine.yield()
  end
end

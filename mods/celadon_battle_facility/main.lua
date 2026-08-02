-- A battle facility on Celadon City's west lawn: a three-tier gauntlet
-- ladder of consecutive battles, scaled to the player's party.
--
-- Placement is data-verified rather than eyeballed.  Celadon is the only
-- oversized city map (25x18 blocks; every other city is 20x18) and block
-- rows 7-11 / columns 1-9 are a contiguous field of block 85 -- the largest
-- unused space in Kanto.  The footprint below is the one 4x2 rectangle in
-- that field that touches neither a map object nor the Celadon Dept. Store's
-- approach row (its warps at cells (8,13) and (10,13) are entered from
-- below, so block row 7 columns 4-5 have to stay walkable).

local CITY = "CELADON_CITY"
local FACILITY = "CELADON_BATTLE_FACILITY"

local GREETER = "CBF_GREETER"
local GREETER_TEXT = "TEXT_CBF_GREETER"

local CLERK_TEXT = "TEXT_CBF_CLERK"
local ARCHIVIST_TEXT = "TEXT_CBF_ARCHIVIST"
local ROOKIE_TEXT = "TEXT_CBF_ROOKIE"

-- The facility's own currency, paid out per tier cleared and spent at the
-- prize counter.  A normal item rather than a key item, so it stacks.
local TOKEN = "CBF_TOKEN"
local TOKEN_NAME = "BATTLE PT"
local TOKEN_AWARD = { bronze = 1, silver = 3, gold = 5 }

-- Prize counter stock, cheapest first.  The last row is the exit.
local PRIZES = {
  { item = "FULL_RESTORE", cost = 1, label = "FULL RESTORE" },
  { item = "PP_UP",        cost = 3, label = "PP UP" },
  { item = "RARE_CANDY",   cost = 4, label = "RARE CANDY" },
  { item = "MASTER_BALL",  cost = 12, label = "MASTER BALL" },
}

local RECORDS_SCREEN = "CbfRecords"

-- ------- the ladder

-- Three tiers, unlocked in order.  `bonus` is added to the player's average
-- party level when the opponent is built, so Gold is a real step up rather
-- than the same fight with more rounds.  Rosters are thematic; the levels in
-- them are placeholders that the scaling hook overwrites.
local TIERS = {
  { id = "bronze", label = "BRONZE", class = "OPP_CBF_BRONZE", rounds = 3, bonus = 0 },
  { id = "silver", label = "SILVER", class = "OPP_CBF_SILVER", rounds = 5, bonus = 3 },
  { id = "gold",   label = "GOLD",   class = "OPP_CBF_GOLD",   rounds = 7, bonus = 6 },
}

-- One roster per round, so round N fights party N of the tier's class.
local ROSTERS = {
  bronze = {
    { "RATICATE", "FEAROW" },
    { "ARBOK", "SANDSLASH" },
    { "PRIMEAPE", "GOLDUCK", "VICTREEBEL" },
  },
  silver = {
    { "MAGNETON", "ELECTRODE" },
    { "WEEZING", "MUK" },
    { "HYPNO", "MR_MIME" },
    { "RHYDON", "GOLEM" },
    { "STARMIE", "NINETALES", "VILEPLUME" },
  },
  gold = {
    { "MACHAMP", "POLIWRATH" },
    { "GENGAR", "ALAKAZAM" },
    { "CLOYSTER", "LAPRAS" },
    { "ARCANINE", "FLAREON" },
    { "TENTACRUEL", "SLOWBRO" },
    { "AERODACTYL", "KABUTOPS" },
    { "DRAGONITE", "SNORLAX", "EXEGGUTOR" },
  },
}

-- Which vanilla class each tier borrows its portrait from.  basePic is the
-- sanctioned way to have trainer art without redistributing any.
local TIER_PIC = {
  bronze = "OPP_JR_TRAINER_M",
  silver = "OPP_COOLTRAINER_M",
  gold = "OPP_COOLTRAINER_F",
}

local function tierById(id)
  for _, tier in ipairs(TIERS) do
    if tier.id == id then return tier end
  end
end

-- ------- the exterior footprint

-- Top-left corner of the 4x2 block footprint, in block coordinates.
local FOOT_COL, FOOT_ROW = 2, 9

-- A roofed 4x2 building, copied whole from ROUTE_5 (block columns 3-6, rows
-- 15-16 -- the Route 5 gate house), whose warp sits on block 58's bottom-left
-- cell at (10,33).  32/13/13/33 is the roof and 55/125/58/126 the wall, with
-- 58 carrying the door.
--
-- The roof row is the point.  An earlier draft stacked two *wall* rows
-- (104/127/127/105 over 55/58/58/126, the Dept. Store's middle floors), which
-- gave a building with no roofline -- it read as a brick wall standing in the
-- grass rather than a structure.
--
-- Signage is baked into the tileset art, so copying a neighbour wholesale is
-- a trap: block 17 draws "GYM", 115 draws "MART", and 113/114 draw "POKe".
-- This pattern is the one real 4-wide roofed building in Kanto that carries a
-- door and no lettering.
local FOOTPRINT = {
  {  32,  13,  13,  33 },
  {  55, 125,  58, 126 },
}

-- Which footprint columns (0-based) carry a door, matching block 58.
local DOOR_COLS = { 2 }

-- The lawn block every footprint cell is expected to be replacing.  Asserted
-- rather than assumed: if an engine update reshapes Celadon, this mod should
-- fail loudly instead of silently stamping over something that matters.
local LAWN = 85

-- ------- the interior

-- Follows SILPH_CO_1F's idiom on the FACILITY tileset: 60/61/62 top wall,
-- 68 and 70 side walls, 14 floor, and a 72/73/74 bottom wall whose 88/44/87
-- run is the doorway.  Block 44 is the two-cell-wide exit.
--
-- Sized against the camera, not the lawn: the Game Boy screen is 10x9 cells,
-- so a 7x6-block room (14x12 cells) keeps the whole lobby and its cast
-- within roughly a screen of the door.  An earlier 10x9-block version was
-- 20x18 cells -- four screens of bare floor with everyone off-camera.
local IN_W, IN_H = 7, 6
local IN_DOOR_COL = 3
local IN_BORDER = 46

-- Floor cells, derived from the walls so the NPC placements below and the
-- test's bounds check share one source of truth.
local FLOOR_MIN_X, FLOOR_MAX_X = 2, (IN_W - 2) * 2 + 1
local FLOOR_MIN_Y, FLOOR_MAX_Y = 2, (IN_H - 2) * 2 + 1

local function interiorBlocks()
  local blocks = {}
  local function put(v) blocks[#blocks + 1] = v end

  put(60)
  for _ = 2, IN_W - 1 do put(61) end
  put(62)

  for _ = 2, IN_H - 1 do
    put(68)
    for _ = 2, IN_W - 1 do put(14) end
    put(70)
  end

  put(72)
  for col = 1, IN_W - 2 do
    if col == IN_DOOR_COL - 1 then put(88)
    elseif col == IN_DOOR_COL then put(44)
    elseif col == IN_DOOR_COL + 1 then put(87)
    else put(73) end
  end
  put(74)

  return blocks
end

return function(mod)
  -- ------- Celadon: stamp the building and append its doors

  -- The base map is wired before mod entry points run (Loader:load installs
  -- registry.base ahead of _discover), and every registry op invalidates the
  -- id's cache, so read-then-patch is safe here.
  local city = mod.content.maps:get(CITY)

  -- The ROM-free fixture base carries no maps, so `modkit validate` on a
  -- fixture would otherwise fail on a nil read.  Register everything else
  -- regardless and skip only the part that needs the real Celadon.
  if not city then
    mod.log:warn("%s is absent from the base data; skipping the exterior "
      .. "patch (this is expected on a ROM-free fixture base)", CITY)
  else
    local width = city.width

    local blocks = {}
    for i, v in ipairs(city.blocks) do blocks[i] = v end

    for r, row in ipairs(FOOTPRINT) do
      for c, block in ipairs(row) do
        local col = FOOT_COL + (c - 1)
        local mapRow = FOOT_ROW + (r - 1)
        local idx = mapRow * width + col + 1
        assert(blocks[idx] == LAWN, ("%s block (%d,%d) is %s, expected lawn "
          .. "block %d -- the footprint needs re-verifying")
          :format(CITY, col, mapRow, tostring(blocks[idx]), LAWN))
        blocks[idx] = block
      end
    end

    -- Each door block warps from its own bottom-left cell, which is where
    -- the Dept. Store puts both of its warps.
    local doorY = (FOOT_ROW + #FOOTPRINT - 1) * 2 + 1

    -- Rebuild the warp list from the live base rather than restating
    -- Celadon's own warps, so an upstream change to them survives.
    local warps = {}
    for i, w in ipairs(city.warps or {}) do warps[i] = w end

    -- The indices the interior's exits point back at, paired left-to-right
    -- with the interior doorway cells so each door round-trips to itself.
    mod.cityWarpIndices = {}
    for i, col in ipairs(DOOR_COLS) do
      warps[#warps + 1] = {
        x = (FOOT_COL + col) * 2, y = doorY,
        destMap = FACILITY, destWarp = i,
      }
      mod.cityWarpIndices[i] = #warps
    end

    mod.content.maps:patch(CITY, { blocks = blocks, warps = warps })
  end

  -- ------- the interior map

  -- The interior doorway is two cells wide but the building has a single
  -- door, so both cells return to it.  Falls back to warp 1 when the
  -- exterior patch was skipped; on a fixture base there is no Celadon to
  -- return to anyway.
  local back = mod.cityWarpIndices or {}
  local backLeft = back[1] or 1
  local backRight = back[2] or backLeft
  local exitX = IN_DOOR_COL * 2
  local exitY = (IN_H - 1) * 2 + 1

  mod.content.maps:register(FACILITY, {
    id = FACILITY,
    label = "CeladonBattleFacility",
    index = 1000,
    tileset = "FACILITY",
    width = IN_W,
    height = IN_H,
    blocks = interiorBlocks(),
    borderBlock = IN_BORDER,
    -- Both cells of the doorway block exit, the way every Gen 1 interior
    -- does it, so you cannot slip past the door diagonally.  Each cell
    -- returns to the exterior door you came in by.
    warps = {
      { x = exitX, y = exitY, destMap = CITY, destWarp = backLeft },
      { x = exitX + 1, y = exitY, destMap = CITY, destWarp = backRight },
    },
    -- The cast sits one row clear of the back wall.  The camera clamps its
    -- top at y=3 in a room this tall, so NPCs on the first floor row (y=2-3)
    -- are always clipped at the screen edge; y=4 is the first row that sits
    -- comfortably in frame from the doorway.
    objects = {
      {
        index = 1,
        name = GREETER,
        sprite = "SPRITE_LINK_RECEPTIONIST",
        text = GREETER_TEXT,
        movement = "STAY", range = "DOWN",
        x = 6, y = 4,
      },
      {
        index = 2,
        name = "CBF_CLERK",
        sprite = "SPRITE_CLERK",
        text = CLERK_TEXT,
        movement = "STAY", range = "DOWN",
        x = 2, y = 4,
      },
      {
        index = 3,
        name = "CBF_ARCHIVIST",
        sprite = "SPRITE_SCIENTIST",
        text = ARCHIVIST_TEXT,
        movement = "STAY", range = "DOWN",
        x = 10, y = 4,
      },
      {
        index = 4,
        name = "CBF_ROOKIE",
        sprite = "SPRITE_YOUNGSTER",
        text = ROOKIE_TEXT,
        movement = "WALK", range = "LEFT_RIGHT",
        x = 9, y = 7,
      },
    },
    signs = {},
  })

  -- ------- the currency and the prize stock

  mod.content.items:register(TOKEN, {
    id = TOKEN,
    name = TOKEN_NAME,
    price = 0,
    tossable = false,
  })

  -- ------- the opponents

  for _, tier in ipairs(TIERS) do
    local parties = {}
    for round, roster in ipairs(ROSTERS[tier.id]) do
      local party = {}
      for _, species in ipairs(roster) do
        -- a placeholder level; the scaling hook rebuilds this per battle
        party[#party + 1] = { level = 30, species = species }
      end
      parties[round] = party
    end
    assert(#parties == tier.rounds,
      ("%s needs %d rosters, has %d"):format(tier.id, tier.rounds, #parties))

    mod.content.trainers:register(tier.class, {
      id = tier.class,
      name = tier.label .. " ACE",
      basePic = TIER_PIC[tier.id],
      baseMoney = 40 + tier.bonus * 5,
      parties = parties,
    })
  end

  -- ------- scaling: rebuild a facility party at the player's level
  --
  -- start_battle resolves a *static* registered party, so the tiers ship
  -- placeholder levels and this hook overwrites them per battle.  Doing it
  -- on trainer.party rather than in a custom command means the scaling holds
  -- however the battle was reached.

  local BY_CLASS = {}
  for _, tier in ipairs(TIERS) do BY_CLASS[tier.class] = tier end

  local function averagePartyLevel(game)
    local party = game and game.save and game.save.party
    if not party or #party == 0 then return 15 end
    local total = 0
    for _, mon in ipairs(party) do total = total + (mon.level or 5) end
    return math.floor(total / #party + 0.5)
  end

  mod.hooks:wrap("trainer.party", function(next, oppClass, partyIndex, party)
    local tier = BY_CLASS[oppClass]
    if not tier then return next(oppClass, partyIndex, party) end

    local base = averagePartyLevel(mod.game) + tier.bonus
    -- the last round of a tier is its champion, a touch above the rest
    local level = base + (partyIndex == tier.rounds and 2 or 0)
    level = math.max(2, math.min(100, level))

    local scaled = {}
    for i, slot in ipairs(party) do
      scaled[i] = { species = slot.species, level = level }
    end
    return next(oppClass, partyIndex, scaled)
  end)

  -- ------- progress, kept in the mod's own save bucket

  local function bests()
    local stored = mod.save:get("bests")
    if type(stored) ~= "table" then
      stored = {}
      mod.save:set("bests", stored)
    end
    return stored
  end

  local function cleared(tierId)
    return bests()[tierId] ~= nil
  end

  -- Bronze is always open; each later tier needs the one before it cleared.
  local function unlocked(tierId)
    for i, tier in ipairs(TIERS) do
      if tier.id == tierId then
        return i == 1 or cleared(TIERS[i - 1].id)
      end
    end
    return false
  end

  -- Another mod reads these with mod.find("celadon_battle_facility").exports.
  -- Assigned field by field, the way the gallery does it, rather than
  -- replacing the table the loader handed us.
  mod.exports.bests = function() return bests() end
  mod.exports.cleared = cleared
  mod.exports.unlocked = unlocked
  mod.exports.tiers = function() return TIERS end
  -- the walkable rectangle of the lobby, so tests and any companion mod
  -- placing its own NPC agree on where the floor is
  mod.exports.floor = function()
    return { minX = FLOOR_MIN_X, maxX = FLOOR_MAX_X,
             minY = FLOOR_MIN_Y, maxY = FLOOR_MAX_Y }
  end

  -- ------- custom verbs the gauntlet script needs
  --
  -- Scripts are data rows, so anything that has to touch mod.save goes
  -- through a registered command.

  -- cbf_gate <tierId>: lastCheck = the tier is open to the player
  mod.content.commands:register("cbf_gate", function(ctx, tierId)
    ctx.lastCheck = unlocked(tierId)
  end)

  -- cbf_streak <n>: remember how far into the current run the player got,
  -- so a loss still records a best-effort streak
  mod.content.commands:register("cbf_streak", function(_, n)
    mod.save:set("run_streak", n)
  end)

  -- cbf_clear <tierId>: the tier is beaten; record the win and the run
  mod.content.commands:register("cbf_clear", function(_, tierId)
    local tier = tierById(tierId)
    local table_ = bests()
    local wins = (table_[tierId] or 0) + 1
    table_[tierId] = wins
    mod.save:set("bests", table_)
    local best = mod.save:get("best_streak", 0)
    if tier and tier.rounds > best then mod.save:set("best_streak", tier.rounds) end
  end)

  -- cbf_pick <n>: lastCheck = the previous `choice` landed on option n.
  -- `choice` only reports "was it the first option" on its own.
  mod.content.commands:register("cbf_pick", function(ctx, n)
    ctx.lastCheck = (ctx.lastChoice and ctx.lastChoice.index) == n
  end)

  -- cbf_afford <n>: lastCheck = the player holds at least n tokens
  mod.content.commands:register("cbf_afford", function(ctx, n)
    ctx.lastCheck = (ctx.save.inventory[TOKEN] or 0) >= n
  end)

  -- ------- the gauntlet script
  --
  -- Rows are data, so the ladder is generated rather than written out three
  -- times.  ScriptRunner resolves `label` targets, so each tier's rounds can
  -- share one loss path.

  local function tierBranch(rows, tier)
    local function add(row) rows[#rows + 1] = row end
    local locked = tier.id .. "_locked"
    local lost = tier.id .. "_lost"
    local won = tier.id .. "_won"

    add({ "label", tier.id })
    add({ "cbf_gate", tier.id })
    add({ "jump_if_false", locked })
    add({ "show_text", ("The %s CHALLENGE!\n%d battles, back\vto back.\f"
      .. "No healing until\nit is over. Good\vluck!"):format(tier.label, tier.rounds) })

    for round = 1, tier.rounds do
      add({ "show_text", ("ROUND %d of %d!"):format(round, tier.rounds) })
      add({ "cbf_streak", round - 1 })
      add({ "start_battle", "trainer", tier.class, round })
      add({ "jump_if_false", lost })
    end

    add({ "label", won })
    add({ "cbf_clear", tier.id })
    add({ "cbf_streak", tier.rounds })
    add({ "heal_party" })
    add({ "show_text", ("A perfect run!\nThe %s tier is\vyours."):format(tier.label) })
    add({ "give_item", TOKEN, TOKEN_AWARD[tier.id] })
    add({ "show_text", "Your POKeMON have\nbeen restored.\f"
      .. "Spend your BATTLE\nPT at the counter." })
    add({ "jump", "end" })

    add({ "label", lost })
    add({ "heal_party" })
    add({ "show_text", "Your challenge\nends here.\f"
      .. "Your POKeMON have\nbeen restored.\vCome back stronger!" })
    add({ "jump", "end" })

    add({ "label", locked })
    add({ "show_text", ("The %s tier is\nnot open to you\vyet.\f"
      .. "Clear the tier\nbefore it first."):format(tier.label) })
    add({ "jump", "end" })
  end

  local function greeterScript()
    local rows = {}
    local function add(row) rows[#rows + 1] = row end

    add({ "face_player" })
    add({ "show_text", "Welcome to the\nBATTLE FACILITY!\f"
      .. "Trainers here\nbattle back to\vback, with no\fchance to heal in\n"
      .. "between." })

    -- One yes/no per tier, hardest first, so a player who wants GOLD is not
    -- walked through three prompts.  `choice` would be tidier, but yes/no is
    -- the primitive every Gen 1 script already uses.
    for i = #TIERS, 1, -1 do
      local tier = TIERS[i]
      add({ "ask", ("Take on the %s\nchallenge?"):format(tier.label) })
      add({ "jump_if_true", tier.id })
    end

    add({ "show_text", "Come back when\nyou're ready." })
    add({ "jump", "end" })

    for _, tier in ipairs(TIERS) do tierBranch(rows, tier) end
    return rows
  end

  -- ------- the prize counter

  local function clerkScript()
    local rows = {}
    local function add(row) rows[#rows + 1] = row end

    local labels = {}
    for i, prize in ipairs(PRIZES) do
      labels[i] = ("%s  %d"):format(prize.label, prize.cost)
    end
    labels[#labels + 1] = "CANCEL"

    add({ "face_player" })
    add({ "show_text", "Trade BATTLE PT\nfor prizes here." })
    add({ "choice", labels })

    for i, prize in ipairs(PRIZES) do
      add({ "cbf_pick", i })
      add({ "jump_if_true", "buy_" .. prize.item })
    end
    add({ "jump", "done" })

    for _, prize in ipairs(PRIZES) do
      add({ "label", "buy_" .. prize.item })
      add({ "cbf_afford", prize.cost })
      add({ "jump_if_false", "broke" })
      -- take payment only once the bag has accepted the goods: give_item
      -- halts the script when the bag is full, so this order cannot charge
      -- for an item the player never received
      add({ "give_item", prize.item, 1 })
      add({ "take_item", TOKEN, prize.cost })
      add({ "show_text", "Thank you!" })
      add({ "jump", "done" })
    end

    add({ "label", "broke" })
    add({ "show_text", "You don't have\nenough BATTLE PT." })
    add({ "jump", "done" })

    add({ "label", "done" })
    add({ "show_text", "Come again!" })
    return rows
  end

  -- ------- the records board

  mod.content.screens:register(RECORDS_SCREEN, {
    new = function(game)
      local Font = mod.ui.Font
      local state = { game = game, isOpaque = true }

      function state:update()
        local input = game.input
        if not input then return end
        if input:wasPressed("a") or input:wasPressed("b")
           or input:wasPressed("start") then
          game.stack:pop()
        end
      end

      function state:draw()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 160, 144)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw("HALL OF RECORDS", 8, 8)
        local won = bests()
        local y = 32
        for _, tier in ipairs(TIERS) do
          local wins = won[tier.id]
          Font.draw(tier.label, 16, y)
          Font.draw(wins and ("CLEARED x" .. wins)
            or (unlocked(tier.id) and "OPEN" or "LOCKED"), 80, y)
          y = y + 16
        end
        -- "BEST RUN" is 8 glyphs at 8px from x=16, so it ends exactly on 80;
        -- the value needs 88 to leave a space rather than read as "RUN0"
        Font.draw("BEST RUN", 16, y + 8)
        Font.draw(tostring(mod.save:get("best_streak", 0)), 88, y + 8)
        Font.draw("PRESS A", 52, 120)
      end

      return state
    end,
  })

  mod.content.map_scripts:register(FACILITY, {
    talk = {
      [GREETER_TEXT] = greeterScript(),
      [CLERK_TEXT] = clerkScript(),
      [ARCHIVIST_TEXT] = {
        { "face_player" },
        { "show_text", "I keep the records\nof every challenge\vrun here." },
        { "push_screen", RECORDS_SCREEN },
      },
      [ROOKIE_TEXT] = {
        { "show_text", "Seven straight\nbattles with no\vhealing?\f"
          .. "I got through two.\nI'll train more\vand come back!" },
      },
    },
  })

  -- the scaling hook needs the live Game; game.ready is where it arrives
  mod.events:on("game.ready", function(ev) mod.game = ev.game end)
end

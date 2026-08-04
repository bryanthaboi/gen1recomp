-- Gift NPCs and in-game trades.  Each cites its pokered source.

local M = {}

local function text(game) return game.data.text end

local function push(game, s, done)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, done))
end

-- fill the extracted text placeholders ({RAM:...}, {PLAYER})
local function fill(s, subs)
  s = s:gsub("{PLAYER}", subs.player or "")
  s = s:gsub("{RAM:[^}]*}", function() return subs.ram or "" end)
  return s
end

-- One-time item gift, following the original text_asm flow:
-- pre text (optional) -> GiveItem (bag-full refusal keeps the flag
-- unset, talk again after making room) -> received text -> optional
-- explanation; repeat visits get the already text.
local function gift(opts)
  return function(game, ow, npc, done)
    local t = text(game)
    local itemName = game.data.items[opts.item].name
    local subs = { ram = itemName, player = game.save.player.name }
    local function say(label, fallback, cb)
      push(game, fill(t[label] or fallback, subs), cb)
    end
    if game.save.flags[opts.flag] then
      say(opts.already or opts.explain, "It's a useful\nitem, isn't it?", done)
      return
    end
    local function give()
      if not require("src.inventory.Bag").add(game.save, opts.item, 1) then
        say(opts.noRoom, "You have no room\nfor this item!", done)
        return
      end
      game.save.flags[opts.flag] = true
      local idef = game.data.items[opts.item]
      require("src.core.Sound").play(game.data,
        (idef and idef.keyItem) and "Get_Key_Item" or "Get_Item1")
      say(opts.received, "{PLAYER} received\n{RAM:}!", function()
        if opts.explain then
          say(opts.explain, "", done)
        else
          done()
        end
      end)
    end
    if opts.pre then say(opts.pre, "", give) else give() end
  end
end

-- Coin Case (scripts/CeladonDiner.asm, the busted gym guide)
M.CELADON_DINER = {
  talk = {
    TEXT_CELADONDINER_GYM_GUIDE = gift({
      flag = "EVENT_GOT_COIN_CASE", item = "COIN_CASE",
      pre = "_CeladonDinerGymGuideImFlatOutBustedText",
      received = "_CeladonDinerGymGuideReceivedCoinCaseText",
      noRoom = "_CeladonDinerGymGuideCoinCaseNoRoomText",
      already = "_CeladonDinerGymGuideWinItBackText",
    }),
  },
}

-- TM18 Counter (scripts/CeladonMart3F.asm, the TV-game-shop clerk)
M.CELADON_MART_3F = {
  talk = {
    TEXT_CELADONMART3F_CLERK = gift({
      flag = "EVENT_GOT_TM18", item = "TM_COUNTER",
      pre = "_CeladonMart3FClerkTM18PreReceiveText",
      received = "_CeladonMart3FClerkReceivedTM18Text",
      explain = "_CeladonMart3FClerkTM18ExplanationText",
      noRoom = "_CeladonMart3FClerkTM18NoRoomText",
    }),
  },
}

-- TM39 Swift (scripts/Route12Gate2F.asm)
M.ROUTE_12_GATE_2F = {
  talk = {
    TEXT_ROUTE12GATE2F_BRUNETTE_GIRL = gift({
      flag = "EVENT_GOT_TM39", item = "TM_SWIFT",
      pre = "_Route12Gate2FBrunetteGirlYouCanHaveThisText",
      received = "_Route12Gate2FBrunetteGirlReceivedTM39Text",
      explain = "_Route12Gate2FBrunetteGirlTM39ExplanationText",
      noRoom = "_Route12Gate2FBrunetteGirlTM39NoRoomText",
    }),
  },
}

-- TM41 Softboiled (scripts/CeladonCity.asm, Gramps3)
M.CELADON_CITY = {
  talk = {
    TEXT_CELADONCITY_GRAMPS3 = gift({
      flag = "EVENT_GOT_TM41", item = "TM_SOFTBOILED",
      pre = "_CeladonCityGramps3Text",
      received = "_CeladonCityGramps3ReceivedTM41Text",
      explain = "_CeladonCityGramps3TM41ExplanationText",
      noRoom = "_CeladonCityGramps3TM41NoRoomText",
    }),
  },
}

-- TM35 Metronome (scripts/CinnabarLabMetronomeRoom.asm)
M.CINNABAR_LAB_METRONOME_ROOM = {
  talk = {
    TEXT_CINNABARLABMETRONOMEROOM_SCIENTIST1 = gift({
      flag = "EVENT_GOT_TM35", item = "TM_METRONOME",
      pre = "_CinnabarLabMetronomeRoomScientist1Text",
      received = "_CinnabarLabMetronomeRoomScientist1ReceivedTM35Text",
      explain = "_CinnabarLabMetronomeRoomScientist1TM35ExplanationText",
      noRoom = "_CinnabarLabMetronomeRoomScientist1TM35NoRoomText",
    }),
  },
}

-- TM42 Dream Eater (scripts/ViridianCity.asm, the fisher; no pre text)
M.VIRIDIAN_CITY = {
  talk = {
    TEXT_VIRIDIANCITY_FISHER = gift({
      flag = "EVENT_GOT_TM42", item = "TM_DREAM_EATER",
      received = "_ViridianCityFisherReceivedTM42Text",
      explain = "_ViridianCityFisherTM42ExplanationText",
      noRoom = "_ViridianCityFisherTM42NoRoomText",
    }),
  },
}

-- TM36 Selfdestruct (scripts/SilphCo2F.asm, the rescued worker)
M.SILPH_CO_2F = {
  talk = {
    TEXT_SILPHCO2F_SILPH_WORKER_F = gift({
      flag = "EVENT_GOT_TM36", item = "TM_SELFDESTRUCT",
      -- the label carries no leading underscore: pokered keeps this one in
      -- the script bank, not the far-text bank (#393)
      pre = "SilphCo2FSilphWorkerFPleaseTakeThisText",
      received = "_SilphCo2FSilphWorkerFReceivedTM36Text",
      explain = "_SilphCo2FSilphWorkerFTM36ExplanationText",
      noRoom = "_SilphCo2FSilphWorkerFTM36NoRoomText",
    }),
  },
}

-- Free POTION sample (scripts/Route1.asm; the original burns the flag
-- even on a full bag -- we keep the port's kinder halt-and-retry)
M.ROUTE_1 = {
  talk = {
    TEXT_ROUTE1_YOUNGSTER1 = gift({
      flag = "EVENT_GOT_POTION_SAMPLE", item = "POTION",
      pre = "_Route1Youngster1MartSampleText",
      received = "_Route1Youngster1GotPotionText",
      noRoom = "_Route1Youngster1NoRoomText",
      already = "_Route1Youngster1AlsoGotPokeballsText",
    }),
  },
}

-- The three in-game trades the port was missing (data/events/trades.asm
-- indices are 1-based in data/generated/field.lua trades)
M.ROUTE_11_GATE_2F = {
  talk = {
    TEXT_ROUTE11GATE2F_YOUNGSTER = {
      { "face_player" },
      { "trade", 1, "EVENT_TRADED_NIDORINO_FOR_NIDORINA" }, -- TERRY
    },
  },
}

M.ROUTE_18_GATE_2F = {
  talk = {
    TEXT_ROUTE18GATE2F_YOUNGSTER = {
      { "face_player" },
      { "trade", 6, "EVENT_TRADED_SLOWBRO_FOR_LICKITUNG" }, -- MARC
    },
    -- Yellow replaces the youngster with a cook trading SPIKE
    -- (TANGELA -> PARASECT): pokeyellow/scripts/Route18Gate2F.asm
    -- Route18Gate2FCookText runs TRADE_FOR_SPIKE, index 6 in the Yellow
    -- TradeMons table that Data:applyVersionedFieldData swaps in.  Red
    -- maps have no COOK object here and Yellow maps have no YOUNGSTER,
    -- so each version only ever fires its own row (#651).  Both rows
    -- share the Red-flavoured done flag on purpose: a .sav tracks
    -- "trade slot 6 completed" in one wCompletedInGameTradeFlags bit
    -- either version reads, and the save codec maps that bit to this
    -- flag name (src/save_convert/GenSave.lua EXTRA_FLAG_BITS).
    TEXT_ROUTE18GATE2F_COOK = {
      { "face_player" },
      { "trade", 6, "EVENT_TRADED_SLOWBRO_FOR_LICKITUNG" }, -- SPIKE (Yellow)
    },
  },
}

M.UNDERGROUND_PATH_ROUTE_5 = {
  talk = {
    TEXT_UNDERGROUNDPATHROUTE5_LITTLE_GIRL = {
      { "face_player" },
      { "trade", 10, "EVENT_TRADED_NIDORAN_M_FOR_NIDORAN_F" }, -- SPOT
    },
  },
}

-- =====================================================================
-- Progression gates and rival ambushes
-- =====================================================================

local function inCoords(coords, x, y)
  for _, c in ipairs(coords) do
    if x == c[1] and y == c[2] then return true end
  end
  return false
end

-- coordinate block: show a line and shove the player back one step.  pokered
-- shoves with a SIMULATED JOYPAD press (scripts/ViridianCity.asm ViridianCity-
-- CheckGymOpenScript), which runs the normal overworld step pipeline including
-- HandleLedges (engine/overworld/ledges.asm), so the shove must HOP a ledge
-- when one sits in front: the tile below the Viridian Gym door is a down-ledge
-- (#151).  Gates with no ledge in front (Cinnabar gym lock at (18,4)) get
-- checkLedgeHop == false and fall back to the plain forced step, unchanged.
local function stepGate(opts)
  return function(game, ow, x, y)
    if not inCoords(opts.coords, x, y) then return false end
    if not opts.blocked(game) then return false end
    require("src.core.Sound").play(game.data, "Denied")
    push(game, text(game)[opts.text] or opts.fallback, function()
      ow.player.facing = opts.push
      if not ow:checkLedgeHop(opts.push) then
        ow:scriptMove(ow.player, opts.push, 1)
      end
    end)
    return true
  end
end

-- Viridian Gym stays locked until the seven other badges are earned
-- (scripts/ViridianCity.asm ViridianCityCheckGymOpenScript: wObtained-
-- Badges == ~EARTHBADGE at (32,8) shoves the player off the door)
local SEVEN_BADGES = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE",
                       "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
                       "VOLCANOBADGE" }
local viridianGymLock = stepGate({
  coords = { { 32, 8 } },
  blocked = function(game)
    for _, b in ipairs(SEVEN_BADGES) do
      if not game.save.inventory[b] then return true end
    end
    return false
  end,
  text = "_ViridianCityGymLockedText",
  fallback = "The GYM's doors\nare locked...",
  push = "down",
})

-- story.lua's VIRIDIAN_CITY module owns the sleeping-old-man block;
-- chain it behind the gym lock (the registry keeps one onStep per map)
local viridianOldManStep = require("data.scripts.story").VIRIDIAN_CITY.onStep
M.VIRIDIAN_CITY.onStep = function(game, ow, x, y)
  if viridianGymLock(game, ow, x, y) then return true end
  return viridianOldManStep(game, ow, x, y)
end

-- Cinnabar Gym needs the SECRET KEY (scripts/CinnabarIsland.asm)
M.CINNABAR_ISLAND = {
  onStep = stepGate({
    coords = { { 18, 4 } },
    blocked = function(game) return not game.save.inventory.SECRET_KEY end,
    text = "_CinnabarIslandDoorIsLockedText",
    fallback = "The door is\nlocked...",
    push = "down",
  }),
  -- CinnabarIsland_Script line 6: ResetEvent EVENT_LAB_STILL_REVIVING_
  -- FOSSIL on every (re)load of this map -- OverworldState:setMap runs
  -- onEnter on every entry, not just the first, so this fires both
  -- when the player walks out of the fossil lab back onto the island
  -- and on any later re-entry (boat, Mansion exit, etc.), matching the
  -- oracle's every-load map script.  Paired with the deposit/pending/
  -- ready state machine in data/scripts/story2.lua's
  -- TEXT_CINNABARLABFOSSILROOM_SCIENTIST1.
  onEnter = function(game, ow)
    if game.save.flags.EVENT_LAB_STILL_REVIVING_FOSSIL then
      game.save.flags.EVENT_LAB_STILL_REVIVING_FOSSIL = nil
    end
  end,
}

-- Pewter's youngster stops you leaving east before Brock is beaten and
-- escorts you to the gym (scripts/PewterCity.asm
-- PewterCityCheckPlayerLeavingEastScript /
-- PewterCityYoungsterShowsPlayerGymScript, engine/overworld/auto_movement.asm
-- PewterGymGuyMovementScriptPointerTable, engine/events/pewter_guys.asm
-- PewterGymGuyCoords).  Same lockstep style as Oak's lab escort: the
-- youngster walks RLEList_PewterGymGuy while the player plays the
-- reverse of RLEList_PewterGymPlayer with a PewterGuys positioning
-- preamble.  Ends at (11,18) / (12,18) by the gym, not phasing through
-- the building.
local pewterEscort = {}

-- RLEList_PewterGymGuy (NPC directions play forward)
pewterEscort.guySteps = {
  "down", "down",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left", "left", "left", "left", "left",
  "up", "up", "up", "up", "up",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left",
  "down", "down", "down", "down", "down",
  "right", "right", "right",
}

-- Reverse of guySteps with opposite facings, i.e. the gym-to-spawn
-- mirror of RLEList_PewterGymGuy.  Kept as the documented inverse that
-- tests/parity_pewter_escort.lua checks; the youngster does NOT walk it
-- home any more, because its first step is LEFT through the player
-- parked on (11,18) (#241).  See walkHome below.
do
  local opp = { up = "down", down = "up", left = "right", right = "left" }
  local ret = {}
  for i = #pewterEscort.guySteps, 1, -1 do
    ret[#ret + 1] = opp[pewterEscort.guySteps[i]]
  end
  pewterEscort.guyReturnSteps = ret
end

-- RLEList_PewterGymPlayer before reverse / PewterGuys (NO_INPUT, RIGHT×2,
-- DOWN×5, LEFT×11, UP×5, LEFT×15)
pewterEscort.playerRle = {
  "NO",
  "right", "right",
  "down", "down", "down", "down", "down",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left",
  "up", "up", "up", "up", "up",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left", "left", "left", "left", "left",
}

-- PewterGymGuyCoords: (x, y) -> positioning moves written after the RLE
-- (played in reverse; $00 pauses are one overworld frame ≈ 1/8 tile for
-- the NPC, so eight of them ≈ one guy head-start step)
pewterEscort.preambles = {
  ["34,16"] = { "left", "down", "down", "right" },
  ["35,17"] = { "left", "down", "right", "left" },
  ["37,18"] = { "left", "left", "left",
                "NO", "NO", "NO", "NO", "NO", "NO", "NO", "NO" },
  ["37,19"] = { "left", "left", "up", "left" },
  ["36,17"] = { "left", "down", "left",
                "NO", "NO", "NO", "NO", "NO", "NO", "NO", "NO" },
}

-- Realized player path for a trigger tile: PewterGuys overwrites the
-- last RLE byte and appends the preamble, then simulated joypad plays
-- high→low (reverse).  Leading NO×8 collapses to guyHeadStart=1; the
-- trailing end-of-list NO is dropped (one-frame pause).
function pewterEscort.playerPlan(x, y)
  local pre = pewterEscort.preambles[x .. "," .. y]
  if not pre then return nil end
  local buf = {}
  for i, d in ipairs(pewterEscort.playerRle) do buf[i] = d end
  buf[#buf] = pre[1]
  for i = 2, #pre do buf[#buf + 1] = pre[i] end
  local path = {}
  for i = #buf, 1, -1 do path[#path + 1] = buf[i] end
  local head = 0
  while path[head + 1] == "NO" do head = head + 1 end
  local tail = #path
  while tail > head and path[tail] == "NO" do tail = tail - 1 end
  local steps = {}
  for i = head + 1, tail do steps[#steps + 1] = path[i] end
  return { steps = steps, guyHeadStart = math.floor(head / 8) }
end

local function pewterGymEscort(game, ow)
  if ow.runner:isRunning() or #ow.scriptMoves > 0 then return end
  local x, y = ow.player.cellX, ow.player.cellY
  local plan = pewterEscort.playerPlan(x, y)
  local Music = require("src.core.Music")
  local t = text(game)
  local follow = t._PewterCityYoungsterYoureATrainerFollowMeText
    or "You're a trainer\nright? BROCK's\nlooking for new\nchallengers!\nFollow me!"
  -- PewterGuys only has entries for five tiles; an unmatched talk tile
  -- (e.g. (36,16) east of him) just gets the follow-me line, same as a
  -- failed coords lookup would refuse to arm the walk.
  if not plan then
    push(game, follow)
    return
  end
  local guy = ow:npcByIndex(5) -- PEWTERCITY_YOUNGSTER
  local guySteps = pewterEscort.guySteps
  local head = plan.guyHeadStart

  -- After the walk: face the player, restore map music, "Go take on
  -- BROCK", then MovementData_PewterGymGuyExit -- five steps RIGHT out of
  -- (12,18), the cell PewterCityYoungsterShowsPlayerGymScript pins him to
  -- with SetSpritePosition1 (hSpriteMapXCoord 16 / hSpriteMapYCoord 22,
  -- minus the +4 border offset object_event coords carry per
  -- macros/scripts/maps.asm) and exactly where the escort leaves him.
  -- That lands him on (17,18), the last walkable cell before the fence at
  -- (18,18) and one column past the screen edge with the player parked on
  -- (11,18).  PewterCityHideYoungsterScript then HideObject's him and
  -- PewterCityResetYoungsterScript's SetSpritePosition2 + ShowObject put
  -- him back on his object_event spawn (35,16) facing DOWN, which is the
  -- snap below (the vanish/reappear is off screen, same as the original).
  --
  -- The old code retraced guyReturnSteps instead, whose first step is
  -- LEFT into (11,18) -- the cell the player is standing on -- and
  -- scriptMove is a pure tween with no entity test, so he walked straight
  -- through Red (#241).  There is no honest route home: (17,18) is a
  -- dead-end pocket ((18,18) fence, (17,17) wall), which is precisely why
  -- the original teleports.  guyReturnSteps stays as the documented
  -- mirror of RLEList_PewterGymGuy that parity_pewter_escort asserts.
  -- Brock victory still HideObject's him.
  local function walkHome()
    if not guy then return end
    local i = 0
    local function tick()
      i = i + 1
      if i > 5 then
        -- SetSpritePosition2: same field writes as Commands.place_npc,
        -- including the target clear -- a stale targetX/targetY would
        -- leave OverworldState:npcAtCell reserving (17,18) forever and
        -- silently wall the player out of that pocket.
        guy.cellX, guy.cellY = 35, 16
        guy.px, guy.py = 35 * 16, 16 * 16
        guy.moving = false
        guy.targetX, guy.targetY = nil, nil
        guy.facing = "down"
        return
      end
      ow:scriptMove(guy, "right", 1, tick)
    end
    tick()
  end

  local function afterWalk()
    if guy then guy.facing = "left" end
    Music.playMap(game.data, "PEWTER_CITY")
    push(game, t._PewterCityYoungsterGoTakeOnBrockText
      or "Go take on BROCK\nat the GYM first!", walkHome)
  end

  local function lockstep()
    local i = 0
    local function tick()
      i = i + 1
      local ps = plan.steps[i]
      if not ps then
        afterWalk()
        return
      end
      local gs = guySteps[head + i]
      if guy and gs then ow:scriptMove(guy, gs, 1) end
      ow:scriptMove(ow.player, ps, 1, tick)
    end
    tick()
  end

  local function beginWalk()
    Music.play(game.data, "Music_MuseumGuy")
    if guy and head > 0 then
      local h = 0
      local function headTick()
        h = h + 1
        if h > head then lockstep(); return end
        ow:scriptMove(guy, guySteps[h], 1, headTick)
      end
      headTick()
    else
      lockstep()
    end
  end

  push(game, follow, beginWalk)
end

M.PEWTER_CITY = {
  escort = pewterEscort,
  -- PewterCityYoungsterText: talking also arms the gym escort script
  talk = {
    TEXT_PEWTERCITY_YOUNGSTER = function(game, ow, npc, done)
      pewterGymEscort(game, ow)
      if done then done() end
    end,
  },
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_BROCK then return false end
    if ow.runner:isRunning() or #ow.scriptMoves > 0 then return false end
    if not inCoords({ { 35, 17 }, { 36, 17 }, { 37, 18 }, { 37, 19 } }, x, y) then
      return false
    end
    pewterGymEscort(game, ow)
    return true
  end,
}

-- Rival ambush: show the hidden rival, walk him up to the player, run
-- the battle rows, march him back and hide him.  On a loss the walk is
-- skipped (the blackout rebuilds the map mid-script).
local function runAmbush(game, ow, rows, playerFacing)
  if ow.runner:isRunning() then return false end
  ow.player.facing = playerFacing
  -- the rival encounter sting (MUSIC_MEET_RIVAL); the battle music
  -- takes over and the map theme returns after the victory jingle
  require("src.core.Music").play(game.data, "Music_MeetRival")
  ow.runner:run(rows)
  return true
end

-- Route 22 rival, both visits (scripts/Route22.asm).  pokered arms
-- EVENT_ROUTE22_RIVAL_WANTS_BATTLE in Oak's lab (expired by Pewter
-- Gym) and again in Viridian Gym; we derive the same windows from the
-- surrounding story flags so old saves work too.
-- Rival1Exit → Viridian (right/down); Rival2Exit → League (left).
-- Both exit lists are keyed on wSavedCoordIndex -- WHICH entry of
-- Route22DefaultScript.Route22RivalBattleCoords the player matched -- not
-- on where the rival ended up.  CheckCoords (home/map_objects.asm:107)
-- zeroes wCoordIndex and `inc [hl]` BEFORE each compare, so the first
-- entry reports 1: index 1 is (29,4), index 2 is (29,5).
-- Route22Rival1AfterBattleScript (Route22.asm:175) takes
-- ...ExitMovementData1 on index 1 and ...Data2 otherwise.  From the top
-- tile the rival stands BELOW the player on (29,5) and leaves east along
-- row 5; from the bottom tile he stands LEFT of him on (28,5) and has to
-- step UP to row 4 to get around him.  The port had the two branches
-- swapped, so the top tile started the walk with UP out of (28,4) into
-- the cliff cell (28,3), which is not walkable (#236).
local function route22ExitDirs(n, py)
  if n == 2 then
    -- Route22Rival2ExitMovementData1 falls through into ...Data2: LEFT x4
    -- from (29,5), LEFT x3 from (28,5), both back onto the spawn (25,5).
    if py == 4 then return { "left", "left", "left", "left" } end
    return { "left", "left", "left" }
  end
  -- Route22Rival1ExitMovementData1: (29,5) -> (31,5) -> (31,10)
  if py == 4 then
    return { "right", "right", "down", "down", "down", "down", "down" }
  end
  -- Route22Rival1ExitMovementData2: (28,5) -> (28,4) -> (31,4) -> (31,10)
  return { "up", "right", "right", "right",
           "down", "down", "down", "down", "down", "down" }
end

local function route22Scene(n, objIndex, objName, oppClass, baseParty, beatFlag, py)
  -- Route22MoveRivalRightScript (Route22.asm:39) walks him RIGHT along his
  -- own row from the object_event spawn (25,5): the full four-RIGHT
  -- Route22RivalMovementData on coord index 1 (player on (29,4)), so he
  -- stops BELOW the player on (29,5); `inc de` drops one RIGHT on index 2
  -- (player on (29,5)), so he stops LEFT of him on (28,5).  He never
  -- leaves row 5.  Route22Rival{1,2}StartBattleScript (Route22.asm:110)
  -- then faces him UP on index 1 and RIGHT otherwise (#236).
  local rx = (py == 4) and 29 or 28
  local rivalFacing = (py == 4) and "up" or "right"
  return {
    { "show_object", "ROUTE_22", objName },                    -- 1
    { "move_npc_to", objIndex, rx, 5 },                        -- 2
    { "face_object", objIndex, rivalFacing },                  -- 3
    { "show_text", "_Route22RivalBeforeBattleText" .. n },     -- 4
    { "rival_battle", oppClass, baseParty },                   -- 5
    { "jump_if_false", 11 },                                   -- 6
    { "set_flag", beatFlag },                                  -- 7
    { "show_text", "_Route22Rival" .. n .. "DefeatedText" },   -- 8
    { "show_text", "_Route22RivalAfterBattleText" .. n },      -- 9
    { "walk_npc", objIndex, route22ExitDirs(n, py) },          -- 10
    { "hide_object", "ROUTE_22", objName },                    -- 11
  }
end

-- Route22Rival{1,2}StartBattleScript turns the player toward him too:
-- PLAYER_DIR_DOWN on coord index 1 (the (29,4) tile, rival below him),
-- and the PLAYER_DIR_LEFT Route22DefaultScript already set on index 2
-- (the (29,5) tile, rival to his left) (#236).
M.ROUTE_22 = {
  onStep = function(game, ow, x, y)
    if not inCoords({ { 29, 4 }, { 29, 5 } }, x, y) then return false end
    local f = game.save.flags
    local playerFacing = (y == 4) and "down" or "left"
    if f.EVENT_GOT_POKEDEX and not f.EVENT_BEAT_BROCK
       and not f.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE then
      return runAmbush(game, ow,
        route22Scene(1, 1, "ROUTE22_RIVAL1", "OPP_RIVAL1", 4,
                     "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE", y), playerFacing)
    end
    if f.EVENT_BEAT_GIOVANNI and not f.EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE then
      return runAmbush(game, ow,
        route22Scene(2, 2, "ROUTE22_RIVAL2", "OPP_RIVAL2", 10,
                     "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE", y), playerFacing)
    end
    return false
  end,
}

-- Cerulean City: the Nugget Bridge rival ambush (CeruleanCityCoords2),
-- the TM28 rocket thief with his forced-fight cells (Coords1), and the
-- cave guard who steps aside once you are Champion.
-- Post-battle: Bill text then CeruleanCityMovement3/4 into town.
local function ceruleanRivalExitDirs(px)
  if px == 20 then
    return { "right", "down", "down", "down", "down", "down", "down" }
  end
  return { "left", "down", "down", "down", "down", "down", "down" }
end

local function ceruleanRivalScene(px, py)
  return {
    { "show_object", "CERULEAN_CITY", "CERULEANCITY_RIVAL" },  -- 1
    { "move_npc_to", 1, px, py - 1 },                          -- 2
    { "face_object", 1, "down" },                              -- 3
    { "show_text", "_CeruleanCityRivalPreBattleText" },        -- 4
    { "rival_battle", "OPP_RIVAL1", 7 },                       -- 5
    { "jump_if_false", 11 },                                   -- 6
    { "set_flag", "EVENT_BEAT_CERULEAN_RIVAL" },               -- 7
    { "show_text", "_CeruleanCityRivalDefeatedText" },         -- 8
    { "show_text", "_CeruleanCityRivalIWentToBillsText" },     -- 9
    { "walk_npc", 1, ceruleanRivalExitDirs(px) },              -- 10
    { "hide_object", "CERULEAN_CITY", "CERULEANCITY_RIVAL" },  -- 11
  }
end

-- scripts/CeruleanCity.asm CeruleanCityRocketText: fight the thief,
-- then he returns TM28 (DIG) and hurries off.  CeruleanHideRocket
-- (CeruleanCity_2.asm) is GBFadeOutToBlack → Show GUARD1 / Hide GUARD2 /
-- Hide ROCKET → GBFadeInFromBlack -- not a bare hide_object.
local rocketRows = {
  { "face_player" },                                           -- 1
  { "check_flag", "EVENT_GOT_TM28" },                          -- 2
  { "jump_if_true", 15 },                                      -- 3 → CeruleanHideRocket
  { "check_flag", "EVENT_BEAT_CERULEAN_ROCKET_THIEF" },        -- 4
  { "jump_if_true", 9 },                                       -- 5
  { "show_text", "_CeruleanCityRocketText" },                  -- 6
  { "start_battle", "trainer", "OPP_ROCKET", 5 },              -- 7
  { "jump_if_false", "end" },                                  -- 8
  { "show_text", "_CeruleanCityRocketIllReturnTheTMText" },    -- 9
  { "set_flag", "EVENT_BEAT_CERULEAN_ROCKET_THIEF" },          -- 10
  { "give_item", "TM_DIG", 1, false },                         -- 11 (row 13 prints)
  { "set_flag", "EVENT_GOT_TM28" },                            -- 12
  { "show_text", "_CeruleanCityRocketReceivedTM28Text" },      -- 13
  { "show_text", "_CeruleanCityRocketIBetterGetMovingText" },  -- 14
  { "fade", "out" },                                           -- 15 GBFadeOutToBlack
  -- CeruleanHideRocket while black: GUARD1 (28,12) appears, GUARD2
  -- (27,12) and the ROCKET go.  GUARD2 blocks the trashed-house south
  -- door neighbour -- the swap reconnects the city (Bill's ticket does
  -- the same in story.lua; either route is enough).
  { "show_object", "CERULEAN_CITY", "CERULEANCITY_GUARD1" },   -- 16
  { "hide_object", "CERULEAN_CITY", "CERULEANCITY_GUARD2" },   -- 17
  { "hide_object", "CERULEAN_CITY", "CERULEANCITY_ROCKET" },   -- 18
  { "fade", "in" },                                            -- 19 GBFadeInFromBlack
}

M.CERULEAN_CITY = {
  talk = {
    TEXT_CERULEANCITY_ROCKET = rocketRows,
  },
  onEnter = function(game, ow)
    if game.save.flags.EVENT_BEAT_CHAMPION_RIVAL then
      local Commands = require("src.script.Commands")
      Commands.hide_object({ game = game, save = game.save, overworld = ow },
                           "CERULEAN_CITY", "CERULEANCITY_SUPER_NERD3")
    end
  end,
  onStep = function(game, ow, x, y)
    local f = game.save.flags
    if not f.EVENT_BEAT_CERULEAN_ROCKET_THIEF
       and inCoords({ { 30, 7 }, { 30, 9 } }, x, y) then
      if ow.runner:isRunning() then return false end
      local rocket = ow:npcByIndex(2)
      if rocket then
        ow.player.facing = y < 8 and "down" or "up"
        ow.runner:run(rocketRows, { npc = rocket })
        return true
      end
      return false
    end
    if not f.EVENT_BEAT_CERULEAN_RIVAL
       and inCoords({ { 20, 6 }, { 21, 6 } }, x, y) then
      return runAmbush(game, ow, ceruleanRivalScene(x, y), "up")
    end
    return false
  end,
}

-- The Pewter museum's fossil exhibits (engine/events/hidden_events/
-- museum_fossils.asm: DisplayMonFrontSpriteInBox + the plaque text)
M.MUSEUM_1F = {
  onInteract = function(game, ow, fx, fy)
    if ow.player.facing ~= "up" then return false end
    local PicBox = require("src.ui.PicBox")
    local t = text(game)
    if fx == 2 and fy == 3 then
      game.stack:push(PicBox.new(game,
        "assets/generated/battle/front/fossilaerodactyl.png",
        t._AerodactylFossilText or "AERODACTYL Fossil"))
      return true
    end
    if fx == 2 and fy == 6 then
      game.stack:push(PicBox.new(game,
        "assets/generated/battle/front/fossilkabutops.png",
        t._KabutopsFossilText or "KABUTOPS Fossil"))
      return true
    end
    return false
  end,
}

-- The Pewter Center's singing JIGGLYPUFF (scripts/PewterPokecenter.asm
-- PewterPokecenterJigglypuffText).  The text_asm sets
-- wDoNotWaitForButtonPressAfterDisplayingText before PrintText, so the box
-- prints with no A prompt and the script keeps running underneath it:
-- SFX_STOP_ALL_MUSIC, DelayFrames 32, PlayMusic MUSIC_JIGGLYPUFF_SONG,
-- then .spinMovementLoop writes the next of DOWN -> LEFT -> UP -> RIGHT (a
-- clockwise turn) every 24 frames for as long as the song's CHAN1/CHAN2
-- still sound, DelayFrames 48, PlayDefaultMusic, TextScriptEnd.  Only that
-- last step closes the box, so the whole dance plays out unskippably
-- (#249).  Music.playOnce's pendingRestore stands in for both the channel
-- poll and PlayDefaultMusic, so the Center's theme comes back the frame
-- the song ends rather than 48 frames later.
local JIGGLYPUFF_SPIN = { "down", "left", "up", "right" }
local JIGGLYPUFF_SILENCE, JIGGLYPUFF_STEP, JIGGLYPUFF_TAIL = 32, 24, 48

-- Built as a TextBox `auto` table: auto.sound fires the frame the last
-- page has typed out (PrintText returning), and auto.tick then runs once
-- per frame while the gate it returns still reads as playing.
local function jigglypuffDance(game, npc)
  local Music = require("src.core.Music")
  -- .findMatchingFacingDirectionLoop: the rotation picks up at the entry
  -- matching the sprite's current facing (showMapText has just turned it
  -- toward the player), and the first write is that same facing, so the
  -- first visible quarter turn lands 24 frames in
  local step = 1
  for i, dir in ipairs(JIGGLYPUFF_SPIN) do
    if npc and npc.facing == dir then step = i end
  end
  local frames, phase = 0, "silence"
  return {
    sound = function()
      Music.stop() -- SFX_STOP_ALL_MUSIC
      return { isPlaying = function() return phase ~= "done" end }
    end,
    tick = function()
      frames = frames + 1
      if phase == "silence" then
        if frames < JIGGLYPUFF_SILENCE then return end
        frames = 0
        if Music.playOnce(game.data, "Music_JigglypuffSong") then
          phase = "spin"
        else
          -- no song def (or headless): Music.stop above already took the
          -- map theme down and nothing armed pendingRestore, so put it
          -- back by hand and fall through to the tail rather than hold
          -- the box on a poll that would never clear
          Music.restoreMap(game.data)
          phase = "tail"
        end
        return
      end
      if phase == "spin" then
        if frames < JIGGLYPUFF_STEP then return end
        frames = 0
        -- the loop tests the channels after the delay and before the next
        -- write, so a song that just ended costs no extra quarter turn
        if not Music.oneShotPlaying() then
          phase = "tail"
          return
        end
        step = step % #JIGGLYPUFF_SPIN + 1
        if npc then npc.facing = JIGGLYPUFF_SPIN[step] end
        return
      end
      if frames >= JIGGLYPUFF_TAIL then phase = "done" end
    end,
  }
end

M.PEWTER_POKECENTER = {
  talk = {
    TEXT_PEWTERPOKECENTER_JIGGLYPUFF = function(game, ow, npc, done)
      -- not the local push() helper: this box needs opts.auto, which is
      -- also what suppresses the blinking arrow and the A dismissal
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        text(game)._PewterPokecenterJigglypuffText or "JIGGLYPUFF: Puu\npupuu!",
        done, { auto = jigglypuffDance(game, npc) }))
    end,
  },
}

-- Cycling Road gate guards (scripts/Route16Gate1F.asm /
-- Route18Gate1F.asm): without a BICYCLE in the bag the guard stops you
-- on the west-side cells and walks you back
local function bikeGateGuard(coords, stopText, explainText)
  return function(game, ow, x, y)
    if game.save.inventory.BICYCLE then return false end
    if not inCoords(coords, x, y) then return false end
    -- walk the player up to the tile beside the counter, no further:
    -- (matchedY - closestY) tiles, 0 when already next to it
    -- (Route16Gate1FDefaultScript's wCoordIndex-1). Forcing a fixed one
    -- tile up from the counter-adjacent row shoved the player onto the
    -- impassable desk and boxed them in.
    local closestY = coords[1][2]
    for _, c in ipairs(coords) do
      if c[2] < closestY then closestY = c[2] end
    end
    local dist = y - closestY
    local t = text(game)
    push(game, t[stopText] or "Hey! Wait up!", function()
      push(game, t[explainText] or "You need a\nBICYCLE for\nCYCLING ROAD!", function()
        -- pokered's Route16Gate1FGuardScript / Route18Gate1FGuardScript
        -- (scripts/Route16Gate1F.asm, Route18Gate1F.asm) simulate one
        -- PAD_RIGHT step after the refusal text, and only clear
        -- wJoyIgnore / hand control back once that step finishes
        -- (PlayerMovingRightScript). Without it the player was left
        -- parked beside the guard's counter with no way past. #518
        local function shoveRight()
          ow:scriptMove(ow.player, "right", 1)
        end
        if dist > 0 then
          ow:scriptMove(ow.player, "up", dist, shoveRight)
        else
          shoveRight()
        end
      end)
    end)
    return true
  end
end

M.ROUTE_16_GATE_1F = {
  onStep = bikeGateGuard(
    { { 4, 7 }, { 4, 8 }, { 4, 9 }, { 4, 10 } },
    "_Route16Gate1FGuardWaitUpText",
    "_Route16Gate1FGuardNoPedestriansAllowedText"),
}

M.ROUTE_18_GATE_1F = {
  onStep = bikeGateGuard(
    { { 4, 3 }, { 4, 4 }, { 4, 5 }, { 4, 6 } },
    "_Route18Gate1FGuardExcuseMeText",
    "_Route18Gate1FGuardYouNeedABicycleText"),
}

-- Silph Co. 7F rival ambush (scripts/SilphCo7F.asm
-- SilphCo7FDefaultScript: coords (3,2)/(3,3), the rival at (3,7) walks
-- up, MUSIC_MEET_RIVAL, OPP_RIVAL2 parties 7-9 by starter, then he
-- wishes you luck, walks off right and disappears; one-time via
-- EVENT_BEAT_SILPH_CO_RIVAL)
M.SILPH_CO_7F = {
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_SILPH_CO_RIVAL then return false end
    if not inCoords({ { 3, 2 }, { 3, 3 } }, x, y) then return false end
    return runAmbush(game, ow, {
      { "show_object", "SILPH_CO_7F", "SILPHCO7F_RIVAL" },     -- 1
      { "show_text", "_SilphCo7FRivalText" },                  -- 2
      { "move_npc_to", 9, 3, y + 1 },                          -- 3
      { "face_object", 9, "up" },                              -- 4
      { "show_text", "_SilphCo7FRivalWaitedHereText" },        -- 5
      { "rival_battle", "OPP_RIVAL2", 7 },                     -- 6
      { "jump_if_false", 12 },                                 -- 7
      { "set_flag", "EVENT_BEAT_SILPH_CO_RIVAL" },             -- 8
      { "show_text", "_SilphCo7FRivalDefeatedText" },          -- 9
      { "show_text", "_SilphCo7FRivalGoodLuckToYouText" },     -- 10
      { "move_npc_to", 9, 5, y + 1 },                          -- 11
      { "hide_object", "SILPH_CO_7F", "SILPHCO7F_RIVAL" },     -- 12
    }, "down")
  end,
}

-- SSAnne2FRivalAfterBattleScript's exit walk is keyed on the player's X,
-- not on where the rival stopped: from (37,8) the rival stands below him on
-- (36,8) and takes .RivalDownFourMovement straight down out of the room;
-- from (36,8) he stands above him on (36,7) and takes
-- .RivalWalkAroundPlayerMovement, which steps RIGHT and then falls through
-- into the same four DOWNs, so five downs in all (#360).
local function ssAnne2FRivalExitDirs(onLeft)
  if onLeft then
    return { "right", "down", "down", "down", "down", "down" }
  end
  return { "down", "down", "down", "down" }
end

-- S.S. Anne 2F rival ambush (scripts/SSAnne2F.asm; coords 36/37,8)
M.SS_ANNE_2F = {
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_SS_ANNE_RIVAL then return false end
    if not inCoords({ { 36, 8 }, { 37, 8 } }, x, y) then return false end
    local onLeft = x == 36
    return runAmbush(game, ow, {
      { "show_object", "SS_ANNE_2F", "SSANNE2F_RIVAL" },       -- 1
      { "move_npc_to", 2, 36, onLeft and 7 or 8 },             -- 2
      { "face_object", 2, onLeft and "down" or "right" },      -- 3
      { "show_text", "_SSAnne2FRivalText" },                   -- 4
      { "rival_battle", "OPP_RIVAL2", 1 },                     -- 5
      { "jump_if_false", 11 },                                 -- 6
      { "set_flag", "EVENT_BEAT_SS_ANNE_RIVAL" },              -- 7
      { "show_text", "_SSAnne2FRivalDefeatedText" },           -- 8
      { "show_text", "_SSAnne2FRivalCutMasterText" },          -- 9
      { "walk_npc", 2, ssAnne2FRivalExitDirs(onLeft) },        -- 10
      { "hide_object", "SS_ANNE_2F", "SSANNE2F_RIVAL" },       -- 11
    }, onLeft and "up" or "left")
  end,
}

return M

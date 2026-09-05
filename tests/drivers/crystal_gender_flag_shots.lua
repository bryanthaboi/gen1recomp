-- U2 verification: ENGINE_PLAYER_IS_FEMALE end to end, plus the four gendered
-- pictures and the Crystal surf refusal.  Not a suite; a shot harness.
--
--   POKEPORT_GAME=crystal POKEPORT_BOOT_CINEMA=1 POKEPORT_GENDER=girl \
--     POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_gender_flag_shots.lua love .
local U = require("tests.drivers.util")

local BattleState = require("src.ui.gen2.BattleState")
local FieldMoves = require("src.world.gen2.FieldMoves")
local GameVersion = require("src.core.GameVersion")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local HallOfFame = require("src.ui.gen2.HallOfFame")
local MainMenu = require("src.ui.gen2.MainMenu")
local Mon = require("src.battle.gen2.Mon")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local Screens = require("src.ui.Screens")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/u2-gender"
  local want = (os.getenv("POKEPORT_GENDER") or "girl"):lower()
  local log = io.open(out .. "/driver.log", "w")

  local function say(line)
    print("[u2] " .. line)
    if log then log:write(line .. "\n"); log:flush() end
  end

  local function done(code)
    if log then log:close() end
    love.event.quit(code)
    if code ~= 0 then error("driver failed", 0) end
    coroutine.yield()
  end

  local function bail(reason)
    say("FAIL " .. reason)
    done(1)
  end

  local function top() return game.stack:top() end
  local function isA(class)
    local s = top()
    return s ~= nil and getmetatable(s) == class
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return true end
      U.wait(1)
    end
    bail(("stalled waiting for %s (top is %s)"):format(label, tostring(top())))
  end

  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())
  say("fixes.surfOntoNpc=" .. tostring(GameVersion.fixes().surfOntoNpc))

  ------------------------------------------------------------------ new game
  U.wait(10)
  for _ = 1, 1200 do
    if isA(MainMenu) then break end
    tap("start", 2)
  end
  waitFor("the main menu", function() return isA(MainMenu) end, 600)
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")

  local gendered = false
  for _ = 1, 400 do
    if isA(GenderSelect) then gendered = true break end
    if isA(OakSpeech) or isA(NamePick) then break end
    U.wait(1)
  end
  if GameVersion.engine() == "crystal" then
    if not gendered then bail("Crystal never offered InitGender") end
    local pick = top()
    -- pokecrystal/engine/menus/init_gender.asm:29-34
    for _ = 1, 600 do
      if pick:menuOpen() then break end
      U.wait(1)
    end
    pick.cursor = (want == "girl") and 2 or 1
    U.shot(game, out .. "/00-gender.png")
    say("OK gender screen, choosing " .. want)
    tap("a")
  else
    if gendered then bail("Gold offered a gender prompt; it has none") end
    say("OK no gender prompt on " .. GameVersion.get())
  end

  for _ = 1, 900 do
    if game.phase == "play" and game.world and game.world.map then break end
    if isA(NamingScreen) then
      local naming = top()
      naming.row = naming:bottomRow()
      naming.col = 6
    end
    tap("a", 2)
  end
  if not (game.phase == "play" and game.world and game.world.map) then
    bail("never reached the overworld (top is " .. tostring(top()) .. ")")
  end
  local world = game.world
  local save = game.save
  say("OK overworld, name=" .. tostring(save.player.name)
    .. " gender=" .. tostring(save.player.gender)
    .. " sprite=" .. tostring(world:playerSpriteName()))

  ------------------------------------------------------ the engine flag itself
  local id = FieldMoves.FEMALE_FLAG
  say("FieldMoves.FEMALE_FLAG=" .. tostring(id))
  if GameVersion.engine() == "crystal" then
    if id ~= 99 then bail("female flag id is " .. tostring(id) .. ", want 99") end
    local reads = world:engineFlag(id)
    say("world:engineFlag(" .. id .. ")=" .. tostring(reads))
    if reads ~= (want == "girl") then
      bail("checkflag ENGINE_PLAYER_IS_FEMALE read " .. tostring(reads))
    end
  elseif id ~= nil then
    bail("Gold bound a female flag id: " .. tostring(id))
  end

  ------------------------------------------------------------- the three sites
  local sites = {
    { "COPYCATS_HOUSE_2F", 3, 4, "up", "01-copycat" },
    { "ROUTE_37", 5, 9, "up", "02-route37" },
    { "POKECENTER_2F", 5, 5, "up", "03-pokecenter2f" },
  }
  for _, site in ipairs(sites) do
    local mapId, x, y, facing, name = site[1], site[2], site[3], site[4], site[5]
    if world.maps and world.maps[mapId] then
      world:setMap(mapId, x, y, facing)
      U.wait(40)
      U.shot(game, out .. "/" .. name .. ".png")
      local names = {}
      for _, npc in ipairs(world.npcs or {}) do
        names[#names + 1] = tostring(npc.def and npc.def.sprite)
      end
      say(name .. " map=" .. tostring(world.map.id)
        .. " objects=" .. table.concat(names, ","))
    else
      say("SKIP " .. mapId .. ": not in this cache")
    end
  end

  ------------------------------------------------------------------- the pack
  world:setMap("NEW_BARK_TOWN", 13, 6, "down")
  U.wait(20)
  save.inventory = save.inventory or {}
  save.inventory.POTION = 3
  Screens.push(game, "Gen2PackMenu", { save = save, world = {},
    onClose = function() game.stack:pop() end })
  U.wait(20)
  U.shot(game, out .. "/04-pack.png")
  local packGfx = top() and top().gfx
  local pals = packGfx and packGfx.gfx and packGfx.gfx.palettes
  local menuGfx = game.data.gen2MenuGfx or {}
  local femalePals = menuGfx.pack and menuGfx.pack.palettesFemale
  say("pack palettes are the female set: "
    .. tostring(pals ~= nil and pals == femalePals))
  tap("b")
  U.wait(10)
  while top() do game.stack:pop() end

  ------------------------------------------------------------ battle back pic
  local hud = menuGfx.battleHud or {}
  say("battleHud.playerBack=" .. tostring(hud.playerBack)
    .. " playerBackFemale=" .. tostring(hud.playerBackFemale))
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12) }
  world:startBattle({ wild = Mon.new(game.data, "WOOPER", 5) })
  local battle
  for _ = 1, 600 do
    if getmetatable(top()) == BattleState then battle = top() break end
    U.wait(1)
  end
  if not battle then bail("startBattle never reached the battle screen") end
  -- showPlayerTrainer is only true until SendOutPlayerMon; hold it so the
  -- back pic is what the shot catches.
  for _ = 1, 90 do
    battle.showPlayerTrainer = true
    U.wait(1)
  end
  battle.showPlayerTrainer = true
  U.shot(game, out .. "/05-battle-backpic.png")
  say("battle backpic path=" .. tostring(battle.playerBackPath))
  while top() do game.stack:pop() end
  U.wait(10)

  ------------------------------------------------------------- trainer card
  Screens.push(game, "Gen2TrainerCard", { onClose = function()
    game.stack:pop() end })
  U.wait(30)
  U.shot(game, out .. "/06-trainercard.png")
  say("trainer card female arm=" .. tostring(top() and top().female))
  tap("b")
  U.wait(10)
  while top() do game.stack:pop() end

  ------------------------------------------------------------- hall of fame
  save.hallOfFame = nil
  Screens.push(game, "Gen2HallOfFame", {
    save = save, mode = "induct", text = world.text,
    entry = { winCount = 1, mons = { { species = "CYNDAQUIL", level = 12,
      nickname = "CYNDAQUIL", otId = 1234, gender = "male" } } },
    onDone = function() game.stack:pop() end })
  U.wait(20)
  local hof = top()
  if getmetatable(hof) ~= HallOfFame then
    bail("Gen2HallOfFame did not push (top is " .. tostring(hof) .. ")")
  end
  -- The ceremony walks its own phases; freeze it so the two player cards can
  -- be posed and shot.
  hof.update = function() end
  hof.scx, hof.scy = 0, 0
  hof.phase = "player"
  U.shot(game, out .. "/07-hof-trainerpic.png")
  hof.phase = "playerBack"
  U.shot(game, out .. "/08-hof-backpic.png")
  say("hof backpic=" .. tostring(hof.playerBackPath)
    .. " trainerPic=" .. tostring(hof.trainerPicPath))
  while top() do game.stack:pop() end
  U.wait(10)

  ------------------------------------------------------------- surf onto NPC
  --
  -- SurfFunction.TrySurf with a facing object: Crystal refuses, Gold does not
  -- (../pokecrystal/engine/events/overworld.asm:364).
  local ctx = {
    save = { player = { badges = { FOG = true } } },
    mon = { species = "LAPRAS" },
    facing = "down",
    facingColl = 0x29,
    playerColl = 0x00,
    playerState = FieldMoves.PLAYER_NORMAL,
    facingObject = { id = "an NPC standing on the water" },
  }
  local refused = FieldMoves.surfFromMenu(ctx)
  say("surf onto an NPC: ok=" .. tostring(refused.ok)
    .. " text=" .. tostring(refused.text))
  local shouldRefuse = GameVersion.fixes().surfOntoNpc == true
  if (refused.ok ~= true) ~= shouldRefuse then
    bail("surf-onto-NPC answered ok=" .. tostring(refused.ok)
      .. " but fixes().surfOntoNpc=" .. tostring(shouldRefuse))
  end
  ctx.facingObject = nil
  if not FieldMoves.surfFromMenu(ctx).ok then
    bail("open water refused SURF")
  end

  say("PASS " .. GameVersion.get() .. " / " .. want .. " in " .. out)
  done(0)
end

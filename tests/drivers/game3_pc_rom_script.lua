-- pokefirered/data/scripts/pc.inc:1
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pc_rom_script"

local FLAG_SYS_POKEDEX_GET = 0x829 -- include/constants/flags.h:1375
local FLAG_SYS_GAME_CLEAR = 0x82C -- include/constants/flags.h:1378
local FLAG_SYS_PC_STORAGE_DISABLED = 0x841 -- include/constants/flags.h:1399
local MB_PC = 0x83 -- include/constants/metatile_behaviors.h:94
local SE_PC_LOGIN = 2 -- include/constants/songs.h:6
local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076 -- include/constants/vars.h:170

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_pc_rom_script")
    love.event.quit(0)
  else
    print("FAIL game3_pc_rom_script failures=" .. failures)
    love.event.quit(1)
  end
end

local function flat(s)
  return (tostring(s or ""):gsub("[\n\f]", " "))
end

local function Message() return require("src.ui.game3.message") end
local function PcMenu() return require("src.ui.game3.pc_menu") end
local function Choice() return require("src.ui.game3.choice") end

local function waitPage(game, pattern, frames)
  local seen = {}
  for _ = 1, frames do
    local M = Message()
    if M.isOpen() then
      local page = flat(M.currentPage())
      if page:find(pattern, 1, true) then
        while not M.isWaiting() do U.wait(1) end
        return true, page
      end
      if seen[#seen] ~= page then seen[#seen + 1] = page end
      if M.isWaiting() and not (Choice().active) then
        U.tap(game, "a")
      end
    end
    if Choice().active then U.tap(game, "a") end
    U.wait(1)
  end
  return false, table.concat(seen, " | ")
end

local function waitMenu(game, frames)
  for _ = 1, frames do
    local P = PcMenu()
    if P.isOpen() and P.mode == "root" then return true end
    local M = Message()
    local prompt = flat(M.currentPage()):find("Which PC should be accessed?", 1, true)
    if M.isOpen() and M.isWaiting() and not prompt then U.tap(game, "a") end
    U.wait(1)
  end
  return false
end

local function pickRow(game, id)
  local P = PcMenu()
  for i, r in ipairs(P._rootEntries()) do
    if r.id == id then P.cursor = i end
  end
  U.tap(game, "a")
end

local function waitReleased(game, frames)
  local Space = require("src.core.game3.scripting.space")
  for _ = 1, frames do
    local running = Space.vm and Space.vm:isRunning()
    if not running and not Message().isOpen() and not PcMenu().isOpen() then return true end
    if Message().isOpen() and Message().isWaiting() then U.tap(game, "a") end
    U.wait(1)
  end
  return false
end

local function standAtPc(game, mapId)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, mapId, { x = 1, y = 1, facing = "up" })
  U.wait(30)
  local Collision = require("src.core.game3.collision")
  for y = 1, 20 do
    for x = 0, 30 do
      if Collision.behavior(x, y) == MB_PC then
        Map.load(nil, game, mapId, { x = x, y = y + 1, facing = "up" })
        game.session.x, game.session.y, game.session.facing = x, y + 1, "up"
        U.wait(60)
        return true
      end
    end
  end
  return false
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local Audio = require("src.core.game3.audio")
  local origSe = Audio.playSe
  local seLog = {}
  Audio.playSe = function(id, ...)
    seLog[#seLog + 1] = id
    return origSe(id, ...)
  end

  -- data/maps/OneIsland_PokemonCenter_1F/scripts.inc:116
  local ONE = MapCatalog.pretToEngine("OneIsland_PokemonCenter_1F")
  Flags.setVar(Space.store, nil, VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 1)
  Flags.setFlag(Space.store, nil, FLAG_SYS_PC_STORAGE_DISABLED, true)
  if not result(standAtPc(game, ONE), "One Island Pokemon Center PC found") then return finish() end
  U.tap(game, "a")
  local ok, page = waitPage(game, "The usual PC services aren't available…", 300)
  result(ok, "One Island before Celio: \"The usual PC services aren't available…\" (got " .. page .. ")")
  if ok then U.shot(game, DIR .. "/pc_one_island_services_unavailable.png") end
  result(not PcMenu().isOpen(), "One Island PC does not open the PC menu")
  result(waitReleased(game, 300), "One Island PC releases the player")
  Flags.setFlag(Space.store, nil, FLAG_SYS_PC_STORAGE_DISABLED, false)

  local VIRIDIAN = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  if not result(standAtPc(game, VIRIDIAN), "Viridian Pokemon Center PC found") then return finish() end
  Flags.setFlag(Space.store, nil, FLAG_SYS_POKEDEX_GET, true)
  U.tap(game, "a")
  if not result(waitMenu(game, 300), "PC menu opens after booted-up text") then return finish() end
  pickRow(game, "oak")
  ok, page = waitPage(game, "Accessed PROF. OAK's PC…", 300)
  result(ok, "Oak's PC: \"Accessed PROF. OAK's PC…\" (got " .. page .. ")")
  ok, page = waitPage(game, "PROF. OAK's rating:", 2400)
  result(ok, "Oak's PC runs PokedexRating_EventScript_Rate (got " .. page .. ")")
  if ok then U.shot(game, DIR .. "/pc_oak_pc_rating.png") end
  ok, page = waitPage(game, "Closed link to PROF. OAK's PC.", 3000)
  result(ok, "Oak's PC: \"Closed link to PROF. OAK's PC.\" (got " .. page .. ")")
  result(waitMenu(game, 300), "Oak's PC returns to the PC menu")
  pickRow(game, "quit")
  result(waitReleased(game, 300), "LOG OFF releases the player")

  Flags.setFlag(Space.store, nil, FLAG_SYS_GAME_CLEAR, true)
  session.gameStats = session.gameStats or {}
  session.gameStats[10] = 3
  session.hallOfFameTeams = {
    {
      { species = 6, level = 50, nickname = "CHARIZARD", trainerId = 12345, personality = 0 },
      { species = 25, level = 42, nickname = "SPARKY", trainerId = 12345, personality = 0xFF },
      { species = 412, level = 5, nickname = "EGG", trainerId = 12345, personality = 0 },
    },
    {
      { species = 3, level = 61, nickname = "VENUSAUR", trainerId = 12345, personality = 0x10 },
      { species = 9, level = 60, nickname = "BLASTOISE", trainerId = 12345, personality = 0 },
      { species = 65, level = 58, nickname = "ALAKAZAM", trainerId = 12345, personality = 0xF0 },
      { species = 143, level = 55, nickname = "SNORLAX", trainerId = 12345, personality = 0 },
      { species = 130, level = 55, nickname = "GYARADOS", trainerId = 12345, personality = 0 },
      { species = 29, level = 50, nickname = "NIDORAN", trainerId = 12345, personality = 0 },
    },
  }
  U.tap(game, "a")
  if not result(waitMenu(game, 300), "PC menu opens with HALL OF FAME row") then return finish() end
  local mark = #seLog
  pickRow(game, "hall")
  local HofPc = require("src.ui.game3.hall_of_fame_pc")
  for _ = 1, 120 do
    if HofPc.isOpen() then break end
    U.wait(1)
  end
  if not result(HofPc.isOpen(), "HALL OF FAME row opens the HoF PC viewer") then return finish() end
  local login = false
  for i = mark + 1, #seLog do if seLog[i] == SE_PC_LOGIN then login = true end end
  result(login, "AccessHallOfFame plays SE_PC_LOGIN from the ROM script")
  result(HofPc._team == 2 and HofPc._number == 3, "viewer starts on the newest team, HALL OF FAME No. 3")
  U.wait(30)
  U.shot(game, DIR .. "/pc_hof_viewer_newest_team.png")
  U.tap(game, "a")
  U.wait(20)
  result(HofPc._team == 1 and HofPc._number == 2, "A steps to the older team, No. 2")
  U.tap(game, "down")
  U.wait(20)
  result(HofPc._mon == 2, "DOWN selects the second member")
  U.shot(game, DIR .. "/pc_hof_viewer_older_team_mon2.png")
  U.tap(game, "b")
  result(waitMenu(game, 300) and not HofPc.isOpen(), "B leaves the viewer and reshows the PC menu")
  pickRow(game, "quit")
  result(waitReleased(game, 300), "LOG OFF after the viewer releases the player")

  Audio.playSe = origSe
  finish()
end

local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_league_lighting_diploma"

local LORELEI = "FR_POKEMON_LEAGUE_LORELEIS_ROOM"
local CHAMPION = "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM"
local PC_1F = "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F"
local CONDO_3F = "FR_CELADON_CITY_CONDOMINIUMS_3F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_league_lighting_diploma")
    love.event.quit(0)
  else
    print("FAIL game3_league_lighting_diploma failures=" .. failures)
    love.event.quit(1)
  end
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local NativeTileset = require("src.core.game3.tileset_native")
  local Lighting = require("src.core.game3.league_lighting")
  local Message = require("src.ui.game3.message")
  local Dex = require("src.core.game3.dex")
  local Pokemon = require("src.core.game3.pokemon")
  local Diploma = require("src.ui.game3.diploma")
  local Audio = require("src.core.game3.audio")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end

  local function flag(id) return Flags.getFlag(Space.store, nil, id) end
  local function setFlag(id, on) Flags.setFlag(Space.store, nil, id, on) end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
  end

  local function pumpUntil(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function slotPixel()
    local def = Map.currentDef()
    local ts = def and NativeTileset.get(def.pair)
    local pix = ts and ts.slotPix[7]
    if not (pix and #pix.under > 0) then return nil end
    local parts = {}
    for i = 1, #pix.under do
      local p = pix.under[i]
      if p[3] >= 8 then
        local r, g, b = ts.imageData:getPixel(p[1], p[2])
        parts[#parts + 1] = string.format("%.2f%.2f%.2f", r, g, b)
      end
    end
    return table.concat(parts), ts
  end

  -- pokefirered/data/scripts/pokemon_league.inc:10
  Flags.setVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE, 0)
  goTo(LORELEI, 6, 12, "up")
  result(Map.current == LORELEI, "loaded Lorelei's room")
  result(Lighting.task ~= nil and Lighting.task.phase == "run",
    "ON_RESUME started DoPokemonLeagueLightingEffect")
  local walked = pumpUntil(600, function() return flag(0x2) end)
  result(walked, "EnterRoom walked the player in and set FLAG_TEMP_2")
  pumpUntil(600, function() return Lighting.task and Lighting.task.index == 1 end)
  local idxA = Lighting.task and Lighting.task.index
  local pixA = slotPixel()
  result(idxA == 1, "E4 cycle advanced to palette 1 after the 40-frame hold")
  U.shot(game, DIR .. "/leag_lorelei_lighting_frame1.png")
  pumpUntil(200, function() return Lighting.task and Lighting.task.index == 4 end)
  local idxB = Lighting.task and Lighting.task.index
  local pixB = slotPixel()
  result(idxB == 4, "E4 cycle reached palette 4 on the 12-frame cadence")
  result(pixA ~= nil and pixA ~= pixB, "floor light pixels changed between frames 1 and 4")
  U.shot(game, DIR .. "/leag_lorelei_lighting_frame4.png")

  setFlag(0x5, true)
  local frozen = Lighting.task.index
  U.wait(60)
  result(Lighting.task.index == frozen, "FLAG_TEMP_5 (talk/battle) freezes the cycle")
  setFlag(0x5, false)

  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  U.tap(game, "start")
  pumpUntil(60, function() return StartMenu.isOpen() end)
  local bagIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "bag" then bagIdx = i end
  end
  for _ = 1, 10 do
    if StartMenu.cursor == bagIdx then break end
    U.tap(game, "down")
    U.wait(4)
  end
  result(Lighting.task ~= nil, "the lighting task keeps running while only the start menu is up")
  U.tap(game, "a")
  local bagOpen = pumpUntil(120, function() return BagMenu.isOpen and BagMenu.isOpen() end)
  result(bagOpen, "BAG opened from the start menu")
  U.wait(60)
  result(Lighting.task == nil, "leaving the field for the BAG stops the lighting task")
  for _ = 1, 8 do
    if not (BagMenu.isOpen and BagMenu.isOpen()) and not StartMenu.isOpen() then break end
    U.tap(game, "b")
    U.wait(30)
  end
  pumpUntil(120, function() return Lighting.task ~= nil end)
  result(Lighting.task and Lighting.task.phase == "run" and Lighting.task.index == 0,
    "back on the field ON_RESUME restarts the cycle from palette 0 (index="
      .. tostring(Lighting.task and Lighting.task.index) .. ")")

  -- pokefirered/data/maps/PokemonLeague_LoreleisRoom/scripts.inc:59
  setFlag(0x3, true)
  Space.returnToField()
  result(Lighting.task and Lighting.task.phase == "cancel",
    "return from battle with FLAG_TEMP_3 starts Task_CancelPokemonLeagueLightingEffect")
  U.wait(10)
  -- pokefirered/data/scripts/pokemon_league.inc:7
  setFlag(0x4, true)
  pumpUntil(10, function() return Lighting.task and Lighting.task.phase == "held" end)
  result(Lighting.task and Lighting.task.phase == "held", "door open (FLAG_TEMP_4) loads the final palette")
  local pixFinal = slotPixel()
  result(pixFinal ~= nil and pixFinal ~= pixB, "final palette differs from the cycle frame")
  U.wait(30)
  result(slotPixel() == pixFinal, "the room holds the final palette")
  U.shot(game, DIR .. "/leag_lorelei_final_palette.png")

  local _, tsL = slotPixel()
  goTo(PC_1F, 11, 8, "up")
  U.wait(30)
  result(Lighting.task == nil, "leaving the room ends the lighting task")
  result(tsL and not (tsL.patchedSlots and tsL.patchedSlots[7]), "slot 7 restored on the shared atlas")

  local function diploma(label, national)
    session.dex = Dex.new()
    for nat = 1, national and 386 or 151 do
      local sp = Pokemon.speciesFromNational(nat)
      Dex.setSeen(session.dex, sp)
      Dex.setCaught(session.dex, sp)
    end
    goTo(CONDO_3F, 3, 9, "up")
    U.wait(60)
    U.tap(game, "a")
    local opened = pumpUntil(900, function()
      if Diploma.isOpen() then return true end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      return Diploma.isOpen()
    end)
    if not result(opened, label .. ": designer opened the diploma") then return end
    result(Diploma.isNational() == national, label .. ": " .. (national and "NATIONAL" or "KANTO") .. " half chosen")
    pumpUntil(60, function() return Diploma.phase() == "fanfare" end)
    result(Diploma.phase() == "fanfare", label .. ": fade in then badge fanfare")
    U.tap(game, "a")
    U.wait(2)
    result(Diploma.phase() == "fanfare", label .. ": A ignored until the fanfare ends")
    pumpUntil(600, function() return Diploma.phase() == "wait" end)
    result(Diploma.phase() == "wait" and Audio.isFanfareFinished(), label .. ": fanfare finished")
    U.shot(game, DIR .. "/leag_diploma_" .. (national and "national" or "kanto") .. ".png")
    U.tap(game, "b")
    U.wait(5)
    result(Diploma.isOpen(), label .. ": B does not close the diploma")
    U.tap(game, "a")
    local closed = pumpUntil(120, function() return not Diploma.isOpen() end)
    result(closed, label .. ": A fades out and closes")
    local released = pumpUntil(300, function() return not (Space.vm and Space.vm:isRunning()) end)
    result(released, label .. ": script resumed past waitstate and released")
  end
  diploma("kanto", false)
  diploma("national", true)

  Flags.setVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE, 0)
  goTo(CHAMPION, 6, 19, "up")
  pumpUntil(600, function() return flag(0x2) end)
  local champSteps = Lighting.task and Lighting.task.steps
  result(champSteps == 8, "Champion room runs the 8-palette cycle")
  local t0
  for i = 1, 200 do
    if Lighting.task and Lighting.task.index == 1 then t0 = i break end
    U.wait(1)
  end
  local t1
  for i = 1, 30 do
    U.wait(1)
    if Lighting.task and Lighting.task.index == 2 then t1 = i break end
  end
  result(t0 ~= nil and t1 == 8, "Champion cycle steps every 8 frames (got " .. tostring(t1) .. ")")
  U.shot(game, DIR .. "/leag_champion_lighting.png")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    print("FAIL game3_league_lighting_diploma driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end

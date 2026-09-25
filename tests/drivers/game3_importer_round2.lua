local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_importer_round2"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_importer_round2")
    love.event.quit(0)
  else
    print("FAIL game3_importer_round2 failures=" .. failures)
    love.event.quit(1)
  end
end

local function is_hidden(ev)
  return ev.type == "hidden_item" or ev.kind == 7
end

-- pokefirered/src/itemfinder.c:354
local function find_edge_item(game)
  local maps = game.data and game.data.maps or {}
  local Map = require("src.core.game3.map")
  local names = {}
  for id in pairs(maps) do names[#names + 1] = id end
  table.sort(names)
  for _, id in ipairs(names) do
    local def = maps[id]
    for _, conn in ipairs(require("src.core.game3.connections").each(def)) do
      local dir = conn.dir
      local nid = conn.map
      local ndef = maps[nid]
      if ndef and (dir == "north" or dir == "up") then
        for _, ev in ipairs(ndef.bgEvents or {}) do
          if is_hidden(ev) and not ev.underfoot then
            local L = Map.ensureMidLayout(game, nid, ndef)
            local off = tonumber(conn.offset) or 0
            local fromBottom = L and (L.height - 1 - ev.y)
            if fromBottom and fromBottom <= 2 then
              return id, nid, ev, ev.x + off, fromBottom
            end
          end
        end
      end
    end
  end
  return nil
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
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local Itemfinder = require("src.core.game3.itemfinder")
  local Audio = require("src.core.game3.audio")
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local HallOfFame = require("src.ui.game3.hall_of_fame")
  local RomText = require("src.core.game3.rom_text")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end

  local ses = {}
  local playSe = Audio.playSe
  Audio.playSe = function(id, ...) ses[#ses + 1] = id return playSe(id, ...) end

  result(RomText.plain("gText_PlayerScurriedToCenter", { playerName = "RED" })
    :find("RED scurried to a POKéMON CENTER,", 1, true) ~= nil, "whiteout text comes from the ROM cache")
  result(Runtime and require("src.core.game3.scripting.space").ensureBundle().scripts.EventScript_AfterWhiteOutHeal ~= nil,
    "EventScript_AfterWhiteOutHeal is a ROM script")

  local mapId, nid, ev, itemX, fromBottom = find_edge_item(game)
  if result(mapId ~= nil, "found a hidden item just across a north map connection") then
    local px, py = itemX, 1
    Map.load(nil, game, mapId, { x = px, y = py, facing = "up" })
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = px, py, px, py
    Player.px, Player.py, Player.facing = px * 16, py * 16, "up"
    session.x, session.y, session.map = px, py, mapId
    U.wait(60)
    local ok, _, _, info = Field.useItemfinder(session, true)
    result(ok and info and info.y < 0, string.format("itemfinder answers for %s item in %s (dy=%s)",
      tostring(ev.item), tostring(nid), tostring(info and info.y)))
    U.wait(6)
    result(#Itemfinder.sprites() > 0, "itemfinder arrow sprite is up")
    result(ses[#ses] == 65, "SE_ITEMFINDER played")
    U.shot(game, DIR .. "/r2_itemfinder_arrow_connected_map.png")
    local shown = false
    for _ = 1, 300 do
      if Message.isOpen() and tostring(Message.currentPage()):find("ITEMFINDER's responding", 1, true) then
        shown = true
        break
      end
      U.wait(1)
    end
    for _ = 1, 300 do
      if not shown or Message.isWaiting() then break end
      U.wait(1)
    end
    result(shown and Message.isWaiting(), "gText_ItemfinderResponding printed after the dings")
    if shown and Message.isWaiting() then U.shot(game, DIR .. "/r2_itemfinder_responding_text.png") end
    for _ = 1, 600 do
      if not Message.isOpen() then break end
      if Message.isWaiting() then U.tap(game, "a") else U.wait(1) end
    end
    U.wait(2)
    result(not Message.isOpen() and not Field.locked and not Itemfinder.isActive(),
      "field unlocked after the itemfinder message")
  end

  do
    local Objects = require("src.core.game3.objects")
    local Space = require("src.core.game3.scripting.space")
    local Flags = require("src.core.game3.scripting.flags")
    local FieldMoves = require("src.core.game3.field_moves")
    local FieldEffects = require("src.core.game3.field_effects")
    Map.load(nil, game, "FR_SEAFOAM_ISLANDS_B3F", { x = 6, y = 16, facing = "down" })
    session.x, session.y, session.facing = 6, 16, "down"
    Player.moving = false
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = 6, 16, 6, 16
    Player.px, Player.py, Player.facing = 6 * 16, 16 * 16, "down"
    U.wait(60)
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
    for _ = 1, 20 do
      U.hold(game, "down", 1)
      if Player.boulderPush then break end
    end
    result(Player.boulderPush ~= nil, "boulder push started")
    U.wait(3)
    local dust
    for _, a in ipairs(FieldEffects._anims or {}) do
      if a.kind == "dust" then dust = a end
    end
    result(dust ~= nil and FieldEffects.loadSheet("ground_impact_dust", 16, 8, 3) ~= nil,
      "boulder push dust uses the ROM ground_impact_dust sheet")
    U.shot(game, DIR .. "/r2_boulder_push_dust.png")
    for _ = 1, 60 do
      if not Player.boulderPush then break end
      U.wait(1)
    end
  end

  session.party = {}
  local tid = (tonumber(session.trainerId) or 0) % 65536
  local sid = (tonumber(session.secretId) or 0) % 65536
  Party.giveMon(session, 6, 62)
  Party.giveMon(session, 201, 40)
  local shinyMon, unownD = session.party[1], session.party[2]
  shinyMon.personality = bit.bxor(tid, sid) * 65536
  shinyMon.isShiny = nil
  unownD.personality = 0xFC000003
  unownD.isShiny = nil
  result(Pokemon.isShiny(shinyMon), "the Charizard is shiny for this trainer")
  result(not Pokemon.isShiny(unownD), "the Unown is not shiny")
  result(Pokemon.monPicSpecies(unownD) == 415, "Unown personality 0xFC000003 picks SPECIES_UNOWN_D")
  local shinyPic = Pokemon.monFrontPic(shinyMon)
  local plainPic = Pokemon.frontPic(6)
  result(shinyPic and plainPic and shinyPic.image ~= plainPic.image, "shiny Charizard uses the shiny front pic")
  result(Pokemon.monIcon(unownD) ~= Pokemon.icon(201), "Unown D uses its own menu icon")

  HallOfFame.start({ session = session, dontSave = true, warp = false })
  local applause = false
  for _ = 1, 4000 do
    if HallOfFame.phase() == "applause" and #(HallOfFame._confetti or {}) >= 20 then
      applause = true
      break
    end
    U.wait(1)
  end
  result(applause, "Hall of Fame applause spawned confetti sprites")
  U.shot(game, DIR .. "/r2_hof_confetti_shiny_unown.png")
  HallOfFame.close()
  U.wait(10)

  Audio.playSe = playSe
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end

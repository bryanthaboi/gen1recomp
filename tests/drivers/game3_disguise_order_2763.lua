local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_disguise_order_2763")

return function(game)
  if not F.boot(game) then return F.finish() end
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local version = session.version
  local prefix = ({ emerald = "EM", ruby = "RU", sapphire = "SA" })[version]
  if not F.check(prefix ~= nil, "disguise2763 RSE version") then return F.finish() end
  local Objects = require("src.core.game3.objects")
  local Fx = require("src.core.game3.field_effects_rse")
  local View = require("src.core.game3.field_view")
  local Player = require("src.core.game3.player")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Sight = require("src.core.game3.trainer_sight")
  local Field = require("src.core.game3.field")

  local function ordered(eo, tag)
    local actors, ninja = {}, nil
    for _, obj in ipairs(Objects.forDraw()) do
      local actor = { kind = "npc", i = obj.localId, eventObject = obj,
        x = obj.px, y = obj.py, sortY = obj.py, elevation = obj.elevation }
      actors[#actors + 1] = actor
      if obj == eo then ninja = actor end
    end
    Fx.collectActors(actors)
    local under = View.applyDrawOrder(actors, {}, {}, Player.py - 72)
    local ni, mi, mask
    for i, actor in ipairs(under) do
      if actor == ninja then ni = i end
      if actor.disguiseObject == eo then mi, mask = i, actor end
    end
    return F.check(ni and mi and ni < mi and mask.subpriority == (ninja.subpriority - 1) % 256,
      "disguise2763 " .. version .. " " .. tag .. " ninja_before_mask")
  end

  local function spot(route, lid, kind)
    local tag = kind .. "_" .. route
    local mapId = prefix .. "_" .. route
    if not F.check(F.goTo(game, mapId, 5, 5, "down"), tag .. " map_loaded") then return end
    for _, id in ipairs(Objects._order) do
      local trainerId = Sight.getTrainerId(Objects._byId[id])
      if trainerId then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(trainerId), true) end
    end
    local eo = Objects.find(lid)
    if not F.check(eo and eo.disguise and eo.disguise.sheet == kind,
      "disguise2763 " .. version .. " " .. tag .. " cached_disguise") then return end
    F.goTo(game, mapId, eo.cellX + 3, eo.cellY + 1, "left", { wait = 20 })
    eo = Objects.find(lid)
    Field.lock()
    F.check(eo.disguise and eo.disguise.a and eo.disguise.a.frame == 0 and not eo.invisible,
      "disguise2763 " .. version .. " " .. tag .. " idle_frame")
    ordered(eo, tag .. "_hidden")
    F.check(F.shot(game, "2763_" .. version .. "_" .. tag .. "_01_hidden.png", true),
      "disguise2763 " .. version .. " " .. tag .. " hidden_capture")
    Objects.revealTrainer(eo)
    U.wait(10)
    F.check(eo.disguise and eo.disguise.revealing and not eo.disguise.done
      and eo.disguise.a.frame > 0 and not eo.invisible,
      "disguise2763 " .. version .. " " .. tag .. " midtear_frame")
    ordered(eo, tag .. "_midtear")
    F.check(F.shot(game, "2763_" .. version .. "_" .. tag .. "_02_midtear.png", true),
      "disguise2763 " .. version .. " " .. tag .. " midtear_capture")
    U.wait(40)
    local actors = {}
    Fx.collectActors(actors)
    local mask
    for _, actor in ipairs(actors) do if actor.disguiseObject == eo then mask = actor end end
    local drawn = false
    for _, obj in ipairs(Objects.forDraw()) do if obj == eo then drawn = true end end
    F.check(mask == nil and drawn and not eo.invisible,
      "disguise2763 " .. version .. " " .. tag .. " revealed_ninja_only")
    F.check(F.shot(game, "2763_" .. version .. "_" .. tag .. "_03_revealed.png", true),
      "disguise2763 " .. version .. " " .. tag .. " revealed_capture")
    Field.unlock()
    F.haltVm()
  end

  spot("ROUTE119", 12, "tree_disguise")
  spot("ROUTE120", 34, "mountain_disguise")
  F.finish()
end

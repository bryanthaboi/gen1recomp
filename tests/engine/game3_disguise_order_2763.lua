package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Objects = require("src.core.game3.objects")
local Prepare = require("src.core.game3.object_prepare")
local sheets, sprites = {}, {}
package.loaded["src.core.game3.ow_sprites"] = { get = function(id) return sprites[id] end }
package.loaded["src.core.game3.field_effects"] = {
  loadSheet = function(name) return sheets[name] end,
  manifestObject = function(name) return sheets[name] end,
}
local Fx = require("src.core.game3.field_effects_rse")
local View = require("src.core.game3.field_view")

local function check(ok, label)
  assert(ok, "FAIL disguise2763 " .. label)
end

local function maskFor(eo)
  local actors = {}
  Fx.collectActors(actors)
  for _, actor in ipairs(actors) do
    if actor.disguiseObject == eo then return actor end
  end
end

local function exercise(def, version, label)
  local eo = Prepare.instance(def, {
    version = version, rse = true, graphicsId = def.graphicsId, elevation = def.elevation,
  })
  eo.disguise.a = Fx.anim(Fx.animCmds(eo.disguise.sheet, 1))
  Objects._order, Objects._byId = { eo.localId }, { [eo.localId] = eo }
  Objects._bounds = nil
  check(#Objects.forDraw() == 1, label .. " ninja_drawn")
  for _, camY in ipairs({ 0, eo.py - 112, eo.py - 23, eo.py + 17 }) do
    for _, fixed in ipairs({ false, 0, 1, 83, 255 }) do
      eo.fixedPriority, eo.subpriority = fixed ~= false, fixed ~= false and fixed or nil
      eo.fixedClass = nil
      local ninja = { kind = "npc", i = eo.localId, eventObject = eo,
        x = eo.px, y = eo.py, sortY = eo.py, elevation = eo.elevation }
      local back = { kind = "npc", i = 201, y = eo.py - 32, elevation = 3 }
      local front = { kind = "npc", i = 202, y = eo.py + 32, elevation = 3 }
      local actors = { front, ninja, back }
      Fx.collectActors(actors)
      check(#actors == 4, label .. " mask_collected")
      local mask = actors[4]
      check(mask.x == eo.px and mask.y == eo.py - 16, label .. " bitmap_anchor")
      check(mask.eventObject == nil, label .. " independent_sprite")
      actors = { mask, front, ninja, back }
      local under, over = View.applyDrawOrder(actors, {}, {}, camY)
      check(#under == 4 and #over == 0, label .. " mask_priority_class")
      check(mask.subpriority == (ninja.subpriority - 1) % 256, label .. " linked_subpriority")
      check(mask.priority == 2 and not mask.fixedPriority, label .. " mask_fixed_state")
      check(eo.fixedClass == (fixed ~= false and 2 or nil), label .. " linked_fixed_class")
      local indices = {}
      for i, actor in ipairs(under) do indices[actor] = i end
      check(indices[back] < indices[front], label .. " unrelated_objects_order")
      if fixed == 0 then
        check(mask.subpriority == 255 and indices[mask] < indices[ninja], label .. " unsigned_wrap")
      else
        check(indices[ninja] < indices[mask], label .. " ninja_before_mask")
      end
      check(mask.x == eo.px and mask.y == eo.py - 16, label .. " sorting_preserves_position")
    end
  end
  eo.fixedPriority, eo.subpriority, eo.fixedClass = false, nil, nil
  eo.invisible = true
  check(maskFor(eo) == nil and #Objects.forDraw() == 0, label .. " linked_invisible")
  eo.invisible, eo.hidden = false, true
  check(maskFor(eo) == nil, label .. " linked_hidden")
  eo.hidden, eo.visible = false, false
  check(maskFor(eo) == nil, label .. " linked_not_visible")
  eo.visible = true
  Objects.revealTrainer(eo)
  Fx.stepObjects()
  check(eo.disguise.revealing and maskFor(eo) ~= nil and #Objects.forDraw() == 1,
    label .. " ninja_drawn_during_tear")
  for _ = 1, 100 do Fx.stepObjects() end
  check(eo.disguise.done and maskFor(eo) == nil and #Objects.forDraw() == 1,
    label .. " reveal_removes_only_mask")
  print("PASS disguise2763 " .. label .. " linked_order_visibility_reveal")
end

local version = arg and arg[1]
if version then
  GameVersion.set(version)
  Versions.select(version)
  local Cache = require("tests.game3_cache")
  local root = Cache.mount()
  if not root then
    print("[skip] disguise2763 cache integration: " .. tostring(Cache.reason))
    os.exit(0)
  end
  local cache = Cache.cache()
  local function data(rel)
    return assert(loadstring(assert(cache:read(root .. "/" .. rel)), "@" .. rel))()
  end
  sprites = data("ow/manifest.lua").sprites
  for _, row in ipairs(data("field_effects/objects.lua").objects) do
    if row.name == "tree_disguise" or row.name == "mountain_disguise" then
      row.image, row.quads = {}, {}
      for frame = 0, row.frames - 1 do row.quads[frame] = {} end
      sheets[row.name] = row
    end
  end
  local ninja = assert(cache:read(root .. "/ow/5.rgba"))
  for name in pairs(sheets) do
    local mask = assert(cache:read(root .. "/field_effects/" .. name .. ".rgba"))
    local opaque, covered = 0, 0
    for pixel = 0, 255 do
      if ninja:byte(pixel * 4 + 4) > 0 then
        opaque = opaque + 1
        if mask:byte((pixel + 256) * 4 + 4) > 0 then covered = covered + 1 end
      end
    end
    check(opaque == 124 and covered == opaque, version .. " " .. name .. " opaque_occlusion")
    print("PASS disguise2763 " .. version .. " " .. name .. " opaque_occlusion_124_of_124")
  end
  local count = 0
  for mapId, events in pairs(data("scripts/events.lua")) do
    for _, def in ipairs(events.objects or {}) do
      if def.movementType == 0x39 or def.movementType == 0x3A then
        exercise(def, version, version .. " " .. mapId .. " " .. def.localId)
        count = count + 1
      end
    end
  end
  check(count == (version == "emerald" and 7 or 5), version .. " all_cached_disguises")
  print("PASS disguise2763 " .. version .. " cached_disguises=" .. count)
else
  sprites[5] = { width = 16, height = 16 }
  for _, name in ipairs({ "tree_disguise", "mountain_disguise" }) do
    sheets[name] = { fw = 16, fh = 32, image = {}, quads = { [0] = {}, [1] = {} },
      anims = { { { "frame", 0, 2 }, { "end" } },
        { { "frame", 0, 2 }, { "frame", 1, 2 }, { "end" } } } }
  end
  for _, selected in ipairs({ "emerald", "ruby", "sapphire" }) do
    GameVersion.set(selected)
    Versions.select(selected)
    for _, movement in ipairs({ 0x39, 0x3A }) do
      exercise({ localId = 1, x = 12, y = 14, elevation = 3, graphicsId = 5,
        movementType = movement }, selected, selected .. " movement=" .. movement)
    end
  end
end
print("PASS game3_disguise_order_2763")

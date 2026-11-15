-- ../pokecrystal/engine/overworld/events.asm:512-572
-- ../pokecrystal/engine/items/pack.asm:425-470
-- ../pokecrystal/engine/items/pack.asm:860-884

local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")

local MOD = {
  ["mods/talk_use/manifest.json"] = [[{
    "id": "talk_use",
    "name": "talk use",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/talk_use/main.lua"] = [[
return function(mod)
  local e = mod.exports
  e.talks, e.uses = {}, {}
  e.spawn = function(mapId, def)
    e.npcId = mod.world:spawnNpc(mapId, def)
    return e.npcId
  end
  mod.hooks:wrap("world.talk", function(next, world, target)
    e.talks[#e.talks + 1] = target
    if target and target.def and target.def.owner == "talk_use" then
      mod.world:queueScript({ { "text", "HELLO FROM MOD" } })
      return
    end
    return next(world, target)
  end)
  mod.hooks:wrap("item.use", function(next, game, battle, id, target, pack)
    e.uses[#e.uses + 1] = { battle = battle, id = id, target = target, pack = pack }
    return next(game, battle, id, target, pack)
  end)
end
]],
}

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_talk_item_use"
  local version = game.save.version
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail ~= nil and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_mod_talk_item_use " .. tostring(version)
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  local function boxHas(top, needle)
    if not (top and top.pages) then return false end
    local function walk(value)
      if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
      if type(value) == "table" then
        for _, v in pairs(value) do if walk(v) then return true end end
      end
      return false
    end
    return walk(top.pages)
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map and world.vm, "world booted") then return finish() end

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 2, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.talk_use
  local out = loader.exports.talk_use
  if not check(mod and not mod.failed and out ~= nil, "mod loaded") then return finish() end

  world:warpToMapId("ROUTE_29", 20, 8, "left")
  U.wait(60)
  local p = world.player
  local template
  for _, obj in ipairs((world.map.def and world.map.def.objects) or {}) do
    if obj.sprite and not obj.trainer and not obj.itemball then template = obj break end
  end
  if not check(template ~= nil, "found an object shape to copy") then return finish() end
  local def = {}
  for k, v in pairs(template) do
    if k ~= "scriptKey" and k ~= "script" and k ~= "index" and k ~= "runtime"
        and k ~= "owner" and k ~= "trainer" and k ~= "itemball" then
      def[k] = v
    end
  end
  def.x, def.y = p.cellX - 1, p.cellY
  def.movement = 6
  local npcId = out.spawn(world.map.id, def)
  check(type(npcId) == "string", "spawnNpc returned an id", npcId)
  U.wait(10)
  local npc = world:npcAt(p.cellX - 1, p.cellY)
  check(npc ~= nil and npc.def and npc.def.runtime, "the spawned object stands in front of the player")
  if npc then U.still(game, dir .. "/talk_01_spawned_npc.png") end

  U.tap(game, "a")
  local said = false
  for _ = 1, 120 do
    if boxHas(game.stack:top(), "HELLO FROM MOD") then said = true break end
    U.wait(1)
  end
  check(#out.talks == 1, "world.talk fired once on the A press", #out.talks)
  check(out.talks[1] == npc, "with the spawned object as the target")
  check(said, "the mod's answer is on screen")
  if said then
    U.wait(90)
    U.still(game, dir .. "/talk_02_mod_answer.png")
  end
  for _ = 1, 120 do
    if not game.stack:top() or game.stack:top().pages == nil then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(10)

  game.save.inventory = game.save.inventory or {}
  game.save.inventory.REPEL = 2
  game.save.repelSteps = 0
  out.uses = {}
  game:pushStartMenuItem("pack")
  U.wait(20)
  local pack = game.stack:top()
  if not check(pack and getmetatable(pack) and getmetatable(pack).__index == PackMenu,
      "field PACK open") then return finish() end
  for i, pocket in ipairs(PackMenu.POCKETS) do
    if pocket.id == "ITEM" then pack.pocketIndex = i end
  end
  pack:rebuild()
  for i, row in ipairs(pack.rows) do
    if row.id == "REPEL" then pack.index = i end
  end
  check(pack.rows[pack.index] and pack.rows[pack.index].id == "REPEL", "REPEL row selected")
  pack:useSelected()
  U.wait(30)
  U.still(game, dir .. "/use_01_field_repel.png")
  check(#out.uses == 1, "item.use fired once for the field PACK USE", #out.uses)
  local use = out.uses[1] or {}
  check(use.id == "REPEL" and use.battle == nil and use.target == nil and use.pack == pack,
    "with (game, nil, REPEL, nil, pack)")
  check((game.save.repelSteps or 0) > 0, "next() ran the REPEL", game.save.repelSteps)
  check(game.save.inventory.REPEL == 1, "and spent one", game.save.inventory.REPEL)
  for _ = 1, 200 do
    local top = game.stack:top()
    if not top or top == world or top.isOverworld then break end
    U.tap(game, "b")
    U.wait(3)
  end
  U.wait(20)

  local lead = Mon.new(game.data, "DRAGONITE", 60)
  game.save.party = { lead }
  game.save.inventory.MASTER_BALL = 1
  game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
  game.save.pokedex.caught.PIDGEY = true
  out.uses = {}
  if not check(world:startBattle({ wild = Mon.new(game.data, "PIDGEY", 3) }), "battle started") then
    return finish()
  end
  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not check(screen ~= nil, "battle screen up") then return finish() end
  for _ = 1, 400 do
    if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
    U.tap(game, "a")
    U.wait(3)
  end
  screen:openPack()
  U.wait(10)
  local bpack = game.stack:top()
  check(bpack and bpack.battle == true, "battle PACK open")
  if bpack then
    for i, pocket in ipairs(PackMenu.POCKETS) do
      if pocket.id == "BALL" then bpack.pocketIndex = i end
    end
    bpack:rebuild()
    for i, row in ipairs(bpack.rows) do
      if row.id == "MASTER_BALL" then bpack.index = i end
    end
    bpack:useSelected()
  end
  U.wait(30)
  U.still(game, dir .. "/use_02_battle_ball.png")
  check(#out.uses == 1, "item.use fired once for the battle PACK use", #out.uses)
  use = out.uses[1] or {}
  check(use.id == "MASTER_BALL" and use.battle == screen and use.target == nil,
    "with (game, battleScreen, MASTER_BALL, nil)")
  for _ = 1, 3000 do
    local top = game.stack:top()
    if not (top and top.battle) then break end
    if screen.phase == "ask-nickname" and (screen.messageTimer or 0) <= 0 then
      U.tap(game, "b")
    else
      U.tap(game, "a")
    end
    U.wait(2)
  end
  check(screen.battle and screen.battle.outcome == "caught", "next() threw the ball and caught PIDGEY")
  finish()
end

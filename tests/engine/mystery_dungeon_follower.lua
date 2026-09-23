package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Sprite = require("src.import.pmd.Sprite")
local Runtime = require("src.mods.Runtime")
local Writer = require("src.import.LuaWriter")
local path = "mods/mystery_dungeon_follower/"
local function read(file) local f = assert(io.open(file)); local s = f:read("*a"); f:close(); return s end
local animations = Writer.encode({ animations = {{1,1,1,1,1,1,1,1}}, sequences = {{{1,8,0,0,0,0,0}}} })
local entries = {}
for i, id in ipairs({"pikachu", "bulbasaur", "unown_a", "unown_qmark", "deoxys_attack", "deoxys_defense"}) do
  entries[id] = { file = id .. ".png", size = 4, width = 32, height = 32, frames = 1,
    sprite = { monsterId = i, dexNumber = ({25,1,201,201,386,386})[i],
      frameWidth = 32, frameHeight = 32, frameColumns = 1, anchorX = 16, anchorY = 24 },
    metadata = { file = id .. ".lua", size = #animations } }
end
local files = {
  [path .. "manifest.json"] = read(path .. "manifest.json"),
  [path .. "main.lua"] = read(path .. "main.lua"),
  ["asset_packs/pmd_red/sprites/pack.lua"] = Writer.encode({ format = 1, importer = "pmd_red",
    pack = "sprites", kind = "sprite", version = "1.0.0", source = {md5="test",name="PMD"}, entries = entries }),
}
for id in pairs(entries) do
  files["asset_packs/pmd_red/sprites/" .. id .. ".lua"] = animations
  files["asset_packs/pmd_red/sprites/" .. id .. ".png"] = "PNG!"
end
local originalNew = Sprite.new
Sprite.new = function(entry, metadata)
  T.check(metadata.sequences ~= nil, "animation sidecar reaches renderer")
  return { id = entry.id, step = function(self) self.stepped = true end }
end
local npc = {}
for _, name in ipairs({"src.world.PikachuFollower", "src.world.gen2.Follower", "src.world.game3.Follower"}) do
  package.loaded[name] = { current = function() return npc end }
end
package.loaded["src.core.game3.pokemon"] = {
  national = function(id) return id end, unownLetter = function(n) return n end,
}
for _, version in ipairs({"red", "yellow", "gold", "crystal", "firered", "leafgreen"}) do
  Version.set(version)
  local gen = Version.generation()
  local run = T.sdk.loadMods({path:sub(1,-2)}, {
    fs = T.sdk.memfs(files), generation = gen,
    data = gen == 3 and T.sdk.gen3Data() or nil,
  })
  T.eq(#run.errors, 0, version .. " example loads with declared pack")
  local save = {party={{species=gen == 3 and 25 or "PIKACHU",hp=10}}}
  local world = { player = {} }
  local game = {save=save,overworld=world}
  if gen == 3 then game.session = save end
  local function spawn() return Runtime.call("world.follower.spawn", function() return false end, game, world) end
  T.check(spawn(), version .. " healthy lead enables follower")
  T.eq(npc.sprite.id, "pikachu", version .. " lead chooses Pikachu")
  save.party[1] = { species=gen == 3 and 1 or "BULBASAUR",hp=5 }
  T.check(spawn(), version .. " party reorder stays enabled")
  T.eq(npc.sprite.id, "bulbasaur", version .. " party reorder changes sheet")
  world.player.surfing = true
  T.check(not spawn(), version .. " surfing hides companion")
  world.player.surfing = false
  save.party[1].isEgg = true
  T.check(not spawn(), version .. " egg lead is hidden")
  save.party[1].isEgg, save.party[1].hp = nil, 0
  T.check(not spawn(), version .. " fainted lead is hidden")
  save.party = {}
  T.check(not spawn(), version .. " empty party is hidden")
  if gen == 3 then
    save.party = {{species=386,hp=10}}
    T.check(spawn(), "Deoxys enabled")
    T.eq(npc.sprite.id, version == "leafgreen" and "deoxys_defense" or "deoxys_attack", "version chooses Deoxys form")
    save.party = {{species=201,hp=10,personality=27}}
    T.check(spawn(), "Unown enabled")
    T.eq(npc.sprite.id, "unown_qmark", "personality chooses Unown form")
  end
  Runtime.hooks:removeOwner("mystery_dungeon_follower")
  T.check(not spawn(), "removing mod restores native spawn predicate")
  run.release()
end
Sprite.new = originalNew
T.finish("mystery_dungeon_follower")

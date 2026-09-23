local mod = ...
local Version = require("src.core.GameVersion")
local Sprite = require("src.import.pmd.Sprite")
local generation = Version.generation()
local follower = require(generation == 3 and "src.world.game3.Follower"
  or generation == 2 and "src.world.gen2.Follower" or "src.world.PikachuFollower")
local entries, byDex = {}, {}
for _, entry in ipairs(assert(mod.packs:entries("pmd_red", "sprites"))) do
  entries[entry.id] = entry
  local dex = entry.sprite and entry.sprite.dexNumber
  if dex and dex > 0 and (not byDex[dex]
      or entry.sprite.monsterId < byDex[dex].sprite.monsterId) then byDex[dex] = entry end
end

-- The existing Gen 1/2 follower factories need a sprite before their first tick.
if generation < 3 then
  mod.content.sprites:override("SPRITE_PIKACHU", Sprite.definition(assert(entries.pikachu)))
end

local activeId, renderer
local FOLLOWER_GAP = 4
local function updateSpacing(npc, player)
  if not (renderer and npc and player and npc.px and npc.py and player.px and player.py) then return end
  local dx, dy = player.px - npc.px, player.py - npc.py
  -- Ease the extra space out as they overlap at a warp or pass each other.
  local distance = math.max(16, math.sqrt(dx * dx + dy * dy))
  renderer.anchorX = renderer.def.anchorX + dx / distance * FOLLOWER_GAP
  renderer.anchorY = renderer.def.anchorY + dy / distance * FOLLOWER_GAP
end

local function entryFor(mon)
  if not mon or mon.isEgg or mon.egg or (tonumber(mon.hp) or 0) <= 0 then return nil end
  local species = mon.species or mon.speciesId
  local id
  if generation == 3 then
    local Pokemon = require("src.core.game3.pokemon")
    local dex = Pokemon.national(species)
    if dex == 201 then
      local letter = Pokemon.unownLetter(mon.personality or 0)
      id = letter < 26 and ("unown_" .. string.char(97 + letter))
        or (letter == 26 and "unown_emark" or "unown_qmark")
    elseif dex == 386 then
      id = Version.get() == "leafgreen" and "deoxys_defense" or "deoxys_attack"
    else return byDex[dex] end
  elseif type(species) == "string" then
    id = species:lower()
    if id == "unown" then
      local letter = require("src.core.gen2.Unown").monLetter(mon)
      id = "unown_" .. string.char(96 + letter)
    end
  end
  return entries[id]
end

mod.hooks:wrap("world.follower.spawn", function(_, game, world)
  local save = game and (game.session or game.save)
  local player = world and world.player
  if not save or not player or save.onBike or player.biking or player.surfing
      or player.visible == false or player.hidden or player.fishing then return false end
  local entry = entryFor(save.party and save.party[1])
  if not entry then return false end
  if activeId ~= entry.id then
    renderer, activeId = Sprite.new(entry,
      assert(mod.packs:metadata("pmd_red", "sprites", entry.id))), entry.id
  end
  local npc = follower.current(world)
  if npc then
    npc.sprite = renderer
    updateSpacing(npc, player)
  end
  return true
end)

mod.hooks:wrap("input.step", function(next, game, dt)
  local result = next(game, dt)
  local world = game.overworld or game.world
  local npc = generation == 3 and follower.current() or (world and follower.current(world))
  if npc and renderer then
    npc.sprite = renderer
    local player = generation == 3 and require("src.core.game3.player") or (world and world.player)
    updateSpacing(npc, player)
    renderer:step(npc.moving)
  end
  return result
end)

mod.exports.entryFor = entryFor

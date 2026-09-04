-- engine/battle/battle_transitions.asm:28

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local OW = require("src.world.OverworldController")
local Commands = require("src.script.Commands")
local Renderer = require("src.render.Renderer")

local player = { id = "player" }
local trainer = { id = "trainer" }
local bystander = { id = "bystander" }

do
  local ow = { player = player }
  check(OW.oamCulled(ow, bystander) == false,
        "no transition up: nothing is culled")
  check(OW.oamCulled(ow, player) == false, "no transition up: the player draws")

  ow.battleOamKeep = false
  check(OW.oamCulled(ow, player) == false, "wild battle keeps the player block")
  check(OW.oamCulled(ow, trainer) == true, "wild battle clears every other block")

  ow.battleOamKeep = trainer
  check(OW.oamCulled(ow, player) == false, "trainer battle keeps the player")
  check(OW.oamCulled(ow, trainer) == false, "trainer battle keeps the engaged NPC")
  check(OW.oamCulled(ow, bystander) == true, "trainer battle clears bystanders")
end

do
  local got
  local ctx = { npc = trainer, overworld = {
    pushBattle = function(_, _, keep) got = keep end } }
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, trainer, "a scripted trainer battle keeps the talked-to NPC")
  got = "unset"
  -- home/text_script.asm:8
  Commands.pushBattle(ctx, { kind = "wild" })
  eq(got, trainer, "a scripted wild battle keeps the talked-to NPC (#2119)")
  local oak = { id = "oak" }
  local bare = { overworld = ctx.overworld }
  got = "unset"
  Commands.pushBattle(bare, { kind = "wild" }, oak)
  eq(got, oak, "an explicit keep wins when the ctx has no npc")
  got = "unset"
  Commands.pushBattle(ctx, { kind = "wild" }, oak)
  eq(got, oak, "an explicit keep wins over ctx.npc")
  got = "unset"
  Commands.pushBattle(bare, { kind = "wild" })
  eq(got, nil, "no npc and no keep: the player only")
end

-- home/text_script.asm:8
do
  local rival = { id = "rival" }
  local other = { id = "other" }
  local got
  local ow = {
    player = player,
    pushBattle = function(_, _, keep) got = keep end,
    npcByIndex = function(_, i)
      if i == 1 then return rival elseif i == 2 then return other end
    end,
  }
  local ctx = { overworld = ow, runner = {} }
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, nil, "an unaddressed ambush still keeps nothing")
  Commands.face_object(ctx, 1, "down")
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, rival, "face_object stamps the sprite an ambush battle keeps")
  Commands.place_npc(ctx, 2, 3, 4)
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, other, "place_npc restamps, like hSpriteIndex being overwritten")
  Commands.walk_npc(ctx, 1, {})
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, rival, "walk_npc stamps the object it moves")
  Commands.walk_npc(ctx, "player", {})
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, rival, "walk_npc \"player\" leaves the stamp alone")
  local talked = { id = "talked" }
  ctx.npc = talked
  Commands.pushBattle(ctx, { kind = "trainer" })
  eq(got, talked, "a talked-to npc still wins over the script stamp")
  Commands.pushBattle(ctx, { kind = "trainer" }, other)
  eq(got, other, "an explicit keep still wins over both")
end

do
  Renderer.wipeSprites = function() end
  Renderer.wipeWox, Renderer.wipeWoy = 1, 2
  Renderer.wipeSx, Renderer.wipeSy = 3, 4
  Renderer.battleWipe = { prog = 0.5 }
  local ok = pcall(Renderer.beginFrame, Renderer, true)
  check(ok, "beginFrame runs headless")
  check(Renderer.wipeSprites == nil, "beginFrame drops last frame's survivors")
  check(Renderer.wipeWox == nil and Renderer.wipeWoy == nil
        and Renderer.wipeSx == nil and Renderer.wipeSy == nil,
        "beginFrame drops last frame's world placement")
  check(Renderer.battleWipe == nil, "beginFrame drops last frame's wipe")
end

do
  local f = io.open("src/render/Renderer.lua", "rb")
  check(f ~= nil, "Renderer source is readable")
  local src = f:read("*a")
  f:close()
  local guard = src:match("if self%.wipeSprites and self%.wipeWox%s*\n"
                          .. "%s*and %(self%.battleWipe%.prog or 0%) < 1 then")
  check(guard ~= nil,
        "the survivor replay stops at prog >= 1 (BattleTransition_BlackScreen)")
  local body = src:match("drawBattleWipe%(self%.battleWipe.-\n  end\n")
  check(body ~= nil and body:find("pcall%(self%.wipeSprites%)") ~= nil,
        "the replay runs after drawBattleWipe, not before it")
end

do
  local PaletteFX = require("src.render.PaletteFX")
  local savedMode = PaletteFX.mode
  PaletteFX.setMode("ogred")
  local seen = {}
  local function ent()
    return { px = 0, py = 0,
             draw = function() seen[#seen + 1] = PaletteFX.spriteRedrawPassActive() end }
  end
  local keep, hero = ent(), ent()
  local ow = { camera = { x = 0, y = 0 }, player = hero, battleOamKeep = keep,
               sgbWorldZones = function() return nil end }
  PaletteFX.setPass("ui")
  local ok, err = pcall(OW.drawWipeSprites, ow)
  check(ok, "drawWipeSprites runs headless: " .. tostring(err))
  eq(#seen, 2, "both survivors are replayed")
  check(seen[1] == true and seen[2] == true,
        "OG RED replays inside the world pass so SpriteRenderer takes the ogObj bake")
  eq(PaletteFX.pass(), "ui", "the caller's pass is restored")
  PaletteFX.setPass(nil)
  PaletteFX.setMode(savedMode)
end

do
  local f = io.open("src/world/OverworldController.lua", "rb")
  check(f ~= nil, "OverworldController source is readable")
  local src = f:read("*a")
  f:close()
  check(src:find("Game.renderer.wipeSprites = self.wipeSpritesFn", 1, true) ~= nil,
        "drawWorld hands over the hoisted closure instead of allocating one")
  check(src:find("self.wipeSpritesFn = function() self:drawWipeSprites() end",
                 1, true) ~= nil,
        "pushBattle owns the one closure")
end

T.finish("battle_transition_oam_bug1948")

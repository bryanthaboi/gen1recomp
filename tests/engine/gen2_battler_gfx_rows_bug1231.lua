-- engine/battle_anims/anim_commands.asm:755 BattleAnimCmd_BattlerGFX_1Row

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local AnimRunner = require("src.battle.gen2.AnimRunner")

local function findLoaded(runner, gfx)
  for _, entry in ipairs(runner.loaded) do
    if entry.gfx == gfx then return entry end
  end
  return nil
end

do
  local runner = AnimRunner.new({})
  runner:start(nil)
  runner:loadBattlerGfx(1)
  local head = findLoaded(runner, "BATTLE_ANIM_GFX_PLAYERHEAD")
  local feet = findLoaded(runner, "BATTLE_ANIM_GFX_ENEMYFEET")
  T.check(head and feet, "both pseudo-sheets registered")
  T.eq(head.battler, "enemy",
    "GFX_PLAYERHEAD's tiles are the ENEMY's feet row")
  T.eq(head.tiles, 7, "seven tiles, the enemy pic's width")
  T.eq(head.tile, (0x80 - 6 - 7) - 49, "at the asm's fixed base")
  T.eq(feet.battler, "player",
    "GFX_ENEMYFEET's tiles are the PLAYER's head row")
  T.eq(feet.tiles, 6, "six tiles, the backpic's width")
  T.eq(feet.tile, (0x80 - 6) - 49, "at the asm's fixed base")
  T.eq(head.rows, 1, "one row each")
  T.eq(feet.rows, 1, "on both sheets")
end

do
  local runner = AnimRunner.new({})
  runner:start(nil)
  runner:loadBattlerGfx(2)
  local head = findLoaded(runner, "BATTLE_ANIM_GFX_PLAYERHEAD")
  local feet = findLoaded(runner, "BATTLE_ANIM_GFX_ENEMYFEET")
  T.eq(head.battler, "enemy", "2ROW keeps the same crossing")
  T.eq(head.tiles, 14, "two enemy rows")
  T.eq(feet.battler, "player", "on both sides")
  T.eq(feet.tiles, 12, "two player rows")
  T.eq(head.tile, (0x80 - 6 * 2 - 7 * 2) - 49, "2ROW base")
  T.eq(feet.tile, (0x80 - 6 * 2) - 49, "2ROW base")
end

-- engine/battle_anims/anim_commands.asm:317
do
  local runner = AnimRunner.new({})
  runner:start(nil)
  AnimRunner.COMMANDS.battlergfx_1row(runner)
  local head = findLoaded(runner, "BATTLE_ANIM_GFX_PLAYERHEAD")
  local feet = findLoaded(runner, "BATTLE_ANIM_GFX_ENEMYFEET")
  T.eq(head and head.battler, "enemy", "the script command routes the same way")
  T.eq(head.rows, 2, "$da's macro says 1row, its jumptable slot says _2Row")
  T.eq(head.tiles, 14, "two enemy rows")
  T.eq(head.tile, (0x80 - 6 * 2 - 7 * 2) - 49, "at the _2Row base")
  T.eq(feet.tiles, 12, "two player rows")
  T.eq(feet.tile, (0x80 - 6 * 2) - 49, "at the _2Row base")
end

do
  local runner = AnimRunner.new({})
  runner:start(nil)
  AnimRunner.COMMANDS.battlergfx_2row(runner)
  local head = findLoaded(runner, "BATTLE_ANIM_GFX_PLAYERHEAD")
  local feet = findLoaded(runner, "BATTLE_ANIM_GFX_ENEMYFEET")
  T.eq(head.rows, 1, "$d9's macro says 2row, its jumptable slot says _1Row")
  T.eq(head.tiles, 7, "one enemy row")
  T.eq(head.tile, (0x80 - 6 - 7) - 49, "at the _1Row base")
  T.eq(feet.tiles, 6, "one player row")
  T.eq(feet.tile, (0x80 - 6) - 49, "at the _1Row base")
end

T.finish("gen2 battler gfx row attribution bug 1231")

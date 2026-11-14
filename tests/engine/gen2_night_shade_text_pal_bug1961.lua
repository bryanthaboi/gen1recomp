-- engine/battle_anims/anim_commands.asm:1293
-- engine/gfx/cgb_layouts.asm:146

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local GbcPalette = require("src.render.GbcPalette")
local Chrome = require("src.ui.gen2.Chrome")
local BattleState = require("src.ui.gen2.BattleState")

require("src.core.Logger").warn = function() end

GbcPalette.available = function() return true end

-- data/moves/animations.asm:2621
local NIGHT_SHADE_BGP = 0x1b

do
  local boxes = {}
  local clearBgp = "unset"
  Chrome.paletteBox = function(tx, ty)
    boxes[#boxes + 1] = { ty = ty, bgp = GbcPalette.bgp }
  end
  Chrome.clear = function() clearBgp = GbcPalette.bgp end

  local hudBgp = "unset"
  local state = setmetatable({
    battle = { player = { species = 1 }, enemy = { species = 2 } },
    phase = "message",
    palettes = { battleText = {
      { 255, 255, 255 }, { 140, 156, 255 }, { 115, 132, 255 }, { 0, 0, 0 },
    } },
    drawHud = function() hudBgp = GbcPalette.bgp end,
    printMessage = function() end,
  }, { __index = BattleState })

  GbcPalette.setBgp(NIGHT_SHADE_BGP)
  BattleState.drawPanel(state)

  T.eq(clearBgp, NIGHT_SHADE_BGP,
    "the battle backdrop is palette 0 and takes the byte")
  T.eq(hudBgp, NIGHT_SHADE_BGP,
    "the HUD is BG palettes 2/3/4 and takes the byte")
  local message
  for _, box in ipairs(boxes) do
    if box.ty == 12 then message = box end
  end
  T.check(message, "the bottom message box was drawn")
  T.eq(message.bgp, nil,
    "PAL_BATTLE_BG_TEXT is palette 7: CopyPals c,7 never reaches it")
  T.eq(GbcPalette.bgp, NIGHT_SHADE_BGP,
    "drawPanel puts the byte back for anything drawn after it")
  GbcPalette.setBgp(nil)
end

do
  local liftBgp = {}
  local state = setmetatable({
    battle = { player = { species = 1 }, enemy = { species = 2 } },
    anim = {
      picOverride = {},
      bg = {
        bgp = NIGHT_SHADE_BGP,
        hidden = {},
        -- data/moves/animations.asm:4814
        liftedRows = { player = { 0, 2 } },
        picSize = {},
        slide = {},
        monShade = {},
      },
    },
    drawPic = function(_, _, back)
      liftBgp[back and "player" or "enemy"] = GbcPalette.bgp
    end,
  }, { __index = BattleState })

  BattleState.drawLiftedRows(state)

  T.eq(liftBgp.player, NIGHT_SHADE_BGP,
    "the lifted band is PAL_BATTLE_OB_PLAYER and inverts with the BG")
  T.eq(liftBgp.enemy, nil, "only the lifted side is drawn in the lift pass")
  T.eq(GbcPalette.bgp, nil, "the byte does not leak out of the lift pass")
end

T.finish("gen2 night shade text palette bug 1961")

-- sevii/game3 package entry.

local Game3 = {
  Runtime = require("src.core.game3.runtime"),
  Display = require("src.core.game3.display"),
  Gfx = require("src.core.game3.gfx"),
  Field = require("src.core.game3.field"),
  FieldView = require("src.core.game3.field_view"),
  Player = require("src.core.game3.player"),
  Collision = require("src.core.game3.collision"),
  Bridge = require("src.core.game3.bridge"),
  Party = require("src.core.game3.party"),
  Bag = require("src.core.game3.bag"),
  Items = require("src.core.game3.items"),
  Dex = require("src.core.game3.dex"),
  Map = require("src.core.game3.map"),
  Warp = require("src.core.game3.warp"),
  Objects = require("src.core.game3.objects"),
  Weather = require("src.core.game3.weather"),
  Encounters = require("src.core.game3.encounters"),
  Battle = require("src.core.game3.battle"),
  BattleBridge = require("src.core.game3.battle_bridge"),
  BattleDowngrade = require("src.core.game3.battle_downgrade"),
  Palette = require("src.core.game3.palette"),
  NativeTileset = require("src.core.game3.tileset_native"),
  LayoutNative = require("src.core.game3.layout_native"),
  OwSprites = require("src.core.game3.ow_sprites"),
  Oam = require("src.core.game3.oam"),
  Bg = require("src.core.game3.bg"),
  TilesetAnim = require("src.core.game3.tileset_anim"),
  FieldEffects = require("src.core.game3.field_effects"),
  Hud = require("src.ui.game3.hud"),
  SummaryMenu = require("src.ui.game3.summary_menu"),
}

function Game3.install(mod)
  Game3.Runtime.install(mod)
  Game3.Encounters.loadFromMod(mod)
  Game3.BattleBridge.installWhiteoutIntercept(mod, mod.game)
end

function Game3.isActive()
  return Game3.Runtime.isActive()
end

return Game3

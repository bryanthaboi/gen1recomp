-- Regression coverage for #1345 (BattleState:sgbBattlePals bar bypassing
-- PaletteFX.pal), #1346 (SummaryMenu double-tinting the HP fill) and #1340
-- (animSpriteColors hardcoding the SGB anim model).  engine/gfx/palettes.asm
-- SetPal_Battle, engine/pokemon/status_screen.asm:120-125,
-- engine/battle/animations.asm:551-578.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity hpcolor og palette")
local check, eq, same = S.check, S.eq, S.same

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local PaletteFX = require("src.render.PaletteFX")
local GameVersion = require("src.core.GameVersion")
local BattleState = require("src.battle.BattleState")
local HudTiles = require("src.render.HudTiles")
local SummaryMenu = require("src.ui.SummaryMenu")
local Pokemon = require("src.pokemon.Pokemon")
local Sound = require("src.core.Sound")

Sound.playCry = function() end

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode

local function setup(version, mode)
  GameVersion.set(version)
  PaletteFX.setMode(mode)
end

local function colorEq(got, want, msg)
  local ok = got and want and got[1] == want[1] and got[2] == want[2]
             and got[3] == want[3]
  return check(ok, ("%s (got %s, want %s)"):format(msg,
    got and ("(%d,%d,%d)"):format(got[1], got[2], got[3]) or "nil",
    want and ("(%d,%d,%d)"):format(want[1], want[2], want[3]) or "nil"))
end

local function bucket(r)
  if r > 0.83 then return 1 elseif r > 0.5 then return 2
  elseif r > 0.17 then return 3 else return 4 end
end

-- ------------------------------------------------------- #1345 bar() routes
-- through PaletteFX.pal instead of the raw SGB pack
local ZONE0 = {
  { "red", "gbc", { 255, 239, 255 }, { 247, 214, 123 }, { 74, 165, 90 }, { 25, 16, 16 } },
  { "blue", "gbc", { 255, 239, 255 }, { 247, 214, 123 }, { 74, 165, 90 }, { 25, 16, 16 } },
  -- pokeyellow/data/sgb/sgb_palettes.asm:35 PAL_GREENBAR
  { "yellow", "gbc", { 255, 255, 247 }, { 255, 255, 156 }, { 0, 173, 0 }, { 49, 49, 49 } },
  { "red", "ogred", { 255, 255, 255 }, { 255, 132, 132 }, { 148, 58, 58 }, { 0, 0, 0 } },
  { "blue", "ogred", { 255, 255, 255 }, { 99, 165, 255 }, { 0, 0, 255 }, { 0, 0, 0 } },
  { "yellow", "ogred", { 255, 255, 255 }, { 255, 255, 0 }, { 0, 255, 0 }, { 25, 25, 25 } },
}

local function fullHpBattle()
  return {
    data = Data,
    player = { mon = { hp = 20, stats = { hp = 20 } } },
    enemy = { mon = { hp = 20, stats = { hp = 20 } } },
  }
end

for _, c in ipairs(ZONE0) do
  local version, mode = c[1], c[2]
  setup(version, mode)
  local pals = BattleState.sgbBattlePals(fullHpBattle())
  check(pals ~= nil, ("%s/%s sgbBattlePals returns four zones"):format(version, mode))
  local zone0 = pals and pals[0]
  colorEq(zone0 and zone0[1], c[3], ("%s/%s zone0 color0"):format(version, mode))
  colorEq(zone0 and zone0[2], c[4], ("%s/%s zone0 color1 (GetHealthBarColor)"):format(version, mode))
  colorEq(zone0 and zone0[3], c[5], ("%s/%s zone0 color2 (bar fill)"):format(version, mode))
  colorEq(zone0 and zone0[4], c[6], ("%s/%s zone0 color3"):format(version, mode))
end

-- --------------------------------------------- #1345 placeholder branch lock
-- OG RED / OG BLUE: zones 2/3 must land on the version's boot-ROM BG
-- endpoints regardless of placeholder, never the raw SGB pack's paper/ink.
for _, version in ipairs({ "red", "blue" }) do
  setup(version, "ogred")
  local white = PaletteFX.ogBg()[1]
  local black = PaletteFX.ogBg()[4]
  for _, ph in ipairs({ false, true }) do
    local fake = fullHpBattle()
    fake.showPlayerBack, fake.showEnemyTrainer = ph, ph
    local pals = BattleState.sgbBattlePals(fake)
    for _, z in ipairs({ 2, 3 }) do
      local zone = pals[z]
      colorEq(zone[1], white, ("%s/ogred placeholder=%s zone%d color0 is boot-ROM white")
        :format(version, tostring(ph), z))
      colorEq(zone[4], black, ("%s/ogred placeholder=%s zone%d color3 is boot-ROM black")
        :format(version, tostring(ph), z))
      check(not (zone[1][1] == 255 and zone[1][2] == 239 and zone[1][3] == 255),
        ("%s/ogred placeholder=%s zone%d color0 is not the raw SGB paper")
          :format(version, tostring(ph), z))
      check(not (zone[4][1] == 25 and zone[4][2] == 16 and zone[4][3] == 16),
        ("%s/ogred placeholder=%s zone%d color3 is not the raw SGB ink")
          :format(version, tostring(ph), z))
    end
  end
  setup(version, "ogred")
  local off = BattleState.sgbBattlePals(fullHpBattle())
  local fakeOn = fullHpBattle()
  fakeOn.showPlayerBack, fakeOn.showEnemyTrainer = true, true
  local on = BattleState.sgbBattlePals(fakeOn)
  for _, z in ipairs({ 2, 3 }) do
    same(off[z], on[z], ("%s/ogred zone%d is byte-identical placeholder or not")
      :format(version, z))
  end
end

-- Yellow keeps the raw MEWMON pack in both gbc and ogred (usesYellowCgb
-- guards both call sites), so placeholder must be byte-identical across modes.
do
  setup("yellow", "gbc")
  local fakeGbc = fullHpBattle()
  fakeGbc.showPlayerBack, fakeGbc.showEnemyTrainer = true, true
  local gbcPals = BattleState.sgbBattlePals(fakeGbc)

  setup("yellow", "ogred")
  local fakeOgred = fullHpBattle()
  fakeOgred.showPlayerBack, fakeOgred.showEnemyTrainer = true, true
  local ogredPals = BattleState.sgbBattlePals(fakeOgred)

  for _, z in ipairs({ 2, 3 }) do
    same(ogredPals[z], gbcPals[z],
      ("yellow/ogred placeholder zone%d is byte-identical to yellow/gbc"):format(z))
  end
end

-- ------------------------------------------------------- #1345 blackout lock
-- OG RED / OG BLUE blacked-out zones must be the boot-ROM white/black, not
-- the raw PAL_BLACK pack.  Yellow keeps the raw pack in both modes.
for _, version in ipairs({ "red", "blue" }) do
  setup(version, "ogred")
  local white = PaletteFX.ogBg()[1]
  local black = PaletteFX.ogBg()[4]
  local fake = fullHpBattle()
  fake.blackedOut = true
  local pals = BattleState.sgbBattlePals(fake)
  check(pals ~= nil, ("%s/ogred blackout still returns four zones"):format(version))
  for z = 0, 3 do
    colorEq(pals[z][1], white, ("%s/ogred blackout zone%d color0 is boot-ROM white"):format(version, z))
    colorEq(pals[z][4], black, ("%s/ogred blackout zone%d color3 is boot-ROM black"):format(version, z))
    check(not (pals[z][1][1] == 255 and pals[z][1][2] == 239 and pals[z][1][3] == 255),
      ("%s/ogred blackout zone%d color0 is not the raw PAL_BLACK paper"):format(version, z))
  end
end

do
  setup("yellow", "gbc")
  local gbcOut = BattleState.sgbBattlePals({ data = Data, blackedOut = true,
    player = { mon = {} }, enemy = { mon = {} } })
  setup("yellow", "ogred")
  local ogredOut = BattleState.sgbBattlePals({ data = Data, blackedOut = true,
    player = { mon = {} }, enemy = { mon = {} } })
  same(ogredOut[0], gbcOut[0], "yellow/ogred blackout is byte-identical to yellow/gbc")
end

-- ------------------------------------------------------- #1346 grayFill guard
-- SummaryMenu:draw must pass grayFill behind the same barZoned guard
-- PartyMenu already used, or the fill double-applies through the zone pass.
local SUMMARY = {
  { "blue", "ogred", { 0, 0, 0 }, { 0, 0, 255 } },
  { "red", "gbc", { 25, 16, 16 }, { 74, 165, 90 } },
  { "red", "redpp", { 0, 0, 0 }, { 0, 189, 0 } },
  { "yellow", "ogred", { 25, 25, 25 }, { 0, 255, 0 } },
  { "red", "ogred", { 148, 58, 58 }, { 148, 58, 58 } },
}

for _, c in ipairs(SUMMARY) do
  local version, mode, wantOld, wantNew = c[1], c[2], c[3], c[4]
  setup(version, mode)

  local mon = Pokemon.new(Data, "BULBASAUR", 20)
  mon.hp = mon.stats.hp
  local game = { data = Data,
    save = { options = {}, player = { id = 1, name = "RED" } } }
  local menu = SummaryMenu.new(game, mon)

  local realBar = HudTiles.drawHPBar
  local realShader = PaletteFX.shader
  local seenGrayFill
  HudTiles.drawHPBar = function(_, _, _, _, _, grayFill)
    seenGrayFill = grayFill and true or false
  end
  PaletteFX.shader = function() return { send = function() end } end
  local ok, err = pcall(function() menu:draw() end)
  HudTiles.drawHPBar, PaletteFX.shader = realBar, realShader
  check(ok, ("%s/%s SummaryMenu:draw runs headless%s"):format(version, mode,
    ok and "" or (": " .. tostring(err))))
  check(seenGrayFill == true,
    ("%s/%s SummaryMenu:draw asks for a gray fill when a zone pass will run")
      :format(version, mode))

  local pal = PaletteFX.pal(Data, "GREENBAR")
  check(pal ~= nil, ("%s/%s GREENBAR resolves"):format(version, mode))
  local predicted
  if seenGrayFill then
    predicted = pal[bucket(85 / 255)]
  else
    local tintR = math.min(1, pal[3][1] / 170)
    predicted = pal[bucket((85 / 255) * tintR)]
  end
  colorEq(predicted, wantNew,
    ("%s/%s summary HP fill matches the fixed color"):format(version, mode))

  local oldPredicted = pal[bucket((85 / 255) * math.min(1, pal[3][1] / 170))]
  colorEq(oldPredicted, wantOld,
    ("%s/%s summary HP fill's pre-fix formula reproduces the reported color")
      :format(version, mode))
end

-- ---------------------------------------------------- #1340 animSpriteColors
local ANIM = {
  { "red", "ogred", { 123, 255, 49 }, { 0, 132, 0 }, { 0, 0, 0 } },
  { "blue", "ogred", { 255, 132, 132 }, { 148, 58, 58 }, { 0, 0, 0 } },
  { "red", "gbc", { 255, 239, 255 }, { 25, 16, 16 }, { 25, 16, 16 } },
  { "blue", "gbc", { 255, 239, 255 }, { 25, 16, 16 }, { 25, 16, 16 } },
  -- pokeyellow/data/sgb/sgb_palettes.asm:35 PAL_GREENBAR
  { "yellow", "gbc", { 255, 255, 247 }, { 49, 49, 49 }, { 49, 49, 49 } },
  { "yellow", "ogred", { 255, 255, 247 }, { 49, 49, 49 }, { 49, 49, 49 } },
}

for _, c in ipairs(ANIM) do
  local version, mode = c[1], c[2]
  setup(version, mode)
  local zone = PaletteFX.pack(Data).palettes.GREENBAR
  local fake = { data = Data, zoneColorsAt = function() return zone end }
  local s = { obp = "f0", x = 72, y = 80 }
  local out = BattleState.animSpriteColors(fake, s, 64, 64)
  check(out ~= nil, ("%s/%s animSpriteColors returns a triple"):format(version, mode))
  local rounded = {}
  for i = 1, 3 do
    rounded[i] = out and {
      math.floor(out[i][1] * 255 + 0.5),
      math.floor(out[i][2] * 255 + 0.5),
      math.floor(out[i][3] * 255 + 0.5),
    } or nil
  end
  colorEq(rounded[1], c[3], ("%s/%s animSpriteColors f0 shade0"):format(version, mode))
  colorEq(rounded[2], c[4], ("%s/%s animSpriteColors f0 shade1"):format(version, mode))
  colorEq(rounded[3], c[5], ("%s/%s animSpriteColors f0 shade2"):format(version, mode))
end

GameVersion.set("red")
eq(PaletteFX.usesSpriteObp("ogred"), true, "OG RED uses the boot-ROM OBJ ramp for anims")
GameVersion.set("yellow")
eq(PaletteFX.usesSpriteObp("ogred"), false, "OG YELLOW keeps the SGB anim model")

GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)
S.finish()

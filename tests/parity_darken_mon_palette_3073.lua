package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity darken mon palette")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local BattleState = require("src.battle.BattleState")

local prevVersion, prevMode = GameVersion.current, PaletteFX.mode

local function fmt(m)
  return m and (m[0] .. m[1] .. m[2] .. m[3]) or "nil"
end

-- engine/battle/animations.asm:1060
-- pokeyellow/engine/gfx/palettes.asm:543
local SGB = {
  red    = { ogred = false, gbc = true, redpp = true, og = false,
             og_inv = false, gbc_inv = true, classic = false },
  blue   = { ogred = false, gbc = true, redpp = true, og = false,
             og_inv = false, gbc_inv = true, classic = false },
  yellow = { ogred = true, gbc = true, redpp = true, og = false,
             og_inv = false, gbc_inv = true, classic = false },
}

for _, version in ipairs({ "red", "blue", "yellow" }) do
  GameVersion.set(version)
  for _, mode in ipairs(PaletteFX.MODES) do
    PaletteFX.mode = mode
    local onSgb = SGB[version][mode]
    check(onSgb ~= nil, version .. "/" .. mode .. " has an expected wOnSGB")
    eq(not PaletteFX.runsNotSGB(), onSgb,
      version .. "/" .. mode .. " runsNotSGB matches wOnSGB")

    local side = setmetatable({}, { __index = BattleState })
    BattleState.applyAnimEffect(side, { effect = "SE_DARKEN_MON_PALETTE" })
    eq(fmt(side.fx.bgp), onSgb and "0133" or "1233",
      version .. "/" .. mode .. " SE_DARKEN_MON_PALETTE bgp")

    BattleState.applyAnimEffect(side, { effect = "SE_FLASH_SCREEN_LONG" })
    local steps = side.fx.bgpSeq.steps
    eq(#steps, 36, version .. "/" .. mode .. " SE_FLASH_SCREEN_LONG runs 3 cycles of 12")
    local want = onSgb
      and { "0233", "0333", "3333", "0333", "0233", "0123",
            "0012", "0001", "0000", "0001", "0012", "0123" }
      or  { "1233", "2333", "3333", "2333", "1233", "0123",
            "0012", "0001", "0000", "0001", "0012", "0123" }
    local got = {}
    for i = 1, 12 do got[i] = fmt(steps[i].map) end
    eq(table.concat(got, " "), table.concat(want, " "),
      version .. "/" .. mode .. " SE_FLASH_SCREEN_LONG table")
  end
end

GameVersion.set("yellow")
PaletteFX.mode = "redpp"
local side = setmetatable({}, { __index = BattleState })
BattleState.applyAnimEffect(side, { effect = "SE_DARKEN_MON_PALETTE" })
eq(fmt(side.fx.bgp), "0133", "yellow ADVANCED SMOG darken is $f4")
PaletteFX.mode = "ogred"
BattleState.applyAnimEffect(side, { effect = "SE_DARKEN_MON_PALETTE" })
eq(fmt(side.fx.bgp), "0133", "OG YELLOW SMOG darken is $f4")
GameVersion.set("red")
BattleState.applyAnimEffect(side, { effect = "SE_DARKEN_MON_PALETTE" })
eq(fmt(side.fx.bgp), "1233", "OG RED SMOG darken is $f9")

GameVersion.set(prevVersion)
PaletteFX.mode = prevMode

S.finish()

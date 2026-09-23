#!/usr/bin/env luajit
-- The screens that show a single mon draw an egg as an egg, as pret does with
-- GetMonData(MON_DATA_SPECIES_OR_EGG) and MON_DATA_NICKNAME
-- (pokefirered/src/pokemon.c:3245, :3020): the party slots, the PC's hovered-mon
-- panel, the summary's egg page, the trade scene, and the script string buffers.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

require("src.core.GameVersion").set("firered")
package.loaded["src.core.game3.audio"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local Strings = require("src.core.Strings")
local Pokemon = require("src.core.game3.pokemon")
Pokemon._names = { [25] = "PIKACHU", [172] = "PICHU" } -- a minimal pack, so no ROM is needed
Strings.load({ strings = { EGG = "OEUF" } })

local pics = {}
Pokemon.frontPic = function(species)
  pics[#pics + 1] = species
  return { image = { getDimensions = function() return 64, 64 end }, w = 64, h = 64 }
end
local texts = {}
local FrlgFont = require("src.ui.game3.frlg_font")
FrlgFont.draw = function(text) texts[#texts + 1] = tostring(text) end

local function egg()
  return { species = 172, isEgg = true, nickname = "EGG", name = "EGG", level = 5,
    heldItem = 1, gender = "M", personality = 1, otName = "RED", otId = 1,
    hp = 1, maxHp = 1, moves = {}, pp = {} }
end
local function has(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

-- pokefirered/src/pokemon_storage_system_data.c:1034, :1091
local PcChrome = require("src.ui.game3.pc_chrome")
PcChrome.ensure = function() end
PcChrome.drawWaveforms = function() end
pics, texts = {}, {}
PcChrome.drawLeftDataPanel(egg(), 0)
check(pics[1] == 412, "the PC panel draws an egg's front pic as the EGG's (got " .. tostring(pics[1]) .. ")")
check(texts[1] == "OEUF", "and names it by the language's EGG (got " .. tostring(texts[1]) .. ")")
check(not has(texts, "/PICHU") and not has(texts, "Lv5"),
  "with no species, level or item line: " .. table.concat(texts, " | "))
pics, texts = {}, {}
PcChrome.drawLeftDataPanel({ species = 172, nickname = "PICHU", level = 5, gender = "M" }, 0)
check(pics[1] == 172 and has(texts, "/PICHU") and has(texts, "Lv5"),
  "a hatched mon keeps its pic, species and level lines")

-- pokefirered/src/party_menu.c:781 DisplayPartyPokemonData, :2197 sSlotTilemap_MainNoHP
local PartyMenu = require("src.ui.game3.party_menu")
local PartyChrome = require("src.ui.game3.party_chrome")
local slotsHidingHp = {}
PartyChrome.drawSlot = function(kind, _, _, _, hideHp)
  if kind ~= "empty" then slotsHidingHp[#slotsHidingHp + 1] = hideHp and true or false end
end
texts, slotsHidingHp = {}, {}
PartyMenu.show({ { species = 25, nickname = "SPARKY", level = 12, gender = "M", hp = 30, maxHp = 30 }, egg() })
PartyMenu.draw()
PartyMenu.close()
check(has(texts, "OEUF") and has(texts, "SPARKY"), "the party names both mons: " .. table.concat(texts, " | "))
check(not has(texts, "Lv5") and has(texts, "Lv12"), "an egg's party slot shows no level, the other one does")
check(slotsHidingHp[1] == false and slotsHidingHp[2] == true,
  "and an egg's slot has no HP frame (hideHp = " .. tostring(slotsHidingHp[1]) .. ", " .. tostring(slotsHidingHp[2]) .. ")")

-- pokefirered/src/pokemon_summary_screen.c:4016
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")
for k, v in pairs(SummaryChrome) do
  if type(v) == "function" and k:match("^draw") then SummaryChrome[k] = function() end end
end
pics = {}
SummaryMenu.openMenu({ egg() }, 1, { page = 0 })
SummaryMenu.draw()
SummaryMenu.close()
check(has(pics, 412) and not has(pics, 172),
  "the summary's egg page draws the EGG's front pic (got " .. table.concat(pics, ",") .. ")")
pics = {}
local flagOnly = egg()
flagOnly.isEgg, flagOnly.egg = nil, true
SummaryMenu.openMenu({ flagOnly }, 1, { page = 0 })
SummaryMenu.draw()
SummaryMenu.close()
check(has(pics, 412) and not has(pics, 172), "for any egg flag (got " .. table.concat(pics, ",") .. ")")

-- pokefirered/src/trade_scene.c:757, :1239
local TradeSceneUi = require("src.ui.game3.trade_scene")
local offer, received = egg(), { species = 25, nickname = "SPARKY" }
TradeSceneUi._core = { state = function()
  return { playerVisible = true, partnerVisible = true, offer = offer, received = received }
end }
pics = {}
TradeSceneUi.draw()
check(pics[1] == 412 and pics[2] == 25,
  "the trade scene draws a sent egg as the EGG (got " .. table.concat(pics, ",") .. ")")
TradeSceneUi._core = nil
local savedLove = _G.love
_G.love = nil
local TradeScene = require("src.core.game3.trade_scene")
TradeScene.play(offer, received, nil, {})
local st = TradeScene.state()
check(st.sentName == "OEUF", "and names it by the language's EGG (got " .. tostring(st.sentName) .. ")")
check(st.recvName == "SPARKY", "while the other mon keeps its nickname")
_G.love = savedLove

-- pokefirered/src/field_specials.c:1671 BufferMonNickname, daycare.c:1216
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return { party = { egg() } } end,
  isActive = function() return true end,
}
local ctx = Ctx.new({})
ctx.mode, ctx.status = "bytecode", "running"
Flags.setVar(nil, ctx, 0x8004, 0)
Natives.special(ctx, Std.SPECIAL.GetSelectedMonNicknameAndSpecies, { log = function() end })
check(ctx.stringVars and ctx.stringVars[1] == "OEUF",
  "a script buffering an egg's nickname gets the language's EGG (got "
  .. tostring(ctx.stringVars and ctx.stringVars[1]) .. ")")

Strings.load({})
T.finish("game3_egg_screens_test")

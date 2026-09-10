package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Assets = require("src.render.Assets")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

local FRONT = "assets/generated/battle/front/cyndaquil.png"
local BACK = "assets/generated/battle/back/cyndaquil.png"
local SHEET = "assets/generated/battle/anim/cyndaquil.png"
local UNOWN_A = "assets/generated/battle/front/unown_a.png"
local UNOWN_D = "assets/generated/battle/front/unown_d.png"

local image = {
  getDimensions = function() return 56, 56 end,
  getWidth = function() return 56 end,
  getHeight = function() return 56 end,
}
local loaded = {}
Assets.image = function(path)
  loaded[#loaded + 1] = path
  return image
end
Assets.resolve = function(path) return path end

local pokemon = {
  CYNDAQUIL = {
    index = 155, spriteFront = FRONT, spriteBack = BACK,
    anim = { sheet = SHEET, tiles = 7, play = { { 1 } } },
  },
  UNOWN = {
    index = 201, spriteFront = UNOWN_A,
    letters = { D = { spriteFront = UNOWN_D } },
  },
}
local data = { pokemon = pokemon }
local game = { data = data }
local mon = { species = "CYNDAQUIL", shiny = false }
local unown = { species = "UNOWN", unownLetter = "D" }

Runtime.hooks = Hooks.new()
local calls = {}
local animMod = false
Runtime.hooks:wrap("pokemon.sprite", function(next, path, ctx)
  calls[#calls + 1] = { path = path, kind = ctx.kind, species = ctx.species,
    letter = ctx.letter, side = ctx.side }
  if ctx.kind:match("_anim$") and not animMod then return next(path, ctx) end
  ctx.trueColor = true
  return "mods/skin/" .. ctx.kind .. ".png"
end)

local function last() return calls[#calls] end
local function lastLoaded() return loaded[#loaded] end

local function screen(Module, fields)
  return setmetatable(fields, { __index = Module })
end

do
  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local s = screen(SummaryMenu, { pokemon = pokemon, picCache = {},
    game = game, mon = mon })
  local img, tc = s:picFor(mon)
  T.eq(last().kind, "summary", "summary picFor raises kind summary")
  T.eq(last().path, FRONT, "summary hands the vanilla path to the wrap")
  T.eq(lastLoaded(), "mods/skin/summary.png", "summary loads the mod path")
  T.check(img == image and tc == true, "summary returns image + trueColor")

  s:startPicAnim()
  T.eq(last().kind, "summary_anim", "summary anim sheet raises summary_anim")
  T.eq(s.picAnim, nil, "a replaced static pic with a stock sheet holds still")

  animMod = true
  s:startPicAnim()
  T.check(s.picAnim ~= nil, "a mod that answers the sheet too animates")
  T.eq(lastLoaded(), "mods/skin/summary_anim.png", "off the mod sheet")
  T.check(s.picAnim and s.picAnim.trueColor == true,
    "the anim view carries the sheet's trueColor")
  animMod = false

  local u = screen(SummaryMenu, { pokemon = pokemon, picCache = {},
    game = game, mon = unown })
  u:picFor(unown)
  T.eq(last().path, UNOWN_D, "summary picks the Unown form before the wrap")
  T.eq(last().letter, 4, "summary ctx carries the Unown letter")
end

do
  local BoxMenu = require("src.ui.gen2.BoxMenu")
  local s = screen(BoxMenu, { pokemon = pokemon, picCache = {}, game = game })
  local img, tc = s:picFor(unown)
  T.eq(last().kind, "box", "box picFor raises kind box")
  T.eq(last().path, UNOWN_D, "box hands the Unown form path")
  T.eq(last().letter, 4, "box ctx carries the letter")
  T.check(img == image and tc == true, "box returns image + trueColor")
end

do
  local PokedexMenu = require("src.ui.gen2.PokedexMenu")
  local s = screen(PokedexMenu, { pokemon = pokemon, picCache = {},
    game = game, save = { firstUnownSeen = 4 } })
  local img, tc = s:picFor("UNOWN")
  T.eq(last().kind, "dex", "dex picFor raises kind dex")
  T.eq(last().path, UNOWN_D, "dex shows the first Unown seen")
  T.eq(last().letter, 4, "dex ctx carries the first letter")
  T.check(img == image and tc == true, "dex returns image + trueColor")
  s:drawUnownPic(4, 6, 5)
  T.eq(last().kind, "dex", "UNOWN mode raises kind dex")
  T.eq(last().letter, 4, "UNOWN mode ctx carries the letter")
end

do
  local TradeAnim = require("src.ui.gen2.TradeAnim")
  local s = screen(TradeAnim, { data = data, picCache = {}, get = mon })
  local img, tc = s:pic(mon)
  T.eq(last().kind, "trade", "trade pic raises kind trade")
  T.check(img == image and tc == true, "trade returns image + trueColor")
  s:startPicAnim()
  T.eq(last().kind, "trade_anim", "trade anim sheet raises trade_anim")
  T.eq(s.picAnim, nil, "trade holds a replaced static pic still")
end

do
  local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")
  local s = screen(EvolutionAnim, { data = data, picCache = {}, mon = mon,
    newSpecies = "CYNDAQUIL" })
  local img, tc = s:pic("CYNDAQUIL")
  T.eq(last().kind, "evolution", "evolution pic raises kind evolution")
  T.check(img == image and tc == true, "evolution returns image + trueColor")
end

do
  local EggHatchAnim = require("src.ui.gen2.EggHatchAnim")
  local s = screen(EggHatchAnim, { data = data, picCache = {}, mon = mon,
    species = "CYNDAQUIL", showMon = true })
  local img, tc = s:pic()
  T.eq(last().kind, "hatch", "hatch pic raises kind hatch")
  T.check(img == image and tc == true, "hatch returns image + trueColor")
  s:startPicAnim()
  T.eq(last().kind, "hatch_anim", "hatch anim sheet raises hatch_anim")
end

do
  local HallOfFame = require("src.ui.gen2.HallOfFame")
  local s = screen(HallOfFame, { data = data, pokemon = pokemon,
    picCache = {}, entry = { party = { mon } }, index = 1 })
  local img, tc = s:monPic(mon, false)
  T.eq(last().kind, "hof", "hof front raises kind hof")
  T.eq(last().side, "front", "hof front is side front")
  T.check(img == image and tc == true, "hof returns image + trueColor")
  s:monPic(mon, true)
  T.eq(last().side, "back", "hof back is side back")
  T.eq(last().path, BACK, "hof back hands the back pic path")
end

do
  local PhotoStudio = require("src.ui.gen2.PhotoStudio")
  local s = screen(PhotoStudio, { pokemon = pokemon, picCache = {},
    game = game, mon = mon })
  local img, tc = s:picFor("CYNDAQUIL")
  T.eq(last().kind, "photo", "photo picFor raises kind photo")
  T.check(img == image and tc == true, "photo returns image + trueColor")
end

do
  local UnownPrinter = require("src.ui.gen2.UnownPrinter")
  local s = screen(UnownPrinter, { pokemon = pokemon, picCache = {},
    game = game })
  local img, tc = s:picFor(4)
  T.eq(last().kind, "unown_printer", "stamp viewer raises kind unown_printer")
  T.eq(last().letter, 4, "stamp viewer ctx carries the letter")
  T.check(img == image and tc == true,
    "stamp viewer returns image + trueColor")
end

do
  local OakSpeech = require("src.ui.gen2.OakSpeech")
  local s = screen(OakSpeech, { game = game })
  local img = s:resolvePic({ type = "pokemon", id = "CYNDAQUIL" })
  T.eq(last().kind, "oak", "oak speech pic raises kind oak")
  T.eq(lastLoaded(), "mods/skin/oak.png", "oak speech loads the mod path")
  T.check(img == image, "oak speech returns the image")
end

do
  local World = require("src.world.gen2.World")
  local s = screen(World, { game = game })
  s:showPokePic(155)
  T.eq(last().kind, "overworld", "pokepic raises kind overworld")
  T.eq(last().species, "CYNDAQUIL", "pokepic resolves the species index")
  T.check(s.pokePic == image and s.pokePicTrueColor == true,
    "pokepic stores the image and trueColor")
end

do
  local OnlineSprites = require("src.online.OnlineSprites")
  OnlineSprites.reset()
  OnlineSprites.readBytes = function(_, path)
    if path == "data/generated/pokemon.lua" then
      return ("return { CYNDAQUIL = { spriteFront = %q } }"):format(FRONT)
    end
    return nil
  end
  OnlineSprites.ensure("gold", mon)
  T.eq(last().kind, "online", "lobby preview raises kind online")
  T.eq(last().path, FRONT, "lobby preview hands the vanilla path")
end

local kinds = {}
for _, call in ipairs(calls) do kinds[call.kind] = true end
for _, kind in ipairs({ "summary", "summary_anim", "box", "dex", "trade",
    "trade_anim", "evolution", "hatch", "hatch_anim", "hof", "photo",
    "unown_printer", "oak", "overworld", "online" }) do
  T.check(kinds[kind], "pokemon.sprite saw kind " .. kind)
end

T.finish("gen2 pokemon.sprite sites bug 2217")

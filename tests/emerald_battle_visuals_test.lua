package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function loadRel(rel)
  local src = cache:read("data/generated/gba/" .. rel)
  if type(src) ~= "string" then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local manifest = loadRel("pokemon/battle/manifest.lua")
if not (manifest and manifest.layout == "rse") then
  print("emerald_battle_visuals_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

local PicCoords = require("src.core.game3.battle.pic_coords")
local pack = assert(loadRel("pokemon/pic_coords.lua"), "pic_coords pack")
eq(PicCoords.front[1], pack.front[1].y, "Emerald front y comes from the pack")
eq(PicCoords.front[1], 14, "Emerald Bulbasaur front y (front_pic_coordinates.h)")
eq(PicCoords.back[25], pack.back[25].y, "Emerald back y comes from the pack")
eq(PicCoords.elev[16], pack.elevation[16], "Emerald Pidgey elevation from the pack")
check(PicCoords.front ~= PicCoords.FRLG.front, "Emerald does not read the FRLG hand table")
local differ = 0
for sp, y in pairs(PicCoords.FRLG.front) do
  if PicCoords.front[sp] ~= y then differ = differ + 1 end
end
check(differ > 100, "Emerald front rows differ from FRLG (" .. differ .. ")")

local BattleChrome = require("src.ui.game3.battle_chrome")
BattleChrome._manifest = manifest
check(BattleChrome.layout() == "emerald", "chrome layout is emerald")
local msg = BattleChrome.window(BattleChrome.WIN.MSG)
eq(msg.x, 16, "B_WIN_MSG left")
eq(msg.y, 120, "B_WIN_MSG top")
eq(msg.w, 26, "B_WIN_MSG width")
local x, y = BattleChrome.textOrigin(BattleChrome.WIN.ACTION_MENU)
eq(x, 136, "action menu text x")
eq(y, 121, "action menu text y")
local ppx, ppy = BattleChrome.textOrigin(BattleChrome.WIN.PP_REMAINING)
eq(ppx, 202, "PP remaining text x")
eq(ppy, 121, "PP remaining text y")
local tx, ty = BattleChrome.textOrigin(BattleChrome.WIN.MOVE_TYPE)
eq(tx, 168, "move type text x")
eq(ty, 137, "move type text y")
local mx, my, mw = BattleChrome.messageOrigin()
eq(mx, 16, "message text x")
eq(my, 121, "message text y")
eq(mw, 208, "message text width")

local EnvRse = require("src.core.game3.battle.env_rse")
for id = 0, 9 do
  local key = EnvRse.sheetFor(id, manifest)
  check(manifest.terrains[key] ~= nil, "environment " .. id .. " sheet " .. tostring(key) .. " is baked")
end
for name, id in pairs(EnvRse.SCENE) do
  local key = EnvRse.sheetFor(id, manifest)
  check(manifest.terrains[key] ~= nil, "scene " .. name .. " sheet " .. tostring(key) .. " is baked")
end

local BattleBg = require("src.core.game3.battle.bg")
check(BattleBg.env() == EnvRse, "bg dispatches to env_rse")
eq(BattleBg.sheetKey(EnvRse.SCENE.KYOGRE), "kyogre", "Kyogre scene sheet")
eq(BattleBg.sheetKey(EnvRse.ENVIRONMENT.LONG_GRASS), "long_grass", "long grass sheet")

local tman = assert(loadRel("pokemon/battle_transition/manifest.lua"), "transition manifest")
local IdsRse = require("src.core.game3.battle_transition_ids_rse")
for name, id in pairs(tman.ids) do
  eq(IdsRse.ID[name], id, "transition id " .. name .. " matches the cache manifest")
end
local pics, coords, scales = IdsRse.mugshotTables(tman)
eq(pics.glacia, 38, "Glacia mugshot pic")
eq(coords.champion[1], -8, "Wallace mugshot x")
eq(scales.drake[1], 416, "Drake mugshot scale")

local Chrome = require("src.ui.game3.battle_transition_chrome")
Chrome._cache = cache
Chrome._manifest = tman
Chrome._assets = {}
Chrome._assetImages = {}
eq(Chrome.assetBanks("kyogre", 1), 10, "Kyogre flash palette banks")
eq(Chrome.assetBanks("kyogre", 2), 14, "Kyogre brighten palette banks")
eq(Chrome.assetBanks("rayquaza", 1), 16, "Rayquaza palette banks")
eq(#Chrome.assetPalette("aqua", 1, 0), 32, "Aqua palette bank is 16 colours")
eq(Chrome.assetPalette("aqua", 1, 1), nil, "Aqua has one bank")

Profile.reset()
T.finish("emerald_battle_visuals_test")

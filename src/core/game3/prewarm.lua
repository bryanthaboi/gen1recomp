local Warm = require("src.core.game3.warm")
local Prewarm = {}

Prewarm.FIELD_SE = { "SE_SELECT", "SE_WIN_OPEN", "SE_WALL_HIT", "SE_EXIT", "SE_DOOR", "SE_LEDGE",
  "SE_SLIDING_DOOR", "SE_PIN" }

Prewarm.BATTLE_SE = { "SE_BALL_OPEN", "SE_BALL_THROW", "SE_FAINT", "SE_NOT_EFFECTIVE", "SE_EFFECTIVE",
  "SE_SUPER_EFFECTIVE", "SE_EXP" }

Prewarm.MODULES = {
  "src.core.game3.party", "src.core.game3.trainer_sight", "src.core.game3.warp",
  "src.core.game3.battle_downgrade", "src.core.game3.battle_bridge", "src.core.game3.battle_transition",
  "src.core.game3.battle.ai", "src.core.game3.battle.ai_cmds", "src.core.game3.battle.ai_vm",
  "src.core.game3.battle.ai_items", "src.core.game3.battle.link_guard", "src.ui.game3.stat_growth",
  "src.ui.game3.map_name_popup",
}

Prewarm.FAMILY_MODULES = {
  rse = { "src.core.game3.audio_policy_rse", "src.ui.game3.rse.mapsec", "src.ui.game3.rse.scene_kit",
    "src.core.game3.battle_transition_ids_rse", "src.core.game3.battle_transition_rse_a",
    "src.core.game3.battle_transition_rse_b", "src.core.game3.battle_transition_rse_frontier" },
  frlg = { "src.core.game3.battle_transition_ids_frlg" },
}

Prewarm.FONT_FACES = { "normal", "small", "short", "narrow", "small_narrow" }

Prewarm.CONSTANTS = { "weather", "region_map_sections", "trainer_classes", "moves", "abilities" }

local function se_list(names, priority)
  local Audio = package.loaded["src.core.game3.audio"]
  if not Audio then return end
  for _, name in ipairs(names) do Audio.prewarmSe(name, priority) end
end

function Prewarm.session(session)
  local Profile = require("src.core.game3.profile")
  local family = Profile.family(session)
  Warm.require(Prewarm.MODULES, 6)
  Warm.require(Prewarm.FAMILY_MODULES[family] or {}, 6)
  local okG, game = pcall(function() return require("src.core.GameVersion").get() end)
  if okG and game then
    for _, kind in ipairs(Prewarm.CONSTANTS) do
      Warm.add("const:" .. tostring(game) .. ":" .. kind, function()
        local C = require("src.core.game3.constants").of(game)
        local _ = C[kind]
      end, 7)
    end
  end
  for _, face in ipairs(Prewarm.FONT_FACES) do
    Warm.add("font:" .. face, function()
      local Font = require("src.ui.game3.frlg_font")
      if Font.face then pcall(Font.face, { font = face }) end
    end, 5)
  end
  Warm.add("data:pic_coords", function() require("src.core.game3.battle.pic_coords").active() end, 7)
  Warm.add("data:mon_anim", function() require("src.core.game3.mon_anim_data").get() end, 7)
  Warm.add("data:moves", function() require("src.core.game3.battle.moves").loadRomPack() end, 7)
  se_list(Prewarm.FIELD_SE, 9)
end

local function species_of(mon)
  if type(mon) ~= "table" then return nil end
  return tonumber(mon.species or mon.speciesId)
end

local function lead_of(party)
  for _, mon in ipairs(type(party) == "table" and party or {}) do
    if type(mon) == "table" and not mon.isEgg and not mon.egg and (tonumber(mon.hp) or 1) > 0 then return mon end
  end
end

function Prewarm.battle(session, foe)
  local Audio = package.loaded["src.core.game3.audio"]
  if not Audio then return end
  local lead = lead_of(session and session.party)
  local IntroSeq = package.loaded["src.core.game3.battle.intro_seq"]
  local mode = lead and IntroSeq and IntroSeq.releaseCryMode and IntroSeq.releaseCryMode(lead) or 0
  if species_of(lead) then Audio.prewarmCry(species_of(lead), mode, -25, 1) end
  local first = foe and ((type(foe.party) == "table" and foe.party[1]) or foe)
  if species_of(first) then Audio.prewarmCry(species_of(first), 0, 25, 1) end
  se_list(Prewarm.BATTLE_SE, 2)
end

function Prewarm.battleStart(opts)
  if type(opts) ~= "table" then return end
  Warm.add("battle:chrome", function()
    require("src.ui.game3.battle_chrome").ensureInstalled()
    local BattleBg = require("src.core.game3.battle.bg")
    require("src.ui.game3.battle_chrome").terrain(BattleBg.sheetKey(BattleBg.resolveOpts(opts)))
  end, 1)
  Warm.add("battle:back", function()
    require("src.core.game3.trainer_pic").back(tonumber(opts.playerGender) or 0)
  end, 1)
end

return Prewarm

-- Rewards for winning specific trainer battles, keyed by
-- "OPP_CLASS#partyIndex" (the object_event trainer args).  Hand-ported
-- from the leaders'/bosses' text_asm victory scripts:
--   gym badges: scripts/PewterGym.asm ... ViridianGym.asm
--   Rocket Hideout Giovanni: Silph Scope is a hidden item ball revealed by
--   ShowObject in RocketHideoutB4FBeatGiovanniScript (ported as the
--   TEXT_ROCKETHIDEOUTB4F_GIOVANNI talk handler in story3.lua).
-- The TM each gym leader hands out afterwards is also ported.
--
-- `deactivate` lists the EVENT_BEAT_* flags each gym's victory script
-- sets to retire unfought non-leader trainers (PewterGym.asm
-- "; deactivate gym trainers" / SetEventRange in the other gyms, and
-- FightingDojo.asm SetEventRange EVENT_BEAT_KARATE_MASTER ..
-- EVENT_BEAT_FIGHTING_DOJO_TRAINER_3).
--
-- `dialogue` is the end-battle + post-battle text chain each gym leader
-- runs (SaveEndBattleTextPointers then the map's *PostBattle / ReceiveTM
-- script).  Leaders are not def_trainers entries, so engageTrainer has
-- no header.won -- checkVictoryRewards shows this chain instead of a
-- synthetic "received badge/TM" stub.
--
-- Gym entries split the TM hand-over out of `dialogue`, mirroring the
-- originals' GiveItem check (`call GiveItem` / `jr nc, .BagFull`):
-- `tmPre` is the ReceiveTM script's lead-in (badge info / "Wait! Take
-- this!"), shown at the victory and again when a beaten leader retries
-- the hand-over; `tmDialogue` shows only when the TM actually goes in
-- the bag; `noRoom` is the "make room" line shown instead when the bag
-- is full; `gotFlag` (pokered's EVENT_GOT_TM*) is set only on a
-- successful give, which is what makes the leader's talk script retry
-- later (gyms.lua).
--
-- `badgeSound` / `tmSound` are the text sound command each gym's reward
-- text carries right after its FIRST label -- home/text.asm TextCommand_SOUND
-- plays it once that page has typed out and then blocks on
-- WaitForSoundToFinish, so the jingle sits between the pages rather than
-- under them.  The names are the OVERWORLD sound engine's meaning of those
-- commands (sound_get_item_1 -> Get_Item1, sound_get_key_item ->
-- Get_Key_Item; macros/scripts/text.asm aliases sound_level_up to
-- sound_get_item_1).  Vermilion, Celadon and Fuchsia carry no sound on the
-- badge text in any version.
--
-- The badge jingle is the one place where those names are not what the
-- cartridge plays, because a sound command names an id rather than a sound and
-- each engine numbers the ids with its own SFX header table.  Every gym's badge
-- line is saved with SaveEndBattleTextPointers in both Red and Yellow, so it is
-- printed while the BATTLE sound engine is still loaded, and that engine's
-- SFX_Headers_2 gives those ids different sounds: the id behind
-- sound_get_item_1 / sound_level_up is SFX_Level_Up there, and the id behind
-- sound_get_key_item is SFX_Ball_Poof.  pret's own comments say as much
-- ("probably supposed to play SFX_GET_ITEM_1 but the wrong music bank is
-- loaded"), and home/text.asm carries the note on TX_SOUND_GET_ITEM_1.
-- Cerulean is the only badge whose jingle differs between versions, because
-- Yellow's CeruleanGym.asm drops the command from that line.  badgeSoundFor()
-- below answers with the jingle that is actually audible; the raw `badgeSound`
-- field stays the overworld-engine name, which is what `tmSound` really needs
-- (the TM texts print in the overworld, where those names are correct).

local function range(prefix, first, last)
  local t = {}
  for i = first, last do
    t[#t + 1] = prefix .. i
  end
  return t
end

local M = {
  -- PewterGym.asm .gymVictory also HideObject TOGGLE_GYM_GUY
  -- (PEWTERCITY_YOUNGSTER) and TOGGLE_ROUTE_22_RIVAL_1 so the east-exit
  -- escort NPC and the first Route 22 rival stay gone after the badge.
  ["OPP_BROCK#1"] = { badge = "BOULDERBADGE", flag = "EVENT_BEAT_BROCK",
                      item = "TM_BIDE",
                      gotFlag = "EVENT_GOT_TM34",
                      noRoom = "_PewterGymTM34NoRoomText",
                      deactivate = { "EVENT_BEAT_PEWTER_GYM_TRAINER_0" },
                      hide = {
                        { "PEWTER_CITY", "PEWTERCITY_YOUNGSTER" },
                        { "ROUTE_22", "ROUTE22_RIVAL1" },
                      },
                      badgeSound = "Get_Item1", -- sound_level_up -> battle engine: Level_Up
                      tmSound = "Get_Item1",
                      dialogue = {
                        "_PewterGymBrockReceivedBoulderBadgeText",
                        "_PewterGymBrockBoulderBadgeInfoText",
                      },
                      tmPre = { "_PewterGymBrockWaitTakeThisText" },
                      tmDialogue = {
                        "_PewterGymReceivedTM34Text",
                        "_TM34ExplanationText",
                      } },
  ["OPP_MISTY#1"] = { badge = "CASCADEBADGE", flag = "EVENT_BEAT_MISTY",
                      item = "TM_BUBBLEBEAM",
                      gotFlag = "EVENT_GOT_TM11",
                      noRoom = "_CeruleanGymMistyTM11NoRoomText",
                      deactivate = range("EVENT_BEAT_CERULEAN_GYM_TRAINER_", 0, 1),
                      badgeSound = "Get_Key_Item", -- sound_get_key_item -> battle engine: Ball_Poof (Yellow: none)
                      tmSound = "Get_Item1",
                      dialogue = {
                        "_CeruleanGymMistyReceivedCascadeBadgeText",
                      },
                      tmPre = { "_CeruleanGymMistyCascadeBadgeInfoText" },
                      tmDialogue = {
                        "_CeruleanGymMistyReceivedTM11Text",
                      } },
  ["OPP_LT_SURGE#1"] = { badge = "THUNDERBADGE", flag = "EVENT_BEAT_LT_SURGE",
                         item = "TM_THUNDERBOLT",
                         gotFlag = "EVENT_GOT_TM24",
                         noRoom = "_VermilionGymLTSurgeTM24NoRoomText",
                         deactivate = range("EVENT_BEAT_VERMILION_GYM_TRAINER_", 0, 2),
                         tmSound = "Get_Key_Item",
                         dialogue = {
                           "_VermilionGymLTSurgeReceivedThunderBadgeText",
                         },
                         tmPre = { "_VermilionGymLTSurgeThunderBadgeInfoText" },
                         tmDialogue = {
                           "_VermilionGymLTSurgeReceivedTM24Text",
                           "_TM24ExplanationText",
                         } },
  ["OPP_ERIKA#1"] = { badge = "RAINBOWBADGE", flag = "EVENT_BEAT_ERIKA",
                      item = "TM_MEGA_DRAIN",
                      gotFlag = "EVENT_GOT_TM21",
                      noRoom = "_CeladonGymTM21NoRoomText",
                      deactivate = range("EVENT_BEAT_CELADON_GYM_TRAINER_", 0, 6),
                      tmSound = "Get_Item1",
                      dialogue = {
                        "_CeladonGymErikaReceivedRainbowBadgeText",
                      },
                      tmPre = { "_CeladonGymRainbowBadgeInfoText" },
                      tmDialogue = {
                        "_CeladonGymReceivedTM21Text",
                        "_TM21ExplanationText",
                      } },
  ["OPP_KOGA#1"] = { badge = "SOULBADGE", flag = "EVENT_BEAT_KOGA",
                     item = "TM_TOXIC",
                     gotFlag = "EVENT_GOT_TM06",
                     noRoom = "_FuchsiaGymKogaTM06NoRoomText",
                     deactivate = range("EVENT_BEAT_FUCHSIA_GYM_TRAINER_", 0, 5),
                     tmSound = "Get_Key_Item",
                     dialogue = {
                       "_FuchsiaGymKogaReceivedSoulBadgeText",
                     },
                     tmPre = { "_FuchsiaGymKogaSoulBadgeInfoText" },
                     tmDialogue = {
                       "_FuchsiaGymKogaReceivedTM06Text",
                       "_FuchsiaGymKogaTM06ExplanationText",
                     } },
  ["OPP_SABRINA#1"] = { badge = "MARSHBADGE", flag = "EVENT_BEAT_SABRINA",
                        item = "TM_PSYWAVE",
                        gotFlag = "EVENT_GOT_TM46",
                        noRoom = "_SaffronGymSabrinaTM46NoRoomText",
                        deactivate = range("EVENT_BEAT_SAFFRON_GYM_TRAINER_", 0, 6),
                        badgeSound = "Get_Key_Item", -- sound_get_key_item -> battle engine: Ball_Poof
                        tmSound = "Get_Item1",
                        dialogue = {
                          "_SaffronGymSabrinaReceivedMarshBadgeText",
                        },
                        tmPre = { "_SaffronGymSabrinaMarshBadgeInfoText" },
                        tmDialogue = {
                          "_SaffronGymSabrinaReceivedTM46Text",
                          "_TM46ExplanationText",
                        } },
  ["OPP_BLAINE#1"] = { badge = "VOLCANOBADGE", flag = "EVENT_BEAT_BLAINE",
                       item = "TM_FIRE_BLAST",
                       gotFlag = "EVENT_GOT_TM38",
                       noRoom = "_CinnabarGymBlaineTM38NoRoomText",
                       deactivate = range("EVENT_BEAT_CINNABAR_GYM_TRAINER_", 0, 6),
                       badgeSound = "Get_Key_Item", -- sound_get_key_item -> battle engine: Ball_Poof
                       tmSound = "Get_Item1",
                       dialogue = {
                         "_CinnabarGymBlaineReceivedVolcanoBadgeText",
                       },
                       tmPre = { "_CinnabarGymBlaineVolcanoBadgeInfoText" },
                       tmDialogue = {
                         "_CinnabarGymBlaineReceivedTM38Text",
                         "_CinnabarGymBlaineTM38ExplanationText",
                       } },
  ["OPP_GIOVANNI#3"] = { badge = "EARTHBADGE", flag = "EVENT_BEAT_GIOVANNI",
                         item = "TM_FISSURE",
                         gotFlag = "EVENT_GOT_TM27",
                         noRoom = "_ViridianGymGiovanniTM27NoRoomText",
                         deactivate = range("EVENT_BEAT_VIRIDIAN_GYM_TRAINER_", 0, 7),
                         badgeSound = "Get_Item1", -- sound_level_up -> battle engine: Level_Up
                         tmSound = "Get_Item1",
                         dialogue = {
                           "_ViridianGymGiovanniReceivedEarthBadgeText",
                         },
                         tmPre = { "_ViridianGymGiovanniEarthBadgeInfoText" },
                         tmDialogue = {
                           "_ViridianGymGiovanniReceivedTM27Text",
                           "_ViridianGymGiovanniTM27ExplanationText",
                         } },

  -- Silph Co. Giovanni: unlocks the president's Master Ball gift.
  -- SilphCo11FGiovanniStartBattleScript (scripts/SilphCo11F.asm) hands the
  -- battle SilphCo10FGiovanniILostAgainText through SaveEndBattleTextPointers,
  -- but he has no def_trainers header on 11F, so engageTrainer finds no
  -- header.won to give it -- this chain is the port's stand-in for that loss
  -- line (#722).  The "Blast it all!" speech, the fade and the rockets
  -- leaving are SilphCo11FGiovanniAfterBattleScript, ported in M.SILPH_CO_11F
  -- (data/scripts/story.lua).
  ["OPP_GIOVANNI#2"] = { flag = "EVENT_BEAT_SILPH_CO_GIOVANNI",
                         dialogue = { "_SilphCo10FGiovanniILostAgainText" } },

  -- Fighting Dojo Karate Master (scripts/FightingDojo.asm
  -- FightingDojoKarateMasterPostBattleScript sets EVENT_BEAT_KARATE_MASTER,
  -- which gates the HITMONLEE/HITMONCHAN gift).  OPP_BLACKBELT party 1 is
  -- only him (data/maps/objects/FightingDojo.asm).  `dialogue` is the
  -- concede + prize offer he speaks after the win (his header supplies the
  -- "Hwa! Arrgh! Beaten!" won line first; #197).
  ["OPP_BLACKBELT#1"] = { flag = "EVENT_BEAT_KARATE_MASTER",
                          deactivate = range("EVENT_BEAT_FIGHTING_DOJO_TRAINER_", 0, 3),
                          dialogue = { "_FightingDojoKarateMasterIWillGiveYouAPokemonText" } },

  -- Elite Four progress flags (their rooms' door logic isn't ported, but
  -- the flags make the Hall of Fame checkable)
  ["OPP_LORELEI#1"] = { flag = "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0" },
  ["OPP_BRUNO#1"] = { flag = "EVENT_BEAT_BRUNOS_ROOM_TRAINER_0" },
  ["OPP_AGATHA#1"] = { flag = "EVENT_BEAT_AGATHAS_ROOM_TRAINER_0" },
  ["OPP_LANCE#1"] = { flag = "EVENT_BEAT_LANCE" },
}

-- The jingle the cartridge actually plays for these badges, which is not the
-- overworld name above: the badge lines are end-battle texts, so the battle
-- sound engine resolves their sound id through its own SFX_Headers_2 table
-- (see the note at the top).  Blue runs Red's scripts, so it shares Red's
-- entry.  `false` means the badge line carries no sound command at all.
local BADGE_SOUND = {
  red = {
    ["OPP_BROCK#1"] = "Level_Up",    -- sound_level_up -> SFX_Level_Up
    ["OPP_MISTY#1"] = "Ball_Poof",   -- sound_get_key_item -> SFX_Ball_Poof
    ["OPP_SABRINA#1"] = "Ball_Poof", -- sound_get_key_item -> SFX_Ball_Poof
    ["OPP_BLAINE#1"] = "Ball_Poof",
    ["OPP_GIOVANNI#3"] = "Level_Up", -- sound_level_up -> SFX_Level_Up
  },
  yellow = {
    ["OPP_BROCK#1"] = "Level_Up",    -- sound_get_item_1 -> SFX_Level_Up
    ["OPP_MISTY#1"] = false,         -- CeruleanGym.asm prints no sound
    ["OPP_SABRINA#1"] = "Ball_Poof", -- sound_get_key_item -> SFX_Ball_Poof
    ["OPP_BLAINE#1"] = "Ball_Poof",
    ["OPP_GIOVANNI#3"] = "Level_Up", -- sound_level_up -> SFX_Level_Up
  },
}

-- The jingle to play when this victory hands its badge over, or nil when it
-- has none -- the jingle the cartridge plays, i.e. the one the battle sound
-- engine gives the line's sound id, since the badge line rides the battle
-- screen (checkVictoryRewards' shownOnBattleScreen).  The overworld reward
-- fallback plays the same jingle rather than the raw `badgeSound` name: the
-- cartridge never prints a badge line from the overworld, so there is no
-- overworld reading of it to honour.  Resolved on every call rather than at
-- load time, because GameVersion can change under an already-required (and
-- therefore cached) module.
function M.badgeSoundFor(victoryKey)
  local reward = M[victoryKey]
  if not reward then return nil end
  local overrides = BADGE_SOUND[require("src.core.GameVersion").get()]
                    or BADGE_SOUND.red
  local override = overrides[victoryKey]
  if override ~= nil then return override or nil end
  return reward.badgeSound
end

return M

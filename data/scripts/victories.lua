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

local function range(prefix, first, last)
  local t = {}
  for i = first, last do
    t[#t + 1] = prefix .. i
  end
  return t
end

return {
  -- PewterGym.asm .gymVictory also HideObject TOGGLE_GYM_GUY
  -- (PEWTERCITY_YOUNGSTER) and TOGGLE_ROUTE_22_RIVAL_1 so the east-exit
  -- escort NPC and the first Route 22 rival stay gone after the badge.
  ["OPP_BROCK#1"] = { badge = "BOULDERBADGE", flag = "EVENT_BEAT_BROCK",
                      item = "TM_BIDE",
                      deactivate = { "EVENT_BEAT_PEWTER_GYM_TRAINER_0" },
                      hide = {
                        { "PEWTER_CITY", "PEWTERCITY_YOUNGSTER" },
                        { "ROUTE_22", "ROUTE22_RIVAL1" },
                      },
                      dialogue = {
                        "_PewterGymBrockReceivedBoulderBadgeText",
                        "_PewterGymBrockBoulderBadgeInfoText",
                        "_PewterGymBrockWaitTakeThisText",
                        "_PewterGymReceivedTM34Text",
                        "_TM34ExplanationText",
                      } },
  ["OPP_MISTY#1"] = { badge = "CASCADEBADGE", flag = "EVENT_BEAT_MISTY",
                      item = "TM_BUBBLEBEAM",
                      deactivate = range("EVENT_BEAT_CERULEAN_GYM_TRAINER_", 0, 1),
                      dialogue = {
                        "_CeruleanGymMistyReceivedCascadeBadgeText",
                        "_CeruleanGymMistyCascadeBadgeInfoText",
                        "_CeruleanGymMistyReceivedTM11Text",
                      } },
  ["OPP_LT_SURGE#1"] = { badge = "THUNDERBADGE", flag = "EVENT_BEAT_LT_SURGE",
                         item = "TM_THUNDERBOLT",
                         deactivate = range("EVENT_BEAT_VERMILION_GYM_TRAINER_", 0, 2),
                         dialogue = {
                           "_VermilionGymLTSurgeReceivedThunderBadgeText",
                           "_VermilionGymLTSurgeThunderBadgeInfoText",
                           "_VermilionGymLTSurgeReceivedTM24Text",
                           "_TM24ExplanationText",
                         } },
  ["OPP_ERIKA#1"] = { badge = "RAINBOWBADGE", flag = "EVENT_BEAT_ERIKA",
                      item = "TM_MEGA_DRAIN",
                      deactivate = range("EVENT_BEAT_CELADON_GYM_TRAINER_", 0, 6),
                      dialogue = {
                        "_CeladonGymErikaReceivedRainbowBadgeText",
                        "_CeladonGymRainbowBadgeInfoText",
                        "_CeladonGymReceivedTM21Text",
                        "_TM21ExplanationText",
                      } },
  ["OPP_KOGA#1"] = { badge = "SOULBADGE", flag = "EVENT_BEAT_KOGA",
                     item = "TM_TOXIC",
                     deactivate = range("EVENT_BEAT_FUCHSIA_GYM_TRAINER_", 0, 5),
                     dialogue = {
                       "_FuchsiaGymKogaReceivedSoulBadgeText",
                       "_FuchsiaGymKogaSoulBadgeInfoText",
                       "_FuchsiaGymKogaReceivedTM06Text",
                       "_FuchsiaGymKogaTM06ExplanationText",
                     } },
  ["OPP_SABRINA#1"] = { badge = "MARSHBADGE", flag = "EVENT_BEAT_SABRINA",
                        item = "TM_PSYWAVE",
                        deactivate = range("EVENT_BEAT_SAFFRON_GYM_TRAINER_", 0, 6),
                        dialogue = {
                          "_SaffronGymSabrinaReceivedMarshBadgeText",
                          "_SaffronGymSabrinaMarshBadgeInfoText",
                          "_SaffronGymSabrinaReceivedTM46Text",
                          "_TM46ExplanationText",
                        } },
  ["OPP_BLAINE#1"] = { badge = "VOLCANOBADGE", flag = "EVENT_BEAT_BLAINE",
                       item = "TM_FIRE_BLAST",
                       deactivate = range("EVENT_BEAT_CINNABAR_GYM_TRAINER_", 0, 6),
                       dialogue = {
                         "_CinnabarGymBlaineReceivedVolcanoBadgeText",
                         "_CinnabarGymBlaineVolcanoBadgeInfoText",
                         "_CinnabarGymBlaineReceivedTM38Text",
                         "_CinnabarGymBlaineTM38ExplanationText",
                       } },
  ["OPP_GIOVANNI#3"] = { badge = "EARTHBADGE", flag = "EVENT_BEAT_GIOVANNI",
                         item = "TM_FISSURE",
                         deactivate = range("EVENT_BEAT_VIRIDIAN_GYM_TRAINER_", 0, 7),
                         dialogue = {
                           "_ViridianGymGiovanniReceivedEarthBadgeText",
                           "_ViridianGymGiovanniEarthBadgeInfoText",
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

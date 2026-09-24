-- Engine-owned contract for generated ROM caches.
--
-- A cache is playable only when its versioned marker matches the ROM and every
-- required output for that version exists. Extraction writers may differ by
-- platform, but they must publish through this contract so partial staging
-- cannot look ready to the runtime.
local GameVersion = require("src.core.GameVersion")

local CacheContract = {}

-- engine/battle/animations.asm:2418
CacheContract.FORMAT = "rom-cache-v12-gen1:"
CacheContract.VERSION_FORMAT = {
  -- v11: Gen 2 maps carry their object list's ROM address, which a .sav
  -- export re-anchoring a save onto another map writes back into
  -- wCurMapObjectEventsPointer. A v10 cache has no address to write, and
  -- such an export is refused until the ROM re-imports.
  gold = "rom-cache-v12:",
  silver = "rom-cache-v12:",
  crystal = "rom-cache-v12-crystal4:",
  -- engine/overworld/map_sprites.asm:181, engine/battle/animations.asm:2600
  yellow = "rom-cache-v12-yellow1:",
  -- v8: M4A tracks retain reachable patterns and explicit entry offsets.
  firered = "rom-cache-v16-firered:",
  leafgreen = "rom-cache-v1-leafgreen:",
}
CacheContract.MARKER_PATH = "rom-cache.complete"

CacheContract.REQUIRED_FILES = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
  "assets/generated/trade/game_boy.png",
  -- engine/items/town_map.asm:296, 150
  "assets/generated/townmap/nest.png",
  "assets/generated/townmap/up_arrow.png",
}

CacheContract.VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png",
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
    "assets/generated/minigame/surf_1a.png",
    "assets/generated/minigame/surf_1b.png",
    "assets/generated/minigame/surf_1c.png",
    "assets/generated/minigame/title_bg.png",
    "assets/generated/minigame/intro_pika_0.png",
  },
}

CacheContract.VERSION_REQUIRED_FILES_OVERRIDE = {
  gold = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    -- The engine's label-keyed strings are separate from Gen 2 script text.
    -- Caches made before RomExtractorGen2:extractText must be rebuilt so
    -- src/core/RomText.lua does not silently fall back to built-in wording.
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/tilesets.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/pokemon_logo.png",
    "assets/generated/title/title_screen.png",
    "assets/generated/title/hooh.png",
    "assets/generated/title/hooh_5.png",
    "assets/generated/title/clouds.png",
    "assets/generated/title/copyright_splash.png",
    "data/generated/oak_speech.lua",
    "assets/generated/intro/oak.png",
    "assets/generated/intro/cal.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/front/marill.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    -- engine/events/fishing_gfx.asm:23
    "assets/generated/emotes/fishing.png",
    -- data/sprites/emotes.asm:19, engine/events/field_moves.asm:390
    "assets/generated/emotes/jump_shadow.png",
    "assets/generated/emotes/cut_grass.png",
    -- engine/pokegear/pokegear.asm:2298
    "assets/generated/pokegear/nest_icon.png",
  },
  crystal = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/encounters.lua",
    "data/generated/tilesets.lua",
    "data/generated/landmarks.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "data/generated/oak_speech.lua",
    "data/generated/title.lua",
    "data/generated/intro.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    -- ../pokecrystal/gfx/font.asm:60
    "assets/generated/fonts/map_entry_sign.png",
    "assets/generated/title/crystal_logo.png",
    "assets/generated/title/crystal_wordmark.png",
    "assets/generated/title/crystal_suicune.png",
    "assets/generated/title/copyright_splash.png",
    "assets/generated/splash/ditto.png",
    "assets/generated/intro/chris.png",
    "assets/generated/intro/kris.png",
    "assets/generated/intro/suicune_run_sprites.png",
    "assets/generated/intro/unowns_tiles.png",
    "assets/generated/intro/oak.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/sprites/kris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/wooper.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    "assets/generated/trainer_card/card_f.png",
    "data/generated/mobile_gfx.lua",
    "assets/generated/battle/player_back_female.png",
    "assets/generated/battle/trainers/kris.png",
    "assets/generated/battle/trainers/chris.png",
    -- ../pokecrystal/engine/events/fishing_gfx.asm:38-42
    "assets/generated/emotes/fishing.png",
    -- data/sprites/emotes.asm:19, engine/events/field_moves.asm:390
    "assets/generated/emotes/jump_shadow.png",
    "assets/generated/emotes/cut_grass.png",
    -- engine/pokegear/pokegear.asm:2298
    "assets/generated/pokegear/nest_icon.png",
  },
  firered = {
    "data/generated/gba/help/pack.lua",
    "data/generated/gba/quest_log/pack.lua",
    "data/generated/gba/objects/pack.lua",
    "data/generated/gba/meta.json",
    "data/generated/gba/maps.json",
    "data/generated/gba/audio/meta.json",
    "data/generated/intro.lua",
    "data/generated/gba/intro/meta.json",
    "data/generated/gba/intro/oak.png",
    "data/generated/gba/intro/boy.png",
    "data/generated/gba/intro/girl.png",
    "data/generated/gba/intro/rival.png",
    "data/generated/gba/intro/title_screen.png",
    "data/generated/gba/intro/title_logo.png",
    "data/generated/gba/intro/box_art_mon.png",
    "data/generated/gba/intro/press_start.png",
    "data/generated/gba/intro/platform.png",
    "data/generated/gba/intro/oak_speech_bg.png",
    "data/generated/gba/intro/controls_page1.png",
    "data/generated/gba/intro/pikachu_intro_bg.png",
    "data/generated/gba/intro/nidoran_f.png",
    "data/generated/gba/naming/manifest.lua",
    "data/generated/gba/ow/manifest.lua",
    "data/generated/gba/ow/0.rgba",
    "data/generated/gba/ow/7.rgba",
    "data/generated/gba/pokemon/manifest.lua",
    "data/generated/gba/pokemon/names.lua",
    "data/generated/gba/pokemon/front/1.rgba",
    "data/generated/gba/pokemon/front/200.rgba",
    "data/generated/gba/pokemon/front/411.rgba",
    "data/generated/gba/pokemon/back/1.rgba",
    "data/generated/gba/pokemon/back/200.rgba",
    "data/generated/gba/pokemon/back/411.rgba",
    "data/generated/gba/pokemon/icons/1.rgba",
    "data/generated/gba/pokemon/icons/200.rgba",
    "data/generated/gba/pokemon/icons/411.rgba",
    -- src/pokedex_screen.c:930
    "data/generated/gba/pokemon/pokedex/paper_bg.rgba",
    -- src/pokedex_screen.c:2901
    "data/generated/gba/pokemon/pokedex/footprints/1.rgba",
    "data/generated/gba/pokemon/pokedex/footprints/bulbasaur.rgba",
    "data/generated/gba/pokemon/pokedex/footprints/question_mark.rgba",
    "data/generated/gba/region_map/kanto_map.png",
    "data/generated/gba/region_map/cursor.png",
    "data/generated/gba/region_map/player_red.png",
    -- src/region_map.c:425
    "data/generated/gba/region_map/fly_icon.rgba",
    "data/generated/gba/region_map/fly_icon.png",
    "data/generated/gba/region_map/map_sections.lua",
    -- src/heal_location.c:62, src/region_map.c:4023
    "data/generated/gba/region_map/heal_locations.lua",
    "data/generated/gba/region_map/fly_destinations.lua",
    "data/generated/gba/scripts/multichoice.lua",
    "data/generated/gba/pokemon/stats.lua",
    "data/generated/gba/pokemon/learnsets.lua",
    "data/generated/gba/pokemon/move_names.lua",
    "data/generated/gba/pokemon/battle_moves.lua",
    "data/generated/gba/pokemon/battle/manifest.lua",
    "data/generated/gba/pokemon/battle/healthbox_player.rgba",
    "data/generated/gba/pokemon/battle/healthbox_doubles_player.rgba",
    "data/generated/gba/pokemon/battle/healthbox_doubles_opponent.rgba",
    "data/generated/gba/pokemon/battle/hp_bold_digits.rgba",
    "data/generated/gba/pokemon/battle/terrain_building.rgba",
    -- src/battle_bg.c:439
    "data/generated/gba/pokemon/battle/terrain_grass.rgba",
    "data/generated/gba/pokemon/battle/terrain_cave.rgba",
    "data/generated/gba/pokemon/battle/terrain_water.rgba",
    "data/generated/gba/pokemon/battle/terrain_champion.rgba",
    "data/generated/gba/pokemon/battle/terrain_bg_cave.rgba",
    "data/generated/gba/pokemon/battle/ball_open/manifest.lua",
    "data/generated/gba/pokemon/battle/ball_open/particles.rgba",
    "data/generated/gba/pokemon/battle/ball_open/balls.rgba",
    "data/generated/gba/pokemon/battle_transition/manifest.lua",
    "data/generated/gba/pokemon/battle_transition/big_pokeball.rgba",
    "data/generated/gba/pokemon/battle_transition/sliding_pokeball.rgba",
    "data/generated/gba/pokemon/party/slot_main.rgba",
    -- src/party_menu.c:2273
    "data/generated/gba/pokemon/party/slot_main_multi.rgba",
    "data/generated/gba/pokemon/party/slot_main_multi_selected.rgba",
    "data/generated/gba/pokemon/party/slot_wide_multi.rgba",
    "data/generated/gba/pokemon/party/slot_wide_multi_selected.rgba",
    -- src/data/party_menu.h:664
    "data/generated/gba/pokemon/party/hold_icons.rgba",
    "data/generated/gba/items/bag/manifest.lua",
    "data/generated/gba/items/bag/bg.rgba",
    "data/generated/gba/items/bag/bg_female.rgba",
    "data/generated/gba/items/bag/list.rgba",
    "data/generated/gba/items/bag/list_female.rgba",
    "data/generated/gba/items/bag/list_blank.rgba",
    "data/generated/gba/items/bag/list_blank_female.rgba",
    "data/generated/gba/items/bag/desc_sel.rgba",
    "data/generated/gba/items/bag/red_arrow.rgba",
    -- src/item_menu.c:569, src/item_menu_icons.c:150
    "data/generated/gba/items/bag/bg_itempc.rgba",
    "data/generated/gba/items/bag/bg_itempc_female.rgba",
    "data/generated/gba/items/bag/swap_line.rgba",
    -- src/item_pc.c:435
    "data/generated/gba/items/item_pc/bg.rgba",
    "data/generated/gba/items/item_pc/bg_submenu.rgba",
    -- src/pokedex_screen.c:1161
    "data/generated/gba/pokemon/pokedex/chrome.lua",
    "data/generated/gba/items/shop/manifest.lua",
    "data/generated/gba/items/shop/bg.rgba",
    "data/generated/gba/doors/manifest.lua",
    "data/generated/gba/doors/pallet.rgba",
    "data/generated/gba/native/manifest.lua",
    -- src/scrcmd.c:711, include/constants/layouts.h:253,267,268,308
    "data/generated/gba/native/layouts/alt_264.mid",
    "data/generated/gba/native/layouts/alt_278.mid",
    "data/generated/gba/native/layouts/alt_279.mid",
    "data/generated/gba/native/layouts/alt_319.mid",
    "data/generated/gba/pokemon/summary/manifest.lua",
    "data/generated/gba/pokemon/summary/menu_info.rgba",
    -- src/pokemon_summary_screen.c:1862
    "data/generated/gba/pokemon/summary/bg3_info.rgba",
    "data/generated/gba/pokemon/summary/bg3_moves.rgba",
    "data/generated/gba/pokemon/summary/layer_moves_info.rgba",
    "data/generated/gba/pokemon/summary/progress_moves_info_select.rgba",
    "data/generated/gba/pokemon/summary/markings.rgba",
    "data/generated/gba/pokemon/storage/manifest.lua",
    "data/generated/gba/pokedex/manifest.lua",
    "data/generated/gba/chrome/manifest.lua",
    "data/generated/gba/chrome/menu_message_rgba.rgba",
    "data/generated/gba/chrome/std_rgba.rgba",
    "data/generated/gba/chrome/signpost_rgba.rgba",
    "data/generated/gba/chrome/user_frame_0.rgba",
    "data/generated/gba/chrome/user_frame_9.rgba",
    "data/generated/gba/chrome/fonts/latin_normal_fg.rgba",
    "data/generated/gba/chrome/fonts/latin_widths.lua",
    -- src/text.c:100
    "data/generated/gba/chrome/fonts/latin_small_fg.rgba",
    "data/generated/gba/chrome/fonts/latin_small_shadow.rgba",
    "data/generated/gba/chrome/fonts/latin_small_widths.lua",
    -- src/text.c:141, :227, :228 (the Japanese fonts)
    "data/generated/gba/chrome/fonts/japanese_normal_fg.rgba",
    "data/generated/gba/chrome/fonts/japanese_normal_shadow.rgba",
    "data/generated/gba/chrome/fonts/japanese_widths.lua",
    "data/generated/gba/chrome/fonts/japanese_small_fg.rgba",
    "data/generated/gba/chrome/fonts/japanese_small_shadow.rgba",
    -- src/braille_text.c:15
    "data/generated/gba/chrome/fonts/braille_fg.rgba",
    "data/generated/gba/chrome/fonts/braille_shadow.rgba",
    "data/generated/gba/chrome/fonts/braille.lua",
    -- src/seagallop.c:41
    "data/generated/gba/seagallop/manifest.lua",
    "data/generated/gba/seagallop/water.4bpp",
    "data/generated/gba/seagallop/ferry.4bpp",
    "data/generated/gba/seagallop/wake.4bpp",
    "data/generated/gba/seagallop/wb_tilemap.bin",
    "data/generated/gba/seagallop/eb_tilemap.bin",
    "data/generated/gba/seagallop/wb.rgba",
    "data/generated/gba/seagallop/eb.rgba",
    "data/generated/gba/trainers.lua",
    "data/generated/gba/trainers/back_0.rgba",
    "data/generated/gba/trainers/back_1.rgba",
    "data/generated/gba/trainer_card/manifest.lua",
    "data/generated/gba/trainer_card/bg.rgba",
    "data/generated/gba/field_effects/tall_grass.rgba",
    "data/generated/gba/field_effects/cut_grass.rgba",
    "data/generated/gba/field_effects/rock_smash.rgba",
    "data/generated/gba/field_effects/surf_blob.rgba",
    "data/generated/gba/field_effects/fly_bird.rgba",
    "data/generated/gba/field_effects/ripple.rgba",
    -- src/field_effect.c:3963 (Birth Island meteorite shatter shards)
    "data/generated/gba/field_effects/deoxys_rock_fragments.rgba",
    -- src/data/field_effects/field_effect_objects.h:565,1203
    "data/generated/gba/field_effects/splash.rgba",
    "data/generated/gba/field_effects/hot_springs_water.rgba",
    "data/generated/gba/field_effects/emoticons.rgba",
    -- src/slot_machine.c:399, :739
    "data/generated/gba/slot_machine/manifest.lua",
    "data/generated/gba/slot_machine/reel_icons.rgba",
    "data/generated/gba/slot_machine/clefairy.rgba",
    "data/generated/gba/slot_machine/digits.rgba",
    "data/generated/gba/slot_machine/bg.rgba",
    "data/generated/gba/slot_machine/payout_lights.rgba",
    "data/generated/gba/slot_machine/match_lines.rgba",
    "data/generated/gba/slot_machine/button_pressed.rgba",
    "data/generated/gba/slot_machine/combos_window.rgba",
    -- src/trade_scene.c:151
    "data/generated/gba/trade/manifest.lua",
    "data/generated/gba/trade/gba_screen.rgba",
    "data/generated/gba/trade/gba_screen_wireless.rgba",
    "data/generated/gba/trade/gba_screen_flash.rgba",
    "data/generated/gba/trade/cable_closeup.rgba",
    "data/generated/gba/trade/cable_end.rgba",
    "data/generated/gba/trade/link_mon_glow.rgba",
    "data/generated/gba/trade/link_mon_shadow.rgba",
    -- src/trade_scene.c:1121
    "data/generated/gba/trade/mon_shadow_bg.rgba",
    "data/generated/gba/trade/ball.rgba",
    "data/generated/gba/trade/ball_spin.rgba",
    -- src/trade.c:1368
    "data/generated/gba/trade/menu_bg1.rgba",
    "data/generated/gba/trade/stripes_bg2.rgba",
    "data/generated/gba/trade/stripes_bg3.rgba",
    "data/generated/gba/trade/party_box.rgba",
    "data/generated/gba/trade/moves_box.rgba",
    "data/generated/gba/trade/mon_box.rgba",
    "data/generated/gba/trade/menu_tiles.rgba",
    "data/generated/gba/trade/cursor.rgba",
    -- src/link_rfu_3.c:34, src/union_room_chat_objects.c:30
    "data/generated/gba/union_room/manifest.lua",
    "data/generated/gba/union_room/wireless_icon.rgba",
    "data/generated/gba/union_room/chat_bg.rgba",
    "data/generated/gba/union_room/chat_panel.rgba",
    "data/generated/gba/union_room/chat_icons.rgba",
    "data/generated/gba/union_room/chat_selector_cursor.rgba",
    "data/generated/gba/union_room/chat_text_entry_cursor.rgba",
    "data/generated/gba/union_room/chat_char_select_cursor.rgba",
    "data/generated/gba/union_room/chat_r_button.rgba",
    -- src/wireless_communication_status_screen.c:50
    "data/generated/gba/wireless_status/manifest.lua",
    "data/generated/gba/wireless_status/bg.rgba",
    "data/generated/gba/wireless_status/bg_index.bin",
    "data/generated/gba/wireless_status/palettes.pal",
    -- src/fame_checker.c:119, src/graphics.c:1230
    "data/generated/gba/fame_checker/manifest.lua",
    "data/generated/gba/fame_checker/bg.rgba",
    "data/generated/gba/fame_checker/pick_panel.rgba",
    "data/generated/gba/fame_checker/0.rgba",
    "data/generated/gba/fame_checker/1.rgba",
    "data/generated/gba/fame_checker/13.rgba",
    "data/generated/gba/fame_checker/14.rgba",
    "data/generated/gba/fame_checker/cursor.rgba",
    "data/generated/gba/fame_checker/question_mark.rgba",
    "data/generated/gba/fame_checker/silhouette.pal",
    "data/generated/gba/fame_checker/pack.lua",
    -- src/graphics.c:1117, src/teachy_tv.c:526
    "data/generated/gba/teachy_tv/manifest.lua",
    "data/generated/gba/teachy_tv/screen.rgba",
    "data/generated/gba/teachy_tv/title.rgba",
    "data/generated/gba/teachy_tv/end.rgba",
    -- src/teachy_tv.c:637, :1218
    "data/generated/gba/teachy_tv/static.rgba",
    "data/generated/gba/teachy_tv/bg3.rgba",
    -- src/mystery_gift_show_card.c:150, src/mystery_gift_show_news.c:99
    "data/generated/gba/mystery_gift/manifest.lua",
    "data/generated/gba/mystery_gift/card_bg0.rgba",
    "data/generated/gba/mystery_gift/card_bg7.rgba",
    "data/generated/gba/mystery_gift/news_bg0.rgba",
    "data/generated/gba/mystery_gift/news_bg7.rgba",
    -- src/trainer_tower_sets.c:8956
    "data/generated/gba/trainer_tower.lua",
    -- src/data/pokemon/tutor_learnsets.h:22
    "data/generated/gba/pokemon/tutor.lua",
    -- src/trainer_tower.c:554, include/constants/layouts.h:355, :363
    "data/generated/gba/native/layouts/alt_366.mid",
    "data/generated/gba/native/layouts/alt_373.mid",
    "data/generated/gba/native/layouts/alt_374.mid",
    "data/generated/gba/native/layouts/alt_381.mid",
    -- src/script_menu.c:1161
    "data/generated/gba/museum/manifest.lua",
    "data/generated/gba/museum/kabutops.rgba",
    "data/generated/gba/museum/aerodactyl.rgba",
    -- src/region_map.c:790 sAnim_DungeonIconVisited
    "data/generated/gba/region_map/dungeon_icon_visited.rgba",
    "data/generated/gba/region_map/dungeon_icon_visited.png",
    -- src/learn_move.c:403
    "data/generated/gba/move_relearner/manifest.lua",
    "data/generated/gba/move_relearner/bg.rgba",
    -- src/daycare.c:137, :138, :139
    "data/generated/gba/pokemon/egg/manifest.lua",
    "data/generated/gba/pokemon/egg/hatch.rgba",
    "data/generated/gba/pokemon/egg/shard.rgba",
    "data/generated/gba/pokemon/front/412.rgba",
    -- src/party_menu.c:2655
    "data/generated/gba/pokemon/icons/412.rgba",
    -- src/battle_records.c:563
    "data/generated/gba/trainer_tower/manifest.lua",
    "data/generated/gba/trainer_tower/records_bg.rgba",
    -- src/trainer_card.c:265, :1454, :1560
    "data/generated/gba/trainer_card/front_0.rgba",
    "data/generated/gba/trainer_card/front_4_female.rgba",
    "data/generated/gba/trainer_card/back_0.rgba",
    "data/generated/gba/trainer_card/back_4_female.rgba",
    "data/generated/gba/trainer_card/screen_0.rgba",
    "data/generated/gba/trainer_card/screen_4_female.rgba",
    "data/generated/gba/trainer_card/star.rgba",
    "data/generated/gba/trainer_card/stickers.rgba",
    -- src/credits.c:815, :1101, :1230
    "data/generated/gba/credits/manifest.lua",
    "data/generated/gba/credits/pack.lua",
    "data/generated/gba/credits/copyright.rgba",
    "data/generated/gba/credits/the_end.rgba",
    "data/generated/gba/credits/circle.rgba",
    "data/generated/gba/credits/pokeball_0.rgba",
    "data/generated/gba/credits/mon_0_1.rgba",
    "data/generated/gba/credits/player_male.rgba",
    "data/generated/gba/credits/rival.rgba",
    "data/generated/gba/credits/ground_grass.rgba",
    -- src/field_specials.c:2133
    "data/generated/gba/league/lighting.lua",
    -- src/diploma.c:119
    "data/generated/gba/diploma/manifest.lua",
    "data/generated/gba/diploma/kanto.rgba",
    "data/generated/gba/diploma/national.rgba",
    -- src/hall_of_fame.c:1163, :1181
    "data/generated/gba/hall_of_fame/manifest.lua",
    "data/generated/gba/hall_of_fame/bands.rgba",
    "data/generated/gba/hall_of_fame/stripes.rgba",
    "data/generated/gba/hall_of_fame/confetti.rgba",
    -- src/data/field_effects/field_effect_objects.h:288, src/itemfinder.c:39
    "data/generated/gba/field_effects/ground_impact_dust.rgba",
    "data/generated/gba/field_effects/itemfinder_arrow_star.rgba",
    -- src/field_effect.c:73, :77
    "data/generated/gba/field_effects/field_move_streaks_outdoors.rgba",
    "data/generated/gba/field_effects/field_move_streaks_indoors.rgba",
    -- src/pokemon.c:5904, src/decompress.c:83
    "data/generated/gba/pokemon/front_shiny/1.rgba",
    "data/generated/gba/pokemon/back_shiny/1.rgba",
    "data/generated/gba/pokemon/front_shiny/385_3.rgba",
    "data/generated/gba/pokemon/front/413.rgba",
    "data/generated/gba/pokemon/back/439.rgba",
    "data/generated/gba/pokemon/front_shiny/439.rgba",
    "data/generated/gba/pokemon/back_shiny/439.rgba",
    "data/generated/gba/pokemon/icons/439.rgba",
    -- src/pokemon.c:1350, :5339
    "data/generated/gba/pokemon/spinda/front.4bpp",
    "data/generated/gba/pokemon/spinda/normal.gbapal",
    "data/generated/gba/pokemon/spinda/shiny.gbapal",
    "data/generated/gba/pokemon/spinda/spots.bin",
    -- src/ss_anne.c:21-22
    "data/generated/gba/field_effects/ss_anne_wake.rgba",
    "data/generated/gba/field_effects/ss_anne_smoke.rgba",
    -- src/data/trainer_graphics/front_pic_tables.h:153
    "data/generated/gba/trainers/front/0.rgba",
    "data/generated/gba/trainers/front/147.rgba",
    -- src/pokeball.c:61
    "data/generated/gba/intro/ball_poke.png",
    -- src/battle_message.c:517, src/item_menu.c:183, src/oak_speech.c:588
    "data/generated/gba/scripts/text_tables.lua",
    -- src/easy_chat.c:41, src/data/easy_chat/easy_chat_groups.h:26
    "data/generated/gba/easy_chat/words.lua",
    -- src/fldeff_flash.c:157-162
    "data/generated/gba/cave_transition/screen.bin",
    "data/generated/gba/cave_transition/palettes.lua",
    -- src/data/ingame_trades.h:1, :184
    "data/generated/gba/trades/ingame_trades.lua",
    -- src/pokemon.c:1666, :6206
    "data/generated/gba/trainers/union_room_classes.lua",
    -- src/region_map.c:393-427, :527, :3158-3171, :3359
    "data/generated/gba/region_map/manifest.lua",
    "data/generated/gba/region_map/layouts.lua",
    "data/generated/gba/region_map/section_geometry.lua",
    "data/generated/gba/region_map/sevii123_map.png",
    "data/generated/gba/region_map/sevii45_map.png",
    "data/generated/gba/region_map/sevii67_map.png",
    "data/generated/gba/region_map/switch_button.png",
    "data/generated/gba/region_map/navel_rock_patch.png",
    "data/generated/gba/region_map/birth_island_patch.png",
    "data/generated/gba/region_map/frame_normal.png",
    "data/generated/gba/region_map/frame_fly.png",
    "data/generated/gba/region_map/switch_menu_123.png",
    "data/generated/gba/region_map/switch_menu_all.png",
    "data/generated/gba/region_map/switch_cursor_left.png",
    "data/generated/gba/region_map/switch_cursor_right.png",
    "data/generated/gba/region_map/edge_top_left.png",
    "data/generated/gba/region_map/edge_top_right.png",
    "data/generated/gba/region_map/edge_mid_left.png",
    "data/generated/gba/region_map/edge_mid_right.png",
    "data/generated/gba/region_map/edge_bottom_left.png",
    "data/generated/gba/region_map/edge_bottom_right.png",
    -- data/battle_ai_scripts.s:17
    "data/generated/gba/battle_ai/pack.lua",
    -- src/menu_indicators.c:258
    "data/generated/gba/chrome/scroll_arrows.rgba",
    "data/generated/gba/chrome/red_arrow_cursor.rgba",
    "data/generated/gba/chrome/selector_outline.rgba",
    "data/generated/gba/chrome/red_arrow.pal",
    -- src/minigame_countdown.c:213, src/pokemon_jump.c:454, src/digit_obj_util.c:67
    "data/generated/gba/link/countdown_321.pal",
    "data/generated/gba/link/countdown_321.rgba",
    "data/generated/gba/link/manifest.lua",
    "data/generated/gba/link/minigame_countdown.pal",
    "data/generated/gba/link/minigame_countdown_numbers.rgba",
    "data/generated/gba/link/minigame_countdown_start.rgba",
    "data/generated/gba/link/minigame_digits.pal",
    "data/generated/gba/link/minigame_digits.rgba",
    -- src/mystery_gift_show_card.c:115, src/mystery_gift_menu.c:33
    "data/generated/gba/mystery_gift/border.pal",
    "data/generated/gba/mystery_gift/border_tiles.rgba",
    "data/generated/gba/mystery_gift/menu_bg.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow.pal",
    "data/generated/gba/mystery_gift/stamp_shadow_0.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_1.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_2.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_3.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_4.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_5.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_6.rgba",
    "data/generated/gba/mystery_gift/stamp_shadow_7.rgba",
    -- src/union_room_player_avatar.c:33
    "data/generated/gba/union_room/avatars.lua",
    -- src/berry_crush.c:647, src/graphics.c:1378
    "data/generated/gba/berry_crush/bg.bin",
    "data/generated/gba/berry_crush/bg.rgba",
    "data/generated/gba/berry_crush/container_cap.bin",
    "data/generated/gba/berry_crush/container_cap.rgba",
    "data/generated/gba/berry_crush/core.pal",
    "data/generated/gba/berry_crush/crusher.4bpp",
    "data/generated/gba/berry_crush/crusher.pal",
    "data/generated/gba/berry_crush/crusher.rgba",
    "data/generated/gba/berry_crush/crusher_base.rgba",
    "data/generated/gba/berry_crush/crusher_top.bin",
    "data/generated/gba/berry_crush/crusher_top.rgba",
    "data/generated/gba/berry_crush/effect.pal",
    "data/generated/gba/berry_crush/impact.rgba",
    "data/generated/gba/berry_crush/manifest.lua",
    "data/generated/gba/berry_crush/sparkle.rgba",
    "data/generated/gba/berry_crush/tables.lua",
    "data/generated/gba/berry_crush/text_windows.bin",
    "data/generated/gba/berry_crush/text_windows.rgba",
    "data/generated/gba/berry_crush/timer.pal",
    "data/generated/gba/berry_crush/timer_digits.rgba",
    -- src/dodrio_berry_picking.c:3323
    "data/generated/gba/dodrio_berry_picking/berries.pal",
    "data/generated/gba/dodrio_berry_picking/berries.rgba",
    "data/generated/gba/dodrio_berry_picking/bg.bin",
    "data/generated/gba/dodrio_berry_picking/bg.pal",
    "data/generated/gba/dodrio_berry_picking/bg.rgba",
    "data/generated/gba/dodrio_berry_picking/cloud.pal",
    "data/generated/gba/dodrio_berry_picking/cloud.rgba",
    "data/generated/gba/dodrio_berry_picking/dodrio.pal",
    "data/generated/gba/dodrio_berry_picking/dodrio.rgba",
    "data/generated/gba/dodrio_berry_picking/dodrio_shiny.pal",
    "data/generated/gba/dodrio_berry_picking/dodrio_shiny.rgba",
    "data/generated/gba/dodrio_berry_picking/manifest.lua",
    "data/generated/gba/dodrio_berry_picking/scenery.4bpp",
    "data/generated/gba/dodrio_berry_picking/status.pal",
    "data/generated/gba/dodrio_berry_picking/status.rgba",
    "data/generated/gba/dodrio_berry_picking/tables.lua",
    "data/generated/gba/dodrio_berry_picking/tree_border.4bpp",
    "data/generated/gba/dodrio_berry_picking/tree_border_left.bin",
    "data/generated/gba/dodrio_berry_picking/tree_border_left.rgba",
    "data/generated/gba/dodrio_berry_picking/tree_border_right.bin",
    "data/generated/gba/dodrio_berry_picking/tree_border_right.rgba",
    -- src/pokemon_jump.c:2901
    "data/generated/gba/pokemon_jump/bg.4bpp",
    "data/generated/gba/pokemon_jump/bg.bin",
    "data/generated/gba/pokemon_jump/bg.pal",
    "data/generated/gba/pokemon_jump/bg.rgba",
    "data/generated/gba/pokemon_jump/bonuses.4bpp",
    "data/generated/gba/pokemon_jump/bonuses.bin",
    "data/generated/gba/pokemon_jump/bonuses.rgba",
    "data/generated/gba/pokemon_jump/manifest.lua",
    "data/generated/gba/pokemon_jump/pal1.pal",
    "data/generated/gba/pokemon_jump/pal2.pal",
    "data/generated/gba/pokemon_jump/star.rgba",
    "data/generated/gba/pokemon_jump/tables.lua",
    "data/generated/gba/pokemon_jump/venusaur.4bpp",
    "data/generated/gba/pokemon_jump/venusaur.bin",
    "data/generated/gba/pokemon_jump/venusaur.rgba",
    "data/generated/gba/pokemon_jump/vine1.rgba",
    "data/generated/gba/pokemon_jump/vine1_pal2.rgba",
    "data/generated/gba/pokemon_jump/vine2.rgba",
    "data/generated/gba/pokemon_jump/vine2_pal2.rgba",
    "data/generated/gba/pokemon_jump/vine3.rgba",
    "data/generated/gba/pokemon_jump/vine3_pal2.rgba",
    "data/generated/gba/pokemon_jump/vine4.rgba",
    "data/generated/gba/pokemon_jump/vine4_pal2.rgba",
  },
}
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.leafgreen = {}
for i, path in ipairs(CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered) do
  CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.leafgreen[i] = path
end
table.insert(CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.leafgreen,
  "data/generated/gba/intro/title_streak.png")
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.silver =
  CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.gold

local SEMANTIC_MODULES = {
  [1] = {
    "constants", "maps", "tilesets", "text", "text_pointers",
    "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
    "type_chart", "trainers", "encounters", "field", "battle_anims",
  },
  [2] = {
    "pokemon", "moves", "items", "type_chart", "audio", "font", "maps",
    "tilesets", "text", "rom_text", "trainers", "encounters", "sprites",
    "palettes", "icons", "battle_anims", "constants", "landmarks",
  },
  [3] = { "maps", "intro", "audio" },
}

local OPTIONAL_SEMANTIC_MODULES = {
  [1] = { "audio", "palettes", "icons" },
  [2] = {},
  [3] = {},
}

local function copy(values)
  local out = {}
  for index, value in ipairs(values or {}) do out[index] = value end
  return out
end

function CacheContract.requiredFilesFor(version)
  local override = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE[version]
  if override then return override, true end
  return CacheContract.REQUIRED_FILES, false
end

-- A detached, version-specific inventory for read-only consumers. Semantic
-- consumers additionally require every generated module that backs the public
-- registry surface; optional semantic roots are discovered lazily.
function CacheContract.requiredFiles(version, semantic)
  local base, isOverride = CacheContract.requiredFilesFor(version)
  local files = copy(base)
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      files[#files + 1] = path
    end
  end
  if semantic then
    for _, name in ipairs(SEMANTIC_MODULES[GameVersion.generation(version)] or {}) do
      files[#files + 1] = "data/generated/" .. name .. ".lua"
    end
  end
  local seen, out = {}, {}
  for _, path in ipairs(files) do
    if not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

function CacheContract.semanticModules(version)
  return copy(SEMANTIC_MODULES[GameVersion.generation(version)])
end

function CacheContract.optionalSemanticModules(version)
  return copy(OPTIONAL_SEMANTIC_MODULES[GameVersion.generation(version)])
end

function CacheContract.formatFor(version)
  return CacheContract.VERSION_FORMAT[version] or CacheContract.FORMAT
end

function CacheContract.markerFor(version, sha1)
  return CacheContract.formatFor(version)
    .. (sha1 or GameVersion.info(version).sha1)
end

function CacheContract.markerMatches(version, marker)
  for _, revision in ipairs(GameVersion.revisions(version)) do
    if marker == CacheContract.markerFor(version, revision.sha1) then return true end
  end
  return false
end

-- Keep the process-global CacheFs prefix isolated even when a filesystem
-- adapter raises while probing or publishing.  The real CacheFs methods
-- return errors, but this also makes the contract safe for platform adapters
-- that surface I/O failures as Lua errors.
local function withVersionPrefix(version, fs, action)
  local saved = fs.prefix
  fs.prefix = GameVersion.cachePrefix(version)
  local ok, first, second = pcall(action)
  fs.prefix = saved
  if not ok then return false, first end
  return true, first, second
end

function CacheContract.allRequiredFilesExist(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, complete, missing = withVersionPrefix(version, fs, function()
    local required, isOverride = CacheContract.requiredFilesFor(version)
    local missingPath
    for _, path in ipairs(required) do
      if not fs.exists(path) then missingPath = path; break end
    end
    if not missingPath and not isOverride then
      for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
        if not fs.exists(path) then missingPath = path; break end
      end
    end
    return missingPath == nil, missingPath
  end)
  if not ok then return false, complete end
  return complete, missing
end

function CacheContract.readMarker(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, marker, readError = withVersionPrefix(version, fs, function()
    return fs.read(CacheContract.MARKER_PATH)
  end)
  if not ok then return nil, marker end
  -- LÖVE may return contents plus a byte count; only a nil contents result
  -- makes the auxiliary value an error.  CacheFs' portable reader returns
  -- just the contents, so this remains adapter-neutral.
  if marker == nil then return nil, readError end
  return marker
end

function CacheContract.cacheVersionCurrent(version, fs)
  if GameVersion.generation(version) ~= 3 then return true end
  fs = fs or require("src.import.CacheFs")
  local okV, Versions = pcall(require, "src.import.gba.versions")
  if not okV or not Versions or not Versions.CACHE_VERSION then return true end
  local ok, raw = withVersionPrefix(version, fs, function()
    return fs.read("data/generated/gba/meta.json")
  end)
  if not ok or type(raw) ~= "string" then return false end
  local stamped = tonumber(raw:match('"cache_version"%s*:%s*(%d+)'))
  return stamped == Versions.CACHE_VERSION
end

function CacheContract.isReady(version, fs)
  fs = fs or require("src.import.CacheFs")
  if CacheContract.sourceTreeHasData(version) then return true end
  local marker, readError = CacheContract.readMarker(version, fs)
  if readError or not CacheContract.markerMatches(version, marker) then return false end
  if not CacheContract.cacheVersionCurrent(version, fs) then return false end
  return CacheContract.allRequiredFilesExist(version, fs)
end

function CacheContract.publish(version, fs, sha1)
  fs = fs or require("src.import.CacheFs")
  local complete, missing = CacheContract.allRequiredFilesExist(version, fs)
  if not complete then
    -- A caller may be retrying over a partially replaced cache.  Do not
    -- leave its old marker advertising readiness after this failed check.
    local removed, removeError = withVersionPrefix(version, fs, function()
      if not fs.remove then
        error("cache filesystem cannot remove the completion marker")
      end
      return fs.remove(CacheContract.MARKER_PATH)
    end)
    if not removed then
      return false, "cache is incomplete; missing " .. tostring(missing)
        .. "; could not remove completion marker: " .. tostring(removeError)
    end
    return false, "cache is incomplete; missing " .. tostring(missing)
  end
  local changed, ok, err = withVersionPrefix(version, fs, function()
    return fs.write(CacheContract.MARKER_PATH, CacheContract.markerFor(version, sha1))
  end)
  if not changed then return false, tostring(ok) end
  return ok, err
end

function CacheContract.sourceTreeHasData(version)
  if not (love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getRealDirectory and love.filesystem.getSource) then
    return false
  end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  local source = love.filesystem.getSource()
  for _, path in ipairs(required) do
    local fullPath = prefix .. path
    if love.filesystem.getInfo(fullPath, "file") == nil
        or love.filesystem.getRealDirectory(fullPath) ~= source then
      return false
    end
  end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      local fullPath = prefix .. path
      if love.filesystem.getInfo(fullPath, "file") == nil
          or love.filesystem.getRealDirectory(fullPath) ~= source then
        return false
      end
    end
  end
  return true
end

-- Inspect another version without mutating CacheFs.prefix, GameVersion, mounts,
-- or the active Data table. The injected filesystem addresses exact paths.
local function readAt(fs, path)
  if fs.readAt then return fs.readAt(path) end
  if fs.read then return fs.read(path) end
  return nil
end

local function isFileAt(fs, path)
  if fs.getInfo then
    local info = fs.getInfo(path, "file")
    return info ~= nil and (info.type == nil or info.type == "file")
  end
  if fs.existsAt then return fs.existsAt(path) == true end
  return false
end

local function hasExactFiles(version, fs, prefix, semantic)
  for _, path in ipairs(CacheContract.requiredFiles(version, semantic)) do
    if not isFileAt(fs, prefix .. path) then return false, path end
  end
  return true
end

local function sourceReady(version, fs, semantic)
  if not (fs.getInfo and fs.getRealDirectory and fs.getSource) then return nil end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local complete = hasExactFiles(version, fs, prefix, semantic)
  if not complete then return nil end
  local first = prefix .. CacheContract.requiredFiles(version, semantic)[1]
  if fs.getRealDirectory(first) ~= fs.getSource() then return nil end
  return { kind = "source", prefix = prefix }
end

function CacheContract.inspect(version, fs, opts)
  opts = opts or {}
  if not (GameVersion.VERSIONS[version] and fs) then
    return nil, "not_imported", "unsupported cache inspection"
  end
  if opts.allowSource then
    local source = sourceReady(version, fs, opts.semantic)
    if source then return source end
  end
  local prefix = GameVersion.cachePrefix(version)
  local marker = readAt(fs, prefix .. CacheContract.MARKER_PATH)
  if not CacheContract.markerMatches(version, marker) then
    return nil, "not_imported", "completion marker is missing or stale"
  end
  local complete, missing = hasExactFiles(version, fs, prefix, opts.semantic)
  if not complete then
    return nil, "not_imported", "required cache file is missing: " .. tostring(missing)
  end
  return { kind = "cache", prefix = prefix, marker = marker }
end

return CacheContract

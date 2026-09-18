# FireRed Quest Log

Continue plays a history of up to four recent scenes, then shows the saved
location and resumes the field. A advances to the next scene; B ends the recap.
Scenes also advance automatically. The existing input bindings apply, including
touch controls and controllers.

Restart the engine to load the feature. Existing saves remain compatible but have
no recorded history until you play with this version. Visit another map or perform
a recorded action, save, return to the title screen, and choose Continue.

## Recording and presentation

The importer extracts all 125 Quest Log strings from the user's FireRed ROM into
`data/generated/gba/quest_log/pack.lua`. Offsets have been checked against BPRE 1.0
and Rev 1; the main game importer still supports FireRed 1.0. Cache version is 92.
No extracted strings, ROMs, or graphics are included in the source tree.

Records include map arrivals, player/NPC movement and sprite poses, trainer wins,
wild wins/catches, Pokémon Center use, shopping, field moves implemented by this
engine, successful item use, held-item changes, TM/HM learning, party ordering,
PC Pokémon/item deposits and withdrawals, box movement, and key items received
through scripts. Failed item transactions do not generate records. Trainer battle
wording uses the active Pokémon's remaining HP thresholds from the original game.
Trainer Tower, elevators, the Trainer Fan Club, and e-Reader rooms are excluded.

Previous scenes use monochrome maps and sprites, the original font and event
narration, descending scene numbers, and the recorded map music. The final saved
location appears in color. Scene data is part of the normal native save schema.

## Playback isolation

`quest_log.lua` owns bounded data and playback timing. `quest_log_recorder.lua`
observes completed engine actions and captures visible tiles/actors.
`src/ui/game3/quest_log.lua` renders those records without loading a historical map
into the live runtime. Continue delays starting the field until playback ends.
Scripts, encounters, playtime, and gameplay RNG do not run during the recap.
Closing the application during the recap does not write a save.

This is a native reconstruction of the feature, not execution of the ROM's Quest
Log bytecode. Each scene retains at most 300 actor samples (10 Hz, interpolated
for presentation), eight event descriptions, and deduplicated visible metatiles.
Tiles reflect their most recently captured state within that scene. Engine field
particle effects, door animation, weather, and battle/menu screens themselves
are not replayed. Event selection is broader than the ROM's story-dependent
filters, and narration timing/scene transitions are not frame-exact. Multiplayer
recap events are not connected to this engine's link functionality.

## Verification

- `luajit tests/game3_quest_log_test.lua`
- `luajit tests/game3_quest_log_integration_test.lua`
- `luajit tests/game3_quest_log_events_test.lua`
- `luajit tests/game3_quest_log_rom_test.lua /path/to/FireRed.gba`

Tests cover bounded history, detached persistence, JSON round-tripping, automatic
playback, A/B skipping, legacy saves, Continue integration, RNG/runtime isolation,
quit/save protection, event scoping, failed item use, PC moves, and nurse specials.
ROM tests cover both revisions and original text placeholders. Existing help,
shop, storage, party-item, parcel/script, battle-reward, save, title-exit, and cache
contract suites were also run. ROM-dependent suites require the imported cache.

The renderer and recorder were exercised offline with the user's imported maps,
sprites, font atlases and save-schema JSON, without opening or controlling the
running game. Live gameplay testing is still required.

# Mystery Dungeon Follower

Your lead Pokémon follows you using sprite sheets imported from Pokémon Mystery
Dungeon: Red Rescue Team. Works with Red, Blue, Yellow, Gold, Silver, Crystal,
FireRed, and LeafGreen.

1. In the launcher, open **IMPORTERS → Pokémon Mystery Dungeon** and import your
   USA/Australia Red Rescue Team `.gba` ROM.
2. Enable **Mystery Dungeon Follower** in the mod manager for your game.
3. Put a healthy Pokémon in the first party slot and enter the overworld.

Changing the lead changes the follower. Eggs and fainted leads stay in their
Poké Balls. The follower hides while surfing, biking, or fishing. Shiny Pokémon
use the standard PMD colors. This replaces Yellow's usual companion while enabled.

This folder is a standalone example mod and contains no Pokémon artwork.
Publish/package the folder with its manifest and main script; players supply
their own ROM through the importer. It requires an engine build with the PMD
importer, `mod.packs:metadata`, and the `world.follower.spawn` hook.

See `docs/mystery-dungeon-importer.md` in the engine repository for the sprite
format, animation metadata, renderer helper, and verification commands.

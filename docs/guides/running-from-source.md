# Running from source

Requires LÖVE 11.x. Place a ROM in the project folder and double-click
`Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Pokemon Red.gb"
scripts/run.sh
```

then `love .` for later launches.

## The `baseroms/` drop folder

The launcher scans `baseroms/` once at startup on desktop, the same way the
Xbox build has always done it. Put your legally obtained dumps there and each
game's tab shows ROM FOUND with an import button, so a library survives a
deleted cache without going through the picker again.

Where the folder is looked for:

- the project folder when you run `love .` (beside `main.lua`);
- the folder holding the executable in a packaged build;
- inside the portable folder when `portable.txt` is present.

A file is identified by its SHA-1. The size is only a gate: a clean dump is
1, 2 or 16 MiB and nothing else, so a file of any other size is skipped
without being read. The filename is ignored on purpose, because a name proves
nothing and the importer re-verifies the hash before it writes a cache.

Only the clean dumps in the [README table](../../README.md) are accepted. A
patched, trimmed or region-changed ROM hashes to something unknown, so the
launcher leaves that tab empty and says so instead of offering an import that
would fail. `roms/` is a different folder: that one holds the copy the
importer keeps for auto re-import, not a drop zone.

Windows PowerShell scripts, the optional developer data build, test suites,
and cache management are covered in the
[Developer Setup guide](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Developer-Setup).
Runtime internals are in [architecture.md](../architecture.md).

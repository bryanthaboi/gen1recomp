-- Root-level ROM-free regressions that predate the globbed engine directory.
-- Keep the explicit list small: broad families belong in a discovered tier
-- such as run_gen2.lua, while one-off files here must be deliberately named.

package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.tier_runner").mainFiles({
  "tests/launcher_mods_shadow_copy_bug801_834_test.lua",
  "tests/rom_importer_cursor_bug781_test.lua",
  "tests/rom_importer_ios_save_export_test.lua",
}, "standalone regressions")

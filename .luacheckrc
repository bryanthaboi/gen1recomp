-- Static-analysis config for `luacheck` (https://luacheck.readthedocs.io).
--
-- Run it over the engine with:  luacheck src   (or scripts/lint.sh)
--
-- The point is a high-signal baseline: the categories left on are the ones
-- that catch real defects -- undefined globals/locals (the class that hid a
-- `music.volume` crash: applyVolume read a `state` that was still the nil
-- global), unused values, unreachable code, redefinitions. The cosmetic
-- categories the codebase deliberately lives with (a `self`/`dt` an
-- interface requires but a given method ignores, documented empty
-- fall-through branches, the odd long line) are muted so they don't drown
-- the signal.

std = "luajit"

-- LÖVE exposes `love` as a mutable table: games assign their callbacks onto
-- it (love.wheelmoved, love.run, ...), so it is a regular global, not
-- read-only -- otherwise every callback registration reads as a violation.
globals = { "love" }

read_globals = {
  "jit",
  -- LuaJIT 2.1 ships table.unpack even though the bare 5.1 `table` std lacks
  -- it; without this, every `table.unpack` reads as an undefined field.
  table = { fields = { "unpack" } },
  "POKEPORT_DISPLAY_COMPANION",
  "POKEPORT_EDITOR_MODE",
  "rawlen",
  package = { fields = { "searchers" } },
}

-- Vendored/native trees and the test suites have their own conventions.
exclude_files = {
  "mobile/",
  "tests/",
  "tools/save-editor/",
  "tools/save_convert/vendor/",
}

ignore = {
  "212",  -- unused argument -- self/dt kept for a shared method signature
  "213",  -- unused loop variable -- `for _, v in` where only v is wanted
  "421",  -- shadowing a local -- deliberate re-use in a few tight scopes
  "431",  -- shadowing an upvalue
  "432",  -- shadowing an argument
  "542",  -- empty if branch -- documented fall-throughs, not gaps
  "631",  -- line is too long
}

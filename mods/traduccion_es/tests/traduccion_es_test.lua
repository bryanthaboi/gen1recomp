-- Standalone: luajit mods/traduccion_es/tests/traduccion_es_test.lua
-- Loads the mod through the real headless loader and asserts its stated
-- effects. The cartridge layer needs a player's EUR dump and love.data,
-- neither of which exists headlessly, so here it must degrade to a clean
-- no-op; its decoding is exercised below against synthetic byte streams
-- authored in this file (nothing ROM-derived).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

-- ---- loads clean, cartridge layer degrades gracefully ----------------
local run = T.sdk.loadMod("mods/traduccion_es", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded", "reached the loaded state")

-- ---- stated effect: the hand-translated engine strings land ----------
T.eq(Data.strings["FIGHT"], "LUCHA", "battle menu translated")
T.eq(Data.strings["%s\nfainted!"], "¡%s\nse debilitó!",
  "faint message translated")
T.eq(Data.strings["Go! %s!"], "¡Adelante,\n%s!", "send-out translated")

-- every filled string keeps its directive arity, or the engine would
-- refuse it at draw time and quietly fall back to English
local strings = assert(loadfile("mods/traduccion_es/lang/strings.lua"))()
local function directives(s)
  local n = 0
  for _ in s:gmatch("%%[sd]") do n = n + 1 end
  return n
end
local mismatched = 0
for source, value in pairs(strings) do
  if value ~= "" and directives(source) ~= directives(value) then
    mismatched = mismatched + 1
  end
end
T.eq(mismatched, 0, "every translated string keeps its directive count")

-- ---- decoder: synthetic byte streams ---------------------------------
local Decoder = assert(loadfile("mods/traduccion_es/rom/decoder.lua"))()
local charmap = {
  [0x4F] = "\n", [0x80] = "A", [0x81] = "B", [0x60] = "<BOLD_A>",
}

local function stream(at, bytes)
  return ("\0"):rep(at) .. string.char(unpack(bytes))
end

-- plain text: command $00, glyphs, terminator $50
T.eq(Decoder.text(stream(16, { 0x00, 0x80, 0x4F, 0x81, 0x57 }),
  0, 16, charmap), "A\nB", "decodes a plain stream")

-- the engine's glyph overrides win over the charmap, and <X> respells {X}
T.eq(Decoder.text(stream(0, { 0x00, 0x4B, 0x60, 0x57 }), 0, 0, charmap),
  "{_CONT}{BOLD_A}", "overrides and <X> -> {X} respelling")

-- an unmapped byte keeps the {BYTE:XX} escape
T.eq(Decoder.text(stream(0, { 0x00, 0x7E, 0x57 }), 0, 0, charmap),
  "{BYTE:7E}", "unmapped byte escapes")

-- dynamic substitution: command $01 consumes its 2-byte operand
T.eq(Decoder.text(stream(0, { 0x01, 0x34, 0x12, 0x00, 0x80, 0x57 }),
  0, 0, charmap, { { 1, "{RAM:wBuffer}" } }),
  "{RAM:wBuffer}A", "dynamic substitution applies")

-- a stream demanding a substitution the spec does not carry soft-fails
local text, reason = Decoder.text(stream(0, { 0x01, 0x34, 0x12, 0x50 }),
  0, 0, charmap)
T.eq(text, nil, "missing substitution soft-fails")
T.check(tostring(reason):find("missing dynamic"), "with the right reason")

-- name tables: 0x50-terminated sequential and fixed-width reads
local names, consumed = Decoder.string(
  stream(4, { 0x80, 0x81, 0x50 }), 0, 4, charmap, 32)
T.eq(names, "AB", "sequential name decodes")
T.eq(consumed, 3, "and reports its consumed bytes")
T.eq(Decoder.fixed(stream(0, { 0x80, 0x50, 0x81, 0x81 }), 0, 0, charmap, 4),
  "A", "fixed-width name stops at the pad byte")

-- catalogs: a mini spec end to end, including the UNUSED slot skip
local spec = {
  charmap = charmap,
  dialogue = { _TestText = { 0, 16 } },
  dynamic = {},
  names = {
    moves = { bank = 0, address = 32, order = { "POUND", "KARATE_CHOP" } },
    species = { bank = 0, address = 64, width = 4,
                order = { "RHYDON", "UNUSED" } },
  },
}
local rom = ("\0"):rep(16) .. string.char(0x00, 0x80, 0x57)
  .. ("\0"):rep(32 - 19) .. string.char(0x80, 0x50, 0x81, 0x50)
  .. ("\0"):rep(64 - 36)
  .. string.char(0x80, 0x81, 0x50, 0x50, 0x81, 0x81, 0x81, 0x81)
local catalogs, stats = Decoder.catalogs(rom, spec)
T.eq(catalogs.dialogue._TestText, "A", "catalog dialogue decodes")
T.eq(catalogs.names.moves.POUND, "A", "first sequential name lands")
T.eq(catalogs.names.moves.KARATE_CHOP, "B", "second follows the terminator")
T.eq(catalogs.names.species.RHYDON, "AB", "fixed-width species name lands")
T.eq(catalogs.names.species.UNUSED, nil, "UNUSED slots are skipped")
T.eq(#stats.skipped, 0, "nothing skipped in the mini spec")

-- ---- the shipped spec stays sound ------------------------------------
local shipped = assert(loadfile("mods/traduccion_es/rom/spec_es.lua"))()
T.eq(#shipped.roms, 2, "spec carries the Red and Blue EUR hashes")
for _, entry in ipairs(shipped.roms) do
  T.check(entry.sha1:match("^%x{40}$") or #entry.sha1 == 40,
    "sha1 is 40 hex chars: " .. entry.sha1)
end
local labels = 0
for label in pairs(shipped.dialogue) do
  labels = labels + 1
  T.check(shipped.dialogue[label][1] ~= nil and shipped.dialogue[label][2],
    "label carries bank and address: " .. label)
end
T.eq(labels, 2585, "all 2585 dialogue labels present")
T.eq(#shipped.names.moves.order, 165, "165 move slots")
T.eq(#shipped.names.items.order, 97, "97 item slots")
T.eq(#shipped.names.trainers.order, 47, "47 trainer classes")
T.eq(#shipped.names.species.order, 190, "190 species slots")

run.release()
T.finish("traduccion_es")

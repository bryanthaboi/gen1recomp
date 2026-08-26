-- Gen 2's engine text, the counterpart to Gen 1's data/generated/text.lua.
--
-- Gold and Silver had no label-keyed string table at all: the manifests
-- carried no `text` section, RomExtractorGen2 had no extractText, and
-- game.data.text was never assigned, so every call through
-- src/core/RomText.lua fell back to the literal written beside it.  These
-- cover the three halves of closing that: the manifest names the labels and
-- resolves every one, the decoder emits the runtime name slots rather than
-- dropping them, and RomText fills those slots.
--
--   GOLD_CACHE="..." luajit tests/gen2_rom_text_test.lua
--
-- ROM-free apart from the last section, which reads an imported cache's
-- rom_text.lua and skips cleanly when there is none.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 rom text")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Json = require("src.link.Json")
local romText = require("src.core.RomText")

local function manifest(path)
  local file = assert(io.open(path, "r"))
  local data = assert(Json.decode(file:read("*a")))
  file:close()
  return data
end

-- ---- the label list, and that every label resolves ------------------------
-- A label the list names but the symbol table cannot place would fail the
-- import at the Dialogue stage rather than at generation time, so the pairing
-- is asserted here instead.
for _, edition in ipairs({ "gold", "silver", "crystal" }) do
  local data = manifest("tools/rom_manifest_" .. edition .. ".json")
  local labels = (data.text or {}).labels or {}
  check((data.text or {}).labels ~= nil,
    edition .. " carries a text section")
  check(#labels > 800,
    ("%s names %d text labels"):format(edition, #labels))

  local unresolved = {}
  for _, label in ipairs(labels) do
    if not data.symbols[label] then unresolved[#unresolved + 1] = label end
  end
  eq(#unresolved, 0,
    ("every %s text label resolves to a symbol (%s)")
      :format(edition, table.concat(unresolved, ", "):sub(1, 60)))

  local named = {}
  for _, label in ipairs(labels) do named[label] = true end

  -- data/text/ also holds keyboard layouts and kana tables.  Decoded as text
  -- they come out as keyboard rows, so make_gold_manifest.TEXT_SOURCES leaves
  -- their files out.  `BattleText::` is excluded for a different reason: it
  -- is a bank anchor sharing an address with the first real label under it,
  -- and its own comment in the disassembly says so.
  for _, excluded in ipairs({ "NameInputLower", "MailEntry_Uppercase",
      "Dakutens", "Gen1TrainerClassNames", "BattleText" }) do
    check(not named[excluded],
      edition .. " leaves " .. excluded .. " out of the text list")
  end
end

-- Gold and Silver describe the same strings; only the addresses move.
do
  local gold = (manifest("tools/rom_manifest_gold.json").text or {}).labels or {}
  local silver =
    (manifest("tools/rom_manifest_silver.json").text or {}).labels or {}
  eq(#gold, #silver, "Gold and Silver name the same number of labels")
  local mismatch
  for index, label in ipairs(gold) do
    if silver[index] ~= label then mismatch = label; break end
  end
  eq(mismatch, nil, "and the same labels in the same order")

  local crystal =
    (manifest("tools/rom_manifest_crystal.json").text or {}).labels or {}
  check(#crystal > #gold,
    ("Crystal names more labels than Gold (%d vs %d)"):format(#crystal, #gold))
  local named = {}
  for _, label in ipairs(gold) do named[label] = true end
  local extra = 0
  for _, label in ipairs(crystal) do
    if not named[label] then extra = extra + 1 end
  end
  check(extra > 0,
    ("and %d of them are Crystal-only, so it is not a Gold alias")
      :format(extra))
end

-- ---- the gendered player name ---------------------------------------------
-- ../pokecrystal/constants/charmap.asm:6 <PLAY_G> ($14),
-- ../pokecrystal/home/text.asm:243,380 PlaceGenderedPlayerName
do
  local Extractor = require("src.import.RomExtractorGen2")
  local charmap = manifest("tools/rom_manifest_crystal.json").charmap

  local function decode(edition, bytes)
    local rom = {}
    function rom:byte(_, address) return bytes[address] or 0x50 end
    function rom:word(_, address)
      return (bytes[address] or 0) + (bytes[address + 1] or 0) * 0x100
    end
    local extractor = setmetatable({ rom = rom, edition = edition }, Extractor)
    return extractor:decodeGen2Text(0, 0, charmap)
  end

  local H, i, comma, space, bang = 0x87, 0xa8, 0xf4, 0x7f, 0xe7
  local inString = { [0] = 0x00, H, i, comma, space, 0x14, bang, 0x57 }
  eq(decode("crystal", inString), "Hi, {PLAYER}!",
    "an in-string $14 decodes as the player's name")
  eq(decode("gold", inString), "Hi, !",
    "and only on Crystal, which is the only edition that writes one")

  local command = { [0] = 0x14, 0x03, 0x00, H, i, 0x57 }
  eq(decode("crystal", command), "{STRBUF}Hi",
    "a $14 outside a string is still TX_STRINGBUFFER and eats its buffer id")
end

-- ---- the slots RomText fills ----------------------------------------------
-- decodeGen2Text emits {USER}, {TARGET} and {ENEMY} for the three names
-- PlaceMoveUsersName / PlaceMoveTargetsName / PlaceEnemysName write at
-- runtime (home/text.asm:302, :307, :327).  Dropped, the line printed with a
-- hole where the name belongs.
do
  local data = { text = {
    SubTookDamageText = "The SUBSTITUTE\ntook damage for\v{TARGET}!",
    WantsToBattleText = "{ENEMY}\nwants to battle!",
    ConfusedNoMoreText = "{USER}'s\nconfused no more!",
    SuperEffectiveText = "It's super-\neffective!",
  } }

  eq(romText(data, "SubTookDamageText", "fallback", "GEODUDE"),
    "The SUBSTITUTE\ntook damage for\vGEODUDE!",
    "a {TARGET} slot takes the name the caller passes")
  eq(romText(data, "WantsToBattleText", "fallback", "FALKNER"),
    "FALKNER\nwants to battle!", "and so does {ENEMY}")
  eq(romText(data, "ConfusedNoMoreText", "fallback", "CYNDAQUIL"),
    "CYNDAQUIL's\nconfused no more!", "and {USER}")
  eq(romText(data, "SuperEffectiveText", "It's super effective!"),
    "It's super-\neffective!",
    "a line with no slot comes back as the cart wrote it")
  eq(romText(data, "NoSuchLabel", "the engine's own wording"),
    "the engine's own wording",
    "and a label the cache does not carry falls back")
end

-- ---- against a real imported cache ----------------------------------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local path = cache .. "/data/generated/rom_text.lua"
  local file = io.open(path, "r")
  if not file then
    print("  (skipped: no rom_text.lua at " .. path .. ")")
  else
    file:close()
    local texts = assert(loadfile(path))()
    check(next(texts) ~= nil, "the imported cache carries strings")
    -- Wording taken from pokegold's data/text/battle.asm, with \n for `line`
    -- and \v for `cont`, which is what RomExtractorGen2 decodes those to.
    eq(texts.SuperEffectiveText, "It's super-\neffective!",
      "SuperEffectiveText comes off the cart hyphenated and broken")
    eq(texts.NotVeryEffectiveText, "It's not very\neffective…",
      "NotVeryEffectiveText ends on the ellipsis glyph")
    eq(texts.StartPerishText, "Both POKéMON will\nfaint in 3 turns!",
      "StartPerishText names both sides")
    eq(texts.ButItFailedText, "But it failed!", "and a one-row line is one row")
    eq(texts.SubTookDamageText, "The SUBSTITUTE\ntook damage for\v{TARGET}!",
      "SpikesText's neighbour keeps its cont row and its target slot")
    eq(texts.PlayerHitTimesText, "Hit {NUM} times!",
      "a text_decimal reads back as {NUM}")
  end
end

S.finish()

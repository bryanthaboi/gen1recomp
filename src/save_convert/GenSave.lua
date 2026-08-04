-- Vanilla Gen1 (Red/Blue, international) raw SRAM save (32768 bytes) <->
-- this project's save.lua shape (src/core/SaveData.lua / SaveData.newGame).
--
-- Pure Lua, no love.* dependency -- runs under plain luajit for the CLI
-- (tools/save_convert/convert.lua) and headless tests alike.
--
-- Every offset below was derived mechanically from the authoritative
-- source (../pokered/ram/wram.asm, ram/sram.asm, macros/ram.asm) and
-- cross-checked against three independently well-known Gen1 save
-- addresses: money @ 0x25F3, badges @ 0x2602, party data @ 0x2F2C --
-- all three fall out exactly right from the single sPlayerName anchor
-- below, strong triangulated confirmation the whole chain (SRAM bank 1
-- layout, wMainData field order, party_struct/box_struct sizes) is right.
--
-- SRAM layout (32768 bytes = 4 banks x 8192): bank 0 is sprite buffers +
-- Hall of Fame (not modeled -- see "explicitly out of scope" in the
-- save-converter plan); bank 1 is "Save Data" (sPlayerName through
-- sMainDataCheckSum); banks 2/3 are the 12 PC boxes (6 each) + checksums.
--
-- Fields with no equivalent in save.lua (current sprite/animation state,
-- connection-header cache, Day Care, Safari Zone, HOF roster) are
-- intentionally not modeled: on export, encode() starts from the
-- ORIGINAL imported bytes as a template when available (GenSave.decode
-- stashes them) so that scratch state round-trips untouched instead of
-- being invented; with no template (a save that originated in this
-- project) those bytes stay zero-filled, which is safe because the real
-- game regenerates all of it from wCurMap on the next map load anyway.

local bit = require("bit")

local GenSave = {}

-- ------------------------------------------------------------------
-- Absolute byte offsets (0-based, matching a raw 32768-byte .sav file)
-- ------------------------------------------------------------------

local NAME_LENGTH = 11
local PARTY_LENGTH = 6
local MONS_PER_BOX = 20
local NUM_BADGES = 8
local NUM_CITY_MAPS = 11     -- PALLET_TOWN..SAFFRON_CITY, the bit width of
                              -- wTownVisitedFlag (constants/map_constants.asm)
local BOX_STRUCT_SIZE = 33   -- Species,HP,Level,Status,Type1,Type2,CatchRate,
                              -- Moves x4,OTID,Exp x3,HPExp,AtkExp,DefExp,
                              -- SpdExp,SpcExp,DVs,PP x4 (macros/ram.asm box_struct)
local PARTY_STRUCT_SIZE = 44 -- box_struct + Level + Stats x5 (party_struct)
local BOX_REGION_SIZE = 1 + (MONS_PER_BOX + 1) + MONS_PER_BOX * BOX_STRUCT_SIZE
                       + MONS_PER_BOX * NAME_LENGTH + MONS_PER_BOX * NAME_LENGTH -- 1122

local O = {}
O.playerName = 9624                                    -- sPlayerName (11B)  = 0x2598
O.mainData = O.playerName + NAME_LENGTH                 -- sMainData (wMainDataStart mirror)
O.pokedexOwned = O.mainData + 0                         -- 19B (flag_array 151)
O.pokedexSeen = O.mainData + 19                         -- 19B
O.numBagItems = O.mainData + 38                         -- 1B
O.bagItems = O.mainData + 39                             -- 41B (20 x (id,qty) + $FF term)
O.money = O.mainData + 80                                -- 3B BCD             = 0x25F3
O.rivalName = O.mainData + 83                            -- 11B
O.options = O.mainData + 94                              -- 1B
O.badges = O.mainData + 95                                -- 1B                = 0x2602
O.playerId = O.mainData + 98                              -- 2B (big-endian)
O.curMap = O.mainData + 103                               -- 1B
O.yCoord = O.mainData + 106                               -- 1B
O.xCoord = O.mainData + 107                               -- 1B
O.lastMap = O.mainData + 110                              -- 1B
O.numPcItems = O.mainData + 579                           -- 1B
O.pcItems = O.mainData + 580                              -- 101B (50 x (id,qty) + $FF term)
O.currentBoxNum = O.mainData + 681                        -- 1B (bits 0-6: box 0-11, bit 7: unused here)
O.coins = O.mainData + 685                                -- 2B BCD
-- wTownVisitedFlag (ram/wram.asm:2057): the FLY destination set, a
-- flag_array NUM_CITY_MAPS whose bit index IS the town's map index (see the
-- decode note).  Triangulated from both neighbours, which agree exactly:
-- backwards from the checksum-covered, independently derived O.eventFlags
-- below by summing every wram.asm declaration between the two labels --
-- 2 (wTownVisitedFlag) + 2 (wSafariSteps) + 1 + 1 + 2 + 1 + 1 + 1 + 1 + 1
-- + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 8 + 1 + 1 + 1 (wBeatGymFlags) + 1 + 1 + 1
-- (wStatusFlags3, aliased wCableClubDestinationMap) + 1 + 1 + 1 + 1 + 1 + 1
-- + 1 + 1 + 1 (wMovementFlags) + 2 + 2 + 1 + 1 + 2 + 1 + 1 + 2 + 1 + 1 + 2
-- = 60, so 1104 - 60 = 1044; and forwards from O.coins (mainData + 685)
-- with 2 (wPlayerCoins) + 32 (wToggleableObjectFlags, flag_array $100) + 7
-- + 1 (wSavedSpriteImageIndex) + 33 (wToggleableObjectList) + 1 + 200
-- (wGameProgressFlags..End) + 56 + 14 (wObtainedHiddenItemsFlags,
-- flag_array MAX_HIDDEN_ITEMS = 112) + 2 (wObtainedHiddenCoinsFlags) + 1
-- (wWalkBikeSurfState) + 10 = 359, so 685 + 359 = 1044 as well.
O.townVisited = O.mainData + 1044                         -- 2B (flag_array NUM_CITY_MAPS)
O.eventFlags = O.mainData + 1104                          -- 320B (flag_array NUM_EVENTS = 2560 bits)
-- Progress bits vanilla keeps OUTSIDE wEventFlags that this port still spells
-- as save.flags entries (#396).  Offsets walk forward from wTownVisitedFlag
-- over the same ram/wram.asm declaration run the 60-byte gap above sums:
-- +29 wStatusFlags1, +35 wStatusFlags4, +41 wElite4Flags,
-- +44 wCompletedInGameTradeFlags.
O.statusFlags1 = O.townVisited + 29                       -- 1B
O.statusFlags4 = O.townVisited + 35                       -- 1B
O.elite4Flags = O.townVisited + 41                        -- 1B
O.tradeFlags = O.townVisited + 44                         -- 2B (flag_array NUM_NPC_TRADES)
-- Play time (wPlayTimeHours/Maxed/Minutes/Seconds/Frames) lives INSIDE the
-- sMainData window (wMainDataStart..wMainDataEnd is copied verbatim into
-- SRAM), 1866 bytes past wMainDataStart -- reached from the checksum-verified
-- wEventFlags anchor: 320 (event flag_array) + 293 (the wGrassRate/enemy-party
-- battle UNION) + 66 + 66 (wEnemyMonOT/Nicks, 6 x NAME_LENGTH each; the
-- rgbds FOR n,1,PARTY_LENGTH+1 loop is end-exclusive => 6 mons, not 7) + 2
-- (wTrainerHeaderPtr) + 6 (ds) + 1 (wOpponentAfterWrongAnswer) + 1
-- (wCurMapScript) + 7 (ds) = 762. Confirmed on the real fixture: those five
-- bytes read 201h 30m 07s, a sane completed-save clock.
O.playTimeHours = O.mainData + 1866                       -- 1B
O.playTimeMaxed = O.mainData + 1867                       -- 1B (set once past 255h)
O.playTimeMinutes = O.mainData + 1868                     -- 1B (0-59)
O.playTimeSeconds = O.mainData + 1869                     -- 1B (0-59)
O.playTimeFrames = O.mainData + 1870                      -- 1B (0-59, 1/60s ticks)
O.mainDataSize = 1929                                     -- wMainDataEnd - wMainDataStart

O.spriteData = O.mainData + O.mainDataSize
O.spriteDataSize = 512                                    -- 2 x 16 sprites x 16B

O.partyData = O.spriteData + O.spriteDataSize             -- = 0x2F2C
O.partyCount = O.partyData
O.partySpecies = O.partyData + 1                          -- 7B (PARTY_LENGTH+1)
O.partyMons = O.partyData + 8                             -- 6 x 44B
O.partyMonOT = O.partyData + 8 + PARTY_LENGTH * PARTY_STRUCT_SIZE
O.partyMonNicks = O.partyMonOT + PARTY_LENGTH * NAME_LENGTH
O.partyDataSize = 1 + (PARTY_LENGTH + 1) + PARTY_LENGTH * PARTY_STRUCT_SIZE
                 + PARTY_LENGTH * NAME_LENGTH + PARTY_LENGTH * NAME_LENGTH -- 404

O.curBoxData = O.partyData + O.partyDataSize
O.boxCount = O.curBoxData
O.boxSpecies = O.curBoxData + 1                           -- 21B
O.boxMons = O.curBoxData + 22                             -- 20 x 33B
O.boxMonOT = O.curBoxData + 22 + MONS_PER_BOX * BOX_STRUCT_SIZE
O.boxMonNicks = O.boxMonOT + MONS_PER_BOX * NAME_LENGTH

O.checksumStart = O.playerName
O.checksumEnd = O.curBoxData + BOX_REGION_SIZE + 1        -- + sTileAnimations (1B)
O.mainChecksum = O.checksumEnd                            -- 1B

O.box1 = 16384                                             -- bank 2 start
O.boxBank2Checksum = O.box1 + 6 * BOX_REGION_SIZE
O.boxBank2IndividualChecksums = O.boxBank2Checksum + 1     -- 6B
O.box7 = 24576                                              -- bank 3 start
O.boxBank3Checksum = O.box7 + 6 * BOX_REGION_SIZE
O.boxBank3IndividualChecksums = O.boxBank3Checksum + 1      -- 6B

GenSave.OFFSETS = O
GenSave.BOX_REGION_SIZE = BOX_REGION_SIZE
GenSave.SAVE_SIZE = 32768

-- ------------------------------------------------------------------
-- Byte-level helpers.  `bytes` is a 32768-byte Lua string (1-based
-- indexing, so byte offset N is string position N+1); `buf` for writing
-- is a 32768-entry array of 1-char strings, joined at the end.
-- ------------------------------------------------------------------

local function u8(bytes, off) return bytes:byte(off + 1) end
local function u16be(bytes, off) return u8(bytes, off) * 256 + u8(bytes, off + 1) end
local function u24be(bytes, off)
  return u8(bytes, off) * 65536 + u8(bytes, off + 1) * 256 + u8(bytes, off + 2)
end

local function setByte(buf, off, v)
  buf[off + 1] = string.char(bit.band(v, 0xFF))
end
local function setU16be(buf, off, v)
  setByte(buf, off, bit.band(bit.rshift(v, 8), 0xFF))
  setByte(buf, off + 1, bit.band(v, 0xFF))
end
local function setU24be(buf, off, v)
  setByte(buf, off, bit.band(bit.rshift(v, 16), 0xFF))
  setByte(buf, off + 1, bit.band(bit.rshift(v, 8), 0xFF))
  setByte(buf, off + 2, bit.band(v, 0xFF))
end
local function setBcd(buf, off, nbytes, v)
  for i = nbytes - 1, 0, -1 do
    local d = v % 100
    v = math.floor(v / 100)
    setByte(buf, off + i, math.floor(d / 10) * 16 + (d % 10))
  end
end
local function readBcd(bytes, off, nbytes)
  local n = 0
  for i = 0, nbytes - 1 do
    local b = u8(bytes, off + i)
    n = n * 100 + math.floor(b / 16) * 10 + (b % 16)
  end
  return n
end

-- CalcCheckSum (engine/menus/save.asm): complement of the additive sum
local function checksum(bytes, from, to)
  local sum = 0
  for i = from, to - 1 do sum = bit.band(sum + u8(bytes, i), 0xFF) end
  return bit.band(bit.bnot(sum), 0xFF)
end

-- flag_array packs LSB-first within each byte (bit 0 of byte 0 = index 0).
-- This is pokered's runtime FlagAction convention (home/predef macros): it
-- takes flag number N, addresses byte N/8, and builds the mask by rotating
-- a 1 left N%8 times starting from bit 0 -- i.e. flag N%8==0 is the LSB.
-- Same convention PKHeX uses for Gen1 dex/event flags (FlagUtil.GetFlag:
-- data[ofs + bit/8] >> (bit%8) & 1). Cross-validated against the real save:
-- ZAPDOS (dex 145) is physically boxed there, so its owned/seen flag must be
-- set; only the LSB reading returns it set (MSB-first spuriously drops
-- exactly that one bit at the byte-18 boundary), yielding a complete 151/151
-- dex. The prior MSB-first code round-tripped self-consistently but decoded
-- every flag_array (pokedex AND event flags) to the wrong bit.
local function bitGet(bytes, base, index)
  local byteOff = base + math.floor(index / 8)
  local b = u8(bytes, byteOff)
  return bit.band(bit.rshift(b, index % 8), 1) == 1
end

-- Set one bit directly in `buf` (0-based flag index into a flag_array
-- starting at `base`), preserving every other bit already in that byte --
-- template bytes (see encode()'s header note) survive for bits this pass
-- never explicitly touches, e.g. event-flag bits with no known name
-- sharing a byte with ones that do.
local function bitSet(buf, base, index, value)
  local byteOff = base + math.floor(index / 8)
  local bitIdx = index % 8
  local cur = buf[byteOff + 1] and buf[byteOff + 1]:byte() or 0
  local mask = bit.lshift(1, bitIdx)
  setByte(buf, byteOff, value and bit.bor(cur, mask) or bit.band(cur, bit.bnot(mask)))
end

-- ------------------------------------------------------------------
-- Text (fixed-length name fields: charmap-encoded, "@" ($50) terminated,
-- $50-padded after the terminator). setCharmap(cm) must be called once
-- before decode/encode (src/save_convert/data/charmap.lua's shape).
-- ------------------------------------------------------------------

local charmap

function GenSave.setCharmap(cm) charmap = cm end

local function decodeName(bytes, off, len)
  local out = {}
  for i = 0, len - 1 do
    local b = u8(bytes, off + i)
    if b == 0x50 then break end
    out[#out + 1] = charmap.byByte[b] or "?"
  end
  return table.concat(out)
end

local function encodeName(buf, off, len, text, padTail)
  local i, pos = 0, 1
  while i < len - 1 and pos <= #text do
    -- a bracketed control token (e.g. "<DOT>", from decodeName reading a
    -- byte with no plain-glyph mapping) is ONE game character despite
    -- being several text bytes here; match it as a whole unit first, or
    -- it would fall through to per-byte matching and turn into "?" x5
    local bracket = text:match("^(<[^<>]*>)", pos)
    local ch, clen
    if bracket and charmap.byToken[bracket] then
      ch, clen = bracket, #bracket
    else
      local b0 = text:byte(pos)
      clen = (b0 < 0x80 and 1) or (b0 < 0xE0 and 2) or (b0 < 0xF0 and 3) or 4
      ch = text:sub(pos, pos + clen - 1)
    end
    setByte(buf, off + i, charmap.byToken[ch] or charmap.byToken["?"] or 0x50)
    i, pos = i + 1, pos + clen
  end
  -- Write exactly ONE $50 terminator.  The tail past it is $50-padded only
  -- on a templateless (engine-origin) export, where the zero-filled buffer
  -- is what PKHeX renders as garbage glyphs after the name ("JOHN{}", #206).
  -- With a template the tail keeps the original save's bytes verbatim --
  -- real cartridge saves legitimately hold 0x00 (and other stale glyph)
  -- bytes after the terminator, and rewriting any of them broke the
  -- import->export byte-identical round trip (the game and PKHeX both stop
  -- reading at the terminator, so preserved tails are always safe).
  if i < len then setByte(buf, off + i, 0x50) end
  if padTail then
    for j = i + 1, len - 1 do setByte(buf, off + j, 0x50) end
  end
end

-- ------------------------------------------------------------------
-- DV / PP packing (box_struct DVs, PP)
-- ------------------------------------------------------------------

-- DVs:: dw, packed as byte0=(Attack<<4)|Defense, byte1=(Speed<<4)|Special;
-- HP DV is derived, not stored, from each stat DV's low bit.
local function decodeDVs(bytes, off)
  local b0, b1 = u8(bytes, off), u8(bytes, off + 1)
  local atk, def = bit.rshift(b0, 4), bit.band(b0, 0xF)
  local spe, spc = bit.rshift(b1, 4), bit.band(b1, 0xF)
  local hp = bit.bor(bit.lshift(bit.band(atk, 1), 3), bit.lshift(bit.band(def, 1), 2),
                     bit.lshift(bit.band(spe, 1), 1), bit.band(spc, 1))
  return { hp = hp, attack = atk, defense = def, speed = spe, special = spc }
end

local function encodeDVs(buf, off, dvs)
  setByte(buf, off, bit.bor(bit.lshift(bit.band(dvs.attack or 0, 0xF), 4), bit.band(dvs.defense or 0, 0xF)))
  setByte(buf, off + 1, bit.bor(bit.lshift(bit.band(dvs.speed or 0, 0xF), 4), bit.band(dvs.special or 0, 0xF)))
end

-- PP byte: top 2 bits = PP Up count (0-3), bottom 6 bits = current PP
local function decodePPByte(b) return bit.band(b, 0x3F), bit.rshift(b, 6) end
local function encodePPByte(pp, ppUps) return bit.bor(bit.lshift(bit.band(ppUps or 0, 3), 6), bit.band(pp or 0, 0x3F)) end

-- ------------------------------------------------------------------
-- Crosswalks (built once from `data` = {pokemon=,moves=,items=,maps=})
-- ------------------------------------------------------------------

-- pokered constants/type_constants.asm PHYSICAL/SPECIAL block; stable,
-- not worth a dedicated extractor for 15 names.
local TYPE_BY_INDEX = {
  [0] = "NORMAL", [1] = "FIGHTING", [2] = "FLYING", [3] = "POISON",
  [4] = "GROUND", [5] = "ROCK", [6] = "BIRD", [7] = "BUG", [8] = "GHOST",
  [20] = "FIRE", [21] = "WATER", [22] = "GRASS", [23] = "ELECTRIC",
  [24] = "PSYCHIC_TYPE", [25] = "ICE", [26] = "DRAGON",
}
local TYPE_INDEX = {}
for i, name in pairs(TYPE_BY_INDEX) do TYPE_INDEX[name] = i end

-- Badge bit order (constants/ram_constants.asm BIT_BOULDERBADGE=0 ..
-- BIT_EARTHBADGE=7); this project stores badges as truthy
-- save.inventory[id] entries, not a flag or a separate bitmask
-- (src/inventory/Badges.lua Badges.list's VANILLA order matches exactly).
local BADGE_BY_BIT = {
  [0] = "BOULDERBADGE", [1] = "CASCADEBADGE", [2] = "THUNDERBADGE",
  [3] = "RAINBOWBADGE", [4] = "SOULBADGE", [5] = "MARSHBADGE",
  [6] = "VOLCANOBADGE", [7] = "EARTHBADGE",
}
local BADGE_BY_BIT_SET = {}
for _, name in pairs(BADGE_BY_BIT) do BADGE_BY_BIT_SET[name] = true end

-- save.flags names whose vanilla home is NOT wEventFlags (#396: exporting a
-- save and importing it back made the Saffron gate guards thirsty again,
-- because BIT_GAVE_SAFFRON_GUARDS_DRINK is a wStatusFlags1 bit and nothing
-- carried it).  Bit numbers are constants/ram_constants.asm; the trade bits
-- are wWhichTrade, which engine/events/in_game_trades.asm uses to index
-- wCompletedInGameTradeFlags, i.e. the data/events/trades.asm row order the
-- port's `trade` command takes 1-based.
local EXTRA_FLAG_BITS = {
  EVENT_GOT_OLD_ROD       = { O.statusFlags1, 3 },
  EVENT_GOT_GOOD_ROD      = { O.statusFlags1, 4 },
  EVENT_GOT_SUPER_ROD     = { O.statusFlags1, 5 },
  EVENT_GAVE_GUARDS_DRINK = { O.statusFlags1, 6 },
  EVENT_GOT_LAPRAS        = { O.statusFlags4, 0 },
  EVENT_STARTED_ELITE_4   = { O.elite4Flags, 1 },
  EVENT_TRADED_NIDORINO_FOR_NIDORINA   = { O.tradeFlags, 0 },
  EVENT_TRADED_ABRA_FOR_MR_MIME        = { O.tradeFlags, 1 },
  EVENT_TRADED_PONYTA_FOR_SEEL         = { O.tradeFlags, 3 },
  EVENT_TRADED_SPEAROW_FOR_FARFETCHD   = { O.tradeFlags, 4 },
  EVENT_TRADED_SLOWBRO_FOR_LICKITUNG   = { O.tradeFlags, 5 },
  EVENT_TRADED_POLIWHIRL_FOR_JYNX      = { O.tradeFlags, 6 },
  EVENT_TRADED_RAICHU_FOR_ELECTRODE    = { O.tradeFlags, 7 },
  EVENT_TRADED_VENONAT_FOR_TANGELA     = { O.tradeFlags, 8 },
  EVENT_TRADED_NIDORAN_M_FOR_NIDORAN_F = { O.tradeFlags, 9 },
}

-- port-local name -> the wEventFlags name it means (#396)
local FLAG_ALIAS = { EVENT_RECEIVED_BIKE_VOUCHER = "EVENT_GOT_BIKE_VOUCHER" }

-- STATUS_* bits (constants/battle_constants.asm): 0-2 sleep-turns-left,
-- 3 PSN, 4 BRN, 5 FRZ, 6 PAR
local STATUS_BIT = { PSN = 3, BRN = 4, FRZ = 5, PAR = 6 }
local function decodeStatus(b)
  if bit.band(b, 7) > 0 then return "SLP" end
  for name, bitIdx in pairs(STATUS_BIT) do
    if bit.band(b, bit.lshift(1, bitIdx)) ~= 0 then return name end
  end
  return nil
end
local function encodeStatus(status)
  if status == "SLP" then return 7 end
  if status and STATUS_BIT[status] then return bit.lshift(1, STATUS_BIT[status]) end
  return 0
end

local function buildIndexCrosswalk(defs)
  local byIndex, byId = {}, {}
  for id, def in pairs(defs or {}) do
    if def.index ~= nil then
      byIndex[def.index] = id
      byId[id] = def.index
    end
  end
  return byIndex, byId
end

-- Pokedex bit position: NATIONAL DEX NUMBER (1-151), NOT the internal ROM
-- species byte (`def.index`, used for party/box mon structs) -- these are
-- two completely different Gen1 numbering schemes (the whole "MissingNo"
-- phenomenon is dex-number vs internal-index mismatches). This project's
-- generated data has no dedicated dex-number field, but every pokemon.lua
-- entry's `source` documents its extraction origin as "ROM:BaseStats[N]",
-- and BaseStats is declared in dex order in the disassembly -- verified
-- directly against 5 species (BULBASAUR->[1], CHARMANDER->[4],
-- SQUIRTLE->[7], PIKACHU->[25], MEWTWO->[150], all exactly their real
-- national dex numbers) before relying on it here.
local function buildDexCrosswalk(defs)
  local byDex, dexOf = {}, {}
  for id, def in pairs(defs or {}) do
    local n = def.source and tonumber(def.source:match("BaseStats%[(%d+)%]"))
    if n then
      byDex[n] = id
      dexOf[id] = n
    end
  end
  return byDex, dexOf
end

-- TM/HM item entries carry no `index` (data/generated/items.lua extracts
-- them by move/slot, not by their place in the raw item-constant table),
-- so buildIndexCrosswalk alone would silently drop every TM/HM from the
-- bag/PC on encode. Their real item ids ARE derivable: pokered's
-- constants/item_constants.asm declares "HM_\1: the item id, starting at
-- $C4" and "TM_\1: the item id, starting at $C9" for slot 1, incrementing
-- per slot -- i.e. HM01=196+.. , TM01=201+(number-1).
local function addMachineIndices(defs, byIndex, byId)
  for id, def in pairs(defs or {}) do
    if byId[id] == nil and def.machine and def.machine.number then
      local base = def.machine.kind == "HM" and 195 or 200
      local idx = base + def.machine.number
      byIndex[idx] = id
      byId[id] = idx
    end
  end
end

function GenSave.crosswalks(data)
  local pokemonByIndex, pokemonIndex = buildIndexCrosswalk(data.pokemon)
  local movesByIndex, movesIndex = buildIndexCrosswalk(data.moves)
  local itemsByIndex, itemsIndex = buildIndexCrosswalk(data.items)
  addMachineIndices(data.items, itemsByIndex, itemsIndex)
  local mapsByIndex, mapsIndex = buildIndexCrosswalk(data.maps)
  local pokemonByDex, pokemonDex = buildDexCrosswalk(data.pokemon)
  return {
    pokemonByIndex = pokemonByIndex, pokemonIndex = pokemonIndex,
    pokemonByDex = pokemonByDex, pokemonDex = pokemonDex,
    movesByIndex = movesByIndex, movesIndex = movesIndex,
    itemsByIndex = itemsByIndex, itemsIndex = itemsIndex,
    mapsByIndex = mapsByIndex, mapsIndex = mapsIndex,
    speciesDefs = data.pokemon or {},
  }
end

-- Gen1 has no "is nicknamed" bit.  An un-nicknamed mon literally stores its
-- species' standard name in the nickname slot: engine/menus/naming_screen.asm
-- AskName's .declinedNickname copies wNameBuffer (the MonsterNames entry
-- GetMonName just loaded) straight over the mon's nickname field.  The game
-- recovers "was it nicknamed?" by comparing the two --
-- engine/pokemon/evos_moves.asm RenameEvolvedMon rewrites the name on
-- evolution only while the stored one still equals the PRE-evolution
-- species' standard name ("Renames the mon to its new, evolved form's
-- standard name unless it had a nickname, in which case the nickname is
-- kept").  This project models that state as mon.nickname == nil instead:
-- every display site reads `mon.nickname or def.name` and
-- src/pokemon/Evolution.lua deliberately never touches the field.  So the
-- two conventions must be translated at this boundary, or an imported
-- SQUIRTLE still reads "SQUIRTLE" after it becomes a WARTORTLE and an
-- engine-origin export writes the species CONSTANT ("NIDORAN_M", whose "_"
-- has no charmap glyph and encodes as "?") where the cartridge keeps the
-- display name.  Both read back as a forced nickname (#257).
--
-- def.name is byte-for-byte what the cartridge stores: tools/extract/
-- pokemon.py parse_names reads pokered's data/pokemon/names.asm, the very
-- table GetMonName loads from, and all 151 names round-trip exactly through
-- src/save_convert/data/charmap.lua, so the equality test below is exact
-- and never mis-fires on a name the charmap mangles.
local function speciesName(cw, species)
  local def = species and cw.speciesDefs[species]
  return (def and def.name) or species or ""
end

-- stored fixed-length name -> save.lua nickname (nil when never nicknamed)
local function importedNickname(cw, species, stored)
  if stored == speciesName(cw, species) then return nil end
  return stored
end

-- ------------------------------------------------------------------
-- Mon struct (box_struct is a byte-for-byte prefix of party_struct;
-- decodeMon reads the box_struct fields, then Level+Stats if isParty).
-- Type1/Type2 are read for nothing (this project derives type from
-- species) but re-derived from data.pokemon[species].types on encode.
-- ------------------------------------------------------------------

local function decodeMon(bytes, off, isParty, cw)
  local speciesIdx = u8(bytes, off)
  if speciesIdx == 0 then return nil end -- empty slot
  local species = cw.pokemonByIndex[speciesIdx]
  local hp = u16be(bytes, off + 1)
  local boxLevel = u8(bytes, off + 3)
  local status = decodeStatus(u8(bytes, off + 4))
  local catchRate = u8(bytes, off + 7)
  local moves = {}
  for i = 0, 3 do
    local moveIdx = u8(bytes, off + 8 + i)
    if moveIdx > 0 then
      local pp, ppUps = decodePPByte(u8(bytes, off + 29 + i))
      moves[#moves + 1] = { id = cw.movesByIndex[moveIdx], pp = pp, ppUps = ppUps }
    end
  end
  local otId = u16be(bytes, off + 12)
  local exp = u24be(bytes, off + 14)
  local statExp = {
    hp = u16be(bytes, off + 17), attack = u16be(bytes, off + 19),
    defense = u16be(bytes, off + 21), speed = u16be(bytes, off + 23),
    special = u16be(bytes, off + 25),
  }
  local dvs = decodeDVs(bytes, off + 27)
  local mon = {
    species = species, exp = exp, dvs = dvs, statExp = statExp,
    hp = hp, status = status, moves = moves, otId = otId,
    catchRate = catchRate, level = boxLevel,
    -- Type1/Type2 as physically stored. This project derives type from species
    -- for gameplay, but the raw bytes are captured so encode() can reproduce
    -- them verbatim: some real saves (traded/tampered mons) carry type values
    -- that do not match the ROM base stats, and re-deriving would corrupt them.
    typeBytes = { u8(bytes, off + 5), u8(bytes, off + 6) },
  }
  if isParty then
    mon.level = u8(bytes, off + 33)
    mon.stats = {
      hp = u16be(bytes, off + 34), attack = u16be(bytes, off + 36),
      defense = u16be(bytes, off + 38), speed = u16be(bytes, off + 40),
      special = u16be(bytes, off + 42),
    }
  end
  return mon
end

local function encodeMon(buf, off, mon, isParty, cw)
  if not mon then
    setByte(buf, off, 0)
    return
  end
  setByte(buf, off, cw.pokemonIndex[mon.species] or 0)
  setU16be(buf, off + 1, mon.hp or 0)
  setByte(buf, off + 3, mon.level or 1)
  setByte(buf, off + 4, encodeStatus(mon.status))
  local def = cw.speciesDefs[mon.species]
  if mon.typeBytes then
    -- reproduce the exact stored type bytes captured on decode (faithful
    -- byte round-trip); fresh, engine-built mons have none and derive below.
    setByte(buf, off + 5, mon.typeBytes[1] or 0)
    setByte(buf, off + 6, mon.typeBytes[2] or 0)
  else
    local t = (def and def.types) or {}
    setByte(buf, off + 5, TYPE_INDEX[t[1]] or 0)
    setByte(buf, off + 6, TYPE_INDEX[t[2] or t[1]] or 0)
  end
  setByte(buf, off + 7, mon.catchRate or (def and def.catchRate) or 0)
  for i = 0, 3 do
    local mv = mon.moves and mon.moves[i + 1]
    setByte(buf, off + 8 + i, mv and (cw.movesIndex[mv.id] or 0) or 0)
    setByte(buf, off + 29 + i, mv and encodePPByte(mv.pp, mv.ppUps) or 0)
  end
  setU16be(buf, off + 12, mon.otId or 0)
  setU24be(buf, off + 14, mon.exp or 0)
  local se = mon.statExp or {}
  setU16be(buf, off + 17, se.hp or 0)
  setU16be(buf, off + 19, se.attack or 0)
  setU16be(buf, off + 21, se.defense or 0)
  setU16be(buf, off + 23, se.speed or 0)
  setU16be(buf, off + 25, se.special or 0)
  encodeDVs(buf, off + 27, mon.dvs or {})
  if isParty then
    setByte(buf, off + 33, mon.level or 1)
    local st = mon.stats or {}
    setU16be(buf, off + 34, st.hp or 0)
    setU16be(buf, off + 36, st.attack or 0)
    setU16be(buf, off + 38, st.defense or 0)
    setU16be(buf, off + 40, st.speed or 0)
    setU16be(buf, off + 42, st.special or 0)
  end
end

-- ------------------------------------------------------------------
-- Bag / PC items: (id, qty) byte pairs, $FF-terminated
-- ------------------------------------------------------------------

local function decodeItemList(bytes, off, capacity, cw)
  local inventory, order = {}, {}
  for i = 0, capacity - 1 do
    local idByte = u8(bytes, off + i * 2)
    if idByte == 0xFF then break end
    local qty = u8(bytes, off + i * 2 + 1)
    local id = cw.itemsByIndex[idByte]
    if id then
      inventory[id] = qty
      order[#order + 1] = id
    end
  end
  return inventory, order
end

local function encodeItemList(buf, off, capacity, inventory, order, cw)
  local i = 0
  local seen = {}
  local function put(id, qty)
    if i >= capacity or not qty or qty <= 0 then return end
    local idByte = cw.itemsIndex[id]
    if not idByte then return end
    setByte(buf, off + i * 2, idByte)
    setByte(buf, off + i * 2 + 1, math.min(qty, 99))
    i = i + 1
    seen[id] = true
  end
  for _, id in ipairs(order or {}) do
    if inventory[id] and not seen[id] then put(id, inventory[id]) end
  end
  for id, qty in pairs(inventory or {}) do
    if not seen[id] then put(id, qty) end
  end
  setByte(buf, off + i * 2, 0xFF)
  return i -- count actually written (badges etc. in `inventory` that
           -- aren't real items are silently skipped by put(), so this
           -- can be less than #inventory -- see the wNumBagItems caller)
end

-- ------------------------------------------------------------------
-- decode: raw 32768-byte SRAM string -> save.lua-shaped table
-- ------------------------------------------------------------------

function GenSave.decode(bytes, data, opts)
  assert(#bytes == GenSave.SAVE_SIZE, "expected a 32768-byte save")
  local cw = GenSave.crosswalks(data)
  local warnings = {}
  local function warn(msg) warnings[#warnings + 1] = msg end

  if checksum(bytes, O.checksumStart, O.checksumEnd) ~= u8(bytes, O.mainChecksum) then
    warn("main data checksum mismatch (importing anyway)")
  end

  local save = {
    meta = { format = "gen1_import" },
    player = {
      name = decodeName(bytes, O.playerName, NAME_LENGTH),
      rival = decodeName(bytes, O.rivalName, NAME_LENGTH),
      id = u16be(bytes, O.playerId),
    },
    money = readBcd(bytes, O.money, 3),
    coins = readBcd(bytes, O.coins, 2),
    inventory = {},
    pcItems = {},
    pokedex = { seen = {}, owned = {} },
    flags = {},
    party = {},
    boxes = {},
    currentBox = 1,
  }

  -- pokedex (own/seen, flag_array NUM_POKEMON: bit 0 = dex #1)
  for dex, species in pairs(cw.pokemonByDex) do
    local bitIdx = dex - 1
    if bitGet(bytes, O.pokedexOwned, bitIdx) then save.pokedex.owned[species] = true end
    if bitGet(bytes, O.pokedexSeen, bitIdx) then save.pokedex.seen[species] = true end
  end

  save.inventory, save.bagOrder = decodeItemList(bytes, O.bagItems, 20, cw)
  save.pcItems, save.pcOrder = decodeItemList(bytes, O.pcItems, 50, cw)

  -- badges: truthy save.inventory[id] entries (src/inventory/Badges.lua),
  -- set AFTER decodeItemList since that call replaces save.inventory
  local badgesByte = u8(bytes, O.badges)
  for i = 0, NUM_BADGES - 1 do
    if bit.band(badgesByte, bit.lshift(1, i)) ~= 0 then
      save.inventory[BADGE_BY_BIT[i]] = 1
    end
  end

  -- party
  local partyCount = u8(bytes, O.partyCount)
  for i = 0, math.min(partyCount, PARTY_LENGTH) - 1 do
    local mon = decodeMon(bytes, O.partyMons + i * PARTY_STRUCT_SIZE, true, cw)
    if mon then
      mon.ot = decodeName(bytes, O.partyMonOT + i * NAME_LENGTH, NAME_LENGTH)
      -- a stored name equal to the species' standard name means NOT
      -- nicknamed, which this project spells as nil (#257)
      mon.nickname = importedNickname(cw, mon.species,
        decodeName(bytes, O.partyMonNicks + i * NAME_LENGTH, NAME_LENGTH))
      save.party[#save.party + 1] = mon
    end
  end

  -- current box (bank 1) + the 11 stored boxes (banks 2/3)
  for i = 1, 12 do save.boxes[i] = {} end
  local function decodeBoxRegion(base, boxNum)
    local count = u8(bytes, base)
    for i = 0, math.min(count, MONS_PER_BOX) - 1 do
      local mon = decodeMon(bytes, base + 22 + i * BOX_STRUCT_SIZE, false, cw)
      if mon then
        mon.ot = decodeName(bytes, base + 22 + MONS_PER_BOX * BOX_STRUCT_SIZE + i * NAME_LENGTH, NAME_LENGTH)
        mon.nickname = importedNickname(cw, mon.species,
          decodeName(bytes, base + 22 + MONS_PER_BOX * (BOX_STRUCT_SIZE + NAME_LENGTH) + i * NAME_LENGTH, NAME_LENGTH))
        table.insert(save.boxes[boxNum], mon)
      end
    end
  end
  local curBoxNum = bit.band(u8(bytes, O.currentBoxNum), 0x7F) -- 0-based box index
  curBoxNum = math.max(1, math.min(12, curBoxNum + 1))
  decodeBoxRegion(O.curBoxData, curBoxNum)
  for b = 1, 6 do
    if b + 0 ~= curBoxNum then decodeBoxRegion(O.box1 + (b - 1) * BOX_REGION_SIZE, b) end
  end
  for b = 7, 12 do
    if b ~= curBoxNum then decodeBoxRegion(O.box7 + (b - 7) * BOX_REGION_SIZE, b) end
  end
  save.currentBox = curBoxNum

  -- event flags (only bits with a known name are decoded)
  local events = data.eventFlags
  if events then
    for bitIdx, name in pairs(events.byBit) do
      if bitGet(bytes, O.eventFlags, bitIdx) then save.flags[name] = true end
    end
  end

  -- the same progress under names that are not wEventFlags bits (#396)
  for name, spec in pairs(EXTRA_FLAG_BITS) do
    if bitGet(bytes, spec[1], spec[2]) then save.flags[name] = true end
  end
  for portName, vanillaName in pairs(FLAG_ALIAS) do
    if save.flags[vanillaName] then save.flags[portName] = true end
  end

  -- FLY destinations.  wTownVisitedFlag's bit index IS the town's map index:
  -- engine/items/town_map.asm BuildFlyLocationsList loads the 16-bit value
  -- into de and rotates it right one bit per iteration with b counting up
  -- from 0, storing b ("the map number of the town if it has been visited"),
  -- so bit 0 = map 0 = PALLET_TOWN, LSB first; and
  -- engine/overworld/toggleable_objects.asm
  -- MarkTownVisitedAndLoadToggleableObjects sets bit [wCurMap] on entry for
  -- any map below FIRST_ROUTE_MAP.  Map indices 0-10 in
  -- data/generated/maps.lua match PALLET_TOWN..SAFFRON_CITY one for one.
  -- This project keeps the same set as save.visited[mapId]
  -- (src/ui/FlyMenu.lua, src/ui/TownMap.lua, and the only writer,
  -- src/world/OverworldController.lua's mark-on-map-entry), which an import
  -- used to leave nil: FLY then listed only the town the player happened to
  -- be standing in when the save was loaded (#263).
  save.visited = {}
  for townIdx = 0, NUM_CITY_MAPS - 1 do
    if bitGet(bytes, O.townVisited, townIdx) then
      local townId = cw.mapsByIndex[townIdx]
      if townId then save.visited[townId] = true end
    end
  end

  -- map + position
  local mapIdx = u8(bytes, O.curMap)
  local mapId = cw.mapsByIndex[mapIdx]
  local y, x = u8(bytes, O.yCoord), u8(bytes, O.xCoord)
  if mapId then
    save.player.map, save.player.x, save.player.y = mapId, x, y
  else
    warn(("unknown map index %d, defaulting spawn"):format(mapIdx))
  end
  local lastMapIdx = u8(bytes, O.lastMap)
  local lastMapId = cw.mapsByIndex[lastMapIdx]
  if lastMapId then save.lastOutdoor = { id = lastMapId } end

  -- play time: this project stores save.playTime as a single float of
  -- SECONDS (src/core/Game.lua accumulates dt each frame; StartMenu /
  -- TrainerCard / TitleState render it H:MM via t/3600 and (t/60)%60).
  -- Fold the Gen1 H/M/S/F fields into that one number; frames are 1/60s
  -- sub-second ticks, kept as a fraction so an export recovers them exactly.
  save.playTime = u8(bytes, O.playTimeHours) * 3600
                + u8(bytes, O.playTimeMinutes) * 60
                + u8(bytes, O.playTimeSeconds)
                + u8(bytes, O.playTimeFrames) / 60

  save.warnings = warnings
  save.rawImport = bytes -- template for a later encode(); see file header
  return save
end

-- ------------------------------------------------------------------
-- encode: save.lua-shaped table -> raw 32768-byte SRAM string
-- ------------------------------------------------------------------

function GenSave.encode(save, data, template)
  local cw = GenSave.crosswalks(data)
  local src = template or save.rawImport
  local buf = {}
  if src then
    for i = 1, GenSave.SAVE_SIZE do buf[i] = src:sub(i, i) end
  else
    local zero = string.char(0)
    for i = 1, GenSave.SAVE_SIZE do buf[i] = zero end
  end

  local padTail = not src
  encodeName(buf, O.playerName, NAME_LENGTH, (save.player and save.player.name) or "RED", padTail)
  encodeName(buf, O.rivalName, NAME_LENGTH, (save.player and save.player.rival) or "BLUE", padTail)
  setU16be(buf, O.playerId, (save.player and save.player.id) or 0)
  -- wOptions (engine/menus/main_menu.asm InitOptions): bit 7 = battle
  -- effects OFF, bit 6 = SET style, bits 2-0 = text speed -- the recomp's
  -- textSpeed 1/3/5 are pokered's exact FAST/MEDIUM/SLOW values
  -- (SaveData.defaultOptions).  Templateless exports only: with a
  -- template the byte survives untouched (the round-trip invariant), and
  -- decode() never reads it back anyway.
  if not src then
    local opts = save.options or {}
    local ob = (tonumber(opts.textSpeed) or 3) % 8
    if opts.battleStyle == "set" then ob = bit.bor(ob, 0x40) end
    if opts.animations == false then ob = bit.bor(ob, 0x80) end
    setByte(buf, O.options, ob)
  end
  setBcd(buf, O.money, 3, math.min(save.money or 0, 999999))
  setBcd(buf, O.coins, 2, math.min(save.coins or 0, 9999))

  local badgesByte = 0
  for bitIdx, name in pairs(BADGE_BY_BIT) do
    if save.inventory and save.inventory[name] then
      badgesByte = bit.bor(badgesByte, bit.lshift(1, bitIdx))
    end
  end
  setByte(buf, O.badges, badgesByte)

  for dex, species in pairs(cw.pokemonByDex) do
    local bitIdx = dex - 1
    bitSet(buf, O.pokedexOwned, bitIdx,
          (save.pokedex and save.pokedex.owned and save.pokedex.owned[species]) and true or false)
    bitSet(buf, O.pokedexSeen, bitIdx,
          (save.pokedex and save.pokedex.seen and save.pokedex.seen[species]) and true or false)
  end

  -- Badges occupy real item IDs in data/generated/items.lua (Gen1's item
  -- ID space includes them, $01-$08, for the "got the BOULDERBADGE!"
  -- text display), but this project's save.lua stores them as truthy
  -- save.inventory[id] entries alongside actual bag items (see the badge
  -- block above and src/inventory/Badges.lua) -- a real save NEVER
  -- writes them into wBagItems (they only ever live in wObtainedBadges,
  -- already encoded above), so they must be filtered out here or they'd
  -- corrupt the bag with bogus "badge items".
  local bagInventory = {}
  for id, qty in pairs(save.inventory or {}) do
    if not BADGE_BY_BIT_SET[id] then bagInventory[id] = qty end
  end
  local bagN = encodeItemList(buf, O.bagItems, 20, bagInventory, save.bagOrder, cw)
  setByte(buf, O.numBagItems, bagN)
  local pcN = encodeItemList(buf, O.pcItems, 50, save.pcItems or {}, save.pcOrder, cw)
  setByte(buf, O.numPcItems, pcN)

  local events = data.eventFlags
  if events and save.flags then
    for name in pairs(save.flags) do
      local bitIdx = events.byName[name]
      if bitIdx then bitSet(buf, O.eventFlags, bitIdx, true) end
    end
    for portName, vanillaName in pairs(FLAG_ALIAS) do
      local bitIdx = events.byName[vanillaName]
      if bitIdx and save.flags[portName] then bitSet(buf, O.eventFlags, bitIdx, true) end
    end
  end

  -- Non-wEventFlags progress, written both ways: this port's save is the only
  -- authority for these names, so a flag it does not hold must clear the
  -- template's bit rather than survive in the export (#396).
  if save.flags then
    for name, spec in pairs(EXTRA_FLAG_BITS) do
      bitSet(buf, spec[1], spec[2], save.flags[name] and true or false)
    end
  end

  -- FLY destinations back into wTownVisitedFlag (see the decode note), so a
  -- save exported from this port is flyable on hardware (#263).  A save
  -- table with no `visited` key at all says nothing about the set, so leave
  -- the template's bits exactly as they are rather than blanking every town.
  if type(save.visited) == "table" then
    for townIdx = 0, NUM_CITY_MAPS - 1 do
      local townId = cw.mapsByIndex[townIdx]
      bitSet(buf, O.townVisited, townIdx,
             (townId and save.visited[townId]) and true or false)
    end
  end

  -- party
  local party = save.party or {}
  local partyN = math.min(#party, PARTY_LENGTH)
  setByte(buf, O.partyCount, partyN)
  for i = 0, partyN - 1 do
    local mon = party[i + 1]
    encodeMon(buf, O.partyMons + i * PARTY_STRUCT_SIZE, mon, true, cw)
    setByte(buf, O.partySpecies + i, cw.pokemonIndex[mon.species] or 0)
    encodeName(buf, O.partyMonOT + i * NAME_LENGTH, NAME_LENGTH,
              mon.ot or (save.player and save.player.name) or "RED", padTail)
    -- no nickname stores the species' DISPLAY name, not its ROM constant id
    -- ("NIDORAN_M" would charmap the "_" to "?") (#257)
    encodeName(buf, O.partyMonNicks + i * NAME_LENGTH, NAME_LENGTH,
              mon.nickname or speciesName(cw, mon.species), padTail)
  end
  -- $FF-terminate the species index list right after the last real mon. The
  -- struct, OT-name and nickname bytes of the empty slots past partyN are left
  -- exactly as the template holds them (original stale data -> byte-identical
  -- round-trip) or zero on a fresh export -- the game never reads past the
  -- count, so this matches how it leaves those bytes itself.
  setByte(buf, O.partySpecies + partyN, 0xFF)

  -- boxes: current box mirrors save.currentBox into sCurBoxData; all 12
  -- also get written into their bank-2/3 slot (sCurBoxData is a working
  -- copy the real game keeps in sync on every PC visit, so keeping both
  -- copies consistent here matches that invariant)
  local function encodeBoxRegion(base, mons)
    local n = math.min(#mons, MONS_PER_BOX)
    setByte(buf, base, n)
    for i = 0, n - 1 do
      local mon = mons[i + 1]
      encodeMon(buf, base + 22 + i * BOX_STRUCT_SIZE, mon, false, cw)
      setByte(buf, base + 1 + i, cw.pokemonIndex[mon.species] or 0)
      encodeName(buf, base + 22 + MONS_PER_BOX * BOX_STRUCT_SIZE + i * NAME_LENGTH, NAME_LENGTH,
                mon.ot or (save.player and save.player.name) or "RED", padTail)
      encodeName(buf, base + 22 + MONS_PER_BOX * (BOX_STRUCT_SIZE + NAME_LENGTH) + i * NAME_LENGTH, NAME_LENGTH,
                mon.nickname or speciesName(cw, mon.species), padTail)  -- #257, as above
    end
    -- $FF-terminate the species list after the last real mon; empty slots past
    -- n keep their template bytes (byte-identical round-trip) or zero (fresh
    -- export), just as the game leaves stale box data untouched past the count.
    setByte(buf, base + 1 + n, 0xFF)
  end
  local boxes = save.boxes or {}
  local curBoxNum = math.max(1, math.min(12, save.currentBox or 1))
  encodeBoxRegion(O.curBoxData, boxes[curBoxNum] or {})
  -- bit 7 of wCurBoxNum is the "box system initialized" flag, not part of the
  -- 0-11 index; preserve it from the template, or set it on a templateless
  -- export (any save we emit has an initialized box system).
  local prevBoxByte = buf[O.currentBoxNum + 1]
  local boxHiBit = (src and prevBoxByte) and bit.band(prevBoxByte:byte(), 0x80) or 0x80
  setByte(buf, O.currentBoxNum, bit.bor(bit.band(curBoxNum - 1, 0x7F), boxHiBit))
  for b = 1, 6 do encodeBoxRegion(O.box1 + (b - 1) * BOX_REGION_SIZE, boxes[b] or {}) end
  for b = 7, 12 do encodeBoxRegion(O.box7 + (b - 7) * BOX_REGION_SIZE, boxes[b] or {}) end

  -- map + position
  if save.player and save.player.map then
    setByte(buf, O.curMap, cw.mapsIndex[save.player.map] or 0)
    setByte(buf, O.yCoord, save.player.y or 0)
    setByte(buf, O.xCoord, save.player.x or 0)
  end
  if save.lastOutdoor and save.lastOutdoor.id then
    setByte(buf, O.lastMap, cw.mapsIndex[save.lastOutdoor.id] or 0)
  end

  -- play time: split save.playTime (seconds) back into H/M/S/F. The real
  -- game freezes the clock at 255h and sets wPlayTimeMaxed once past it, so
  -- mirror that cap rather than letting hours overflow a single byte.
  local totalFrames = math.floor((save.playTime or 0) * 60 + 0.5)
  local hours = math.floor(totalFrames / 216000) -- 3600s * 60 frames
  if hours > 255 then
    setByte(buf, O.playTimeHours, 255)
    setByte(buf, O.playTimeMaxed, 1)
    setByte(buf, O.playTimeMinutes, 59)
    setByte(buf, O.playTimeSeconds, 59)
    setByte(buf, O.playTimeFrames, 59)
  else
    local rem = totalFrames - hours * 216000
    local mins = math.floor(rem / 3600); rem = rem - mins * 3600
    local secs = math.floor(rem / 60)
    setByte(buf, O.playTimeHours, hours)
    setByte(buf, O.playTimeMaxed, 0)
    setByte(buf, O.playTimeMinutes, mins)
    setByte(buf, O.playTimeSeconds, secs)
    setByte(buf, O.playTimeFrames, rem - secs * 60)
  end

  local out = table.concat(buf)
  -- checksums, computed last over the now-final bytes
  local outBuf = {}
  for i = 1, #out do outBuf[i] = out:sub(i, i) end
  setByte(outBuf, O.mainChecksum, checksum(out, O.checksumStart, O.checksumEnd))
  -- Per pokered (engine/menus/save.asm SaveSAVtoSRAM / CalcCheckSum): each box
  -- gets its own checksum, and the bank aggregate is CalcCheckSum over the
  -- ENTIRE six-box region (6 x 1122 bytes), not a sum of the six box sums.
  local function boxChecksum(base) return checksum(out, base, base + BOX_REGION_SIZE) end
  for b = 0, 5 do
    setByte(outBuf, O.boxBank2IndividualChecksums + b,
            boxChecksum(O.box1 + b * BOX_REGION_SIZE))
  end
  setByte(outBuf, O.boxBank2Checksum,
          checksum(out, O.box1, O.box1 + 6 * BOX_REGION_SIZE))
  for b = 0, 5 do
    setByte(outBuf, O.boxBank3IndividualChecksums + b,
            boxChecksum(O.box7 + b * BOX_REGION_SIZE))
  end
  setByte(outBuf, O.boxBank3Checksum,
          checksum(out, O.box7, O.box7 + 6 * BOX_REGION_SIZE))

  return table.concat(outBuf)
end

return GenSave

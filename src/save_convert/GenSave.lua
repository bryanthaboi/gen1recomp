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
-- Hall of Fame; bank 1 is "Save Data" (sPlayerName through
-- sMainDataCheckSum); banks 2/3 are the 12 PC boxes (6 each) + checksums.
--
-- Fields with no equivalent in save.lua (current sprite/animation state,
-- connection-header cache, Day Care, Safari Zone) are
-- intentionally not modeled: on export, encode() starts from the
-- ORIGINAL imported bytes as a template when available (GenSave.decode
-- stashes them) so that scratch state round-trips untouched instead of
-- being invented; with no template (a save that originated in this
-- project) src/save_convert/MapContext.lua rebuilds it (home/overworld.asm:2016).

local bit = require("bit")
local MapContext = require("src.save_convert.MapContext")

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
O.currentBoxNum = O.mainData + 681                        -- 1B (bits 0-6: box 0-11, bit 7: BIT_HAS_CHANGED_BOXES)
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
-- +10 wRivalStarter / +12 wPlayerStarter from the same run (ram/wram.asm:2057-2078;
-- engine/debug/debug_party.asm:119 ASSERTs the spacing) (#1625)
O.rivalStarter = O.townVisited + 10
O.playerStarter = O.townVisited + 12
-- wToggleableObjectFlags (ram/wram.asm, flag_array $100): the ShowObject/
-- HideObject persistence, one bit per data/maps/toggleable_objects.asm entry,
-- set = hidden (engine/overworld/toggleable_objects.asm IsObjectHidden).
-- Sits 2 bytes (wPlayerCoins) past O.coins per the walk above; absolute
-- 0x2852 (#763, #857).
O.toggleObjectFlags = O.coins + 2                         -- 32B
O.hiddenItemFlags = O.townVisited - 27
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
-- wPikachuHappiness, Yellow only (pret/pokeyellow ram/wram.asm; no local
-- pokeyellow checkout, so verified against the pokeyellow symbol file
-- instead: d46f - wMainDataStart d2f6 = 377, the well-known absolute
-- 0x271C).  In Red/Blue this byte is current-map scratch the game
-- regenerates on load, so the codec touches it only when the crosswalk
-- data set names the game "yellow" (#763, #838).  Every other modeled
-- offset is identical between pokered and pokeyellow (same sram.asm, same
-- wMainData field spacing per both symbol files).
O.pikachuHappiness = O.mainData + 377
O.pikachuMood = O.mainData + 378                          -- engine/menus/save.asm:260
O.pikachuEmotionModifier = O.mainData + 421               -- ram/wram.asm:2090
O.numHoFTeams = O.mainData + 683                          -- ram/wram.asm:1904
O.walkBikeSurf = O.townVisited - 11                       -- ram/wram.asm:2053
O.lastBlackoutMap = O.townVisited + 14                    -- ram/wram.asm:2083
O.mapPalOffset = 0x2609                                   -- ram/wram.asm:1780
O.safariGateScript = 0x28CB                               -- ram/wram.asm:1968
O.hiddenCoinFlags = 0x29AA                                -- ram/wram.asm:2048
O.safariSteps = 0x29B9                                    -- ram/wram.asm:2060
O.fossilItem = 0x29BB                                     -- ram/wram.asm:2063
O.fossilMon = 0x29BC
O.beatGymFlags = 0x29D6                                   -- ram/wram.asm:2107
O.statusFlags6 = 0x29DE                                   -- ram/wram.asm:2116
O.trashFirst = 0x29EF                                     -- ram/wram.asm:2136
O.trashSecond = 0x29F0
O.safariBalls = 0x2CF3                                    -- ram/wram.asm:2208
O.dayCare = 0x2CF4                                        -- ram/wram.asm:2212
O.surfHiScore = 0x2741                                    -- pokeyellow ram/wram.asm:2084
local function isDarkMap(data, mapId)
  local dark = type(data.field) == "table" and data.field.darkMaps
  for _, id in ipairs(type(dark) == "table" and dark.maps or {}) do
    if id == mapId then return true end
  end
  return false
end
local DAYCARE_SIZE = 1 + 2 * NAME_LENGTH + BOX_STRUCT_SIZE
local DAYCARE_OT = 1 + NAME_LENGTH
local DAYCARE_MON = 1 + 2 * NAME_LENGTH
local FOSSIL_ITEM_FOR_MON = { KABUTO = "DOME_FOSSIL", OMANYTE = "HELIX_FOSSIL", AERODACTYL = "OLD_AMBER" }
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

O.identityTag = 8192                                       -- ram/sram.asm:14
O.padByte = 0x2009
O.padByteTagged = 0x2024
O.hallOfFame = 0x0598                                      -- ram/sram.asm:9
local HOF_MON = 16                                         -- constants/pokemon_data_constants.asm:63
local HOF_TEAM = PARTY_LENGTH * HOF_MON
local HOF_TEAM_CAPACITY = 50
local TRAINER_NAME_MAX = 7
GenSave.IDENTITY_MAGIC = "G1RC"
GenSave.IDENTITY_ID_LENGTH = 32

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

-- Main-data checksum gate used before an import policy is decided.  Returns
-- nil when the buffer is too short to even carry the stored checksum byte
-- (offset O.mainChecksum, the last byte of wMainData), false on a mismatch,
-- true when it matches.  Works on any length >= O.mainChecksum + 1, so a
-- caller can classify a truncated or footer-padded file without a full
-- decode -- the checksummed region (0x2598..0x3522) always sits entirely
-- inside the first 0x3524 bytes of a save.
function GenSave.mainChecksumValid(bytes)
  if #bytes < O.mainChecksum + 1 then return nil end
  return checksum(bytes, O.checksumStart, O.checksumEnd) == u8(bytes, O.mainChecksum)
end

GenSave.MSG_REBUILT = "the cartridge image kept with this save was damaged, so the "
  .. "cartridge save was rebuilt from this playthrough and anything the port does "
  .. "not track starts over as in a new game"

-- engine/menus/save.asm:32
function GenSave.templateIntact(bytes)
  return type(bytes) == "string" and #bytes == GenSave.SAVE_SIZE
    and GenSave.mainChecksumValid(bytes) == true
end

function GenSave.looksLikeJapaneseSave(bytes)
  if type(bytes) ~= "string" or #bytes < 0x3595 then return false end
  if checksum(bytes, O.checksumStart, 0x3594) ~= u8(bytes, 0x3594) then return false end
  local party, box = u8(bytes, 0x2ED5), u8(bytes, 0x302D)
  return party <= PARTY_LENGTH and u8(bytes, 0x2ED6 + party) == 0xFF
    and box <= 30 and u8(bytes, 0x302E + box) == 0xFF
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
    out[#out + 1] = charmap.byByte[b] or ("<$%02X>"):format(b)
  end
  return table.concat(out)
end

local function encodeName(buf, off, len, text, padTail, maxChars)
  local i, pos = 0, 1
  local limit = math.min(len - 1, maxChars or len - 1)
  text = tostring(text or "")
  while i < limit and pos <= #text do
    -- a bracketed control token (e.g. "<DOT>", from decodeName reading a
    -- byte with no plain-glyph mapping) is ONE game character despite
    -- being several text bytes here; match it as a whole unit first, or
    -- it would fall through to per-byte matching and turn into "?" x5
    local bracket = text:match("^(<[^<>]*>)", pos)
    local rawByte = bracket and bracket:match("^<%$(%x%x)>$")
    local ch, clen, code
    if rawByte then
      ch, clen, code = bracket, #bracket, tonumber(rawByte, 16)
    elseif bracket and charmap.byToken[bracket] then
      ch, clen = bracket, #bracket
    elseif text:byte(pos) == 0x27 and charmap.byToken[text:sub(pos, pos + 1)] then
      ch, clen = text:sub(pos, pos + 1), 2
    else
      local b0 = text:byte(pos)
      clen = (b0 < 0x80 and 1) or (b0 < 0xE0 and 2) or (b0 < 0xF0 and 3) or 4
      ch = text:sub(pos, pos + clen - 1)
    end
    setByte(buf, off + i, code or charmap.byToken[ch] or charmap.byToken["?"] or 0x50)
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
}

local function tradeFlagsOf(data)
  if type(data.tradeFlags) == "table" then return data.tradeFlags end
  return require("src.save_convert.data.trade_flags")
end

-- port-local name -> the wEventFlags name it means (#396)
local FLAG_ALIAS = {
  EVENT_RECEIVED_BIKE_VOUCHER = "EVENT_GOT_BIKE_VOUCHER",
  EVENT_GOT_HM_FLASH = "EVENT_GOT_HM05",
}

-- scripts/OaksLab.asm:797-825
local PLAYER_TO_RIVAL = {
  CHARMANDER = "SQUIRTLE", SQUIRTLE = "BULBASAUR", BULBASAUR = "CHARMANDER",
}
local RIVAL_TO_PLAYER = {}
for player, rival in pairs(PLAYER_TO_RIVAL) do RIVAL_TO_PLAYER[rival] = player end
-- pokeyellow scripts/OaksLab.asm:1020 (wPlayerStarter) and :231/:381
local YELLOW_STARTER = "PIKACHU"

-- STATUS_* bits (constants/battle_constants.asm): 0-2 sleep-turns-left,
-- 3 PSN, 4 BRN, 5 FRZ, 6 PAR
local STATUS_BIT = { PSN = 3, BRN = 4, FRZ = 5, PAR = 6 }
local STATUS_ORDER = { "PSN", "BRN", "FRZ", "PAR" }
local function decodeStatus(b)
  if bit.band(b, 7) > 0 then return "SLP" end
  for _, name in ipairs(STATUS_ORDER) do
    if bit.band(b, bit.lshift(1, STATUS_BIT[name])) ~= 0 then return name end
  end
  return nil
end
local function encodeStatus(status, sleepTurns)
  if status == "SLP" then
    local n = math.floor(tonumber(sleepTurns) or 1)
    return math.max(1, math.min(7, n))
  end
  if status and STATUS_BIT[status] then return bit.lshift(1, STATUS_BIT[status]) end
  return 0
end

-- Def rows share a generated table's top level with provenance scalars on
-- some data sets (src/import/RomExtractorGen2.lua stamps `generation` and
-- `source` beside the entries), so every pairs(defs) walk here must keep
-- to table rows: indexing a scalar row raises instead of skipping it.
local function buildIndexCrosswalk(defs)
  local byIndex, byId = {}, {}
  for id, def in pairs(defs or {}) do
    if type(def) == "table" and def.index ~= nil then
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
    local n = type(def) == "table" and def.source
      and tonumber(def.source:match("BaseStats%[(%d+)%]"))
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
    if type(def) == "table" and byId[id] == nil
       and def.machine and def.machine.number then
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

local function hexOf(bytes, off, len)
  return (bytes:sub(off + 1, off + len):gsub(".", function(c)
    return ("%02X"):format(c:byte())
  end))
end

local function unhex(s)
  if type(s) ~= "string" or #s % 2 ~= 0 or s:find("[^%x]") then return nil end
  return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

local function putRaw(buf, off, raw, len)
  for i = 1, math.min(#raw, len) do buf[off + i] = raw:sub(i, i) end
end

local function decodeMon(bytes, off, isParty, cw, listByte)
  local speciesIdx = u8(bytes, off)
  local species = cw.pokemonByIndex[speciesIdx]
  local carrier = species == nil or (listByte ~= nil and listByte ~= speciesIdx)
  local moves, slots, gap, emptyPP = {}, {}, false, nil
  for i = 0, 3 do
    local moveIdx = u8(bytes, off + 8 + i)
    if moveIdx == 0 and u8(bytes, off + 29 + i) ~= 0 then
      emptyPP = emptyPP or {}
      emptyPP[i + 1] = u8(bytes, off + 29 + i)
    end
    if moveIdx > 0 then
      local id = cw.movesByIndex[moveIdx]
      if not id then carrier = true end
      local pp, ppUps = decodePPByte(u8(bytes, off + 29 + i))
      moves[#moves + 1] = { id = id, pp = pp, ppUps = ppUps }
      slots[#slots + 1] = i + 1
      if i + 1 ~= #slots then gap = true end
    end
  end
  if carrier then
    return {
      cartRaw = hexOf(bytes, off, isParty and PARTY_STRUCT_SIZE or BOX_STRUCT_SIZE),
      cartListSpecies = listByte,
    }
  end
  local hp = u16be(bytes, off + 1)
  local boxLevel = u8(bytes, off + 3)
  local statusByte = u8(bytes, off + 4)
  local status = decodeStatus(statusByte)
  local catchRate = u8(bytes, off + 7)
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
  if status == "SLP" then mon.sleepTurns = bit.band(statusByte, 7) end
  if encodeStatus(status, mon.sleepTurns) ~= statusByte then mon.cartStatus = statusByte end
  if gap then mon.cartMoveSlots = slots end
  if emptyPP then mon.cartEmptyPP = emptyPP end
  if isParty then
    mon.level = u8(bytes, off + 33)
    if boxLevel ~= mon.level then mon.boxLevel = boxLevel end
    mon.stats = {
      hp = u16be(bytes, off + 34), attack = u16be(bytes, off + 36),
      defense = u16be(bytes, off + 38), speed = u16be(bytes, off + 40),
      special = u16be(bytes, off + 42),
    }
  end
  return mon
end

local function speciesIndexOf(cw, mon)
  local idx = cw.pokemonIndex[mon.species]
  if not idx or idx == 0 then
    error(("this save cannot be exported: %s has no Gen 1 species index"):format(tostring(mon.species)), 0)
  end
  return idx
end

local function validMoveSlots(slots, n)
  if type(slots) ~= "table" or #slots ~= n then return false end
  local last = 0
  for _, s in ipairs(slots) do
    if type(s) ~= "number" or s <= last or s > 4 then return false end
    last = s
  end
  return true
end

local function encodeMon(buf, off, mon, isParty, cw, save)
  setByte(buf, off, speciesIndexOf(cw, mon))
  setU16be(buf, off + 1, mon.hp or 0)
  setByte(buf, off + 3, (isParty and mon.boxLevel) or mon.level or 1)
  local status = encodeStatus(mon.status, mon.sleepTurns)
  local cartStatus = tonumber(mon.cartStatus)
  if cartStatus and decodeStatus(cartStatus) == mon.status
      and (mon.status ~= "SLP" or bit.band(cartStatus, 7) == status) then
    status = cartStatus
  end
  setByte(buf, off + 4, status)
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
  local moves = mon.moves or {}
  local n = math.min(#moves, 4)
  local useSlots = validMoveSlots(mon.cartMoveSlots, n)
  local placed = {}
  for k = 1, n do placed[useSlots and mon.cartMoveSlots[k] or k] = moves[k] end
  for i = 0, 3 do
    local mv = placed[i + 1]
    setByte(buf, off + 8 + i, mv and (cw.movesIndex[mv.id] or 0) or 0)
    local pad = type(mon.cartEmptyPP) == "table" and tonumber(mon.cartEmptyPP[i + 1]) or 0
    setByte(buf, off + 29 + i, mv and encodePPByte(mv.pp, mv.ppUps) or pad)
  end
  local otId = mon.otId
  if otId == nil and not mon.traded then otId = save.player and save.player.id end
  setU16be(buf, off + 12, otId or 0)
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

local function listLayout(base, cap, structSize)
  local monsAt = base + 2 + cap
  local otAt = monsAt + cap * structSize
  return monsAt, otAt, otAt + cap * NAME_LENGTH
end

local function decodeList(bytes, base, cap, structSize, isParty, cw, where)
  local list = {}
  local monsAt, otAt, nickAt = listLayout(base, cap, structSize)
  for i = 0, math.min(u8(bytes, base), cap) - 1 do
    local mon = decodeMon(bytes, monsAt + i * structSize, isParty, cw, u8(bytes, base + 1 + i))
    local otOff, nickOff = otAt + i * NAME_LENGTH, nickAt + i * NAME_LENGTH
    if mon.cartRaw then
      mon.cartOt = hexOf(bytes, otOff, NAME_LENGTH)
      mon.cartNick = hexOf(bytes, nickOff, NAME_LENGTH)
      mon.cartSlot = { where = where, index = i + 1 }
      mon.nickname = decodeName(bytes, nickOff, NAME_LENGTH)
    else
      mon.ot = decodeName(bytes, otOff, NAME_LENGTH)
      -- a stored name equal to the species' standard name means NOT
      -- nicknamed, which this project spells as nil (#257)
      mon.nickname = importedNickname(cw, mon.species, decodeName(bytes, nickOff, NAME_LENGTH))
    end
    list[#list + 1] = mon
  end
  return list
end

local function encodeList(buf, base, cap, structSize, isParty, mons, save, cw, padTail)
  local n = math.min(#mons, cap)
  setByte(buf, base, n)
  local monsAt, otAt, nickAt = listLayout(base, cap, structSize)
  local playerName = (save.player and save.player.name) or "RED"
  for i = 0, n - 1 do
    local mon = mons[i + 1]
    local monOff = monsAt + i * structSize
    local otOff, nickOff = otAt + i * NAME_LENGTH, nickAt + i * NAME_LENGTH
    local raw = unhex(mon.cartRaw)
    if raw then
      putRaw(buf, monOff, raw, structSize)
      setByte(buf, base + 1 + i, tonumber(mon.cartListSpecies) or raw:byte(1))
      local ot, nick = unhex(mon.cartOt), unhex(mon.cartNick)
      if ot then putRaw(buf, otOff, ot, NAME_LENGTH) end
      if nick then putRaw(buf, nickOff, nick, NAME_LENGTH) end
    else
      encodeMon(buf, monOff, mon, isParty, cw, save)
      setByte(buf, base + 1 + i, speciesIndexOf(cw, mon))
      encodeName(buf, otOff, NAME_LENGTH, mon.ot or playerName, padTail, TRAINER_NAME_MAX)
      -- no nickname stores the species' DISPLAY name, not its ROM constant id
      -- ("NIDORAN_M" would charmap the "_" to "?") (#257)
      encodeName(buf, nickOff, NAME_LENGTH, mon.nickname or speciesName(cw, mon.species), padTail)
    end
  end
  -- $FF-terminate the species index list right after the last real mon. The
  -- struct, OT-name and nickname bytes of the empty slots past n are left
  -- exactly as the template holds them (original stale data -> byte-identical
  -- round-trip) or zero on a fresh export -- the game never reads past the
  -- count, so this matches how it leaves those bytes itself.
  setByte(buf, base + 1 + n, 0xFF)
end

local function copyList(list)
  local out = {}
  for i, v in ipairs(type(list) == "table" and list or {}) do out[i] = v end
  return out
end

local function withCarriers(save)
  local party = copyList(save.party)
  local boxes = {}
  for b = 1, 12 do boxes[b] = copyList(save.boxes and save.boxes[b]) end
  local orphans = type(save.orphaned) == "table" and save.orphaned.mons
  for _, mon in ipairs(type(orphans) == "table" and orphans or {}) do
    local slot = type(mon) == "table" and mon.cartRaw and mon.cartSlot
    if type(slot) == "table" then
      local list, cap
      if slot.where == "party" then
        list, cap = party, PARTY_LENGTH
      elseif boxes[tonumber(slot.where) or 0] then
        list, cap = boxes[tonumber(slot.where)], MONS_PER_BOX
      end
      if not (list and #list < cap) then
        list = nil
        for b = 1, 12 do
          if #boxes[b] < MONS_PER_BOX then list = boxes[b]; break end
        end
      end
      if list then
        local at = math.max(1, math.min(tonumber(slot.index) or (#list + 1), #list + 1))
        table.insert(list, at, mon)
      end
    end
  end
  return party, boxes
end

-- ------------------------------------------------------------------
-- Bag / PC items: (id, qty) byte pairs, $FF-terminated
-- ------------------------------------------------------------------

local function decodeItemRows(bytes, off, capacity)
  local rows = {}
  for i = 0, capacity - 1 do
    local idByte = u8(bytes, off + i * 2)
    if idByte == 0xFF then break end
    rows[#rows + 1] = { idByte, u8(bytes, off + i * 2 + 1) }
  end
  return rows
end

local function stackCounts(stacks, id, qty)
  local list = type(stacks) == "table" and stacks[id]
  if type(list) ~= "table" or #list < 2 then return nil end
  local sum = 0
  for i = 1, #list do
    local c = list[i]
    if type(c) ~= "number" or c < 1 or c > 99 or c % 1 ~= 0 then return nil end
    sum = sum + c
  end
  if sum ~= qty then return nil end
  return list
end

local function foldRows(rows, cw)
  local inventory, order, counts = {}, {}, {}
  for _, r in ipairs(rows) do
    local id = cw.itemsByIndex[r[1]]
    if id and not BADGE_BY_BIT_SET[id] and r[2] > 0 then
      order[#order + 1] = id
      inventory[id] = (inventory[id] or 0) + r[2]
      local list = counts[id] or {}
      list[#list + 1] = r[2]
      counts[id] = list
    end
  end
  local stacks = {}
  for id, list in pairs(counts) do
    local derived = true
    for k = 1, #list - 1 do
      if list[k] ~= 99 then derived = false end
    end
    if not derived and stackCounts({ [id] = list }, id, inventory[id]) then stacks[id] = list end
  end
  return inventory, order, next(stacks) ~= nil and stacks or nil
end

-- engine/items/inventory.asm:64
local function modelRows(inventory, order, capacity, cw, stacks)
  inventory = inventory or {}
  local need, lists = {}, {}
  local function slots(id)
    if need[id] == nil then
      local qty = tonumber(inventory[id])
      qty = qty and math.floor(qty) or 0
      lists[id] = stackCounts(stacks, id, qty)
      need[id] = (qty > 0 and cw.itemsIndex[id] and not BADGE_BY_BIT_SET[id])
        and (lists[id] and #lists[id] or math.ceil(qty / 99)) or 0
    end
    return need[id]
  end
  local kept, have = {}, {}
  for _, id in ipairs(type(order) == "table" and order or {}) do
    if (have[id] or 0) < slots(id) then
      have[id] = (have[id] or 0) + 1
      kept[#kept + 1] = id
    end
  end
  local ids, at = {}, {}
  for _, id in ipairs(kept) do
    at[id] = (at[id] or 0) + 1
    ids[#ids + 1] = id
    if at[id] == have[id] then
      for _ = have[id] + 1, slots(id) do ids[#ids + 1] = id end
    end
  end
  local rest = {}
  for id in pairs(inventory) do
    if not have[id] and slots(id) > 0 then rest[#rest + 1] = id end
  end
  table.sort(rest, function(a, b)
    local ia, ib = cw.itemsIndex[a] or 1e9, cw.itemsIndex[b] or 1e9
    if ia ~= ib then return ia < ib end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(rest) do
    for _ = 1, slots(id) do ids[#ids + 1] = id end
  end
  local rows, k = {}, {}
  for _, id in ipairs(ids) do
    if #rows >= capacity then break end
    k[id] = (k[id] or 0) + 1
    local n = slots(id)
    local q = lists[id] and lists[id][k[id]]
      or (k[id] < n and 99 or math.floor(tonumber(inventory[id])) - 99 * (n - 1))
    rows[#rows + 1] = { cw.itemsIndex[id], q }
  end
  return rows
end

local function sameRows(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then return false end
  end
  return true
end

local function validRows(rows)
  if type(rows) ~= "table" then return nil end
  for _, r in ipairs(rows) do
    if type(r) ~= "table" or type(r[1]) ~= "number" or type(r[2]) ~= "number" then return nil end
  end
  return rows
end

local function decodeItems(bytes, off, capacity, cw)
  local rows = decodeItemRows(bytes, off, capacity)
  local inventory, order, stacks = foldRows(rows, cw)
  local carrier = nil
  if not sameRows(modelRows(inventory, order, capacity, cw, stacks), rows) then carrier, stacks = rows, nil end
  return inventory, order, carrier, stacks
end

local function encodeItems(buf, countOff, off, capacity, inventory, order, carrier, cw, stacks)
  local rows = modelRows(inventory, order, capacity, cw, stacks)
  carrier = validRows(carrier)
  if carrier then
    local inv, ord = foldRows(carrier, cw)
    if sameRows(modelRows(inv, ord, capacity, cw), rows) then
      rows = carrier
    else
      for _, r in ipairs(carrier) do
        if #rows >= capacity then break end
        if not cw.itemsByIndex[r[1]] or BADGE_BY_BIT_SET[cw.itemsByIndex[r[1]]] then
          rows[#rows + 1] = r
        end
      end
    end
  end
  local n = math.min(#rows, capacity)
  for i = 1, n do
    setByte(buf, off + (i - 1) * 2, rows[i][1])
    setByte(buf, off + (i - 1) * 2 + 1, rows[i][2])
  end
  setByte(buf, off + n * 2, 0xFF)
  setByte(buf, countOff, n)
end

local function eachTrainerEvent(data, fn)
  local headers = data.trainerHeaders
  if type(headers) ~= "table" or type(data.maps) ~= "table" then return end
  for mapId, def in pairs(data.maps) do
    local perMap = type(def) == "table" and def.label and headers[def.label]
    if type(perMap) == "table" then
      local wild = {}
      for _, obj in ipairs(def.objects or {}) do
        if type(obj) == "table" and obj.pokemon and obj.index then wild[obj.index] = true end
      end
      for idx, h in pairs(perMap) do
        if type(h) == "table" and type(h.event) == "string" and type(idx) == "number" and not wild[idx] then
          fn(mapId .. "_obj_" .. idx, h.event)
        end
      end
    end
  end
end

-- data/maps/special_warps.asm:64
local function blackoutSpots()
  local spots = {}
  for _, row in ipairs(require("src.save_convert.data.blackout_maps")) do spots[row[1]] = row end
  return spots
end

local function blackoutTown(cw, data, heal)
  local spots = blackoutSpots()
  local function usable(id)
    return type(id) == "string" and spots[id] ~= nil and cw.mapsIndex[id] ~= nil
  end
  if type(heal.outdoor) == "table" and usable(heal.outdoor.id) then return heal.outdoor.id end
  if usable(heal.map) then return heal.map end
  if type(data.maps) ~= "table" or type(heal.map) ~= "string" then return nil end
  local towns = {}
  for id in pairs(spots) do towns[#towns + 1] = id end
  table.sort(towns)
  for _, id in ipairs(towns) do
    local def = data.maps[id]
    for _, warp in ipairs(type(def) == "table" and def.warps or {}) do
      if warp.destMap == heal.map and usable(id) then return id end
    end
  end
  return nil
end

-- ------------------------------------------------------------------
-- decode: raw 32768-byte SRAM string -> save.lua-shaped table
-- ------------------------------------------------------------------

function GenSave.decode(bytes, data, opts)
  assert(#bytes == GenSave.SAVE_SIZE, "expected a 32768-byte save")
  if GenSave.looksLikeJapaneseSave(bytes) then
    error("Japanese Gen 1 cartridge saves are not supported", 0)
  end
  local cw = GenSave.crosswalks(data)
  local warnings = {}
  local function warn(msg) warnings[#warnings + 1] = msg end

  if checksum(bytes, O.checksumStart, O.checksumEnd) ~= u8(bytes, O.mainChecksum) then
    warn("main data checksum mismatch (importing anyway)")
  end

  local save = {
    meta = { format = "gen1_import", playthroughId = GenSave.readIdentity(bytes) },
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

  save.inventory, save.bagOrder, save.cartBag, save.bagStacks = decodeItems(bytes, O.bagItems, 20, cw)
  save.pcItems, save.pcOrder, save.cartPc, save.pcStacks = decodeItems(bytes, O.pcItems, 50, cw)

  -- badges: truthy save.inventory[id] entries (src/inventory/Badges.lua),
  -- set AFTER the bag decode since that call replaces save.inventory
  local badgesByte = u8(bytes, O.badges)
  for i = 0, NUM_BADGES - 1 do
    if bit.band(badgesByte, bit.lshift(1, i)) ~= 0 then
      save.inventory[BADGE_BY_BIT[i]] = 1
    end
  end

  -- engine/menus/main_menu.asm InitOptions
  local ob = u8(bytes, O.options)
  save.options = {
    textSpeed = bit.band(ob, 0x07),
    battleStyle = bit.band(ob, 0x40) ~= 0 and "set" or "shift",
    animations = bit.band(ob, 0x80) == 0,
  }
  local sound = bit.band(bit.rshift(ob, 4), 3)
  if sound ~= 0 then save.options.sound = sound end
  save.importedOptions = {
    textSpeed = save.options.textSpeed,
    battleStyle = save.options.battleStyle,
    animations = save.options.animations,
  }

  save.party = decodeList(bytes, O.partyData, PARTY_LENGTH, PARTY_STRUCT_SIZE, true, cw, "party")

  -- current box (bank 1) + the 11 stored boxes (banks 2/3)
  -- engine/menus/save.asm:365
  for i = 1, 12 do save.boxes[i] = {} end
  local boxByte = u8(bytes, O.currentBoxNum)
  local initialized = bit.band(boxByte, 0x80) ~= 0
  local rawBox = bit.band(boxByte, 0x7F)
  local curBoxNum = nil
  if rawBox <= 11 then
    curBoxNum = rawBox + 1
    save.boxes[curBoxNum] = decodeList(bytes, O.curBoxData, MONS_PER_BOX, BOX_STRUCT_SIZE, false, cw, curBoxNum)
    save.currentBox = curBoxNum
  else
    save.cartBoxNum = rawBox
    save.currentBox = 1
  end
  if initialized then
    for b = 1, 12 do
      if b ~= curBoxNum then
        local base = b <= 6 and (O.box1 + (b - 1) * BOX_REGION_SIZE) or (O.box7 + (b - 7) * BOX_REGION_SIZE)
        save.boxes[b] = decodeList(bytes, base, MONS_PER_BOX, BOX_STRUCT_SIZE, false, cw, b)
      end
    end
  end

  -- constants/event_constants.asm
  local events = data.eventFlags
  if events then
    local raw = {}
    local anyRaw = false
    for i = 0, 319 do raw[i] = u8(bytes, O.eventFlags + i) end
    for bitIdx, name in pairs(events.byBit) do
      local byteIdx = math.floor(bitIdx / 8)
      if bitGet(bytes, O.eventFlags, bitIdx) then save.flags[name] = true end
      raw[byteIdx] = bit.band(raw[byteIdx], bit.bnot(bit.lshift(1, bitIdx % 8)))
    end
    local hex = {}
    for i = 0, 319 do
      if raw[i] ~= 0 then anyRaw = true end
      hex[i + 1] = ("%02X"):format(raw[i])
    end
    if anyRaw then save.flagsRaw = table.concat(hex) end
  end

  -- the same progress under names that are not wEventFlags bits (#396)
  for name, spec in pairs(EXTRA_FLAG_BITS) do
    if bitGet(bytes, spec[1], spec[2]) then save.flags[name] = true end
  end
  for bitIdx, name in pairs(tradeFlagsOf(data)) do
    if bitGet(bytes, O.tradeFlags, bitIdx) then save.flags[name] = true end
  end
  for portName, vanillaName in pairs(FLAG_ALIAS) do
    if save.flags[vanillaName] then save.flags[portName] = true end
  end

  save.defeatedTrainers = {}
  eachTrainerEvent(data, function(key, event)
    if save.flags[event] then save.defeatedTrainers[key] = true end
  end)

  -- scripts/OaksLab.asm:335, :900-901
  if save.flags.EVENT_GOT_STARTER then
    local chosen = cw.pokemonByIndex[u8(bytes, O.playerStarter)]
    if data.gameVersion == "yellow" then
      if chosen ~= YELLOW_STARTER then chosen = nil end
    elseif not PLAYER_TO_RIVAL[chosen or ""] then
      chosen = RIVAL_TO_PLAYER[cw.pokemonByIndex[u8(bytes, O.rivalStarter)] or ""]
    end
    if chosen then
      save.flags["EVENT_CHOSE_" .. chosen] = true
    else
      warn("no starter recorded in the save; rival parties will default")
    end
  end
  if data.gameVersion == "yellow" then
    local rival = u8(bytes, O.rivalStarter)
    if rival >= 1 and rival <= 3 then save.rivalStarter = rival end
  end
  local starterFlag = false
  for _, species in ipairs({ "BULBASAUR", "CHARMANDER", "SQUIRTLE", YELLOW_STARTER }) do
    if save.flags["EVENT_CHOSE_" .. species] then starterFlag = true end
  end
  if not starterFlag then
    local ps, rs = u8(bytes, O.playerStarter), u8(bytes, O.rivalStarter)
    if data.gameVersion == "yellow" then rs = 0 end
    if ps ~= 0 or rs ~= 0 then save.cartStarters = { ps, rs } end
  end

  -- wToggleableObjectFlags -> save.objectToggles (bit set = hidden).  A few
  -- of these are re-derived from flags on map entry (#106/#234 onEnter
  -- re-applies), but most ShowObject/HideObject state -- the Mt Moon
  -- fossils, the Cerulean guard swap -- has no flag to re-derive from, so
  -- an import that drops the array resurrects taken fossils and blocking
  -- guards (#763, #857).
  local toggles = data.toggleObjects
  if toggles then
    save.objectToggles = {}
    for bitIdx, e in pairs(toggles.byBit) do
      local mapToggles = save.objectToggles[e[1]]
      if not mapToggles then
        mapToggles = {}
        save.objectToggles[e[1]] = mapToggles
      end
      mapToggles[e[2]] = not bitGet(bytes, O.toggleObjectFlags, bitIdx)
    end
  end

  if data.hiddenItems then
    save.hiddenTaken = {}
    for i, row in ipairs(data.hiddenItems) do
      if bitGet(bytes, O.hiddenItemFlags, i - 1) then
        save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] = true
      end
    end
  end

  local coinSpots = require("src.save_convert.data.hidden_coins")
  for i, row in ipairs(coinSpots) do
    if bitGet(bytes, O.hiddenCoinFlags, i - 1) then
      save.hiddenTaken = save.hiddenTaken or {}
      save.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] = true
    end
  end

  if save.flags.EVENT_IN_SAFARI_ZONE then
    save.safari = { balls = u8(bytes, O.safariBalls), steps = u16be(bytes, O.safariSteps) }
  end

  local dayCareIn = u8(bytes, O.dayCare)
  if dayCareIn ~= 0 then
    local mon = decodeMon(bytes, O.dayCare + DAYCARE_MON, false, cw, nil)
    if mon.cartRaw then
      save.daycare = { cartRaw = hexOf(bytes, O.dayCare, DAYCARE_SIZE) }
    else
      mon.ot = decodeName(bytes, O.dayCare + DAYCARE_OT, NAME_LENGTH)
      mon.nickname = importedNickname(cw, mon.species, decodeName(bytes, O.dayCare + 1, NAME_LENGTH))
      save.daycare = { mon = mon, steps = 0, depositLevel = mon.level }
    end
  end

  if bitGet(bytes, O.statusFlags6, 5) then save.forcedBike = true end
  if bitGet(bytes, O.statusFlags4, 2) then save.usedPokecenter = true end

  local trashFirst, trashSecond = u8(bytes, O.trashFirst), u8(bytes, O.trashSecond)
  if trashFirst ~= 0 or trashSecond ~= 0 then
    save.trashPuzzle = { first = trashFirst, second = trashSecond }
  end

  if save.flags.EVENT_GAVE_FOSSIL_TO_LAB then
    local fossil = cw.pokemonByIndex[u8(bytes, O.fossilMon)]
    if FOSSIL_ITEM_FOR_MON[fossil or ""] then save.labFossilMon = fossil end
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
  if mapId and isDarkMap(data, mapId) and u8(bytes, O.mapPalOffset) == 0 then save.flashLit = true end
  local lastMapIdx = u8(bytes, O.lastMap)
  local lastMapId = cw.mapsByIndex[lastMapIdx]
  if lastMapId then
    save.lastOutdoor = { id = lastMapId }
  else
    save.cartLastMap = lastMapIdx
  end

  -- engine/events/set_blackout_map.asm:19
  local blackoutIdx = u8(bytes, O.lastBlackoutMap)
  local spot = blackoutSpots()[cw.mapsByIndex[blackoutIdx] or ""]
  if spot then
    save.lastHeal = { map = spot[1], x = spot[2], y = spot[3] }
  else
    local pallet = require("src.save_convert.data.blackout_maps")[1]
    save.lastHeal = { map = pallet[1], x = pallet[2], y = pallet[3] }
    save.cartBlackoutMap = blackoutIdx
  end

  -- ram/wram.asm:2053
  local walk = u8(bytes, O.walkBikeSurf)
  if walk == 1 then save.onBike = true elseif walk == 2 then save.player.surfing = true end

  -- play time: this project stores save.playTime as a single float of
  -- SECONDS (src/core/Game.lua accumulates dt each frame; StartMenu /
  -- TrainerCard / TitleState render it H:MM via t/3600 and (t/60)%60).
  -- Fold the Gen1 H/M/S/F fields into that one number; frames are 1/60s
  -- sub-second ticks, kept as a fraction so an export recovers them exactly.
  local hours = u8(bytes, O.playTimeHours)
  save.playTime = hours * 3600
                + u8(bytes, O.playTimeMinutes) * 60
                + u8(bytes, O.playTimeSeconds)
                + u8(bytes, O.playTimeFrames) / 60
  local maxed = u8(bytes, O.playTimeMaxed)
  if maxed ~= 0 or hours == 255 then save.playTimeMaxed = maxed end

  -- engine/menus/save.asm:655
  local numHoF = u8(bytes, O.numHoFTeams)
  local stored = math.min(numHoF, HOF_TEAM_CAPACITY)
  if stored > 0 then
    save.hallOfFame = {}
    for t = 0, stored - 1 do
      local team = {}
      for s = 0, PARTY_LENGTH - 1 do
        local at = O.hallOfFame + t * HOF_TEAM + s * HOF_MON
        local sp = u8(bytes, at)
        if sp == 0xFF then break end
        local species = cw.pokemonByIndex[sp]
        if species then
          team[#team + 1] = { species = species, level = u8(bytes, at + 1),
            nickname = importedNickname(cw, species, decodeName(bytes, at + 2, NAME_LENGTH)) }
        else
          team[#team + 1] = { cartRaw = hexOf(bytes, at, HOF_MON), level = u8(bytes, at + 1) }
        end
      end
      save.hallOfFame[#save.hallOfFame + 1] = team
    end
  end
  if numHoF > stored then save.hallOfFameTotal = numHoF end

  -- Yellow starter friendship (save.pikachuHappiness,
  -- src/world/PikachuFollower.lua reads it; pokeyellow's
  -- init_player_data.asm seeds 90 on a new game), gated on the data set's
  -- game because the byte is map scratch in Red/Blue (see
  -- O.pikachuHappiness) (#763, #838).
  if data.gameVersion == "yellow" then
    save.pikachuHappiness = u8(bytes, O.pikachuHappiness)
    save.pikachuMood = u8(bytes, O.pikachuMood)
    local modifier = u8(bytes, O.pikachuEmotionModifier)
    save.pikachuEmotionModifier = modifier ~= 0 and modifier or nil
  end

  if data.gameVersion == "yellow" then
    local lo, hi = u8(bytes, O.surfHiScore), u8(bytes, O.surfHiScore + 1)
    if lo % 16 < 10 and hi % 16 < 10 and math.floor(lo / 16) < 10 and math.floor(hi / 16) < 10 then
      local score = readBcd(bytes, O.surfHiScore + 1, 1) * 100 + readBcd(bytes, O.surfHiScore, 1)
      if score > 0 then save.surfingHighScore = score end
    else
      save.cartSurfHiScore = { lo, hi }
    end
  end

  save.warnings = warnings
  save.rawImport = bytes -- template for a later encode(); see file header
  return save
end

-- ------------------------------------------------------------------
-- encode: save.lua-shaped table -> raw 32768-byte SRAM string
-- ------------------------------------------------------------------

local function identityOf(save)
  local meta = type(save) == "table" and save.meta
  local id = type(meta) == "table" and meta.playthroughId
  if type(id) ~= "string" or #id ~= GenSave.IDENTITY_ID_LENGTH then return nil end
  if not id:match("^%x+$") then return nil end
  return id
end

function GenSave.readIdentity(bytes)
  if type(bytes) ~= "string" or #bytes < GenSave.SAVE_SIZE then return nil end
  local off = O.identityTag
  local magic = GenSave.IDENTITY_MAGIC
  if bytes:sub(off + 1, off + #magic) ~= magic then return nil end
  return identityOf({ meta = { playthroughId =
    bytes:sub(off + #magic + 1, off + #magic + GenSave.IDENTITY_ID_LENGTH) } })
end

local function sum8(s, from, toExcl)
  local sum = 0
  for i = from + 1, toExcl do sum = sum + s:byte(i) end
  return sum % 256
end

local function looksLikeGen2(s)
  local crystal = sum8(s, 0x2009, 0x2B83) == s:byte(0x2D0D + 1)
    and sum8(s, 0x1209, 0x1D83) == s:byte(0x1F0D + 1)
  local gs = sum8(s, 0x2009, 0x2D69) == s:byte(0x2D69 + 1)
    and (sum8(s, 0x15C7, 0x17ED) + sum8(s, 0x3D96, 0x3F40) + sum8(s, 0x0C6B, 0x10E8)
      + sum8(s, 0x7E39, 0x7E6D) + sum8(s, 0x10E8, 0x15C7)) % 256 == s:byte(0x7E6D + 1)
  return crystal or gs
end

function GenSave.encode(save, data, template)
  local cw = GenSave.crosswalks(data)
  local src = template or save.rawImport
  local note
  if type(src) ~= "string" then
    src = nil
  elseif not GenSave.templateIntact(src) then
    src, note = nil, GenSave.MSG_REBUILT
  end
  local buf = {}
  if src then
    for i = 1, GenSave.SAVE_SIZE do buf[i] = src:sub(i, i) end
  else
    local zero = string.char(0)
    for i = 1, GenSave.SAVE_SIZE do buf[i] = zero end
  end

  local identity = identityOf(save)
  if identity then
    local tag = GenSave.IDENTITY_MAGIC .. identity
    for i = 1, #tag do buf[O.identityTag + i] = tag:sub(i, i) end
  end
  local padAt = (src and src:sub(O.identityTag + 1, O.identityTag + 4) == GenSave.IDENTITY_MAGIC or identity)
    and O.padByteTagged or O.padByte

  local padTail = not src
  encodeName(buf, O.playerName, NAME_LENGTH, (save.player and save.player.name) or "RED", padTail, TRAINER_NAME_MAX)
  encodeName(buf, O.rivalName, NAME_LENGTH, (save.player and save.player.rival) or "BLUE", padTail, TRAINER_NAME_MAX)
  setU16be(buf, O.playerId, (save.player and save.player.id) or 0)
  -- wOptions (engine/menus/main_menu.asm InitOptions): bit 7 = battle
  -- effects OFF, bit 6 = SET style, bits 2-0 = text speed -- the recomp's
  -- textSpeed 1/3/5 are pokered's exact FAST/MEDIUM/SLOW values
  -- (SaveData.defaultOptions).
  local opts = save.options
  if type(opts) == "table" or not src then
    opts = type(opts) == "table" and opts or {}
    local ob = src and u8(src, O.options) or 0
    ob = bit.bor(bit.band(ob, 0x38), bit.band(math.floor(tonumber(opts.textSpeed) or 3), 0x07))
    if opts.battleStyle == "set" then ob = bit.bor(ob, 0x40) end
    if opts.animations == false then ob = bit.bor(ob, 0x80) end
    local sound = tonumber(opts.sound)
    if sound then ob = bit.bor(bit.band(ob, 0xCF), bit.lshift(bit.band(math.floor(sound), 3), 4)) end
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

  -- Badges occupy real item IDs in data/generated/items.lua, but this
  -- project's save.lua stores them as truthy save.inventory[id] entries
  -- alongside actual bag items (see the badge block above and
  -- src/inventory/Badges.lua) -- a real save NEVER writes them into
  -- wBagItems (they only ever live in wObtainedBadges, already encoded
  -- above), so they must be filtered out here or they'd corrupt the bag
  -- with bogus "badge items".
  encodeItems(buf, O.numBagItems, O.bagItems, 20, save.inventory or {}, save.bagOrder, save.cartBag, cw, save.bagStacks)
  encodeItems(buf, O.numPcItems, O.pcItems, 50, save.pcItems or {}, save.pcOrder, save.cartPc, cw, save.pcStacks)

  local flags = type(save.flags) == "table" and save.flags or {}
  local events = data.eventFlags
  if events then
    local beaten = {}
    eachTrainerEvent(data, function(key, event)
      if type(save.defeatedTrainers) == "table" and save.defeatedTrainers[key] then beaten[event] = true end
    end)
    local raw = unhex(save.flagsRaw)
    if raw and #raw ~= 320 then raw = nil end
    local named = {}
    for bitIdx in pairs(events.byBit) do
      local byteIdx = math.floor(bitIdx / 8)
      named[byteIdx] = bit.bor(named[byteIdx] or 0, bit.lshift(1, bitIdx % 8))
    end
    for i = 0, 319 do
      local b = raw and raw:byte(i + 1) or (src and u8(src, O.eventFlags + i)) or 0
      setByte(buf, O.eventFlags + i, bit.band(b, bit.bnot(named[i] or 0)))
    end
    local portOf = {}
    for portName, vanillaName in pairs(FLAG_ALIAS) do portOf[vanillaName] = portName end
    for bitIdx, name in pairs(events.byBit) do
      if flags[name] or (portOf[name] and flags[portOf[name]]) or beaten[name] then
        bitSet(buf, O.eventFlags, bitIdx, true)
      end
    end
  end

  -- Non-wEventFlags progress, written both ways: this port's save is the only
  -- authority for these names, so a flag it does not hold must clear the
  -- template's bit rather than survive in the export (#396).
  for name, spec in pairs(EXTRA_FLAG_BITS) do
    bitSet(buf, spec[1], spec[2], flags[name] and true or false)
  end
  for bitIdx, name in pairs(tradeFlagsOf(data)) do
    bitSet(buf, O.tradeFlags, bitIdx, flags[name] and true or false)
  end

  local cartStarters = type(save.cartStarters) == "table" and save.cartStarters
  if cartStarters then
    if tonumber(cartStarters[1]) then setByte(buf, O.playerStarter, cartStarters[1]) end
    if tonumber(cartStarters[2]) and data.gameVersion ~= "yellow" then setByte(buf, O.rivalStarter, cartStarters[2]) end
  end
  -- scripts/OaksLab.asm:322-323, :900-901
  if data.gameVersion == "yellow" then
    if flags["EVENT_CHOSE_" .. YELLOW_STARTER] then
      setByte(buf, O.playerStarter, cw.pokemonIndex[YELLOW_STARTER] or 0)
    end
    local rival = tonumber(save.rivalStarter)
    if rival and rival >= 1 and rival <= 3 then
      setByte(buf, O.rivalStarter, rival)
    end
  else
    for _, species in ipairs({ "BULBASAUR", "CHARMANDER", "SQUIRTLE" }) do
      if flags["EVENT_CHOSE_" .. species] then
        setByte(buf, O.playerStarter, cw.pokemonIndex[species] or 0)
        setByte(buf, O.rivalStarter, cw.pokemonIndex[PLAYER_TO_RIVAL[species]] or 0)
      end
    end
  end

  -- wToggleableObjectFlags, written both ways like the #396 extras: this
  -- port's save is the authority, and vanilla folds three stores this port
  -- keeps separate into these same bits -- script ShowObject/HideObject
  -- (save.objectToggles), taken overworld items (engine/events/
  -- pick_up_item.asm -> save.itemsTaken) and beaten static encounters
  -- (home/trainers.asm HideObject after battle -> save.defeatedTrainers) --
  -- so all three fold back in here or an exported save resurrects them
  -- (#763, #857).
  local toggleData = data.toggleObjects
  if toggleData then
    local objectToggles = save.objectToggles or {}
    local itemsTaken = save.itemsTaken or {}
    local beaten = save.defeatedTrainers or {}
    for bitIdx, e in pairs(toggleData.byBit) do
      local mapId, objName, visible = e[1], e[2], e[3]
      local mapToggles = objectToggles[mapId]
      if mapToggles and mapToggles[objName] ~= nil then
        visible = mapToggles[objName]
      end
      if visible and data.maps and data.maps[mapId] then
        for _, obj in ipairs(data.maps[mapId].objects or {}) do
          if obj.name == objName then
            local key = mapId .. "_obj_" .. obj.index
            if (obj.item and itemsTaken[key])
               or (obj.pokemon and beaten[key]) then
              visible = false
            end
            break
          end
        end
      end
      bitSet(buf, O.toggleObjectFlags, bitIdx, not visible)
    end
  end

  if data.hiddenItems then
    local taken = save.hiddenTaken or {}
    for i, row in ipairs(data.hiddenItems) do
      local key = row[1] .. "_" .. row[2] .. "_" .. row[3]
      bitSet(buf, O.hiddenItemFlags, i - 1, taken[key] and true or false)
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

  local coinSpotsOut = require("src.save_convert.data.hidden_coins")
  do
    local taken = save.hiddenTaken or {}
    for i, row in ipairs(coinSpotsOut) do
      bitSet(buf, O.hiddenCoinFlags, i - 1, taken[row[1] .. "_" .. row[2] .. "_" .. row[3]] and true or false)
    end
  end

  local safari = type(save.safari) == "table" and save.safari or nil
  if safari then
    setByte(buf, O.safariBalls, math.max(0, math.min(255, math.floor(tonumber(safari.balls) or 0))))
    setU16be(buf, O.safariSteps, math.max(0, math.min(65535, math.floor(tonumber(safari.steps) or 0))))
  end
  local eventBits = data.eventFlags and data.eventFlags.byName
  if eventBits then
    if eventBits.EVENT_IN_SAFARI_ZONE then
      bitSet(buf, O.eventFlags, eventBits.EVENT_IN_SAFARI_ZONE, safari ~= nil)
    end
    if eventBits.EVENT_SAFARI_GAME_OVER then
      bitSet(buf, O.eventFlags, eventBits.EVENT_SAFARI_GAME_OVER,
        save.safariGameOver == true or (flags.EVENT_SAFARI_GAME_OVER == true and safari == nil))
    end
  end

  -- scripts/SafariZoneGate.asm:8
  local SAFARI_GATE_LEAVING = 5
  local sameSafari = safari and src and eventBits and eventBits.EVENT_IN_SAFARI_ZONE
    and bitGet(src, O.eventFlags, eventBits.EVENT_IN_SAFARI_ZONE)
    and u8(src, O.safariBalls) == safari.balls and u16be(src, O.safariSteps) == safari.steps
  if sameSafari then
    setByte(buf, O.safariGateScript, u8(src, O.safariGateScript))
  elseif safari or save.safariGameOver == true then
    setByte(buf, O.safariGateScript, SAFARI_GATE_LEAVING)
  elseif src and eventBits and eventBits.EVENT_IN_SAFARI_ZONE
      and bitGet(src, O.eventFlags, eventBits.EVENT_IN_SAFARI_ZONE)
      and u8(src, O.safariGateScript) == SAFARI_GATE_LEAVING then
    setByte(buf, O.safariGateScript, 0)
  end

  local dayCare = save.daycare
  local dayCareMon = type(dayCare) == "table" and type(dayCare.mon) == "table" and dayCare.mon
  if dayCareMon then
    local mon = {}
    for k, v in pairs(dayCareMon) do mon[k] = v end
    mon.level = tonumber(dayCare.depositLevel) or dayCareMon.level
    mon.exp = math.min(0xFFFFFF, (tonumber(dayCareMon.exp) or 0) + math.floor(tonumber(dayCare.steps) or 0))
    mon.boxLevel = nil
    local was = src and u8(src, O.dayCare) or 0
    setByte(buf, O.dayCare, was ~= 0 and was or 1)
    encodeMon(buf, O.dayCare + DAYCARE_MON, mon, false, cw, save)
    encodeName(buf, O.dayCare + 1, NAME_LENGTH, mon.nickname or speciesName(cw, mon.species), padTail)
    encodeName(buf, O.dayCare + DAYCARE_OT, NAME_LENGTH, mon.ot or (save.player and save.player.name) or "RED",
      padTail, TRAINER_NAME_MAX)
  elseif type(dayCare) == "table" and unhex(dayCare.cartRaw) then
    putRaw(buf, O.dayCare, unhex(dayCare.cartRaw), DAYCARE_SIZE)
  else
    setByte(buf, O.dayCare, 0)
  end

  bitSet(buf, O.statusFlags6, 5, save.forcedBike == true)
  bitSet(buf, O.statusFlags4, 2, save.usedPokecenter == true)
  -- scripts/OaksLab.asm:933
  local starterBit = eventBits and eventBits.EVENT_GOT_STARTER
  if starterBit then
    local now = flags.EVENT_GOT_STARTER == true
    if not src or bitGet(src, O.eventFlags, starterBit) ~= now then bitSet(buf, O.statusFlags4, 3, now) end
  end

  local trash = save.trashPuzzle
  if type(trash) == "table" then
    if tonumber(trash.first) then setByte(buf, O.trashFirst, trash.first) end
    if tonumber(trash.second) then setByte(buf, O.trashSecond, trash.second) end
  end

  local fossilIdx = save.labFossilMon and cw.pokemonIndex[save.labFossilMon]
  local fossilItem = FOSSIL_ITEM_FOR_MON[save.labFossilMon or ""]
  if fossilIdx and fossilItem and cw.itemsIndex[fossilItem] then
    setByte(buf, O.fossilMon, fossilIdx)
    setByte(buf, O.fossilItem, cw.itemsIndex[fossilItem])
  end

  do
    local was = src and u8(src, O.badges) or 0
    local changed = bit.bxor(was, badgesByte)
    local beat = src and u8(src, O.beatGymFlags) or 0
    setByte(buf, O.beatGymFlags, bit.bor(bit.band(beat, bit.bnot(changed)), bit.band(badgesByte, changed)))
  end

  local party, boxes = withCarriers(save)
  encodeList(buf, O.partyData, PARTY_LENGTH, PARTY_STRUCT_SIZE, true, party, save, cw, padTail)

  -- engine/menus/save.asm:421
  local cartBoxNum = tonumber(save.cartBoxNum)
  local curBoxNum = math.max(1, math.min(12, math.floor(tonumber(save.currentBox) or 1)))
  local keepRawBox = cartBoxNum and cartBoxNum > 11 and cartBoxNum <= 0x7F and curBoxNum == 1
  local boxHiBit = 0x80
  if src then boxHiBit = bit.band(u8(src, O.currentBoxNum), 0x80) end
  local writeBanks = not src or boxHiBit ~= 0
  if not writeBanks then
    for b = 1, 12 do
      if (keepRawBox or b ~= curBoxNum) and #boxes[b] > 0 then writeBanks = true end
    end
  end
  if writeBanks then boxHiBit = 0x80 end
  if keepRawBox then
    setByte(buf, O.currentBoxNum, bit.bor(cartBoxNum, boxHiBit))
    if not src then
      setByte(buf, O.curBoxData, 0)
      setByte(buf, O.curBoxData + 1, 0xFF)
    end
  else
    encodeList(buf, O.curBoxData, MONS_PER_BOX, BOX_STRUCT_SIZE, false, boxes[curBoxNum], save, cw, padTail)
    setByte(buf, O.currentBoxNum, bit.bor(curBoxNum - 1, boxHiBit))
  end
  if writeBanks then
    for b = 1, 12 do
      local base = b <= 6 and (O.box1 + (b - 1) * BOX_REGION_SIZE) or (O.box7 + (b - 7) * BOX_REGION_SIZE)
      if b == curBoxNum and not keepRawBox then
        if not src or bit.band(u8(src, O.currentBoxNum), 0x80) == 0 then
          setByte(buf, base, 0)
          setByte(buf, base + 1, 0xFF)
        end
      else
        encodeList(buf, base, MONS_PER_BOX, BOX_STRUCT_SIZE, false, boxes[b], save, cw, padTail)
      end
    end
  end

  -- map + position
  local px = math.floor(tonumber(save.player and save.player.x) or 0)
  local py = math.floor(tonumber(save.player and save.player.y) or 0)
  if save.player and save.player.map then
    setByte(buf, O.curMap, cw.mapsIndex[save.player.map] or 0)
    setByte(buf, O.yCoord, py)
    setByte(buf, O.xCoord, px)
  end
  if save.player and save.player.map then
    if isDarkMap(data, save.player.map) then
      local was = src and u8(src, O.mapPalOffset) or 0
      setByte(buf, O.mapPalOffset, save.flashLit and 0 or (was ~= 0 and was or 6))
    else
      setByte(buf, O.mapPalOffset, 0)
    end
  end
  if save.lastOutdoor and save.lastOutdoor.id then
    if tonumber(save.cartLastMap) and save.lastOutdoor.id == (save.player and save.player.map) then
      setByte(buf, O.lastMap, save.cartLastMap)
    else
      setByte(buf, O.lastMap, cw.mapsIndex[save.lastOutdoor.id] or 0)
    end
  end

  -- engine/events/set_blackout_map.asm:19
  local heal = save.lastHeal
  if type(heal) == "table" then
    local target = blackoutTown(cw, data, heal)
    local idx = target and cw.mapsIndex[target]
    local raw = tonumber(save.cartBlackoutMap)
    if raw and target == "PALLET_TOWN" and type(heal.outdoor) ~= "table" then
      setByte(buf, O.lastBlackoutMap, raw)
    elseif idx then
      setByte(buf, O.lastBlackoutMap, idx)
    end
  end

  -- ram/wram.asm:2053
  local walk = (save.player and save.player.surfing) and 2 or (save.onBike and 1) or 0
  if walk == 0 and src and u8(src, O.walkBikeSurf) > 2 then walk = u8(src, O.walkBikeSurf) end
  setByte(buf, O.walkBikeSurf, walk)

  -- Current-map engine state (see src/save_convert/MapContext.lua).  A
  -- Continue restores this window from the save and never rebuilds it, so a
  -- zero-filled one boots into a garbled map on a silent hang (#889).
  --
  -- Rebuilt when there is no template at all (a save that began as a New Game
  -- in this port), and when the template was saved on a DIFFERENT map or cell
  -- than the one the player is standing on now -- an imported save that has
  -- since been played carries a stale map window, which is just as unbootable.
  -- A template still on its own cell keeps its bytes untouched: they are the
  -- game's own, including live NPC positions, and preserving them is what
  -- makes import -> export byte-identical.
  local mapId = save.player and save.player.map
  if mapId then
    local rebuild = true
    if src then
      -- compare the way the byte was written (masked), and rebuild when the
      -- map has no index at all rather than trusting a stale template
      local index = cw.mapsIndex[mapId]
      rebuild = index == nil or u8(src, O.curMap) ~= bit.band(index, 0xFF)
        or u8(src, O.yCoord) ~= bit.band(py, 0xFF)
        or u8(src, O.xCoord) ~= bit.band(px, 0xFF)
    end
    if rebuild then
      local ctx, why = MapContext.build(data, mapId, px, py)
      -- home/overworld.asm:2016 (#1691)
      if not ctx then
        error(("this save cannot be exported: %s"):format(tostring(why)), 0)
      end
      for offset, values in pairs(ctx.writes) do
        for i, value in ipairs(values) do
          setByte(buf, O.mainData + offset + i - 1, value)
        end
      end
      for i, value in ipairs(ctx.spriteData) do
        setByte(buf, O.spriteData + i - 1, value)
      end
      setByte(buf, O.checksumEnd - 1, ctx.tileAnimations)
    end
  end

  -- play time: split save.playTime (seconds) back into H/M/S/F. The real
  -- game freezes the clock at 255h and sets wPlayTimeMaxed once past it, so
  -- mirror that cap rather than letting hours overflow a single byte.
  -- engine/play_time.asm:36
  local totalFrames = math.floor((tonumber(save.playTime) or 0) * 60 + 0.5)
  local hours = math.floor(totalFrames / 216000) -- 3600s * 60 frames
  local maxedRaw = tonumber(save.playTimeMaxed)
  if hours > 255 then
    setByte(buf, O.playTimeHours, 255)
    setByte(buf, O.playTimeMaxed, (maxedRaw and maxedRaw ~= 0) and maxedRaw or 0xFF)
    setByte(buf, O.playTimeMinutes, 59)
    setByte(buf, O.playTimeSeconds, 59)
    setByte(buf, O.playTimeFrames, 59)
  else
    local rem = totalFrames - hours * 216000
    local mins = math.floor(rem / 3600); rem = rem - mins * 3600
    local secs = math.floor(rem / 60)
    setByte(buf, O.playTimeHours, hours)
    setByte(buf, O.playTimeMaxed, maxedRaw or (hours == 255 and 0xFF or 0))
    setByte(buf, O.playTimeMinutes, mins)
    setByte(buf, O.playTimeSeconds, secs)
    setByte(buf, O.playTimeFrames, rem - secs * 60)
  end

  -- engine/menus/save.asm:655
  local hof = save.hallOfFame
  if type(hof) == "table" then
    local total = #hof
    local first = math.max(1, total - HOF_TEAM_CAPACITY + 1)
    for k = first, total do
      local team = type(hof[k]) == "table" and hof[k] or {}
      local base = O.hallOfFame + (k - first) * HOF_TEAM
      local n = 0
      for s = 1, #team do
        if n >= PARTY_LENGTH then break end
        local mon = team[s]
        local at = base + n * HOF_MON
        local raw = type(mon) == "table" and unhex(mon.cartRaw)
        local idx = type(mon) == "table" and cw.pokemonIndex[mon.species]
        if raw then
          putRaw(buf, at, raw, HOF_MON)
          n = n + 1
        elseif idx and idx ~= 0 then
          setByte(buf, at, idx)
          setByte(buf, at + 1, math.max(0, math.min(255, math.floor(tonumber(mon.level) or 1))))
          encodeName(buf, at + 2, NAME_LENGTH, mon.nickname or speciesName(cw, mon.species), padTail)
          n = n + 1
        end
      end
      if n < PARTY_LENGTH then setByte(buf, base + n * HOF_MON, 0xFF) end
    end
    local importedTotal = math.max(0, math.floor(tonumber(save.hallOfFameTotal) or 0))
    local earned = math.max(0, total - math.min(importedTotal, HOF_TEAM_CAPACITY))
    setByte(buf, O.numHoFTeams, math.min(255, math.max(total, importedTotal + earned)))
  end

  if data.gameVersion == "yellow" then
    local score = tonumber(save.surfingHighScore)
    local cartHi = type(save.cartSurfHiScore) == "table" and save.cartSurfHiScore
    if score then
      score = math.max(0, math.min(9999, math.floor(score)))
      setBcd(buf, O.surfHiScore + 1, 1, math.floor(score / 100))
      setBcd(buf, O.surfHiScore, 1, score % 100)
    elseif cartHi then
      setByte(buf, O.surfHiScore, tonumber(cartHi[1]) or 0)
      setByte(buf, O.surfHiScore + 1, tonumber(cartHi[2]) or 0)
    end
  end

  -- Yellow starter friendship back out (see O.pikachuHappiness); Red/Blue
  -- data sets never reach this write.  90 is the fresh-game seed the
  -- follower system itself uses when the save has never tracked it.
  -- Placed before the checksum pass so the byte is covered by the
  -- main-data checksum automatically (#763, #838).
  if data.gameVersion == "yellow" then
    local h = tonumber(save.pikachuHappiness) or 90
    setByte(buf, O.pikachuHappiness, math.max(0, math.min(255, math.floor(h))))
    -- engine/movie/oak_speech/init_player_data.asm:17
    local mood = tonumber(save.pikachuMood) or 0x80
    setByte(buf, O.pikachuMood, math.max(0, math.min(255, math.floor(mood))))
    local modifier = tonumber(save.pikachuEmotionModifier) or 0
    setByte(buf, O.pikachuEmotionModifier, math.max(0, math.min(255, math.floor(modifier))))
  end

  local out = table.concat(buf)
  -- checksums, computed last over the now-final bytes
  local outBuf = {}
  for i = 1, #out do outBuf[i] = out:sub(i, i) end
  setByte(outBuf, O.mainChecksum, checksum(out, O.checksumStart, O.checksumEnd))
  -- Per pokered (engine/menus/save.asm SaveSAVtoSRAM / CalcCheckSum): each box
  -- gets its own checksum, and the bank aggregate is CalcCheckSum over the
  -- ENTIRE six-box region (6 x 1122 bytes), not a sum of the six box sums.
  if writeBanks then
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
  end

  out = table.concat(outBuf)
  for _ = 1, 255 do
    if not looksLikeGen2(out) then break end
    setByte(outBuf, padAt, (outBuf[padAt + 1]:byte() % 255) + 1)
    out = table.concat(outBuf)
  end
  return out, note
end

return GenSave

-- src/trade_scene.c:57, src/data/ingame_trades.h:1, :184

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local InGameTradesExtract = {}

InGameTradesExtract.CACHE_SUB = "trades"
InGameTradesExtract.FILES = { "ingame_trades.lua" }

local MAIL_WORDS = 9 -- include/constants/global.h:65
local MAIL_ROW = 10
local MAIL_NONE = 255

local function name_at(rom, off, len)
  local bytes = {}
  for i = 0, len - 1 do
    local b = rom:get(off + i)
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  return TextIR.toPlain(TextIR.decode(bytes), {})
end

function InGameTradesExtract.extract(rom)
  local trades = {}
  for i = 0, Versions.INGAME_TRADE_COUNT - 1 do
    local off = Versions.INGAME_TRADES + i * Versions.INGAME_TRADE_SIZE
    local ivs = {}
    for s = 0, 5 do ivs[s + 1] = rom:get(off + 0x0E + s) end
    local conditions = {}
    for c = 0, 4 do conditions[c + 1] = rom:get(off + 0x1C + c) end
    local mailNum = rom:get(off + 0x2A)
    trades[i] = {
      nickname = name_at(rom, off, 11),
      species = rom:u16(off + 0x0C),
      ivs = ivs,
      abilityNum = rom:get(off + 0x14),
      otId = rom:u32(off + 0x18),
      conditions = conditions,
      personality = rom:u32(off + 0x24),
      heldItem = rom:u16(off + 0x28),
      mailNum = mailNum ~= MAIL_NONE and mailNum or nil,
      otName = name_at(rom, off + 0x2B, 11),
      otGender = rom:get(off + 0x36),
      sheen = rom:get(off + 0x37),
      requestedSpecies = rom:u16(off + 0x38),
    }
  end
  local mail = {}
  for m = 0, Versions.INGAME_TRADE_MAIL_COUNT - 1 do
    local words = {}
    for w = 0, MAIL_WORDS - 1 do
      words[w + 1] = rom:u16(Versions.INGAME_TRADE_MAIL + (m * MAIL_ROW + w) * 2)
    end
    mail[m] = words
  end
  return { trades = trades, mail = mail }
end

function InGameTradesExtract.run(rom, cache, opts)
  opts = opts or {}
  local serialize = require("src.import.gba.extract_scripts").serialize_lua
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. InGameTradesExtract.CACHE_SUB
  local pack = InGameTradesExtract.extract(rom)
  cache:write(root .. "/ingame_trades.lua", "return " .. serialize(pack) .. "\n")
  return pack
end

return InGameTradesExtract

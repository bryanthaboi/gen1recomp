-- The in-game trades (engine/events/npc_trade.asm, data/events/npc_trades.asm).
--
-- Six of them, one per NPC_TRADE_* constant, reached by the `trade` script
-- command.  Each row names the mon the NPC wants, the mon it hands over, and
-- everything that mon arrives wearing: its nickname, its DVs, its held item,
-- its original trainer's name and ID, and which gender of the requested mon it
-- will accept.
--
-- love-free: the conversation is src/ui/gen2/TradeMenu.lua, this is the rules.
--
-- Facts worth keeping:
--
--   * NPCTRADE_GIVEMON is what YOU hand over and NPCTRADE_GETMON what you get,
--     which is the opposite way round from the macro's own argument comment
--     ("requested mon, offered mon").  GetTradeAttr reads them by name, so the
--     comment is the only thing that is backwards.
--   * The row's DVs are TWO RAW BYTES, not a number: attack/defense in the
--     high and low nibbles of the first, speed/special of the second.  The
--     mon's gender and shininess fall straight out of them, which is why every
--     one of these trades hands over the same mon to every player.
--   * The OT ID is stored little-endian in the table and byte-swapped into the
--     party struct (Trade_CopyTwoBytesReverseEndian), so the number the table
--     holds IS the ID the player sees.
--   * `trade` writes no wScriptVar.  Every outcome -- the refusal, the wrong
--     mon, the completed trade -- prints its line and returns, and the script
--     after it carries on either way.
--   * The trade is one-shot, tracked in wTradeFlags by the trade's own id.  A
--     second visit prints TRADE_DIALOG_AFTER and nothing else, which is the
--     check that happens BEFORE the intro line.
--   * ComputeNPCTrademonStats runs at the END, on the mon that just landed in
--     the last party slot: the received mon keeps the LEVEL of the one handed
--     over and recomputes its stats from the new species' bases.

local Mail = require("src.core.gen2.Mail")
local Mon = require("src.battle.gen2.Mon")

local NpcTrade = {}

-- constants/npc_trade_constants.asm
NpcTrade.NUM_NPC_TRADES = 6
NpcTrade.TRADE_GENDER_EITHER = "TRADE_GENDER_EITHER"
NpcTrade.TRADE_GENDER_MALE = "TRADE_GENDER_MALE"
NpcTrade.TRADE_GENDER_FEMALE = "TRADE_GENDER_FEMALE"

-- The outcomes, which are also the TRADE_DIALOG_* rows PrintTradeText picks.
NpcTrade.DIALOG_INTRO = "TRADE_DIALOG_INTRO"
NpcTrade.DIALOG_CANCEL = "TRADE_DIALOG_CANCEL"
NpcTrade.DIALOG_WRONG = "TRADE_DIALOG_WRONG"
NpcTrade.DIALOG_COMPLETE = "TRADE_DIALOG_COMPLETE"
NpcTrade.DIALOG_AFTER = "TRADE_DIALOG_AFTER"

-- data/generated/events.lua `trades`, 1-based over the 0-based NPC_TRADE_*.
function NpcTrade.row(eventTables, id)
  local rows = type(eventTables) == "table" and eventTables.trades
  if type(rows) ~= "table" then return nil end
  return rows[(tonumber(id) or 0) + 1]
end

-- wTradeFlags, a bit per trade id.  Save-side it is a plain set.
function NpcTrade.done(save, id)
  local flags = save and save.tradeFlags
  return (flags and flags[tonumber(id) or -1]) == true
end

function NpcTrade.markDone(save, id)
  if not save then return end
  save.tradeFlags = save.tradeFlags or {}
  save.tradeFlags[tonumber(id) or 0] = true
end

-- The row's two DV bytes as the port's named-DV table.  `dn attack, defense`
-- then `dn speed, special` -- the same packing wild mons use.
function NpcTrade.dvs(row)
  local raw = (row and row.dvs) or {}
  local dvs = {
    attack = math.floor((raw[1] or 0) / 16),
    defense = (raw[1] or 0) % 16,
    speed = math.floor((raw[2] or 0) / 16),
    special = (raw[2] or 0) % 16,
  }
  dvs.hp = Mon.hpDV(dvs)
  return dvs
end

-- NPCTRADE_ITEM is an item id BYTE (data/events/npc_trades.asm's `db \5, \6,
-- \7` tail), and DoNPCTrade copies that byte straight into wPartyMon1Item of
-- the last party slot, so the received mon wears it like any other held item.
-- Everywhere else in this port a held item is a KEY of data/generated/items.lua
-- -- wild base data, trainer party mons and `givepokemail` are named at
-- extraction, and `givepoke` names its own byte at runtime through World's
-- itemByIndex -- so the byte is named here too and nothing downstream has to
-- know the row is raw.  A row item of 0 is NO_ITEM.  A cache that already
-- carries the name passes straight through.
function NpcTrade.item(data, row)
  local raw = row and row.item
  if raw == nil or raw == 0 then return nil end
  if type(raw) == "string" then return raw end
  local items = data and data.items
  if type(items) == "table" then
    for id, def in pairs(items) do
      if type(def) == "table" and def.index == raw then return id end
    end
  end
  local order = data and data.constants and data.constants.itemOrder
  return (order and order[raw]) or nil
end

-- CheckTradeGender.  EITHER takes anything; the other two run GetGender on the
-- mon the player picked and refuse on a mismatch.  A genderless species
-- ("unknown") satisfies neither, which is the `jr nz` / `jr z` pair falling to
-- .not_matching.
function NpcTrade.genderOk(row, mon)
  local want = row and row.gender
  if not want or want == NpcTrade.TRADE_GENDER_EITHER then return true end
  local gender = mon and mon.gender
  if want == NpcTrade.TRADE_GENDER_MALE then return gender == "male" end
  return gender == "female"
end

-- The three refusals NPCTrade checks in order, before any swap happens.
-- Answers the TRADE_DIALOG_* the conversation should print, or nil for "go
-- ahead".
function NpcTrade.check(row, mon)
  if not row then return NpcTrade.DIALOG_CANCEL end
  if not mon then return NpcTrade.DIALOG_CANCEL end
  if mon.species ~= row.give then return NpcTrade.DIALOG_WRONG end
  if not NpcTrade.genderOk(row, mon) then return NpcTrade.DIALOG_WRONG end
  return nil
end

-- DoNPCTrade: the mon at `index` leaves the party and the row's mon takes the
-- last slot, at the SAME level, with the row's DVs, nickname, held item, OT
-- name and OT ID.  Answers the two mons, given away first.
--
-- RemoveMonFromPartyOrBox runs before TryAddMonToParty, so the incoming mon
-- lands in the slot vacated by the outgoing one only when that was the last
-- slot -- otherwise the party closes up and the new mon goes on the end.  That
-- reordering is visible in the party list, so it is reproduced rather than
-- tidied into an in-place swap.
function NpcTrade.perform(data, save, row, index)
  local party = save and save.party
  local given = party and party[index]
  if not (data and given and row) then return nil end
  local received = Mon.new(data, row.get, given.level, {
    dvs = NpcTrade.dvs(row),
    nickname = row.nickname,
    item = NpcTrade.item(data, row),
  })
  if not received then return nil end
  -- `ot` is what Breeding reads and `otName` what the summary screen prints;
  -- both are set rather than picking one, because the two halves of the port
  -- already disagree and a traded mon has to answer both.
  received.ot, received.otName = row.otName, row.otName
  received.otId = row.otId
  table.remove(party, index)
  -- RemoveMonFromPartyOrBox's "Mail time!" tail.  NPCTrade itself has no mail
  -- check -- unlike the Day-Care and the PC, it will trade a mon holding a
  -- letter away -- so the shift here is what stops the mon that closes up into
  -- that slot inheriting it (src/core/gen2/Mail.lua).
  Mail.removeSlot(save, index)
  party[#party + 1] = received
  -- TryAddMonToParty's SetSeenAndCaughtMon (engine/pokemon/move_mon.asm:196),
  -- which the `predef` at engine/events/npc_trade.asm:168 runs like any other.
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  save.pokedex.seen[received.species] = true
  save.pokedex.caught[received.species] = true
  return given, received
end

return NpcTrade

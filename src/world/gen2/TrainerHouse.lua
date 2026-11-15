-- The Viridian Trainer House: the one battle a day against CAL in the
-- basement's TRAINING HALL (maps/TrainerHouseB1F.asm).
--
-- The conversation itself is script bytecode and stays in the cache: the
-- coord_event on the doorway cell runs TrainerHouseReceptionistScript, which
-- checks ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY, asks `special TrainerHouse`
-- whose opponent it is, walks the player into the room and starts the battle.
-- What that script needs from the port is the three compiled routines behind
-- it, and all three are about the SAME question: whether a Mystery Gift trade
-- has left a custom trainer in SRAM.
--
--   TrainerHouse            engine/events/specials.asm -- reads
--                           sMysteryGiftTrainerHouseFlag into wScriptVar, so
--                           the script picks CAL2 (the visitor) or CAL3 (the
--                           house's own trainer).
--   ReadTrainerParty        engine/battle/read_trainer_party.asm -- CAL2 is
--                           the ONLY trainer in the game whose party does not
--                           come from data/trainers/parties.asm.  Its `.cal2`
--                           arm reads sMysteryGiftTrainer as a
--                           TRAINERTYPE_MOVES party instead.
--   GetTrainerName          same file -- and CAL is the only class whose name
--                           is not read from the parties table either: with
--                           the flag set it is copied out of
--                           sMysteryGiftPartnerName.
--
-- MYSTERY GIFT IS OUT OF SCOPE (it is one of the six peripheral stubs in
-- src/script/gen2/Specials.lua: the trade rides the Game Boy's infrared port
-- into a second cartridge, and there is no second cartridge here).  So the
-- flag is permanently clear, which is exactly the state of a cartridge that
-- has never been linked, and every one of the three routines above takes its
-- own no-custom-data arm.  That fallback is what this module ports:
--
--   * the script asks once before the walk-in and once at the battle, gets
--     FALSE both times, and fights CAL3 -- MEGANIUM, TYPHLOSION and FERALIGATR
--     at level 50, the strongest of the three CAL rows;
--   * a CAL2 lookup that reaches here anyway is answered with CAL3 rather than
--     with parties.asm's CAL (2) row, because that row is DEAD DATA on the
--     cart: `ReadTrainerParty` branches to SRAM before it ever indexes the
--     table, so handing back BAYLEEF/QUILAVA/CROCONAW at level 30 would be a
--     team no cartridge ever fields;
--   * the name is the parties table's own "CAL".
--
-- The once-a-day gate is not here: ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY is a
-- wDailyFlags1 bit like Kurt's, so the script's own setflag is the whole of
-- the write and src/core/gen2/Apricorns.lua's daily reset is the whole of the
-- clear.  The id below is for readers and for the test that pins the pair.

local Trainers = require("src.world.gen2.Trainers")

local EngineFlags = require("src.core.gen2.EngineFlags")
local TrainerHouse = EngineFlags.expose({}, { "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY" })

-- constants/trainer_constants.asm: the CAL class and its three members.  CAL1
-- is the Route 27 battle, CAL2 the Mystery Gift visitor, CAL3 the house's own.
TrainerHouse.CAL = 12
TrainerHouse.CAL1, TrainerHouse.CAL2, TrainerHouse.CAL3 = 1, 2, 3

-- sMysteryGiftTrainerHouseFlag (ram/sram.asm), the byte a completed Mystery
-- Gift trade leaves behind.  STUB, and a deliberate one: nothing in this port
-- can set it, because nothing in this port can run the infrared trade that
-- writes it (engine/link/mystery_gift.asm).  Kept as a function rather than as
-- a constant `false` so the day Mystery Gift lands there is one place to teach
-- about save.mysteryGift, and so the two readers below cannot drift apart.
function TrainerHouse.hasCustomTrainer(save)
  local gift = type(save) == "table" and save.mysteryGift or nil
  return (gift and gift.trainerHouse) and true or false
end

-- ReadTrainerParty's `cp CAL / cp CAL2` pair, as the question a caller with a
-- class and a member can ask: which member should actually be loaded.  Only
-- CAL2 is ever redirected, and only when there is no custom trainer to redirect
-- it to -- with one in SRAM the cart reads the party out of SRAM and this
-- would have nothing to say about it either.
function TrainerHouse.resolveMember(save, class, member)
  if class == TrainerHouse.CAL and member == TrainerHouse.CAL2
      and not TrainerHouse.hasCustomTrainer(save) then
    return TrainerHouse.CAL3
  end
  return member
end

-- GetTrainerName's CAL arm.  Returns the name the SRAM copy would have
-- supplied, or nil for "fall through to the parties table", which is what
-- `.not_cal2` does.  nil rather than "CAL" on purpose: the caller already has
-- the table, and inventing the answer here would hide a lookup that failed.
function TrainerHouse.customName(save, class)
  if class ~= TrainerHouse.CAL then return nil end
  if not TrainerHouse.hasCustomTrainer(save) then return nil end
  local gift = save and save.mysteryGift
  return gift and gift.partnerName or nil
end

-- The pair of lookups the World hands to the VM, with the CAL2 redirect
-- applied.  `trainerData` is the cache's trainers table.
function TrainerHouse.lookup(trainerData, save, class, member)
  return Trainers.lookup(trainerData, class,
    TrainerHouse.resolveMember(save, class, member))
end

function TrainerHouse.name(trainerData, save, class, member)
  local custom = TrainerHouse.customName(save, class)
  if custom then return custom end
  local entry = TrainerHouse.lookup(trainerData, save, class, member)
  return entry and entry.name or nil
end

-- The daily gate, for a reader holding nothing but a save file.  The script
-- owns both sides of it in game (checkflag / setflag), so neither of these has
-- a call site in the engine: they exist so the test can state the rule, and so
-- a future rematch feature has one name for the bit rather than the number 86
-- written out again.
function TrainerHouse.foughtToday(save)
  local flags = type(save) == "table" and save.engineFlags or nil
  return (flags and flags[TrainerHouse.ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY])
    == true
end

return TrainerHouse

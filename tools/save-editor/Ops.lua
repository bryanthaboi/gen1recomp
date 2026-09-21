-- Every mutation the save editor can make to a loaded save, behind one
-- funnel: Ops.mark() is the ONLY thing that sets S.dirty, and it always
-- writes the status line at the same time.  That is rule 2 of the design
-- spec (SaveEditor.dc.html) -- dirty state has to be visible from any tab,
-- and no branch may silently no-op.  Panels above this file only lay out
-- pixels and dispatch; the rules live here, which is also what makes them
-- testable without a window (tests/save_editor_*).
--
-- Clamps mirror the running game, not the UI: level 1-100, DV 0-15, party 6
-- (src/pokemon/Party), box 20 x 12 (src/pokemon/Boxes), money 0-999999,
-- item stack 99 and the configured bag capacity (20 by default;
-- src/inventory/Bag).

local Pokemon = require("src.pokemon.Pokemon")
local PartyMod = require("src.pokemon.Party")
local BoxesMod = require("src.pokemon.Boxes")
local Bag = require("src.inventory.Bag")
local MonOps = require("MonOps")
local Charmap = require("src.save_convert.data.charmap")
local Gen = require("Gen")

local Ops = {}
local G3 = require("Game3Adapter")
local boxInsert, boxRemove

Ops.MONEY_MAX = 999999
Ops.STACK_MAX = 99
function Ops.stackMax(S)
  return Gen.ofState(S) == 3 and 999 or Ops.STACK_MAX
end

local function moveId(mon, slot)
  local move = mon.moves and mon.moves[slot]
  return type(move) == "table" and (move.moveId or move.id) or move
end
Ops.ARM_SECONDS = 2.5
-- The in-game naming screen caps a nickname at 10 glyphs
-- (BattleState:askNicknameUI / src/ui/NamingScreen.lua maxLen = 10); the
-- editor mirrors that cap instead of inventing its own.
Ops.NICKNAME_MAX = 10

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end
Ops.clamp = clamp

local function stampNewMon(S, mon)
  if Gen.ofState(S) == 3 then
    mon.ot = (S.save.player and S.save.player.name) or S.save.name or "RED"
    mon.otId = (S.save.player and S.save.player.id) or S.save.trainerId or 0
  elseif Gen.ofState(S) == 2 then
    require("src.battle.gen2.Mon").stampOT(S.save, mon)
  else
    mon.ot = S.save.player and S.save.player.name or "RED"
    mon.otId = S.save.player and S.save.player.id or 0
  end
  return mon
end

local function createMon(S, species, level)
  local mon = MonOps.create(S.data, species, level, Gen.ofState(S))
  return stampNewMon(S, mon)
end

local function partySlot(S, mon)
  for i, member in ipairs(S.save.party or {}) do
    if member == mon then return i end
  end
end

-- Portrait mail (and CheckPokeMail) store species on the letter, not the mon.
local function partyMailEntry(S, slot)
  local Mail = require("src.core.gen2.Mail")
  return Mail.state(S.save).party[slot]
end

local function syncPartyMailSpecies(S, mon)
  if Gen.ofState(S) ~= 2 then return end
  local slot = partySlot(S, mon)
  if not slot then return end
  local entry = partyMailEntry(S, slot)
  if entry then entry.species = mon.species end
end

local function syncPartyMailHeldItem(S, mon, prevItem, newItem)
  if Gen.ofState(S) ~= 2 then return end
  local slot = partySlot(S, mon)
  if not slot then return end
  local Mail = require("src.core.gen2.Mail")
  if Mail.isMail(newItem) then
    local prev = partyMailEntry(S, slot)
    local player = S.save.player or {}
    Mail.set(S.save, slot, Mail.entry(
      newItem,
      prev and prev.message or "",
      tostring(mon.otName or mon.ot or player.name or ""):sub(1, Mail.AUTHOR_LENGTH),
      mon.otId or player.id or 0,
      mon.species))
    return
  end
  if Mail.isMail(prevItem) or partyMailEntry(S, slot) then
    Mail.clear(S.save, slot)
  end
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return nil
end

-- ------------------------------------------------------------ the funnel
-- Mark the save dirty and say what changed.  Also disarms any pending
-- destructive confirmation: doing something else is an implicit "no".
function Ops.mark(S, msg)
  S.dirty = true
  S.status = msg or S.status
  S.armed = nil
  -- A fresh edit invalidates any prior "leave anyway" arming: quitting,
  -- closing or opening another file has to be confirmed again, so a stale
  -- confirmation from an earlier round of edits cannot discard these.
  S._quitArmed = false
  S._openArmed = false
  return true
end

-- Status-only: used by the branches that refuse (party full, box full, no
-- cell selected).  A refusal must still speak, it must just not dirty.
function Ops.say(S, msg)
  S.status = msg
  return false
end

-- Two-click confirm for destructive verbs.  The first call arms `id` and
-- returns false; a second call with the same id inside ARM_SECONDS returns
-- true and disarms.  Panels label the button through Ops.armLabel.
function Ops.arm(S, id, msg)
  local t = now()
  if S.armed == id then
    local at = S.armedAt
    if not (t and at and (t - at) > Ops.ARM_SECONDS) then
      S.armed, S.armedAt = nil, nil
      return true
    end
  end
  S.armed, S.armedAt = id, t
  S.status = msg
  return false
end

-- The label a destructive button should carry right now.
function Ops.armLabel(S, id, label)
  if S.armed ~= id then return label end
  local t, at = now(), S.armedAt
  if t and at and (t - at) > Ops.ARM_SECONDS then
    S.armed, S.armedAt = nil, nil
    return label
  end
  return "Confirm?"
end

function Ops.disarm(S)
  S.armed, S.armedAt = nil, nil
end

-- ------------------------------------------------------------------ party
function Ops.selectParty(S, index)
  local mon = S.save.party[index]
  if not mon then return false end
  S.selectedParty = index
  S.editingMon = mon
  S.status = ("Selected party slot %d (%s)"):format(index, mon.species)
  return true
end

function Ops.partyAdd(S)
  if #S.save.party >= PartyMod.MAX then
    return Ops.say(S, ("Party is full (%d/%d)"):format(#S.save.party, PartyMod.MAX))
  end
  local species = S.cat.species[1]
  local mon = createMon(S, species, 5)
  table.insert(S.save.party, mon)
  S.selectedParty = #S.save.party
  S.editingMon = mon
  return Ops.mark(S, ("Added %s Lv5 to party slot %d"):format(species, #S.save.party))
end

function Ops.partyRemove(S)
  local index = S.selectedParty
  local mon = S.save.party[index]
  if not mon then return Ops.say(S, "No party slot selected") end
  if not Ops.arm(S, "party-remove",
      ("Remove %s from slot %d? Click again to confirm"):format(mon.species, index)) then
    return false
  end
  table.remove(S.save.party, index)
  -- sPartyMail is keyed by party slot, not by mon: dropping a member without
  -- shifting letters hands the next mon someone else's mail.
  if Gen.ofState(S) == 2 then
    require("src.core.gen2.Mail").removeSlot(S.save, index)
  end
  if S.editingMon == mon then S.editingMon = nil end
  S.selectedParty = clamp(index, 1, math.max(#S.save.party, 1))
  S.editingMon = S.save.party[S.selectedParty]
  return Ops.mark(S, ("Removed %s from the party"):format(mon.species))
end

-- delta is -1 (up) or +1 (down); the selection follows the mon.
function Ops.partyMove(S, delta)
  local i = S.selectedParty
  local j = i + delta
  local party = S.save.party
  if not (party[i] and party[j]) then
    return Ops.say(S, delta < 0 and "Already the lead mon" or "Already the last mon")
  end
  party[i], party[j] = party[j], party[i]
  if Gen.ofState(S) == 2 then
    require("src.core.gen2.Mail").swapSlots(S.save, i, j)
  end
  S.selectedParty = j
  return Ops.mark(S, ("Moved %s to slot %d"):format(party[j].species, j))
end

-- ------------------------------------------------------- selected mon edits
-- All four of these round-trip through MonOps, which recomputes stats from
-- the Gen1 formula, so the inspector can never show illegal HP.
function Ops.setLevel(S, mon, level)
  if not mon then return false end
  local want = clamp(math.floor(level), 1, 100)
  if want == mon.level then
    return Ops.say(S, want == 1 and "Level is already 1" or "Level is already 100")
  end
  MonOps.setLevel(S.data, mon, want, Gen.ofState(S))
  return Ops.mark(S, ("%s is now Lv%d"):format(mon.species, mon.level))
end

-- A catalog id is only usable as a real mon when its record carries what the
-- Gen1 formulas read: Stats.calc indexes baseStats.<stat> unconditionally
-- (src/pokemon/Stats.lua, home/move_mon.asm CalcStat), because the asm's
-- BaseStats is a fixed 151-entry table and every row is complete.  The
-- editor's list is NOT that table -- it is every key in Data.pokemon after
-- the mod merge -- and a mod loaded at api 1 can leave a partial record in
-- there, since the schema violation downgrades to a warning rather than a
-- rejection (src/mods/Schemas.lua R.pokemon).  So the editor tests the record
-- instead of trusting the list: without this, picking such a species walked
-- Stats.calc into `speciesDef.baseStats[key]` on a nil and took the window
-- down (#541).
local BASE_STAT_KEYS_G1 = { "hp", "attack", "defense", "speed", "special" }
local BASE_STAT_KEYS_G2 = {
  "hp", "attack", "defense", "speed", "specialAttack", "specialDefense",
}

local function baseStatsComplete(bs, keys)
  for _, key in ipairs(keys) do
    if type(bs[key]) ~= "number" then return false end
  end
  return true
end

function Ops.speciesUsable(S, id)
  if Gen.ofState(S) == 3 then
    local def = id and S.data and S.data.pokemon and (S.data.pokemon[id] or (type(id) == "number" and S.data.pokemon[id]))
    if type(def) == "table" and (def.speciesId or def.species or def.name) then return true end
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    if okP and Pokemon then
      local spId = tonumber(id) or (Pokemon.speciesFromName and Pokemon.speciesFromName(tostring(id)))
      if spId and Pokemon.name(spId) then return true end
    end
    return false
  end
  local def = id and S.data.pokemon[id]
  if type(def) ~= "table" or type(def.baseStats) ~= "table" then return false end
  return baseStatsComplete(def.baseStats, BASE_STAT_KEYS_G1)
      or baseStatsComplete(def.baseStats, BASE_STAT_KEYS_G2)
end

-- The one funnel every species change goes through (the picker, the stepper,
-- anything later).  MonOps asserts and recalculates, so an unusable record is
-- refused before it runs, and the round trip itself is fenced: a record that
-- passes the check above but still trips a formula has to leave the mon
-- exactly as it was and speak in the status bar, not take the editor with it.
function Ops.setSpecies(S, mon, id)
  if not mon then return false end
  if id == mon.species then
    return Ops.say(S, ("Already a %s"):format(tostring(id)))
  end
  if not Ops.speciesUsable(S, id) then
    return Ops.say(S, ("%s has no usable base stats,  cannot assign it")
      :format(tostring(id)))
  end
  -- MonOps.recalc replaces mon.stats with a fresh table rather than editing
  -- it in place, so holding the old reference is a real rollback.
  local wasSpecies, wasLevel, wasExp, wasExperience = mon.species, mon.level, mon.exp, mon.experience
  local wasStats, wasHp, wasName = mon.stats, mon.hp, mon.name
  local wasTypes, wasGender, wasShiny, wasUnown, wasMaxHp =
    mon.types, mon.gender, mon.shiny, mon.unownLetter, mon.maxHp
  local ok, err = pcall(MonOps.setSpecies, S.data, mon, id, Gen.ofState(S))
  if not ok then
    mon.species, mon.level, mon.exp, mon.experience = wasSpecies, wasLevel, wasExp, wasExperience
    mon.stats, mon.hp, mon.name = wasStats, wasHp, wasName
    mon.types, mon.gender, mon.shiny, mon.unownLetter, mon.maxHp =
      wasTypes, wasGender, wasShiny, wasUnown, wasMaxHp
    return Ops.say(S, ("Could not set %s: %s"):format(tostring(id), tostring(err)))
  end
  syncPartyMailSpecies(S, mon)
  return Ops.mark(S, ("Species set to %s"):format(id))
end

-- Kept for the keyboard and test path; the inspector opens the searchable
-- picker instead of walking the catalog one arrow at a time (#541).  Skips
-- ids Ops.setSpecies would refuse, so one bad record cannot park the walk.
function Ops.stepSpecies(S, mon, delta)
  if not mon then return false end
  local list = S.cat.species
  local n = #list
  if n == 0 then return Ops.say(S, "No species in the catalog") end
  local idx = 1
  for i, id in ipairs(list) do
    if id == mon.species then idx = i break end
  end
  for step = 1, n do
    local nextId = list[((idx - 1 + delta * step) % n) + 1]
    if nextId ~= mon.species and Ops.speciesUsable(S, nextId) then
      return Ops.setSpecies(S, mon, nextId)
    end
  end
  return Ops.say(S, "No other species in the catalog can be assigned")
end

-- Search predicate behind the picker's field: the id, the display name, and a
-- bare dex number ("25" finds PIKACHU), all case-insensitive and plain (no
-- pattern magic, so a "." typed by accident matches a literal dot).
function Ops.speciesMatches(S, id, query)
  if not query or query == "" then return true end
  local q = tostring(query):lower()
  if id:lower():find(q, 1, true) then return true end
  local def = S.data.pokemon[id]
  local name = def and def.name
  if name and tostring(name):lower():find(q, 1, true) then return true end
  local dex = tonumber(def and def.dex)
  -- dex matches exactly, in either the bare or the padded form the inspector
  -- prints ("25" and "025" both find PIKACHU).  A substring match here would
  -- pull in ELECTABUZZ (#125) on a search for 25, which reads as a bug.
  return dex ~= nil and (q == tostring(dex) or q == ("%03d"):format(dex))
end

function Ops.speciesSearch(S, query)
  local out = {}
  for _, id in ipairs(S.cat.species) do
    if Ops.speciesMatches(S, id, query) then out[#out + 1] = id end
  end
  -- Rank hits so a typed prefix ("pika") puts PIKACHU above mid-string
  -- noise; empty query keeps the catalog's A-Z order.
  if query and tostring(query) ~= "" then
    local q = tostring(query):lower()
    local function rank(id)
      local idLower = id:lower()
      local def = S.data.pokemon[id]
      local nameLower = def and def.name and tostring(def.name):lower() or ""
      if idLower == q or nameLower == q then return 0 end
      if idLower:sub(1, #q) == q
          or (nameLower ~= "" and nameLower:sub(1, #q) == q) then
        return 1
      end
      if idLower:find(q, 1, true)
          or (nameLower ~= "" and nameLower:find(q, 1, true)) then
        return 2
      end
      return 3  -- dex-number hit
    end
    table.sort(out, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return a < b
    end)
  end
  return out
end

-- The picker is modal editor chrome, not a save mutation, so its flag lives
-- with the other view state on S (State.new).  Ops owns the door only because
-- both the inspector and App need one and neither should require the other.
-- `opened` marks the frame the picker went up: the click that opened it is
-- still live when the overlay draws later in that same frame (#541).
function Ops.openSpeciesPicker(S, Kit)
  if not S.editingMon then
    return Ops.say(S, "Pick a slot first, then choose its species")
  end
  S.speciesPicker = { query = "", offset = 0, opened = true }
  -- focus the field on open so the mobile soft keyboard rises with it (#529)
  if Kit then Kit.focus = "species-picker" end
  return true
end

-- The item catalog minus the badges, which are toggles on their own row and
-- would otherwise be "addable" into the bag as ordinary items.
function Ops.itemSearch(S, query)
  query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local out = {}
  for _, id in ipairs(S.cat.items) do
    if not Ops.isBadgeId(id)
        and (query == "" or id:lower():find(query, 1, true)) then
      out[#out + 1] = id
    end
  end
  return out
end

-- `dest` is "bag" or "pc"; the picker can flip it while open.  `opened`
-- marks the frame it went up, so the click that opened it is not also read
-- as a tap outside (the same rule the species picker follows).
function Ops.openItemPicker(S, Kit, dest)
  S.itemPicker = { query = "", offset = 0, opened = true,
    dest = dest or "bag" }
  -- focus the field on open so the mobile soft keyboard rises with it (#529)
  if Kit then Kit.focus = "item-picker" end
  return true
end

function Ops.closeItemPicker(S, Kit)
  S.itemPicker = nil
  if Kit and Kit.blur then Kit.blur() end
end

function Ops.closeSpeciesPicker(S, Kit)
  S.speciesPicker = nil
  if Kit and Kit.blur then Kit.blur() end
end

-- The Boxes panel's add flow rides the same picker (#715): instead of
-- silently dropping catalog entry #1 into the box, "+ Add mon here" and the
-- dashed empty cells open the picker in box-add mode, and the committed
-- species goes through Ops.boxAddSpecies below.  No selection is required:
-- the target is the box, not a mon.
function Ops.openBoxAddPicker(S, Kit)
  local box = Ops.boxes(S)[S.selectedBox]
  if Ops.boxSize(S, box) >= Ops.boxCapacity(S) then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, Ops.boxSize(S, box), Ops.boxCapacity(S)))
  end
  S.speciesPicker = { query = "", offset = 0, opened = true, mode = "box-add" }
  if Kit then Kit.focus = "species-picker" end  -- soft keyboard rises (#529)
  return true
end

-- Commit half of the box-add picker.  Builds the mon exactly the way
-- Ops.partyAdd does (MonOps.create at Lv5, owned by the save's player), so a
-- box mon and a party mon born in the editor are indistinguishable.
function Ops.boxAddSpecies(S, id)
  local box = Ops.boxes(S)[S.selectedBox]
  if Ops.boxSize(S, box) >= Ops.boxCapacity(S) then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, Ops.boxSize(S, box), Ops.boxCapacity(S)))
  end
  if not Ops.speciesUsable(S, id) then
    return Ops.say(S, ("%s has no usable base stats,  cannot add it")
      :format(tostring(id)))
  end
  local mon = createMon(S, id, 5)
  S.selectedBoxSlot = boxInsert(S, box, mon)
  S.editingMon = mon
  return Ops.mark(S, ("Added %s Lv5 to box %d slot %d")
    :format(id, S.selectedBox, S.selectedBoxSlot))
end

function Ops.setDv(S, mon, key, value)
  if not mon then return false end
  local want = clamp(math.floor(value), 0, 15)
  if want == mon.dvs[key] then
    return Ops.say(S, ("%s DV is already %d"):format(key, want))
  end
  MonOps.setDv(S.data, mon, key, want, Gen.ofState(S))
  return Ops.mark(S, ("%s DV %d  (HP DV now %d)"):format(key, mon.dvs[key], mon.dvs.hp))
end

-- Kept for tests and any keyboard path; the inspector opens the searchable
-- picker instead of walking the catalog one tap at a time.
function Ops.cycleMove(S, mon, slot)
  if not mon or not (S.cat and S.cat.moves and #S.cat.moves > 0) then return false end
  local moves = S.cat.moves
  local current = moveId(mon, slot)
  local idx = 0
  if current then
    for i, id in ipairs(moves) do
      if id == current then idx = i break end
    end
  end
  for step = 1, #moves do
    local nextId = moves[((idx + step - 1) % #moves) + 1]
    if Ops.moveUsable(S, nextId) then
      return Ops.setMove(S, mon, slot, nextId)
    end
  end
  return false
end

-- A move record is usable when it is a real table with a numeric PP -- the
-- same floor Catalog already uses to keep provenance scalars out of the list.
function Ops.moveUsable(S, id)
  local def = id and S.data and S.data.moves and S.data.moves[id]
  return type(def) == "table" and type(def.pp) == "number"
end

-- Search predicate behind the move picker's field: id, display name, and type
-- substring-match case-insensitively; power / accuracy match as whole numbers
-- (same plain-text / no-pattern rule as Ops.speciesMatches).
function Ops.moveMatches(S, id, query)
  if not query or query == "" then return true end
  local q = tostring(query):lower()
  if id:lower():find(q, 1, true) then return true end
  local def = S.data.moves[id]
  if type(def) ~= "table" then return false end
  local name = def.name
  if name and tostring(name):lower():find(q, 1, true) then return true end
  local typ = def.type
  if typ and tostring(typ):lower():find(q, 1, true) then return true end
  local power = tonumber(def.power)
  if power ~= nil and q == tostring(power) then return true end
  local accuracy = tonumber(def.accuracy)
  return accuracy ~= nil and q == tostring(accuracy)
end

function Ops.moveSearch(S, query)
  local out = {}
  for _, id in ipairs(S.cat.moves or {}) do
    if Ops.moveMatches(S, id, query) then out[#out + 1] = id end
  end
  -- Rank hits so a typed prefix ("sur") puts SURF above mid-string noise
  -- like ACUPRESSURE / FISSURE; empty query keeps the catalog's A-Z order.
  if query and tostring(query) ~= "" then
    local q = tostring(query):lower()
    local function rank(id)
      local idLower = id:lower()
      local def = S.data.moves[id]
      local nameLower = (type(def) == "table" and def.name)
        and tostring(def.name):lower() or ""
      if idLower == q or nameLower == q then return 0 end
      if idLower:sub(1, #q) == q
          or (nameLower ~= "" and nameLower:sub(1, #q) == q) then
        return 1
      end
      if idLower:find(q, 1, true)
          or (nameLower ~= "" and nameLower:find(q, 1, true)) then
        return 2
      end
      return 3  -- type / power / accuracy hit
    end
    table.sort(out, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return a < b
    end)
  end
  return out
end

local function canonicalMoveId(data, id)
  if not id then return nil end
  local num = tonumber(id)
  if num then return num end
  local mdef = data and data.moves and data.moves[id]
  if mdef and mdef.moveId then return tonumber(mdef.moveId) end
  local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
  if okP and PokemonG3 and PokemonG3.moveFromName then
    return PokemonG3.moveFromName(tostring(id))
  end
  return nil
end

-- One funnel for assigning a move (picker commit and cycleMove).  Refuses
-- unknown / scalar ids before MonOps asserts, and speaks in the status bar.
function Ops.setMove(S, mon, slot, id)
  if not mon then return false end
  slot = math.floor(tonumber(slot) or 0)
  if slot < 1 or slot > 4 then return false end
  local current = moveId(mon, slot)
  local curCanon = canonicalMoveId(S.data, current)
  local candCanon = canonicalMoveId(S.data, id)
  if (curCanon and candCanon and curCanon == candCanon)
      or (current and tostring(current):upper() == tostring(id):upper()) then
    return Ops.say(S, ("Move %d is already %s"):format(slot, tostring(id)))
  end
  if not Ops.moveUsable(S, id) then
    return Ops.say(S, ("%s is not a usable move,  cannot assign it")
      :format(tostring(id)))
  end
  local ok, err = pcall(MonOps.setMove, S.data, mon, slot, id)
  if not ok then
    return Ops.say(S, ("Could not set move %d: %s"):format(slot, tostring(err)))
  end
  return Ops.mark(S, ("Move %d set to %s"):format(slot, id))
end

-- Modal door for the move picker.  `slot` is which of the four move rows the
-- inspector opened; the picker writes back through Ops.setMove on commit.
function Ops.openMovePicker(S, Kit, slot)
  if not S.editingMon then
    return Ops.say(S, "Pick a slot first, then choose a move")
  end
  slot = math.floor(tonumber(slot) or 0)
  if slot < 1 or slot > 4 then
    return Ops.say(S, "Move slots are 1 through 4")
  end
  if not (S.cat and S.cat.moves and #S.cat.moves > 0) then
    return Ops.say(S, "No moves in the catalog")
  end
  S.movePicker = { query = "", offset = 0, opened = true, slot = slot }
  if Kit then Kit.focus = "move-picker" end
  return true
end

function Ops.closeMovePicker(S, Kit)
  S.movePicker = nil
  if Kit and Kit.blur then Kit.blur() end
end

function Ops.clearMove(S, mon, slot)
  if not (mon and mon.moves and mon.moves[slot]) then
    return Ops.say(S, ("Move slot %d is already empty"):format(slot))
  end
  local id = moveId(mon, slot)
  if Gen.ofState(S) == 3 then MonOps.clearMove(mon, slot) else mon.moves[slot] = nil end
  return Ops.mark(S, ("Cleared move slot %d (%s)"):format(slot, id))
end

function Ops.resetMoves(S, mon)
  if not mon then return false end
  local def = S.data.pokemon[mon.species]
  local gen = Gen.ofState(S)
  local learned
  if gen == 3 then
    learned = require("src.core.game3.pokemon").movesAtLevel(mon, mon.level)
    for slot = 1, 4 do MonOps.clearMove(mon, slot) end
  elseif gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    learned = {}
    for _, mv in ipairs(Mon.movesAtLevel(def, mon.level, S.data.moves)) do
      learned[#learned + 1] = mv.id
    end
  else
    learned = Pokemon.movesAtLevel(def, mon.level)
  end
  mon.moves = {}
  for slot, id in ipairs(learned) do
    MonOps.setMove(S.data, mon, slot, id)
  end
  return Ops.mark(S, ("Reset %s to its Lv%d learnset (%d moves)")
    :format(mon.species, mon.level, #learned))
end

function Ops.healMon(S, mon)
  if not mon then return false end
  if mon.hp == mon.stats.hp and not mon.status then
    return Ops.say(S, ("%s is already at full HP"):format(mon.species))
  end
  mon.hp = mon.stats.hp
  if mon.maxHp then mon.maxHp = mon.stats.hp end
  mon.status = nil
  for slot, mv in pairs(mon.moves or {}) do
    if Gen.ofState(S) == 3 then
      local pp = mon.maxPp and mon.maxPp[slot] or require("src.core.game3.pokemon").movePp(moveId(mon, slot))
      mon.pp = mon.pp or {}
      mon.pp[slot] = pp
      if type(mv) == "table" then mv.pp = pp end
    else
      local def = S.data.moves[mv.id]
      if def then mv.pp = def.pp + ((mv.ppUps or 0) * math.floor(def.pp / 5)) end
    end
  end
  return Ops.mark(S, ("Healed %s to %d/%d HP"):format(mon.species, mon.hp, mon.stats.hp))
end

-- ----------------------------------------------------------------- nicknames
-- Gen1 has no "is nicknamed" bit: an un-nicknamed mon is mon.nickname == nil,
-- and every display site reads `mon.nickname or def.name`
-- (src/save_convert/GenSave.lua).  The editor edits that field directly.

-- The byte length of the UTF-8 glyph starting at lead byte `b`.  Self-contained
-- so this (and eachGlyph) also runs headless under luajit, which has no `utf8`
-- standard library.
local function glyphByteLen(b)
  if b < 0x80 then return 1 end
  if b < 0xE0 then return 2 end
  if b < 0xF0 then return 3 end
  return 4
end

-- Walk `name` one UTF-8 glyph at a time; fn(glyph) returning false stops the
-- walk early and eachGlyph returns false.  Returns true when every glyph was
-- visited.  The single place that walks a name, so the count / validate /
-- sanitize paths cannot drift apart (a glyph is "é" or "♂", not one of its
-- bytes, exactly as the naming screen counts its grid cells).
local function eachGlyph(name, fn)
  local i, n = 1, #name
  while i <= n do
    local b = name:byte(i)
    local ch = name:sub(i, i + glyphByteLen(b) - 1)
    if fn(ch) == false then return false end
    i = i + #ch
  end
  return true
end

-- Glyph count, not byte count: "é" or "♂" is ONE game character, exactly as
-- the naming screen counts its grid cells and GenSave.encodeName counts a
-- charmap sequence.
function Ops.nicknameLength(name)
  local n = 0
  eachGlyph(tostring(name or ""), function() n = n + 1 end)
  return n
end

-- The set of glyphs a nickname may hold: present in BOTH the Gen1 text codec
-- charmap (so the name round-trips through a .sav) and the game's font
-- charmap (so it actually draws).  The codec alone is not enough: "@" is the
-- string-terminator byte, and "#" plus the dakuten kana have codec entries
-- but no font tile, so Font.encode (src/render/Font.lua) draws them as a
-- space -- an invisible nickname.  Only single-codepoint entries qualify:
-- multi-character macros ("<PK>", the 'd ligature) cannot be typed one
-- character at a time, so they have no place in the input gate.
-- Built once per loaded font table (a mod replacing the font rebuilds it);
-- falls back to the codec-only set when no font data is loaded (headless
-- suites that never call Data:load).
local glyphCache, glyphCacheFont
local function nameGlyphSet(S)
  local font = S and S.data and S.data.font
  if not (font and font.charmap) then return Charmap.byToken end
  if glyphCache and glyphCacheFont == font then return glyphCache end
  local set = {}
  for _, e in ipairs(font.charmap) do
    local s = e.seq
    if type(s) == "string" and s ~= "" and Charmap.byToken[s]
        and #s == glyphByteLen(s:byte(1)) then
      set[s] = true
    end
  end
  glyphCache, glyphCacheFont = set, font
  return set
end

-- True when every glyph is a legal nickname glyph (see nameGlyphSet): the
-- name can be stored in a .sav AND draws in the game.  Anything else either
-- encodes as "?" (GenSave.encodeName) or renders as a space (Font.encode),
-- which the user did not ask for, so it is refused rather than mangled.
function Ops.nicknameUsable(S, name)
  local set = nameGlyphSet(S)
  return eachGlyph(tostring(name or ""), function(ch)
    return set[ch] ~= nil
  end)
end

-- The species' display name, what an un-nicknamed mon reads as.
local function speciesName(S, species)
  local def = species and S.data.pokemon[species]
  return (def and def.name) or tostring(species or "")
end

-- The input gate for the inspector's nickname field.  Given the whole draft
-- (existing text plus this frame's keystrokes and any paste), return the
-- version the game can actually hold: every glyph kept draws in the game
-- (see nameGlyphSet) and the result never exceeds the naming screen's
-- 10-glyph cap.  Unrenderable glyphs are skipped, not used to abort the rest
-- of the string, so a paste of "PIKA€CHU" lands as "PIKACHU".  The field runs
-- this through Kit.textfield's opts.sanitize, so a blocked character never
-- appears at all.
function Ops.nicknameSanitize(S, name)
  local set = nameGlyphSet(S)
  local out, count = {}, 0
  eachGlyph(tostring(name or ""), function(ch)
    if count < Ops.NICKNAME_MAX and set[ch] then
      out[#out + 1] = ch
      count = count + 1
    end
  end)
  return table.concat(out)
end

-- One verb for both writing and clearing.  An empty field means "no nickname",
-- exactly like an empty confirm on the in-game naming screen (which falls
-- through to the species' standard name).  A name that equals the species'
-- standard name is the un-nicknamed state in this save format
-- (importedNickname in GenSave.lua maps exactly that to nil), so it is
-- normalized to nil rather than stored as a literal copy of the default.
function Ops.setNickname(S, mon, name)
  if not mon then return Ops.say(S, "Pick a slot first") end
  name = tostring(name or "")
  if name == "" then
    return Ops.clearNickname(S, mon)
  end
  if name == mon.nickname then
    return Ops.say(S, ("Already nicknamed %s"):format(name))
  end
  if name == speciesName(S, mon.species) then
    if mon.nickname == nil then
      return Ops.say(S, ("%s is already un-nicknamed"):format(mon.species))
    end
    mon.nickname = nil
    return Ops.mark(S, ("%s matches its standard name;  nickname cleared")
      :format(name))
  end
  if Ops.nicknameLength(name) > Ops.NICKNAME_MAX then
    return Ops.say(S, ("Nicknames are capped at %d characters"):format(Ops.NICKNAME_MAX))
  end
  if not Ops.nicknameUsable(S, name) then
    return Ops.say(S,
      "That name has characters the game cannot render or export cleanly")
  end
  mon.nickname = name
  return Ops.mark(S, ("Nicknamed %s \"%s\""):format(mon.species, name))
end

function Ops.clearNickname(S, mon)
  if not mon then return Ops.say(S, "Pick a slot first") end
  if mon.nickname == nil then
    return Ops.say(S, ("%s has no nickname to clear"):format(mon.species))
  end
  mon.nickname = nil
  return Ops.mark(S, ("Cleared %s's nickname"):format(mon.species))
end

-- ------------------------------------------------------------------ boxes
function Ops.boxSize(S, box)
  if Gen.ofState(S) ~= 3 then return #box end
  local count = 0
  for slot = 1, 30 do if box[slot] then count = count + 1 end end
  return count
end

boxInsert = function(S, box, mon)
  if Gen.ofState(S) ~= 3 then table.insert(box, mon); return #box end
  local wanted = S.selectedBoxSlot
  if wanted and wanted >= 1 and wanted <= 30 and not box[wanted] then box[wanted] = mon; return wanted end
  for slot = 1, 30 do if not box[slot] then box[slot] = mon; return slot end end
end

boxRemove = function(S, box, slot)
  if Gen.ofState(S) == 3 then box[slot] = nil else table.remove(box, slot) end
end

function Ops.boxCount(S)
  return Gen.boxCount(S.save)
end

function Ops.boxCapacity(S)
  return Gen.boxCapacity(S.save)
end

function Ops.boxes(S)
  return Gen.ensureBoxes(S.save)
end

function Ops.selectBox(S, index)
  S.selectedBox = clamp(index, 1, Ops.boxCount(S))
  S.selectedBoxSlot = 1
  S.save.currentBox = S.selectedBox
  if Gen.ofState(S) == 3 then S.save.storage.currentBox = S.selectedBox end
  local box = Ops.boxes(S)[S.selectedBox]
  S.status = ("Box %d  (%d/%d)"):format(S.selectedBox, Ops.boxSize(S, box), Ops.boxCapacity(S))
  return true
end

function Ops.stepBox(S, delta)
  local n = Ops.boxCount(S)
  return Ops.selectBox(S, ((S.selectedBox - 1 + delta) % n) + 1)
end

function Ops.selectBoxSlot(S, index)
  local box = Ops.boxes(S)[S.selectedBox]
  S.selectedBoxSlot = clamp(index, 1, Ops.boxCapacity(S))
  local mon = box[S.selectedBoxSlot]
  S.editingMon = mon
  S.status = mon
    and ("Selected %s Lv%d in box %d slot %d")
        :format(mon.species, mon.level, S.selectedBox, S.selectedBoxSlot)
    or ("Box %d slot %d is empty"):format(S.selectedBox, S.selectedBoxSlot)
  return true
end

-- Kept for the keyboard/test path; the Boxes panel itself goes through the
-- species picker (Ops.openBoxAddPicker -> Ops.boxAddSpecies) so the user
-- chooses what lands in the box instead of always getting catalog entry #1.
function Ops.boxAdd(S)
  local box = Ops.boxes(S)[S.selectedBox]
  if Ops.boxSize(S, box) >= Ops.boxCapacity(S) then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, Ops.boxSize(S, box), Ops.boxCapacity(S)))
  end
  local species = S.cat.species[1]
  local mon = createMon(S, species, 5)
  S.selectedBoxSlot = boxInsert(S, box, mon)
  S.editingMon = mon
  return Ops.mark(S, ("Added %s Lv5 to box %d slot %d")
    :format(species, S.selectedBox, S.selectedBoxSlot))
end

function Ops.withdraw(S)
  local box = Ops.boxes(S)[S.selectedBox]
  local mon = box[S.selectedBoxSlot]
  if not mon then return Ops.say(S, "No box slot selected") end
  if #S.save.party >= PartyMod.MAX then
    return Ops.say(S, ("Party is full (%d/%d), deposit one first")
      :format(#S.save.party, PartyMod.MAX))
  end
  if Gen.ofState(S) == 2 then
    local Boxes2 = require("src.core.gen2.Boxes")
    local ok, reason = Boxes2.canWithdraw(S.save, S.selectedBox, S.selectedBoxSlot)
    if not ok then return Ops.say(S, reason) end
    Boxes2.withdraw(S.save, S.selectedBox, S.selectedBoxSlot)
  else
    boxRemove(S, box, S.selectedBoxSlot)
    table.insert(S.save.party, mon)
  end
  S.selectedBoxSlot = clamp(S.selectedBoxSlot, 1, math.max(#Ops.boxes(S)[S.selectedBox], 1))
  S.selectedParty = #S.save.party
  return Ops.mark(S, ("Withdrew %s to party slot %d"):format(mon.species, #S.save.party))
end

function Ops.release(S)
  local box = Ops.boxes(S)[S.selectedBox]
  local mon = box[S.selectedBoxSlot]
  if not mon then return Ops.say(S, "No box slot selected") end
  if not Ops.arm(S, "box-release",
      ("Release %s permanently? Click again to confirm"):format(mon.species)) then
    return false
  end
  boxRemove(S, box, S.selectedBoxSlot)
  if S.editingMon == mon then S.editingMon = nil end
  S.selectedBoxSlot = clamp(S.selectedBoxSlot, 1, math.max(#box, 1))
  return Ops.mark(S, ("Released %s"):format(mon.species))
end

-- Follows BoxesMod.deposit: fills the current box first, then the next box
-- with room, and says where the mon actually landed.
function Ops.deposit(S)
  local i = S.selectedParty
  local mon = S.save.party[i]
  if not mon then return Ops.say(S, "No party slot selected") end
  if Gen.ofState(S) == 2 then
    local Boxes2 = require("src.core.gen2.Boxes")
    local boxIndex = S.selectedBox or S.save.currentBox or 1
    local ok, reason = Boxes2.canDeposit(S.save, i, boxIndex)
    if not ok then return Ops.say(S, reason) end
    Boxes2.deposit(S.save, i, boxIndex)
    S.selectedParty = clamp(i, 1, math.max(#S.save.party, 1))
    S.selectedBox = boxIndex
    if S.editingMon == mon then S.editingMon = nil end
    return Ops.mark(S, ("Deposited %s into box %d"):format(mon.species, boxIndex))
  end
  if Gen.ofState(S) == 3 then
    local boxes = Ops.boxes(S)
    local first = S.selectedBox or S.save.currentBox or 1
    for offset = 0, 13 do
      local b = ((first - 1 + offset) % 14) + 1
      if Ops.boxSize(S, boxes[b]) < 30 then
        local slot = boxInsert(S, boxes[b], mon)
        table.remove(S.save.party, i)
        S.selectedParty = clamp(i, 1, math.max(#S.save.party, 1))
        S.selectedBox, S.selectedBoxSlot = b, slot
        if S.editingMon == mon then S.editingMon = nil end
        return Ops.mark(S, ("Deposited %s into box %d"):format(mon.species, b))
      end
    end
    return Ops.say(S, "Every box is full")
  end
  local boxNum = BoxesMod.deposit(S.save, mon)
  if not boxNum then
    return Ops.say(S, "Every box is full,  release something first")
  end
  table.remove(S.save.party, i)
  S.selectedParty = clamp(i, 1, math.max(#S.save.party, 1))
  S.selectedBox = boxNum
  if S.editingMon == mon then S.editingMon = nil end
  return Ops.mark(S, ("Deposited %s into box %d"):format(mon.species, boxNum))
end

-- ------------------------------------------------------------------ items
function Ops.addMoney(S, delta)
  local have = Gen.money(S.save)
  local want = clamp(have + delta, 0, Ops.MONEY_MAX)
  if want == have then
    return Ops.say(S, delta < 0 and "Money is already $0"
      or ("Money is already capped at $%d"):format(Ops.MONEY_MAX))
  end
  Gen.setMoney(S.save, want)
  return Ops.mark(S, ("Money set to $%d"):format(want))
end

function Ops.maxMoney(S)
  return Ops.addMoney(S, Ops.MONEY_MAX)
end

-- ram/wram.asm:1908 wPlayerCoins is two BCD bytes, so 9999 is the ceiling on
-- both generations (misc_constants.asm:47 MAX_COINS).
Ops.COIN_MAX = 9999

function Ops.addCoins(S, delta)
  local have = Gen.coins(S.save)
  local want = clamp(have + delta, 0, Ops.COIN_MAX)
  if want == have then
    return Ops.say(S, delta < 0 and "Coins are already 0"
      or ("Coins are already capped at %d"):format(Ops.COIN_MAX))
  end
  Gen.setCoins(S.save, want)
  return Ops.mark(S, ("Coins set to %d"):format(want))
end

function Ops.maxCoins(S)
  return Ops.addCoins(S, Ops.COIN_MAX)
end

local function itemQty(inv, id)
  if not inv or id == nil then return 0 end
  local val = inv[id]
  if type(val) == "number" then return val end
  if type(val) == "table" then
    return tonumber(val.qty or val.quantity or val.count or val[2]) or 0
  end
  if val == true then return 1 end
  return tonumber(val) or 0
end
Ops.itemQty = itemQty

local function changeG3(S, pc, id, quantity)
  if not id then return Ops.say(S, "Pick an item first") end
  if not G3.change(S.data, S.save, pc, { { id = id, qty = quantity } }) then
    return Ops.say(S, "Item change refused: quantity or storage capacity")
  end
  return Ops.mark(S, ("%s x%d%s"):format(tostring(id), quantity, pc and " in PC storage" or ""))
end

local function maxG3(S, pc)
  local changes = {}
  for id, qty in pairs(pc and S.save.pcItems or S.save.inventory) do
    if type(qty) == "number" and qty > 0 and qty < 999 and Ops.itemStacks(S, id) then
      changes[#changes + 1] = { id = id, qty = 999 }
    end
  end
  if #changes == 0 then return Ops.say(S, "Every stack is already maxed") end
  if not G3.change(S.data, S.save, pc, changes) then return Ops.say(S, "Item changes refused") end
  return Ops.mark(S, ("Maxed %d stacks to x999"):format(#changes))
end

function Ops.addToBag(S, id)
  if not id then return Ops.say(S, "Pick an item first") end
  S.save.inventory = S.save.inventory or {}
  if Gen.ofState(S) == 3 then return changeG3(S, false, id, G3.quantity(S.data, S.save, false, id) + 1) end
  local pocket = Bag.pocketOf(id, S.data)
  local capacity = Bag.capacity(S.data, pocket)
  if Bag.add(S.save, id, 1, S.data) then
    return Ops.mark(S, ("Added %s to the bag (%d/%d %s slots)")
      :format(tostring(id), Bag.slots(S.save, S.data, pocket), capacity, pocket))
  end
  return Ops.say(S, ("Bag is full (%d/%d %s slots)")
    :format(Bag.slots(S.save, S.data, pocket), capacity, pocket))
end

function Ops.bagAdjust(S, id, delta)
  if not id then return Ops.say(S, "No bag row selected") end
  S.save.inventory = S.save.inventory or {}
  local have = itemQty(S.save.inventory, id)
  if Gen.ofState(S) == 3 then return changeG3(S, false, id, math.max(0, G3.quantity(S.data, S.save, false, id) + delta)) end
  if delta > 0 then
    if have >= Ops.stackMax(S) then
      return Ops.say(S, ("%s is already at x%d"):format(tostring(id), Ops.stackMax(S)))
    end
    Bag.add(S.save, id, delta, S.data)
  else
    Bag.remove(S.save, id, -delta)
    if not S.save.inventory[id] then
      return Ops.mark(S, ("Removed the last %s from the bag"):format(tostring(id)))
    end
  end
  return Ops.mark(S, ("%s x%d"):format(tostring(id), itemQty(S.save.inventory, id)))
end

function Ops.bagDrop(S, id)
  if not id then return Ops.say(S, "No bag row selected") end
  S.save.inventory = S.save.inventory or {}
  local qty = itemQty(S.save.inventory, id)
  if Gen.ofState(S) == 3 then return changeG3(S, false, id, 0) end
  Bag.remove(S.save, id, qty)
  return Ops.mark(S, ("Dropped all %d %s"):format(qty, tostring(id)))
end

-- home/list_menu.asm:474 IsKeyItem (Gen 1 prints no count for key items or
-- HMs); ram/wram.asm:3115 wKeyItems (Gen 2 stores that pocket as bare ids)
-- and engine/items/tmhm.asm:390 prints no count for an HM.
function Ops.itemStacks(S, id)
  if not id then return false end
  if Gen.ofState(S) == 3 then
    local id3 = G3.itemId(S.data, id)
    local info = require("src.core.game3.items_data")
    return info.pocketOf(id3) ~= "KEY_ITEMS" and not info.isHm(id3)
  end
  if Gen.ofState(S) == 2 then
    return Bag.pocketOf(id, S.data) ~= "KEY_ITEM"
      and tostring(id):sub(1, 3) ~= "HM_"
  end
  local def = S.data and S.data.items and S.data.items[id]
  return not ((def and def.keyItem) or tostring(id):find("^HM_") ~= nil)
end

-- engine/items/inventory.asm:74 caps a slot at 99
function Ops.bagMax(S, id)
  if Gen.ofState(S) == 3 then
    if not id or not Ops.itemStacks(S, id) or G3.quantity(S.data, S.save, false, id) <= 0 then return Ops.say(S, "No stack to max") end
    return changeG3(S, false, id, 999)
  end
  if not id then return Ops.say(S, "No bag row selected") end
  S.save.inventory = S.save.inventory or {}
  local have = itemQty(S.save.inventory, id)
  if have <= 0 then return Ops.say(S, ("%s is not in the bag"):format(tostring(id))) end
  if not Ops.itemStacks(S, id) then
    return Ops.say(S, ("%s has no quantity to max"):format(tostring(id)))
  end
  if have >= Ops.stackMax(S) then
    return Ops.say(S, ("%s is already at x%d"):format(tostring(id), Ops.stackMax(S)))
  end
  Bag.add(S.save, id, Ops.stackMax(S) - have, S.data)
  return Ops.mark(S, ("%s x%d"):format(tostring(id), Ops.stackMax(S)))
end

function Ops.bagCanMax(S, id)
  if id ~= nil then
    local have = Gen.ofState(S) == 3 and G3.quantity(S.data, S.save, false, id) or itemQty(S.save.inventory, id)
    return have > 0 and have < Ops.stackMax(S) and Ops.itemStacks(S, id)
  end
  for _, rowId in ipairs(Bag.order(S.save, S.data)) do
    if Ops.bagCanMax(S, rowId) then return true end
  end
  return false
end

function Ops.bagMaxAll(S)
  if Gen.ofState(S) == 3 then return maxG3(S, false) end
  local order = Bag.order(S.save, S.data)
  local ids = {}
  for i = 1, #order do ids[i] = order[i] end
  local n = 0
  for _, id in ipairs(ids) do
    local have = itemQty(S.save.inventory, id)
    if have > 0 and have < Ops.stackMax(S) and Ops.itemStacks(S, id) then
      Bag.add(S.save, id, Ops.stackMax(S) - have, S.data)
      n = n + 1
    end
  end
  if n == 0 then
    return Ops.say(S, ("Every bag stack is already at x%d"):format(Ops.stackMax(S)))
  end
  return Ops.mark(S, ("Maxed %d bag stack%s to x%d")
    :format(n, n == 1 and "" or "s", Ops.stackMax(S)))
end

-- constants/item_data_constants.asm:41
local POCKET_RANK = { ITEM = 1, ITEMS = 1, BALL = 2, POKE_BALLS = 2, KEY_ITEM = 3, KEY_ITEMS = 3, TM_HM = 4, TM_CASE = 4, BERRY_POUCH = 5 }

local ITEM_SORT_KEYS = {
  index = function(def, id) return (def and (def.itemId or def.index)) or math.huge end,
  name = function(def, id)
    return tostring((def and def.name) or id):lower()
  end,
}

local function itemRows(S, ids, mode)
  local make = ITEM_SORT_KEYS[mode] or ITEM_SORT_KEYS.index
  local items = S.data and S.data.items
  local isPocketGen = Gen.ofState(S) >= 2
  local rows = {}
  for i = 1, #ids do
    local id = ids[i]
    local def = items and items[id]
    local pName = (def and def.pocket) or Bag.pocketOf(id, S.data) or "ITEM"
    rows[i] = { id = id, key = make(def, id),
      rank = isPocketGen and (POCKET_RANK[pName] or 9) or 0 }
  end
  table.sort(rows, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.key ~= b.key then
      if type(a.key) == type(b.key) then return a.key < b.key end
      return tostring(a.key) < tostring(b.key)
    end
    if type(a.id) == type(b.id) then return a.id < b.id end
    return tostring(a.id) < tostring(b.id)
  end)
  local out = {}
  for i = 1, #rows do out[i] = rows[i].id end
  return out
end

function Ops.bagSort(S, mode)
  if not ITEM_SORT_KEYS[mode] then return false end
  local order = Bag.order(S.save, S.data)
  if #order < 2 then return Ops.say(S, "Nothing to sort in the bag") end
  local sorted = itemRows(S, order, mode)
  for i = 1, #sorted do order[i] = sorted[i] end
  S.bagOffset = 0
  return Ops.mark(S, ("Bag sorted by %s (%d items)"):format(mode, #order))
end

function Ops.pcItems(S)
  S.save.pcItems = S.save.pcItems or {}
  return S.save.pcItems
end

function Ops.pcOrder(S)
  local ids = {}
  for id in pairs(Ops.pcItems(S)) do ids[#ids + 1] = id end
  return itemRows(S, ids, S.pcSort)
end

function Ops.pcSort(S, mode)
  if not ITEM_SORT_KEYS[mode] then return false end
  local repeated = S.pcSort == mode
  S.pcSort = mode
  if not repeated then S.pcOffset = 0 end
  local stored = S.save.pcOrder
  if type(stored) == "table" then
    local sorted = Ops.pcOrder(S)
    local same = #stored == #sorted
    for i = 1, #sorted do
      if stored[i] ~= sorted[i] then same = false end
    end
    if not same then
      S.pcOffset = 0
      for i = 1, #stored do stored[i] = nil end
      for i = 1, #sorted do stored[i] = sorted[i] end
      return Ops.mark(S, ("PC storage sorted by %s"):format(mode))
    end
  end
  return not repeated
end

function Ops.addToPc(S, id)
  if Gen.ofState(S) == 3 then return changeG3(S, true, id, G3.quantity(S.data, S.save, true, id) + 1) end
  if not id then return Ops.say(S, "Pick an item first") end
  local pc = Ops.pcItems(S)
  local n = 0
  for _ in pairs(pc) do n = n + 1 end
  if not pc[id] and Gen.ofState(S) == 2 and n >= 50 then
    return Ops.say(S, "PC item storage is full (50 stacks)")
  end
  local cur = itemQty(pc, id)
  pc[id] = math.min(Ops.stackMax(S), cur + 1)
  return Ops.mark(S, ("%s x%d in PC storage"):format(tostring(id), pc[id]))
end

function Ops.pcAdjust(S, id, delta)
  if Gen.ofState(S) == 3 then return changeG3(S, true, id, math.max(0, G3.quantity(S.data, S.save, true, id) + delta)) end
  if not id then return Ops.say(S, "No PC row selected") end
  local pc = Ops.pcItems(S)
  local cur = itemQty(pc, id)
  if not pc[id] and cur <= 0 then return Ops.say(S, ("%s is not in PC storage"):format(tostring(id))) end
  if delta > 0 and cur >= Ops.stackMax(S) then
    return Ops.say(S, ("%s is already at x%d"):format(tostring(id), Ops.stackMax(S)))
  end
  local nextQty = clamp(cur + delta, 0, Ops.stackMax(S))
  if nextQty <= 0 then
    pc[id] = nil
    return Ops.mark(S, ("Removed %s from PC storage"):format(tostring(id)))
  end
  pc[id] = nextQty
  return Ops.mark(S, ("%s x%d in PC storage"):format(tostring(id), pc[id]))
end

function Ops.pcDrop(S, id)
  if Gen.ofState(S) == 3 then return changeG3(S, true, id, 0) end
  if not id then return Ops.say(S, "No PC row selected") end
  local pc = Ops.pcItems(S)
  local qty = itemQty(pc, id)
  pc[id] = nil
  return Ops.mark(S, ("Dropped all %d %s from PC storage"):format(qty, tostring(id)))
end

function Ops.pcMax(S, id)
  if Gen.ofState(S) == 3 then
    if not id or not Ops.itemStacks(S, id) or G3.quantity(S.data, S.save, true, id) <= 0 then return Ops.say(S, "No stack to max") end
    return changeG3(S, true, id, 999)
  end
  if not id then return Ops.say(S, "No PC row selected") end
  local pc = Ops.pcItems(S)
  local cur = itemQty(pc, id)
  if not pc[id] and cur <= 0 then return Ops.say(S, ("%s is not in PC storage"):format(tostring(id))) end
  if not Ops.itemStacks(S, id) then
    return Ops.say(S, ("%s has no quantity to max"):format(tostring(id)))
  end
  if cur >= Ops.stackMax(S) then
    return Ops.say(S, ("%s is already at x%d"):format(tostring(id), Ops.stackMax(S)))
  end
  pc[id] = Ops.stackMax(S)
  return Ops.mark(S, ("%s x%d in PC storage"):format(tostring(id), Ops.stackMax(S)))
end

function Ops.pcCanMax(S, id)
  local pc = Ops.pcItems(S)
  if id ~= nil then
    local have = Gen.ofState(S) == 3 and G3.quantity(S.data, S.save, true, id) or itemQty(pc, id)
    return have > 0 and have < Ops.stackMax(S) and Ops.itemStacks(S, id)
  end
  for rowId, val in pairs(pc) do
    local qty = itemQty(pc, rowId)
    if qty > 0 and qty < Ops.stackMax(S) and Ops.itemStacks(S, rowId) then
      return true
    end
  end
  return false
end

function Ops.pcMaxAll(S)
  if Gen.ofState(S) == 3 then return maxG3(S, true) end
  local pc = Ops.pcItems(S)
  local n = 0
  for id, val in pairs(pc) do
    local qty = itemQty(pc, id)
    if qty > 0 and qty < Ops.stackMax(S) and Ops.itemStacks(S, id) then
      pc[id] = Ops.stackMax(S)
      n = n + 1
    end
  end
  if n == 0 then
    return Ops.say(S, ("Every PC stack is already at x%d"):format(Ops.stackMax(S)))
  end
  return Ops.mark(S, ("Maxed %d PC stack%s to x%d")
    :format(n, n == 1 and "" or "s", Ops.stackMax(S)))
end

-- Badges are truthy inventory flags, not stackable items, which is why the
-- design gives them toggle chips instead of quantity rows.
function Ops.isBadgeId(id)
  if type(id) ~= "string" then return false end
  return id:find("BADGE", 1, true) ~= nil
end

function Ops.badgeIds(S)
  return Gen.badgeIds(S.save, S.cat)
end

function Ops.toggleBadge(S, id)
  local nowOn = Gen.toggleBadge(S.save, id)
  return Ops.mark(S, ("%s %s"):format(id, nowOn and "earned" or "removed"))
end

-- ----------------------------------------------------------------- events
function Ops.setFlag(S, name, on)
  Gen.setFlag(S.save, name, on)
  return Ops.mark(S, ("%s = %s"):format(name, tostring(on and true or false)))
end

function Ops.setKey(S, tableKey, key, on)
  S.save[tableKey] = S.save[tableKey] or {}
  S.save[tableKey][key] = on and true or nil
  return Ops.mark(S, ("%s.%s = %s"):format(tableKey, key, tostring(on and true or false)))
end

function Ops.setToggle(S, mapId, name, on)
  local toggles = S.save.objectToggles or {}
  S.save.objectToggles = toggles
  toggles[mapId] = toggles[mapId] or {}
  toggles[mapId][name] = on and true or false
  return Ops.mark(S, ("%s / %s = %s"):format(mapId, name, tostring(on and true or false)))
end

function Ops.setVar(S, nameOrId, val)
  Gen.setVar(S.save, nameOrId, val)
  local displayVal = Gen.getVar(S.save, nameOrId)
  return Ops.mark(S, ("%s = %d"):format(tostring(nameOrId), displayVal))
end

function Ops.clearTrainers(S)
  local g = Gen.ofState(S)
  if g == 3 then
    local Gen3Flags = require("Gen3Flags")
    local ids = Gen3Flags.allTrainerFlagIds()
    local count = 0
    for _, id in ipairs(ids) do
      if Gen.getFlag(S.save, id) then count = count + 1 end
    end
    if count == 0 then return Ops.say(S, "Trainers are already empty") end
    if not Ops.arm(S, "clear-trainers",
        ("Clear all %d defeated trainers? Click again to confirm"):format(count)) then
      return false
    end
    for _, id in ipairs(ids) do
      Gen.setFlag(S.save, id, false)
    end
    if type(S.save.vsSeeker) == "table" then
      S.save.vsSeeker.rematches = {}
    end
    if S.save.trainerRematches then S.save.trainerRematches = {} end
    if S.save.vars then S.save.vars[0x40AA] = 0 end
    S.save.defeatedTrainers = {}
    return Ops.mark(S, ("Cleared %d defeated trainers"):format(count))
  end
  return Ops.clearTable(S, "defeatedTrainers", "trainers")
end

function Ops.clearItems(S)
  local g = Gen.ofState(S)
  if g == 3 then
    local Gen3Flags = require("Gen3Flags")
    local ids = Gen3Flags.allItemFlagIds()
    local count = 0
    for _, id in ipairs(ids) do
      if Gen.getFlag(S.save, id) then count = count + 1 end
    end
    if count == 0 then return Ops.say(S, "Items taken are already empty") end
    if not Ops.arm(S, "clear-items",
        ("Clear all %d items taken? Click again to confirm"):format(count)) then
      return false
    end
    for _, id in ipairs(ids) do
      Gen.setFlag(S.save, id, false)
    end
    S.save.itemsTaken = {}
    return Ops.mark(S, ("Cleared %d items taken"):format(count))
  end
  return Ops.clearTable(S, "itemsTaken", "items taken")
end

function Ops.clearToggles(S)
  local g = Gen.ofState(S)
  if g == 3 then
    local Gen3Flags = require("Gen3Flags")
    local ids = Gen3Flags.allToggleFlagIds()
    local count = 0
    for _, id in ipairs(ids) do
      if Gen.getFlag(S.save, id) then count = count + 1 end
    end
    if count == 0 then return Ops.say(S, "Object toggles are already empty") end
    if not Ops.arm(S, "clear-toggles",
        ("Clear all %d object toggles? Click again to confirm"):format(count)) then
      return false
    end
    for _, id in ipairs(ids) do
      Gen.setFlag(S.save, id, false)
    end
    S.save.objectToggles = {}
    return Ops.mark(S, ("Cleared %d object toggles"):format(count))
  end
  local count = 0
  for _ in pairs(S.save.objectToggles or {}) do count = count + 1 end
  if count == 0 then return Ops.say(S, "Object toggles are already empty") end
  if not Ops.arm(S, "clear-toggles",
      ("Clear all %d map object toggles? Click again to confirm"):format(count)) then
    return false
  end
  S.save.objectToggles = {}
  return Ops.mark(S, ("Cleared %d map object toggles"):format(count))
end

function Ops.clearTable(S, tableKey, label)
  local count = 0
  for _ in pairs(S.save[tableKey] or {}) do count = count + 1 end
  if count == 0 then return Ops.say(S, ("%s is already empty"):format(label)) end
  if not Ops.arm(S, "clear-" .. tableKey,
      ("Clear all %d %s entries? Click again to confirm"):format(count, label)) then
    return false
  end
  S.save[tableKey] = {}
  return Ops.mark(S, ("Cleared %d %s entries"):format(count, label))
end

-- -------------------------------------------------------------------- dex
function Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  local dex = S.save.dex or S.save.pokedex
  if not dex then
    dex = { seen = {}, [key] = {} }
    if Gen.ofState(S) == 3 then
      S.save.dex = dex
    else
      S.save.pokedex = dex
    end
  end
  dex.seen = dex.seen or {}
  dex[key] = dex[key] or (Gen.ofState(S) == 3 and ((key == "owned" and dex.caught) or (key == "caught" and dex.owned))) or {}
  if Gen.ofState(S) == 3 then
    if key == "owned" and dex.caught == nil then dex.caught = dex[key] end
    if key == "caught" and dex.owned == nil then dex.owned = dex[key] end
  end
  return dex
end

function Ops.dexCounts(S)
  local dex = Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  local seenSet, ownedSet = {}, {}
  for k, v in pairs(dex.seen or {}) do
    if v then
      local sp = tonumber(k) or (S.data and S.data.pokemon and S.data.pokemon[k] and S.data.pokemon[k].speciesId) or k
      seenSet[sp] = true
    end
  end
  local ownedTable = dex[key] or {}
  for k, v in pairs(ownedTable) do
    if v then
      local sp = tonumber(k) or (S.data and S.data.pokemon and S.data.pokemon[k] and S.data.pokemon[k].speciesId) or k
      ownedSet[sp] = true
    end
  end
  local seen, owned = 0, 0
  for _ in pairs(seenSet) do seen = seen + 1 end
  for _ in pairs(ownedSet) do owned = owned + 1 end
  return seen, owned, #S.cat.species
end

local function dexSpeciesKeys(S, species)
  local keys = { species }
  if Gen.ofState(S) == 3 then
    local def = S.data and S.data.pokemon and S.data.pokemon[species]
    local spId = (def and (def.speciesId or def.dex)) or tonumber(species)
    if spId and spId ~= species then keys[#keys + 1] = spId end
  end
  return keys
end

-- Owning implies having seen; un-seeing clears owned.  Both directions are
-- the game's own rule, enforced here so a hand-edited dex stays legal.
function Ops.dexSeen(S, species, on)
  local dex = Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  for _, k in ipairs(dexSpeciesKeys(S, species)) do
    dex.seen[k] = on and true or nil
    if not on then
      dex[key][k] = nil
      if Gen.ofState(S) == 3 then
        if dex.caught then dex.caught[k] = nil end
        if dex.owned then dex.owned[k] = nil end
      end
    end
  end
  return Ops.mark(S, ("%s %s"):format(species, on and "marked seen" or "cleared"))
end

function Ops.dexOwned(S, species, on)
  local dex = Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  for _, k in ipairs(dexSpeciesKeys(S, species)) do
    dex[key][k] = on and true or nil
    if Gen.ofState(S) == 3 then
      if dex.caught then dex.caught[k] = on and true or nil end
      if dex.owned then dex.owned[k] = on and true or nil end
    end
    if on then dex.seen[k] = true end
  end
  return Ops.mark(S, ("%s %s"):format(species, on and "marked owned" or "un-owned"))
end

function Ops.dexStamp(S)
  local dex = Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  local n = 0
  local function stamp(mon)
    if not mon then return end
    local sp = mon.species or mon.speciesId
    local keys = dexSpeciesKeys(S, sp)
    local isNew = not dex[key][sp] and not (keys[2] and dex[key][keys[2]])
    if isNew then n = n + 1 end
    for _, k in ipairs(keys) do
      dex.seen[k] = true
      dex[key][k] = true
      if Gen.ofState(S) == 3 then
        if dex.caught then dex.caught[k] = true end
        if dex.owned then dex.owned[k] = true end
      end
    end
  end
  for _, m in ipairs(S.save.party or {}) do stamp(m) end
  for _, box in ipairs(S.save.boxes or {}) do
    for _, m in pairs(type(box) == "table" and box or {}) do
      if type(m) == "table" then stamp(m) end
    end
  end
  if n == 0 then return Ops.say(S, "Party and boxes are already all in the dex") end
  return Ops.mark(S, ("Owned %d more species from party + boxes"):format(n))
end

function Ops.dexSeeAll(S)
  local dex = Ops.dex(S)
  for _, species in ipairs(S.cat.species) do
    for _, k in ipairs(dexSpeciesKeys(S, species)) do
      dex.seen[k] = true
    end
  end
  return Ops.mark(S, ("Marked all %d species seen"):format(#S.cat.species))
end

function Ops.dexOwnAll(S)
  local dex = Ops.dex(S)
  local key = Gen.dexOwnedKey(S.save)
  for _, species in ipairs(S.cat.species) do
    for _, k in ipairs(dexSpeciesKeys(S, species)) do
      dex.seen[k] = true
      dex[key][k] = true
      if Gen.ofState(S) == 3 then
        if dex.caught then dex.caught[k] = true end
        if dex.owned then dex.owned[k] = true end
      end
    end
  end
  return Ops.mark(S, ("Marked all %d species owned"):format(#S.cat.species))
end

function Ops.dexClear(S)
  if not Ops.arm(S, "dex-clear", "Wipe the whole Pokedex? Click again to confirm") then
    return false
  end
  local key = Gen.dexOwnedKey(S.save)
  local dex = { seen = {}, [key] = {} }
  if Gen.ofState(S) == 3 then
    dex.caught = dex[key]
    dex.owned = dex[key]
    dex.national = S.save.dex and S.save.dex.national or false
    S.save.dex = dex
  else
    S.save.pokedex = dex
  end
  return Ops.mark(S, "Pokedex wiped")
end

function Ops.toggleNationalDex(S)
  local dex = Ops.dex(S)
  local on = not (dex.national == true or (S.save.dex and S.save.dex.national == true))
  dex.national = on
  if S.save.dex then S.save.dex.national = on end
  local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
  if okF and Flags then
    Flags.setFlag(S.save, nil, "FLAG_SYS_NATIONAL_DEX", on)
  else
    S.save.flags = S.save.flags or {}
    S.save.flags[0x829] = on and true or nil
    S.save.flags["FLAG_SYS_NATIONAL_DEX"] = on and true or nil
  end
  return Ops.mark(S, ("National Dex %s"):format(on and "enabled" or "disabled"))
end

-- ------------------------------------------------------------------ dex sort
-- The DEX grid's row order.  Sorting is view-only: it never touches the save,
-- so the list itself is computed here (pure, testable) and the switch is
-- narrated through Ops.say, never Ops.mark.
--
--   "dex"  -- by Pokedex number (1-151), the panel default
--   "name" -- by display name, alphabetical (case-insensitive)
--
-- A species whose record lacks the sort key (a partial mod record) sorts
-- last, ordered by its id, so the grid can never drop a row or crash.
-- table.sort is not stable, so every sort carries the id as a tiebreak and
-- the order is fully deterministic.
local SORT_KEYS = {
  dex = function(def, id)
    return def and def.dex or math.huge
  end,
  name = function(def, id)
    local name = def and def.name
    return (name and tostring(name):lower()) or tostring(id):lower()
  end,
}

function Ops.dexList(S)
  local list = S and S.cat and S.cat.species
  if not list then return {} end
  local make = SORT_KEYS[S.dexSort == "name" and "name" or "dex"]
  local data = S.data
  local rows = {}
  for _, id in ipairs(list) do
    rows[#rows + 1] = { key = make(data and data.pokemon and data.pokemon[id], id),
                        id = id }
  end
  table.sort(rows, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.id < b.id
  end)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.id end
  return out
end

-- View-only verb: switching the DEX grid's order resets its scroll but never
-- dirties the save or narrates in the status bar (the active chip carries
-- the mode).  Returns true when the mode changed, false on a no-op.
function Ops.dexSort(S, mode)
  if mode ~= "name" and mode ~= "dex" then return false end
  if S.dexSort == mode then return false end
  S.dexSort = mode
  S.dexOffset = 0
  return true
end

-- -------------------------------------------------------------------- map
-- Outdoor is detected the way the game treats LAST_MAP sources:
-- OVERWORLD/PLATEAU tilesets, maps with connections, or fly spots the save
-- has already visited.
function Ops.isOutdoor(S, map)
  if not map or not map.def then return false end
  if Gen.ofState(S) == 3 then
    local env = map.def.environment
    if env == "TOWN" or env == "ROUTE" or env == "OVERWORLD" then return true end
    if map.def.connections and next(map.def.connections) ~= nil then return true end
    return false
  end
  local Map2 = require("src.world.gen2.Map")
  if Gen.ofState(S) == 2 and Map2.isOutdoor then
    return Map2.isOutdoor(map.def) and true or false
  end
  if map.def.tileset == "OVERWORLD" or map.def.tileset == "PLATEAU" then
    return true
  end
  if next(map.def.connections or {}) ~= nil then return true end
  return (S.save.visited and S.save.visited[map.id]) or false
end

function Ops.setPlayerHere(S)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  Gen.setPlayerHere(S.save, S.mapId, cell.cx, cell.cy)
  return Ops.mark(S, ("Player set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

function Ops.setLastOutdoor(S, map)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  if Gen.ofState(S) == 3 then
    S.save.healMap = S.mapId
    S.save.healX = cell.cx
    S.save.healY = cell.cy
    return Ops.mark(S, ("heal location set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
  elseif Gen.ofState(S) == 2 then
    S.save.spawn = S.mapId
    return Ops.mark(S, ("spawn set to %s"):format(S.mapId))
  end
  if not Ops.isOutdoor(S, map) then
    return Ops.say(S, S.mapId .. " doesn't look outdoor (no connections, not visited)")
  end
  S.save.lastOutdoor = { id = S.mapId, x = cell.cx, y = cell.cy }
  return Ops.mark(S, ("lastOutdoor set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

function Ops.setLastHeal(S)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  if Gen.ofState(S) == 3 then
    S.save.healMap = S.mapId
    S.save.healX = cell.cx
    S.save.healY = cell.cy
    return Ops.mark(S, ("heal location set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
  elseif Gen.ofState(S) == 2 then
    S.save.spawn = S.mapId
    return Ops.mark(S, ("spawn set to %s"):format(S.mapId))
  end
  S.save.lastHeal = { map = S.mapId, x = cell.cx, y = cell.cy }
  return Ops.mark(S, ("lastHeal set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

function Ops.setHeldItem(S, mon, id)
  if not mon then return false end
  if id == "" or id == nil then
    if not (mon.item or mon.heldItem) then return Ops.say(S, "No held item to clear") end
    local was = mon.item or mon.heldItem
    mon.item = nil
    mon.heldItem = nil
    syncPartyMailHeldItem(S, mon, was, nil)
    return Ops.mark(S, ("Cleared held item (%s)"):format(tostring(was)))
  end
  local def = S.data.items[id]
  if not def then
    return Ops.say(S, ("%s is not an item"):format(tostring(id)))
  end
  local was = mon.item or mon.heldItem
  MonOps.setHeldItem(S.data, mon, def.itemId or def.id or id, Gen.ofState(S))
  syncPartyMailHeldItem(S, mon, was, id)
  return Ops.mark(S, ("%s now holds %s"):format(mon.species, id))
end

function Ops.setHappiness(S, mon, value)
  if not mon then return false end
  local want = clamp(math.floor(value), 0, 255)
  if want == (mon.happiness or mon.friendship or 0) then
    return Ops.say(S, ("Happiness is already %d"):format(want))
  end
  MonOps.setHappiness(S.data, mon, want, Gen.ofState(S))
  return Ops.mark(S, ("%s happiness %d"):format(mon.species, want))
end

function Ops.setNature(S, mon, natureId)
  if not mon then return false end
  natureId = clamp(math.floor(tonumber(natureId) or 0), 0, 24)
  MonOps.setNature(S.data, mon, natureId, Gen.ofState(S))
  local SummaryData = require("src.core.game3.summary_data")
  local name = SummaryData.NATURES[natureId] or tostring(natureId)
  return Ops.mark(S, ("%s nature set to %s"):format(mon.species, name))
end

function Ops.setAbility(S, mon, abilitySlot)
  if not mon then return false end
  abilitySlot = (tonumber(abilitySlot) or 0) % 2
  MonOps.setAbility(S.data, mon, abilitySlot, Gen.ofState(S))
  return Ops.mark(S, ("%s ability set to slot %d"):format(mon.species, abilitySlot + 1))
end

function Ops.setMonGender(S, mon, gender)
  if not mon then return false end
  MonOps.setGender(S.data, mon, gender, Gen.ofState(S))
  return Ops.mark(S, ("%s gender set to %s"):format(mon.species, tostring(gender)))
end

function Ops.setShiny(S, mon, shiny)
  if not mon then return false end
  MonOps.setShiny(S.data, mon, shiny, Gen.ofState(S))
  return Ops.mark(S, ("%s %s"):format(mon.species, shiny and "is now shiny!" or "is no longer shiny"))
end

function Ops.setPokerus(S, mon, value)
  if not mon then return false end
  local want = clamp(math.floor(value), 0, 255)
  if want == (mon.pokerus or 0) then
    return Ops.say(S, ("Pokerus is already %d"):format(want))
  end
  mon.pokerus = want
  return Ops.mark(S, ("%s pokerus byte %d"):format(mon.species, want))
end

-- engine/pokemon/caught_data.asm:169-172
Ops.CAUGHT_TIMES = { "UNKNOWN", "MORN", "DAY", "NITE" }

local function caughtGuard(S, mon)
  if not mon then return false end
  if not Gen.hasCaughtData(S.save, S.version) then
    return Ops.say(S, "This game has no caught data")
  end
  return true
end

function Ops.setCaughtTime(S, mon, value)
  if not caughtGuard(S, mon) then return false end
  local want = clamp(math.floor(tonumber(value) or 0), 0, 3)
  if want == (mon.caughtTime or 0) then
    return Ops.say(S, ("Caught time is already %s"):format(Ops.CAUGHT_TIMES[want + 1]))
  end
  mon.caughtTime = want
  return Ops.mark(S, ("%s caught time %s")
    :format(mon.species, Ops.CAUGHT_TIMES[want + 1]))
end

-- constants/pokemon_data_constants.asm:120-121
function Ops.setCaughtLevel(S, mon, value)
  if not caughtGuard(S, mon) then return false end
  local Mon = require("src.battle.gen2.Mon")
  local want = clamp(math.floor(tonumber(value) or 0), 0, Mon.CAUGHT_LEVEL_MASK)
  if want == (mon.caughtLevel or 0) then
    return Ops.say(S, ("Caught level is already %d"):format(want))
  end
  mon.caughtLevel = want
  return Ops.mark(S, ("%s caught level %d"):format(mon.species, want))
end

-- constants/landmark_constants.asm:111-113
function Ops.setCaughtLocation(S, mon, value)
  if not caughtGuard(S, mon) then return false end
  local Mon = require("src.battle.gen2.Mon")
  local span = Mon.CAUGHT_LOCATION_MASK + 1
  local want = math.floor(tonumber(value) or 0) % span
  if want == (mon.caughtLocation or 0) then
    return Ops.say(S, ("Caught location is already %s")
      :format(Gen.landmarkName(S.data, want)))
  end
  mon.caughtLocation = want
  return Ops.mark(S, ("%s caught at %s")
    :format(mon.species, Gen.landmarkName(S.data, want)))
end

function Ops.setCaughtByGender(S, mon, gender)
  if not caughtGuard(S, mon) then return false end
  local Mon = require("src.battle.gen2.Mon")
  local want = Mon.caughtGenderOf(gender)
  if want == mon.caughtByGender then
    return Ops.say(S, ("Caught by is already %s"):format(tostring(want or "none")))
  end
  mon.caughtByGender = want
  return Ops.mark(S, ("%s caught by %s"):format(mon.species, tostring(want or "none")))
end

function Ops.setPlayerGender(S, gender)
  if not Gen.hasPlayerGender(S.save, S.version) then
    return Ops.say(S, "This game has no player gender")
  end
  if Gen.playerGender(S.save) == gender then
    return Ops.say(S, ("Player is already %s"):format(tostring(gender)))
  end
  return Ops.mark(S, ("Player gender %s"):format(Gen.setPlayerGender(S.save, gender)))
end

return Ops

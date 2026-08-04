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

local Ops = {}

Ops.MONEY_MAX = 999999
Ops.STACK_MAX = 99
Ops.ARM_SECONDS = 2.5

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end
Ops.clamp = clamp

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
  local mon = MonOps.create(S.data, species, 5)
  mon.ot = S.save.player.name
  mon.otId = S.save.player.id
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
  MonOps.setLevel(S.data, mon, want)
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
local BASE_STAT_KEYS = { "hp", "attack", "defense", "speed", "special" }

function Ops.speciesUsable(S, id)
  local def = id and S.data.pokemon[id]
  if type(def) ~= "table" or type(def.baseStats) ~= "table" then return false end
  for _, key in ipairs(BASE_STAT_KEYS) do
    if type(def.baseStats[key]) ~= "number" then return false end
  end
  return true
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
  local wasSpecies, wasLevel, wasExp = mon.species, mon.level, mon.exp
  local wasStats, wasHp = mon.stats, mon.hp
  local ok, err = pcall(MonOps.setSpecies, S.data, mon, id)
  if not ok then
    mon.species, mon.level, mon.exp = wasSpecies, wasLevel, wasExp
    mon.stats, mon.hp = wasStats, wasHp
    return Ops.say(S, ("Could not set %s: %s"):format(tostring(id), tostring(err)))
  end
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
  if #box >= BoxesMod.CAPACITY then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, #box, BoxesMod.CAPACITY))
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
  if #box >= BoxesMod.CAPACITY then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, #box, BoxesMod.CAPACITY))
  end
  if not Ops.speciesUsable(S, id) then
    return Ops.say(S, ("%s has no usable base stats,  cannot add it")
      :format(tostring(id)))
  end
  local mon = MonOps.create(S.data, id, 5)
  mon.ot = S.save.player.name
  mon.otId = S.save.player.id
  table.insert(box, mon)
  S.selectedBoxSlot = #box
  S.editingMon = mon
  return Ops.mark(S, ("Added %s Lv5 to box %d slot %d")
    :format(id, S.selectedBox, #box))
end

function Ops.setDv(S, mon, key, value)
  if not mon then return false end
  local want = clamp(math.floor(value), 0, 15)
  if want == mon.dvs[key] then
    return Ops.say(S, ("%s DV is already %d"):format(key, want))
  end
  MonOps.setDv(S.data, mon, key, want)
  return Ops.mark(S, ("%s DV %d  (HP DV now %d)"):format(key, mon.dvs[key], mon.dvs.hp))
end

function Ops.cycleMove(S, mon, slot)
  if not mon then return false end
  local moves = S.cat.moves
  local current = mon.moves and mon.moves[slot] and mon.moves[slot].id
  local idx = 0
  if current then
    for i, id in ipairs(moves) do
      if id == current then idx = i break end
    end
  end
  local nextId = moves[(idx % #moves) + 1]
  MonOps.setMove(S.data, mon, slot, nextId)
  return Ops.mark(S, ("Move %d set to %s"):format(slot, nextId))
end

function Ops.clearMove(S, mon, slot)
  if not (mon and mon.moves and mon.moves[slot]) then
    return Ops.say(S, ("Move slot %d is already empty"):format(slot))
  end
  local id = mon.moves[slot].id
  mon.moves[slot] = nil
  return Ops.mark(S, ("Cleared move slot %d (%s)"):format(slot, id))
end

function Ops.resetMoves(S, mon)
  if not mon then return false end
  local def = S.data.pokemon[mon.species]
  local learned = Pokemon.movesAtLevel(def, mon.level)
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
  mon.status = nil
  for _, mv in ipairs(mon.moves or {}) do
    local def = S.data.moves[mv.id]
    if def then mv.pp = def.pp + ((mv.ppUps or 0) * math.floor(def.pp / 5)) end
  end
  return Ops.mark(S, ("Healed %s to %d/%d HP"):format(mon.species, mon.hp, mon.stats.hp))
end

-- ------------------------------------------------------------------ boxes
function Ops.boxes(S)
  return BoxesMod.ensure(S.save)
end

function Ops.selectBox(S, index)
  S.selectedBox = clamp(index, 1, BoxesMod.COUNT)
  S.selectedBoxSlot = 1
  S.save.currentBox = S.selectedBox
  local box = Ops.boxes(S)[S.selectedBox]
  S.status = ("Box %d  (%d/%d)"):format(S.selectedBox, #box, BoxesMod.CAPACITY)
  return true
end

function Ops.stepBox(S, delta)
  local n = BoxesMod.COUNT
  return Ops.selectBox(S, ((S.selectedBox - 1 + delta) % n) + 1)
end

function Ops.selectBoxSlot(S, index)
  local box = Ops.boxes(S)[S.selectedBox]
  S.selectedBoxSlot = clamp(index, 1, BoxesMod.CAPACITY)
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
  if #box >= BoxesMod.CAPACITY then
    return Ops.say(S, ("Box %d is full (%d/%d)")
      :format(S.selectedBox, #box, BoxesMod.CAPACITY))
  end
  local species = S.cat.species[1]
  local mon = MonOps.create(S.data, species, 5)
  mon.ot = S.save.player.name
  mon.otId = S.save.player.id
  table.insert(box, mon)
  S.selectedBoxSlot = #box
  S.editingMon = mon
  return Ops.mark(S, ("Added %s Lv5 to box %d slot %d")
    :format(species, S.selectedBox, #box))
end

function Ops.withdraw(S)
  local box = Ops.boxes(S)[S.selectedBox]
  local mon = box[S.selectedBoxSlot]
  if not mon then return Ops.say(S, "No box slot selected") end
  if #S.save.party >= PartyMod.MAX then
    return Ops.say(S, ("Party is full (%d/%d), deposit one first")
      :format(#S.save.party, PartyMod.MAX))
  end
  table.remove(box, S.selectedBoxSlot)
  table.insert(S.save.party, mon)
  S.selectedBoxSlot = clamp(S.selectedBoxSlot, 1, math.max(#box, 1))
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
  table.remove(box, S.selectedBoxSlot)
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
  local want = clamp((S.save.money or 0) + delta, 0, Ops.MONEY_MAX)
  if want == S.save.money then
    return Ops.say(S, delta < 0 and "Money is already $0"
      or ("Money is already capped at $%d"):format(Ops.MONEY_MAX))
  end
  S.save.money = want
  return Ops.mark(S, ("Money set to $%d"):format(want))
end

function Ops.maxMoney(S)
  return Ops.addMoney(S, Ops.MONEY_MAX)
end

function Ops.addToBag(S, id)
  if not id then return Ops.say(S, "Pick an item first") end
  local capacity = Bag.capacity(S.data)
  if Bag.add(S.save, id, 1, S.data) then
    return Ops.mark(S, ("Added %s to the bag (%d/%d slots)")
      :format(id, Bag.slots(S.save), capacity))
  end
  return Ops.say(S, ("Bag is full (%d/%d slots)")
    :format(Bag.slots(S.save), capacity))
end

function Ops.bagAdjust(S, id, delta)
  if not id then return Ops.say(S, "No bag row selected") end
  if delta > 0 then
    local have = S.save.inventory[id] or 0
    if have >= Ops.STACK_MAX then
      return Ops.say(S, ("%s is already at x%d"):format(id, Ops.STACK_MAX))
    end
    Bag.add(S.save, id, delta, S.data)
  else
    Bag.remove(S.save, id, -delta)
    if not S.save.inventory[id] then
      return Ops.mark(S, ("Removed the last %s from the bag"):format(id))
    end
  end
  return Ops.mark(S, ("%s x%d"):format(id, S.save.inventory[id] or 0))
end

function Ops.bagDrop(S, id)
  if not id then return Ops.say(S, "No bag row selected") end
  local qty = S.save.inventory[id] or 0
  Bag.remove(S.save, id, qty)
  return Ops.mark(S, ("Dropped all %d %s"):format(qty, id))
end

function Ops.pcItems(S)
  S.save.pcItems = S.save.pcItems or {}
  return S.save.pcItems
end

function Ops.pcOrder(S)
  local ids = {}
  for id in pairs(Ops.pcItems(S)) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function Ops.addToPc(S, id)
  if not id then return Ops.say(S, "Pick an item first") end
  local pc = Ops.pcItems(S)
  pc[id] = math.min(Ops.STACK_MAX, (pc[id] or 0) + 1)
  return Ops.mark(S, ("%s x%d in PC storage"):format(id, pc[id]))
end

function Ops.pcAdjust(S, id, delta)
  if not id then return Ops.say(S, "No PC row selected") end
  local pc = Ops.pcItems(S)
  if not pc[id] then return Ops.say(S, ("%s is not in PC storage"):format(id)) end
  if delta > 0 and pc[id] >= Ops.STACK_MAX then
    return Ops.say(S, ("%s is already at x%d"):format(id, Ops.STACK_MAX))
  end
  pc[id] = clamp(pc[id] + delta, 0, Ops.STACK_MAX)
  if pc[id] <= 0 then
    pc[id] = nil
    return Ops.mark(S, ("Removed %s from PC storage"):format(id))
  end
  return Ops.mark(S, ("%s x%d in PC storage"):format(id, pc[id]))
end

function Ops.pcDrop(S, id)
  if not id then return Ops.say(S, "No PC row selected") end
  local pc = Ops.pcItems(S)
  local qty = pc[id] or 0
  pc[id] = nil
  return Ops.mark(S, ("Dropped all %d %s from PC storage"):format(qty, id))
end

-- Badges are truthy inventory flags, not stackable items, which is why the
-- design gives them toggle chips instead of quantity rows.
function Ops.isBadgeId(id)
  return id:find("BADGE", 1, true) ~= nil
end

function Ops.badgeIds(S)
  local ids = {}
  for _, id in ipairs(S.cat.items) do
    if Ops.isBadgeId(id) then ids[#ids + 1] = id end
  end
  return ids
end

function Ops.toggleBadge(S, id)
  -- #515: badges are truthy inventory entries written as 1 by the in-game
  -- grant (checkVictoryRewards, src/world/OverworldController.lua) and by
  -- GenSave's .sav import; read and write that same shape here, or a badge
  -- earned in game reads as unowned and an editor-written boolean blows up
  -- Bag.add's `(inv[id] or 0) + qty` (src/inventory/Bag.lua).
  local on = S.save.inventory[id] and true or false
  S.save.inventory[id] = (not on) and 1 or nil
  return Ops.mark(S, ("%s %s"):format(id, on and "removed" or "earned"))
end

-- ----------------------------------------------------------------- events
function Ops.setFlag(S, name, on)
  S.save.flags[name] = on and true or nil
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
  S.save.pokedex = S.save.pokedex or { seen = {}, owned = {} }
  S.save.pokedex.seen = S.save.pokedex.seen or {}
  S.save.pokedex.owned = S.save.pokedex.owned or {}
  return S.save.pokedex
end

function Ops.dexCounts(S)
  local dex = Ops.dex(S)
  local seen, owned = 0, 0
  for _ in pairs(dex.seen) do seen = seen + 1 end
  for _ in pairs(dex.owned) do owned = owned + 1 end
  return seen, owned, #S.cat.species
end

-- Owning implies having seen; un-seeing clears owned.  Both directions are
-- the game's own rule, enforced here so a hand-edited dex stays legal.
function Ops.dexSeen(S, species, on)
  local dex = Ops.dex(S)
  dex.seen[species] = on and true or nil
  if not on then dex.owned[species] = nil end
  return Ops.mark(S, ("%s %s"):format(species, on and "marked seen" or "cleared"))
end

function Ops.dexOwned(S, species, on)
  local dex = Ops.dex(S)
  dex.owned[species] = on and true or nil
  if on then dex.seen[species] = true end
  return Ops.mark(S, ("%s %s"):format(species, on and "marked owned" or "un-owned"))
end

function Ops.dexStamp(S)
  local dex = Ops.dex(S)
  local n = 0
  local function stamp(mon)
    if not dex.owned[mon.species] then n = n + 1 end
    dex.seen[mon.species] = true
    dex.owned[mon.species] = true
  end
  for _, m in ipairs(S.save.party) do stamp(m) end
  for _, box in ipairs(S.save.boxes or {}) do
    for _, m in ipairs(box) do stamp(m) end
  end
  if n == 0 then return Ops.say(S, "Party and boxes are already all in the dex") end
  return Ops.mark(S, ("Owned %d more species from party + boxes"):format(n))
end

function Ops.dexSeeAll(S)
  local dex = Ops.dex(S)
  for _, species in ipairs(S.cat.species) do dex.seen[species] = true end
  return Ops.mark(S, ("Marked all %d species seen"):format(#S.cat.species))
end

function Ops.dexOwnAll(S)
  local dex = Ops.dex(S)
  for _, species in ipairs(S.cat.species) do
    dex.seen[species] = true
    dex.owned[species] = true
  end
  return Ops.mark(S, ("Marked all %d species owned"):format(#S.cat.species))
end

function Ops.dexClear(S)
  if not Ops.arm(S, "dex-clear", "Wipe the whole Pokedex? Click again to confirm") then
    return false
  end
  S.save.pokedex = { seen = {}, owned = {} }
  return Ops.mark(S, "Pokedex wiped")
end

-- -------------------------------------------------------------------- map
-- Outdoor is detected the way the game treats LAST_MAP sources:
-- OVERWORLD/PLATEAU tilesets, maps with connections, or fly spots the save
-- has already visited.
function Ops.isOutdoor(S, map)
  if map.def.tileset == "OVERWORLD" or map.def.tileset == "PLATEAU" then
    return true
  end
  if next(map.def.connections or {}) ~= nil then return true end
  return (S.save.visited and S.save.visited[map.id]) or false
end

function Ops.setPlayerHere(S)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  S.save.player.map = S.mapId
  S.save.player.x = cell.cx
  S.save.player.y = cell.cy
  return Ops.mark(S, ("Player set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

function Ops.setLastOutdoor(S, map)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  if not Ops.isOutdoor(S, map) then
    return Ops.say(S, S.mapId .. " doesn't look outdoor (no connections, not visited)")
  end
  S.save.lastOutdoor = { id = S.mapId, x = cell.cx, y = cell.cy }
  return Ops.mark(S, ("lastOutdoor set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

function Ops.setLastHeal(S)
  local cell = S.mapClickCell
  if not cell then return Ops.say(S, "Click a cell first") end
  S.save.lastHeal = { map = S.mapId, x = cell.cx, y = cell.cy }
  return Ops.mark(S, ("lastHeal set to %s (%d,%d)"):format(S.mapId, cell.cx, cell.cy))
end

return Ops

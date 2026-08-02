-- Standalone: luajit mods/celadon_battle_facility/tests/celadon_battle_facility_test.lua
-- Asserts the building lands on Celadon's west lawn without disturbing the
-- city, and that the door round-trips into the interior and back.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = require("src.core.Data")

-- Celadon before the mod touches it, for the untouched-cell comparisons.
local Pristine = require("data.generated.maps").CELADON_CITY
local baseBlocks = {}
for i, v in ipairs(Pristine.blocks) do baseBlocks[i] = v end
local baseWarpCount = #(Pristine.warps or {})

Data:load()

local run = T.sdk.loadMod("mods/celadon_battle_facility", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.manifest.profile, "content",
  "declares the content profile, so it never implies affects_link")

local city = Data.maps.CELADON_CITY
local facility = Data.maps.CELADON_BATTLE_FACILITY

-- ------- the exterior patch

T.eq(#city.blocks, city.width * city.height,
  "the patched block array still matches width*height")

-- The 4x2 footprint at block (2,9), and nothing else, changed.  Signage is
-- baked into the tileset art, so this asserts the two sign blocks stay out:
-- 17 draws "GYM" and 115 draws "MART".
local FOOT = { [0] = { 32, 13, 13, 33 }, [1] = { 55, 125, 58, 126 } }
-- 17 draws "GYM", 115 "MART", 113/114 "POKe"
local SIGN_BLOCKS = { [17] = "GYM", [115] = "MART", [113] = "POKe", [114] = "POKe" }
-- the roof row is what makes it read as a building rather than a wall
local ROOF_BLOCKS = { [32] = true, [13] = true, [33] = true, [12] = true, [14] = true }
local changed = {}
for i, v in ipairs(city.blocks) do
  if v ~= baseBlocks[i] then changed[#changed + 1] = i end
end
T.eq(#changed, 8, "exactly the eight footprint blocks moved")

for r = 0, 1 do
  for c = 0, 3 do
    local idx = (9 + r) * city.width + (2 + c) + 1
    T.eq(baseBlocks[idx], 85, ("footprint cell (%d,%d) was lawn"):format(2 + c, 9 + r))
    T.eq(city.blocks[idx], FOOT[r][c + 1],
      ("footprint cell (%d,%d) carries the building block"):format(2 + c, 9 + r))
    T.check(SIGN_BLOCKS[city.blocks[idx]] == nil,
      ("footprint cell (%d,%d) is free of baked-in signage (%s)")
        :format(2 + c, 9 + r, tostring(SIGN_BLOCKS[city.blocks[idx]])))
    if r == 0 then
      T.check(ROOF_BLOCKS[city.blocks[idx]],
        ("footprint top row (%d,%d) is a roof block, so the building has a "
         .. "roofline instead of reading as a bare wall"):format(2 + c, 9 + r))
    end
  end
end

-- the neighbours that would break the city if they moved
local function blockAt(col, row) return city.blocks[row * city.width + col + 1] end
T.eq(blockAt(4, 7), 85, "the Dept. Store approach row is still lawn")
T.eq(blockAt(5, 7), 85, "the Dept. Store approach row is still lawn")
for col = 2, 5 do
  T.eq(blockAt(col, 11), 85, ("the door approach row stays walkable at col %d"):format(col))
end

-- ------- the door

T.eq(#city.warps, baseWarpCount + 1, "the doorway warp was appended")
for i = 1, baseWarpCount do
  T.eq(city.warps[i].destMap, Pristine.warps[i].destMap,
    ("Celadon's own warp %d is untouched"):format(i))
  T.eq(city.warps[i].x, Pristine.warps[i].x, ("warp %d keeps its cell"):format(i))
  T.eq(city.warps[i].y, Pristine.warps[i].y, ("warp %d keeps its cell"):format(i))
end

-- block 58 sits at footprint column 2, so its bottom-left cell is x=8
local doors = { city.warps[baseWarpCount + 1] }
T.eq(doors[1].x, 8, "the door sits on block 58's bottom-left cell")
for i, door in ipairs(doors) do
  T.eq(door.y, 21, ("door %d sits on the footprint's bottom row"):format(i))
  T.eq(door.destMap, "CELADON_BATTLE_FACILITY",
    ("door %d leads into the facility"):format(i))
end

-- no existing Celadon object shares a door cell, an approach cell, or the
-- footprint itself
for _, group in ipairs({ Pristine.objects or {}, Pristine.signs or {} }) do
  for _, obj in ipairs(group) do
    for _, door in ipairs(doors) do
      T.check(not (obj.x == door.x and obj.y == door.y),
        ("nothing already occupies door cell (%d,%d)"):format(door.x, door.y))
      T.check(not (obj.x == door.x and obj.y == door.y + 1),
        ("nothing already occupies approach cell (%d,%d)"):format(door.x, door.y + 1))
    end
    T.check(not (obj.x >= 4 and obj.x <= 11 and obj.y >= 18 and obj.y <= 21),
      ("nothing stands inside the footprint (found one at %d,%d)")
        :format(obj.x, obj.y))
  end
end

-- ------- the interior

T.check(facility ~= nil, "the interior map merged")
T.eq(facility.tileset, "FACILITY", "the interior uses the FACILITY tileset")
T.eq(#facility.blocks, facility.width * facility.height,
  "the interior block array matches width*height")
T.check(facility.index >= 1000, "mod maps take ids at or above 1000")

T.eq(#facility.warps, 2, "both doorway cells exit")
for _, w in ipairs(facility.warps) do
  T.eq(w.destMap, "CELADON_CITY", "the exit returns to Celadon")
  T.eq(w.y, (facility.height - 1) * 2 + 1,
    "the exit sits on the bottom wall's doorway")
  T.eq(city.warps[w.destWarp] and city.warps[w.destWarp].destMap,
    "CELADON_BATTLE_FACILITY",
    "the exit's destWarp indexes a door we appended, so the round trip closes")
end
T.eq(facility.warps[2].x, facility.warps[1].x + 1,
  "the doorway's two cells are adjacent")

-- each exterior door and its interior counterpart point at each other, so
-- entering by one door and leaving puts you back where you started
for i, door in ipairs(doors) do
  T.eq(facility.warps[door.destWarp].destWarp, baseWarpCount + i,
    ("door %d round-trips to itself"):format(i))
end

-- ------- the greeter and the challenge

local greeter
for _, obj in ipairs(facility.objects or {}) do
  if obj.name == "CBF_GREETER" then greeter = obj end
end
T.check(greeter ~= nil, "the greeter stands in the lobby")
T.eq(greeter.text, "TEXT_CBF_GREETER", "the greeter carries the script's text constant")
T.check(Data.sprites[greeter.sprite] ~= nil,
  "the greeter's sprite resolves: " .. tostring(greeter.sprite))

-- the greeter must stand on floor, not inside a wall.  Bounds come from the
-- mod's own export so resizing the room cannot silently invalidate this.
local floor = run.loader.exports.celadon_battle_facility.floor()
T.check(greeter.x >= floor.minX and greeter.x <= floor.maxX
    and greeter.y >= floor.minY and greeter.y <= floor.maxY,
  ("the greeter stands on the lobby floor (at %d,%d)"):format(greeter.x, greeter.y))

-- ------- the three tiers

local TIERS = {
  { id = "bronze", class = "OPP_CBF_BRONZE", rounds = 3 },
  { id = "silver", class = "OPP_CBF_SILVER", rounds = 5 },
  { id = "gold",   class = "OPP_CBF_GOLD",   rounds = 7 },
}

for _, tier in ipairs(TIERS) do
  local cls = Data.trainers[tier.class]
  T.check(cls ~= nil, tier.class .. " merged")
  if cls then
    T.check(Data.trainers[cls.basePic] ~= nil,
      tier.class .. " borrows a real vanilla portrait: " .. tostring(cls.basePic))
    T.eq(#cls.parties, tier.rounds,
      ("%s has one roster per round"):format(tier.class))
    for p, party in ipairs(cls.parties) do
      T.check(#party >= 1 and #party <= 6,
        ("%s party %d is a legal size"):format(tier.class, p))
      for _, mon in ipairs(party) do
        T.check(Data.pokemon[mon.species] ~= nil,
          ("%s party %d species resolves: %s")
            :format(tier.class, p, tostring(mon.species)))
      end
    end
  end
end

-- ------- the tiers gate in order

local ex = run.loader.exports and run.loader.exports.celadon_battle_facility
T.check(ex ~= nil, "the mod publishes its progress helpers")
if ex then
  T.check(ex.unlocked("bronze"), "BRONZE is open from the start")
  T.check(not ex.unlocked("silver"), "SILVER is locked until BRONZE is cleared")
  T.check(not ex.unlocked("gold"), "GOLD is locked until SILVER is cleared")
end

-- ------- the script itself

local MapScripts = require("src.script.MapScripts")
local ScriptRunner = require("src.script.ScriptRunner")
local scripts = MapScripts.get("CELADON_BATTLE_FACILITY")
T.check(scripts and scripts.talk, "the facility has a talk table")

local script = scripts.talk and scripts.talk[greeter.text]
T.check(script ~= nil, "the greeter's text constant resolves to a script")

-- Catches unknown verbs, duplicate labels, and jumps to nowhere.  The
-- lookup has to know the mod's own verbs too, or every cbf_* row reads as
-- an unknown command.
local problems = ScriptRunner.validate(script, function(verb)
  return Data.commands[verb] ~= nil
end)
T.eq(#problems, 0, "the challenge script validates (" ..
  tostring(problems[1]) .. ")")

for _, verb in ipairs({ "cbf_gate", "cbf_streak", "cbf_clear" }) do
  T.check(Data.commands[verb] ~= nil, "the mod's verb registered: " .. verb)
end

-- every trainer the script battles has the party index it asks for
local rounds = {}
for _, row in ipairs(script) do
  if row[1] == "start_battle" and row[2] == "trainer" then
    local cls = Data.trainers[row[3]]
    T.check(cls ~= nil, ("start_battle names a real class: %s"):format(tostring(row[3])))
    T.check(cls and cls.parties[row[4]] ~= nil,
      ("%s has party %s"):format(tostring(row[3]), tostring(row[4])))
    rounds[row[3]] = (rounds[row[3]] or 0) + 1
  end
end
for _, tier in ipairs(TIERS) do
  T.eq(rounds[tier.class], tier.rounds,
    ("the %s branch runs all %d rounds"):format(tier.id, tier.rounds))
end

-- every tier is reachable from the greeter's opening prompts
for _, tier in ipairs(TIERS) do
  local jumped, labelled = false, false
  for _, row in ipairs(script) do
    if row[1] == "jump_if_true" and row[2] == tier.id then jumped = true end
    if row[1] == "label" and row[2] == tier.id then labelled = true end
  end
  T.check(jumped, ("the greeter offers the %s tier"):format(tier.id))
  T.check(labelled, ("the %s branch has a landing label"):format(tier.id))
end

-- ------- the lobby cast

local byName = {}
for _, obj in ipairs(facility.objects or {}) do byName[obj.name] = obj end
for _, name in ipairs({ "CBF_GREETER", "CBF_CLERK", "CBF_ARCHIVIST", "CBF_ROOKIE" }) do
  local obj = byName[name]
  T.check(obj ~= nil, name .. " stands in the lobby")
  if obj then
    T.check(Data.sprites[obj.sprite] ~= nil,
      name .. " has a real sprite: " .. tostring(obj.sprite))
    T.check(obj.x >= floor.minX and obj.x <= floor.maxX
        and obj.y >= floor.minY and obj.y <= floor.maxY,
      ("%s stands on the lobby floor (at %d,%d)"):format(name, obj.x, obj.y))
    T.check(not (obj.x == facility.warps[1].x and obj.y == facility.warps[1].y)
        and not (obj.x == facility.warps[2].x and obj.y == facility.warps[2].y),
      name .. " does not stand in the doorway")
    T.check(scripts.talk[obj.text] ~= nil,
      name .. " has a script behind its text constant")
  end
end

-- nobody shares a cell with anybody else
local seen = {}
for _, obj in ipairs(facility.objects or {}) do
  local key = obj.x .. "," .. obj.y
  T.check(seen[key] == nil,
    ("%s does not stand on top of %s"):format(obj.name, tostring(seen[key])))
  seen[key] = obj.name
end

-- every script in the map validates, not just the greeter's
for constant, rows in pairs(scripts.talk) do
  local found = ScriptRunner.validate(rows, function(verb)
    return Data.commands[verb] ~= nil
  end)
  T.eq(#found, 0, ("%s validates (%s)"):format(constant, tostring(found[1])))
end

-- ------- the currency and the prize counter

local token = Data.items.CBF_TOKEN
T.check(token ~= nil, "the BATTLE PT item merged")
T.check(token and not token.keyItem,
  "the token is a normal item so it can stack")

local clerk = scripts.talk[byName.CBF_CLERK and byName.CBF_CLERK.text]
T.check(clerk ~= nil, "the prize counter has a script")
if clerk then
  local sells, charges = 0, 0
  for i, row in ipairs(clerk) do
    if row[1] == "give_item" then
      sells = sells + 1
      T.check(Data.items[row[2]] ~= nil,
        ("the counter sells a real item: %s"):format(tostring(row[2])))
      -- payment must come after the goods: give_item halts the script on a
      -- full bag, so charging first would take tokens for nothing
      local nextRow = clerk[i + 1]
      if row[2] ~= "CBF_TOKEN" then
        T.check(nextRow and nextRow[1] == "take_item" and nextRow[2] == "CBF_TOKEN",
          ("%s is paid for only after the bag accepts it"):format(tostring(row[2])))
      end
    end
    if row[1] == "take_item" then charges = charges + 1 end
  end
  T.check(sells >= 4, "the counter stocks the full prize list")
  T.eq(charges, sells, "every prize handed over is also charged for")
end

-- the tier payouts are all real, positive token grants
local payouts = 0
for _, row in ipairs(script) do
  if row[1] == "give_item" and row[2] == "CBF_TOKEN" then
    payouts = payouts + 1
    T.check(type(row[3]) == "number" and row[3] > 0,
      "a tier payout hands over at least one token")
  end
end
T.eq(payouts, 3, "all three tiers pay out on a clear")

-- ------- the records screen

local Screens = require("src.ui.Screens")
local factory = Screens.get({ data = Data }, "CbfRecords")
T.check(factory and factory.new, "the records screen resolves through the registry")

run.release()
Screens.invalidate()
T.finish("celadon_battle_facility")

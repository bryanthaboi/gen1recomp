-- #2297: in PalletTown_PlayersHouse_1F the wall tile immediately left of the
-- front-door mat could be walked through, and stepping down on it warped the
-- player out of the house.
--
-- Ground truth: pret/pokefirered data/layouts/PalletTown_PlayersHouse_1F/map.bin
-- (13x10 u16 cells: mid | coll << 10 | elev << 12) plus the `building` tileset
-- metatile_attributes. The map header carries FOUR warps -- (5,8) and (4,8)
-- out to PalletTown, (10,2) up to 2F, and (3,9) on the solid bottom-wall tile
-- directly left of the door mat. In pret that fourth warp is dead: (3,9) is
-- mid 26, coll 1, behavior 0x00 MB_NORMAL, so the player can never stand on it
-- and the warp never fires. Collision.installWarps used to force every warp
-- cell walkable, which turned (3,9) into COLL_DOOR and let the player walk out
-- through the wall.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Collision = require("src.core.game3.collision")
local Layout = require("src.core.game3.layout_native")
local Interactions = require("src.core.game3.scripting.interaction_scripts")
local ScriptingCollision = require("src.core.game3.scripting.collision")
local Versions = require("src.import.gba.versions")

-- pret map.bin, rows y=0..9 top to bottom, "mid:coll:elev" left to right.
local GRID_ROWS = {
  "8:1:0 32:1:0 32:1:0 46:1:0 47:1:0 32:1:0 45:1:0 33:1:0 34:1:0 32:1:0 32:1:0 32:1:0 32:1:0",
  "8:1:0 49:1:0 50:1:0 54:1:0 55:1:0 40:1:0 53:1:0 41:1:0 42:1:0 40:1:0 40:1:0 22:1:0 23:1:0",
  "8:1:0 57:0:3 58:0:3 62:0:3 63:0:3 9:0:3 61:0:3 9:0:3 9:0:3 9:0:3 29:0:3 30:1:0 31:1:0",
  "8:1:0 9:0:3 1:0:3 1:0:3 67:0:3 68:0:3 68:0:3 68:0:3 68:0:3 70:0:3 37:0:3 38:0:3 39:0:3",
  "8:1:0 9:0:3 1:0:3 1:0:3 83:0:3 75:0:3 76:1:0 77:1:0 78:0:3 86:0:3 1:0:3 1:0:3 1:0:3",
  "8:1:0 9:0:3 1:0:3 1:0:3 83:0:3 75:0:3 84:1:0 85:1:0 78:0:3 86:0:3 1:0:3 1:0:3 1:0:3",
  "8:1:0 87:0:3 1:0:3 1:0:3 91:0:3 92:0:3 92:0:3 92:0:3 92:0:3 94:0:3 1:0:3 1:0:3 71:0:3",
  "8:1:0 95:1:0 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 79:1:0",
  "8:1:0 9:0:3 1:0:3 18:0:3 19:0:3 20:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3 1:0:3",
  "8:1:0 8:1:0 8:1:0 26:1:0 27:1:0 28:1:0 8:1:0 8:1:0 8:1:0 8:1:0 8:1:0 8:1:0 8:1:0",
}
local WIDTH, HEIGHT = 13, 10

-- pret `building` metatile_attributes: the only mids this layout uses that are
-- not MB_NORMAL (0x00) are the arrow-warp exit mat, the 2F stairs, and the
-- north-wall decoration tiles. Verified against
-- data/tilesets/primary/building/metatile_attributes.bin (640 entries).
local NONZERO_BEHAVIOR = {
  [19] = 0x65, -- MB_SOUTH_ARROW_WARP (door mat)
  [29] = 0x6C, -- MB_UP_RIGHT_STAIR_WARP (stairs to 2F)
  [42] = 0x9D,
  [49] = 0x8A, [50] = 0x8A,
  [53] = 0x86,
  [54] = 0x89, [55] = 0x89,
}
-- Editing GRID_ROWS means re-deriving the behaviors above from pret; this
-- pin makes that impossible to forget.
local VERIFIED_MIDS = "1 8 9 18 19 20 22 23 26 27 28 29 30 31 32 33 34 37 38 39 "
  .. "40 41 42 45 46 47 49 50 53 54 55 57 58 61 62 63 67 68 70 71 75 76 77 78 "
  .. "79 83 84 85 86 87 91 92 94 95"

local cells, seenMids = {}, {}
for y = 1, #GRID_ROWS do
  local n = 0
  for token in GRID_ROWS[y]:gmatch("%S+") do
    local mid, coll, elev = token:match("^(%d+):(%d+):(%d+)$")
    assert(mid, "bad grid token " .. token)
    n = n + 1
    cells[(y - 1) * WIDTH + n] = {
      mid = tonumber(mid), coll = tonumber(coll), elev = tonumber(elev),
    }
    seenMids[tonumber(mid)] = true
  end
  T.eq(n, WIDTH, "grid row " .. (y - 1) .. " has the layout width")
end
T.eq(#cells, WIDTH * HEIGHT, "grid has the layout cell count")

local sortedMids = {}
for mid in pairs(seenMids) do sortedMids[#sortedMids + 1] = mid end
table.sort(sortedMids)
T.eq(table.concat(sortedMids, " "), VERIFIED_MIDS,
  "layout mid set matches the pret building attrs these behaviors came from")

local BEHAVIOR = {}
for mid in pairs(seenMids) do BEHAVIOR[mid] = NONZERO_BEHAVIOR[mid] or 0x00 end

-- pret walkability -> engine COLL bytes, the same translation the extract uses.
local translated = {}
for i, c in ipairs(cells) do
  local coll = ScriptingCollision.fromCell(c.mid, c.coll, BEHAVIOR[c.mid], "indoor")
  translated[i] = { mid = c.mid, coll = coll, elev = c.elev }
end

local layout = Layout.fromDecoded(
  { width = WIDTH, height = HEIGHT, cells = translated },
  "FR_PLAYERS_HOUSE_1F", "player_house")

local warps = assert(Versions.WARPS.FR_PLAYERS_HOUSE_1F,
  "FR_PLAYERS_HOUSE_1F warp list is missing")
T.eq(#warps, 4, "pret map header has four warps, including the dead one")

Interactions.install({ behaviors = { player_house = BEHAVIOR } })
Collision.clear()
Collision.bindMap(nil, "FR_PLAYERS_HOUSE_1F", {
  id = "FR_PLAYERS_HOUSE_1F",
  kind = "indoor",
  pair = "player_house",
  midLayout = layout,
  warps = warps,
})

T.eq(Collision.behavior(3, 9), 0x00, "(3,9) is MB_NORMAL in pret")
T.eq(Collision.cell(3, 9), 0x07, "the wall left of the door stays solid")
T.check(not Collision.isWalkable(3, 9), "the wall left of the door is not walkable")
T.eq(Collision.warpAt(3, 9), nil, "the dead warp on the wall is not live")

for x = 0, WIDTH - 1 do
  T.eq(Collision.cell(x, 9), 0x07, "bottom wall stays solid at x=" .. x)
end

T.eq(Collision.cell(4, 8), 0x72, "the door mat is a keep-facing warp")
local exitWarp = Collision.warpAt(4, 8)
T.eq(exitWarp and exitWarp.destMap, "FR_PALLET_TOWN", "the door mat still exits to town")
T.eq(Collision.cell(10, 2), 0x72, "the 2F stairs are a keep-facing warp")
local stairWarp = Collision.warpAt(10, 2)
T.eq(stairWarp and stairWarp.destMap, "FR_PLAYERS_HOUSE_2F", "the stairs still go up")
Collision.clear()

-- The repair still has to happen where the behavior table cannot answer: a
-- cache whose tileset attrs stop before this mid (Collision.behavior -> nil).
local function bindOneCell(behavior, coll)
  Collision.clear()
  local one = Layout.fromDecoded(
    { width = 1, height = 1, cells = { { mid = 100, coll = coll, elev = 0 } } },
    "TEST", "test")
  Interactions.install({
    behaviors = behavior and { test = { [100] = behavior } } or {},
  })
  Collision.bindMap(nil, "TEST", {
    pair = "test",
    midLayout = one,
    warps = { { x = 0, y = 0, destMap = "FR_PALLET_TOWN", destWarp = 1 } },
  })
  return Collision.cell(0, 0), Collision.warpAt(0, 0)
end

local coll, warp = bindOneCell(nil, 0x07)
T.eq(coll, 0x71, "unreadable attrs still get the walkable-door repair")
T.check(warp ~= nil, "unreadable attrs still index the warp")

coll, warp = bindOneCell(0x69, 0x07)
T.eq(coll, 0x71, "a real MB_WARP_DOOR behind a solid cell still opens")
T.check(warp ~= nil, "a real MB_WARP_DOOR still indexes the warp")

coll, warp = bindOneCell(0x00, 0x07)
T.eq(coll, 0x07, "a readable MB_NORMAL wall is not opened by a warp event")
T.eq(warp, nil, "a readable MB_NORMAL wall does not index the warp")

coll = bindOneCell(0x65, 0x07)
T.eq(coll, 0x71, "MB_SOUTH_ARROW_WARP is a warp behavior")

coll = bindOneCell(0x6C, 0x07)
T.eq(coll, 0x71, "MB_UP_RIGHT_STAIR_WARP is a warp behavior")

coll = bindOneCell(0x60, 0x07)
T.eq(coll, 0x71, "MB_CAVE_DOOR is a warp behavior")

coll = bindOneCell(0x00, 0x00)
T.eq(coll, 0x00, "an already-walkable cell is left alone")
Collision.clear()

-- pokefirered/src/field_control_avatar.c: live map-header warp behaviors.
local WARP_BEHAVIORS = {
  [0x60] = true, -- MB_CAVE_DOOR
  [0x61] = true, -- MB_LADDER
  [0x62] = true, [0x63] = true, [0x64] = true, [0x65] = true, -- arrow warps
  [0x66] = true, -- MB_FALL_WARP
  [0x67] = true, -- MB_REGULAR_WARP
  [0x68] = true, -- MB_LAVARIDGE_1F_WARP
  [0x69] = true, -- MB_WARP_DOOR
  [0x6A] = true, [0x6B] = true, -- escalators
  [0x6C] = true, [0x6D] = true, [0x6E] = true, [0x6F] = true, -- stair warps
  [0x71] = true, -- MB_UNION_ROOM_WARP
}
for beh = 0, 0xFF do
  T.check(Collision.isWarpMetatileBehavior(beh) == (WARP_BEHAVIORS[beh] == true),
    ("isWarpMetatileBehavior(0x%02X)"):format(beh))
end
T.check(not Collision.isWarpMetatileBehavior(nil),
  "an unreadable behavior is not a warp behavior")

T.finish("firered house wall warp #2297")

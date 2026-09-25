package.path = "./?.lua;./?/init.lua;" .. package.path

require("src.core.GameVersion").set("firered")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local Gen3Compat = require("src.mods.Gen3Compat")

local def = {
  id = "FR_SIX_ISLAND_WATER_PATH", width = 20, height = 70,
  connections = {
    { dir = "west", map = "FR_SIX_ISLAND_GREEN_PATH", offset = 0 },
    { dir = "west", map = "FR_SIX_ISLAND", offset = 40 },
    { dir = "west", map = "FR_SIX_ISLAND_RUIN_VALLEY", offset = 80 },
    { dir = "north", map = "FR_SIX_ISLAND_POKEMON_CENTER", offset = 0 },
  },
}
local game = { data = { maps = { FR_SIX_ISLAND_WATER_PATH = def } } }
Gen3Compat.bind(function() return game end)

local view = Gen3Compat.mapView("FR_SIX_ISLAND_WATER_PATH")
local conns = view.connections
check(type(conns) == "table" and #conns == 4, "four ordered connections")

local seen = 0
for _ in pairs(conns) do seen = seen + 1 end
check(seen == 4, "pairs() yields each connection once (got " .. seen .. ")")

check(conns.west and conns.west.map == "FR_SIX_ISLAND_GREEN_PATH", "direction name resolves to the first entry")
check(conns.north and conns.north.map == "FR_SIX_ISLAND_POKEMON_CENTER", "single-entry direction resolves")
check(conns.south == nil, "missing direction is nil")
check(conns[1].map == "FR_SIX_ISLAND_GREEN_PATH" and conns[3].map == "FR_SIX_ISLAND_RUIN_VALLEY", "ROM order kept")

check(rawequal(view.connections, conns), "view is cached per def")
check(rawequal(Gen3Compat.mapView("FR_SIX_ISLAND_WATER_PATH").connections, conns), "cache is shared across views")

def.connections = { { dir = "east", map = "FR_SIX_ISLAND", offset = 0 } }
local fresh = view.connections
check(not rawequal(fresh, conns) and #fresh == 1 and fresh.east ~= nil, "replaced connections rebuild the view")

os.exit(failures == 0 and 0 or 1)

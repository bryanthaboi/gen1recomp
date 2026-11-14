package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen3 replaceBlock defined metatile")
local check, eq = S.check, S.eq

local PAIR = "probe_pair"
require("src.core.game3.scripting.interaction_scripts").behaviors = {
  [PAIR] = { [0] = 0, [5] = 0x02 },
}

local NT = require("src.core.game3.tileset_native")
local atlas = { pair = PAIR, cols = 4, midToSlot = { [0] = 0, [5] = 1 }, quads = {}, overQuads = {},
  image = { getDimensions = function() return 64, 64 end },
  overImage = { getDimensions = function() return 64, 64 end } }
eq(NT.slotFor(atlas, 5), 1, "slotFor answers a packed metatile's slot")
eq(NT.slotFor(atlas, 7), nil, "slotFor answers nil for a metatile the pair does not hold")
eq(NT.slotFor(atlas, 0), 0, "metatile 0 still has its own slot")
eq(NT.quad(atlas, nil), nil, "quad refuses a nil slot")
eq(NT.overQuad(atlas, nil), nil, "overQuad refuses a nil slot")
check(NT.quad(atlas, 1) ~= nil, "quad still builds a defined slot")

local MAP = "FR_PROBE"
local layout = { width = 4, height = 4, pair = PAIR, midAt = function() return 0 end }
local def = { id = MAP, width = 4, height = 4, pair = PAIR, midLayout = layout,
  warps = {}, objects = {} }
local session = { map = MAP, x = 1, y = 1, facing = "down", party = {}, flags = {}, vars = {} }
local game = { data = { maps = { [MAP] = def } }, session = session, phase = "field" }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  uiBusy = function() return false end,
}
local MapStub = { current = MAP }
function MapStub.currentDef() return def end
package.loaded["src.core.game3.map"] = MapStub
package.loaded["src.core.game3.player"] = { cellX = 1, cellY = 1, facing = "down", moving = false }

local Field = require("src.core.game3.field")
Field.running, Field._game, Field._session, Field._locks = true, { data = { maps = {} } }, session, {}
Field.metatileOverrides = {}
for _, bad in ipairs({ "abc", 3.5, 0 / 0 }) do
  local ok, err = Field.setMetatile(1, 1, bad)
  eq(ok, nil, "Field.setMetatile refuses " .. tostring(bad))
  check(type(err) == "string", "Field.setMetatile explains refusing " .. tostring(bad))
end
eq(Field.metatileOverrideAt(MAP, 1, 1), nil, "a refused id leaves no override behind")
Field._game = game
eq(Field.currentPair(), PAIR, "currentPair reads the active map's tileset pair")

local applied = {}
function layout:applyOverride(x, y, mid) applied[#applied + 1] = { x, y, mid } end
function layout:elevAt() return 0 end
local Collision = require("src.core.game3.collision")
local realPatchCell = Collision.patchCell
Collision.patchCell = function() return true end
local Logger = require("src.core.Logger")
local function warnsAbout(mid)
  local n = 0
  for _, line in ipairs(Logger.history) do
    if line:find("metatile " .. mid .. " ", 1, true) and line:find(PAIR, 1, true) then n = n + 1 end
  end
  return n
end
eq(Field.setMetatile(1, 1, 5), true, "Field.setMetatile answers true on a write")
eq(warnsAbout(5), 0, "a defined metatile write logs nothing")
eq(Field.setMetatile(1, 1, 7), true, "Field.setMetatile still writes an undefined integer metatile")
eq(applied[#applied] and applied[#applied][3], 7, "the undefined metatile reaches the layout")
eq(warnsAbout(7), 1, "an undefined metatile write logs the id and the pair")
Field.setMetatile(2, 1, 7)
eq(warnsAbout(7), 1, "the undefined metatile log fires once per pair and id")
Collision.patchCell = realPatchCell
Field.metatileOverrides = {}

local writes = {}
Field.setMetatile = function(x, y, mid) writes[#writes + 1] = { x, y, mid } end
Field.metatileOverrideAt = function() return nil end

local function refused(label, ok, err)
  eq(ok, nil, label .. " is refused")
  check(type(err) == "string" and err:find("unknown block id", 1, true) ~= nil
    and err:find("7", 1, true) ~= nil and err:find(PAIR, 1, true) ~= nil,
    label .. " names the id and the pair: " .. tostring(err))
end

local Gen3Compat = require("src.mods.Gen3Compat")
Gen3Compat.bind(function() return game end)

local WorldAPI = require("src.world.game3.WorldAPI")
local api = WorldAPI.new(game, "probe")
refused("WorldAPI:replaceBlock with an undefined metatile", api:replaceBlock(1, 1, 7))
eq(#writes, 0, "WorldAPI never writes the undefined metatile")
check(api:replaceBlock(1, 1, 5), "WorldAPI:replaceBlock with a defined metatile")
eq(writes[#writes] and writes[#writes][3], 5, "the defined metatile reaches Field.setMetatile")

writes = {}
local OW = Gen3Compat.resolve("src.world.OverworldController", "probe")
refused("OverworldState.replaceBlock with an undefined metatile", OW.replaceBlock(1, 1, 7))
eq(#writes, 0, "the facade never writes the undefined metatile")
check(OW.replaceBlock(1, 1, 5), "OverworldState.replaceBlock with a defined metatile")
eq(writes[#writes] and writes[#writes][3], 5, "the facade writes the defined metatile")

writes = {}
local UnifiedWorld = require("src.mods.UnifiedWorld")
local world = UnifiedWorld.new(function() return game end, 3, "firered", "probe")
refused("mod.world:replaceBlock with an in-range undefined metatile", world:replaceBlock(1, 1, 7))
eq(#writes, 0, "mod.world never writes the undefined metatile")
check(world:replaceBlock(1, 1, 5), "mod.world:replaceBlock with a defined metatile")
eq(writes[#writes] and writes[#writes][3], 5, "mod.world writes the defined metatile")

writes = {}
local handle, qerr = world:queueScript({ { "replace_block", 1, 1, 7 } })
refused("a queued replace_block with an undefined metatile", handle, qerr)
eq(#writes, 0, "the queued script never writes the undefined metatile")

local Runtime = require("src.mods.Runtime")
local realHooks = Runtime.hooks
local updates = {}
Runtime.hooks = setmetatable({ wrap = function(_, _, callback)
  updates[#updates + 1] = callback
  return function() end
end }, { __index = realHooks })
local function drain()
  while #updates > 0 do
    table.remove(updates, 1)(function() end, game)
  end
end

local outcome
handle, qerr = world:queueScript({ { "replace_block", 1, 1, 5 } },
  { onDone = function(ok, err) outcome = { ok = ok, err = err } end })
check(handle ~= nil, "a queued replace_block with a defined metatile is accepted (" .. tostring(qerr) .. ")")
drain()
eq(writes[#writes] and writes[#writes][3], 5, "the queued replace_block writes the defined metatile")
eq(outcome and outcome.ok, true, "the queued replace_block finishes cleanly")

local OTHER = "probe_other_pair"
require("src.core.game3.scripting.interaction_scripts").behaviors[OTHER] = { [0] = 0, [7] = 0 }
local realCurrentPair = Field.currentPair
Field.currentPair = function() return OTHER end
writes, outcome = {}, nil
handle, qerr = world:queueScript({ { "replace_block", 1, 1, 5 } },
  { onDone = function(ok, err) outcome = { ok = ok, err = err } end })
drain()
Field.currentPair = realCurrentPair
eq(#writes, 0, "the run-time check never writes a metatile the live pair does not define")
check(outcome and not outcome.ok and type(outcome.err) == "string"
  and outcome.err:find("unknown block id", 1, true) ~= nil and outcome.err:find(OTHER, 1, true) ~= nil,
  "the run-time check names the live pair: " .. tostring(handle) .. " " .. tostring(outcome and outcome.err))
Runtime.hooks = realHooks

S.finish()

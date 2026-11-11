-- FieldView.prepareFrame: a frame whose ground a render pipeline owns draws
-- nothing but keeps the native batches and their dirty, animation and overhead
-- state exactly as a drawn frame would.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function newBatch(texture)
  local b = { texture = texture, sprites = {} }
  function b:add(q, x, y) self.sprites[#self.sprites + 1] = { q = q, x = x, y = y }; return #self.sprites end
  function b:set(i, q, x, y) self.sprites[i] = { q = q, x = x, y = y } end
  function b:clear() self.sprites = {} end
  function b:getCount() return #self.sprites end
  function b:getTexture() return self.texture end
  function b:release() end
  return b
end

local draws = 0
local function counted() draws = draws + 1 end
love = love or {}
love.graphics = love.graphics or {}
love.graphics.newSpriteBatch = function(texture) return newBatch(texture) end
love.graphics.setColor = counted
love.graphics.rectangle = counted
love.graphics.draw = counted

local Versions = require("src.import.gba.versions")
Versions.NATIVE_RENDER = true

local ts = { pair = "a", image = { name = "a" }, layered = false, quads = {} }
local Native = { _pairs = { a = ts } }
function Native.ready() return true end
function Native.get() return ts end
function Native.slotFor(_, mid) return mid end
function Native.hasMid() return true end
function Native.quad(t, slot)
  local q = t.quads[slot]
  if not q then q = { slot = slot }; t.quads[slot] = q end
  return q
end
function Native.overQuad() return nil end
package.loaded["src.core.game3.tileset_native"] = Native
local animPairs
package.loaded["src.core.game3.tileset_anim"] = { setVisiblePairs = function(p) animPairs = p end }

local layout = { width = 64, height = 64, pair = "a" }
function layout:midAt(x, y) return (x + y) % 7 end
local mapDef = { midLayout = layout, pair = "a" }
local Map = { world = {}, neighborList = {} }
function Map.worldMidAt(wx, wy, def) return def.midLayout:midAt(wx, wy), "a" end
package.loaded["src.core.game3.map"] = Map

local FieldView = require("src.core.game3.field_view")
local drawNativeTiles
for i = 1, 200 do
  local name, fn = debug.getupvalue(FieldView.draw, i)
  if not name then break end
  if name == "drawNativeTiles" then drawNativeTiles = fn break end
end
check(type(drawNativeTiles) == "function", "found drawNativeTiles")
check(type(FieldView.prepareFrame) == "function", "prepareFrame exists")
if not drawNativeTiles then os.exit(1) end

local W, H = 240, 160

-- 1. a prepare-only frame issues no graphics call and builds the batches
draws = 0
check(drawNativeTiles(mapDef, 0, 0, W, H, true) == true, "prepare-only frame reports native")
check(draws == 0, "prepare-only frame draws nothing")
check(FieldView._nativeBatches.a ~= nil, "prepare-only frame builds the batch")
check(FieldView._nativeOverPair == "a", "overhead pair set for the actor pass")
check(animPairs ~= nil and animPairs.a == true, "tile animation learns the visible pairs")

-- 2. the flags the rest of the game reads are consumed just as a draw would
FieldView._nativeDirty = true
drawNativeTiles(mapDef, 0, 0, W, H, true)
check(FieldView._nativeDirty == false, "prepare-only frame consumes the dirty flag")
FieldView.invalidateCell(3, 3, layout)
check(FieldView._nativeDirtyCells ~= nil, "a metatile write queues its cell")
drawNativeTiles(mapDef, 0, 0, W, H, true)
check(FieldView._nativeDirtyCells == nil, "prepare-only frame consumes queued cells")

-- 3. scrolling while prepare-only leaves a following drawn frame correct
for step = 1, 30 do drawNativeTiles(mapDef, step * 4, 0, W, H, true) end
local batch = FieldView._nativeBatches.a
draws = 0
drawNativeTiles(mapDef, 120, 0, W, H)
check(draws > 0, "a drawn frame after prepare-only frames draws")
check(FieldView._nativeBatches.a == batch, "the batch carries over to the drawn frame")
local cols, rows = math.ceil(W / 16) + 3, math.ceil(H / 16) + 3
local live = 0
for _, row in pairs(FieldView._nativeVisibleCells) do
  for _ in pairs(row) do live = live + 1 end
end
check(live == cols * rows, "visible cells match the view")

print((failures == 0 and "PASS " or "FAIL ") .. "game3_field_prepare_frame_test")
os.exit(failures == 0 and 0 or 1)

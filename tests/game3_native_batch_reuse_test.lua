-- FieldView native tile SpriteBatches: a full reset reuses (clears) the
-- existing batches instead of allocating new ones, an atlas texture swap
-- mid-scroll rebuilds instead of indexing a replaced batch, and a single
-- metatile write re-samples one cell without a full rebuild.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local created, released = 0, 0
local function newBatch(texture)
  created = created + 1
  local b = { texture = texture, sprites = {}, released = false }
  local function live(self)
    if self.released then error("use of released SpriteBatch", 2) end
  end
  function b:add(q, x, y)
    live(self)
    self.sprites[#self.sprites + 1] = { q = q, x = x, y = y }
    return #self.sprites
  end
  function b:set(i, q, x, y)
    live(self)
    if i < 1 or i > #self.sprites then error("Invalid sprite index: " .. tostring(i), 2) end
    self.sprites[i] = { q = q, x = x, y = y }
  end
  function b:clear() live(self); self.sprites = {} end
  function b:getCount() return #self.sprites end
  function b:getTexture() return self.texture end
  function b:release() released = released + 1; self.released = true end
  return b
end

local noop = function() end
love = love or {}
love.graphics = love.graphics or {}
love.graphics.newSpriteBatch = function(texture) return newBatch(texture) end
love.graphics.setColor = noop
love.graphics.rectangle = noop
love.graphics.draw = noop

local Versions = require("src.import.gba.versions")
Versions.NATIVE_RENDER = true

-- Fake native atlases: quad = { pair, slot } so tests can read back mids.
local Native = { _pairs = {} }
local function atlas(pair)
  local ts = { pair = pair, image = { name = pair .. "#" .. tostring(math.random()) },
    layered = false, quads = {} }
  Native._pairs[pair] = ts
  return ts
end
function Native.ready() return true end
function Native.get(pair) return Native._pairs[pair] end
function Native.slotFor(_, mid) return mid end
function Native.hasMid() return true end
function Native.quad(ts, slot)
  local q = ts.quads[slot]
  if not q then q = { pair = ts.pair, slot = slot }; ts.quads[slot] = q end
  return q
end
function Native.overQuad() return nil end
package.loaded["src.core.game3.tileset_native"] = Native
package.loaded["src.core.game3.tileset_anim"] = { setVisiblePairs = noop }

-- Primary map "A" (pair a) covers x >= 0; everything west of it is pair b.
local overrides = {}
local layout = { width = 64, height = 64, pair = "a" }
function layout:midAt(x, y) return overrides[y * 1024 + x] or ((x + y) % 7) end
local mapDef = { midLayout = layout, pair = "a" }
local Map = { world = {}, neighborList = {} }
function Map.worldMidAt(wx, wy, def)
  if wx < 0 then return (wx * 3 + wy) % 5, "b" end
  return def.midLayout:midAt(wx, wy), "a"
end
package.loaded["src.core.game3.map"] = Map

local FieldView = require("src.core.game3.field_view")
local drawNativeTiles
for i = 1, 200 do
  local name, fn = debug.getupvalue(FieldView.draw, i)
  if not name then break end
  if name == "drawNativeTiles" then drawNativeTiles = fn break end
end
check(type(drawNativeTiles) == "function", "found drawNativeTiles")
if not drawNativeTiles then os.exit(1) end

local W, H = 240, 160
local function cellSprite(wx, wy)
  local info = FieldView._nativeVisibleCells[wy] and FieldView._nativeVisibleCells[wy][wx]
  local batch = info and info.under and FieldView._nativeBatches[info.under.key]
  return batch and batch.sprites[info.under.index], info
end

local function allCellsValid()
  for wy, row in pairs(FieldView._nativeVisibleCells) do
    for wx, info in pairs(row) do
      if info.under then
        local batch = FieldView._nativeBatches[info.under.key]
        if not batch or batch.released or info.under.index > #batch.sprites then return false end
        local s = batch.sprites[info.under.index]
        local mid = Map.worldMidAt(wx, wy, mapDef)
        if s.q.slot ~= mid or s.x ~= (wx - FieldView._nativeBaseBx) * 16 then return false end
      end
    end
  end
  return true
end

atlas("a")
atlas("b")
check(drawNativeTiles(mapDef, 0, 0, W, H) == true, "first native draw")
local first = FieldView._nativeBatches
local batchA, batchB = first.a, first.b
local createdAfterFirst = created
check(batchA and batchB, "one batch per visible pair")
check(allCellsValid(), "first build samples every visible cell")

-- 1. full reset keeps the same SpriteBatch objects
FieldView._nativeDirty = true
drawNativeTiles(mapDef, 0, 0, W, H)
check(created == createdAfterFirst, "dirty reset allocates no new SpriteBatch")
check(FieldView._nativeBatches == first and first.a == batchA and first.b == batchB,
  "dirty reset reuses the batch store and batches")
check(allCellsValid(), "reset rebuild samples every visible cell")
local cols, rows = math.ceil(W / 16) + 3, math.ceil(H / 16) + 3
check(batchA:getCount() + batchB:getCount() == cols * rows, "reset clears before refilling")

-- 2. scrolling reuses freed slots; the slot counter stays bounded
for step = 1, 40 do drawNativeTiles(mapDef, step * 4, 0, W, H) end
for step = 40, 1, -1 do drawNativeTiles(mapDef, step * 4, step, W, H) end
check(allCellsValid(), "scrolling keeps every cell's sprite valid")
check(FieldView._nativeSpriteSlots <= cols * rows * 4, "slot counter bounded by the reset heuristic")

-- 3. a pair scrolled fully out of view is pruned (released) on the next reset
local goneB = FieldView._nativeBatches.b
FieldView._nativeDirty = true
drawNativeTiles(mapDef, 400, 0, W, H)
check(goneB and FieldView._nativeBatches.b == nil and goneB.released,
  "reset releases a batch no visible cell uses")

-- 4. neighbour atlas reloaded mid-scroll: rebuild, never index a new batch
drawNativeTiles(mapDef, -8, 0, W, H)
local oldB = FieldView._nativeBatches.b
check(oldB ~= nil, "pair b batch back in view")
local freshB = atlas("b")
local ok, err = pcall(drawNativeTiles, mapDef, -40, 0, W, H)
check(ok, "texture swap mid-scroll does not crash (" .. tostring(err) .. ")")
check(FieldView._nativeBatches.b ~= oldB and FieldView._nativeBatches.b:getTexture() == freshB.image,
  "swapped pair gets a batch on the new texture")
check(oldB.released, "old batch released after the swap")
ok, err = pcall(function()
  for step = 1, 30 do drawNativeTiles(mapDef, -40 + step * 8, step, W, H) end
end)
check(ok, "scrolling after the swap releases cells safely (" .. tostring(err) .. ")")
check(allCellsValid(), "cells valid after swap + scroll")

-- 5. primary atlas reloaded with no scroll: rebuild onto the new texture
local freshA = atlas("a")
drawNativeTiles(mapDef, 200, 40, W, H)
check(FieldView._nativeBatches.a:getTexture() == freshA.image, "primary atlas swap rebuilds")
check(allCellsValid(), "cells valid after primary swap")

-- 6. one metatile write re-samples just that cell
local clearsBefore = created
local base = FieldView._nativeBaseBx
local cx, cy = 20, 6
overrides[cy * 1024 + cx] = 99
FieldView.invalidateLayoutCell(layout, cx, cy)
check(FieldView._nativeDirty == false, "cell write does not force a full rebuild")
local countBefore = FieldView._nativeBatches.a:getCount()
drawNativeTiles(mapDef, 200, 40, W, H)
local s = cellSprite(cx, cy)
check(s and s.q.slot == 99, "written cell shows the new metatile")
check(FieldView._nativeBaseBx == base and FieldView._nativeBatches.a:getCount() == countBefore
  and created == clearsBefore, "cell write reused a freed slot without a rebuild")
check(allCellsValid(), "all cells valid after cell write")

-- a layout that is not the drawn map's falls back to a full rebuild
FieldView.invalidateLayoutCell({}, 1, 1)
check(FieldView._nativeDirty == true, "foreign layout write forces a full rebuild")
drawNativeTiles(mapDef, 200, 40, W, H)

-- LayoutNative wiring: applyOverride invalidates a single cell
local LayoutNative = require("src.core.game3.layout_native")
local realCells = {}
for i = 1, 64 * 64 do realCells[i] = { mid = 0, coll = 0, elev = 0 } end
local real = LayoutNative.fromDecoded({ width = 64, height = 64, cells = realCells, borderMids = { 0 } }, "T", "a")
local realDef = { midLayout = real, pair = "a" }
drawNativeTiles(realDef, 0, 0, W, H)
real:applyOverride(3, 4, 42, 0, 0)
check(FieldView._nativeDirty == false and FieldView._nativeDirtyCells
  and FieldView._nativeDirtyCells[1] == 3 and FieldView._nativeDirtyCells[2] == 4,
  "applyOverride queues one dirty cell")
Map.worldMidAt = function(wx, wy, def) return def.midLayout:midAt(wx, wy), "a" end
drawNativeTiles(realDef, 0, 0, W, H)
local info = FieldView._nativeVisibleCells[4][3]
check(info and FieldView._nativeBatches.a.sprites[info.under.index].q.slot == 42,
  "applyOverride cell redrawn with the new metatile")
real:clearOverrides()
check(FieldView._nativeDirty == true, "clearOverrides still rebuilds everything")

print(failures == 0 and "PASS game3_native_batch_reuse_test" or ("FAIL game3_native_batch_reuse_test failures=" .. failures))
os.exit(failures == 0 and 0 or 1)

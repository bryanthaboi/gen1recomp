-- Rendering pipelines: the engine side of the render_pipelines registry.
--
-- A pipeline is a display mode a mod owns.  It may replace the overworld's
-- world pass with geometry of its own (drawWorld) and/or post-process the
-- finished composite (present).  Everything else about being a display mode
-- -- the OFF/1/2/3 ladder, the options row, the hotkey, persistence, the
-- free-roam gate, and never letting a mod's error take the frame down -- is
-- engine plumbing and lives here, so a renderer mod writes the two draw
-- functions and declares the rest.
--
-- The two halves compose independently and in priority order: the highest
-- priority eligible drawWorld renders the world, then every eligible
-- present folds over whatever came out (the world pipeline's canvas, or the
-- vanilla flat/tilt composite when none ran).  A present that is switched
-- off returns its input, so a full ladder of them costs nothing at level 0.
--
-- Nothing here reaches collision, movement, triggers or scripts: like
-- survey zoom and tilt, a pipeline is purely presentational, which is why
-- its level rides in save.options rather than the save proper.
--
-- Spec: docs/modding.md (rendering pipelines)

local Data = require("src.core.Data")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Zoom = require("src.render.Zoom")

local Pipelines = {}

-- id -> level.  Levels live here rather than on the records because the
-- records are merged content: frozen after load, and shared with whatever
-- else reads Data.
local levels = {}

-- ids whose callbacks have already thrown, so a pipeline that fails every
-- frame reports once instead of filling the log at 60Hz
local broken = {}

Pipelines.DEFAULT_LEVELS = { "OFF", "ON" }

-- The merged dataset the records live in.  The boot singleton is the
-- default -- Game.data is that very table -- and install() lets a headless
-- caller (the SDK harness, a tool) point this at a dataset of its own.
local source = Data
local worldPass = true

function Pipelines.install(data)
  source = data or Data
  local Schemas = require("src.mods.Schemas")
  worldPass = not Schemas.isGen3Data(source)
  Pipelines.reset()
end

-- Gen 3 has no pipeline world pass unless a record says it knows Gen 3's ctx
-- (`gen3 = true`): a Gen 1 pipeline's drawWorld stays inert there.
local function drawsWorld(def)
  return def.drawWorld ~= nil and (worldPass or def.gen3 == true)
end

local function inert(def)
  return def.drawWorld ~= nil and not drawsWorld(def) and def.present == nil
    and def.worldPresent == nil
end

-- ------- catalog

-- Every registered pipeline as { id = ..., def = ... }, ordered by priority
-- (descending, ties by id) so selection, the options rows and the present
-- fold all walk the same sequence.
--
-- Memoized on the namespace table's identity.  Content freezes at the merge
-- boundary, so the answer cannot change for a given table -- and this is
-- read several times per frame by update(), worldPipeline() and the
-- endFrame present check, which is no place to allocate and sort.  An empty
-- list is cached too, so a mod-free boot pays one table for the process.
local listCache, listSource = nil, nil

function Pipelines.list()
  local defs = source and source.render_pipelines
  if defs == listSource and listCache then return listCache end
  local out = {}
  if type(defs) == "table" then
    for id, def in pairs(defs) do
      -- the merge writes provenance under _owners; skip the bookkeeping
      -- keys rather than treating them as pipelines
      if type(id) == "string" and id:sub(1, 1) ~= "_" and type(def) == "table" then
        out[#out + 1] = { id = id, def = def }
      end
    end
    table.sort(out, function(a, b)
      local pa, pb = a.def.priority or 0, b.def.priority or 0
      if pa ~= pb then return pa > pb end
      return a.id < b.id
    end)
  end
  listCache, listSource = out, defs
  return out
end

function Pipelines.get(id)
  local defs = source and source.render_pipelines
  local def = type(defs) == "table" and defs[id] or nil
  return type(def) == "table" and def or nil
end

-- the mod that registered a pipeline, so a runtime failure lands in the
-- feed the mod manager shows instead of only in the console
local function ownerOf(id)
  local defs = source and source.render_pipelines
  local owners = type(defs) == "table" and defs._owners or nil
  return owners and owners[id] or nil
end

-- Run one of a pipeline's callbacks under pcall.  A mod that throws mid-
-- frame must not take the frame with it: the pipeline is marked broken,
-- attributed once, and treated as absent from then on -- which degrades to
-- the vanilla 2D path rather than a black screen.
local function guard(id, fn, ...)
  if broken[id] then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
  broken[id] = true
  Logger.error("render pipeline %s failed: %s -- disabled for this session",
               id, tostring(result))
  Runtime.reportError(ownerOf(id), "render pipeline failed: " .. tostring(result))
  return nil
end

-- Whether a callback's return is a real Canvas we can composite.  A mod that
-- forgets a return, or hands back a shade string / flag / number, must be
-- ignored rather than trusted -- draw() on a non-canvas takes the frame down.
-- Real LOVE canvases are userdata answering typeOf("Canvas"); the headless
-- test stub (tests/love_stub) fakes them as tables carrying the Canvas method
-- shape (love.graphics.newCanvas), so accept either and nothing else.
local function isCanvas(v)
  if type(v) == "userdata" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  if type(v) == "table" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  return false
end

-- Dispatch a mod render callback with its GPU state fenced off: push("all")
-- before and pop() after, so a callback that returns cleanly but leaves a
-- shader bound, the canvas redirected, or blend/colour changed cannot corrupt
-- the engine composite that follows.  guard() catches a callback that throws;
-- this catches one that dirties state.  A pipeline already retired skips the
-- push/pop entirely, so the stack stays balanced.
local function guardRender(id, fn, ...)
  if broken[id] then return nil end
  love.graphics.push("all")
  local out = guard(id, fn, ...)
  love.graphics.pop()
  return out
end

-- ------- levels

function Pipelines.levelLabels(id)
  local def = Pipelines.get(id)
  local labels = def and def.levels
  if type(labels) ~= "table" or labels[1] == nil then
    return Pipelines.DEFAULT_LEVELS
  end
  return labels
end

-- highest selectable level: one less than the label count, so a two-label
-- ladder is a plain OFF/ON toggle
function Pipelines.maxLevel(id)
  local max = #Pipelines.levelLabels(id) - 1
  -- a required pipeline is never OFF, so even a one-label ladder has a level 1
  local def = Pipelines.get(id)
  if def and def.required and max < 1 then max = 1 end
  return max
end

-- The lowest level a pipeline may sit at: 1 for a required one, else 0 (OFF).
local function floorLevel(def)
  return def.required and 1 or 0
end

function Pipelines.level(id)
  return levels[id] or 0
end

function Pipelines.levelLabel(id, level)
  local labels = Pipelines.levelLabels(id)
  return labels[(level or Pipelines.level(id)) + 1] or labels[1] or "OFF"
end

-- A world pipeline and the engine's own tilt mode are two answers to the
-- same question, so switching one on switches the other off -- the rule
-- tilt and survey zoom already follow between themselves.  Present-only
-- pipelines (post-processes) compose with tilt and are left alone.
local function excludeTilt(id, level)
  local def = Pipelines.get(id)
  if not (def and drawsWorld(def)) or level <= 0 then return end
  -- keepTilt: a pipeline that projects through the engine's Tilt state needs it
  if not def.keepTilt then
    local Tilt = require("src.render.Tilt")
    if Tilt.level > 0 then Tilt.setLevel(0) end
  end
  -- one world pipeline at a time, for the same reason
  for _, entry in ipairs(Pipelines.list()) do
    if entry.id ~= id and drawsWorld(entry.def) and not entry.def.required
        and Pipelines.level(entry.id) > 0 then
      levels[entry.id] = 0
    end
  end
end

-- A required world pipeline that is on: no other world pipeline may displace it.
local function requiredWorld(except)
  for _, entry in ipairs(Pipelines.list()) do
    if entry.id ~= except and entry.def.required and drawsWorld(entry.def)
        and Pipelines.level(entry.id) > 0 then
      return entry.id
    end
  end
  return nil
end

function Pipelines.setLevel(id, level)
  local def = Pipelines.get(id)
  if not def then return 0 end
  level = math.floor(tonumber(level) or 0)
  local floor = floorLevel(def)
  if level < floor then level = floor end
  local max = Pipelines.maxLevel(id)
  if level > max then level = max end
  if inert(def) then level = 0 end
  -- a required world pipeline keeps the world: another one cannot switch on
  if level > 0 and drawsWorld(def) and not def.required and requiredWorld(id) then
    level = 0
  end
  levels[id] = level
  excludeTilt(id, level)
  return level
end

-- The engine's Tilt is being switched on: world pipelines that exclude it
-- (no keepTilt) switch off, and `opts` is synced.  False when a required one
-- excludes it, so Tilt has to stay off.
function Pipelines.yieldToTilt(opts)
  local allowed = true
  for _, entry in ipairs(Pipelines.list()) do
    if drawsWorld(entry.def) and not entry.def.keepTilt and Pipelines.level(entry.id) > 0 then
      if entry.def.required then allowed = false else levels[entry.id] = 0 end
    end
  end
  Pipelines.syncOptions(opts)
  return allowed
end

-- Advance the ladder and wrap to OFF, the shape every display hotkey walks.
function Pipelines.cycle(id, dir)
  local max = Pipelines.maxLevel(id)
  if max < 1 then return 0 end
  local span = max + 1
  local target = (Pipelines.level(id) + (dir or 1)) % span
  if target < 0 then target = target + span end
  return Pipelines.setLevel(id, target)
end

-- Turning a world pipeline on must switch tilt off in the save too, not
-- just in the live module, or the next boot restores both.  Call sites hand
-- over the options table so this stays the one place that rule lives.
function Pipelines.syncOptions(opts)
  if type(opts) ~= "table" then return end
  local bucket = opts.pipelines
  if type(bucket) ~= "table" then
    bucket = {}
    opts.pipelines = bucket
  end
  for _, entry in ipairs(Pipelines.list()) do
    bucket[entry.id] = Pipelines.level(entry.id)
    if drawsWorld(entry.def) and not entry.def.keepTilt and Pipelines.level(entry.id) > 0 then
      opts.tilt = 0
    end
  end
end

-- Restore levels from a loaded options table.  A pipeline whose mod is gone
-- keeps its stored level untouched in the bucket (so re-enabling the mod
-- restores the mode) but contributes nothing while absent.
function Pipelines.applyOptions(opts)
  local bucket = type(opts) == "table" and opts.pipelines or nil
  levels = {}
  broken = {}
  for _, entry in ipairs(Pipelines.list()) do
    local stored = type(bucket) == "table" and bucket[entry.id] or nil
    if stored == nil then stored = entry.def.defaultLevel or 0 end
    local level = math.floor(tonumber(stored) or 0)
    local floor = floorLevel(entry.def)
    if level < floor then level = floor end
    local max = Pipelines.maxLevel(entry.id)
    if level > max then level = max end
    if inert(entry.def) then level = 0 end
    levels[entry.id] = level
  end
  -- One world pipeline at a time.  A required one wins; otherwise list() is
  -- priority order, so the first with a stored level wins.  The rest restore
  -- to OFF rather than sitting on a level that can never render.
  local world = nil
  for pass = 1, 2 do
    for _, entry in ipairs(Pipelines.list()) do
      if not world and drawsWorld(entry.def) and levels[entry.id] > 0
          and (pass == 2 or entry.def.required) then
        world = entry
      end
    end
  end
  for _, entry in ipairs(Pipelines.list()) do
    if entry ~= world and drawsWorld(entry.def) and not entry.def.required then
      levels[entry.id] = 0
    end
  end
  local dropTilt = world ~= nil and not world.def.keepTilt
  -- a restored world pipeline and tilt are two answers to the same
  -- question; the pipeline wins, as it does at every place that sets one
  if dropTilt then require("src.render.Tilt").setLevel(0) end
end

function Pipelines.reset()
  levels = {}
  broken = {}
end

-- ------- per-frame

-- Presentational tweens run on real frame time, like Tilt's.  Every
-- pipeline ticks, not just the active ones: a mode easing back OUT still
-- has an angle to retire.
function Pipelines.update(dt)
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.update then
      guardRender(entry.id, entry.def.update, dt, Pipelines.level(entry.id))
    end
  end
end

-- A pipeline may run this frame when it is switched on, has not thrown, and
-- its hardware gate says yes.  `available` is consulted every frame rather
-- than cached: a driver that loses its depth canvas on a resize has to be
-- able to change its mind.
--
-- Deliberately NOT gated on the state stack.  `gate` governs whether the
-- player may CHANGE the mode, never whether it draws -- a display mode that
-- stopped rendering during a warp, a scripted cutscene or an open menu
-- would flash the flat 2D world for those frames every time the player
-- walked through a door.  Once a mode is on it renders until it is off.
function Pipelines.eligible(id)
  local def = Pipelines.get(id)
  if not def or broken[id] or inert(def) then return false end
  if Pipelines.level(id) <= 0 then return false end
  if def.available and guard(id, def.available) ~= true then return false end
  return true
end

-- Whether the player may cycle this mode right now: the free-roam gate,
-- which keeps a hotkey press from switching modes mid-warp or mid-cutscene.
-- Input only -- see eligible() for why the draw path does not consult it.
function Pipelines.canToggle(id, top, overworld)
  local def = Pipelines.get(id)
  if not def or inert(def) then return false end
  local gate = def.gate or Zoom.gateOK
  return guard(id, gate, top, overworld) == true
end

-- The pipeline that owns the world pass right now, or nil for the vanilla
-- flat/tilt draw.  Highest priority wins; the exclusion rules above mean
-- there is normally only one candidate anyway.
function Pipelines.worldPipeline()
  for _, entry in ipairs(Pipelines.list()) do
    if drawsWorld(entry.def) and Pipelines.eligible(entry.id) then
      return entry.id, entry.def
    end
  end
  return nil
end

-- The ownsField pipeline that is switched on, or nil.  Unlike worldPipeline
-- this ignores `available` and retirement: while it is on, a frame it does
-- not draw is black rather than the engine's own map.
function Pipelines.fieldOwner()
  for _, entry in ipairs(Pipelines.list()) do
    -- a required one counts from install, before its level is restored
    if entry.def.ownsField and drawsWorld(entry.def)
        and (entry.def.required or Pipelines.level(entry.id) > 0) then
      return entry.id, entry.def
    end
  end
  return nil
end

-- Who draws the field's actors under a Gen 3 world pipeline: "engine" (the
-- upright pass still runs, into Renderer.uprightCanvas) or "mod" (it does not;
-- the pipeline draws them itself, e.g. with FieldView.draw's actorsOnly).
-- A record's `actors` may be either string or (level) -> string.
function Pipelines.actorMode(id)
  local def = Pipelines.get(id)
  local mode = def and def.actors
  if type(mode) == "function" then mode = guard(id, mode, Pipelines.level(id)) end
  return mode == "mod" and "mod" or "engine"
end

-- Render the world through `id`.  Returns the canvas to composite, or nil
-- when the pipeline declined this frame (nothing to draw, a transient
-- failure), which the caller treats as "fall back to the 2D path".
function Pipelines.drawWorld(id, ctx)
  local def = Pipelines.get(id)
  if not (def and def.drawWorld) then return nil end
  return guardRender(id, def.drawWorld, ctx)
end

-- Fold every eligible world post-process over a pipeline's world image,
-- before the UI composites on top.  This is where a depth-of-field or a
-- colour grade belongs when it must leave the dialog boxes and menus crisp;
-- `present` below is the whole-frame counterpart.  Only reachable once some
-- pipeline rendered the world, so it is gated on the overworld state the
-- same way drawWorld is.
function Pipelines.worldPresent(canvas, ctx)
  if canvas == nil then return nil end
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.worldPresent and Pipelines.eligible(entry.id) then
      local out = guardRender(entry.id, entry.def.worldPresent, canvas, ctx)
      -- accept only a real Canvas: a pass that returns a non-canvas (a
      -- forgotten return, a shade string) is ignored, not folded in
      if isCanvas(out) then canvas = out end
    end
  end
  return canvas
end

-- Fold every eligible post-process over the finished frame.  Present
-- pipelines are not gated on the overworld state -- a CRT curve or a colour
-- grade applies to menus and battles too -- so eligibility here is just
-- "switched on and available".  A pass that returns a non-canvas is
-- ignored rather than trusted, so a mod cannot blank the screen by
-- forgetting a return.
function Pipelines.present(canvas, ctx)
  if canvas == nil then return nil end
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.present and Pipelines.eligible(entry.id) then
      local out = guardRender(entry.id, entry.def.present, canvas, ctx)
      -- accept only a real Canvas: a pass that returns a non-canvas is
      -- ignored (docstring above), so a mod cannot blank or crash the frame
      -- by forgetting a return or handing back a truthy non-canvas
      if isCanvas(out) then canvas = out end
    end
  end
  return canvas
end

-- true when any present-only pass wants to run, so the composite path can
-- skip allocating a target it would not use
function Pipelines.wantsPresent()
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.present and Pipelines.eligible(entry.id) then return true end
  end
  return false
end

-- ------- input and UI

-- Cycle whichever pipeline claims `key`.  Returns the id when one did, so
-- the caller knows the key was consumed.  Checked after the engine's own
-- display hotkeys, so a mod can never shadow one.
function Pipelines.hotkey(key, top, overworld)
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.hotkey == key then
      -- the gate belongs here and nowhere else: it stops the player
      -- flipping modes mid-warp or mid-cutscene, and has no say over
      -- whether an already-on mode draws
      if Pipelines.canToggle(entry.id, top, overworld) then
        Pipelines.cycle(entry.id)
        return entry.id
      end
      return nil
    end
  end
  return nil
end

-- Options rows for every registered pipeline, in the same priority order,
-- in the descriptor shape src/ui/OptionRows.lua renders.
function Pipelines.rows(game)
  local rows = {}
  for _, entry in ipairs(Pipelines.list()) do
    local id = entry.id
    rows[#rows + 1] = {
      id = "pipeline:" .. id,
      label = entry.def.label or id:upper(),
      value = function() return Pipelines.levelLabel(id) end,
      step = function(g, dir)
        Pipelines.cycle(id, dir)
        local opts = g and g.save and g.save.options
        if opts then
          Pipelines.syncOptions(opts)
          -- the exclusion above may have switched tilt off; keep the live
          -- module in step with the option it just wrote
          require("src.render.Tilt").setLevel(opts.tilt or 0)
        end
        return true
      end,
    }
  end
  return rows
end

-- Drop every pipeline's GPU objects (window resize, hot reload).
function Pipelines.invalidate()
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def.invalidate then guardRender(entry.id, entry.def.invalidate) end
  end
end

return Pipelines

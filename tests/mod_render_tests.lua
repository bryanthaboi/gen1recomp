-- The rendering-pipeline seam, exercised through the public mod API.
--
-- A render pipeline is the one extension point that owns part of the
-- frame, so the properties worth pinning are the ones a mod cannot be
-- trusted to honor on its own: that a pipeline nobody switched on costs
-- nothing, that its callbacks are dispatched in priority order, and above
-- all that a mod which throws mid-frame degrades to the vanilla 2D path
-- instead of taking the frame down with it.
package.path = "./?.lua;./?/init.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
local Pipelines = require("src.render.Pipelines")
local Tilt = require("src.render.Tilt")

local S = require("tests.harness").suite("mod render")
local check, eq = S.check, S.eq

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

local function manifest(id, extra)
  local body = ('{"id":"%s","name":"%s","version":"1.0.0","api":2,' ..
                '"entry":"main.lua"%s}'):format(id, id, extra or "")
  return body
end

-- ------- schema: a record must actually do something

do
  local spec = Schemas.REGISTRIES.render_pipelines
  check(spec ~= nil, "the render_pipelines registry is in the catalog")
  eq(spec.semantics, "record", "render_pipelines merges as records")
  eq(spec.target, "render_pipelines", "render_pipelines writes to its own namespace")

  local ok = Schemas.check(spec, "render_pipelines", "good",
    { label = "GOOD", drawWorld = function() end }, "register")
  check(ok, "a drawWorld-only record validates")

  local okPresent = Schemas.check(spec, "render_pipelines", "grade",
    { label = "GRADE", present = function() end }, "register")
  check(okPresent, "a present-only record validates")

  local okBillboards = Schemas.check(spec, "render_pipelines", "billboards",
    { label = "BILLBOARDS", drawBillboards = function() end }, "register")
  check(okBillboards, "a drawBillboards-only record validates")

  -- the whole point of the record is to draw something
  local bad, err = Schemas.check(spec, "render_pipelines", "inert",
    { label = "INERT" }, "register")
  check(not bad, "a record with no draw callback is rejected")
  check(tostring(err):find("drawWorld", 1, true) ~= nil,
    "the rejection names the callbacks it wanted: " .. tostring(err))

  local wrong = Schemas.check(spec, "render_pipelines", "typo",
    { label = "T", drawWorld = "not a function" }, "register")
  check(not wrong, "a non-function draw callback is rejected")
end

-- ------- a mod registers two pipelines and the engine dispatches them

-- The probe table is the mod's, published through mod.exports: a mod's
-- globals are its own now (src/mods/Sandbox.lua).  The world/present folds
-- accept only a real Canvas, so the mod makes concrete ones to return and the
-- test pins identity through the dispatch.
local FILES = {
  ["mods/painter/manifest.json"] = manifest("painter", ',"priority":10'),
  ["mods/painter/main.lua"] = [[
    local mod = ...
    local T = mod.exports
    T.trace, T.available = {}, true
    T.worldOut = love.graphics.newCanvas(2, 2)
    T.blurOut = love.graphics.newCanvas(2, 2)
    T.gradeOut = love.graphics.newCanvas(2, 2)
    mod.content.render_pipelines:register("diorama", {
      label = "DIORAMA",
      levels = { "OFF", "LOW", "HIGH" },
      hotkey = "7",
      priority = 20,
      available = function() return T.available end,
      update = function(dt, level) T.trace[#T.trace + 1] = "update:" .. level end,
      drawWorld = function(ctx)
        T.trace[#T.trace + 1] = "world:" .. tostring(ctx.tag)
        return T.worldOut
      end,
      worldPresent = function(canvas)
        T.trace[#T.trace + 1] = "worldPresent"
        return T.blurOut
      end,
    })
    mod.content.render_pipelines:register("grade", {
      label = "GRADE",
      priority = 5,
      present = function(canvas)
        T.trace[#T.trace + 1] = "present"
        return T.gradeOut
      end,
    })
  ]],
}

local data = {}
local loader = Loader.new({ fs = memfs(FILES) })
local okLoad = loader:load(data)
check(okLoad, "the pipeline mod loads clean: " .. table.concat(loader.errors, "; "))
local RT = loader.exports.painter
local trace = RT.trace
Pipelines.install(data)

check(type(data.render_pipelines) == "table",
  "the merge created the render_pipelines namespace")
eq(data.render_pipelines._owners.diorama, "painter",
  "the merge stamped the owning mod for runtime attribution")

-- priority order, highest first, is what selection and the folds walk
local list = Pipelines.list()
eq(#list, 2, "both pipelines are catalogued")
eq(list[1].id, "diorama", "the higher-priority pipeline sorts first")
eq(list[2].id, "grade", "the lower-priority pipeline sorts second")
check(list[1].id ~= "_owners" and list[2].id ~= "_owners",
  "the provenance key is not mistaken for a pipeline")

-- ------- switched off costs nothing

eq(Pipelines.worldPipeline(), nil, "nothing owns the world while off")
eq(Pipelines.wantsPresent(), false, "no present pass is wanted while off")
eq(Pipelines.present("frame"), "frame", "present is identity while off")
eq(Pipelines.worldPresent("frame"), "frame", "worldPresent is identity while off")
eq(#trace, 0, "no callback ran for a switched-off pipeline")

-- update ticks every pipeline regardless, so a mode easing out still eases
Pipelines.update(0.016)
eq(trace[1], "update:0", "update ticks a switched-off pipeline")

-- ------- switched on, the callbacks dispatch

trace[1] = nil
Pipelines.setLevel("diorama", 2)
Pipelines.setLevel("grade", 1)

eq(Pipelines.worldPipeline(), "diorama",
  "the eligible world pipeline claims the world pass")
eq(Pipelines.drawWorld("diorama", { tag = "ctx" }), RT.worldOut,
  "drawWorld returns the mod's canvas")
eq(trace[#trace], "world:ctx", "drawWorld received the frame context")

eq(Pipelines.worldPresent(RT.worldOut), RT.blurOut,
  "worldPresent folds its canvas over the world image")
eq(Pipelines.wantsPresent(), true, "a live present pass asks for the canvas")
eq(Pipelines.present(RT.gradeOut), RT.gradeOut,
  "present folds its canvas over the finished composite")

-- ------- the hardware gate

RT.available = false
eq(Pipelines.worldPipeline(), nil,
  "an unavailable pipeline never takes the world pass")
eq(Pipelines.worldPresent("world-canvas"), "world-canvas",
  "an unavailable pipeline's worldPresent is skipped")
RT.available = true
eq(Pipelines.worldPipeline(), "diorama", "availability is re-read each frame")

-- ------- the gate governs input, never the draw
--
-- Regression: gating the DRAW on the free-roam state made the world drop
-- to the flat 2D path for the handful of frames a warp is transitioning,
-- so walking through a door flashed 2D before snapping back to 3D.  A mode
-- that is on renders until it is off; the gate only stops the player
-- CHANGING it at a bad moment.

Pipelines.setLevel("diorama", 2)

-- a state that every free-roam gate refuses: mid-warp, and running a script
local warping = { transitioning = true }
local overworld = warping
eq(Pipelines.canToggle("diorama", warping, overworld), false,
  "the gate refuses a mode change mid-warp")
eq(Pipelines.worldPipeline(), "diorama",
  "but the mode keeps rendering through the warp -- no 2D flash")

local scripted = { runner = { isRunning = function() return true end } }
eq(Pipelines.canToggle("diorama", scripted, scripted), false,
  "the gate refuses a mode change mid-cutscene")
eq(Pipelines.worldPipeline(), "diorama",
  "and the mode keeps rendering through the cutscene")

-- a menu on top of the overworld is not the overworld, so the gate refuses
-- there too -- and the world beneath it must still be the 3D one
eq(Pipelines.canToggle("diorama", { menu = true }, overworld), false,
  "the gate refuses a mode change from a menu")
eq(Pipelines.worldPipeline(), "diorama",
  "the world under an open menu keeps rendering in the pipeline")

eq(Pipelines.hotkey("7", warping, overworld), nil,
  "a hotkey press mid-warp is refused")
eq(Pipelines.level("diorama"), 2, "and the refused press changed no level")

-- ------- mutual exclusion

Tilt.setLevel(3)
Pipelines.setLevel("diorama", 1)
eq(Tilt.level, 0, "a world pipeline switches the engine's TILT off")
Tilt.setLevel(0)

-- ------- a throwing mod loses its pipeline, not the frame

local BOOM = {
  ["mods/boom/manifest.json"] = manifest("boom"),
  ["mods/boom/main.lua"] = [[
    local mod = ...
    mod.content.render_pipelines:register("boom", {
      label = "BOOM",
      drawWorld = function() error("pipeline exploded", 0) end,
    })
  ]],
}
local boomData = {}
local boomLoader = Loader.new({ fs = memfs(BOOM) })
boomLoader:load(boomData)
Pipelines.install(boomData)
Pipelines.setLevel("boom", 1)

eq(Pipelines.worldPipeline(), "boom", "the pipeline is eligible before it throws")
eq(Pipelines.drawWorld("boom", {}), nil,
  "a throwing drawWorld yields nil, so the caller falls back to 2D")
eq(Pipelines.worldPipeline(), nil,
  "a pipeline that threw is retired rather than retried every frame")

-- the failure has to reach the feed the mod manager shows, named after the
-- mod that owns it -- a console line alone leaves the player with a world
-- that silently stopped being 3D and nothing to disable
local blamed = nil
for _, message in ipairs(boomLoader.errors) do
  if message:find("boom:", 1, true) and message:find("pipeline exploded", 1, true) then
    blamed = message
  end
end
check(blamed ~= nil,
  "the runtime failure is attributed to its mod in the manager's error feed")

-- ------- a non-canvas return is ignored, and a dirty callback cannot leak
--
-- The fold composites only a real Canvas, so a present that forgets its
-- return -- or hands back a truthy shade string, flag or number -- must leave
-- the composite untouched rather than blank or crash the frame.  Unlike a
-- throw, a clean-but-useless return is NOT a crash, so the pipeline stays
-- eligible instead of being retired.  Separately, a callback that returns
-- cleanly while leaving a shader bound or the canvas redirected must not leak
-- that state into the engine composite that follows: the fold fences each
-- dispatch in push("all")/pop.

local SLOPPY = {
  ["mods/sloppy/manifest.json"] = manifest("sloppy"),
  ["mods/sloppy/main.lua"] = [[
    local mod = ...
    local T = mod.exports
    T.ran = 0
    mod.content.render_pipelines:register("sloppy", {
      label = "SLOPPY",
      present = function(canvas)
        T.ran = (T.ran or 0) + 1
        return T.ret
      end,
    })
    mod.content.render_pipelines:register("dirty", {
      label = "DIRTY",
      present = function(canvas)
        love.graphics.setShader("mod-shader")
        love.graphics.setCanvas("mod-canvas")
        love.graphics.setColor(0.1, 0.2, 0.3, 0.4)
        love.graphics.setBlendMode("add")
        return canvas
      end,
    })
  ]],
}
local sloppyData = {}
local sloppyLoader = Loader.new({ fs = memfs(SLOPPY) })
sloppyLoader:load(sloppyData)
local SL = sloppyLoader.exports.sloppy
Pipelines.install(sloppyData)

local composite = love.graphics.newCanvas(4, 4)
Pipelines.setLevel("sloppy", 1)
for _, bad in ipairs({ "just-a-string", true, 42 }) do
  SL.ret = bad
  eq(Pipelines.present(composite), composite,
    "a present returning a " .. type(bad) .. " leaves the composite untouched")
end
check(SL.ran == 3, "the present callback still ran each frame")
check(Pipelines.eligible("sloppy") == true,
  "a non-canvas return does not retire the pipeline as broken")
Pipelines.setLevel("sloppy", 0)

love.graphics.setShader("engine-shader")
love.graphics.setCanvas("engine-canvas")
love.graphics.setBlendMode("alpha")
love.graphics.setColor(1, 1, 1, 1)
Pipelines.setLevel("dirty", 1)
eq(Pipelines.present(composite), composite,
  "a dirty present that returns its input leaves the composite unchanged")
eq(love.graphics.getShader(), "engine-shader",
  "a present that bound a shader cannot leak it past the fold")
eq(love.graphics.getCanvas(), "engine-canvas",
  "a present that redirected the canvas cannot leak it past the fold")
eq(love.graphics.getBlendMode(), "alpha",
  "a present that changed blend mode cannot leak it past the fold")
Pipelines.setLevel("dirty", 0)

-- ------- additive TILT billboards dispatch without claiming the world

local billboardCtx = { tag = "tilt" }
local billboardSeen, billboardLevel = nil, nil
Pipelines.install({
  render_pipelines = {
    billboards = {
      label = "BILLBOARDS",
      drawBillboards = function(ctx)
        billboardSeen = ctx
        billboardLevel = ctx.level
      end,
    },
  },
})
Pipelines.setLevel("billboards", 1)
check(Pipelines.wantsBillboards(),
  "an enabled additive billboard stage is discoverable")
Pipelines.drawBillboards(billboardCtx)
eq(billboardSeen, billboardCtx,
  "drawBillboards receives the owning TILT frame context")
eq(billboardLevel, 1,
  "drawBillboards receives its pipeline's configured level")

Pipelines.reset()
Pipelines.install(nil)

-- ------- and with no mods at all, the whole subsystem is inert

eq(#Pipelines.list(), 0, "a mod-free boot registers no pipelines")
eq(Pipelines.worldPipeline(), nil, "a mod-free boot draws the vanilla world")
eq(Pipelines.wantsPresent(), false, "a mod-free boot allocates no present canvas")
eq(Pipelines.present("frame"), "frame", "a mod-free present is the identity")
eq(#Pipelines.rows({}), 0, "a mod-free options menu gains no rows")
eq(Pipelines.hotkey("6", nil, nil), nil, "a mod-free build claims no hotkeys")

S.finish()

-- A required render pipeline on Gen 3: never OFF, keeps the world from other
-- world pipelines, and keeps or refuses the engine's Tilt by keepTilt.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

love = love or {}
love.graphics = love.graphics or {}
for _, name in ipairs({ "push", "pop" }) do love.graphics[name] = function() end end

local Tilt = { level = 0 }
function Tilt.setLevel(level) Tilt.level = level end
package.loaded["src.render.Tilt"] = Tilt
package.loaded["src.mods.Runtime"] = { reportError = function() end, wantsHook = function() return false end }

local Schemas = require("src.mods.Schemas")
local Pipelines = require("src.render.Pipelines")

local canvas = { getWidth = function() return 1 end, getHeight = function() return 1 end }
local function draw() return canvas end

local function install(records)
  local data = { render_pipelines = records }
  Schemas.bindGen3(data, "firered")
  Pipelines.install(data)
end

-- 1. never OFF, and higher levels still reachable
install({
  must = { label = "M", gen3 = true, required = true, priority = 1,
    levels = { "OFF", "LOW", "HIGH" }, drawWorld = draw },
  other = { label = "O", gen3 = true, priority = 9, drawWorld = draw },
})
Pipelines.applyOptions({ pipelines = { must = 0, other = 1 } })
check(Pipelines.level("must") == 1, "a stored OFF restores a required pipeline at 1")
check(Pipelines.level("other") == 0, "a required pipeline wins the world over a higher priority one")
check(Pipelines.worldPipeline() == "must", "the required pipeline owns the world")
Pipelines.applyOptions({ pipelines = { must = 2 } })
check(Pipelines.level("must") == 2, "a stored higher level is kept")
check(Pipelines.setLevel("must", 0) == 1, "setLevel cannot switch a required pipeline OFF")
check(Pipelines.setLevel("must", 2) == 2, "setLevel reaches a required pipeline's higher levels")
check(Pipelines.cycle("must", 1) == 1, "cycling wraps to 1, not OFF")

-- 2. another world pipeline cannot displace it
check(Pipelines.setLevel("other", 1) == 0, "another world pipeline cannot switch on")
check(Pipelines.level("must") == 1, "the required pipeline stays on")

-- 3. a one-label ladder is still on
install({
  only = { label = "ONLY", gen3 = true, required = true, levels = { "ON" }, drawWorld = draw },
})
Pipelines.applyOptions({})
check(Pipelines.level("only") == 1, "a one-label required ladder restores on")
check(Pipelines.setLevel("only", 0) == 1, "a one-label required ladder stays on")
check(Pipelines.levelLabel("only") == "ON", "its level reads as its one label")

-- 4. Tilt: keepTilt allows it, otherwise a required pipeline refuses it
install({
  keeps = { label = "K", gen3 = true, required = true, keepTilt = true, drawWorld = draw },
})
Tilt.level = 2
Pipelines.applyOptions({ tilt = 2 })
check(Tilt.level == 2, "keepTilt leaves a restored Tilt on")
check(Pipelines.yieldToTilt({ tilt = 2 }) == true, "keepTilt lets Tilt switch on")

install({
  owns = { label = "W", gen3 = true, required = true, drawWorld = draw },
  soft = { label = "S", gen3 = true, priority = 5, drawWorld = draw },
})
Pipelines.applyOptions({ tilt = 2 })
check(Tilt.level == 0, "a required pipeline without keepTilt switches a restored Tilt off")
local opts = { tilt = 2 }
check(Pipelines.yieldToTilt(opts) == false, "a required pipeline without keepTilt refuses Tilt")
check(opts.tilt == 0, "and the saved tilt is put back to 0")

install({
  soft = { label = "S", gen3 = true, drawWorld = draw },
})
Pipelines.applyOptions({ pipelines = { soft = 1 } })
opts = { tilt = 2 }
check(Pipelines.yieldToTilt(opts) == true, "Tilt may switch on over an optional world pipeline")
check(Pipelines.level("soft") == 0 and opts.pipelines.soft == 0, "which switches off, in the save too")

print((failures == 0 and "PASS " or "FAIL ") .. "game3_pipeline_required_test")
os.exit(failures == 0 and 0 or 1)

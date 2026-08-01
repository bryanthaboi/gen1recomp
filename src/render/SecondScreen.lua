-- Thin helper around love.system.hasSecondaryDisplay/presentUIFrame (see
-- mobile/android/love/src/jni/love/src/common/android.cpp and
-- GameActivity.java) for UI that lives on the AYN Thor's bottom panel
-- instead of the main GB screen. Reuses the main screen's 160x144
-- coordinate space so callers can draw with the same Font.* calls they'd
-- use on the primary canvas; the Java side scales the pushed frame to fill
-- whatever the panel's actual resolution is.
--
-- Uses PixelCanvas (not a plain love.graphics.newCanvas) because LÖVE
-- always runs highdpi on Android (conf.lua) -- an undpiscaled canvas
-- allocates its backing texture at the device's DPI-scaled size, not the
-- WIDTH/HEIGHT asked for, so newImageData()'s buffer length would silently
-- mismatch the w*h*4 this module tells the native side to expect and every
-- frame would get dropped by the size check in android.cpp.
local PixelCanvas = require("src.render.PixelCanvas")

local SecondScreen = {}

-- The main GB screen's own size; the default for callers that don't need
-- anything larger (e.g. src/render/PartyStatusHUD.lua).
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 160, 144
local PUSH_EVERY_N_FRAMES = 3 -- canvas readback stalls the GPU; menus are
                               -- mostly static so this stays responsive

local canvas
local canvasW, canvasH
local frame = 0

-- Options row: ENABLE DS (src/ui/OptionsMenu.lua). Defaults on -- this
-- whole module is already inert everywhere without
-- love.system.hasSecondaryDisplay hardware, so opting out is the rare
-- case, not the common one.
local enabled = true

-- Reads options.enableDS; Game:applyOptions calls this at boot and
-- whenever options change, same as PaletteFX.applyOptions/Tilt.applyOptions
-- etc. On a disabled transition, pushes one blank frame so the panel goes
-- visibly inert instead of freezing on whatever it last drew.
function SecondScreen.applyOptions(opts)
  local want = (opts and opts.enableDS) ~= false
  if enabled and not want and canvas
     and love.system.hasSecondaryDisplay and love.system.hasSecondaryDisplay() then
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.pop()
    love.system.presentUIFrame(canvas:newImageData():getString(), canvasW, canvasH)
  end
  enabled = want
end

function SecondScreen.available()
  return enabled and love.system.hasSecondaryDisplay ~= nil
    and love.system.hasSecondaryDisplay()
end

-- Switches love.graphics onto the second-screen canvas, sized w x h
-- (defaulting to the main screen's own 160x144 -- pass explicit ones for a
-- taller/wider layout, e.g. BattleState's stacked dialogue/controls
-- canvas). Pair with finish() once the caller's draw calls are done;
-- push("all")/pop("all") means whatever canvas/color/scissor/transform was
-- active before is restored afterward, so this nests safely inside an
-- in-progress main-screen draw. The cached canvas is only recreated when
-- the requested size actually changes, so callers sharing the default
-- size never pay for a caller that asked for something bigger.
function SecondScreen.begin(w, h)
  w, h = w or DEFAULT_WIDTH, h or DEFAULT_HEIGHT
  if not canvas or canvasW ~= w or canvasH ~= h then
    canvas = PixelCanvas.new(w, h)
    canvasW, canvasH = w, h
  end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  -- White, not black: every panel drawn here (Font.drawBox's own fill,
  -- PartyStatusHUD's bordered panel) is white-on-black-border GB style,
  -- so a black clear only showed as a stray dark void in whatever gap
  -- wasn't covered by a panel that frame.
  love.graphics.clear(1, 1, 1, 1)
  return canvas
end

function SecondScreen.finish()
  love.graphics.pop()
  frame = frame + 1
  if frame % PUSH_EVERY_N_FRAMES ~= 0 then return end
  local imageData = canvas:newImageData()
  love.system.presentUIFrame(imageData:getString(), canvasW, canvasH)
end

return SecondScreen

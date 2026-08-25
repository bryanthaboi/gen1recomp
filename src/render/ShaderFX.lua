-- ShaderFX: runtime libretro slang-shader presets. Translated ahead of time
-- into a cached Lua artifact, then run as a LOVE canvas pass-graph over the
-- finished frame. Two independent slots, "main" and "secondary", chain in
-- that order. See docs/shaderfx.md.

local ShaderFX = {}

local Json = require("src.link.Json")
local SaveData = require("src.core.SaveData")
local Performance = require("src.core.Performance")

-- ------- preset discovery: the local drop-in folder

-- A real OS path, not a love.filesystem mount: the native bridge and the LUT
-- loads both read it directly.
function ShaderFX.presetDir()
  local base = (SaveData.portableBaseDir and SaveData.portableBaseDir())
    or (love.filesystem and love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory())
  if not base then return nil end
  local sep = package.config:sub(1, 1)
  return base .. sep .. "shaders"
end

function ShaderFX.list()
  local dir = ShaderFX.presetDir()
  if not dir then return {} end
  love.filesystem.createDirectory("shaders")
  local out = {}
  local function scan(relPath)
    local items = love.filesystem.getDirectoryItems(relPath)
    for _, name in ipairs(items) do
      local rel = relPath .. "/" .. name
      local info = love.filesystem.getInfo(rel)
      if info and info.type == "directory" then
        scan(rel)
      elseif name:match("%.slangp$") then
        local entry = { name = name, relPath = rel, fullPath = dir .. rel:gsub("^shaders", "") }
        entry.converted = ShaderFX.isConverted(entry)
        out[#out + 1] = entry
      end
    end
  end
  local ok, err = pcall(scan, "shaders")
  if not ok then
    require("src.core.Logger").error("ShaderFX.list: scan failed: %s", tostring(err))
    return {}
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function ShaderFX.artifactPath(entry)
  return (entry.fullPath:gsub("%.slangp$", ".lua"))
end

-- A real OS path outside any love.filesystem mount, so io.open, not getInfo.
function ShaderFX.isConverted(entry)
  local f = io.open(ShaderFX.artifactPath(entry), "rb")
  if not f then return false end
  f:close()
  return true
end

-- ------- buildbot download: the second acquisition path, alongside the
-- local drop-in folder above. Downloaded presets arrive unconverted.
ShaderFX.BUILDBOT_URL = "https://buildbot.libretro.com/assets/frontend/shaders_slang.zip"

local DOWNLOAD_ZIP_REL = "shaderfx_buildbot.zip"
local DOWNLOAD_MOUNT = "shaderfx_buildbot_mount"
-- The buildbot's own ETag, replayed as If-None-Match so a repeat download
-- that changed nothing costs one small request instead of the full transfer.
local DOWNLOAD_ETAG_REL = "shaderfx_buildbot.etag"

-- Returns a Fetch job id; poll it with ShaderFX.downloadStatus(). A status of
-- "ok" with .notModified true means nothing was re-downloaded.
function ShaderFX.downloadPresets()
  return require("src.net.Fetch").download(ShaderFX.BUILDBOT_URL, DOWNLOAD_ZIP_REL,
    { etagRel = DOWNLOAD_ETAG_REL })
end

function ShaderFX.downloadStatus(jobId)
  return require("src.net.Fetch").poll(jobId)
end

-- Collapses "." and ".." segments; Lua has no stdlib equivalent.
local function normalizePath(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        parts[#parts] = nil
      else
        parts[#parts + 1] = ".."
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or ""
end

-- .png (a LUT) is a real dependency but never itself a source of references.
local TEXT_EXT = { slang = true, slangp = true, inc = true, h = true }
local REF_EXT = { slang = true, slangp = true, inc = true, h = true, png = true }

-- Quoted assignments are matched first: the closing quote is an unambiguous
-- delimiter, so a path with spaces or parens survives (real packs ship them).
local function extractRefs(text)
  local refs, seen = {}, {}
  local function addPathRef(path)
    local ext = path:match("%.(%a+)$")
    if ext and REF_EXT[ext:lower()] and not seen[path] then
      seen[path] = true
      refs[#refs + 1] = path
    end
  end
  for line in text:gmatch("[^\r\n]+") do
    local quoted = line:match('=%s*"([^"]+)"')
    if quoted then
      addPathRef(quoted)
    else
      local bare = line:match('=%s*([%.%w/_%-]+)')
      if bare then addPathRef(bare) end
    end
  end
  for path in text:gmatch('#include%s+"([^"]+)"') do
    if not seen[path] then seen[path] = true; refs[#refs + 1] = path end
  end
  for path in text:gmatch('#reference%s+"([^"]+)"') do
    if not seen[path] then seen[path] = true; refs[#refs + 1] = path end
  end
  return refs
end

local function findAll(dir, pattern)
  local out = {}
  local function scan(rel)
    for _, name in ipairs(love.filesystem.getDirectoryItems(rel)) do
      local sub = rel .. "/" .. name
      local info = love.filesystem.getInfo(sub)
      if info and info.type == "directory" then
        scan(sub)
      elseif name:match(pattern) then
        out[#out + 1] = sub
      end
    end
  end
  scan(dir)
  return out
end

-- Curated shortlist of handheld/'s own 78 presets -- a temporary trim, expect
-- this list to change (see docs/shaderfx.md).
local KEPT_PRESETS = {
  ["gameboy.slangp"] = true,
  ["gameboy-advance-dot-matrix.slangp"] = true,
  ["gameboy-color-dot-matrix.slangp"] = true,
  ["gameboy-color-dot-matrix-white-bg.slangp"] = true,
  ["gameboy-dark-mode.slangp"] = true,
  ["gameboy-light.slangp"] = true,
  ["gameboy-light-mode.slangp"] = true,
  ["gameboy-pocket.slangp"] = true,
  ["gameboy-pocket-high-contrast.slangp"] = true,
  ["gb-palette-dmg.slangp"] = true,
  ["gb-palette-light.slangp"] = true,
  ["gb-palette-pocket.slangp"] = true,
  ["sameboy-lcd.slangp"] = true,
  ["dot.slangp"] = true,
  ["lcd1x.slangp"] = true,
  ["lcd1x_nds.slangp"] = true,
  ["lcd1x_psp.slangp"] = true,
  ["lcd3x.slangp"] = true,
  ["simpletex_lcd.slangp"] = true,
  ["simpletex_lcd_720p.slangp"] = true,
  ["simpletex_lcd-4k.slangp"] = true,
  ["zfast-lcd.slangp"] = true,
  ["bevel.slangp"] = true,
  ["sunlight_shimmer.slangp"] = true,
  ["pixel_transparency.slangp"] = true,
  ["retro-v3.slangp"] = true,
}

-- BFS over the real file-level dependency closure of every KEPT_PRESETS entry
-- inside the mounted zip, copied preserving each file's zip-relative path.
local function extractClosure(mountRoot)
  local queue = {}
  for _, s in ipairs(findAll(mountRoot .. "/handheld", "%.slangp$")) do
    if KEPT_PRESETS[s:match("([^/]+)$")] then queue[#queue + 1] = s end
  end
  local closure = {}
  for _, s in ipairs(queue) do closure[s] = true end

  local head = 1
  while queue[head] do
    local rel = queue[head]
    head = head + 1
    local zipRel = rel:sub(#mountRoot + 2) -- strip "<mountRoot>/"
    local ext = zipRel:match("%.(%a+)$")
    if ext and TEXT_EXT[ext:lower()] then
      local text = love.filesystem.read(rel)
      if text then
        local base = dirname(zipRel)
        for _, ref in ipairs(extractRefs(text)) do
          local resolved = normalizePath(base == "" and ref or (base .. "/" .. ref))
          local mounted = mountRoot .. "/" .. resolved
          if not closure[mounted] and love.filesystem.getInfo(mounted) then
            closure[mounted] = true
            queue[#queue + 1] = mounted
          end
        end
      end
    end
  end

  -- love.filesystem.write does not create intermediate directories.
  local madeDirs = {}
  local function ensureDir(destPath)
    local dir = dirname(destPath)
    if dir == "" or madeDirs[dir] then return end
    madeDirs[dir] = true
    love.filesystem.createDirectory(dir)
  end

  local copied = 0
  for rel in pairs(closure) do
    local destPath = "shaders/" .. rel:sub(#mountRoot + 2)
    local bytes = love.filesystem.read(rel)
    if bytes then
      ensureDir(destPath)
      if love.filesystem.write(destPath, bytes) then copied = copied + 1 end
    end
  end
  return copied
end

-- Returns the number of files copied, or nil + an error string; a third
-- `unchanged` return means the ETag matched and no zip was ever written.
function ShaderFX.installDownloaded(notModified)
  if notModified then
    return 0, nil, true
  end
  love.filesystem.createDirectory("shaders")
  if not love.filesystem.mount(DOWNLOAD_ZIP_REL, DOWNLOAD_MOUNT) then
    return nil, "could not open the downloaded archive"
  end
  local ok, copiedOrErr = pcall(extractClosure, DOWNLOAD_MOUNT)
  -- unmount() takes the ARCHIVE path passed to mount(), not the mountpoint.
  love.filesystem.unmount(DOWNLOAD_ZIP_REL)
  love.filesystem.remove(DOWNLOAD_ZIP_REL)
  if not ok then return nil, tostring(copiedOrErr) end
  return copiedOrErr
end

-- ------- the native bridge (translation only, called by convert())

-- Where the vendored Rust bridge crate builds to, relative to the source dir.
ShaderFX.BRIDGE_DIR = "tools/shaderfx-bridge"

-- Candidate names per OS, same shape as src/net/Gen1Tls.lua's libNames.
local function libNames()
  local osName = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  if osName == "iOS" then
    return {}
  elseif osName == "Windows" then
    return { "librashader_bridge.dll" }
  elseif osName == "OS X" then
    return { "liblibrashader_bridge.dylib", "librashader_bridge.dylib" }
  end
  -- Android resolves the bare name through jniLibs, so try it last.
  return { "liblibrashader_bridge.so", "librashader_bridge.so" }
end

-- getSource is the game directory (where the vendored crate sits); the base
-- directory is its parent (where a packaged build puts the library).
local function sourceDirs()
  local out, seen = {}, {}
  local function add(dir)
    if type(dir) == "string" and dir ~= "" and not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  local fs = love and love.filesystem
  if fs then
    if fs.getSource then add(fs.getSource()) end
    if fs.getSourceBaseDirectory then add(fs.getSourceBaseDirectory()) end
    if fs.getWorkingDirectory then add(fs.getWorkingDirectory()) end
  end
  if type(arg) == "table" and type(arg[0]) == "string" then
    add(arg[0]:match("^(.*)[/\\]"))
  end
  add(".")
  return out
end

local function saveDir()
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local dir = love.filesystem.getSaveDirectory()
    if type(dir) == "string" and dir ~= "" then return dir end
  end
  return nil
end

local function fileReadable(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

-- Every place the bridge may sit, most specific first.
local function libCandidates()
  local names = libNames()
  if #names == 0 then return {} end
  local out = {}
  local override = os.getenv("LIBRASHADER_BRIDGE_DLL")
  if override and override ~= "" then out[#out + 1] = override end
  local dirs, save = sourceDirs(), saveDir()
  for _, name in ipairs(names) do
    for _, dir in ipairs(dirs) do
      out[#out + 1] = dir .. "/" .. name
      out[#out + 1] = dir .. "/" .. ShaderFX.BRIDGE_DIR .. "/target/release/" .. name
    end
    if save then out[#out + 1] = save .. "/" .. name end
    out[#out + 1] = name
  end
  return out
end

local lib
local libError

local function ensureLib()
  if lib then return lib end
  if libError then return nil, libError end
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi or type(ffi) ~= "table" then
    libError = "this build has no ffi, so presets cannot be converted here"
    return nil, libError
  end
  pcall(ffi.cdef, [[
    char* librashader_translate_preset(const char* preset_path, int es);
    void librashader_free_string(char* s);
  ]])
  local tried = {}
  for _, path in ipairs(libCandidates()) do
    -- A bare name goes to the system loader; a path only when a file is there.
    local bare = not path:find("[/\\]")
    if bare or fileReadable(path) then
      local ok, loaded = pcall(ffi.load, path)
      if ok then lib = loaded; return lib end
    end
    tried[#tried + 1] = path
  end
  local okSym, sym = pcall(function()
    return ffi.C and ffi.C.librashader_translate_preset
  end)
  if okSym and sym ~= nil then
    lib = ffi.C
    return lib
  end
  libError = "librashader bridge not found; ffi.C has no librashader_translate_preset"
  if #tried > 0 then
    libError = libError .. "; looked in " .. table.concat(tried, ", ")
  end
  return nil, libError
end

-- True when a preset can be converted on this machine. Activating an
-- already-converted preset never needs the bridge.
function ShaderFX.canConvert()
  local l = ensureLib()
  return l ~= nil
end

function ShaderFX.bridgeError()
  return libError
end

-- `es`: true for GLSL ES 1.00 (mobile), false for GLSL 1.20 (desktop). Only
-- ever called from ShaderFX.convert().
function ShaderFX.translate(fullPath, es)
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi or type(ffi) ~= "table" then
    return nil, "this build has no ffi, so presets cannot be converted here"
  end
  local ok, l, lerr = pcall(ensureLib)
  if not ok then return nil, "ffi.load failed: " .. tostring(l) end
  if not l then return nil, tostring(lerr or libError or "librashader bridge not available") end
  local ptr = l.librashader_translate_preset(fullPath, es and 1 or 0)
  if ptr == nil then return nil, "librashader_translate_preset returned NULL" end
  local json = ffi.string(ptr)
  l.librashader_free_string(ptr)
  local preset, decodeErr = Json.decode(json)
  if not preset then return nil, "JSON decode failed: " .. tostring(decodeErr) end
  if preset.error then return nil, "translate_preset reported an error: " .. tostring(preset.error) end
  if preset.pass_count ~= #preset.passes then
    return nil, ("pass_count metadata (%s) disagrees with passes array length (%d)")
      :format(tostring(preset.pass_count), #preset.passes)
  end
  return preset
end

-- love.graphics.newImage cannot open an absolute path outside LOVE's own
-- mounts, which is where a preset's LUTs live, so read the bytes by hand.
function ShaderFX.loadImageFromPath(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, "io.open failed: " .. tostring(err) end
  local bytes = f:read("*a")
  f:close()
  local byteData = love.data.newByteData(bytes)
  local imgData = love.image.newImageData(byteData)
  return love.graphics.newImage(imgData)
end

-- librashader's wrap_mode names are not LOVE's; ES3-legal set only.
local function loveWrapMode(w)
  if w == "clamp_to_border" then return "clampzero"
  elseif w == "clamp_to_edge" then return "clamp"
  elseif w == "repeat" then return "repeat"
  elseif w == "mirrored_repeat" then return "mirroredrepeat"
  else error("loveWrapMode: unknown wrap_mode " .. tostring(w)) end
end

-- Called once per activate(). A LUT that fails to load is logged and left nil;
-- runPass's own sampler assert is the fail-loud point, not this.
local function loadLuts(preset)
  local byName = {}
  for _, t in ipairs(preset.textures) do
    local img, err = ShaderFX.loadImageFromPath(t.path)
    if img then
      img:setFilter(t.filter_mode, t.filter_mode)
      img:setWrap(loveWrapMode(t.wrap_mode))
    else
      require("src.core.Logger").error("ShaderFX: LUT %s (%s) failed to load: %s",
        t.name, tostring(t.path), tostring(err))
    end
    byName[t.name] = img
  end
  return byName
end

-- ------- the pass-graph runtime

local Fixup = require("src.render.ShaderFixup")
local Sensors = require("src.core.Sensors")
local ShaderSourcePatches = require("src.render.ShaderSourcePatches")

-- Glsl100Es (mobile) vs Glsl120 (desktop). Convert and render always run on
-- the same device, so the dialect emitted and the one validated always agree.
local function defaultEs()
  if not love or not love.system or not love.system.getOS then return false end
  local osName = love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

local function roundDim(x) return math.max(1, math.floor(x + 0.5)) end

local function resolveScale(scaling, viewportDim, inputDim, originalDim)
  local st = scaling.scale_type
  if st == "absolute" then return roundDim(scaling.factor)
  elseif st == "viewport" then return roundDim(viewportDim * scaling.factor)
  elseif st == "source" then return roundDim(inputDim * scaling.factor)
  elseif st == "original" then return roundDim(originalDim * scaling.factor)
  else error("resolveScale: unknown scale_type " .. tostring(st)) end
end

local function sizeVec(dims) return { dims.w, dims.h, 1 / dims.w, 1 / dims.h } end

-- One instance per loaded preset, never module-global, so switching presets
-- cannot leak a previous preset's canvases or dims.
local function newChainState(preset)
  local state = { preset = preset, outputDims = {}, ALL_DEFAULTS = {},
                   shaderCache = {}, canvasCache = {} }
  for _, pass in ipairs(preset.passes) do
    for _, p in ipairs(pass.parameters) do state.ALL_DEFAULTS[p.id] = p.initial end
  end
  for _, o in ipairs(preset.parameter_overrides) do state.ALL_DEFAULTS[o.name] = o.value end
  return state
end

local function passInputDims(state, i, original)
  return (i == 0) and original or assert(state.outputDims[i - 1],
    ("pass%d: input dims requested before pass%d ran"):format(i, i - 1))
end

local function computePassDims(state, i, pass, viewport, original)
  local inputDims = passInputDims(state, i, original)
  return {
    w = resolveScale(pass.scale_x, viewport.w, inputDims.w, original.w),
    h = resolveScale(pass.scale_y, viewport.h, inputDims.h, original.h),
  }
end

-- love.sensor.SensorType each built-in motion semantic reads from.
-- AccelerometerRest is librashader's calibration reference, not a real kind.
local SENSOR_KIND = { Accelerometer = "accelerometer", Gyroscope = "gyroscope" }

-- Yaw integration: deliberately a decaying spring, not a true heading --
-- gyro-only integration drifts without a magnetometer. Tuned on-device.
local YAW_SHADER_NAME = "sunlight_shimmer.slangp" -- the only twist-reactive preset
local YAW_GAIN = 0.6
local YAW_TWIST_CLAMP = 2
local YAW_DECAY_PER_SEC = 2.0 -- higher = snaps back to neutral faster

-- Throttled on-device diagnostic (~1/sec per slot), tagged for logcat.
local debugLastLog = {}
local function debugThrottle(key)
  local now = love.timer and love.timer.getTime() or os.clock()
  if not debugLastLog[key] or now - debugLastLog[key] >= 1.0 then
    debugLastLog[key] = now
    return true
  end
  return false
end

local function updateYawTwist(state, dt)
  if not state or state.entryName ~= YAW_SHADER_NAME then return end
  local gx, yawRate, gz = Sensors.read("gyroscope")
  local twist = (state.yawTwist or 0) + yawRate * dt * YAW_GAIN
  twist = twist * math.exp(-YAW_DECAY_PER_SEC * dt)
  twist = math.max(-YAW_TWIST_CLAMP, math.min(YAW_TWIST_CLAMP, twist))
  state.yawTwist = twist
  if debugThrottle("yaw:" .. tostring(state.entryName)) then
    require("src.core.Logger").info(
      "[DEBUG-tfxsns2] yaw entry=%s gyro=(%.3f,%.3f,%.3f) dt=%.4f twist=%.4f",
      tostring(state.entryName), gx, yawRate, gz, dt, twist)
  end
end

local function sizeTable(state, i, dims, sizeUniforms, viewport, original)
  local values = {
    OutputSize = sizeVec(dims),
    SourceSize = sizeVec(passInputDims(state, i, original)),
    OriginalSize = sizeVec(original),
  }
  for _, entry in ipairs(sizeUniforms) do
    if entry.kind == "unique" and entry.semantic == "Output" then
      values[entry.name] = sizeVec(dims)
    elseif entry.kind == "unique" and SENSOR_KIND[entry.semantic] then
      local x, y, z = Sensors.read(SENSOR_KIND[entry.semantic])
      local dbgRawX, dbgRawY, dbgRawZ = x, y, z
      if entry.semantic == "Accelerometer" then
        -- Calibrate against the pose captured at activate(), then swap gravity
        -- onto the axis getOrientedTilt ignores (this engine rests upright).
        if state.accelRest then
          x = x - state.accelRest[1]
          y = y - state.accelRest[2]
          z = z - state.accelRest[3]
        end
        y, z = z, y
        -- Keep getOrientedTilt's normalize denominator stable, but only against
        -- a live reading: an all-zero raw read is Sensors.lua's no-hardware sentinel.
        if state.accelRest and (dbgRawX ~= 0 or dbgRawY ~= 0 or dbgRawZ ~= 0) then
          z = 9.8
        end
        if state.entryName == YAW_SHADER_NAME and state.yawTwist then
          -- The only already-compiled channel this preset's stock math reads.
          x = x + state.yawTwist
        end
      end
      values[entry.name] = { x, y, z }
      if entry.semantic == "Accelerometer" then
        -- Test seam: the values that actually reached the packed uniform.
        state.lastAccelPacked = { x, y, z }
        if debugThrottle("accel:" .. tostring(state.entryName)) then
          local d = state.ALL_DEFAULTS or {}
          require("src.core.Logger").info(
            "[DEBUG-tfxsns2] accel entry=%s raw=(%.3f,%.3f,%.3f) packed=(%.3f,%.3f,%.3f) mag=%.3f twist=%s " ..
            "ACCEL_ENABLE=%s SHADOW_MOTION=%s YAW_ENABLE=%s SENSITIVITY=%s",
            tostring(state.entryName), dbgRawX, dbgRawY, dbgRawZ, x, y, z,
            math.sqrt(x * x + y * y + z * z), tostring(state.yawTwist),
            tostring(d.PT_ACCEL_ENABLE), tostring(d.PT_SHADOW_MOTION),
            tostring(d.PT_YAW_ENABLE), tostring(d.PT_ACCEL_SENSITIVITY))
        end
      end
    elseif entry.kind == "unique" and entry.semantic == "AccelerometerRest" then
      values[entry.name] = { 0, 0, 0 }
    elseif entry.kind == "unique" and entry.semantic == "Rotation" then
      -- retroarch_get_rotation(): the CONTENT's rotation, not the device's.
      -- Nothing here rotates GB content, so 0 is correct, not a placeholder.
      values[entry.name] = 0
    elseif entry.kind == "texture" then
      if entry.semantic == "Original" then
        values[entry.name] = sizeVec(original)
      elseif entry.semantic == "Source" then
        values[entry.name] = sizeVec(passInputDims(state, i, original))
      elseif entry.semantic == "OriginalHistory" then
        -- Steady-state fallback: every history slot reads the current frame.
        values[entry.name] = sizeVec(original)
      elseif entry.semantic == "PassOutput" then
        values[entry.name] = sizeVec(assert(state.outputDims[entry.index],
          ("pass%d: %s references pass%d's output, not yet computed")
            :format(i, entry.name, entry.index)))
      elseif entry.semantic == "PassFeedback" or entry.semantic == "User" then
        error(("pass%d: %s is a %s size uniform -- not yet supported")
          :format(i, entry.name, entry.semantic))
      end
    end
  end
  return values
end

-- Runs pass `i`, drawing `srcImg` into a freshly sized canvas. `lutByName`
-- resolves a User-semantic sampler by the name the translation reported.
local function runPass(state, i, pass, outputs, frameSource, lutByName, viewport, original)
  local dims = computePassDims(state, i, pass, viewport, original)
  state.outputDims[i] = dims

  -- Compiled once per (state, pass): a pass's GLSL and manifest depend only on
  -- the preset, never on per-frame input. fragManifest is cached alongside it.
  local cached = state.shaderCache[i]
  local shader, fragManifest
  if cached then
    shader, fragManifest = cached.shader, cached.fragManifest
  else
    local fixedFragBody
    fixedFragBody, fragManifest = Fixup.fragment(pass.fragment)
    local fixedVert, vertManifest = Fixup.vertex(pass.vertex)
    assert(#fragManifest == #vertManifest, ("pass%d: PUSH struct member count differs"):format(i))

    local validateErrs = {}
    local isEs = defaultEs()
    for headIdx, head in ipairs(Fixup.PREC_HEADS) do
      local fixedFrag = head .. fixedFragBody
      local okShader, err = love.graphics.validateShader(isEs, fixedFrag, fixedVert)
      if okShader then
        shader = love.graphics.newShader(fixedFrag, fixedVert)
        break
      else
        validateErrs[#validateErrs + 1] = ("variant %d: %s"):format(headIdx, tostring(err))
      end
    end
    if not shader then
      require("src.core.Logger").error("ShaderFX: pass%d shader failed to validate -- %s",
        i, table.concat(validateErrs, " | "))
    end
    assert(shader, ("pass%d: no PREC_HEADS variant validated (%s)")
      :format(i, table.concat(validateErrs, " | ")))
    state.shaderCache[i] = { shader = shader, fragManifest = fragManifest }
  end

  for _, s in ipairs(pass.samplers) do
    local img
    if s.semantic == "Source" then img = (i == 0) and frameSource or outputs[i - 1]
    elseif s.semantic == "Original" then img = frameSource
    elseif s.semantic == "OriginalHistory" then img = frameSource
    elseif s.semantic == "PassOutput" then img = outputs[s.index]
    elseif s.semantic == "User" then img = lutByName and lutByName[s.user_name] end
    assert(img, ("pass%d: no binding resolved for sampler %s (semantic=%s)")
      :format(i, s.name, tostring(s.semantic)))
    pcall(shader.send, shader, "LIBRA_TEXTURE_" .. s.name, img)
  end

  local values = sizeTable(state, i, dims, pass.size_uniforms, viewport, original)
  for name, value in pairs(state.ALL_DEFAULTS) do values[name] = value end
  local packed = Fixup.packValues(fragManifest, values)
  for name, value in pairs(packed) do pcall(shader.send, shader, name, value) end

  local srcImg = (i == 0) and frameSource or outputs[i - 1]
  local srcDims = passInputDims(state, i, original)
  local drawScaleX, drawScaleY = dims.w / srcDims.w, dims.h / srcDims.h

  -- Reallocated only when this pass's resolved size actually changes.
  local cc = state.canvasCache[i]
  local canvas
  if cc and cc.w == dims.w and cc.h == dims.h then
    canvas = cc.canvas
  else
    canvas = love.graphics.newCanvas(dims.w, dims.h)
    canvas:setFilter("nearest", "nearest")
    state.canvasCache[i] = { canvas = canvas, w = dims.w, h = dims.h }
  end

  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setShader(shader)
  if i == state.preset.pass_count - 1 then
    love.graphics.setBlendMode("replace", "premultiplied")
  else
    love.graphics.setBlendMode("replace")
  end
  love.graphics.draw(srcImg, 0, 0, 0, drawScaleX, drawScaleY)
  love.graphics.pop()

  outputs[i] = canvas
end

-- Runs the whole chain once over `frameSource` (sized `original`), with
-- `viewport` the size "viewport" scale_type passes resolve against.
function ShaderFX.runChain(state, frameSource, lutByName, viewport, original)
  local outputs = {}
  state.outputDims = {}
  for i = 0, state.preset.pass_count - 1 do
    runPass(state, i, state.preset.passes[i + 1], outputs, frameSource, lutByName, viewport, original)
  end
  return outputs[state.preset.pass_count - 1]
end

-- ------- public, minimal load/render entry points

-- Loads one entry from its cached Lua artifact; never calls the bridge.
-- Returns a chain state, or nil + an error when it has not been converted.
function ShaderFX.load(entry)
  local path = ShaderFX.artifactPath(entry)
  local chunk, err = loadfile(path)
  if not chunk then
    return nil, "no cached artifact, convert this preset first: " .. tostring(err)
  end
  local ok, preset = pcall(chunk)
  if not ok then return nil, "cached artifact failed to run: " .. tostring(preset) end
  if type(preset) ~= "table" then return nil, "cached artifact did not return a table" end
  local state = newChainState(preset)
  state.entryName = entry.name -- see updateYawTwist/sizeTable's Accelerometer branch
  return state
end

-- Every #pragma parameter the entry's artifact declares, deduped by id, each
-- with its currently-effective default. Reads the artifact only.
function ShaderFX.listParams(entry)
  local state, err = ShaderFX.load(entry)
  if not state then return nil, err end
  local order, byId = {}, {}
  for _, pass in ipairs(state.preset.passes) do
    for _, p in ipairs(pass.parameters) do
      if not byId[p.id] then
        byId[p.id] = p
        order[#order + 1] = p.id
      end
    end
  end
  local out = {}
  for _, id in ipairs(order) do
    local p = byId[id]
    -- "!"-prefixed descriptions are engine-owned, not a player preference, so
    -- they never become an editable row. No preset uses this today.
    if not (p.description and p.description:sub(1, 1) == "!") then
      out[#out + 1] = {
        id = p.id, description = p.description,
        minimum = p.minimum, maximum = p.maximum, step = p.step,
        initial = state.ALL_DEFAULTS[p.id],
      }
    end
  end
  return out
end

-- ------- active-preset tracking and the real endFrame render entry point

-- ------- AOT convert: the one function that calls the bridge, writing its
-- decoded result to disk as a plain Lua artifact.

-- #t counts a trailing nil as absent, so walk every key instead.
local function arrayLen(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return nil end
  end
  return n
end

-- Serializes the string/number/boolean/nested-table shape Json.decode
-- produces; array-shaped tables (arrayLen) serialize positionally.
local function serializeLua(v, buf)
  local t = type(v)
  if t == "string" then
    buf[#buf + 1] = string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    buf[#buf + 1] = tostring(v)
  elseif t == "table" then
    buf[#buf + 1] = "{"
    local n = arrayLen(v)
    if n then
      for i = 1, n do
        serializeLua(v[i], buf)
        buf[#buf + 1] = ","
      end
    else
      for k, item in pairs(v) do
        assert(type(k) == "string", "serializeLua: non-string, non-array-index table key")
        buf[#buf + 1] = "[" .. string.format("%q", k) .. "]="
        serializeLua(item, buf)
        buf[#buf + 1] = ","
      end
    end
    buf[#buf + 1] = "}"
  else
    error("serializeLua: unsupported value type " .. t)
  end
end

-- Translates `entry` via the bridge and writes ShaderFX.artifactPath(entry).
-- Sets entry.converted on success; an existing artifact survives a failure.
local function doConvert(entry, es)
  ShaderSourcePatches.apply(entry)
  local preset, err = ShaderFX.translate(entry.fullPath, es == nil and defaultEs() or es)
  if not preset then return false, err end
  local buf = {}
  serializeLua(preset, buf)
  local path = ShaderFX.artifactPath(entry)
  local f, ferr = io.open(path, "wb")
  if not f then return false, "io.open failed: " .. tostring(ferr) end
  f:write("return ")
  f:write(table.concat(buf))
  f:write("\n")
  f:close()
  entry.converted = true
  return true
end

function ShaderFX.convert(entry, es)
  local ok, res, err = pcall(doConvert, entry, es)
  if not ok then return false, tostring(res) end
  return res, err
end

-- Two independent slots. "shaderfx" stays main's option key, so existing
-- saves keep meaning what they already meant.
ShaderFX.SLOTS = { "main", "secondary" }
ShaderFX.OPTION_KEY = { main = "shaderfx", secondary = "shaderfxSecondary" }

local slots = { main = {}, secondary = {} } -- slots[s] = { state=, entry= }
local autoActivateTried = false -- see applyOptions()/tryAutoActivateFromEnv() below

-- Loads `entry`'s cached artifact into `slot` and makes it that slot's active
-- preset. `paramOverrides` layers a player's pragma edits over ALL_DEFAULTS.
function ShaderFX.activate(slot, entry, paramOverrides)
  assert(slots[slot], "ShaderFX.activate: unknown slot " .. tostring(slot))
  local state, err = ShaderFX.load(entry)
  if not state then return false, err end
  if paramOverrides then
    for id, value in pairs(paramOverrides) do state.ALL_DEFAULTS[id] = value end
  end
  state.luts = loadLuts(state.preset)
  -- Snapshot whatever pose the player is actually holding right now as neutral,
  -- subtracted from every later reading. Recalibrates on every activate().
  state.accelRest = { Sensors.read("accelerometer") }
  require("src.core.Logger").info(
    "[DEBUG-tfxsns2] activate entry=%s accelRest=(%.3f,%.3f,%.3f)",
    tostring(entry and entry.name), state.accelRest[1], state.accelRest[2], state.accelRest[3])
  slots[slot].state, slots[slot].entry = state, entry
  return true
end

-- `slot` nil deactivates both.
function ShaderFX.deactivate(slot)
  if slot then
    slots[slot].state, slots[slot].entry = nil, nil
  else
    for _, s in pairs(slots) do s.state, s.entry = nil, nil end
  end
end

-- `slot` nil answers "is anything active".
function ShaderFX.active(slot)
  if slot then return slots[slot].state ~= nil end
  return slots.main.state ~= nil or slots.secondary.state ~= nil
end

function ShaderFX.activeEntry(slot)
  return slots[slot] and slots[slot].entry
end

-- Finds a ShaderFX.list() entry by its `name` field, or nil (e.g. the preset
-- was deleted from the drop-in folder since it was selected).
function ShaderFX.findEntry(name)
  if not name or name == "" then return nil end
  for _, entry in ipairs(ShaderFX.list()) do
    if entry.name == name then return entry end
  end
  return nil
end

-- Under AUTO, a tier that caps shaderfx off would force-deactivate a persisted
-- preset choice every boot; pin "high" instead. Never touches an explicit
-- performance choice, and never un-escalates on deactivate.
local function escalatePerformanceIfNeeded(opts)
  if not opts then return false end
  local wantsShaderfx = false
  for _, slot in ipairs(ShaderFX.SLOTS) do
    local want = opts[ShaderFX.OPTION_KEY[slot]]
    if want and want ~= "" then wantsShaderfx = true end
  end
  if not wantsShaderfx then return false end
  if opts.performance ~= nil and opts.performance ~= "auto" then return false end
  local Performance = require("src.core.Performance")
  if Performance.caps("auto").shaderfx then return false end
  opts.performance = "high"
  return true
end

function ShaderFX.applyOptions(opts)
  autoActivateTried = true
  local cleared = false
  for _, slot in ipairs(ShaderFX.SLOTS) do
    local key = ShaderFX.OPTION_KEY[slot]
    local want = opts and opts[key]
    if not want or want == "" then
      ShaderFX.deactivate(slot)
    else
      local entry = ShaderFX.findEntry(want)
      if not entry then
        if opts then opts[key] = nil end
        ShaderFX.deactivate(slot)
        cleared = true
      else
        -- isConverted() is existence-only with no staleness check, so a saved
        -- choice reconverts here too -- at boot/options-save, never per frame.
        local convOk, convErr = ShaderFX.convert(entry)
        if not convOk then
          require("src.core.Logger").error("ShaderFX.applyOptions: reconvert failed for %s (%s): %s",
            want, slot, tostring(convErr))
        end
        local paramOverrides = opts.shaderfxParams and opts.shaderfxParams[entry.name]
        local ok, err = ShaderFX.activate(slot, entry, paramOverrides)
        if not ok then
          require("src.core.Logger").error("ShaderFX.applyOptions: %s (%s) failed to activate: %s",
            want, slot, tostring(err))
          if opts then opts[key] = nil end
          ShaderFX.deactivate(slot)
          cleared = true
        end
      end
    end
  end
  if escalatePerformanceIfNeeded(opts) then cleared = true end
  return cleared
end

-- Stand-in from before the real OPTIONS row existed; only still fires for
-- harnesses that call ShaderFX.render() without ever calling applyOptions().
local function tryAutoActivateFromEnv()
  autoActivateTried = true
  local want = os.getenv("POKEPORT_SHADERFX")
  if not want or want == "" then return end
  local entry = ShaderFX.findEntry(want)
  if not entry then
    require("src.core.Logger").error("ShaderFX: POKEPORT_SHADERFX=%s not found under %s",
      want, tostring(ShaderFX.presetDir()))
    return
  end
  local ok, err = ShaderFX.activate("main", entry)
  if not ok then
    require("src.core.Logger").error("ShaderFX: POKEPORT_SHADERFX=%s failed to activate: %s",
      want, tostring(err))
  end
end

-- Crops the playfield rect out of `canvas` at `renderScale`. The output canvas
-- is cached module-wide and reallocated only on a real size change.
local cropCanvasCache
local function cropToGbSource(canvas, rect, srcW, srcH, renderScale)
  -- Cheap insurance against a read-after-write hazard between this draw and
  -- whatever last rendered into `canvas`.
  love.graphics.flushBatch()
  local outW, outH = roundDim(srcW * renderScale), roundDim(srcH * renderScale)
  local quad = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h,
    canvas:getPixelWidth(), canvas:getPixelHeight())
  local out
  if cropCanvasCache and cropCanvasCache.w == outW and cropCanvasCache.h == outH then
    out = cropCanvasCache.canvas
  else
    out = love.graphics.newCanvas(outW, outH)
    out:setFilter("nearest", "nearest")
    cropCanvasCache = { canvas = out, w = outW, h = outH }
  end
  local invScale = renderScale / rect.scale
  love.graphics.push("all")
  love.graphics.setCanvas(out)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace")
  -- push("all") saves the caller's draw color but does not reset it: a menu can
  -- leave it black, which would multiply the whole crop to black.
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, quad, 0, 0, 0, invScale, invScale)
  love.graphics.pop()
  return out
end

-- The tier's SHADER FX chain-resolution multiplier; 1.0 when the tier's cap is
-- not a number.
local function chainRenderScale()
  local caps = Performance.CAPS[Performance.tier]
  return (caps and tonumber(caps.shaderfx)) or 1.0
end

-- Renderer.lua's endFrame entry point. `canvas` is the finished window-size
-- composite; `rect` is this frame's real game rect in PHYSICAL framebuffer
-- pixels and `source` the content size it frames. See docs/shaderfx.md.
function ShaderFX.render(canvas, rect, source, dpiX, dpiY)
  if not autoActivateTried then tryAutoActivateFromEnv() end
  if not slots.main.state and not slots.secondary.state then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
    return
  end

  dpiX, dpiY = tonumber(dpiX) or 1, tonumber(dpiY) or 1
  -- Same physical location as `rect`, in the logical units LOVE draws in.
  local uRect = {
    x = math.floor(rect.x / dpiX), y = math.floor(rect.y / dpiY),
    w = math.floor(rect.w / dpiX), h = math.floor(rect.h / dpiY),
  }
  -- Runs the chain at a reduced internal resolution on tiers that ask for one.
  local scale = chainRenderScale()
  local viewport = { w = roundDim(uRect.w * scale), h = roundDim(uRect.h * scale) }

  -- exposed for tests only (tests/drivers/gold_shaderfx_zoom_sizing_test.lua)
  ShaderFX._lastRect, ShaderFX._lastSource = rect, source

  local dt = love.timer and love.timer.getDelta() or 0
  updateYawTwist(slots.main.state, dt)
  updateYawTwist(slots.secondary.state, dt)
  -- Test seam: the live per-frame integration, before it rides into the shader.
  ShaderFX._lastYawTwist = {
    main = slots.main.state and slots.main.state.yawTwist,
    secondary = slots.secondary.state and slots.secondary.state.yawTwist,
  }

  local ok, chainOut, chainPreset = pcall(function()
    local frameSource = cropToGbSource(canvas, rect, source.w, source.h, scale)
    -- exposed for tests only (gold_shaderfx_menu_black_crop_test.lua)
    ShaderFX._lastCrop = frameSource
    local dims = { w = frameSource:getWidth(), h = frameSource:getHeight() }
    local img, preset = frameSource, nil
    if slots.main.state then
      img = ShaderFX.runChain(slots.main.state, img, slots.main.state.luts, viewport, dims)
      dims = { w = img:getWidth(), h = img:getHeight() }
      preset = slots.main.state.preset
    end
    if slots.secondary.state then
      img = ShaderFX.runChain(slots.secondary.state, img, slots.secondary.state.luts, viewport, dims)
      dims = { w = img:getWidth(), h = img:getHeight() }
      preset = slots.secondary.state.preset
    end
    return img, preset
  end)

  if not ok or not chainOut then
    require("src.core.Logger").error(
      "ShaderFX.render chain failed ok=%s chainOut=%s err=%s",
      tostring(ok), tostring(chainOut), tostring(not ok and chainOut or nil))
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("replace")
  love.graphics.draw(canvas, 0, 0)
  if ok and chainOut then
    -- A chain's final pass need not land on the viewport size (most presets end
    -- at scale_type="source"), so stretch, using that pass's own filter.
    local cw, ch = chainOut:getWidth(), chainOut:getHeight()
    local lastPass = chainPreset.passes[chainPreset.pass_count]
    local mode = (lastPass.filter == "linear") and "linear" or "nearest"
    chainOut:setFilter(mode, mode)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
    love.graphics.draw(chainOut, uRect.x, uRect.y, 0, uRect.w / cw, uRect.h / ch)
  elseif not ok then
    require("src.core.Logger").error("ShaderFX.render: chain failed, showing unprocessed frame: %s",
      tostring(chainOut))
  end
  love.graphics.setBlendMode("alpha")
  -- Test seam; set only after the real chain ran.
  ShaderFX._lastAccelPacked = {
    main = slots.main.state and slots.main.state.lastAccelPacked,
    secondary = slots.secondary.state and slots.secondary.state.lastAccelPacked,
  }
end

return ShaderFX

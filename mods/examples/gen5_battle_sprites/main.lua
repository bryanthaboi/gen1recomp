-- Native asset-pack example. All sprite pixels come from the player's cache.
local mod = ...
local MAX_IMAGE = 8 * 1024 * 1024
local clock, reason, ready, warned = 0, "Gen 5 sprite pack is not installed", false, false
local entries, images, slots, atlases = {}, {}, {}, {}
local partEntries, composites, plans, pixelSets = {}, {}, {}, {}
local serial, imageCount, atlasCount = 0, 0, 0
local compositeCount, planCount, pixelCount = 0, 0, 0
local function integer(n, lo, hi)
  return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end
local function warn(message)
  reason = tostring(message)
  if not warned then
    warned = true
    mod.log:warn("Gen 5 sprites unavailable: %s. Import your own Black/White ROM in the launcher; native sprites remain active.", reason)
  end
end
local function loadIndex()
  local info, err = mod.packs:info("gen5_bw", "battle_sprites")
  if not info then error(err or reason, 0) end
  local list, listErr = mod.packs:entries("gen5_bw", "battle_sprites")
  if type(list) ~= "table" or #list > 10000 then error(listErr or "invalid pack entries", 0) end
  local composite = {}
  for _, raw in ipairs(list) do
    local s = raw.sprite
    if type(raw.id) ~= "string" or #raw.id > 80 or type(s) ~= "table"
        or not integer(s.width, 1, 256) or not integer(s.height, 1, 256)
        or not integer(s.columns, 1, 512) or not integer(s.frames, 1, 512)
        or s.tickRate ~= 60 or type(s.durations) ~= "table" or #s.durations ~= s.frames
        or not integer(raw.size, 24, MAX_IMAGE)
        or raw.width ~= s.width * s.columns
        or raw.height ~= s.height * math.ceil(s.frames / s.columns)
        or raw.width * raw.height > 4 * 1024 * 1024 then
      error("invalid pack sprite metadata " .. tostring(raw.id), 0)
    end
    local total, intro = 0, 0
    local loop = s.loopStartFrame or 0
    if not integer(loop, 0, s.frames - 1) then error("invalid animation loop start", 0) end
    for i, duration in ipairs(s.durations) do
      if not integer(duration, 1, 3600000) then error("invalid tick duration", 0) end
      total = total + duration
      if i <= loop then intro = intro + duration end
    end
    if s.cycleTicks ~= nil and s.cycleTicks ~= total then error("animation cycle length mismatch", 0) end
    if s.kind == "parts" then
      -- Exporter 1.1 part tracks. Their inert atlas descriptor is capped, so
      -- 1.0 consumers skip them; the tracks live in the entry's metadata.
      if s.cycleCapped == true and type(raw.metadata) == "table" then
        partEntries[raw.id] = {size = raw.size, atlasWidth = raw.width, atlasHeight = raw.height}
      end
    elseif s.cycleCapped ~= true then
      entries[raw.id] = {width=s.width,height=s.height,columns=s.columns,frames=s.frames,
        durations=s.durations,total=total,intro=intro,loop=loop,size=raw.size,
        atlasWidth=raw.width,atlasHeight=raw.height}
    elseif type(s.partsEntry) == "string" and #s.partsEntry <= 80
        and (s.partsPalette == "normal" or s.partsPalette == "shiny") then
      composite[#composite + 1] = {id = raw.id, parts = s.partsEntry, palette = s.partsPalette}
    end
  end
  -- A capped entry plays complete only through its part tracks; otherwise it
  -- keeps native artwork exactly as before.
  for _, item in ipairs(composite) do
    if partEntries[item.parts] then entries[item.id] = {parts = item.parts, palette = item.palette} end
  end
  ready, reason = true, nil
end
local function release(value)
  if value and value.release then value:release() end
end
local function evictOldest(cache)
  local oldest, used
  for candidate, item in pairs(cache) do
    if not used or item.used < used then oldest, used = candidate, item.used end
  end
  return oldest
end
local function decodePng(id, size, aw, ah)
  local bytes, err = mod.packs:read("gen5_bw", "battle_sprites", id)
  if type(bytes) ~= "string" or #bytes ~= size or #bytes > MAX_IMAGE then error(err or "invalid pack image length", 0) end
  -- IHDR is checked before decoding: a tiny compressed PNG must not allocate
  -- an arbitrary-size image. Atlas dimensions come from validated metadata.
  if bytes:sub(1, 8) ~= "\137PNG\13\10\26\10" or bytes:sub(13,16) ~= "IHDR" then error("invalid PNG", 0) end
  local function be(pos)
    local a,b,c,d = bytes:byte(pos, pos + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  if aw * ah > 4 * 1024 * 1024 or be(17) ~= aw or be(21) ~= ah then error("PNG dimensions do not match index", 0) end
  local file = love.filesystem.newFileData(bytes, "private-gen5.png")
  local data = love.image.newImageData(file)
  release(file)
  return data
end
local function remember(key, image)
  if imageCount >= 8 then
    local oldest = evictOldest(images)
    release(images[oldest].image); images[oldest] = nil; imageCount = imageCount - 1
  end
  images[key], imageCount = {image = image, used = serial}, imageCount + 1
  return image
end
local function imageFor(id, entry, frame)
  local key = id .. ":" .. frame
  serial = serial + 1
  if images[key] then images[key].used = serial; return images[key].image end
  local data = atlases[id] and atlases[id].data
  if data then atlases[id].used = serial end
  if not data then
  data = decodePng(id, entry.size, entry.atlasWidth, entry.atlasHeight)
  if atlasCount >= 4 then
    local oldest = evictOldest(atlases)
    release(atlases[oldest].data); atlases[oldest] = nil; atlasCount = atlasCount - 1
  end
  atlases[id], atlasCount = {data = data, used = serial}, atlasCount + 1
  end
  local W, H = entry.width, entry.height
  local out = love.image.newImageData(W, H)
  local sx = ((frame - 1) % entry.columns) * entry.width
  local sy = math.floor((frame - 1) / entry.columns) * entry.height
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      out:setPixel(x, y, data:getPixel(sx + x, sy + y))
    end
  end
  local image = love.graphics.newImage(out)
  release(out)
  image:setFilter("nearest", "nearest")
  return remember(key, image)
end

-- Part-track composition (exporter 1.1). Each track keeps its own intro and
-- loop on the shared 60 Hz tick, so no global loop is ever baked. Pieces are
-- painted in the source compositor's global order: OAM priority high to low,
-- then multicell record last to first, clipped to that tick's canvas.
local TRANSPARENT = "\0\0\0\0"
local function list(value, lo, hi, multiple)
  if type(value) ~= "table" or #value < lo or #value > hi or #value % multiple ~= 0 then
    error("invalid part track metadata", 0)
  end
  for i = 1, #value do if not integer(value[i], -4096, 65536) then error("invalid part track metadata", 0) end end
  return value
end
local function paletteBytes(values)
  list(values, 4, 1024, 4)
  local out = {[0] = TRANSPARENT}
  for i = 1, #values / 4 do
    local r, g, b, a = values[i*4-3], values[i*4-2], values[i*4-1], values[i*4]
    if not (integer(r,0,255) and integer(g,0,255) and integer(b,0,255) and integer(a,0,255)) then
      error("invalid part palette", 0)
    end
    out[i - 1] = i == 1 and TRANSPARENT or string.char(r, g, b, a)
  end
  return out
end
-- A plan holds the tracks, piece rectangles and palettes. It
-- is small, so many stay cached; a composite-cache hit needs only the plan.
local function loadPlan(partsId)
  local pe = partEntries[partsId]
  if not pe then error("missing part tracks", 0) end
  local meta, err = mod.packs:metadata("gen5_bw", "battle_sprites", partsId)
  if type(meta) ~= "table" then error(err or "missing part track metadata", 0) end
  local W, H = meta.width, meta.height
  if meta.format ~= "gen5-parts" or meta.version ~= 1 or meta.tickRate ~= 60
      or not integer(W, 1, 256) or not integer(H, 1, 256)
      or meta.atlasWidth ~= pe.atlasWidth or meta.atlasHeight ~= pe.atlasHeight
      or type(meta.tracks) ~= "table" or #meta.tracks < 1 or #meta.tracks > 512
      or type(meta.palettes) ~= "table" then
    error("invalid part track metadata", 0)
  end
  local rawPieces = list(meta.pieces, 6, 6 * 4096, 6)
  local pieceCount = #rawPieces / 6
  local pieces, area = {}, 0
  for i = 1, pieceCount do
    local x, y, w, h, ax, ay = unpack(rawPieces, i * 6 - 5, i * 6)
    if not (integer(w, 1, W) and integer(h, 1, H) and integer(x, 0, W - w) and integer(y, 0, H - h)
        and integer(ax, 0, pe.atlasWidth - w) and integer(ay, 0, pe.atlasHeight - h)) then
      error("invalid part piece", 0)
    end
    -- Pieces are packed without overlap, so their area never exceeds the atlas.
    area = area + w * h
    if area > pe.atlasWidth * pe.atlasHeight then error("part pieces exceed atlas", 0) end
    pieces[i] = {index = i, x = x, y = y, w = w, h = h, ax = ax, ay = ay}
  end
  local tracks, ticks, stateTotal = {}, 0, 0
  for r = 1, #meta.tracks do
    local t = meta.tracks[r]
    if type(t) ~= "table" or not integer(t.intro, 0, 65535) or not integer(t.period, 1, 65536)
        or t.intro + t.period > 65536 then
      error("invalid part track", 0)
    end
    local span = t.intro + t.period
    ticks = ticks + span
    if ticks > 262144 then error("part tracks exceed bounds", 0) end
    local rawStates = list(t.states, 9, 9 * math.min(span, 4096), 9)
    stateTotal = stateTotal + #rawStates / 9
    if stateTotal > 8192 then error("part states exceed bounds", 0) end
    local states = {}
    for s = 1, #rawStates / 9 do
      local o = s * 9 - 9
      local has = rawStates[o + 1]
      if has ~= 0 and has ~= 1 then error("invalid part state", 0) end
      local state = {pieces = {}, key = s}
      if has == 1 then state.bounds = {rawStates[o+2], rawStates[o+3], rawStates[o+4], rawStates[o+5]} end
      for p = 1, 4 do
        local index = rawStates[o + 5 + p]
        if not integer(index, 0, pieceCount) then error("invalid part state", 0) end
        if index > 0 then state.pieces[p] = pieces[index] end
      end
      states[s] = state
    end
    local runs = list(t.runs, 2, 2 * span, 2)
    local at, n = {}, 0
    for i = 1, #runs, 2 do
      local length, state = runs[i], runs[i + 1]
      if not integer(length, 1, span) or not integer(state, 1, #states) or n + length > span then
        error("invalid part run", 0)
      end
      for k = n + 1, n + length do at[k] = states[state] end
      n = n + length
    end
    if n ~= span then error("part run length mismatch", 0) end
    tracks[r] = {intro = t.intro, period = t.period, at = at}
  end
  -- The animation-union canvas is fixed across poses, with one output
  -- pixel for every source pixel and all transparent margins preserved.
  local strings = {}
  for i = 1, W * H do strings[i] = TRANSPARENT end
  return {width = W, height = H, tracks = tracks, pieces = pieces,
    out = {}, strings = strings, states = {}, key = {},
    palettes = {normal = paletteBytes(meta.palettes.normal), shiny = paletteBytes(meta.palettes.shiny)}}
end
-- Palette indices per piece, unpacked from the index atlas (red = index,
-- alpha 0 = transparent). Only needed when a new state combination appears.
local function loadPixels(partsId, plan)
  local pe = partEntries[partsId]
  local data = decodePng(partsId, pe.size, pe.atlasWidth, pe.atlasHeight)
  local raw = data:getString()
  release(data)
  local out = {}
  for i, piece in ipairs(plan.pieces) do
    local values, w = {}, piece.w
    for py = 0, piece.h - 1 do
      local base, row = ((piece.ay + py) * pe.atlasWidth + piece.ax) * 4, py * w
      for px = 0, w - 1 do
        local o = base + px * 4
        local index, alpha = raw:byte(o + 1), raw:byte(o + 4)
        values[row + px + 1] = alpha == 0 and 0 or index
      end
    end
    out[i] = values
  end
  return out
end
local function cached(cache, limit, counter, key, load)
  serial = serial + 1
  local item = cache[key]
  if item then item.used = serial; return item.value, counter end
  local value = load()
  if counter >= limit then
    cache[evictOldest(cache)] = nil; counter = counter - 1
  end
  cache[key] = {value = value, used = serial}
  return value, counter + 1
end
local function planFor(partsId)
  local plan
  plan, planCount = cached(plans, 16, planCount, partsId, function() return loadPlan(partsId) end)
  return plan
end
local function pixelsFor(partsId, plan)
  local data
  data, pixelCount = cached(pixelSets, 6, pixelCount, partsId, function() return loadPixels(partsId, plan) end)
  return data
end
-- The state of every track at one tick, and a key naming that combination.
local function selectStates(plan, tick)
  local states, key = plan.states, plan.key
  for r, track in ipairs(plan.tracks) do
    local t = tick
    if t >= track.intro then t = track.intro + (t - track.intro) % track.period end
    local state = track.at[t + 1]
    states[r], key[r] = state, state.key
  end
  return states, table.concat(key, ",")
end
local function compose(plan, states, colors, data)
  local W, H = plan.width, plan.height
  local cx0, cy0, cx1, cy1 = math.huge, math.huge, -math.huge, -math.huge
  for r = 1, #plan.tracks do
    local b = states[r].bounds
    if b then
      if b[1] < cx0 then cx0 = b[1] end
      if b[2] < cy0 then cy0 = b[2] end
      if b[3] > cx1 then cx1 = b[3] end
      if b[4] > cy1 then cy1 = b[4] end
    end
  end
  cx0, cy0, cx1, cy1 = math.max(cx0, 0), math.max(cy0, 0), math.min(cx1, W), math.min(cy1, H)
  local out = plan.out
  for i = 1, W * H do out[i] = 0 end
  if cx0 < cx1 and cy0 < cy1 then
    for p = 4, 1, -1 do
      for r = #plan.tracks, 1, -1 do
        local piece = states[r].pieces[p]
        if piece then
          local px, py, pw = piece.x, piece.y, piece.w
          local u0, u1 = math.max(px, cx0), math.min(px + pw, cx1)
          local v0, v1 = math.max(py, cy0), math.min(py + piece.h, cy1)
          if u0 < u1 and v0 < v1 then
            local values = data[piece.index]
            for y = v0, v1 - 1 do
              local base, row = (y - py) * pw - px + 1, y * W + 1
              for x = u0, u1 - 1 do
                local v = values[base + x]
                if v ~= 0 then out[row + x] = v end
              end
            end
          end
        end
      end
    end
  end
  local strings = plan.strings
  for i = 1, W * H do strings[i] = colors[out[i]] or TRANSPARENT end
  return table.concat(strings)
end
-- Composed frames are cached by the exact state combination, separately from
-- atlas frames. Ticks that change no track state reuse the same image.
local function compositeFor(id, entry, tick)
  local plan = planFor(entry.parts)
  local states, signature = selectStates(plan, tick)
  local key = id .. "@" .. signature
  serial = serial + 1
  local hit = composites[key]
  if hit then hit.used = serial; return hit.image, key, plan.width, plan.height end
  local data = pixelsFor(entry.parts, plan)
  local rgba = love.image.newImageData(plan.width, plan.height, "rgba8", compose(plan, states, plan.palettes[entry.palette], data))
  local image = love.graphics.newImage(rgba)
  release(rgba)
  image:setFilter("nearest", "nearest")
  if compositeCount >= 16 then
    local oldest = evictOldest(composites)
    release(composites[oldest].image); composites[oldest] = nil; compositeCount = compositeCount - 1
  end
  composites[key], compositeCount = {image = image, used = serial}, compositeCount + 1
  return image, key, plan.width, plan.height
end

local function clear()
  for _, item in pairs(images) do release(item.image) end
  for _, item in pairs(composites) do release(item.image) end
  for _, item in pairs(atlases) do release(item.data) end
  images, composites, atlases, slots, plans, pixelSets = {}, {}, {}, {}, {}, {}
  imageCount, compositeCount, atlasCount, planCount, pixelCount, clock = 0, 0, 0, 0, 0, 0
end

mod.exports.api = 2
mod.exports.apiVersion = 2
-- Art generation is independent of the receiving game or voxel engine.
mod.exports.capabilities = {
  contract = "national-dex-battle-sprites", version = 2,
  source = "gen5_bw", maxDex = 649, sides = {"front", "back"},
  shiny = true, female = true, nativeResolution = true, variableDimensions = true,
  maxFrameWidth = 256, maxFrameHeight = 256,
  clock = "input.step", optional = true,
}
function mod.exports.status()
  return {ready = ready, reason = reason, cachedImages = imageCount, cachedAtlases = atlasCount,
    cachedComposites = compositeCount, cachedPartPlans = planCount, cachedPartPixels = pixelCount}
end
-- Advanced by input.step once per simulation update; never by eye draws.
function mod.exports.update(dt)
  if type(dt) == "number" and dt == dt and dt >= 0 and dt < math.huge then clock = clock + dt * 1000 end
end
function mod.exports.frame(request)
  if not ready or type(request) ~= "table" or not integer(request.dex, 1, 649)
      or (request.side ~= "front" and request.side ~= "back")
      or (request.form ~= nil and request.form ~= 0 and request.form ~= "normal") then return nil end
  local id = (request.shiny and "shiny/" or "normal/") .. string.format("%03d", request.dex) .. "/" .. request.side
  local female = request.gender == "female" or request.gender == "F" or request.gender == 2
  if female and entries[id .. "/female"] then id = id .. "/female" end
  local entry = entries[id]
  if not entry then return nil end
  local slotKey = tostring(request.battleId or "battle") .. "/" .. tostring(request.battlerId or request.side)
  local slot = slots[slotKey]
  if not slot or slot.id ~= id or slot.mon ~= request.mon then
    local count = 0
    for _ in pairs(slots) do count = count + 1 end
    if count >= 16 then slots = {} end
    slot = {id = id, mon = request.mon, started = clock}; slots[slotKey] = slot
  end
  -- Keep identity storage bounded across battles, without advancing animation.
  if not slot.touched or clock - slot.touched > 60000 then
    for key, value in pairs(slots) do if clock - (value.touched or value.started) > 60000 then slots[key] = nil end end
  end
  slot.touched = clock
  local elapsed = math.floor((clock - slot.started) * 60 / 1000 + 1e-7)
  if entry.parts then
    -- Complete animation: every part follows its own loop on the shared tick.
    -- frame is the 1-based 60 Hz tick shown, not an atlas index.
    if slot.partTick == elapsed and composites[slot.partKey] then
      local hit = composites[slot.partKey]
      serial = serial + 1; hit.used = serial
      return {image = hit.image, width = slot.partWidth, height = slot.partHeight,
        groundOffset = slot.partHeight / 2, frame = elapsed + 1, entryId = id}
    end
    local ok, image, key, width, height = pcall(compositeFor, id, entry, elapsed)
    if not ok then entries[id] = nil; warn(image); return nil end
    slot.partTick, slot.partKey = elapsed, key
    slot.partWidth, slot.partHeight = width, height
    return {image = image, width = width, height = height, groundOffset = height / 2, frame = elapsed + 1, entryId = id}
  end
  local phase, frame = elapsed, 1
  if elapsed >= entry.intro then
    phase = entry.intro + (elapsed - entry.intro) % (entry.total - entry.intro)
  end
  for i, duration in ipairs(entry.durations) do
    if phase < duration then frame = i; break end
    phase = phase - duration
  end
  local ok, image = pcall(imageFor, id, entry, frame)
  if not ok then entries[id] = nil; warn(image); return nil end
  local width, height = entry.width, entry.height
  return {image = image, width = width, height = height, groundOffset = height / 2, frame = frame, entryId = id}
end
local ok, err = pcall(loadIndex)
if not ok then entries = {}; warn(err) end
local function capture(...) return {n=select("#",...),...} end
mod.hooks:wrap("input.step", function(next, game, dt)
  local result = capture(next(game, dt))
  mod.exports.update(dt)
  return unpack(result,1,result.n)
end)
mod.events:on("core.session_ending", clear)

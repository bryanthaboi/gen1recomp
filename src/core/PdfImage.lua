-- Recover a raster from a PDF that is really a wrapped JPEG.  Delta skins
-- ship artwork that way so iOS can scale it; LOVE has no PDF renderer, so
-- import pulls the embedded image out instead of refusing the skin.  True
-- vector PDFs (no Image XObject, no JPEG) still fail.

local PdfImage = {}

local function isPdf(bytes)
  return type(bytes) == "string" and bytes:sub(1, 5) == "%PDF-"
end

-- After the `stream` keyword the spec allows \n or \r\n before the bytes.
-- `endstream` also contains the letters "stream", so skip that match.
local function streamDataStart(bytes, from)
  local s, e = bytes:find("stream", from, true)
  while s do
    if s == 1 or bytes:sub(s - 3, s - 1) ~= "end" then
      local p = e + 1
      if bytes:sub(p, p) == "\r" then p = p + 1 end
      if bytes:sub(p, p) == "\n" then p = p + 1 end
      return p, s
    end
    s, e = bytes:find("stream", e + 1, true)
  end
  return nil
end

local function dictWindow(bytes, imageAt)
  local from = imageAt > 400 and (imageAt - 400) or 1
  local to = math.min(#bytes, imageAt + 800)
  return bytes:sub(from, to)
end

local function dictNumber(window, key)
  -- Prefer an indirect ref so `/Length 5 0 R` is not read as length 5.
  if window:find("/" .. key .. "%s+%d+%s+%d+%s+R") then return nil end
  return tonumber(window:match("/" .. key .. "%s+(%d+)"))
end

local function dictFilter(window)
  local named = window:match("/Filter%s*/(%w+)")
  if named then return named end
  return window:match("/Filter%s*%[%s*/(%w+)")
end

local function jpegIn(bytes, from, to)
  if from < 1 then from = 1 end
  if not to or to > #bytes then to = #bytes end
  if to < from then return nil end
  local region = bytes:sub(from, to)
  local soi = region:find("\255\216\255", 1, true)
  if not soi then return nil end
  local eoi = region:find("\255\217", soi + 3, true)
  if not eoi then return nil end
  return region:sub(soi, eoi + 1)
end

local function candidate(data, width, height, ext)
  if not data or data == "" then return nil end
  return {
    data = data,
    ext = ext or "jpg",
    width = width or 0,
    height = height or 0,
  }
end

local function bigger(a, b)
  if not a then return b end
  if not b then return a end
  local as = (a.width or 0) * (a.height or 0)
  local bs = (b.width or 0) * (b.height or 0)
  if bs ~= as then return bs > as and b or a end
  return #b.data > #a.data and b or a
end

-- Walk Image XObjects and take the largest DCTDecode (JPEG) stream.
local function fromImageXObjects(bytes)
  local best
  local i = 1
  while true do
    local s, e = bytes:find("/Subtype%s*/Image", i)
    if not s then break end
    local window = dictWindow(bytes, s)
    local filter = dictFilter(window)
    local width = dictNumber(window, "Width")
    local height = dictNumber(window, "Height")
    local dataStart = streamDataStart(bytes, e)
    i = e + 1
    if dataStart and filter == "DCTDecode" then
      local es = bytes:find("endstream", dataStart, true)
      local jpeg = jpegIn(bytes, dataStart, es and (es - 1) or nil)
      best = bigger(best, candidate(jpeg, width, height, "jpg"))
    end
  end
  return best
end

-- Image-to-PDF converters (3-Heights, Preview, etc.) leave a single JPEG
-- body even when /Length is an indirect object we do not resolve.
local function fromBareJpeg(bytes)
  local jpeg = jpegIn(bytes, 1, #bytes)
  if not jpeg then return nil end
  return candidate(jpeg, 0, 0, "jpg")
end

function PdfImage.extract(bytes)
  if not isPdf(bytes) then return nil, "not a pdf" end
  local best = fromImageXObjects(bytes)
  if not best then best = fromBareJpeg(bytes) end
  if not best then return nil, "no extractable image" end
  return best
end

return PdfImage

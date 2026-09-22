local Json = require("src.link.Json")

local Canon = {}

local function encode(v, out)
  local t = type(v)
  if t ~= "table" then
    out[#out + 1] = Json.encode(v)
    return
  end
  local n = #v
  local isArray = n > 0
  if not isArray then isArray = next(v) == nil end
  if isArray then
    out[#out + 1] = "["
    for i = 1, n do
      if i > 1 then out[#out + 1] = "," end
      encode(v[i], out)
    end
    out[#out + 1] = "]"
    return
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  out[#out + 1] = "{"
  for i = 1, #keys do
    if i > 1 then out[#out + 1] = "," end
    out[#out + 1] = Json.encode(tostring(keys[i]))
    out[#out + 1] = ":"
    encode(v[keys[i]], out)
  end
  out[#out + 1] = "}"
end

function Canon.encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

return Canon

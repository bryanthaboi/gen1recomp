-- Application-owned message descriptor for locale-neutral service modules.
-- tostring() deliberately produces the English source for logs, tests and
-- non-UI callers; AppLocale.message() translates it at a presentation edge.
local AppMessage = {}
local mt = {}

function mt.__tostring(message)
  local ok, text = pcall(string.format, message.source,
    unpack(message.args, 1, message.args.n))
  return ok and text or message.source
end

setmetatable(AppMessage, {
  __call = function(_, source, ...)
    return setmetatable({
      source = tostring(source),
      args = { n = select("#", ...), ... },
    }, mt)
  end,
})

function AppMessage.is(value)
  return getmetatable(value) == mt
end

return AppMessage

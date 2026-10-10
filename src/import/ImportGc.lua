local ImportGc = {}

ImportGc.PAUSE = 100
ImportGc.STEPMUL = 400

local LOW_MEMORY_ENV = { "HANDHELD", "POKEPORT_HANDHELD", "PORTMASTER", "POKEPORT_PORTMASTER" }

function ImportGc.lowMemoryHost(getenv)
  getenv = getenv or os.getenv
  for _, name in ipairs(LOW_MEMORY_ENV) do
    if getenv(name) == "1" then return true end
  end
  return false
end

function ImportGc.tune(getenv)
  if not ImportGc.lowMemoryHost(getenv) then return false end
  collectgarbage("setpause", ImportGc.PAUSE)
  collectgarbage("setstepmul", ImportGc.STEPMUL)
  return true
end

return ImportGc

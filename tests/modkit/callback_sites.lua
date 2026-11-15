local FsIo = require("tests.fs_io")

local Sites = {}

local GEN1_DIRS = { "src/battle/", "src/world/", "src/ui/", "src/pokemon/", "src/script/" }

local function isAdapter(path)
  return path:match("^src/mods/Unified") ~= nil
end

local PATH_GENERATIONS = {
  ["src/ui/LevelDisplay.lua"] = { [1] = true, [2] = true, [3] = true },
  ["src/pokemon/Sprites.lua"] = { [1] = true, [2] = true },
  ["src/core/Game.lua"] = { [1] = true },
  ["src/link/LinkState.lua"] = { [1] = true },
  ["src/link/Protocol.lua"] = { [1] = true },
}

function Sites.generations(path)
  if PATH_GENERATIONS[path] then return PATH_GENERATIONS[path] end
  if path:find("/gen2/", 1, true) or path:find("Game2", 1, true)
      or path == "src/link/LinkBattle2.lua" or path == "src/mods/Gen2Compat.lua" then
    return { [2] = true }
  end
  if path:find("game3", 1, true) or path:find("Game3", 1, true)
      or path == "src/mods/Gen3Compat.lua" then return { [3] = true } end
  if path == "src/link/LinkBattle.lua" or path == "src/render/BattleTransition.lua" then
    return { [1] = true }
  end
  for _, dir in ipairs(GEN1_DIRS) do
    if path:sub(1, #dir) == dir then return { [1] = true } end
  end
  return { [1] = true, [2] = true, [3] = true }
end

function Sites.scan(root)
  local found = { events = {}, hooks = {} }
  for _, path in ipairs(FsIo.luaFilesUnder(root or "src")) do
    if not isAdapter(path) then
      local file = io.open(path, "rb")
      local text = file:read("*a")
      file:close()
      text = text:gsub("%-%-[^\n]*", "")
      for fn, name in text:gmatch("[%w_]+[.:](%a+)%(%s*\"([%l][%l%d_]*%.[%l%d_.]+)\"") do
        local surface = (fn == "call" or fn == "wantsHook") and "hooks"
          or (fn == "emit" or fn == "wants") and "events" or nil
        if surface then
          local set = found[surface][name] or {}
          found[surface][name] = set
          for gen in pairs(Sites.generations(path)) do set[gen] = true end
        end
      end
    end
  end
  return found
end

return Sites

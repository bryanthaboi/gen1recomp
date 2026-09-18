package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen3 shim engine require")
local check, eq = S.check, S.eq

local Loader = require("src.mods.Loader")
local Gen3Compat = require("src.mods.Gen3Compat")
local GameVersion = require("src.core.GameVersion")
local SessionLifecycle = require("src.core.SessionLifecycle")

local NAME = "src.core.Game"
local REAL = { load = function() end }

local function memfs(files)
  return {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content return true end,
    remove = function(path) files[path] = nil return true end,
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
    createDirectory = function() return true end,
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

local function requireFrom(source, name)
  local chunk = assert(loadstring(
    "local name = ... local mod = require(name) return mod", "@" .. source))
  return chunk(name or NAME)
end

local savedVersion = GameVersion.get()
local savedModule = package.loaded[NAME]
package.loaded[NAME] = REAL

GameVersion.set("firered")
local files = {
  ["mods/facade/manifest.json"] =
    [[{"id":"facade","name":"facade","version":"1.0.0","entry":"main.lua",]]
    .. [["games":["gen3"]}]],
  ["mods/facade/main.lua"] = "return function(mod) end",
}
local loader = Loader.new({ fs = memfs(files) })
loader:load({ maps = {} })

eq(loader.generation, 3, "the fixture loader is a Gen 3 one")
check(Gen3Compat.serves(NAME), "the facade serves " .. NAME)

local facade = Gen3Compat.resolve(NAME)
eq(requireFrom("mods/facade/main.lua"), facade,
  "a mod's require resolves to the Gen 3 facade")
eq(requireFrom("mods/facade/main.lua", "src.world.WorldAPI"),
  require("src.world.game3.WorldAPI"),
  "src.world.WorldAPI from a mod is the FireRed WorldAPI")
eq(requireFrom("main.lua"), REAL,
  "main.lua's require is the engine's own, never the facade")
eq(requireFrom("conf.lua"), REAL, "conf.lua's require is the engine's own")

SessionLifecycle.endMountedSession()
eq(requireFrom("mods/facade/main.lua"), REAL,
  "after the session ends the facade stops answering for the next boot")

package.loaded[NAME] = savedModule
GameVersion.set(savedVersion)

S.finish()

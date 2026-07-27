-- The `strings` registry and src/core/Strings.lua: the seam a translation
-- mod uses to replace the text the engine authors itself, as opposed to the
-- extracted dialogue that `text` already covered (#186, #245).
--
-- Keyed by the English source, so the assertions here are mostly about what
-- happens at the edges: a source nothing translated, a context that
-- disambiguates two identical sources, and a translation whose format
-- directives do not match the source (which would otherwise raise inside
-- string.format in the middle of a battle).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Loader = require("src.mods.Loader")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")

local S = require("tests.harness").suite("strings registry")
local check, eq = S.check, S.eq

-- the fs surface the loader needs, backed by a flat path->content table
local function memfs(files)
  return {
    read = function(path) return files[path] end,
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

local function manifestJson(id)
  return ([[{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua","dependencies":[]}]])
    :format(id, id)
end

-- ------- the seam is declared where a mod looks for it

do
  local Schemas = require("src.mods.Schemas")
  local spec = Schemas.REGISTRIES["strings"]
  check(spec ~= nil, [[the "strings" registry is declared]])
  eq(spec.target, "strings", "it writes through to Data.strings")
  eq(spec.semantics, "record", "one entry per source string, like text")
end

-- ------- no mod: S is an identity function

do
  Strings.load({})
  check(not Strings.active(), "no catalog means the layer is inert")
  eq(Strings("But, it failed!"), "But, it failed!", "an unloaded catalog passes text through")
  eq(Strings("Wild %s\nappeared!", "PIDGEY"), "Wild PIDGEY\nappeared!",
     "formatting still happens with no catalog")
end

-- ------- a translation mod supplies the catalog

local files = {
  ["mods/fr/manifest.json"] = manifestJson("fr"),
  ["mods/fr/main.lua"] = [[
return function(mod)
  mod.content.strings:override("But, it failed!", "Mais cela echoue !")
  mod.content.strings:override("Wild %s\nappeared!", "Un %s\nsauvage apparait !")
  mod.content.strings:override("OFF", "NON")
  mod.content.strings:override("options.musicFilter|OFF", "AUCUN")
  mod.content.strings:override("%d of %d", "%d perdus")
end
]],
}
local data = { strings = {} }
local loader = Loader.new({ fs = memfs(files) })
check(loader:load(data) == true, "the translation mod loads headlessly")
eq(data.strings["But, it failed!"], "Mais cela echoue !",
   "mod.content.strings merges into Data.strings")

Strings.load(data)
check(Strings.active(), "a non-empty catalog activates the layer")

-- ------- lookup

do
  eq(Strings("But, it failed!"), "Mais cela echoue !", "a plain source translates")
  eq(Strings("Nothing happened!"), "Nothing happened!",
     "a source the translation missed stays in English")
  eq(Strings("Wild %s\nappeared!", "RATTATA"), "Un RATTATA\nsauvage apparait !",
     "a formatted source translates and then formats")
end

-- ------- context disambiguates identical sources

do
  eq(Strings("OFF", "options.musicFilter"), "AUCUN",
     "a context key wins over the bare source")
  eq(Strings("OFF"), "NON", "the bare source is still reachable")
  eq(Strings("OFF", "options.tilt"), "NON",
     "an unlisted context falls back to the bare source")
end

-- ------- a mistranslated format string must not crash a battle

-- Logger.history is a 200-line ring buffer that drops from the front, so
-- absolute indices shift under a full aggregator run.  Count matches
-- instead of slicing.
local function complaints()
  local n = 0
  for _, line in ipairs(Logger.history) do
    if line:find("format directives", 1, true) then n = n + 1 end
  end
  return n
end

do
  local before = complaints()
  eq(Strings("%d of %d", 3, 6), "3 of 6",
     "a translation with the wrong arity falls back to the English source")
  check(complaints() > before, "the arity mismatch is reported")

  -- and the complaint does not repeat on every frame it draws
  local mid = complaints()
  Strings("%d of %d", 1, 2)
  eq(complaints(), mid, "the arity complaint is not repeated")
end

-- The catalog is module state, and the aggregator runs every suite in one
-- Lua process: leaving it loaded translated the battle text underneath the
-- suites that run after this one (parity_J asserted on "But, it failed!"
-- and got the French).  Put it back before handing the process on.
Strings.load({})
check(not Strings.active(), "the catalog is unloaded for the suites after this one")
eq(Strings("But, it failed!"), "But, it failed!", "English is restored")

S.finish()

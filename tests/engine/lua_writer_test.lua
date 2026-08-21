-- Focused coverage for the generated-cache serializer. Extraction and touch
-- skin tests consume its output, but previously did not pin escaping, stable
-- key order, invalid values, cycles, or the CacheFs failure path.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("lua writer")
local LuaWriter = require("src.import.LuaWriter")

local function decode(encoded)
  local chunk, err = loadstring(encoded)
  T.check(chunk ~= nil, "encoded Lua compiles: " .. tostring(err))
  return chunk and chunk()
end

local source = {
  plain = true,
  [2] = "two",
  [1] = "one",
  ["end"] = "keyword",
  ["not-an-identifier"] = "punctuation",
  escaped = "quote=\" slash=\\ newline=\n tab=\t nul=\0",
  nested = { 10, 20 },
}
local encoded = LuaWriter.encode(source)
local roundTrip = decode(encoded)

T.eq(roundTrip[1], "one", "numeric keys survive a mixed table")
T.eq(roundTrip[2], "two", "second numeric key survives")
T.eq(roundTrip.plain, true, "identifier keys use ordinary Lua fields")
T.eq(roundTrip["end"], "keyword", "Lua keywords are quoted as keys")
T.eq(roundTrip["not-an-identifier"], "punctuation",
  "non-identifier keys are quoted")
T.eq(roundTrip.escaped, source.escaped,
  "quotes, slashes, whitespace controls, and NUL round-trip")
T.eq(roundTrip.nested[2], 20, "dense arrays round-trip")

T.eq(encoded, LuaWriter.encode(source),
  "the same table serializes deterministically")
T.check(encoded:find("%[1%] =", 1) < encoded:find("plain =", 1),
  "mixed numeric keys sort before string keys")

local sparse = decode(LuaWriter.encode({ [1] = "first", [3] = "third" }))
T.eq(sparse[1], "first", "sparse table keeps its first index")
T.eq(sparse[2], nil, "sparse table does not invent a missing index")
T.eq(sparse[3], "third", "sparse table keeps its high index")

local shared = { value = 7 }
local sharedResult = decode(LuaWriter.encode({ left = shared, right = shared }))
T.eq(sharedResult.left.value, 7, "shared acyclic tables serialize")
T.eq(sharedResult.right.value, 7, "a repeated table is not mistaken for a cycle")

local cyclic = {}
cyclic.self = cyclic
local okCycle, cycleErr = pcall(LuaWriter.encode, cyclic)
T.check(not okCycle and tostring(cycleErr):find("cyclic table", 1, true),
  "cyclic input is rejected explicitly")

local okFunction, functionErr = pcall(LuaWriter.encode, { callback = function() end })
T.check(not okFunction and tostring(functionErr):find("cannot serialize function", 1, true),
  "unsupported value types are rejected explicitly")

local oldCacheFs = package.loaded["src.import.CacheFs"]
local writes = {}
package.loaded["src.import.CacheFs"] = {
  write = function(path, body)
    writes[#writes + 1] = { path = path, body = body }
    return true
  end,
}
LuaWriter.write("data/generated/probe.lua", { answer = 42 })
T.eq(writes[1].path, "data/generated/probe.lua", "write forwards the requested path")
T.eq(decode(writes[1].body).answer, 42, "write forwards valid serialized Lua")

package.loaded["src.import.CacheFs"] = {
  write = function() return nil, "disk full" end,
}
local okWrite, writeErr = pcall(LuaWriter.write, "data/generated/probe.lua", {})
T.check(not okWrite and tostring(writeErr):find("disk full", 1, true),
  "CacheFs write failures retain their cause")
package.loaded["src.import.CacheFs"] = oldCacheFs

T.finish()

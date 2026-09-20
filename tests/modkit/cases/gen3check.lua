-- T4: FireRed mod API parity, read from src/mods/Gen3Compat.lua and the
-- per-generation mod.world / mod.battle modules at run time.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local Gen2Compat = require("src.mods.Gen2Compat")
local Gen3Compat = require("src.mods.Gen3Compat")

for _, fn in ipairs({ "serves", "resolve", "bind", "coverage", "modules",
                      "memberStatus", "applyMerged", "scriptCtx" }) do
  T.eq(type(Gen3Compat[fn]), "function", "Gen3Compat." .. fn .. " exists")
end
T.eq(type(Gen3Compat.ADAPTERS), "table", "Gen3Compat.ADAPTERS is published")
T.eq(Gen3Compat.COVERAGE_VERSION, Gen2Compat.COVERAGE_VERSION,
  "both compat layers speak one coverage contract version")

for name in pairs(Gen2Compat.ADAPTERS) do
  T.check(Gen3Compat.serves(name),
    "a module Gold adapts is adapted on FireRed too: " .. name)
end
for name in pairs(Gen3Compat.ADAPTERS) do
  T.check(Gen2Compat.serves(name),
    "FireRed adapts nothing Gold does not: " .. name)
  local row = Gen3Compat.coverage(name)
  T.check(row ~= nil, "coverage row for " .. name)
  if row then
    T.check(row.kind == "facade" or row.kind == "alias",
      "coverage kind is facade or alias: " .. name)
    for member, status in pairs(row.members) do
      T.check(status == "backed" or status == "warned" or status == "absent",
        ("%s.%s carries one of the three statuses"):format(name, member))
    end
  end
end

local function publicMethods(module)
  local out = {}
  for key, value in pairs(module) do
    if type(value) == "function" and not key:find("^_") then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

local function surface(label, gen3Name, others)
  local ok3, gen3 = pcall(require, gen3Name)
  T.check(ok3, label .. ": " .. gen3Name .. " loads headless")
  if not ok3 then return end
  for _, otherName in ipairs(others) do
    local ok, other = pcall(require, otherName)
    if ok and type(other) == "table" then
      for _, key in ipairs(publicMethods(other)) do
        T.eq(type(gen3[key]), "function",
          ("%s: %s.%s has a FireRed arm"):format(label, otherName, key))
      end
    else
      T.check(true, label .. ": " .. otherName .. " not loadable headless, skipped")
    end
  end
end

surface("mod.world", "src.world.game3.WorldAPI",
  { "src.world.WorldAPI", "src.world.gen2.WorldAPI" })
surface("mod.battle", "src.battle.game3.BattleAPI",
  { "src.battle.BattleAPI", "src.battle.gen2.BattleAPI" })

local worldRow = Gen3Compat.coverage("src.world.WorldAPI")
T.eq(worldRow and worldRow.target, "src.world.game3.WorldAPI",
  "the WorldAPI coverage row names the FireRed module")

-- ------- the command itself.  `gen3check` is the same checks as `gen2check`
-- run against src/mods/Gen3Compat.lua, so what this section has to prove is
-- that the generation reached every one of them and that the one rule which
-- only makes sense on Gold was switched off.  Every fixture is derived from
-- the engine, for the reason this file's header gives.

local isWindows = package.config:sub(1, 1) == "\\"

-- luajit's pclose drops the exit status, so the shell reports it in-band
-- (tests/modkit_tests.lua uses the same shape)
local function run(command)
  if isWindows then
    command = 'cmd /v:on /c "' .. command .. ' 2>&1 & echo EXIT:!errorlevel!"'
  else
    command = command .. ' 2>&1; echo "EXIT:$?"'
  end
  local pipe = io.popen(command)
  local output = pipe:read("*a")
  pipe:close()
  return output, tonumber(output:match("EXIT:(%d+)%s*$")) or -1
end

local python = isWindows and "python" or "python3"
if not run(python .. " --version"):find("Python 3", 1, true) then
  T.check(true, "python3 is absent: the gen3check command is not exercised")
  T.finish("gen3check")
  return
end

local function gen3check(dir, extra)
  return run(("%s tools/modkit.py gen3check %q %s")
    :format(python, dir, extra or ""))
end

-- ------- what to write the fixtures against, taken from the engine

local names = {}
for name in pairs(Gen3Compat.ADAPTERS) do names[#names + 1] = name end
table.sort(names)

-- written onto the running game and never onto the module table, which is
-- what MK410 is about; read from the Gen 1 source, as the tool does
local function instanceField(module, member)
  local handle = io.open(module:gsub("%.", "/") .. ".lua", "r")
  if not handle then return false end
  local body = handle:read("*a")
  handle:close()
  if not body:find("self%." .. member .. "%s*=[^=]") then return false end
  if body:find("function%s+%w+[%.:]" .. member .. "%s*%(") then return false end
  for owner in body:gmatch("[\n%s]([%a_][%w_]*)%." .. member .. "%s*=[^=]") do
    if owner ~= "self" then return false end
  end
  return true
end

local aliasName, backedMember, absentName, absentMember, liveName, liveMember
for _, name in ipairs(names) do
  local row = Gen3Compat.coverage and Gen3Compat.coverage(name)
  local members = row and row.members or {}
  local sorted = {}
  for member in pairs(members) do sorted[#sorted + 1] = member end
  table.sort(sorted)
  for _, member in ipairs(sorted) do
    if not member:find("[%.%s]") then
      if members[member] == "absent" and not absentMember then
        absentName, absentMember = name, member
      end
      if members[member] == "backed" and row.kind == "alias"
          and not backedMember then
        aliasName, backedMember = name, member
      end
      if members[member] == "backed" and row.kind == "facade"
          and not liveMember and instanceField(name, member) then
        liveName, liveMember = name, member
      end
    end
  end
end
T.check(absentMember ~= nil, "the FireRed coverage table names at least one "
  .. "absent member")

-- the Gen 1 modules a FireRed boot never instantiates (src/mods/Loader.lua),
-- at least one of which the coverage table refuses to adapt: MK402
local unservedName
do
  local handle = io.open("src/mods/Loader.lua", "r")
  local body = handle and handle:read("*a") or ""
  if handle then handle:close() end
  local block = body:match("GEN1_ONLY_MODULES%s*=%s*{(.-)\n}")
  for name in (block or ""):gmatch('%["([^"]+)"%]') do
    if not Gen3Compat.serves(name) then
      unservedName = name
      break
    end
  end
end
T.check(unservedName ~= nil,
  "at least one Gen 1 module has no FireRed adapter, which is MK402")

-- the shape only FireRed has: a module a FireRed boot really runs from a
-- snake_case file under a game3/ directory, on a Gen 1 module nothing adapts,
-- so the sibling search has to try its second spelling.  The directory comes
-- from a coverage target, so nothing here restates the tree.
local function listLua(dir)
  local files = {}
  local pipe = io.popen(isWindows and ('dir /b "%s\\*.lua" 2>nul'):format(dir)
    or ('ls "%s"/*.lua 2>/dev/null'):format(dir))
  if not pipe then return files end
  for line in pipe:lines() do
    local base = line:match("([^/\\]+)%.lua$")
    if base and base ~= "init" then files[#files + 1] = base end
  end
  pipe:close()
  table.sort(files)
  return files
end

local siblingName, siblingPath, siblingCamel
for _, name in ipairs(Gen3Compat.modules()) do
  if not siblingName then
    local row = Gen3Compat.coverage(name)
    local dir = row and row.target and row.target:match("^(.*%.)")
    if dir and dir:find("%.game3%.$") then
      local gen1 = dir:gsub("%.game3%.$", ".")
      local gen1dir = gen1:gsub("%.", "/")
      for _, file in ipairs(listLua(dir:gsub("%.$", ""):gsub("%.", "/"))) do
        local camel = file:gsub("_(%a)", string.upper):gsub("^%l", string.upper)
        local handle = io.open(gen1dir .. camel .. ".lua", "r")
        if handle then handle:close() end
        if handle and camel ~= file and not Gen3Compat.serves(gen1 .. camel)
            and not siblingName then
          siblingName = gen1 .. camel     -- src.ui.BagMenu, what a mod requires
          siblingPath = dir .. file       -- src.ui.game3.bag_menu, what runs
          siblingCamel = dir .. camel     -- src.ui.game3.BagMenu, not on disk
        end
      end
    end
  end
end
T.check(siblingName ~= nil,
  "a snake_case game3 sibling with no adapter exists, which is MK403")

-- ------- fixtures on disk, because the tool reads a mod directory

local tmp = os.tmpname()
os.remove(tmp)
local root = (isWindows and tmp:gsub("\\", "/") or tmp) .. "_gen3check"
run((isWindows and "mkdir " or "mkdir -p ") .. ("%q"):format(root))

local function write(dir, files)
  run((isWindows and "mkdir " or "mkdir -p ")
    .. ("%q"):format(root .. "/" .. dir))
  for name, body in pairs(files) do
    local handle = assert(io.open(root .. "/" .. dir .. "/" .. name, "w"))
    handle:write(body)
    handle:close()
  end
  return root .. "/" .. dir
end

local function manifest(id, extra)
  return ('{ "id": "%s", "name": "%s", "version": "1.0.0", "api": 2, '
    .. '"entry": "main.lua", "description": "gen3check fixture"%s }')
    :format(id, id, extra or "")
end

local FIRERED = ', "games": ["firered"]'

-- claims FireRed and nothing else, so gen2check has to fail it while
-- gen3check passes it: the same checks against two generations
local firered = write("gen3_firered", {
  ["manifest.json"] = manifest("gen3_firered", FIRERED),
  ["main.lua"] = "local mod = ...\n",
})

-- claims no generation at all
local unclaimed = write("gen3_unclaimed", {
  ["manifest.json"] = manifest("gen3_unclaimed"),
  ["main.lua"] = "local mod = ...\n",
})

-- only reads what the FireRed adapter backs
local clean = aliasName and write("gen3_clean", {
  ["manifest.json"] = manifest("gen3_clean", FIRERED),
  ["main.lua"] = ([[
local mod = ...
local M = require("%s")
local held = M.%s
mod.exports.held = held ~= nil
]]):format(aliasName, backedMember),
})

-- requires a module a FireRed boot never instantiates and nothing adapts
local unserved = write("gen3_unserved", {
  ["manifest.json"] = manifest("gen3_unserved", FIRERED),
  ["main.lua"] = ([[
local mod = ...
local M = require("%s")
M.thing(mod)
]]):format(unservedName),
})

-- requires a module a FireRed boot runs out of another file entirely
local sibling = siblingName and write("gen3_sibling", {
  ["manifest.json"] = manifest("gen3_sibling", FIRERED),
  ["main.lua"] = ([[
local mod = ...
local M = require("%s")
M.open(mod)
]]):format(siblingName),
})

-- calls a member the FireRed coverage table refuses to invent
local absent = write("gen3_absent", {
  ["manifest.json"] = manifest("gen3_absent", FIRERED),
  ["main.lua"] = ([[
local mod = ...
local M = require("%s")
M.%s(mod)
]]):format(absentName, absentMember),
})

-- an entry chunk holding a member of a game that is not up yet
local held = liveMember and write("gen3_held", {
  ["manifest.json"] = manifest("gen3_held", FIRERED),
  ["main.lua"] = ([[
local mod = ...
local G = require("%s")
local captured = G.%s
mod.events:on("game.ready", function()
  mod.exports.live = G.%s ~= nil
end)
mod.exports.captured = captured ~= nil
]]):format(liveName, liveMember, liveMember),
})

-- the Gen 2 screen-twin half of MK409 is off on FireRed, so the version
-- string is the only MK409 a FireRed boot can raise
local version = write("gen3_version", {
  ["manifest.json"] = manifest("gen3_version", FIRERED),
  ["main.lua"] = ([[
local mod = ...
if mod.game.version == "red" then mod.exports.gen1 = true end
]]),
})

-- ------- a mod claiming FireRed, run through both commands

local out, code = gen3check(firered)
T.eq(code, 0, "a mod claiming FireRed exits 0 from gen3check: " .. out)
T.check(out:find("will load", 1, true) ~= nil,
  "and its verdict is 'will load': " .. out)
T.check(out:find("on gen 3", 1, true) ~= nil,
  "and the verdict line names the generation it checked: " .. out)
T.check(out:find("MK400", 1, true) == nil,
  "a FireRed mod is never told it claims no FireRed game: " .. out)

out, code = run(("%s tools/modkit.py gen2check %q"):format(python, firered))
T.eq(code, 1, "the same mod fails gen2check, which is the point: " .. out)
T.check(out:find("MK400", 1, true) ~= nil,
  "on the manifest gate: " .. out)
T.check(out:find("on gen 2", 1, true) ~= nil,
  "with a verdict naming Gen 2: " .. out)

-- ------- the manifest gate, in FireRed's words

out, code = gen3check(unclaimed)
T.eq(code, 1, "a mod claiming no Gen 3 game fails the check")
T.check(out:find("MK400", 1, true) ~= nil, "MK400 names the manifest: " .. out)
T.check(out:find("Gen 3", 1, true) ~= nil,
  "and the message is the FireRed one, not Gold's: " .. out)
T.check(out:find("will not work", 1, true) ~= nil,
  "and the verdict says so: " .. out)

-- ------- a mod that only reads what the adapter backs

if clean then
  out, code = gen3check(clean)
  T.eq(code, 0, "a mod inside the FireRed adapter's coverage exits 0: " .. out)
  T.check(out:find("MK40", 1, true) == nil,
    "and raises nothing: " .. out)
end

-- ------- a module FireRed never instantiates and nothing adapts

out, code = gen3check(unserved)
T.eq(code, 1, "requiring it fails the check: " .. out)
T.check(out:find("MK402", 1, true) ~= nil, "MK402 names it: " .. out)
T.check(out:find(unservedName, 1, true) ~= nil,
  "and quotes the module by name: " .. out)
T.check(out:find("Gen3Compat", 1, true) ~= nil,
  "and points at the FireRed adapter file: " .. out)
T.check(out:find("Gen2Compat", 1, true) == nil,
  "with no mention of the Gold one: " .. out)

-- ------- a module FireRed runs, from a file with another spelling

if sibling then
  out, code = gen3check(sibling)
  T.eq(code, 0, "MK403 is a warning, so it does not fail the gate: " .. out)
  T.check(out:find("MK403", 1, true) ~= nil,
    "a module FireRed runs from another file is MK403: " .. out)
  T.check(out:find(siblingPath, 1, true) ~= nil,
    "and the sibling it names is the snake_case one: " .. out)
  T.check(out:find(siblingCamel, 1, true) == nil,
    "never the CamelCase spelling that is not on disk: " .. out)
end

-- ------- a member the coverage table refuses to invent

out, code = gen3check(absent)
T.eq(code, 1, "calling an unbacked member fails the check: " .. out)
T.check(out:find("MK404", 1, true) ~= nil, "MK404 names the member: " .. out)
T.check(out:find(absentMember, 1, true) ~= nil,
  "and quotes it by name: " .. out)
T.check(out:find("Gen 3 backing", 1, true) ~= nil,
  "and says which generation has no backing for it: " .. out)

-- ------- the entry chunk holding a member of a game that is not up yet

if held then
  out = gen3check(held)
  T.check(out:find("MK410", 1, true) ~= nil,
    "MK410 names the file-scope read: " .. out)
  T.check(select(2, out:gsub("MK410", "")) == 1,
    "and only the file-scope one, not the read inside the handler: " .. out)
end

-- ------- MK409's screen half is a Gen 2 fact and is off here

out = gen3check(version)
T.check(out:find("MK409", 1, true) ~= nil,
  "a Gen 1 version string is MK409 on FireRed too: " .. out)
T.check(out:find("a Gen 3 game by construction", 1, true) ~= nil,
  "and the message is the FireRed one: " .. out)

-- ------- the machine-readable form one CI step reads

out, code = run(("%s tools/modkit.py --json gen3check %q"):format(python,
  firered))
T.eq(code, 0, "the JSON run of a passing mod exits 0")
T.check(out:find('"verdict": "will load"', 1, true) ~= nil,
  "the JSON carries a verdict per mod: " .. out)
T.check(out:find('"ok": true', 1, true) ~= nil,
  "and one ok for the batch: " .. out)

out, code = run(("%s tools/modkit.py --json gen3check %q %q")
  :format(python, firered, unclaimed))
T.eq(code, 1, "the batch fails when any mod in it fails")
T.check(out:find('"ok": false', 1, true) ~= nil,
  "and the batch ok follows: " .. out)

-- ------- every adapted name is served, so requiring one is never MK402

local requires = { "local mod = ..." }
for _, name in ipairs(names) do
  requires[#requires + 1] = ("require(%q)"):format(name)
end
local served = write("gen3_served", {
  ["manifest.json"] = manifest("gen3_served", FIRERED),
  ["main.lua"] = table.concat(requires, "\n") .. "\n",
})
out = gen3check(served)
T.check(out:find("MK402", 1, true) == nil,
  "no adapted module is reported as unserved: " .. out)

run((isWindows and "rmdir /s /q " or "rm -rf ") .. ("%q"):format(root))

T.finish("gen3check")

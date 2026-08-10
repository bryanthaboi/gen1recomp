-- Headless tests for tools/save-editor pure logic.
-- Run from repo root: lua5.4 tests/run_save_editor_tests.lua
-- (If lua5.4 is missing, use the same interpreter as tests/run_tests.lua.)
--
-- Panel suites (Boxes/Items, Events/Dex, Map) live in separate files so each
-- can define its own harness without colliding with this runner, and each is
-- its own tier in scripts/test.sh:
--   tests/save_editor_task6_tests.lua
--   tests/save_editor_task7_tests.lua
--   tests/save_editor_task8_tests.lua
--   tests/save_editor_mod_tests.lua
-- See tools/save-editor/README.md for the full list.
--
-- All of them drive tools/save-editor/Ops.lua rather than clicking pixel
-- coordinates: the panels are layout over Ops, so the rules live there and a
-- redesign cannot silently invalidate the suites (which is exactly what the
-- old coordinate-based tests did not survive).

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love_stub

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

print("== save editor tests ==")

local SaveData = require("src.core.SaveData")

do
  local data = SaveData.newGame()
  data.player.map = "VIRIDIAN_CITY"
  data.money = 1234
  data.flags.EVENT_GOT_POKEDEX = true
  local encoded = SaveData.encode(data)
  check(type(encoded) == "string", "encode returns string")
  check(encoded:match("^return "), "encode starts with return")
  local back, err = SaveData.decode(encoded)
  check(back ~= nil, "decode ok: " .. tostring(err))
  eq(back.player.map, "VIRIDIAN_CITY", "decode map")
  eq(back.money, 1234, "decode money")
  check(back.flags.EVENT_GOT_POKEDEX == true, "decode flag")
end

do
  local bad, err = SaveData.decode("not lua {{{")
  check(bad == nil, "decode rejects garbage")
  check(type(err) == "string", "decode returns err string")
end

local SaveIO = require("SaveIO")
local FsIo = require("tests.fs_io")

do
  local path = SaveIO.defaultPath()
  check(type(path) == "string" and #path > 0, "defaultPath nonempty")
  check(path:match("save%.lua$"), "defaultPath ends with save.lua")
  check(path:match("pokemon%-love2d"), "defaultPath uses game identity folder")
  local sys = ""
  if package.config:sub(1, 1) ~= "\\" then
    -- no uname on Windows; the macOS-only check below just skips there
    local uname = io.popen("uname -s 2>/dev/null")
    sys = uname and uname:read("*l") or ""
    if uname then uname:close() end
  end
  if sys == "Darwin" then
    check(path:match("/LOVE/"), "defaultPath on macOS includes LOVE folder")
  end
  check(type(SaveIO.choosePath) == "function", "choosePath exists")
end

do
  local path = os.tmpname() .. "-gamesave.lua"

  local data = SaveData.newGame()
  data.money = 42
  local ok, err = SaveIO.save(path, data)
  check(ok, "SaveIO.save ok: " .. tostring(err))
  local f = io.open(path, "r")
  check(f ~= nil, "save file exists")
  if f then f:close() end

  local loaded, lerr = SaveIO.load(path)
  check(loaded ~= nil, "SaveIO.load ok: " .. tostring(lerr))
  eq(loaded.money, 42, "SaveIO round trip money")

  data.money = 99
  ok, err = SaveIO.save(path, data)
  check(ok, "second save ok: " .. tostring(err))
  loaded = assert(SaveIO.load(path))
  eq(loaded.money, 99, "second save money")

  local bakFiles = FsIo.globPrefix(path .. ".bak-")
  check(#bakFiles >= 1, "second save creates .bak-* sibling")
  if #bakFiles >= 1 then
    local bakData, berr = SaveIO.load(bakFiles[1])
    check(bakData ~= nil, "backup load ok: " .. tostring(berr))
    if bakData then eq(bakData.money, 42, "backup preserves previous money") end
  end

  os.remove(path)
  for _, bak in ipairs(bakFiles) do
    os.remove(bak)
  end
end

local Catalog = require("Catalog")
local MonOps = require("MonOps")
local Data = require("src.core.Data")
Data:load()

do
  local cat = Catalog.build(Data)
  check(#cat.species > 140, "species catalog size")
  check(#cat.items > 100, "items catalog size")
  check(#cat.moves > 150, "moves catalog size")
  check(cat.species[1] < cat.species[2], "species sorted")
end

do
  local events = Catalog.scrapeEvents("data/scripts", "data/generated/trainer_headers.lua")
  check(#events > 50, "scraped events")
  check(events[1]:match("^EVENT_"), "event prefix")
end

do
  local mon = MonOps.create(Data, "PIDGEY", 10)
  eq(mon.species, "PIDGEY", "create species")
  eq(mon.level, 10, "create level")
  local hpBefore = mon.stats.hp
  MonOps.setLevel(Data, mon, 20)
  eq(mon.level, 20, "setLevel")
  check(mon.stats.hp > hpBefore, "stats grew on level")
  check(mon.hp <= mon.stats.hp, "hp clamped")
  MonOps.setMove(Data, mon, 1, "GUST")
  eq(mon.moves[1].id, "GUST", "setMove id")
  check(mon.moves[1].pp > 0, "setMove pp")
end

do
  -- Magikarp is SLOW, Butterfree is MEDIUM_FAST,  same level, different exp
  local mon = MonOps.create(Data, "MAGIKARP", 20)
  local expSlow = mon.exp
  MonOps.setSpecies(Data, mon, "BUTTERFREE")
  eq(mon.species, "BUTTERFREE", "setSpecies id")
  eq(mon.level, 20, "setSpecies keeps level")
  check(mon.exp ~= expSlow, "setSpecies resyncs exp for new growth curve")
  eq(mon.exp, require("src.pokemon.Growth").expForLevel(
    Data.pokemon.BUTTERFREE.growthRate, 20), "setSpecies exp matches curve")
  MonOps.setDv(Data, mon, "attack", 15)
  eq(mon.dvs.attack, 15, "setDv attack")
  check(mon.dvs.hp >= 8, "syncHpDv sets high bit from odd attack")
end

local State = require("State")

do
  local s = State.new()
  eq(s.tab, "party", "State.new default tab")
  eq(s.dirty, false, "State.new default dirty")
  eq(s.selectedParty, 1, "State.new default selectedParty")
  eq(s.selectedBox, 1, "State.new default selectedBox")
  check(s.editingMon == nil, "State.new default editingMon nil")
  State.markDirty(s)
  check(s.dirty == true, "State.markDirty sets dirty")
end

-- Party roster + the docked mon inspector.  Both are pure layout over
-- tools/save-editor/Ops.lua, so the rules are asserted against Ops directly
-- instead of against pixel coordinates the design can (and did) move.
local Ops = require("Ops")
local Pokemon = require("src.pokemon.Pokemon")

do
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  local wartortle = MonOps.create(Data, "WARTORTLE", 20)
  local pidgey = MonOps.create(Data, "PIDGEY", 5)
  S.save.party = { wartortle, pidgey }
  S.selectedParty = 1

  Ops.selectParty(S, 2)
  eq(S.selectedParty, 2, "selectParty selects the row")
  check(S.editingMon == pidgey, "selectParty points the inspector at that mon")

  Ops.partyAdd(S)
  eq(#S.save.party, 3, "partyAdd appends a mon")
  check(S.dirty == true, "partyAdd marks the save dirty")
  S.dirty = false

  S.selectedParty = 3
  check(Ops.partyRemove(S) == false, "partyRemove arms on the first call")
  eq(#S.save.party, 3, "an armed partyRemove has not removed anything")
  check(Ops.partyRemove(S) == true, "partyRemove commits on the second call")
  eq(#S.save.party, 2, "the committed partyRemove drops the selected mon")

  S.selectedParty = 2
  Ops.partyMove(S, -1)
  eq(S.selectedParty, 1, "partyMove up follows the mon to its new slot")
  check(S.save.party[1] == pidgey, "partyMove up swaps the two slots")

  S.dirty = false
  check(Ops.partyMove(S, -1) == false, "the lead mon cannot move further up")
  check(S.dirty == false, "a refused partyMove does not dirty the save")
  check(S.status:match("lead mon") ~= nil, "a refused partyMove explains itself")

  -- a full party refuses another mon
  while #S.save.party < require("src.pokemon.Party").MAX do
    table.insert(S.save.party, MonOps.create(Data, "PIDGEY", 5))
  end
  S.dirty = false
  check(Ops.partyAdd(S) == false, "partyAdd refuses a full party")
  check(S.status:match("Party is full") ~= nil, "a refused partyAdd explains itself")
end

do
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  local mon = MonOps.create(Data, "WARTORTLE", 20)
  S.editingMon = mon

  local levelBefore = mon.level
  local hpStatBefore = mon.stats.hp
  Ops.setLevel(S, mon, mon.level + 1)
  eq(mon.level, levelBefore + 1, "setLevel raises the level")
  check(mon.stats.hp >= hpStatBefore, "a level change recalculates stats")
  check(S.dirty == true, "a level change marks the save dirty")
  S.dirty = false

  Ops.setLevel(S, mon, 999)
  eq(mon.level, 100, "setLevel clamps at 100")
  Ops.setLevel(S, mon, -5)
  eq(mon.level, 1, "setLevel clamps at 1")

  local attackBefore = mon.dvs.attack
  Ops.setDv(S, mon, "attack", attackBefore + 1)
  eq(mon.dvs.attack, math.min(15, attackBefore + 1), "setDv adjusts a DV")
  Ops.setDv(S, mon, "attack", 99)
  eq(mon.dvs.attack, 15, "setDv clamps at 15")
  Ops.setDv(S, mon, "attack", -1)
  eq(mon.dvs.attack, 0, "setDv clamps at 0")
  -- the HP DV is the parity nibble of the other four, never set directly
  eq(mon.dvs.hp,
     (mon.dvs.attack % 2) * 8 + (mon.dvs.defense % 2) * 4
     + (mon.dvs.speed % 2) * 2 + (mon.dvs.special % 2),
     "setDv re-derives the HP DV from the other four")

  local moveBefore = mon.moves[1] and mon.moves[1].id
  Ops.cycleMove(S, mon, 1)
  check(mon.moves[1] ~= nil, "cycleMove leaves a move in the slot")
  check(mon.moves[1].id ~= moveBefore, "cycleMove moves on to a different move")

  Ops.clearMove(S, mon, 1)
  eq(mon.moves[1], nil, "clearMove empties the slot")
  S.dirty = false
  check(Ops.clearMove(S, mon, 1) == false, "clearing an empty slot is a no-op")
  check(S.dirty == false, "a no-op clearMove does not dirty the save")

  Ops.resetMoves(S, mon)
  local def = Data.pokemon[mon.species]
  local learned = Pokemon.movesAtLevel(def, mon.level)
  eq(#mon.moves, #learned, "resetMoves matches the learnset size")

  mon.hp = 1
  Ops.healMon(S, mon)
  eq(mon.hp, mon.stats.hp, "healMon restores full HP")
  S.dirty = false
  check(Ops.healMon(S, mon) == false, "healing an already-full mon is a no-op")

  local speciesBefore = mon.species
  Ops.stepSpecies(S, mon, 1)
  check(mon.species ~= speciesBefore, "stepSpecies changes the species")
  eq(mon.level, 1, "stepSpecies keeps the level")
end

do
  -- Nicknames: the editor edits mon.nickname, which is nil when un-nicknamed
  -- (every display site reads `mon.nickname or def.name`, GenSave.lua).  The
  -- game's naming screen caps at 10 glyphs and treats an empty confirm as "no
  -- nickname", so the verbs below mirror that: "" clears, a name matching the
  -- species' standard name normalizes back to nil, too-long or unrenderable
  -- names refuse with a status line, and nothing silently no-ops.
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  local mon = MonOps.create(Data, "CHARIZARD", 50)
  S.save.party = { mon }
  S.editingMon = mon

  eq(Ops.nicknameLength("POKEMON"), 7, "nicknameLength counts ASCII glyphs")
  eq(Ops.nicknameLength("ééé"), 3, "nicknameLength counts a multi-byte char as one glyph")
  eq(Ops.nicknameLength("♂♀!"), 3, "nicknameLength counts symbol glyphs")
  check(Ops.nicknameUsable(S, "CHARIZARD"), "ASCII letters are renderable")
  check(Ops.nicknameUsable(S, "Nidoking"), "lower case is renderable")
  check(Ops.nicknameUsable(S, "é") == true, "a charmap glyph is renderable")
  check(Ops.nicknameUsable(S, "PIKA€") == false, "a non-charmap glyph is not renderable")
  check(Ops.nicknameUsable(S, "🤖") == false, "an emoji is not renderable")
  -- "@" is the Gen1 string terminator: the codec has an entry for it but the
  -- game font has no tile, so Font.encode draws it as a space in-game
  check(Ops.nicknameUsable(S, "POKE@MON") == false,
        "the terminator @ is not a renderable nickname glyph")
  check(Ops.nicknameUsable(S, "POKE#MON") == false,
        "the # marker is not a renderable nickname glyph")

  -- the field gate: sanitize skips unrenderable glyphs and clamps at 10, so
  -- what reaches the mon can only ever be a legal Gen 1 nickname
  eq(Ops.nicknameSanitize(S, "PIKA\226\130\172"), "PIKA",
    "sanitize drops an unrenderable glyph")
  eq(Ops.nicknameSanitize(S, "PIKA\226\130\172CHU"), "PIKACHU",
    "sanitize skips a bad glyph mid-name instead of aborting the rest")
  eq(Ops.nicknameSanitize(S, "POKE@MON"), "POKEMON",
    "sanitize strips the invisible @ terminator")
  eq(Ops.nicknameSanitize(S, "1234567890123"), "1234567890",
    "sanitize clamps the draft at 10 glyphs")
  eq(Ops.nicknameSanitize(S, "\195\169"), "\195\169",
    "sanitize keeps a charmap glyph")
  eq(Ops.nicknameSanitize(S, ""), "", "sanitize of empty is empty")

  Ops.setNickname(S, mon, "SPARKY")
  eq(mon.nickname, "SPARKY", "setNickname stores the name")
  check(S.dirty == true, "setNickname marks the save dirty")
  eq(S.status:match("SPARKY") ~= nil, true, "setNickname narrates the new name")
  S.dirty = false

  check(Ops.setNickname(S, mon, "SPARKY") == false,
        "setting the same nickname again is a no-op")
  check(S.dirty == false, "the no-op did not dirty the save")
  check(S.status:match("Already nicknamed") ~= nil, "the no-op explains itself")

  -- a name matching the species' standard name is the un-nicknamed state
  Ops.setNickname(S, mon, "CHARIZARD")
  eq(mon.nickname, nil, "a name equal to the standard name normalizes to nil")
  eq(S.status:match("standard name") ~= nil, true, "the normalization explains itself")

  check(Ops.clearNickname(S, mon) == false,
        "clearing an already-un-nicknamed mon is a no-op")
  check(S.status:match("no nickname") ~= nil, "the no-op explains itself")

  -- empty input means clear, like an empty naming-screen confirm
  Ops.setNickname(S, mon, "SPARKY")
  eq(mon.nickname, "SPARKY", "re-nicknamed for the empty-clear check")
  check(Ops.setNickname(S, mon, "") == true, "an empty name is a valid clear")
  eq(mon.nickname, nil, "an empty name clears the nickname")
  check(S.status:match("Cleared") ~= nil, "the clear narrates")

  Ops.setNickname(S, mon, "1234567890")
  eq(mon.nickname, "1234567890", "a 10-glyph name is accepted")
  S.dirty = false
  check(Ops.setNickname(S, mon, "12345678901") == false,
        "an 11-glyph name is refused")
  eq(mon.nickname, "1234567890", "a refused name leaves the mon alone")
  check(S.dirty == false, "a refused name does not dirty the save")
  check(S.status:match("capped at 10") ~= nil, "the length refusal explains itself")

  check(Ops.setNickname(S, mon, "PIKA€") == false,
        "a name with an unrenderable glyph is refused")
  eq(mon.nickname, "1234567890", "a refused glyph leaves the mon alone")
  check(S.status:match("cannot render") ~= nil, "the glyph refusal explains itself")
  check(Ops.setNickname(S, mon, "POKE@MON") == false,
        "a name with the invisible @ terminator is refused")
  eq(mon.nickname, "1234567890", "a refused @ name leaves the mon alone")
  check(S.status:match("cannot render") ~= nil, "the @ refusal explains itself")

  check(Ops.setNickname(S, nil, "X") == false, "setNickname without a mon refuses")
  check(S.status:match("Pick a slot") ~= nil, "and explains itself")
  check(Ops.clearNickname(S, nil) == false, "clearNickname without a mon refuses")

  -- the canonical round trip: what the game reads back is the same either way
  mon.nickname = "SPARKY"
  local encoded = SaveData.encode(S.save)
  local back = SaveData.decode(encoded)
  eq(back.party[1].nickname, "SPARKY", "a nickname survives a save round trip")
end

-- App.load corrupt-save vs missing-save (Important fix #2): App.load takes
-- an optional path override precisely so tests can drive this without
-- touching the real default save file.
local App = require("App")

-- App.draw() reads the pointer at draw time, so a headless draw needs a mouse
-- module.  Parked off-screen: these tests call App.save/App.reload/App.close
-- directly (the chrome is layout over those, exactly like the panels are
-- layout over Ops) and use App.draw only as a "does the whole editor still
-- paint" smoke test.
love.mouse = { getPosition = function() return -1, -1 end }

do
  local tmpPath = os.tmpname() .. "-missing-save.lua"
  os.remove(tmpPath)

  App.load(tmpPath)
  local s = App.getState()
  eq(s.loadError, false, "App.load missing-file: loadError stays false")
  eq(s.allowSave, true, "App.load missing-file: allowSave stays true")
  check(s.status:match("No save at") ~= nil, "App.load missing-file status mentions no save")
end

do
  local tmpPath = os.tmpname() .. "-corrupt-save.lua"
  local f = io.open(tmpPath, "wb")
  f:write("not valid lua {{{")
  f:close()

  App.load(tmpPath)
  local s = App.getState()
  eq(s.loadError, true, "App.load corrupt-file: loadError set true")
  eq(s.allowSave, false, "App.load corrupt-file: allowSave set false")
  check(s.status:match("Corrupt save") ~= nil, "App.load corrupt-file status mentions corrupt save")

  -- Save while loadError is set must be a no-op: the file on disk (the
  -- corrupt real save) must not be overwritten by the stub we are editing.
  App.save()
  local unchanged = io.open(tmpPath, "rb")
  local contents = unchanged:read("*a")
  unchanged:close()
  eq(contents, "not valid lua {{{", "Save no-op leaves the corrupt file on disk untouched")
  check(App.getState().status:match("disabled") ~= nil, "Save no-op reports a disabled status")

  -- Fixing the file and Reloading must re-enable Save.
  local fixed = io.open(tmpPath, "wb")
  fixed:write(SaveData.encode(SaveData.newGame()))
  fixed:close()
  App.reload()
  eq(App.getState().loadError, false, "Reload after fixing the file clears loadError")
  eq(App.getState().allowSave, true, "Reload after fixing the file re-enables allowSave")

  os.remove(tmpPath)
end

do
  -- The quit / close confirmation re-arms once new edits land, so a prior
  -- "press quit again" arming cannot be spent discarding later changes.
  local tmpPath = os.tmpname() .. "-quitarmed-save.lua"
  os.remove(tmpPath)
  App.load(tmpPath)
  local s = App.getState()
  s._quitArmed = true

  Ops.addMoney(s, 10)
  eq(App.getState()._quitArmed, false, "A fresh dirty edit resets _quitArmed")
  eq(App.getState()._openArmed, false, "A fresh dirty edit resets _openArmed")

  os.remove(tmpPath)
end

do
  -- Close: unsaved edits arm once, and the teardown itself is deferred to the
  -- end of the frame -- doing it inline left the rest of App.draw painting
  -- against a state that had already been unloaded.
  local tmpPath = os.tmpname() .. "-close-save.lua"
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(SaveData.newGame()))
  f:close()

  local closed = 0
  App.load(tmpPath, { version = "red", slotId = "slot1", embedded = true,
                      onClose = function() closed = closed + 1 end })
  local s = App.getState()
  Ops.addMoney(s, 10)

  check(App.close() == false, "Close with unsaved edits arms instead of leaving")
  eq(closed, 0, "an armed Close has not left yet")
  check(s.status:match("Unsaved changes") ~= nil, "an armed Close explains itself")

  check(App.close() == true, "a second Close goes through")
  eq(closed, 0, "Close does not tear down mid-dispatch")
  check(s._closeRequested, "Close records the request for the end of the frame")

  App.draw()
  eq(closed, 1, "the deferred Close ran once the frame finished")

  -- the host (main.lua's closeEditor) is what unloads; after that, events
  -- still in flight must not crash it
  App.unload()
  eq(App.getState(), nil, "App.unload drops the editor state")
  App.draw()
  App.keypressed("escape")
  App.wheelmoved(0, 1)
  eq(App.quit(), false, "a torn-down editor never blocks quit")
  check(true, "post-close events are tolerated")

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- Save and Reload need a modifier: a bare letter key is one stray keystroke
  -- away from writing the file, and there is no undo.
  local tmpPath = os.tmpname() .. "-shortcut-save.lua"
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(SaveData.newGame()))
  f:close()

  App.load(tmpPath)
  local s = App.getState()
  local before = s.save.money
  Ops.addMoney(s, 10)
  check(s.dirty, "the edit landed")

  love.keyboard = { isDown = function() return false end }
  App.keypressed("s")
  check(App.getState().dirty, "bare s does not save")
  App.keypressed("r")
  eq(App.getState().save.money, before + 10, "bare r does not discard the edit")

  love.keyboard = { isDown = function() return true end }
  App.keypressed("s")
  check(App.getState().dirty == false, "Cmd/Ctrl+S saves")
  love.keyboard = { isDown = function() return false end }

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- #476: on Android a high-DPI 1560x720 capture can leave the editor with
  -- only a compact logical viewport.  The Items picker must not hand a
  -- negative list height to love.graphics.setScissor in that layout.
  local tmpPath = os.tmpname() .. "-items-compact-save.lua"
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(SaveData.newGame()))
  f:close()

  local oldDimensions = love.graphics.getDimensions
  local oldScissor = love.graphics.setScissor
  love.graphics.getDimensions = function() return 520, 240 end
  love.graphics.setScissor = function(_, _, width, height)
    if width and (width < 0 or height < 0) then
      error("Can't set scissor with negative width and/or height.")
    end
  end
  App.load(tmpPath, { version = "red" })
  App.getState().tab = "items"
  local ok, err = pcall(App.draw)
  check(ok, "the Items tab draws in a compact Android viewport: " .. tostring(err))
  love.graphics.getDimensions = oldDimensions
  love.graphics.setScissor = oldScissor

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- Whole-editor smoke test: every tab has to survive a real headless draw,
  -- which is what catches a layout that divides by a nil font metric or
  -- indexes a save field the panel assumed was always present.
  local tmpPath = os.tmpname() .. "-draw-save.lua"
  local data = SaveData.newGame()
  data.party = { MonOps.create(Data, "CHARIZARD", 100) }
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  App.load(tmpPath, { version = "red" })
  local s = App.getState()
  for _, tab in ipairs({ "party", "boxes", "items", "events", "map", "dex" }) do
    s.tab = tab
    local ok, err = pcall(App.draw)
    check(ok, "the " .. tab .. " tab draws headlessly: " .. tostring(err))
  end
  -- and with a mon selected, which is a different code path in the inspector
  s.tab = "party"
  Ops.selectParty(s, 1)
  local ok, err = pcall(App.draw)
  check(ok, "the party inspector draws with a selection: " .. tostring(err))

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- Open... / App.openPath: switch to another save; dirty needs a second open.
  local a = os.tmpname() .. "-open-a.lua"
  local b = os.tmpname() .. "-open-b.lua"
  local dataA = SaveData.newGame(); dataA.money = 111
  local dataB = SaveData.newGame(); dataB.money = 222
  assert(SaveIO.save(a, dataA))
  assert(SaveIO.save(b, dataB))

  App.load(a)
  eq(App.getState().save.money, 111, "openPath setup: loaded A")
  eq(App.getState().path, a, "openPath setup: path is A")

  check(App.openPath(b) == true, "openPath clean switch succeeds")
  eq(App.getState().path, b, "openPath updates path to B")
  eq(App.getState().save.money, 222, "openPath loads B money")
  eq(App.getState().dirty, false, "openPath clears dirty")

  App.getState().dirty = true
  check(App.openPath(a) == false, "openPath dirty first call arms confirm")
  eq(App.getState().path, b, "openPath dirty first call keeps current path")
  check(App.getState().status:match("Unsaved changes") ~= nil,
        "openPath dirty first call status warns")
  check(App.openPath(a) == true, "openPath dirty second call proceeds")
  eq(App.getState().path, a, "openPath dirty second call switches path")
  eq(App.getState().save.money, 111, "openPath dirty second call loads A")

  check(App.openPath(b, true) == true, "openPath force=true skips arming")
  eq(App.getState().path, b, "openPath force switches immediately")

  -- Drag-drop uses the File:getFilename() API.
  local dropped = { getFilename = function() return a end }
  App.filedropped(dropped)
  eq(App.getState().path, a, "filedropped opens the dropped path")

  os.remove(a); os.remove(b)
  for _, path in ipairs({ a, b }) do
    for _, bak in ipairs(FsIo.globPrefix(path .. ".bak-")) do os.remove(bak) end
  end
end

do
  -- #515: badge read/write agreement between SaveData/the in-game grant
  -- and the editor.  checkVictoryRewards (src/world/OverworldController.lua)
  -- writes save.inventory[badge] = 1, a truthy number, not the boolean
  -- `true` the editor used to compare against with `== true`.  This drives
  -- the same field through a real save encode/decode round trip and checks
  -- src/inventory/Badges.count (what the in-game badge case/count reads)
  -- agrees with what the editor's own badge state shows.
  local Badges = require("src.inventory.Badges")

  local save = SaveData.newGame()
  local id = Badges.list(Data)[1].id
  -- simulate the in-game grant's exact representation, not the editor's
  save.inventory[id] = 1
  eq(Badges.count(Data, save), 1, "Badges.count sees a numeric 1 grant as earned")

  local encoded = SaveData.encode(save)
  local back = SaveData.decode(encoded)
  eq(back.inventory[id], 1, "save round trip preserves the numeric badge flag")
  eq(Badges.count(Data, back), 1, "Badges.count still agrees after the round trip")

  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = back
  check(Ops.badgeIds(S)[1] ~= nil, "the editor's badge catalog is non-empty")
  check(S.save.inventory[id] and true or false,
        "the editor's own truthy read (panel badge chip state) sees the grant as earned")

  -- toggling off then on again round-trips through the editor's own write
  -- shape and still agrees with Badges.count
  Ops.toggleBadge(S, id)
  eq(S.save.inventory[id], nil, "toggleBadge clears the badge (nil, not false)")
  eq(Badges.count(Data, S.save), 0, "Badges.count agrees once cleared")
  Ops.toggleBadge(S, id)
  eq(S.save.inventory[id], 1, "toggleBadge re-earns the badge as a truthy 1, matching the in-game grant")
  eq(Badges.count(Data, S.save), 1, "Badges.count agrees once re-earned")
end

do
  -- #529: focusing a text field raises the OS soft keyboard on Android/iOS
  -- (love.keyboard.setTextInput(true, x, y, w, h)) and blurring lowers it;
  -- desktop raises the same way but never lowers, since setTextInput is
  -- global SDL state and the launcher's own text fields (RomImporter slot
  -- rename, ROM finder) depend on it staying enabled.
  --
  -- This is the closest honest check this checkout can run: the real soft
  -- keyboard is OS chrome outside the LOVE frame, unreachable by any
  -- driver. A human still has to verify on an Android build that the
  -- keyboard visibly rises over the Items search bar, typed characters
  -- filter the list, and Enter/Escape/switching tabs lowers it again.
  local Kit = require("Kit")
  local calls = {}
  local savedKeyboard, savedSystem = love.keyboard, love.system

  local function stubOS(name)
    love.system = { getOS = function() return name end }
    love.keyboard = {
      isDown = function() return false end,
      setTextInput = function(...) calls[#calls + 1] = { ... } end,
    }
  end

  -- Android: focusing raises with the field's rect, restaying focused on
  -- the same id does not re-raise, and blur lowers it.
  stubOS("Android")
  Kit.focus = nil
  Kit.beginFrame(15, 15, true)
  Kit.textfield("kb-test", 10, 10, 100, 20, "", "type here")
  eq(#calls, 1, "Android: focusing a field raises the soft keyboard")
  check(calls[1][1] == true, "Android: raise call passes enable=true")
  eq(calls[1][2], 10, "Android: raise call passes the field's x")
  eq(calls[1][3], 10, "Android: raise call passes the field's y")
  eq(calls[1][4], 100, "Android: raise call passes the field's w")
  eq(calls[1][5], 20, "Android: raise call passes the field's h")

  Kit.beginFrame(15, 15, false)
  Kit.textfield("kb-test", 10, 10, 100, 20, "abc", "type here")
  eq(#calls, 1, "Android: staying focused on the same field does not re-raise")

  Kit.blur()
  eq(#calls, 2, "Android: blur lowers the soft keyboard")
  eq(calls[2][1], false, "Android: lower call passes enable=false")
  check(Kit.focus == nil, "blur clears Kit.focus")

  -- Desktop: focusing still raises (harmless there), but blur must not
  -- disable text input globally -- the launcher's own fields rely on it
  -- staying on.
  calls = {}
  stubOS("Mac OS X")
  Kit.beginFrame(65, 65, true)
  Kit.textfield("kb-test2", 60, 60, 80, 24, "", "")
  eq(#calls, 1, "desktop: focusing a field still raises setTextInput")
  Kit.blur()
  eq(#calls, 1, "desktop: blur does not call setTextInput(false)")

  love.keyboard, love.system = savedKeyboard, savedSystem
  Kit.focus = nil
end

do
  -- #541: changing species took the editor down.  The inspector's arrows
  -- called MonOps.setSpecies on whatever record came next in the catalog, and
  -- the stat recalculation indexes baseStats.<stat> unconditionally
  -- (src/pokemon/Stats.lua, ported from home/move_mon.asm CalcStat) because
  -- the asm's BaseStats is a fixed 151-entry table with no partial rows.  The
  -- editor's catalog is NOT that table: it is every key in Data.pokemon after
  -- the mod merge, and a partial record survives that merge as a warning
  -- rather than a rejection (src/mods/Schemas.lua R.pokemon).  So the sweep
  -- below is the real check -- every id the catalog offers has to either
  -- assign or refuse in words, and neither may raise.
  local S = State.new()
  S.data = Data
  S.save = SaveData.newGame()

  -- a mod-shaped partial record: registered, listed, missing the stats the
  -- Gen1 formulas read
  Data.pokemon.TESTMON_PARTIAL = { name = "TESTMON", dex = 0,
    baseStats = { hp = 40, attack = 30 }, growthRate = "MEDIUM_FAST",
    types = { "NORMAL" }, learnset = {} }
  S.cat = Catalog.build(Data)

  check(Ops.speciesUsable(S, "PIKACHU"), "a complete record is usable")
  check(Ops.speciesUsable(S, "TESTMON_PARTIAL") == false,
        "a record missing base stats is not usable")
  check(Ops.speciesUsable(S, "NO_SUCH_SPECIES") == false,
        "an id that is not in the data at all is not usable")

  local mon = MonOps.create(Data, "WARTORTLE", 20)
  S.editingMon = mon
  local statsBefore = mon.stats.attack
  check(Ops.setSpecies(S, mon, "TESTMON_PARTIAL") == false,
        "setSpecies refuses a record the formulas cannot use")
  eq(mon.species, "WARTORTLE", "a refused setSpecies leaves the mon alone")
  eq(mon.stats.attack, statsBefore, "a refused setSpecies leaves the stats alone")
  check(S.status:match("base stats") ~= nil, "a refused setSpecies explains itself")
  check(S.dirty == false, "a refused setSpecies does not dirty the save")

  -- the crash itself: walk the whole catalog the way the arrows did
  local landed = {}
  local walkOk, walkErr = pcall(function()
    for _ = 1, #S.cat.species do
      Ops.stepSpecies(S, mon, 1)
      landed[mon.species] = true
      assert(Ops.speciesUsable(S, mon.species),
        "stepSpecies parked on " .. tostring(mon.species))
    end
  end)
  check(walkOk, "cycling the whole catalog never errors: " .. tostring(walkErr))
  check(landed.TESTMON_PARTIAL == nil, "cycling steps over an unusable record")
  check(landed.PIKACHU, "cycling still reaches ordinary species")

  local backOk, backErr = pcall(function()
    for _ = 1, #S.cat.species do Ops.stepSpecies(S, mon, -1) end
  end)
  check(backOk, "cycling backwards never errors: " .. tostring(backErr))

  -- and every real id assigns, so "nothing crashes" cannot be bought by
  -- refusing everything
  local assigned, refused = 0, 0
  for _, id in ipairs(S.cat.species) do
    if id ~= "TESTMON_PARTIAL" then
      local ok, err = pcall(Ops.setSpecies, S, mon, id)
      check(ok, "setSpecies " .. id .. ": " .. tostring(err))
      if ok and mon.species == id then assigned = assigned + 1 else refused = refused + 1 end
    end
  end
  eq(refused, 0, "no real species is refused")
  check(assigned > 140, "the whole dex assigns (" .. assigned .. " species)")

  Data.pokemon.TESTMON_PARTIAL = nil
end

do
  -- #541 search predicate.  The picker replaced the arrows, so the filter is
  -- the only way to reach a species now and its rules are worth pinning: ids
  -- and names substring-match case-insensitively, a dex number matches whole
  -- (a substring match would answer "25" with ELECTABUZZ, #125), and the
  -- query is plain text, not a Lua pattern.
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()

  check(Ops.speciesMatches(S, "PIKACHU", "pika"), "lowercase query matches an id")
  check(Ops.speciesMatches(S, "PIKACHU", "KACH"), "a mid-word substring matches")
  check(Ops.speciesMatches(S, "PIKACHU", "25"), "a bare dex number matches")
  check(Ops.speciesMatches(S, "PIKACHU", "025"), "the padded dex number matches")
  check(Ops.speciesMatches(S, "ELECTABUZZ", "25") == false,
        "a dex number does not substring-match #125")
  check(Ops.speciesMatches(S, "PIKACHU", ""), "an empty query matches everything")

  eq(#Ops.speciesSearch(S, ""), #S.cat.species, "an empty search lists the catalog")
  -- a dot is a literal, not a pattern wildcard: MR.MIME is the one species
  -- whose printed name carries one, so it is the whole result
  local dots = Ops.speciesSearch(S, ".")
  eq(#dots, 1, "a dot matches literally instead of matching everything")
  eq(dots[1], "MR_MIME", "and the literal it matched is MR.MIME's name")
  eq(#Ops.speciesSearch(S, "%a"), 0, "a pattern class is literal too")
  check(#Ops.speciesSearch(S, "zzzznope") == 0, "a miss returns nothing")
  local pika = Ops.speciesSearch(S, "pikachu")
  eq(#pika, 1, "an exact name search narrows to one")
  eq(pika[1], "PIKACHU", "and it is the right one")
end

do
  -- #541 end to end through App: open the picker off a selected slot, type,
  -- commit with Enter.  Enter and Escape have to be taken before the focused
  -- field sees them -- Kit maps both to the same "\r" edit, which cannot tell
  -- "commit the top match" from "give up".
  local Kit = require("Kit")
  local SpeciesPicker = require("SpeciesPicker")
  local tmpPath = os.tmpname() .. "-picker-save.lua"
  local data = SaveData.newGame()
  data.party = { MonOps.create(Data, "WARTORTLE", 20) }
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  App.load(tmpPath, { version = "red" })
  local S = App.getState()
  S.tab = "party"

  check(Ops.openSpeciesPicker(S, Kit) == false,
        "the picker refuses to open with no slot selected")
  check(S.speciesPicker == nil, "and it stayed closed")
  check(S.status:match("Pick a slot") ~= nil, "and it said why")

  Ops.selectParty(S, 1)
  check(Ops.openSpeciesPicker(S, Kit) == true, "the picker opens on a selected slot")
  check(S.speciesPicker ~= nil, "the picker is up")
  eq(S.speciesPicker.query, "", "it opens with an empty query")
  eq(Kit.focus, "species-picker", "it opens with the field focused (#529 keyboard)")

  local ok, err = pcall(App.draw)
  check(ok, "the picker draws headlessly: " .. tostring(err))

  App.textinput("PIKACHU")
  ok, err = pcall(App.draw)
  check(ok, "the picker draws while typing: " .. tostring(err))
  eq(S.speciesPicker.query, "PIKACHU", "typing reaches the picker's field")
  eq(#SpeciesPicker.results(S), 1, "the list narrowed to the typed species")

  App.keypressed("return")
  eq(S.save.party[1].species, "PIKACHU", "Enter commits the top match")
  check(S.speciesPicker == nil, "and closes the picker")
  check(S.dirty, "and the save is dirty")

  -- Escape leaves without touching the mon
  Ops.openSpeciesPicker(S, Kit)
  App.textinput("BULBASAUR")
  App.draw()
  App.keypressed("escape")
  check(S.speciesPicker == nil, "Escape closes the picker")
  eq(S.save.party[1].species, "PIKACHU", "Escape did not commit anything")
  check(S.editingMon ~= nil, "Escape closed the picker, not the selection")

  -- a query nothing matches cannot commit
  Ops.openSpeciesPicker(S, Kit)
  App.textinput("zzzznope")
  App.draw()
  App.keypressed("return")
  check(S.speciesPicker ~= nil, "Enter on an empty result set keeps the picker up")
  check(S.status:match("No species matches") ~= nil, "and says so")
  eq(S.save.party[1].species, "PIKACHU", "and changes nothing")
  Ops.closeSpeciesPicker(S, Kit)

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- The inspector's nickname field is commit-on-Enter: the draft lives in
  -- S.nicknameDraft while typing, Enter commits it through Ops.setNickname,
  -- and Escape discards it.  Drive it through App the way a player would:
  -- focus the field (a click is just a Kit.focus assignment here), type,
  -- drain the edits with a draw, then press Enter / Escape.
  local Kit = require("Kit")
  local tmpPath = os.tmpname() .. "-nickname-save.lua"
  local data = SaveData.newGame()
  data.party = { MonOps.create(Data, "CHARIZARD", 50) }
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  App.load(tmpPath, { version = "red" })
  local S = App.getState()
  S.tab = "party"
  Ops.selectParty(S, 1)
  local mon = S.editingMon
  eq(mon.nickname, nil, "the save starts un-nicknamed")

  -- type "SPARKY" and commit with Enter
  Kit.focus = "mon-nickname"
  App.textinput("SPARKY")
  App.draw()
  eq(S.nicknameDraft, "SPARKY", "typed text lands in the draft")
  App.keypressed("return")
  eq(mon.nickname, "SPARKY", "Enter commits the draft to the mon")
  check(S.dirty == true, "the commit marks the save dirty")
  check(Kit.focus == nil, "Enter blurs the field")
  S.dirty = false

  -- The field has no select-all, so a rename is backspace-then-type (the
  -- caret parks at the end, exactly like the editor's other fields).
  local function clearField(n)
    Kit.focus = "mon-nickname"
    for _ = 1, n do App.keypressed("backspace") end
    App.draw()
  end

  -- type junk, then Escape: nothing is committed and the draft is discarded
  clearField(#mon.nickname)
  App.textinput("ZEPTO")
  App.draw()
  eq(S.nicknameDraft, "ZEPTO", "the draft holds the new typing")
  App.keypressed("escape")
  eq(mon.nickname, "SPARKY", "Escape does not commit")
  eq(S.nicknameDraft, "SPARKY", "Escape resets the draft to the committed name")
  check(Kit.focus == nil, "Escape blurs the field")

  -- an unrenderable glyph is blocked AT INPUT: the euro sign never reaches
  -- the draft, so the field can only ever hold what the game can render
  clearField(#mon.nickname)
  App.textinput("PIKA\226\130\172") -- PIKA + euro sign, not a charmap glyph
  App.draw()
  eq(S.nicknameDraft, "PIKA", "an unrenderable glyph is dropped at input")
  App.keypressed("return")
  eq(mon.nickname, "PIKA", "the clean draft commits on Enter")

  -- and the 10-glyph cap blocks extra input the same way
  clearField(#mon.nickname)
  App.textinput("123456789012345")
  App.draw()
  eq(S.nicknameDraft, "1234567890", "typing past 10 glyphs clamps at 10")

  -- the @ terminator never reaches the draft either: it draws as a space
  -- in-game, so the field strips it like any other unrenderable glyph.  The
  -- clamp test above left an uncommitted draft, so clear the whole draft.
  clearField(#S.nicknameDraft)
  App.textinput("POKE@MON")
  App.draw()
  eq(S.nicknameDraft, "POKEMON", "the @ terminator is stripped at input")

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- #541 modal shield.  Kit hit-tests without a z-order, so the picker cannot
  -- simply be drawn last: the chrome and the panel underneath would take the
  -- same tap.  App raises Kit.blockClicks around everything it draws before
  -- the picker and lowers it for the picker's own layer, which is asserted
  -- here by watching what Kit.press sees over one frame rather than by
  -- clicking coordinates the design is free to move.
  local Kit = require("Kit")
  local tmpPath = os.tmpname() .. "-shield-save.lua"
  local data = SaveData.newGame()
  data.party = { MonOps.create(Data, "WARTORTLE", 20) }
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  App.load(tmpPath, { version = "red" })
  local S = App.getState()
  S.tab = "party"
  Ops.selectParty(S, 1)

  -- the shield itself: a raised shield refuses a click that hits
  Kit.beginFrame(15, 15, true)
  Kit.blockClicks = false
  check(Kit.press(10, 10, 100, 20) == true, "an unshielded press takes the click")
  Kit.blockClicks = true
  check(Kit.press(10, 10, 100, 20) == false, "a shielded press refuses it")
  Kit.blockClicks = false
  Kit.endFrame()

  local realPress = Kit.press
  local seen = {}
  Kit.press = function(...)
    seen[#seen + 1] = Kit.blockClicks
    return realPress(...)
  end

  Ops.openSpeciesPicker(S, Kit)
  seen = {}
  App.draw()
  check(#seen > 0, "the opening frame dispatched clicks at all")
  local allShielded = true
  for _, v in ipairs(seen) do allShielded = allShielded and (v == true) end
  check(allShielded,
        "on the opening frame even the picker's own layer is shielded, so the "
        .. "click that opened it cannot read as a tap outside")

  seen = {}
  App.draw()
  check(seen[1] == true, "the frame under an open picker is shielded")
  check(seen[#seen] == false, "the picker's own layer is not")
  check(Kit.blockClicks == false, "the shield is down again once the frame ends")

  Kit.press = realPress

  -- a Close taken with the picker up must not leak the shield into the next
  -- session, which would open deaf to every click
  Kit.blockClicks = true
  App.unload()
  check(Kit.blockClicks == false, "unload lowers the shield")

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- #497 shrank the layout to fit a phone's width; #715 replaced that with
  -- reflow.  The scale never dips below the 0.9 readability floor now: a
  -- narrow window keeps readable fonts and 26px tap targets and the panels
  -- stack / drop columns / scroll instead of shrinking.  The width term
  -- (width/640) only stops a portrait phone from inflating to the 1.6 cap
  -- its height alone would buy.
  local Kit = require("Kit")
  local Theme = require("Theme")
  local function about(got, want, msg)
    check(math.abs(got - want) < 0.001,
          msg .. string.format(" (got %.4f, want %.4f)", got, want))
  end

  about(Kit.layout(720, 1560), 720 / 640,
    "portrait phone scales off its width, gently")
  check(Kit.layout(720, 1560) >= 0.9,
        "a portrait phone never drops below the readability floor")
  about(Kit.layout(1560, 720), 720 / 768, "landscape phone still scales off height")
  about(Kit.layout(360, 640), 0.9,
    "a tiny window stops at the readable floor and reflows instead of shrinking")
  about(Kit.layout(500, 800), 0.9, "500px wide sits on the floor too")

  -- desktop and laptop sizes keep the height-only scale they always had
  for _, size in ipairs({ { 1280, 800 }, { 1024, 768 }, { 1920, 1080 },
                          { 1440, 900 }, { 2560, 1440 }, { 900, 700 } }) do
    about(Kit.layout(size[1], size[2]),
      Theme.clamp(math.min(size[1] / 640, size[2] / 768), 0.9, 1.6),
      ("%dx%d keeps its height-based scale"):format(size[1], size[2]))
  end
end

do
  -- #497 draw pass at the two shapes the report came in on (720x1560 and
  -- 1560x720, an A20s held either way).  The layout is what a human has to
  -- judge, but a panel that lays itself out at a negative width is machine
  -- visible: LOVE rejects a negative scissor, so the inspector's own clip
  -- catches the collapse the roster used to cause by keeping an absolute
  -- 300px floor on a 720px-wide window.
  local Kit = require("Kit")
  local Theme = require("Theme")
  local tmpPath = os.tmpname() .. "-phone-save.lua"
  local data = SaveData.newGame()
  data.party = { MonOps.create(Data, "CHARIZARD", 100),
                 MonOps.create(Data, "PIDGEY", 5) }
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  local oldDimensions = love.graphics.getDimensions
  local oldScissor = love.graphics.setScissor
  love.graphics.setScissor = function(_, _, width, height)
    if width and (width < 0 or height < 0) then
      error(("negative scissor %sx%s"):format(tostring(width), tostring(height)))
    end
  end

  -- 720x1280 / 1280x720 are the #715 report's shapes (Android, both
  -- orientations): the Map tab used to lay its viewport out at a negative
  -- width in portrait and crash on the scissor.  The desktop sizes pin that
  -- the responsive reflow does not disturb the layouts that already worked.
  for _, size in ipairs({ { 720, 1560 }, { 1560, 720 }, { 480, 1040 },
                          { 1280, 800 }, { 720, 1280 }, { 1280, 720 },
                          { 1024, 768 }, { 1920, 1080 }, { 360, 640 } }) do
    love.graphics.getDimensions = function() return size[1], size[2] end
    App.load(tmpPath, { version = "red" })
    local S = App.getState()
    local label = ("%dx%d"):format(size[1], size[2])
    for _, tab in ipairs({ "party", "boxes", "items", "events", "map", "dex" }) do
      S.tab = tab
      local ok, err = pcall(App.draw)
      check(ok, ("the %s tab draws at %s: %s"):format(tab, label, tostring(err)))
    end
    check((S._mapViewW or 0) >= 0 and (S._mapViewH or 0) >= 0,
      ("the map viewport stays non-negative at %s (#715)"):format(label))
    S.tab = "party"
    Ops.selectParty(S, 1)
    local ok, err = pcall(App.draw)
    check(ok, ("the inspector draws at %s: %s"):format(label, tostring(err)))
    Ops.openSpeciesPicker(S, Kit)
    ok, err = pcall(App.draw)
    check(ok, ("the species picker draws at %s: %s"):format(label, tostring(err)))
    ok, err = pcall(App.draw)
    check(ok, ("the species picker redraws at %s: %s"):format(label, tostring(err)))
    Ops.closeSpeciesPicker(S, Kit)
  end

  love.graphics.getDimensions = oldDimensions
  love.graphics.setScissor = oldScissor

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- #715 reflow audit.  Kit records every control that could take a click
  -- while Kit.audit is set (shielded widgets are skipped, since a modal
  -- legitimately covers what it shields).  The sweep below drives every tab
  -- at the window shapes the reflow has to serve and FAILS if any two
  -- controls overlap or any control escapes the window, which is exactly
  -- the "buttons covering things" class of bug the shrink-to-fit layout
  -- kept producing.  Rects clip to the region that bounds their hit test,
  -- so a row scrolled out of a list is not a phantom overlap.
  local Kit = require("Kit")

  local function clipped(r)
    local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
    if r.clip then
      x1 = math.max(x1, r.clip.x); y1 = math.max(y1, r.clip.y)
      x2 = math.min(x2, r.clip.x + r.clip.w); y2 = math.min(y2, r.clip.y + r.clip.h)
    end
    if x2 - x1 <= 1 or y2 - y1 <= 1 then return nil end
    return x1, y1, x2, y2
  end

  local function overlap(a, b)
    local ax1, ay1, ax2, ay2 = clipped(a)
    if not ax1 then return false end
    local bx1, by1, bx2, by2 = clipped(b)
    if not bx1 then return false end
    return math.min(ax2, bx2) - math.max(ax1, bx1) > 1
       and math.min(ay2, by2) - math.max(ay1, by1) > 1
  end

  local function auditFrame(label, W, H)
    local rects = Kit.audit
    local controls = {}
    for _, r in ipairs(rects) do
      if r.class == "control" then controls[#controls + 1] = r end
    end
    check(#controls > 0, label .. ": the frame dispatched controls at all")
    local collisions, escapes = 0, 0
    for i = 1, #controls do
      local a = controls[i]
      local x1, y1, x2, y2 = clipped(a)
      if x1 and (x1 < -0.5 or y1 < -0.5 or x2 > W + 0.5 or y2 > H + 0.5) then
        escapes = escapes + 1
        print(("  escape: %s (%.0f,%.0f %.0fx%.0f)")
          :format(a.label, a.x, a.y, a.w, a.h))
      end
      for j = i + 1, #controls do
        if overlap(a, controls[j]) then
          collisions = collisions + 1
          print(("  overlap: '%s' vs '%s' at (%.0f,%.0f) / (%.0f,%.0f)")
            :format(a.label, controls[j].label, a.x, a.y,
              controls[j].x, controls[j].y))
        end
      end
    end
    check(collisions == 0, label .. ": no two controls overlap")
    check(escapes == 0, label .. ": every control stays inside the window")
  end

  local tmpPath = os.tmpname() .. "-audit-save.lua"
  local data = SaveData.newGame()
  data.party = {}
  for i = 1, require("src.pokemon.Party").MAX do
    data.party[i] = MonOps.create(Data, i % 2 == 0 and "PIDGEY" or "CHARIZARD",
      10 * i)
  end
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(data))
  f:close()

  local oldDimensions = love.graphics.getDimensions
  local sizes = { { 500, 800 }, { 720, 1280 }, { 1280, 720 },
                  { 1024, 768 }, { 900, 700 }, { 1920, 1080 } }
  for _, size in ipairs(sizes) do
    local W, H = size[1], size[2]
    love.graphics.getDimensions = function() return W, H end
    App.load(tmpPath, { version = "red" })
    local S = App.getState()
    -- populate the panels the fresh save leaves empty, so their controls
    -- (quantity rows, box cells, dock rows, flags) are exercised too
    Ops.selectParty(S, 1)
    Ops.boxAdd(S); Ops.boxAdd(S)
    Ops.addToBag(S, S.cat.items[1])
    Ops.addToPc(S, S.cat.items[2])
    Ops.setFlag(S, "EVENT_GOT_POKEDEX", true)
    for _, tab in ipairs({ "party", "boxes", "items", "events", "map", "dex" }) do
      S.tab = tab
      Kit.audit = {}
      local ok, err = pcall(App.draw)
      check(ok, ("%dx%d %s draws: %s"):format(W, H, tab, tostring(err)))
      if ok then auditFrame(("%dx%d %s"):format(W, H, tab), W, H) end
      Kit.audit = nil
    end
    -- the species picker dialog reflows too; frame 2, since the opening
    -- frame is fully shielded by design (#541) and would audit empty
    S.tab = "party"
    Ops.openSpeciesPicker(S, Kit)
    App.draw()
    Kit.audit = {}
    local ok, err = pcall(App.draw)
    check(ok, ("%dx%d species picker draws: %s"):format(W, H, tostring(err)))
    if ok then auditFrame(("%dx%d species picker"):format(W, H), W, H) end
    Kit.audit = nil
    Ops.closeSpeciesPicker(S, Kit)
  end
  love.graphics.getDimensions = oldDimensions

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  -- Box add flow: the Boxes panel's "+ Add mon here" and its dashed empty
  -- cells open the SAME species picker the inspector uses, in box-add mode,
  -- and the committed species lands in the selected box as a Lv5 mon built
  -- by the same MonOps path Ops.partyAdd uses.
  local Kit = require("Kit")
  local BoxesMod = require("src.pokemon.Boxes")
  local tmpPath = os.tmpname() .. "-boxadd-save.lua"
  local f = io.open(tmpPath, "wb")
  f:write(SaveData.encode(SaveData.newGame()))
  f:close()

  App.load(tmpPath, { version = "red" })
  local S = App.getState()
  S.tab = "boxes"

  check(Ops.openBoxAddPicker(S, Kit) == true, "box-add picker opens")
  check(S.speciesPicker ~= nil, "the picker is up")
  eq(S.speciesPicker.mode, "box-add", "and it is in box-add mode")
  eq(Kit.focus, "species-picker", "with the search field focused (#529)")

  local ok, err = pcall(App.draw)
  check(ok, "the box-add picker draws headlessly: " .. tostring(err))

  App.textinput("PIKACHU")
  App.draw()
  App.keypressed("return")
  local box = Ops.boxes(S)[S.selectedBox]
  check(S.speciesPicker == nil, "committing closes the picker")
  eq(#box, 1, "the commit added exactly one mon to the box")
  local mon = box[1]
  eq(mon.species, "PIKACHU", "the picked species landed in the box")
  eq(mon.level, 5, "as a Lv5 mon, matching partyAdd's default")
  check(mon.stats and mon.stats.hp and mon.stats.hp > 0,
        "with real Gen1 stats from MonOps.create")
  eq(mon.ot, S.save.player.name, "owned by the save's player")
  eq(mon.otId, S.save.player.id, "with the player's trainer id")
  check(S.editingMon == mon, "and the inspector now points at it")
  check(S.dirty, "and the save is dirty")

  -- Escape leaves without adding anything
  Ops.openBoxAddPicker(S, Kit)
  App.textinput("BULBASAUR")
  App.draw()
  App.keypressed("escape")
  check(S.speciesPicker == nil, "Escape closes the box-add picker")
  eq(#box, 1, "Escape added nothing")

  -- an unusable (mod-partial) record refuses instead of crashing (#541)
  Data.pokemon.TESTMON_BOXADD = { name = "TESTMON", dex = 0,
    baseStats = { hp = 40 }, growthRate = "MEDIUM_FAST",
    types = { "NORMAL" }, learnset = {} }
  S.cat = Catalog.build(Data)
  S.dirty = false
  check(Ops.boxAddSpecies(S, "TESTMON_BOXADD") == false,
        "a record without usable base stats is refused")
  eq(#box, 1, "and nothing was added")
  check(S.status:match("base stats") ~= nil, "and the refusal explains itself")
  check(S.dirty == false, "and the save stays clean")
  Data.pokemon.TESTMON_BOXADD = nil
  S.cat = Catalog.build(Data)

  -- a full box refuses to even open the picker
  while #box < BoxesMod.CAPACITY do Ops.boxAdd(S) end
  check(Ops.openBoxAddPicker(S, Kit) == false, "a full box refuses the picker")
  check(S.speciesPicker == nil, "and it stays closed")
  check(S.status:match("full") ~= nil, "and says why")

  -- ...and a commit raced against a filling box refuses too
  check(Ops.boxAddSpecies(S, "PIKACHU") == false,
        "boxAddSpecies refuses a full box")

  os.remove(tmpPath)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

print(string.format("save editor tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

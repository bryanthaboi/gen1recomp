package.path = "./?.lua;./?/init.lua;" .. package.path
local CacheBlob = require("src.import.CacheBlob")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_contest_ui_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_contest_ui_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local GV = require("src.core.GameVersion")

local function stubAnims(fn)
  local Anim = require("src.core.game3.battle.anim")
  local launchMove = Anim.launchMove
  Anim.launchMove = function(_, opts)
    if opts and opts.onEnd then opts.onEnd() end
    return true
  end
  local ok, err = pcall(fn)
  Anim.launchMove = launchMove
  if not ok then error(err, 0) end
end
local Versions = require("src.import.gba.versions")
local Rom = require("src.import.gba.rom")
GV.set("emerald")
Versions.select("emerald")
local sha = GV.VERSIONS.emerald.sha1
local rom = assert(Rom.open({
  info = function() return { size = #data, md5 = sha } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}, GV.forSha1(sha)))

local ROOT = "data/generated/gba"
local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}

local home = os.getenv("HOME") or ""
local identity = os.getenv("POKEPORT_IDENTITY")
local IDROOT
if identity and identity ~= "" then
  for _, r in ipairs({ home .. "/Library/Application Support/LOVE/" .. identity .. "/emerald/",
    home .. "/.local/share/love/" .. identity .. "/emerald/" }) do
    local h = io.open(r .. ROOT .. "/scripts/text.lua", "rb")
    if h then h:close(); IDROOT = r; break end
  end
end
if not IDROOT then
  local dir = require("tests.game3_cache").gameDir("emerald", "scripts/text.lua")
  IDROOT = dir and dir .. "/"
end

local function readFile(path)
  if files[path] then return files[path] end
  if not IDROOT then return nil end
  local h = io.open(IDROOT .. path, "rb")
  if not h then return nil end
  local s = CacheBlob.decode(IDROOT .. path, h:read("*a"))
  h:close()
  return s
end

package.loaded["src.core.game3.dataset"] = {
  cache = function() return { read = function(_, rel) return readFile(rel) end, exists = function(_, rel) return readFile(rel) ~= nil end } end,
  mountExtractRoots = function() end,
}

print("[test] extractors (pokeemerald/src/contest.c:1298, contest_painting.c:66)")
local GX = require("src.import.gba.rse.contest_gfx_extract")
local PX = require("src.import.gba.rse.contest_painting_extract")
local CX = require("src.import.gba.rse.contest_extract")
eq((GX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })), true, "contest stage gfx extractor ran")
eq((PX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })), true, "contest painting extractor ran")
CX.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
for _, rel in ipairs(GX.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
for _, rel in ipairs(PX.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
check(GX.ready(cache, ROOT) and PX.ready(cache, ROOT), "both manifests are ready")

local Vram = require("src.ui.game3.rse.contest_vram")
Vram.reset()
Vram.reader = readFile
local gm = Vram.manifest("rse/contest_gfx")
eq(#files[gm.gfx.interface.path], 0x2000, "interface tiles decompress to 8 KB (256 tiles)")
eq(#files[gm.gfx.audience.path], 0x2000, "audience tiles hold two 0x1000 frames")
eq(gm.maps.interface.entries, 32 * 64, "interface tilemap is 32x64")
eq(gm.sliderHeartY[0] .. "," .. gm.sliderHeartY[3], "36,156", "slider heart rows (contest.c:369)")
eq(gm.windows[4].left .. "," .. gm.windows[4].top .. "," .. gm.windows[4].width .. "," .. gm.windows[4].height, "1,15,17,4",
  "general text window template (contest.c:896)")
eq(gm.windows[10].left, 11, "move description window starts at column 11")
eq(#gm.palettes.interface_audience, 256, "interface + audience palette is 256 colors")
eq(gm.sine[64], 256, "gSineTable[64] is 256")
eq(#gm.affine.sliderHeart[1], 3, "slider heart disappear anim has two frames + end")
local pm = Vram.manifest("rse/contest_painting")
eq(pm.frames.lobby.entries, 1024, "lobby frame tilemap RL-decompresses to 32x32")
eq(pm.frames.cool.tiles, 176, "cool frame RL-decompresses to 176 tiles")
eq(pm.pointillism.count, 3200, "3200 pointillism points")
eq(#pm.framePalette, 128, "eight frame palettes")
eq(pm.captions[4], "gContestPaintingBeauty2", "museum caption table order")

print("[test] image processing (pokeemerald/src/image_processing_effects.c)")
local Fx = require("src.ui.game3.rse.contest_image_fx")
local function canvas(fill)
  local px = {}
  for i = 0, 64 * 64 - 1 do px[i] = fill end
  return px
end
local px = canvas(Fx.ALPHA)
px[10 * 64 + 10] = Fx.rgb2(10, 20, 30)
local ctx = Fx.context(px, { effect = Fx.EFFECT.GRAYSCALE_LIGHT, quantizeEffect = Fx.QUANTIZE.GRAYSCALE })
Fx.apply(ctx)
eq(px[10 * 64 + 10], Fx.rgb2(21, 21, 21), "grayscale light: Q8.8 weights then red + 3")
Fx.quantize(ctx)
eq(px[10 * 64 + 10], 22, "grayscale quantize maps gray 21 to index 22")
eq(px[0], 0, "transparent pixels quantize to the palette start")
eq(ctx.palette[22], Fx.rgb2(21, 21, 21), "grayscale preset palette")

px = canvas(Fx.ALPHA)
for y = 20, 22 do for x = 20, 22 do px[y * 64 + x] = Fx.rgb2(28, 28, 28) end end
ctx = Fx.context(px, { effect = Fx.EFFECT.OUTLINE_COLORED, personality = 3 })
Fx.apply(ctx)
eq(px[20 * 64 + 20], Fx.rgb2(23, 0, 0), "outline pixel takes the personality color (type 3 red, strength 0)")
eq(px[21 * 64 + 21], 0x7FFF, "interior light pixel turns white")
eq(px[0], Fx.ALPHA, "outline keeps transparency")

px = canvas(Fx.rgb2(3, 5, 7))
ctx = Fx.context(px, { effect = Fx.EFFECT.INVERT })
Fx.apply(ctx)
eq(px[100], Fx.rgb2(28, 26, 24), "invert")
px = canvas(Fx.rgb2(5, 9, 13))
ctx = Fx.context(px, { quantizeEffect = Fx.QUANTIZE.STANDARD_LIMITED_COLORS })
Fx.quantize(ctx)
eq(px[5], 1, "standard quantize: first color gets index 1")
eq(ctx.palette[1], Fx.rgb2(8, 12, 16), "standard quantize rounds channels up to multiples of 4")
eq(ctx.palette[0xDF], Fx.rgb2(15, 15, 15), "limited palette overflow gray at 0xDF")

local points = {}
local pb = files[pm.pointillism.path]
for i = 1, #pb do points[i - 1] = pb:byte(i) end
px = canvas(Fx.rgb2(16, 16, 16))
ctx = Fx.context(px, { effect = Fx.EFFECT.POINTILLISM, pointillism = points, pointillismCount = pm.pointillism.count })
Fx.apply(ctx)
local changed = 0
for i = 0, 64 * 64 - 1 do if px[i] ~= Fx.rgb2(16, 16, 16) then changed = changed + 1 end end
check(changed > 2000, "pointillism touches most of the canvas (" .. changed .. " pixels)")
eq(px[29 * 64 + 0] ~= Fx.rgb2(16, 16, 16), true, "first pointillism point lands at column 0 row 29")

print("[test] contest stage + results play the engine's events (pokeemerald/src/contest.c:1726)")
local Contest = require("src.core.game3.rse.contest")
local Util = require("src.core.game3.rse.contest_util")
local man = assert(load(files[ROOT .. "/" .. CX.SUB .. "/manifest.lua"], "@m", "t", {}))()
local moves = require("src.import.gba.contest_moves_extract").extract(rom)
local D = Contest.buildData(moves, man)

local function lcg(seed)
  local Rng = require("src.core.game3.rng")
  local v = seed
  return function()
    v = (Rng.mulU32(v, 1103515245) + 24691) % 4294967296
    return math.floor(v / 65536)
  end
end

local Stage = require("src.ui.game3.rse.contest")
local textTable
if IDROOT then
  local chunk = loadfile(IDROOT .. ROOT .. "/scripts/text.lua")
  textTable = chunk and chunk() or nil
end
Stage.ir = function(key)
  if textTable and textTable[key] then return textTable[key] end
  return { { t = "text", s = key }, { t = "eos" } }
end
Stage.has = function(key) return true end

local C = require("src.core.game3.constants").of("emerald")
local function mv(name) return C:require("moves", name) end
local PLAYER = {
  species = C:require("species", "SPECIES_SALAMENCE"), nickname = "SALAMENCE", trainerName = "NICK",
  moves = { mv("MOVE_HEADBUTT"), mv("MOVE_EMBER"), mv("MOVE_DRAGON_BREATH"), mv("MOVE_FLY") },
  cool = 120, beauty = 40, cute = 10, smart = 20, tough = 80, sheen = 30, personality = 12345, otId = 1,
}

local function newContest(seed, category)
  local c = Contest.new({ data = D, category = category or 0, rank = 0, rng = lcg(seed) })
  c:setContestants({ gameClear = false, player = PLAYER })
  c:calculateRound1Points()
  return c
end

local function heartsOf(appeal)
  local q = appeal / 10
  local h = q >= 0 and math.floor(q) or -math.floor(-q)
  if h > 16 then h = 16 elseif h < -16 then h = -16 end
  return h
end

local function countHearts(screen, i)
  local row = screen.c.turnOrder[i] * 5 + 2
  local red, black = 0, 0
  local base = ({ [0] = 0x5011, 0x6011, 0x7011 })[i] or 0x8011
  for y = row, row + 1 do
    for x = 22, 29 do
      local e = screen.bg[0]:get(x, y)
      if e == base + 1 then red = red + 1 elseif e == base + 3 then black = black + 1 end
    end
  end
  return red, black
end

for _, case in ipairs({ { seed = 0x1234, sched = { 2, 0, 2, 3, 1 }, cat = 0 }, { seed = 0xBEEF, sched = { 1, 1, 0, 2, 3 }, cat = 0 },
  { seed = 0x77, sched = { 3, 2, 1, 0, 2 }, cat = 4 } }) do
  local ref = newContest(case.seed, case.cat)
  ref:init()
  ref:run(case.sched)
  local c = newContest(case.seed, case.cat)
  local turns, heartsOk, heartsChecked = 0, true, 0
  local screen
  local sched = case.sched
  local Anim = require("src.core.game3.battle.anim")
  local launchMove, launched = Anim.launchMove, {}
  Anim.launchMove = function(move, opts)
    launched[#launched + 1] = { move = move, opts = opts }
    if opts.onEnd then opts.onEnd() end
    return true
  end
  screen = Stage.open({
    contest = c, headless = true, moveName = function(m) return "MOVE" .. m end,
    autoInput = function(s)
      if s.m.tasks:isActive(s:func("taskHandleMoveSelectInput")) then
        c.contest.playerMoveChoice = sched[c.contest.appealNumber + 1]
      end
      return { new = { a = true }, held = { a = true }, rep = {} }
    end,
  })
  Anim.launchMove = launchMove
  eq(screen.done, true, string.format("seed %04X: the stage finishes all five appeals", case.seed))
  eq(c.contest.appealNumber, 5, "five appeal rounds ran through the UI")
  local same = true
  for i = 0, 3 do
    if c.totals[i] ~= ref.totals[i] or c.standings[i] ~= ref.standings[i] or c.round2[i] ~= ref.round2[i] then same = false end
  end
  check(same, string.format("seed %04X: UI playback leaves the engine result unchanged (totals %d %d %d %d)", case.seed,
    c.totals[0], c.totals[1], c.totals[2], c.totals[3]))
  check(screen.frames > 2000 and screen.frames < 20000, "stage ran " .. screen.frames .. " frames")
  check(#launched > 0, "appeal turns launch the shared move-animation VM")
  local sample = launched[1]
  eq(sample.opts.ctx.isContest, true, "contest animations enter jumpifcontest context")
  eq(sample.opts.attackerId .. "/" .. sample.opts.targetId, "2/3", "contest move animation uses battlers 2 and 3")
  eq(sample.opts.coordinateOverrides[2].x .. "/" .. sample.opts.coordinateOverrides[3].x, "112/48",
    "contest animation uses opponent-right and player-right coordinates")
end

print("[test] hearts on BG0 track every contestant's appeal at each turn end (pokeemerald/src/contest.c:3737)")
do
  local c = newContest(0x4242, 0)
  local mismatches, checks = 0, 0
  local turnEnd = Stage.turnEndStep
  Stage.turnEndStep = function(self, t)
    for i = 0, 3 do
      local red, black = countHearts(self, i)
      local h = heartsOf(self.c.status[i].appeal)
      checks = checks + 1
      if (h >= 0 and (red ~= h or black ~= 0)) or (h < 0 and (black ~= -h or red ~= 0)) then mismatches = mismatches + 1 end
    end
    return turnEnd(self, t)
  end
  stubAnims(function() Stage.open({ contest = c, headless = true, moveName = function(m) return "M" .. m end }) end)
  Stage.turnEndStep = turnEnd
  eq(checks, 80, "checked 4 contestants at 20 turn ends")
  eq(mismatches, 0, "heart tiles match hearts(appeal) for every contestant")
end

local Results = require("src.ui.game3.rse.contest_results")
do
  local c = newContest(0x99, 0)
  stubAnims(function() Stage.open({ contest = c, headless = true, moveName = function(m) return "M" .. m end }) end)
  local sess = { gameStats = {}, party = {} }
  local r = Results.open({ contest = c, session = sess, headless = true, noFieldHooks = true })
  eq(r.done, true, "results screen reaches the end")
  eq(sess.gameStats[36], 1, "GAME_STAT_ENTERED_CONTEST incremented")
  eq(sess.gameStats[37] or 0, c.standings[c.playerIndex] == 0 and 1 or 0, "GAME_STAT_WON_CONTEST follows the standings")
  local rd = Util.resultsData(c)
  for i = 0, 3 do
    local want = rd[i].barLengthPreliminary + (rd[i].lostPoints and -rd[i].barLengthRound2 or rd[i].barLengthRound2)
    eq(r.d.barLength[i], want, "result bar " .. i .. " ends at its last target (contest_util.c:1856)")
  end
  eq(r.d.numStandingsPrinted, 4, "four final standing numbers drawn")
  local winner = Util.winnerId(c)
  local L = r.bg[2]
  eq(math.floor(L:get(5, winner * 3 + 5) / 4096), 9, "the winner's box row is switched to palette 9")
end

print("[test] painting build (pokeemerald/src/contest_painting.c:474)")
do
  local Painting = require("src.ui.game3.rse.contest_painting")
  Painting.resetCache()
  local sp = C:require("species", "SPECIES_SALAMENCE")
  local winner = { species = sp, personality = 7, trainerId = 1, contestCategory = 3 * 1 + 2, contestRank = 3,
    monName = "SALAMENCE", trainerName = "NICK" }
  local st = Painting.build({ winner = winner, saveIdx = 9, isForArtist = false })
  eq(st.mon.effect, Fx.EFFECT.SHIMMER, "beauty museum painting uses the shimmer effect")
  eq(st.frameKey, "beauty", "beauty museum frame")
  local maxIdx = 0
  for i = 0, 64 * 64 - 1 do if st.mon.indices[i] > maxIdx then maxIdx = st.mon.indices[i] end end
  check(maxIdx < 0xE0, "limited quantization stays below 0xE0 (" .. maxIdx .. ")")
  if IDROOT then check(maxIdx > 4, "the Salamence front pic quantizes to several colors") end
  local art = Painting.build({ winner = winner, saveIdx = 9, isForArtist = true })
  eq(art.map[0], 0x1015, "artist painting background tile (contest_painting.c:418)")
  eq(art.caption, nil, "artist painting has no caption")
  local hall = Painting.build({ winner = { species = sp, personality = 7, trainerId = 1, contestCategory = 4, contestRank = 0,
    monName = "SALAMENCE", trainerName = "NICK" }, saveIdx = 0 })
  eq(hall.frameKey, "lobby", "hall painting uses the lobby frame")
  eq(hall.mon.effect, Fx.EFFECT.GRAYSCALE_LIGHT, "tough hall painting is light grayscale")
  if IDROOT then
    local spinda = C:require("species", "SPECIES_SPINDA")
    local a = Painting.monPixels({ species = spinda, personality = 0x12345678, trainerId = 0x00010001 })
    local b = Painting.monPixels({ species = spinda, personality = 0xFEDCBA98, trainerId = 0x00010001 })
    local changed = 0
    for i = 0, 64 * 64 - 1 do if a[i] ~= b[i] then changed = changed + 1 end end
    check(changed > 0, "contest painting applies each Spinda personality's spot pattern (" .. changed .. " pixels)")
  end
  if textTable then
    check(type(hall.caption) == "string" and hall.caption:find("NICK", 1, true) ~= nil, "hall caption names the trainer")
  end
end

print("[test] contest specials (pokeemerald/src/contest_util.c:1958)")
do
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  local sess = { version = "emerald", name = "NICK", gender = "male", party = {}, gameStats = {} }
  local mon = { species = C:require("species", "SPECIES_SALAMENCE"), level = 50, hp = 100, maxHp = 100,
    moves = { mv("MOVE_HEADBUTT"), mv("MOVE_EMBER"), mv("MOVE_DRAGON_BREATH"), mv("MOVE_FLY") },
    personality = 12345, otId = 1, nickname = IDROOT and "" or "SALAMENCE" }
  local cond = Pokeblock.contest(mon)
  cond.cool, cond.tough, cond.beauty, cond.sheen = 200, 100, 100, 50
  sess.party[1] = mon
  package.loaded["src.core.game3.runtime"] = { getSession = function() return sess end }
  local Contest2 = require("src.core.game3.rse.contest")
  local realData = Contest2.data
  Contest2.data = function() return D end
  local NC = require("src.core.game3.scripting.natives_contest")
  local Rse = require("src.core.game3.rse.init")
  local ctx = { specialVars = {}, stringVars = { "", "", "" } }
  local function set(id, v) ctx.specialVars[id] = v end
  local function get(id) return ctx.specialVars[id] or 0 end
  NC.partyIndex = 0
  set(0x8011, 0)
  set(0x8010, 0)
  NC.BY_NAME.TryEnterContestMon(ctx)
  eq(get(0x800D), 1, "TryEnterContestMon: ribbonless mon, Normal rank -> CAN_ENTER_CONTEST_EQUAL_RANK")
  local c = Util.current()
  check(c ~= nil and c.mons[3].species == mon.species, "the party mon becomes contestant 4")
  check(c.mons[3].nickname ~= "", "an unnamed mon enters under its species name (contest.c:2798)")
  set(0x8010, 1)
  NC.BY_NAME.TryEnterContestMon(ctx)
  eq(get(0x800D), 0, "Super rank without a Normal ribbon -> CANT_ENTER_CONTEST")
  set(0x8010, 0)
  NC.BY_NAME.TryEnterContestMon(ctx)
  c = Util.current()
  set(0x8006, 3)
  NC.BY_NAME.GetContestMonCondition(ctx)
  eq(get(0x8004), c.round1[3], "GetContestMonCondition reads round 1 points")
  NC.BY_NAME.BufferContestTrainerAndMonNames(ctx)
  eq(ctx.stringVars[1], "NICK", "BufferContestTrainerAndMonNames: STR_VAR_1 trainer")
  eq(get(0x8004), mon.species, "BufferContestTrainerAndMonNames: VAR_0x8004 species")
  c:init()
  c:run({ 0, 1, 2, 3, 0 })
  NC.BY_NAME.GetContestWinnerId(ctx)
  eq(get(0x8005), Util.winnerId(c), "GetContestWinnerId")
  NC.BY_NAME.BufferContestWinnerMonName(ctx)
  eq(ctx.stringVars[1], Util.monName(c.mons[Util.winnerId(c)]), "BufferContestWinnerMonName")
  NC.BY_NAME.ShouldReadyContestArtist(ctx)
  eq(get(0x8004), 0, "ShouldReadyContestArtist is false below Master rank")
  local _, n = NC.BY_NAME.CountPlayerMuseumPaintings(ctx)
  eq(n, 0, "no museum paintings yet (winners initialized from gDefaultContestWinners)")
  check(type(sess.contestWinners) == "table" and (sess.contestWinners[1].species or 0) ~= 0, "hall defaults filled on first use")
  set(0x800D, 8)
  NC.BY_NAME.GenerateContestRand(ctx)
  check(get(0x800D) < 8, "GenerateContestRand reduces VAR_RESULT modulo itself")
  NC.BY_NAME.TryContestGModeLinkup(ctx)
  for _ = 1, 700 do
    if not ctx.nativePoll or ctx.nativePoll() then break end
  end
  eq(get(0x800D), 6, "link contest linkup with nobody to link reports LINKUP_CONNECTION_ERROR")
  local _, won = NC.BY_NAME.HasMonWonThisContestBefore(ctx)
  eq(won, 0, "HasMonWonThisContestBefore is false without a ribbon")
  Contest2.data = realData
  Rse.reset()
end

print("[test] paintings match pygba captures pixel for pixel (pokeemerald/src/contest_painting.c:474)")
if not IDROOT then
  print("  skipped: POKEPORT_IDENTITY cache with mon pics not found")
else
  local Painting = require("src.ui.game3.rse.contest_painting")
  Painting.resetCache()
  local CASES = {
    { name = "museum_cool", species = 397, personality = 0x12345678, trainerId = 0x00010001, category = 2, rank = 3, saveIdx = 8, artist = false, fnv = 0x183FBBA8 },
    { name = "museum_beauty", species = 329, personality = 0x0BADBEEF, trainerId = 0x00020002, category = 3, rank = 3, saveIdx = 9, artist = false, fnv = 0x7CCDE6FC },
    { name = "museum_cute", species = 315, personality = 0x00000007, trainerId = 0x00030003, category = 7, rank = 3, saveIdx = 10, artist = false, fnv = 0xDA489FEC },
    { name = "museum_smart", species = 65, personality = 0x0000FF10, trainerId = 0x00040004, category = 11, rank = 3, saveIdx = 11, artist = false, fnv = 0x39AC0EEC },
    { name = "museum_tough", species = 68, personality = 0x00ABCDEF, trainerId = 0x00050005, category = 12, rank = 3, saveIdx = 12, artist = false, fnv = 0xDA6AB98D },
    { name = "hall_cute", species = 25, personality = 0x00000042, trainerId = 0x00060006, category = 2, rank = 1, saveIdx = 0, artist = false, fnv = 0x753BA90D },
    { name = "artist_cool", species = 394, personality = 0x7777AAAA, trainerId = 0x00070007, category = 1, rank = 3, saveIdx = 8, artist = true, fnv = 0x653DAC72 },
  }
  local bit = require("bit")
  local function render(st)
    local W = 240
    local out = {}
    for i = 0, W * 112 * 3 - 1 do out[i] = 0 end
    local gfx, pal = st.gfx, st.framePalette
    local tiles = math.floor(#gfx / 32)
    for ty = 0, 13 do for tx = 0, 29 do
      local e = st.map[ty * 32 + tx] or 0
      local tile, hf, vf, bank = e % 1024, math.floor(e / 1024) % 2 == 1, math.floor(e / 2048) % 2 == 1, math.floor(e / 4096) % 16
      for py = 0, 7 do for px = 0, 7 do
        local sx, sy = hf and 7 - px or px, vf and 7 - py or py
        local v = 0
        if tile < tiles then
          local b = gfx:byte(tile * 32 + sy * 4 + math.floor(sx / 2) + 1) or 0
          v = sx % 2 == 0 and b % 16 or math.floor(b / 16)
        end
        if v ~= 0 then
          local c = pal[bank * 16 + v + 1] or 0
          local o = ((ty * 8 + py) * W + tx * 8 + px) * 3
          out[o], out[o + 1], out[o + 2] = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
        end
      end end
    end end
    for i = 0, 64 * 64 - 1 do
      local v = st.mon.indices[i]
      if v ~= 0 then
        local c = st.mon.palette[v] or 0
        local o = ((24 + math.floor(i / 64)) * W + 88 + i % 64) * 3
        out[o], out[o + 1], out[o + 2] = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
      end
    end
    local h = 0x811C9DC5
    for i = 0, W * 112 * 3 - 1 do
      h = bit.bxor(h, out[i]) % 4294967296
      h = require("src.core.game3.rng").mulU32(h, 0x01000193)
    end
    return h
  end
  for _, cs in ipairs(CASES) do
    local st = Painting.build({ winner = { species = cs.species, personality = cs.personality, trainerId = cs.trainerId,
      contestCategory = cs.category, contestRank = cs.rank, monName = "TESTMON", trainerName = "NICK" },
      saveIdx = cs.saveIdx, isForArtist = cs.artist })
    eq(string.format("%08X", render(st)), string.format("%08X", cs.fnv), cs.name .. " frame + processed mon match the ROM")
  end
  local st = Painting.build({ winner = { species = 397, personality = 0x12345678, trainerId = 0x00010001, contestCategory = 2,
    contestRank = 3, monName = "TESTMON", trainerName = "NICK" }, saveIdx = 8 })
  eq(st.caption, "The marvelous, wonderful, and\nvery great TESTMON", "museum caption 3 of the cool set")
end

T.finish()

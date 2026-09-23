#!/usr/bin/env luajit
-- pokefirered/src/trade_scene.c:1337 DoTradeAnim_Cable

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_ROUTE2_HOUSE", party = {},
  name = "RED", trainerId = 4242, vars = {}, flags = {},
  dex = { seen = {}, owned = {} },
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local TradeScene = require("src.core.game3.trade_scene")

local function run(offer, received, opts, limit)
  local order, counts = {}, {}
  local frames = 0
  TradeScene.play(offer, received, nil, opts)
  local seen = TradeScene.phase()
  order[#order + 1] = seen
  counts[seen] = 0
  while frames < (limit or 20000) do
    frames = frames + 1
    local over = TradeScene.step()
    counts[seen] = (counts[seen] or 0) + 1
    if over then break end
    local now = TradeScene.phase()
    if now ~= seen then
      seen = now
      order[#order + 1] = seen
      counts[seen] = 0
    end
  end
  return order, counts, frames
end

local OFFER = { species = 63, nickname = "ABRA", level = 12 }
local RECEIVED = { species = 122, nickname = "MIMIEN", otName = "REYLEY", otId = 1985, level = 12 }

print("[test] 1. every cable-trade phase runs in pret's order")
-- pokefirered/src/trade_scene.c:1266 the STATE_* enum, cable branch
local EXPECTED = {
  { "start", 1 },
  { "mon_slide_in", 61 },
  { "send_msg", 1 },
  { "bye_bye", 80 },
  { "pokeball_depart", 64 },
  { "pokeball_depart_wait", 87 },
  { "fade_out_to_gba_send", 1 },
  { "wait_fade_out_to_gba_send", 16 },
  { "fade_in_to_gba_send", 1 },
  { "wait_fade_in_to_gba_send", 16 },
  { "gba_zoom_out", 16 },
  { "gba_flash_send", 21 },
  { "gba_stop_flash_send", 126 },
  { "pan_away_gba", 32 },
  { "create_link_mon_leaving", 1 },
  { "link_mon_travel_out", 75 },
  { "link_mon_travel_offscreen", 45 },
  { "fade_out_to_crossing", 1 },
  { "wait_fade_out_to_crossing", 16 },
  { "fade_in_to_crossing", 1 },
  { "wait_fade_in_to_crossing", 16 },
  { "crossing_link_mons_enter", 14 },
  { "crossing_blend_white_1", 1 },
  { "crossing_blend_white_2", 1 },
  { "crossing_blend_white_3", 1 },
  { "crossing_create_mon_pics", 1 },
  { "crossing_mon_pics_move", 75 },
  { "crossing_link_mons_exit", 44 },
  { "create_link_mon_arriving", 16 },
  { "fade_out_to_gba_recv", 1 },
  { "wait_fade_out_to_gba_recv", 16 },
  { "link_mon_travel_in", 28 },
  { "pan_to_gba", 76 },
  { "destroy_link_mon", 1 },
  { "link_mon_arrived_delay", 10 },
  { "move_gba_to_center", 33 },
  { "gba_flash_recv", 1 },
  { "gba_stop_flash_recv", 126 },
  { "gba_zoom_in", 19 },
  { "fade_out_to_new_mon", 1 },
  { "wait_fade_out_to_new_mon", 16 },
  { "fade_in_to_new_mon", 1 },
  { "wait_fade_in_to_new_mon", 16 },
  { "pokeball_arrive", 1 },
  { "fade_pokeball_to_normal", 1 },
  { "pokeball_arrive_wait", 107 },
  { "show_new_mon", 1 },
  { "new_mon_msg", 1 },
  { "delay_for_mon_anim", 61 },
  { "wait_for_mon_cry", 1 },
  { "take_care_of_mon", 250 },
  { "after_new_mon_delay", 60 },
  { "check_ribbons", 1 },
  { "end_link_trade", 1 },
  { "try_evolution", 1 },
  { "wait_evolution", 1 },
  { "fade_out_end", 1 },
  { "wait_fade_out_end", 16 },
}

local order, counts, total = run(OFFER, RECEIVED, { art = { gba = true } })
eq(#order, #EXPECTED, "the cinema ran " .. #EXPECTED .. " phases")
for i, want in ipairs(EXPECTED) do
  eq(order[i], want[1], "phase " .. i .. " is " .. want[1])
  eq(counts[want[1]], want[2], want[1] .. " lasts " .. want[2] .. " frames")
end

local sum = 0
for _, want in ipairs(EXPECTED) do sum = sum + want[2] end
eq(total, sum, "the whole cinema is " .. sum .. " frames")
check(not TradeScene.isOpen(), "the scene closed itself when the last phase ended")

print("[test] 2. a nil art sheet degrades to the timed hold")
local holdOrder, holdCounts, holdTotal = run(OFFER, RECEIVED, nil)
local held = {}
for _, name in ipairs(holdOrder) do held[name] = true end
check(held.hold, "the no-art run holds on black instead of the transfer")
for _, name in ipairs({
  "gba_zoom_out", "gba_flash_send", "pan_away_gba", "link_mon_travel_out",
  "crossing_mon_pics_move", "gba_zoom_in", "link_mon_travel_in",
}) do
  check(not held[name], "the no-art run skips " .. name)
end
check(held.fade_out_to_gba_send, "the no-art run keeps pret's fade to black")
eq(holdCounts.hold, TradeScene.HOLD_FRAMES, "the hold lasts HOLD_FRAMES")
eq(holdCounts.mon_slide_in, 61, "the art-free slide-in keeps pret's 61 frames")
eq(holdCounts.take_care_of_mon, 250, "the art-free reveal keeps pret's 250 frames")
check(holdTotal < total, "the held run is shorter than the full cinema")

print("[test] 3. the ball velocity table is pret's")
-- pokefirered/src/trade_scene.c:538
eq(TradeScene.BALL_VELOCITY[0], 0, "velocity[0]")
eq(TradeScene.BALL_VELOCITY[22], -4, "velocity[22]")
eq(TradeScene.BALL_VELOCITY[43], 0, "velocity[43]")
eq(TradeScene.BALL_VELOCITY[66], -4, "velocity[66]")
eq(TradeScene.BALL_VELOCITY[95], -1, "velocity[95]")
eq(TradeScene.BALL_VELOCITY[107], 3, "velocity[107]")
eq(TradeScene.BALL_VELOCITY[108], nil, "the table stops at 108 entries")

if not require("tests.game3_cache").mount() then
  print("[skip] 4-5: the in-game trades are ROM data: " .. tostring(require("tests.game3_cache").reason))
else
  print("[test] 4. the received mon lands in the party exactly once")
  local Trade = require("src.core.game3.scripting.natives_trade")
  local sent = { species = 63, nickname = "ABRA", level = 12, mail = nil }
  local offered = {
    species = 122, nickname = "MIMIEN", otName = "REYLEY", otId = 1985, level = 12,
  }
  session.party = { sent, { species = 25, nickname = "PIKA", level = 9 } }
  Trade._offered = offered
  local swaps = 0
  local realTradeMons = Trade.tradeMons
  Trade.tradeMons = function(...)
    swaps = swaps + 1
    return realTradeMons(...)
  end
  local task = Trade.sceneTask(nil, nil, 0, 0)
  local guard = 0
  while guard < 20000 do
    guard = guard + 1
    if task() then break end
  end
  Trade.tradeMons = realTradeMons
  check(guard < 20000, "the scene task finished, frames=" .. guard)
  eq(swaps, 1, "TradeMons ran exactly once")
  eq(session.party[1], offered, "the received mon took the sent mon's slot")
  eq(#session.party, 2, "the party did not grow")
  eq(session.party[2].nickname, "PIKA", "the rest of the party is untouched")
  eq(session.dex.owned[122], true, "the received species is registered as owned")

  print("[test] 5. a second run of the same task does not swap again")
  swaps = 0
  Trade.tradeMons = function(...)
    swaps = swaps + 1
    return realTradeMons(...)
  end
  local done = task()
  Trade.tradeMons = realTradeMons
  check(done, "the finished task stays finished")
  eq(swaps, 0, "no second swap")
  eq(session.party[1], offered, "the party still holds the received mon once")
end

print("[test] 6. the map music is cached at the start and put back at the end")
-- pokefirered/src/trade_scene.c:1348
local MAP_SONG = 314
local realAudio = package.loaded["src.core.game3.audio"]
local realLove = _G.love
local songs = {}
package.loaded["src.core.game3.audio"] = {
  _mapSong = MAP_SONG,
  _currentSong = { id = MAP_SONG },
  playSe = function() end,
  playFanfare = function() end,
  playCry = function() end,
  isCryFinished = function() return true end,
  playSong = function(id) songs[#songs + 1] = tonumber(id) end,
  playMapSong = function(id) songs[#songs + 1] = tonumber(id) end,
}
_G.love = { graphics = {} }
local function runWithMusic(opts)
  songs = {}
  TradeScene.play(OFFER, RECEIVED, nil, opts)
  TradeScene.step()
  local cached = TradeScene.state() and TradeScene.state().cachedMapMusic
  local guard = 0
  while guard < 20000 do
    guard = guard + 1
    if TradeScene.phase() == "end_link_trade" then TradeScene.pressA() end
    if TradeScene.step() then break end
  end
  return cached
end
local cachedInGame = runWithMusic({})
local inGameSongs = songs
local cachedLink = runWithMusic({ peer = { name = "TRIS", id = 31337 }, uiDriven = true })
local linkSongs = songs
_G.love = realLove
package.loaded["src.core.game3.audio"] = realAudio
eq(cachedInGame, MAP_SONG, "the in-game arm caches the map music at STATE_START")
eq(inGameSongs[1], 264, "STATE_START plays MUS_EVOLUTION")
-- pokefirered/src/trade_scene.c:1790
eq(inGameSongs[#inGameSongs], MAP_SONG, "the in-game arm ends on the cached map music")
eq(cachedLink, MAP_SONG, "the link arm caches the map music too")
-- pokefirered/src/trade_scene.c:2290
eq(linkSongs[#linkSongs], MAP_SONG, "the link arm ends on the cached map music")
check(not TradeScene.isOpen(), "both runs closed the scene")

if not require("tests.game3_cache").mount() then
  print("[skip] 7: the in-game trades are ROM data: " .. tostring(require("tests.game3_cache").reason))
else
  print("[test] 7. a trade with no mon to swap still fades the field back in")
  local Trade = require("src.core.game3.scripting.natives_trade")
  local realFade = package.loaded["src.ui.game3.fade"]
  local fades = {}
  package.loaded["src.ui.game3.fade"] = {
    MODE = { TO_BLACK = "to_black", FROM_BLACK = "from_black" },
    begin = function(mode) fades[#fades + 1] = mode end,
  }
  session.party = {}
  Trade._offered = nil
  local bail = Trade.sceneTask(nil, nil, 0, 3)
  local bailFrames = 0
  while bailFrames < 20000 do
    bailFrames = bailFrames + 1
    if bail() then break end
  end
  package.loaded["src.ui.game3.fade"] = realFade
  check(bailFrames < 20000, "the bail-out task finished, frames=" .. bailFrames)
  eq(fades[1], "to_black", "it still fades out first")
  eq(fades[#fades], "from_black", "and the last fade brings the field back")
end

finish()

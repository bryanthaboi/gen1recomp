local SE = require("src.core.game3.se_ids")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local TradeScene = {}

-- pokefirered/include/constants/songs.h:271
local MUS_EVOLUTION = 264
-- pokefirered/include/constants/songs.h:266
local MUS_EVOLVED = 259
-- pokefirered/include/constants/species.h:421
local SPECIES_EGG = 412

-- pokefirered/src/trade_scene.c:1119
local MON_SLIDE_HOFS = 0xB4
-- pokefirered/src/trade_scene.c:1355
local MON_SLIDE_STEP = 3
-- pokefirered/src/trade_scene.c:1377
local BYE_BYE_DELAY = 80
-- pokefirered/src/trade_scene.c:1379
local BALL_DEPART_DELAY = 0x14
-- pokefirered/src/data.c:133
local MON_RETURN_FRAMES = 18 + 15
-- pokefirered/src/pokeball.c:145
local BALL_CLOSE_FRAMES = 5 + 5
-- pokefirered/src/pokeball.c:1188
local BALL_TRADE_SE_AT = 11
-- pokefirered/src/trade_scene.c:2384
local BALL_DEPART_FRAMES = 44
-- pokefirered/src/trade_scene.c:2382
local BALL_DEPART_BOUNCE_AT = 22
-- pokefirered/src/trade_scene.c:2397
local BALL_DEPART_END_HOLD = 20
-- pokefirered/src/trade_scene.c:2400
local BALL_DEPART_END_FRAMES = 23
-- pokefirered/src/trade_scene.c:1398
local FADE_FRAMES = 16
-- pokefirered/src/trade_scene.c:1172
local ZOOM_MAX = 0x400
-- pokefirered/src/trade_scene.c:1419
local ZOOM_MIN = 0x100
-- pokefirered/src/trade_scene.c:1421
local ZOOM_STEP = 0x34
-- pokefirered/src/trade_scene.c:1194
local ZOOM_FAR = 0x80
-- pokefirered/src/trade_scene.c:1433
local GBA_FLASH_DELAY = 20
-- pokefirered/src/trade_scene.c:398
local FLASH_ANIM_FRAMES = 7 * 2 * 9
-- pokefirered/src/trade_scene.c:1128
local BG1_GBA_TOP = 0x15C
-- pokefirered/src/trade_scene.c:1452
local BG1_PAN_END = 316
-- pokefirered/src/trade_scene.c:1455
local CABLE_END_VOFS = 328
-- pokefirered/src/trade_scene.c:1465
local LINK_MON_TRAVEL_END = 166
-- pokefirered/src/trade_scene.c:1459
local LINK_MON_Y = 80
-- pokefirered/src/trade_scene.c:1475
local LINK_MON_OFFSCREEN = -8
-- pokefirered/src/trade_scene.c:1503
local CROSS_STEP = 3
-- pokefirered/src/trade_scene.c:1509
local CROSS_ENTER_LIMIT = -90
-- pokefirered/src/trade_scene.c:1570
local CROSS_EXIT_LIMIT = -222
-- pokefirered/src/trade_scene.c:1557
local CROSS_MON_LIMIT = -222
-- pokefirered/src/trade_scene.c:1493
local CROSS_MON_A_Y = 170
-- pokefirered/src/trade_scene.c:1494
local CROSS_MON_B_Y = -10
-- pokefirered/src/trade_scene.c:1584
local LINK_MON_ARRIVE_Y = -20
-- pokefirered/src/trade_scene.c:1604
local LINK_MON_ARRIVE_TARGET = 64
-- pokefirered/src/trade_scene.c:1625
local BG1_CENTER = 348
-- pokefirered/src/trade_scene.c:1621
local ARRIVED_DELAY = 10
-- pokefirered/src/trade_scene.c:1691
local BALL_ARRIVE_Y = -8
-- pokefirered/src/trade_scene.c:1692
local BALL_ARRIVE_TARGET = 74
-- pokefirered/src/trade_scene.c:2412
local BALL_ARRIVE_STEP = 4
-- pokefirered/src/trade_scene.c:2416
local BALL_ARRIVE_IDX = 22
-- pokefirered/src/trade_scene.c:2429
local BALL_ARRIVE_END = 108
-- pokefirered/src/trade_scene.c:1737
local MON_ANIM_DELAY = 60
-- pokefirered/src/trade_scene.c:1750
local FANFARE_AT = 10
-- pokefirered/src/trade_scene.c:1753
local TAKE_CARE_AT = 250
-- pokefirered/src/trade_scene.c:1762
local AFTER_MON_DELAY = 60
-- pokefirered/src/trade_scene.c:1552
local DISPLAY_HEIGHT = 160
-- pokefirered/src/trade_scene.c:2650
local LINK_SAVE_HOLD = 50
-- pokefirered/src/trade_scene.c:2653
local LINK_HOST_JITTER = 30
-- pokefirered/src/trade_scene.c:2699
local LINK_CLOSE_HOLD = 60

local HOLD_FRAMES = 60

TradeScene.FADE_FRAMES = FADE_FRAMES
TradeScene.HOLD_FRAMES = HOLD_FRAMES

-- pokefirered/src/trade_scene.c:538 sTradeBallVerticalVelocityTable
local BALL_VELOCITY = {
  [0] = 0, 0, 1, 0,
  1, 0, 1, 1,
  1, 1, 2, 2,
  2, 2, 3, 3,
  3, 3, 4, 4,
  4, 4, -4, -4,
  -4, -3, -3, -3,
  -3, -2, -2, -2,
  -2, -1, -1, -1,
  -1, 0, -1, 0,
  -1, 0, 0, 0,
  0, 0, 1, 0,
  1, 0, 1, 1,
  1, 1, 2, 2,
  2, 2, 3, 3,
  3, 3, 4, 4,
  4, 4, -4, -3,
  -3, -2, -2, -1,
  -1, -1, 0, -1,
  0, 0, 0, 0,
  0, 0, 1, 0,
  1, 1, 1, 2,
  2, 3, 3, 4,
  -4, -3, -2, -1,
  -1, -1, 0, 0,
  0, 0, 1, 0,
  1, 1, 2, 3,
}
TradeScene.BALL_VELOCITY = BALL_VELOCITY

local function velocity(idx)
  return BALL_VELOCITY[idx] or 0
end

local function audioMod()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and type(Audio) == "table" then return Audio end
  return nil
end

local function playSe(s, id)
  if s.headless or not id then return end
  local Audio = audioMod()
  if Audio and Audio.playSe then pcall(Audio.playSe, id) end
end

-- pokefirered/src/sound.c:124 GetCurrentMapMusic
local function currentMapMusic()
  local Audio = audioMod()
  if not Audio then return nil end
  if Audio._mapSong then return Audio._mapSong end
  local cur = Audio._currentSong
  return cur and cur.id or nil
end

-- pokefirered/src/sound.c:129 PlayNewMapMusic
local function playNewMapMusic(s, id)
  if s.headless or not id then return end
  local Audio = audioMod()
  if Audio and Audio.playMapSong then
    pcall(Audio.playMapSong, id, { restart = true, loop = true })
  end
end

local function playFanfare(s, id)
  if s.headless then return end
  local Audio = audioMod()
  if Audio and Audio.playFanfare then pcall(Audio.playFanfare, id) end
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function isEgg(mon)
  if not mon then return false end
  if mon.isEgg or mon.egg then return true end
  return speciesOf(mon) == SPECIES_EGG
end

-- pokefirered/src/trade_scene.c:1371
local function playCry(s, mon)
  if s.headless or isEgg(mon) then return end
  local Audio = audioMod()
  if Audio and Audio.playCry then
    s.cryPlaying = true
    pcall(Audio.playCry, speciesOf(mon))
  end
end

-- pokefirered/src/trade_scene.c:1746
local function cryFinished(s)
  if s.headless or not s.cryPlaying then return true end
  local Audio = audioMod()
  if not (Audio and Audio.isCryFinished) then return true end
  local ok, done = pcall(Audio.isCryFinished)
  if not ok then return true end
  return done and true or false
end

-- pokefirered/src/trade_scene.c:1239 GetMonData(MON_DATA_NICKNAME), which is
-- gText_EggNickname for an egg (pokemon.c:3020)
local function nameOf(mon)
  if not mon then return "" end
  if isEgg(mon) then return Strings("EGG") end
  local nick = mon.nickname or mon.name
  if type(nick) == "string" and nick ~= "" then return nick end
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if ok and Pokemon and Pokemon.name then
    local n = Pokemon.name(speciesOf(mon))
    if type(n) == "string" then return n end
  end
  return ""
end

local function otNameOf(mon)
  if not mon then return "" end
  local ot = mon.otName or mon.ot
  if type(ot) == "string" and ot ~= "" then return ot end
  return ""
end

-- pokefirered/src/trade_scene.c:2808 DrawTextOnTradeWindow
local function setText(s, text)
  s.text = text or ""
end

local function evolutionOpen()
  local Scene = package.loaded["src.ui.game3.evolution_scene"]
  return (Scene and Scene.isOpen and Scene.isOpen()) or false
end

local function fade(s, toBlack)
  if s.headless then return end
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  if not (ok and Fade and Fade.begin and Fade.MODE) then return end
  pcall(Fade.begin, toBlack and Fade.MODE.TO_BLACK or Fade.MODE.FROM_BLACK, 1, function() end)
end

local PHASES = {}
local INDEX = {}

local function phase(name, step, only)
  PHASES[#PHASES + 1] = { name = name, step = step, only = only }
  INDEX[name] = #PHASES
end

-- pokefirered/src/trade_scene.c:1054 TradeMons
local function doSwap(s)
  if s.swapped then return end
  s.swapped = true
  if s.onSwap then s.onSwap(s.offer, s.received) end
end

-- pokefirered/src/trade.c:1297 CB_FadeToStartTrade
phase("fade_to_black", function(s)
  fade(s, true)
  return true
end, "fadein")

-- pokefirered/src/trade.c:1301 CB_WaitToStartTrade
phase("wait_fade_to_black", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  return true
end, "fadein")

-- pokefirered/src/trade_scene.c:1343
phase("start", function(s)
  s.playerVisible = true
  s.monX2 = -180
  s.veil = 0
  fade(s, false)
  -- pokefirered/src/trade_scene.c:1348
  s.cachedMapMusic = currentMapMusic()
  -- pokefirered/src/trade_scene.c:1349
  playNewMapMusic(s, MUS_EVOLUTION)
  return true
end)

-- pokefirered/src/trade_scene.c:1351
phase("mon_slide_in", function(s)
  if s.bg2hofs > 0 then
    s.monX2 = s.monX2 + MON_SLIDE_STEP
    s.bg2hofs = s.bg2hofs - MON_SLIDE_STEP
    return false
  end
  s.monX2 = 0
  s.bg2hofs = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1366
phase("send_msg", function(s)
  setText(s, Strings("%s will be\nsent to %s.", s.sentName, s.otName))
  playCry(s, s.offer)
  return true
end)

-- pokefirered/src/trade_scene.c:1376
phase("bye_bye", function(s)
  s.timer = s.timer + 1
  if s.timer ~= BYE_BYE_DELAY then return false end
  setText(s, Strings("Bye-bye, %s!", s.sentName))
  s.ballVisible = true
  s.ballX, s.ballY, s.ballY2 = 120, 32, 0
  return true
end)

-- pokefirered/src/trade_scene.c:1385
phase("pokeball_depart", function(s)
  s.timer = s.timer + 1
  if s.timer <= BALL_DEPART_DELAY then return false end
  local t = s.timer - BALL_DEPART_DELAY - 1
  if t == BALL_TRADE_SE_AT then playSe(s, SE.SE_BALL_TRADE) end
  if t <= MON_RETURN_FRAMES then
    s.monScale = 1 - (t / MON_RETURN_FRAMES)
    return false
  end
  s.monScale = 0
  s.playerVisible = false
  return t >= MON_RETURN_FRAMES + BALL_CLOSE_FRAMES
end)

-- pokefirered/src/trade_scene.c:2379
phase("pokeball_depart_wait", function(s)
  if s.ballStage ~= "end" then
    s.ballY2 = s.ballY2 + velocity(s.ballIdx)
    if s.ballIdx == BALL_DEPART_BOUNCE_AT then playSe(s, SE.SE_BALL_BOUNCE_1) end
    s.ballIdx = s.ballIdx + 1
    if s.ballIdx == BALL_DEPART_FRAMES then
      playSe(s, SE.SE_M_MEGA_KICK)
      s.ballStage = "end"
      s.ballIdx = 0
      s.ballHold = 0
      s.ballWhite = 1
    end
    return false
  end
  -- pokefirered/src/trade_scene.c:2397
  s.ballHold = s.ballHold + 1
  if s.ballHold <= BALL_DEPART_END_HOLD then return false end
  s.ballY2 = s.ballY2 - velocity(s.ballIdx)
  s.ballIdx = s.ballIdx + 1
  if s.ballIdx ~= BALL_DEPART_END_FRAMES then return false end
  s.ballVisible = false
  return true
end)

-- pokefirered/src/trade_scene.c:1397
phase("fade_out_to_gba_send", function(s)
  fade(s, true)
  s.veil = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1401
phase("wait_fade_out_to_gba_send", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  setText(s, "")
  -- pokefirered/src/trade_scene.c:1166
  s.bg2Zoom = ZOOM_MAX
  return true
end)

TradeScene.ART_FIRST = "fade_in_to_gba_send"

-- pokefirered/src/trade_scene.c:1410
phase("fade_in_to_gba_send", function(s)
  s.gbaVisible = true
  fade(s, false)
  return true
end)

-- pokefirered/src/trade_scene.c:1414
phase("wait_fade_in_to_gba_send", function(s)
  s.veil = 1 - (s.frames / FADE_FRAMES)
  if s.frames < FADE_FRAMES then return false end
  s.veil = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1418
phase("gba_zoom_out", function(s)
  if s.bg2Zoom > ZOOM_MIN then
    s.bg2Zoom = s.bg2Zoom - ZOOM_STEP
    return false
  end
  -- pokefirered/src/trade_scene.c:1126
  s.bg1vofs = BG1_GBA_TOP
  s.bg2Zoom = ZOOM_FAR
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1432
phase("gba_flash_send", function(s)
  s.timer = s.timer + 1
  if s.timer <= GBA_FLASH_DELAY then return false end
  s.flash = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1440
phase("gba_stop_flash_send", function(s)
  s.flash = s.frames
  if s.frames < FLASH_ANIM_FRAMES then return false end
  s.flash = nil
  return true
end)

-- pokefirered/src/trade_scene.c:1451
phase("pan_away_gba", function(s)
  s.bg1vofs = s.bg1vofs - 1
  if s.bg1vofs == CABLE_END_VOFS then s.cableEnd = true end
  return s.bg1vofs == BG1_PAN_END
end)

-- pokefirered/src/trade_scene.c:1458
phase("create_link_mon_leaving", function(s)
  s.linkVisible = true
  s.linkY = LINK_MON_Y
  s.linkY2 = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1464
phase("link_mon_travel_out", function(s)
  s.bg1vofs = s.bg1vofs - 2
  return s.bg1vofs == LINK_MON_TRAVEL_END
end)

-- pokefirered/src/trade_scene.c:1472
phase("link_mon_travel_offscreen", function(s)
  s.linkY = s.linkY - 2
  return s.linkY < LINK_MON_OFFSCREEN
end)

-- pokefirered/src/trade_scene.c:1478
phase("fade_out_to_crossing", function(s)
  fade(s, true)
  return true
end)

-- pokefirered/src/trade_scene.c:1482
phase("wait_fade_out_to_crossing", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  s.linkVisible = false
  s.gbaVisible = false
  s.cableEnd = false
  s.bg1vofs = 0
  s.cableCloseup = true
  return true
end)

-- pokefirered/src/trade_scene.c:1491
phase("fade_in_to_crossing", function(s)
  fade(s, false)
  s.crossVisible = true
  s.crossY2a, s.crossY2b = 0, 0
  return true
end)

-- pokefirered/src/trade_scene.c:1497
phase("wait_fade_in_to_crossing", function(s)
  s.crossY2a = s.crossY2a - CROSS_STEP
  s.crossY2b = s.crossY2b + CROSS_STEP
  s.veil = 1 - (s.frames / FADE_FRAMES)
  if s.frames < FADE_FRAMES then return false end
  s.veil = 0
  playSe(s, SE.SE_WARP_OUT)
  return true
end)

-- pokefirered/src/trade_scene.c:1506
phase("crossing_link_mons_enter", function(s)
  s.crossY2a = s.crossY2a - CROSS_STEP
  s.crossY2b = s.crossY2b + CROSS_STEP
  return s.crossY2a <= CROSS_ENTER_LIMIT
end)

-- pokefirered/src/trade_scene.c:1516
phase("crossing_blend_white_1", function(s)
  s.whiteBlend = 1
  return true
end)

-- pokefirered/src/trade_scene.c:1520
phase("crossing_blend_white_2", function(s)
  s.whiteBlend = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1524
phase("crossing_blend_white_3", function(s)
  s.whiteBlend = 1
  return true
end)

-- pokefirered/src/trade_scene.c:1528
phase("crossing_create_mon_pics", function(s)
  s.crossMonVisible = true
  s.monY2a, s.monY2b = 0, 0
  return true
end)

-- pokefirered/src/trade_scene.c:1549
phase("crossing_mon_pics_move", function(s)
  s.monY2a = s.monY2a - CROSS_STEP
  s.monY2b = s.monY2b + CROSS_STEP
  if s.monY2a < -DISPLAY_HEIGHT and s.monY2a >= -DISPLAY_HEIGHT - CROSS_STEP then
    playSe(s, SE.SE_WARP_IN)
  end
  if s.monY2a >= CROSS_MON_LIMIT then return false end
  s.crossMonVisible = false
  s.whiteBlend = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1567
phase("crossing_link_mons_exit", function(s)
  s.crossY2a = s.crossY2a - CROSS_STEP
  s.crossY2b = s.crossY2b + CROSS_STEP
  if s.crossY2a > CROSS_EXIT_LIMIT then return false end
  fade(s, true)
  s.crossVisible = false
  return true
end)

-- pokefirered/src/trade_scene.c:1578
phase("create_link_mon_arriving", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  s.cableCloseup = false
  s.gbaVisible = true
  s.bg1vofs = LINK_MON_TRAVEL_END
  s.linkVisible = true
  s.linkY = LINK_MON_ARRIVE_Y
  s.linkY2 = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1589
phase("fade_out_to_gba_recv", function(s)
  fade(s, false)
  return true
end)

-- pokefirered/src/trade_scene.c:1593
phase("wait_fade_out_to_gba_recv", function(s)
  s.veil = 1 - (s.frames / FADE_FRAMES)
  if s.frames < FADE_FRAMES then return false end
  s.veil = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1601
phase("link_mon_travel_in", function(s)
  s.linkY2 = s.linkY2 + CROSS_STEP
  return s.linkY2 + s.linkY == LINK_MON_ARRIVE_TARGET
end)

-- pokefirered/src/trade_scene.c:1607
phase("pan_to_gba", function(s)
  s.bg1vofs = s.bg1vofs + 2
  if s.bg1vofs <= BG1_PAN_END then return false end
  s.bg1vofs = BG1_PAN_END
  return true
end)

-- pokefirered/src/trade_scene.c:1614
phase("destroy_link_mon", function(s)
  s.linkVisible = false
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1620
phase("link_mon_arrived_delay", function(s)
  s.timer = s.timer + 1
  return s.timer == ARRIVED_DELAY
end)

-- pokefirered/src/trade_scene.c:1624
phase("move_gba_to_center", function(s)
  s.bg1vofs = s.bg1vofs + 1
  if s.bg1vofs == CABLE_END_VOFS then s.cableEnd = true end
  if s.bg1vofs <= BG1_CENTER then return false end
  s.bg1vofs = BG1_CENTER
  return true
end)

-- pokefirered/src/trade_scene.c:1636
phase("gba_flash_recv", function(s)
  s.flash = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1640
phase("gba_stop_flash_recv", function(s)
  s.flash = s.frames
  if s.frames < FLASH_ANIM_FRAMES then return false end
  s.flash = nil
  -- pokefirered/src/trade_scene.c:1188
  s.bg2Zoom = ZOOM_FAR
  playSe(s, SE.SE_M_SAND_ATTACK)
  return true
end)

-- pokefirered/src/trade_scene.c:1649
phase("gba_zoom_in", function(s)
  if s.bg2Zoom < ZOOM_MAX then
    s.bg2Zoom = s.bg2Zoom + ZOOM_STEP
    return false
  end
  s.bg2Zoom = ZOOM_MAX
  return true
end)

-- pokefirered/src/trade_scene.c:1661
phase("fade_out_to_new_mon", function(s)
  fade(s, true)
  return true
end)

-- pokefirered/src/trade_scene.c:1666
phase("wait_fade_out_to_new_mon", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  s.gbaVisible = false
  return true
end)

TradeScene.ART_LAST = "wait_fade_out_to_new_mon"

-- pokefirered/src/trade_scene.c:1675
phase("fade_in_to_new_mon", function(s)
  fade(s, false)
  return true
end)

-- pokefirered/src/trade_scene.c:1680
phase("wait_fade_in_to_new_mon", function(s)
  s.veil = 1 - (s.frames / FADE_FRAMES)
  if s.frames < FADE_FRAMES then return false end
  s.veil = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1690
phase("pokeball_arrive", function(s)
  s.ballVisible = true
  s.ballX, s.ballY, s.ballY2 = 120, BALL_ARRIVE_Y, 0
  s.ballIdx = 0
  s.ballStage = "fall"
  s.ballWhite = 1
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1700
phase("fade_pokeball_to_normal", function(s)
  s.ballWhite = 0
  return true
end)

-- pokefirered/src/trade_scene.c:2408
phase("pokeball_arrive_wait", function(s)
  if s.ballStage == "fall" then
    s.ballY = s.ballY + BALL_ARRIVE_STEP
    if s.ballY > BALL_ARRIVE_TARGET then
      s.ballStage = "bounce"
      s.ballIdx = BALL_ARRIVE_IDX
      playSe(s, SE.SE_BALL_BOUNCE_1)
    end
    return false
  end
  if s.ballIdx == 66 then playSe(s, SE.SE_BALL_BOUNCE_2) end
  if s.ballIdx == 92 then playSe(s, SE.SE_BALL_BOUNCE_3) end
  if s.ballIdx == 107 then playSe(s, SE.SE_BALL_BOUNCE_4) end
  s.ballY2 = s.ballY2 + velocity(s.ballIdx)
  s.ballIdx = s.ballIdx + 1
  return s.ballIdx == BALL_ARRIVE_END
end)

-- pokefirered/src/trade_scene.c:1714
phase("show_new_mon", function(s)
  s.ballVisible = false
  s.partnerVisible = true
  return true
end)

-- pokefirered/src/trade_scene.c:1725
phase("new_mon_msg", function(s)
  setText(s, Strings("%s sent over %s.", s.otName, s.recvName))
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1736
phase("delay_for_mon_anim", function(s)
  s.timer = s.timer + 1
  if s.timer <= MON_ANIM_DELAY then return false end
  playCry(s, s.received)
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1745
phase("wait_for_mon_cry", function(s)
  return cryFinished(s)
end)

-- pokefirered/src/trade_scene.c:1749
phase("take_care_of_mon", function(s)
  s.timer = s.timer + 1
  if s.timer == FANFARE_AT then playFanfare(s, MUS_EVOLVED) end
  if s.timer ~= TAKE_CARE_AT then return false end
  setText(s, Strings("Take good care of %s!", s.recvName))
  s.timer = 0
  return true
end)

-- pokefirered/src/trade_scene.c:1761
phase("after_new_mon_delay", function(s)
  s.timer = s.timer + 1
  return s.timer == AFTER_MON_DELAY
end)

-- pokefirered/src/trade_scene.c:1765
phase("check_ribbons", function(s)
  if s.onRibbons then s.onRibbons(s.received) end
  return true
end)

-- pokefirered/src/trade_scene.c:1769
phase("end_link_trade", function(s)
  if s.link then
    -- pokefirered/src/trade_scene.c:2533 CB2_UpdateLinkTrade
    doSwap(s)
    return true
  end
  if s.headless or not s.needsConfirm then return true end
  if not s.aPressed then return false end
  s.aPressed = false
  return true
end)

-- pokefirered/src/trade_scene.c:2344
phase("link_wait_peer", function(s)
  if not s.awaitPeer then return true end
  return s.peerConfirmed == true
end, "link")

-- pokefirered/src/trade_scene.c:1775
phase("try_evolution", function(s)
  -- pokefirered/src/trade_scene.c:1776
  doSwap(s)
  if not s.evolved then
    s.evolved = true
    -- pokefirered/src/trade_scene.c:2322 CB2_TryLinkTradeEvolution
    if s.onEvolve then s.onEvolve(s.received) end
  end
  return true
end)

phase("wait_evolution", function(s)
  return not evolutionOpen()
end)

-- pokefirered/src/trade_scene.c:2572
phase("link_standby", function(s)
  setText(s, RomText.plain("gText_CommunicationStandby4"))
  if not s.awaitSave then return true end
  return s.linkTaskDone == true
end, "link")

-- pokefirered/src/trade_scene.c:2595
phase("link_save", function(s)
  setText(s, RomText.plain("gText_SavingDontTurnOffThePower2"))
  if not s.awaitSave then return true end
  return s.saveDone == true
end, "link")

-- pokefirered/src/trade_scene.c:2649
phase("link_save_delay", function(s)
  s.timer = s.timer + 1
  if s.timer <= LINK_SAVE_HOLD then return false end
  if s.hostJitter == nil then
    -- pokefirered/src/trade_scene.c:2652
    s.hostJitter = s.linkHost and (require("src.core.game3.rng").Random() % LINK_HOST_JITTER) or 0
    return false
  end
  -- pokefirered/src/trade_scene.c:2659
  if s.hostJitter > 0 then
    s.hostJitter = s.hostJitter - 1
    return false
  end
  return true
end, "link")

-- pokefirered/src/trade_scene.c:2698
phase("link_close_delay", function(s)
  s.timer = s.timer + 1
  return s.timer > LINK_CLOSE_HOLD
end, "link")

-- pokefirered/src/trade_scene.c:1783
phase("fade_out_end", function(s)
  fade(s, true)
  return true
end)

-- pokefirered/src/trade_scene.c:1787
phase("wait_fade_out_end", function(s)
  s.veil = s.frames / FADE_FRAMES
  if s.frames < FADE_FRAMES then return false end
  s.veil = 1
  -- pokefirered/src/trade_scene.c:1790, :2290
  playNewMapMusic(s, s.cachedMapMusic)
  return true
end)

TradeScene.PHASES = PHASES

local HOLD_PHASE = { name = "hold", step = function(s)
  s.veil = 1
  return s.frames >= HOLD_FRAMES
end }

local function buildSequence(hasArt, link, fadeIn)
  local flags = { link = link and true or false, fadein = fadeIn and true or false }
  local out = {}
  local skipping = false
  for _, ph in ipairs(PHASES) do
    if ph.name == TradeScene.ART_FIRST and not hasArt then
      skipping = true
      out[#out + 1] = HOLD_PHASE
    end
    local wanted = (ph.only == nil) or (flags[ph.only] == true)
    if not skipping and wanted then out[#out + 1] = ph end
    if ph.name == TradeScene.ART_LAST and skipping then skipping = false end
  end
  return out
end

local SEQUENCES = {}

function TradeScene.sequence(hasArt, link, fadeIn)
  local key = (hasArt and 1 or 0) + (link and 2 or 0) + (fadeIn and 4 or 0)
  local seq = SEQUENCES[key]
  if not seq then
    seq = buildSequence(hasArt, link, fadeIn)
    SEQUENCES[key] = seq
  end
  return seq
end

function TradeScene.isOpen()
  return TradeScene.open == true
end

function TradeScene.state()
  return TradeScene._s
end

function TradeScene.phase()
  local s = TradeScene._s
  if not s then return nil end
  local ph = s.phases[s.phaseIndex]
  return ph and ph.name or nil
end

function TradeScene.hasArt()
  local s = TradeScene._s
  return (s and s.art) and true or false
end

-- pokefirered/src/trade_scene.c:1772
function TradeScene.pressA()
  local s = TradeScene._s
  if s and TradeScene.phase() == "end_link_trade" then s.aPressed = true end
end

function TradeScene.isLink()
  local s = TradeScene._s
  return (s and s.link) and true or false
end

function TradeScene.peer()
  local s = TradeScene._s
  return s and s.peer or nil
end

-- pokefirered/src/trade_scene.c:885 QuestLogEvent_Traded
function TradeScene.questLogData()
  local s = TradeScene._s
  return s and s.questLog or nil
end

-- pokefirered/src/trade_scene.c:2344 LINKCMD_CONFIRM_FINISH_TRADE
function TradeScene.peerConfirmed()
  local s = TradeScene._s
  if s then s.peerConfirmed = true end
end

-- pokefirered/src/trade_scene.c:2586 IsLinkTaskFinished
function TradeScene.linkTaskDone()
  local s = TradeScene._s
  if s then s.linkTaskDone = true end
end

-- pokefirered/src/trade_scene.c:2628 LinkFullSave_WriteSector
function TradeScene.saveDone()
  local s = TradeScene._s
  if s then s.saveDone = true end
end

local function uiMod()
  local ok, Ui = pcall(require, "src.ui.game3.trade_scene")
  if ok and type(Ui) == "table" then return Ui end
  return nil
end

local function finish(s)
  TradeScene.open = false
  TradeScene._s = nil
  if not s.headless then
    local Ui = uiMod()
    if Ui and Ui.close then pcall(Ui.close) end
    fade(s, false)
  end
  if s.onDone then s.onDone(s.received) end
end

-- pokefirered/src/trade_scene.c:951 CB2_InitInGameTrade
function TradeScene.play(offer, received, onDone, opts)
  opts = opts or {}
  local headless = not (type(love) == "table" and love.graphics)
  local s = {
    offer = offer,
    received = received,
    onDone = onDone,
    onSwap = opts.onSwap,
    onEvolve = opts.onEvolve,
    onRibbons = opts.onRibbons,
    peer = opts.peer,
    link = (opts.link or opts.peer) and true or false,
    linkHost = opts.linkHost and true or false,
    awaitPeer = opts.awaitPeer and true or false,
    awaitSave = opts.awaitSave and true or false,
    -- pokefirered/src/trade_scene.c:2527 CB2_UpdateLinkTrade
    uiDriven = opts.uiDriven and true or false,
    headless = headless,
    needsConfirm = not headless,
    art = opts.art,
    frames = 0,
    timer = 0,
    phaseIndex = 1,
    -- pokefirered/src/trade_scene.c:1119
    bg2hofs = MON_SLIDE_HOFS,
    bg1vofs = BG1_GBA_TOP,
    -- pokefirered/src/trade_scene.c:1172
    bg2Zoom = ZOOM_MAX,
    monX2 = -180,
    monScale = 1,
    ballIdx = 0,
    ballHold = 0,
    ballStage = "depart",
    ballWhite = 0,
    veil = 0,
    text = "",
    crossY2a = 0,
    crossY2b = 0,
    monY2a = 0,
    monY2b = 0,
    crossMonAy = CROSS_MON_A_Y,
    crossMonBy = CROSS_MON_B_Y,
    swapped = false,
  }
  -- pokefirered/src/trade_scene.c:1230 TradeBufferOTnameAndNicknames
  s.sentName = opts.sentName or nameOf(offer)
  s.recvName = opts.recvName or nameOf(received)
  s.otName = opts.otName or (opts.peer and opts.peer.name) or otNameOf(received)
  s.peerId = opts.peer and tonumber(opts.peer.id or opts.peer.trainerId or opts.peer.otId) or nil
  -- pokefirered/src/trade_scene.c:885
  s.questLog = {
    speciesSent = speciesOf(offer),
    speciesReceived = speciesOf(received),
    partnerName = s.otName,
    partnerId = s.peerId,
  }

  if not headless then
    local Ui = uiMod()
    if Ui then
      if s.art == nil and Ui.loadArt then
        local ok, art = pcall(Ui.loadArt)
        s.art = ok and art or nil
      end
      if Ui.start then pcall(Ui.start, TradeScene) end
    end
  end

  s.phases = TradeScene.sequence(s.art ~= nil, s.link, opts.fadeIn)
  TradeScene._s = s
  TradeScene.open = true
  return true
end

-- pokefirered/src/trade_scene.c:1255 DoTradeAnim
function TradeScene.step()
  local s = TradeScene._s
  if not s then return true end
  local ph = s.phases[s.phaseIndex]
  if not ph then
    finish(s)
    return true
  end
  s.frames = s.frames + 1
  if ph.step(s) then
    s.phaseIndex = s.phaseIndex + 1
    s.frames = 0
    s.timer = 0
    if not s.phases[s.phaseIndex] then
      finish(s)
      return true
    end
  end
  return false
end

function TradeScene.cancel()
  local s = TradeScene._s
  if not s then return end
  TradeScene.open = false
  TradeScene._s = nil
  if not s.headless then
    local Ui = uiMod()
    if Ui and Ui.close then pcall(Ui.close) end
  end
end

return TradeScene

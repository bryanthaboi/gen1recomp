-- pokefirered/src/hall_of_fame.c:361 CB2_DoHallOfFameScreen

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local RomText = require("src.core.game3.rom_text")
local HofGfx = require("src.ui.game3.hall_of_fame_gfx")
local Rng = require("src.core.game3.rng")
local Trig = require("src.core.game3.trig")

local HallOfFame = {}

HallOfFame.open = false
HallOfFame._session = nil
HallOfFame._onDone = nil
HallOfFame._mons = {}
HallOfFame._currentIndex = 1
HallOfFame._phase = "idle"
HallOfFame._timer = 0

local FLAG_SYS_GAME_CLEAR = 0x82C -- 2092

-- pokefirered/src/hall_of_fame.c:30
local BG_PAL = { 22 / 31, 24 / 31, 29 / 31 }
-- pokefirered/src/hall_of_fame.c:152
local FULL_TEAM = {
  { 120, 210, 120, 40 }, { 326, 220, 56, 40 }, { -86, 220, 184, 40 },
  { 120, -62, 120, 88 }, { -70, -92, 200, 88 }, { 310, -92, 40, 88 },
}
-- pokefirered/src/hall_of_fame.c:162
local HALF_TEAM = { { 120, 234, 120, 64 }, { 326, 244, 56, 64 }, { -86, 244, 184, 64 } }
-- pokefirered/include/constants/songs.h:294
local MUS_HALL_OF_FAME = 286
-- pokefirered/include/constants/songs.h:52
local SE_SAVE = 48
-- pokefirered/include/constants/songs.h:102
local SE_APPLAUSE = 98
-- pokefirered/include/constants/trainers.h:156
local TRAINER_PIC_RED, TRAINER_PIC_LEAF = 135, 136
-- pokefirered/include/constants/species.h:33
local SPECIES_NIDORAN_F, SPECIES_NIDORAN_M = 29, 32
-- pokefirered/src/hall_of_fame.c:126
local PLAYER_WIN = { left = 2, top = 2, width = 17, height = 6 }
local WHITE_TEXT = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
local GRAY_TEXT = { fg = FrlgFont.STDPAL[2], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] }

-- pokefirered/src/hall_of_fame.c:382 Task_Hof_InitMonData
local function extract_eligible_mons(party)
  local eligible = {}
  if type(party) ~= "table" then return eligible end
  for i = 1, math.min(6, #party) do
    local mon = party[i]
    if mon and (tonumber(mon.species) or 0) ~= 0 then
      table.insert(eligible, mon)
    end
  end
  return eligible
end

local function commit_clear_and_save(session, eligibleMons)
  if not session then return end

  -- 1. Set clear flag
  session.flags = session.flags or {}
  session.flags[FLAG_SYS_GAME_CLEAR] = true
  session.game_cleared = true
  session.hasHallOfFameRecords = true

  -- 2. Timestamp debut
  local h = tonumber(session.playTimeHours or session.hours) or 0
  local m = tonumber(session.playTimeMinutes or session.minutes) or 0
  local s = tonumber(session.playTimeSeconds or session.seconds) or 0
  session.hofDebutHours = h
  session.hofDebutMinutes = m
  session.hofDebutSeconds = s
  session.hofDebutTime = string.format("%d:%02d:%02d", h, m, s)

  -- 3. Record Hall of Fame team
  session.hallOfFameTeams = session.hallOfFameTeams or {}
  local teamRecord = {}
  -- pokefirered/src/hall_of_fame.c:389
  for i = 1, math.min(6, #eligibleMons) do
    local mon = eligibleMons[i]
    local egg = Pokemon.isEgg(mon)
    local sp = egg and 412 or (mon.species or 1)
    local lvl = tonumber(mon.level) or 1
    local nick = egg and RomText.plain("gText_EggNickname") or (mon.nickname or mon.name or Pokemon.name(sp) or "POKéMON")
    local tid = tonumber(mon.otId or mon.tid or session.trainerId or 0)
    table.insert(teamRecord, {
      species = sp,
      level = lvl,
      nickname = nick,
      trainerId = tid,
      otSecretId = tonumber(mon.otSecretId) or 0,
      personality = tonumber(mon.personality) or 0,
    })
  end
  table.insert(session.hallOfFameTeams, teamRecord)
  -- pokefirered/src/hall_of_fame.c:443
  while #session.hallOfFameTeams > 50 do
    table.remove(session.hallOfFameTeams, 1)
  end
  -- pokefirered/src/save.c:665
  session.gameStats = session.gameStats or {}
  local entered = tonumber(session.gameStats[10]) or 0
  if entered < 999 then session.gameStats[10] = entered + 1 end

  -- 4. Commit to disk through the engine's save path.  This used to pcall
  -- "src.core.game3.save", which does not exist -- so the clear flag, the debut
  -- timestamp and the team above were set in memory and never written.
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  if game and type(game.saveGame) == "function" then
    local ok, err = pcall(game.saveGame, game)
    if not ok then
      pcall(function()
        require("src.core.Logger").warn("[hall_of_fame] save failed: %s", tostring(err))
      end)
    end
  end
end

-- Test seam: the induction commit (pret hall_of_fame.c) sets the clear flag, the
-- debut timestamp and the HOF team, then commits the save.
HallOfFame._commitClearAndSave = commit_clear_and_save

local function audio()
  return require("src.core.game3.audio")
end

local function player_female(session)
  local g = session and (session.gender or session.playerGender)
  return g == 1 or g == "female" or g == "F"
end

local function national_enabled(session)
  local ok, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  return ok and PokedexData.isNationalUnlocked
    and PokedexData.isNationalUnlocked(session, session and session.dex) or false
end

-- pokefirered/src/palette.c:151
local function begin_fade(y, target, delay, color)
  HallOfFame._fade = {
    y = y, target = target, delay = delay or 0, counter = delay or 0,
    color = color or { 0, 0, 0 }, active = y ~= target,
  }
end

local function fade_active()
  return HallOfFame._fade and HallOfFame._fade.active
end

local function tick_fade()
  local f = HallOfFame._fade
  if not (f and f.active) then return end
  if f.counter > 0 then
    f.counter = f.counter - 1
    return
  end
  f.counter = f.delay
  if f.y < f.target then
    f.y = math.min(f.target, f.y + 2)
  else
    f.y = math.max(f.target, f.y - 2)
  end
  if f.y == f.target then f.active = false end
end

local blendShader

local function shader()
  if blendShader == nil then
    local ok, s = pcall(love.graphics.newShader, [[
      extern vec3 target;
      extern number coeff;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(mix(p.rgb, target, coeff), p.a) * color;
      }
    ]])
    blendShader = ok and s or false
  end
  return blendShader or nil
end

function HallOfFame.start(opts)
  opts = opts or {}
  local session = opts.session or {}
  HallOfFame._session = session
  HallOfFame._onDone = opts.onDone
  HallOfFame._dontSave = opts.dontSave == true
  HallOfFame._warp = opts.warp ~= false
  HallOfFame.open = true
  HallOfFame._mons = extract_eligible_mons(session.party)
  HallOfFame._currentIndex = 1
  HallOfFame._sprites = {}
  HallOfFame._selected = {}
  HallOfFame._dimmed = false
  HallOfFame._info = nil
  HallOfFame._welcome = false
  HallOfFame._saving = false
  HallOfFame._band = 7
  HallOfFame._bandEva = 16
  HallOfFame._confetti = {}
  HallOfFame._player = nil
  HallOfFame._playerInfo = false
  HallOfFame._national = national_enabled(session)
  HallOfFame._timer = 0
  HallOfFame._phase = "fadein"
  -- pokefirered/src/hall_of_fame.c:344
  begin_fade(16, 0, 0)
  require("src.ui.game3.fade").clear()
  Stack.push("hall_of_fame", HallOfFame, { hideBelow = true, fullscreen = true })
end

-- pokefirered/src/hall_of_fame.c:699 SetWarpsToRollCredits
function HallOfFame.setWarpsToRollCredits()
  local Flags = require("src.core.game3.scripting.flags")
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Map = require("src.core.game3.map")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  assert(Space and Space.store, "SetWarpsToRollCredits: no script space")
  assert(game, "SetWarpsToRollCredits: no running game")
  local store = Space.store
  Flags.setVar(store, nil, Flags.VAR_IDS.VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR, 1)
  Flags.setFlag(store, nil, Flags.IDS.FLAG_DONT_SHOW_MAP_NAME_POPUP, true)
  Map.disableMusicChange = Map.MUSIC_DISABLE_KEEP
  -- pokefirered/src/hall_of_fame.c:704
  Map.load(nil, game, "FR_INDIGO_PLATEAU_EXTERIOR", { x = 11, y = 6, facing = "down" })
  local Player = package.loaded["src.core.game3.player"]
  if Player and Player.setVisible then Player.setVisible(true) end
  local Fade = require("src.ui.game3.fade")
  Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  return true
end

function HallOfFame.close()
  if not HallOfFame.open then return end
  HallOfFame.open = false
  HallOfFame._phase = "done"
  Stack.pop("hall_of_fame")
  if HallOfFame._warp then
    HallOfFame.setWarpsToRollCredits()
  end
  local cb = HallOfFame._onDone
  HallOfFame._onDone = nil
  if cb then cb() end
end

function HallOfFame.reset()
  HallOfFame.open = false
  HallOfFame._phase = "idle"
  HallOfFame._onDone = nil
  HallOfFame._session = nil
  HallOfFame._fade = nil
end

function HallOfFame.isOpen()
  return HallOfFame.open
end

function HallOfFame.phase()
  return HallOfFame._phase
end

function HallOfFame.getCurrentMon()
  if not HallOfFame.open then return nil end
  return HallOfFame._mons[HallOfFame._currentIndex]
end

local function positions()
  return #HallOfFame._mons > 3 and FULL_TEAM or HALF_TEAM
end

-- pokefirered/src/hall_of_fame.c:1223 SpriteCB_GetOnScreen
local function slide(s)
  if s.x == s.dx and s.y == s.dy then return true end
  if s.x < s.dx then s.x = s.x + 15 end
  if s.x > s.dx then s.x = s.x - 15 end
  if s.y < s.dy then s.y = s.y + 10 end
  if s.y > s.dy then s.y = s.y - 10 end
  return false
end

-- pokefirered/src/hall_of_fame.c:1267 Hof_SpawnConfetti
local function spawn_confetti()
  local x = Rng.Random() % 240
  local y = -(Rng.Random() % 8)
  local frame = Rng.Random() % 17
  local fall = (Rng.Random() % 4 ~= 0) and 0 or 1
  local list = HallOfFame._confetti
  list[#list + 1] = { x = x, y = y, frame = frame, fall = fall, x2 = 0, y2 = 0, angle = 0 }
end

-- pokefirered/src/hall_of_fame.c:1245 SpriteCB_Confetti
local function update_confetti()
  local keep = {}
  for _, c in ipairs(HallOfFame._confetti or {}) do
    if c.y2 <= 120 then
      c.y2 = c.y2 + 1 + c.fall
      local amp = Rng.Random() % 4 + 8
      local v = amp * Trig.SINE[c.angle % 256 + 1]
      c.x2 = v >= 0 and math.floor(v / 256) or -math.floor(-v / 256)
      c.angle = c.angle + 4
      keep[#keep + 1] = c
    end
  end
  HallOfFame._confetti = keep
end

local function run_phase()
  local phase = HallOfFame._phase
  if phase == "fadein" then
    if fade_active() then return end
    -- pokefirered/src/hall_of_fame.c:353
    audio().playSong(MUS_HALL_OF_FAME)
    HallOfFame._phase = HallOfFame._dontSave and "display" or "save"
  elseif phase == "save" then
    -- pokefirered/src/hall_of_fame.c:456
    HallOfFame._saving = true
    HallOfFame._phase = "trysave"
  elseif phase == "trysave" then
    -- pokefirered/src/hall_of_fame.c:462
    local session = HallOfFame._session
    commit_clear_and_save(session, type(session.party) == "table" and session.party or {})
    audio().playSe(SE_SAVE)
    HallOfFame._timer = 32
    HallOfFame._phase = "savewait"
  elseif phase == "savewait" then
    -- pokefirered/src/hall_of_fame.c:471
    if HallOfFame._timer ~= 0 then
      HallOfFame._timer = HallOfFame._timer - 1
    else
      HallOfFame._phase = "display"
    end
  elseif phase == "display" then
    -- pokefirered/src/hall_of_fame.c:484
    local i = HallOfFame._currentIndex
    local pos = positions()[i]
    local mon = HallOfFame._mons[i]
    if not (pos and mon) then
      HallOfFame._phase = "welcome"
      return
    end
    HallOfFame._sprites[i] = { x = pos[1], y = pos[2], dx = pos[3], dy = pos[4], mon = mon }
    HallOfFame._saving = false
    HallOfFame._info = nil
    HallOfFame._phase = "slide"
  elseif phase == "slide" then
    local s = HallOfFame._sprites[HallOfFame._currentIndex]
    slide(s)
    -- pokefirered/src/hall_of_fame.c:521
    if s.x == s.dx and s.y == s.dy then
      local sp = tonumber(s.mon.species) or 0
      if not Pokemon.isEgg(s.mon) then
        pcall(function() audio().playCry(sp) end)
      end
      HallOfFame._info = s.mon
      HallOfFame._timer = 120
      HallOfFame._phase = "hold"
    end
  elseif phase == "hold" then
    -- pokefirered/src/hall_of_fame.c:535
    if HallOfFame._timer ~= 0 then
      HallOfFame._timer = HallOfFame._timer - 1
      return
    end
    local i = HallOfFame._currentIndex
    HallOfFame._selected[i] = true
    if i < 6 and HallOfFame._mons[i + 1] then
      HallOfFame._currentIndex = i + 1
      HallOfFame._dimmed = true
      HallOfFame._phase = "display"
    else
      HallOfFame._phase = "welcome"
    end
  elseif phase == "welcome" then
    -- pokefirered/src/hall_of_fame.c:561
    HallOfFame._dimmed = false
    HallOfFame._info = nil
    HallOfFame._welcome = true
    audio().playSe(SE_APPLAUSE)
    HallOfFame._timer = 400
    HallOfFame._phase = "applause"
  elseif phase == "applause" then
    -- pokefirered/src/hall_of_fame.c:578
    if HallOfFame._timer ~= 0 then
      HallOfFame._timer = HallOfFame._timer - 1
      if HallOfFame._timer % 4 == 0 and HallOfFame._timer > 110 then spawn_confetti() end
      return
    end
    HallOfFame._dimmed = true
    HallOfFame._welcome = false
    HallOfFame._timer = 7
    HallOfFame._phase = "bands"
  elseif phase == "bands" then
    -- pokefirered/src/hall_of_fame.c:602
    if HallOfFame._timer > 15 then
      HallOfFame._phase = "playerpic"
    else
      HallOfFame._timer = HallOfFame._timer + 1
      HallOfFame._band = HallOfFame._timer
      HallOfFame._bandEva = 0
    end
  elseif phase == "playerpic" then
    -- pokefirered/src/hall_of_fame.c:615
    HallOfFame._band = 16
    local pic = player_female(HallOfFame._session) and TRAINER_PIC_LEAF or TRAINER_PIC_RED
    HallOfFame._player = { x = 0x78, y = 0x48, pic = pic }
    HallOfFame._timer = 120
    HallOfFame._phase = "playerwait"
  elseif phase == "playerwait" then
    -- pokefirered/src/hall_of_fame.c:628
    if HallOfFame._timer ~= 0 then
      HallOfFame._timer = HallOfFame._timer - 1
    elseif HallOfFame._player.x ~= 192 then
      HallOfFame._player.x = HallOfFame._player.x + 1
    else
      HallOfFame._playerInfo = true
      HallOfFame._phase = "exitwait"
    end
  elseif phase == "exit" then
    -- pokefirered/src/hall_of_fame.c:665
    if not fade_active() then HallOfFame.close() end
  end
end

function HallOfFame.update(_dt)
  if not HallOfFame.open then return end
  tick_fade()
  run_phase()
  update_confetti()
end

-- pokefirered/src/hall_of_fame.c:649 Task_Hof_ExitOnKeyPressed
function HallOfFame.handleInput(inp)
  if not HallOfFame.open or not inp then return end
  if HallOfFame._phase ~= "exitwait" then return end
  if inp:wasPressed("a") then
    audio().fadeOutBgm(4)
    -- pokefirered/src/hall_of_fame.c:661
    begin_fade(0, 16, 8)
    HallOfFame._phase = "exit"
  end
end

-- pokefirered/src/hall_of_fame.c:1181 DrawHofBackground
local function draw_background()
  HofGfx.drawStripes()
  HofGfx.drawBands(HallOfFame._bandEva or 16, HallOfFame._band or 7)
end

local function draw_confetti()
  local sheet = HofGfx.confetti()
  if not sheet then return end
  love.graphics.setColor(1, 1, 1, 1)
  for _, c in ipairs(HallOfFame._confetti or {}) do
    love.graphics.draw(sheet.image, sheet.quads[c.frame], c.x + c.x2 - 4, c.y + c.y2 - 4)
  end
end

local function draw_mon(s, dim)
  local pic = Pokemon.monFrontPic(s.mon)
  if not (pic and pic.image) then return end
  local sh = dim and shader() or nil
  if sh then
    love.graphics.setShader(sh)
    sh:send("target", BG_PAL)
    sh:send("coeff", 12 / 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(pic.image, s.x - 32, s.y - 32)
  if sh then love.graphics.setShader() end
end

-- pokefirered/src/hall_of_fame.c:993 HallOfFame_PrintMonInfo
local function draw_mon_info(mon)
  local x0, y0 = 16, 120
  local sp = tonumber(mon.species) or 0
  local egg = Pokemon.isEgg(mon)
  if not egg then
    local dex = Pokemon.national(sp) or sp
    local digits = (not HallOfFame._national and dex > 151) and "???" or string.format("%03d", dex)
    FrlgFont.draw(RomText.plain("gText_Number") .. digits, x0 + 16, y0 + 1, { colors = WHITE_TEXT })
  end
  local nick = egg and RomText.plain("gText_EggNickname") or Pokemon.displayName(mon)
  local w = FrlgFont.measure(nick)
  local nx = egg and (0x80 - math.floor(w / 2)) or (0x80 - w)
  FrlgFont.draw(nick, x0 + nx, y0 + 1, { colors = WHITE_TEXT })
  if egg then return end
  local gender = " "
  if sp ~= SPECIES_NIDORAN_M and sp ~= SPECIES_NIDORAN_F then
    local g = Pokemon.gender(sp, tonumber(mon.personality) or 0)
    if g == "M" then gender = "♂" elseif g == "F" then gender = "♀" end
  end
  FrlgFont.draw("/" .. tostring(Pokemon.name(sp) or "") .. gender, x0 + 0x80, y0 + 1, { colors = WHITE_TEXT })
  FrlgFont.draw(RomText.plain("gText_Level") .. tostring(tonumber(mon.level) or 0), x0 + 0x20, y0 + 0x11,
    { colors = WHITE_TEXT })
  local tid = tonumber(mon.otId or mon.tid or HallOfFame._session.trainerId) or 0
  FrlgFont.draw(RomText.plain("gText_IDNumber") .. string.format("%05d", tid % 65536), x0 + 0x60, y0 + 0x11,
    { colors = WHITE_TEXT })
end

-- pokefirered/src/hall_of_fame.c:1080 HallOfFame_PrintPlayerInfo
local function draw_player_info()
  local session = HallOfFame._session or {}
  local ox, oy = PLAYER_WIN.left * 8, PLAYER_WIN.top * 8
  local textWidth = PLAYER_WIN.width * 8 - 6
  Window.fill(PLAYER_WIN, 1, 1, 1, 1)
  Window.stdFrame(PLAYER_WIN)
  local name = tostring(session.name or session.playerName or "")
  FrlgFont.draw(RomText.plain("gText_Name"), ox + 4, oy + 3, { colors = GRAY_TEXT })
  FrlgFont.draw(name, ox + textWidth - FrlgFont.measure(name), oy + 3, { colors = GRAY_TEXT })
  local tid = (tonumber(session.trainerId or session.playerTrainerId) or 0) % 65536
  FrlgFont.draw(RomText.plain("gText_IDNumber"), ox + 4, oy + 18, { colors = GRAY_TEXT })
  FrlgFont.draw(string.format("%05d", tid), ox + textWidth - 30, oy + 18, { colors = GRAY_TEXT })
  local h = tonumber(session.playTimeHours or session.hours) or 0
  local m = tonumber(session.playTimeMinutes or session.minutes) or 0
  FrlgFont.draw(RomText.plain("gText_MainMenuTime"), ox + 4, oy + 32, { colors = GRAY_TEXT })
  FrlgFont.draw(string.format("%3d:%02d", h % 1000, m % 100), ox + textWidth - 36, oy + 32,
    { colors = GRAY_TEXT })
end

function HallOfFame.draw()
  if not HallOfFame.open then return end
  draw_background()
  for i = 1, 6 do
    local s = HallOfFame._sprites[i]
    if s then
      draw_mon(s, HallOfFame._dimmed and HallOfFame._selected[i])
    end
  end
  if HallOfFame._player then
    local TrainerPic = require("src.core.game3.trainer_pic")
    local pic = TrainerPic.front(HallOfFame._player.pic)
    if pic and pic.image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(pic.image, HallOfFame._player.x - 32, HallOfFame._player.y - 32)
    end
  end
  if HallOfFame._saving then
    -- pokefirered/src/hall_of_fame.c:456
    Window.dialogueFrame()
    Window.printPx(RomText.plain("gText_SavingDontTurnOffThePower2"), 16, 121)
  end
  if HallOfFame._info then draw_mon_info(HallOfFame._info) end
  if HallOfFame._welcome then
    -- pokefirered/src/hall_of_fame.c:984
    local text = RomText.plain("gText_WelcomeToHOF")
    local x = math.floor((0xD0 - FrlgFont.measure(text)) / 2)
    FrlgFont.draw(text, 16 + x, 121, { colors = WHITE_TEXT })
  end
  if HallOfFame._playerInfo then
    draw_player_info()
    -- pokefirered/src/hall_of_fame.c:642
    Window.dialogueFrame()
    Window.printPx(RomText.plain("gText_LeagueChamp"), 16, 121)
  end
  draw_confetti()
  local f = HallOfFame._fade
  if f and f.y > 0 then
    love.graphics.setColor(f.color[1], f.color[2], f.color[3], f.y / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return HallOfFame

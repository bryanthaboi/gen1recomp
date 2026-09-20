-- FRLG Hall of Fame Induction Screen (pret hall_of_fame.c).
-- Displays team members 1..6 (strictly skipping eggs), saves clear status
-- and debut timestamp before yielding to credits.

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local Strings = require("src.core.Strings")

local HallOfFame = {}

HallOfFame.open = false
HallOfFame._session = nil
HallOfFame._onDone = nil
HallOfFame._mons = {}
HallOfFame._currentIndex = 1
HallOfFame._phase = "idle" -- "saving", "mon", "congrats", "done"
HallOfFame._timer = 0

local FLAG_SYS_GAME_CLEAR = 0x82C -- 2092

local function extract_eligible_mons(party)
  local eligible = {}
  if type(party) ~= "table" then return eligible end
  for i = 1, math.min(6, #party) do
    local mon = party[i]
    if mon and not Pokemon.isEgg(mon) then
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
  for _, mon in ipairs(eligibleMons) do
    local sp = mon.species or 1
    local lvl = tonumber(mon.level) or 1
    local nick = mon.nickname or mon.name or Pokemon.name(sp) or "POKéMON"
    local tid = tonumber(mon.otId or mon.tid or session.trainerId or 0)
    table.insert(teamRecord, {
      species = sp,
      level = lvl,
      nickname = nick,
      trainerId = tid,
    })
  end
  table.insert(session.hallOfFameTeams, teamRecord)

  -- 4. Commit atomic save to disk
  local okSave, SaveData = pcall(require, "src.core.game3.save")
  if okSave and SaveData and SaveData.save then
    pcall(SaveData.save, session)
  end
end

function HallOfFame.start(opts)
  opts = opts or {}
  local session = opts.session or {}
  HallOfFame._session = session
  HallOfFame._onDone = opts.onDone
  HallOfFame.open = true
  HallOfFame._currentIndex = 1
  HallOfFame._timer = 0

  -- Filter non-egg party members
  HallOfFame._mons = extract_eligible_mons(session.party)

  -- Audio
  local okAudio, Audio = pcall(require, "src.core.game3.audio")
  if okAudio and Audio and Audio.playBGM then
    Audio.playBGM(297) -- MUS_HALL_OF_FAME
  end

  -- Atomic save
  commit_clear_and_save(session, HallOfFame._mons)

  if #HallOfFame._mons > 0 then
    HallOfFame._phase = "mon"
  else
    HallOfFame._phase = "congrats"
  end

  Stack.push("hall_of_fame", HallOfFame, { hideBelow = true })
end

function HallOfFame.close()
  if not HallOfFame.open then return end
  HallOfFame.open = false
  HallOfFame._phase = "done"
  Stack.pop("hall_of_fame")
  local cb = HallOfFame._onDone
  HallOfFame._onDone = nil
  if cb then cb() end
end

function HallOfFame.isOpen()
  return HallOfFame.open
end

function HallOfFame.getCurrentMon()
  if not HallOfFame.open or HallOfFame._phase ~= "mon" then return nil end
  return HallOfFame._mons[HallOfFame._currentIndex]
end

function HallOfFame.advance()
  if HallOfFame._phase == "mon" then
    if HallOfFame._currentIndex < #HallOfFame._mons then
      HallOfFame._currentIndex = HallOfFame._currentIndex + 1
      HallOfFame._timer = 0
    else
      HallOfFame._phase = "congrats"
      HallOfFame._timer = 0
    end
  elseif HallOfFame._phase == "congrats" then
    HallOfFame.close()
  end
end

function HallOfFame.handleInput(inp)
  if not HallOfFame.open or not inp then return end
  if inp:wasPressed("a") or inp:wasPressed("b") or inp:wasPressed("start") then
    HallOfFame.advance()
  end
end

function HallOfFame.update(dt)
  if not HallOfFame.open then return end
  HallOfFame._timer = (HallOfFame._timer or 0) + (dt or 0)
  -- Auto-advance after 5 seconds per mon if no button pressed
  if HallOfFame._timer >= 5.0 then
    HallOfFame.advance()
  end
end

function HallOfFame.draw()
  if not HallOfFame.open then return end
  local session = HallOfFame._session or {}

  -- Background: deep dark navy / slate tone
  love.graphics.setColor(0.08, 0.09, 0.14, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)

  -- Inner card frame
  love.graphics.setColor(0.18, 0.22, 0.32, 1)
  love.graphics.rectangle("fill", 8, 8, 224, 144)
  love.graphics.setColor(0.12, 0.14, 0.22, 1)
  love.graphics.rectangle("fill", 10, 10, 220, 140)

  if HallOfFame._phase == "mon" then
    local mon = HallOfFame.getCurrentMon()
    if mon then
      -- Header
      local hdr = Strings("HALL OF FAME No. %d", HallOfFame._currentIndex)
      FrlgFont.draw(hdr, 20, 16, { colors = FrlgFont.COLOR.WHITE or FrlgFont.COLOR.NORMAL })

      -- Mon Sprite Frame
      love.graphics.setColor(0.25, 0.30, 0.42, 1)
      love.graphics.rectangle("fill", 18, 34, 68, 68)
      love.graphics.setColor(0.15, 0.18, 0.28, 1)
      love.graphics.rectangle("fill", 20, 36, 64, 64)

      local sp = mon.species or 1
      local frontImg = Pokemon.front and Pokemon.front(sp)
      if frontImg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(frontImg, 20, 36)
      end

      -- Mon Stats
      local dexNo = Pokemon.nationalDex and Pokemon.nationalDex(sp) or tonumber(sp) or 1
      local monName = mon.nickname or mon.name or Pokemon.name(sp) or "POKéMON"
      local lvl = tonumber(mon.level) or 1
      local otId = tonumber(mon.otId or mon.tid or session.trainerId or 0) % 65536
      local otName = tostring(mon.otName or mon.ot or session.name or session.playerName or "RED")

      FrlgFont.draw(Strings("No. %03d", dexNo), 96, 36, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(monName, 96, 50, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(Strings("Lv. %d", lvl), 96, 64, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(Strings("IDNo. %05d", otId), 96, 78, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(Strings("OT/ %s", otName), 96, 92, { colors = FrlgFont.COLOR.NORMAL })

      -- Moves Section (4 moves)
      love.graphics.setColor(0.18, 0.22, 0.32, 1)
      love.graphics.rectangle("fill", 18, 108, 204, 36)

      local moves = mon.moves or mon.moveIds or {}
      for slot = 1, 4 do
        local mv = moves[slot]
        local mvName = "-"
        if mv then
          if type(mv) == "table" then
            mvName = mv.name or (mv.id and Pokemon.moveName and Pokemon.moveName(mv.id)) or "-"
          elseif type(mv) == "number" or type(mv) == "string" then
            mvName = (Pokemon.moveName and Pokemon.moveName(mv)) or tostring(mv)
          end
        end
        local col = (slot - 1) % 2
        local row = math.floor((slot - 1) / 2)
        local mx = 24 + col * 100
        local my = 112 + row * 14
        FrlgFont.draw(mvName:upper(), mx, my, { colors = FrlgFont.COLOR.NORMAL })
      end
    end
  elseif HallOfFame._phase == "congrats" then
    -- League Champions Congratulations Screen
    FrlgFont.draw(Strings("LEAGUE CHAMPION!"), 54, 24, { colors = FrlgFont.COLOR.WHITE or FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(Strings("CONGRATULATIONS!"), 48, 44, { colors = FrlgFont.COLOR.NORMAL })

    local name = tostring(session.name or session.playerName or "RED")
    local rawId = tonumber(session.trainerId or session.id or session.playerTrainerId) or 0
    local idStr = string.format("%05d", rawId % 65536)

    FrlgFont.draw(Strings("NAME: %s", name), 32, 72, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(Strings("IDNo. %s", idStr), 140, 72, { colors = FrlgFont.COLOR.NORMAL })

    local h = session.hofDebutHours or tonumber(session.playTimeHours or session.hours) or 0
    local m = session.hofDebutMinutes or tonumber(session.playTimeMinutes or session.minutes) or 0
    local s = session.hofDebutSeconds or tonumber(session.playTimeSeconds or session.seconds) or 0
    FrlgFont.draw(Strings("HOF DEBUT: %d:%02d:%02d", h, m, s), 32, 94, { colors = FrlgFont.COLOR.NORMAL })

    FrlgFont.draw(Strings("PRESS A TO CONTINUE"), 52, 126, { colors = FrlgFont.COLOR.NORMAL })
  end
end

return HallOfFame

-- Gen 3 Pokémon Release Sequence (emotional upward shrink & float animation).
-- "Release this POKéMON?" -> [YES/NO] -> float/shrink animation -> "Bye-bye, <MON>!" -> data release.

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local Storage = require("src.core.game3.storage")
local Strings = require("src.core.Strings")

local ReleaseSeq = {}

ReleaseSeq.active = false
ReleaseSeq.state = "idle" -- idle | confirm | anim | bye | done
ReleaseSeq.mon = nil
ReleaseSeq.boxId = 1
ReleaseSeq.slotIdx = 1
ReleaseSeq.session = nil
ReleaseSeq.onComplete = nil
ReleaseSeq.yesNoCursor = 2 -- default to NO
ReleaseSeq.animT = 0
ReleaseSeq.startX = 0
ReleaseSeq.startY = 0

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

function ReleaseSeq.start(opts)
  opts = opts or {}
  ReleaseSeq.active = true
  ReleaseSeq.state = "confirm"
  ReleaseSeq.session = opts.session
  ReleaseSeq.mon = opts.mon
  ReleaseSeq.boxId = opts.boxId or 1
  ReleaseSeq.slotIdx = opts.slotIdx or 1
  ReleaseSeq.onComplete = opts.onComplete
  ReleaseSeq.yesNoCursor = 2 -- Default to NO
  ReleaseSeq.animT = 0
  ReleaseSeq.startX = opts.startX or 80
  ReleaseSeq.startY = opts.startY or 60
  se(5)
end

function ReleaseSeq.isActive()
  return ReleaseSeq.active
end

function ReleaseSeq.handleInput(input)
  if not ReleaseSeq.active then return end

  if ReleaseSeq.state == "confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then
      ReleaseSeq.yesNoCursor = (ReleaseSeq.yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("a") then
      se(5) -- pokefirered/src/menu.c:376
      if ReleaseSeq.yesNoCursor == 1 then
        -- Confirmed YES
        ReleaseSeq.state = "anim"
        ReleaseSeq.animT = 0
      else
        -- Chose NO
        ReleaseSeq.close(false)
      end
    elseif input:wasPressed("b") then
      ReleaseSeq.close(false)
    end
    return
  end

  if ReleaseSeq.state == "bye" then
    if input:wasPressed("a") or input:wasPressed("b") then
      ReleaseSeq.close(true)
    end
    return
  end
end

function ReleaseSeq.update(dt)
  if not ReleaseSeq.active then return end

  if ReleaseSeq.state == "anim" then
    ReleaseSeq.animT = ReleaseSeq.animT + (dt or (1 / 60))
    if ReleaseSeq.animT >= 0.8 then
      -- Finalize data deletion in storage
      if ReleaseSeq.session and ReleaseSeq.boxId and ReleaseSeq.slotIdx then
        Storage.releaseMon(ReleaseSeq.session, ReleaseSeq.boxId, ReleaseSeq.slotIdx)
      end
      ReleaseSeq.state = "bye"
      se(5)
    end
  end
end

function ReleaseSeq.close(released)
  ReleaseSeq.active = false
  ReleaseSeq.state = "idle"
  local cb = ReleaseSeq.onComplete
  ReleaseSeq.onComplete = nil
  if cb then cb(released) end
end

function ReleaseSeq.draw()
  if not ReleaseSeq.active then return end
  local monName = (ReleaseSeq.mon and Pokemon.displayName(ReleaseSeq.mon)) or "POKéMON"

  if ReleaseSeq.state == "confirm" then
    -- Bottom dialogue box
    Window.dialogueFrame()
    Window.printPx(Strings("Release %s?", monName), 16, 120)

    -- YES/NO Confirmation Box
    Window.stdFrame(Window.template(21, 8, 6, 4))
    Window.printPx(Strings("YES"), 184, 68)
    Window.printPx(Strings("NO"), 184, 84)
    Window.cursorPx(174, ReleaseSeq.yesNoCursor == 1 and 68 or 84)
    return
  end

  if ReleaseSeq.state == "anim" then
    -- Draw upward shrinking sprite
    local progress = math.min(1.0, ReleaseSeq.animT / 0.8)
    local scale = math.max(0.01, 1.0 - progress * 0.85)
    local alpha = math.max(0.0, 1.0 - progress)
    local curX = ReleaseSeq.startX
    local curY = ReleaseSeq.startY - (progress * 40) -- float upward 40px

    local icon = ReleaseSeq.mon and Pokemon.icon(Pokemon.speciesOrEgg(ReleaseSeq.mon))
    if icon and icon.image then
      local q = icon.quads and icon.quads[0]
      love.graphics.setColor(1, 1, 1, alpha)
      if q then
        love.graphics.draw(icon.image, q, curX, curY, 0, scale, scale, 16, 16)
      else
        love.graphics.draw(icon.image, curX, curY, 0, scale, scale, 16, 16)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    Window.dialogueFrame()
    Window.printPx(Strings("Releasing %s…", monName), 16, 120)
    return
  end

  if ReleaseSeq.state == "bye" then
    Window.dialogueFrame()
    Window.printPx(Strings("Bye-bye, %s!", monName), 16, 120)
    return
  end
end

return ReleaseSeq

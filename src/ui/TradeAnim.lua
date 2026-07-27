-- InternalClockTradeAnim (engine/movie/trade.asm): cable-trade cinematic
-- used by in-game NPC trades and internally-clocked link trades.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local TradeAnim = {}
TradeAnim.__index = TradeAnim
TradeAnim.isOpaque = true

function TradeAnim:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local DEFAULT_ART = {
  gameBoy = "assets/generated/trade/game_boy.png",
  openCable = "assets/generated/trade/open_cable.png",
  cableHoriz = "assets/generated/trade/cable_horiz.png",
  cableConn = "assets/generated/trade/cable_conn.png",
  cableVert = "assets/generated/trade/cable_vert.png",
  cableCorner = "assets/generated/trade/cable_corner.png",
  cableEnd = "assets/generated/trade/cable_end.png",
  cableBall = "assets/generated/trade/cable_ball.png",
  cableBallAlt = "assets/generated/trade/cable_ball_alt.png",
  bubble = "assets/generated/trade/bubble.png",
}

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

local function nameOf(game, mon)
  local def = game.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or mon.species
end

local function speciesName(game, mon)
  local def = game.data.pokemon[mon.species]
  return (def and def.name) or mon.species
end

local function dexOf(game, mon)
  local def = game.data.pokemon[mon.species]
  return def and def.dex or 0
end

local function spriteOf(game, mon)
  local path = require("src.pokemon.Sprites").path(game.data, mon.species, "front",
    { mon = mon, kind = "trade" })
  return tryImage(path)
end

local function expand(game, key, subs)
  local raw = game.data.text and game.data.text[key]
  if not raw then return key end
  for token, value in pairs(subs or {}) do
    raw = raw:gsub("{" .. token .. "}", value)
  end
  return TextBox.substitute(game, raw)
end

-- InternalClockTradeFuncSequence
local SEQ = {
  "show_player",
  "open_cable",
  "ball_enter",
  "transfer_lr",
  "delay",
  "went_to",
  "for_sends",
  "farewell",
  "transfer_rl",
  "open_cable2",
  "show_enemy",
  "done",
}

function TradeAnim.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TradeAnim)
  self.game = game
  self.sent = opts.sent
  self.received = opts.received
  self.onDone = opts.onDone
  self.enemyName = opts.enemyName or (self.received and self.received.ot) or "TRAINER"
  self.playerName = (game.save.player and game.save.player.name) or "RED"
  self.playerOt = opts.playerOt or self.playerName
  self.playerOtId = opts.playerOtId
    or (self.sent and self.sent.otId)
    or (game.save.player and game.save.player.id)
    or 0
  self.enemyOtId = opts.enemyOtId
    or (self.received and self.received.otId)
    or love.math.random(0, 65535)

  local art = (game.data.field and game.data.field.tradeArt) or DEFAULT_ART
  self.img = {
    gameBoy = tryImage(art.gameBoy or DEFAULT_ART.gameBoy),
    openCable = tryImage(art.openCable or DEFAULT_ART.openCable),
    cableHoriz = tryImage(art.cableHoriz or DEFAULT_ART.cableHoriz),
    cableConn = tryImage(art.cableConn or DEFAULT_ART.cableConn),
    cableVert = tryImage(art.cableVert or DEFAULT_ART.cableVert),
    cableCorner = tryImage(art.cableCorner or DEFAULT_ART.cableCorner),
    cableEnd = tryImage(art.cableEnd or DEFAULT_ART.cableEnd),
    cableBall = tryImage(art.cableBall or DEFAULT_ART.cableBall),
    cableBallAlt = tryImage(art.cableBallAlt or DEFAULT_ART.cableBallAlt),
    bubble = tryImage(art.bubble or DEFAULT_ART.bubble),
  }
  self.sentSprite = spriteOf(game, self.sent)
  self.recvSprite = spriteOf(game, self.received)

  self.seq = 1
  self.phase = SEQ[1]
  self.t = 0
  self.scx = 0
  self.ballX = 0
  self.ballY = 0
  self.monX = 0
  self.monY = 0
  self.flash = false
  self.monVisible = true
  self.waitingText = false
  self.cableFlash = false
  return self
end

function TradeAnim:enter()
  Sound.play(self.game.data, "Trade_Machine")
end

function TradeAnim:advance()
  self.seq = self.seq + 1
  self.phase = SEQ[self.seq] or "done"
  self.t = 0
  self.scx = 0
  self.sub = nil
  self.flash = false
  self.cableFlash = false
  self.poof = nil
  if self.phase == "done" then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  elseif self.phase == "show_enemy" then
    self.monVisible = false
  elseif self.phase == "transfer_lr" then
    -- wBaseCoord $54, $1c OAM -> screen (76, 12)
    self.monX, self.monY = 76, 12
  elseif self.phase == "transfer_rl" then
    -- wBaseCoord $64, $44 OAM -> screen (92, 52), right GB on screen
    self.monX, self.monY = 92, 52
    self.scx = 160
  elseif self.phase == "ball_enter" then
    -- lb bc, $20, $60: b = Y, c = X (Trade_AnimateBallEnteringLinkCable)
    self.ballX, self.ballY = 0x60, 0x20
  elseif self.phase == "open_cable" or self.phase == "open_cable2" then
    -- SCX $a0 -> $f0: cable slides in from the right, open end rests at x64
    self.scx = 0x50
    Sound.play(self.game.data, "Heal_HP")
  end
end

function TradeAnim:say(text, delay, thenFn)
  self.waitingText = true
  self.game.stack:push(TextBox.new(self.game, text, function()
    self.waitingText = false
    if thenFn then thenFn() else self:advance() end
  end, { auto = { delay = delay or 80 } }))
end

function TradeAnim:skipHeld()
  return self.game.input:wasPressed("a") or self.game.input:isDown("a")
end

function TradeAnim:update(dt)
  if self.waitingText or self.phase == "done" then return end
  local skip = self.game.input:wasPressed("a")
  self.t = self.t + 1
  local p = self.phase

  if p == "show_player" then
    -- slide from SCX $86 -> 0, hold 80, poof, cry (Trade_ShowPlayerMon)
    if not self.sub then self.sub = "slide" end
    if self.sub == "slide" then
      self.scx = math.max(0, 0x86 - self.t * 2)
      if skip or self.scx <= 0 then
        self.scx = 0
        self.sub = "hold"
        self.t = 0
      end
    elseif self.sub == "hold" then
      if skip or self.t >= 80 then
        self.sub = "poof"
        self.t = 0
        self.monVisible = false
        Sound.play(self.game.data, "Ball_Poof")
      end
    elseif self.sub == "poof" then
      self.poof = math.max(0, 16 - self.t)
      if skip or self.t >= 16 then
        Sound.playCry(self.game.data, self.sent.species)
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "open_cable" or p == "open_cable2" then
    -- 20 steps of 4px, matching the SCX loop
    self.scx = math.max(0, 0x50 - self.t * 4)
    if skip or self.scx <= 0 then
      self.scx = 0
      self:advance()
    end

  elseif p == "ball_enter" then
    -- TRADE_BALL_SHAKE then ball rides the cable; X from $60 toward $a0
    if self.t < 20 then
      if skip then self.t = 20 end
      return
    end
    local step = self.t - 20
    if step % 3 == 0 then
      self.ballX = 0x60 + math.floor(step / 3) * 4
      self.flash = not self.flash
      if self.ballX < 0xA0 then Sound.play(self.game.data, "Tink") end
    end
    if skip then self.ballX = 0xA0 end
    if self.ballX >= 0xA0 then self:advance() end

  elseif p == "transfer_lr" then
    -- scroll left GB off while the mon rides the cable, then the sprite
    -- itself moves right and down into the right GB (Trade_AnimMonMoveVertical)
    if self.t <= 80 then
      self.scx = math.min(160, self.t * 2)
      self.monX, self.monY = 76, 12
    elseif self.t <= 80 + 32 then
      self.monX = 76 + math.floor((self.t - 80) / 8) * 4
    elseif self.t <= 80 + 64 then
      self.monX = 92
      self.monY = 12 + math.floor((self.t - 112) / 8) * 10
    else
      self:advance()
      return
    end
    if self.t % 8 == 0 then self.cableFlash = not self.cableFlash end
    if skip then self:advance() end

  elseif p == "transfer_rl" then
    -- mirror: sprite climbs out of the right GB, then the screen scrolls
    -- back to the left GB
    if self.t <= 32 then
      self.scx = 160
      self.monX, self.monY = 92, 52 - math.floor(self.t / 8) * 10
    elseif self.t <= 64 then
      self.monX = 92 - math.floor((self.t - 32) / 8) * 4
      self.monY = 12
    elseif self.t <= 64 + 80 then
      self.scx = math.max(0, 160 - (self.t - 64) * 2)
      self.monX, self.monY = 76, 12
    else
      self:advance()
      return
    end
    if self.t % 8 == 0 then self.cableFlash = not self.cableFlash end
    if skip then self:advance() end

  elseif p == "delay" then
    if skip or self.t >= 100 then self:advance() end

  elseif p == "went_to" then
    local text = expand(self.game, "_TradeWentToText", {
      ["RAM:wStringBuffer"] = speciesName(self.game, self.sent),
      ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
    })
    self:say(text, 200)

  elseif p == "for_sends" then
    local a = expand(self.game, "_TradeForText", {
      ["RAM:wStringBuffer"] = speciesName(self.game, self.sent),
    })
    local b = expand(self.game, "_TradeSendsText", {
      ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
      ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
    })
    self.waitingText = true
    self.game.stack:push(TextBox.new(self.game, a, function()
      self.game.stack:push(TextBox.new(self.game, b, function()
        self.waitingText = false
        self:advance()
      end, { auto = { delay = 80 } }))
    end, { auto = { delay = 80 } }))

  elseif p == "farewell" then
    local a = expand(self.game, "_TradeWavesFarewellText", {
      ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
    })
    local b = expand(self.game, "_TradeTransferredText", {
      ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
    })
    self.waitingText = true
    self.game.stack:push(TextBox.new(self.game, a, function()
      self.game.stack:push(TextBox.new(self.game, b, function()
        self.waitingText = false
        self:advance()
      end, { auto = { delay = 80 } }))
    end, { auto = { delay = 80 } }))

  elseif p == "show_enemy" then
    if self.t == 1 then
      Sound.play(self.game.data, "Ball_Poof")
      self.monVisible = true
    elseif self.t == 20 then
      Sound.playCry(self.game.data, self.received.species)
    elseif self.t >= 120 or skip then
      local text = expand(self.game, "_TradeTakeCareText", {
        ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
      })
      self:say(text, 80)
    end
  end
end

local function drawCableHoriz(self, y, x0, x1)
  if self.img.cableHoriz then
    love.graphics.draw(self.img.cableHoriz, x0 - (self.scx % 8), y)
  else
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", x0, y + 1, math.max(0, x1 - x0), 6)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function TradeAnim:drawMonInfo(mon, ot, otId, boxTy)
  -- Trade_PrintPlayerMonInfoText: rows +0/+2/+4/+6 from the box top; the
  -- No. line replaces part of the top border (hlcoord 5, 0 in trade2.asm)
  Font.drawBox(4, boxTy, 12, 8)
  local y0 = boxTy * 8
  local no = ("No.%03d"):format(dexOf(self.game, mon))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 56, y0, Font.width(no), 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(no, 56, y0)
  Font.draw(speciesName(self.game, mon), 40, y0 + 16)
  Font.draw(Strings("OT/%s", ot or "????"), 40, y0 + 32)
  Font.draw(("IDNo.%05d"):format(otId or 0), 40, y0 + 48)
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:drawIconInBubble(mon, x, y)
  local spr = (mon.species == self.received.species) and self.recvSprite or self.sentSprite
  if spr then
    local sw, sh = spr:getDimensions()
    local s = 16 / math.max(sw, sh)
    love.graphics.draw(spr, x, y, 0, s, s)
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x + 4, y + 4, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.img.bubble then
    if not self.bubbleQuad then
      local iw, ih = self.img.bubble:getDimensions()
      self.bubbleQuad = love.graphics.newQuad(0, 0, 16, 16, iw, ih)
      self.bubbleQuadAlt = ih >= 32
        and love.graphics.newQuad(0, 16, 16, 16, iw, ih)
        or self.bubbleQuad
    end
    local q = self.cableFlash and self.bubbleQuadAlt or self.bubbleQuad
    love.graphics.draw(self.img.bubble, q, x - 8, y - 8)
  end
end

function TradeAnim:drawGameBoy(x, y)
  if self.img.gameBoy then
    love.graphics.draw(self.img.gameBoy, x, y)
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x, y, 48, 64)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function TradeAnim:drawLeftGB()
  -- cable from GB to the right edge
  if self.img.cableConn then
    love.graphics.draw(self.img.cableConn, 88, 32)
  end
  drawCableHoriz(self, 32, 96, 160)
  self:drawGameBoy(40, 24)
  Font.drawBox(4, 12, 9, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.playerName, 40, 112)
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:drawRightGB()
  drawCableHoriz(self, 32, 0, 112)
  if self.img.cableCorner then love.graphics.draw(self.img.cableCorner, 112, 32) end
  if self.img.cableVert then
    for i = 1, 4 do
      love.graphics.draw(self.img.cableVert, 120, 40 + (i - 1) * 8)
    end
  end
  if self.img.cableEnd then love.graphics.draw(self.img.cableEnd, 112, 72) end
  if self.img.cableConn then love.graphics.draw(self.img.cableConn, 104, 72) end
  self:drawGameBoy(56, 64)
  Font.drawBox(6, 0, 9, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.enemyName, 56, 16)
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local p = self.phase

  if p == "show_player" then
    love.graphics.push()
    love.graphics.translate(-self.scx, 0)
    -- mon pic on the BG at hlcoord 7, 2; info box on the window at
    -- hWY $50, so it sits in the bottom half of the screen
    if self.monVisible and self.sentSprite then
      love.graphics.draw(self.sentSprite, 56, 16)
    end
    self:drawMonInfo(self.sent, self.playerOt, self.playerOtId, 10)
    love.graphics.pop()
    if self.poof and self.poof > 0 then
      love.graphics.setColor(0, 0, 0, self.poof / 16)
      love.graphics.circle("fill", 80, 40, 20 - (self.poof or 0))
      love.graphics.setColor(1, 1, 1, 1)
    end

  elseif p == "open_cable" or p == "open_cable2" then
    love.graphics.push()
    love.graphics.translate(self.scx, 0)
    if self.img.openCable then
      love.graphics.draw(self.img.openCable, 64, 16) -- open end at SCX $f0
    end
    love.graphics.pop()

  elseif p == "ball_enter" then
    if self.img.openCable then
      love.graphics.draw(self.img.openCable, 64, 16)
    end
    -- OAM coords carry a (+8, +16) hardware offset
    local ball = self.flash and (self.img.cableBallAlt or self.img.cableBall)
                or self.img.cableBall
    if ball then
      love.graphics.draw(ball, self.ballX - 8, self.ballY - 16)
    else
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.circle("fill", self.ballX, self.ballY - 8, 6)
      love.graphics.setColor(1, 1, 1, 1)
    end

  elseif p == "transfer_lr" or p == "transfer_rl" then
    -- two-screen world: left GB scene at x0, right GB scene at x160;
    -- the mon icon stays in screen space like the OAM sprite it ports
    love.graphics.push()
    love.graphics.translate(-self.scx, 0)
    self:drawLeftGB()
    love.graphics.translate(160, 0)
    self:drawRightGB()
    love.graphics.pop()
    local mon = (p == "transfer_lr") and self.sent or self.received
    self:drawIconInBubble(mon, self.monX, self.monY)
    if self.cableFlash then
      love.graphics.setColor(1, 1, 1, 0.15)
      love.graphics.rectangle("fill", 0, 32, 160, 8)
      love.graphics.setColor(1, 1, 1, 1)
    end

  elseif p == "show_enemy" then
    if self.monVisible and self.recvSprite then
      love.graphics.draw(self.recvSprite, 56, 16)
    end
    self:drawMonInfo(self.received, self.enemyName, self.enemyOtId, 10)
  end
  -- went_to / for_sends / farewell / delay: cleared window; TextBox draws
end

return TradeAnim

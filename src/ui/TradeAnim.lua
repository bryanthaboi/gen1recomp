-- InternalClockTradeAnim (engine/movie/trade.asm): cable-trade cinematic
-- used by in-game NPC trades and internally-clocked link trades.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local TradeAnim = {}
TradeAnim.__index = TradeAnim
TradeAnim.isOpaque = true

-- Trade_LoadMonSprite runs SET_PAL_POKEMON_WHOLE_SCREEN for the mon it puts
-- on screen; every other step of the sequence runs SET_PAL_GENERIC, which is
-- PAL_MEWMON (data/sgb/sgb_packets.asm PalPacket_Generic).  #750
function TradeAnim:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local mon = (self.phase == "show_player" and self.sent)
    or (self.phase == "show_enemy" and self.received)
  local colors = mon and P.monPal(game.data, mon.species)
  if colors then return { P.whole(colors) } end
  return P.wholeNamed(game.data, "MEWMON")
end

local DEFAULT_ART = {
  gameBoy = "assets/generated/trade/game_boy.png",
  openCable = "assets/generated/trade/open_cable.png",
  cableHoriz = "assets/generated/trade/cable_horiz.png",
  cableConn = "assets/generated/trade/cable_conn.png",
  cableSeg = "assets/generated/trade/cable_seg.png",
  cableVert = "assets/generated/trade/cable_vert.png",
  cableCorner = "assets/generated/trade/cable_corner.png",
  cableEnd = "assets/generated/trade/cable_end.png",
  cableBall = "assets/generated/trade/cable_ball.png",
  cableBallAlt = "assets/generated/trade/cable_ball_alt.png",
  bubble = "assets/generated/trade/bubble.png",
  moveAnim0 = "assets/generated/battle/anims/move_anim_0.png",
  balls = "assets/generated/battle/balls.png",
}

local function tryImage(path)
  if not (path and love and love.graphics and love.graphics.newImage) then return nil end
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
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, mon.species, "front", { mon = mon, kind = "trade" })
  local image = tryImage(path)
  return image, image and trueColor or false
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

-- FrameBlocks 03..08 definition for move_anim_0.png (128x40, 16 tiles/row, 8x8 per tile)
local FRAME_BLOCKS = {
  -- FrameBlock03: Pokeball normal (16x16)
  [3] = {
    { tile = 2,  dx = 0, dy = 0, xflip = false, yflip = false },
    { tile = 2,  dx = 8, dy = 0, xflip = true,  yflip = false },
    { tile = 18, dx = 0, dy = 8, xflip = false, yflip = false },
    { tile = 18, dx = 8, dy = 8, xflip = true,  yflip = false },
  },
  -- FrameBlock04: Pokeball tilted left (16x16)
  [4] = {
    { tile = 6,  dx = 0, dy = 0, xflip = false, yflip = false },
    { tile = 7,  dx = 8, dy = 0, xflip = false, yflip = false },
    { tile = 22, dx = 0, dy = 8, xflip = false, yflip = false },
    { tile = 23, dx = 8, dy = 8, xflip = false, yflip = false },
  },
  -- FrameBlock05: Pokeball tilted right (16x16)
  [5] = {
    { tile = 7,  dx = 0, dy = 0, xflip = true,  yflip = false },
    { tile = 6,  dx = 8, dy = 0, xflip = true,  yflip = false },
    { tile = 23, dx = 0, dy = 8, xflip = true,  yflip = false },
    { tile = 22, dx = 8, dy = 8, xflip = true,  yflip = false },
  },
  -- FrameBlock06: Small Poof smoke cloud (32x32)
  [6] = {
    { tile = 0x23, dx = 8,  dy = 0,  xflip = false, yflip = false },
    { tile = 0x32, dx = 0,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x33, dx = 8,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x23, dx = 16, dy = 0,  xflip = true,  yflip = false },
    { tile = 0x33, dx = 16, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x32, dx = 24, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x32, dx = 0,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x33, dx = 8,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x23, dx = 8,  dy = 24, xflip = false, yflip = true  },
    { tile = 0x33, dx = 16, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x32, dx = 24, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x23, dx = 16, dy = 24, xflip = true,  yflip = true  },
  },
  -- FrameBlock07: Medium Poof smoke cloud (32x32)
  [7] = {
    { tile = 0x20, dx = 0,  dy = 0,  xflip = false, yflip = false },
    { tile = 0x21, dx = 8,  dy = 0,  xflip = false, yflip = false },
    { tile = 0x30, dx = 0,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x31, dx = 8,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x21, dx = 16, dy = 0,  xflip = true,  yflip = false },
    { tile = 0x20, dx = 24, dy = 0,  xflip = true,  yflip = false },
    { tile = 0x31, dx = 16, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x30, dx = 24, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x30, dx = 0,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x31, dx = 8,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x20, dx = 0,  dy = 24, xflip = false, yflip = true  },
    { tile = 0x21, dx = 8,  dy = 24, xflip = false, yflip = true  },
    { tile = 0x31, dx = 16, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x30, dx = 24, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x21, dx = 16, dy = 24, xflip = true,  yflip = true  },
    { tile = 0x20, dx = 24, dy = 24, xflip = true,  yflip = true  },
  },
  -- FrameBlock08: Large Poof smoke cloud (32x32)
  [8] = {
    { tile = 0x22, dx = 0,  dy = 0,  xflip = false, yflip = false },
    { tile = 0x23, dx = 8,  dy = 0,  xflip = false, yflip = false },
    { tile = 0x32, dx = 0,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x33, dx = 8,  dy = 8,  xflip = false, yflip = false },
    { tile = 0x23, dx = 16, dy = 0,  xflip = true,  yflip = false },
    { tile = 0x22, dx = 24, dy = 0,  xflip = true,  yflip = false },
    { tile = 0x33, dx = 16, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x32, dx = 24, dy = 8,  xflip = true,  yflip = false },
    { tile = 0x32, dx = 0,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x33, dx = 8,  dy = 16, xflip = false, yflip = true  },
    { tile = 0x22, dx = 0,  dy = 24, xflip = false, yflip = true  },
    { tile = 0x23, dx = 8,  dy = 24, xflip = false, yflip = true  },
    { tile = 0x33, dx = 16, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x32, dx = 24, dy = 16, xflip = true,  yflip = true  },
    { tile = 0x23, dx = 16, dy = 24, xflip = true,  yflip = true  },
    { tile = 0x22, dx = 24, dy = 24, xflip = true,  yflip = true  },
  },
}

-- BallMoveDistances1 (engine/battle/animations.asm:881)
-- Pokéball jumps up into the open link cable nozzle: -12, -12, -8 (3 frames each)
local BALL_SUCTION_DISTANCES = { -12, -12, -8 }

-- BallMoveDistances2 (engine/battle/animations.asm:922)
-- Incoming Pokéball bounces out of nozzle onto the ground: 11, 12, -12, -7, 7, 12, -8, 8 (5 frames each)
local BALL_BOUNCE_DISTANCES = { 11, 12, -12, -7, 7, 12, -8, 8 }

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
    cableSeg = tryImage(art.cableSeg or DEFAULT_ART.cableSeg),
    cableVert = tryImage(art.cableVert or DEFAULT_ART.cableVert),
    cableCorner = tryImage(art.cableCorner or DEFAULT_ART.cableCorner),
    cableEnd = tryImage(art.cableEnd or DEFAULT_ART.cableEnd),
    cableBall = tryImage(art.cableBall or DEFAULT_ART.cableBall),
    cableBallAlt = tryImage(art.cableBallAlt or DEFAULT_ART.cableBallAlt),
    bubble = tryImage(art.bubble or DEFAULT_ART.bubble),
    moveAnim0 = tryImage(DEFAULT_ART.moveAnim0),
    balls = tryImage(DEFAULT_ART.balls),
  }
  self.sentSprite, self.sentSpriteTrueColor = spriteOf(game, self.sent)
  self.recvSprite, self.recvSpriteTrueColor = spriteOf(game, self.received)

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
  self.activeBallBlock = nil
  self.activeBallX = 0
  self.activeBallY = 0
  self.activePoofBlock = nil
  self.activePoofX = 0
  self.activePoofY = 0
  self.wx = 0
  self.slidingBox = false
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
  self.activeBallBlock = nil
  self.activePoofBlock = nil
  self.slidingBox = false
  self.wx = 0

  if self.phase == "done" then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  elseif self.phase == "show_enemy" then
    self.monVisible = false
    self.activeBallBlock = 4
    self.activeBallX, self.activeBallY = 72, 40
    self.activePoofBlock = nil
    self.cableSlideOut = 0
  elseif self.phase == "transfer_lr" then
    -- BaseCoord $54, $1c -> Screen (92, 28) for 16x16 icon (center 100, 36)
    self.monX, self.monY = 92, 28
    self.scx = 0
  elseif self.phase == "transfer_rl" then
    -- BaseCoord $64, $44 -> Screen (108, 68) for 16x16 icon (center 116, 76)
    self.monX, self.monY = 108, 68
    self.scx = 256
  elseif self.phase == "ball_enter" then
    -- Pokéball sits at BaseCoord $48 (Screen 72, 64) before shake and suction
    self.activeBallBlock = 3
    self.activeBallX, self.activeBallY = 72, 64
    self.ballX, self.ballY = 0x60, 0x20
  elseif self.phase == "open_cable" or self.phase == "open_cable2" then
    -- SCX $a0 (160) -> $f0 (240): cable slides in from right, open end rests at x64
    self.scx = 80
    if self.phase == "open_cable" then
      self.activeBallBlock = 3
      self.activeBallX, self.activeBallY = 72, 64
    end
    Sound.play(self.game.data, "Heal_HP")
  end
end

function TradeAnim:skipHeld()
  return self.game.input:wasPressed("a") or self.game.input:wasPressed("b")
end

function TradeAnim:drawFrameBlock(blockId, x, y)
  local block = FRAME_BLOCKS[blockId]
  if not block then return end
  if self.img.moveAnim0 then
    local iw, ih = self.img.moveAnim0:getDimensions()
    for _, tile in ipairs(block) do
      local tx = (tile.tile % 16) * 8
      local ty = math.floor(tile.tile / 16) * 8
      local quad = love.graphics.newQuad(tx, ty, 8, 8, iw, ih)
      local sx = tile.xflip and -1 or 1
      local sy = tile.yflip and -1 or 1
      local ox = tile.xflip and 8 or 0
      local oy = tile.yflip and 8 or 0
      love.graphics.draw(self.img.moveAnim0, quad, x + tile.dx + ox, y + tile.dy + oy, 0, sx, sy)
    end
  else
    if blockId == 3 or blockId == 4 or blockId == 5 then
      love.graphics.setColor(0.9, 0.2, 0.2, 1)
      love.graphics.arc("fill", x + 8, y + 8, 7, math.pi, 0)
      love.graphics.setColor(0.9, 0.9, 0.9, 1)
      love.graphics.arc("fill", x + 8, y + 8, 7, 0, math.pi)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.circle("line", x + 8, y + 8, 7)
      love.graphics.line(x + 1, y + 8, x + 15, y + 8)
      love.graphics.circle("fill", x + 8, y + 8, 2)
      love.graphics.setColor(1, 1, 1, 1)
    elseif blockId == 6 or blockId == 7 or blockId == 8 then
      local r = (blockId - 5) * 5
      love.graphics.setColor(0.8, 0.8, 0.8, 0.8)
      love.graphics.circle("fill", x + 16, y + 16, r)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

function TradeAnim:update(dt)
  if self.waitingText or self.phase == "done" then return end
  local skip = self:skipHeld()
  self.t = self.t + 1
  local p = self.phase

  if p == "show_player" then
    -- Trade_ShowPlayerMon:
    -- 1. Slide from SCX $7e (126) -> 0 at 2px/frame (63 frames)
    -- 2. Hold 80 frames
    -- 3. TRADE_BALL_POOF_ANIM at BaseCoord $72 (Screen 64, 48): 3 frames x 6 ticks = 18 ticks
    -- 4. TRADE_BALL_DROP_ANIM: mon vanishes, ball drops $41 (72, 56) -> $48 (72, 64) over 36 ticks
    -- 5. PlayCry while ball sits on ground at (72, 64)
    if not self.sub then self.sub = "slide" end

    if self.sub == "slide" then
      self.scx = math.max(0, 126 - self.t * 2)
      if skip or self.scx <= 0 then
        self.scx = 0
        self.sub = "hold"
        self.t = 0
      end
    elseif self.sub == "hold" then
      if skip or self.t >= 80 then
        self.sub = "poof"
        self.t = 0
        Sound.play(self.game.data, "Ball_Poof")
      end
    elseif self.sub == "poof" then
      local step = math.floor(self.t / 6)
      if step >= 3 or skip then
        self.sub = "ball_drop"
        self.t = 0
        self.activePoofBlock = nil
        self.monVisible = false
      else
        self.activePoofBlock = 6 + step
        self.activePoofX, self.activePoofY = 64, 48
      end
    elseif self.sub == "ball_drop" then
      if skip or self.t >= 36 then
        self.sub = "cry"
        self.t = 0
        self.activeBallBlock = 3
        self.activeBallX, self.activeBallY = 72, 64
        Sound.playCry(self.game.data, self.sent.species)
      else
        local step = math.floor(self.t / 6)
        if step == 0 then
          self.activeBallBlock = 3
          self.activeBallX, self.activeBallY = 72, 56
        else
          local blocks = { 3, 4, 3, 5, 3 }
          self.activeBallBlock = blocks[step] or 3
          self.activeBallX, self.activeBallY = 72, 64
        end
      end
    elseif self.sub == "cry" then
      if skip or self.t >= 40 then
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "open_cable" or p == "open_cable2" then
    -- Trade_DrawOpenEndOfLinkCable: SCX $a0 (160) -> $f0 (240) in 20 steps of 4px
    self.scx = math.max(0, 80 - self.t * 4)
    if skip or self.scx <= 0 then
      self.scx = 0
      self:advance()
    end

  elseif p == "ball_enter" then
    -- Trade_AnimateBallEnteringLinkCable:
    -- 1. TRADE_BALL_SHAKE_ANIM (16 ticks) + TradeShakePokeball suction jump (-12, -12, -8 over 9 ticks):
    --    - Shakes at (72, 64) for 16 ticks (FrameBlock 04, 03, 05, 03)
    --    - Jumps up: Y=52 (3 ticks), Y=40 (3 ticks), Y=32 (3 ticks)
    --    - Ball cleared, SFX_TRADE_MACHINE plays
    -- 2. DelayFrames 10 (chills for 10 frames)
    -- 3. Ball inside horizontal cable: 16 steps of +4px every 3 frames (48 frames) with Tink sfx & bulge toggle
    -- 4. Delay3
    if not self.sub then self.sub = "shake" end

    if self.sub == "shake" then
      if skip or self.t >= 16 then
        self.sub = "jump_up"
        self.t = 0
      else
        local shakeBlocks = { 4, 3, 5, 3 }
        local step = math.floor(self.t / 4) + 1
        self.activeBallBlock = shakeBlocks[step] or 3
        self.activeBallX, self.activeBallY = 72, 64
      end
    elseif self.sub == "jump_up" then
      local step = math.floor(self.t / 3) + 1
      if step > #BALL_SUCTION_DISTANCES or skip then
        self.sub = "chill"
        self.t = 0
        self.activeBallBlock = nil
        Sound.play(self.game.data, "Trade_Machine")
      else
        local yPos = 64
        for i = 1, step do
          yPos = yPos + BALL_SUCTION_DISTANCES[i]
        end
        self.activeBallBlock = 3
        self.activeBallX, self.activeBallY = 72, yPos
      end
    elseif self.sub == "chill" then
      if skip or self.t >= 10 then
        self.sub = "suction"
        self.t = 0
        self.ballX = 0x60
      end
    elseif self.sub == "suction" then
      local step = math.floor(self.t / 3)
      if step >= 16 or skip then
        self.sub = "exit_pause"
        self.t = 0
        self.ballX = 0xA0
      else
        self.ballX = 0x60 + step * 4
        self.flash = (step % 2 == 1)
        if self.t % 3 == 0 and step < 16 then
          Sound.play(self.game.data, "Tink")
        end
      end
    elseif self.sub == "exit_pause" then
      if skip or self.t >= 3 then
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "transfer_lr" then
    -- 16 units of 16px (256px total scroll) at 2px/frame = 128 frames (SCX 0 -> 256)
    if self.t <= 128 then
      self.scx = math.min(256, self.t * 2)
      self.monX, self.monY = 92, 28
    elseif self.t <= 128 + 32 then
      local step = math.floor((self.t - 128) / 8) + 1
      step = math.min(4, step)
      self.scx = 256
      self.monX = 92 + step * 4
      self.monY = 28
    elseif self.t <= 128 + 64 then
      local step = math.floor((self.t - 160) / 8) + 1
      step = math.min(4, step)
      self.scx = 256
      self.monX = 108
      self.monY = 28 + step * 10
    else
      self:advance()
      return
    end
    if self.t % 8 == 0 then self.cableFlash = not self.cableFlash end
    if skip then self:advance() end

  elseif p == "transfer_rl" then
    -- 64 frames vertical ascent + 128 frames horizontal scroll (SCX 256 -> 0)
    if self.t <= 32 then
      local step = math.floor(self.t / 8) + 1
      step = math.min(4, step)
      self.scx = 256
      self.monX = 108
      self.monY = 68 - step * 10
    elseif self.t <= 64 then
      local step = math.floor((self.t - 32) / 8) + 1
      step = math.min(4, step)
      self.scx = 256
      self.monX = 108 - step * 4
      self.monY = 28
    elseif self.t <= 64 + 128 then
      self.scx = math.max(0, 256 - (self.t - 64) * 2)
      self.monX, self.monY = 92, 28
    else
      self:advance()
      return
    end
    if self.t % 8 == 0 then self.cableFlash = not self.cableFlash end
    if skip then self:advance() end

  elseif p == "delay" then
    if skip or self.t >= 100 then self:advance() end

  elseif p == "went_to" then
    if not self.sub then
      self.sub = "text"
      self.t = 0
      local text = expand(self.game, "_TradeWentToText", {
        ["RAM:wStringBuffer"] = speciesName(self.game, self.sent),
        ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
      })
      self.dialogText = text
    end

    if self.sub == "text" then
      if skip or self.t >= 200 then
        self.sub = "slide_hold"
        self.t = 0
      end
    elseif self.sub == "slide_hold" then
      if skip or self.t >= 50 then
        self.sub = "slide_off"
        self.t = 0
        self.slidingBox = true
      end
    elseif self.sub == "slide_off" then
      self.wx = math.min(160, self.t * 2)
      if skip or self.wx >= 160 then
        self.wx = 160
        self.sub = "slide_end_pause"
        self.t = 0
      end
    elseif self.sub == "slide_end_pause" then
      if skip or self.t >= 10 then
        self.slidingBox = false
        self.dialogText = nil
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "for_sends" then
    if not self.sub then
      self.sub = "for_text"
      self.t = 0
      self.dialogText = expand(self.game, "_TradeForText", {
        ["RAM:wStringBuffer"] = speciesName(self.game, self.sent),
      })
    end

    if self.sub == "for_text" then
      if skip or self.t >= 80 then
        self.sub = "sends_text"
        self.t = 0
        self.dialogText = expand(self.game, "_TradeSendsText", {
          ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
          ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
        })
      end
    elseif self.sub == "sends_text" then
      if skip or self.t >= 80 then
        self.dialogText = nil
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "farewell" then
    if not self.sub then
      self.sub = "farewell_text"
      self.t = 0
      self.dialogText = expand(self.game, "_TradeWavesFarewellText", {
        ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
      })
    end

    if self.sub == "farewell_text" then
      if skip or self.t >= 80 then
        self.sub = "transferred_text"
        self.t = 0
        self.dialogText = expand(self.game, "_TradeTransferredText", {
          ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
        })
      end
    elseif self.sub == "transferred_text" then
      if skip or self.t >= 80 then
        self.sub = "slide_hold"
        self.t = 0
      end
    elseif self.sub == "slide_hold" then
      if skip or self.t >= 50 then
        self.sub = "slide_off"
        self.t = 0
        self.slidingBox = true
      end
    elseif self.sub == "slide_off" then
      self.wx = math.min(160, self.t * 2)
      if skip or self.wx >= 160 then
        self.wx = 160
        self.sub = "slide_end_pause"
        self.t = 0
      end
    elseif self.sub == "slide_end_pause" then
      if skip or self.t >= 10 then
        self.slidingBox = false
        self.dialogText = nil
        self.sub = nil
        self:advance()
      end
    end

  elseif p == "show_enemy" then
    -- Trade_ShowEnemyMon (engine/movie/trade.asm:354):
    -- 1. TRADE_BALL_TILT_ANIM with TradeJumpPokeball (8 bounce steps, 5 ticks each = 40 ticks):
    --    - Starts at BaseCoord $84 (Screen X=72, Y=40)
    --    - Moves Y by BallMoveDistances2 (+11, +12, -12, -7, +7, +12, -8, +8)
    --    - On each step: Cable slides off-screen right by 8px
    --    - Plays SFX_SWAP on impacts
    -- 2. ClearScreen, Info box at (4, 10), Mon front sprite at (7, 2)
    -- 3. TRADE_BALL_POOF_ANIM: FrameBlock 06, 07, 08 (18 ticks), SFX_BALL_POOF, revealing mon
    -- 4. PlayCry
    -- 5. Trade_Delay100
    -- 6. Info box cleared, PrintTradeTakeCareText (80 ticks)
    -- 7. Trade_Delay100 -> finish
    if not self.sub then
      self.sub = "ball_bounce"
      self.t = 0
      self.cableSlideOut = 0
      self.activeBallBlock = 4
      self.activeBallX, self.activeBallY = 72, 40
    end

    if self.sub == "ball_bounce" then
      local step = math.floor(self.t / 5) + 1
      if step > #BALL_BOUNCE_DISTANCES or skip then
        self.sub = "poof"
        self.t = 0
        self.activeBallBlock = nil
        self.monVisible = true
        self.cableSlideOut = nil
        Sound.play(self.game.data, "Ball_Poof")
      else
        local yPos = 40
        for i = 1, step do
          yPos = yPos + BALL_BOUNCE_DISTANCES[i]
        end
        self.activeBallBlock = 4
        self.activeBallX, self.activeBallY = 72, yPos
        self.cableSlideOut = (step - 1) * 8
        if self.t % 5 == 0 and (BALL_BOUNCE_DISTANCES[step] == 12 or step == #BALL_BOUNCE_DISTANCES) then
          Sound.play(self.game.data, "Swap")
        end
      end
    elseif self.sub == "poof" then
      local step = math.floor(self.t / 6)
      if step >= 3 or skip then
        self.sub = "cry"
        self.t = 0
        self.activePoofBlock = nil
        Sound.playCry(self.game.data, self.received.species)
      else
        self.activePoofBlock = 6 + step
        self.activePoofX, self.activePoofY = 64, 48
      end
    elseif self.sub == "cry" then
      if skip or self.t >= 100 then
        self.sub = "take_care"
        self.t = 0
        self.dialogText = expand(self.game, "_TradeTakeCareText", {
          ["RAM:wNameBuffer"] = nameOf(self.game, self.received),
        })
      end
    elseif self.sub == "take_care" then
      if skip or self.t >= 80 then
        self.sub = "delay_end"
        self.t = 0
        self.dialogText = nil
      end
    elseif self.sub == "delay_end" then
      if skip or self.t >= 100 then
        self.sub = nil
        self:advance()
      end
    end
  end
end

local function drawCableHoriz(self, y, x0, x1)
  local w = math.max(0, x1 - x0)
  if w <= 0 then return end
  if self.cableFlash then
    love.graphics.setColor(0.65, 0.65, 0.65, 1)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.img.cableHoriz then
    local iw, ih = self.img.cableHoriz:getDimensions()
    for x = x0, x1 - 1, iw do
      local drawW = math.min(iw, x1 - x)
      local quad = love.graphics.newQuad(0, 0, drawW, ih, iw, ih)
      love.graphics.draw(self.img.cableHoriz, quad, x, y)
    end
  elseif self.img.cableSeg then
    for x = x0, x1 - 8, 8 do
      love.graphics.draw(self.img.cableSeg, x, y)
    end
  else
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", x0, y + 1, w, 6)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:drawMonInfo(mon, ot, otId, boxTy)
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
  if self.img.bubble then
    if not self.bubbleQuad then
      local iw, ih = self.img.bubble:getDimensions()
      self.bubbleQuad = love.graphics.newQuad(0, 0, 16, 16, iw, ih)
      self.bubbleQuadAlt = ih >= 32
        and love.graphics.newQuad(0, 16, 16, 16, iw, ih)
        or self.bubbleQuad
    end
    local q = self.cableFlash and self.bubbleQuadAlt or self.bubbleQuad
    local left, top = x - 8, y - 8
    local right, bottom = left + 32, top + 32
    love.graphics.draw(self.img.bubble, q, left, top)
    love.graphics.draw(self.img.bubble, q, right, top, 0, -1, 1)
    love.graphics.draw(self.img.bubble, q, left, bottom, 0, 1, -1)
    love.graphics.draw(self.img.bubble, q, right, bottom, 0, -1, -1)
  end
  local drawn = mon and require("src.ui.PartyMenu").drawIcon(
    self.game, mon, x, y, false, 0, self.cableFlash)
  if not drawn then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x + 4, y + 4, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
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
  if self.cableFlash then
    love.graphics.setColor(0.65, 0.65, 0.65, 1)
  end
  if self.img.cableConn then
    love.graphics.draw(self.img.cableConn, 88, 32)
  end
  love.graphics.setColor(1, 1, 1, 1)
  drawCableHoriz(self, 32, 96, 256)
  self:drawGameBoy(40, 24)
  Font.drawBox(4, 12, 9, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.playerName, 40, 112)
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:drawRightGB()
  drawCableHoriz(self, 32, 0, 112)
  if self.cableFlash then
    love.graphics.setColor(0.65, 0.65, 0.65, 1)
  end
  if self.img.cableCorner then love.graphics.draw(self.img.cableCorner, 112, 32) end
  if self.img.cableVert then
    for i = 1, 4 do
      love.graphics.draw(self.img.cableVert, 112, 40 + (i - 1) * 8)
    end
  end
  if self.img.cableEnd then love.graphics.draw(self.img.cableEnd, 112, 72) end
  if self.img.cableConn then love.graphics.draw(self.img.cableConn, 104, 72) end
  love.graphics.setColor(1, 1, 1, 1)
  self:drawGameBoy(56, 64)
  Font.drawBox(6, 0, 9, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.enemyName, 56, 16)
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnim:drawDialog()
  if not self.dialogText then return end
  love.graphics.push()
  if self.slidingBox then
    love.graphics.translate(self.wx, 0)
  end
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local lines = {}
  for line in self.dialogText:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  if lines[1] then Font.draw(lines[1], 8, 112) end
  if lines[2] then Font.draw(lines[2], 8, 128) end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

function TradeAnim:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local p = self.phase

  if p == "show_player" then
    love.graphics.push()
    love.graphics.translate(-self.scx, 0)
    if self.monVisible and self.sentSprite then
      love.graphics.draw(self.sentSprite, 56 + self.sentSprite:getWidth(), 16, 0, -1, 1)
      if self.sentSpriteTrueColor then
        require("src.render.PaletteFX").markTrueColor(
          56 - self.scx, 16, self.sentSprite:getDimensions())
      end
    end
    self:drawMonInfo(self.sent, self.playerOt, self.playerOtId, 10)
    love.graphics.pop()

    if self.activePoofBlock then
      self:drawFrameBlock(self.activePoofBlock, self.activePoofX, self.activePoofY)
    end
    if self.activeBallBlock then
      self:drawFrameBlock(self.activeBallBlock, self.activeBallX, self.activeBallY)
    end

  elseif p == "open_cable" or p == "open_cable2" then
    love.graphics.push()
    love.graphics.translate(self.scx, 0)
    if self.img.openCable then
      love.graphics.draw(self.img.openCable, 64, 16)
    end
    love.graphics.pop()
    if p == "open_cable" and self.activeBallBlock then
      self:drawFrameBlock(self.activeBallBlock, self.activeBallX, self.activeBallY)
    end

  elseif p == "ball_enter" then
    if self.img.openCable then
      love.graphics.draw(self.img.openCable, 64, 16)
    end
    if self.activeBallBlock then
      self:drawFrameBlock(self.activeBallBlock, self.activeBallX, self.activeBallY)
    elseif self.sub == "suction" or self.sub == "exit_pause" then
      local ball = self.flash and (self.img.cableBallAlt or self.img.cableBall)
                  or self.img.cableBall
      if ball then
        love.graphics.draw(ball, self.ballX - 8, self.ballY - 16)
      else
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("fill", self.ballX, self.ballY - 8, 6)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end

  elseif p == "transfer_lr" or p == "transfer_rl" then
    love.graphics.push()
    love.graphics.translate(-self.scx, 0)
    self:drawLeftGB()
    love.graphics.translate(256, 0)
    self:drawRightGB()
    love.graphics.pop()
    local mon = p == "transfer_lr" and self.sent or self.received
    self:drawIconInBubble(mon, self.monX, self.monY)

  elseif p == "show_enemy" then
    if self.cableSlideOut and self.img.openCable then
      love.graphics.push()
      love.graphics.translate(self.cableSlideOut, 0)
      love.graphics.draw(self.img.openCable, 64, 16)
      love.graphics.pop()
    end
    if self.monVisible and self.recvSprite then
      love.graphics.draw(self.recvSprite, 56 + self.recvSprite:getWidth(), 16, 0, -1, 1)
      if self.recvSpriteTrueColor then
        require("src.render.PaletteFX").markTrueColor(
          56, 16, self.recvSprite:getDimensions())
      end
    end
    if self.monVisible and self.sub ~= "take_care" and self.sub ~= "delay_end" then
      self:drawMonInfo(self.received, self.enemyName, self.enemyOtId, 10)
    end
    if self.activeBallBlock then
      self:drawFrameBlock(self.activeBallBlock, self.activeBallX, self.activeBallY)
    end
    if self.activePoofBlock then
      self:drawFrameBlock(self.activePoofBlock, self.activePoofX, self.activePoofY)
    end
  end

  self:drawDialog()
end

return TradeAnim

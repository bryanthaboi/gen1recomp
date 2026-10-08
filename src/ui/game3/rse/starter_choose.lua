local Kit = require("src.ui.game3.rse.scene_kit")
local RomText = require("src.core.game3.rom_text")
local Strings = require("src.core.Strings")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pal = require("src.core.game3.pal_fade")
local Trig = require("src.core.game3.trig")

local bit = require("bit")

local StarterChoose = {}
StarterChoose.__index = StarterChoose

-- pokeemerald/src/starter_choose.c:30
StarterChoose.PKMN_POS_X = 240 / 2
StarterChoose.PKMN_POS_Y = 64
-- pokeemerald/src/starter_choose.c:435
StarterChoose.BLDY = 7

local function Sin(i, a)
  local v = bit.arshift(a * Trig.SINE[bit.band(i, 0xFF) + 1], 8)
  return v
end

local function newAnimState(anims, n)
  return { anims = anims, num = n or 1, cmd = 1, delay = 0, frame = 0, started = false }
end

-- pokeemerald/src/sprite.c:909
local function animStart(st, n)
  st.num, st.cmd, st.started = n, 1, true
  local c = st.anims[n] and st.anims[n][1]
  if c and c.op == "frame" then
    st.frame = c.frame or 0
    st.delay = math.max(0, (c.duration or 0) - 1)
  end
end

local function animIfDifferent(st, n)
  if st.num ~= n or not st.started then animStart(st, n) end
end

-- pokeemerald/src/sprite.c:943
local function animStep(st)
  if not st.started then animStart(st, st.num) return end
  if st.delay > 0 then
    st.delay = st.delay - 1
    return
  end
  local list = st.anims[st.num] or {}
  local guard = 0
  while guard < 16 do
    guard = guard + 1
    st.cmd = st.cmd + 1
    local c = list[st.cmd]
    if not c or c.op == "end" then
      st.cmd = st.cmd - 1
      return
    elseif c.op == "jump" then
      st.cmd = (c.target or 0)
    elseif c.op == "frame" then
      st.frame = c.frame or 0
      st.delay = math.max(0, (c.duration or 0) - 1)
      return
    end
  end
end

local function affineNew(cmds)
  return { cmds = cmds or {}, idx = 1, delay = 0, scale = 256, begun = false, ended = false }
end

-- pokeemerald/src/sprite.c:1330
local function affineApply(a, c)
  a.cur = c
  local d = tonumber(c.duration) or 0
  if d > 0 then
    a.scale = a.scale + (c.xScale or 0)
    a.delay = d - 1
  else
    a.scale = c.xScale or a.scale
    a.delay = 0
  end
end

-- pokeemerald/src/sprite.c:1067
local function affineStep(a)
  if a.ended then return end
  if not a.begun then
    a.begun = true
    local c = a.cmds[1]
    if c and c.op == "frame" then affineApply(a, c) else a.ended = true end
    return
  end
  if a.delay > 0 then
    a.delay = a.delay - 1
    a.scale = a.scale + (a.cur.xScale or 0)
    return
  end
  a.idx = a.idx + 1
  local c = a.cmds[a.idx]
  if not c or c.op ~= "frame" then
    a.ended = true
    return
  end
  affineApply(a, c)
end

StarterChoose._anim = { start = animStart, step = animStep, ifDifferent = animIfDifferent }
StarterChoose._affine = { new = affineNew, step = affineStep }

function StarterChoose.manifest()
  return Kit.manifest("starter_choose")
end

function StarterChoose.species(man, selection)
  man = man or StarterChoose.manifest()
  local list = man and man.species or {}
  selection = tonumber(selection) or 0
  -- pokeemerald/src/starter_choose.c:351
  if selection > #list then selection = 0 end
  return list[selection + 1]
end

local function categoryText(species, policy)
  local Pokemon = require("src.core.game3.pokemon")
  local dex = Kit.loadLua("data/generated/gba/pokemon/dex.lua")
  local nat = Pokemon.national and Pokemon.national(species) or species
  local row = dex and dex[nat]
  -- pokeemerald/src/international_string_util.c:86
  local category = Strings((row and row.category) or "")
  if policy then return policy.categoryText(category, RomText.plain(policy.categoryKey)) end
  return category .. " " .. RomText.plain("gText_Pokemon")
end

local function speciesName(species)
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon.name(species) or ""
end

function StarterChoose.new(opts)
  opts = opts or {}
  local man = StarterChoose.manifest()
  if not man then error("starter choose: data/generated/gba/starter_choose/manifest.lua missing from the cache", 2) end
  local profile = require("src.core.game3.profile").forSession()
  local policy = (profile.id == "ruby" or profile.id == "sapphire")
    and require("src.ui.game3.rs.starter_choose_policy") or nil
  local self = setmetatable({
    man = man,
    policy = policy,
    onDone = opts.onDone,
    frameType = opts.frameType or 0,
    pal = Pal.new(),
    selection = 1,
    state = "choose",
    frames = 0,
    handPhase = 0,
    balls = {},
    hand = newAnimState(man.sprites.hand.anims, 1),
  }, StarterChoose)
  for i = 1, 3 do self.balls[i] = newAnimState(man.sprites.pokeball.anims, 1) end
  animStart(self.hand, 1)
  -- pokeemerald/src/starter_choose.c:423
  self.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
  return self
end

function StarterChoose:_createLabel()
  local sp = StarterChoose.species(self.man, self.selection)
  self.label = { selection = self.selection, category = categoryText(sp, self.policy), name = speciesName(sp) }
end

function StarterChoose:_clearLabel()
  self.label = nil
end

-- pokeemerald/src/starter_choose.c:474
function StarterChoose:_taskStarterChoose()
  self:_createLabel()
  self.message = self.policy and self.policy.messageKey or "gText_BirchInTrouble"
  self.messageFill = self.policy ~= nil
  self.state = "input"
end

-- pokeemerald/src/starter_choose.c:656
local function spriteToward(s)
  local X, Y = StarterChoose.PKMN_POS_X, StarterChoose.PKMN_POS_Y
  if s.x > X then s.x = s.x - 4 end
  if s.x < X then s.x = s.x + 4 end
  if s.y > Y then s.y = s.y - 2 end
  if s.y < Y then s.y = s.y + 2 end
end

function StarterChoose:frame(inp)
  inp = inp or { new = {}, held = {} }
  inp.new, inp.held = inp.new or {}, inp.held or {}
  self.frames = self.frames + 1
  if not self.policy then self.pal:updateFade() end
  local st = self.state
  if st == "choose" then
    self:_taskStarterChoose()
  elseif st == "input" then
    -- pokeemerald/src/starter_choose.c:484
    local sel = self.selection
    if inp.new.a then
      self:_clearLabel()
      local c = self.man.pokeballCoords[sel + 1]
      self.circle = { x = c[1], y = c[2], affine = affineNew(self.man.affine.circle) }
      self.mon = { x = c[1], y = c[2], affine = affineNew(self.man.affine.pokemon),
        species = StarterChoose.species(self.man, sel) }
      self.state = "wait_sprite"
    elseif inp.new.left and sel > 0 then
      self.selection = sel - 1
      self:_clearLabel()
      if self.policy then self:_createLabel() else self.state = "create_label" end
    elseif inp.new.right and sel < 2 then
      self.selection = sel + 1
      self:_clearLabel()
      if self.policy then self:_createLabel() else self.state = "create_label" end
    end
  elseif st == "create_label" then
    -- pokeemerald/src/starter_choose.c:623
    self:_createLabel()
    self.state = "input"
  elseif st == "wait_sprite" then
    -- pokeemerald/src/starter_choose.c:518
    local c = self.circle
    if c.affine.ended and c.x == StarterChoose.PKMN_POS_X and c.y == StarterChoose.PKMN_POS_Y then
      self.state = "ask"
    end
  elseif st == "ask" then
    -- pokeemerald/src/starter_choose.c:528
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playCry then Audio.playCry(self.mon.species) end
    self.message = self.policy and self.policy.confirmKey or "gText_ConfirmStarterChoice"
    self.messageFill = true
    if self.policy then
      self.confirm = self.policy.confirm(self.frameType)
    else
      local w = self.man.windows.confirm
      self.confirm = Kit.yesNo(w.tilemapLeft, w.tilemapTop, { frameType = self.frameType, initial = 0 })
    end
    self.state = "confirm"
  elseif st == "confirm" then
    -- pokeemerald/src/starter_choose.c:538
    local r = self.confirm:input(inp)
    if r == 0 then
      self.confirm = nil
      self.done = true
      self.result = self.selection
    elseif r == 1 or r == -1 then
      Kit.playSe("SE_SELECT")
      self.confirm = nil
      self.circle, self.mon = nil, nil
      self.state = "decline"
    end
  elseif st == "decline" then
    self.state = "choose"
  end
  -- pokeemerald/src/starter_choose.c:638
  self.handY2 = Sin(self.handPhase, 8)
  self.handPhase = bit.band(self.handPhase + 4, 0xFF)
  for i = 1, 3 do
    animIfDifferent(self.balls[i], (i - 1) == self.selection and 2 or 1)
    animStep(self.balls[i])
  end
  animStep(self.hand)
  if self.circle then
    spriteToward(self.circle)
    affineStep(self.circle.affine)
  end
  if self.mon then
    spriteToward(self.mon)
    affineStep(self.mon.affine)
  end
  if self.policy then self.pal:updateFade() end
  return self.done
end

local quads = {}

local function frameQuad(img, entry, frame)
  local key = tostring(img) .. ":" .. frame
  local q = quads[key]
  if not q then
    q = love.graphics.newQuad(0, frame * entry.h, entry.w, entry.h, img:getDimensions())
    quads[key] = q
  end
  return q
end

local function drawSprite(entry, frame, cx, cy, scale)
  local img = Kit.image(entry.png)
  if not img then return end
  scale = scale or 1
  local w, h = entry.w, entry.h
  love.graphics.draw(img, frameQuad(img, entry, frame or 0), cx, cy, 0, scale, scale, w / 2, h / 2)
end

local function monImage(species)
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not ok then return nil end
  local e = Pokemon.frontPic(species, nil, nil, nil, "overworld")
  return e and e.image or nil
end

function StarterChoose:labelRect()
  if self.policy and self.label then return self.policy.labelRect(self.man, self.label.selection) end
  local lc = self.label and self.man.labelCoords[self.label.selection + 1]
  if not lc then return nil end
  -- pokeemerald/src/starter_choose.c:598
  local left = (lc[1] * 8 - 4) % 256
  local right = ((lc[1] + 13) * 8 + 4) % 256
  if left > right then left = 0 end
  return left, lc[2] * 8, right, (lc[2] + 4) * 8
end

function StarterChoose:draw()
  local man = self.man
  local bd = Kit.color555(man.layers.grass.backdrop or 0)
  love.graphics.clear(bd[1], bd[2], bd[3], 1)
  love.graphics.setColor(1, 1, 1, 1)
  local grass = Kit.image(man.layers.grass.png)
  if grass then love.graphics.draw(grass, 0, 0) end
  local bag = Kit.image(man.layers.bag.png)
  if bag then love.graphics.draw(bag, 0, 0) end
  local sp = man.sprites
  -- pokeemerald/src/starter_choose.c:638
  local cc = man.cursorCoords[self.selection + 1]
  drawSprite(sp.hand, self.hand.frame, cc[1], cc[2] + (self.handY2 or 0))
  for i = 1, 3 do
    local c = man.pokeballCoords[i]
    drawSprite(sp.pokeball, self.balls[i].frame, c[1], c[2])
  end
  if self.circle then
    if self.policy then
      self.policy.drawAffine(self.circle.x, self.circle.y, self.circle.affine.scale, 64, function(scale)
        drawSprite(sp.circle, 0, self.circle.x, self.circle.y, scale)
      end)
    else
      drawSprite(sp.circle, 0, self.circle.x, self.circle.y, self.circle.affine.scale / 256)
    end
  end
  local l, t, r, b = self:labelRect()
  if l then
    love.graphics.setColor(0, 0, 0, StarterChoose.BLDY / 16)
    love.graphics.rectangle("fill", l, t, r - l, b - t)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- pokeemerald/src/starter_choose.c:151
  local tc = man.textColors or { 0, 1, 3 }
  local white = Kit.messageColors("message_box", tc[2], tc[1], tc[3])
  white.bg = { 0, 0, 0, 0 }
  if self.label and self.policy then
    self.policy.drawLabel(self.label, man)
  elseif self.label then
    local lc = man.labelCoords[self.label.selection + 1]
    local wx, wy = lc[1] * 8, lc[2] * 8
    local width = 0x68
    -- pokeemerald/src/starter_choose.c:589
    local cw = FrlgFont.measure(self.label.category, { font = "narrow" })
    FrlgFont.draw(self.label.category, wx + math.max(0, math.floor((width - cw) / 2)), wy + 1,
      { colors = white, font = "narrow" })
    local nw = FrlgFont.measure(self.label.name)
    FrlgFont.draw(self.label.name, wx + math.max(0, math.floor((width - nw) / 2)), wy + 17, { colors = white })
  end
  if self.message then
    local w = self.policy and self.policy.windows.message or man.windows.message
    local colors = self.policy and self.policy.messageColors or Kit.messageColors()
    local text = RomText.plain(self.message)
    local x0, y0 = w.tilemapLeft * 8, w.tilemapTop * 8
    Kit.userFrame(w.tilemapLeft, w.tilemapTop, w.width, w.height, self.frameType, self.messageFill and colors.bg or nil)
    FrlgFont.draw(text, x0, y0 + (self.policy and 0 or 1), { colors = colors, maxWidth = w.width * 8 })
  end
  if self.confirm then self.confirm:draw() end
  if self.mon then
    local img = monImage(self.mon.species)
    if img then
      local function draw(scale)
        love.graphics.draw(img, frameQuad(img, { w = 64, h = 64 }, 0), self.mon.x, self.mon.y, 0, scale, scale, 32, 32)
      end
      if self.policy then self.policy.drawAffine(self.mon.x, self.mon.y, self.mon.affine.scale, 32, draw)
      else draw(self.mon.affine.scale / 256) end
    end
  end
  Kit.drawFade(self.pal, 0)
end

local Host = {}
StarterChoose.Host = Host
Host._screen = nil
Host._step = nil

function StarterChoose.open(opts)
  local Stack = require("src.ui.game3.stack")
  local screen = StarterChoose.new(opts)
  Host._screen = screen
  Host._step = Kit.stepper()
  local userDone = screen.onDone
  screen.onDone = function(result)
    Host._screen = nil
    Stack.pop("starter_choose")
    if userDone then userDone(result) end
  end
  Stack.push("starter_choose", Host, { hideBelow = true, fullscreen = true })
  return screen
end

function StarterChoose.isOpen()
  return Host._screen ~= nil
end

function StarterChoose.active()
  return Host._screen
end

function StarterChoose.reset()
  if Host._screen then
    Host._screen = nil
    require("src.ui.game3.stack").pop("starter_choose")
  end
  Host._step = nil
end

function Host.handleInput(input)
  if Host._step then Host._step:collect(input) end
end

function Host.update(dt)
  local screen = Host._screen
  if not screen then return end
  local done = Host._step:run(dt, function(inp)
    if screen.done then return true end
    screen:frame(inp)
    return screen.done or nil
  end)
  if done and screen.onDone then screen.onDone(screen.result) end
end

function Host.draw()
  if Host._screen then Host._screen:draw() end
end

return StarterChoose

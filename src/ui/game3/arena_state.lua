local Strings = require("src.core.Strings")

local ArenaState = {}
ArenaState.__index = ArenaState

ArenaState.HOLD_FRAMES = 300
ArenaState.CANCEL_FRAMES = 120
ArenaState.CATCH_UP_STEPS = 4

local RESULTS = { win = true, lose = true, draw = true, ended = true, error = true }

local function LB() return require("src.core.game3.link.battle") end
local function Link() return require("src.core.game3.link") end
local function Battle() return require("src.core.game3.battle") end

local function installChrome()
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache and Dataset.cache()
  for _, name in ipairs({ "src.core.game3.pokemon", "src.ui.game3.party_chrome", "src.ui.game3.battle_chrome" }) do
    local ok, mod = pcall(require, name)
    if ok and type(mod) == "table" and mod.install then
      local okI, err = pcall(mod.install, cache)
      if not okI then print("[arena3] " .. name .. " install failed: " .. tostring(err)) end
    end
  end
end

local function standbyText()
  local ok, RomText = pcall(require, "src.core.game3.rom_text")
  local text = ok and RomText.plain("gText_LinkStandby") or nil
  if type(text) ~= "string" or text == "" then return nil end
  return text
end

function ArenaState.new(game, spec)
  local self = setmetatable({
    game = game,
    spec = spec or {},
    stage = "linking",
    frames = 0,
    result = nil,
    message = standbyText(),
    done = false,
    spectator = (spec and spec.role == "spectator") and true or false,
  }, ArenaState)
  installChrome()
  local ok, err = pcall(self.start, self)
  if not ok then self:fail(err) end
  return self
end

function ArenaState:start()
  local spec, game = self.spec, self.game
  local finish = function(result) self:finish(result) end
  if self.spectator then
    LB().startSpectator(spec, finish)
    return
  end
  if not spec.myParty then
    local ArenaBoot = require("src.online.ArenaBoot")
    local packed, why = ArenaBoot.packOwnParty(game, spec)
    if not packed then error(why or "no party to send") end
  end
  local RelayTransport = require("src.core.game3.link.relay_transport")
  local Game3Link = require("src.link.Game3Link")
  local transport = RelayTransport.new(spec.session, { client = spec.client })
  self.transport = transport
  local lb = LB()
  local link = Game3Link.attach(transport, {
    seat = spec.seat,
    seats = spec.seats,
    game = game,
    linkType = lb.arenaLinkType(lb.MODE_OF[spec.mode or "single"]),
  })
  Link().attach(link)
  lb.startArena(spec, finish)
end

function ArenaState:fail(reason)
  print("[arena3] the battle could not start: " .. tostring(reason))
  self.finished = true
  self.stage = "failed"
  self.frames = 0
  self.result = "error"
  self.message = Strings("The battle could not start.")
end

function ArenaState:finish(result)
  if self.finished then return end
  self.finished = true
  if not RESULTS[result] then result = "error" end
  self.result = result
  if result == "error" and self.stage == "linking" then
    self.stage = "failed"
    self.frames = 0
    self.message = Strings("The battle could not start.")
    return
  end
  self.stage = "leaving"
end

function ArenaState:leave()
  if self.done then return end
  self.done = true
  local result = self.result or "ended"
  if not self.spectator and (result == "win" or result == "lose" or result == "draw") then
    LB().report(result)
  end
  local onDone = self.spec.onDone
  if onDone then
    local ok, err = pcall(onDone, result)
    if not ok then print("[arena3] onDone failed: " .. tostring(err)) end
  end
  local B = Battle()
  if B.isActive() then B.abort("draw") end
  Link().closeLink("arena_done")
  local t = self.transport or (LB()._spec and LB()._spec.t)
  if t and t.leave then pcall(t.leave, t) end
  LB().reset()
  local game = self.game
  if game and type(game.leaveArena) == "function" then game:leaveArena() end
  if game and type(game.returnToLauncher) == "function" then
    game.returnToLauncher({ tab = "online" })
  end
end

function ArenaState:handleInput(input)
  if not input then return end
  local pressed = input.wasPressed and (input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start"))
  if self.stage == "failed" and pressed then
    self.stage = "leaving"
    return
  end
  if self.stage == "linking" and self.frames >= ArenaState.CANCEL_FRAMES and input.wasPressed and input:wasPressed("b") then
    self.result = "ended"
    self.stage = "leaving"
  end
end

function ArenaState:update(dt)
  self.frames = self.frames + 1
  local game = self.game
  self:handleInput(game and game.input)
  if self.stage == "failed" then
    if self.frames >= ArenaState.HOLD_FRAMES then self.stage = "leaving" end
    return
  end
  if self.stage == "leaving" then
    self:leave()
    return
  end
  local lb = LB()
  local B = Battle()
  local steps = 1
  if self.spectator and lb.spectatorBehind and lb.spectatorBehind() then steps = ArenaState.CATCH_UP_STEPS end
  for _ = 1, steps do
    if self.spectator then
      lb.update(dt)
    else
      Link().update(dt)
    end
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade.tick then Fade.tick(dt) end
    local okT, Task = pcall(require, "src.core.game3.task")
    if okT and Task.update then Task.update(dt) end
    if B.isActive() then
      self.stage = "battle"
      B.update(dt, game)
    end
    local Message = package.loaded["src.ui.game3.message"]
    if Message and Message.tick then Message.tick() end
    if self.stage == "leaving" then break end
  end
end

local function drawBox(text)
  local Chrome = require("src.ui.game3.chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Display = require("src.core.game3.display")
  love.graphics.clear(0, 0, 0, 1)
  if not text or text == "" then return end
  Chrome.dialogueFrame()
  local x = Chrome.DLG_LEFT * Display.TILE
  local y = Chrome.DLG_TOP * Display.TILE + 1
  local wrapped = FrlgFont.wrap(text, Chrome.DLG_W * Display.TILE) or text
  local i = 0
  for line in (wrapped .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    if i > 2 then break end
    FrlgFont.draw(line, x, y + (i - 1) * 16, { colors = FrlgFont.COLOR.NORMAL })
  end
end

function ArenaState:draw(w, h)
  local Display = require("src.core.game3.display")
  local B = Battle()
  if B.isActive() then
    Display.present(self.game, w, h)
    return
  end
  local text = self.message
  if self.stage == "leaving" then text = nil end
  Display.presentUi(self.game, w, h, "boot", function() drawBox(text) end)
end

return ArenaState

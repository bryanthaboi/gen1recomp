-- Central game object: owns the data, renderer, input, state stack, world
-- and save state.  Everything else reaches shared services through here.

local Data = require("src.core.Data")
local FixedStep = require("src.core.FixedStep")
local Input = require("src.core.Input")
local Logger = require("src.core.Logger")
local Renderer = require("src.render.Renderer")
local GameViewport = require("src.render.GameViewport")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TouchControls = require("src.core.TouchControls")
local GamepadMap = require("src.core.GamepadMap")
local ModLoader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")

local Game = {}

local function renderVisible(stack, state)
  return state and (not stack.renderVisible or stack:renderVisible(state))
end

-- Vanilla defaults for ModRuntime.call, hoisted to module level: called from
-- the 60Hz logic step / per-frame speed resolution, an inline closure here
-- allocated a fresh function every tick for no behavioral gain.
local function noop() end
local function resolveLogicSpeedVanilla(g) return g:_resolveLogicSpeed() end

-- dev-mode gate for the F5/backtick hotkeys; false keeps every src/dev
-- module unloaded, so a player boot never touches a byte of dev code
local devMode = os.getenv("POKEPORT_DEV") == "1" or _G.POKEPORT_DEV_MODE == true

-- the boot screen ids (field.boot.screens); a plain function so the
-- headless harness can borrow makeTitleState onto a stub game
local function bootScreens(game)
  local boot = game.data and game.data.field and game.data.field.boot
  return (boot and boot.screens) or {}
end

function Game:load(opts)
  opts = opts or {}
  local arena = opts.arena
  self.data = Data
  self.sessionStartedAt = os.time()
  Data:load()

  -- Mods are a native engine subsystem.  They load after the verified ROM
  -- data exists, so mods can register or override the same definitions that
  -- the rest of the game consumes.  A broken mod is reported and skipped by
  -- the loader without preventing the base game from booting.
  self.mods = ModLoader.new()
  if arena then
    self.mods:load(Data, {
      mode = (arena.profile and arena.profile.kind == "cart")
        and "cartOnly" or "disableAll",
      cartId = opts.cartId,
    })
  else
    self.mods:load(Data)
  end
  self.modStatus = self.mods:status()
  -- render pipelines dispatch off the merged dataset; point them at the
  -- one the mods just merged into before anything can draw a frame
  require("src.render.Pipelines").install(Data)
  -- Same reason, same moment: TypeChart caches the merged type records in an
  -- upvalue, and until now only BattleState loaded it, on entering a battle.
  -- Every non-battle reader of a type -- the summary screen's TYPE1/TYPE2
  -- rows, the move-select TYPE/ box -- ran against an unloaded module and got
  -- the raw id back instead of the display name, so a translation could not
  -- reach them. Loading here means a type reads the same whoever asks first.
  require("src.battle.TypeChart").load(Data)

  self.input = Input
  Input:init()

  self.touchControls = TouchControls
  TouchControls:init()
  TouchControls:setHotkeyHandler(function(action, pressed)
    self:touchSkinHotkey(action, pressed)
  end)

  self.renderer = Renderer
  Renderer:init()

  require("src.render.Font").load(Data)
  -- menu cursor/border/geometry constants; field.theme restyles them
  require("src.ui.Theme").load(Data)
  -- the engine's own text, after the merge so a translation mod's catalog
  -- is already in Data.strings; empty on a mod-free boot and skipped
  require("src.core.Strings").load(Data)

  self.stack = StateStack
  StateStack:init()

  self.save = SaveData.newGame(self:bootConfig())
  -- seed=true keeps what entry chunks wrote through mod.save before any
  -- save existed; the skeleton fires save.created exactly once
  self:adoptSave(self.save, true)
  ModRuntime.emit("save.created", { save = self.save })
  -- apply the persisted audio + display options before anything plays
  self:applyOptions(self.save.options)

  FixedStep:init(function(step) self:step(step) end)
  self.fixedStep = FixedStep

  local OverworldState = require("src.world.OverworldController")
  self.overworld = OverworldState

  -- Discord Rich Presence: map name / battle status on the player's profile.
  -- Soft-fail: missing Discord / IPC errors must never block boot.
  pcall(function() require("src.core.DiscordPresence").init(self) end)

  -- every service is up but nothing is on the stack yet; this payload is
  -- the sanctioned way for a mod to obtain the Game object
  ModRuntime.emit("game.ready", { game = self })

  -- boot into the title screen (engine/movie/title.asm); NEW GAME runs
  -- the Oak speech + naming, CONTINUE restores the save.  The headless
  -- autopilot skips straight into the overworld.
  if arena then
    self:enterArena(arena)
  elseif os.getenv("POKEPORT_AUTOPILOT") then
    StateStack:push(OverworldState, self.save.player.map,
                    self.save.player.x, self.save.player.y, self.save.player.facing)
  else
    local titleState = self:makeTitleState()
    -- the copyright splash + attract movie plays before the title
    -- (engine/movie/splash.asm + intro.asm; Yellow swaps in its own
    -- 18-scene movie, engine/movie/intro_yellow.asm); the ids come from
    -- field.boot.screens so a total conversion owns the whole boot
    local splash = require("src.core.GameVersion").isYellow()
      and "YellowIntro" or "IntroMovie"
    Screens.push(self, bootScreens(self).splash or splash, function()
      StateStack:push(titleState)
    end)
  end

  Logger.info("game loaded")
  -- Scaling bug reports (#87, #208) are unanswerable without these three
  -- numbers: LOVE units, drawable pixels, and the integer physical pixels
  -- per GB pixel the renderer settled on.  Cheap, once, and it turns "it
  -- looks stretched" into something reproducible.
  if love.graphics and love.graphics.getDimensions then
    local ww, wh = love.graphics.getDimensions()
    local pw, ph = ww, wh
    if love.graphics.getPixelDimensions then
      pw, ph = love.graphics.getPixelDimensions()
    end
    Logger.info(string.format(
      "display: %dx%d units, %dx%d px, fit scale %d px/GB px",
      ww, wh, pw, ph, Renderer:fitScale()))
  end
end

-- the merged field.boot: spawn, names, money and the naming presets a
-- total conversion overrides.  Threaded into SaveData so persistence stays
-- free of a Data dependency.
function Game:bootConfig()
  local boot = self.data and self.data.field and self.data.field.boot
  -- stamp the running game version onto the boot config so a New Game records
  -- it (SaveData.newGame reads boot.version); this is what routes a Blue
  -- playthrough to save_blue.lua and Blue's version-gated content
  if boot then boot.version = require("src.core.GameVersion").get() end
  return boot
end

-- NEW GAME, as a call: a fresh skeleton (through save.new_game, so a mod
-- can reshape it), the overworld at the skeleton's spawn, and the intro
-- screen on top.  The title menu's NEW GAME row is this; a mod that starts a
-- game on its own terms -- a match, a challenge mode -- calls it directly.
--
-- opts.intro = false skips the newGame screen (Oak's speech) so the player
-- lands straight in the world; the skeleton then has to carry a name and a
-- party, which is the caller's job via save.new_game.
function Game:startNewGame(opts)
  local OverworldState = require("src.world.OverworldController")
  while self.stack:top() do self.stack:pop() end
  -- New Game keeps the standalone options.lua preferences
  self.sessionStartedAt = os.time()
  self.save = SaveData.newGame(self:bootConfig())
  -- no bucket carry-over: mod state from an abandoned session must
  -- not leak into a fresh slot; mods seed via save.created instead
  self:adoptSave(self.save)
  ModRuntime.emit("save.created", { save = self.save })
  self:applyOptions(self.save.options)
  self.stack:push(OverworldState, self.save.player.map,
                  self.save.player.x, self.save.player.y,
                  self.save.player.facing,
                  { via = "boot", freshBoot = true })
  if not (opts and opts.intro == false) then
    Screens.push(self, bootScreens(self).newGame or "OakSpeech",
                 function() end)
  end
end

function Game:enterArena(spec)
  local version = require("src.core.GameVersion").get()
  if spec.slotId then pcall(SaveData.setActiveSlot, version, spec.slotId) end
  local loaded = SaveData.load()
  if loaded then
    local activeMods = self.modStatus and self.modStatus.loaded
    SaveData.runMigrations(loaded, self.mods and self.mods.migrations, activeMods)
    self.saveReport = SaveData.validate(loaded, self.data)
    self.save = loaded
    loaded.startMenuIndex = nil
    self.startMenuIndex = nil
    self:adoptSave(loaded)
    self:applyOptions(loaded.options)
    local stamp = require("src.battle.BattleState").stampOT
    for _, mon in ipairs(loaded.party or {}) do stamp(loaded, mon) end
  else
    Logger.warn("arena: save slot %s could not be loaded", tostring(spec.slotId))
  end
  self.linkSession = true
  StateStack:push(require("src.ui.ArenaState").new(self, spec))
end

-- the title screen with its NEW GAME / CONTINUE wiring; used at boot
-- and by the START-menu QUIT confirmation
function Game:makeTitleState()
  local OverworldState = require("src.world.OverworldController")
  local factory = Screens.get(self, bootScreens(self).title or "TitleState")
  local title = factory.new(self, {
    onNewGame = function() self:startNewGame() end,
    onContinue = function()
      local loaded, recovered = SaveData.load()
      if loaded then
        self:restoreSave(loaded, recovered,
                         { freshBoot = true, continued = true })
      end
    end,
    onExit = self.onExit,
  })
  title.screenId = title.screenId or "TitleState"
  return title
end

-- QUIT from the START menu: back to the title like a power-cycle,
-- unsaved progress discarded.  TitleState:enter restarts the title
-- theme; stop() keeps the map song from bleeding over in the meantime.
function Game:returnToTitle()
  require("src.core.Music").stop()
  while self.stack:top() do self.stack:pop() end
  self.stack:push(self:makeTitleState())
end

Game.SKIN_FAST_FORWARD = 4

function Game:touchSkinHotkey(action, pressed)
  if action == "fast_forward_hold" then
    if pressed then
      self.skinSpeedSaved = self.speedOverride
      self.speedOverride = Game.SKIN_FAST_FORWARD
    else
      self.speedOverride = self.skinSpeedSaved
      self.skinSpeedSaved = nil
    end
  elseif action == "fast_forward_toggle" then
    if pressed then self:_cycleSpeed(1) end
  elseif action == "soft_reset" then
    if pressed then
      Input:reset()
      TouchControls:reset()
      self:returnToTitle()
    end
  elseif action == "menu" then
    if pressed then
      local Screens = require("src.ui.Screens")
      local top = self.stack and self.stack:top()
      if top and not top.isTouchSkinMenu then
        local state = Screens.build(self, "OptionsMenu")
        if state then
          state.isTouchSkinMenu = true
          self.stack:push(state)
        end
      end
    end
  end
end

function Game:breakLink(err, source)
  if source == "engine" then
    Logger.error("link: engine error, link torn down\n%s", tostring(err))
  else
    Logger.error("link: torn down after an error\n%s", tostring(err))
  end
  self.linkSession = nil
  local net = self.linkNet
  self.linkNet = nil
  if net then pcall(net.close, net) end
  pcall(ModRuntime.emit, "link.ended", { reason = "error" })
  local stack = self.stack
  local guard = 0
  while #stack.states > 1 and stack:top() ~= self.overworld and guard < 64 do
    guard = guard + 1
    pcall(stack.pop, stack)
  end
  pcall(function()
    local Strings = require("src.core.Strings")
    local TextBox = require("src.render.TextBox")
    stack:push(TextBox.new(self, source == "engine"
      and Strings("Something broke\nduring the link.")
      or Strings("The link was\nbroken.")))
  end)
end

function Game:step(dt)
  -- Tool mods (autoplay, accessibility drivers, input visualizers) act on
  -- the same fixed-step boundary as a physical controller.  Run them before
  -- Input:step promotes queued edges so a button chosen here is visible to
  -- this logic tick, not one tick later.  With no wrapper this is a no-op.
  ModRuntime.call("input.step", noop, self, dt)
  self.input:step()
  -- A+B+SELECT+START held for 16 steps: SoftReset (home/init.asm) stops the
  -- audio, whites the palettes out and falls through into Init, i.e. the
  -- power-on boot, so everything unsaved is gone and the title sequence
  -- comes back -- exactly what returnToTitle does for the START menu's QUIT.
  -- The check lives here, above stack:update, so it fires from any state:
  -- overworld, battle, a menu or a cutscene, the way _Joypad's does (#563).
  -- Input:reset clears the four still-physically-held buttons so the title
  -- screen does not read A as a menu choice on its first frame.
  -- a tool mod (or a harness) may hand Game a stand-in input with no
  -- chord bookkeeping; those simply never soft reset
  if self.input.softResetStep and self.input:softResetStep() then
    Input:reset()
    TouchControls:reset()
    self:returnToTitle()
    return
  end
  -- serviced unconditionally: a link battle's ENet transport must not
  -- stall just because PartyMenu/ChoiceBox/NamingScreen is temporarily
  -- on top of BattleState (see LinkBattle.new)
  if self.linkNet and not self.linkNet.closed then
    local ok, err = pcall(self.linkNet.update, self.linkNet)
    if not ok then
      self:breakLink(err, "transport")
      return
    end
  end
  if self.linkSession or self.linkNet then
    local ok, err = xpcall(function() self.stack:update(dt) end,
      function(e) return debug.traceback(tostring(e), 2) end)
    if not ok then
      self:breakLink(err, "engine")
      return
    end
  else
    self.stack:update(dt)
  end
  -- play time for the trainer card / save screen
  self.save.playTime = (self.save.playTime or 0) + dt
  -- Music.update is NOT serviced here: it decrements fade counters and
  -- drives ChipAudio once per call, so running it inside the logic step
  -- would pitch music and sfx up under fast-forward. Game:update advances
  -- it on its own real-time 60Hz accumulator instead.
end

-- The per-category (RFC 0007) save.options multiplier for whichever of
-- "battle"/"overworld"/"menu" Game.speedCategoryInStack says is active
-- right now.  This is the "vanilla" the core.logic_speed hook wraps below
-- -- Game:logicSpeed calls it AFTER the link and speedOverride checks, so
-- neither a mod nor the category resolution ever has a seam to defeat them.
function Game:_resolveLogicSpeed()
  local GameSpeed = require("src.core.GameSpeed")
  local category = Game.speedCategoryInStack(self.stack)
  local key = GameSpeed.optionKey(category)
  local opts = self.save and self.save.options
  return GameSpeed.clamp(opts and opts[key] or GameSpeed.DEFAULT)
end

-- The logic multiplier for this frame. Read live rather than cached so the
-- Options rows take effect immediately; speedOverride is the --speed /
-- POKEPORT_SPEED run argument, which wins over the saved option so a bot
-- or screenshot run does not depend on whatever the player last chose.
function Game:logicSpeed()
  local GameSpeed = require("src.core.GameSpeed")
  -- Link play is always 1X on both machines, and this wins over every other
  -- source including POKEPORT_SPEED and every per-category option.
  -- Fast-forward multiplies the logic clock, so a peer at 10X burned a
  -- tournament shot clock ten times faster than the opponent it is racing,
  -- and drove its own animation/message queue at a different rate than the
  -- peer it is locked to.  Nothing about a match should depend on what
  -- either player set this to -- checked here, before the core.logic_speed
  -- hook ever runs, so a mod cannot defeat it either.
  if self.linkSession or (self.linkNet and not self.linkNet.closed) then
    return 1
  end
  if Game.isFixedSpeedInStack and Game.isFixedSpeedInStack(self.stack) then
    return 1
  end
  if self.speedOverride then return GameSpeed.clamp(self.speedOverride) end
  -- Clamp here too, not just in _resolveLogicSpeed's vanilla path: a mod's
  -- core.logic_speed hook can return anything (0, negative, nil, NaN) and
  -- Hooks:call only guards against a hook that throws, not one that
  -- returns a bad value, so an unclamped result would flow straight into
  -- the FixedStep accumulator math below and freeze or destabilize logic.
  return GameSpeed.clamp(ModRuntime.call("core.logic_speed",
    resolveLogicSpeedVanilla, self))
end

function Game:update(dt)
  -- Fast-forward scales only the logic clock (see src/core/GameSpeed.lua).
  -- Give the accumulator room for one full frame at the current speed,
  -- or the anti-spiral clamp quietly caps every level above ~15X.
  local speed = self:logicSpeed()
  FixedStep.maxAccum = FixedStep.catchupLimit(speed)
  FixedStep:update(dt, speed)
  -- Audio runs off real time at a fixed 60Hz regardless of game speed or
  -- display refresh, so fades and chip synthesis keep their intended tempo
  -- whether we are at 1X, 10X, or running with vsync disabled.  One-shot
  -- SFX stay at natural pitch too (#1990/#1991/#1997).
  local step = FixedStep.STEP
  self.audioAccum = math.min((self.audioAccum or 0) + dt, 0.25)
  while self.audioAccum >= step do
    self.audioAccum = self.audioAccum - step
    require("src.core.Music").update(Data)
  end
  -- Overworld tilt toggle tween: presentational, so it runs on the real
  -- frame dt (not the fixed logic step) for a smooth ~0.25s glide.
  require("src.render.Tilt").update(dt)
  -- mod render pipelines tween on the same real-frame clock, for the same
  -- reason: they are presentational, so fast-forward must not speed them up
  require("src.render.Pipelines").update(dt)
  pcall(function() require("src.core.DiscordPresence").update(dt) end)
  self:updateSync(dt)
  -- Steady-state memory backstop: advance the incremental collector one
  -- small step every few rendered frames.  The heavy GPU objects are now
  -- freed explicitly (map eviction, battle exit, canvas/renderer swaps), so
  -- this only has to keep ordinary Lua-heap garbage (per-frame tables) from
  -- drifting upward over a long session, and to spread collection out so the
  -- default lazy schedule never batches it into a visible pause.  Every 4th
  -- frame (not every frame) so the stepping itself does not compete with
  -- the frame budget on weak single-core handhelds.
  self.gcStepFrame = (self.gcStepFrame or 0) + 1
  if collectgarbage and self.gcStepFrame % 4 == 0 then collectgarbage("step", 1) end
end

-- render.zones' identity default: unhooked, the zone list reaches the blit
-- exactly as the owning state computed it
local function sameZones(_, zones) return zones end

-- Dim alpha for a BATTLE BG "world" battle anywhere in the stack, or nil.
-- Same whole-stack rule as fillScaleInStack: a party menu or text box opened
-- during the battle must not drop the dim for a frame.
function Game.worldBgBattleDim(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.bgMode and state:bgMode() == "world" then
      -- The extended fixed HUD intentionally exposes the live world across
      -- the whole physical window.  Keep this as a world-backed battle (zero
      -- is non-nil, so scaling and overlay holds remain active), but do not
      -- paint the standard dim veil around the native battle rectangle.
      if state.extendedWorldHUD and state:extendedWorldHUD() then
        return 0
      end
      return state.BG_WORLD_DIM or 0.55
    end
  end
  return nil
end

-- Does the stack contain the opt-in fixed Extended WORLD battle?  Renderer
-- uses this separately from battleDim: the world remains the surround, while
-- the native-width battle field receives a paper backing from top to bottom.
function Game.extendedWorldHUDInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.extendedWorldHUD and state:extendedWorldHUD() then
      return true
    end
  end
  return false
end

-- Is a BATTLE BG "world" battle composing itself over the live map right now?
-- Same whole-stack walk as worldBgBattleDim, asked for a different reason: the
-- dark-cave shade shift (wMapPalOffset) must not reach a frame a battle is
-- drawing in.  InitBattleCommon (engine/battle/core.asm) pushes wMapPalOffset,
-- InitBattleVariables (engine/battle/init_battle_variables.asm) writes 0 over
-- it and core.asm pops it back when the battle ends, so a battle in an
-- un-flashed Rock Tunnel is lit on hardware.  Every other BATTLE BG gets that
-- for free -- no map draws beneath an opaque battle, so nothing re-arms the
-- per-frame shade map -- but "world" keeps the overworld drawing underneath,
-- and its arming then darkened the battle's own pics, HUD and text at colorize
-- time (#773).
function Game.worldBgBattleInStack(stack)
  return Game.worldBgBattleDim(stack) ~= nil
end

-- Does anything on the stack want the surface scaled to FILL the window
-- (aspect preserved, bars on the long axis) rather than sit at the fixed
-- integer scale?
--
-- Asked of the WHOLE stack, not just the top.  For BATTLE SIZE "fill" that is
-- because the party menu, bag and text boxes a battle opens must not snap the
-- surface back to the fixed scale for a frame; the title screen and intro want
-- it unconditionally, since neither has a world behind it and neither has any
-- reason to sit in a small box in the middle of a large window.
function Game.fillScaleInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.wantsFillScale and state:wantsFillScale() then
      return true
    end
  end
  return false
end

-- A wide battle owns the surface until it leaves the stack.  The party,
-- bag, choice and text states it opens still draw their original 160px UI,
-- but the canvas must not snap to 160px between those states.
function Game.wideBattleInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.isWideBattleLayout and state:isWideBattleLayout() then
      return state
    end
  end
  return nil
end

-- Which of "battle"/"overworld"/"menu" per-category GAME SPEED (RFC 0007)
-- applies right now. Whole-stack, the same idiom as fillScaleInStack/
-- wideBattleInStack above: an overlay with neither marker (PartyMenu,
-- ChoiceBox, a NamingScreen, a text box) is transparent to the walk and
-- inherits whatever is under it, making the category a property of the
-- STACK POSITION the overlay sits over, not of the overlay itself. A
-- scripted sequence (script.started/ended) never pushes a state of its
-- own either -- it runs through the owning overworld/battle state's own
-- script runner or message queue -- so it inherits the same way. Nothing
-- identifying as either (the title screen, credits, an intro cutscene
-- with nothing under it) falls to "menu", the bucket every non-gameplay
-- screen gets; see the RFC's Decisions section for the full reasoning.
function Game.speedCategoryInStack(stack)
  local states = stack and stack.states
  for i = #(states or {}), 1, -1 do
    local state = states[i]
    if state and state.isBattle then return "battle" end
    if state and state.isOverworld then return "overworld" end
  end
  return "menu"
end

function Game.isFixedSpeedInStack(stack)
  local states = stack and stack.states
  for i = #(states or {}), 1, -1 do
    local state = states[i]
    if state and (state.isFixedSpeed or state.isMinigame) then return true end
  end
  return false
end

-- Whether a state on the stack composes its own screen and so wants the
-- edge anchors held off (BattleState.holdsUIAnchors).  Whole-stack, like
-- everything else here: the text box and YES/NO a battle puts up are states
-- of their own sitting above it, and they are exactly the elements that must
-- stay inside the battle's composition rather than dock to the window.
-- UI LAYOUT: is edge docking switched on?  Only the explicit "dynamic" turns
-- it on, so a save written before the option existed -- and any caller with no
-- save at all, which is most of the headless suites -- gets CENTERED, the
-- behaviour the port shipped with.
function Game.dynamicUI(save)
  local options = save and save.options
  return options ~= nil and options.uiLayout == "dynamic"
end

function Game.uiAnchorsHeldInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.holdsUIAnchors then return true end
  end
  return false
end

-- Where Game:draw starts drawing this frame.  Normally the topmost opaque
-- state (StateStack:visibleBase) -- but an opaque menu pushed over a WIDE
-- battle must not prevent that battle from drawing.  Native WIDE battles own
-- the 304x144 surround around a centred classic menu, while external arena
-- providers establish their window-sized scene from BattleState:draw.  If the
-- menu becomes the draw base, neither owner runs and the menu's white field
-- replaces the whole presentation.  BATTLE BG "world" additionally needs the
-- overworld below the battle, as before.
--
-- Only the START of the draw moves.  The clear stays keyed to the real
-- visibleBase, so the menu still gets its opaque canvas and draws exactly as
-- before; what changes is the window AROUND its letterbox, which keeps
-- showing the map instead of going black.  Both menus fill their own
-- 160x144 field first, so nothing beneath them shows through it.
function Game.drawBaseInStack(stack, visibleBase)
  local states = stack and stack.states or {}
  for i = visibleBase - 1, 1, -1 do
    local state = states[i]
    local worldBattle = state and state.bgMode and state:bgMode() == "world"
    local wideBattle = state and state.isWideBattleLayout
      and state:isWideBattleLayout()
    if worldBattle or wideBattle then
      -- restart the search from under the battle: the highest opaque state at
      -- or below it (the battle itself for white/black WIDE, the overworld for
      -- a non-opaque world-backed battle), not the menu sitting over it
      for j = i, 1, -1 do
        if states[j].isOpaque then return j end
      end
      return 1
    end
  end
  return visibleBase
end

-- A classic overlay above the approved world-backed extended HUD paints only
-- its centred area. Keep the wider owner surface transparent so its margins
-- continue to reveal the world instead of becoming an opaque white sheet.
function Game.uiCanvasTransparent(worldBelow, worldDrawn, wideBattle)
  return worldBelow or (worldDrawn and wideBattle ~= nil
    and wideBattle.extendedHUD and wideBattle:extendedHUD())
end

-- Shift classic SGB zones to the centred UI. A full-width base zone extends
-- into both margins, keeping the canvas' paper color continuous; narrower
-- sprite and status zones move with the classic UI content.
local function centerClassicZones(zones, offset)
  if not zones or offset == 0 then return zones end
  local shifted = {}
  for i, zone in ipairs(zones) do
    local copy = {}
    for key, value in pairs(zone) do copy[key] = value end
    if copy.x == 0 and copy.w == Renderer.WIDTH then
      copy.w = copy.w + offset * 2
    else
      copy.x = (copy.x or 0) + offset
    end
    shifted[i] = copy
  end
  return shifted
end

function Game:draw()
  GameViewport.begin(1)
  -- the UI canvas clears transparent when the overworld's world pass
  -- shows through beneath it; opaque full-screen states get the classic
  -- white clear
  local base = self.stack:visibleBase()
  local worldBelow = self.stack.states[base] == self.overworld
  -- a world-bg battle keeps the map drawing under whatever it opened, so the
  -- world pass can run for a frame whose CLEAR is still an opaque menu's
  local drawFrom = Game.drawBaseInStack(self.stack, base)
  local worldDrawn = self.stack.states[drawFrom] == self.overworld
  -- A wide battle holds its 304px surface through every menu or prompt it
  -- opens. States that do not draw the wide battle composition are centred
  -- in that surface below, so their classic coordinates and hit testing stay
  -- unchanged. Outside a battle, including the title screen, the option is
  -- intentionally inactive because it is a battle-layout setting.
  local top = self.stack:top()
  local wideBattle = Game.wideBattleInStack(self.stack)
  local classicOffset = 0
  if wideBattle and wideBattle.uiSize then
    Renderer:setUISize(wideBattle:uiSize())
    classicOffset = math.floor((select(1, Renderer:uiSize()) - Renderer.WIDTH) / 2)
  elseif top and top.uiSize then
    Renderer:setUISize(top:uiSize())
  else
    Renderer:setUISize(Renderer.WIDTH, Renderer.HEIGHT)
  end
  -- BATTLE SIZE: scale the battle surface to the window instead of the
  -- classic integer letterbox.  Read from the whole stack, not just the top,
  -- so a party menu or text box opened mid-battle keeps the same surface.
  Renderer.uiFill = Game.fillScaleInStack(self.stack)
  -- BATTLE BG "world": dim the overworld the battle is drawn over.  Read off
  -- the stack for the same reason as uiFill above -- a prompt opened during
  -- the battle must not drop the dim for a frame.
  Renderer.battleDim = Game.worldBgBattleDim(self.stack)
  Renderer.extendedWorldBand = Game.extendedWorldHUDInStack(self.stack)
  -- ...and for the same reason the UI's own scale has to know the world is
  -- still the backdrop while an opaque menu covers it.  Renderer:uiScale
  -- steps the UI down with the survey zoom only while a world is behind it,
  -- gated on this frame's world pass -- which the party menu ends by being
  -- opaque (the bag's item box shows the map around it, #1521).  Without
  -- this hold it loses the step-down and blits at full fit scale over a
  -- battle drawn at the zoomed-out one.
  Renderer.uiWorldHold = Renderer.battleDim ~= nil
  -- ...and a battle keeps its dialogue box and YES/NO inside its own screen
  -- instead of letting them dock to the window edge.
  -- UI LAYOUT: CENTERED (the default) is a fixed letterbox -- every element
  -- stays inside the 160x144 canvas and the UI does not follow the survey
  -- zoom, so the screen furniture never moves or resizes under the player.
  -- That is the composition the port shipped with.  DYNAMIC opts into both
  -- halves: the dialogue box docks to the window's bottom edge, the START
  -- menu to its top right, and the whole UI steps down with the zoom.
  Renderer.uiCentered = not Game.dynamicUI(self.save)
  Renderer.uiAnchorHold = Game.uiAnchorsHeldInStack(self.stack)
  Renderer:beginFrame(Game.uiCanvasTransparent(
    worldBelow, worldDrawn, wideBattle))
  for i = drawFrom, #self.stack.states do
    local state = self.stack.states[i]
    local wideState = state and state.isWideBattleLayout
      and state:isWideBattleLayout()
    if renderVisible(self.stack, state) and state.draw then
      if classicOffset ~= 0 and not wideState then
        love.graphics.push()
        love.graphics.translate(classicOffset, 0)
        -- a classic state reports its trueColor rects in its own 160x144
        -- coordinates, so they take the same shift its pixels just got --
        -- centerClassicZones already does exactly this to its zone list,
        -- and without the pair the unshaded re-blit misses the pic (#637)
        local P = require("src.render.PaletteFX")
        P.setMarkOffset(classicOffset)
        state:draw()
        P.setMarkOffset(0)
        love.graphics.pop()
      else
        state:draw()
      end
    end
  end
  -- SGB colorization: the topmost state that knows its palette owns the
  -- screen (overlays like text boxes inherit from what's beneath them);
  -- the overworld's world pass colors each visible map area separately
  local zones, worldZones, zoneOwner
  for i = #self.stack.states, 1, -1 do
    local s = self.stack.states[i]
    if renderVisible(self.stack, s) and s.sgbPalettes then
      zones = s:sgbPalettes(self)
      zoneOwner = s
      break
    end
  end
  if classicOffset ~= 0 and zoneOwner
      and not (zoneOwner.isWideBattleLayout
               and zoneOwner:isWideBattleLayout()) then
    zones = centerClassicZones(zones, classicOffset)
  end
  -- 14's render.zones: weather/lighting overlays and custom colorization
  -- recolor or add zones before the blit
  if ModRuntime.wantsHook("render.zones") then
    zones = ModRuntime.call("render.zones", sameZones, self, zones)
  end
  -- Keyed to whether the map actually DREW, not to whether it is the clear's
  -- base: an opaque menu over a world-bg battle still renders the world pass
  -- (drawBaseInStack), and leaving worldZones nil there drops endFrame's
  -- world blit onto the UI zone list instead -- the party menu's own HP-bar
  -- palettes, in 160x144 space, smeared across a world-canvas-sized image.
  -- That is the offset, red-for-green map behind the menu.
  if worldDrawn and self.overworld.sgbWorldZones then
    worldZones = self.overworld:sgbWorldZones()
  end
  local viewport = Renderer:endFrame(zones, worldZones)
  -- Persistent tool status is screen-space UI: draw it over the completed
  -- render pipeline with exact playfield/margin geometry, but below mobile
  -- controls. It never becomes an updating game state.
  if ModRuntime.wantsHook("render.hud") then
    ModRuntime.call("render.hud", function() end, self, viewport)
  end
  GameViewport.finish(self)
  -- OS-window chrome: keep the pad full-size and above any composed companion
  -- view instead of capturing and shrinking it with the game viewport.
  TouchControls:draw()
end

-- overworld survey zoom: wheel up / '=' zooms in, wheel down / '-' out
function Game:zoomStep(delta)
  local Zoom = require("src.render.Zoom")
  if not Zoom.gateOK(self.stack:top(), self.overworld) then return end
  local offset = Zoom.step(delta, Renderer:fitScale())
  if self.save and self.save.options then
    self.save.options.zoom = offset
    self:writeOptions()
  end
end

-- RFC 0020: input.wheel is a plain observer, contract-identical to
-- input.pointer -- nothing else depends on suppressing a wheel event, so
-- there is no real behavior to gate here, only to watch.
function Game:wheelmoved(_, dy)
  local function vanilla()
    if dy > 0 then
      self:zoomStep(1)
    elseif dy < 0 then
      self:zoomStep(-1)
    end
  end
  if not ModRuntime.wantsHook("input.wheel") then return vanilla() end
  return ModRuntime.call("input.wheel", vanilla, self, dy)
end

function Game:_cycleSpeed(dir)
  if not (self.save and self.save.options) then return end
  local busy
  local ow = self.overworld
  if ow then
    local top = self.stack:top()
    busy = ow.transitioning
      or (top == ow and (
           (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
        or (ow.scriptMoves and #ow.scriptMoves > 0)
        or ow.engaging or ow.emote))
  end
  if busy then return end
  -- Cycles whichever category Game.speedCategoryInStack says is active
  -- right now (RFC 0007) -- pressing the hotkey during a battle speeds up
  -- just the battle, on the overworld just the walk, in a menu just the
  -- menu. A single physical control that means "speed up whatever I'm
  -- looking at right now" needs no new UI and matches what a player
  -- pressing it mid-battle almost certainly wants.
  local GameSpeed = require("src.core.GameSpeed")
  local key = GameSpeed.optionKey(Game.speedCategoryInStack(self.stack))
  self.save.options[key] = GameSpeed.cycle(self.save.options[key], dir)
  self:writeOptions()
end

-- RFC 0020: input.key fires before ANY of this method's own logic runs --
-- including the top-of-stack capture two lines down, which is itself an
-- engine-owned "first refusal" system (BindingsMenu et al). This mirrors
-- the exact precedence a mod had before the sandbox changes (commit
-- 83682f01), when a mod's Lua chunk ran with the real, unsandboxed love.*
-- globals and could simply reassign love.keypressed itself -- there was
-- nothing an engine-internal capture could do to go first, because the mod
-- WAS the entry point. `vanilla` below is this method's entire pre-RFC-0020
-- body, unchanged; a mod that returns without calling `next(...)` prevents
-- every bit of it -- the stack capture, every hotkey, Input:keypressed --
-- from running for this key at all, same as the old global override always
-- could. See RFC 0020's Motivation section for the comparison this was
-- cross-referenced against.
function Game:keypressed(key)
  local function vanilla()
    if self.stack and self.stack:top() and self.stack:top().onKeyPressed then
      self.stack:top():onKeyPressed(key)
      return
    end
    if devMode and key == "f5" then
      require("src.dev.HotReload").run(self)
      return
    end
    if devMode and key == "`" then
      self.stack:push(require("src.dev.Console").new(self))
      return
    end
    if key == "f10" then
      -- toggle: the manager no longer swallows the keyboard, so a second
      -- press reaches this branch and closes it instead of stacking another
      local top = self.stack:top()
      if top and top.screenId == "ManagerState" then
        self.stack:pop()
      else
        Screens.push(self, "ManagerState")
      end
      return
    end
    if key == "f1" then
      if not self:quickSaveAllowed() then return end
      self:writeSave()
      return
    elseif key == "f2" then
      if not self:quickSaveAllowed() then return end
      local loaded, recovered = SaveData.load()
      if loaded then
        -- F2 jumps straight to the loaded save's map/position, with no
        -- walking transition -- a hard state teleport like Continue, not a
        -- smooth warp -- whether pressed at the title screen or mid-session.
        self:restoreSave(loaded, recovered, { freshBoot = true })
      end
      return
    elseif key == "-" then
      self:zoomStep(-1)
      return
    elseif key == "=" then
      self:zoomStep(1)
      return
    elseif key == "1" then
      -- cycle GAME SPEED (0.25X → 200X, logic only; audio unaffected);
      -- shoulders/triggers on gamepad do the same (see gamepadpressed)
      self:_cycleSpeed(1)
      return
    elseif key == "2" then
      -- cycle COLORS (GBC / OG / OG INV / GBC INV / CLASSIC); the pack change
      -- forces Game.overworld:reloadMap, which rebuilds the live NPC array, so
      -- hold it while a warp/transition or an on-screen scripted cutscene is
      -- driving the overworld rather than tear the escort's NPCs out mid-move
      local ow = self.overworld
      local top = self.stack:top()
      local busy = ow and (ow.transitioning
        or (top == ow and (
             (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
          or (ow.scriptMoves and #ow.scriptMoves > 0)
          or ow.engaging or ow.emote)))
      if not busy then
        local PaletteFX = require("src.render.PaletteFX")
        self.save.options.colors = PaletteFX.cycleMode()
        self:writeOptions()
      end
      return
    elseif key == "3" then
      -- cycle TILT OFF → 15 → 35 → 50 → OFF (mnemonic: 3D), free-roam only
      local Tilt = require("src.render.Tilt")
      if Tilt.gateOK(self.stack:top(), self.overworld) then
        self.save.options.tilt = Tilt.cycle()
        self:writeOptions()
      end
      return
    elseif key == "4" then
      -- cycle ZOOM through every integer level (survey → FIT → close-up → wrap)
      local Zoom = require("src.render.Zoom")
      if Zoom.gateOK(self.stack:top(), self.overworld) then
        self.save.options.zoom = Zoom.cycle(Renderer:fitScale())
        self:writeOptions()
      end
      return
    end
    -- Mod render pipelines claim their hotkeys last, so one can never shadow
    -- an engine display key however a mod declares it (12 §rendering
    -- pipelines).  syncOptions writes the whole ladder back, including the
    -- tilt exclusion a world pipeline forces.
    local Pipelines = require("src.render.Pipelines")
    if Pipelines.hotkey(key, self.stack:top(), self.overworld) then
      Pipelines.syncOptions(self.save.options)
      require("src.render.Tilt").setLevel(self.save.options.tilt or 0)
      self:writeOptions()
      return
    end
    Input:keypressed(key)
  end
  if not ModRuntime.wantsHook("input.key") then return vanilla() end
  return ModRuntime.call("input.key", vanilla, self, { phase = "pressed", key = key })
end

-- Mod enablement is stored with persistent options.  Restarting the actual
-- LÖVE process ensures scripts, registries, and assets are all rebuilt from
-- the newly selected mod state.
function Game:restartWithMods()
  require("src.core.HostShell").restart()
end

-- Releases reach Input even while a top state captures raw input: a
-- swallowed key-up would strand a held-state flag for a key Input saw go
-- down before the capture armed (the stuck-flag hazard Input:reset
-- exists for).  The top state only OBSERVES the release afterwards,
-- unlike onKeyPressed above which owns the press, so BindingsMenu can
-- commit a capture on the key-up (#589).
-- RFC 0020: same "fires before everything, vanilla is the untouched whole
-- body" contract as Game:keypressed above -- including here, before
-- Input:keyreleased. Before the sandbox changes, a mod's love.keyreleased
-- override had this same absolute precedence; #589's own "release must
-- still reach Input even under a top-state capture" hazard was about the
-- ENGINE's internal capture ladder, not about a mod -- mods could already
-- swallow a release outright before the sandbox changes (kanto_companion's own
-- Game:gamepadreleased-era override did exactly this for its active-drag
-- case, see RFC 0020), so a mod choosing to do the same here via
-- input.key is restoring that power, not introducing a new hazard class.
function Game:keyreleased(key)
  local function vanilla()
    Input:keyreleased(key)
    local top = self.stack and self.stack:top()
    if top and top.onKeyReleased then top:onKeyReleased(key) end
  end
  if not ModRuntime.wantsHook("input.key") then return vanilla() end
  return ModRuntime.call("input.key", vanilla, self, { phase = "released", key = key })
end

-- RFC 0020: input.gamepad covers press/release/axis (see this method,
-- Game:gamepadreleased, and Game:gamepadaxis below) -- three raw callbacks
-- feeding one hook, because the motivating use case (a stick-driven
-- cursor) needs raw axis values a button-only hook could never deliver.
-- Same "fires first, vanilla is the whole untouched body" contract as
-- Game:keypressed; see its comment and RFC 0020 for the precedent this
-- restores.
function Game:gamepadpressed(joystick, button)
  local function vanilla()
    -- a controller is being used: the touch overlay steps aside until the
    -- next screen touch (mobile only; a no-op elsewhere)
    TouchControls:noteGamepad()
    -- Select held? Needed both to suppress shoulder speed hotkeys (Select+L
    -- is a display chord on NX) and for the chord path below.
    local selectHeld = Input:isDown("select")
    if not selectHeld and joystick and joystick.isGamepadDown then
      local ok, down = pcall(function()
        return joystick:isGamepadDown("back")
      end)
      selectHeld = ok and down == true
    end
    local top = self.stack and self.stack:top()
    if top and top.onGamepadPressed then
      top:onGamepadPressed(button)
      return
    end
    if not selectHeld then
      local action = Input:padAction(button)
      if action == "speedUp" then
        self:_cycleSpeed(1)
        return
      elseif action == "speedDown" then
        self:_cycleSpeed(-1)
        return
      end
    end
    -- Select+face display chords → same digit path as Game:keypressed
    -- (COLORS/TILT/pipelines). Intercept before Input so face does not
    -- also fire GB A/B. Dual-path: raw already ignored when isGamepad().
    if selectHeld then
      local digit = GamepadMap.displayChordDigit(button)
      if digit then
        self:keypressed(digit)
        return
      end
    end
    Input:gamepadpressed(joystick, button)
  end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "pressed", joystick = joystick, button = button })
end

function Game:gamepadreleased(joystick, button)
  local function vanilla()
    -- same observe-after-Input contract as Game:keyreleased (#589)
    Input:gamepadreleased(joystick, button)
    local top = self.stack and self.stack:top()
    if top and top.onGamepadReleased then top:onGamepadReleased(button) end
  end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "released", joystick = joystick, button = button })
end

function Game:gamepadaxis(joystick, axis, value)
  local function vanilla()
    -- past-deadzone only, so resting-stick drift can't hide the overlay
    if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
    Input:gamepadaxis(joystick, axis, value)
  end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "axis", joystick = joystick, axis = axis, value = value })
end

local isAccelerometer = GamepadMap.isAccelerometer

-- BindingsMenu's raw-stick capture rides the same top-state routing as the
-- keyboard and gamepad paths (#632).  Only a stick SDL does not recognize
-- as a gamepad reaches the capture: a recognized pad raises BOTH
-- joystickpressed and gamepadpressed for one press, and the joystick half
-- would otherwise beat its own gamepadpressed to the armed row and record
-- "JOY1" for a button the player can plainly see is A.  Same predicate as
-- Input's, kept local here so Game never reaches into Input's internals.
local function isRawStick(joystick)
  return not (joystick and joystick.isGamepad and joystick:isGamepad())
end

function Game:joystickpressed(joystick, button)
  if isAccelerometer(joystick) then return end
  TouchControls:noteGamepad()
  local top = self.stack and self.stack:top()
  if isRawStick(joystick) and top and top.onJoystickPressed then
    top:onJoystickPressed(button)
    return
  end
  Input:joystickpressed(joystick, button)
end

function Game:joystickreleased(joystick, button)
  if isAccelerometer(joystick) then return end
  -- same observe-after-Input contract as Game:keyreleased (#589): the
  -- capture watches the release, it never owns it, so a held-state flag
  -- Input saw go down before the capture armed cannot be stranded
  Input:joystickreleased(joystick, button)
  local top = self.stack and self.stack:top()
  if isRawStick(joystick) and top and top.onJoystickReleased then
    top:onJoystickReleased(button)
  end
end

function Game:joystickaxis(joystick, axis, value)
  if isAccelerometer(joystick) then return end
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:joystickaxis(joystick, axis, value)
end

function Game:joystickhat(joystick, hat, direction)
  if isAccelerometer(joystick) then return end
  if direction ~= "c" then TouchControls:noteGamepad() end
  Input:joystickhat(joystick, hat, direction)
end

-- Window focus/visibility flips: a release due while unfocused/hidden can
-- be swallowed by the OS. Reset on both edges; on the regain, reconcile
-- re-arms only what is still physically held -- a held key won't re-fire
-- keypressed by itself, and without the rebuild a spurious lifecycle event
-- parked the player until every direction was re-pressed (#799).
function Game:focus(f)
  Input:reset()
  if f then
    Input:reconcile()
    local eng = self:syncEngine()
    if eng then pcall(eng.noteResumed, eng) end
  end
  TouchControls:reset()
  self:cancelPointers()
end

function Game:visible(v)
  if v then
    self:onResume()
  else
    Input:reset()
    TouchControls:reset()
    self:cancelPointers()
  end
end

function Game:onResume()
  Input:reset()
  Input:reconcile()
  TouchControls:reset()
  self:cancelPointers()
  local eng = self:syncEngine()
  if eng then pcall(eng.noteResumed, eng) end
  -- Chip music may survive NX suspend as a duplicate stream; stop it and let
  -- the active screen re-cue on the next frame (hardware audio check: T19).
  -- Desktop/mobile window-visible flips must not kill overworld music.
  if require("src.core.Platform").isNX() then
    require("src.core.ChipAudio").stopMusic()
  end
  local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")
  if SwitchDiagnostics.isEnabled() then
    SwitchDiagnostics.onEvent("lifecycle", { event = "resume" })
  end
end

function Game:recoverInput(event, joystick)
  Input:reset()
  -- A hotplug can arrive with no hotplug (macOS Bluetooth re-enumeration),
  -- and the blanket reset above also drops unrelated keyboard holds; put
  -- back whatever is still physically down (#799).
  Input:reconcile()
  TouchControls:reset()
  -- reset just dropped every source, mod holds included: retire the mods'
  -- outstanding press tokens so nothing stale can be released later, and
  -- tell subscribers their live pointers died (#807)
  if self.mods and self.mods.releaseModInput then self.mods:releaseModInput() end
  self:cancelPointers()
  local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")
  if SwitchDiagnostics.isEnabled() then
    if joystick then
      SwitchDiagnostics.onJoystickEvent(event, joystick)
    else
      SwitchDiagnostics.onEvent("lifecycle", { event = event })
    end
  end
end

function Game:joystickadded(joystick)
  self:recoverInput("joystickadded", joystick)
end

-- A disconnected/dropped controller can't send the button-up for whatever
-- it was holding, so drop all input state rather than try to guess which
-- flags it owned.
function Game:joystickremoved(joystick)
  self:recoverInput("joystickremoved", joystick)
  TouchControls:joystickremoved()
end

-- Gameplay pointer seam (#807).  TouchControls keeps first refusal: a
-- pointer that begins on a virtual control belongs to the pad for its
-- whole lifecycle and never reaches mods, while one that begins outside
-- stays mod-visible even if it later wanders across a control
-- (TouchControls only tracks ids it captured at press).  Everything a
-- subscriber costs -- the per-pointer records in self.modPointers, the
-- payload tables -- sits behind wantsHook, so a mod-free boot allocates
-- nothing here.

-- vanilla for input.pointer: nobody consumed the event
local function pointerUnclaimed() return false end

-- coordinates are LOVE window units, the same space render.hud's viewport
-- and the touch overlay lay out in
function Game:pointerEvent(phase, source, id, x, y, dx, dy, pressure, button)
  local gameX, gameY, insideGame = GameViewport.toLocal(x, y)
  return ModRuntime.call("input.pointer", pointerUnclaimed, self, {
    phase = phase, source = source, id = id, x = x, y = y,
    gameX = gameX, gameY = gameY, insideGame = insideGame,
    dx = dx or 0, dy = dy or 0, pressure = pressure, button = button,
  })
end

function Game:touchpressed(id, x, y, dx, dy, pressure)
  if TouchControls:touchpressed(id, x, y) then return end
  if not ModRuntime.wantsHook("input.pointer") then return end
  -- POKEPORT_TOUCH routes the mouse through here as a stand-in finger
  -- under the id "mouse" (see main.lua); mods still see its true source
  local source = id == "mouse" and "mouse" or "touch"
  self.modPointers = self.modPointers or {}
  self.modPointers[id] = { source = source, x = x, y = y,
                           pressure = pressure }
  self:pointerEvent("pressed", source, id, x, y, dx, dy, pressure)
end

function Game:touchmoved(id, x, y, dx, dy, pressure)
  TouchControls:touchmoved(id, x, y)
  local p = self.modPointers and self.modPointers[id]
  if not p then return end
  -- the POKEPORT_TOUCH mouse path carries no deltas; derive them from the
  -- pointer's last seen position so drags read the same either way
  if dx == nil then dx, dy = x - p.x, y - p.y end
  p.x, p.y = x, y
  if pressure ~= nil then p.pressure = pressure end
  if ModRuntime.wantsHook("input.pointer") then
    self:pointerEvent("moved", p.source, id, x, y, dx, dy, pressure)
  end
end

function Game:touchreleased(id, x, y, dx, dy, pressure)
  TouchControls:touchreleased(id, x, y)
  local p = self.modPointers and self.modPointers[id]
  if not p then return end
  self.modPointers[id] = nil
  if ModRuntime.wantsHook("input.pointer") then
    self:pointerEvent("released", p.source, id, x, y, dx, dy, pressure)
  end
end

-- A real mouse without POKEPORT_TOUCH (#807).  Gameplay itself has no
-- mouse verbs, so the pointer hook is the only consumer and everything is
-- behind the wantsHook gate.  A synthesized istouch twin is dropped
-- unconditionally: the same contact already arrived through
-- Game:touchpressed, and forwarding both would fire a mobile touch twice.
function Game:mousepressed(x, y, button, istouch)
  if istouch then return end
  if not ModRuntime.wantsHook("input.pointer") then return end
  self.modPointers = self.modPointers or {}
  local p = self.modPointers.mouse
  if p then
    p.held, p.x, p.y = (p.held or 1) + 1, x, y
  else
    self.modPointers.mouse = { source = "mouse", x = x, y = y,
                               held = 1, button = button }
  end
  self:pointerEvent("pressed", "mouse", "mouse", x, y, 0, 0, nil, button)
end

-- hover moves are delivered too (button = nil); only pressed pointers are
-- tracked, because only they owe a released/cancelled later
function Game:mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  local p = self.modPointers and self.modPointers.mouse
  if p then p.x, p.y = x, y end
  if not ModRuntime.wantsHook("input.pointer") then return end
  self:pointerEvent("moved", "mouse", "mouse", x, y, dx, dy, nil, nil)
end

function Game:mousereleased(x, y, button, istouch)
  if istouch then return end
  local p = self.modPointers and self.modPointers.mouse
  if not p then return end
  p.held = (p.held or 1) - 1
  if p.held <= 0 then self.modPointers.mouse = nil end
  if ModRuntime.wantsHook("input.pointer") then
    self:pointerEvent("released", "mouse", "mouse", x, y, 0, 0, nil, button)
  end
end

-- Focus/visibility loss and input recovery swallow pointer releases the
-- same way they swallow key-ups (the hazard Input:reset exists for):
-- every mod-visible pointer gets a "cancelled" instead of leaving
-- subscribers waiting on a "released" that can never arrive (#807).
-- Cleared even when the subscriber is already gone, so no stale record
-- outlives its mod.
function Game:cancelPointers()
  local pointers = self.modPointers
  if not pointers then return end
  self.modPointers = nil
  if not ModRuntime.wantsHook("input.pointer") then return end
  for id, p in pairs(pointers) do
    self:pointerEvent("cancelled", p.source, id, p.x, p.y, 0, 0,
                      p.pressure, p.button)
  end
end

-- Point the loader's mod.save backing at this save's modData so per-mod
-- state persists with the slot.  seedBuckets is boot-only: it keeps what
-- entry chunks wrote before any save existed, while NEW GAME and
-- CONTINUE replace the backing outright.
function Game:adoptSave(save, seedBuckets)
  save.modData = save.modData or {}
  local loader = self.mods
  if not loader then return end
  if seedBuckets then
    for id, bucket in pairs(loader.modSave or {}) do
      if save.modData[id] == nil then save.modData[id] = bucket end
    end
  end
  loader.modSave = save.modData
end

-- Capture the live world state into the save table and persist it.
-- Options are flushed to options.lua as part of SaveData.save.
function Game:writeSave()
  -- Tool sessions can be deliberately ephemeral. Give them one narrow veto
  -- before captureSave mutates the snapshot or any progress bytes reach disk.
  if ModRuntime.call("save.write", function() return true end, self) == false then
    return false
  end
  if self.overworld and self.overworld.captureSave then
    self.overworld:captureSave(self.save)
  end
  -- stamp here so the save.writing payload carries the exact meta the
  -- file gets; mods snapshot runtime state into their namespace now
  self.save.meta = SaveData.buildMeta(
    self.modStatus and self.modStatus.loaded, self.save.meta,
    self.sessionStartedAt)
  if ModRuntime.wants("save.writing") then
    ModRuntime.emit("save.writing", { save = self.save, meta = self.save.meta })
  end
  local written = SaveData.save(self.save)
  if written then
    local eng = self:syncEngine()
    if eng then pcall(eng.noteSaveWritten, eng) end
  end
  return written
end

function Game:quickSaveAllowed()
  local ow = self.overworld
  if not (ow and ow.player) then return true end
  local states = self.stack.states
  local top = states[#states]
  if not top then return true end
  if top ~= ow then
    for i = #states - 1, 1, -1 do
      if states[i] == ow then return false end
    end
    return true
  end
  if ow.transitioning then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return false end
  if ow.engaging or ow.emote then return false end
  if ow.player.moving then return false end
  return true
end

function Game:syncEngine()
  if self._syncOff then return nil end
  local eng = self._syncEngineRef
  if not eng then
    local ok, SyncEngine = pcall(require, "src.sync.SyncEngine")
    if not ok or type(SyncEngine) ~= "table" then
      self._syncOff = true
      return nil
    end
    eng = SyncEngine.shared()
    if not eng then
      self._syncOff = true
      return nil
    end
    self._syncEngineRef = eng
  end
  if type(eng.protectPlaythrough) == "function" then
    local meta = self.save and self.save.meta
    eng:protectPlaythrough(
      (self.save and self.save.version) or require("src.core.GameVersion").get(),
      type(meta) == "table" and meta.playthroughId or nil)
  end
  return eng
end

function Game:updateSync(dt)
  local eng = self:syncEngine()
  if not eng then return end
  if not (eng.state.enabled and eng:linked()) and not eng:busy() then return end
  local wasBusy = eng:busy()
  pcall(eng.update, eng, dt)
  if wasBusy and not eng:busy() then self:adoptPlaythroughId() end
end

function Game:adoptPlaythroughId()
  local save = self.save
  local meta = type(save) == "table" and save.meta
  if type(meta) ~= "table" or meta.savedAt == nil then return end
  if type(meta.playthroughId) == "string" and meta.playthroughId ~= "" then return end
  local id = SaveData.selectedPlaythroughId(save)
  if type(id) == "string" and id ~= "" then meta.playthroughId = id end
end

-- Persist options.lua only (Options menu / hotkeys 2-5).  Keeps settings
-- across New Game without touching the progress save.
function Game:writeOptions()
  if not (self.save and self.save.options) then return end
  SaveData.saveLiveOptions(self.save)
end

-- Push the live options table into audio + display subsystems.
function Game:applyOptions(opts)
  opts = opts or (self.save and self.save.options) or {}
  local Music = require("src.core.Music")
  local Sound = require("src.core.Sound")
  if Music.applyOptions then Music.applyOptions(opts) end
  if Sound.applyOptions then Sound.applyOptions(opts) end
  require("src.render.PaletteFX").applyOptions(opts)
  require("src.render.Tilt").applyOptions(opts)
  require("src.render.Letterbox").applyOptions(opts)
  -- after Tilt, so a persisted world pipeline can switch the tilt level it
  -- just restored back off (the two are mutually exclusive)
  require("src.render.Pipelines").applyOptions(opts)
  require("src.render.Zoom").applyOptions(opts)
  require("src.render.TileRenderer").applyOptions(opts)
  -- returns true when a persisted preset name no longer resolves (deleted
  -- from the drop-in folder, or failed to (re)translate) and had to be
  -- cleared back to OFF -- "sanitized, please persist" contract
  local shaderfxCleared = require("src.render.ShaderFX").applyOptions(opts)
  require("src.core.VideoMode").applyOptions(opts)
  -- Android orientation lock (#592); no-op everywhere else
  require("src.core.Orientation").applyOptions(opts)
  -- after VideoMode: a faithful-resolution lock is an exact window size, so
  -- it has to be the last word on the window (it drops fullscreen to hold)
  require("src.core.FaithfulRes").applyOptions(opts)
  require("src.core.ScreenPosition").applyOptions(opts)
  require("src.core.VSync").applyOptions(opts)
  require("src.core.FrameCap").applyOptions(opts)
  require("src.core.LogicClock").applyOptions(opts)
  require("src.core.PresentSync").applyFixedStepPeriod()
  -- Scale the optional presentation extras to the device's performance
  -- tier.  Every heavy feature was just applied from the stored options
  -- above; here we clamp the *live* state down for a weaker device without
  -- rewriting what the player saved, so raising the tier later restores
  -- their exact TILT / ZOOM / MAX FPS choices.  A HIGH tier (the
  -- default on a normal desktop, and every options.lua predating this
  -- option) clamps nothing, so it is a no-op for the common case.
  local caps = require("src.core.Performance").applyOptions(opts)
  if not caps.tilt then require("src.render.Tilt").setLevel(0) end
  if not caps.shaderfx then require("src.render.ShaderFX").deactivate() end
  local Zoom = require("src.render.Zoom")
  Zoom.allowSurvey = caps.survey
  if not caps.survey and Zoom.offset < 0 then Zoom.offset = 0 end
  if caps.fpsMax then
    require("src.core.FrameCap").clampToPerformance(caps.fpsMax)
  end
  Input:applyBindings(opts.bindings)
  TouchControls:applyOptions(opts)
  if shaderfxCleared then self:writeOptions() end
end

function Game:restoreSave(loaded, recovered, opts)
  self.sessionStartedAt = os.time()
  if ModRuntime.wants("save.loading") then
    ModRuntime.emit("save.loading", { raw = loaded })
  end
  -- mod chains replay before validation so a mod repairs its own data
  -- instead of watching it get quarantined; core steps already ran in
  -- SaveData.load and skip on the format guard
  local activeMods = self.modStatus and self.modStatus.loaded
  SaveData.runMigrations(loaded, self.mods and self.mods.migrations, activeMods)
  -- Issue #103: 0.1.11 softlocks left CONTINUE in HALL_OF_FAME with
  -- lastOutdoor on Indigo.  One-shot relocate + heal before validate.
  if SaveData.needsPostGameRescue(loaded) then
    SaveData.applyPostGameHome(loaded, self:bootConfig())
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(loaded.party or {}) do Pokemon.heal(mon) end
  end
  local modsDiff = SaveData.modsDiff(loaded, activeMods)
  local report = SaveData.validate(loaded, self.data)
  report.recovered = recovered
  report.modsDiff = modsDiff
  self.save = loaded
  -- the START cursor lives outside sGameData (ram/sram.asm:17-21)
  loaded.startMenuIndex = nil
  self.startMenuIndex = nil
  self:adoptSave(loaded)
  -- SaveData.load already attached the standalone options.lua table
  self:applyOptions(loaded.options)
  -- saves from before OT/ID stamping: backfill with the player's
  local stamp = require("src.battle.BattleState").stampOT
  for _, mon in ipairs(loaded.party or {}) do stamp(loaded, mon) end
  for _, box in ipairs(loaded.boxes or {}) do
    for _, mon in ipairs(box) do stamp(loaded, mon) end
  end
  -- rebuild the state stack from the save
  while self.stack:top() do self.stack:pop() end
  -- freshBoot threads through from the caller (onContinue and F2 both set
  -- it); a future caller that doesn't ask for it keeps the ordinary
  -- crossfade by default.
  -- engine/menus/main_menu.asm:110 (CONTINUE forces PLAYER_DIR_DOWN)
  local facing = (opts and opts.continued) and "down" or loaded.player.facing
  self.stack:push(self.overworld, loaded.player.map,
                  loaded.player.x, loaded.player.y, facing,
                  { via = "boot", freshBoot = opts and opts.freshBoot })
  self.saveReport = report
  if not SaveData.emptyReport(report) then
    -- the report screen is a Screens id so mods (or the ui milestone) own
    -- its looks; until one exists the log keeps a quarantine from being
    -- silent
    local ok = pcall(Screens.push, self, "QuarantineReport", report)
    if not ok then
      Logger.warn("load report: %d mons quarantined, %d items removed, %d maps remapped%s",
        #report.lostMons, #report.lostItems, #report.remappedMaps,
        recovered and (", recovered from " .. recovered) or "")
      local notice = SaveData.modsDiffNotice(modsDiff, loaded.meta)
      if notice then Logger.warn("%s", notice) end
    end
  end
  if ModRuntime.wants("save.loaded") then
    ModRuntime.emit("save.loaded",
      { save = loaded, meta = loaded.meta, modsDiff = modsDiff })
  end
end

-- Reconstruct a previously validated runtime checkpoint without replaying the
-- ordinary CONTINUE lifecycle. In particular, map onEnter scripts and
-- save.loading/save.loaded events must not run a second time. Validation,
-- identity checks and transactional rollback live in Checkpoint.lua.
function Game:restoreCheckpointSave(loaded)
  self.save = loaded
  self:adoptSave(loaded)
  while self.stack:top() do self.stack:pop() end
  -- setMap zeroes poisonSteps on every non-seamless map entry, mirroring
  -- ClearVariablesOnEnterMap.  Re-entering the map is how a restore installs
  -- the world, but it is not a map entry from the player's point of view, and
  -- Checkpoint.restore verifies the applied state against the checkpoint --
  -- so the discarded counter failed the comparison and rolled the whole
  -- restore back three steps out of four (#1971).
  local poisonSteps = loaded.poisonSteps
  -- freshBoot unconditionally: both callers arrive through Checkpoint.apply
  -- (src/core/Checkpoint.lua), which serves Checkpoint.resume from the title
  -- session and Checkpoint.restore from a settled runtime.
  self.stack:push(self.overworld, loaded.player.map,
                  loaded.player.x, loaded.player.y, loaded.player.facing,
                  { via = "checkpoint", checkpoint = true, freshBoot = true })
  self.save.poisonSteps = poisonSteps
end

-- Install a reconstructed battle without calling BattleState:enter(), whose
-- transition, intro queues and battle-start side effects already happened in
-- the checkpointed timeline.
function Game:restoreCheckpointBattle(battle)
  if self.stack:top() ~= self.overworld then
    error("battle checkpoint requires a reconstructed overworld base", 0)
  end
  self.stack.states[#self.stack.states + 1] = battle
  if battle.resumeCheckpoint then battle:resumeCheckpoint() end
end

-- Drop every session-owned field so the next Game:load() starts clean when
-- the process returns to the launcher in-place (Android / intent_game).
--
-- Gen1 Game is a MODULE SINGLETON (methods live on this table).  Never fan
-- out arbitrary field:release() here: session fields can hold shared modules
-- (Fetch, SyncClient, …) whose :release is a job-handle API, not instance
-- teardown -- calling them as value:release() corrupts process state and has
-- been observed to leave Game.load nil after EXIT GAME on Android.
-- Explicit GPU owners are released below; everything else is just dropped.
function Game:reset()
  if self.stack and self.stack.clear then
    pcall(function() self.stack:clear() end)
  end
  if self.world and self.world.release then
    pcall(function() self.world:release() end)
  end
  if self._canvases then
    for _, canvas in pairs(self._canvases) do
      if canvas and canvas.release then pcall(canvas.release, canvas) end
    end
  end
  if self.renderer then
    local release = self.renderer.releaseCanvases or self.renderer.release
    if release then pcall(release, self.renderer) end
  end
  -- Keep methods; clear every other field (including session scalars like
  -- speedOverride).  Re-seed module constants afterward.
  local skinFast = self.SKIN_FAST_FORWARD
  local keys = {}
  for key, value in pairs(self) do
    if type(value) ~= "function" then
      keys[#keys + 1] = key
    end
  end
  for _, key in ipairs(keys) do
    self[key] = nil
  end
  self.SKIN_FAST_FORWARD = skinFast or 4
end

return Game

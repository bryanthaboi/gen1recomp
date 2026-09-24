-- Pokemon FireRed service owner (Gen 3 peer of Game / Game2).
-- Boot: copyright → title → main menu → Oak → gender → field (FR_* maps only).

local FixedStep = require("src.core.FixedStep")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local Schema = require("src.core.game3.save_schema_firered")
local MapIds = require("src.core.game3.map_ids")
local Profile = require("src.core.game3.profile")
local Runtime = require("src.core.game3.runtime")
local Audio = require("src.core.game3.audio")
local Options = require("src.core.game3.options")
local Dataset = require("src.core.game3.dataset")
local Display = require("src.core.game3.display")
local Boot = require("src.ui.game3.boot")
local Help = require("src.ui.game3.help_system")

local QuestLog = require("src.ui.game3.quest_log")
local QuestRecorder = require("src.core.game3.quest_log_recorder")
local ModRuntime = require("src.mods.Runtime")

local s9Warned = {}
local function s9log(key, err)
  if s9Warned[key] then return end
  s9Warned[key] = true
  print("[game3] hot-path pcall failed (" .. key .. "): " .. tostring(err))
end

local Game3 = {}
Game3.__index = Game3

local function noop() end

Game3.SKIN_FAST_FORWARD = 4

-- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
local FIELD_CB_SILENT = { bike = true, rod = true, map = true, escape = true }

function Game3.new()
  return setmetatable({
    generation = 3,
    input = Input,
    save = nil,
    session = nil,
    phase = "boot", -- boot UI | field
    boot = nil,
    returnToLauncher = nil,
    onExit = nil,
  }, Game3)
end

function Game3:_hasContinueSave()
  if not SaveData.load then return false end
  local ok, save = pcall(SaveData.load)
  if not ok or type(save) ~= "table" then return false end
  return save.engine == "game3" and type(save.map) == "string"
    and MapIds.isGame3Map(save.map, save.version)
end

function Game3:_enterField(session, reason)
  self.session = session
  Options.bind(session, self.options)
  -- Continue restores stream; new_game already seeded inside Schema.newGame.
  local Rng = require("src.core.game3.rng")
  if reason == "continue" then
    if not Rng.restoreFromSession(session) then
      -- Legacy saves without rng: soft-reset-ish reseed.
      session.trainerId = Rng.seedNewGame()
      Rng.captureToSession(session)
    else
      -- On GBA FRLG, continuing from title screen seeds/perturbs gRngValue with timer TM0
      Rng.perturb()
    end
  elseif session.rng then
    Rng.restoreFromSession(session)
    Rng.perturb()
  end
  self.save = Schema.toSaveTable(session)
  self.phase = "field"
  self.boot = nil
  -- Drop boot/title BG+OAM so Display.present composites the field underlay only.
  local okBg, Bg = pcall(require, "src.core.game3.bg")
  if okBg and Bg and Bg.reset then Bg.reset() end
  local okOam, Oam = pcall(require, "src.core.game3.oam")
  if okOam and Oam and Oam.reset then Oam.reset() end
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade then
    if Fade.clear then Fade.clear() end
    -- Come out of Oak's black screen onto the bedroom.
    if Fade.begin then Fade.begin(Fade.MODE.FROM_BLACK, 1) end
    Fade.lockInput = true -- pokefirered/src/field_fadetransition.c:441
  end
  session._questNewScene=true
  if reason == "continue" then session._questMap=session.map end
  local Map = require("src.core.game3.map")
  Map._announced = nil
  Map._nextEnterVia = (reason == "continue") and "continue" or "new_game"
  -- pokefirered/src/fieldmap.c:100
  Runtime.start(nil, self, session, { reason = reason or "new_game" })
  Map._nextEnterVia = nil
  if reason == "continue" then
    -- pokefirered/src/overworld.c:1717
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if okS and Space and Space.runOnReturnToField then
      Space.runOnReturnToField()
    end
  end
end

function Game3:load(opts)
  require("src.import.gba.versions").select(require("src.core.GameVersion").get())
  opts = opts or {}
  self.onExit = opts.onExit or self.onExit
  Input:init()
  self.input = Input
  Dataset.hydrate(self)
  if type(self.data) == "table" then self.data.generation = 3 end
  Help.reset()
  Help.install(Dataset.cache())
  QuestLog.install(Dataset.cache())

  local TouchControls = require("src.core.TouchControls")
  TouchControls:init()
  self.touchControls = TouchControls
  TouchControls:setHotkeyHandler(function(action, pressed)
    if not action then return end
    if action:sub(1, 4) == "key:" then
      local key = action:sub(5)
      if pressed then
        if self.keypressed then self:keypressed(key) end
      else
        if self.keyreleased then self:keyreleased(key) end
      end
      return
    end
    if action == "fast_forward_hold" then
      if pressed then
        if self._skinSpeedPrev == nil then
          self._skinSpeedPrev = self.speedOverride or false
        end
        self.speedOverride = Game3.SKIN_FAST_FORWARD
      else
        local prev = self._skinSpeedPrev
        self._skinSpeedPrev = nil
        self.speedOverride = (prev ~= false) and prev or nil
      end
    elseif action == "fast_forward_toggle" then
      if pressed then self:_cycleSpeed(1) end
    elseif action == "soft_reset" then
      if pressed and self.phase ~= "arena" then
        if self.input then self.input:reset() end
        TouchControls:reset()
        self:returnToTitle()
      end
    elseif action == "menu" then
      if pressed and self.phase == "field" and self.session then
        require("src.ui.game3.option_menu").show({ session = self.session, game = self })
      end
    end
  end)

  local okLoad, rawSave, recovered = false, nil, nil
  if SaveData.load then okLoad, rawSave, recovered = pcall(SaveData.load) end
  if not okLoad then rawSave, recovered = nil, nil end
  local saveStatus = "ok"
  if recovered then
    saveStatus = "error" -- pokefirered/src/main_menu.c:251
  elseif okLoad and rawSave == nil and SaveData.persistenceFs and SaveData.saveFilename then
    local okFs, exists = pcall(function()
      local fs = SaveData.persistenceFs(nil)
      return fs and fs.getInfo and fs.getInfo(SaveData.saveFilename()) ~= nil
    end)
    if okFs and exists then saveStatus = "invalid" end -- pokefirered/src/main_menu.c:246
  end
  local options = (SaveData.loadOptions and SaveData.loadOptions())
    or (rawSave and rawSave.options)
    or (SaveData.defaultOptions and SaveData.defaultOptions())
  self.options = options
  self:applyOptions(options)

  self:_exposeModData()
  self:_loadMods(opts)
  pcall(function() require("src.core.DiscordPresence").init(self) end)

  if opts.arena then
    FixedStep:init(function(dt)
      self:fixedUpdate(dt)
    end)
    pcall(function()
      require("src.core.PresentSync").applyFixedStepPeriod()
    end)
    self:enterArena(opts.arena)
    return
  end

  -- Never auto-skip boot into a legacy Sevii sidecar.
  local continueOk = self:_hasContinueSave()
  require("src.ui.game3.start_menu").resetCursor() -- pokefirered/src/main.c:134
  self.boot = Boot.new()
  Boot.setHasContinue(self.boot, continueOk)
  if continueOk then
    Boot.setContinueInfo(self.boot, Boot.continueInfoFromSave(rawSave))
  end
  Boot.setSaveStatus(self.boot, saveStatus)
  Boot.setTextSpeed(self.boot, Options.block(self.options).textSpeed)
  self.phase = "boot"
  self.session = nil

  FixedStep:init(function(dt)
    self:fixedUpdate(dt)
  end)
  pcall(function()
    require("src.core.PresentSync").applyFixedStepPeriod()
  end)
  if ModRuntime.wants("game.ready") then
    ModRuntime.emit("game.ready", { game = self })
  end
end

local function arenaSession(self, spec)
  local session
  local version = require("src.core.GameVersion").get()
  if spec and spec.slotId and SaveData.setActiveSlot then
    pcall(SaveData.setActiveSlot, version, spec.slotId)
  end
  local ok, save = pcall(SaveData.load)
  if ok and type(save) == "table" and save.engine == "game3" then
    local activeMods = self.modStatus and self.modStatus.loaded
    if SaveData.runMigrations then
      pcall(SaveData.runMigrations, save, self.mods and self.mods.migrations, activeMods)
    end
    local okS, loaded = pcall(Schema.fromSaveTable, save)
    if okS and type(loaded) == "table" then session = loaded end
  elseif spec and spec.role ~= "spectator" then
    require("src.core.Logger").warn("arena3: save slot %s could not be loaded", tostring(spec and spec.slotId))
  end
  session = session or { party = {}, bag = {} }
  if type(session.name) ~= "string" or session.name == "" then
    for _, row in ipairs((spec and spec.players) or {}) do
      if spec.seat ~= nil and tonumber(row.seat) == tonumber(spec.seat) then session.name = row.name end
    end
  end
  session.store = session.store or { flags = {}, vars = {} }
  return session
end

-- pokefirered/src/cable_club.c:964
function Game3:enterArena(spec)
  local session = arenaSession(self, spec)
  Options.bind(session, self.options)
  self.session = session
  self.save = Schema.toSaveTable(session)
  self.boot = nil
  Runtime.session = session
  Runtime._game = self
  self.phase = "arena"
  self.arena = require("src.ui.game3.arena_state").new(self, spec)
  return self.arena
end

function Game3:leaveArena()
  self.arena = nil
  if Runtime.session == self.session then Runtime.session = nil end
  if Runtime._game == self and not Runtime.isActive() then Runtime._game = nil end
end

function Game3:_exposeModData()
  local data = self.data
  if type(data) ~= "table" then return end
  data.gen3Pokemon = require("src.core.game3.pokemon")
  local Moves = require("src.core.game3.battle.moves")
  if not Moves._romLoaded then pcall(Moves.loadRomPack, Dataset.cache()) end
  data.gen3Moves = Moves
  local ItemsData = require("src.core.game3.items_data")
  pcall(ItemsData.ensureLoaded)
  data.gen3Items = ItemsData
  local Encounters = require("src.core.game3.encounters")
  data.gen3Encounters = Encounters._tables
  local Trainers = require("src.core.game3.scripting.trainers")
  local okT, pack = pcall(Trainers.pack)
  data.gen3Trainers = okT and type(pack) == "table" and pack or nil
  local Space = require("src.core.game3.scripting.space")
  local bundle = Space.bundle
  data.gen3Text = bundle and bundle.text or nil
  data.gen3Scripts = bundle and bundle.scripts or nil
  data.gen3RomText = require("src.core.game3.rom_text").overrides
end

function Game3:_loadMods(opts)
  local modOpts = opts and opts.modOpts or nil
  local ok, loader = pcall(function()
    local mods = require("src.mods.Loader").new()
    mods.game = self
    mods:load(self.data, modOpts)
    return mods
  end)
  if ok and loader then
    self.mods = loader
    self.modStatus = loader:status()
  else
    require("src.core.Logger").error(
      "mods failed to load, continuing without them: %s", tostring(loader))
  end
  -- After the merge, so a translation mod's catalog is what Strings() reads,
  -- as Game (src/core/Game.lua) and Game2 do.  Without it the catalog the
  -- launcher preloaded (every enabled mod's lang/strings.lua, whatever game
  -- it targets) stayed in place for the whole FireRed session.
  require("src.core.Strings").load(self.data)
  local okC, Gen3Compat = pcall(require, "src.mods.Gen3Compat")
  if okC and type(Gen3Compat) == "table" and Gen3Compat.applyMerged then
    local okA, err = pcall(Gen3Compat.applyMerged, self)
    if not okA then
      require("src.core.Logger").error("Gen3Compat.applyMerged failed: %s", tostring(err))
    end
  end
end

function Game3:adoptSave(session, seedBuckets)
  if type(session) ~= "table" then return end
  if type(session.modData) ~= "table" then session.modData = {} end
  local loader = self.mods
  if not loader then return end
  if seedBuckets then
    for id, bucket in pairs(loader.modSave or {}) do
      if session.modData[id] == nil then session.modData[id] = bucket end
    end
  end
  loader.modSave = session.modData
end

function Game3:writeOptions()
  if type(self.options) ~= "table" then return end
  if SaveData.saveOptions then pcall(SaveData.saveOptions, self.options) end
end
Game3.persistOptions = Game3.writeOptions

function Game3:applyOptions(opts)
  opts = opts or self.options or {}
  self.options = opts
  local function try(mod, fn, ...)
    local ok, m = pcall(require, mod)
    if not ok or type(m) ~= "table" then return nil end
    local f = m[fn]
    if type(f) ~= "function" then return nil end
    local okCall, res = pcall(f, ...)
    if not okCall then return nil end
    return res
  end
  Audio.applyEngineOptions(opts)
  local cartOpts = Options.block(opts)
  require("src.core.game3.void_fill").setMode(cartOpts.voidFill)
  pcall(function()
    require("src.ui.game3.chrome").setFrameType(cartOpts.frameType)
  end)
  try("src.render.Tilt", "applyOptions", opts)
  try("src.render.Letterbox", "applyOptions", opts)
  try("src.render.Xbrz", "applyOptions", opts)
  try("src.render.Zoom", "applyOptions", opts)
  try("src.core.VideoMode", "applyOptions", opts)
  try("src.core.Orientation", "applyOptions", opts)
  local FaithfulRes = require("src.core.FaithfulRes")
  if FaithfulRes.setNativeSize then
    FaithfulRes.setNativeSize(Display.W, Display.H)
  end
  try("src.core.FaithfulRes", "applyOptions", opts)
  try("src.core.ScreenPosition", "applyOptions", opts)
  try("src.core.VSync", "applyOptions", opts)
  try("src.core.FrameCap", "applyOptions", opts)
  try("src.core.LogicClock", "applyOptions", opts)
  try("src.core.PresentSync", "applyFixedStepPeriod")
  local caps = try("src.core.Performance", "applyOptions", opts)
  if type(caps) == "table" then
    if not caps.tilt then try("src.render.Tilt", "setLevel", 0) end
    local okZ, Zoom = pcall(require, "src.render.Zoom")
    if okZ and Zoom then
      Zoom.allowSurvey = caps.survey
      if not caps.survey and (Zoom.offset or 0) < 0 then Zoom.offset = 0 end
    end
    if caps.fpsMax then
      try("src.core.FrameCap", "clampToPerformance", caps.fpsMax)
    end
  end
  if self.touchControls then
    self.touchControls:applyOptions({
      touchControls = opts.touchControls,
      haptics = opts.haptics,
      hotbar = opts.hotbar,
    })
  end
  if self.input and opts.bindings then
    self.input:applyBindings(opts.bindings)
  end
end

-- pokefirered/src/main.c:325
function Game3:_aliasLA()
  local input = self.input
  if not input or not input.setButtonAlias then return end
  local on
  if self.session then
    on = Options.lEqualsA(self.session)
  elseif type(self.options) == "table" then
    on = tonumber(Options.block(self.options).buttonMode) == 2
  end
  input:setButtonAlias("l", on and "a" or nil)
end

function Game3:_handleRegisteredItem()
  local input = self.input
  if not input or not input.wasPressed or not input:wasPressed("select") then
    return
  end
  local session = self.session
  local item = session and session.registeredItem
  if not item then return end
  -- src/item_menu.c:2025
  local Map = package.loaded["src.core.game3.map"]
  if Map and Map.current == "FR_UNION_ROOM" then return end
  -- src/overworld.c:2813
  local Link = package.loaded["src.core.game3.link"]
  if type(Link) == "table" and Link.link ~= nil and Link.inLinkRoom() == true then return end
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return end
  local P = package.loaded["src.core.game3.player"]
  if P and P.boulderPush then return end
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  if not session.bag or not Bag.has(session.bag, item, 1) then
    session.registeredItem = nil
    return
  end
  local ok, kind, text = ItemUse.useField(session, session.bag, item, nil)
  if kind == "vs_seeker" then
    -- pokefirered/src/item_use.c:712
    if ok then
      require("src.core.game3.vs_seeker").use(session, self)
    elseif text then
      require("src.ui.game3.hud").openMessage(self, text)
    end
    return
  end
  -- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
  if text and not (ok and FIELD_CB_SILENT[kind]) then
    require("src.ui.game3.hud").openMessage(self, text)
  end
end

function Game3:_handleBootAction(action)
  if not action then return end
  if action.action == "continue" then
    local ok, save = pcall(SaveData.load)
    if ok and save and save.engine == "game3" then
      if ModRuntime.wants("save.loading") then
        ModRuntime.emit("save.loading", { raw = save })
      end
      local activeMods = self.modStatus and self.modStatus.loaded
      if SaveData.runMigrations then
        SaveData.runMigrations(save, self.mods and self.mods.migrations, activeMods)
      end
      local modsDiff = SaveData.modsDiff and SaveData.modsDiff(save, activeMods) or nil
      local session = Schema.fromSaveTable(save)
      Options.bind(session, self.options)
      self:adoptSave(session, not self._modSaveAdopted)
      self._modSaveAdopted = true
      self.sessionStartedAt = os.time()
      self.questPlayback = QuestLog.begin(session)
      if self.questPlayback then
        self.session=session
        self.phase="quest_log"
        Audio.stopAll()
      else
        self:_enterField(session, "continue")
      end
      if modsDiff and SaveData.modsDiffNotice then
        local notice = SaveData.modsDiffNotice(modsDiff, save.meta)
        if notice then require("src.core.Logger").warn("%s", notice) end
      end
      if ModRuntime.wants("save.loaded") then
        ModRuntime.emit("save.loaded", { save = session, meta = session.meta, modsDiff = modsDiff })
      end
    end
    return
  end
  if action.action == "new_game" then
    local session = Schema.newGame({
      name = action.name or "RED",
      rivalName = action.rivalName or "BLUE",
      gender = action.gender or 0,
      start = action.start,
    })
    self:adoptSave(session, not self._modSaveAdopted)
    self._modSaveAdopted = true
    self.sessionStartedAt = os.time()
    if ModRuntime.wants("save.created") then
      ModRuntime.emit("save.created", { save = session })
    end
    self:_enterField(session, "new_game")
    return
  end
  if action.action == "exit" then
    Audio.stopAll()
    if self.returnToLauncher then
      self.returnToLauncher()
    elseif self.onExit then
      self.onExit()
    elseif love.event and love.event.quit then
      love.event.quit()
    end
    return
  end
end

function Game3:fixedUpdate(dt)
  self:_aliasLA()
  if ModRuntime.wantsHook("input.step") then
    ModRuntime.call("input.step", noop, self, dt or FixedStep.STEP)
  end
  if self.input and self.input.step then self.input:step() end
  if self.phase == "arena" then
    if self.session then Audio.applyOptions(self.session) end
    if self.arena then self.arena:update(dt) end
    return
  end
  if (self.input and self.input.softResetStep and self.input:softResetStep()) or self.softResetRequested then
    self.softResetRequested = nil
    if self.input then self.input:reset() end
    if self.touchControls then self.touchControls:reset() end
    self:returnToTitle()
    return
  end
  if self.phase == "quest_log" then
    local p=self.questPlayback
    local scene=p:current()
    Audio.applyOptions(self.session)
    if scene and scene.song then Audio.playSong(scene.song) end
    Audio.pumpBgm()
    p:update({a=self.input:wasPressed("a"),b=self.input:wasPressed("b")})
    if p.done then
      self.questPlayback=nil
      self.input:reset()
      self:_enterField(self.session,"continue")
    end
    return
  end
  if Help.update(self) then
    -- Keep streaming BGM fed without advancing fanfare/script callbacks.
    Audio.pumpBgm()
    return
  end
  if self.session then Audio.applyOptions(self.session) end

  local Rng = require("src.core.game3.rng")
  Rng.step()

  if self.phase == "boot" and self.boot then
    local action = Boot.update(self.boot, self.input, dt)
    self:_handleBootAction(action)
    return
  end

  if self.phase == "field" then
    self:_handleRegisteredItem()
    if Runtime.isActive() then
      Runtime.update(dt)
      QuestRecorder.update(self)
    end
  end
end

function Game3:speedCategory()
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if okB and Battle and Battle.isActive and Battle.isActive() then
    return "battle"
  end
  if self.phase == "field" then return "overworld" end
  return "menu"
end

function Game3:isFixedSpeed()
  if self.phase == "arena" then return true end
  local Link = package.loaded["src.core.game3.link"]
  if type(Link) == "table" and Link.link ~= nil then return true end
  local MG = package.loaded["src.core.game3.minigames.common"]
  return type(MG) == "table" and MG.isActive ~= nil and MG.isActive() == true
end

function Game3:logicSpeed()
  if self:isFixedSpeed() then return 1 end
  local override = tonumber(self.speedOverride)
  if override then return math.max(1, override) end
  local b = self.phase == "boot" and self.boot
  if b and (b.phase == Boot.PHASE.INTRO or b.phase == Boot.PHASE.TITLE
      or b.phase == Boot.PHASE.TITLE_CRY or b.phase == Boot.PHASE.TITLE_RESTART) then
    return 1
  end
  local GameSpeed = require("src.core.GameSpeed")
  local opts = self.options
  if type(opts) ~= "table" then return 1 end
  local key = GameSpeed.optionKey(self:speedCategory())
  return math.max(1, GameSpeed.clamp(opts[key]))
end

function Game3:_cycleSpeed(dir)
  if type(self.options) ~= "table" then return end
  local GameSpeed = require("src.core.GameSpeed")
  local key = GameSpeed.optionKey(self:speedCategory())
  self.options[key] = GameSpeed.cycle(self.options[key], dir)
  self:writeOptions()
end

function Game3:zoomGateOK()
  if self.phase ~= "field" then return false end
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if okB and Battle and Battle.isActive and Battle.isActive() then return false end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return false end
  local Shop = package.loaded["src.ui.game3.shop_menu"]
  if Shop and Shop.isShopCamera and Shop.isShopCamera() then return false end
  return true
end

function Game3:zoomStep(delta)
  if not self:zoomGateOK() then return end
  local Zoom = require("src.render.Zoom")
  local Renderer = require("src.render.Renderer")
  local offset = Zoom.step(delta, Renderer:fitScale())
  if type(self.options) == "table" then
    self.options.zoom = offset
    self:writeOptions()
  end
end

function Game3:update(dt)
  local speed = self:logicSpeed()
  FixedStep.maxAccum = FixedStep.catchupLimit(speed)
  FixedStep:update(dt, speed)
  self._audioAccum = (self._audioAccum or 0) + dt
  local STEP = 1 / 60
  local guard = 0
  while self._audioAccum >= STEP and guard < 8 do
    self._audioAccum = self._audioAccum - STEP
    guard = guard + 1
    local okA, errA = pcall(Audio.update, STEP)
    if not okA then s9log("audio", errA) end
  end
  if self._audioAccum > 0.25 then self._audioAccum = 0 end
  local okT, errT = pcall(function() require("src.render.Tilt").update(dt) end)
  if not okT then s9log("tilt", errT) end
  pcall(function() require("src.core.DiscordPresence").update(dt) end)
end

function Game3:_drawHud(w, h)
  if not ModRuntime.wantsHook("render.hud") then return end
  local scale, ox, oy, _, _, scaleY = Display.fit(w, h)
  local viewport = {
    width = w, height = h,
    gameX = ox, gameY = oy,
    gameWidth = Display.W * scale, gameHeight = Display.H * (scaleY or scale),
    scale = scale,
  }
  love.graphics.push("all")
  local okR, errR = pcall(function() ModRuntime.call("render.hud", noop, self, viewport) end)
  if not okR then s9log("render.hud", errR) end
  love.graphics.pop()
end

function Game3:draw()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()

  if self.phase == "arena" then
    if self.arena then self.arena:draw(w, h) end
    self:_drawHud(w, h)
    if self.touchControls then self.touchControls:draw() end
    return
  end

  if self.phase == "quest_log" or (self.phase == "boot" and self.boot) then
    local kind = (self.phase == "quest_log") and "quest" or "boot"
    local function drawBootFrame()
      if self.phase == "quest_log" then QuestLog.draw(self.questPlayback,self.session)
      elseif Help.isOpen() then Help.draw() else Boot.draw(self.boot) end
    end
    if not Display.presentUi(self, w, h, kind, drawBootFrame) then
      local canvas = Display.ensureCanvas("main")
      if canvas then
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.origin()
        drawBootFrame()
        love.graphics.setCanvas()
        love.graphics.pop()
        local scale, ox, oy, _, _, scaleY = Display.fit(w, h)
        love.graphics.setColor(0.02, 0.04, 0.08, 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, ox, oy, 0, scale, scaleY)
      else
        drawBootFrame()
      end
    end
    self:_drawHud(w, h)
    if self.touchControls then
      self.touchControls:draw()
    end
    return
  end

  if Runtime.isActive() then
    if Display.present(self, w, h) then
      self:_drawHud(w, h)
      if self.touchControls then
        self.touchControls:draw()
      end
      return
    end
  end

  love.graphics.clear(0.05, 0.05, 0.12)
  love.graphics.setColor(0.4, 0.8, 0.4)
  local map = self.session and self.session.map or "?"
  love.graphics.printf("Fire Red field: " .. tostring(map), 0, h * 0.45, w, "center")
  self:_drawHud(w, h)
  if self.touchControls then
    self.touchControls:draw()
  end
end

function Game3:_hotkey(key)
  local hk = Input.hotkeyKey(key)
  if key == "f1" then
    if self.phase == "field" and self:saveOffered() then self:saveGame() end
    return true
  elseif key == "f2" then
    if self.phase == "field" then
      pcall(function() require("src.ui.game3.stack").clear() end)
      pcall(function()
        local R = require("src.core.game3.runtime")
        if R.stop then R.stop(nil, self) end
      end)
      pcall(function() require("src.core.game3.ghosts").clear() end)
      self:_handleBootAction({ action = "continue" })
    end
    return true
  elseif hk == "1" then
    self:_cycleSpeed(1)
    return true
  elseif hk == "3" then
    if self:zoomGateOK() then
      local Tilt = require("src.render.Tilt")
      Tilt.cycle()
      if type(self.options) == "table" then
        self.options.tilt = Tilt.level
        self:writeOptions()
      end
    end
    return true
  elseif hk == "4" then
    if self:zoomGateOK() then
      local Zoom = require("src.render.Zoom")
      local Renderer = require("src.render.Renderer")
      local offset = Zoom.cycle(Renderer:fitScale())
      if type(self.options) == "table" then
        self.options.zoom = offset
        self:writeOptions()
      end
    end
    return true
  elseif key == "-" or key == "kp-" then
    self:zoomStep(-1)
    return true
  elseif key == "=" or key == "kp+" then
    self:zoomStep(1)
    return true
  end
  return false
end

function Game3:keypressed(key)
  local function vanilla()
    if self:_hotkey(key) then return end
    if self.input and self.input.keypressed then self.input:keypressed(key) end
  end
  if not ModRuntime.wantsHook("input.key") then return vanilla() end
  return ModRuntime.call("input.key", vanilla, self, { phase = "pressed", key = key })
end
function Game3:keyreleased(key)
  local function vanilla()
    if self.input and self.input.keyreleased then self.input:keyreleased(key) end
  end
  if not ModRuntime.wantsHook("input.key") then return vanilla() end
  return ModRuntime.call("input.key", vanilla, self, { phase = "released", key = key })
end

function Game3:_padPressedBody(joystick, button)
  if self.touchControls then self.touchControls:noteGamepad() end
  local Input2 = self.input
  if not Input2 then return end
  local selectHeld = Input2.isDown and Input2:isDown("select")
  if not selectHeld and joystick and joystick.isGamepadDown then
    local ok, down = pcall(function() return joystick:isGamepadDown("back") end)
    selectHeld = ok and down == true
  end
  local isShoulder = button == "leftshoulder" or button == "rightshoulder"
  if not selectHeld and not isShoulder and Input2.padAction then
    local action = Input2:padAction(button)
    if action == "speedUp" then
      self:_cycleSpeed(1)
      return
    elseif action == "speedDown" then
      self:_cycleSpeed(-1)
      return
    end
  end
  if selectHeld then
    local GamepadMap = require("src.core.GamepadMap")
    local digit = GamepadMap.displayChordDigit(button)
    if digit and self:_hotkey(digit) then return end
  end
  if Input2.gamepadpressed then Input2:gamepadpressed(joystick, button) end
end

function Game3:_padReleasedBody(joystick, button)
  if self.input and self.input.gamepadreleased then
    self.input:gamepadreleased(joystick, button)
  end
end

function Game3:gamepadpressed(joystick, button)
  if self.input and self.input.padEventSeen then self.input:padEventSeen(button) end
  local function vanilla() self:_padPressedBody(joystick, button) end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "pressed", joystick = joystick, button = button })
end
function Game3:gamepadreleased(joystick, button)
  local function vanilla() self:_padReleasedBody(joystick, button) end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "released", joystick = joystick, button = button })
end

-- pokefirered/src/start_menu.c:198
function Game3:saveOffered()
  local session = (Runtime.getSession and Runtime.getSession()) or self.session
  return require("src.ui.game3.start_menu").saveOffered(session, self)
end

function Game3:saveGame()
  if not self.session or self.phase == "quest_log" or self.phase == "arena" then return end
  if ModRuntime.wantsHook("save.write")
      and ModRuntime.call("save.write", function() return true end, self) == false then
    return false
  end
  if Runtime.getSession then
    local s = Runtime.getSession()
    if s then self.session = s end
  end
  pcall(function()
    require("src.core.game3.scripting.space").persistSession(nil, self)
  end)
  QuestRecorder.save(self)
  local save = Schema.toSaveTable(self.session)
  if SaveData.buildMeta then
    save.meta = SaveData.buildMeta(
      self.modStatus and self.modStatus.loaded, save.meta, self.sessionStartedAt)
    self.session.meta = save.meta
  end
  self.save = save
  if ModRuntime.wants("save.writing") then
    ModRuntime.emit("save.writing", { save = save, meta = save.meta })
  end
  if not SaveData.save then return false end
  local ok, written = pcall(SaveData.save, save)
  return ok and written ~= false
end

function Game3:resize() end

function Game3:mousepressed(x, y, button, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchpressed("mouse", x, y)
  end
end

function Game3:mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchmoved("mouse", x, y)
  end
end

function Game3:mousereleased(x, y, button, istouch)
  if istouch then return end
  if os.getenv("POKEPORT_TOUCH") == "1" and self.touchControls then
    self.touchControls:touchreleased("mouse", x, y)
  end
end

function Game3:wheelmoved(_, dy)
  if type(dy) ~= "number" then return end
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
function Game3:textinput() end
function Game3:filedropped() end

function Game3:touchpressed(id, x, y, dx, dy, pressure)
  if self.touchControls and self.touchControls:touchpressed(id, x, y) then return end
end

function Game3:touchmoved(id, x, y, dx, dy, pressure)
  if self.touchControls then self.touchControls:touchmoved(id, x, y) end
end

function Game3:touchreleased(id, x, y, dx, dy, pressure)
  if self.touchControls then self.touchControls:touchreleased(id, x, y) end
end

function Game3:gamepadaxis(joystick, axis, value)
  local function vanilla()
    if math.abs(value) > 0.5 and self.touchControls then
      self.touchControls:noteGamepad()
    end
    if self.input and self.input.triggerAxis then
      local trigger, phase = self.input:triggerAxis(axis, value)
      if trigger then
        if phase == "pressed" then
          self:_padPressedBody(joystick, trigger)
        elseif phase == "released" then
          self:_padReleasedBody(joystick, trigger)
        end
        return
      end
    end
    if self.input and self.input.gamepadaxis then self.input:gamepadaxis(joystick, axis, value) end
  end
  if not ModRuntime.wantsHook("input.gamepad") then return vanilla() end
  return ModRuntime.call("input.gamepad", vanilla, self,
    { phase = "axis", joystick = joystick, axis = axis, value = value })
end

function Game3:joystickpressed(joystick, button)
  if self.touchControls then self.touchControls:noteGamepad() end
  local Input2 = self.input
  if Input2 and Input2.joyAction
      and not (Input2.isDown and Input2:isDown("select")) then
    local action = Input2:joyAction(button)
    if action == "speedUp" then
      self:_cycleSpeed(1)
      return
    elseif action == "speedDown" then
      self:_cycleSpeed(-1)
      return
    end
  end
  if Input2 and Input2.joystickpressed then Input2:joystickpressed(joystick, button) end
end

function Game3:joystickreleased(joystick, button)
  if self.input and self.input.joystickreleased then self.input:joystickreleased(joystick, button) end
end

function Game3:joystickaxis(joystick, axis, value)
  if math.abs(value) > 0.5 and self.touchControls then
    self.touchControls:noteGamepad()
  end
  if self.input and self.input.joystickaxis then self.input:joystickaxis(joystick, axis, value) end
end

function Game3:joystickhat(joystick, hat, direction)
  if direction ~= "c" and self.touchControls then
    self.touchControls:noteGamepad()
  end
  if self.input and self.input.joystickhat then self.input:joystickhat(joystick, hat, direction) end
end

function Game3:_releaseModInput()
  if self.mods and self.mods.releaseModInput then self.mods:releaseModInput() end
end

function Game3:joystickadded()
  self:_releaseModInput()
end

function Game3:joystickremoved(joystick)
  self:_releaseModInput()
  if self.touchControls then self.touchControls:joystickremoved() end
end

function Game3:focus(f)
  if self.input then self.input:reset() end
  if self.touchControls then self.touchControls:reset() end
  self:_releaseModInput()
  if f then
    if self.input then self.input:reconcile() end
    Audio.onFocusGained()
  end
end

function Game3:visible(v)
  if v then
    self:onResume()
  else
    if self.input then self.input:reset() end
    if self.touchControls then self.touchControls:reset() end
  end
end

function Game3:onResume()
  if self.input then
    self.input:reset()
    self.input:reconcile()
  end
  if self.touchControls then self.touchControls:reset() end
  Audio.onFocusGained()
end

local function closeFlag(flag)
  return function(m)
    m[flag] = false
    for k, v in pairs(m) do
      if type(k) == "string" and type(v) == "function" and k:match("^_on%u") then m[k] = nil end
    end
  end
end

local function dropField(field)
  return function(m) m[field] = nil end
end

-- pokefirered/src/main.c:480
local SOFT_RESET = {
  { "src.core.game3.battle.init", "reset" },
  { "src.core.game3.battle_bridge", "reset" },
  { "src.core.game3.battle_transition", "abort" },
  { "src.core.game3.task", "clear" },
  { "src.core.game3.step_events", "flush" },
  { "src.core.game3.field_move_show_mon", "reset" },
  { "src.core.game3.pokecenter_heal", dropField("_fx") },
  { "src.core.game3.ss_anne_cutscene", "reset" },
  { "src.core.game3.itemfinder", "reset" },
  { "src.core.game3.special_field_anim", "stopEscalator" },
  { "src.core.game3.pc_anim", "reset" },
  { "src.core.game3.camera_object", "reset" },
  { "src.core.game3.trade_scene", "cancel" },
  { "src.core.game3.scripting.natives_listmenu", "close" },
  { "src.ui.game3.hud", "clearWaitButton" },
  { "src.ui.game3.mon_pic", "hide" },
  { "src.ui.game3.seagallop", "stop" },
  { "src.ui.game3.map_preview_screen", "reset" },
  { "src.ui.game3.cave_transition", "clear" },
  { "src.ui.game3.map_name_popup", "dismiss" },
  { "src.ui.game3.help_window", "reset" },
  { "src.ui.game3.whiteout_rush", dropField("_state") },
  { "src.ui.game3.trade_scene", "close" },
  { "src.ui.game3.shop_menu", "reset" },
  { "src.ui.game3.choice", "reset" },
  { "src.ui.game3.message", "reset" },
  { "src.ui.game3.money_box", "hide" },
  { "src.ui.game3.coins_box", "hide" },
  { "src.ui.game3.elevator_window", "hide" },
  { "src.ui.game3.berry_powder_box", "hide" },
  { "src.ui.game3.minigame_records", "reset" },
  { "src.ui.game3.hall_of_fame", "reset" },
  { "src.ui.game3.hall_of_fame_pc", "reset" },
  { "src.ui.game3.credits", "reset" },
  { "src.ui.game3.start_menu", closeFlag("open") },
  { "src.ui.game3.start_menu", "resetCursor" }, -- pokefirered/src/start_menu.c:64
  { "src.ui.game3.bag_menu", closeFlag("open") },
  { "src.ui.game3.berry_pouch", closeFlag("open") },
  { "src.ui.game3.tm_case", closeFlag("open") },
  { "src.ui.game3.party_menu", closeFlag("open") },
  { "src.ui.game3.summary_menu", closeFlag("open") },
  { "src.ui.game3.pokedex", closeFlag("open") },
  { "src.ui.game3.option_menu", closeFlag("open") },
  { "src.ui.game3.save_menu", closeFlag("open") },
  { "src.ui.game3.trainer_card", closeFlag("open") },
  { "src.ui.game3.pc_menu", closeFlag("open") },
  { "src.ui.game3.item_pc", closeFlag("open") },
  { "src.ui.game3.box_storage_ui", closeFlag("open") },
  { "src.ui.game3.region_map", closeFlag("open") },
  { "src.ui.game3.daycare_menu", closeFlag("open") },
  { "src.ui.game3.fame_checker", closeFlag("open") },
  { "src.ui.game3.move_relearner", closeFlag("open") },
  { "src.ui.game3.egg_hatch", closeFlag("open") },
  { "src.ui.game3.evolution_scene", closeFlag("open") },
  { "src.ui.game3.diploma", closeFlag("open") },
  { "src.ui.game3.trainer_tower_records", closeFlag("open") },
  { "src.ui.game3.teachy_tv", closeFlag("open") },
  { "src.ui.game3.slot_machine", closeFlag("open") },
  { "src.ui.game3.mod_manager", closeFlag("open") },
  { "src.ui.game3.prize_corner", "reset" },
  { "src.ui.game3.stat_growth", closeFlag("_open") },
  { "src.ui.game3.release_seq", function(m) m.active = false; m.onComplete = nil end },
  { "src.ui.game3.naming", closeFlag("openFlag") },
  { "src.ui.game3.easy_chat", closeFlag("openFlag") },
  { "src.ui.game3.fade", "clear" },
}

local function clearFieldScreens()
  for _, e in ipairs(SOFT_RESET) do
    local mod = package.loaded[e[1]]
    if type(mod) == "table" then
      local fn = e[2]
      if type(fn) == "string" then
        if mod[fn] then pcall(mod[fn]) end
      else
        pcall(fn, mod)
      end
    end
  end
  local LeagueLighting = package.loaded["src.core.game3.league_lighting"]
  if LeagueLighting and LeagueLighting.reset then pcall(LeagueLighting.reset) end
  local Map = require("src.core.game3.map")
  Map.disableMusicChange = Map.MUSIC_DISABLE_OFF
  local FieldView = require("src.core.game3.field_view")
  FieldView.hideActors = false
  FieldView.setCameraPanning(0, 0)
end

function Game3:returnToTitle()
  self.questPlayback=nil
  Help.reset()
  Audio.stopAll()
  local Stack = require("src.ui.game3.stack")
  Stack.clear()
  clearFieldScreens()
  if Runtime.isActive() then
    Runtime.stop(nil, self)
  end
  local Objects = package.loaded["src.core.game3.objects"]
  if Objects and Objects.reset then pcall(Objects.reset) end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.clearMetatiles then pcall(Field.clearMetatiles) end
  self.phase = "boot"
  self.session = nil

  local okLoad, rawSave, recovered = false, nil, nil
  if SaveData.load then okLoad, rawSave, recovered = pcall(SaveData.load) end
  if not okLoad then rawSave, recovered = nil, nil end
  local saveStatus = "ok"
  if recovered then
    saveStatus = "error"
  elseif okLoad and rawSave == nil and SaveData.persistenceFs and SaveData.saveFilename then
    local okFs, exists = pcall(function()
      local fs = SaveData.persistenceFs(nil)
      return fs and fs.getInfo and fs.getInfo(SaveData.saveFilename()) ~= nil
    end)
    if okFs and exists then saveStatus = "invalid" end
  end
  local continueOk = self:_hasContinueSave()
  require("src.ui.game3.start_menu").resetCursor()
  self.boot = Boot.new()
  Boot.setHasContinue(self.boot, continueOk)
  if continueOk then
    Boot.setContinueInfo(self.boot, Boot.continueInfoFromSave(rawSave))
  end
  Boot.setSaveStatus(self.boot, saveStatus)
  Boot.setTextSpeed(self.boot, Options.block(self.options).textSpeed)
  self.boot.phase = Boot.PHASE.TITLE
  self.boot.timer = 0
  local TitleScreen = require("src.ui.game3.title_screen")
  TitleScreen.enter(self.boot)
end

function Game3:reset()
  self.questPlayback = nil
  Help.reset()
  Audio.endSession()
  require("src.ui.game3.stack").clear()
  clearFieldScreens()
  local WarpMod = package.loaded["src.core.game3.warp"]
  if WarpMod and WarpMod.clear then pcall(WarpMod.clear) end
  local DoorsMod = package.loaded["src.core.game3.doors"]
  if DoorsMod and DoorsMod.release then pcall(DoorsMod.release) end
  if Runtime.isActive() then
    pcall(function() Runtime.stop(nil, self) end)
  end
  local Ghosts = package.loaded["src.core.game3.ghosts"]
  if Ghosts and Ghosts.clear then pcall(Ghosts.clear) end
  for _, name in ipairs({ "src.core.game3.oam", "src.core.game3.bg", "src.core.game3.objects" }) do
    local mod = package.loaded[name]
    if mod and mod.reset then pcall(mod.reset) end
  end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.clearMetatiles then pcall(Field.clearMetatiles) end
  Display.release()
  if self.touchControls then
    pcall(function() self.touchControls:setHotkeyHandler(nil) end)
    self.touchControls = nil
  end
  self.boot = nil
  self.arena = nil
  self.session = nil
  self.data = nil
  self.mods = nil
  self.modStatus = nil
  self._modSaveAdopted = nil
  self.phase = "boot"
  self.returnToLauncher = nil
  self.onExit = nil
end

function Game3:quit()
  self:saveGame()
end

return Game3

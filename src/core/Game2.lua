-- Gold's service owner: the Gen 2 peer of src/core/Game.lua.  It owns the
-- data tables, input, state stack, world and save state for a Gold boot, and
-- everything under src/*/gen2 reaches shared services through here.  Gen 1
-- Game:load cannot consume a Gen 2 cache -- different generated tables, save
-- shape and screen registry -- so main.lua's bootGame picks this owner when
-- GameVersion.isGold(), and the two never branch into each other.
--
-- Boot: copyright → GameFreak Presents → GS intro stub → title
-- (tilemap + Ho-Oh flap / clouds / trails) → Oak speech (Marill + shrink)
-- → name pick → New Bark Town via src/world/gen2/World.lua.
--
-- IMPORTANT: do not use a catch-all __index that returns functions.  main.lua
-- also reads optional fields like Game.capturePath every frame; a truthy
-- function there is treated as a path and crashes io.open.

local AutoInput = require("src.core.gen2.AutoInput")
local Chrome = require("src.ui.gen2.Chrome")
local Clock = require("src.core.gen2.Clock")
local FixedStep = require("src.core.FixedStep")
local Font = require("src.render.Font")
local Input = require("src.core.Input")
local Music = require("src.core.Music")
local Save = require("src.core.gen2.Save")
local StateStack = require("src.core.StateStack")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
-- The mobile on-screen pad, shared with Gen 1 rather than reimplemented: the
-- same module, the same Xelu CC0 art under assets/touch/, the same
-- options.touchControls layout the launcher's editor writes, and the same
-- Input:overlayPressed source names.  A player who lays the pad out in Red
-- finds it in the same place in Gold.
local TouchControls = require("src.core.TouchControls")
local World = require("src.world.gen2.World")

-- The mod event/hook buses.  Gold reaches them through Runtime like every
-- other engine file, so a call site here is the same call site Gen 1 has.
local ModRuntime = require("src.mods.Runtime")
local GameViewport = require("src.render.GameViewport")
-- Only for the mod-supplied save migrations and the mods-changed report, which
-- are keyed off save.meta and know nothing about a generation; Gold's own save
-- IO is src/core/gen2/Save.lua.
local SaveData = require("src.core.SaveData")

-- Every Gold screen this file opens goes through a src/ui/Screens.lua id
-- rather than a direct require, the same contract the Gen 1 path has: the id
-- is what a mod registers a replacement under, and the boot cinema, the START
-- menu and its submenus are exactly the screens a reskin wants.  Screens.push
-- resolves the registry, falls back to src/ui/gen2/<name>.lua when nothing is
-- registered, degrades a broken mod screen back to that builtin, and lands the
-- instance on self.stack -- so these call sites keep the push semantics they
-- had when they required the module by hand.
local Screens = require("src.ui.Screens")

local Game2 = {}
Game2.__index = Game2

local function noop() end

for _, name in ipairs({
  "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat",
  "joystickadded",
}) do
  Game2[name] = noop
end

-- Not a noop, because the overlay has to come back on its own: a player who
-- unplugs the only controller would otherwise have to tap a blind screen to
-- get the pad back (src/core/Game.lua:869 does the same).
function Game2:joystickremoved()
  TouchControls:joystickremoved()
end

-- THE FRAME AND INPUT SEAMS.
--
-- Gold composites its own frame (Game2:draw / drawScene) and pumps its own pad
-- (the FixedStep callback in Game2:load), so none of it goes through
-- src/render/Renderer.lua or src/core/Game.lua.  That explains why the hooks
-- below never used to fire here; it is not a reason they should not.  A
-- hook is a contract about a MOMENT in the frame, and Gold has every one of
-- these moments -- so each is raised under the Gen 1 NAME with the Gen 1
-- PAYLOAD, at the Gen 1 point in the order:
--
--   input.step       before the pad is read          (src/core/Game.lua:191)
--   input.pointer    uncaptured pointer events       (src/core/Game.lua:887)
--   render.zones     the palette pass, pre-blit      (src/core/Game.lua:505)
--   render.compose   the whole-window composite      (Renderer.lua:759)
--   render.output*   the normal composed frame       (Renderer.lua:1063)
--   render.letterbox the void around the 160x144 blit (Renderer.lua:840)
--   render.hud       screen-space UI over the frame  (src/core/Game.lua:521)
--   render.viewport  the game's OS-window rectangle  (GameViewport.lua:52)
--   render.window    final OS-window composition     (GameViewport.lua:145)
--
-- Where Gold genuinely cannot tell two Gen 1 things apart -- it composites the
-- world pass and the UI into ONE canvas, not two -- the call site says so and
-- fills both keys with what it does have, rather than inventing a second name.

-- vanilla for input.pointer: nobody consumed the event (src/core/Game.lua:882)
local function pointerUnclaimed() return false end

-- render.zones' identity default: unhooked, the zone list reaches the present
-- pass exactly as the frame computed it (src/core/Game.lua:278)
local function sameZones(_, zones) return zones end

-- Gold runs the engine's own src/core/StateStack.lua, not a private stack.
-- It already draws bottom-up from the topmost opaque state, which is the
-- behavior the boot cinema needs (Oak's pic stays under a TextBox), and going
-- through it is what gives Gold screen.pushed / screen.popped and the
-- screen.render_visible hook for free -- the same three a mod gets in Gen 1.
-- Push semantics are identical; the exit callback is named `exit` there and
-- no Gold screen defines one.
local function makeStack()
  StateStack:init()
  return StateStack
end

local function visibleBaseState(stack)
  if not stack then return nil end
  local state = stack.states[stack:visibleBase()]
  return stack:renderVisible(state) and state or nil
end

local function loadGenerated(path)
  -- CacheFs.loadActive, not love.filesystem.load: Gold's cache lives under
  -- gold/ and fused NX often cannot mount that tree onto data/generated/.
  local CacheFs = require("src.import.CacheFs")
  local data = CacheFs.loadActive(path)
  return data
end

-- NewGame (engine/menus/intro_menu.asm) calls OakSpeech, and OakSpeech's first
-- line is `farcall InitClock`: wStartHour / wStartMinute are anchored before
-- InitializeWorld runs, on every new game there is.  A run that never reaches
-- that screen -- a driver with the boot cinema skipped -- would leave the base
-- unset, and Clock reads an unanchored save straight off the host clock, so the
-- same new game is MORN on one run and NITE on the next (which mon a patch of
-- grass rolls follows from that).  Anchor with InitClock's own 10 AM default so
-- every run mode starts on the same clock the cinema's default would have set.
--
-- POKEPORT_GOLD_HOUR anchors here as well as pinning World:hour, so the
-- Pokegear card and the main menu box agree with the light outside; the day
-- stays wStartDay 0 (the host weekday), because InitDayOfWeek is Mom's wheel
-- and not part of New Game.
local function anchorNewGameClock(save)
  if Clock.isSet(save) then return false end
  local forced = tonumber(os.getenv("POKEPORT_GOLD_HOUR") or "")
  return Clock.setTime(save, forced or Clock.DEFAULT_HOUR,
    Clock.DEFAULT_MINUTE)
end
Game2.anchorNewGameClock = anchorNewGameClock

function Game2.new()
  local self = setmetatable({
    speedOverride = nil,
    capturePath = nil,
    world = nil,
    status = nil,
    phase = "boot", -- boot | play | error
    input = Input,
    -- The automated joypad stream (home/joypad.asm).  Owned here rather than
    -- by the World so an armed stream survives the map reload a script can do
    -- while it is running, and so the boot cinema shares one ring with play.
    autoInput = AutoInput.new(),
    stack = makeStack(),
    -- A real save arrives from CONTINUE or Save.newGame; this skeleton only
    -- has to survive the boot cinema, which reads player.name.
    save = Save.newGame(),
    -- No `tokens` here, deliberately.  It is the tokens registry's Data
    -- target, and src/mods/Builtins.lua seeds that registry from
    -- TextBox.registerInto on both generations -- so a table sitting here
    -- before the merge is a BASE the registry folds against, and every one of
    -- those seed registrations then collides ("tokens already registered:
    -- RIVAL") and takes the whole mod subsystem down with it.  Gen 1 has no
    -- Data.tokens before the merge either; the merge is what creates it.
    -- TextBox.substitute falls back to TextBox.TOKENS while it is absent,
    -- which covers the window before mods:load, and nothing draws text in it.
    data = { audio = {}, pokemon = {} },
    titleData = nil,
    oakSpeechData = nil,
    fontData = nil,
    -- Options live in options.lua under `gold`, not in the save file: they
    -- survive New Game, and the launcher's gear edits the same block before
    -- the game boots.  The save keeps a reference so the OPTION screen and
    -- anything holding a save still read one table.
    options = Save.loadOptions(),
  }, Game2)
  self.save.options = self.options
  anchorNewGameClock(self.save)
  return self
end

-- Persist the option block.  Called from every place that changes it -- the
-- OPTION screen, the hotkey ladder, the pad's speed buttons -- rather than
-- from applyOptions, which also runs on boot and on CONTINUE where there is
-- nothing new to write.
function Game2:persistOptions()
  pcall(Save.saveOptions, self.options)
end

-- Point the loader's mod.save backing at this save's modData so per-mod state
-- persists with the slot.  Same contract and same three call sites as Gen 1
-- (src/core/Game.lua:990): seedBuckets is boot-only and keeps what entry
-- chunks wrote before any save existed, NEW GAME and CONTINUE replace the
-- backing outright.  src/core/gen2/Save.lua serializes the whole table and
-- Save.normalize keeps keys it does not know, so modData round-trips.
function Game2:adoptSave(save, seedBuckets)
  if not save then return end
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

function Game2:startWorld()
  if self.world and self.world.map then
    self.phase = "play"
    return true
  end
  self.world = World.new(self)
  if not self.world:load() then
    self.status = self.world.status
    self.phase = "error"
    return false
  end
  self.phase = "play"
  return true
end

function Game2:showOakSpeech()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2OakSpeech", {
    data = self.oakSpeechData or {},
    font = self.fontData,
    onDone = function()
      self.stack:clear()
      self:startWorld()
    end,
  })
end

-- NEW GAME: a fresh save, then the Oak speech (which collects the name), then
-- SPAWN_HOME.  engine/menus/intro_menu.asm NewGame is this same order.
function Game2:newGame()
  self.save = Save.newGame({ playerName = self.save.player.name })
  self.save.options = self.options
  -- InitClock re-anchors this the moment the player answers Oak; the default
  -- only has to hold for a run that skips the screen.
  anchorNewGameClock(self.save)
  -- Where Gen 1 emits it on NEW GAME (src/core/Game.lua:158): the skeleton is
  -- finished and adopted, nothing has been pushed yet.  save.new_game already
  -- fired inside Save.newGame, so a mod that reshaped the skeleton sees its
  -- own work in this payload.  Same name, same `save` key as Gen 1.
  -- No bucket carry-over, for the reason Gen 1 gives (src/core/Game.lua:155):
  -- state from an abandoned session must not leak into a fresh slot.
  self:adoptSave(self.save)
  ModRuntime.emit("save.created", { save = self.save })
  self:showOakSpeech()
end

-- CONTINUE: adopt the loaded save and drop straight into the world at the
-- position it recorded (World:load reads save.position).
function Game2:continueGame(save)
  if not save then
    self:newGame()
    return
  end
  -- Gen 1 raises this from Game:restoreSave (src/core/Game.lua:1079) at the
  -- same point: the file is off disk and migrated but not yet adopted, so a
  -- mod still has a window to repair its own data in `raw`.  Gold's read
  -- happens in the caller (the intro menu's CONTINUE row, the F2 hotkey), the
  -- way Gen 1's happens in SaveData.load before restoreSave is reached.
  if ModRuntime.wants("save.loading") then
    ModRuntime.emit("save.loading", { raw = save })
  end
  -- Mod chains replay before the world stands, where Gen 1 runs them
  -- (src/core/Game.lua:1076): a mod repairs its own data before anything reads
  -- it.  Generation-blind -- these are mod-supplied functions keyed off
  -- save.meta -- so there is no Gen 2 variant to write.
  local activeMods = self.modStatus and self.modStatus.loaded
  SaveData.runMigrations(save, self.mods and self.mods.migrations, activeMods)
  local modsDiff = SaveData.modsDiff(save, activeMods)
  self.save = save
  self:adoptSave(save)
  -- Editor species swaps used to leave mon.name on the previous species.
  -- CONTINUE rewrites party, boxes, and Day-Care copies from the live record.
  require("src.battle.gen2.Mon").syncSaveIdentity(save, self.data)
  -- options.lua wins over anything a save file carries: options are a display
  -- preference that survives New Game and is edited from the launcher, so a
  -- save written before they moved out must not drag old values back in.
  self.save.options = self.options
  self:applyOptions()
  self.stack:clear()
  self.world = nil
  self:startWorld()
  -- After the adopt and after the world is standing, which is where Gen 1
  -- emits it (src/core/Game.lua:1127, once the stack has been rebuilt).
  -- `meta` stays absent on a Gold save, which stamps no meta block; modsDiff
  -- is derived from it and so comes back empty rather than missing.
  if modsDiff then
    local notice = SaveData.modsDiffNotice(modsDiff, save.meta)
    if notice then require("src.core.Logger").warn("%s", notice) end
  end
  if ModRuntime.wants("save.loaded") then
    ModRuntime.emit("save.loaded",
      { save = save, meta = save.meta, modsDiff = modsDiff })
  end
end

function Game2:showMainMenu()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2MainMenu", {
    onNewGame = function() self:newGame() end,
    onContinue = function(save) self:continueGame(save) end,
    onOption = function() self:showOptions(function() self:showMainMenu() end) end,
  })
end

-- QUIT from the START menu: back to the title like a power-cycle, with
-- everything since the last save discarded.  Same contract as Game:returnToTitle
-- in the Gen 1 path, so the two generations' QUIT rows behave identically.
function Game2:returnToTitle()
  Music.stop()
  self.stack:clear()
  self.world = nil
  self:showTitle()
end

-- Reset (home/init.asm:1-14) falls into Init -> GameInit -> IntroSequence
-- (engine/menus/intro_menu.asm:1140-1143, :848-849): copyright splash, not title.
function Game2:softReset()
  Music.stop()
  self.stack:clear()
  self.world = nil
  self:showCopyright()
end

function Game2:showOptions(onDone)
  Screens.push(self, "Gen2OptionsMenu", {
    options = self.options,
    onDone = function(options)
      self.options = options
      if self.save then self.save.options = options end
      self:applyOptions()
      self:persistOptions()
      if onDone then onDone() end
    end,
  })
end

function Game2:showTitle()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2TitleState", {
    title = self.titleData or {},
    onContinue = function()
      self:showMainMenu()
    end,
  })
end

function Game2:showIntro()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2GoldSilverIntro", {
    onDone = function()
      self:showTitle()
    end,
  })
end

function Game2:showGameFreak()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2GameFreakPresents", {
    title = self.titleData or {},
    oakSpeech = self.oakSpeechData or {},
    onDone = function()
      self:showIntro()
    end,
  })
end

function Game2:showCopyright()
  self.stack:clear()
  self.phase = "boot"
  Screens.push(self, "Gen2CopyrightSplash", {
    title = self.titleData or {},
    onDone = function()
      self:showGameFreak()
    end,
  })
end

-- START in the overworld.  The submenus each push themselves and pop back to
-- the start menu, matching .MenuReturns (most entries reopen it; SAVE and EXIT
-- close it).
function Game2:openStartMenu()
  Screens.push(self, "Gen2StartMenu", {
    save = self.save,
    onClose = function() self.stack:pop() end,
    onChoose = function(id) self:openStartMenuItem(id) end,
  })
end

function Game2:openStartMenuItem(id)
  local function back() self.stack:pop() end
  if id == "pokedex" then
    Screens.push(self, "Gen2PokedexMenu", { onClose = back })
  elseif id == "pokemon" then
    -- The field list is the one flavour that opens PokemonActionSubmenu on A
    -- (engine/pokemon/mon_menu.asm) rather than answering to a caller.
    Screens.push(self, "Gen2PartyMenu", {
      prompt = "choose", submenu = true, onCancel = back,
    })
  elseif id == "pack" then
    Screens.push(self, "Gen2PackMenu", {
      onClose = back,
      onChoose = function(itemId) self:useFieldItem(itemId) end,
    })
  elseif id == "pokegear" then
    Screens.push(self, "Gen2Pokegear", {
      onClose = back,
      currentLandmark = self:currentLandmark(),
      onCall = function(call) return self:runPokegearCall(call) end,
    })
  elseif id == "status" then
    Screens.push(self, "Gen2TrainerCard", { onClose = back })
  elseif id == "save" then
    Screens.push(self, "Gen2SaveMenu", {
      save = self:snapshotSave(),
      -- The screen's default writer is Save.save; route it through writeSave
      -- so the save.write veto and the save.writing event fire at the moment
      -- the cart writes (between the two SAVING messages) rather than when
      -- the menu opened.  It re-snapshots, which costs nothing and cannot go
      -- stale if a script moved the player while the box was up.
      writer = function() return self:writeSave() end,
      onDone = function()
        self.stack:pop() -- the save screen
        self.stack:pop() -- and the start menu, like .Exit does
      end,
    })
  elseif id == "option" then
    self:showOptions(back)
  elseif id == "mods" then
    Screens.push(self, "ManagerState")
  end
end

-- MakePhoneCallFromPokegear's .DoPhoneCall (engine/phone/phone.asm): the
-- contact's SCRIPT1 runs while the Pokegear keeps the screen -- on the cart
-- through ExecuteCallbackScript, here through the overworld VM, whose text
-- pages are TextBox states pushed OVER the card, exactly the stack they ride
-- over the overworld.  Only a connected call ("call" without the wrong-number
-- fallback) has a script to run; the out-of-area / just-talk kinds keep the
-- card's own one-line answer.  wCurCaller rides vm.curPhoneCaller so
-- GetCallerLocation's two specials know who picked up, and A/B afterwards is
-- PokegearPhone_FinishPhoneCall's hang-up, unchanged.
function Game2:runPokegearCall(call)
  if not (call and call.kind == "call") or call.wrongNumber then return false end
  local world = self.world
  local vm = world and world.vm
  local key = call.scriptKey
  if not (vm and key and vm.scripts[key]) then return false end
  if vm:running() then return false end
  vm.curPhoneCaller = call.contact
  local ok = vm:start(key)
  if ok then call.ranScript = true end
  return ok
end

-- home/hm_moves.asm IsHMMove's .HMMoves.
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
  WATERFALL = true, WHIRLPOOL = true,
}

-- LearnMove (engine/pokemon/learn.asm): a free slot learns outright, a full
-- set runs ForgetMove's ask / pick / "Stop learning" loop.  onDone(true) is
-- the routine's own `ld b, 1`.
function Game2:learnMoveOn(mon, moveId, onDone)
  local Mon = require("src.battle.gen2.Mon")
  local moveDef = (self.data.moves or {})[moveId]
  local moveName = (moveDef and moveDef.name) or moveId
  local name = mon.nickname or mon.name or mon.species or "?"
  local ok, reason, entry = Mon.learnMove(mon, moveId, self.data)
  local function finish(learned)
    if onDone then onDone(learned) end
  end
  if ok then
    return self:say(("%s learned\n%s!"):format(name, moveName),
      function() finish(true) end)
  end
  if reason ~= "full" then return finish(false) end
  local askForget, pickMove, askStop
  -- DidNotLearnMoveText, then `ld b, 0` (learn.asm:110-113).
  local function decline()
    self:say(("%s\ndid not learn\v%s."):format(name, moveName),
      function() finish(false) end)
  end
  -- ForgetMove's AskForgetMoveText + YesNoBox (learn.asm:123-127).
  askForget = function()
    self.stack:push(TextBox.new(self,
      ("%s is\ntrying to learn\v%s.\fBut %s\ncan't learn more\vthan four moves."
       .. "\fDelete an older\nmove to make room\vfor %s?")
        :format(name, moveName, name, moveName),
      nil, { choice = function(yes)
        if yes then return pickMove() end
        return askStop()
      end }))
  end
  -- StopLearningMoveText, whose NO is `jp c, .loop` (learn.asm:104-108).
  askStop = function()
    self.stack:push(TextBox.new(self,
      ("Stop learning\n%s?"):format(moveName), nil,
      { choice = function(yes)
        if yes then return decline() end
        return askForget()
      end }))
  end
  -- The four-slot list ForgetMove draws under MoveAskForgetText, which is the
  -- Blackthorn deleter's own SetUpMoveList box (learn.asm:135-146).
  local function pushList()
    Screens.push(self, "Gen2MoveDeleter", {
      mon = mon,
      moves = self.data.moves,
      onCancel = function()
        self.stack:pop() -- the move list
        self.stack:pop() -- the question it stood on
        askStop()
      end,
      onChoose = function(slot)
        local old = mon.moves[slot]
        self.stack:pop() -- the move list
        -- MoveCantForgetHMText, then `jr .loop` (learn.asm:183-197): the
        -- question stays up and the list comes back over it.
        if old and HM_MOVES[old.id] then
          return self:say("HM moves can't be\nforgotten now.", pushList)
        end
        self.stack:pop() -- the question the list stood on
        local oldDef = (self.data.moves or {})[old and old.id]
        local oldName = (oldDef and oldDef.name) or (old and old.id) or "?"
        mon.moves[slot] = entry
        -- The slot is written here rather than through Mon.learnMove, so
        -- pokemon.move_learned is raised here too.
        ModRuntime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
        self:say(("1, 2 and… Poof!\f%s forgot\n%s.\fAnd…\f%s learned\n%s!")
          :format(name, oldName, name, moveName),
          function() finish(true) end)
      end,
    })
  end
  -- MoveAskForgetText, a `done` text: the box stays while the list stands on
  -- it (learn.asm:136-137).
  pickMove = function()
    self.stack:push(TextBox.new(self, "Which move should\nbe forgotten?", nil,
      { stay = { onShown = pushList } }))
  end
  askForget()
end

-- Using an item from the PACK outside a battle: pack.asm UseItem's .Party
-- arm, for the two families it covers.  A TM/HM opens the party to teach
-- (ItemAttributes says its ITEMMENU_PARTY opens the list, `teaches` names the
-- move, BASE_TMHM on the species says whether it may learn it -- TeachTMHM);
-- everything else with a ported party effect (src/core/gen2/ItemEffects.lua:
-- heals, status cures, revives, RARE CANDY, the PP family) opens the same
-- list under UseOnWhichPKMNString and runs its item_effects.asm routine on
-- the pick.  The world's own .Current / .Field items never reach here --
-- PackMenu hands them to World:useFieldItem first.
function Game2:useFieldItem(itemId)
  local items = self.data.items or {}
  local def = items[itemId]
  local moveId = def and def.teaches
  if not moveId then return self:usePartyItem(itemId) end
  local moves = self.data.moves or {}
  local moveDef = moves[moveId]
  local moveName = (moveDef and moveDef.name) or moveId
  Screens.push(self, "Gen2PartyMenu", {
    prompt = "choose",
    onCancel = function() self.stack:pop() end,
    onChoose = function(index, mon)
      self.stack:pop()
      local species = self.data.pokemon and self.data.pokemon[mon.species]
      local learnable = species and species.tmhm
      local allowed = false
      for _, id in ipairs(learnable or {}) do
        if id == moveId then allowed = true end
      end
      if not allowed then
        self:say(("%s can't learn %s!"):format(
          require("src.battle.gen2.Mon").displayName(mon), moveName))
        return
      end
      for _, move in ipairs(mon.moves or {}) do
        if move.id == moveId then
          self:say(("%s already knows %s!"):format(
            require("src.battle.gen2.Mon").displayName(mon), moveName))
          return
        end
      end
      -- TeachTMHM's `predef LearnMove`, then `ld a, b / and a / jr z, .nope`:
      -- a refusal spends nothing (engine/items/tmhm.asm:142-153).
      self:learnMoveOn(mon, moveId, function(learned)
        if not learned then return end
        -- IsHM `ret c`: an HM is never consumed and pays no happiness.
        if tostring(itemId):sub(1, 3) == "HM_" then return end
        require("src.core.gen2.Happiness").change(mon, "LEARNMOVE")
        self:consumeItem(itemId)
      end)
    end,
  })
end

-- UseDisposableItem (engine/items/item_effects.asm): one copy leaves the
-- pack, and only on a success -- every refusal above it returns first.
function Game2:consumeItem(itemId)
  if not (self.save and self.save.inventory) then return end
  local left = (self.save.inventory[itemId] or 1) - 1
  self.save.inventory[itemId] = left > 0 and left or nil
end

-- RareCandyEffect's tail (engine/items/item_effects.asm): LearnLevelMoves at
-- the new level, then EvolvePokemon.  LearnLevelMoves' .learn arm is `predef
-- LearnMove` (engine/pokemon/evolve.asm), so a full set gets ForgetMove's ask
-- rather than a refusal; the evolution rides the very screen the battle's own
-- EvolveAfterBattle pass pushes, with wForceEvolution clear --
-- Evolution.checkMon's ordinary condition walk -- so an Everstone or an
-- unmet happiness row still refuses.
function Game2:afterRareCandy(mon, result, onDone)
  local data = self.data
  local queue = {}
  for _, moveId in ipairs(result.learned or {}) do
    queue[#queue + 1] = moveId
  end
  local function evolve()
    local Evolution = require("src.core.gen2.Evolution")
    local Palettes = require("src.world.gen2.Palettes")
    local entry = Evolution.checkMon(data, mon, {
      timeOfDay = Palettes.clockDaytime(),
    })
    if not entry then
      if onDone then onDone() end
      return
    end
    local party = (self.save and self.save.party) or {}
    local index
    for i, member in ipairs(party) do
      if member == mon then index = i end
    end
    Screens.push(self, "Gen2EvolutionAnim", {
      mon = mon,
      entry = entry,
      index = index,
      party = party,
      save = self.save,
      onDone = function()
        self.stack:pop()
        if onDone then onDone() end
      end,
    })
  end
  local nextMove
  nextMove = function()
    local moveId = table.remove(queue, 1)
    if not moveId then return evolve() end
    self:learnMoveOn(mon, moveId, function() nextMove() end)
  end
  nextMove()
end

-- The non-TM half of UseItem's .Party: ChooseMonToUseItemOn over the party
-- ("Use on which <PK><MN>?"), then the item family's own item_effects.asm
-- routine on the pick.  The PP family threads one more screen first --
-- MoveSelectionScreen's "Restore the PP of which move?" pick, which the port
-- serves with the move-list screen the Blackthorn deleter already draws
-- (both are SetUpMoveList on the cart).  Backing out of either list is the
-- .SelectMon / PPRestoreItem_Cancel carry path: nothing spent.
function Game2:usePartyItem(itemId)
  local ItemEffects = require("src.core.gen2.ItemEffects")
  -- without the merged dataset this can only ever see RECORDS, the
  -- module's own built-ins, so a mod's field item resolves to no action
  -- at all and never gets past the .Oak refusal below
  local action = ItemEffects.partyAction(itemId, self.data)
  if not action then return end
  local party = (self.save and self.save.party) or {}
  if #party == 0 then
    -- UseItem's .NoPokemon arm (_YouDontHaveAMonText).
    self:say(Strings("You don't have a\n#MON!"))
    return
  end
  local function finish(result, mon)
    if not result.used then
      self:say(result.text)
      return
    end
    if action == "stone" then
      local party = (self.save and self.save.party) or {}
      local index
      for i, member in ipairs(party) do
        if member == mon then index = i break end
      end
      Screens.push(self, "Gen2EvolutionAnim", {
        mon = mon, entry = result.evolution, index = index,
        party = party, save = self.save,
        force = true,
        onDone = function(evolution)
          if evolution and evolution.evolved then self:consumeItem(itemId) end
          self.stack:pop()
        end,
      })
    elseif action == "candy" then
      self:consumeItem(itemId)
      self:say(result.text, function() self:afterRareCandy(mon, result) end)
    else
      self:consumeItem(itemId)
      self:say(result.text)
    end
  end
  Screens.push(self, "Gen2PartyMenu", {
    prompt = "useItem",
    onCancel = function() self.stack:pop() end,
    onChoose = function(_, mon)
      if action ~= "pp" then
        self.stack:pop()
        finish(ItemEffects.useOnMon(itemId, mon, self.data), mon)
        return
      end
      -- RestorePPEffect: the ELIXER pair needs no move pick; an EGG refuses
      -- before the move list ever opens (UseItem_SelectMon's `cp EGG`).
      local row = ItemEffects.RESTORE_PP[itemId] or {}
      if row.each or mon.isEgg then
        self.stack:pop()
        finish(ItemEffects.usePpItem(itemId, mon, nil, self.data), mon)
        return
      end
      Screens.push(self, "Gen2MoveDeleter", {
        mon = mon,
        moves = self.data.moves,
        onCancel = function() self.stack:pop() end,
        onChoose = function(slot)
          self.stack:pop() -- the move list
          self.stack:pop() -- the party list
          finish(ItemEffects.usePpItem(itemId, mon, slot, self.data), mon)
        end,
      })
    end,
  })
end

-- SelectMenu (engine/overworld/select_menu.asm): the SELECT press in the
-- overworld.  World:useSelectItem runs CheckRegisteredItem's re-validation
-- and UseRegisteredItem's dispatch; everything past that is just which of
-- the cart's fixed messages to print, the same way the START handler above
-- is the whole of .MenuReturns for its own button.
function Game2:useSelectItem()
  local outcome, itemId = self.world:useSelectItem()
  if outcome == "not_registered" then
    -- MayRegisterItemText.
    self:say(Strings(
      "An item in your\nPACK may be\fregistered for use\non SELECT Button."))
  elseif outcome == "cant_use" or outcome == "nowhere" then
    -- ItemsOakWarningText, the same "not the time" line CheckItemMenu's
    -- .CantUse arm and a busy world both land on.
    self:say(Strings("OAK: {PLAYER}!\nThis isn't the\vtime to use that!"))
  elseif outcome == "repel_active" then
    self:say(Strings("The REPEL used\nearlier is still\vin effect."))
  elseif outcome == "repel_used" then
    local items = self.data.items or {}
    local name = (items[itemId] and items[itemId].name) or itemId
    self:say(Strings("{PLAYER} used the\n%s.", name))
  elseif outcome == "trophy_sent" then
    self:say(Strings(
      "There was a trophy\ninside!\fThe trophy was\nsent home."))
  end
  -- Anything else (a fishing bite, the ITEMFINDER's queued script) already
  -- drives its own presentation off World:step -- nothing left to print here.
end

-- A message over whatever is on screen.  TextBox pops ITSELF on the final A
-- press before running onDone -- the same contract every other push site in
-- the tree leans on -- so onDone here is only the caller's continuation.  An
-- onDone that popped again ate the state UNDER the box: dismissing a message
-- over the PACK closed the PACK with it, and over an empty overworld stack it
-- was a silent extra pop.
function Game2:say(text, onDone)
  local TextBox = require("src.render.TextBox")
  self.stack:push(TextBox.new(self, text, onDone))
end

-- The landmark the player is standing in, for the Pokegear map's marker.
-- Through src/core/gen2/Nests.lua rather than off landmarks.order, so the
-- `landmarks` registry's own records answer too: order is a flat list the
-- extractor writes and a registered landmark is not in it, while every record
-- carries the map header's own `index` byte.
function Game2:currentLandmark()
  local map = self.world and self.world.map and self.world.map.def
  return require("src.core.gen2.Nests")
    .landmarkId(self.data, map and map.landmark)
end

-- Fold the live world state into the save before writing it, so a reload comes
-- back on the same tile facing the same way.
function Game2:snapshotSave()
  local world = self.world
  if world and world.map and world.player then
    self.save.position = {
      map = world.map.id,
      x = world.player.cellX,
      y = world.player.cellY,
      facing = world.player.facing,
    }
    self.save.events = world.events and world.events:serialize()
      or self.save.events
    self.save.mapScenes = world.mapScenes or self.save.mapScenes
    -- wPlayerState, out of the same sPlayerData block the flags and the scene
    -- ids come from: save on the BICYCLE and the reload has to come back on
    -- the BICYCLE, save aboard a Lapras and it has to come back afloat.
    -- Without this line a save walks the player off the bike and, worse, off
    -- the water -- World:loadPlayerData reads it back.
    self.save.playerState = world.playerState or self.save.playerState
    -- The script VM's sparse WRAM store.  These are counters no other field
    -- covers -- the Goldenrod underground switch positions and the MooMoo
    -- berries -- so leaving them out of the snapshot is the same as never
    -- having flicked a switch.
    self.save.scriptMem = world.vm and world.vm:serializeMem()
      or self.save.scriptMem
    -- wVariableSprites.  WRAM on the cart and therefore never saved there,
    -- which the cart survives because it never rebuilds the world mid-session.
    -- This port does, on every CONTINUE -- and an unfilled slot is an object
    -- that does not spawn -- so the chosen sprites ride along with the save.
    -- Route 36 is why it matters both ways: the slot holds the disguised
    -- Sudowoodo before the fight and the TWIN who replaces it after.
    self.save.variableSprites = world.variableSprites
      or self.save.variableSprites
    -- wBackupWarpNumber / wBackupMapGroup / wBackupMapNumber (home/map.asm
    -- CopyWarpData), which a -1 warp destination resolves through.  Saved
    -- WRAM on the cart, so a save made on POKECENTER_2F must still know which
    -- centre's stairs lead back down -- World:loadPlayerData reads it back.
    self.save.backupWarp = world.backupWarp or self.save.backupWarp
  end
  self.save.options = self.options
  return self.save
end

-- Snapshot the world and persist it.  The mirror of Game:writeSave
-- (src/core/Game.lua:1005): same veto hook, same event, same order, so a mod
-- written against the Gen 1 save lifecycle behaves identically on Gold.
--
-- Every write the player can ask for goes through here -- the SAVE row of the
-- start menu (via the writer handed to Gen2SaveMenu) and the F1 hotkey -- so
-- there is one place the veto has to hold.
function Game2:writeSave()
  -- Tool sessions can be deliberately ephemeral.  Give them one narrow veto
  -- before snapshotSave folds the live world in or any progress bytes reach
  -- disk.  Returning false here is what SaveMenu reads back as "not saved".
  if ModRuntime.call("save.write", function() return true end, self) == false then
    return false
  end
  local save = self:snapshotSave()
  -- The snapshot is complete, so this payload carries exactly the table the
  -- file gets; mods stash runtime state into their own keys now.  `meta` is
  -- the Gen 1 key, absent rather than renamed: a Gold save stamps no meta
  -- block yet (see save.loaded in continueGame).
  if ModRuntime.wants("save.writing") then
    ModRuntime.emit("save.writing", { save = save, meta = save.meta })
  end
  return Save.save(save)
end

function Game2:load()
  Input:init()
  -- Before applyOptions, which is what pushes options.touchControls into it:
  -- init() decides whether the platform wants the overlay at all and loads the
  -- art, applyOptions then lays it out (src/core/Game.lua:59-60 does the pair
  -- in the same order).
  TouchControls:init()
  self.touchControls = TouchControls
  self:applyOptions()
  self.titleData = loadGenerated("data/generated/title.lua") or {}
  self.oakSpeechData = loadGenerated("data/generated/oak_speech.lua") or {}
  -- data.font, not a private field: it is the `font` registry's Data target,
  -- so a mod that overrides a glyph is merged in before Font.load reads it
  -- below.  self.fontData stays as the handle the boot screens pass around.
  self.data.font = loadGenerated("data/generated/font.lua")
  self.fontData = self.data.font
  self.data.audio = loadGenerated("data/generated/audio.lua") or {}
  self.data.pokemon = loadGenerated("data/generated/pokemon.lua") or {}
  self.data.items = loadGenerated("data/generated/items.lua") or {}
  self.data.moves = loadGenerated("data/generated/moves.lua") or {}
  self.data.type_chart = loadGenerated("data/generated/type_chart.lua") or {}
  -- data/types/type_matchups.asm:112-116: the rows after the `db -2` marker
  -- apply by default; Foresight is what cuts the table short at it.
  local chart = self.data.type_chart
  for _, row in ipairs(chart.foresightMatchups or {}) do
    chart.matchups[#chart.matchups + 1] = row
  end
  -- The `held_items` registry's merge target: ItemAttributes' last two columns
  -- as their own table, so a mod can give an item a held behaviour without
  -- owning the whole item record.  Built BEFORE mods:load so the registry
  -- folds against the vanilla row (a mod's register collides, a patch stacks),
  -- and snapshotted so the write-back below can tell what the merge actually
  -- changed from what a mod reached through the shared `items` registry
  -- instead.  Both halves live in src/core/gen2/ItemEffects.lua.
  local ItemEffects = require("src.core.gen2.ItemEffects")
  self.data.gen2HeldItems = ItemEffects.heldItemsFrom(self.data.items)
  local heldBefore = ItemEffects.heldSnapshot(self.data.gen2HeldItems)
  -- Gen 2-only tables the menus read.  Namespaced so nothing collides with the
  -- Gen 1 keys of the same idea (data.palettes, data.icons).
  self.data.gen2Palettes = loadGenerated("data/generated/palettes.lua")
  self.data.gen2Icons = loadGenerated("data/generated/icons.lua")
  self.data.gen2Pokedex = loadGenerated("data/generated/pokedex.lua")
  self.data.gen2Landmarks = loadGenerated("data/generated/landmarks.lua")
  self.data.gen2Sprites = loadGenerated("data/generated/sprites.lua")
  self.data.gen2MenuGfx = loadGenerated("data/generated/menu_gfx.lua")
  self.data.gen2Intro = loadGenerated("data/generated/intro.lua")
  self.data.gen2Credits = loadGenerated("data/generated/credits.lua")
  self.data.gen2Diploma = loadGenerated("data/generated/diploma.lua")
  self.data.gen2Trade = loadGenerated("data/generated/trade.lua")
  self.data.gen2Trainers = loadGenerated("data/generated/trainers.lua")
  self.data.gen2Encounters = loadGenerated("data/generated/encounters.lua")
  -- The battle-animation script pool and the ordered name lists its ids index
  -- into (BattleAnimObjects rows, framesets, OAM sets, BG effects).  Both are
  -- read by src/battle/gen2/AnimRunner.lua.
  self.data.gen2BattleAnims = loadGenerated("data/generated/battle_anims.lua")
  self.data.gen2Constants = loadGenerated("data/generated/constants.lua")
  -- The overworld's own tables.  src/world/gen2/World.lua:load used to read
  -- these straight off disk into World fields, which meant they never passed
  -- through game.data and a registry had no Data path to merge into -- the one
  -- cause behind most of the `false` rows in Schemas.GEN2.  Loading them here
  -- puts them in self.data ahead of the mods:load(self.data) call below, so a
  -- merge lands before World ever holds the table; World takes each by
  -- reference and never copies, so the table it walks IS the merged one.
  self.data.gen2Maps = loadGenerated("data/generated/maps.lua")
  self.data.gen2Tilesets = loadGenerated("data/generated/tilesets.lua")
  self.data.gen2Roofs = loadGenerated("data/generated/roofs.lua")
  -- engine/events/magnet_train.asm:165 DrawMagnetTrain
  self.data.gen2Field = loadGenerated("data/generated/field.lua")
  self.data.gen2Marts = loadGenerated("data/generated/marts.lua")
  self.data.gen2Scripts = loadGenerated("data/generated/scripts.lua")
  self.data.gen2StdScripts = loadGenerated("data/generated/std_scripts.lua")
  self.data.gen2Text = loadGenerated("data/generated/text.lua")
  -- data/generated/events.lua: the side tables a script command NAMES rather
  -- than carries -- the phone book, the in-game trades, the elevator's floor
  -- labels, the decoration descriptions.  Keyed for World's own `eventTables`
  -- field rather than "gen2Events" so it is never read as the mod event bus.
  self.data.gen2EventTables = loadGenerated("data/generated/events.lua")
  -- InitializeEventsScript's seed: the setevent list AND the nine
  -- `variablesprite` assignments, both of which World:load applies.
  self.data.gen2InitialEvents =
    loadGenerated("data/generated/initial_events.lua")
  -- Gold's trainer table under the second name the Gen 2 code already reads it
  -- by (World:trainerParty, src/core/gen2/BugContest.lua and
  -- src/world/gen2/Palettes.lua all say data.trainers).  The SAME table as
  -- data.gen2Trainers, never a copy, so a merge into either key is seen
  -- through both; World:load used to set this from a second disk read, which
  -- is what dropped a merge on the floor.
  self.data.trainers = self.data.gen2Trainers

  -- Mods.  Discovery and the manager are generation-agnostic -- they read
  -- manifests and the enable/disable state, not game data -- so Gold gets the
  -- same MODS row the Gen 1 start menu has.  Only a mod whose manifest says
  -- gen2compat is actually run here (Loader:_gateGeneration); the rest are
  -- listed and skipped rather than half-applied.  Registry targets route per
  -- generation through Schemas.GEN2, so the ones with a Gen 2 home merge into
  -- self.data and the ones without report instead of silently vanishing.  The
  -- whole thing is behind a pcall so a mod problem can never cost Gold its
  -- boot.
  local ok, loader = pcall(function()
    local mods = require("src.mods.Loader").new()
    -- the live service owner, before load: mod.world and mod.input resolve
    -- through this, and without it the facade would bind to the Gen 1
    -- src/core/Game.lua singleton that a Gold boot never loads
    mods.game = self
    mods:load(self.data)
    return mods
  end)
  if ok and loader then
    self.mods = loader
    self.modStatus = loader:status()
  else
    -- The pcall above keeps a mod problem from costing Gold its boot, which is
    -- right; swallowing it without a word is not.  A throw here takes out the
    -- WHOLE subsystem -- no discovery, no manager, no registry merge -- and
    -- with no line printed the only symptom is that mods quietly do nothing,
    -- which is indistinguishable from having none installed.
    require("src.core.Logger").error(
      "mods failed to load, continuing without them: %s", tostring(loader))
  end

  -- The Gen 2-only content registries, collected after the merge and before
  -- anything reads their tables.  Each module holds the merged table by
  -- reference (or folds it onto the rows it already keys by, for the two whose
  -- callers have a byte and not a dataset), so this is where a registered
  -- decoration, phone contact, apricorn or held item becomes the one the game
  -- actually uses.  `landmarks` and `radio_channels` need no call: their
  -- consumers (src/core/gen2/Nests.lua, src/ui/gen2/MapRadio.lua) read
  -- game.data at the point of use.
  ItemEffects.applyHeldItems(self.data, heldBefore)
  require("src.core.gen2.Phone").useRegistry(self.data)
  require("src.core.gen2.Decorations").useRegistry(self.data)
  require("src.core.gen2.Apricorns").useRegistry(self.data)

  -- Rendering pipelines: the engine half of the render_pipelines registry
  -- (src/render/Pipelines.lua).  install() points it at GOLD's merged dataset
  -- -- Gen 1 points it at the src/core/Data.lua singleton, which a Gold boot
  -- never loads (src/core/Game.lua:47) -- and applyOptions restores the ladder
  -- the player left in options.pipelines.  Both after the merge, so a mod's
  -- pipeline record is already in data.render_pipelines when either reads it.
  local Pipelines = require("src.render.Pipelines")
  Pipelines.install(self.data)
  Pipelines.applyOptions(self.options)
  -- Both halves run on Gold now: `present` folds over the composite in
  -- Game2:draw, `drawWorld` owns the world pass in World:drawPipeline.  So a
  -- restored world level stays switched on, as it does for Gen 1.

  -- After the merge, so a font override and a translation mod's catalog
  -- (#501) are both in Data before the first screen draws a glyph.  Gen 1
  -- calls these two here for the same reason (src/core/Game.lua:65,70).
  if self.data.font then
    pcall(Font.load, self.data)
  end
  Strings.load(self.data)

  -- The boot skeleton (Game2.new built it, before any bus existed) announced
  -- here rather than at its construction, which is the same spot in the boot
  -- order Gen 1 announces its own from: after the merge, before game.ready,
  -- stack still empty (src/core/Game.lua:79).  A driver that skips the cinema
  -- plays on this save, so a mod that seeds through save.created has to be
  -- given it exactly once, here.
  -- seed=true keeps what entry chunks wrote through mod.save before any save
  -- existed, the way Gen 1 seeds its boot skeleton (src/core/Game.lua:78).
  self:adoptSave(self.save, true)
  ModRuntime.emit("save.created", { save = self.save })

  -- The handshake every behavior mod waits on: the one place a mod is handed
  -- the live service owner (mod.input needs it, and it is what the docs tell
  -- a mod to hold).  Emitted where Gen 1 emits it -- every service up, the
  -- stack still empty -- so a listener that pushes a state lands underneath
  -- the boot cinema rather than being buried by it.
  ModRuntime.emit("game.ready", { game = self })

  -- Drivers that walk the overworld skip boot cinema so smoke stays stable.
  -- POKEPORT_BOOT_CINEMA=1 opts back in, which is how the boot-chain driver
  -- exercises copyright -> title -> intro menu -> Oak -> naming.
  if os.getenv("POKEPORT_DRIVER")
      and os.getenv("POKEPORT_BOOT_CINEMA") ~= "1" then
    self:startWorld()
  else
    self:showCopyright()
  end

  FixedStep:init(function(dt)
    -- Tool mods (autoplay, accessibility drivers, input visualizers) act on the
    -- same fixed-step boundary a physical controller does.  Raised HERE, ahead
    -- of both the AUTO_INPUT arm and Input:step, for the reason Gen 1 raises it
    -- ahead of Input:step (src/core/Game.lua:188): a button chosen by a mod has
    -- to be visible to THIS logic tick, not the next one, and the cart's own
    -- canned stream must be able to overwrite it the way GetJoypad's arm
    -- overwrites the mirrors.  Payload is Gen 1's exactly: (game, fixed dt).
    ModRuntime.call("input.step", noop, self, dt or 1 / 60)
    -- GetJoypad's AUTO_INPUT arm runs ahead of everything that reads the pad,
    -- and it overwrites the mirrors outright, so a stream frame has to land
    -- before Input:step promotes this tick's edges -- otherwise the canned
    -- press would be a tick late and the player's own keys would still be in
    -- the queue alongside it.
    self.autoInput:step(self.input)
    self.input:step()
    -- UpdateJoypad's soft reset (home/joypad.asm:99-102) is `and PAD_BUTTONS /
    -- cp PAD_BUTTONS`, so the d-pad is masked off and the chord fires at once.
    if self.input.isDown and self.input:isDown("a") and self.input:isDown("b")
        and self.input:isDown("start") and self.input:isDown("select") then
      Input:reset()
      TouchControls:reset()
      self:softReset()
      return
    end
    -- Not the audio tick: _UpdateSound runs once per frame off VBlank
    -- (audio/engine.asm:84, home/vblank.asm:141-143), never off the logic clock.
    local top = self.stack:top()
    if top and top.update then
      top:update(1 / 60)
      return
    end
    if self.phase ~= "play" or not self.world then return end
    -- The play clock only runs in the overworld, the way wGameTimerPaused is
    -- set while the intro menu is up.
    Save.tickPlayTime(self.save)
    -- START and SELECT are read only at the tail of OWPlayerInput, which
    -- PlayerEvents never reaches while a script is running or the player is
    -- mid-step (World:acceptsMenuInput transcribes the three gates).  A press
    -- that arrives under one of them is dropped, not queued -- and the frame
    -- still runs, so world:step must not be skipped on the swallowed press.
    if self.input:wasPressed("start") and self.world:acceptsMenuInput() then
      self:openStartMenu()
      return
    end
    if self.input:wasPressed("select") and self.world:acceptsMenuInput() then
      self:useSelectItem()
      return
    end
    self.world:pollInput(self.input)
    if self.input:wasPressed("a") then
      self.world:interact()
    end
    self.world:step()
  end)
end

function Game2:inFillBoot()
  -- Entire pre-world cinema (copyright / title / Oak / name / nested NamingScreen)
  -- draws in GB letterbox space.
  return self.phase == "boot" and self.stack:top() ~= nil
end

function Game2:update(dt)
  -- _UpdateSound is a VBlank job, so it runs at 60Hz off real time whatever the
  -- logic multiplier is (audio/engine.asm:84, home/vblank.asm:141-143).
  local step = FixedStep.STEP
  self.audioAccum = math.min((self.audioAccum or 0) + dt, 0.25)
  while self.audioAccum >= step do
    self.audioAccum = self.audioAccum - step
    Music.update(self.data)
  end
  -- TILT eases toward its new angle in real time, not on the logic clock, so
  -- fast-forward does not fling the camera over.
  require("src.render.Tilt").update(dt)
  -- Mod render pipelines tween on the same real-frame clock, for the same
  -- reason and at the same place Gen 1 ticks them (src/core/Game.lua:265):
  -- they are presentational, so fast-forward must not speed them up.
  require("src.render.Pipelines").update(dt)
  -- GAME SPEED scales the logic clock only, exactly as the Gen 1 path does:
  -- audio runs off its own real-time accumulator, so music and sfx keep their
  -- tempo at every multiplier.  speedOverride is the driver/CLI hook and wins
  -- over the saved option.
  -- pokegold engine/menus/intro_menu.asm:848 IntroSequence: boot cinema runs on the same clock as the overworld
  local speed = math.max(1,
    tonumber(self.speedOverride) or tonumber(self.options and self.options.speed)
    or 1)
  if self.phase == "boot" then
    FixedStep.maxAccum = math.max(0.25, speed / 60 + 0.05)
    FixedStep:update(dt * speed)
    return
  end
  if not self.world or not self.world.map then return end
  FixedStep.maxAccum = math.max(0.25, speed / 60 + 0.05)
  FixedStep:update(dt * speed)
end

-- The screen-pixels-per-GB-pixel scale the post passes need so their grid and
-- shadow offsets stay window-size independent.  Always the plain letterbox
-- fit, never the survey zoom: GBC FX is simulating the PANEL the picture is
-- being shown on, and the panel does not resize when the player zooms the map
-- -- Gen 1 hands the same pass its `Renderer:fitScale()` for that reason
-- (Renderer:endFrame's Sp).  Following the zoom used to shrink the LCD grid to
-- one screen pixel a cell out at survey range.
function Game2:pixelScale(w, h)
  return math.max(1, math.floor(math.min(w / 160, h / 144)))
end

-- A window-sized canvas the whole frame is composed into, so the post passes
-- have something to read.  Rebuilt on resize; nil (and a plain draw) when the
-- backend cannot give us one.
function Game2:presentCanvas(index, w, h)
  self._canvases = self._canvases or {}
  local canvas = self._canvases[index]
  if canvas then
    local cw, ch = canvas:getDimensions()
    if cw ~= w or ch ~= h then canvas = nil end
  end
  if not canvas then
    local ok, made = pcall(love.graphics.newCanvas, w, h)
    if not ok or not made then return nil end
    made:setFilter("nearest", "nearest")
    self._canvases[index] = made
    canvas = made
  end
  return canvas
end

-- The letterbox this frame is being drawn in, in the terms Gen 1's
-- Renderer:endFrame reports it: the integer fit scale, the centred origin that
-- goes with it, the window in LOVE units and in framebuffer pixels, and the DPI
-- scale between the two.
--
-- One difference from Gen 1 has to be named, because two payload fields carry
-- it.  Gen 1 fits in FRAMEBUFFER pixels and divides back into units, so its
-- `scale` is framebuffer-pixels-per-GB-pixel; Gold fits in LOVE units
-- throughout (Chrome.fitScale takes love.graphics.getDimensions), so `scale`
-- here is units-per-GB-pixel.  They are the same number on every 1x display,
-- which is where Gen 1 mods are written and verified, and on a HiDPI display
-- this is the one that actually describes Gold's picture -- `gameX + x * scale`
-- lands on GB pixel x either way.  The rect fields (gameX/gameY/gameWidth/
-- gameHeight, ox/oy/vpw/vph) are LOVE units in both generations.
function Game2:frameFit(w, h)
  local scale = Chrome.fitScale(w, h)
  local ox, oy = Chrome.fitOrigin(w, h, scale)
  local dpi = 1
  if love.window and love.window.getDPIScale then
    dpi = tonumber(love.window.getDPIScale()) or 1
  end
  local pw, ph = w * dpi, h * dpi
  pw, ph = GameViewport.pixelDimensions()
  return scale, ox, oy, dpi, pw, ph
end

-- render.hud's payload (src/core/Game.lua:521), which is what Renderer:endFrame
-- returns on the Gen 1 side: the window and the playfield rect inside it, both
-- in LOVE window units.  Built only when someone is subscribed, so a mod-free
-- frame allocates nothing.
function Game2:viewport(w, h)
  local scale, ox, oy, dpi = self:frameFit(w, h)
  return {
    width = w, height = h,
    gameX = ox, gameY = oy,
    gameWidth = 160 * scale, gameHeight = 144 * scale,
    scale = scale, dpiX = dpi, dpiY = dpi,
  }
end

-- The render.hud layer, in Gen 1's order over the finished game frame. The
-- on-screen pad is drawn separately after GameViewport.finish, because it is
-- OS-window chrome and must not be captured or scaled with this canvas.
--
-- render.hud: persistent tool status.  The call is fenced with
-- push("all")/pop for the reason src/render/Pipelines.lua:guardRender fences a
-- mod render callback: a subscriber that returns cleanly but leaves a shader
-- bound, the canvas redirected or the colour changed must not corrupt the next
-- frame.
function Game2:drawHud(w, h)
  if ModRuntime.wantsHook("render.hud") then
    local G = love.graphics
    G.push("all")
    ModRuntime.call("render.hud", noop, self, self:viewport(w, h))
    G.pop()
  end
end

-- render.letterbox: SGB borders and custom void art in the bars around the
-- 160x144 blit.  Gen 1 raises it in Renderer:endFrame after the background
-- clear and before the game canvas, so the playfield sits on top of the border;
-- this is the same instant, and Gold reaches it five different ways -- a title
-- screen's own widescreen sky, a page's paper surround, the white void a nested
-- screen gets, the opaque-page safety net, and the live overworld -- so
-- drawScene calls this at each of them and exactly one fires per frame.
--
-- Payload is Gen 1's table field for field (Renderer.lua:840).
function Game2:letterbox(w, h, worldActive)
  if not ModRuntime.wantsHook("render.letterbox") then return end
  local scale, ox, oy, dpi, pw, ph = self:frameFit(w, h)
  local G = love.graphics
  G.push("all")
  ModRuntime.call("render.letterbox", noop, {
    ww = w, wh = h, pw = pw, ph = ph,
    ox = ox, oy = oy, vpw = 160 * scale, vph = 144 * scale,
    scale = scale, dpiX = dpi, dpiY = dpi,
    worldActive = worldActive and true or false,
  })
  G.pop()
end

-- The zone pass: one scissored full-frame draw per zone, later zones on top,
-- each through its own palette.  This is src/render/Renderer.lua:blitCanvas
-- with Gold's palette shader standing in for PaletteFX's, down to the
-- `colors == false` opt-out that draws its rect with no shader at all.
--
-- Zone rects are 160x144 SCREEN space and map onto the WINDOW, not onto the
-- letterbox: Gold's picture fills the window (the overworld draws edge to edge
-- at World:zoomScale, and every full-screen page paints its own surround), so
-- a whole-screen zone is the whole window -- which is exactly what the CLASSIC
-- present pass has always been.
function Game2:blitZones(canvas, zones, w, h)
  local G = love.graphics
  local GbcPalette = require("src.render.GbcPalette")
  local sx, sy = w / 160, h / 144
  G.setColor(1, 1, 1, 1)
  for _, z in ipairs(zones) do
    -- a colors == false zone is the true-colour opt-out; anything the shader
    -- refuses (no GPU shader support) also falls back to a plain draw
    if z.colors == false or not GbcPalette.useRaw(z.colors) then
      G.setShader()
    end
    -- Clamped to the frame and SKIPPED when it clamps to nothing, which is
    -- what src/render/Renderer.lua:scissorClamped does with a zone rect on the
    -- Gen 1 side.  A zone list is mod input (render.zones), so an empty or
    -- backwards rect is reachable -- a weather mod deriving one from a
    -- viewport that is momentarily zero-sized, say -- and there it just draws
    -- nothing.  Here it reached love.graphics.setScissor, which raises "Can't
    -- set scissor with negative width and/or height" from inside Game2:draw
    -- and takes the whole frame down: the hazard the seam rule names, a hook
    -- whose contract differs from Gen 1's.  Whole-screen and half-screen zones
    -- come out of this at exactly the pixels the plain floor/ceil pair gave
    -- them, so the vanilla picture is untouched.
    local zx, zy = (z.x or 0) * sx, (z.y or 0) * sy
    local x1 = math.floor(math.max(zx, 0))
    local y1 = math.floor(math.max(zy, 0))
    local x2 = math.ceil(math.min(zx + (z.w or 160) * sx, w))
    local y2 = math.ceil(math.min(zy + (z.h or 144) * sy, h))
    if x2 > x1 and y2 > y1 then
      G.setScissor(x1, y1, x2 - x1, y2 - y1)
      G.draw(canvas, 0, 0)
    end
  end
  G.setScissor()
  G.setShader()
end

-- render.compose: hand a mod the finished frame and the frame metrics and let
-- it lay the picture out however it likes -- two stacked Game Boy screens, one
-- driven onto a second physical display.  The mod returns true to take over the
-- whole window; anything else falls through to the normal present below.
-- Returns whether it took over.
--
-- Gold composites its world pass and its UI into ONE canvas rather than the two
-- Gen 1 keeps apart, so `worldCanvas` and `uiCanvas` are the same texture here
-- and `worldZones` is nil -- there is no second zone space for them to be in.
-- Every other key is what Renderer.lua:748 puts there, and `generation` /
-- `sceneCanvas` are ADDITIONS, so a mod that reads uiCanvas plus the metrics
-- works unchanged while one that needs the two passes apart can tell which
-- game it is in.
function Game2:compose(scene, zones, w, h)
  local scale, ox, oy, dpi, pw, ph = self:frameFit(w, h)
  local ctx = {
    renderer = self,
    worldCanvas = scene, uiCanvas = scene,
    worldOverride = nil,
    worldActive = self.frameWorldActive and true or false,
    zones = zones, worldZones = nil,
    ww = w, wh = h, pw = pw, ph = ph, ox = ox, oy = oy,
    vpw = 160 * scale, vph = 144 * scale, uiw = 160, uih = 144,
    scale = scale, Sx = scale, Sy = scale, dpiX = dpi, dpiY = dpi,
    secondScreen = require("src.render.SecondScreen"),
    -- Gen 2 additions: the one canvas both passes landed in, and which game
    -- this is, so a compose mod can branch instead of guessing from uiw.
    sceneCanvas = scene, generation = 2,
  }
  local G = love.graphics
  G.push("all")
  local handled = ModRuntime.call("render.compose",
    function() return false end, self, ctx) == true
  G.pop()
  return handled
end

-- Gold's frame, and then the passes that run over it.
--
-- The Gen 1 path gets these for free because everything it draws goes through
-- src/render/Renderer.lua, which owns a present canvas and calls GBCFX there.
-- Gold draws straight to the screen instead, which is why its GBC FX row used
-- to change a number and nothing else: nothing ever presented a canvas for the
-- shader to read.  So compose into one here when a pass wants it, and skip the
-- canvas entirely when none does -- the common case, and one less full-screen
-- blit than the old path would have paid.
--
-- CLASSIC runs first and GBC FX second, matching the Gen 1 order: the palette
-- IS the picture, and the screen effects are simulating the panel that picture
-- is being shown on.  Mod post-processes fold in between the two, where
-- Renderer.lua:1058 folds them -- a blur or a colour grade is what the LCD grid
-- is then drawn over, rather than something that smears the grid itself.
function Game2:drawViewportFrame()
  local G = love.graphics
  local w, h = GameViewport.dimensions()
  local GBCFX = require("src.render.GBCFX")
  local GbcPalette = require("src.render.GbcPalette")
  local Pipelines = require("src.render.Pipelines")
  local fx = GBCFX.active()

  -- render.zones, at the instant Gen 1 raises it: the palette list is settled
  -- and the blit has not happened yet.  Gen 1's list is the SGB packet zones
  -- the top state exposed; Gold is a CGB game whose colour is already IN the
  -- picture, so the only zone it computes for itself is the whole-screen
  -- present palette CLASSIC needs.  That is the same case Gen 1 covers with
  -- PaletteFX.ensureZones, where a forced mono/CLASSIC mode over a raw DMG
  -- canvas gets exactly one whole-screen zone and nothing else -- same rect
  -- shape (x/y/w/h in 160x144 screen space, `colors` four 0-255 triples,
  -- `colors == false` the opt-out), same identity default -- so a weather or
  -- lighting mod written against Gen 1 tints Gold through the same seam.
  local zones = nil
  local classic = GbcPalette.available() and GbcPalette.presentColors() or nil
  if classic then
    zones = { { x = 0, y = 0, w = 160, h = 144, colors = classic } }
  end
  if ModRuntime.wantsHook("render.zones") then
    zones = ModRuntime.call("render.zones", sameZones, self, zones)
  end
  local zoned = type(zones) == "table" and zones[1] ~= nil

  -- A present canvas is paid for only when something reads it: the zone pass,
  -- GBC FX, a mod post-process, render.compose, or an enabled render.output
  -- subscriber. With none of them the frame draws straight to the screen
  -- exactly as it always did.
  local composing = ModRuntime.wantsHook("render.compose")
  local hasOutputHook = ModRuntime.wantsHook("render.output")
    and ModRuntime.call("render.output_enabled", function() return false end) == true
  local scene = nil
  if zoned or fx or composing or Pipelines.wantsPresent() or hasOutputHook then
    scene = self:presentCanvas(1, w, h)
  end
  if not scene then
    self:drawScene(w, h)
    self:drawHud(w, h)
    return
  end

  local previous = G.getCanvas()
  -- A canvas does not reset the transform, so this needs its own origin.
  G.push()
  G.origin()
  G.setCanvas(scene)
  G.clear(0, 0, 0, 1)
  self:drawScene(w, h)
  G.setCanvas(previous)

  if composing and self:compose(scene, zones, w, h) then
    -- the mod owns the window this frame; the HUD still draws over it, as it
    -- does over Gen 1's composed frame
    G.pop()
    G.setColor(1, 1, 1, 1)
    self:drawHud(w, h)
    return
  end

  -- The zone pass has to land in a texture whenever anything still reads one
  -- after it: GBC FX and a post-process both sample the tinted image, not the
  -- untinted one.  On its own the tint rides the final blit and no second
  -- canvas is paid for.
  local source = scene
  local reread = fx or Pipelines.wantsPresent() or hasOutputHook
  if zoned and reread then
    local tinted = self:presentCanvas(2, w, h)
    if tinted then
      G.setCanvas(tinted)
      G.clear(0, 0, 0, 1)
      self:blitZones(scene, zones, w, h)
      G.setCanvas(previous)
      source = tinted
    end
    -- no second canvas: drop the tint rather than the frame
  elseif zoned then
    self:blitZones(scene, zones, w, h)
    source = nil -- already on the screen
  end

  if source then
    -- Post-process pipelines run over the finished composite and before GBC
    -- FX.  Each hands back a canvas; with none registered this returns `source`
    -- unchanged and the frame is byte-identical (Renderer.lua:1058).
    local scale, ox, oy, dpi = self:frameFit(w, h)
    source = Pipelines.present(source, { width = w, height = h, scale = scale,
      dpi = dpi, dpiX = dpi, dpiY = dpi }) or source
    local outputHandled = hasOutputHook
      and ModRuntime.call("render.output", function() return false end, {
        canvas = source, width = w, height = h,
        gameX = ox, gameY = oy,
        gameWidth = 160 * scale, gameHeight = 144 * scale,
        scale = scale, dpiX = dpi, dpiY = dpi,
        generation = 2,
      }) == true
    if not outputHandled then
      if fx then
        GBCFX.present(source, self:pixelScale(w, h))
      else
        G.setColor(1, 1, 1, 1)
        G.draw(source, 0, 0)
        G.setShader()
      end
    end
  end
  G.pop()
  G.setColor(1, 1, 1, 1)
  self:drawHud(w, h)
end

function Game2:draw()
  GameViewport.begin(2)
  GameViewport.setTarget()
  self:drawViewportFrame()
  GameViewport.finish(self)
  -- OS-window chrome: draw after companion composition so viewport layouts
  -- neither shrink nor cover the touch pad.
  TouchControls:draw()
end

-- The paper a pushed TextBox has to sit on.  A textbox is built entirely from
-- font-page tiles ($79-$7e frame, ' ' $7f interior), so it takes BG palette 0
-- colour 0 from the screen UNDER it (pokegold engine/pokegear/pokegear.asm
-- TownMapPals: the attribute map covers $00-$5f and everything >= $60 uses
-- palette 0).  White on every screen whose colour 0 is white, which is all of
-- them but the Pokegear, whose paper is RGB 28,31,20.  Nil means white, which
-- is what Font.drawBox does by default.
function Game2:textboxPaper()
  local base = visibleBaseState(self.stack)
  if base and base.paperColor then return base:paperColor() end
  return nil
end

function Game2:drawScene(w, h)
  local G = love.graphics
  -- render.compose reads this after the scene is drawn; the plain overworld
  -- branch below is the only one where Gen 1 would call the world pass live.
  self.frameWorldActive = false

  if self:inFillBoot() then
    local top = self.stack:top()
    local base = visibleBaseState(self.stack)
    -- Title (and friends) paint sky/clouds edge-to-edge; Oak speech and
    -- name pick paint a paper-white surround via drawWidescreen.
    local wide = (self.stack:renderVisible(top)
      and top.drawsWidescreen and top:drawsWidescreen()
      and top.drawWidescreen) and top
      or (base and base.drawsWidescreen and base:drawsWidescreen()
        and base.drawWidescreen and base)
    if wide then
      -- Widescreen layer paints the surround; GB canvas stacks on top so
      -- TextBox can overlay Oak's pic without wiping the white field.
      wide:drawWidescreen(w, h)
      self:letterbox(w, h, false)
      if wide ~= top or #self.stack.states > self.stack:visibleBase() then
        -- Same integer blit the widescreen layer under it used, or the GB
        -- canvas would land on a different grid than the panel it overlays.
        local scale = Chrome.fitScale(w, h)
        local ox, oy = Chrome.fitOrigin(w, h, scale)
        G.push()
        G.translate(ox, oy)
        G.scale(scale, scale)
        self.stack:draw()
        G.pop()
      end
    else
      -- Nested NamingScreen etc.: paper void instead of black pillarboxes.
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", 0, 0, w, h)
      self:letterbox(w, h, false)
      local scale = Chrome.fitScale(w, h)
      local ox, oy = Chrome.fitOrigin(w, h, scale)
      G.push()
      G.translate(ox, oy)
      G.scale(scale, scale)
      self.stack:draw()
      G.pop()
    end
    return
  end

  if self.world and self.world.map then
    -- A screen that paints its own surround (the battle) covers the window
    -- edge to edge instead of sitting in a letterbox over the overworld --
    -- the battle background IS white on the cart, so a white field is what
    -- "full screen" means here.
    -- The widescreen layer is whichever of the stack's TOP or its visible BASE
    -- paints one, the same resolution inFillBoot already makes above.  Testing
    -- only the top loses the surround the moment anything is pushed over such a
    -- screen: .DoPhoneCall (engine/phone/phone.asm) runs the caller's script
    -- with the POKEGEAR still owning the screen, and the same happens to the
    -- PARTY, PACK, #DEX, PC, DAY-CARE, MAILBOX and TRADE screens whenever a
    -- TextBox goes up over them.
    local top = self.stack:top()
    local base = visibleBaseState(self.stack)
    local wide = (self.stack:renderVisible(top)
      and top.drawsWidescreen and top:drawsWidescreen()
      and top.drawWidescreen) and top
      or (base and base.drawsWidescreen and base:drawsWidescreen()
        and base.drawWidescreen and base)
    if wide then
      wide:drawWidescreen(w, h)
      self:letterbox(w, h, false)
      if wide ~= top then
        -- The pushed box blits at the same integer fit the widescreen layer
        -- used, or it lands on a different grid than the panel underneath it.
        local scale = Chrome.fitScale(w, h)
        local ox, oy = Chrome.fitOrigin(w, h, scale)
        G.push()
        G.translate(ox, oy)
        G.scale(scale, scale)
        self.stack:draw()
        G.pop()
      end
      return
    end

    -- CLEARTILEMAP SAFETY NET.  Every full-screen Gold page wipes the tilemap
    -- on its way in -- ClearBGPalettes / ClearTilemap at engine/games/
    -- unown_puzzle.asm:11, engine/events/diploma.asm:13, engine/events/
    -- magnet_train.asm:101 (ClearBGPalettes / ClearSprites / DisableLCD),
    -- engine/printer/print_party.asm:134 and engine/events/print_unown.asm:17
    -- -- so not one map tile can survive underneath one.  A screen that
    -- declares itself OPAQUE but ships no widescreen layer would otherwise
    -- letterbox over a live `world:draw()` and show the overworld all round
    -- its edges, which is the one thing the cart cannot do.
    --
    -- Gated strictly on isOpaque, because the screens that deliberately sit
    -- OVER the map (StartMenu, DayCareMenu, MailboxMenu, ScriptMenu,
    -- ElevatorMenu, HeldItemMenu, MoveDeleter, TradeMenu, MapRadio,
    -- BankOfMom, BattleTransition) leave it false and MUST keep the world
    -- behind them -- src/ui/gen2/DayCareMenu.lua draws only its box.
    if base and base.isOpaque then
      if base.drawWidescreen then
        -- Already paints its own surround and only misses the
        -- `drawsWidescreen` opt-in the resolution above tests, so use it:
        -- the panel's own field colour is what belongs outside the page.
        base:drawWidescreen(w, h)
      else
        -- No surround of its own: the paper-white void the boot path uses,
        -- rather than a window full of somebody else's map.
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", 0, 0, w, h)
      end
      self:letterbox(w, h, false)
      -- Same integer blit every widescreen layer uses, or the GB canvas lands
      -- on a different grid than the field behind it.
      local scale = Chrome.fitScale(w, h)
      local ox, oy = Chrome.fitOrigin(w, h, scale)
      G.push()
      G.translate(ox, oy)
      G.scale(scale, scale)
      self.stack:draw()
      G.pop()
      return
    end

    -- The live overworld IS the background here -- it draws edge to edge at
    -- World:zoomScale, with no surround to paint first -- so the border seam
    -- sits ahead of it, which is where Gen 1 puts it too: Renderer:endFrame
    -- raises render.letterbox before the world blit as well as before the UI
    -- one, and `worldActive` in the payload is how a subscriber tells the two
    -- frames apart.
    self.frameWorldActive = true
    self:letterbox(w, h, true)
    self.world:draw()
    if self.stack:top() then
      -- ZOOM RESIZES THE MAP, NOT THE UI.  The world fills the window at
      -- `world:zoomScale()`; the stack canvas -- the dialogue box, the START
      -- menu, every screen that sits over the overworld -- blits at the plain
      -- integer letterbox fit instead, so a zoom step moves the map under a
      -- text box that stays exactly the size it is at FIT.
      --
      -- This is the split src/render/Renderer.lua makes for Gen 1, whose UI
      -- LAYOUT defaults to CENTERED: `Renderer:uiScale` returns `fitScale()`
      -- and only the world canvas follows `Zoom.scale`.  Gold has no DYNAMIC
      -- row to opt into the step-down half, so CENTERED is the whole rule
      -- here.
      local s = self.world:fitScale()
      G.push()
      G.translate(math.floor((w - 160 * s) / 2), math.floor((h - 144 * s) / 2))
      G.scale(s, s)
      self.stack:draw()
      G.pop()
    end
    return
  end

  G.clear(0.07, 0.05, 0.02, 1)
  G.setColor(0.85, 0.57, 0.13, 1)
  G.printf("POKEMON GOLD", 0, math.floor(h * 0.38), w, "center")
  G.setColor(0.92, 0.90, 0.82, 1)
  G.printf(self.status or "Failed to boot Gen 2 world.",
    0, math.floor(h * 0.48), w, "center")
  G.printf("Press Escape to quit.", 0, math.floor(h * 0.62), w, "center")
  G.setColor(1, 1, 1, 1)
end

-- The display/speed hotkey ladder, the same keys and the same order the Gen 1
-- path binds them in (src/core/Game.lua keypressed), driving the same shared
-- modules so a player's muscle memory carries between the two games:
--
--   F1/F2  write / reload the save        1  GAME SPEED
--   -  =   zoom one step out / in         2  COLOR
--   4      cycle ZOOM                     3  TILT (mnemonic: 3D)
--                                         5  GBC FX
--
-- `2` is COLOR here rather than Gen 1's COLORS.  The Gen 1 row cycles SGB
-- palette packs, which a CGB-native game has no use for; what it cycles here
-- is whether the cart's own colour is showing at all (GBC / DMG / CLASSIC).
-- Same key, same place in the ladder, same idea: "change how this looks".
function Game2:hotkey(key)
  local options = self.options or {}
  local function persist()
    if self.save then self.save.options = options end
    self:persistOptions()
  end
  if key == "f1" then
    self:writeSave()
    return true
  elseif key == "f2" then
    local loaded = Save.load("gold")
    if loaded then self:continueGame(loaded) end
    return true
  elseif key == "1" then
    local GameSpeed = require("src.core.GameSpeed")
    options.speed = GameSpeed.cycle(options.speed, 1)
    persist()
    return true
  elseif key == "2" then
    local GbcPalette = require("src.render.GbcPalette")
    GbcPalette.setMode(options.color or "gbc")
    options.color = GbcPalette.cycle(1)
    persist()
    return true
  elseif key == "3" then
    local Tilt = require("src.render.Tilt")
    options.tilt = Tilt.cycle()
    persist()
    return true
  elseif key == "5" then
    local GBCFX = require("src.render.GBCFX")
    if GBCFX.isSupported() then
      options.gbcfx = GBCFX.cycle()
      persist()
    end
    return true
  end
  if not (self.world and self.world.map) then
    return self:pipelineHotkey(key, options, persist)
  end
  if key == "-" or key == "kp-" then
    self.world:zoomStep(-1)
    options.zoom = require("src.render.Zoom").offset
    persist()
    return true
  elseif key == "=" or key == "kp+" then
    self.world:zoomStep(1)
    options.zoom = require("src.render.Zoom").offset
    persist()
    return true
  elseif key == "4" then
    self.world:zoomCycle()
    options.zoom = require("src.render.Zoom").offset
    persist()
    return true
  end
  return self:pipelineHotkey(key, options, persist)
end

-- The (top, overworld) pair src/render/Pipelines.lua's free-roam gate reads.
--
-- Gen 1 hands it (stack:top(), overworld), and the default gate (Zoom.gateOK)
-- asks "is the overworld itself the top state, and is it idle".  Gold's
-- overworld is not a state at all -- an empty stack IS free roam -- so
-- reporting the world as its own top in that case is what makes a Gen 1-shaped
-- gate answer correctly here.  The idle half is World:acceptsMenuInput, which
-- transcribes CheckMenuOW's three gates (engine/overworld/events.asm:802) and
-- is the same test Gold's own START/SELECT presses go through.
function Game2:pipelineGate()
  local world = self.world
  if not (world and world.map) then return nil, nil end
  local top = self.stack:top()
  if top then return top, world end
  if not world:acceptsMenuInput() then return nil, world end
  return world, world
end

-- Mod render pipelines claim their hotkeys LAST, so one can never shadow an
-- engine display key however a mod declares it -- the rule and the order
-- src/core/Game.lua:652 follows.  syncOptions writes the whole ladder back,
-- including the tilt exclusion a world pipeline forces.
function Game2:pipelineHotkey(key, options, persist)
  local Pipelines = require("src.render.Pipelines")
  local top, world = self:pipelineGate()
  if not Pipelines.hotkey(key, top, world) then return false end
  Pipelines.syncOptions(options)
  require("src.render.Tilt").setLevel(options.tilt or 0)
  persist()
  return true
end

function Game2:keypressed(key)
  -- Escape is NOT a quit key: src/core/Input.lua binds it to START, which is
  -- how the start menu opens on a desktop keyboard.  Quitting is the start
  -- menu's QUIT row and the intro menu's EXIT GAME.
  -- A screen that is open owns the keyboard, the same way Game hands the top
  -- state first refusal -- except for the display ladder, which is a host
  -- control rather than a game button.  It runs during the boot cinema too:
  -- the title screen and the intro menu are exactly where someone tries the
  -- COLOR key, and the ladder's world-only rungs already refuse themselves
  -- when there is no map.
  if self:hotkey(key) then return end
  Input:keypressed(key)
end

function Game2:keyreleased(key)
  Input:keyreleased(key)
end

function Game2:wheelmoved(_x, dy)
  if self.phase == "boot" or self.stack:top() then return end
  if not (self.world and self.world.map) then return end
  if dy > 0 then
    self.world:zoomStep(1)
  elseif dy < 0 then
    self.world:zoomStep(-1)
  end
end

-- ---- the gameplay pointer seam (#807) --------------------------------------
--
-- The same hook, the same payload and the same lifecycle rules
-- src/core/Game.lua:872 documents, including the ownership rule:
-- src/core/TouchControls.lua gets FIRST REFUSAL on every touch, because a
-- pointer that begins on a virtual d-pad belongs to the pad for its whole life
-- and must never reach a mod.  Capture is decided at press and rides
-- TouchControls.touches[id]; a pointer that begins outside the controls stays
-- mod-visible even if it later wanders across one.
--
-- Everything a subscriber costs -- the per-pointer records in self.modPointers,
-- the payload tables -- is behind wantsHook, so a mod-free boot allocates
-- nothing here.

-- coordinates are LOVE window units, the same space render.hud's viewport is in
function Game2:pointerEvent(phase, source, id, x, y, dx, dy, pressure, button)
  local gameX, gameY, insideGame = GameViewport.toLocal(x, y)
  return ModRuntime.call("input.pointer", pointerUnclaimed, self, {
    phase = phase, source = source, id = id, x = x, y = y,
    gameX = gameX, gameY = gameY, insideGame = insideGame,
    dx = dx or 0, dy = dy or 0, pressure = pressure, button = button,
  })
end

function Game2:touchpressed(id, x, y, dx, dy, pressure)
  if TouchControls:touchpressed(id, x, y) then return end
  if not ModRuntime.wantsHook("input.pointer") then return end
  -- POKEPORT_TOUCH routes the mouse through here as a stand-in finger under the
  -- id "mouse" (see main.lua); mods still see its true source
  local source = id == "mouse" and "mouse" or "touch"
  self.modPointers = self.modPointers or {}
  self.modPointers[id] = { source = source, x = x, y = y, pressure = pressure }
  self:pointerEvent("pressed", source, id, x, y, dx, dy, pressure)
end

function Game2:touchmoved(id, x, y, dx, dy, pressure)
  -- The pad tracks only ids it captured at press, so this is a no-op for a
  -- mod-visible pointer; a captured one sliding between d-pad directions swaps
  -- the held GB button here.
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

function Game2:touchreleased(id, x, y, dx, dy, pressure)
  TouchControls:touchreleased(id, x, y)
  local p = self.modPointers and self.modPointers[id]
  if not p then return end
  self.modPointers[id] = nil
  if ModRuntime.wantsHook("input.pointer") then
    self:pointerEvent("released", p.source, id, x, y, dx, dy, pressure)
  end
end

-- A real mouse without POKEPORT_TOUCH.  Gameplay itself has no mouse verbs, so
-- the pointer hook is the only consumer and everything is behind the wantsHook
-- gate.  A synthesized istouch twin is dropped unconditionally: the same
-- contact already arrived through touchpressed, and forwarding both would fire
-- a mobile touch twice.
function Game2:mousepressed(x, y, button, istouch)
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
function Game2:mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  local p = self.modPointers and self.modPointers.mouse
  if p then p.x, p.y = x, y end
  if not ModRuntime.wantsHook("input.pointer") then return end
  self:pointerEvent("moved", "mouse", "mouse", x, y, dx, dy, nil, nil)
end

function Game2:mousereleased(x, y, button, istouch)
  if istouch then return end
  local p = self.modPointers and self.modPointers.mouse
  if not p then return end
  p.held = (p.held or 1) - 1
  if p.held <= 0 then self.modPointers.mouse = nil end
  if ModRuntime.wantsHook("input.pointer") then
    self:pointerEvent("released", "mouse", "mouse", x, y, 0, 0, nil, button)
  end
end

-- Focus/visibility loss swallows pointer releases the same way it swallows
-- key-ups (the hazard Input:reset exists for): every mod-visible pointer gets a
-- "cancelled" instead of leaving subscribers waiting on a "released" that can
-- never arrive.  Cleared even when the subscriber is already gone, so no stale
-- record outlives its mod.
function Game2:cancelPointers()
  local pointers = self.modPointers
  if not pointers then return end
  self.modPointers = nil
  if not ModRuntime.wantsHook("input.pointer") then return end
  for id, p in pairs(pointers) do
    self:pointerEvent("cancelled", p.source, id, p.x, p.y, 0, 0,
                      p.pressure, p.button)
  end
end

-- The three window-lifecycle callbacks main.lua forwards, with the bodies
-- src/core/Game.lua:804 gives them: drop every held button the window is about
-- to stop hearing key-ups for, reconcile back whatever is still physically
-- down, cancel live pointers, and clear the touch overlay.  LÖVE has no
-- touchcancelled, so a finger the OS takes away (an app switch, a system
-- gesture) never fires touchreleased and would strand its GB button held
-- forever -- TouchControls:reset is the only thing that frees it.
function Game2:focus(f)
  Input:reset()
  TouchControls:reset()
  if f then Input:reconcile() end
  self:cancelPointers()
end

function Game2:visible(v)
  if v then
    self:onResume()
  else
    Input:reset()
    TouchControls:reset()
    self:cancelPointers()
  end
end

function Game2:onResume()
  Input:reset()
  TouchControls:reset()
  Input:reconcile()
  self:cancelPointers()
end

-- Push the saved display options into the modules that own them.  Called
-- whenever the options table changes hands (boot, CONTINUE, the OPTION
-- screen), so a reload comes back at the zoom, tilt and GBC FX the player left.
function Game2:applyOptions()
  local options = self.options or {}
  Music.applyOptions(options)
  require("src.core.Sound").applyOptions(options)
  require("src.render.Zoom").applyOptions(options)
  require("src.render.Tilt").applyOptions(options)
  require("src.render.GbcPalette").applyOptions(options)
  -- engine/gfx/load_font.asm:29 LoadFrame, off options.lua's wTextboxFrame.
  Font.setFrame(options.frame or 1)
  -- the mod pipeline ladder rides options.pipelines and restores with the rest
  -- of the display block, as it does in src/core/Game.lua:1041
  require("src.render.Pipelines").applyOptions(options)
  -- src/core/Game.lua:1121 mirrors this call for Gen 1
  Input:applyBindings(options.bindings)
  TouchControls:applyOptions({
    touchControls = options.touchControls,
    haptics = options.haptics,
  })
  require("src.core.VideoMode").applyOptions(options)
  require("src.core.FrameCap").applyOptions(options)
  require("src.world.gen2.BorderFill").applyOptions(options)
  local GBCFX = require("src.render.GBCFX")
  if GBCFX.applyOptions(options) and self.save then
    -- applyOptions returns true when it had to clear an unsupported level.
    self.save.options = options
  end
end

-- `back` -- SDL's name for the small left-hand menu button: Xbox VIEW, the PS
-- CREATE/SHARE beside the touchpad, the Switch MINUS -- is SELECT, and has been
-- since src/core/GamepadMap.lua's DEFAULT_GAMEPAD_BINDINGS was written
-- (`back = "select"`).  It used to QUIT here, from the same era as the START
-- comment below: before there was a start menu, the menu button was the only
-- way out of a Gold boot.  That left a controller with no SELECT at all -- the
-- register/use-item press (UseRegisteredItem, engine/overworld/select_menu.asm),
-- the PACK's move-item, the party menu's reorder and half the soft-reset chord
-- (A+B+SELECT+START) were all unreachable from a pad, and pressing the button
-- to find out killed the process.  It reaches Input like every other button now.
function Game2:gamepadpressed(_joystick, button)
  -- a controller is being used: the touch overlay steps aside until the next
  -- screen touch (mobile only; a no-op elsewhere)
  TouchControls:noteGamepad()
  -- The shoulders cycle GAME SPEED, as they do in the Gen 1 path.
  if button == "rightshoulder" or button == "leftshoulder" then
    local GameSpeed = require("src.core.GameSpeed")
    local dir = button == "rightshoulder" and 1 or -1
    self.options.speed = GameSpeed.cycle(self.options.speed, dir)
    if self.save then self.save.options = self.options end
    self:persistOptions()
    return
  end
  -- START opens the start menu in the overworld; it used to quit, from before
  -- there was a menu to open.

  Input:gamepadpressed(_joystick, button)
end

function Game2:gamepadreleased(joystick, button)
  Input:gamepadreleased(joystick, button)
end

function Game2:gamepadaxis(joystick, axis, value)
  -- past-deadzone only, so resting-stick drift cannot hide the overlay
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:gamepadaxis(joystick, axis, value)
end

return Game2

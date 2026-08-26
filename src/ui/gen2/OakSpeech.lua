-- Gen 2 Oak speech (pokegold OakSpeech in engine/menus/intro_menu.asm).
-- Retail order: InitClock → Oak → Marill wipe (+ cry) → Oak → player pic →
-- NamePlayer → ready → ShrinkPlayer.  Gender select is Crystal-later;
-- InitClock is not, it is the very first thing OakSpeech farcalls
-- (engine/menus/intro_menu.asm) and it is src/ui/gen2/InitClock.lua.
--
-- The beats are a DATA TABLE for the same reason Gen 1's are
-- (src/ui/OakSpeech.lua): Gold has a real Oak speech, so it is the same
-- extension point under the same names rather than a second one.  Concretely
-- this screen carries:
--
--   hook  intro.oak_speech.build     (steps, speech) -> steps
--   event intro.oak_speech.started   { speech, steps }
--   event intro.oak_speech.step      { speech, step, index }
--   event intro.oak_speech.answered  { speech, step, index, label, value,
--                                      saveKey }
--   event intro.oak_speech.finished  { speech, answers }
--
-- Same names, same payload keys, same moments in the sequence as the Gen 1
-- site: `started` before the first beat runs, `step` immediately before each
-- beat, `answered` whenever a beat produces a value (the name menu, and any
-- choice a mod inserted), `finished` once, on the way out.  Step ids match
-- Gen 1's wherever the moment is the same one -- oak_welcome, demo_mon,
-- world_spiel, ask_player_name, name_player, legend, shrink -- so a mod that
-- does insertBefore("name_player", ...) lands in the right place in both
-- games.  The two ids with no Gen 1 counterpart are Gold's own beats:
-- `init_clock` (the farcall InitClock this speech opens with) and `oak_study`
-- (the return to Oak for _OakText5, which Red's speech does not have).
--
-- Gen 1 has no confirm_player_name / ask_rival_name / name_rival /
-- confirm_rival_name equivalents here on purpose: Gold's Oak never says the
-- name back and never asks for the rival's, so inventing those anchors would
-- promise moments that do not exist (the rival is named by the CopScript in
-- maps/ElmsLab.asm, hours later).

-- src/render/Assets.lua is the mod-override choke point: a raw
-- love.graphics.newImage skips overrides/ and AssetTransform output.
local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Font = require("src.render.Font")
local Gen2Save = require("src.core.gen2.Save")
local GbcPalette = require("src.render.GbcPalette")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local OakSpeech = {}
OakSpeech.__index = OakSpeech
OakSpeech.isOpaque = true

local FADE_FRAMES = 24
local WIPE_FRAMES = 32

local FALLBACKS = {
  _OakText1 = Strings("Hello! Sorry to\nkeep you waiting!\fWelcome to the\nworld of POKéMON!\fMy name is OAK.\fPeople call me the\nPOKéMON PROF."),
  _OakText2 = Strings("This world is in-\nhabited by crea-\vtures that we call\vPOKéMON."),
  _OakText4 = Strings("People and POKéMON\nlive together by\fsupporting each\nother.\fSome people play\nwith POKéMON, some\vbattle with them."),
  _OakText5 = Strings("But we don't know\neverything about\vPOKéMON yet.\fThere are still\nmany mysteries to\vsolve.\fThat's why I study\nPOKéMON every day."),
  _OakText6 = Strings("Now, what did you\nsay your name was?"),
  _OakText7 = Strings("{PLAYER}, are you\nready?\fYour very own\nPOKéMON story is\vabout to unfold.\fYou'll face fun\ntimes and tough\vchallenges.\fA world of dreams\nand adventures\fwith POKéMON\nawaits! Let's go!\fI'll be seeing you\nlater!"),
}

local function tryImage(path)
  if not path then return nil end
  local ok, image = pcall(Assets.image, path)
  return ok and image or nil
end

-- Naming presets are boot config the same way Gen 1 reads them
-- (field.boot.namePresets), so a total conversion that replaces the list once
-- replaces it for both games; NamePick.presetsFor (data/player_names.asm
-- PlayerNameArray) is the running edition's fallback.
local function namePresets(game, who, fallback)
  local boot = game and game.data and game.data.field
    and game.data.field.boot
  local presets = boot and boot.namePresets and boot.namePresets[who]
  if type(presets) == "table" and #presets > 0 then return presets end
  return fallback
end

function OakSpeech:wantsFillScale() return true end
function OakSpeech:drawsWidescreen() return true end

function OakSpeech.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, OakSpeech)
  self.game = game
  self.onDone = opts.onDone
  local data = opts.data or {}
  self.cfg = data
  self.texts = data.text or {}
  self.oakPic = tryImage(data.oakPic or "assets/generated/intro/oak.png")
  -- player.sprite, where Gen 1's Oak speech raises it (src/ui/OakSpeech.lua:121).
  self.playerPic = tryImage(require("src.pokemon.Sprites").playerPic(
    data.playerPic or "assets/generated/intro/cal.png",
    { side = "front", kind = "intro", data = game and game.data }))
  -- DrawIntroPlayerPic's other arm, KrisPic under trainer class KRIS
  -- (../pokecrystal/engine/gfx/player_gfx.asm:170-188).
  self.playerPicFemale = tryImage(require("src.pokemon.Sprites").playerPic(
    data.playerPicFemale or "assets/generated/intro/kris.png",
    { side = "front", kind = "intro", data = game and game.data }))
  self.marillPic = tryImage(data.marillPic
    or "assets/generated/battle/front/marill.png")
  self.shrinkPic1 = tryImage(data.shrink1 or "assets/generated/intro/shrink1.png")
  self.shrinkPic2 = tryImage(data.shrink2 or "assets/generated/intro/shrink2.png")
  self.music = data.music or "Music_Route30"
  self.demoSpecies = data.demoSpecies or "MARILL"
  -- Every pic on this screen is loaded under SCGB_TRAINER_OR_MON_FRONTPIC_PALS,
  -- which is _CGB_PlayerOrMonFrontpicPals -- the pic's own two shipped colours
  -- bracketed by white and black, exactly as a battle pic gets them.  The
  -- speech names the class the ASM names: POKEMON_PROF for Oak, CAL for the
  -- player (Chris shares Cal's colours, which is why the extractor calls row 0
  -- PLAYER).  The shrink frames are the player still, so they wear his.
  local palettes = (game and game.data and game.data.gen2Palettes) or nil
  self.palettes = palettes
  self.oakColors = Palettes.trainerColors(palettes, "POKEMON_PROF")
  self.playerColors = Palettes.trainerColors(palettes, "CAL")
  -- KrisPalette is Falkner's row, shared rather than shipped
  -- (../pokecrystal/data/trainers/palettes.asm:11-12).
  self.playerColorsFemale = Palettes.trainerColors(palettes, "FALKNER")
  self.marillColors = Palettes.monColors(palettes, self.demoSpecies)
  self.picColors = nil
  self.fontOk = false
  local font = opts.font
  if font then
    local ok = pcall(Font.load, { font = font })
    self.fontOk = ok
  end
  self.step = 0
  self.steps = nil
  self.answers = {}
  self.pic = nil
  self.picFlip = false
  self.picReveal = nil
  self.busy = false
  self.shrink = nil
  self.shrinkText = nil
  return self
end

-- wPlayerGender, the byte the gender step below writes
-- (../pokecrystal/engine/menus/init_gender.asm:36-38).
function OakSpeech:gender()
  local save = self.game and self.game.save
  return save and save.player and save.player.gender or nil
end

-- DrawIntroPlayerPic reads the byte every time it runs, so the pic follows the
-- answer rather than whatever was loaded when the speech opened
-- (../pokecrystal/engine/gfx/player_gfx.asm:170-188).
function OakSpeech:playerPicNow()
  if self:gender() == "female" and self.playerPicFemale then
    return self.playerPicFemale, self.playerColorsFemale or self.playerColors
  end
  return self.playerPic, self.playerColors
end

function OakSpeech:text(key)
  local t = self.texts[key]
  if type(t) == "string" and #t > 0 then return t end
  return FALLBACKS[key] or ""
end

-- ------------------------------------------------------------------ steps

-- The vanilla beat list.  Ids are the stable anchors a build wrapper inserts
-- around; see the header for which of them are shared with Gen 1.
function OakSpeech.defaultSteps(speech)
  local steps = {
    -- `farcall InitClock` is the first line of OakSpeech.
    { id = "init_clock", kind = "initclock" },
    -- Intro_PrepTrainerPic POKEMON_PROF, FadeInIntroPic, OakText1.
    { id = "oak_welcome", kind = "say", textKey = "_OakText1",
      pic = "oak", reveal = "fade" },
    -- The Marill show-off: MovePicRight wipes it in, then its cry, then
    -- OakText2.  Gen 1's demo_mon beat with a different mon.
    { id = "demo_mon", kind = "demo" },
    -- OakText4 over the same pic, exactly as Gen 1's world_spiel prints
    -- OakSpeechText2B over the NIDORINO already on screen.
    { id = "world_spiel", kind = "say", textKey = "_OakText4" },
    -- Back to Oak for OakText5.  Red's speech never returns to him, so this
    -- id is Gold's own.
    { id = "oak_study", kind = "say", textKey = "_OakText5",
      pic = "oak", reveal = "fade" },
    -- The CAL frontpic comes up under the question NamePlayer answers.
    { id = "ask_player_name", kind = "say", textKey = "_OakText6",
      pic = "player", reveal = "fade" },
    { id = "name_player", kind = "name", who = "player", saveKey = "name" },
    -- OakText7 with the pic already up: NamePlayer walked it back itself
    -- (MovePlayerPicLeft), so there is nothing to reveal here.
    { id = "legend", kind = "say", textKey = "_OakText7", pic = "player" },
    { id = "shrink", kind = "shrink", textKey = "_OakText7" },
  }
  -- PlayerProfileSetup's `farcall InitGender` runs before OakSpeech is called.
  -- ../pokecrystal/engine/menus/intro_menu.asm:61-67, :79-83
  local data = speech and speech.game and speech.game.data
  if FieldMoves.hasGenderChoice(data and data.gen2Sprites) then
    table.insert(steps, 1, { id = "gender_select", kind = "gender",
      saveKey = "gender" })
  end
  return steps
end

local function sameSteps(steps) return steps end

-- intro.oak_speech.build, the same hook Gen 1 offers and with the same
-- contract: a wrapper is handed the step list and the speech and returns a
-- step list.  Anything else degrades to vanilla with a logged line rather
-- than dropping the player into a speech that cannot run.
function OakSpeech:buildSteps()
  local steps = OakSpeech.defaultSteps(self)
  if not Runtime.wantsHook("intro.oak_speech.build") then return steps end
  local hooked = Runtime.call("intro.oak_speech.build", sameSteps, steps, self)
  if type(hooked) ~= "table" then
    Logger.error("intro.oak_speech.build returned %s; keeping vanilla steps",
                 type(hooked))
    return steps
  end
  return hooked
end

-- `ld de, MUSIC_ROUTE_30 / call PlayMusic`, after InitGender's fade.
-- ../pokecrystal/engine/menus/intro_menu.asm:632-633, init_gender.asm:59-65
function OakSpeech:startMusic()
  if self.musicStarted then return end
  self.musicStarted = true
  local data = self.game and self.game.data
  if data and data.audio and data.audio.runtime then
    Music.play(data, self.music, true, { reason = "oak_speech" })
  end
end

function OakSpeech:enter()
  self.step = 0
  self.answers = {}
  self.steps = self:buildSteps()
  if not (self.steps[1] and self.steps[1].kind == "gender") then
    self:startMusic()
  end
  if Runtime.wants("intro.oak_speech.started") then
    Runtime.emit("intro.oak_speech.started", { speech = self, steps = self.steps })
  end
  self:advance()
end

-- ------------------------------------------------------------------ pics

-- A step's `pic`.  The three names are this speech's own art; the table forms
-- are for a build wrapper bringing its own, and they carry their palette the
-- same way every pic on this screen does (two shipped colours, bracketed).
function OakSpeech:resolvePic(desc)
  if desc == "oak" then return self.oakPic, self.oakColors end
  if desc == "player" then return self:playerPicNow() end
  if desc == "demo" then return self.marillPic, self.marillColors end
  if type(desc) ~= "table" then return nil, nil end
  if desc.type == "pokemon" then
    local mon = self.game and self.game.data and self.game.data.pokemon
    local def = mon and mon[desc.id]
    return tryImage(def and def.spriteFront),
      desc.colors or Palettes.monColors(self.palettes, desc.id)
  end
  if desc.type == "trainer" then
    return tryImage(desc.path),
      desc.colors or Palettes.trainerColors(self.palettes, desc.id)
  end
  -- { type = "image", path = ..., colors = ... }, and a pre-loaded image.
  if desc.path then return tryImage(desc.path), desc.colors end
  return desc.image, desc.colors
end

-- picFlip belongs to the pic and not to the step: only a beat that changes
-- the pic may change it, so a text-only beat leaves whatever is on screen
-- exactly as the beat before it left it.
function OakSpeech:applyPic(step)
  if step.pic == nil then return end
  local img, colors = self:resolvePic(step.pic)
  self.pic = img
  self.picColors = colors
  self.picFlip = step.flip and true or false
end

function OakSpeech:reveal(kind, next)
  self.picReveal = {
    kind = kind,
    t = 0,
    dur = kind == "wipe" and WIPE_FRAMES or FADE_FRAMES,
    next = next,
  }
end

function OakSpeech:afterReveal(step, fn)
  if step.reveal then
    self:reveal(step.reveal, fn)
  else
    fn()
  end
end

function OakSpeech:showPic(img, reveal, next, colors)
  self.pic = img
  self.picColors = colors
  self.picFlip = false
  if reveal then
    self:reveal(reveal, next)
  elseif next then
    next()
  end
end

function OakSpeech:playCry(species)
  local data = self.game and self.game.data
  if data and data.audio and data.audio.cries and data.audio.cries[species] then
    Sound.playCry(data, species)
  end
end

function OakSpeech:playMarillCry()
  self:playCry(self.demoSpecies)
end

-- A step's own cry: `cry = true` means "the mon this step's pic shows".
function OakSpeech:runCry(step)
  local cry = step.cry
  if not cry then return end
  if cry == true then
    if type(step.pic) == "table" and step.pic.type == "pokemon" then
      cry = step.pic.id
    elseif step.pic == "demo" then
      cry = self.demoSpecies
    else
      return
    end
  end
  self:playCry(cry)
end

-- ------------------------------------------------------------------ beats

function OakSpeech:stepText(step)
  if step.text then return step.text end
  if step.textKey then return self:text(step.textKey) end
  return ""
end

function OakSpeech:sayText(text, next, opts)
  self.busy = true
  self.game.stack:push(TextBox.new(self.game, text, function()
    self.busy = false
    if next then next() end
  end, opts))
end

function OakSpeech:say(key, next)
  self:sayText(self:text(key), next)
end

-- `farcall InitClock` does not return until both halves are confirmed, so the
-- port pushes the screen and only advances on its way out.  A build with no
-- stack (a headless logic test) skips straight to Oak, the way every other
-- pushed screen here does.
function OakSpeech:openInitClock()
  local game = self.game
  if not (game and game.stack) then return self:advance() end
  self.busy = true
  local pushed = Screens.push(game, "Gen2InitClock", {
    mode = "clock",
    save = game.save,
    autoConfirm = self.autoConfirm,
    onDone = function()
      game.stack:pop()
      self.busy = false
      self:advance()
    end,
  })
  if not pushed then
    self.busy = false
    self:advance()
  end
end

-- InitGender, pushed where PlayerProfileSetup farcalls it: before the speech
-- says anything and before its music starts
-- (../pokecrystal/engine/menus/intro_menu.asm:79-83).
function OakSpeech:openGenderSelect(step)
  local game = self.game
  if not (game and game.stack) then
    self:startMusic()
    return self:advance()
  end
  self.busy = true
  local pushed = Screens.push(game, "Gen2GenderSelect", {
    save = game.save,
    onDone = function(gender)
      game.stack:pop()
      self.busy = false
      -- `ld hl, wPlayerName / ld de, .Chris|.Kris / call InitName`, the default
      -- NamePlayer lays down before the menu opens
      -- (../pokecrystal/engine/menus/intro_menu.asm:768-781).
      local save = game.save
      if save and save.player then
        save.player.name = Gen2Save.defaultPlayerName(save.version, gender)
      end
      self:recordAnswer(step, gender == "female" and 2 or 1,
        gender == "female" and "Girl" or "Boy", gender)
      self:startMusic()
      self:advance()
    end,
  })
  if not pushed then
    self.busy = false
    self:startMusic()
    self:advance()
  end
end

function OakSpeech:openNamePick(step)
  self.busy = true
  local NamePick = require("src.ui.gen2.NamePick")
  local gender = self:gender()
  local pic, picColors = self:playerPicNow()
  Screens.push(self.game, "Gen2NamePick", {
    font = self.game.fontData,
    gender = gender,
    -- NamePlayer opens with MovePlayerPicRight, so the name menu owns the
    -- pic while it is up: it is the same CAL frontpic this speech has been
    -- showing, walked over to make room for the box.
    pic = pic,
    picColors = picColors,
    presets = step.presets
      or namePresets(self.game, step.presetsWho or step.who or "player",
                     step.presetsFallback or NamePick.presetsFor(gender)),
    onDone = function(name)
      name = name or NamePick.presetsFor(gender)[1]
      self.game.save.player.name = name
      self.game.stack:pop() -- NamePick
      self.busy = false
      self:recordAnswer(step, 1, name, name)
      self:advance()
    end,
  })
end

function OakSpeech:lastPageLines(key)
  local body = self:text(key)
  local pages = {}
  for page in (body .. "\f"):gmatch("(.-)\f") do
    pages[#pages + 1] = page
  end
  local last = pages[#pages] or body
  local lines = {}
  for line in (last .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then lines[#lines + 1] = line end
  end
  if #lines == 0 and last ~= "" then lines[1] = last end
  return lines
end

function OakSpeech:startShrink(step)
  self.shrinkText = self:lastPageLines((step and step.textKey) or "_OakText7")
  self.shrink = { frame = 0 }
  local data = self.game and self.game.data
  if data and data.audio and data.audio.sfx
      and data.audio.sfx.Sfx_EscapeRope then
    Sound.play(data, "Sfx_EscapeRope")
  end
end

-- A beat that produced a value: the name menu, and any choice/yesno a build
-- wrapper inserted.  Same store and same event payload as Gen 1's, so a mod
-- reading answers off intro.oak_speech.answered needs no second listener.
function OakSpeech:recordAnswer(step, index, label, value)
  if value == nil then value = label end
  if step.saveKey then
    self.answers[step.saveKey] = value
  end
  if Runtime.wants("intro.oak_speech.answered") then
    Runtime.emit("intro.oak_speech.answered", {
      speech = self,
      step = step,
      index = index,
      label = label,
      value = value,
      saveKey = step.saveKey,
    })
  end
end

-- The choice menu a build wrapper's `choice` step opens: VerticalMenu, which
-- is Gold's generic list (src/ui/gen2/ScriptMenu.lua) and so already carries
-- the shared ui.list_menu hook.  Vanilla Gold has no such beat -- this is the
-- Gen 1 step kind honoured on Gold rather than skipped with a warning.
function OakSpeech:openChoice(step)
  local labels = step.choices or {}
  local left, top = step.tx or 0, step.ty or 0
  local width = step.tw or 10
  local pushed = Screens.push(self.game, "Gen2ScriptMenu", {
    header = {
      left = left, top = top,
      right = left + width, bottom = top + #labels * 2 + 1,
      items = labels,
      -- STATICMENU_CURSOR; B is left enabled only when the step asks for it.
      dataFlags = 0x80,
      cursor = 1,
    },
    style = "vertical",
    onChoose = function(index)
      self.game.stack:pop()
      self.busy = false
      if index == 0 or index == nil then
        if step.cancelable then return self:advance() end
        index = 1
      end
      local label = labels[index]
      local value = label
      if step.values and step.values[index] ~= nil then
        value = step.values[index]
      end
      self:recordAnswer(step, index, label, value)
      self:advance()
    end,
  })
  if not pushed then
    self.busy = false
    self:advance()
  end
end

function OakSpeech:runStep(step)
  local kind = step.kind or "say"
  if kind == "gender" then
    self:openGenderSelect(step)
  elseif kind == "initclock" then
    self:openInitClock()
  elseif kind == "say" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      self:sayText(self:stepText(step), function() self:advance() end)
    end)
  elseif kind == "demo" then
    -- Intro_PrepMonFrontpic + MovePicRight + the cry, then OakText2.
    self:showPic(self.marillPic, "wipe", function()
      self:playMarillCry()
      self:say("_OakText2", function() self:advance() end)
    end, self.marillColors)
  elseif kind == "pic" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      self:advance()
    end)
  elseif kind == "name" then
    self:openNamePick(step)
  elseif kind == "yesno" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      self.busy = true
      self:sayText(self:stepText(step), nil, {
        instant = true,
        choice = function(yes)
          self.busy = false
          local label = yes and "YES" or "NO"
          local value = yes
          if step.values then
            value = yes and step.values[1] or step.values[2]
          end
          self:recordAnswer(step, yes and 1 or 2, label, value)
          self:advance()
        end,
      })
    end)
  elseif kind == "choice" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      local text = self:stepText(step)
      if text ~= "" then
        self:sayText(text, function() self:openChoice(step) end)
      else
        self:openChoice(step)
      end
    end)
  elseif kind == "shrink" then
    self:startShrink(step)
  elseif kind == "fn" then
    -- full escape hatch: step.run(speech, done)
    if type(step.run) == "function" then
      step.run(self, function() self:advance() end)
    else
      self:advance()
    end
  else
    Logger.warn("oak speech unknown step kind %s (id=%s); skipping",
                tostring(kind), tostring(step.id))
    self:advance()
  end
end

function OakSpeech:advance()
  self.step = self.step + 1
  local steps = self.steps
  if not steps then
    -- enter() builds the list; keep a path for callers that advance early.
    steps = self:buildSteps()
    self.steps = steps
  end
  local step = steps[self.step]
  if not step then return self:finish() end
  if Runtime.wants("intro.oak_speech.step") then
    Runtime.emit("intro.oak_speech.step", {
      speech = self, step = step, index = self.step,
    })
  end
  self:runStep(step)
end

function OakSpeech:finish()
  -- Guarded like the Gen 1 site (#308): the shrink timeline keeps ticking
  -- while a `finished` listener does whatever it does, and a second emit from
  -- the same run would look like a second speech.
  if self.finished then return end
  self.finished = true
  if Runtime.wants("intro.oak_speech.finished") then
    Runtime.emit("intro.oak_speech.finished", {
      speech = self, answers = self.answers,
    })
  end
  if self.onDone then self.onDone() end
end

function OakSpeech:update(_dt)
  local r = self.picReveal
  if r then
    r.t = r.t + 1
    if r.t >= r.dur then
      self.picReveal = nil
      if r.next then r.next() end
    end
    return
  end
  -- ShrinkPlayer timeline (intro_menu.asm ShrinkPlayer): pic1 → pic2 →
  -- clear → chris sprite beat → fade music → overworld.
  local s = self.shrink
  if not s then return end
  s.frame = s.frame + 1
  if s.frame == 8 then
    self.pic = self.shrinkPic1 or self.pic
  elseif s.frame == 16 then
    self.pic = self.shrinkPic2 or self.pic
  elseif s.frame == 24 then
    self.pic = nil
  elseif s.frame == 32 then
    Music.fadeOut(10)
  elseif s.frame >= 80 then
    self.shrink = nil
    self.shrinkText = nil
    self:finish()
  end
end

function OakSpeech:drawPic()
  if not self.pic then return end
  local G = love.graphics
  local w, h = self.pic:getDimensions()
  -- Intro_PrepTrainerPic / PrepMonFrontpic: 7x7 cell at hlcoord 6,4.
  local x = 48 + math.floor((8 - w / 8) / 2) * 8
  local y = 32 + (7 - h / 8) * 8
  local reveal = self.picReveal
  local off = 0
  if reveal and reveal.kind == "fade" then
    G.setColor(1, 1, 1, math.min(1, reveal.t / reveal.dur))
  elseif reveal and reveal.kind == "wipe" then
    off = math.floor((160 - x) * (1 - math.min(1, reveal.t / reveal.dur)))
  else
    G.setColor(1, 1, 1, 1)
  end
  local function body()
    if self.picFlip then
      G.draw(self.pic, x + off + w, y, 0, -1, 1)
    else
      G.draw(self.pic, x + off, y)
    end
  end
  -- A "fade" reveal is an alpha ramp, and GbcPalette multiplies the tint into
  -- its own output, so the two compose: the shader picks the colour and
  -- setColor's alpha still fades it in.
  if self.picColors and GbcPalette.available() then
    GbcPalette.with(self.picColors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function OakSpeech:drawPanel()
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, 160, 144)
  self:drawPic()
  if self.shrinkText and self.fontOk then
    G.setColor(0, 0, 0, 1)
    for i, line in ipairs(self.shrinkText) do
      Font.draw(line, 16, 104 + (i - 1) * 16)
    end
    G.setColor(1, 1, 1, 1)
  end
end

function OakSpeech:draw()
  self:drawPanel()
end

function OakSpeech:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return OakSpeech

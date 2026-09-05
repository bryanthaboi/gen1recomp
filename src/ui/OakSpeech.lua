-- The intro sequence (engine/movie/oak_speech/oak_speech.asm): Oak's
-- welcome, the NIDORINO show-off, player and rival naming, and the
-- closing "legend is about to unfold" text followed by the shrink-away.
--
-- Steps are a data table so mods can reshape the whole speech through
-- hooks:wrap("intro.oak_speech.build").  Vanilla ids stay stable so a
-- mod can insertBefore("name_player", ...) without counting indices.
-- Calls onDone() after popping itself.

local Assets = require("src.render.Assets")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local TextBox = require("src.render.TextBox")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local OakSpeech = {}
OakSpeech.__index = OakSpeech
OakSpeech.isOpaque = true

-- The speech is a white field with a pic on it, and its dialogue box docks to
-- the WINDOW's bottom edge (Renderer:setUIAnchor, via TextBox).  The white it
-- fills below is only the 160x144 UI canvas, so once the box moved to the
-- window edge the two stopped touching: black letterbox showed between the
-- bottom of Oak's white and the top of the box he is speaking from.  Filling
-- the voids with the paper shade -- the same opt-in a battle uses -- puts the
-- box back on the field.  Not a literal 1,1,1: the canvas is colorized, so
-- endFrame matches it with PaletteFX.paperShade.
OakSpeech.letterboxWhite = true

-- FadeInIntroPic runs a 6-step palette fade; MovePicLeft wipes the mon
-- sprite in from the right.  Both play out before the beat's text prints.
-- engine/movie/oak_speech/oak_speech.asm:191-209
local INTRO_FADE_BGP = { 0x54, 0xA8, 0xFC, 0xF8, 0xF4, 0xE4 }
local INTRO_FADE_STEP = 10
-- home/fade.asm:48-62,65-73
local WHITE_IN_BGP = { 0x40, 0x90, 0xE4 }
local WHITE_FADE_STEP = 8
local WIPE_FRAMES = 32

OakSpeech.INTRO_FADE_BGP = INTRO_FADE_BGP
OakSpeech.INTRO_FADE_STEP = INTRO_FADE_STEP
OakSpeech.WHITE_IN_BGP = WHITE_IN_BGP
OakSpeech.WHITE_FADE_STEP = WHITE_FADE_STEP

-- OakSpeechSlidePicRight / OakSpeechSlidePicLeft (oak_speech2.asm:67-89)
local SLIDE_TILES = 6
local SLIDE_FRAMES = 3

local PicSlide = {}
PicSlide.__index = PicSlide

function PicSlide:update(dt)
  -- OakSpeechSlidePicLeft: ClearScreenArea, ld c, 10 / DelayFrames, Delay3
  -- before the first slide step (oak_speech2.asm:69-78)
  if (self.delay or 0) > 0 then
    self.delay = self.delay - 1
    return
  end
  self.t = self.t + 1
  local tiles = math.min(SLIDE_TILES, math.floor(self.t / SLIDE_FRAMES))
  self.speech.picSlide = (self.dir > 0 and tiles or (SLIDE_TILES - tiles)) * 8
  if tiles >= SLIDE_TILES then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

-- naming presets are boot config (field.boot.namePresets), which a total
-- conversion replaces; the Red/Blue lists remain the fallback
local function namePresets(game, who, fallback)
  local boot = game.data.field and game.data.field.boot
  local presets = boot and boot.namePresets and boot.namePresets[who]
  if type(presets) == "table" and #presets > 0 then return presets end
  return fallback
end

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function OakSpeech:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local FALLBACKS = {
  _OakSpeechText1 = Strings.source("Hello there!\nWelcome to the\vworld of POKéMON!\fMy name is OAK!\nPeople call me\vthe POKéMON PROF!"),
  _OakSpeechText2A = Strings.source("This world is\ninhabited by\vcreatures called\vPOKéMON!"),
  _OakSpeechText2B = Strings.source("\fFor some people,\nPOKéMON are\vpets. Others use\vthem for fights.\fMyself...\fI study POKéMON\nas a profession."),
  _OakSpeechText3 = Strings.source("{PLAYER}!\fYour very own\nPOKéMON legend is\vabout to unfold!\fA world of dreams\nand adventures\vwith POKéMON\vawaits! Let's go!"),
  _IntroducePlayerText = Strings.source("First, what is\nyour name?"),
  _IntroduceRivalText = Strings.source("This is my grand-\nson. He's been\vyour rival since\vyou were a baby.\f...Erm, what is\nhis name again?"),
  _YourNameIsText = Strings.source("Right! So your\nname is {PLAYER}!"),
  _HisNameIsText = Strings.source("That's right! I\nremember now! His\vname is {RIVAL}!"),
}

local function textOr(game, key)
  local t = game.data.text
  return (t and t[key]) or FALLBACKS[key]
end

-- through Assets.resolve so an enabled mod's overrides/ shadows these the
-- same way it shadows every other generated asset
local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
  return ok and img or nil
end

-- Resolve a pic descriptor to (image, flip, trueColor).
-- Descriptors:
--   "oak" | "rival" | "player"          shorthand
--   { type = "trainer", id = "OPP_PROF_OAK" }
--   { type = "pokemon", id = "PIKACHU", flip = true }
--   { type = "player", path = "..." }   optional override path
--   { type = "image", path = "..." }
--   { type = "sprite", id = "SPRITE_RED" }
function OakSpeech.resolvePic(game, desc, speech)
  if desc == nil then return nil, false, false end
  if type(desc) == "string" then
    if desc == "oak" then
      desc = { type = "trainer", id = "OPP_PROF_OAK" }
    elseif desc == "rival" then
      desc = { type = "trainer", id = "OPP_RIVAL1" }
    elseif desc == "player" then
      desc = { type = "player" }
    else
      -- bare species id
      desc = { type = "pokemon", id = desc }
    end
  end
  local t = desc.type
  if t == "trainer" then
    if speech and desc.id == "OPP_PROF_OAK" and speech.oakPic then
      return speech.oakPic, false, speech.oakTrueColor or false
    end
    if speech and desc.id == "OPP_RIVAL1" and speech.rivalPic then
      return speech.rivalPic, false, speech.rivalTrueColor or false
    end
    local trainers = game.data.trainers or {}
    local tr = trainers[desc.id]
    return tryImage(tr and tr.pic), false, tr and tr.trueColor or false
  elseif t == "pokemon" then
    if speech and desc.id == speech.demoSpecies and speech.demoPic then
      return speech.demoPic, desc.flip and true or false, speech.demoTrueColor
    end
    local path, trueColor = require("src.pokemon.Sprites").path(
      game.data, desc.id, "front", { kind = "oak" })
    return tryImage(path), desc.flip and true or false, trueColor
  elseif t == "player" then
    if speech and speech.playerPic and not desc.path then
      return speech.playerPic, false, speech.playerTrueColor
    end
    if desc.path then return tryImage(desc.path), false, false end
    local path, trueColor = require("src.pokemon.Sprites").playerPath(
      game.data, "front", { kind = "intro" })
    return tryImage(path), false, trueColor
  elseif t == "image" then
    return tryImage(desc.path), desc.flip and true or false, false
  elseif t == "sprite" then
    local sp = game.data.sprites and game.data.sprites[desc.id]
    return tryImage(sp and sp.image), desc.flip and true or false,
           sp and sp.trueColor or false
  end
  return nil, false, false
end

-- Vanilla step list.  Ids are the stable anchors mods insert around.
function OakSpeech.defaultSteps(speech)
  return {
    {
      id = "oak_welcome",
      kind = "say",
      textKey = "_OakSpeechText1",
      pic = "oak",
      -- text_2.asm:1704
      -- oak_speech.asm:73
      reveal = "fade",
      fadeOut = true,
    },
    {
      id = "demo_mon",
      kind = "demo",
    },
    {
      id = "world_spiel",
      kind = "say",
      textKey = "_OakSpeechText2B",
      -- text_2.asm:1725
      -- oak_speech.asm:84
      fadeOut = true,
    },
    {
      id = "ask_player_name",
      kind = "say",
      textKey = "_IntroducePlayerText",
      pic = "player",
      -- oak_speech.asm:89-92: MovePicLeft, then IntroducePlayerText's
      -- `prompt` (text_2.asm:1730) waits for A and leaves the box up
      reveal = "wipe",
      stay = true,
    },
    {
      id = "name_player",
      kind = "name",
      who = "player",
      title = Strings("YOUR NAME?"),
      presetsWho = "player",
      presetsFallback = { "RED", "ASH", "JACK" },
    },
    {
      -- oak_speech.asm prints YourNameIsText right after the naming screen
      -- returns ("Right! So your name is RED!"); the port went straight on
      -- to the rival and dropped it, in every language.
      id = "confirm_player_name",
      kind = "say",
      textKey = "_YourNameIsText",
      -- _YourNameIsText's `prompt` (text_2.asm:1766), then GBFadeOutToWhite
      -- / ClearScreen with the box still up (oak_speech.asm:93-94)
      fadeOut = true,
    },
    {
      id = "ask_rival_name",
      kind = "say",
      textKey = "_IntroduceRivalText",
      pic = "rival",
      -- oak_speech.asm:98-101: FadeInIntroPic, then IntroduceRivalText's
      -- `prompt` (text_2.asm:1740) leaves the box up for ChooseRivalName
      reveal = "fade",
      stay = true,
    },
    {
      id = "name_rival",
      kind = "name",
      who = "rival",
      -- engine/menus/naming_screen.asm:487
      title = Strings("RIVAL's NAME?"),
      presetsWho = "rival",
      presetsFallback = { "BLUE", "GARY", "JOHN" },
    },
    {
      -- HisNameIsText, the rival's counterpart to the confirmation above
      id = "confirm_rival_name",
      kind = "say",
      textKey = "_HisNameIsText",
      -- _HisNameIsText's `prompt` (text_2.asm:1772) then the .skipSpeech
      -- fade with the box up (oak_speech.asm:103-104)
      fadeOut = true,
    },
    {
      id = "legend",
      kind = "say",
      textKey = "_OakSpeechText3",
      pic = "player",
      -- oak_speech.asm:106-108
      reveal = "fade_white_in",
    },
    {
      id = "shrink",
      kind = "shrink",
    },
  }
end

-- list helpers for intro.oak_speech.build wrappers (also on ModUI)
local function indexOfId(steps, id)
  for i, step in ipairs(steps) do
    if step.id == id then return i end
  end
  return nil
end

function OakSpeech.insertBefore(steps, anchorId, step)
  local i = indexOfId(steps, anchorId)
  table.insert(steps, i or (#steps + 1), step)
  return steps
end

function OakSpeech.insertAfter(steps, anchorId, step)
  local i = indexOfId(steps, anchorId)
  table.insert(steps, i and (i + 1) or (#steps + 1), step)
  return steps
end

function OakSpeech.removeId(steps, id)
  for i = #steps, 1, -1 do
    if steps[i].id == id then table.remove(steps, i) end
  end
  return steps
end

function OakSpeech.new(game, onDone)
  local self = setmetatable({}, OakSpeech)
  self.game = game
  self.onDone = onDone
  self.step = 0
  self.pic = nil
  self.answers = {}
  local trainers = game.data.trainers or {}
  self.oakPic = tryImage(trainers.OPP_PROF_OAK and trainers.OPP_PROF_OAK.pic)
  self.oakTrueColor = self.oakPic
    and trainers.OPP_PROF_OAK and trainers.OPP_PROF_OAK.trueColor or false
  self.rivalPic = tryImage(trainers.OPP_RIVAL1 and trainers.OPP_RIVAL1.pic)
  self.rivalTrueColor = self.rivalPic
    and trainers.OPP_RIVAL1 and trainers.OPP_RIVAL1.trueColor or false
  local oakGfx = (game.data.field and game.data.field.oakSpeech) or {}
  self.cfg = oakGfx
  -- the show-off mon and the name length cap come from data; the vanilla
  -- literals stay as the fallbacks
  self.demoSpecies = oakGfx.demoSpecies or "NIDORINO"
  local demoPath, demoTrueColor = require("src.pokemon.Sprites").path(
    game.data, self.demoSpecies, "front", { kind = "oak" })
  self.demoPic = tryImage(demoPath)
  self.demoTrueColor = self.demoPic and demoTrueColor or false
  local constants = game.data.constants or {}
  self.nameLen = constants.playerNameLength or 7
  -- RedPicFront (gfx/player/red.png, shared with the trainer card) and
  -- the ShrinkPic1/ShrinkPic2 frames (gfx/player/shrink{1,2}.png)
  local playerPath, playerTrueColor = require("src.pokemon.Sprites").playerPath(
    game.data, "front", { kind = "intro" })
  self.playerPic = tryImage(playerPath)
  self.playerTrueColor = self.playerPic and playerTrueColor or false
  self.shrinkPic1 = tryImage(oakGfx.shrink1
                             or "assets/generated/intro/shrink1.png")
  self.shrinkPic2 = tryImage(oakGfx.shrink2
                             or "assets/generated/intro/shrink2.png")
  -- RedSprite: the walking sprite the pic shrinks into (frame 0 =
  -- standing, facing down)
  local playerSprites = (game.data.field and game.data.field.playerSprites) or {}
  -- The fallback has to read the same guarded table: reaching for
  -- game.data.sprites.SPRITE_RED after the `and` already found it nil threw.
  local sprites = game.data.sprites or {}
  local red = sprites[playerSprites.walk or "SPRITE_RED"] or sprites.SPRITE_RED
  self.walkSheet = tryImage(red and red.image)
  return self
end

function OakSpeech:buildSteps()
  local steps = OakSpeech.defaultSteps(self)
  local hooked = Runtime.call("intro.oak_speech.build",
    function(s) return s end, steps, self)
  if type(hooked) ~= "table" then
    Logger.error("intro.oak_speech.build returned %s; keeping vanilla steps",
                 type(hooked))
    return steps
  end
  return hooked
end

function OakSpeech:enter()
  -- MUSIC_ROUTES2 plays under the whole speech (oak_speech.asm:43-48)
  Music.play(self.game.data, self.cfg.music or "Music_Routes2")
  self.answers = {}
  self.steps = self:buildSteps()
  if Runtime.wants("intro.oak_speech.started") then
    Runtime.emit("intro.oak_speech.started", { speech = self, steps = self.steps })
  end
  self:advance()
end

function OakSpeech:say(key, next)
  self.game.stack:push(TextBox.new(self.game, textOr(self.game, key), next))
end

function OakSpeech:sayText(text, next, opts)
  self.game.stack:push(TextBox.new(self.game, text, next, opts))
end

function OakSpeech:stepText(step)
  if step.text then return step.text end
  if step.textKey then return textOr(self.game, step.textKey) end
  return ""
end

function OakSpeech:applyPic(step)
  if step.pic == nil then return end
  local img, flip, trueColor = OakSpeech.resolvePic(self.game, step.pic, self)
  if img then
    self.pic = img
    self.picFlip = flip or false
    self.picTrueColor = trueColor or false
  elseif step.pic == "player" or (type(step.pic) == "table" and step.pic.type == "player") then
    -- mirror the old fallback: player pic missing → oak
    self.pic = self.playerPic or self.oakPic
    self.picFlip = false
    self.picTrueColor = self.pic == self.playerPic and self.playerTrueColor
                        or false
  end
end

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

function OakSpeech:afterReveal(step, fn)
  if step.reveal then
    self:revealPic(step.reveal, fn)
  else
    fn()
  end
end

function OakSpeech:runCry(step)
  local cry = step.cry
  if not cry then return end
  if cry == true then
    if type(step.pic) == "string" and step.pic ~= "oak"
        and step.pic ~= "rival" and step.pic ~= "player" then
      cry = step.pic
    elseif type(step.pic) == "table" and step.pic.type == "pokemon" then
      cry = step.pic.id
    else
      return
    end
  end
  Sound.playCry(self.game.data, cry)
end

function OakSpeech:runStep(step)
  local kind = step.kind or "say"
  if kind == "say" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      if step.stay or step.fadeOut then
        local box = TextBox.new(self.game, self:stepText(step), nil,
          { stay = { prompt = true, onShown = function()
            if step.fadeOut then
              -- GBFadeOutToWhite / ClearScreen (oak_speech.asm:93-94)
              self.bgpFade = true
              self.game.stack:push(require("src.render.Transition")
                .whiteOut(self.game, function()
                  self.bgpFade = nil
                  self:closeHoldBox()
                  self:advance()
                end))
            else
              self:advance()
            end
          end } })
        self.holdBox = box
        self.game.stack:push(box)
      else
        self:sayText(self:stepText(step), function() self:advance() end)
      end
    end)
  elseif kind == "demo" then
    -- NIDORINO show-off: mirrored front sprite + wipe + cry + text 2A
    self.pic = self.demoPic
    self.picFlip = true
    self.picTrueColor = self.demoTrueColor
    self:revealPic("wipe", function()
      Sound.playCry(self.game.data, self.demoSpecies)
      self:say("_OakSpeechText2A", function() self:advance() end)
    end)
  elseif kind == "name" then
    local who = step.who or "player"
    local presets = step.presets
      or namePresets(self.game, step.presetsWho or who,
                     step.presetsFallback or { "RED" })
    local function openNaming()
      require("src.ui.Screens").push(self.game, "NamingScreen", {
        title = step.title or (who == "rival" and Strings("RIVAL's NAME?")
                                              or Strings("YOUR NAME?")),
        presets = presets,
        introBox = true,
        maxLen = step.maxLen or self.nameLen,
        onDone = function(name, custom)
          if who == "rival" then
            self.game.save.player.rival = name
          else
            self.game.save.player.name = name
          end
          self:recordAnswer(step, 1, name, name)
          -- YourNameIsText / HisNameIsText print into the box this one
          -- held (oak_speech2.asm:26-28, :59-61)
          self:closeHoldBox()
          if custom then
            -- .customName: ClearScreen / Delay3 / pic recentered, no
            -- slide-back (oak_speech2.asm:21-25)
            self.picSlide = 0
            self:advance()
          else
            -- OakSpeechSlidePicLeft's 13-frame pre-slide beat
            -- (oak_speech2.asm:69-78)
            self:slidePic(-1, function() self:advance() end, 13)
          end
        end,
      })
    end
    self:slidePic(1, openNaming)
  elseif kind == "choice" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      local function openMenu()
        local Menu = require("src.ui.Menu")
        local items = {}
        for i, label in ipairs(step.choices or {}) do
          items[i] = {
            label = label,
            onSelect = function()
              local value = label
              if step.values and step.values[i] ~= nil then
                value = step.values[i]
              end
              self:recordAnswer(step, i, label, value)
              self:advance()
            end,
          }
        end
        self.game.stack:push(Menu.new(self.game, items, {
          cancelable = step.cancelable == true,
          tx = step.tx or 4,
          ty = step.ty or 0,
          tw = step.tw or 12,
          th = step.th,
        }))
      end
      local text = self:stepText(step)
      if text ~= "" then
        self:sayText(text, openMenu)
      else
        openMenu()
      end
    end)
  elseif kind == "yesno" then
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      self:sayText(self:stepText(step), nil, {
        defaultNo = step.defaultNo,
        choice = function(yes)
          local label = yes and "YES" or "NO"
          local value = yes
          if step.values then
            if yes then
              value = step.values[1]
            else
              value = step.values[2]
            end
          end
          self:recordAnswer(step, yes and 1 or 2, label, value)
          self:advance()
        end,
      })
    end)
  elseif kind == "pic" then
    -- show a sprite with an optional reveal, no text
    self:applyPic(step)
    self:afterReveal(step, function()
      self:runCry(step)
      self:advance()
    end)
  elseif kind == "shrink" then
    Sound.play(self.game.data, "Shrink")
    -- prefer an explicit shrink text key; fall back to the legend beat
    local key = step.textKey or "_OakSpeechText3"
    self.shrinkText = self:lastPageLines(key)
    self.shrink = { frame = 0 }
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

-- the last two visible lines of a text's final page, pre-encoded
function OakSpeech:lastPageLines(key)
  local ok, lines = pcall(function()
    local text = TextBox.substitute(self.game, textOr(self.game, key))
    local pages = TextBox.paginate(text)
    local page = pages[#pages]
    local out = {}
    for i = math.max(1, #page - 1), #page do
      out[#out + 1] = Font.encode(page[i])
    end
    return out
  end)
  return ok and lines or nil
end

-- Reveal the current pic over `dur` frames, then run `next`.  Ticked from
-- update() while OakSpeech is the top state (before the beat's text box is
-- pushed), so the fade/wipe plays out ahead of the text like the ROM.
function OakSpeech:revealPic(kind, next)
  local tab = (kind == "fade" and INTRO_FADE_BGP)
              or (kind == "fade_white_in" and WHITE_IN_BGP) or nil
  local step = (kind == "fade") and INTRO_FADE_STEP or WHITE_FADE_STEP
  self.picReveal = {
    kind = kind,
    t = 0,
    bgp = tab,
    step = step,
    dur = tab and (#tab * step) or WIPE_FRAMES,
    next = next,
  }
end

-- engine/movie/oak_speech/oak_speech.asm:195-198
function OakSpeech.revealBgp(r)
  if not (r and r.bgp) then return nil end
  local i = math.floor((math.max(1, r.t) - 1) / r.step) + 1
  return r.bgp[math.min(#r.bgp, i)]
end

-- ..(engine/movie/oak_speech/oak_speech2.asm ln 67)
function OakSpeech:slidePic(dir, onDone, delay)
  self.picSlide = (dir > 0 and 0 or SLIDE_TILES * 8)
  self.game.stack:push(setmetatable({
    game = self.game, speech = self, dir = dir, t = 0, onDone = onDone,
    delay = delay,
  }, PicSlide))
end

-- IntroducePlayerText's text_end box (oak_speech.asm:90) is ours to close
function OakSpeech:closeHoldBox()
  local box = self.holdBox
  self.holdBox = nil
  if box and self.game.stack:top() == box then self.game.stack:pop() end
end

function OakSpeech:advance()
  self.step = self.step + 1
  -- picFlip belongs to the pic, not to the step: OakSpeechText2 prints 2A
  -- and 2B over one flipped NIDORINO with no redraw between them
  -- (oak_speech.asm:80-83), so a pic-less step must not un-mirror what is
  -- still on screen; only applyPic and the demo step may change it (#397)
  local steps = self.steps
  if not steps then
    -- enter() builds steps; keep a path for callers that advance early
    steps = self:buildSteps()
    self.steps = steps
  end
  local step = steps[self.step]
  if step then
    if Runtime.wants("intro.oak_speech.step") then
      Runtime.emit("intro.oak_speech.step", {
        speech = self, step = step, index = self.step,
      })
    end
    self:runStep(step)
  else
    self:finish()
  end
end

function OakSpeech:finish()
  if Runtime.wants("intro.oak_speech.finished") then
    Runtime.emit("intro.oak_speech.finished", {
      speech = self, answers = self.answers,
    })
  end
  -- the map theme starts with the overworld beneath (the original's
  -- special warp into Pallet Town)
  local ow = self.game.overworld
  local mapId = (ow and ow.map and ow.map.id)
                or (self.game.save.player and self.game.save.player.map)
  if mapId then Music.playMap(self.game.data, mapId) end
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- Shrink timeline (oak_speech.asm .next):
--   frames  1-4   RedPicFront still up      (ld c, 4 / DelayFrames)
--   frames  5-8   ShrinkPic1                (ld c, 4 / DelayFrames)
--   frames  9-28  ShrinkPic2, music fades   (wAudioFadeOutControl; ld c, 20)
--   frames 29-78  pic area cleared, walking sprite at the standard
--                 player screen spot        (ResetPlayerSpriteData /
--                 ClearScreenArea / wUpdateSpritesEnabled; ld c, 50)
--   frames 79-102 GBFadeOutToWhite          (3 palettes x 8 frames)
function OakSpeech:update(dt)
  local r = self.picReveal
  if r then
    r.t = r.t + 1
    if r.t >= r.dur then
      self.picReveal = nil
      if r.next then r.next() end
    end
    return
  end
  if not self.shrink then return end
  local s = self.shrink
  s.frame = s.frame + 1
  if s.frame == 5 then
    self.pic = self.shrinkPic1 or self.pic
    self.picTrueColor = false
  elseif s.frame == 9 then
    self.pic = self.shrinkPic2 or self.pic
    self.picTrueColor = false
    -- wAudioFadeOutControl = 10: the music ramps to silence over ~70
    -- frames (7 levels x 10), reaching 0 just as the fade-to-white
    -- begins at frame 79, instead of a hard cut (oak_speech.asm:145-149,
    -- home/fade_audio.asm)
    Music.fadeOut(10)
  elseif s.frame == 29 then
    self.pic = nil
    self.picTrueColor = false
    self.walkVisible = true
  elseif s.frame >= 79 and s.frame <= 102 then
    self.fadeLevel = math.floor((s.frame - 79) / 8) + 1
  elseif s.frame > 102 then
    -- clear before finish(): a finished-listener that pushes a state gets
    -- ITS state popped in the speech's place, and a live shrink would call
    -- finish() again next frame, re-firing the event every frame (#308)
    self.shrink = nil
    self:finish()
  end
end

function OakSpeech:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  -- home/fade.asm:58
  local revealBgp = OakSpeech.revealBgp(self.picReveal)
  if revealBgp then
    require("src.render.PaletteFX").setShadeMap(
      require("src.render.Transition").shadeMapFor(revealBgp))
  end
  if self.pic then
    -- IntroDisplayPicCenteredOrUpperRight centered: the 7x7-tile pic
    -- area sits at hlcoord 6,4 = (48,32); smaller mon pics pad inside
    -- it like the sprite buffer does ((8 - w) >> 1) tiles across,
    -- bottom-aligned
    local w, h = self.pic:getDimensions()
    local x = 48 + math.floor((8 - w / 8) / 2) * 8 + (self.picSlide or 0)
    local y = 32 + (7 - h / 8) * 8
    local reveal = self.picReveal
    local off = 0
    if reveal and reveal.kind == "wipe" then
      -- MovePicLeft: the pic slides in from the right edge to its spot
      off = math.floor((160 - x) * (1 - math.min(1, reveal.t / reveal.dur)))
    end
    if self.picFlip then
      -- LoadFlippedFrontSpriteByMonIndex mirrors the front sprite
      -- horizontally (wSpriteFlipped): draw with a negative x scale
      love.graphics.draw(self.pic, x + off + w, y, 0, -1, 1)
    else
      love.graphics.draw(self.pic, x + off, y)
    end
    if self.picTrueColor and not revealBgp and not self.bgpFade then
      require("src.render.PaletteFX").markTrueColor(x + off, y, w, h)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.walkVisible and self.walkSheet then
    -- ResetPlayerSpriteData: Y screen pos $3c, X screen pos $40
    self.walkQuad = self.walkQuad
      or love.graphics.newQuad(0, 0, 16, 16, self.walkSheet:getDimensions())
    love.graphics.draw(self.walkSheet, self.walkQuad, 64, 60)
  end
  if self.shrinkText then
    -- This is a REPLICA of the dialogue box that just closed, redrawn at
    -- TextBox's own rect (BOX_TX..BOX_TH = 0,12,20,6) so the last page holds
    -- while the pic shrinks.  The real box rides the bottom anchor, so this
    -- one has to as well -- otherwise the text visibly jumps up a letterbox
    -- on the frame the real box is swapped for this copy.
    local r = self.game and self.game.renderer
    if r and r.setUIAnchor then
      r:setUIAnchor(0, 12 * 8, 20 * 8, 6 * 8, "bottom")
    end
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    for i, line in ipairs(self.shrinkText) do
      local y = (12 + 2 * i) * 8
      for j, code in ipairs(line) do
        Font.drawCode(code, 8 + (j - 1) * 8, y)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.fadeLevel then
    love.graphics.setColor(1, 1, 1, self.fadeLevel / 3)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return OakSpeech

-- The Gen 2 battle screen.
--
-- All logic lives in src/battle/gen2/Battle.lua; this only draws it and feeds
-- it actions.  That split is deliberate: the engine emits an event queue, so a
-- test can assert a whole battle without a window and this file stays about
-- layout and pacing.
--
-- Layout follows the cart (engine/battle/core.asm's HUD placement): the enemy's
-- name/level and HP bar top-left with its pic top-right, the player's pic
-- bottom-left with its HUD bottom-right, and the message box across the bottom
-- two rows.  FIGHT/PACK/POKéMON/RUN sit in that box when it is the player's
-- turn.

local AnimRunner = require("src.battle.gen2.AnimRunner")
local Assets = require("src.render.Assets")
local Battle = require("src.battle.gen2.Battle")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
local BattleHud = require("src.ui.gen2.BattleHud")
local BattleMusic = require("src.battle.gen2.BattleMusic")
local BerryJuice = require("src.battle.gen2.BerryJuice")
local Boxes = require("src.core.gen2.Boxes")
local BugContest = require("src.core.gen2.BugContest")
local CatchTutorial = require("src.core.gen2.CatchTutorial")
local Catching = require("src.battle.gen2.Catching")
local Chrome = require("src.ui.gen2.Chrome")
local Evolution = require("src.core.gen2.Evolution")
local GbcPalette = require("src.render.GbcPalette")
local Font = require("src.render.Font")
local HpBar = require("src.battle.gen2.HpBar")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Mon = require("src.battle.gen2.Mon")
local Palettes = require("src.world.gen2.Palettes")
local Pokerus = require("src.core.gen2.Pokerus")
local Prize = require("src.battle.gen2.Prize")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
-- Only for playerPic: the player.sprite raiser both generations share.
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")
-- Only for TextBox.substitute: the {PLAYER} / {RIVAL} markers a map text
-- carries into the battle box (PrintWinLossText, home/trainers.asm:230).
local TextBox = require("src.render.TextBox")
local Unown = require("src.core.gen2.Unown")

local BattleState = {}
BattleState.__index = BattleState
BattleState.isOpaque = true

function BattleState:moveGridNavigation()
  if not Runtime.wantsHook("battle.move_grid_navigation") then return false end
  return Runtime.call("battle.move_grid_navigation", function() return false end,
                      self) == true
end

-- Armed while a battle line waits for PromptButton (home/text.asm).  Any
-- positive value means "hold until A/B"; the cart never times these out, so
-- the victory jingle can keep looping through the post-win prompts.
local MESSAGE_FRAMES = 48

-- engine/battle/effect_commands.asm:6661
local MOVE_DELAY_FRAMES = 40

-- home/hm_moves.asm:17-25 IsHMMove's .HMMoves.
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
  WATERFALL = true, WHIRLPOOL = true,
}

-- CheckReceivedDex's ENGINE_POKEDEX (home/flag.asm:97-102), read the way
-- StartMenu:availability reads it out of save.engineFlags.
local ENGINE_POKEDEX = 11

-- The message box's own two rows.  PrintTextboxText plants the cursor at
-- (TEXTBOX_INNERX, TEXTBOX_INNERY) = tile (1,14) (home/text.asm:143), and
-- LineChar does NOT step one row: it reloads the cursor at TEXTBOX_INNERY + 2
-- (home/text.asm:397), so a two-line battle string sits on rows 14 and 16 with
-- row 15 left blank.  Paragraph's ClearBox wipes exactly rows 14-16
-- (home/text.asm:411), which is why there is no third row to spill onto.
local TEXT_INNER_X = 1
local TEXT_INNER_Y = 14
local TEXT_WIDTH = 18
local TEXT_ROWS = 2
local TEXT_ROW_STEP = 2

-- SlideBattlePicOut (engine/battle/core.asm:2882) is called with a = 8: eight
-- one-tile steps with `ld c, 2 / call DelayFrames` between them, so the enemy
-- trainer's pic clears the box in 16 frames.
local TRAINER_SLIDE_STEPS = 8
local TRAINER_SLIDE_FRAMES_PER_STEP = 2
local TRAINER_SLIDE_FRAMES = TRAINER_SLIDE_STEPS * TRAINER_SLIDE_FRAMES_PER_STEP

-- BattleWinSlideInEnemyTrainerFrontpic (engine/battle/core.asm:6279-6318) and
-- WinTrainerBattle's DelayFrames 40 (:2311)
local WIN_SLIDE_STEPS = 6
local WIN_SLIDE_FRAMES_PER_STEP = 4
local WIN_SLIDE_FRAMES = WIN_SLIDE_STEPS * WIN_SLIDE_FRAMES_PER_STEP
local WIN_SLIDE_REST_TILES = 2
local WIN_SLIDE_DELAY_FRAMES = 40

local function winSlideTiles(frames)
  local step = math.min(WIN_SLIDE_STEPS,
    math.floor(frames / WIN_SLIDE_FRAMES_PER_STEP) + 1)
  return WIN_SLIDE_STEPS + WIN_SLIDE_REST_TILES - step
end

-- MonFaintedAnimation (engine/battle/core.asm), which PlayerMonFaintedAnimation
-- and EnemyMonFaintedAnimation both fall into with the fainted side's pic
-- corner: the pic's tilemap rows are copied DOWN one row per step and the row
-- it vacates is blanked, so what is left standing shrinks from the top while
-- the feet stay on the ground line -- the mon sinks out of the field.  The step
-- is the same `ld c, 2 / call DelayFrames` SlideBattlePicOut uses, and the loop
-- runs the pic box's own height (7 rows for the enemy's 7x7 box, 6 for the
-- player's 6x6), so the pic is gone when it ends.
local FAINT_SLIDE_FRAMES_PER_ROW = 2

-- BattleText_TheresNoWillToBattle / BattleText_AnEGGCantBattle, the two lines
-- CheckIfCurPartyMonIsFitToFight prints before it returns zero
-- (engine/battle/core.asm:3439-3466, data/text/battle.asm:241-249).
local TEXT_NO_WILL_TO_FIGHT = "There's no will to battle!"
local TEXT_EGG_CANT_BATTLE = "An EGG can't battle!"
-- data/text/battle.asm:207
local TEXT_USE_NEXT_MON = "Use next POKéMON?"

-- BattleText_TheMoveIsDisabled / BattleText_TheresNoPPLeftForThisMove
-- (data/text/battle.asm:315-322).
local TEXT_NO_PP_LEFT = "There's no PP left for this move!"
local TEXT_MOVE_DISABLED = "The move is DISABLED!"

-- _MoveAskForgetText, _MoveCantForgetHMText and _StopLearningMoveText
-- (data/text/common_3.asm:124-134).
local TEXT_ASK_FORGET_SLOT = Strings.source("Which move should\nbe forgotten?")
local TEXT_CANT_FORGET_HM = Strings.source("HM moves can't be\nforgotten now.")
local TEXT_STOP_LEARNING = Strings.source("Stop learning\n%s?")

-- BattleText_EnemyIsAboutToUseWillPlayerChangeMon (data/text/battle.asm:222-231).
local TEXT_ENEMY_ABOUT_TO_USE = Strings.source(
  "%s\nis about to use\v%s.\fWill %s\nchange POKéMON?")

-- _AskForgetMoveText, all three paragraphs (data/text/common_3.asm:141-165).
local TEXT_ASK_FORGET_MOVE = Strings.source(
  "%s is\ntrying to learn\v%s.\fBut %s\ncan't learn more\vthan four moves."
  .. "\fDelete an older\nmove to make room\vfor %s?")

-- engine/battle/menu.asm BattleMenuHeader: a 2x2 grid at menu_coords 8, 12,
-- 19, 17 with 6 tiles of column spacing, filled row-major, so the order on
-- screen is FIGHT / PkMn on top and PACK / RUN below -- not the four-in-a-row
-- Gen 1 uses.  The second label is the two-glyph <PK><MN> ligature (charmap
-- $e1/$e2), which is what makes it fit a six-tile column.
local MENU = { "FIGHT", "<PK><MN>", "PACK", "RUN" }
local MENU_ACTION = { FIGHT = "fight", ["<PK><MN>"] = "party",
  PACK = "item", RUN = "run" }
local MENU_BOX_X = 8
local MENU_COL_SPACING = 6

-- ContestBattleMenuHeader is the same 2x2 grid moved out to menu_coords 2, 12
-- with 12 tiles of column spacing, because its third label is "PARKBALL×" and
-- the count PrintNum writes after it (two digits, leading zeros) at (13,16).
local CONTEST_MENU_BOX_X = 2
local CONTEST_MENU_COL_SPACING = 12

-- PrintMoveType prints the type table's own names; only these two differ from
-- the constant (data/types/names.asm).
local TYPE_NAMES = SummaryMenu.TYPE_NAMES
-- charmap.asm's quantity glyph, spelled the way MartMenu spells it.
local CONTEST_BALL_LABEL = "PARKBALL\xc3\x97"

-- data/items/heal_status.asm StatusHealingActions: the four rows whose status
-- mask is %11111111.  HealStatus's `.not_full_heal` arm is what makes exactly
-- these also clear SUBSTATUS_CONFUSED, and IsItemUsedOnConfusedMon what lets
-- them be spent on a mon whose only complaint IS the confusion.
local FULL_MASK_HEALERS = {
  FULL_HEAL = true, FULL_RESTORE = true, HEAL_POWDER = true,
  MIRACLEBERRY = true,
}

-- Collapses runs of spaces and tabs so a text assembled out of several pieces
-- prints as one flowing line.  A "\n" is deliberately NOT touched: it is the
-- cart's own `line` control byte and Chrome.wrap honours it as a hard break, so
-- flattening it here would throw away a break the cart authored (the used-move
-- line, data/text/common_2.asm:339).
local function oneLine(text)
  return (tostring(text or ""):gsub("[ \t]+", " "))
end

-- `para` and `cont` both PromptButton before they redraw, and `cont` scrolls
-- twice so the new page opens on the old page's last line (home/text.asm:403).
local PAGE, SCROLL, LINE = "\f", "\v", "\n"
local SEPARATORS = "([^" .. LINE .. PAGE .. SCROLL .. "]*)([" ..
  LINE .. PAGE .. SCROLL .. "])"
local function paginate(text)
  local pages, rows = {}, {}
  local function flush(scroll)
    if #rows > 0 then pages[#pages + 1] = table.concat(rows, LINE) end
    rows = scroll and { rows[#rows] or "" } or {}
  end
  for chunk, sep in (tostring(text or "") .. PAGE):gmatch(SEPARATORS) do
    rows[#rows + 1] = chunk
    if sep == PAGE then flush(false)
    elseif sep == SCROLL then flush(true) end
  end
  if #pages == 0 then pages[1] = tostring(text or "") end
  return pages
end

function BattleState:wantsFillScale() return true end
function BattleState:drawsWidescreen() return true end

function BattleState:bottomUIVisible()
  if not Runtime.wantsHook("battle.bottom_ui_visible") then return true end
  return Runtime.call("battle.bottom_ui_visible", function() return true end,
                      self) ~= false
end

function BattleState:statusHUDVisible()
  if not Runtime.wantsHook("battle.status_hud_visible") then return true end
  return Runtime.call("battle.status_hud_visible", function() return true end,
                      self) ~= false
end

-- Class frontpic for the battle intro.  A trainers-registry `pic` wins over
-- the extracted menu_gfx sheet; `trueColor` skips the GBC 4-shade remap.
-- Returns path, trueColor.
function BattleState.trainerArt(data, classId)
  if not classId then return nil, false end
  local classes = data and data.gen2Trainers and data.gen2Trainers.classes
  local classDef = classes and classes[classId]
  local hud = data and data.gen2MenuGfx and data.gen2MenuGfx.battleHud
  local path = (classDef and classDef.pic)
    or (hud and hud.trainerPics and hud.trainerPics[classId])
  return path, (classDef and classDef.trueColor) and true or false
end

-- opts: battle (a Battle), onDone(outcome), save
function BattleState.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BattleState)
  self.game = game
  self.save = opts.save or (game and game.save)
  local data = (game and game.data) or {}
  self.palettes = data.gen2Palettes
  self.pokemon = data.pokemon
  self.battle = opts.battle
  self.onDone = opts.onDone
  -- What PlayVictoryMusic needs to know about the opponent (the class the
  -- trainer belongs to); nil for a wild battle.
  self.music = opts.music
  -- BATTLETYPE_CONTEST (constants/battle_constants.asm): the park ball menu,
  -- the caught mon being HELD in wContestMon rather than added to the party,
  -- and CheckContestBattleOver's draw on the last ball.  Set only by
  -- World:tryContestEncounter.
  self.contest = opts.contest and true or nil
  -- BATTLETYPE_TUTORIAL: the DUDE's demonstration.  No mon is sent out
  -- (engine/battle/core.asm jumps straight to BattleMenu), the pack is his,
  -- the ball cannot fail and nothing it catches is kept.  Set only by
  -- World:startCatchTutorial; src/core/gen2/CatchTutorial.lua has the rest.
  self.tutorial = opts.tutorial and true or nil
  self.queue = {}
  self.message = nil
  self.messageTimer = 0
  self.phase = "intro" -- intro | menu | moves | resolving | evolving | done
  -- wEvolvableFlags (ram/wram.asm, one bit per party slot).
  -- engine/battle/core.asm sets a mon's bit the moment it levels up, right
  -- after its LearnLevelMoves run, and ExitBattle's EvolveAfterBattle sweep
  -- only looks at flagged slots.  start_battle.asm clears the array at the
  -- start of every battle, which is why this lives on the screen and not on
  -- the save.
  self.evolvable = {}
  self.menuIndex = 1
  self.moveIndex = 1
  self.picCache = {}
  -- Which side's pic box stays EMPTY until a send-out redraws it: a catch
  -- latches from stepAnim (data/moves/animations.asm:379), a faint from the slide.
  self.picHidden = { player = false, enemy = false }
  -- engine/battle/sliding_intro.asm: 72 frames of the two halves sliding in
  -- from opposite sides before the first message.
  self.slideFrame = 0
  -- The HUD draws from the cart's own tiles when the cache has them; without
  -- them (an older import) drawHpBar falls back to the plain rectangles.
  self.hud = BattleHud.new(data.gen2MenuGfx, self.palettes)
  -- The battle-animation runtime.  Both halves are optional: a cache built
  -- before the scripts were extracted simply has no `anims`, and every call
  -- site below already guards on that.
  self.anims = data.gen2BattleAnims
  self.animConstants = data.gen2Constants
  if self.anims and self.anims.scripts then
    self.animView = BattleAnimView.new(self.anims, self.palettes)
  end
  self.anim = nil

  -- The intro sequence is the cart's, in the cart's order:
  --   BattleIntroSlidingPics    both halves slide in, and the player's box
  --                             holds the TRAINER's back-pic, not a mon
  --   BattleStartMessage        "Wild X appeared!"
  --   SendOutPlayerMon          swap in the mon's backpic, play
  --                             ANIM_SEND_OUT_MON, then "Go! X!"
  -- so `showPlayerTrainer` is true for everything up to the send-out.
  --
  -- In the tutorial the send-out never comes, so the back-pic stands for the
  -- whole battle -- and GetTrainerBackpic's "Special exception for Dude" swaps
  -- ChrisBackpic for DudeBackpic to draw it.  A cache built before DudeBackpic
  -- was extracted has no `dudeBack`, and falls back to the player's own.
  self.showPlayerTrainer = true
  self.playerBackImage = nil
  self.playerBackTrueColor = false
  local hudGfx = data.gen2MenuGfx and data.gen2MenuGfx.battleHud
  local backPath = hudGfx and hudGfx.playerBack
  if self.tutorial and hudGfx and hudGfx.dudeBack then
    backPath = hudGfx.dudeBack
  end
  -- player.sprite, the same hook and payload Gen 1 raises for its own back pic
  -- (src/pokemon/Sprites.lua): the Dude's stand-in is the `demo` flag there.
  -- Both return values matter here -- a mod's trueColor answer has to survive
  -- to drawPic, or GbcPalette treats the replacement art as a grayscale 2bpp
  -- sheet and remaps it through a palette instead of leaving it alone.
  local backTrueColor
  backPath, backTrueColor = Sprites.playerPic(backPath, {
    side = "back", kind = "battle", demo = self.tutorial and true or false,
    battle = self.battle, data = data,
  })
  if backPath then
    local ok, image = pcall(Assets.image, backPath)
    if ok then
      self.playerBackImage = image
      -- Kept so battle_sprite_scales can be looked up for this pic too: it is
      -- not a species' pic, so its asset path is the only key it has.
      self.playerBackPath = backPath
      self.playerBackTrueColor = backTrueColor and true or false
    end
  end

  -- Neither HUD exists while the bands slide.  InitBattleDisplay blanks the
  -- WHOLE tilemap (.BlankBGMap) and draws only the textbox and the two pics
  -- before BattleIntroSlidingPics (engine/battle/core.asm:8554/8564), so the
  -- names, levels, bars and borders are not on screen to ride in with them.
  -- UpdateEnemyHUD runs only after BattleStartMessage returns, and then only
  -- for a WILD battle (core.asm:7815-7817); a trainer's comes up at the tail of
  -- ShowSetEnemyMonAndSendOutAnimation (core.asm:3384).  UpdatePlayerHUD runs
  -- at the tail of SendOutPlayerMon, after the send-out anim and the cry
  -- (core.asm:3838).
  self.showEnemyHud = false
  self.showPlayerHud = false

  -- BattleStart_TrainerHuds, farcalled from BattleStartMessage before the
  -- opening line (engine/battle/trainer_huds.asm:1-9, core.asm:8733).
  self.ballRows = {
    player = true,
    enemy = not (self.battle and self.battle.wild),
  }

  -- InitEnemyTrainer (engine/battle/core.asm:7848) puts the CLASS's 7x7
  -- frontpic in the enemy pic box BEFORE the intro slide, and it stays there
  -- until ResetEnemyBattleVars slides it off; only then is the mon drawn.  The
  -- pic is a cache asset, so an import made before the extractor grew that
  -- stage has none and the mon stands in for the whole intro.
  self.showEnemyTrainer = false
  self.enemyTrainerTrueColor = false
  -- The CLASS CONSTANT (BUG_CATCHER), which is what both tables this looks the
  -- pic up in are keyed by: menu_gfx's trainerPics is written out of
  -- constants.trainerClassOrder, and palettes.trainers out of the same names.
  -- Trainers.lookup's `class` field is whatever the CALLER asked with, and the
  -- overworld asks with the numeric constant an object_event's trainer struct
  -- carries (36, not "BUG_CATCHER") -- so reading `class` here found no pic and
  -- no palette for every trainer the world starts, which is all of them.
  -- `classId` is the trainers.lua key, i.e. the constant; `className` is the
  -- DISPLAY name ("BUG CATCHER", with the space) and is not a key at all.
  -- A class record's own `pic` / `trueColor` (the trainers registry) wins
  -- over the extracted sheet, so a mod can drop in full-color art.
  local enemyTrainer = self.battle and self.battle.trainer
  self.enemyTrainerClass = enemyTrainer
    and (enemyTrainer.classId or enemyTrainer.class)
  local trainerPath, trainerTrueColor =
    BattleState.trainerArt(data, self.enemyTrainerClass)
  if trainerPath then
    local ok, image = pcall(Assets.image, trainerPath)
    if ok and image then
      self.enemyTrainerImage = image
      self.enemyTrainerPath = trainerPath
      self.enemyTrainerTrueColor = trainerTrueColor and true or false
      self.showEnemyTrainer = true
    end
  end

  local enemy = self.battle and self.battle.enemy
  self:noteFirstUnown(enemy)
  self:markSeen(enemy)
  if enemy then
    if self.battle.wild then
      -- BattleCheckEnemyShininess: a shiny wild mon gets ANIM_SEND_OUT_MON's
      -- `.Shiny` arm before its cry and its line (core.asm:8705-8715).
      if enemy.shiny then self:push({ kind = "shiny-flash" }) end
      -- BattleStartMessage's `.wild` arm ends on WildPokemonAppearedText
      -- (core.asm:8730); `intro` is what defers the enemy HUD to the step after
      -- it, which is where StartBattle's `call z, UpdateEnemyHUD` sits.
      self:push({ kind = "message", intro = true, cry = enemy,
        text = "Wild " .. self:name(enemy) .. " appeared!" })
    else
      local trainerName = (self.battle.trainer and self.battle.trainer.name)
        or "Foe"
      -- WantsToBattleText (core.asm:8701), read against the trainer's own pic.
      self:push({ kind = "message",
        text = trainerName .. " wants to battle!" })
      -- ResetEnemyBattleVars' SlideBattlePicOut at the head of EnemySwitch
      -- (core.asm:3027) pushes that pic off the right edge before the mon is
      -- announced.  Nothing to slide when the cache has no trainer pic.
      if self.showEnemyTrainer then
        self:push({ kind = "trainer-slide" })
      end
      -- ShowBattleTextEnemySentOut, then ShowSetEnemyMonAndSendOutAnimation
      -- (core.asm:2978-2980, 3354): this is where the mon's frontpic first
      -- appears, where ANIM_SEND_OUT_MON plays and where the HUD comes up.
      self:push({ kind = "send", side = "enemy", mon = enemy,
        text = trainerName .. " sent out " .. self:name(enemy) .. "!" })
    end
  end
  local player = self.battle and self.battle.player
  if player then
    self:push({ kind = "sendout",
      text = "Go! " .. self:name(player) .. "!" })
  end
  -- What the HUD shows chases the real HP one tick at a time
  -- (engine/battle/anim_hp_bar.asm), re-armed by each damage/heal event as
  -- the queue consumes it.  The engine has already finished the whole turn's
  -- math by the time the first message shows, so drawing mon.hp directly
  -- would spoil every hit before its own line ran -- and leave the bars
  -- looking frozen while the messages replay.
  self.shownHp = {
    player = (player and player.hp) or 0,
    enemy = (enemy and enemy.hp) or 0,
  }
  -- Which mon each side's HUD and pic actually draw, for the same reason: the
  -- engine has already rebound battle.enemy by the time the faint line runs, so
  -- reading it straight would swap the sprite and the name a beat before
  -- "X fainted!" is even displayed.  The replacement arrives with its own
  -- `send` event, which is where the cart's send-out animation sits.
  self.shownMon = { player = player, enemy = enemy }
  -- home/battle.asm:150 UpdateBattleHuds
  self.shownStatus = {
    player = (player and player.status) or false,
    enemy = (enemy and enemy.status) or false,
  }
  -- engine/battle/trainer_huds.asm:142-151
  self.caughtMark = self:dexCaught(enemy)
  -- And the same for the two numbers AnimateExpBar walks: wBattleMonLevel is
  -- only advanced inside its level loop, right after that level's bar has
  -- crawled full (engine/battle/core.asm:7267-7274), so neither the level nor
  -- the exp fill may be read live off the mon.
  self.shownLevel = (player and player.level) or 1
  self.shownExp = player
    and self:expPixels(player, player.level, player.experience) or 0
  return self
end

-- CalcExpBar (engine/battle/core.asm:7555): the bar is 64 pixels of the span
-- between THIS level's exp and the next level's, not a share of the mon's
-- total exp.
function BattleState:expPixels(mon, level, exp)
  local growth = self:growthOf(mon)
  if not growth then return 0 end
  level = math.max(1, math.min(Mon.MAX_LEVEL, level or 1))
  local base = Mon.experienceForLevel(growth, level)
  local next_ = Mon.experienceForLevel(growth, level + 1)
  if not base or not next_ or next_ <= base then return 0 end
  local into = math.max(0, math.min(next_ - base, (exp or base) - base))
  return math.floor(into * BattleHud.EXP_LENGTH_PX / (next_ - base))
end

function BattleState:name(mon)
  if not mon then return "?" end
  return mon.nickname or mon.name or mon.species or "?"
end

-- wFirstUnownSeen: the letter of the first Unown the player ever MET, written
-- by both enemy send-out paths (`cp UNOWN / ld a, [wFirstUnownSeen] / and a /
-- jr nz / predef GetUnownLetter / ld [wFirstUnownSeen], a`,
-- engine/battle/core.asm:7894-7902 and :3251-3259) and only while it is still
-- zero.  Pokedex_LoadSelectedMonTiles copies it into wUnownLetter before
-- GetMonFrontpic (engine/pokedex/pokedex.asm:2364), so the #DEX entry shows the
-- form the player first met -- seeing order, not catching order, which is why
-- an Unown that was fled from still sets it.
function BattleState:noteFirstUnown(mon)
  local save = self.save
  if not (save and mon and mon.species == Unown.SPECIES) then return end
  if (save.firstUnownSeen or 0) ~= 0 then return end
  save.firstUnownSeen = Unown.monLetter(mon)
end

-- LoadEnemyMon's "Saw this mon" (engine/battle/core.asm:6203-6209): the seen
-- flag is stamped for every battle mode, so a trainer's mon counts too.
function BattleState:markSeen(mon)
  local save = self.save
  if not (save and mon and mon.species) then return end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[mon.species] = true
end

-- The DUDE answering a prompt.  Every re-arm in the ASM sits at the moment the
-- cart starts WAITING for a button (`.wait_input` in home/joypad.asm, BattleMenu
-- before LoadBattleMenu, TutorialPack before its own loop), so each one goes
-- here right where this screen starts waiting for the same button.
--
-- `key` makes the arm idempotent for a wait that spans many steps: the prompt
-- stream must be armed ONCE per message, not re-armed every step, or its 0x51
-- blank frames restart forever and the A never lands.  A nil key arms every
-- time it is called, which is what the one-shot menu and pack arms want.
--
-- `skipIdle` is the pacing correction, and it is a port decision rather than
-- the cart's: the menu and pack streams are consumed by loops that call
-- GetJoypad with NO frame delay (engine/menus/menu.asm `.loopRTC`, and the
-- pack's own), so their long NO_INPUT runs are loop iterations and are gone in
-- a frame or two.  This port polls once per fixed step, so replaying those runs
-- step by step would park the DUDE on the battle menu for seventeen seconds.
-- The presses and their ORDER are what the stream is for, and both survive.
function BattleState:dudeInput(stream, key, skipIdle)
  if not self.tutorial then return false end
  if key ~= nil and self.dudeArmed == key then return false end
  self.dudeArmed = key
  local game = self.game
  return CatchTutorial.rearm(game and game.autoInput, stream,
    game and game.input, skipIdle)
end

function BattleState:push(event)
  self.queue[#self.queue + 1] = event
end

function BattleState:pushAll(events)
  for _, event in ipairs(events or {}) do self:push(event) end
end

-- LearnMove returns before HandleEnemyMonFaint's send-out/prize arms
-- (engine/battle/core.asm:1959-2010).
function BattleState:pushFront(events)
  for i = #(events or {}), 1, -1 do
    table.insert(self.queue, 1, events[i])
  end
end

function BattleState:pic(mon, back)
  local def = self.pokemon and mon and self.pokemon[mon.species]
  local path = def and (back and def.spriteBack or def.spriteFront)
  -- `ld hl, wEnemyMonDVs / predef GetUnownLetter / predef GetMonFrontpic`:
  -- Unown's pic is picked by FORM, out of UnownPicPointers rather than out of
  -- its own PokemonPicPointers row.  Everything else reads one row.
  local letter
  local trueColor = (def and def.trueColor) and true or false
  if mon and mon.species == Unown.SPECIES then
    letter = Unown.monLetter(mon)
    path = Unown.formSprite(self.pokemon, letter, back) or path
  end
  -- pokemon.sprite, the same name and the same ctx keys Gen 1 resolves its
  -- battle pics through (src/pokemon/Sprites.lua:path), so one subscription
  -- reskins both games: `side` is "front"/"back", `kind` says which screen is
  -- asking, `mon` is the live battler for a per-instance skin and `trueColor`
  -- is the mod's way of saying "this art is already coloured, leave the GBC
  -- palette off it".  The seam sits HERE rather than on Sprites.path because
  -- the vanilla answer it has to be given is the one the Unown row above
  -- picked -- resolving the species row again would throw the form away.  The
  -- two extra keys are what Gen 2 genuinely carries more of: the Unown letter
  -- and the shiny flag that decides the palette.
  if path and Runtime.wantsHook("pokemon.sprite") then
    local ctx = {
      species = mon.species,
      side = back and "back" or "front",
      kind = "battle",
      mon = mon,
      trueColor = (def and def.trueColor) and true or false,
      data = (self.game and self.game.data) or nil,
      letter = letter,
      shiny = mon.shiny and true or false,
    }
    local hooked = Runtime.call("pokemon.sprite",
      function(value) return value end, path, ctx)
    if type(hooked) == "string" and hooked ~= "" then path = hooked end
    trueColor = ctx.trueColor and true or false
  end
  if not path then return nil, false end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil, trueColor, path
end

-- The battle_sprite_scales registry: record id -> { path, scale }, keyed by the
-- ASSET PATH the pic is drawn from rather than by species, which is the only
-- handle there is on the pics that are not a species' own (the player's
-- trainer back, the DUDE's, an opponent's frontpic).  Same table, same record
-- shape and same resolution order as Gen 1's BattleState.imageBattleScale /
-- resolveBattleScale: image-level first, then the species record's own
-- battleScaleFront / battleScaleBack, then the default.  The DEFAULT is where
-- the two generations genuinely differ and why this is not a call into that
-- module: Gen 1's back pics are 32x32 drawn at 2x, Gen 2's are 48x48 and fill
-- their 6x6 box at 1x, so both sides default to 1 here.
function BattleState:imageScale(path)
  local data = self.game and self.game.data
  local scales = data and data.battle_sprite_scales
  if not (scales and path) then return nil end
  for id, record in pairs(scales) do
    -- `_owners` is the registry's own bookkeeping row, not a record.
    if id ~= "_owners" and type(record) == "table" and record.path == path then
      return tonumber(record.scale)
    end
  end
  return nil
end

function BattleState:picScale(path, mon, back)
  local scale = self:imageScale(path)
  if scale then return scale end
  local def = self.pokemon and mon and self.pokemon[mon.species]
  local override = def and (back and def.battleScaleBack or def.battleScaleFront)
  return tonumber(override) or 1
end

-- Where the two pics go, straight out of engine/battle/core.asm:
--
--   enemy front: hlcoord 12, 0 with lb bc, 7, 7  -- a 7x7 tile box at (96, 0)
--   player back: hlcoord 2, 6  with lb bc, 6, 6  -- a 6x6 tile box at (16, 48)
--
-- Back pics are always 48x48 so they fill their box exactly.  Front pics vary
-- (Cyndaquil is 40x40, Onix 56x56) and are padded into the 7x7 box bottom-first,
-- which is what keeps a small mon standing on the same ground line as a big one
-- instead of floating at the top of the box.
BattleState.ENEMY_PIC_TILE_X = 12
BattleState.ENEMY_PIC_TILE_Y = 0
BattleState.ENEMY_PIC_TILES = 7
BattleState.PLAYER_PIC_TILE_X = 2
BattleState.PLAYER_PIC_TILE_Y = 6
BattleState.PLAYER_PIC_TILES = 6

-- BattleBGEffect_RunPicResizeScript draws the mon at one of six BG squares:
-- 6x6 / 4x4 / 2x2 tiles for the player and 7x7 / 5x5 / 3x3 for the enemy, in
-- that order.  Only the SIZE matters here -- the cart's tile tables are the
-- same pic sampled coarsely -- so a size index becomes a scale about the
-- box's own bottom centre.
local PIC_RESIZE_TILES = { [0] = 6, [1] = 4, [2] = 2, [3] = 7, [4] = 5, [5] = 3 }

-- SUBSTATUS_UNDERGROUND / SUBSTATUS_FLYING, which BattleCommand_Charge sets on
-- FLY and DIG only (engine/battle/effect_commands.asm:5478-5485); the port
-- carries both as the volatile `vanished` flag.
function BattleState.isVanished(mon)
  local volatiles = mon and mon.volatile
  return (volatiles and volatiles.vanished) and true or false
end

function BattleState:drawPic(mon, back)
  -- During the intro slide the player-side pic belongs to presentSlide's
  -- backpic overlay, not to the baked bands (see BattleAnimView).
  if back and self.slidingBackpic then return end
  local image, trueColor, path = self:pic(mon, back)
  -- Before SendOutPlayerMon the player's box holds ChrisBackpic instead, in
  -- the same 6x6 box at hlcoord 2, 6 that the mon's backpic uses.
  local trainerBack = back and self.showPlayerTrainer and self.playerBackImage
  if trainerBack then
    image, path = trainerBack, self.playerBackPath
    trueColor = self.playerBackTrueColor
  end
  -- And the enemy's box holds the trainer's own frontpic until EnemySwitch
  -- slides it out (InitEnemyTrainer, engine/battle/core.asm:7848).
  local enemyTrainer = (not back) and self.showEnemyTrainer
    and self.enemyTrainerImage
  if enemyTrainer then
    image, path = enemyTrainer, self.enemyTrainerPath
    trueColor = self.enemyTrainerTrueColor
  end
  if not image then return end
  local side = back and "player" or "enemy"
  local anim = self:animPicState(side)
  -- The box is empty either because the animation running right now has
  -- cleared it, or because the last one ENDED with it cleared (picHidden).
  if (anim and anim.hidden) or self.picHidden[side] then return end
  -- Mid FLY / DIG the box is empty: DisappearUser ClearBoxes it
  -- (engine/battle/misc.asm:1-13), AppearUserRaiseSub puts it back on the
  -- stored attack (engine/battle/effect_commands.asm:2113-2117).
  if not (trainerBack or enemyTrainer) and BattleState.isVanished(mon)
     and not (self.vanishAnim and self.vanishAnim == self.anim) then
    return
  end
  -- GetSubstitutePic (engine/battle_anims/anim_commands.asm:905-960): the
  -- doll sits in the mon's own pic box and takes its palette.
  local doll, dollQuad
  if not (trainerBack or enemyTrainer) then
    local over = anim and anim.pic
    local up
    if over ~= nil then
      up = over == "substitute"
    else
      up = mon and mon.volatile and (mon.volatile.substitute or 0) > 0
    end
    if up then doll, dollQuad = self:substituteDoll(back) end
  end
  local G = love.graphics
  local w, h = image:getDimensions()
  local px, py
  local boxTiles
  if back then
    -- pokegold engine/battle/core.asm:8569: 6x6 box, bottom-aligned/centred
    local box = BattleState.PLAYER_PIC_TILES * 8
    px = BattleState.PLAYER_PIC_TILE_X * 8 + math.floor((box - w) / 2)
    py = BattleState.PLAYER_PIC_TILE_Y * 8 + (box - h)
    boxTiles = BattleState.PLAYER_PIC_TILES
  else
    -- PadFrontpic pads a short pic and never a long one
    -- (engine/gfx/load_pics.asm:342-386), so an oversized mod pic pins to the
    -- box's own corner at hlcoord 12, 0 rather than to a negative offset.
    local box = BattleState.ENEMY_PIC_TILES * 8
    px = BattleState.ENEMY_PIC_TILE_X * 8 + math.max(0, math.floor((box - w) / 2))
    py = BattleState.ENEMY_PIC_TILE_Y * 8 + math.max(0, box - h)
    boxTiles = BattleState.ENEMY_PIC_TILES
  end
  -- One tile per two frames to the right, SlideBattlePicOut's own step.
  if enemyTrainer and self.trainerSlide then
    px = px + math.floor(self.trainerSlide / TRAINER_SLIDE_FRAMES_PER_STEP) * 8
  elseif enemyTrainer and self.winSlide then
    px = px + winSlideTiles(self.winSlide) * 8
  end
  -- The pic's own scale (battle_sprite_scales, then the species record, then
  -- 1x) composed with whatever square BattleBGEffect_RunPicResizeScript has
  -- the mon drawn at this frame.
  local scale = self:picScale(path, mon, back)
  if anim then
    if not self.liftedPass then px = px + (anim.slide or 0) end
    local resized = anim.size and PIC_RESIZE_TILES[anim.size]
    if resized then scale = scale * (resized / boxTiles) end
  end
  if scale ~= 1 then
    -- Centred in the same box and standing on the same ground line at every
    -- scale: the smaller resize squares, and a mod scale, both compensate the
    -- same way.
    px = px + math.floor(w * (1 - scale) / 2)
    py = py + math.floor(h * (1 - scale))
  end
  if doll then
    px = (back and 32 or 112) + ((anim and anim.slide) or 0)
    py = back and 80 or 40
  end
  G.setColor(1, 1, 1, 1)
  -- No mon on this side at all in the catching tutorial, where the box holds
  -- the DUDE's back-pic and nothing else for the whole battle.
  local colors = self.palettes and mon
    and Palettes.monColors(self.palettes, mon.species, mon.shiny)
  if trainerBack then
    -- PAL_BATTLE_OB_PLAYER: the player's own colours, which are row 0 of
    -- TrainerPalettes (Chris shares Cal's).
    colors = Palettes.trainerColors(self.palettes, "PLAYER") or colors
  elseif enemyTrainer then
    -- The opponent's class row out of the same TrainerPalettes table.
    colors = Palettes.trainerColors(self.palettes, self.enemyTrainerClass)
      or colors
  end
  if anim and anim.shade then
    colors = BattleAnimView.shadeColors(colors, anim.shade)
  end
  -- MonFaintedAnimation, mid-slide: the rows that have walked past the bottom
  -- of the pic box are not on the tilemap any more, so the pic is CROPPED to
  -- what is still inside the box rather than drawn over the HUD below it.
  local sunk = self:faintSink(side)
  local function body()
    if doll then
      G.draw(doll, dollQuad, px, py)
      return
    end
    if sunk > 0 then
      local visible = h - math.floor(sunk / scale)
      if visible <= 0 then return end
      G.draw(image, self:cropQuad(image, visible), px, py + sunk, 0,
        scale, scale)
      return
    end
    G.draw(image, px, py, 0, scale, scale)
  end
  -- A mod-supplied pic that says it is already coloured is drawn as it is:
  -- pokemon.sprite's ctx.trueColor, the same flag Gen 1's Sprites.path hands
  -- back to its own draw site.
  local function paint()
    if colors and not (trueColor and GbcPalette.mode == "gbc")
       and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end
  end
  local lifted = anim and anim.lifted
  if not lifted then
    paint()
    return
  end
  -- engine/battle_anims/bg_effects.asm:448-465: the ClearBoxed band is off the BG.
  local bandY = (back and BattleState.PLAYER_PIC_TILE_Y
    or BattleState.ENEMY_PIC_TILE_Y) * 8 + lifted[1] * 8
  local bandH = lifted[2] * 8
  local psx, psy, psw, psh
  if G.getScissor then psx, psy, psw, psh = G.getScissor() end
  if self.liftedPass then
    G.setScissor(0, bandY, 160, bandH)
    paint()
  else
    if bandY > 0 then
      G.setScissor(0, 0, 160, bandY)
      paint()
    end
    local below = 144 - bandY - bandH
    if below > 0 then
      G.setScissor(0, bandY + bandH, 160, below)
      paint()
    end
  end
  if psx then G.setScissor(psx, psy, psw, psh) else G.setScissor() end
end

-- MonsterSpriteGFX (gfx/sprites.asm:82): the facing-DOWN 16x16 frame for the
-- enemy's frontpic, facing-UP for the player's backpic.
function BattleState:substituteDoll(back)
  if self.subDoll == nil then
    local ok, image = pcall(Assets.image, "assets/generated/sprites/monster.png")
    if ok and image then
      local w, h = image:getDimensions()
      self.subDoll = { image = image,
        down = love.graphics.newQuad(0, 0, 16, 16, w, h),
        up = love.graphics.newQuad(0, 16, 16, 16, w, h) }
    else
      self.subDoll = false
    end
  end
  if not self.subDoll then return nil end
  return self.subDoll.image, back and self.subDoll.up or self.subDoll.down
end

-- MonsterSpriteGFX (gfx/sprites.asm:82): the facing-DOWN 16x16 frame for the
-- enemy's frontpic, facing-UP for the player's backpic.
function BattleState:substituteDoll(back)
  if self.subDoll == nil then
    local ok, image = pcall(Assets.image, "assets/generated/sprites/monster.png")
    if ok and image then
      local w, h = image:getDimensions()
      self.subDoll = { image = image,
        down = love.graphics.newQuad(0, 0, 16, 16, w, h),
        up = love.graphics.newQuad(0, 16, 16, 16, w, h) }
    else
      self.subDoll = false
    end
  end
  if not self.subDoll then return nil end
  return self.subDoll.image, back and self.subDoll.up or self.subDoll.down
end

-- The top `visible` rows of a pic, for the faint slide.  One quad, re-aimed,
-- the way BattleAnimView keeps one blit quad rather than a new one per frame.
function BattleState:cropQuad(image, visible)
  local w, h = image:getDimensions()
  if not self.picQuad then
    self.picQuad = love.graphics.newQuad(0, 0, w, visible, w, h)
  else
    self.picQuad:setViewport(0, 0, w, visible, w, h)
  end
  return self.picQuad
end

-- How far this side's pic has sunk, in pixels.  MonFaintedAnimation moves one
-- 8px row per FAINT_SLIDE_FRAMES_PER_ROW frames.
function BattleState:faintSink(side)
  local slide = self.faintSlide
  if not (slide and slide.side == side) then return 0 end
  return math.floor(slide.frames / FAINT_SLIDE_FRAMES_PER_ROW) * 8
end

-- The whole slide, in frames: the pic box's own height in rows.
function BattleState:faintSlideFrames(side)
  local tiles = side == "player" and BattleState.PLAYER_PIC_TILES
    or BattleState.ENEMY_PIC_TILES
  return tiles * FAINT_SLIDE_FRAMES_PER_ROW
end

-- One tick of the HP bar chase (_AnimateHPBar): under 48 max HP the bar steps
-- one hit point a frame (ShortAnim_UpdateVariables); from 48 up it moves one
-- PIXEL a frame, which is maxHp/48 hit points at a time
-- (LongAnim_UpdateVariables).  Returns true while a step was taken, so the
-- caller holds the queue the way the cart's loop holds the game.
function BattleState:stepHpAnim()
  local anim = self.hpAnim
  if not anim or not self.shownHp then return false end
  -- wCurHPAnimMaxHP is loaded from the battle struct of the mon whose bar is
  -- ON SCREEN (wEnemyMonMaxHP -> wHPBuffer1 before `predef AnimateHPBar`,
  -- engine/battle/effect_commands.asm:3399-3414), and _AnimateHPBar picks its
  -- short/long loop and its pixels off that alone (anim_hp_bar.asm:42-50,
  -- :56-82).  After a faint that mon is still the OUTGOING one: the engine has
  -- already rebound battle.enemy, but its `send` event has not been dequeued
  -- yet, so sizing the tick off battle[side] drains the dead mon's bar at the
  -- replacement's rate.
  local mon = self:activeMon(anim.side)
  local maxHp = (mon and (mon.maxHp or (mon.stats and mon.stats.hp))) or 0
  local step = 1
  if maxHp >= HpBar.LENGTH_PX then
    step = math.max(1, math.ceil(maxHp / HpBar.LENGTH_PX))
  end
  local shown = self.shownHp[anim.side] or 0
  local target = anim.to or 0
  if shown < target then
    shown = math.min(target, shown + step)
  else
    shown = math.max(target, shown - step)
  end
  self.shownHp[anim.side] = shown
  if shown == target then self.hpAnim = nil end
  return true
end

-- .PlayExpBarSound's own two halves (engine/battle/core.asm:7311-7318): the
-- looping SFX_EXP_BAR, then `ld c, 10 / call DelayFrames` before the first
-- pixel moves.  TerminateExpBarSound (home/audio.asm:497) cuts it dead at the
-- end of the segment rather than letting it ring on, and the end-of-bar hit
-- only plays where a level was actually crossed.
local SFX_EXP_BAR = "Sfx_ExpBar"
local SFX_END_OF_EXP_BAR = "Sfx_HitEndOfExpBar"
local EXP_SOUND_FRAMES = 10

-- One tick of the exp bar crawl.  AnimateExpBar walks the bar one PIXEL at a
-- time out of 64 (.LoopBarAnimation, engine/battle/core.asm:7325-7362): the
-- gap starts at three frames a pixel and drops by one after every SECOND
-- pixel, floored at one, so the bar starts slow and finishes fast.  A level
-- crossing fills the segment to 64, plays SFX_HIT_END_OF_EXP_BAR, advances the
-- level the HUD prints and restarts the bar at 0 (:7259-7285), which is why
-- the number changes as the bar tops out and not a message earlier.
--
-- Returns true while the crawl is running so the caller holds the queue the
-- way the cart's loop holds the game.
function BattleState:stepExpAnim()
  local anim = self.expAnim
  if not anim then return false end
  local mon = anim.mon
  local toLevel = (mon and mon.level) or self.shownLevel or 1
  local target = BattleHud.EXP_LENGTH_PX
  if (self.shownLevel or 1) >= toLevel then
    target = self:expPixels(mon, self.shownLevel, mon and mon.experience)
  end
  if not anim.started then
    anim.started = true
    anim.frames = 3
    anim.wait = 0
    anim.pixels = 0
    anim.delay = EXP_SOUND_FRAMES
    self:playSfx(SFX_EXP_BAR)
  end
  if anim.delay > 0 then
    anim.delay = anim.delay - 1
    return true
  end
  local shown = self.shownExp or 0
  if shown < target then
    anim.wait = anim.wait + 1
    if anim.wait < anim.frames then return true end
    anim.wait = 0
    shown = shown + 1
    self.shownExp = shown
    anim.pixels = anim.pixels + 1
    if anim.pixels % 2 == 0 then anim.frames = math.max(1, anim.frames - 1) end
    if shown < target then return true end
  end
  -- TerminateExpBarSound at the tail of every segment (:7279 and :7301).
  Sound.stop(SFX_EXP_BAR)
  if (self.shownLevel or 1) < toLevel then
    self.shownLevel = (self.shownLevel or 1) + 1
    self.shownExp = 0
    self:playSfx(SFX_END_OF_EXP_BAR)
    anim.started = false
    return true
  end
  self.expAnim = nil
  return true
end

-- The HP a side's HUD prints and fills its bar from: the chased value, not
-- the engine's, which ran a whole turn ahead.
function BattleState:hudHp(mon, side)
  local shown = self.shownHp and self.shownHp[side]
  if shown == nil then return (mon and mon.hp) or 0 end
  return shown
end

-- The bar is src/battle/gen2/HpBar.lua's: the pixel count comes from
-- ComputeHPBarPixels and the colour from GetHPPal, so this screen and the party
-- list can never disagree about when a mon is in the red.
function BattleState:drawHpBar(mon, side, tx, ty)
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
  local hp = self:hudHp(mon, side)
  if self.hud:available() then
    return self.hud:drawHpBar(hp, maxHp, tx, ty)
  end
  return HpBar.drawWithLabel(self.palettes, hp, maxHp, tx, ty, Font)
end

-- CheckCaughtMon against wPokedexCaught (home/pokedex_flags.asm:48-51).
function BattleState:dexCaught(mon)
  local caught = self.save and self.save.pokedex and self.save.pokedex.caught
  return (mon and caught and caught[mon.species]) and true or false
end

-- The status the HUD prints, one drain behind the engine the way shownHp is:
-- UpdateBattleHuds runs after the animation and its line (home/battle.asm:150).
function BattleState:hudStatus(mon, side)
  local shown = side and self.shownStatus and self.shownStatus[side]
  if shown == nil then return mon and mon.status or nil end
  return shown or nil
end

-- home/battle.asm:150, for the clears no queued event carries (a mon waking,
-- a thaw, a bag cure): the tags catch up once the queue is idle.
function BattleState:syncShownStatus()
  local shown, battle = self.shownStatus, self.battle
  if not (shown and battle) then return end
  for _, side in ipairs({ "player", "enemy" }) do
    local mon = battle[side]
    shown[side] = (mon and mon.status) or false
  end
end

-- The low-HP alarm is not an SFX id at all.  PlayDanger (audio/engine.asm:531)
-- runs every frame while DANGER_ON_F is set in wLowHealthAlarm and writes a
-- two-tone square straight to channel 1 -- DangerSoundHigh ($750) at counter 0,
-- DangerSoundLow ($6ee) at counter 16 -- while audio/engine.asm:244 keeps music
-- channel 1 quiet for as long as the flag is up.  CheckDanger
-- (engine/battle/core.asm:4393) sets and clears the flag off wPlayerHPPal ==
-- HP_RED, and StopDangerSound (core.asm:2189) zeroes it on a faint and at the
-- end of the battle.  src/core/ChipAudio.lua synthesizes that exact pair, which
-- is what Sound.startLoop("Low_Health_Alarm") reaches.
--
-- Keyed to the DISPLAYED bar, because wPlayerHPPal is what the bar animation
-- updates: the siren starts when the bar drains into the red, not a turn early.
function BattleState:lowHealthAlarmActive()
  -- wBattleLowHealthAlarm is the per-battle DISABLE latch, and CheckDanger
  -- reads it before anything else (`ld a, [wBattleLowHealthAlarm] / and a /
  -- jr nz, .done`, engine/battle/core.asm:4396-4399): once it is set the
  -- DANGER_ON_F bit StopDangerSound just cleared is left alone, so the siren
  -- cannot come back for the rest of the battle however red the bar stays.
  if self.lowHealthAlarmDisabled then return false end
  -- The healing item's exception, set by applyPartyItem: wLowHealthAlarm is
  -- zeroed before the HP moves, and CheckDanger is not asked again until
  -- UpdatePlayerHUD runs at the end of the bar climb, so nothing re-arms the
  -- siren while the bar is walking back out of the red.
  if self.healSilence then
    if self.hpAnim and self.hpAnim.side == "player" then return false end
    self.healSilence = nil
  end
  local player = self.battle and self.battle.player
  return (player and (player.hp or 0) > 0
    and HpBar.paletteFor(self:hudHp(player, "player"),
      player.maxHp or (player.stats and player.stats.hp)) == "red") and true
    or false
end

function BattleState:updateAlarm()
  local data = self.game and self.game.data
  -- Mirrors wLowHealthAlarm's DANGER_ON_F bit, under the same field name Gen 1
  -- keeps it in (src/battle/BattleState.lua).
  self.lowHealthAlarmOn = self:lowHealthAlarmActive() and data ~= nil
  -- battle.low_health_alarm: on/off toggle for the siren loop, ctx.on mirrors
  -- self.lowHealthAlarmOn -- the same name and the same ctx keys as the Gen 1
  -- site, so one subscription covers both games and a mod can reshape the
  -- toggle (mute it after a budget, swap the loop) before vanilla acts on it.
  -- `data` is added because this screen's cache lives on the game rather than
  -- on the battle the way Gen 1's does; `battle` is still the battle screen.
  if Runtime.wantsHook("battle.low_health_alarm") then
    return Runtime.call("battle.low_health_alarm", function(ctx)
      if ctx.on and ctx.data then
        Sound.startLoop(ctx.data, "Low_Health_Alarm")
      else
        Sound.stopLoop("Low_Health_Alarm")
      end
    end, { on = self.lowHealthAlarmOn, battle = self, data = data })
  end
  if self.lowHealthAlarmOn then
    -- Sound.startLoop returns early when the loop is already sounding, so this
    -- can run every step the way PlayDanger runs every frame.
    Sound.startLoop(data, "Low_Health_Alarm")
  else
    self:stopAlarm()
  end
end

-- StopDangerSound (engine/battle/core.asm:2189): the siren cannot outlive the
-- mon that raised it, nor the battle screen.
function BattleState:stopAlarm()
  Sound.stopLoop("Low_Health_Alarm")
end

--------------------------------------------------------------------------
-- Battle animations
--------------------------------------------------------------------------

-- hBattleTurn: 0 while the player is attacking.  Every object function and
-- every BG effect keys the side it acts on off this.
function BattleState:turnFor(side)
  return side == "enemy" and 1 or 0
end

-- Starts an animation script and returns true when there is one to play.
-- `key` is a pool key from battle_anims.lua's `moves` or `ids` map.
function BattleState:startAnim(key, opts)
  if not (self.anims and self.anims.scripts and key) then return false end
  if not self.anims.scripts[key] then return false end
  -- BattleAnimRunScript's own gate: `bit BATTLE_SCENE, [wOptions]` skips the
  -- move animation entirely, which is the OPTION screen's BATTLE SCENE row.
  -- The check only applies to a real move id (wFXAnimID+1 == 0); non-move
  -- ids (isMove unset here) branch straight to .not_move and always run.
  local options = self.game and self.game.options
  if options and options.battleScene == false and opts and opts.isMove then
    return false
  end
  opts = opts or {}
  local data = (self.game and self.game.data) or {}
  local audio = data.audio or {}
  self.anim = AnimRunner.new({
    data = self.anims,
    constants = self.animConstants,
    battleTurn = opts.turn or 0,
    animId = opts.animId,
    param = opts.param or 0,
    sfxOrder = audio.sfxOrder,
    ballPalette = opts.ballPalette,
    -- BGEffect_CheckFlyDigStatus reads wPlayerSubStatus3 / wEnemySubStatus3
    -- (engine/battle_anims/bg_effects.asm:2838-2851); the port keeps that bit
    -- on the mon's volatile table, not on the mon itself.
    flying = {
      player = BattleState.isVanished(self.battle and self.battle.player),
      enemy = BattleState.isVanished(self.battle and self.battle.enemy),
    },
    hooks = {
      -- anim_sound (engine/battle_anims/anim_commands.asm:1105) calls
      -- PlayStereoSFX (audio/engine.asm:2571), the ONE sfx path with no
      -- CheckSFX/wCurSFX comparison: an animation's second sound is never
      -- dropped for being outranked by its first.  BattleAnim_ThrowPokeBall's
      -- SFX_THROW_BALL then SFX_BALL_POOF is the case that goes silent if this
      -- goes through the gated Sound.play.
      sound = function(name)
        if name and audio.sfx and audio.sfx[name] then
          Sound.playStereo(data, name)
        end
      end,
      -- The cry is the battler's own, at the pitch/length the command adds;
      -- the port's Sound layer has no pitch shift, so the plain cry is what
      -- plays.  audio.cries is keyed by SPECIES (the same table every other
      -- Gen 2 screen plays through Sound.playCry), which is what makes
      -- anim_cry moves like GROWL audible at all.
      cry = function(side)
        local mon = side == "enemy" and self.battle.enemy or self.battle.player
        local species = mon and mon.species
        if species and audio.cries and audio.cries[species] then
          Sound.playCry(data, species)
        end
      end,
      -- GetPokeBallWobble, which BattleAnim_ThrowPokeBall's .Loop calls through
      -- anim_checkpokeball once per wobble.
      pokeballWobble = function() return self:pokeballWobble() end,
    },
  })
  self.anim:start(key)
  -- BattleAnimRunScript calls BattleAnimClearHud before a MOVE's script and
  -- BattleAnimRestoreHuds after; the `.not_move` path (the shared ANIM_* ids)
  -- skips both.  ClearActorHud blanks the ATTACKER's own HUD, which is what
  -- keeps a Tackle from dragging the name and HP bar along with the pic.
  self.anim.clearsHud = opts.isMove and true or false
  self.anim.hudSide = (opts.turn or 0) == 0 and "player" or "enemy"
  return true
end

-- wBattleAfterAnim target for this attacker's turn
-- (effect_commands.asm:1963-1972): player swing -> enemy shake, and reverse.
function BattleState:afterAnimFor(side)
  if side == "player" then return "ANIM_ENEMY_DAMAGE" end
  return "ANIM_PLAYER_DAMAGE"
end

function BattleState:animForMove(moveId, side, param)
  local key = self.anims and self.anims.moves and self.anims.moves[moveId]
  local started = self:startAnim(key, {
    turn = self:turnFor(side), animId = moveId, isMove = true, param = param,
  })
  if started then
    -- BattleAnimRunScript (anim_commands.asm:55-72): after the move script
    -- restores HUDs it immediately runs wBattleAfterAnim (the hit shake).
    -- Queue it so stepAnim chains without waiting on the next event.
    self.pendingAfterAnim = { name = self:afterAnimFor(side), side = side }
  end
  return started
end

-- Kick off a queued after-anim; returns true when one is now running.
function BattleState:startPendingAfterAnim()
  local pending = self.pendingAfterAnim
  if not pending then return false end
  self.pendingAfterAnim = nil
  if self:animForId(pending.name, pending.side) then
    -- dealDamage's default ANIM_x_DAMAGE is this same shake; skip it there.
    self.afterAnimPlayed = true
    return true
  end
  return false
end

-- True while BattleAnimClearHud has that side's HUD blanked.
function BattleState:hudCleared(side)
  return self.anim ~= nil and self.anim.clearsHud and self.anim.hudSide == side
end

-- `param` is wBattleAnimParam, which BattleAnim_SendOutMon branches on
-- (data/moves/animations.asm:414-417).
function BattleState:animForId(idName, side, param)
  local key = self.anims and self.anims.ids and self.anims.ids[idName]
  return self:startAnim(key, {
    turn = self:turnFor(side), animId = idName, param = param,
  })
end

-- data/moves/animations.asm:379
function BattleState:latchCaughtPic()
  local anim = self.anim
  if anim and anim.animId == "ANIM_THROW_POKE_BALL"
      and self.ballThrow and self.ballThrow.caught then
    self.picHidden.enemy = true
  end
end

-- One logic frame of a running animation.  B cuts it short, the way holding B
-- pages a text box.
function BattleState:stepAnim(input)
  if not self.anim then return end
  if input and (input:wasPressed("b") or input:wasPressed("start")) then
    -- Cut short: only the explicit latches (a caught mon) survive a skip.
    self:latchCaughtPic()
    self.anim = nil
    -- Cart still reaches the after-anim arm after a move script ends; a skip
    -- of the move should not drop the hit shake that follows it.
    if self:startPendingAfterAnim() then return end
    return self:endSendOutAnim(true)
  end
  if not self.anim:step() then
    self:latchCaughtPic()
    -- pokegold data/moves/animations.asm .Click: anim_keepsprites means
    -- the OAM outlives the script, so keep the runner for drawing too.
    if not self.anim.keepSprites then self.anim = nil end
    if self:startPendingAfterAnim() then return end
    return self:endSendOutAnim()
  end
end

-- REMOVE_MON / RETURN_MON also serve SUBSTITUTE, SKY_ATTACK, BEAT_UP and
-- BATON_PASS, so picHidden is only latched by a catch and a faint.

-- Whatever Call_PlayBattleAnim was standing in front of: a send-out's cry and
-- HUD update run the moment its animation is done, cut short or not.
function BattleState:endSendOutAnim(skipped)
  local after = self.afterSendOut
  if not after then return end
  self.afterSendOut = nil
  if after.shiny and not skipped then
    after.shiny = nil
    if self:animForId("ANIM_SEND_OUT_MON", after.side, 1) then
      self.afterSendOut = after
      return
    end
  end
  self:finishSendOut(after)
end

-- What the BG effects are doing to a battler's pic this frame.
function BattleState:animPicState(side)
  if not self.anim then return nil end
  local bg = self.anim.bg
  return {
    hidden = bg.hidden[side],
    lifted = bg.liftedRows and bg.liftedRows[side] or nil,
    size = bg.picSize[side],
    slide = bg.slide[side] or 0,
    shade = bg.monShade[side],
    pic = self.anim.picOverride[side],
  }
end

function BattleState:advanceQueue()
  local event = table.remove(self.queue, 1)
  -- StartBattle runs `call z, UpdateEnemyHUD` AFTER BattleStartMessage returns,
  -- and only for a wild battle (engine/battle/core.asm:7808-7817): the appeared
  -- line is read against an empty HUD area and the bar comes up on the step
  -- after it.  A trainer's HUD is turned on by the send-out arm below instead.
  if self.introTextShown then
    self.showEnemyHud = true
    self.introTextShown = nil
  end
  if not event then
    self:syncShownStatus()
    -- `jp PlayerSwitch`, which follows the enemy's own send-out and spends no
    -- turn (engine/battle/core.asm:2955-2963).
    if self.shiftSwitchIndex then
      local index = self.shiftSwitchIndex
      self.shiftSwitchIndex = nil
      if self.battle:shiftSwitch(index) then
        self:pushAll(self.battle:takeEvents())
        return self:advanceQueue()
      end
    end
    -- Nothing left: either the battle ended or it is the player's turn.
    if self.battle and self.battle.over then
      -- ExitBattle runs the evolution sweep BEFORE it cleans up the battle
      -- RAM, so the screens come up while the battle is still notionally on.
      return self:startEvolutions()
    end
    self.phase = "menu"
    if self.tutorial then
      -- BattleMenu's tutorial arm skips UpdateBattleHuds AND EmptyBattleTextbox,
      -- so the box keeps whatever it already said while the menu opens over it,
      -- and there is no mon to name in a prompt anyway.  The DOWN + A that
      -- picks PACK is armed here, where the cart arms it: right before
      -- LoadBattleMenu.
      self:dudeInput(CatchTutorial.MENU_STREAM, nil, true)
      return
    end
    -- `call CheckPlayerLockedIn / jr c, .skip_iteration` (engine/battle/core.asm
    -- :162-176) jumps past `call BattleMenu` ENTIRELY, not just past the move
    -- list: a mon partway through a Rollout or a Thrash is offered no menu at
    -- all, and ParsePlayerAction's .locked_in arm runs the move it is stuck on.
    -- The engine side already forces the move (Battle:forcedMove overrides
    -- whatever is submitted, and Battle:usableMoves narrows to the one), so all
    -- that is left here is not to draw a menu the cart never draws.  Deferred
    -- to update() rather than submitted from inside advanceQueue, so a turn
    -- that somehow emitted no events cannot recurse.
    if not self.tutorial and self.battle and self.battle.player
        and self.battle:lockedInMove(self.battle.player) then
      -- The message is deliberately NOT cleared: EmptyBattleTextbox lives
      -- inside BattleMenu, which this turn never calls, so the box keeps
      -- whatever the last line was.
      self.phase = "locked-in"
      return
    end
    -- BattleMenu (engine/battle/core.asm) runs EmptyBattleTextbox before
    -- LoadBattleMenu: the half of the box beside the 2x2 menu is BLANK on the
    -- cart.  Gen 2 has no "What will X do?" line, and printing one here only
    -- got it clipped mid-word by the menu box drawn over its right half.
    self.message = nil
    return
  end
  -- HandleEnemyMonFaint / HandlePlayerMonFaint run their side's
  -- MonFaintedAnimation BEFORE the faint text (engine/battle/core.asm): the pic
  -- sinks out of the field and only then does "X fainted!" go up.  The slide
  -- owns the screen the way SlideBattlePicOut does, so the event is put back at
  -- the head of the queue and re-runs for its text (and for the alarm latch and
  -- the victory jingle below it) once the pic is gone.
  if event.kind == "faint" and event.side and not event.slid
      and not self.faintSlide then
    event.slid = true
    table.insert(self.queue, 1, event)
    self.faintSlide = { side = event.side, frames = 0 }
    -- FaintEnemyPokemon opens on SFX_KINESIS, FaintYourPokemon on the fainting
    -- mon's own cry (engine/battle/core.asm:2196-2201, :2210-2212).
    if event.side == "enemy" then
      self:playSfx("Sfx_Kinesis")
    else
      self:playCry(self:activeMon("player"))
    end
    return
  end
  -- Battle:awardExperience emits one `level` event per mon that grew, which is
  -- exactly where the cart sets that slot's wEvolvableFlags bit.
  if event.kind == "level" and event.index then
    self.evolvable[event.index] = true
    -- GiveExperiencePoints' `.skip_active_mon_update` guard
    -- (engine/battle/core.asm:6999-7003): the OUT mon's shown HP snaps.
    local battle = self.battle
    local mon = battle and battle.party and battle.party[event.index]
    -- pokegold engine/battle/core.asm:7057-7069: every mon that leveled
    -- gets the stats box, not just the mon currently on the field.
    self.pendingStatsMon = mon
    -- engine/battle/core.asm:7284
    if mon and mon == battle.player then
      if self.shownHp then
        self.shownHp.player = mon.hp or 0
        if self.hpAnim and self.hpAnim.side == "player" then
          self.hpAnim = nil
        end
      end
      -- `ld [wBattleMonLevel], a` in the same guarded block (:7018-7020).
      self.shownLevel = mon.level or self.shownLevel
    end
  end
  -- EnemySwitch's shift arm asks BEFORE ClearEnemyMonBox and
  -- ShowBattleTextEnemySentOut (engine/battle/core.asm:2941-2955), so the send
  -- goes back at the head of the queue and re-runs once the prompt is answered.
  if event.kind == "send" and event.side == "enemy" and event.replacement
      and not event.offered and self:shiftOfferAllowed() then
    event.offered = true
    table.insert(self.queue, 1, event)
    return self:offerShiftSwitch(event.mon)
  end
  -- A damage or heal event re-arms the HP bar chase (AnimateHPBar runs from
  -- UpdateBattleHuds between one battle message and the next), and a send
  -- snaps that side's bar straight to the incoming mon.
  if (event.kind == "damage" or event.kind == "heal")
      and event.side and event.hp and self.shownHp
      and self.shownHp[event.side] ~= event.hp then
    self.hpAnim = { side = event.side, to = event.hp }
  elseif event.kind == "send" and event.side and event.mon and self.shownHp then
    self.shownHp[event.side] = event.hp or event.mon.hp or 0
    if self.hpAnim and self.hpAnim.side == event.side then self.hpAnim = nil end
  end
  -- And the same lag for the status tag (home/battle.asm:150); a send snaps it
  -- to the incoming mon.
  if self.shownStatus and event.side
      and (event.kind == "status"
        or (event.kind == "send" and event.mon)) then
    local shown = event.status
    if event.kind == "send" and shown == nil then shown = event.mon.status end
    self.shownStatus[event.side] = shown or false
  end
  -- AnimateExpBar (engine/battle/core.asm:7191) is called from INSIDE
  -- GiveExperiencePoints before the exp is committed (the call at :6888 sits
  -- ahead of the commit at :6889-6901), so the bar crawls from the figures
  -- the HUD is already showing up to the new ones, filling to 64 and
  -- restarting at 0 for every level crossed (:7259-7285).  The engine has
  -- written mon.experience and mon.level a whole turn earlier here, so the
  -- crawl's starting point is the chased state (shownExp / shownLevel) rather
  -- than the mon: same reason the HP bar has shownHp.
  if event.kind == "experience" and event.index then
    local battle = self.battle
    local mon = battle and battle.party and battle.party[event.index]
    -- AnimateExpBar's own two guards: only the mon that is OUT animates (the
    -- wCurBattleMon == wCurPartyMon test at :7194-7197), and nothing animates
    -- at MAX_LEVEL (:7199-7201).
    if mon and mon == battle.player
        and (self.shownLevel or 1) < Mon.MAX_LEVEL then
      self.expAnim = { mon = mon, frames = 3, wait = 0, pixels = 0 }
    end
  end
  if event.kind == "send" and event.side and event.mon then
    -- The pic and the HUD name follow the queue, so the mon that just fainted
    -- is still on screen for its own line and the replacement arrives here.
    if self.shownMon then self.shownMon[event.side] = event.mon end
    -- The second of the cart's two wFirstUnownSeen writes (core.asm:3251).
    if event.side == "enemy" then
      self:noteFirstUnown(event.mon)
      self:markSeen(event.mon)
      -- engine/battle/trainer_huds.asm:142-151
      self.caughtMark = self:dexCaught(event.mon)
    end
    if event.side == "player" then
      -- SendOutPlayerMon zeroes wBattleMenuCursorPosition and wCurMoveNum back
      -- to back (engine/battle/core.asm:3809), so a switched-in mon opens on
      -- FIGHT and on its first move.  Player side only: the zeroing lives
      -- inside SendOutPlayerMon and nothing on the enemy's path touches them.
      self.menuIndex = 1
      self.moveIndex = 1
      -- SendOutPlayerMon reloads wBattleMon* from the party slot (:3838):
      -- snap from the emit-time snapshot, not the live table (#1514).
      local level = event.level or event.mon.level or 1
      self.shownLevel = level
      self.shownExp = self:expPixels(event.mon, level,
        event.experience or event.mon.experience)
      self.expAnim = nil
    end
  end
  -- ResetEnemyBattleVars' SlideBattlePicOut (engine/battle/core.asm:3027):
  -- eight one-tile steps push the trainer's pic off the right edge, and the
  -- queue holds until they are done.
  if event.kind == "trainer-slide" then
    self.trainerSlide = 0
    return
  end
  -- BattleWinSlideInEnemyTrainerFrontpic and the DelayFrames 40 behind it
  -- (engine/battle/core.asm:2310-2312)
  if event.kind == "trainer-return" then
    -- LostBattle's ClearBox wipes the live foe pic and HUD before the slide
    -- (engine/battle/core.asm:2770-2773)
    if event.cleared then
      self.showEnemyHud = false
      self.ballRows.enemy = false
    end
    if not self.enemyTrainerImage then return self:advanceQueue() end
    self.showEnemyTrainer = true
    self.picHidden.enemy = false
    self.winSlide = 0
    self.winSliding = true
    return
  end
  -- PrintWinLossText (home/trainers.asm:230): one FarPrintText of the trainer
  -- struct's own line, paged and held for A/B like any other map text.
  if event.kind == "win-text" then
    local text = event.text
    if self.game then text = TextBox.substitute(self.game, text) end
    self:showPages(text)
    return
  end
  -- The shiny sparkle: hBattleTurn 1 and wBattleAnimParam 1 pick
  -- BattleAnim_SendOutMon's `.Shiny` arm on the enemy (core.asm:8708-8715).
  if event.kind == "shiny-flash" then
    self:animForId("ANIM_SEND_OUT_MON", "enemy", 1)
    return
  end
  -- SendOutPlayerMon: the trainer's back-pic gives way to the mon and
  -- ANIM_SEND_OUT_MON plays over the "Go!" line.
  if event.kind == "sendout" then
    self.showPlayerTrainer = false
    self.menuIndex = 1
    self.moveIndex = 1
    self.message = event.text
    self.messageTimer = MESSAGE_FRAMES
    self:startSendOut("player", self.battle and self.battle.player)
    return
  end
  -- DisplayCaughtContestMonStats, which BugContest_SetCaughtContestMon opens
  -- over the battle once a second mon is caught: the stock-versus-this
  -- comparison and its yes/no, both of which live in the contest screen.
  if event.kind == "contest-switch" then
    return self:openContestSwitch(event)
  end
  -- The failure line is picked from wThrownBallWobbleCount, which only reaches
  -- its final value inside the animation (item_effects.asm:414-428).
  if event.kind == "ball-result" then
    self.message = self:ballFailureText()
    self.messageTimer = MESSAGE_FRAMES
    return
  end
  -- `predef NewPokedexEntry` (item_effects.asm:542).
  if event.kind == "dex-entry" then
    return self:openDexEntry(event.species)
  end
  if event.kind == "ask-nickname" then
    return self:askNickname(event.mon)
  end
  if event.kind == "choose-switch" then
    -- engine/battle/core.asm:2590
    if self.battle and self.battle.wild then
      self.nextMonIndex = 1
      self.phase = "ask-next-mon"
      self.message = TEXT_USE_NEXT_MON
      self.messageTimer = 0
      return
    end
    -- A fainted lead: force a switch before anything else runs.
    self.phase = "forced-switch"
    self.message = "Choose a POKéMON."
    return
  end
  -- LearnMove's full-moveset arm: the exp queue stops on ForgetMove's own text
  -- and the player drops a move or declines (engine/pokemon/learn.asm:29-33).
  if event.kind == "choose-forget" then
    self.pendingLearn = { index = event.index, move = event.move,
      moveName = event.moveName }
    return self:askForget()
  end
  -- PlayVictoryMusic sits in the faint handler, not at the end of the battle:
  -- the jingle is already going while "X fainted!" is on screen and it loops
  -- through the exp and money lines until the overworld comes back.
  if event.kind == "faint" and event.side == "enemy" then
    -- UpdateBattleStateAndExperienceAfterEnemyFaint (core.asm:2044) reaches
    -- `.wild2` on EVERY wild enemy faint and there calls StopDangerSound and
    -- writes 1 to wBattleLowHealthAlarm (:2071-2074), before a single point of
    -- experience is awarded; WinTrainerBattle does the same pair when a
    -- trainer's last mon drops (:2293-2296).  Until this latch existed the
    -- siren kept blaring under the victory jingle, the exp bar and the
    -- level-up prompts for as long as the player's own bar stayed red.
    if self.battle.wild
        or (self.battle.over and self.battle.outcome == "win") then
      self:stopAlarm()
      self.lowHealthAlarmDisabled = true
    end
    if self.battle.over and self.battle.outcome == "win" then
      self:playVictoryMusic()
    end
  end
  if event.text then
    self.message = event.text
    -- move/level lines do not hold for A/B (battle.asm:336-343); experience
    -- keeps the wait (common_1.asm:1660-1665).
    if event.kind == "move" or event.kind == "level" then
      self.messageTimer = 0
      -- engine/battle/effect_commands.asm:1958-1961
      if event.kind == "move" and event.missed then
        self.messageDelay = MOVE_DELAY_FRAMES
      end
    else
      self.messageTimer = MESSAGE_FRAMES
    end
    -- BattleStartMessage's own line: the enemy HUD comes up on the step after
    -- it returns (engine/battle/core.asm:7808-7817), not with it.
    if event.intro then self.introTextShown = true end
    -- BattleStartMessage's `.not_shiny` cries the wild mon before its own line
    -- (engine/battle/core.asm:8718-8721).
    if event.cry then self:playCry(event.cry) end
    -- A text_asm tail that plays its own sound, the way Text_BallCaught's
    -- sound_caught_mon rides the "Gotcha!" line rather than following it.
    if event.sfx then
      self:playSfx(event.sfx)
      -- TextCommand_SOUND is `call PlaySFX` followed by `call WaitSFX`
      -- (home/text.asm:829-836, its table row at :860), so the cart stays
      -- INSIDE the text command until the sound has finished: the box cannot
      -- be paged away from mid-jingle, and PokeBallEffect's `.FinishTutorial`
      -- tail cannot return under it.
      if event.waitSfx then self.waitSfx = event.sfx end
    end
  end
  -- engine/battle/effect_commands.asm:1958: a missed move burns the delay
  -- and plays nothing; the after-anim chain is animForMove / stepAnim's.
  if event.kind == "move" and not event.missed then
    self.afterAnimPlayed = nil
    self.pendingAfterAnim = nil
    if not self:animForMove(event.move, event.side, event.animParam) then
      -- BATTLE SCENE off skips the move script but still runs wBattleAfterAnim
      -- (anim_commands.asm:55-72 .disabled fallthrough).
      local options = self.game and self.game.options
      if options and options.battleScene == false then
        if self:animForId(self:afterAnimFor(event.side), event.side) then
          self.afterAnimPlayed = true
        end
      end
    end
    -- BattleCommand_Charge runs LoadMoveAnim BEFORE DisappearUser
    -- (engine/battle/effect_commands.asm:5459-5470), so FLY / DIG still draw
    -- the take-off or the burrow on the turn the substatus goes up; the box
    -- only empties once THIS animation is done with.
    if BattleState.isVanished(self:activeMon(event.side)) then
      self.vanishAnim = self.anim
    end
  elseif event.kind == "damage" and event.side then
    -- ANIM_x_DAMAGE is the MOVE's after-anim (effect_commands.asm:1963-1972),
    -- so only a move hit gets it; `animMove` is HandleWrap's (core.asm:1198-1203).
    local from = event.animSide
      or (event.side == "enemy" and "player" or "enemy")
    if event.animMove then
      self:animForMove(event.animMove, from)
    elseif event.anim ~= false then
      local hit = event.anim
        or (event.side == "enemy" and "ANIM_ENEMY_DAMAGE"
          or "ANIM_PLAYER_DAMAGE")
      -- Already played as the move's after-anim; do not shake twice.
      if self.afterAnimPlayed
          and (hit == "ANIM_ENEMY_DAMAGE" or hit == "ANIM_PLAYER_DAMAGE") then
        self.afterAnimPlayed = nil
      else
        self:animForId(hit, from)
      end
    end
  else
    -- Status moves still chain the after-anim but emit no damage event to
    -- consume the latch; drop it before the next unrelated line.
    self.afterAnimPlayed = nil
  end
  if event.kind == "heal" and event.anim and event.side then
    -- pokegold engine/battle/core.asm:4074 ItemRecoveryAnim
    self:animForMove(event.anim, event.side)
  elseif event.kind == "send" and event.side then
    -- Every enemy send-out goes through ShowSetEnemyMonAndSendOutAnimation
    -- (engine/battle/core.asm:3354) -- the faint replacement out of
    -- EnemyPartyMonEntrance and the AI's mid-turn rotation alike -- and the
    -- player's voluntary switch through SendOutPlayerMon (:3796).  Without it
    -- the replacement simply appeared, which with two of a species back to back
    -- reads as one mon growing a second health bar.
    self:startSendOut(event.side, event.mon)
  end
end

-- SetEnemyTurn / SetPlayerTurn, then ANIM_SEND_OUT_MON.  The cry and the HUD
-- come after the animation, not with it.
function BattleState:startSendOut(side, mon)
  -- BattleCheckPlayerShininess / BattleCheckEnemyShininess replay the anim's
  -- `.Shiny` arm before the cry (core.asm:3826-3831, :3371-3377).
  local after = { side = side, mon = mon, shiny = mon and mon.shiny and true }
  -- ShowSetEnemyMonAndSendOutAnimation and SendOutPlayerMon both draw the pic
  -- into the box before they play the animation, which is the one thing that
  -- undoes a cleared box.
  self.picHidden[side] = false
  self.faintSlide = nil
  -- The rows are shadow OAM (engine/battle/trainer_huds.asm:203-223), which
  -- this animation's own sprites overwrite.
  self.ballRows.player = false
  self.ballRows.enemy = false
  if self:animForId("ANIM_SEND_OUT_MON", side) then
    self.afterSendOut = after
    return true
  end
  -- BattleAnimRunScript is skipped with BATTLE SCENE off (and there are no
  -- scripts at all in a cache built before they were extracted), but the cart
  -- still runs the cry and the HUD update, so they happen now.
  self:finishSendOut(after)
  return false
end

-- `ld a, [wTempEnemyMonSpecies] / call PlayStereoCry / call UpdateEnemyHUD`
-- (engine/battle/core.asm:3380-3384), and the same pair at the tail of
-- SendOutPlayerMon (:3836-3838).
function BattleState:finishSendOut(after)
  if not after then return end
  self:playCry(after.mon)
  if after.side == "enemy" then
    self.showEnemyHud = true
  else
    self.showPlayerHud = true
  end
end

-- PlaySFX with one of the sfx the extractor named, or nothing at all when this
-- cache does not carry it.
function BattleState:playSfx(name)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if name and audio and audio.sfx and audio.sfx[name] then
    Sound.play(data, name)
  end
end

-- PlayStereoCry with the battler's own species.  audio.cries is keyed by
-- SPECIES, the same table the animation runtime's `cry` callback plays through.
function BattleState:playCry(mon)
  local species = mon and mon.species
  if not species then return end
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.cries and audio.cries[species] then
    Sound.playCry(data, species)
  end
end

--------------------------------------------------------------------------
-- EvolveAfterBattle
--------------------------------------------------------------------------

-- ExitBattle (engine/battle/core.asm): `ld a, [wBattleResult] / and $f /
-- jr nz, .CleanUpBattleRAM` -- only a WIN reaches `xor a / ld
-- [wForceEvolution], a / predef EvolveAfterBattle`.  A loss goes straight to
-- the whiteout, so a mon that leveled on the way down never evolves.
--
-- wForceEvolution is cleared here, which is what makes B a working cancel and
-- what keeps the EVOLVE_ITEM rows (Eevee's stones) from firing off a battle.
function BattleState:startEvolutions()
  self.phase = "evolving"
  -- ExitBattle's CleanUpBattleRAM zeroes wLowHealthAlarm; nothing past here
  -- runs updateAlarm, so the siren has to be cut before the sweep takes over.
  self:stopAlarm()
  local battle = self.battle
  if not (battle and Evolution.runsAfterBattle(battle.outcome)) then
    return self:finishBattle()
  end
  local stack = self.game and self.game.stack
  local party = battle.party or (self.save and self.save.party) or {}
  self.evolutions = Evolution.plan((self.game and self.game.data) or {},
    party, self.evolvable, {
      -- wTimeOfDay, for the TR_MORNDAY / TR_NITE happiness rows.
      timeOfDay = Palettes.clockDaytime(),
    })
  self.evolutionIndex = 0
  if #self.evolutions == 0 or not stack then return self:finishBattle() end
  return self:nextEvolution()
end

-- EvolveAfterBattle_MasterLoop, one flagged slot at a time: the screen owns
-- the stack until it reports back, and the next slot only starts once it does.
function BattleState:nextEvolution()
  self.evolutionIndex = self.evolutionIndex + 1
  local plan = self.evolutions[self.evolutionIndex]
  if not plan then return self:finishBattle() end
  local stack = self.game.stack
  Screens.push(self.game, "Gen2EvolutionAnim", {
    mon = plan.mon,
    entry = plan.entry,
    index = plan.index,
    party = self.battle.party or (self.save and self.save.party),
    save = self.save,
    onDone = function()
      stack:pop()
      self:nextEvolution()
    end,
  })
end

-- ExitBattle's `farcall GivePokerusAndConvertBerries`, which sits immediately
-- after `predef EvolveAfterBattle` inside the same WIN arm -- so it runs once
-- per won battle, after every evolution has resolved, and never after a loss.
-- Silent by design: nothing tells the player, and the Pokemon Center nurse is
-- the first thing that ever mentions it (std_scripts.asm PokeCenterNurseScript,
-- through the CheckPokerus special).
function BattleState:givePokerus()
  local battle = self.battle
  if not (battle and Evolution.runsAfterBattle(battle.outcome)) then return nil end
  local party = battle.party or (self.save and self.save.party)
  -- GivePokerusAndConvertBerries opens on `call ConvertBerriesToBerryJuice`,
  -- so the Shuckle's held BERRY converts before the Pokerus roll runs.
  BerryJuice.convertAfterBattle(self.save, party)
  return Pokerus.giveAfterBattle(self.save, party)
end

-- .ReturnToMap, minus the RestartMapMusic the overworld's own onDone already
-- does (src/world/gen2/World.lua calls Music.restoreMap there).
function BattleState:finishBattle()
  self.phase = "done"
  self:stopAlarm()
  self:clearMenuCursors()
  self:givePokerus()
  -- CleanUpBattleRAM: every substatus the battle wrote goes with the battle.
  -- The party tables it wrote them on are the save's own, so this has to run
  -- before the overworld (and the next save write) sees them again.
  if self.battle then self.battle:clearAllVolatiles() end
  if self.onDone then
    self.onDone(self.battle and self.battle.outcome, self.battle)
  end
end

-- CleanUpBattleRAM's cursor block (engine/battle/core.asm:7994-8004): the menu
-- bytes that live ACROSS menu openings are zeroed here and nowhere else --
-- wPartyMenuCursor, wLastPocket, and the ITEM / KEY_ITEM / BALL pocket cursors
-- with their scroll positions.  The TM/HM pair is deliberately NOT in that
-- list, so it survives a battle and is left alone here.
function BattleState:clearMenuCursors()
  self.shiftIndex, self.shiftSwitchIndex = nil, nil
  local game = self.game
  if not game then return end
  game.partyMenuCursor = nil
  local pack = game.packCursor
  if not pack then return end
  pack.pocket = nil
  for _, id in ipairs({ "ITEM", "KEY_ITEM", "BALL" }) do
    pack.cursor[id] = nil
    pack.scroll[id] = nil
  end
end

-- Whether any mon that took part in the battle is still standing.  A wild win
-- with none left plays NO music at all (PlayVictoryMusic's `.lost` path), so
-- the map theme carries straight on -- which is what a mon fainting to its own
-- recoil on the winning blow sounds like.
function BattleState:participantsFainted()
  local battle = self.battle
  if not battle then return true end
  for index in pairs(battle.participants or {}) do
    local mon = battle.party and battle.party[index]
    if mon and (mon.hp or 0) > 0 then return false end
  end
  return true
end

function BattleState:playVictoryMusic()
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not (audio and audio.songs) then return nil end
  local song = BattleMusic.victorySong({
    class = self.music and self.music.class,
    participantsFainted = self:participantsFainted(),
  })
  if not (song and audio.songs[song]) then return nil end
  require("src.core.Music").play(data, song, true, { reason = "victory" })
  return song
end

function BattleState:submit(action)
  self.phase = "resolving"
  self:pushAll(self.battle:takeTurn(action))
  self.message = nil
  self.messageTimer = 0
  self:advanceQueue()
end

function BattleState:playerMoves()
  return (self.battle and self.battle.player and self.battle.player.moves) or {}
end

-- One semantic path for the native command menu and mod.battle intents.
function BattleState:chooseMenu(choice)
  if self.phase ~= "menu" then return nil, "battle menu is not active" end
  if choice == "fight" then
    -- CheckPlayerHasUsableMoves skips MoveSelectionScreen and uses Struggle.
    local fighter = self.battle and self.battle.player
    if fighter and #self:playerMoves() > 0
        and not self.battle:hasUsableMoves(fighter) then
      self:submit({ kind = "move", move = Battle.STRUGGLE })
    else
      self.phase = "moves"
      -- MoveSelectionScreen reopens on the last used move, clamped if the
      -- moveset shrank since then.
      local moves = self:playerMoves()
      self.moveIndex = math.max(1,
        math.min(self.moveIndex or 1, math.max(1, #moves)))
    end
  elseif choice == "run" then
    self:submit({ kind = "run" })
  elseif choice == "item" then
    if self.tutorial then
      self:openTutorialPack()
    elseif self.contest then
      self:throwParkBall()
    else
      self:openPack()
    end
  elseif choice == "party" then
    self:openParty()
  else
    return nil, "unknown battle menu choice"
  end
  return true
end

function BattleState:chooseMove(index)
  if self.phase ~= "moves" then return nil, "move menu is not active" end
  local move = self:playerMoves()[index]
  if not move then return nil, "invalid move slot" end
  self.moveIndex = index
  self.moveSwapIndex = nil
  if (move.pp or 0) <= 0 then
    self:refuseMove(TEXT_NO_PP_LEFT)
  elseif self.battle:moveDisabled(self.battle.player, move.id) then
    self:refuseMove(TEXT_MOVE_DISABLED)
  else
    self:submit({ kind = "move", move = move.id })
  end
  return true
end

function BattleState:cancelMove()
  if self.phase ~= "moves" then return nil, "move menu is not active" end
  self.moveSwapIndex = nil
  self.phase = "menu"
  return true
end

-- MoveSelectionScreen's `.pressed_select` (engine/battle/core.asm:5320-5374).
-- SELECT marks a slot, SELECT again swaps the marked slot with the one under
-- the cursor, and A or B clears the mark without swapping (the A arm opens
-- `xor a / ld [wSwappingMove], a`).
--
-- The cart swaps wBattleMonMoves and wBattleMonPP as two separate byte pairs,
-- then repeats both in the party struct.  Here a move IS one record carrying
-- its own pp and maxPp, and Battle:switchIn takes the party table by reference
-- (Battle.player is the party entry), so exchanging the two records does all
-- four of those swaps at once and the party keeps the new order after the
-- battle, which is the point of reordering mid-fight.
--
-- Two things the cart does that this does NOT need:
--   * `.not_swapping_disabled_move` rewrites wPlayerDisableCount's slot nibble
--     so DISABLE keeps pointing at the same MOVE after the swap.  Gold's
--     disable here stores the move id (Battle:volatile(mon).disabled == moveId,
--     src/battle/gen2/Battle.lua:3489), so it follows the move already.
--   * `.swap_moves_in_party_struct` is skipped when SUBSTATUS_TRANSFORMED is
--     set -- the COOLTRAINER glitch fix, which stops a Transformed mon writing
--     borrowed moves into its own party slot.  One table per mon means the
--     battle copy and the party slot cannot be written separately, so the swap
--     is refused outright while transformed.  A transformed mon's moves are
--     borrowed and vanish on switch-out, so there is nothing to reorder.
function BattleState:swapAllowed()
  local player = self.battle and self.battle.player
  if not player then return false end
  return not (self.battle:volatile(player) or {}).transformed
end

function BattleState:swapMoves(i, j)
  if i == j then return end
  local moves = self:playerMoves()
  local a, b = moves[i], moves[j]
  if not (a and b) then return end
  moves[i], moves[j] = b, a
end

function BattleState:update(_dt)
  -- The evolution sweep owns the stack (and the low-HP alarm is long over);
  -- this state is only still here because ExitBattle has not cleaned up yet.
  if self.phase == "evolving" or self.phase == "done" then return end
  self:updateAlarm()
  local input = self.game and self.game.input
  if not input then return end

  -- The intro slide blocks everything: BattleIntroSlidingPics is a plain
  -- 72-frame loop with no input read inside it.
  if self.slideFrame < BattleAnimView.SLIDE_FRAMES then
    self.slideFrame = self.slideFrame + 1
    return
  end

  -- BattleWinSlideInEnemyTrainerFrontpic plus WinTrainerBattle's DelayFrames
  -- 40 (engine/battle/core.asm:6279-6318, :2310-2312)
  if self.winSliding then
    self.winSlide = self.winSlide + 1
    if self.winSlide >= WIN_SLIDE_FRAMES + WIN_SLIDE_DELAY_FRAMES then
      self.winSliding = nil
      self:advanceQueue()
    end
    return
  end

  -- SlideBattlePicOut is a plain loop with DelayFrames in it, so it owns the
  -- screen the same way (engine/battle/core.asm:2882).
  if self.trainerSlide then
    self.trainerSlide = self.trainerSlide + 1
    if self.trainerSlide >= TRAINER_SLIDE_FRAMES then
      self.trainerSlide = nil
      self.showEnemyTrainer = false
      self:advanceQueue()
    end
    return
  end

  -- MonFaintedAnimation is a plain loop with DelayFrames in it, like
  -- SlideBattlePicOut above: it owns the screen until the pic is off the
  -- field, and the box it emptied stays empty (only a send-out refills it).
  if self.faintSlide then
    local slide = self.faintSlide
    slide.frames = slide.frames + 1
    if slide.frames >= self:faintSlideFrames(slide.side) then
      self.picHidden[slide.side] = true
      -- SFX_FAINT follows EnemyMonFaintedAnimation, and ClearBox blanks the
      -- fainted side's HUD before its text (core.asm:2213-2218, :2202-2205).
      if slide.side == "enemy" then
        self:playSfx("Sfx_Faint")
        self.showEnemyHud = false
      else
        self.showPlayerHud = false
      end
      self.faintSlide = nil
      self:advanceQueue()
    end
    return
  end

  -- An animation owns the screen for as long as it runs, exactly the way
  -- RunBattleAnimScript owns the main loop.
  -- pokegold data/moves/animations.asm .Click: a finished keepsprites run
  -- no longer owns the loop, just the OAM the draw path still reads.
  if self.anim and not (self.anim:done() and self.anim.keepSprites) then
    self:stepAnim(input)
    return
  end

  -- The bar drain holds the queue the way AnimateHPBar's loop holds the
  -- cart: the next event runs once the shown HP has caught the real one.
  if self:stepHpAnim() then return end

  if self.phase == "resolving" or self.phase == "intro" then
    -- The `call WaitSFX` half of TextCommand_SOUND (home/text.asm:834-835):
    -- the line holds, unskippable, for as long as its own sound is sounding.
    -- Without it the DUDE's auto-input tapped straight through the "Gotcha!"
    -- line and finishBattle closed the tutorial over the jingle.
    if self.waitSfx then
      if Sound.isPlaying(self.waitSfx) then return end
      self.waitSfx = nil
    end
    -- AnimateExpBar sits right after PrintText Text_MonGainedExpPoint
    -- (core.asm:6881-6888), with that line still on screen.  Run the crawl
    -- before any PromptButton wait so the bar does not sit frozen until A.
    if self:stepExpAnim() then return end
    -- engine/battle/effect_commands.asm:6661
    if (self.messageDelay or 0) > 0 then
      self.messageDelay = self.messageDelay - 1
      return
    end
    if self.messageTimer > 0 then
      if self.tutorial then
        -- PromptButton waits for the button; the tutorial cannot press it, so
        -- DudeAutoInput_A (frame 0x51) answers.  Never auto-timeout here: a
        -- 48-frame skip would hand his press to the next screen.
        self:dudeInput(CatchTutorial.PROMPT_STREAM,
          "prompt:" .. tostring(self.message))
      end
      -- PromptButton (home/text.asm): A/B pages; no frame countdown.
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    -- pokegold engine/battle/core.asm:7057-7069: the stats box shows once
    -- the "grew to level" line has finished, held for A/B.
    if self.pendingStatsMon then
      self.statsBoxMon = self.pendingStatsMon
      self.pendingStatsMon = nil
      self.phase = "stats-box"
      return
    end
    -- PrintWinLossText's line pages like any map text (home/text.asm:403-448)
    if self:nextPage() then return end
    self:advanceQueue()
    return
  end

  -- pokegold engine/battle/core.asm:7069 (WaitPressAorB_BlinkCursor).
  if self.phase == "stats-box" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.statsBoxMon = nil
      self.phase = "resolving"
    end
    return
  end

  -- The turn CheckPlayerLockedIn skipped the menu for.  No input is read: the
  -- cart falls straight into ParsePlayerAction, whose .locked_in arm has no
  -- MoveSelectionScreen in front of it.
  if self.phase == "locked-in" then
    local locked = self.battle and self.battle.player
      and self.battle:lockedInMove(self.battle.player)
    if locked then
      self:submit({ kind = "move", move = locked })
    else
      self.phase = "menu"
    end
    return
  end

  if self.phase == "menu" then
    -- 2x2 grid: left/right swap the column, up/down the row.
    -- MenuClickSound / PlayClickSFX (home/menu.asm:746-762): SFX_READ_TEXT_2
    -- on A/B only, never on D-pad.
    if input:wasPressed("left") or input:wasPressed("right") then
      self.menuIndex = self.menuIndex % 2 == 1 and self.menuIndex + 1
        or self.menuIndex - 1
    elseif input:wasPressed("up") or input:wasPressed("down") then
      self.menuIndex = self.menuIndex <= 2 and self.menuIndex + 2
        or self.menuIndex - 2
    elseif input:wasPressed("a") then
      self:playSfx("Sfx_ReadText2")
      self:chooseMenu(MENU_ACTION[MENU[self.menuIndex]])
    end
    return
  end

  if self.phase == "moves" then
    local moves = self:playerMoves()
    local grid
    if self:moveGridNavigation() then
      local index, count = self.moveIndex, #moves
      if input:wasPressed("left") or input:wasPressed("right") then
        local other = math.floor((index - 1) / 2) * 2
          + (1 - (index - 1) % 2) + 1
        grid = other <= count and other or index
      elseif input:wasPressed("up") or input:wasPressed("down") then
        local other = (1 - math.floor((index - 1) / 2)) * 2
          + (index - 1) % 2 + 1
        grid = other <= count and other or index
      end
    end
    if grid then
      self.moveIndex = grid
    elseif input:wasPressed("up") then
      self.moveIndex = self.moveIndex > 1 and self.moveIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.moveIndex = self.moveIndex < #moves and self.moveIndex + 1 or 1
    elseif input:wasPressed("select") then
      if self.moveSwapIndex then
        self:swapMoves(self.moveSwapIndex, self.moveIndex)
        self.moveSwapIndex = nil
      elseif self:swapAllowed() then
        self.moveSwapIndex = self.moveIndex
      end
    elseif input:wasPressed("b") then
      -- B leaves the list, and a mark never survives it
      self:playSfx("Sfx_ReadText2")
      self:cancelMove()
    elseif input:wasPressed("a") then
      -- `xor a / ld [wSwappingMove], a` opens the A arm: choosing a move
      -- cancels a pending swap rather than performing it
      self:playSfx("Sfx_ReadText2")
      self:chooseMove(self.moveIndex)
    end
    return
  end

  if self.phase == "ask-nickname" then
    -- AskGiveNicknameText ends on `done`, so the line stands while the box is
    -- up rather than paging away from under it.
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      self.nicknameIndex = self.nicknameIndex == 1 and 2 or 1
    elseif input:wasPressed("b") then
      -- YesNoMenuHeader carries no STATICMENU_DISABLE_B: B is NO.
      return self:answerNickname(false)
    elseif input:wasPressed("a") then
      return self:answerNickname(self.nicknameIndex == 1)
    end
    return
  end

  -- The prompt's earlier pages: PlaceYesNoBox only follows the LAST one
  -- (engine/battle/core.asm:3302-3305), so the mon is named and read first.
  if self.phase == "shift-intro" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    self:nextPage()
    if not self.messagePages then self.phase = "ask-shift" end
    return
  end

  -- OfferSwitch's YesNoBox: YES opens PickSwitchMonInBattle, NO (and B) falls
  -- straight through to the enemy's send-out (engine/battle/core.asm:3305-3310).
  if self.phase == "ask-shift" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      self.shiftIndex = self.shiftIndex == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self.phase = "resolving"
      return self:advanceQueue()
    elseif input:wasPressed("a") then
      if self.shiftIndex == 1 then return self:openShiftParty() end
      self.phase = "resolving"
      return self:advanceQueue()
    end
    return
  end

  -- engine/battle/core.asm:2590
  if self.phase == "ask-next-mon" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      self.nextMonIndex = self.nextMonIndex == 1 and 2 or 1
    elseif input:wasPressed("b") then
      return self:answerUseNextMon(false)
    elseif input:wasPressed("a") then
      return self:answerUseNextMon(self.nextMonIndex == 1)
    end
    return
  end

  if self.phase == "cant-escape-then-switch" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    self.message = "Choose a POKéMON."
    self.phase = "forced-switch"
    return
  end

  if self.phase == "refuse-shift" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    self.message = nil
    return self:openShiftParty()
  end

  if self.phase == "forced-switch" then
    -- Reuse the party list so the layout and controls match the start menu's.
    self:openParty(true)
    return
  end

  -- CheckIfCurPartyMonIsFitToFight said no.  Its text is read with the list
  -- CLOSED here rather than over it (the party menu is its own screen in this
  -- port), and the list comes back the moment the line is done -- which is
  -- what ForcePickPartyMonInBattle's `jr c, .loop` does with the carry.
  if self.phase == "refuse-switch" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    local forced = self.refuseForced
    self.refuseForced = nil
    self.message = nil
    if not self:openParty(forced) then
      -- No stack to open a list on (headless): the forced arm falls back to
      -- the phase that keeps asking, and a voluntary one to the menu.
      self.phase = forced and "forced-switch" or "menu"
    end
    return
  end

  if self.phase == "refuse-move" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    self.message = nil
    self.phase = "moves"
    return
  end

  if self.phase == "learn-intro" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    -- YesNoBox follows the last page of the text (engine/pokemon/learn.asm:125).
    self:nextPage()
    if not self.messagePages then self.phase = "ask-forget" end
    return
  end

  if self.phase == "ask-forget" or self.phase == "stop-learning" then
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      self.forgetChoice = self.forgetChoice == 1 and 2 or 1
    elseif input:wasPressed("b") then
      -- YesNoMenuHeader carries no STATICMENU_DISABLE_B: B is NO.
      return self:answerForgetPrompt(false)
    elseif input:wasPressed("a") then
      return self:answerForgetPrompt(self.forgetChoice == 1)
    end
    return
  end

  if self.phase == "choose-forget" then
    -- MoveCantForgetHMText holds like any prompt, then `jr .loop` reprints
    -- MoveAskForgetText over the list (engine/pokemon/learn.asm:193-197).
    if self.messageTimer > 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        self.messageTimer = 0
      end
      return
    end
    self.message = Strings(TEXT_ASK_FORGET_SLOT)
    local learn = self.pendingLearn
    local mon = learn and self.battle.party[learn.index]
    local moves = (mon and mon.moves) or {}
    if input:wasPressed("up") then
      self.forgetIndex = self.forgetIndex > 1 and self.forgetIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.forgetIndex = self.forgetIndex < #moves and self.forgetIndex + 1 or 1
    elseif input:wasPressed("b") then
      -- ForgetMove's .cancel sets carry, which is LearnMove's .cancel
      -- (engine/pokemon/learn.asm:187-201).
      return self:askStopLearning()
    elseif input:wasPressed("a") then
      local slot = moves[self.forgetIndex]
      if slot and HM_MOVES[slot.id] then
        -- MoveCantForgetHMText, then `jr .loop`, which re-seeds wMenuCursorY
        -- (engine/pokemon/learn.asm:155-157, 193-197).
        self.message = Strings(TEXT_CANT_FORGET_HM)
        self.messageTimer = MESSAGE_FRAMES
        self.forgetIndex = 1
        return
      end
      self.battle:resolveForget(learn.index, self.forgetIndex,
        learn.move, learn.moveName)
      self.pendingLearn = nil
      self.phase = "resolving"
      self:pushFront(self.battle:takeEvents())
      self:advanceQueue()
    end
    return
  end
end

-- Returns whether the list actually opened, so a caller that has to do
-- something else when it cannot (no stack at all) can tell.
function BattleState:openParty(forced)
  local stack = self.game and self.game.stack
  if not stack then return false end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2PartyMenu", {
    -- PARTYMENUACTION_CHOOSE_POKEMON for the voluntary list and
    -- PARTYMENUACTION_SWITCH for the forced one (engine/battle/core.asm:4795,
    -- :2702; engine/pokemon/party_menu.asm:660-679).  Only the voluntary list
    -- carries BattleMonMenu; PickPartyMonInBattle has no submenu.
    prompt = forced and "which" or "choose",
    battle = true,
    battleSubmenu = not forced,
    onCancel = function()
      stack:pop()
      -- A forced switch cannot be cancelled.
      self.phase = forced and "forced-switch" or "menu"
    end,
    onChoose = function(index, mon)
      stack:pop()
      -- TryPlayerSwitch's own order, every arm ending on
      -- `jp BattleMenuPKMN_Loop` (engine/battle/core.asm:4863-4888).
      if not forced and mon == self.battle.player then
        return self:refuseSwitch(false,
          self:name(mon) .. " is already out.")
      end
      if not forced and self.battle:switchLocked() then
        return self:refuseSwitch(false,
          self:name(self.battle.player) .. " can't be recalled!")
      end
      -- CheckIfCurPartyMonIsFitToFight's `cp EGG` arm (core.asm:3450-3456).
      if mon.isEgg then
        return self:refuseSwitch(forced, TEXT_EGG_CANT_BATTLE)
      end
      if (mon.hp or 0) <= 0 then
        -- CheckIfCurPartyMonIsFitToFight (engine/pokemon/party_menu.asm):
        -- a fainted pick prints Text_TheresNoWillToFight and returns carry, so
        -- the caller re-opens the list -- BattleMenu_PKMN's own loop for a
        -- voluntary switch, ForcePickPartyMonInBattle's `jr c` after a faint.
        -- Silently dropping the player back on the list (or, worse, back on
        -- the battle menu) is what made the forced switch read as taking two
        -- or three presses: the cursor opens on the mon that just fainted, and
        -- pressing A on it did nothing a player could see.
        return self:refuseSwitch(forced)
      end
      if forced then
        -- ForcePickPartyMonInBattle loops on carry: a pick the engine will not
        -- take has to come back as the list again, never as the battle menu
        -- with a fainted mon standing on the field.
        if not self.battle:switch(index) then
          return self:refuseSwitch(true)
        end
        self:pushAll(self.battle:takeEvents())
        self.phase = "resolving"
        self:advanceQueue()
      else
        self:submit({ kind = "switch", index = index })
      end
    end,
  })
  return true
end

-- The refusal itself: the line, then the same list again.  `forced` is carried
-- so a faint's list comes back with no CANCEL of its own and a voluntary one
-- keeps its own.
function BattleState:refuseSwitch(forced, text)
  self.refuseForced = forced and true or false
  self.phase = "refuse-switch"
  self.message = text or TEXT_NO_WILL_TO_FIGHT
  self.messageTimer = MESSAGE_FRAMES
end

function BattleState:refuseMove(text)
  self.phase = "refuse-move"
  self.message = text
  self.messageTimer = MESSAGE_FRAMES
end

-- BattleMenu_Pack: `farcall BattlePack`, which is a different jumptable from
-- the field PACK's -- it dispatches on the item's BATTLE menu nibble and never
-- reaches a field effect.  The empty world is the same guard MartMenu:enterSell
-- and ItemPcMenu:enterDeposit carry: PackMenu falls back to game.world when it
-- is nil, and that world is the overworld this battle is suspended over.
function BattleState:openPack()
  local stack = self.game and self.game.stack
  if not stack then return end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2PackMenu", {
    battle = true,
    world = {},
    onClose = function()
      stack:pop()
      self.phase = "menu"
    end,
    onChoose = function(itemId)
      stack:pop()
      self:useItem(itemId)
    end,
  })
end

-- BattleMenu_Pack's `.tutorial` arm: `farcall TutorialPack`, and then POKE_BALL
-- goes into wCurItem and DoItemEffect runs WHATEVER the pack came back with --
-- TutorialPack's own tail writes FALSE to wPackUsedItem, so its answer is
-- discarded.  The pack is real all the same: it is drawn from the DUDE's own
-- buffers (wDudeNumItems / wDudeNumBalls, one POTION and one POKE BALL), and
-- the DUDE_RIGHT_A stream armed with it is what crosses from the ITEM pocket to
-- the BALL pocket and picks the ball, which is the whole point of the demo.
function BattleState:openTutorialPack()
  local stack = self.game and self.game.stack
  if not stack then return self:useItem(CatchTutorial.BALL) end
  self.phase = "submenu"
  local function throw()
    stack:pop()
    self:useItem(CatchTutorial.BALL)
  end
  Screens.push(self.game, "Gen2PackMenu", {
    battle = true,
    save = CatchTutorial.dudeSave(),
    -- An empty world rather than the real one: a DUDE pocket must not reach
    -- World:useFieldItem, because these buffers are not the player's bag and
    -- nothing in them may be spent.  PackMenu falls back to game.world when
    -- this is nil, so it has to be a table.
    world = {},
    onClose = throw,
    onChoose = throw,
  })
  self:dudeInput(CatchTutorial.PACK_STREAM, nil, true)
end

-- BattleMenu_Pack's `.contest` arm: it does NOT open the pack.  PARK_BALL goes
-- straight into wCurItem and DoItemEffect runs, so the third menu slot IS the
-- throw and nothing else can be used inside the park.
function BattleState:throwParkBall()
  self:useItem(BugContest.BALL)
end

--------------------------------------------------------------------------
-- PokeBallEffect (engine/items/item_effects.asm:213)
--------------------------------------------------------------------------

-- data/battle_anims/ball_colors.asm BallColors, in its own order.  Anything
-- not listed falls to the terminator row's PAL_BATTLE_OB_GRAY.
local BALL_COLORS = {
  MASTER_BALL = "PAL_BATTLE_OB_GREEN",
  ULTRA_BALL = "PAL_BATTLE_OB_YELLOW",
  GREAT_BALL = "PAL_BATTLE_OB_BLUE",
  POKE_BALL = "PAL_BATTLE_OB_RED",
  HEAVY_BALL = "PAL_BATTLE_OB_GRAY",
  LEVEL_BALL = "PAL_BATTLE_OB_BROWN",
  LURE_BALL = "PAL_BATTLE_OB_BLUE",
  FAST_BALL = "PAL_BATTLE_OB_BLUE",
  FRIEND_BALL = "PAL_BATTLE_OB_YELLOW",
  MOON_BALL = "PAL_BATTLE_OB_GRAY",
  LOVE_BALL = "PAL_BATTLE_OB_RED",
}
local BALL_COLOR_DEFAULT = "PAL_BATTLE_OB_GRAY"

-- POKE_BALL's own item id (constants/item_constants.asm:13), for a cache whose
-- items table has no index on the row.
local POKE_BALL_ID = 5

-- data/battle/wobble_probabilities.asm WobbleProbabilities: catch rate, then
-- the chance out of 255 of wobbling again rather than breaking free.
local WOBBLE_PROBABILITIES = {
  { 1, 63 }, { 2, 75 }, { 3, 84 }, { 4, 90 }, { 5, 95 }, { 7, 103 },
  { 10, 113 }, { 15, 126 }, { 20, 134 }, { 30, 149 }, { 40, 160 },
  { 50, 169 }, { 60, 177 }, { 80, 191 }, { 100, 201 }, { 120, 211 },
  { 140, 220 }, { 160, 227 }, { 180, 234 }, { 200, 240 }, { 220, 246 },
  { 240, 251 }, { 254, 253 }, { 255, 255 },
}

-- GetPokeBallWobble's `cp 3 + 1`: the ball wobbles up to three times and the
-- fourth call is the verdict.
local WOBBLE_LIMIT = 3

-- The four failure lines, indexed by wThrownBallWobbleCount exactly the way
-- item_effects.asm:414-428 indexes them (data/text/common_3.asm:239-258).
local BALL_FAILURE_TEXT = {
  "Oh no! The POKéMON broke free!",
  "Aww! It appeared to be caught!",
  "Aargh! Almost had it!",
  "Shoot! It was so close too!",
}

-- Text_BallCaught's own sound_caught_mon (data/text/common_3.asm:265).
local SFX_CAUGHT_MON = "Sfx_CaughtMon"

-- wBattleAnimParam for the throw: the item's own id, except that everything
-- past POKE_BALL (the Kurt balls) is thrown with POKE_BALL's -- `cp POKE_BALL
-- + 1 / jr c, .not_kurt_ball / ld a, POKE_BALL` (item_effects.asm:396).  It is
-- what BattleAnim_ThrowPokeBall's anim_if_param_equal rows branch on
-- (data/moves/animations.asm:305-308).
function BattleState:ballAnimParam(itemId)
  local items = ((self.game and self.game.data) or {}).items or {}
  local pokeBall = (items.POKE_BALL and items.POKE_BALL.index) or POKE_BALL_ID
  local id = (items[itemId] and items[itemId].index) or pokeBall
  if id > pokeBall then return pokeBall end
  return id
end

-- GetBallAnimPal (engine/battle_anims/functions.asm:292), which the thrown
-- ball's object function reads out of env.ballPalette.
function BattleState:ballPalette(itemId)
  return BALL_COLORS[itemId] or BALL_COLOR_DEFAULT
end

-- `ld de, ANIM_THROW_POKE_BALL ... xor a / ldh [hBattleTurn], a`: the ball is
-- thrown from the player's side whatever the turn order was.
function BattleState:startBallAnim(param, itemId)
  local key = self.anims and self.anims.ids
    and self.anims.ids.ANIM_THROW_POKE_BALL
  return self:startAnim(key, {
    turn = 0, animId = "ANIM_THROW_POKE_BALL", param = param,
    ballPalette = self:ballPalette(itemId),
  })
end

-- GetPokeBallWobble (engine/battle_anims/pokeball_wobble.asm), which
-- anim_checkpokeball loops on: 0 wobble again, 1 click, 2 break free.  The
-- counter goes up FIRST, and the fourth call ends the loop -- a caught mon
-- clicks, anything else breaks free.  Before that a caught mon always wobbles
-- again and a doomed one re-rolls: the first WobbleProbabilities row whose
-- catch rate is at least the final rate is the one whose byte the roll has to
-- come in under.
function BattleState:pokeballWobble()
  local throw = self.ballThrow
  if not throw then return 0 end
  throw.wobble = (throw.wobble or 0) + 1
  if throw.wobble == WOBBLE_LIMIT + 1 then
    return throw.caught and 1 or 2
  end
  if throw.caught then return 0 end
  local chance = 0
  for _, row in ipairs(WOBBLE_PROBABILITIES) do
    if row[1] >= (throw.rate or 0) then chance = row[2] break end
  end
  local random = self.battle and self.battle.random
  local roll = random and random(256) or 0
  return roll < chance and 0 or 2
end

-- Which of the four lines the throw earned.  With no animation to run (an
-- older cache, or BATTLE SCENE off) nothing ever wobbled, so it is the first.
function BattleState:ballFailureText()
  local wobble = (self.ballThrow and self.ballThrow.wobble) or 1
  return BALL_FAILURE_TEXT[math.max(1, math.min(#BALL_FAILURE_TEXT, wobble))]
end

-- UseBallInTrainerBattle (item_effects.asm:2579).  Not a bare refusal: the ball
-- is thrown with wBattleAnimParam = 0, which BattleAnim_ThrowPokeBall's
-- `anim_if_param_equal NO_ITEM` sends to .TheTrainerBlockedTheBall, then BOTH
-- lines print and it falls into UseDisposableItem -- so the ball is spent and
-- the turn goes with it.
function BattleState:throwBallAtTrainer(itemId)
  self.queue = {}
  self:push({ kind = "message", text = "The trainer blocked the BALL!" })
  self:push({ kind = "message", text = "Don't be a thief!" })
  self:consumeItem(itemId)
  self:pushAll(self.battle:takeTurn({ kind = "item", item = itemId }))
  -- NO_ITEM is 0, the id BattleAnim_ThrowPokeBall's first row tests.
  self:startBallAnim(0, itemId)
  self.message = nil
  self.messageTimer = 0
  self.phase = "resolving"
  if not self.anim then self:advanceQueue() end
end

-- Which box `.SendToPC` writes into.  wCurBox is a BYTE the cart masks before
-- it ever indexes with it (`ld a, [wCurBox] / and $f`, and GetBoxCount's own
-- bounds), so no value of it can address a box that is not there; this save
-- field holds the same number 1-based.  The mask is worth keeping because
-- Boxes.box answers an index outside 1..NUM_BOXES with a THROWAWAY table
-- rather than an error (src/core/gen2/Boxes.lua), so an out-of-range wCurBox
-- would insert the catch into a table nothing owns while "was sent to BILL's
-- PC" printed -- a silently lost mon.
--
-- No path writes one today, and the comment that used to stand here was wrong
-- to say a converted cartridge save does: GenSave decodes the cart's 0-based
-- byte as `curBoxNum + 1` clamped to 1..12 before it ever reaches
-- save.currentBox (src/save_convert/GenSave.lua), and SaveConvert refuses a
-- Gen 2 cart save outright anyway; Save.lua defaults the field to 1 and
-- Boxes.setCurrent validates every write.  So this is the cart's own mask,
-- not a fix for a reachable state.  What it DOES buy every day is that the
-- storage gate (Ball_BoxIsFullMessage), the box-just-filled test and the
-- insert all ask about the SAME box, so those three can never disagree.
function BattleState:currentBox()
  local save = self.save
  local index = (save and tonumber(save.currentBox)) or 1
  return math.max(1, math.min(Boxes.NUM_BOXES, math.floor(index)))
end

function BattleState:hasPokedex()
  local save = self.save or {}
  return (save.engineFlags or {})[ENGINE_POKEDEX] == true
    or save.pokedexReceived == true
end

-- PokeBallEffect's caught tail, in the cart's order (item_effects.asm:514-676):
-- Text_GotchaMonWasCaught, CheckCaughtMon / SetSeenAndCaughtMon, the new-entry
-- line and NewPokedexEntry, the party add or .SendToPC, then
-- AskGiveNicknameText.
function BattleState:pushCaught(enemy, itemId)
  local save = self.save
  self.battle.over = true
  self.battle.outcome = "caught"
  -- PokeBallEffect's FRIEND_BALL arm: the caught mon's happiness is set to
  -- FRIEND_BALL_HAPPINESS (200) instead of the base 70.  That is the ball's
  -- whole effect; its catch rate is a plain ball's.  It applies on the box
  -- path too (item_effects.asm:620-625).
  if itemId == "FRIEND_BALL" then
    enemy.happiness = Catching.FRIEND_BALL_HAPPINESS
  end
  -- Text_BallCaught ends in `sound_caught_mon` (data/text/common_3.asm:260-266),
  -- and TX_SOUND holds the text engine until the jingle is done
  -- (home/text.asm:834-835), so the line is not dismissable under it.
  self:push({ kind = "message", sfx = SFX_CAUGHT_MON, waitSfx = true,
    text = "Gotcha! " .. self:name(enemy) .. " was caught!" })
  -- BATTLETYPE_TUTORIAL returns before every one of the steps below
  -- (`.FinishTutorial`, and `.return_from_capture: ret z`).
  if self.tutorial or not save then return end
  -- TryAddMonToParty and BugContest_SetCaughtContestMon both end in the same
  -- wPlayerID write (item_effects.asm:548-556, :680; move_mon.asm:143-149).
  Mon.stampOT(save, enemy)
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  -- CheckCaughtMon answers whether this row was ALREADY owned, and it is asked
  -- before SetSeenAndCaughtMon stamps it (item_effects.asm:519-527).  Both run
  -- BEFORE the `.catch_bug_contest_mon` branch, so the dex is marked even
  -- though a contest mon is only being HELD.
  local knew = save.pokedex.caught[enemy.species] and true or false
  save.pokedex.caught[enemy.species] = true
  save.pokedex.seen[enemy.species] = true
  -- NewDexDataText and `predef NewPokedexEntry` both run above `.skip_pokedex`,
  -- so the contest branch is BELOW them (item_effects.asm:528-546), and
  -- CheckReceivedDex gates the pair (:532-533).
  if not knew and self:hasPokedex() then
    -- data/text/common_3.asm:285
    self:push({ kind = "message",
      sfx = "Sfx_SlotMachineStart", waitSfx = true,
      text = self:name(enemy) .. "'s data was newly added to the #DEX." })
    self:push({ kind = "dex-entry", species = enemy.species })
  end
  if self.contest then
    -- A contest catch still exits through the `.run` arm with result WIN
    -- (engine/battle/core.asm:4780-4783), so CheckPayDay runs for it too.
    self:contestCatch(enemy)
    return self:pushPayDay()
  end
  save.party = save.party or {}
  local toPc = #save.party >= Boxes.PARTY_SIZE
  if toPc then
    -- `.SendToPC` / `predef SendMonIntoBox` (item_effects.asm:548-550, 604):
    -- a full party sends the catch to the current box.  Not Boxes.deposit,
    -- which is the PC's own party-to-box move and carries the last-healthy-mon
    -- and mail refusals that have nothing to do with a capture.
    local box = Boxes.box(save, self:currentBox())
    -- SendMonIntoBox inserts at the HEAD: its species loop cascades every
    -- entry one slot further down (move_mon.asm:954-965) and ShiftBoxMon does
    -- the same for the OT names, nicknames and mon structs (:968, :1074-1085),
    -- so the catch lands in slot 1 -- which is what lets the FRIEND_BALL arm
    -- write sBoxMon1Happiness unconditionally ("The captured mon is now first
    -- in the box", item_effects.asm:624).  Boxes.deposit stays an append: the
    -- PC's own move is InsertPokemonIntoBox, which inserts at the cursor.
    table.insert(box, 1, enemy)
    -- SendMonIntoBox refills the boxed slot's PP before it closes SRAM
    -- (move_mon.asm:1062-1063).
    Boxes.restorePP(enemy)
    -- `.SendToPC` re-reads sBoxCount AFTER the insert and sets
    -- BATTLERESULT_BOX_FULL when the box has just filled
    -- (item_effects.asm:612-619); Script_reloadmapafterbattle tests that bit
    -- on the wild arm and rings the player as PHONE_BILL on the first step
    -- back in the overworld (engine/overworld/scripting.asm:1097-1104).
    if Boxes.isFull(save, self:currentBox()) then
      self.battle.boxFilled = true
    end
  else
    save.party[#save.party + 1] = enemy
  end
  -- AddPartyMon's `.registerunowndex` and SendMonIntoBox's `.not_unown` are the
  -- two places the cart appends to wUnownDex, and both are on this path: the
  -- form list is what UNOWN MODE and VAR_UNOWNCOUNT read
  -- (src/core/gen2/Unown.lua).  A contest catch is only HELD, so it returned
  -- above without registering.
  Unown.registerCatch(save, enemy)
  -- Same name and same payload keys as the Gen 1 site
  -- (src/battle/BattleState.lua's pokemon.caught), so one subscription covers
  -- both games: `isNew` is CheckCaughtMon's answer read BEFORE
  -- SetSeenAndCaughtMon stamped it, and `destination` is which of the two
  -- homes PokeBallEffect actually used.  Emitted after the mon is in that
  -- home and after Unown.registerCatch, so a listener reading save.party,
  -- the box or the Unown dex sees the settled state.  A tutorial catch and a
  -- contest catch both returned above without ever owning the mon, which is
  -- why neither reaches this line.
  Runtime.emit("pokemon.caught", {
    battle = self.battle, mon = enemy, species = enemy.species,
    isNew = not knew, ball = itemId,
    destination = toPc and "box" or "party", stored = true, game = self.game,
  })
  self:push({ kind = "ask-nickname", mon = enemy })
  if toPc then
    -- BallSentToPCText, which .SendToPC prints AFTER the nickname prompt
    -- (item_effects.asm:672).
    self:push({ kind = "message",
      text = self:name(enemy) .. " was sent to BILL's PC." })
  end
  self:pushPayDay()
end

-- CheckPayDay runs on a capture too: `and $f` keeps the win arm
-- (engine/battle/core.asm:7971-7976, :8014-8042).
function BattleState:pushPayDay()
  local save = self.save
  local coins = Prize.payDay(save, self.battle.payDay, self.battle.amuletCoin)
  self.battle.payDay = nil
  if coins then
    self:push({ kind = "message",
      text = Prize.payDayMessage(coins, save.player and save.player.name) })
  end
end

-- CheckWhetherToAskSwitch: a started battle, more than one mon, no link, the
-- BATTLE_SHIFT bit CLEAR (which is SHIFT), and the active mon not fainted
-- (engine/battle/core.asm:3269-3295, engine/menus/options_menu.asm:249-256).
function BattleState:shiftOfferAllowed()
  local battle = self.battle
  if not (battle and battle.player and battle.trainer) then return false end
  if #(battle.party or {}) < 2 then return false end
  if (battle.player.hp or 0) <= 0 then return false end
  local options = self.game and self.game.options
  return (options and options.battleStyle or "SHIFT") == "SHIFT"
end

-- OfferSwitch: Battle_GetTrainerName, the prompt, then PlaceYesNoBox
-- (engine/battle/core.asm:3298-3304, data/text/battle.asm:222-231).
function BattleState:offerShiftSwitch(mon)
  self.shiftIndex = 1
  -- HandleEnemySwitch farcalls EnemySwitch_TrainerHud before the prompt
  -- (engine/battle/core.asm:2246, engine/battle/trainer_huds.asm:11-15).
  self.ballRows.enemy = true
  local trainer = (self.battle.trainer and self.battle.trainer.name) or "Foe"
  local player = (self.save and self.save.player and self.save.player.name)
    or "GOLD"
  -- The `para` splits this in two (data/text/battle.asm:222-231): the incoming
  -- mon is NAMED on its own page, and only the second carries the yes/no box.
  self:showPages(Strings(TEXT_ENEMY_ABOUT_TO_USE, trainer, self:name(mon), player))
  self.phase = self.messagePages and "shift-intro" or "ask-shift"
end

function BattleState:answerUseNextMon(yes)
  if yes then
    self.phase = "forced-switch"
    self.message = "Choose a POKéMON."
    return
  end
  local battle = self.battle
  if not battle then
    self.phase = "forced-switch"
    return
  end
  local lead = battle.party and battle.party[1]
  local pSpd = (lead and lead.stats and lead.stats.speed) or 0
  -- engine/battle/core.asm:2614
  if battle:tryRun(pSpd) then
    self:pushAll(battle:takeEvents())
    self.phase = "resolving"
    return self:advanceQueue()
  end
  battle:takeEvents()
  self.message = "Can't escape!"
  self.messageTimer = MESSAGE_FRAMES
  self.phase = "cant-escape-then-switch"
end

-- SetUpBattlePartyMenu + PickSwitchMonInBattle (core.asm:3307-3308), which is
-- PARTYMENUACTION_SWITCH and carries no submenu; a cancel is `.canceled_switch`
-- and answers exactly like NO (:3327).
function BattleState:openShiftParty()
  local stack = self.game and self.game.stack
  if not stack then
    self.phase = "resolving"
    return self:advanceQueue()
  end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2PartyMenu", {
    prompt = "which",
    battle = true,
    onCancel = function()
      stack:pop()
      self.phase = "resolving"
      self:advanceQueue()
    end,
    onChoose = function(index, mon)
      stack:pop()
      if mon == self.battle.player then
        return self:refuseShift(self:name(mon) .. " is already out.")
      end
      if mon.isEgg then return self:refuseShift(TEXT_EGG_CANT_BATTLE) end
      if (mon.hp or 0) <= 0 then return self:refuseShift(nil) end
      self.shiftSwitchIndex = index
      self.phase = "resolving"
      self:advanceQueue()
    end,
  })
end

-- PickSwitchMonInBattle loops on carry the way BattleMenuPKMN_Loop does
-- (engine/battle/core.asm:2716-2728).
function BattleState:refuseShift(text)
  self.phase = "refuse-shift"
  self.message = text or TEXT_NO_WILL_TO_FIGHT
  self.messageTimer = MESSAGE_FRAMES
end

-- AskGiveNicknameText + YesNoBox (item_effects.asm:566-578).  B is the NO arm
-- (`jp c, .return_from_capture`), which leaves the species name standing.
function BattleState:askNickname(mon)
  self.nicknameMon = mon
  -- YesNoBox opens on YES; YesNoMenuHeader sets no STATICMENU_DISABLE_B.
  self.nicknameIndex = 1
  self.phase = "ask-nickname"
  self.message = "Give a nickname to " .. self:name(mon) .. "?"
  self.messageTimer = MESSAGE_FRAMES
end

-- One prompt page in the box, with the rest held for the presses `para` and
-- `cont` wait on (home/text.asm:403-448).
function BattleState:showPages(text)
  local pages = paginate(text)
  self.messagePages = #pages > 1 and pages or nil
  self.messagePage = 1
  self.message = pages[1]
  self.messageTimer = MESSAGE_FRAMES
end

function BattleState:nextPage()
  local pages = self.messagePages
  if not pages then return false end
  local i = self.messagePage + 1
  self.messagePage = i
  self.message = pages[i]
  self.messageTimer = MESSAGE_FRAMES
  if i >= #pages then self.messagePages = nil end
  return true
end

-- ForgetMove's AskForgetMoveText + YesNoBox (engine/pokemon/learn.asm:123-127);
-- LearnMove's `jp c, .loop` reprints the whole text, so this is the loop head.
function BattleState:askForget()
  if not self.pendingLearn then return self:advanceQueue() end
  self.forgetIndex = 1
  self.forgetChoice = 1
  local party = (self.battle and self.battle.party) or {}
  local name = self:name(party[self.pendingLearn.index])
  local moveName = self.pendingLearn.moveName or "?"
  self:showPages(Strings(TEXT_ASK_FORGET_MOVE, name, moveName, name, moveName))
  self.phase = self.messagePages and "learn-intro" or "ask-forget"
end

-- LearnMove's .cancel: StopLearningMoveText, and a NO is `jp c, .loop`
-- (engine/pokemon/learn.asm:104-108).
function BattleState:askStopLearning()
  if not self.pendingLearn then return self:advanceQueue() end
  self.forgetChoice = 1
  self.phase = "stop-learning"
  self:showPages(Strings(TEXT_STOP_LEARNING, self.pendingLearn.moveName or "?"))
end

-- DidNotLearnMoveText, then `ld b, 0` and back to the queue (learn.asm:110-113).
function BattleState:finishDecline()
  local learn = self.pendingLearn
  self.pendingLearn = nil
  self.phase = "resolving"
  if learn then self.battle:declineForget(learn.index, learn.moveName) end
  self:pushFront(self.battle:takeEvents())
  self:advanceQueue()
end

function BattleState:answerForgetPrompt(yes)
  if self.phase == "ask-forget" then
    if not yes then return self:askStopLearning() end
    -- MoveAskForgetText over the four-slot list (learn.asm:135-146).
    self.forgetIndex = 1
    self.phase = "choose-forget"
    self.message = Strings(TEXT_ASK_FORGET_SLOT)
    self.messageTimer = 0
    return
  end
  if yes then return self:finishDecline() end
  return self:askForget()
end

function BattleState:answerNickname(yes)
  local mon = self.nicknameMon
  self.nicknameMon = nil
  self.phase = "resolving"
  local stack = self.game and self.game.stack
  if not (yes and mon and stack) then return self:advanceQueue() end
  self.phase = "submenu"
  local data = (self.game and self.game.data) or {}
  local icons = data.gen2Icons
  local iconId = icons and icons.species and icons.species[mon.species]
  local entry = iconId and icons.icons and icons.icons[iconId]
  local done = function(name)
    stack:pop()
    -- InitName: an empty entry keeps whatever was already in the buffer, which
    -- for a fresh capture is the species name.
    if name and #name > 0 then mon.nickname = name end
    self.phase = "resolving"
    self:advanceQueue()
  end
  Screens.push(self.game, "Gen2NamingScreen", {
    type = "nickname",
    monName = mon.name or mon.species,
    iconPath = entry and entry.image or nil,
    menuGfx = data.gen2MenuGfx,
    onDone = done,
    onCancel = function() done(nil) end,
  })
end

-- BugContest_SetCaughtContestMon (engine/events/bug_contest/caught_mon.asm).
-- With nothing in stock the catch is kept outright (`.firstcatch`); with a mon
-- already in stock the player is shown the comparison and asked, and the NO arm
-- -- which is also what B does -- keeps the mon they already had.
function BattleState:contestCatch(mon)
  local kind, stock, fresh = BugContest.catch(self.save, mon)
  if kind ~= BugContest.ASK_SWITCH then
    self:push({ kind = "message", text = "Caught " .. self:name(mon) .. "!" })
    return
  end
  self:push({ kind = "message",
    text = "You already caught a " .. self:name(stock) .. "." })
  self:push({ kind = "contest-switch", stock = stock, caught = fresh })
end

function BattleState:openContestSwitch(event)
  local stack = self.game and self.game.stack
  if not stack then return self:advanceQueue() end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2ContestMenu", {
    save = self.save,
    stock = event.stock,
    caught = event.caught,
    onClose = function()
      stack:pop()
      self.phase = "resolving"
      self:advanceQueue()
    end,
  })
end

-- NewPokedexEntry: the dex opens straight on the new species' entry and pages
-- twice (engine/pokedex/new_pokedex_entry.asm:19-23).
function BattleState:openDexEntry(species)
  local stack = self.game and self.game.stack
  local dex = ((self.game and self.game.data) or {}).gen2Pokedex
  local entry = dex and dex.entries and dex.entries[species]
  if not (stack and entry) then return self:advanceQueue() end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2PokedexMenu", {
    entrySpecies = species,
    newEntry = true,
    onClose = function()
      stack:pop()
      self.phase = "resolving"
      self:advanceQueue()
    end,
  })
end

function BattleState:catchOptions(itemId)
  local data = self.game and self.game.data or {}
  local battle = self.battle
  local enemy = battle and battle.enemy
  if not enemy then return nil end
  local enemyDef = data.pokemon and data.pokemon[enemy.species]
  local dexEntry = data.gen2Pokedex and data.gen2Pokedex[enemy.species]
  local evolveItem
  for _, entry in ipairs((enemyDef and enemyDef.evolutions) or {}) do
    if entry.method == "EVOLVE_ITEM" then evolveItem = entry.item end
  end
  local player = battle.player
  return {
    battle = battle, mon = enemy, def = enemyDef,
    maxHp = enemy.maxHp or (enemy.stats and enemy.stats.hp), hp = enemy.hp,
    catchRate = enemyDef and enemyDef.catchRate or 45, ball = itemId,
    status = enemy.status, random = battle.random,
    weight = dexEntry and dexEntry.weight, level = enemy.level,
    playerLevel = player and player.level,
    fishing = battle.battleType == "fish", species = enemy.species,
    gender = enemy.gender, playerSpecies = player and player.species,
    playerGender = player and player.gender, evolveItem = evolveItem,
  }
end

function BattleState:catchChance(itemId)
  if self.tutorial then return 100 end
  local opts = self:catchOptions(itemId)
  return opts and Catching.chance(opts) or nil
end

-- Items in battle: balls try a catch, the stat items apply their stage, and
-- everything with a ported party effect runs the same item_effects.asm routine
-- the field pack runs.  Anything else reports that it cannot be used, which is
-- what the cart does for a key item.
function BattleState:useItem(itemId)
  local data = self.game and self.game.data or {}
  local def = data.items and data.items[itemId]
  local pocket = def and def.pocket
  local save = self.save

  if pocket == "BALL" then
    -- `ld a, [wBattleMode] / dec a / jp nz, UseBallInTrainerBattle`, the very
    -- first thing PokeBallEffect does.
    if not self.battle.wild then
      return self:throwBallAtTrainer(itemId)
    end
    -- The storage gate, before the ball is spent and before the rate is
    -- computed (item_effects.asm:217-226): a full party AND a full current box
    -- takes Ball_BoxIsFullMessage, which writes wItemEffectSucceeded = 2 --
    -- "item wasn't used" -- so neither the ball nor the turn goes.
    if #((save and save.party) or {}) >= Boxes.PARTY_SIZE
        and Boxes.isFull(save, self:currentBox()) then
      -- BallBoxFullText (data/text/common_3.asm:427).
      self.message = "The POKéMON BOX is full. That can't be used now."
      self.messageTimer = MESSAGE_FRAMES
      self.phase = "resolving"
      return
    end
    local enemy = self.battle.enemy
    local caught, rate
    if self.tutorial then
      -- `ld a, [wBattleType] / cp BATTLETYPE_TUTORIAL /
      -- jp z, .catch_without_fail`, checked BEFORE the Master Ball and before
      -- the rate is ever computed.  The tail then returns early for a tutorial
      -- battle (`.return_from_capture: ret z`), which is why the DUDE's
      -- RATTATA is not added to a party, not written to the Pokedex and not
      -- registered in wUnownDex, and why the ball is not tossed out of the
      -- bag: the bag it came from was never the player's.  The THROW still
      -- happens: `.catch_without_fail` falls into the shared animation.
      caught, rate = true, 255
    else
      -- The specialty-ball conditions (BallMultiplierFunctionTable): each one
      -- is also used by the read-only preview, so both paths stay exact.
      caught, rate = Catching.attempt(self:catchOptions(itemId))
    end
    -- wWildMon carries the answer through the animation, and
    -- wThrownBallWobbleCount is the counter GetPokeBallWobble bumps once per
    -- wobble -- which is what the failure line is picked from afterwards.
    self.ballThrow = { caught = caught, rate = rate or 0, wobble = 0 }
    -- A PARK BALL is never in the bag: PokeBallEffect's `.used_park_ball` does
    -- `dec [hl]` on wParkBallsRemaining instead of tossing an item, so the
    -- contest takes its ball off the counter and leaves the pack alone.  The
    -- tutorial spends nothing at all (`.return_from_capture: ret z`).
    if not self.tutorial then
      if self.contest then
        if not caught then BugContest.useBall(save) end
      else
        self:consumeItem(itemId)
      end
    end
    self.queue = {}
    if caught then
      self:pushCaught(enemy, itemId)
    else
      -- Resolved at drain time, because which of the four lines it is depends
      -- on how far the wobble counter got inside the animation.
      self:push({ kind = "ball-result" })
      -- A failed ball still costs the turn.
      self:pushAll(self.battle:takeTurn({ kind = "item", item = itemId }))
      -- CheckContestBattleOver: the throw that empties the counter turns the
      -- battle into a DRAW there and then, which is what sends the player back
      -- to the gate instead of into the next patch of grass.
      if self.contest and BugContest.isOver(save) then
        self.battle.over = true
        self.battle.outcome = "draw"
      end
    end
    -- item_effects.asm:405-412: wBattleAnimParam from wCurItem, hBattleTurn 0,
    -- wThrownBallWobbleCount 0, then `predef PlayBattleAnim`.  Everything
    -- pushed above is drained only once the ball has finished wobbling.
    self:startBallAnim(self:ballAnimParam(itemId), itemId)
    if caught and not self.anim then self.picHidden.enemy = true end
    self.message = nil
    self.messageTimer = 0
    self.phase = "resolving"
    if not self.anim then self:advanceQueue() end
    return
  end

  -- The battle stat items (XItemEffect, XAccuracyEffect, DireHitEffect,
  -- GuardSpecEffect): the engine applies the stage or the substatus bit and
  -- this side spends the item and the turn.  A refused re-use
  -- (WontHaveAnyEffect_NotUsedMessage) costs neither.
  if Battle.X_ITEM_STATS[itemId] or Battle.SUBSTATUS_ITEMS[itemId] then
    local ok = self.battle:useBattleItem(itemId)
    if not ok then
      -- _ItemWontHaveEffectText's own `line` break, the same one
      -- ItemEffects.TEXT_NO_EFFECT carries (data/text/common_3.asm).
      self.message = ItemEffects.TEXT_NO_EFFECT
      self.messageTimer = MESSAGE_FRAMES
      self.phase = "resolving"
      return
    end
    if save and save.inventory then
      save.inventory[itemId] = math.max(0, (save.inventory[itemId] or 1) - 1)
      if save.inventory[itemId] == 0 then save.inventory[itemId] = nil end
    end
    self.queue = {}
    self:pushAll(self.battle:takeEvents())
    self:pushAll(self.battle:takeTurn({ kind = "item", item = itemId }))
    self.phase = "resolving"
    self:advanceQueue()
    return
  end

  -- BattlePack's .ItemFunctionJumptable (engine/items/pack.asm): its first
  -- four entries are all .Oak, so an item that is ITEMMENU_NOUSE in a battle
  -- does nothing there at all.  The gate has to sit here rather than in the
  -- pack, because the battle pack has no field-menu filter of its own and the
  -- two nibbles disagree: a RARE CANDY is ITEMMENU_PARTY in the FIELD and
  -- would otherwise level a mon mid-fight, and a BITTER BERRY is the reverse.
  if not (def and def.battleMenu == "ITEMMENU_NOUSE") then
    -- BitterBerryEffect: its whole effect is a battle substatus, so it has no
    -- field row for src/core/gen2/ItemEffects.lua to carry and it never opens
    -- the party list.
    if itemId == "BITTER_BERRY" then
      return self:cureBattleConfusion(itemId)
    end
    -- Everything else the pack can spend on a party mon runs the same
    -- item_effects.asm routine the field pack runs: the potion line and the
    -- drinks, the status cures and their berries, REVIVE / MAX REVIVE, and
    -- the ETHER / ELIXER family.  Without the merged dataset this can only
    -- ever see RECORDS, the module's own built-ins, the same gap
    -- Game2:usePartyItem had for the field pack.
    local action = ItemEffects.partyAction(itemId, self.game and self.game.data)
    if action then
      return self:useOnPartyMon(itemId, action)
    end
  end

  self.message = "That isn't going to help here."
  self.messageTimer = MESSAGE_FRAMES
  self.phase = "resolving"
end

-- UseItem_SelectMon (engine/items/item_effects.asm): every party-target item
-- picks its mon FIRST, so a benched mon can be healed, cured or stood back up
-- mid-battle -- ItemRestoreHP, StatusHealingEffect, ReviveEffect and
-- RestorePPEffect all open the list before they do anything.  Backing out is
-- the .SelectMon carry path: back to the pack with nothing spent.
function BattleState:useOnPartyMon(itemId, action)
  local stack = self.game and self.game.stack
  if not stack then
    return self:applyPartyItem(itemId, action, self.battle.player)
  end
  self.phase = "submenu"
  Screens.push(self.game, "Gen2PartyMenu", {
    prompt = "useItem",
    battle = true,
    party = self.battle.party or (self.save and self.save.party),
    onCancel = function()
      stack:pop()
      self:openPack()
    end,
    onChoose = function(_, mon)
      -- RestorePPEffect: the ETHER pair needs the move pick first, the ELIXER
      -- pair walks every slot without one, and an EGG refuses before the move
      -- list ever opens (UseItem_SelectMon's `cp EGG`).
      local row = (action == "pp") and ItemEffects.RESTORE_PP[itemId] or nil
      if row and not row.each and mon and not mon.isEgg then
        return self:pickMoveForItem(itemId, mon)
      end
      stack:pop()
      self:applyPartyItem(itemId, action, mon)
    end,
  })
end

-- RestorePPEffect's "Restore the PP of which move?" pick.  MoveSelectionScreen
-- and ChooseMoveToDelete are the same SetUpMoveList box on the cart, so the
-- port serves both with src/ui/gen2/MoveDeleter.lua.  Backing out drops only
-- the move list and leaves the party list standing, which is the routine's own
-- `jr nz, .loop`.
function BattleState:pickMoveForItem(itemId, mon)
  local stack = self.game.stack
  Screens.push(self.game, "Gen2MoveDeleter", {
    mon = mon,
    moves = self.game.data and self.game.data.moves,
    onCancel = function() stack:pop() end,
    onChoose = function(slot)
      stack:pop() -- the move list
      stack:pop() -- the party list
      self:applyPartyItem(itemId, "pp", mon, slot)
    end,
  })
end

-- BitterBerryEffect: it reads wPlayerSubStatus3 straight off, so it acts on
-- whoever is out and a mon that is not confused refuses without spending
-- anything.  UseItemText falls through into UseDisposableItem, so a cure does
-- cost the berry.
function BattleState:cureBattleConfusion(itemId)
  local mon = self.battle.player
  local state = mon and self.battle:volatile(mon)
  if not (state and state.confuseCount) then
    self.message = oneLine(ItemEffects.TEXT_NO_EFFECT)
    self.messageTimer = MESSAGE_FRAMES
    self.phase = "resolving"
    return
  end
  state.confuseCount = nil
  self:consumeItem(itemId)
  self.queue = {}
  -- ConfusedNoMoreText (data/text/battle.asm).
  self:push({ kind = "message",
    text = self:name(mon) .. "'s confused no more!" })
  self:pushAll(self.battle:takeTurn({ kind = "item", item = itemId }))
  self.phase = "resolving"
  self:advanceQueue()
end

-- UseDisposableItem: one copy leaves the pack, and only on a success -- every
-- refusal above returns before this.
function BattleState:consumeItem(itemId)
  local save = self.save
  if not (save and save.inventory) then return end
  save.inventory[itemId] = math.max(0, (save.inventory[itemId] or 1) - 1)
  if save.inventory[itemId] == 0 then save.inventory[itemId] = nil end
end

-- The effect itself.  ItemEffects owns the item_effects.asm arithmetic and
-- every refusal it prints (an EGG, a fainted or full-HP heal target, a healthy
-- revive target, a PP slot already full); this side adds the arm that only
-- exists with a battle up, spends the item where UseDisposableItem sits, and
-- pays the turn the pack costs.
function BattleState:applyPartyItem(itemId, action, mon, slot)
  local data = (self.game and self.game.data) or {}
  local before = (mon and mon.hp) or 0
  local result
  if action == "pp" then
    result = ItemEffects.usePpItem(itemId, mon, slot, data)
  else
    result = ItemEffects.useOnMon(itemId, mon, data)
  end
  -- HealStatus's `.not_full_heal` and IsItemUsedOnConfusedMon: a $ff-mask item
  -- used on whoever is OUT also clears SUBSTATUS_CONFUSED, and clears it even
  -- when the status byte was already empty -- which is the one case where a
  -- FULL HEAL that the field routine refuses is still spent in battle.
  if mon and FULL_MASK_HEALERS[itemId] and mon == self.battle.player
      and self.battle:volatile(mon).confuseCount then
    self.battle:volatile(mon).confuseCount = nil
    if not result.used then
      -- PARTYMENUTEXT_HEAL_CONFUSION (_CameToItsSensesText).
      result = { used = true,
        text = self:name(mon) .. " came to its senses." }
    end
  end
  if not result.used then
    self.message = oneLine(result.text)
    self.messageTimer = MESSAGE_FRAMES
    self.phase = "resolving"
    return
  end
  self:consumeItem(itemId)
  self.queue = {}
  if mon == self.battle.player and (mon.hp or 0) ~= before then
    -- Every HP-restoring effect zeroes wLowHealthAlarm BEFORE it touches the
    -- HP or runs HealHP_SFX_GFX (RestoreHPEffect, engine/items/item_effects.asm:
    -- 1657-1658; .FullRestore :1580-1581; .skip_to_revive :1542-1543), so the
    -- siren dies with the item rather than with the bar animation -- the bar
    -- is still in the red for the whole climb.  Not a latch: CheckDanger runs
    -- again from UpdatePlayerHUD once AnimateHPBar has finished, so a heal
    -- that leaves the mon in the red correctly starts the siren back up.
    self:stopAlarm()
    self.healSilence = true
    -- The active mon's HP change carries its new value so the HUD bar refills
    -- on screen (HealHP_SFX_GFX runs AnimateHPBar for exactly this case).
    self:push({ kind = "heal", side = "player", hp = mon.hp,
      text = oneLine(result.text) })
  else
    self:push({ kind = "message", text = oneLine(result.text) })
  end
  self:pushAll(self.battle:takeTurn({ kind = "item", item = itemId }))
  self.phase = "resolving"
  self:advanceQueue()
end

-- The HUD is not a box: engine/battle/core.asm draws an L-shaped frame out of
-- four tiles (DrawEnemyHUDBorder / DrawPlayerHUDBorder) -- a horizontal rule
-- under the whole thing with a short vertical stub at one end, opening left for
-- the enemy and right for the player.  Name and level sit on plain background
-- above it, not inside a border.
function BattleState:drawFrame(tx, ty, width, stubRight)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  -- The bottom rule ($76 repeated, capped by $74/$78 or $6f/$77) sits at the
  -- top of its own tile row, immediately under the bar above it.
  G.rectangle("fill", tx * 8, ty * 8, width * 8, 2)
  -- The vertical stub ($6d on the enemy's left, $73 on the player's right)
  -- climbs from the rule past the bar row.
  local stubX = stubRight and ((tx + width - 2) * 8 + 6) or (tx * 8)
  G.rectangle("fill", stubX, ty * 8 - 8, 2, 10)
end

-- LoadBattleFontsHPBar puts FontBattleExtra in the $60 slot for the whole
-- battle, which is why the HUD's level reads as the bold ":L" glyph ($6e) and
-- not the two characters ':' and 'L'.  The message box below is ordinary text,
-- so the swap is scoped to the HUD.
-- Which mon a side DRAWS.  Battle finishes the whole turn before the first
-- message is displayed, so battle.enemy is already the replacement while the
-- outgoing mon's "fainted!" line is still on screen; the queue's own copy is
-- what keeps the pic and the name where the cart has them.
function BattleState:activeMon(side)
  local shown = self.shownMon and self.shownMon[side]
  if shown ~= nil then return shown end
  return self.battle and self.battle[side] or nil
end

function BattleState:drawHud()
  local wasBattle = Font.useBattleExtra(true)
  local enemy, player = self:activeMon("enemy"), self:activeMon("player")
  local showStatus = self:statusHUDVisible()

  -- Enemy HUD (DrawEnemyHUD clears (1,0) 4 rows x 11 cols):
  --   name at (1,0); PrintLevel at (6,1) with the gender symbol at (9,1);
  --   the HP bar's "HP:" at (2,2); the border from (1,2).
  -- ClearActorHud blanks this whole block while that side's move animation
  -- runs, so a shake or a slide does not drag the HP bar with it.
  -- And nothing at all before UpdateEnemyHUD has ever run: the intro bands
  -- slide in over a blanked tilemap (core.asm:8554/8564).
  if showStatus and self.showEnemyHud and not self:hudCleared("enemy") then
  Chrome.print(self:name(enemy), 1, 0)
  -- PrintLevel writes <LV> at the coordinate it is given and then LEFT-aligns
  -- the digits after it, so the glyph is pinned to column 6 whether the level
  -- is 5 or 100; only a three-digit level moves, and it does so by eating the
  -- <LV> tile.  The gender symbol sits past the two digit columns, at (9,1).
  -- PlaceNonFaintStatus (engine/pokemon/mon_stats.asm): a statused mon's tag
  -- prints where the level goes, and DrawEnemyHUD's `.skip_level` arm drops
  -- the level entirely while one is up.
  Chrome.print(self:statusTag(enemy, "enemy")
    or ("<LV>" .. tostring(enemy.level or 1)), 6, 1)
  local enemyGender = self:genderSymbol(enemy)
  if enemyGender then Chrome.print(enemyGender, 9, 1) end
  -- `ld a, [wBattleMode] / dec a / ret nz`, then CheckCaughtMon puts $5d at
  -- (1,1) (engine/battle/trainer_huds.asm:140-152).
  if self.battle and self.battle.wild and self.caughtMark then
    self.hud:drawCaughtIcon(1, 1, self:hudHp(enemy, "enemy"),
      enemy.maxHp or (enemy.stats and enemy.stats.hp))
  end
  self:drawHpBar(enemy, "enemy", 2, 2)
  -- Stub on the LEFT (tile $6d), rule on the row under the bar.
  if self.hud:available() then
    self.hud:drawEnemyFrame()
  else
    self:drawFrame(1, 3, 10, false)
  end
  end
  -- ShowOTTrainerMonsRemaining (engine/battle/trainer_huds.asm:32-45): balls
  -- walking LEFT from OAM (72, 32), which the -8/-16 offset puts at (8, 2).
  if showStatus and self.ballRows.enemy then
    if not self.showEnemyHud and self.hud:available() then
      self.hud:drawEnemyFrame()
    end
    self.hud:drawBallRow(self.battle and self.battle.enemyParty, 8, 2, -1)
  end

  self:drawPic(enemy, false)

  -- Player HUD (DrawPlayerHUD clears (9,7) 5 rows x 11 cols):
  --   name at (10,7); PrintLevel at (14,8) with the gender at (17,8);
  --   the HP bar at (10,9), its numbers below; the vertical bar at (18,9), the
  --   border from (18,10) going left, and the exp bar at (10,11).
  self:drawPic(player, true)
  -- ShowPlayerMonsRemaining (engine/battle/trainer_huds.asm:17-30): balls
  -- walking RIGHT from OAM (96, 96), i.e. tile (11, 10).
  if showStatus and self.ballRows.player then
    if not self.showPlayerHud and self.hud:available() then
      self.hud:drawPartyIconFrame()
    end
    self.hud:drawBallRow(self.battle and self.battle.party, 11, 10, 1)
  end
  -- No player HUD in the catching tutorial: DrawPlayerHUD lives in
  -- SendOutPlayerMon, which BATTLETYPE_TUTORIAL jumps straight over, and
  -- BattleMenu's own tutorial arm skips UpdateBattleHuds as well.  The DUDE's
  -- half of the screen is his back-pic and nothing more.
  -- Nor before SendOutPlayerMon's own UpdatePlayerHUD (core.asm:3838).
  if not showStatus or not player or not self.showPlayerHud
      or self:hudCleared("player") then
    Font.useBattleExtra(wasBattle)
    return
  end
  Chrome.print(self:name(player), 10, 7)
  -- PrintPlayerHUD places the same status tag at (14,8) and skips the level
  -- while it is up.
  Chrome.print(self:statusTag(player, "player")
    or ("<LV>" .. tostring(self.shownLevel or player.level or 1)), 14, 8)
  local playerGender = self:genderSymbol(player)
  if playerGender then Chrome.print(playerGender, 17, 8) end
  self:drawHpBar(player, "player", 10, 9)
  local maxHp = player.maxHp or (player.stats and player.stats.hp) or 0
  Chrome.printRight(("%d/%d"):format(self:hudHp(player, "player"), maxHp),
    18, 10)
  -- Stub on the RIGHT (tile $73), border from (18,10) laid leftward, exp bar
  -- at (10,11).
  -- The chased fill, not the mon's: AnimateExpBar crawls it, and reading the
  -- mon straight put the bar at its post-kill value before the "gained N EXP.
  -- Points!" line was even on screen.
  local expFraction = (self.shownExp or 0) / BattleHud.EXP_LENGTH_PX
  if self.hud:available() then
    self.hud:drawPlayerFrame()
    -- Eight tiles at (10,11); FillInExpBar's own span.
    self.hud:drawExpBar(expFraction, 10, 11)
  else
    self:drawFrame(9, 11, 10, true)
    HpBar.drawExp(self.palettes, expFraction, 10 * 8, 11 * 8 + 4)
  end
  Font.useBattleExtra(wasBattle)
end

-- PlaceNonFaintStatus's five strings, checked in its own priority order
-- (PSN, BRN, FRZ, PAR, SLP).  Toxic is the PSN bit worn harder, so it shares
-- the tag; confusion is a substatus on the cart and never reaches the HUD.
local STATUS_TAGS = {
  poison = "PSN", toxic = "PSN", burn = "BRN", freeze = "FRZ",
  paralyze = "PAR", sleep = "SLP",
}

function BattleState:statusTag(mon, side)
  return mon and STATUS_TAGS[self:hudStatus(mon, side)] or nil
end

-- ♂ / ♀ after the level, or nil for a genderless species (PrintPlayerHUD
-- writes a plain space in that case).
function BattleState:genderSymbol(mon)
  local gender = mon and mon.gender
  if gender == "male" then return "\xe2\x99\x82" end
  if gender == "female" then return "\xe2\x99\x80" end
  return nil
end

-- The growth record for a mon's species, for the exp bar's "how far to the next
-- level" fraction.
function BattleState:growthOf(mon)
  local def = self.pokemon and mon and self.pokemon[mon.species]
  if not def then return nil end
  -- Mon.growthFor off the LIVE game.data, so the exp bar's fraction is drawn
  -- against the very curve Mon.gainExperience just used; a mod-registered
  -- curve must not leave the bar disagreeing with the level it reports.  The
  -- {pokemon=} fallback is for a screen built with no game (drivers, tests),
  -- where there is no merged registry to find anyway.
  local data = (self.game and self.game.data) or { pokemon = self.pokemon }
  return Mon.growthFor(data, def.growthRate)
end

-- The four labels the battle menu draws.  Inside the contest the third one
-- carries the park ball count, which .PrintParkBallsRemaining writes with
-- PRINTNUM_LEADINGZEROS over two digits.
function BattleState:menuLabels()
  if not self.contest then return MENU end
  return { MENU[1], MENU[2],
    CONTEST_BALL_LABEL .. ("%02d"):format(BugContest.ballsLeft(self.save)),
    MENU[4] }
end

-- The message on the cart's own two rows: 14 and 16, with 15 blank between
-- them (home/text.asm:143 and :397).  A string that will not fit two 18-tile
-- lines is cut rather than spilling onto the rows Paragraph clears.
function BattleState:printMessage()
  local lines = Chrome.wrap(self.message or "", TEXT_WIDTH)
  for i = 1, math.min(#lines, TEXT_ROWS) do
    Chrome.print(lines[i], TEXT_INNER_X,
      TEXT_INNER_Y + (i - 1) * TEXT_ROW_STEP)
  end
end

-- MoveInfoBox (engine/battle/core.asm:5403-5478): "TYPE/" at (1,9), the type
-- at (2,10), cur/max PP at (5,11), or "Disabled!" at (1,10).
function BattleState:drawMoveInfoBox(move)
  if not move then return end
  local fighter = self.battle and self.battle.player
  if fighter and self.battle:moveDisabled(fighter, move.id) then
    Chrome.print("Disabled!", 1, 10)
    return
  end
  local def = self.game and self.game.data and self.game.data.moves
    and self.game.data.moves[move.id]
  Chrome.print("TYPE/", 1, 9)
  local moveType = def and def.type
  Chrome.print(moveType and (TYPE_NAMES[moveType] or moveType) or "", 2, 10)
  Chrome.print(("%2d/%2d"):format(move.pp or 0, move.maxPp or 0), 5, 11)
end

function BattleState:drawPanel()
  Chrome.clear()
  -- A tutorial battle legitimately has no player mon, so only the enemy is
  -- required there; everywhere else a missing side is a caller bug.
  local hasPlayer = self.battle and (self.battle.player or self.tutorial)
  if not (self.battle and hasPlayer and self.battle.enemy) then
    Chrome.print("NO BATTLE", 1, 1)
    return
  end
  self:drawHud()

  if not self:bottomUIVisible() then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- Message box across the bottom, with the menu window over its right half --
  -- the cart draws the prompt into the full-width box and then opens the menu
  -- on top, so the tail of a long name is simply covered.
  -- MoveSelectionScreen type 0 is two boxes: the name-only list
  -- (engine/battle/core.asm:5074-5084) and MoveInfoBox's (:5407-5410).
  local moveMenu = self.phase == "moves"
  Chrome.box(0, 12, 20, 6)
  if moveMenu then
    -- List box first (core.asm:5074-5084), MoveInfoBox on top (:5157).
    Chrome.box(4, 12, 16, 6)
    Chrome.box(0, 8, 11, 5)
  end
  if self.phase == "menu" then
    self:printMessage()
    local boxX = self.contest and CONTEST_MENU_BOX_X or MENU_BOX_X
    local spacing = self.contest and CONTEST_MENU_COL_SPACING
      or MENU_COL_SPACING
    Chrome.box(boxX, 12, 20 - boxX, 6)
    for i, label in ipairs(self:menuLabels()) do
      local col = ((i - 1) % 2) * spacing
      local row = math.floor((i - 1) / 2) * 2
      local tx, ty = boxX + 2 + col, 14 + row
      if i == self.menuIndex then Chrome.cursor(tx - 1, ty) end
      Chrome.print(label, tx, ty)
    end
  elseif self.phase == "moves"
      or (self.phase == "choose-forget" and (self.messageTimer or 0) <= 0) then
    -- The forget picker shows the SAME four moves, cursored by forgetIndex --
    -- pick one to drop for the pending move.
    local forgetting = self.phase == "choose-forget"
    local moves = self:playerMoves()
    if forgetting then
      local learn = self.pendingLearn
      local mon = learn and self.battle.party[learn.index]
      moves = (mon and mon.moves) or moves
    end
    local cursorRow = forgetting and self.forgetIndex or self.moveIndex
    -- w2DMenuCursorInitX 5 with the names at hlcoord 6 (core.asm:5086-5107).
    local cursorCol = moveMenu and 5 or 1
    local nameCol = moveMenu and 6 or 2
    for i, move in ipairs(moves) do
      local ty = 13 + (i - 1)
      -- Cursor in the box's own gutter, not clipped against the border.
      if i == cursorRow then Chrome.cursor(cursorCol, ty) end
      -- The held slot's marker.  `.battle_player_moves` writes '▷' into the
      -- row wSwappingMove names (engine/battle/core.asm:5157-5165) so a move
      -- picked up for a swap is visible while the cursor moves off it.  It
      -- hlcoord 5, 13 is the cursor's own gutter, so PlaceMenuCursor covers
      -- the marker on the cursor's row.
      if not forgetting and self.moveSwapIndex == i and i ~= cursorRow then
        Chrome.print("\u{25B7}", cursorCol, ty)
      end
      local def = self.game and self.game.data and self.game.data.moves
        and self.game.data.moves[move.id]
      Chrome.print((def and def.name) or move.id, nameCol, ty)
      if not moveMenu then
        Chrome.printRight(("%d/%d"):format(move.pp or 0, move.maxPp or 0),
          19, ty)
      end
    end
    if moveMenu then self:drawMoveInfoBox(moves[cursorRow]) end
  else
    -- Battle messages wrap inside the box rather than running off the frame.
    self:printMessage()
    -- YesNoBox: `lb bc, SCREEN_WIDTH - 6, 7`, a 6x5 box at (14,7) with YES at
    -- (16,8) and NO at (16,10), drawn over the battle while the question
    -- stands.
    local asking = self.phase == "ask-nickname" or self.phase == "ask-forget"
      or self.phase == "stop-learning" or self.phase == "ask-shift"
      or self.phase == "ask-next-mon"
    if asking and (self.messageTimer or 0) <= 0 then
      -- OfferSwitch calls PlaceYesNoBox with `lb bc, 1, 7`, so its box is at
      -- (1,7) instead (engine/battle/core.asm:3303, home/menu.asm:392-410).
      local left = (self.phase == "ask-shift" or self.phase == "ask-next-mon")
        and 1 or 14
      Chrome.box(left, 7, 6, 5)
      Chrome.print("YES", left + 2, 8)
      Chrome.print("NO", left + 2, 10)
      local index = self.phase == "ask-nickname" and self.nicknameIndex
        or self.phase == "ask-shift" and self.shiftIndex
        or self.phase == "ask-next-mon" and self.nextMonIndex
        or self.forgetChoice
      Chrome.cursor(left + 1, index == 1 and 8 or 10)
    end
  end
  if self.phase == "stats-box" and self.statsBoxMon then
    self:drawStatsBox(self.statsBoxMon)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokegold engine/pokemon/mon_stats.asm:118-124 (PrintTempMonStats.StatNames).
local STATS_BOX_ROWS = {
  { "ATTACK", "attack" }, { "DEFENSE", "defense" },
  { "SPCL.ATK", "specialAttack" }, { "SPCL.DEF", "specialDefense" },
  { "SPEED", "speed" },
}

-- pokegold engine/battle/core.asm:7060-7066 (box at hlcoord 9,0, stats at 11,y).
function BattleState:drawStatsBox(mon)
  if not mon then return end
  local stats = mon.stats
  local data = self.game and self.game.data
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def and def.baseStats then
    stats = Mon.stats(def.baseStats, mon.dvs, mon.level, mon.statExp)
  end
  if not stats then return end
  Chrome.textbox(9, 0, 9, 10)
  for i, row in ipairs(STATS_BOX_ROWS) do
    local ty = 1 + (i - 1) * 2
    Chrome.print(Strings(row[1]), 11, ty)
    Chrome.printRight(("%d"):format(stats[row[2]] or 0), 19, ty + 1)
  end
end

-- The BG layer, plus whatever the animation is doing to it, plus the OBJ
-- layer on top.  OBJs are not affected by SCX/SCY, which is why they are drawn
-- after the scanline blit rather than into the canvas with everything else.
function BattleState:drawScene()
  self:drawSceneBody()
  -- battle.overlay: shiny sparkles, custom HUD chrome, and so on.  Draw-only,
  -- and the same name, the same payload (the battle screen) and the same place
  -- in the frame as the Gen 1 site (src/battle/BattleState.lua's draw tail):
  -- after everything the scene composites, in the 160x144 space, so a mod
  -- draws in screen coordinates whichever game it is under.  The vanilla link
  -- is a no-op, so an empty chain costs one wantsHook.
  if Runtime.wantsHook("battle.overlay") then
    Runtime.call("battle.overlay", function() end, self)
  end
end

-- data/battle_anims/objects.asm:390-397: the lifted band rides at ABSOLUTE_X,
-- outside the scanline blit, so the attacker's SCX never moves it.
function BattleState:drawLiftedRows()
  local battle = self.battle
  if not battle then return end
  local enemy = self:animPicState("enemy")
  local player = self:animPicState("player")
  local enemyLift = enemy and enemy.lifted
  local playerLift = player and player.lifted
  if not (enemyLift or playerLift) then return end
  local G = love.graphics
  if not self.liftCanvas then
    self.liftCanvas = G.newCanvas(160, 144)
    self.liftCanvas:setFilter("nearest", "nearest")
  end
  local previous = G.getCanvas()
  G.setCanvas(self.liftCanvas)
  G.clear(0, 0, 0, 0)
  G.push()
  G.origin()
  self.liftedPass = true
  if enemyLift then self:drawPic(battle.enemy, false) end
  if playerLift then self:drawPic(battle.player, true) end
  self.liftedPass = nil
  G.pop()
  G.setCanvas(previous)
  G.setColor(1, 1, 1, 1)
  G.draw(self.liftCanvas, 0, 0)
end

function BattleState:drawSceneBody()
  local panel = function() self:drawPanel() end
  if self.animView and self.slideFrame < BattleAnimView.SLIDE_FRAMES then
    -- The back pic is lifted out of the sliding bands and drawn the way the
    -- cart's OAM copy is: one intact piece riding in from the right, so it
    -- cannot tear at the $40 scanline where the bands part ways.
    self.slidingBackpic = true
    self.animView:presentSlide(self.slideFrame, panel, function(offset)
      self.slidingBackpic = nil
      local G = love.graphics
      G.push()
      G.translate(offset, 0)
      self:drawPic(self.battle and self.battle.player, true)
      G.pop()
      self.slidingBackpic = true
    end)
    self.slidingBackpic = nil
    return
  end
  if self.anim and self.animView then
    self.animView:present(self.anim, panel, self.battle)
    self:drawLiftedRows()
    self.animView:drawObjects(self.anim, self.battle)
    return
  end
  panel()
end

function BattleState:draw()
  self:drawScene()
end

function BattleState:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawScene()
  G.pop()
end

BattleState.MENU = MENU
BattleState.STATUS_TAGS = STATUS_TAGS
BattleState.Battle = Battle

return BattleState

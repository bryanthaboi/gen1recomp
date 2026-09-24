-- Dedicated Gen 3 Evolution Scene (pret evolution_scene.c & evolution_graphics.c).
-- Handles visual starburst rays, sparkle particles, white silhouette pulse scaling,
-- B-button cancellation, point-of-no-return mutation, audio choreography, and move learning.

local Stack = require("src.ui.game3.stack")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local Message = require("src.ui.game3.message")
local BattleChrome = require("src.ui.game3.battle_chrome")
local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local Audio = require("src.core.game3.audio")
local LearnMove = require("src.core.game3.battle.learn_move")
local SE = require("src.core.game3.se_ids")
local Oam = require("src.core.game3.oam")
local RomText = require("src.core.game3.rom_text")

local EvolutionScene = {}

EvolutionScene.open = false
EvolutionScene._mon = nil
EvolutionScene._preSpecies = nil
EvolutionScene._postSpecies = nil
EvolutionScene._canStop = true
EvolutionScene._session = nil
EvolutionScene._bag = nil
EvolutionScene._onDone = nil
EvolutionScene._state = "idle"
EvolutionScene._timer = 0
EvolutionScene._frame = 0
EvolutionScene._speed = 8
EvolutionScene._direction = 0
EvolutionScene._preScale = 1.0
EvolutionScene._postScale = 0.0625
EvolutionScene._particles = {}
EvolutionScene._flashAlpha = 0
EvolutionScene._bgAngle = 0
EvolutionScene._bgBrightness = 0
EvolutionScene._savedSong = nil
EvolutionScene._isBattle = false

local silhouetteShader = nil
if love and love.graphics and love.graphics.newShader then
  pcall(function()
    silhouetteShader = love.graphics.newShader([[
      vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texColor = Texel(texture, texture_coords);
        if (texColor.a < 0.05) {
          discard;
        }
        return vec4(color.rgb, texColor.a * color.a);
      }
    ]])
  end)
end

local function clean_string(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("%z+", ""):match("^%s*(.-)%s*$")) or ""
end

local function is_fanfare_or_evo_song(id)
  id = tonumber(id)
  if not id or id == 0 or id == 0xFFFF then return true end
  if id >= 256 and id <= 271 then return true end
  if id == 317 or id == 318 or id == 338 then return true end
  return false
end

function EvolutionScene.isOpen()
  return EvolutionScene.open
end

-- pokefirered/src/evolution_scene.c:266
local function evo_pic(species)
  local mon = EvolutionScene._mon
  return Pokemon.frontPic(Pokemon.picSpecies(species, mon and mon.personality), nil, Pokemon.isShiny(mon),
    mon and mon.personality)
end

--- Start an evolution scene.
-- @param mon table The Pokémon table
-- @param postSpecies number Target species ID
-- @param opts table { canStop, session, bag, isBattle, savedSong, onDone }
function EvolutionScene.start(mon, postSpecies, opts)
  opts = opts or {}
  if not mon or not postSpecies then
    if opts.onDone then opts.onDone("error") end
    return false
  end

  EvolutionScene.open = true
  EvolutionScene._mon = mon
  EvolutionScene._preSpecies = Pokemon.speciesOf(mon) or 1
  EvolutionScene._postSpecies = Pokemon.speciesFromName(postSpecies) or tonumber(postSpecies) or EvolutionScene._preSpecies
  -- pokefirered/src/evolution_scene.c:256
  local nick = clean_string(mon.nickname)
  if nick == "" then nick = clean_string(Pokemon.name(EvolutionScene._preSpecies)) end
  EvolutionScene._nick = nick ~= "" and nick or "POKéMON"
  EvolutionScene._canStop = opts.canStop ~= false
  -- pokefirered/src/evolution_scene.c:641
  EvolutionScene._autoCancel = opts.autoCancel and true or false
  EvolutionScene._session = opts.session
  EvolutionScene._bag = opts.bag
  EvolutionScene._via = opts.via
  EvolutionScene._onDone = opts.onDone
  EvolutionScene._isBattle = opts.isBattle and true or false
  EvolutionScene._headless = opts.headless and true or false

  local saved = opts.savedSong
  if not saved or is_fanfare_or_evo_song(saved) then
    if Audio._currentSong and not is_fanfare_or_evo_song(Audio._currentSong.id) then
      saved = Audio._currentSong.id
    end
  end
  if not saved or is_fanfare_or_evo_song(saved) then
    saved = Audio._mapSong
  end
  EvolutionScene._savedSong = saved

  EvolutionScene._state = "fade_in"
  EvolutionScene._timer = 0
  EvolutionScene._frame = 0
  EvolutionScene._speed = 8
  EvolutionScene._direction = 0
  EvolutionScene._preScale = 1.0
  EvolutionScene._postScale = 0.0625
  EvolutionScene._particles = {}
  EvolutionScene._flashAlpha = 0
  EvolutionScene._bgAngle = 0
  EvolutionScene._bgBrightness = 0

  -- Ensure OAM is cleared so no party menu/field sprites linger
  Oam.destroyAll()

  -- Ensure BattleChrome is installed
  if not BattleChrome._installed then
    BattleChrome.install(nil)
  end

  -- Ensure pre-evolution and post-evolution pics are cached
  evo_pic(EvolutionScene._preSpecies)
  evo_pic(EvolutionScene._postSpecies)

  -- Open message box in battle frame
  if Message.setFrame then Message.setFrame("battle") end

  Stack.push("evolution_scene", EvolutionScene, { hideBelow = true, fullscreen = true })
  return true
end

local function spawn_sparkle(kind)
  local cx, cy = 120, 64
  local p = {
    x = cx,
    y = cy,
    kind = kind or "spiral",
    t = 0,
    maxT = math.random(30, 50),
    angle = math.random() * math.pi * 2,
    dist = math.random(40, 80),
    speed = math.random(1, 3),
    size = math.random(2, 4),
  }
  EvolutionScene._particles[#EvolutionScene._particles + 1] = p
end

local function spawn_flash_spray()
  local cx, cy = 120, 64
  for i = 1, 32 do
    local angle = (i / 32) * math.pi * 2 + (math.random() - 0.5) * 0.2
    local speed = math.random(2, 5)
    EvolutionScene._particles[#EvolutionScene._particles + 1] = {
      x = cx,
      y = cy,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      kind = "spray",
      t = 0,
      maxT = math.random(25, 45),
      size = math.random(2, 5),
    }
  end
end

local function finish_scene(result)
  EvolutionScene.open = false
  Stack.pop("evolution_scene")
  local cb = EvolutionScene._onDone
  local mon = EvolutionScene._mon
  local saved = EvolutionScene._savedSong or Audio._mapSong
  EvolutionScene._onDone = nil
  EvolutionScene._mon = nil
  EvolutionScene._nick = nil
  EvolutionScene._pendingYesNo = nil
  EvolutionScene._learnWait = nil
  EvolutionScene._learnQueue = nil
  EvolutionScene._learnOpts = nil

  if Message.close then Message.close() end

  -- Restore previous BGM (victory loop if after battle, or map song if from menu/field)
  if saved then
    if not is_fanfare_or_evo_song(saved) then
      Audio.playSong(saved)
    elseif Audio._mapSong then
      Audio.playSong(Audio._mapSong)
    end
  end

  if cb then cb(result, mon) end
end

local function open_pending_yesno()
  if EvolutionScene._pendingYesNo == nil then return end
  if not (Message.isOpen and Message.isOpen()) then
    EvolutionScene._pendingYesNo = nil
    return
  end
  -- pokefirered/src/evolution_scene.c:912
  if not (Message.isWaiting and Message.isWaiting()) then return end
  local cb = EvolutionScene._pendingYesNo
  EvolutionScene._pendingYesNo = nil
  local Choice = require("src.ui.game3.choice")
  -- pokefirered/src/evolution_scene.c:914
  Choice.yesNo(function(yes)
    if Message.isOpen() and Message.close then Message.close() end
    if cb then cb(yes == true) end
  end, { left = 24, top = 9, style = "battle" })
end

local learn_next

local function learn_hooks(mon, displayName)
  return {
    mon = mon,
    displayName = displayName,
    headless = EvolutionScene._headless,
    -- pokefirered/src/evolution_scene.c:887
    battleText = true,
    pushMsg = function(text, cb)
      Message.show(text, { frame = "battle", done = cb })
    end,
    askYesNo = function(a, b)
      local cb = (type(a) == "function") and a or b
      local prompt = (type(a) == "string") and a or nil
      if prompt and prompt ~= "" then
        Message.show(prompt, { frame = "battle", stay = true })
        EvolutionScene._pendingYesNo = cb or false
        return
      end
      EvolutionScene._pendingYesNo = nil
      local Choice = require("src.ui.game3.choice")
      Choice.yesNo(function(yes)
        if cb then cb(yes == true) end
      end, { left = 24, top = 9, style = "battle" })
    end,
    askForget = function(_, cb, ctx)
      local SummaryMenu = require("src.ui.game3.summary_menu")
      -- pokefirered/src/evolution_scene.c:971
      SummaryMenu.openMenu({ mon }, 1, {
        mode = "select_move",
        moveToLearn = (ctx and ctx.moveId) or LearnMove._moveId,
        onSelectMove = function(slotIdx)
          if cb then cb(slotIdx) end
        end,
      })
    end,
  }
end

function learn_next()
  if not EvolutionScene.open then return end
  local q = EvolutionScene._learnQueue
  EvolutionScene._learnIdx = (EvolutionScene._learnIdx or 0) + 1
  local item = q and q[EvolutionScene._learnIdx]
  if not item then
    EvolutionScene._learnQueue = nil
    finish_scene("evolved")
    return
  end
  local opts = EvolutionScene._learnOpts
  LearnMove.begin({
    mon = opts.mon,
    moveId = item.moveId,
    displayName = opts.displayName,
    headless = opts.headless,
    battleText = opts.battleText,
    pushMsg = opts.pushMsg,
    askYesNo = opts.askYesNo,
    askForget = opts.askForget,
    onDone = function(learned)
      if learned and not EvolutionScene._headless then
        -- pokefirered/src/evolution_scene.c:871
        EvolutionScene._learnWait = 0x40
      else
        learn_next()
      end
    end,
  })
end

local function start_learn_moves()
  local mon = EvolutionScene._mon
  local level = tonumber(mon.level) or 1
  local displayName = Pokemon.displayMonName(mon)

  EvolutionScene._pendingYesNo = nil
  EvolutionScene._learnWait = nil
  EvolutionScene._learnOpts = learn_hooks(mon, displayName)
  -- pokefirered/src/pokemon.c:2288
  EvolutionScene._learnQueue = LearnMove.movesForLevels(mon, { level })
  EvolutionScene._learnIdx = 0
  learn_next()
end

function EvolutionScene.handleInput(input)
  if not EvolutionScene.open then return end

  local Choice = package.loaded["src.ui.game3.choice"]
  if Choice and Choice.active then
    if input:wasPressed("up") then
      Choice.move(-1)
    elseif input:wasPressed("down") then
      Choice.move(1)
    elseif input:wasPressed("a") then
      Choice.confirm()
    elseif input:wasPressed("b") then
      Choice.cancel()
    end
    return
  end

  -- B-Button Cancellation during CYCLE_SPRITES before T_speed >= 128
  if EvolutionScene._state == "cycle" and EvolutionScene._canStop and EvolutionScene._speed < 128 then
    if input:isDown("b") or input:wasPressed("b") then
      EvolutionScene._state = "cancel"
      EvolutionScene._timer = 0
      Audio.playSong(0)
      pcall(function() Audio.playSe(SE.SE_NOT_EFFECTIVE or 2) end)
      local fromName = Pokemon.displayMonName(EvolutionScene._mon)
      -- pokefirered/src/evolution_scene.c:857
      Message.show(RomText.box("gText_PkmnStoppedEvolving", { stringVars = { fromName } }), { frame = "battle" })
      return
    end
  end

  -- Advance dialogue on A or B during text states
  if EvolutionScene._state == "congrats" or EvolutionScene._state == "cancel" or EvolutionScene._state == "learn_moves" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      if Message.isOpen and Message.isOpen() then
        if Message.isWaiting and Message.isWaiting() then
          Message.advance()
        else
          Message.skipReveal()
        end
      end
      if not (Message.isOpen and Message.isOpen()) then
        if EvolutionScene._state == "congrats" then
          EvolutionScene._state = "learn_moves"
          -- Restore saved music immediately when congratulations message advances (1:1 pret pokefirered)
          local saved = EvolutionScene._savedSong or Audio._mapSong
          if saved then
            if not is_fanfare_or_evo_song(saved) then
              Audio.playSong(saved)
            elseif Audio._mapSong then
              Audio.playSong(Audio._mapSong)
            end
          end
          start_learn_moves()
        elseif EvolutionScene._state == "cancel" then
          finish_scene("stopped")
        end
      end
    end
  end
end

function EvolutionScene.update(dt)
  if not EvolutionScene.open then return end
  EvolutionScene._frame = EvolutionScene._frame + 1
  EvolutionScene._bgAngle = (EvolutionScene._bgAngle + 0.02) % (math.pi * 2)

  if EvolutionScene._state == "learn_moves" then
    open_pending_yesno()
  end

  if Message.isOpen and Message.isOpen() then
    Message.tick()
  end

  if EvolutionScene._state == "learn_moves" then
    if LearnMove.busy() then
      LearnMove.pump()
    elseif EvolutionScene._learnWait and not (Message.isOpen and Message.isOpen()) then
      -- pokefirered/src/evolution_scene.c:876
      EvolutionScene._learnWait = EvolutionScene._learnWait - 1
      if EvolutionScene._learnWait <= 0 then
        EvolutionScene._learnWait = nil
        learn_next()
      end
    end
  end

  -- Update particles
  for i = #EvolutionScene._particles, 1, -1 do
    local p = EvolutionScene._particles[i]
    p.t = p.t + 1
    if p.kind == "spiral" then
      p.angle = p.angle + 0.1
      p.dist = math.max(0, p.dist - p.speed)
      p.x = 120 + math.cos(p.angle) * p.dist
      p.y = 64 + math.sin(p.angle) * p.dist
    elseif p.kind == "spray" then
      p.x = p.x + (p.vx or 0)
      p.y = p.y + (p.vy or 0)
    end
    if p.t >= p.maxT or (p.kind == "spiral" and p.dist <= 2) then
      table.remove(EvolutionScene._particles, i)
    end
  end

  -- pokefirered/src/evolution_scene.c:641
  if EvolutionScene._autoCancel and EvolutionScene._state == "cycle" then
    EvolutionScene._state = "cancel"
    EvolutionScene._timer = 0
    Audio.playSong(0)
    -- pokefirered/src/battle_message.c:1277 gText_EllipsisQuestionMark
    Message.show(RomText.box("gText_EllipsisQuestionMark"), { frame = "battle" })
    return
  end

  local st = EvolutionScene._state

  if st == "fade_in" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._timer >= 16 then
      EvolutionScene._state = "intro_msg"
      EvolutionScene._timer = 0
      local fromName = Pokemon.displayMonName(EvolutionScene._mon)
      -- pokefirered/src/evolution_scene.c:678
      Message.show(RomText.box("gText_PkmnIsEvolving", { stringVars = { fromName } }), { frame = "battle" })
    end

  elseif st == "intro_msg" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._timer >= 45 then
      EvolutionScene._state = "intro_cry"
      EvolutionScene._timer = 0
      Audio.playCry(EvolutionScene._preSpecies)
    end

  elseif st == "intro_cry" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._timer >= 40 then
      EvolutionScene._state = "intro_sound"
      EvolutionScene._timer = 0
      Audio.playSong(263, { loop = false }) -- MUS_EVOLUTION_INTRO
    end

  elseif st == "intro_sound" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._timer >= 35 then
      EvolutionScene._state = "start_music"
      EvolutionScene._timer = 0
      Audio.playSong(264, { restart = true, loop = true }) -- MUS_EVOLUTION
    end

  elseif st == "start_music" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    EvolutionScene._bgBrightness = math.min(1.0, EvolutionScene._timer / 20)
    if EvolutionScene._timer >= 20 then
      EvolutionScene._state = "cycle"
      EvolutionScene._timer = 0
      EvolutionScene._speed = 8
      EvolutionScene._direction = 0
      EvolutionScene._preScale = 1.0
      EvolutionScene._postScale = 0.0625
    end

  elseif st == "cycle" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._frame % 3 == 0 then
      spawn_sparkle("spiral")
    end

    local spd = EvolutionScene._speed / 256
    if EvolutionScene._direction == 0 then
      -- Pre-evo shrinks, Post-evo grows
      EvolutionScene._preScale = math.max(0.0625, EvolutionScene._preScale - spd)
      EvolutionScene._postScale = math.min(1.0, EvolutionScene._postScale + spd)
      if EvolutionScene._preScale <= 0.0625 and EvolutionScene._postScale >= 1.0 then
        EvolutionScene._direction = 1
        EvolutionScene._speed = EvolutionScene._speed + 2
      end
    else
      -- Pre-evo grows, Post-evo shrinks
      EvolutionScene._preScale = math.min(1.0, EvolutionScene._preScale + spd)
      EvolutionScene._postScale = math.max(0.0625, EvolutionScene._postScale - spd)
      if EvolutionScene._preScale >= 1.0 and EvolutionScene._postScale <= 0.0625 then
        EvolutionScene._direction = 0
        EvolutionScene._speed = EvolutionScene._speed + 2
      end
    end

    -- Acceleration cutoff -> Point of no return
    if EvolutionScene._speed >= 128 then
      EvolutionScene._state = "flash_reveal"
      EvolutionScene._timer = 0
      EvolutionScene._flashAlpha = 1.0
      EvolutionScene._preScale = 0
      EvolutionScene._postScale = 1.0

      -- Stop evolution BGM on burst (pokefirered m4aMPlayAllStop)
      Audio.playSong(0)

      -- POINT OF NO RETURN: Mutate species, stats, nickname, dex, Shedinja now
      Evolution.apply(EvolutionScene._mon, EvolutionScene._postSpecies, EvolutionScene._session, EvolutionScene._bag, EvolutionScene._via)

      pcall(function() Audio.playSe(SE.SE_M_PETAL_DANCE or 195) end)
      spawn_flash_spray()
    end

  elseif st == "flash_reveal" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    EvolutionScene._flashAlpha = math.max(0, 1.0 - (EvolutionScene._timer / 15))
    if EvolutionScene._timer >= 30 then
      EvolutionScene._state = "evo_cry"
      EvolutionScene._timer = 0
      Audio.playCry(EvolutionScene._postSpecies)
    end

  elseif st == "evo_cry" then
    EvolutionScene._timer = EvolutionScene._timer + 1
    if EvolutionScene._timer >= 45 then
      EvolutionScene._state = "congrats"
      EvolutionScene._timer = 0
      Audio.stopCry()
      Audio.playFanfare(259) -- MUS_EVOLVED

      local fromName = EvolutionScene._nick or clean_string(Pokemon.name(EvolutionScene._preSpecies))
      local intoName = Pokemon.name(EvolutionScene._postSpecies) or "POKéMON"
      -- pokefirered/src/evolution_scene.c:775
      Message.show(RomText.box("gText_CongratsPkmnEvolved", { stringVars = { fromName, intoName } }),
        { frame = "battle" })
    end

  elseif st == "cancel" then
    -- Handled via handleInput
  elseif st == "learn_moves" then
    -- Handled via LearnMove callbacks
  end
end

local function draw_starburst(cx, cy, radius, numRays, angle, color1, color2)
  if not (love and love.graphics) then return end
  local step = (math.pi * 2) / numRays
  for i = 0, numRays - 1 do
    local a1 = angle + i * step
    local a2 = a1 + step * 0.5
    local x1 = cx + math.cos(a1) * radius
    local y1 = cy + math.sin(a1) * radius
    local x2 = cx + math.cos(a2) * radius
    local y2 = cy + math.sin(a2) * radius
    love.graphics.setColor(color1)
    love.graphics.polygon("fill", cx, cy, x1, y1, x2, y2)
  end
end

function EvolutionScene.draw()
  if not EvolutionScene.open or not (love and love.graphics) then return end

  -- 1. Draw plain battle background (clean wallpaper without platform blotches)
  BattleChrome.drawCleanBg("building")

  local cx, cy = 120, 64

  -- 2. Draw animated starburst background when music active
  if EvolutionScene._bgBrightness > 0 then
    local b = EvolutionScene._bgBrightness
    local c1 = { 0.15 * b, 0.45 * b, 0.85 * b, 0.85 * b }
    local c2 = { 0.05 * b, 0.15 * b, 0.40 * b, 0.70 * b }
    love.graphics.setColor(c2)
    love.graphics.rectangle("fill", 0, 0, Display.W, 112)
    draw_starburst(cx, cy, 200, 16, EvolutionScene._bgAngle, c1, c2)
  end

  -- 3. Draw sparkle particles
  for _, p in ipairs(EvolutionScene._particles) do
    local alpha = math.min(1.0, (p.maxT - p.t) / 10)
    love.graphics.setColor(1, 1, 0.8, alpha)
    love.graphics.circle("fill", p.x, p.y, p.size or 2)
  end

  -- 4. Draw Pokémon sprites (silhouette or full color)
  local st = EvolutionScene._state
  local prePic = evo_pic(EvolutionScene._preSpecies)
  local postPic = evo_pic(EvolutionScene._postSpecies)

  if st == "cycle" then
    -- Solid white silhouette shader
    if silhouetteShader then
      love.graphics.setShader(silhouetteShader)
    end
    love.graphics.setColor(1, 1, 1, 1)

    if prePic and prePic.image and EvolutionScene._preScale > 0.05 then
      local s = EvolutionScene._preScale
      love.graphics.draw(prePic.image, cx, cy, 0, s, s, 32, 32)
    end
    if postPic and postPic.image and EvolutionScene._postScale > 0.05 then
      local s = EvolutionScene._postScale
      love.graphics.draw(postPic.image, cx, cy, 0, s, s, 32, 32)
    end

    if silhouetteShader then
      love.graphics.setShader()
    end

  elseif st == "cancel" or st == "fade_in" or st == "intro_msg" or st == "intro_cry" or st == "intro_sound" or st == "start_music" then
    -- Normal pre-evolution sprite
    if prePic and prePic.image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(prePic.image, cx, cy, 0, 1, 1, 32, 32)
    end

  else
    -- Normal post-evolution sprite (flash_reveal, evo_cry, congrats, learn_moves)
    if postPic and postPic.image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(postPic.image, cx, cy, 0, 1, 1, 32, 32)
    end
  end

  -- 5. Full white flash overlay
  if EvolutionScene._flashAlpha > 0 then
    love.graphics.setColor(1, 1, 1, EvolutionScene._flashAlpha)
    love.graphics.rectangle("fill", 0, 0, Display.W, 112)
  end

  -- 6. Battle panel chrome & message window
  BattleChrome.drawPanel("none")
  if Message.isOpen and Message.isOpen() then
    Message.draw()
  end

  local Choice = package.loaded["src.ui.game3.choice"]
  if Choice and Choice.active and Choice.draw then
    Choice.draw()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return EvolutionScene

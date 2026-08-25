-- ../pokecrystal/engine/events/move_tutor.asm:1 MoveTutor, the submenu
-- FadeToMenu / ChooseMonToLearnTMHM / CloseSubmenu wraps, and :54
-- CheckCanLearnMoveTutorMove, whose refusals print into a Textbox over the
-- party list (:101-103 `menu_coords 0, 12, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1`).
--
-- ChooseMonToLearnTMHM (../pokecrystal/engine/items/tmhm.asm:73) is
-- InitPartyMenuWithCancel with PARTYMENUACTION_TEACH_TMHM, which is the list
-- src/ui/gen2/PartyMenu.lua already draws when it is handed `tmhm`.

local Chrome = require("src.ui.gen2.Chrome")
local Happiness = require("src.core.gen2.Happiness")
local Mon = require("src.battle.gen2.Mon")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local Strings = require("src.core.Strings")

local MoveTutor = {}
MoveTutor.__index = MoveTutor
MoveTutor.isOpaque = true

-- ../pokecrystal/data/text/common_2.asm:187 _TMHMNotCompatibleText and
-- common_3.asm:1424 _KnowsMoveText.  CopyName1 leaves the MOVE in
-- wStringBuffer2 and GetNickname the nickname in wStringBuffer1.
local NOT_COMPATIBLE = Strings.source("%s is\nnot compatible\vwith %s.")
local KNOWS_MOVE = Strings.source("%s knows\n%s.")

-- CanLearnTMHMMove's bitfield: `add_mt` gives the three tutor moves TMHM
-- flags 58-60 (../pokecrystal/constants/item_constants.asm:295-307), which
-- the cache splits out as `tutorMoves`.
function MoveTutor.canLearn(species, moveId)
  if type(species) ~= "table" or not moveId then return false end
  for _, id in ipairs(species.tmhm or {}) do
    if id == moveId then return true end
  end
  for _, id in ipairs(species.tutorMoves or {}) do
    if id == moveId then return true end
  end
  return false
end

-- The same bitfield as a pokemon.lua view, for PartyMenu's ABLE / NOT ABLE
-- column (src/ui/gen2/PartyMenu.lua:735, which walks `tmhm` only).
function MoveTutor.speciesView(pokemon)
  local cache = {}
  return setmetatable({}, { __index = function(_, key)
    local hit = cache[key]
    if hit ~= nil then return hit or nil end
    local def = pokemon and pokemon[key]
    if type(def) ~= "table" then
      cache[key] = false
      return nil
    end
    local merged = {}
    for field, value in pairs(def) do merged[field] = value end
    local list = {}
    for _, id in ipairs(def.tmhm or {}) do list[#list + 1] = id end
    for _, id in ipairs(def.tutorMoves or {}) do list[#list + 1] = id end
    merged.tmhm = list
    cache[key] = merged
    return merged
  end })
end

-- opts: move, moveName, onDone(learned)
function MoveTutor.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MoveTutor)
  self.game = game
  local data = (game and game.data) or {}
  self.move = opts.move
  self.moveName = opts.moveName or opts.move or "?"
  self.onDone = opts.onDone
  self.pokemon = opts.pokemon or data.pokemon
  self.view = MoveTutor.speciesView(self.pokemon)
  self.list = self:buildList()
  return self
end

function MoveTutor:wantsFillScale() return true end
function MoveTutor:drawsWidescreen() return true end

function MoveTutor:buildList()
  return PartyMenu.new(self.game, {
    prompt = "teach",
    tmhm = { move = self.move },
    pokemon = self.view,
    onChoose = function(_, mon) self:picked(mon) end,
    onCancel = function() self:finish(false) end,
  })
end

function MoveTutor:say(body, onDone)
  if self.game and self.game.say then return self.game:say(body, onDone) end
  if onDone then onDone() end
end

function MoveTutor:playSfx(name)
  local world = self.game and self.game.world
  if world and world.playSfxNamed then world:playSfxNamed(name) end
end

-- CheckCanLearnMoveTutorMove (../pokecrystal/engine/events/move_tutor.asm:54);
-- all three failures fall back into the list, `jr nc, .loop` at :24.
function MoveTutor:picked(mon)
  if not mon then return end
  local name = Mon.displayName(mon)
  if not MoveTutor.canLearn(self.view[mon.species], self.move) then
    self:playSfx("Sfx_Wrong")
    return self:say(Strings(NOT_COMPATIBLE, self.moveName, name))
  end
  -- ../pokecrystal/engine/pokemon/knows_move.asm:16 sets carry and prints,
  -- which is the same .didnt_learn arm.
  for _, move in ipairs(mon.moves or {}) do
    if move.id == self.move then
      return self:say(Strings(KNOWS_MOVE, name, self.moveName))
    end
  end
  local game = self.game
  if not (game and game.learnMoveOn) then return self:finish(false) end
  game:learnMoveOn(mon, self.move, function(learned)
    if not learned then return end
    -- :87-88 `ld c, HAPPINESS_LEARNMOVE / callfar ChangeHappiness`.  The 4000
    -- coins are the script's own takecoins (maps/GoldenrodCity.asm:124).
    Happiness.change(mon, "LEARNMOVE")
    self:finish(true)
  end)
end

function MoveTutor:finish(learned)
  if self.done then return end
  self.done = true
  local stack = self.game and self.game.stack
  if stack then stack:pop() end
  if self.onDone then self.onDone(learned) end
end

function MoveTutor:update(dt)
  if self.done then return end
  self.list:update(dt)
end

function MoveTutor:drawPanel()
  self.list:drawPanel()
end

function MoveTutor:draw()
  self.list:draw()
end

-- PartyMenu:drawWidescreen's own blit: the party page is white to the window
-- edge, at the one integer scale Chrome.fitScale picks.
function MoveTutor:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return MoveTutor

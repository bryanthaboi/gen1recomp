-- home/pokemon.asm:246
-- engine/items/item_effects.asm:1979-2006
-- engine/pokemon/learn_move.asm:119-181

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("PP UP / TM move box #2320")
local check, eq = S.check, S.eq

local ItemEffects = require("src.inventory.ItemEffects")

do
  local Data = {
    items = { PP_UP = { name = "PP UP" } },
    moves = { LICK = { name = "LICK", pp = 30 } },
    pokemon = { GENGAR = { name = "GENGAR" } },
    text = {},
  }
  local t = { species = "GENGAR", hp = 20, stats = { hp = 20 },
              moves = { { id = "LICK", pp = 48, ppUps = 3 } } }
  local result, payload = ItemEffects.use(Data, {}, "PP_UP", t, nil, 1)
  eq(result, "ppmaxed", "PP UP on a move with 3 PP Ups reports maxed out")
  eq(payload and payload[1], "LICK's PP\nis maxed out.", "and prints PPMaxedOutText")
  eq(t.moves[1].ppUps, 3, "the move is untouched")
end

local draws
local FontStub = {
  drawBox = function(tx, ty, tw, th) draws[#draws + 1] = { "box", tx, ty, tw, th } end,
  draw = function(text, x, y) draws[#draws + 1] = { "text", text, x, y } end,
  drawCode = function(code, x, y) draws[#draws + 1] = { "code", code, x, y } end,
}
package.loaded["src.render.Font"] = FontStub

local boxes = {}
local TextBoxStub = {}
TextBoxStub.strip = function(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("{DONE}", ""):gsub("{PROMPT}", ""))
end
TextBoxStub.new = function(game, text, onDone, opts)
  local b = { fake = true, text = text, onDone = onDone, opts = opts }
  boxes[#boxes + 1] = b
  return b
end
package.loaded["src.render.TextBox"] = TextBoxStub
package.loaded["src.render.HudTiles"] = {
  tile = function() end, drawHPBar = function() end, statusTile = function() end,
}
package.loaded["src.render.PaletteFX"] = {
  shader = function() return nil end, pal = function() return nil end,
}

local MoveSelectMenu = require("src.ui.MoveSelectMenu")
local MoveLearnMenu = require("src.ui.MoveLearnMenu")
local PartyMenu = require("src.ui.PartyMenu")
PartyMenu.drawIcon = function() end

local pressed = {}
local function newGame()
  local game = {
    input = { wasPressed = function(_, b) return pressed[b] == true end,
              isDown = function() return false end },
    data = {
      moves = { LICK = { name = "LICK" }, HYPNOSIS = { name = "HYPNOSIS" },
                SURF = { name = "SURF" }, MEGA_PUNCH = { name = "MEGA PUNCH", pp = 20 } },
      pokemon = { GENGAR = { name = "GENGAR" } },
      statuses = {},
      text = {},
    },
  }
  game.stack = {
    states = {},
    push = function(self, s, ...)
      self.states[#self.states + 1] = s
      if type(s.enter) == "function" then s:enter(...) end
    end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  return game
end

local function press(state, btn)
  pressed = { [btn] = true }
  state:update(1 / 60)
  pressed = {}
end

local function finishBox(game)
  local b = game.stack:top()
  if b and b.fake and b.opts and b.opts.stay and b.opts.stay.onShown then
    b.opts.stay.onShown()
    return true
  end
  return false
end

local function cursorGlyphAt(y)
  for _, d in ipairs(draws) do
    if d[1] == "code" and d[3] == 0 and d[4] == y then return d[2] end
  end
end

do
  local game = newGame()
  local mon = { species = "GENGAR", level = 30, hp = 60, stats = { hp = 60 },
                moves = { { id = "LICK", pp = 30 }, { id = "HYPNOSIS", pp = 20 } } }
  game.save = { party = { mon, { species = "GENGAR", level = 5, hp = 10,
                                 stats = { hp = 10 }, moves = {} } } }
  local menuRef, chosen
  local picker = PartyMenu.new(game, {
    pickOnly = true, itemUse = true, keepOpen = true,
    onSwitch = function(m, p)
      menuRef = MoveSelectMenu.new(game, m, "Raise PP of which\ntechnique?{DONE}",
        function(i, menu) chosen = { i, menu } end, nil, p)
      game.stack:push(menuRef)
    end,
  })
  game.stack:push(picker)

  draws = {}
  picker:draw()
  eq(cursorGlyphAt(8), 0xED, "the party cursor is the filled arrow before the pick")

  press(picker, "a")
  check(picker.chosenHollow == true, "A on a kept-open picker marks the row chosen")
  draws = {}
  picker:draw()
  eq(cursorGlyphAt(8), 0xEC, "the chosen mon's arrow turns hollow")

  check(menuRef ~= nil, "the move menu was pushed")
  local top = game.stack:top()
  check(top and top.fake, "a text box types the prompt before the move box")
  eq(top and top.text, "Raise PP of which\ntechnique?{DONE}", "with the item's prompt")
  check(top and top.opts and top.opts.stay ~= nil, "a done-text stay box")
  eq(menuRef.ready, false, "the move menu takes no input while the prompt types")
  draws = {}
  menuRef:draw()
  eq(#draws, 0, "and draws nothing yet")
  pressed = { a = true }
  menuRef:update(1 / 60)
  pressed = {}
  eq(chosen, nil, "an A press during the prompt picks nothing")

  check(finishBox(game), "the prompt finished typing")
  eq(game.stack:top(), menuRef, "the prompt box hands the screen to the move menu")
  eq(menuRef.ready, true, "the move menu is live")
  draws = {}
  menuRef:draw()
  eq(draws[1][1], "box", "prompt text box drawn first")
  eq(draws[1][2], 0, "at column 0")
  eq(draws[1][3], 12, "row 12")
  local last
  for _, d in ipairs(draws) do if d[1] == "box" then last = d end end
  eq(last and last[2], 4, "the move box is the last box drawn")
  eq(last and last[3], 7, "at 4,7, over the text box's top edge")

  press(menuRef, "down")
  press(menuRef, "a")
  eq(chosen and chosen[1], 2, "A hands back the picked slot")
  eq(chosen and chosen[2], menuRef, "and the menu")
  eq(game.stack:top(), picker, "nothing was pushed over it, so it released itself")
  eq(#game.stack.states, 1, "back to the party menu")

  menuRef = nil
  press(picker, "a")
  finishBox(game)
  local held = game.stack:top()
  eq(getmetatable(held), MoveSelectMenu, "the move menu is up again")
  local result = { fake = true, text = "LICK's PP\nincreased." }
  held.onChoose = function() game.stack:push(result) end
  press(held, "a")
  eq(game.stack:top(), result, "the result text is on top")
  check(held.held == true, "the move menu is held under it")
  eq(game.stack.states[#game.stack.states - 1], held, "still on the stack under the result")
  draws = {}
  held:draw()
  local moveBox
  for _, d in ipairs(draws) do
    if d[1] == "box" and d[2] == 4 and d[3] == 7 then moveBox = d end
    if d[1] == "box" and d[2] == 0 and d[3] == 12 then moveBox = "prompt" end
  end
  check(type(moveBox) == "table", "the held menu keeps drawing the move box, not its prompt")
  draws = {}
  picker:draw()
  eq(cursorGlyphAt(8), 0xEC, "the party arrow stays hollow under the result")

  game.stack:pop()
  picker:close()
  eq(#game.stack.states, 0, "closing the picker drops the held move box too")
end

do
  local game = newGame()
  local mon = { species = "GENGAR", moves = { { id = "LICK" } } }
  local p = { fake = "picker" }
  local other = MoveSelectMenu.new(game, mon, "x", nil, nil, nil)
  game.stack.states = { p, other }
  PartyMenu.close(setmetatable({ game = game }, { __index = p }))
  eq(#game.stack.states, 2, "close leaves a menu it does not own alone")
end

do
  local game = newGame()
  local mon = { species = "GENGAR", moves = { { id = "LICK" }, { id = "HYPNOSIS" } } }
  local m = MoveSelectMenu.new(game, mon, "Raise PP of which\ntechnique?")
  game.stack:push(m)
  finishBox(game)
  press(m, "down")
  local maxed = { fake = true }
  m.onChoose = function() game.stack:push(maxed) end
  press(m, "a")
  game.stack:pop()
  m:ask()
  local reprompt = game.stack:top()
  check(reprompt.fake and reprompt.text == "Raise PP of which\ntechnique?",
        "ask() types the prompt again")
  eq(m.ready, false, "the menu waits for it")
  draws = {}
  m:draw()
  local promptBox, moveBox = false, false
  for _, d in ipairs(draws) do
    if d[1] == "box" and d[3] == 12 then promptBox = true end
    if d[1] == "box" and d[3] == 7 then moveBox = true end
  end
  check(moveBox and not promptBox, "the move box stays up while the prompt retypes")
  finishBox(game)
  eq(m.index, 1, "the cursor starts over on the first move")
  eq(m.ready, true, "and the menu is live again")
end

do
  local game = newGame()
  local mon = { species = "GENGAR", level = 30,
                moves = { { id = "SURF" }, { id = "LICK" }, { id = "HYPNOSIS" }, { id = "LICK" } } }
  local m = MoveLearnMenu.new(game, mon, "MEGA_PUNCH", function() end)
  game.stack:push(m)
  local ask = game.stack:top()
  check(ask.fake and ask.opts and ask.opts.choice, "TryingToLearn YES/NO first")
  game.stack:pop()
  ask.opts.choice(true)
  local forget = game.stack:top()
  check(forget.fake and forget.text:find("Which move should", 1, true) ~= nil,
        "YES types WhichMoveToForgetText")
  check(forget.opts and forget.opts.stay ~= nil, "as a done-text stay box")
  eq(m.selecting, false, "the forget list waits for the text")
  draws = {}
  m:draw()
  eq(#draws, 0, "and is not drawn yet")
  finishBox(game)
  eq(game.stack:top(), m, "the text hands off to the forget list")
  eq(m.selecting, true, "which is live")
  draws = {}
  m:draw()
  eq(draws[1][1], "box", "text box first")
  eq(draws[1][3], 12, "at row 12")
  local last
  for _, d in ipairs(draws) do if d[1] == "box" then last = d end end
  eq(last and last[2], 4, "forget box last")
  eq(last and last[3], 7, "at 4,7")

  press(m, "a")
  local hm = game.stack:top()
  check(hm.fake and hm.text:find("HM techniques", 1, true) ~= nil, "SURF is refused")
  eq(m.selecting, false, "the forget box is gone under the refusal")
  game.stack:pop()
  hm.onDone()
  local again = game.stack:top()
  check(again.fake and again.text:find("Which move should", 1, true) ~= nil,
        "then the prompt types again")
  finishBox(game)
  eq(m.selecting, true, "and the forget list comes back")
  eq(m.index, 1, "on the first move")
end

S.finish()

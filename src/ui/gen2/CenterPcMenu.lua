-- The Pokemon Center PC's whose-PC menu (engine/events/pokecenter_pc.asm
-- PokemonCenterPC).  Every Pokecenter reaches it the same way: the PC is a
-- COLL_PC tile, the A press runs PCScript (engine/events/std_scripts.asm) and
-- its `special PokemonCenterPC` opens this screen through World:openPc.
--
-- .ChooseWhichPCListToUse picks the row list:
--
--   PCPC_BEFORE_POKEDEX  BILL's PC / <PLAYER>'s PC / TURN OFF
--   PCPC_BEFORE_HOF      + PROF.OAK's PC        (CheckReceivedDex)
--   PCPC_POSTGAME        + HALL OF FAME         (wHallOfFameCount > 0)
--
-- BILL's PC opens the storage system (src/ui/gen2/PcMenu.lua, _BillsPC's own
-- five rows), <PLAYER>'s PC the item PC (src/ui/gen2/ItemPcMenu.lua,
-- PLAYERSPC_NORMAL), PROF.OAK's PC the #DEX rating (ProfOaksPC,
-- engine/events/prof_oaks_pc.asm) and HALL OF FAME the roster viewer
-- (src/ui/gen2/HallOfFame.lua "view" mode, _HallOfFamePC).

local Chrome = require("src.ui.gen2.Chrome")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Specials = require("src.script.gen2.Specials")
local Strings = require("src.core.Strings")

local CenterPcMenu = {}
CenterPcMenu.__index = CenterPcMenu
CenterPcMenu.isOpaque = true

-- ENGINE_POKEDEX (constants/engine_flags.asm, index 11): the flag
-- CheckReceivedDex reads and Mr.Pokemon's `setflag ENGINE_POKEDEX` writes.
-- The port lands plain ENGINE_* ids on save.engineFlags
-- (World:setEngineFlag), so the same store answers here.
local ENGINE_POKEDEX = 11

function CenterPcMenu:wantsFillScale() return true end
function CenterPcMenu:drawsWidescreen() return true end

-- A multi-page body: `para` (a blank line in the transcription) is a
-- screenful of its own, two lines to a page.
local function pagesOf(body)
  local pages = {}
  for chunk in (tostring(body) .. "\n\n"):gmatch("(.-)\n\n") do
    local lines = {}
    for line in (chunk .. "\n"):gmatch("(.-)\n") do
      if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines > 0 then pages[#pages + 1] = lines end
  end
  return pages
end

-- opts: save, events, items (items.lua), onClose()
function CenterPcMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, CenterPcMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.items = opts.items or (game and game.data and game.data.items)
  self.data = game and game.data
  self.events = opts.events
  self.onClose = opts.onClose
  self.index = 1
  self.message = nil
  self.confirm = nil
  self.closed = false
  self:buildEntries()
  local party = self.save and self.save.party
  if not (party and #party > 0) then
    -- PC_CheckPartyForPokemon: SFX_CHOOSE_PC_OPTION, the refusal, and the PC
    -- never boots (`ret c` before PC_PlayBootSound).
    self:playSfx("Sfx_ChoosePcOption")
    self:say({ { "Bzzzzt! You must", "have a #MON to", "use this!" } },
      function() self:close() end)
  else
    -- PC_PlayBootSound + _PokecenterPCTurnOnText.
    self:playSfx("Sfx_BootPc")
    self:say({ { "{PLAYER} turned on", "the PC." } })
  end
  return self
end

function CenterPcMenu:playSfx(name)
  local data = self.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then
    Sound.play(data, name)
  end
end

function CenterPcMenu:playerName()
  local player = self.save and self.save.player
  return (player and player.name) or "GOLD"
end

-- .WhichPC, gated the way .ChooseWhichPCListToUse gates it.  TURN OFF is
-- always last; the extra rows slot in above it in PCPCITEM_* order.
function CenterPcMenu:buildEntries()
  local save = self.save
  local hasDex = save and save.engineFlags
    and save.engineFlags[ENGINE_POKEDEX] == true
  local hofCount = (save and save.hallOfFame and save.hallOfFame.count) or 0
  local entries = {
    { id = "bills", label = "BILL's PC" },
    { id = "players", label = self:playerName() .. "'s PC" },
  }
  if hasDex then
    entries[#entries + 1] = { id = "oaks", label = "PROF.OAK's PC" }
    if hofCount > 0 then
      entries[#entries + 1] = { id = "hof", label = "HALL OF FAME" }
    end
  end
  entries[#entries + 1] = { id = "turnoff", label = "TURN OFF" }
  self.entries = entries
end

-- pages is a list of pages, each a list of lines; a page may carry `sfx`,
-- played the moment it comes up (FindOakRating hands PlaySFX its fanfare
-- right before the rating text prints).
function CenterPcMenu:say(pages, onDone)
  self.message = { pages = pages, page = 1, onDone = onDone }
  local first = pages[1]
  if first and first.sfx then self:playSfx(first.sfx) end
end

function CenterPcMenu:close()
  if self.closed then return end
  self.closed = true
  if self.onClose then self.onClose() end
end

-- .shutdown: PC_PlayShutdownSound, then the menu is gone.  The party refusal
-- never reaches this -- the PC never booted.
function CenterPcMenu:shutdown()
  self:playSfx("Sfx_ShutDownPc")
  self:close()
end

-- ProfOaksPC's `.shutdown`: _OakPCText4 either way, then back to the menu
-- loop (`jr nc, .loop` in PokemonCenterPC -- the OaksPC row answers nc).
function CenterPcMenu:oakClosed()
  self:say({ { "The link to PROF.", "OAK's PC closed." } })
end

-- ProfOaksPCBoot, inside a screen rather than a script: the counts, the
-- rating pick and the texts come from src/script/gen2/Specials.lua so the two
-- callers cannot drift apart.
function CenterPcMenu:oakRate()
  local seen, caught = Specials.dexCounts(self.save)
  local rating = Specials.findOakRating(caught)
  local pages = pagesOf(Strings(Specials.OAK_PC_TEXT.completion))
  for _, page in ipairs(pagesOf(
      Strings(Specials.OAK_PC_TEXT.counts, seen, caught))) do
    pages[#pages + 1] = page
  end
  local ratingPages = pagesOf(Strings(rating.text))
  if ratingPages[1] then ratingPages[1].sfx = rating.sfx end
  for _, page in ipairs(ratingPages) do pages[#pages + 1] = page end
  self:say(pages, function() self:oakClosed() end)
end

function CenterPcMenu:choose()
  local entry = self.entries[self.index]
  if not entry then return end
  local game = self.game
  if entry.id == "turnoff" then
    -- TurnOffPC: PokecenterPCOaksClosedText, then carry into .shutdown.
    self:say({ { "\xe2\x80\xa6", "Link closed\xe2\x80\xa6" } },
      function() self:shutdown() end)
    return
  end
  -- PC_PlayChoosePCSound opens all four of the other rows.
  self:playSfx("Sfx_ChoosePcOption")
  if entry.id == "bills" then
    self:say({ { "BILL's PC", "accessed." },
               { "#MON Storage", "System opened." } }, function()
      if not (game and game.stack) then return end
      Screens.push(game, "Gen2PcMenu", {
        save = self.save,
        bills = true,
        onClose = function() game.stack:pop() end,
      })
    end)
  elseif entry.id == "players" then
    self:say({ { "Accessed own PC." },
               { "Item Storage", "System opened." } }, function()
      if not (game and game.stack) then return end
      Screens.push(game, "Gen2ItemPcMenu", {
        save = self.save,
        items = self.items,
        onClose = function() game.stack:pop() end,
      })
    end)
  elseif entry.id == "oaks" then
    self:say({ { "PROF.OAK's PC", "accessed." },
               { "#DEX Rating", "System opened." } }, function()
      -- _OakPCText1's yes/no; NO is the same `.shutdown` as a finished rating.
      self.confirm = {
        prompt = { "Want to get your", "#DEX rated?" },
        choice = 1,
        onYes = function() self:oakRate() end,
        onNo = function() self:oakClosed() end,
      }
    end)
  elseif entry.id == "hof" then
    if not (game and game.stack) then return end
    -- HallOfFamePC: FadeToMenu, _HallOfFamePC, CloseSubmenu.
    Screens.push(game, "Gen2HallOfFame", {
      save = self.save,
      mode = "view",
      onDone = function() game.stack:pop() end,
    })
  end
end

function CenterPcMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      local m = self.message
      if m.page < #m.pages then
        m.page = m.page + 1
        local page = m.pages[m.page]
        if page and page.sfx then self:playSfx(page.sfx) end
        return
      end
      self.message = nil
      if m.onDone then m.onDone() end
    end
    return
  end

  if self.confirm then
    local c = self.confirm
    if input:wasPressed("up") or input:wasPressed("down") then
      c.choice = c.choice == 1 and 2 or 1
    elseif input:wasPressed("b") then
      -- YesNoBox's B is NO.
      self.confirm = nil
      if c.onNo then c.onNo() end
    elseif input:wasPressed("a") then
      self.confirm = nil
      if c.choice == 1 then
        if c.onYes then c.onYes() end
      elseif c.onNo then
        c.onNo()
      end
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.entries
  elseif input:wasPressed("down") then
    self.index = self.index < #self.entries and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") then
    -- DoNthMenu's carry lands straight in .shutdown, no text.
    self:shutdown()
  end
end

function CenterPcMenu:drawBottomLines(lines)
  Chrome.box(0, 12, 20, 6)
  if not lines then return end
  local name = self:playerName()
  local startY = #lines >= 3 and 13 or 14
  for i, line in ipairs(lines) do
    Chrome.print((line:gsub("{PLAYER}", name)), 1, startY + (i - 1) * 2)
  end
end

function CenterPcMenu:drawPanel()
  Chrome.clear()

  if self.message then
    self:drawBottomLines(self.message.pages[self.message.page])
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- _PokecenterPCWhoseText stays up under the menu
  -- (PC_DisplayTextWaitMenu leaves it there); the menu window is drawn on
  -- top of it, the way the cart's windows stack.
  self:drawBottomLines({ "Access whose PC?" })
  -- .TopMenu is menu_coords 0, 0, 15, 12.
  Chrome.box(0, 0, 16, math.max(12, #self.entries * 2 + 2))
  for i, entry in ipairs(self.entries) do
    local ty = i * 2
    if i == self.index then Chrome.cursor(1, ty) end
    Chrome.print(entry.label, 2, ty)
  end

  if self.confirm then
    self:drawBottomLines(self.confirm.prompt)
    Chrome.box(14, 7, 6, 5)
    Chrome.print("YES", 16, 8)
    Chrome.print("NO", 16, 10)
    Chrome.cursor(15, self.confirm.choice == 1 and 8 or 10)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function CenterPcMenu:draw()
  self:drawPanel()
end

function CenterPcMenu:drawWidescreen(winW, winH)
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

CenterPcMenu.ENGINE_POKEDEX = ENGINE_POKEDEX

return CenterPcMenu

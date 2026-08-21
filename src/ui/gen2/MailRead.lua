-- Reading a letter: ReadAnyMail / ReadPartyMonMail (engine/pokemon/mail_2.asm).
--
-- The screen is one full-page piece of stationery -- ten of them, one per mail
-- item, each its own Load*MailGFX routine painting a border, a mon and a
-- scattering of icons out of gfx/mail.asm's 1bpp art.  None of that art is in
-- the cache (the extractor has never followed gfx/mail.asm), so this draws the
-- page as a plain full-screen box and puts the two pieces that are DATA rather
-- than tiles exactly where MailGFX_PlaceMessage puts them:
--
--   message  hlcoord 2, 7 -- one PlaceString, so the '<NEXT>' stored at offset
--            MAIL_LINE_LENGTH lands the second line on row 8
--   author   hlcoord 5, 14, except hlcoord 8, 14 for PORTRAITMAIL_INDEX and
--            hlcoord 6, 14 for MORPH_MAIL_INDEX -- those two stationeries have
--            art where the name would otherwise sit
--
-- .loop reads A, B and START and exits on any of them (START is the printer,
-- which this port has no path for; the VC builds mask it off entirely with
-- the Forbid_printing_mail patch, so treating it as an exit is the VC
-- behaviour rather than an invention).

local Chrome = require("src.ui.gen2.Chrome")
local Mail = require("src.core.gen2.Mail")

local MailRead = {}
MailRead.__index = MailRead
MailRead.isOpaque = true

local MESSAGE_X, MESSAGE_Y = 2, 7
local AUTHOR_Y = 14

function MailRead:wantsFillScale() return true end
function MailRead:drawsWidescreen() return true end

-- opts: entry (a `mailmsg` from src/core/gen2/Mail.lua), onClose()
function MailRead.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MailRead)
  self.game = game
  self.entry = opts.entry
  self.onClose = opts.onClose
  return self
end

-- MailGFX_PlaceMessage's three author columns, picked by wCurMailIndex --
-- which .LoadGFX set from the mail's TYPE byte by walking MailGFXPointers, so
-- it is the *_MAIL_INDEX of the stationery and nothing else.
function MailRead:authorColumn()
  local index = Mail.INDEX[self.entry and self.entry.type or ""]
  if index == Mail.INDEX.PORTRAITMAIL then return 8 end
  if index == Mail.INDEX.MORPH_MAIL then return 6 end
  return 5
end

function MailRead:close()
  if self.onClose then self.onClose() end
end

function MailRead:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("a") or input:wasPressed("b")
      or input:wasPressed("start") then
    self:close()
  end
end

function MailRead:drawPanel()
  Chrome.clear()
  -- DrawMailBorder frames the whole 20x18 page; without the stationery tiles
  -- the shared box frame is the honest stand-in.
  Chrome.box(0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)

  local top, bottom = Mail.lines(self.entry)
  Chrome.print(top, MESSAGE_X, MESSAGE_Y)
  if bottom ~= "" then Chrome.print(bottom, MESSAGE_X, MESSAGE_Y + 1) end

  -- MailGFX_PlaceMessage returns early when the author field is empty
  -- (`ld a, [de] / and a / ret z`), so a blank author draws nothing at all
  -- rather than an empty line under the message.
  local author = self.entry and self.entry.author or ""
  if author ~= "" then
    Chrome.print(author, self:authorColumn(), AUTHOR_Y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function MailRead:draw()
  self:drawPanel()
end

function MailRead:drawWidescreen(winW, winH)
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

return MailRead

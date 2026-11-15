package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
}
package.loaded["src.core.game3.audio"] = { playSe = function() end }

local reader = {}
package.loaded["src.ui.game3.mail"] = {
  read = function(mail, opts) reader.mail, reader.opts = mail, opts end,
  japaneseName = function(name) return name end,
}
local party = {}
package.loaded["src.ui.game3.party_menu"] = {
  show = function(p, _, opts) party.list, party.opts = p, opts end,
}

local Mail = require("src.core.game3.mail")
local Mailbox = require("src.ui.game3.mailbox")

local function input(key)
  return { wasPressed = function(_, k) return k == key end }
end
local function press(key) Mailbox.handleInput(input(key)) end
local function frames_until(pred)
  for n = 1, 64 do
    Mailbox.update()
    if pred() then return n end
  end
end

local session = { mail = {}, party = {}, bag = {} }
local pool = Mail.pool(session)
pool[Mail.PARTY_SIZE + 1].itemId = 121
pool[Mail.PARTY_SIZE + 1].playerName = "RED"
pool[Mail.PARTY_SIZE + 2].itemId = 127
pool[Mail.PARTY_SIZE + 2].playerName = "BLUE"

Mailbox.show({ session = session })
press("a")
check(Mailbox.state == "options", "A on a mail opens the what-to-do menu")

Mailbox.optCursor = 3
press("a")
check(Mailbox.state == "message" and Mailbox._status == "gText_ThereIsNoPokemon",
  "GIVE with no party prints gText_ThereIsNoPokemon (player_pc.c:716)")
press("a")
check(Mailbox.state == "list", "the no-pokemon message returns to the list")

press("a")
Mailbox.optCursor = 1
press("a")
check(reader.mail == nil and Mailbox._fadeDir == 1, "READ fades to black before the reader opens (player_pc.c:558)")
press("b")
check(Mailbox.state == "options", "input is ignored while the screen fades")
local n = frames_until(function() return reader.mail ~= nil end)
check(n == 8, "the fade to black takes 8 frames at FadeScreen delay 0 (" .. tostring(n) .. ")")
check(reader.mail == pool[Mail.PARTY_SIZE + 1] and Mailbox.state == "reading", "the reader opens on the selected mail")

reader.opts.onClose()
check(Mailbox.state == "list" and Mailbox._fade == 16, "closing the reader returns to a black mailbox list")
n = frames_until(function() return (Mailbox._fadeDir or 0) == 0 end)
check(n == 8 and Mailbox._fade == 0, "the mailbox fades in from black (player_pc.c:592)")

session.party = { { species = 1, item = 0 } }
press("a")
Mailbox.optCursor = 3
press("a")
check(party.opts == nil and Mailbox._fadeDir == 1, "GIVE fades to black before the party opens (player_pc.c:665)")
n = frames_until(function() return party.opts ~= nil end)
check(n == 8 and party.opts.fadeIn == true and party.opts.mode == "choose",
  "the party opens in choose mode and fades in from black")
party.opts.onClose()
check(Mailbox.state == "list" and Mailbox._fade == 16, "leaving the party returns to a black mailbox list")
Mailbox.reset()

local src = assert(io.open("src/ui/game3/mail.lua")):read("*a")
check(not src:find("designOf%(%d"), "mail designs come from item constants, not bare item numbers")
local draw = src:match("function MailRead%.draw%(%)(.-)\nend")
check(draw ~= nil and not draw:find("rgb%(") and not draw:find("fg%s*="),
  "the reader builds its colour table once per read, not every draw")

T.finish("game3_frlg_mailbox_fade")

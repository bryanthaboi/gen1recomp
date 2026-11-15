package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  key = function(key, i) return key .. i end,
}
package.loaded["src.core.game3.audio"] = { playSe = function() end }

local rs = false
package.loaded["src.ui.game3.rs.player_pc_policy"] = { matches = function() return rs end }
local reader = {}
package.loaded["src.ui.game3.rse.mail"] = {
  read = function(mail, opts) reader.mail, reader.opts, reader.rs = mail, opts, false end,
}
package.loaded["src.ui.game3.rs.mail_reader"] = {
  read = function(mail, opts) reader.mail, reader.opts, reader.rs = mail, opts, true end,
}
local party = {}
package.loaded["src.ui.game3.party_menu"] = {
  show = function(p, _, opts) party.list, party.opts = p, opts end,
}

local Mail = require("src.core.game3.mail")
local Mailbox = require("src.ui.game3.rse.mailbox")

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

local function run(version)
  rs = version == "ruby"
  reader.mail, reader.opts, party.opts = nil, nil, nil
  local session = { mail = {}, party = {}, bag = {} }
  local pool = Mail.pool(session)
  pool[Mail.PARTY_SIZE + 1].itemId = 121
  pool[Mail.PARTY_SIZE + 1].playerName = "MAY"
  pool[Mail.PARTY_SIZE + 2].itemId = 122
  pool[Mail.PARTY_SIZE + 2].playerName = "WALLY"

  Mailbox.show({ session = session })
  press("a")
  check(Mailbox.state == "options", version .. " A on a mail opens the what-to-do menu")
  Mailbox.optCursor = 1
  press("a")
  check(reader.mail == nil and Mailbox._fadeDir == 1, version .. " READ fades to black before the reader opens")
  press("b")
  check(Mailbox.state == "options", version .. " input is ignored while the screen fades")
  local n = frames_until(function() return reader.mail ~= nil end)
  check(n == 8, version .. " the fade to black takes 8 frames at FadeScreen delay 0 (" .. tostring(n) .. ")")
  check(reader.mail == pool[Mail.PARTY_SIZE + 1] and Mailbox.state == "reading" and reader.rs == rs,
    version .. " the reader opens on the selected mail")
  reader.opts.onClose()
  check(Mailbox.state == "list" and Mailbox._fade == 16, version .. " closing the reader returns to a black mailbox list")
  n = frames_until(function() return (Mailbox._fadeDir or 0) == 0 end)
  check(n == 8 and Mailbox._fade == 0, version .. " the mailbox fades in from black")

  session.party = { { species = 1, item = 0 } }
  press("a")
  Mailbox.optCursor = 3
  press("a")
  check(party.opts == nil and Mailbox._fadeDir == 1, version .. " GIVE fades to black before the party opens")
  n = frames_until(function() return party.opts ~= nil end)
  check(n == 8 and party.opts.mode == "choose" and Mailbox.state == "party",
    version .. " the party opens in choose mode after the fade (" .. tostring(n) .. ")")
  check(party.opts.fadeIn == (not rs), version .. " the party fades in from black (RS party chrome fades itself)")
  party.opts.onClose()
  check(Mailbox.state == "list" and Mailbox._fade == 16, version .. " leaving the party returns to a black mailbox list")
  n = frames_until(function() return (Mailbox._fadeDir or 0) == 0 end)
  check(n == 8 and Mailbox._fade == 0, version .. " the mailbox fades back in after the party")
  Mailbox.reset()
end

run("emerald")
run("ruby")

T.finish("game3_rse_mailbox_fade")

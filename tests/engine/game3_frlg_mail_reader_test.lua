package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local MailRead = require("src.ui.game3.mail")
local Mailbox = require("src.ui.game3.mailbox")
local Mail = require("src.core.game3.mail")

local red = MailRead.authorName("RED")
check(red ~= "RED" and red == "\xEF\xBC\xB2\xEF\xBC\xA5\xEF\xBC\xA4",
  "a sender name under six letters is printed with the Japanese glyphs (mail.c:653)")
check(MailRead.authorName("LEAFGRN") == "LEAFGRN", "a seven-letter name stays in the Latin font")
check(Mailbox.senderName({ playerName = "BLUE" }) == MailRead.japaneseName("BLUE"),
  "the mailbox list prints names of five letters or fewer in Japanese (mailbox_pc.c:88)")
check(Mailbox.senderName({ playerName = "GREENER" }) == "GREENER", "longer mailbox names stay Latin")

check(MailRead.iconSpecies(25) == 25, "a plain species is its own icon")
check(MailRead.iconSpecies(Mail.speciesToMailSpecies(201, 0)) == 201, "UNOWN A uses the base icon")
local b = Mail.speciesToMailSpecies(201, 1)
check(MailRead.iconSpecies(b) == 413, "UNOWN B maps to SPECIES_UNOWN_B (pokemon_icon.c:1088)")

local session = { mail = {} }
local pool = Mail.pool(session)
pool[9].itemId = 121
pool[12].itemId = 125
check(Mailbox.countFor(session) == 2, "CountPCMail counts PC slots only")
pool[3].itemId = 121
check(Mailbox.countFor(session) == 2, "party mail slots are not in the PC count")

local plan = require("src.import.gba.plans.frlg")
local inPlan = false
for _, e in ipairs(plan.aux) do if e.name == "mail_extract" then inPlan = true end end
check(inPlan and plan.auxSteps == #plan.aux, "the FRLG import plan runs the mail extractor")
local listed = false
for _, name in ipairs(require("src.core.game3.profiles.firered").extractors) do
  if name == "mail_extract" then listed = true end
end
check(listed, "the FireRed/LeafGreen profile wants the mail extractor")
check(#require("src.import.gba.mail_extract").REQUIRED == 25, "the extractor lists the manifest and 24 baked designs")

T.finish("game3_frlg_mail_reader")

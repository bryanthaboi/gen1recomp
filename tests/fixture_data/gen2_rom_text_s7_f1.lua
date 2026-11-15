local Fixture = {}

Fixture.RAW = {
  ["_OakPCText1"] = "Want to get your\nPOKéDEX rated?{DONE}",
  ["_OakPCText2"] = "Current POKéDEX\ncompletion level:{PROMPT}",
  ["_OakPCText3"] = "{STRBUF} POKéMON seen\n{STRBUF} POKéMON owned\12PROF.OAK's\nRating:{DONE}",
  ["_OakPCText4"] = "The link to PROF.\nOAK's PC closed.{DONE}",
  ["_PokecenterPCCantUseText"] = "Bzzzzt! You must\nhave a POKéMON to\11use this!{PROMPT}",
  ["_PokecenterPCTurnOnText"] = "{PLAYER} turned on\nthe PC.{PROMPT}",
  ["_PokecenterPCWhoseText"] = "Access whose PC?{DONE}",
  ["_PokecenterBillsPCText"] = "BILL's PC\naccessed.\12POKéMON Storage\nSystem opened.{PROMPT}",
  ["_PokecenterPlayersPCText"] = "Accessed own PC.\12Item Storage\nSystem opened.{PROMPT}",
  ["_PokecenterOaksPCText"] = "PROF.OAK's PC\naccessed.\12POKéDEX Rating\nSystem opened.{PROMPT}",
  ["_PokecenterPCOaksClosedText"] = "…\nLink closed…{DONE}",
  ["PokemonCenterPC.String_BillsPC"] = "BILL's PC",
  ["PokemonCenterPC.String_PlayersPC"] = "{PLAYER}'s PC",
  ["PokemonCenterPC.String_OaksPC"] = "PROF.OAK's PC",
  ["PokemonCenterPC.String_HallOfFame"] = "HALL OF FAME",
  ["PokemonCenterPC.String_TurnOff"] = "TURN OFF",
  ["YesNoMenuHeader.MenuData#1"] = "YES",
  ["YesNoMenuHeader.MenuData#2"] = "NO",
  ["_MomLeavingText1"] = "Wow, that's a cute\nPOKéMON.\12Where did you get\nit?\12…\12So, you're leaving\non an adventure…\12OK!\nI'll help too.\12But what can I do\nfor you?\12I know! I'll save\nmoney for you.\12On a long journey,\nmoney's important.\12Do you want me to\nsave your money?{DONE}",
  ["_MomLeavingText2"] = "OK, I'll take care\nof your money.\12………………{PROMPT}",
  ["_MomLeavingText3"] = "Be careful.\12POKéMON are your\nfriends. You need\11to work as a team.\12Now, go on!{DONE}",
  ["_MomIsThisAboutYourMoneyText"] = "Hi! Welcome home!\nYou're trying very\11hard, I see.\12I've kept your\nroom tidy.\12Or is this about\nyour money?{DONE}",
  ["_MomBankWhatDoYouWantToDoText"] = "What do you want\nto do?{DONE}",
  ["_MomStoreMoneyText"] = "How much do you\nwant to save?{DONE}",
  ["_MomTakeMoneyText"] = "How much do you\nwant to take?{DONE}",
  ["_MomSaveMoneyText"] = "Do you want to\nsave some money?{DONE}",
  ["_MomHaventSavedThatMuchText"] = "You haven't saved\nthat much.{PROMPT}",
  ["_MomNotEnoughRoomInWalletText"] = "You can't take\nthat much.{PROMPT}",
  ["_MomInsufficientFundsInWalletText"] = "You don't have\nthat much.{PROMPT}",
  ["_MomNotEnoughRoomInBankText"] = "You can't save\nthat much.{PROMPT}",
  ["_MomStartSavingMoneyText"] = "OK, I'll save your\nmoney. Trust me!\12{PLAYER}, stick\nwith it!{DONE}",
  ["_MomStoredMoneyText"] = "Your money's safe\nhere! Get going!{DONE}",
  ["_MomTakenMoneyText"] = "{PLAYER}, don't\ngive up!{DONE}",
  ["_MomJustDoWhatYouCanText"] = "Just do what\nyou can.{DONE}",
  ["BankOfMom_MenuHeader.MenuData#1"] = "GET",
  ["BankOfMom_MenuHeader.MenuData#2"] = "SAVE",
  ["BankOfMom_MenuHeader.MenuData#3"] = "CHANGE",
  ["BankOfMom_MenuHeader.MenuData#4"] = "CANCEL",
  ["Mom_SavedString"] = "SAVED",
  ["Mom_HeldString"] = "HELD",
  ["Mom_DepositString"] = "DEPOSIT",
  ["Mon_WithdrawString"] = "WITHDRAW",
  ["_WhichMonPhotoText"] = "Which POKéMON\nshould I photo-\11graph?{PROMPT}",
  ["_HoldStillText"] = "All righty. Hold\nstill for a bit.{PROMPT}",
  ["_NoPhotoText"] = "Oh, no picture?\nCome again, OK?{DONE}",
  ["_EggPhotoText"] = "An EGG? My talent\nis worth more…{DONE}",
  ["_AlreadyASaveFileText"] = "There is already a\nsave file. Is it\11OK to overwrite?{DONE}",
  ["_AnotherSaveFileText"] = "There is another\nsave file. Is it\11OK to overwrite?{DONE}",
  ["_SavingDontTurnOffThePowerText"] = "SAVING… DON'T TURN\nOFF THE POWER.{DONE}",
  ["_SavedTheGameText"] = "{PLAYER} saved\nthe game.{DONE}",
  ["SpecialShuckleOT"] = "MANIA",
  ["SpecialShuckleNickname"] = "SHUCKIE",
  ["_ReceivedItemText"] = "{PLAYER} received\n{STRBUF}.{DONE}",
  ["_PutItemInPocketText"] = "{PLAYER} put the\n{STRBUF} in\11the {STRBUF}.{PROMPT}",
  ["_PocketIsFullText"] = "The {STRBUF}\nis full…{PROMPT}",
  ["_FruitBearingTreeText"] = "It's a fruit-\nbearing tree.{DONE}",
  ["_HeyItsFruitText"] = "Hey! It's\n{STRBUF}!{DONE}",
  ["_ObtainedFruitText"] = "Obtained\n{STRBUF}!{DONE}",
  ["_FruitPackIsFullText"] = "But the PACK is\nfull…{DONE}",
  ["_NothingHereText"] = "There's nothing\nhere…{DONE}",
  ["_PhoneClickText"] = "Click!{DONE}",
  ["ItemPocketNames.Item"] = "ITEM POCKET",
  ["ItemPocketNames.Key"] = "KEY POCKET",
  ["ItemPocketNames.Ball"] = "BALL POCKET",
  ["ItemPocketNames.TM"] = "TM POCKET",
  ["PrintParty_OTString"] = "OT/",
  ["PrintParty_IDNoString"] = "”·",
  ["PrintParty_MoveString"] = "MOVE",
  ["PrintParty_NoMoveString"] = "------------",
  ["Kurt_SelectApricorn.Cancel"] = "CANCEL",
  ["ScrollingMenu_UpdateDisplay.CancelString"] = "CANCEL",
  ["_OakRating01"] = "Look for POKéMON\nin grassy areas!{DONE}",
  ["_OakRating02"] = "Good. I see you\nunderstand how to\11use POKé BALLS.{DONE}",
  ["_OakRating03"] = "You're getting\ngood at this.\12But you have a\nlong way to go.{DONE}",
  ["_OakRating04"] = "You need to fill\nup the POKéDEX.\12Catch different\nkinds of POKéMON!{DONE}",
  ["_OakRating05"] = "You're trying--I\ncan see that.\12Your POKéDEX is\ncoming together.{DONE}",
  ["_OakRating06"] = "To evolve, some\nPOKéMON grow,\12others use the\neffects of STONES.{DONE}",
  ["_OakRating07"] = "Have you gotten a\nfishing ROD? You\12can catch POKéMON\nby fishing.{DONE}",
  ["_OakRating08"] = "Excellent! You\nseem to like col-\11lecting things!{DONE}",
  ["_OakRating09"] = "Some POKéMON only\nappear during\12certain times of\nthe day.{DONE}",
  ["_OakRating10"] = "Your POKéDEX is\nfilling up. Keep\11up the good work!{DONE}",
  ["_OakRating11"] = "I'm impressed.\nYou're evolving\12POKéMON, not just\ncatching them.{DONE}",
  ["_OakRating12"] = "Have you met KURT?\nHis custom POKé\11BALLS should help.{DONE}",
  ["_OakRating13"] = "Wow. You've found\nmore POKéMON than\12the last POKéDEX\nresearch project.{DONE}",
  ["_OakRating14"] = "Are you trading\nyour POKéMON?\12It's tough to do\nthis alone!{DONE}",
  ["_OakRating15"] = "Wow! You've hit\n200! Your POKéDEX\11is looking great!{DONE}",
  ["_OakRating16"] = "You've found so\nmany POKéMON!\12You've really\nhelped my studies!{DONE}",
  ["_OakRating17"] = "Magnificent! You\ncould become a\12POKéMON professor\nright now!{DONE}",
  ["_OakRating18"] = "Your POKéDEX is\namazing! You're\12ready to turn\nprofessional!{DONE}",
  ["_OakRating19"] = "Whoa! A perfect\nPOKéDEX! I've\12dreamt about this!\nCongratulations!{DONE}",
  ["OakRating01"] = "Look for POKéMON\nin grassy areas!{DONE}",
  ["OakRating02"] = "Good. I see you\nunderstand how to\11use POKé BALLS.{DONE}",
  ["OakRating03"] = "You're getting\ngood at this.\12But you have a\nlong way to go.{DONE}",
  ["OakRating04"] = "You need to fill\nup the POKéDEX.\12Catch different\nkinds of POKéMON!{DONE}",
  ["OakRating05"] = "You're trying--I\ncan see that.\12Your POKéDEX is\ncoming together.{DONE}",
  ["OakRating06"] = "To evolve, some\nPOKéMON grow,\12others use the\neffects of STONES.{DONE}",
  ["OakRating07"] = "Have you gotten a\nfishing ROD? You\12can catch POKéMON\nby fishing.{DONE}",
  ["OakRating08"] = "Excellent! You\nseem to like col-\11lecting things!{DONE}",
  ["OakRating09"] = "Some POKéMON only\nappear during\12certain times of\nthe day.{DONE}",
  ["OakRating10"] = "Your POKéDEX is\nfilling up. Keep\11up the good work!{DONE}",
  ["OakRating11"] = "I'm impressed.\nYou're evolving\12POKéMON, not just\ncatching them.{DONE}",
  ["OakRating12"] = "Have you met KURT?\nHis custom POKé\11BALLS should help.{DONE}",
  ["OakRating13"] = "Wow. You've found\nmore POKéMON than\12the last POKéDEX\nresearch project.{DONE}",
  ["OakRating14"] = "Are you trading\nyour POKéMON?\12It's tough to do\nthis alone!{DONE}",
  ["OakRating15"] = "Wow! You've hit\n200! Your POKéDEX\11is looking great!{DONE}",
  ["OakRating16"] = "You've found so\nmany POKéMON!\12You've really\nhelped my studies!{DONE}",
  ["OakRating17"] = "Magnificent! You\ncould become a\12POKéMON professor\nright now!{DONE}",
  ["OakRating18"] = "Your POKéDEX is\namazing! You're\12ready to turn\nprofessional!{DONE}",
  ["OakRating19"] = "Whoa! A perfect\nPOKéDEX! I've\12dreamt about this!\nCongratulations!{DONE}",
}

Fixture.crystal = {
  ["PrintParty_IDNoString"] = "”·.",
  ["_OakRating12"] = "Have you met KURT?\nHis custom BALLS\11should help.{DONE}",
  ["OakRating12"] = "Have you met KURT?\nHis custom BALLS\11should help.{DONE}",
}

Fixture.crystalAbsent = {
  "Kurt_SelectApricorn.Cancel",
}

Fixture.EVENTS = {
  oakRatings = {
    { max = 9, sfx = "Sfx_DexFanfareLessThan20", text = "OakRating01" },
    { max = 19, sfx = "Sfx_DexFanfareLessThan20", text = "OakRating02" },
    { max = 34, sfx = "Sfx_DexFanfare2049", text = "OakRating03" },
    { max = 49, sfx = "Sfx_DexFanfare2049", text = "OakRating04" },
    { max = 64, sfx = "Sfx_DexFanfare5079", text = "OakRating05" },
    { max = 79, sfx = "Sfx_DexFanfare5079", text = "OakRating06" },
    { max = 94, sfx = "Sfx_DexFanfare80109", text = "OakRating07" },
    { max = 109, sfx = "Sfx_DexFanfare80109", text = "OakRating08" },
    { max = 124, sfx = "Sfx_CaughtMon", text = "OakRating09" },
    { max = 139, sfx = "Sfx_CaughtMon", text = "OakRating10" },
    { max = 154, sfx = "Sfx_DexFanfare140169", text = "OakRating11" },
    { max = 169, sfx = "Sfx_DexFanfare140169", text = "OakRating12" },
    { max = 184, sfx = "Sfx_DexFanfare170199", text = "OakRating13" },
    { max = 199, sfx = "Sfx_DexFanfare170199", text = "OakRating14" },
    { max = 214, sfx = "Sfx_DexFanfare200229", text = "OakRating15" },
    { max = 229, sfx = "Sfx_DexFanfare200229", text = "OakRating16" },
    { max = 239, sfx = "Sfx_DexFanfare230Plus", text = "OakRating17" },
    { max = 248, sfx = "Sfx_DexFanfare230Plus", text = "OakRating18" },
    { max = 255, sfx = "Sfx_DexFanfare230Plus", text = "OakRating19" },
  },
  haircutTables = {
    older = {
      { 76, 2, "OLDERCUT1" },
      { 128, 3, "OLDERCUT2" },
      { 255, 4, "OLDERCUT3" },
    },
    younger = {
      { 154, 2, "YOUNGCUT1" },
      { 76, 3, "YOUNGCUT2" },
      { 255, 4, "YOUNGCUT3" },
    },
    daisy = {
      { 255, 2, "GROOMING" },
    },
  },
}

function Fixture.text(extra, version)
  local text = {}
  for label, body in pairs(Fixture.RAW) do text[label] = body end
  if version == "crystal" then
    for label, body in pairs(Fixture.crystal) do text[label] = body end
    for _, label in ipairs(Fixture.crystalAbsent) do text[label] = nil end
  end
  for key, value in pairs(extra or {}) do text[key] = value end
  return text
end

function Fixture.without(label, version)
  local text = Fixture.text(nil, version)
  text[label] = nil
  return text
end

function Fixture.events(extra)
  local events = {}
  for key, value in pairs(Fixture.EVENTS) do events[key] = value end
  for key, value in pairs(extra or {}) do events[key] = value end
  return events
end

return Fixture

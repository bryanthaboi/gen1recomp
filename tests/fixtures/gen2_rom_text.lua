local Fixture = {}

Fixture.RAW = {
  ["_AnEggCantHoldAnItemText"] = "An EGG can't hold\nan item.{PROMPT}",
  ["_AskDeleteMoveText"] = "Oh, make it forget\n{STRBUF}?{DONE}",
  ["_AskItemMoveText"] = "Where should this\nbe moved to?{DONE}",
  ["_AskQuantityThrowAwayText"] = "Throw away {NUM}\n{STRBUF}(S)?{DONE}",
  ["_AskThrowAwayText"] = "Throw away how\nmany?{DONE}",
  ["_CantRegisterText"] = "You can't register\nthat item.{PROMPT}",
  ["_CaughtAskNicknameText"] = "Give a nickname to\nthe {STRBUF} you\11received?{DONE}",
  ["_CoinCaseCountText"] = "Coins:\n{NUM}{DONE}",
  ["_ContestJudging_FirstPlaceScoreText"] = "\12The winning score\nwas {NUM} points!{PROMPT}",
  ["_ContestJudging_FirstPlaceText"] = "This Bug-Catching\nContest winner is…\12{STRBUF},\nwho caught a\11{STRBUF}!",
  ["_ContestJudging_SecondPlaceScoreText"] = "\12The score was\n{NUM} points!{PROMPT}",
  ["_ContestJudging_SecondPlaceText"] = "Placing second was\n{STRBUF},\12who caught a\n{STRBUF}!",
  ["_ContestJudging_ThirdPlaceScoreText"] = "\12The score was\n{NUM} points!{PROMPT}",
  ["_ContestJudging_ThirdPlaceText"] = "Placing third was\n{STRBUF},\12who caught a\n{STRBUF}!",
  ["_DSTIsThatOKText"] = " DST,\nis that OK?{DONE}",
  ["_DeleterAskWhichMonText"] = "Which POKéMON?{PROMPT}",
  ["_DeleterAskWhichMoveText"] = "Which move should\nit forget, then?{PROMPT}",
  ["_DeleterEggText"] = "An EGG doesn't\nknow any moves!{DONE}",
  ["_DeleterForgotMoveText"] = "Done! Your POKéMON\nforgot the move.{DONE}",
  ["_DeleterIntroText"] = "Um… Oh, yes, I'm\nthe MOVE DELETER.\12I can make POKéMON\nforget moves.\12Shall I make a\nPOKéMON forget?{DONE}",
  ["_DeleterNoComeAgainText"] = "No? Come visit me\nagain.{DONE}",
  ["_ItemUsedText"] = "{PLAYER} used the\n{STRBUF}.{DONE}",
  ["_KnowsMoveText"] = "{STRBUF} knows\n{STRBUF}.{PROMPT}",
  ["_MoveKnowsOneText"] = "That POKéMON knows\nonly one move.{DONE}",
  ["_NameRaterBetterNameText"] = "Hm… {STRBUF}…\nThat's a fairly\11decent name.\12But, how about a\nslightly better\11nickname?\12Want me to give it\na better name?{DONE}",
  ["_NameRaterComeAgainText"] = "OK, then. Come\nagain sometime.{DONE}",
  ["_NameRaterEggText"] = "Whoa… That's just\nan EGG.{DONE}",
  ["_NameRaterFinishedText"] = "That's a better\nname than before!\12Well done!{DONE}",
  ["_NameRaterHelloText"] = "Hello, hello! I'm\nthe NAME RATER.\12I rate the names\nof POKéMON.\12Would you like me\nto rate names?{DONE}",
  ["_NameRaterNamedText"] = "All right. This\nPOKéMON is now\11named {STRBUF}.{PROMPT}",
  ["_NameRaterPerfectNameText"] = "Hm… {STRBUF}?\nWhat a great name!\11It's perfect.\12Treat {STRBUF}\nwith loving care.{DONE}",
  ["_NameRaterSameNameText"] = "It might look the\nsame as before,\12but this new name\nis much better!\12Well done!{DONE}",
  ["_NameRaterWhatNameText"] = "All right. What\nname should we\11give it, then?{PROMPT}",
  ["_NameRaterWhichMonText"] = "Which POKéMON's\nnickname should I\11rate for you?{PROMPT}",
  ["_NoCoinCaseText"] = "You don't have a\nCOIN CASE.{PROMPT}",
  ["_NoCoinsText"] = "You have no coins.{PROMPT}",
  ["_OakThisIsntTheTimeText"] = "OAK: {PLAYER}!\nThis isn't the\11time to use that!{PROMPT}",
  ["_RegisteredItemText"] = "Registered the\n{STRBUF}.{PROMPT}",
  ["_RepelUsedEarlierIsStillInEffectText"] = "The REPEL used\nearlier is still\11in effect.{PROMPT}",
  ["_SentTrophyHomeText"] = "There was a trophy\ninside!\12{STRBUF} sent the\ntrophy home.{PROMPT}",
  ["_TMHMNotCompatibleText"] = "{STRBUF} is\nnot compatible\11with {STRBUF}.\12It can't learn\n{STRBUF}.{PROMPT}",
  ["_ThrewAwayText"] = "Threw away\n{STRBUF}(S).{PROMPT}",
  ["_TimeAskOkayText"] = ",\nis that OK?{DONE}",
  ["_YouDontHaveAMonText"] = "You don't have a\nPOKéMON!{PROMPT}",
  ["_BlueCardBalanceText"] = "You now have\n{NUM} points.{DONE}",
}

function Fixture.text(extra)
  local text = {}
  for label, body in pairs(Fixture.RAW) do text[label] = body end
  for key, value in pairs(extra or {}) do text[key] = value end
  return text
end

return Fixture

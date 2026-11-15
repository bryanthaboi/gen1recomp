return function(text)
  text = text or {}
  text.Text_BallCaught = "Gotcha! {STRBUF}\nwas caught!"
  text._NewDexDataText = "{STRBUF}'s data\nwas newly added to\vthe POKéDEX."
  text._AskGiveNicknameText = "Give a nickname to\n{STRBUF}?{DONE}"
  text._ContestCaughtMonText = "Caught {STRBUF}!{PROMPT}"
  text._ContestAlreadyCaughtText = "You already caught\na {STRBUF}.{PROMPT}"
  text._BallSentToPCText = text._BallSentToPCText or "{STRBUF} was\nsent to BILL's PC.{PROMPT}"
  return text
end

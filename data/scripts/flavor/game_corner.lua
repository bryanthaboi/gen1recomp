-- Flavor dialogue for GameCorner (pokered/scripts/GameCorner.asm)
--
-- TEXT_GAMECORNER_CLERK1, TEXT_GAMECORNER_GYM_GUIDE and
-- TEXT_GAMECORNER_POSTER are already ported on data/scripts/story3.lua's
-- and story7.lua's M.GAME_CORNER tables. This file ports the three
-- remaining coin-giveaway NPCs, each a one-shot "give N coins" gated by
-- its own EVENT_GOT_*_COINS flag, the COIN CASE, and Has9990Coins room
-- to receive them (mirroring GameCornerClerk1Text's coin-case/coin-cap
-- checks in story3.lua).
local function coinGiver(opts)
  return function(game, ow, npc, done)
    local TextBox = require("src.render.TextBox")
    local t = game.data.text
    local function push(label, onDone, popts)
      game.stack:push(TextBox.new(game, t[label], onDone or done, popts))
    end
    if game.save.flags[opts.event] then
      push(opts.alreadyGotLabel)
      return
    end
    push(opts.askLabel, function()
      if not game.save.inventory.COIN_CASE then
        push("_GameCornerOopsForgotCoinCaseText")
        return
      end
      local coins = game.save.coins or 0
      if (opts.exact9990 and coins == 9990)
          or (not opts.exact9990 and coins >= 9990) then
        push(opts.coinCaseFullLabel)
        return
      end
      game.save.coins = math.min(9999, (game.save.coins or 0) + opts.amount)
      game.save.flags[opts.event] = true
      -- the ReceivedNCoinsText strings carry sound_get_item_1
      push(opts.receivedLabel, nil, TextBox.soundOpts(game, "Get_Item1"))
    end)
  end
end

return {
  GAME_CORNER = {
    talk = {
      -- GameCornerFishingGuruText (pokered/scripts/GameCorner.asm):
      -- gives 10 coins once (EVENT_GOT_10_COINS).
      TEXT_GAMECORNER_FISHING_GURU = coinGiver({
        event = "EVENT_GOT_10_COINS",
        amount = 10,
        askLabel = "_GameCornerFishingGuruWantToPlayText",
        receivedLabel = "_GameCornerFishingGuruReceived10CoinsText",
        coinCaseFullLabel = "_GameCornerFishingGuruDontNeedMyCoinsText",
        alreadyGotLabel = "_GameCornerFishingGuruWinsComeAndGoText",
      }),

      -- GameCornerClerk2Text (pokered/scripts/GameCorner.asm): gives 20
      -- coins once (EVENT_GOT_20_COINS_2).
      TEXT_GAMECORNER_CLERK2 = coinGiver({
        event = "EVENT_GOT_20_COINS_2",
        amount = 20,
        askLabel = "_GameCornerClerk2WantSomeCoinsText",
        receivedLabel = "_GameCornerClerk2Received20CoinsText",
        coinCaseFullLabel = "_GameCornerClerk2YouHaveLotsOfCoinsText",
        alreadyGotLabel = "_GameCornerClerk2INeedMoreCoinsText",
      }),

      -- pokered/scripts/GameCorner.asm:378
      TEXT_GAMECORNER_GENTLEMAN = coinGiver({
        event = "EVENT_GOT_20_COINS",
        amount = 20,
        exact9990 = true,
        askLabel = "_GameCornerGentlemanThrowingMeOffText",
        receivedLabel = "_GameCornerGentlemanReceived20CoinsText",
        coinCaseFullLabel = "_GameCornerGentlemanYouGotYourOwnCoinsText",
        alreadyGotLabel = "_GameCornerGentlemanCloselyWatchTheReelsText",
      }),

      -- Yellow keeps all three giveaways with the same events and amounts
      -- but renames the objects and their text labels: FISHING_GURU ->
      -- FISHING_GURU1, CLERK2 -> MIDDLE_AGED_MAN2, GENTLEMAN ->
      -- FISHING_GURU2 (pokeyellow/scripts/GameCorner.asm).  The Red/Blue
      -- keys above never match there, so Yellow needs its own three (#552).
      TEXT_GAMECORNER_FISHING_GURU1 = coinGiver({
        event = "EVENT_GOT_10_COINS",
        amount = 10,
        askLabel = "_GameCornerFishingGuru1WantToPlayText",
        receivedLabel = "_GameCornerFishingGuru1Received10CoinsText",
        coinCaseFullLabel = "_GameCornerFishingGuru1DontNeedMyCoinsText",
        alreadyGotLabel = "_GameCornerFishingGuru1WinsComeAndGoText",
      }),

      TEXT_GAMECORNER_MIDDLE_AGED_MAN2 = coinGiver({
        event = "EVENT_GOT_20_COINS_2",
        amount = 20,
        askLabel = "_GameCornerMiddleAgedMan2WantSomeCoinsText",
        receivedLabel = "_GameCornerMiddleAgedMan2Received20CoinsText",
        coinCaseFullLabel = "_GameCornerMiddleAgedMan2YouHaveLotsOfCoinsText",
        alreadyGotLabel = "_GameCornerMiddleAgedMan2INeedMoreCoinsText",
      }),

      -- pokeyellow/scripts/GameCorner.asm:382
      TEXT_GAMECORNER_FISHING_GURU2 = coinGiver({
        event = "EVENT_GOT_20_COINS",
        amount = 20,
        exact9990 = true,
        askLabel = "_GameCornerFishingGuru2ThrowingMeOffText",
        receivedLabel = "_GameCornerFishingGuru2Received20CoinsText",
        coinCaseFullLabel = "_GameCornerFishingGuru2YouGotYourOwnCoinsText",
        alreadyGotLabel = "_GameCornerFishingGuru2CloselyWatchTheReelsText",
      }),
    },
  },
}

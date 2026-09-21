#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local TrainerCard = require("src.ui.game3.trainer_card")

local function index(list)
  local by = {}
  for _, e in ipairs(list) do by[e.id] = e end
  return by
end

print("[test] 1. Front: labels sit at the window-1 offsets pret prints them at")
-- src/trainer_card.c:224 window 1 is tilemapLeft 1 / tilemapTop 1, so screen = local + (8, 8)
local rich = TrainerCard.cardData({
  name = "RED",
  trainerId = 12345,
  money = 3500,
  playTimeHours = 7,
  playTimeMinutes = 5,
  flags = { [0x829] = true },
  dex = { caught = { [1] = true, [4] = true, [7] = true } },
})
local f = index(TrainerCard.frontTexts(rich, false))

-- src/trainer_card.c:1122 sTrainerCardFrontNameXPositions[0] = 0x14, YPositions[0] = 0x1D
eq(f.name.x, 28, "front name x")
eq(f.name.y, 37, "front name y")
eq(f.name.text, "NAME: RED", "front name concatenates gText_TrainerCardName")

-- src/trainer_card.c:1135 sTrainerCardIdXPositions[0] = 0x8E, YPositions[0] = 0xA
eq(f.id.x, 150, "front IDNo x")
eq(f.id.y, 18, "front IDNo y")
eq(f.id.text, "IDNo.12345", "IDNo. uses STR_CONV_MODE_LEADING_ZEROS width 5")

-- src/trainer_card.c:1145 label at (20, 56), value at x = -122 - 6 * StringLength(buffer)
eq(f.money_label.x, 28, "MONEY label x")
eq(f.money_label.y, 64, "MONEY label y")
eq(f.money.text, "¥3500", "money string is gText_TrainerCardYen + left-aligned digits")
eq(f.money.x, 8 + 134 - 6 * 5, "money x is 6 px per character from 134, ¥ counting as one")
eq(f.money.y, 64, "money y")

-- src/trainer_card.c:1175 label at (20, 72), value at x = -120 - 6 * StringLength(buffer)
eq(f.dex_label.x, 28, "POKéDEX label x")
eq(f.dex_label.y, 80, "POKéDEX label y")
eq(f.dex.text, "3", "dex count")
eq(f.dex.x, 8 + 136 - 6 * 1, "dex value x is 6 px per digit from 136")

-- src/trainer_card.c:1200 label (20, 88); hours 0x65, colon 0x77, minutes 0x7C, all at y 0x58
eq(f.time_label.x, 28, "TIME label x")
eq(f.time_label.y, 96, "TIME label y")
eq(f.hours.x, 109, "hours x")
eq(f.hours.y, 96, "hours y")
eq(f.hours.text, "  7", "hours use STR_CONV_MODE_RIGHT_ALIGN width 3")
eq(f.colon.x, 127, "colon x")
eq(f.minutes.x, 132, "minutes x")
eq(f.minutes.text, "05", "minutes use STR_CONV_MODE_LEADING_ZEROS width 2")

print("[test] 2. Front: POKéDEX line only once FLAG_SYS_POKEDEX_GET is set")
-- src/trainer_card.c:1177 if (FlagGet(FLAG_SYS_POKEDEX_GET))
local noDex = TrainerCard.cardData({ name = "RED", dex = { caught = { [1] = true } } })
local fn = index(TrainerCard.frontTexts(noDex, false))
check(fn.dex == nil, "no POKéDEX value without the flag")
check(fn.dex_label == nil, "no POKéDEX label without the flag")
check(fn.money ~= nil, "MONEY still prints without the dex")

print("[test] 3. Front: the blinking colon disappears on the invisible half")
-- src/trainer_card.c:1226 sTimeColonTextColors[timeColonInvisible]
local blink = index(TrainerCard.frontTexts(rich, true))
check(blink.colon == nil, "colon is not drawn while timeColonInvisible")
check(blink.hours ~= nil, "hours keep drawing while the colon blinks")

print("[test] 4. Back: every stat line is gated on its own counter")
-- src/trainer_card.c:909 SetDataFromTrainerCard clears hasHofResult/hasLinkResults/hasTrades
local empty = TrainerCard.cardData({ name = "RED", trainerId = 12345 })
local b0 = index(TrainerCard.backTexts(empty))
eq(b0.name.text, "RED", "back name is the bare player name")
-- src/trainer_card.c:1264 sTrainerCardBackNameXPositions[0] = 0x8A, YPositions[0] = 0xB
eq(b0.name.x, 146, "back name x")
eq(b0.name.y, 19, "back name y")
check(b0.id == nil, "the back has no IDNo. line")
check(b0.hof_label == nil, "no HALL OF FAME DEBUT with a zero debut time")
check(b0.link_label == nil, "no LINK BATTLES with zero wins and losses")
check(b0.trades_label == nil, "no POKéMON TRADES with zero trades")
check(b0.union_label == nil, "no UNION TRADES & BATTLES at zero")
check(b0.berry_label == nil, "no BERRY CRUSH at zero")

print("[test] 5. Back: all six lines, at pret's coordinates")
local full = TrainerCard.cardData({
  name = "RED",
  hofDebutHours = 42,
  hofDebutMinutes = 7,
  hofDebutSeconds = 9,
  linkBattleWins = 12,
  linkBattleLosses = 3,
  pokemonTrades = 25,
  unionRoomNum = 6,
  berryCrushPoints = 314,
})
local b = index(TrainerCard.backTexts(full))

-- src/trainer_card.c:1300 label at sTrainerCardHofDebutXPositions[0] = 0xA, y 35; value at 164
eq(b.hof_label.x, 18, "HALL OF FAME DEBUT label x")
eq(b.hof_label.y, 43, "HALL OF FAME DEBUT label y")
eq(b.hof.x, 172, "HOF time x")
eq(b.hof.text, " 42:07:09", "HOF time is right-aligned hours plus two-digit m:s")
check(b.hof.stat, "HOF time uses sTrainerCardStatColors")

-- src/trainer_card.c:1320 label at 10 / y 51, W/L at 130, wins 144, losses 192
eq(b.link_label.y, 59, "LINK BATTLES y")
eq(b.link_label.x, 18, "LINK BATTLES x")
eq(b.link_w.x, 138, "W: x")
eq(b.link_wins.x, 152, "wins x")
eq(b.link_wins.text, "  12", "wins right-aligned to width 4")
eq(b.link_l.x, 186, "L: x from gText_WinLossRatio CLEAR_TO 0x30")
eq(b.link_losses.x, 200, "losses x")
eq(b.link_losses.text, "   3", "losses right-aligned to width 4")

-- src/trainer_card.c:1341 trades label 10 / y 67, count 186
eq(b.trades_label.y, 75, "POKéMON TRADES y")
eq(b.trades.x, 194, "trades count x")
eq(b.trades.text, "   25", "trades right-aligned to width 5")

-- src/trainer_card.c:1381 union label 10 / y 83, count 186
eq(b.union_label.y, 91, "UNION TRADES & BATTLES y")
eq(b.union_label.text, "UNION TRADES & BATTLES", "union label text")
eq(b.union.x, 194, "union count x")

-- src/trainer_card.c:1363 berry crush label 10 / y 99, count 186
eq(b.berry_label.y, 107, "BERRY CRUSH y")
eq(b.berry_label.text, "BERRY CRUSH", "berry crush label text")
eq(b.berry.x, 194, "berry crush count x")
eq(b.berry.text, "  314", "berry crush right-aligned to width 5")
check(b.berry.stat, "berry crush count uses the stat colours")

print("[test] 6. Stars: the four FRLG achievements pick the card colour")
-- src/trainer_card.c:866 TrainerCard_GenerateCardForLinkPlayer
eq(TrainerCard.cardData({}).stars, 0, "fresh save is a 0-star blue card")
eq(TrainerCard.cardData({ hofDebutSeconds = 1 }).stars, 1, "Hall of Fame debut is one star")

local kanto = { caught = {} }
for sp = 1, 150 do kanto.caught[sp] = true end
eq(TrainerCard.cardData({ dex = kanto }).stars, 1, "full Kanto dex is one star")
eq(TrainerCard.cardData({ dex = kanto, hofDebutHours = 3 }).stars, 2, "HoF plus Kanto is two stars")

local national = { caught = {} }
for sp = 1, 150 do national.caught[sp] = true end
for sp = 152, 248 do national.caught[sp] = true end
for sp = 252, 384 do national.caught[sp] = true end
eq(TrainerCard.cardData({ dex = national, hofDebutHours = 3 }).stars, 3, "HoF plus national dex is three stars")
eq(TrainerCard.cardData({
  dex = national,
  hofDebutHours = 3,
  berriesPicked = 200,
  jumpsInRow = 200,
}).stars, 4, "berry picking and Pokémon Jump records give the fourth star")
eq(TrainerCard.cardData({
  dex = national,
  hofDebutHours = 3,
  berriesPicked = 200,
  jumpsInRow = 199,
}).stars, 3, "both minigame records are needed for the fourth star")

print("[test] 7. Back: mon icons and stickers come from the photo-studio vars")
-- src/field_specials.c:1710 UpdateTrainerCardPhotoIcons writes VAR_TRAINER_CARD_MON_ICON_1..6
local photo = TrainerCard.cardData({
  name = "RED",
  vars = { [0x4043] = 1, [0x4044] = 4, [0x4049] = 2 },
})
eq(photo.monSpecies[1], 1, "mon icon slot 1 from VAR_TRAINER_CARD_MON_ICON_1")
eq(photo.monSpecies[2], 4, "mon icon slot 2 from VAR_TRAINER_CARD_MON_ICON_2")
eq(photo.monSpecies[3], 0, "unset icon slots stay empty")
eq(photo.stickers[1], 2, "sticker 1 from VAR_HOF_BRAG_STATE")
eq(photo.stickers[2], 0, "sticker 2 from VAR_EGG_BRAG_STATE")

if failed > 0 then
  print(string.format("[test] %d FAILED", failed))
  os.exit(1)
end
print("[test] all passed")

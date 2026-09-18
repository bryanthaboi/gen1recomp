-- Unit tests for Trainer Dialogue, Behaviors, and Rewards (Prize Money & Routing).

local Prize = require("src.core.game3.battle.prize")
local Trainers = require("src.core.game3.scripting.trainers")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")

local checksPassed = 0
local function check(cond, msg)
  if not cond then
    error("[FAIL] " .. tostring(msg))
  end
  checksPassed = checksPassed + 1
  print("[ok] " .. tostring(msg))
end

print("[test] 1. Prize Money Formula Extraction & Calculation")
-- Youngster (class 57, mult 4): Lv 10 mon -> 4 * 10 * 1 * 1 * 4 = 160
local youngsterMoney = Prize.calc(nil, { class = 57, lastLevel = 10 })
check(youngsterMoney == 160, "Youngster Lv 10 prize money = ¥160")

-- Bug Catcher (class 58, mult 3): Lv 8 mon -> 4 * 8 * 1 * 1 * 3 = 96
local bugCatcherMoney = Prize.calc(nil, { class = 58, lastLevel = 8 })
check(bugCatcherMoney == 96, "Bug Catcher Lv 8 prize money = ¥96")

-- Leader Brock (id 414, class 84, mult 25): Onix Lv 14 -> 4 * 14 * 1 * 1 * 25 = 1400
-- Mock pack if needed
Trainers._pack = {
  trainers = {
    [414] = {
      name = "BROCK",
      class = 84,
      className = "LEADER",
      lastLevel = 14,
      encounterMusic = 1,
      party = { { species = 74, level = 12 }, { species = 95, level = 14 } },
      dialogs = {
        intro = "I'm BROCK!\nI'm PEWTER's GYM LEADER!",
        defeat = "I took you for granted.",
      },
    },
    [102] = {
      name = "RICK",
      class = 58,
      className = "BUG CATCHER",
      lastLevel = 6,
      encounterMusic = 1,
      party = { { species = 10, level = 6 } },
      dialogs = {
        intro = "Hey! You have POKéMON!",
        defeat = "CATERPIE can't hack it!",
      },
    },
  },
}

local brockMoney = Prize.calc(414)
check(brockMoney == 1400, "Leader Brock prize money = ¥1400")

-- Double battle multiplier check
local doubleMoney = Prize.calc(414, { double = true })
check(doubleMoney == 2800, "Double battle doubles prize money (¥2800)")

print("[test] 2. Prize Money Session Application & Cap")
local fakeSession = { money = 500 }
local gained = Prize.awardTrainerWin(fakeSession, 414)
check(gained == 1400, "Awarded ¥1400")
check(fakeSession.money == 1900, "Session money updated to ¥1900")

local maxSession = { money = 999900 }
local maxGained = Prize.apply(maxSession, 200)
check(maxGained == 99, "Gained capped at max money limit (999999)")
check(maxSession.money == 999999, "Money reached MAX_MONEY cap (999999)")

print("[test] 3. Pre-battle Intro Dialogue & Encounter Music Execution")
local openedDialog = nil
local battleStarted = false
local playedSong = nil

local mockAudio = {
  playSong = function(song) playedSong = song end,
  role = function(r) return 274 end,
}
package.loaded["src.core.game3.audio"] = mockAudio

local mockVm = {
  ctx = {
    pc = { listKey = "test_key", index = 1 },
    mode = "bytecode",
    status = "running",
  },
  store = { flags = {}, vars = {} },
  adapters = {
    openMessageAsync = function(text, done)
      openedDialog = text
      done()
    end,
    startTrainerBattle = function(foe, done, opts)
      battleStarted = true
      check(opts.defeatText == "CATERPIE can't hack it!", "Defeat text passed to battle options")
      done("win")
    end,
  },
  getText = function(self, ptr) return nil end,
  setPc = function(self, key, idx) end,
}

local row = {
  op = "trainerbattle",
  trainer = 102,
  type = 0,
}

Ops.dispatch(mockVm, row)
check(openedDialog == "Hey! You have POKéMON!", "Trainer intro dialog was displayed before battle")
check(battleStarted == true, "Trainer battle launched after dialog dismiss")
check(playedSong ~= nil, "Encounter music played on encounter")

print("[test] 4. Trainer Defeat Flag & Victory Post-Battle Routing")
local trainerFlag = Flags.trainerFlagId(102)
check(mockVm.store.flags[trainerFlag] == true, "Trainer defeated flag set after victory")

-- Talking to trainer again after defeat skips battle and falls through
openedDialog = nil
battleStarted = false
local ret = Ops.dispatch(mockVm, row)
check(ret == false, "Talking to defeated trainer falls through immediately")
check(battleStarted == false, "No new battle started for already-defeated trainer")

print(string.format("\nAll %d trainer reward and dialog tests passed successfully!", checksPassed))


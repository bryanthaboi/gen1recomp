-- Parity (#552, a regression of #105): the Rocket Hideout B4F grunt drops
-- the LIFT KEY on Yellow too, and the ball he drops reaches the bag.
--
-- Oracle: pokeyellow/scripts/RocketHideoutB4F.asm.  Yellow replaces
-- Rocket1/Rocket2 with Jessie & James and leaves one grunt, spelled
-- ROCKETHIDEOUTB4F_ROCKET / TEXT_ROCKETHIDEOUTB4F_ROCKET where Red and
-- Blue say ROCKET3, so the hand-ported Red/Blue key never matched and the
-- talk fell through to the generic trainer path: battle, no drop, no key,
-- and the B1F elevator stays locked for good.  Yellow also moves the drop
-- off the follow-up talk -- RocketHideoutB4FRocketEndBattleText is
-- text_promptbutton + text_asm, so its SetEvent EVENT_ROCKET_DROPPED_LIFT_KEY
-- and ShowObject TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5 run the moment the
-- battle ends, not on the next conversation.
--
-- The Red/Blue half stays in tests/parity_lift_key.lua; this one owns the
-- Yellow spelling and the pickup that #105 was originally about.
--
-- Self-contained: `luajit tests/parity_lift_key_yellow_bug552.lua`; also
-- globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity Yellow lift key (#552)")
local check, eq = S.check, S.eq

local mapScripts = require("data.scripts.init")
local OverworldState = require("src.world.OverworldController")
local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")
require("src.render.Font").load(Data)

local MAP = "ROCKET_HIDEOUT_B4F"
local BALL = "ROCKETHIDEOUTB4F_LIFT_KEY"

local ballObj
for _, o in ipairs(Data.maps[MAP].objects) do
  if o.name == BALL then ballObj = o end
end
check(ballObj ~= nil, "the LIFT KEY ball is an object_event on B4F")
check(ballObj and ballObj.hidden == true, "it starts hidden")
eq(ballObj and ballObj.item, "LIFT_KEY", "and it carries the LIFT KEY")

-- Yellow's object_event names the same grunt trainer party the Red/Blue
-- Rocket3 does (OPP_ROCKET, 18), so only the text id differs
local script = mapScripts.talkScript(MAP, "TEXT_ROCKETHIDEOUTB4F_ROCKET")
check(type(script) == "function",
      "TEXT_ROCKETHIDEOUTB4F_ROCKET resolves to a hand-ported handler (#552)")
check(type(mapScripts.talkScript(MAP, "TEXT_ROCKETHIDEOUTB4F_ROCKET3")) == "function",
      "the Red/Blue ROCKET3 handler is still registered alongside it")

-- ------------------------------------------------------------------ setup
local function newWorld(defeated)
  local save = SaveData.newGame()
  save.objectToggles = {}
  save.itemsTaken = {}
  save.defeatedTrainers = {}
  local pushed = {}
  local game = {
    data = Data,
    save = save,
    stack = { push = function(_, state) pushed[#pushed + 1] = state end },
  }
  local npc = {
    id = MAP .. "_obj_4",
    def = { name = "ROCKETHIDEOUTB4F_ROCKET", index = 4,
            text = "TEXT_ROCKETHIDEOUTB4F_ROCKET",
            trainerClass = "OPP_ROCKET", trainerParty = 18 },
  }
  if defeated then save.defeatedTrainers[npc.id] = true end
  local ow = {
    map = { id = MAP, def = Data.maps[MAP] },
    npcs = {}, entities = {},
    engagements = 0,
    trainerDefeated = function(_, who)
      return save.defeatedTrainers[who.id] == true
    end,
  }
  -- engageTrainer writes the win before it runs its callback, which is
  -- where the end-battle text's SetEvent + ShowObject belong
  ow.engageTrainer = function(self, who, after)
    self.engagements = self.engagements + 1
    save.defeatedTrainers[who.id] = true
    if after then after() end
  end
  return game, ow, npc, save, pushed
end

-- ------------------------------------------- winning the battle drops it
do
  local game, ow, npc, save, pushed = newWorld(false)
  local done = false
  check(not OverworldState.objectVisible(save, MAP, ballObj),
        "the ball is not on the floor before the fight")
  script(game, ow, npc, function() done = true end)

  eq(ow.engagements, 1, "an undefeated grunt still starts his battle")
  check(save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true,
        "EVENT_ROCKET_DROPPED_LIFT_KEY is set the moment the battle ends")
  eq(save.objectToggles[MAP] and save.objectToggles[MAP][BALL], true,
     "ShowObject reveals ROCKETHIDEOUTB4F_LIFT_KEY (TOGGLE_..._ITEM_5)")
  check(OverworldState.objectVisible(save, MAP, ballObj),
        "the LIFT KEY ball is on the floor without a second conversation")
  check(done, "the talk finishes and hands input back")
  eq(#pushed, 0, "the end-battle text is the battle's, not a second box")
end

-- --------------------------------------------- losing it drops nothing
do
  local game, ow, npc, save = newWorld(false)
  ow.engageTrainer = function(self, _, after)
    self.engagements = self.engagements + 1
    if after then after() end -- blacked out: no win recorded
  end
  script(game, ow, npc, function() end)
  check(not save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY,
        "a lost battle drops no key")
  check(not OverworldState.objectVisible(save, MAP, ballObj),
        "and the ball stays hidden")
end

-- ------------------------------------- later talks only reprint the line
do
  local game, ow, npc, save, pushed = newWorld(true)
  save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = true
  save.objectToggles[MAP] = { [BALL] = true }
  local done = false
  script(game, ow, npc, function() done = true end)
  eq(ow.engagements, 0, "a beaten grunt does not re-engage")
  eq(#pushed, 1, "he says his after-battle line")
  eq(pushed[1] and getmetatable(pushed[1]), TextBox, "in a text box")
  if pushed[1] and pushed[1].onDone then pushed[1].onDone() end
  check(done, "closing that box hands input back to the overworld")
  eq(save.objectToggles[MAP][BALL], true, "the ball is not re-toggled")
end

-- home/trainers.asm:341
do
  local GameVersion = require("src.core.GameVersion")
  local prior = GameVersion.current
  local game, ow, npc, save = newWorld(false)
  local view = mapScripts.get(MAP)
  check(type(view and view.onVictory) == "function",
        "ROCKET_HIDEOUT_B4F declares an onVictory hook (#2277)")

  save.defeatedTrainers[npc.id] = true
  save.flags.EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 = true

  GameVersion.set("yellow")
  if type(view and view.onVictory) == "function" then view.onVictory(game, ow) end
  GameVersion.set(prior)

  check(save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true,
        "a sight battle sets EVENT_ROCKET_DROPPED_LIFT_KEY too")
  eq(save.objectToggles[MAP] and save.objectToggles[MAP][BALL], true,
     "and ShowObject reveals the ball with no conversation")
  check(OverworldState.objectVisible(save, MAP, ballObj),
        "the LIFT KEY ball is on the floor after the sight battle")
end

-- pokered/scripts/RocketHideoutB4F.asm:190
do
  local GameVersion = require("src.core.GameVersion")
  local prior = GameVersion.current
  local game, ow, npc, save = newWorld(false)
  save.defeatedTrainers[npc.id] = true
  save.flags.EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 = true
  local onVictory = mapScripts.get(MAP).onVictory
  GameVersion.set("red")
  if type(onVictory) == "function" then onVictory(game, ow) end
  GameVersion.set(prior)
  check(not save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY,
        "Red/Blue do not gain the ball a conversation early")
  check(not OverworldState.objectVisible(save, MAP, ballObj),
        "the Red/Blue ball stays hidden until Rocket3's after-battle text")
end

-- pokered/scripts/RocketHideoutB4F.asm:193
do
  local game, ow, npc, save, pushed = newWorld(true)
  save.flags.EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 = true
  local done = false
  check(not save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY,
        "the stuck save has the win but not the drop")
  script(game, ow, npc, function() done = true end)
  eq(ow.engagements, 0, "a beaten grunt does not re-engage")
  eq(#pushed, 1, "he still says his after-battle line")
  eq(pushed[1] and getmetatable(pushed[1]), TextBox, "in a text box")
  if pushed[1] and pushed[1].onDone then pushed[1].onDone() end
  check(done, "closing that box hands input back to the overworld")
  check(save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true,
        "and that talk sets EVENT_ROCKET_DROPPED_LIFT_KEY (#2277)")
  check(OverworldState.objectVisible(save, MAP, ballObj),
        "the ball a sight win swallowed is on the floor again")
end

-- ------------------------------------------ the ball itself, #105's half
-- talkTo's item-ball branch is what turns the revealed object into a bag
-- entry; without it the fix above only puts a sprite on the floor.  Same
-- `Game` upvalue rewiring tests/parity_D.lua uses for the Safari counters.
do
  local game, _, _, save, pushed = newWorld(true)
  save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = true
  save.objectToggles[MAP] = { [BALL] = true }

  local function bind(fn, upvalue, value)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if not name then return false end
      if name == upvalue then debug.setupvalue(fn, i, value); return true end
      i = i + 1
    end
  end
  check(bind(OverworldState.talkTo, "Game", game), "talkTo binds the Game upvalue")
  check(bind(OverworldState.talkTo, "mapScripts", mapScripts),
        "talkTo binds the map-script registry")

  local ball = {
    id = MAP .. "_obj_" .. ballObj.index,
    def = ballObj,
    cellX = ballObj.x, cellY = ballObj.y,
  }
  local world = setmetatable({
    map = { id = MAP, def = Data.maps[MAP] },
    npcs = { ball }, entities = { ball },
  }, { __index = OverworldState })

  world:talkTo(ball)
  eq(save.inventory.LIFT_KEY, 1, "picking the ball up puts the LIFT KEY in the bag (#105)")
  eq(save.itemsTaken[ball.id], true, "the ball is marked taken")
  eq(#world.npcs, 0, "and it leaves the floor")
  check(not OverworldState.objectVisible(save, MAP, ballObj),
        "a taken ball does not respawn on the next map load")
  eq(#pushed, 1, "one box: the found-item line")
  local lines = {}
  for _, page in ipairs(pushed[1] and pushed[1].pages or {}) do
    for _, line in ipairs(page) do lines[#lines + 1] = line end
  end
  check(table.concat(lines, " "):find("LIFT KEY", 1, true) ~= nil,
        "the box names the LIFT KEY")
  eq(Data.items.LIFT_KEY and Data.items.LIFT_KEY.keyItem, true,
     "LIFT KEY is a key item, so it cannot be tossed away again")
end

S.finish()

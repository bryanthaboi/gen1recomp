-- Parity test: gym leader TM award respects the bag cap (#797).
--
-- scripts/PewterGym.asm, PewterGymScriptReceiveTM34: after
-- SetEvent EVENT_BEAT_BROCK it runs `lb bc, TM_BIDE, 1` / `call GiveItem`
-- / `jr nc, .BagFull`.  On success it prints TEXT_PEWTERGYM_RECEIVED_TM34
-- (and the TM34 explanation); on carry-clear it prints
-- TEXT_PEWTERGYM_TM34_NO_ROOM instead.  Both paths fall through to
-- .gymVictory, so the badge lands either way and the TM is simply lost.
-- The same `jr nc, .BagFull` shape is in CeruleanGym.asm, VermilionGym.asm,
-- CeladonGym.asm, FuchsiaGym.asm, SaffronGym.asm, CinnabarGym.asm and
-- ViridianGym.asm.
--
-- The port drives this through OverworldState:checkVictoryRewards over
-- data/scripts/victories.lua (gym leaders are not def_trainers entries, so
-- src/script/Commands.lua give_item -- which has always handled a full bag
-- -- is never on this path).  Each gym entry splits the hand-over into
-- tmPre (the lead-in), tmDialogue (GiveItem succeeded) and noRoom (the
-- .BagFull line), with gotFlag (EVENT_GOT_TM*) set only on success so the
-- leader's talk script can retry later (offerGymTm via gyms.lua).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity gym TM bag full #797")
local check, eq = S.check, S.eq

local Bag = require("src.inventory.Bag")
local victories = require("data.scripts.victories")

-- === (1) data shape: every gym reward carries both branches ===
-- A future gym edit must not silently drop the alternate line, so the
-- table check is cheap insurance over the eight leader entries.
do
  local n = 0
  for key, entry in pairs(victories) do
    if type(entry) == "table" and entry.badge then
      n = n + 1
      check(type(entry.tmDialogue) == "table" and #entry.tmDialogue > 0,
        key .. " has a tmDialogue tail (the GiveItem-succeeded text)")
      check(type(entry.noRoom) == "string",
        key .. " names a noRoom text (.BagFull branch)")
      local body = entry.noRoom and (Data.text or {})[entry.noRoom]
      check(type(body) == "string" and body ~= "",
        key .. " noRoom label resolves to extracted text")
      check(type(entry.gotFlag) == "string" and entry.gotFlag:find("EVENT_GOT_"),
        key .. " carries the EVENT_GOT_TM* retry flag")
      -- the received-TM tail must not still be baked into `dialogue`,
      -- or the full-bag path would print it anyway
      for _, label in ipairs(entry.dialogue or {}) do
        for _, tail in ipairs(entry.tmDialogue or {}) do
          check(label ~= tail,
            key .. " dialogue no longer repeats " .. tostring(tail))
        end
      end
    end
  end
  eq(n, 8, "all eight gym leader rewards checked")
end

-- === (2) behavior: Brock with a full bag vs an empty one ===

require("src.render.Font").load(Data)
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()

-- concatenates the pages of the box CHAIN checkVictoryRewards pushed: the
-- reward text splits into a box per gym-script sound command, so close each
-- one and let its onDone push the next
local function stackedDialogue()
  local parts = {}
  local top = Game.stack:top()
  while top and top.pages do
    for _, page in ipairs(top.pages) do
      parts[#parts + 1] = table.concat(page, "\n")
    end
    Game.stack:pop()
    if top.onDone then top.onDone() end
    top = Game.stack:top()
  end
  return table.concat(parts, "\n")
end

local function freshSave()
  while Game.stack:top() do Game.stack:pop() end
  Game.save = SaveData.newGame()
  Game.save.flags = {}
  Game.save.inventory = {}
  Game.save.bagOrder = nil
  Game.save.defeatedTrainers = {}
end

-- --- full bag: the TM is refused, the NoRoom line replaces the TM text ---
freshSave()
local cap = Bag.capacity(Data)
-- Bag.slots only counts non-badge ids, so distinct filler ids fill it
for i = 1, cap do Game.save.inventory["FILLER" .. i] = 1 end
eq(Bag.slots(Game.save), cap, "bag starts at BAG_ITEM_CAPACITY")

Game.stack:push(OW, "PEWTER_GYM", 4, 13, "up")
local ow = Game.stack:top()
ow:checkVictoryRewards("OPP_BROCK", 1)
local fullText = stackedDialogue()

check(Game.save.inventory.TM_BIDE == nil,
  "full bag: TM_BIDE is refused (GiveItem carry clear)")
eq(Bag.slots(Game.save), cap,
  "full bag: no 21st slot appears (the reporter's symptom)")
check(Game.save.inventory.BOULDERBADGE == 1,
  "full bag: .gymVictory still awards BOULDERBADGE")
check(Game.save.flags.EVENT_BEAT_BROCK,
  "full bag: EVENT_BEAT_BROCK is still set")
check(fullText:find("room for this", 1, true) ~= nil,
  "full bag: dialogue prints _PewterGymTM34NoRoomText")
check(fullText:find("BIDE", 1, true) == nil,
  "full bag: the TM34 explanation is skipped")
check(fullText:find("FLASH", 1, true) ~= nil,
  "full bag: the BoulderBadge speech still runs")
check(not Game.save.flags.EVENT_GOT_TM34,
  "full bag: EVENT_GOT_TM34 stays unset so the talk script retries")

-- --- empty bag: the success tail still appends and the TM lands ---
freshSave()
Game.stack:push(OW, "PEWTER_GYM", 4, 13, "up")
ow = Game.stack:top()
ow:checkVictoryRewards("OPP_BROCK", 1)
local okText = stackedDialogue()

check(Game.save.inventory.TM_BIDE == 1,
  "empty bag: TM_BIDE lands in the bag")
local order = Bag.order(Game.save)
check(order[1] == "TM_BIDE",
  "empty bag: Bag.add kept the wBagItems order (bagOrder) honest")
check(okText:find("BIDE", 1, true) ~= nil,
  "empty bag: tmDialogue (TM34 explanation) still appends")
check(Game.save.flags.EVENT_GOT_TM34,
  "empty bag: EVENT_GOT_TM34 is set on a successful give")
check(okText:find("room for this", 1, true) == nil,
  "empty bag: the NoRoom line is not printed")

-- --- one more leader, to prove the split is not Pewter-only ---
freshSave()
for i = 1, cap do Game.save.inventory["FILLER" .. i] = 1 end
Game.stack:push(OW, "CERULEAN_GYM", 4, 10, "up")
ow = Game.stack:top()
ow:checkVictoryRewards("OPP_MISTY", 1)
local mistyText = stackedDialogue()
check(Game.save.inventory.TM_BUBBLEBEAM == nil,
  "Misty full bag: TM_BUBBLEBEAM is refused")
check(Game.save.inventory.CASCADEBADGE == 1,
  "Misty full bag: CASCADEBADGE still awarded")
eq(Bag.slots(Game.save), cap, "Misty full bag: still at capacity")
check(mistyText:find((Data.text or {})._CeruleanGymMistyTM11NoRoomText
      :match("^[^\n]+") or "\1", 1, true) ~= nil,
  "Misty full bag: dialogue prints _CeruleanGymMistyTM11NoRoomText")

while Game.stack:top() do Game.stack:pop() end

S.finish()

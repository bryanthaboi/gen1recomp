-- Curated One Island (FRLG) events / scripts / text / movements for game3 v1.
-- Shared nurse/PC scripts live in stdscripts.lua (behavior-type, not map coords).

local TextIR = require("src.core.game3.scripting.text_ir")
local Flags = require("src.core.game3.scripting.flags")
local Movement = require("src.core.game3.scripting.movement")
local Opcodes = require("src.core.game3.scripting.opcodes")
local Std = require("src.core.game3.scripting.stdscripts")

local Content = {}

local F = Flags.IDS
local STD = Opcodes.STD

local function T(ascii)
  -- Long strings may use real newlines; pret IR wants \n / \p / \l sequences.
  ascii = ascii:gsub("^\n", ""):gsub("\r\n", "\n"):gsub("\n", "\\n")
  return TextIR.fromAscii(ascii)
end

Content.TEXT = {
  OneIsland_Text_LuckyToHaveCelioHere = T([[
Here we are on an island smack in
the middle of nowhere.\pWe're lucky to have an upstanding
young man like CELIO here.\pMy granddaughter was in a tizzy
over CELIO's friend.\pSomething about a famous
POKéMANIAC?\pI'm not sure what that means, but
CELIO is quite the man!]]),
  OneIsland_Text_HavePCLinkageWithKanto = T([[
My granddaughter was in a tizzy
over a new breakthrough.\pShe said we now have PC linkage
with people in KANTO.\pI'm not sure what that means, but
CELIO is quite the man!]]),
  OneIsland_Text_HavePCLinkageWithHoenn = T([[
My granddaughter was in a tizzy
over a new breakthrough.\pShe said we finally have PC linkage
with people in HOENN.\pI'm not sure what that means, but
CELIO is quite the man.\pHe would make a fine husband for
my granddaughter!]]),
  OneIsland_Text_IsntWarmClimateHereGreat = T([[
Hi, sight-seeing, are you?
Isn't the warm climate here great?]]),
  OneIsland_Text_IslandSign = T([[
ONE ISLAND
Friends Gather at Knot Island]]),
  OneIsland_Text_PokemonNetCenterSign = T([[
Expanding the POKéMON World!
POKéMON NET CENTER]]),
  OneIsland_Text_BillLetsGoSeeCelio = T([[
BILL: Here we are!
This is ONE ISLAND.\pLet's just go see CELIO!]]),
  Test_BufferGreeting = T("Hello, {STR_VAR_1}!"),
  NetworkCenter_Text_LittleBoy = T([[
There are lots of islands around here.
I want to visit every one someday!]]),
  NetworkCenter_Text_Hiker = T([[
I've been climbing Mt. Ember.
It's rough going for a HIKER!]]),
  NetworkCenter_Text_CrushGirl = T([[
The NETWORK MACHINE looks so cool!
I wonder what CELIO does with it.]]),
  NetworkCenter_Text_NetworkMachine = T([[
It's a huge machine.
It's humming with some unknown power.]]),
}

-- Merge shared FRLG nurse/PC text (pret data/text).
for k, v in pairs(Std.TEXT) do
  Content.TEXT[k] = v
end

-- Std msgbox bodies (callstd) + shared EventScript_PC / nurse.
Content.STDSCRIPTS = {
  ["std:2"] = { -- MSGBOX_NPC
    { op = "lock" },
    { op = "faceplayer" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "release" },
    { op = "return" },
  },
  ["std:3"] = { -- MSGBOX_SIGN
    { op = "lockall" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "releaseall" },
    { op = "return" },
  },
  ["std:4"] = { -- MSGBOX_DEFAULT
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:5"] = { -- MSGBOX_YESNO (stay + host yes/no → VAR_RESULT)
    { op = "message", ptr = 0, stay = true },
    { op = "waitmessage" },
    { op = "yesnobox" },
    { op = "return" },
  },
  ["std:6"] = {
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:8"] = {
    { op = "return" },
  },
  ["std:9"] = { -- STD_RECEIVED_ITEM
    { op = "compare_var_to_value", var = 0x8002, value = 318 },
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareKeyItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 258 },
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 257 },
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareLevelUp" },
    { op = "goto", target = "EventScript_ReceivedItemFanfareDefault" },
  },
}
for k, v in pairs(Std.SCRIPTS) do
  Content.STDSCRIPTS[k] = v
end

Content.SCRIPTS = {
  OneIsland_OnTransition = {
    { op = "setworldmapflag", flag = F.WORLD_MAP_ONE_ISLAND },
    { op = "end" },
  },
  OneIsland_EventScript_OldMan = {
    { op = "lock" },
    { op = "faceplayer" },
    { op = "checkflag", flag = F.SYS_CAN_LINK_WITH_RS },
    { op = "goto_if", cond = 1, target = "OneIsland_EventScript_OldManLinkHoenn" },
    { op = "checkflag", flag = F.SEVII_DETOUR_FINISHED },
    { op = "goto_if", cond = 1, target = "OneIsland_EventScript_OldManLinkKanto" },
    { op = "loadword", dest = 0, value = "OneIsland_Text_LuckyToHaveCelioHere" },
    { op = "callstd", std = STD.MSGBOX_DEFAULT },
    { op = "release" },
    { op = "end" },
  },
  OneIsland_EventScript_OldManLinkKanto = {
    { op = "loadword", dest = 0, value = "OneIsland_Text_HavePCLinkageWithKanto" },
    { op = "callstd", std = STD.MSGBOX_DEFAULT },
    { op = "release" },
    { op = "end" },
  },
  OneIsland_EventScript_OldManLinkHoenn = {
    { op = "loadword", dest = 0, value = "OneIsland_Text_HavePCLinkageWithHoenn" },
    { op = "callstd", std = STD.MSGBOX_DEFAULT },
    { op = "release" },
    { op = "end" },
  },
  OneIsland_EventScript_BaldingMan = {
    { op = "loadword", dest = 0, value = "OneIsland_Text_IsntWarmClimateHereGreat" },
    { op = "callstd", std = STD.MSGBOX_NPC },
    { op = "end" },
  },
  OneIsland_EventScript_IslandSign = {
    { op = "loadword", dest = 0, value = "OneIsland_Text_IslandSign" },
    { op = "callstd", std = STD.MSGBOX_SIGN },
    { op = "end" },
  },
  OneIsland_EventScript_PokemonNetCenterSign = {
    { op = "loadword", dest = 0, value = "OneIsland_Text_PokemonNetCenterSign" },
    { op = "callstd", std = STD.MSGBOX_SIGN },
    { op = "end" },
  },
  -- Map nurse: pret shape — call shared EventScript_PkmnCenterNurse
  OneIsland_PokemonCenter_1F_EventScript_Nurse = {
    { op = "lock" },
    { op = "faceplayer" },
    { op = "call", target = "EventScript_PkmnCenterNurse" },
    { op = "release" },
    { op = "end" },
  },
  OneIsland_PokemonCenter_1F_EventScript_LittleBoy = {
    { op = "loadword", dest = 0, value = "NetworkCenter_Text_LittleBoy" },
    { op = "callstd", std = STD.MSGBOX_NPC },
    { op = "end" },
  },
  OneIsland_PokemonCenter_1F_EventScript_Hiker = {
    { op = "loadword", dest = 0, value = "NetworkCenter_Text_Hiker" },
    { op = "callstd", std = STD.MSGBOX_NPC },
    { op = "end" },
  },
  OneIsland_PokemonCenter_1F_EventScript_CrushGirl = {
    { op = "loadword", dest = 0, value = "NetworkCenter_Text_CrushGirl" },
    { op = "callstd", std = STD.MSGBOX_NPC },
    { op = "end" },
  },
  OneIsland_PokemonCenter_1F_EventScript_NetworkMachine = {
    { op = "loadword", dest = 0, value = "NetworkCenter_Text_NetworkMachine" },
    { op = "callstd", std = STD.MSGBOX_SIGN },
    { op = "end" },
  },
}

-- walk_up = MOVEMENT_ACTION_WALK_NORMAL_UP (0x11), step_end = 0xFE
Content.MOVEMENTS = {
  OneIsland_Movement_PlayerExitHarbor = Movement.ensureTerminated({
    Movement.CMD.WALK_UP, Movement.STEP_END,
  }),
}

-- graphicsVar demo: template object that resolves OBJ_GFX from 0x4010
Content.EVENTS = {
  SEVII_ONE_ISLAND = {
    objects = {
      {
        localId = 1,
        name = "SEVII_ONE_ISLAND_BILL",
        graphics = "OBJ_EVENT_GFX_BILL",
        sprite = "SPRITE_BILL", -- Gen2 host; may fall back
        x = 12, y = 16,
        elevation = 3,
        movement = "STAY",
        range = "DOWN",
        scriptKey = nil, -- no talk
        flag = F.HIDE_ONE_ISLAND_BILL,
        -- Example of var-driven gfx (story templates); default mirrors Bill.
        graphicsVar = 0x4010,
      },
      {
        localId = 2,
        name = "SEVII_ONE_ISLAND_OLD_MAN",
        graphics = "OBJ_EVENT_GFX_OLD_MAN_1",
        sprite = "SPRITE_GRAMPS",
        x = 16, y = 12,
        elevation = 3,
        -- pret MOVEMENT_TYPE_WANDER_AROUND, range 1×1
        movement = "WALK",
        range = "ANY_DIR",
        radius = { x = 1, y = 1 },
        scriptKey = "OneIsland_EventScript_OldMan",
        flag = 0,
      },
      {
        localId = 3,
        name = "SEVII_ONE_ISLAND_BALDING_MAN",
        graphics = "OBJ_EVENT_GFX_BALDING_MAN",
        sprite = "SPRITE_POKEFAN_M",
        x = 13, y = 9,
        elevation = 3,
        -- pret MOVEMENT_TYPE_FACE_DOWN_AND_UP → host LOOK/spin
        movement = "LOOK",
        range = "DOWN",
        scriptKey = "OneIsland_EventScript_BaldingMan",
        flag = 0,
      },
    },
    bgEvents = {
      {
        type = "sign",
        x = 14, y = 13,
        scriptKey = "OneIsland_EventScript_IslandSign",
      },
      {
        type = "sign",
        x = 15, y = 6,
        scriptKey = "OneIsland_EventScript_PokemonNetCenterSign",
      },
    },
    mapScripts = {
      onTransition = "OneIsland_OnTransition",
      onResume = {}, -- stub slot; always present
      onFrame = {
        -- Bill intro deferred (Tier B): harbor scene var == 2
        -- { var = 0x4075, value = 2, script = "OneIsland_EventScript_EnterOneIslandFirstTime" },
      },
    },
  },
  SEVII_ONE_ISLAND_POKECENTER = {
    -- Object/bg rows mirror pret map.json / FRLG MapEvents (ROM event table).
    -- PC is NOT listed: FRLG uses MB_PC metatile → COLL_PC → EventScript_PC.
    objects = {
      {
        localId = 1,
        name = "SEVII_ONE_PC_NURSE",
        graphics = "OBJ_EVENT_GFX_NURSE",
        sprite = "SPRITE_NURSE",
        x = 5, y = 2,
        movement = "STAY",
        range = "DOWN",
        scriptKey = "OneIsland_PokemonCenter_1F_EventScript_Nurse",
        flag = 0,
      },
      {
        localId = 2,
        name = "SEVII_ONE_PC_BILL",
        graphics = "OBJ_EVENT_GFX_BILL",
        sprite = "SPRITE_BILL",
        x = 14, y = 6,
        movement = "STAY",
        range = "UP",
        scriptKey = nil,
        flag = F.HIDE_ONE_ISLAND_POKECENTER_BILL,
      },
      {
        localId = 3,
        name = "SEVII_ONE_PC_CELIO",
        graphics = "OBJ_EVENT_GFX_CELIO",
        sprite = "SPRITE_SUPER_NERD",
        x = 15, y = 6,
        movement = "STAY",
        range = "UP",
        scriptKey = nil,
        flag = F.HIDE_ONE_ISLAND_POKECENTER_CELIO,
      },
      {
        localId = 4,
        name = "SEVII_ONE_PC_LITTLE_BOY",
        graphics = "OBJ_EVENT_GFX_LITTLE_BOY",
        sprite = "SPRITE_YOUNGSTER",
        x = 6, y = 8,
        -- pret MOVEMENT_TYPE_WANDER_AROUND, range 1×1
        movement = "WALK",
        range = "ANY_DIR",
        radius = { x = 1, y = 1 },
        scriptKey = "OneIsland_PokemonCenter_1F_EventScript_LittleBoy",
        flag = 0,
      },
      {
        localId = 5,
        name = "SEVII_ONE_PC_HIKER",
        graphics = "OBJ_EVENT_GFX_HIKER",
        sprite = "SPRITE_POKEFAN_M",
        x = 3, y = 7,
        movement = "STAY",
        range = "DOWN",
        scriptKey = "OneIsland_PokemonCenter_1F_EventScript_Hiker",
        flag = 0,
      },
      {
        localId = 6,
        name = "SEVII_ONE_PC_CRUSH_GIRL",
        graphics = "OBJ_EVENT_GFX_CRUSH_GIRL",
        sprite = "SPRITE_COOLTRAINER_F",
        x = 7, y = 4,
        movement = "STAY",
        range = "RIGHT",
        scriptKey = "OneIsland_PokemonCenter_1F_EventScript_CrushGirl",
        flag = 0,
      },
    },
    bgEvents = {
      -- From FRLG MapEvents bg_events (Network Machine), not invented coords.
      { type = "sign", x = 12, y = 2, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 12, y = 3, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 12, y = 4, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 12, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 13, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 14, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 15, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 16, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
      { type = "sign", x = 17, y = 5, scriptKey = "OneIsland_PokemonCenter_1F_EventScript_NetworkMachine" },
    },
    mapScripts = {
      onTransition = nil,
      onResume = {},
      onFrame = {},
    },
  },
}

-- Host sprite lookup for FRLG graphics constants / resolved var values.
Content.GFX_TO_SPRITE = {
  OBJ_EVENT_GFX_BILL = "SPRITE_BILL",
  OBJ_EVENT_GFX_OLD_MAN_1 = "SPRITE_GRAMPS",
  OBJ_EVENT_GFX_BALDING_MAN = "SPRITE_POKEFAN_M",
  OBJ_EVENT_GFX_NURSE = "SPRITE_NURSE",
  OBJ_EVENT_GFX_LITTLE_BOY = "SPRITE_YOUNGSTER",
  OBJ_EVENT_GFX_HIKER = "SPRITE_POKEFAN_M",
  OBJ_EVENT_GFX_CRUSH_GIRL = "SPRITE_COOLTRAINER_F",
  OBJ_EVENT_GFX_CELIO = "SPRITE_SUPER_NERD",
}

function Content.resolveSprite(graphics, graphicsVar, getVar)
  if graphicsVar and getVar then
    local v = getVar(graphicsVar)
    if v and v ~= 0 then
      if type(v) == "string" and Content.GFX_TO_SPRITE[v] then
        return Content.GFX_TO_SPRITE[v]
      end
      if Content.GFX_TO_SPRITE[v] then
        return Content.GFX_TO_SPRITE[v]
      end
      -- Unknown resolved id — still prefer static template if present.
      if graphics and Content.GFX_TO_SPRITE[graphics] then
        return Content.GFX_TO_SPRITE[graphics]
      end
      return "SPRITE_YOUNGSTER"
    end
  end
  if graphics and Content.GFX_TO_SPRITE[graphics] then
    return Content.GFX_TO_SPRITE[graphics]
  end
  return "SPRITE_YOUNGSTER"
end

return Content

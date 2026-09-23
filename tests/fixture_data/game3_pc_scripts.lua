-- pokefirered/data/scripts/pc.inc:1

local TextIR = require("src.core.game3.scripting.text_ir")
local Std = require("src.core.game3.scripting.stdscripts")

local S = Std.SPECIAL

local function T(s) return TextIR.fromAscii(s) end

local M = {}

M.TEXT = {
  Text_BootedUpPC = T("{PLAYER} booted up the PC."),
  Text_AccessWhichPC = T("Which PC should be accessed?"),
  Text_UsualPCServicesUnavailable = T("The usual PC services aren't\\navailable…"),
  Text_AccessedSomeonesPC = T("Accessed someone's PC."),
  Text_OpenedPkmnStorage = T("POKéMON Storage System opened."),
  Text_AccessedPlayersPC = T("Accessed {PLAYER}'s PC."),
  Text_AccessedProfOaksPC = T("Accessed PROF. OAK's PC…"),
}

M.SCRIPTS = {
  -- pokefirered/data/scripts/std_msgbox.inc:22
  ["std:4"] = {
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  EventScript_PC = {
    { op = "lockall" },
    { op = "checkflag", flag = 0x841 },
    { op = "goto_if", cond = 1, target = "EventScript_PCDisabled" },
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "special", id = S.AnimatePcTurnOn },
    { op = "playse", [1] = 4 },
    { op = "loadword", dest = 0, value = "Text_BootedUpPC" },
    { op = "callstd", std = 4 },
    { op = "goto", target = "EventScript_PCMainMenu" },
  },
  -- pokefirered/data/scripts/pc.inc:15
  EventScript_PCDisabled = {
    { op = "loadword", dest = 0, value = "Text_UsualPCServicesUnavailable" },
    { op = "callstd", std = 4 },
    { op = "releaseall" },
    { op = "end" },
  },
  -- pokefirered/data/scripts/pc.inc:20
  EventScript_PCMainMenu = {
    { op = "message", ptr = "Text_AccessWhichPC" },
    { op = "waitmessage" },
    { op = "special", id = S.CreatePCMenu },
    { op = "waitstate" },
    { op = "goto", target = "EventScript_ChoosePCMenu" },
  },
  -- pokefirered/data/scripts/pc.inc:28
  EventScript_ChoosePCMenu = {
    { op = "compare_var_to_value", var = 0x800D, value = 0 },
    { op = "goto_if", cond = 1, target = "EventScript_AccessPokemonStorage" },
    { op = "compare_var_to_value", var = 0x800D, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_AccessPlayersPC" },
    { op = "compare_var_to_value", var = 0x800D, value = 2 },
    { op = "goto_if", cond = 1, target = "EventScript_AccessProfOaksPC" },
    { op = "compare_var_to_value", var = 0x800D, value = 3 },
    { op = "goto_if", cond = 1, target = "EventScript_AccessHallOfFame" },
    { op = "goto", target = "EventScript_TurnOffPC" },
  },
  -- pokefirered/data/scripts/pc.inc:38
  EventScript_AccessPlayersPC = {
    { op = "playse", [1] = 2 },
    { op = "loadword", dest = 0, value = "Text_AccessedPlayersPC" },
    { op = "callstd", std = 4 },
    { op = "special", id = S.PlayerPC },
    { op = "waitstate" },
    { op = "goto", target = "EventScript_PCMainMenu" },
  },
  -- pokefirered/data/scripts/pc.inc:46
  EventScript_AccessPokemonStorage = {
    { op = "playse", [1] = 2 },
    { op = "loadword", dest = 0, value = "Text_AccessedSomeonesPC" },
    { op = "callstd", std = 4 },
    { op = "loadword", dest = 0, value = "Text_OpenedPkmnStorage" },
    { op = "callstd", std = 4 },
    { op = "special", id = S.ShowPokemonStorageSystemPC },
    { op = "waitstate" },
    { op = "goto", target = "EventScript_PCMainMenu" },
  },
  -- pokefirered/data/scripts/pc.inc:66
  EventScript_TurnOffPC = {
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "playse", [1] = 3 },
    { op = "special", id = S.AnimatePcTurnOff },
    { op = "releaseall" },
    { op = "end" },
  },
  -- pokefirered/data/scripts/pc.inc:74
  EventScript_AccessHallOfFame = {
    { op = "checkflag", flag = 0x82C },
    { op = "goto_if", cond = 0, target = "EventScript_TurnOffPC" },
    { op = "playse", [1] = 2 },
    { op = "special", id = S.HallOfFamePCBeginFade },
    { op = "waitstate" },
    { op = "goto", target = "EventScript_ChoosePCMenu" },
  },
  -- pokefirered/data/scripts/pc.inc:86
  EventScript_AccessProfOaksPC = {
    { op = "checkflag", flag = 0x829 },
    { op = "goto_if", cond = 0, target = "EventScript_TurnOffPC" },
    { op = "playse", [1] = 2 },
    { op = "loadword", dest = 0, value = "Text_AccessedProfOaksPC" },
    { op = "callstd", std = 4 },
    { op = "goto", target = "EventScript_PCMainMenu" },
  },
}

return M

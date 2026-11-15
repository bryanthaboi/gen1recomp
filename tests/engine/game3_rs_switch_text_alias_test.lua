#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local RsUi = require("src.core.game3.profiles.rs.ui")
local RsText = require("src.import.gba.versions_text_rs")

local named = {}
for _, list in ipairs({ RsText.NAMED_TEXTS, RsText.NAMED_BATTLE_TEXTS }) do
  for _, key in ipairs(list) do named[key] = true end
end

local function target(key)
  local v = RsUi.textAliases[key]
  if type(v) == "table" then v = v.key end
  return v
end

for _, key in ipairs({ "gText_PkmnCantSwitchOut", "gText_PkmnsXPreventsSwitching" }) do
  local t = target(key)
  check(t ~= nil and named[t] == true,
    ("RS extracts the text Engine.canSwitch reads for %s (%s)"):format(key, tostring(t)))
end
check(target("gText_PkmnsXPreventsSwitching") == "BattleText_PreventedSwitch",
  "RS prevents-switching line is pokeruby BattleText_PreventedSwitch")

T.finish("game3 RS switch text alias")

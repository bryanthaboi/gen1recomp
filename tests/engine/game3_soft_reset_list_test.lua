package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local game3 = read("src/core/Game3.lua")
local block = game3:match("\nlocal SOFT_RESET = (%b{})")
check(block ~= nil, "Game3.lua declares the SOFT_RESET list")
block = block or ""

local listed = {}
for name, rest in block:gmatch('{%s*"([%w%._]+)"%s*,%s*([^\n]*)') do
  listed[name] = rest
end

local ALLOW = {
  ["src.core.game3.runtime"] = "Runtime.stop in returnToTitle",
  ["src.core.game3"] = "forwards Runtime.isActive",
  ["src.core.game3.scripting.space"] = "Space.activate on every Runtime.start",
  ["src.core.game3.weather"] = "map-owned, Map.load reapplies it",
  ["src.core.game3.minigames.common"] = "arena phase skips soft reset",
  ["src.ui.game3.minigames.common_lobby"] = "link session owns teardown",
  ["src.ui.game3.minigames.berry_crush.pouch"] = "link session owns teardown",
  ["src.core.game3.link.battle"] = "link session owns teardown",
  ["src.core.game3.link.chat"] = "link session owns teardown",
  ["src.core.game3.link.trade"] = "link session owns teardown",
  ["src.core.game3.link.union_room"] = "link session owns teardown",
  ["src.ui.game3.link_menu"] = "link session owns teardown",
  ["src.ui.game3.link_trade_menu"] = "link session owns teardown",
  ["src.ui.game3.union_chat"] = "link session owns teardown",
  ["src.ui.game3.union_room"] = "link session owns teardown",
  ["src.ui.game3.pin_entry"] = "link session owns teardown",
  ["src.ui.game3.braille"] = "reads Message, which is listed",
  ["src.ui.game3.help_system"] = "Help.reset in returnToTitle",
  ["src.core.game3.battle.anim"] = "Battle.reset calls Anim.reset",
  ["src.core.game3.battle.anim_seq"] = "Battle.reset calls AnimSeq.reset",
  ["src.core.game3.battle.catch_seq"] = "Battle.reset calls CatchSeq.reset",
  ["src.core.game3.battle.evo_seq"] = "Battle.reset calls EvoSeq.reset",
  ["src.core.game3.battle.exp_seq"] = "Battle.reset calls ExpSeq.reset",
  ["src.core.game3.battle.intro_seq"] = "Battle.reset calls IntroSeq.reset",
  ["src.core.game3.battle.learn_move"] = "Battle.reset calls LearnMove.reset",
  ["src.core.game3.battle.switch_seq"] = "Battle.reset calls SwitchSeq.reset",
  ["src.core.game3.battle.ui"] = "only read while a battle runs, Battle.start calls Ui.reset",
  ["src.core.game3.warp"] = "Runtime.stop -> Field.stop -> Warp.clear",
  ["src.core.game3.doors"] = "Runtime.stop -> Field.stop -> Doors.release",
  ["src.ui.game3.stack"] = "Stack.clear in returnToTitle",
}

local FLAG_FNS = { "isOpen", "isActive", "busy", "isBusy" }

local files = {}
local p = assert(io.popen("find src/core/game3 src/ui/game3 -name '*.lua' | sort"))
for line in p:lines() do files[#files + 1] = line end
p:close()
check(#files > 50, "found the game3 module tree")

local seen = {}
for _, path in ipairs(files) do
  local src = read(path)
  local flagged = false
  for _, fn in ipairs(FLAG_FNS) do
    if src:match("\nfunction [%w_]+%." .. fn .. "%(%)") then flagged = true end
  end
  if flagged then
    local name = path:gsub("%.lua$", ""):gsub("/", ".")
    local alt = name:gsub("%.init$", "")
    seen[name], seen[alt] = true, true
    local ok = listed[name] or listed[alt] or ALLOW[name] or ALLOW[alt]
    check(ok ~= nil, name .. " has an open/active/busy flag and is in SOFT_RESET or the allowlist")
  end
  local name = path:gsub("%.lua$", ""):gsub("/", ".")
  local rest = listed[name]
  if rest then
    local method = rest:match('^"([%w_]+)"')
    if method then
      check(src:match("\nfunction [%w_]+%." .. method .. "%(") ~= nil,
        name .. "." .. method .. " exists")
    end
  end
end

for name in pairs(ALLOW) do
  check(seen[name] == true, "allowlisted " .. name .. " still exposes an open/active/busy flag")
end
for name in pairs(listed) do
  local path = name:gsub("%.", "/")
  local f = io.open(path .. ".lua", "rb") or io.open(path .. "/init.lua", "rb")
  check(f ~= nil, "SOFT_RESET entry " .. name .. " is a real module")
  if f then f:close() end
end

T.finish()

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

package.loaded["src.core.game3.scripting.space"] = { store = nil, getStore = function() return nil end }
local Flags = require("src.core.game3.scripting.flags")
local TimeEvents = require("src.core.game3.time_events")

for _, version in ipairs({ "ruby", "sapphire", "emerald" }) do
  local session = { version = version, name = "MAY", flags = {}, vars = {} }
  TimeEvents.run(session)
  check(session.store == nil, version .. " run without live store leaves session.store nil")
  TimeEvents.init(session)
  check(session.store == nil, version .. " init without live store leaves session.store nil")

  local live = Flags.newStore()
  package.loaded["src.core.game3.scripting.space"] = { store = live, getStore = function() return live end }
  local s2 = { version = version, name = "MAY", flags = {}, vars = {} }
  TimeEvents.run(s2)
  check(s2.store == nil, version .. " run with live store leaves session.store nil")
  package.loaded["src.core.game3.scripting.space"] = { store = nil, getStore = function() return nil end }

  local own = { flags = {}, vars = {} }
  local s3 = { version = version, name = "MAY", flags = {}, vars = {}, store = own }
  TimeEvents.run(s3)
  check(s3.store == own, version .. " existing session.store is kept")
end

if failed > 0 then
  print(string.format("%d failure(s)", failed))
  os.exit(1)
end
print("all ok")

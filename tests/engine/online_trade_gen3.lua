package.path = "./?.lua;./?/init.lua;" .. package.path

local SUITES = {
  "tests/online_trade_gen3.lua",
  "tests/online_mon3_test.lua",
  "tests/online_fingerprint3_test.lua",
  "tests/online_trade_remote3_test.lua",
  "tests/online_trade_relay3_test.lua",
  "tests/online_trade_interop3_test.lua",
  "tests/online_arena_data_gen3_test.lua",
}

local lua = (arg and arg[-1]) or "luajit"
local failed = 0
for _, path in ipairs(SUITES) do
  local status = os.execute(("%s %s"):format(lua, path))
  if not (status == 0 or status == true) then
    failed = failed + 1
    print("FAIL " .. path)
  end
end
os.exit(failed == 0 and 0 or 1)

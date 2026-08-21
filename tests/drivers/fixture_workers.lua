-- Runs only under real LÖVE.  The headless stubs deliberately have no thread
-- implementation, so this closes the gap between facade tests and the worker
-- Lua states/channels that ship to players.

local U = require("tests.drivers.util")

return function(game)
  local Job = require("src.mods.Job")
  local Fetch = require("src.net.Fetch")
  local baseUrl = assert(os.getenv("POKEPORT_TEST_HTTP_URL"),
    "POKEPORT_TEST_HTTP_URL is required")

  local function waitFor(poll, label)
    for _ = 1, 300 do
      local state = poll()
      if state.status ~= "pending" then return state end
      U.wait(1)
    end
    error(label .. " stayed pending")
  end

  local function run()
    assert(game.overworld and game.overworld.map.id == "FIX_TOWN",
      "worker test did not boot the fixture world")
    assert(Job.available(), "real LOVE background jobs are unavailable")

    local loader = { mods = { thread_probe = {
      manifest = { permissionSet = { background = true } },
    } } }
    local path = "tests/fixtures/thread_probe"
    local handle, err = Job.run(loader, "thread_probe", path, "job_ok.lua",
      { values = { 3, 5, 8 }, label = "worker" })
    assert(handle, err)
    local state = waitFor(function()
      return Job.poll(loader, "thread_probe", handle)
    end, "positive compute job")
    assert(state.status == "ok" and state.result.total == 16
      and state.result.label == "worker", "compute worker returned wrong data")
    assert(Job.release(loader, "thread_probe", handle))

    local bad = assert(Job.run(loader, "thread_probe", path, "job_error.lua", {}))
    state = waitFor(function()
      return Job.poll(loader, "thread_probe", bad)
    end, "negative compute job")
    assert(state.status == "error"
      and tostring(state.err):find("deliberate worker failure", 1, true),
      "worker exception was not returned as an attributed error")
    assert(Job.release(loader, "thread_probe", bad))

    local fetch = Fetch.get(baseUrl .. "/ok", { maxSeconds = 3 })
    state = waitFor(function() return Fetch.poll(fetch) end, "positive fetch")
    assert(state.status == "ok" and state.body == "fixture-http-ok\n",
      "fetch worker did not return the local response")
    Fetch.release(fetch)

    fetch = Fetch.get(baseUrl .. "/missing", { maxSeconds = 3 })
    state = waitFor(function() return Fetch.poll(fetch) end, "negative fetch")
    assert(state.status == "error" and state.err,
      "HTTP failure was not surfaced by the fetch worker")
    Fetch.release(fetch)
  end

  U.wait(5)
  local ok, err = xpcall(run, debug.traceback)
  -- LOVE waits for live threads at process exit; this assertion also proves
  -- the explicit shutdown path releases an idle pool.
  Fetch.shutdown()
  assert(ok, err)
  print("fixture LOVE workers: PASS")
end

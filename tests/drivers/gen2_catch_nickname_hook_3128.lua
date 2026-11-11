local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Mon = require("src.battle.gen2.Mon")
local Boxes = require("src.core.gen2.Boxes")

local MOD = {
  ["mods/catch_nickname_repro/manifest.json"] = [[{
    "id": "catch_nickname_repro",
    "name": "catch.nickname repro",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/catch_nickname_repro/main.lua"] = [[
return function(mod)
  mod.exports.calls = 0
  mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
    mod.log:info("catch.nickname called")
    mod.exports.calls = mod.exports.calls + 1
    return "SPIKE"
  end)
end
]],
}

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_catch_nickname_hook_3128"
  local version = game.save.version
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_catch_nickname_hook_3128 " .. tostring(version)
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "3128 world booted") then return finish() end

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 2, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.catch_nickname_repro
  local out = loader.exports.catch_nickname_repro
  if not check(mod and not mod.failed and out ~= nil, "3128 repro mod loaded") then return finish() end

  local function battleScreen()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end

  local function catchOne(species, tag, onPcLine, onGotcha)
    local wild = Mon.new(game.data, species, 3)
    if not check(world:startBattle({ wild = wild }), tag .. " battle started") then return nil end
    local screen = battleScreen()
    if not check(screen ~= nil, tag .. " battle screen up") then return nil end
    for _ = 1, 400 do
      if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
      U.tap(game, "a")
      U.wait(3)
    end
    local before = out.calls
    screen:useItem("MASTER_BALL")
    local asked, named, pcLine = false, false, false
    local gotcha, gotchaHud = false, true
    local caughtText = "Gotcha! " .. species .. " was caught!"
    for _ = 1, 1500 do
      if screen.phase == "done" then break end
      if screen.phase == "ask-nickname" then asked = true end
      local top = game.stack:top()
      if top ~= screen and top and top.maxLength then named = true end
      local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
      local pending = false
      for _, event in ipairs(screen.queue) do
        if event.kind == "set-nickname" then pending = true end
      end
      if pending and msg:find(caughtText, 1, true) then
        local hud = screen:name(screen:activeMon("enemy"))
        if hud ~= species then gotchaHud = false end
        if not gotcha then
          gotcha = true
          if onGotcha then onGotcha() end
        end
      end
      if not pcLine and msg:find("SPIKE was sent to BILL's PC.", 1, true) then
        pcLine = true
        if onPcLine then onPcLine() end
      end
      U.tap(game, "b")
      U.wait(3)
    end
    for _ = 1, 300 do
      local top = game.stack:top()
      if not (top and top.battle) then break end
      U.wait(1)
    end
    U.wait(30)
    check(not asked, tag .. " no nickname question")
    check(not named, tag .. " no naming screen")
    check(out.calls == before + 1, tag .. " hook ran once")
    check(gotcha, tag .. " Gotcha line shown")
    check(gotcha and gotchaHud, tag .. " enemy HUD reads " .. species .. " under the Gotcha line")
    return wild, pcLine
  end

  game.save.inventory = { MASTER_BALL = 5 }
  game.save.party = { Mon.new(game.data, "CYNDAQUIL", 30) }
  local partyMon = catchOne("RATTATA", "3128 party")
  check(partyMon ~= nil and game.save.party[2] == partyMon, "3128 party catch joined the party")
  check(partyMon ~= nil and partyMon.nickname == "SPIKE", "3128 party catch named SPIKE")

  game.save.party = {}
  for i = 1, 6 do game.save.party[i] = Mon.new(game.data, "CYNDAQUIL", 30) end
  local shot = false
  local gotchaShot = false
  local pcMon, pcLine = catchOne("SENTRET", "3128 pc", function()
    U.wait(90)
    shot = U.still(game, dir .. "/3128_02_sent_to_pc_as_spike.png")
  end, function()
    U.wait(240)
    gotchaShot = U.still(game, dir .. "/3128_01_gotcha_hud_reads_species.png")
  end)
  check(gotchaShot, "3128 gotcha hud shot")
  check(pcLine, "3128 pc line reads SPIKE was sent to BILL's PC.")
  check(shot, "3128 pc line shot")
  local box = Boxes.box(game.save, game.save.currentBox or 1)
  local head = box and box[1]
  check(pcMon ~= nil and head == pcMon, "3128 pc catch heads the box")
  check(pcMon ~= nil and pcMon.nickname == "SPIKE", "3128 pc catch named SPIKE")
  finish()
end

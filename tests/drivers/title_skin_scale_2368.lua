return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TouchSkin = require("src.core.TouchSkin")
  local Renderer = require("src.render.Renderer")
  local GameVersion = require("src.core.GameVersion")
  local TitleState = require("src.ui.TitleState")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local version = tostring(GameVersion.get())
  local tag = "2368_" .. version

  local fails = 0
  local function check(label, ok, detail)
    U.log((ok and "PASS " or "FAIL ") .. tag .. " " .. label, detail or "")
    if not ok then fails = fails + 1 end
    return ok
  end

  local function finish()
    TouchSkin.setActive(nil)
    if fails > 0 then
      U.log("FAIL " .. tag .. ": " .. fails .. " check(s), shots in " .. SHOT_DIR)
      love.event.quit(1)
    else
      U.log("PASS " .. tag .. ": all checks, shots in " .. SHOT_DIR)
      love.event.quit(0)
    end
    while true do coroutine.yield() end
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local function shot(name)
    U.shot(game, SHOT_DIR .. "/" .. tag .. "_" .. name .. ".png")
  end

  local function scale()
    U.wait(4)
    local r = Renderer:frameRects()
    return r.Up, Renderer:fitScale(), r
  end

  local function wholeFit(label)
    local up, fit = scale()
    check(label .. " draws at the integer fit", up == fit and up == math.floor(up),
      ("Up=%s fit=%s"):format(tostring(up), tostring(fit)))
    return up
  end

  love.window.setMode(1024, 768, { resizable = true })
  U.wait(2)
  local skin = assert(TouchSkin.parse([[
overlays = 1
overlay0_name = "bezel"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_viewport = "0.15,0.08,0.7,0.84"
overlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.02,0.02"
]]))
  TouchSkin.setActive(skin)
  TouchSkin.setOverlayLive(false)
  U.wait(240)

  local introUp = wholeFit("intro inside the bezel")
  shot("01_intro_skin")

  local function isTitle()
    return getmetatable(game.stack:top()) == TitleState
  end
  for _ = 1, 40 do
    if isTitle() then break end
    U.tap(game, "start")
    U.wait(10)
  end
  if not check("reached the title screen", isTitle()) then finish() end
  U.wait(30)
  local titleUp = wholeFit("title inside the bezel")
  check("title matches the intro scale", titleUp == introUp,
    ("title=%s intro=%s"):format(tostring(titleUp), tostring(introUp)))
  shot("02_title_skin")

  local title = game.stack:top()
  waitFor(function()
    U.tap(game, "a")
    U.wait(5)
    return game.stack:top() ~= title
  end, 60)
  if not check("opened the CONTINUE/NEW GAME menu", game.stack:top() ~= title) then finish() end
  U.wait(10)
  wholeFit("main menu over the title inside the bezel")
  shot("03_mainmenu_skin")

  local OverworldState = require("src.world.OverworldController")
  U.tap(game, "a")
  U.wait(10)
  local arrived = waitFor(function()
    U.tap(game, "a")
    U.wait(2)
    return game.stack:top() == OverworldState
  end, 1500)
  if not arrived then
    for i, s in ipairs(game.stack.states) do
      local keys = {}
      for k in pairs(s) do keys[#keys + 1] = tostring(k) end
      U.log("stack", i, tostring(s == OverworldState), tostring(s.screenId),
        table.concat(keys, ","):sub(1, 200))
    end
  end
  if not check("reached the overworld", arrived) then finish() end
  U.wait(20)
  U.tap(game, "start")
  U.wait(20)
  check("START menu is up", game.stack:top() ~= OverworldState)
  local owUp = wholeFit("overworld START menu inside the bezel")
  check("overworld matches the title scale", owUp == titleUp,
    ("overworld=%s title=%s"):format(tostring(owUp), tostring(titleUp)))
  shot("04_overworld_start_skin")

  TouchSkin.setActive(nil)
  game:returnToTitle()
  U.wait(30)
  local up, fit = scale()
  check("title with no skin still fills past the integer fit", up > fit,
    ("Up=%s fit=%s"):format(tostring(up), tostring(fit)))
  shot("05_title_noskin_fill")

  finish()
end

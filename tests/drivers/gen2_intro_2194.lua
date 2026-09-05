-- pokecrystal/engine/menus/init_gender.asm:23-41
-- pokecrystal/engine/menus/intro_menu.asm:645-696,854-872
-- pokecrystal/home/fade.asm:22-113
-- POKEPORT_DRIVER=tests/drivers/gen2_intro_2194.lua POKEPORT_IDENTITY=crystal-sep04 POKEPORT_VERSION=crystal POKEPORT_TOUCH=0 POKEPORT_SHOT_DIR=<dir> love .
local U = require("tests.drivers.util")

local GbcPalette = require("src.render.GbcPalette")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local OakSpeech = require("src.ui.gen2.OakSpeech")

local GameVersion = require("src.core.GameVersion")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2194-intro"
  local log = io.open(out .. "/driver.log", "w")

  local function say(line)
    print("[driver] " .. line)
    if log then log:write(line .. "\n"); log:flush() end
  end

  local function bail(reason)
    say("FAIL " .. reason)
    if log then log:close() end
    love.event.quit(1)
    error(reason, 0)
  end

  local function top() return game.stack:top() end
  local function isA(class)
    local state = top()
    return state ~= nil and getmetatable(state) == class
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return end
      U.wait(1)
    end
    bail(("stalled waiting for %s (top is %s)"):format(label, tostring(top())))
  end

  local function shoot(name, label)
    if not U.shot(game, out .. "/" .. name) then bail("no shot " .. name) end
    say("OK " .. label .. " -> " .. name)
  end

  local version = tostring(GameVersion.get())
  say("version=" .. version .. " engine=" .. tostring(GameVersion.engine()))

  for _ = 1, 900 do
    if isA(MainMenu) then break end
    tap("start", 2)
  end
  if not isA(MainMenu) then
    for _ = 1, 400 do
      if isA(MainMenu) then break end
      tap("a", 2)
    end
  end
  waitFor("the intro menu", function() return isA(MainMenu) end)
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")

  U.wait(4)
  if isA(GenderSelect) then
    local gender = top()
    if gender:menuOpen() then bail("the box was up before PrintText finished") end
    shoot("2194_01_gender_typing_no_box.png",
      "the prompt typing with no menu on it")
    if top():menuOpen() then bail("the box opened while the text still typed") end
    waitFor("the menu to open",
      function() return isA(GenderSelect) and top():menuOpen() end, 600)
    if not top().typer:done() then bail("the box opened before the text ended") end
    shoot("2194_02_gender_box_after_text.png", "LoadMenuHeader after PrintText")

    tap("a")
    waitFor("RotateFourPalettesLeft", function()
      if not isA(GenderSelect) then return false end
      local f = top().fade
      return f ~= nil and f.kind == "outBlack" and f.frame >= 12
    end, 600)
    local byte = top().fade:bgp()
    local rotated = GbcPalette.remap(GenderSelect.PALETTE, byte)
    if rotated[1][1] == GenderSelect.PALETTE[1][1]
        and rotated[1][2] == GenderSelect.PALETTE[1][2]
        and rotated[1][3] == GenderSelect.PALETTE[1][3] then
      bail(("outBlack 0x%02X left the textbox white"):format(byte))
    end
    shoot("2194_03_gender_rotated_blue.png",
      ("the screen palette permuted by 0x%02X"):format(byte))
  else
    say("OK no gender screen on " .. version)
  end

  waitFor("the clock screen", function() return isA(InitClock) end, 600)
  for _ = 1, 200 do
    if isA(OakSpeech) then break end
    if isA(InitClock) and top().fade == nil then tap("a", 3) else U.wait(1) end
  end
  waitFor("the Oak speech", function() return isA(OakSpeech) end, 600)

  waitFor("Oak's palette walk", function()
    local r = isA(OakSpeech) and top().picReveal
    return r ~= nil and r.kind == "rotate" and r.t >= 12
  end, 600)
  local speech = top()
  local row = OakSpeech.frontpicBgp(speech.picReveal.t)
  if row ~= 0xA8 and row ~= 0xFC then
    bail(("the walk is on 0x%02X at frame %d, not a flat silhouette")
      :format(row, speech.picReveal.t))
  end
  if getmetatable(top()) ~= OakSpeech then
    bail("OakText1 printed before the walk finished")
  end
  shoot("2194_04_oak_silhouette_col2.png",
    ("Oak flat on row 0x%02X"):format(row))

  waitFor("OakText1", function()
    return isA(OakSpeech) == false and top() ~= nil
  end, 600)
  say("OK the text box is up only after the walk")

  local shotWhite = false
  for _ = 1, 900 do
    if isA(OakSpeech) then
      local state = top()
      local f = state.fade
      if f and f.kind == "outWhite" and f.frame >= 10 then
        shoot("2194_05_oak_to_white_rotated.png",
          "RotateThreePalettesRight between Oak's pages")
        shotWhite = true
        break
      elseif f or state.picReveal then
        U.wait(1)
      else
        tap("a", 2)
      end
    else
      tap("a", 2)
    end
  end
  if not shotWhite then bail("no fade to white between Oak's pages") end

  say("PASS gen2 intro 2194 (" .. version .. ") in " .. out)
  if log then log:close() end
  love.event.quit(0)
end

local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS u1c_pc_lit")
    love.event.quit(0)
  else
    print("FAIL u1c_pc_lit failures=" .. failures)
    love.event.quit(1)
  end
end

local function waitFor(pred, n)
  for _ = 1, n do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function pcMid()
  local Map = require("src.core.game3.map")
  local def = Map.currentDef and Map.currentDef()
  local layout = def and def.midLayout
  return layout and layout:midAt(1, 1)
end

local function slotStats(ts, mid)
  local slot = ts.midToSlot[mid]
  if not slot or not ts.imageData then return nil end
  local sx, sy = (slot % ts.cols) * 16, math.floor(slot / ts.cols) * 16
  local lit, sig = 0, {}
  for y = 0, 15 do
    for x = 0, 15 do
      local r, g, b = ts.imageData:getPixel(sx + x, sy + y)
      if r + g + b > 0.05 then lit = lit + 1 end
      sig[#sig + 1] = string.format("%.2f%.2f%.2f", r, g, b)
    end
  end
  return lit, table.concat(sig)
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PLAYERS_HOUSE_2F", { x = 1, y = 2, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 1, 2, "up"
  U.wait(90)

  local NativeTileset = require("src.core.game3.tileset_native")
  local def = Map.currentDef and Map.currentDef()
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  local ts = pair and NativeTileset.get(pair)
  local PcAnim = require("src.core.game3.pc_anim")
  result(ts and ts.midToSlot[0x28A] ~= nil and PcAnim.drawable(0x28A),
    "player_house atlas carries PlayersPCOn 0x28A (pair " .. tostring(pair) .. ")")
  local onLit, onSig = slotStats(ts or { midToSlot = {} }, 0x28A)
  local offLit, offSig = slotStats(ts or { midToSlot = {} }, 0x28F)
  result(onLit and onLit > 0 and onSig ~= offSig,
    string.format("0x28A atlas slot is a real tile, not the black void (lit px %s, off px %s)",
      tostring(onLit), tostring(offLit)))

  result(pcMid() == 0x28F, string.format("PC starts dark 0x28F (got %s)", tostring(pcMid())))
  U.shot(game, DIR .. "/u1c_01_pc_dark_before_a.png")

  U.tap(game, "a")
  local seen, last = {}, pcMid()
  for _ = 1, 45 do
    local m = pcMid()
    if m ~= last then
      seen[#seen + 1] = string.format("%X", m or 0)
      last = m
    end
    U.wait(1)
  end
  local seq = table.concat(seen, ",")
  result(seq == "28A,28F,28A,28F,28A", "turn-on flickers on/off/on/off/on (got " .. seq .. ")")
  local Message = package.loaded["src.ui.game3.message"]
  result(pcMid() == 0x28A and Message and Message.isOpen and Message.isOpen(), "PC screen lit behind booted-up message")
  U.shot(game, DIR .. "/u1c_02_pc_lit_booted_msg.png")

  local PcMenu
  local opened = false
  for _ = 1, 6 do
    U.tap(game, "a")
    opened = waitFor(function()
      PcMenu = package.loaded["src.ui.game3.pc_menu"]
      return PcMenu and PcMenu.isOpen and PcMenu.isOpen()
    end, 60)
    if opened then break end
  end
  U.wait(10)
  if not result(opened and PcMenu.mode == "player_pc", "player PC top menu open") then
    return finish()
  end
  result(pcMid() == 0x28A, "PC stays lit while the menu is open")
  U.shot(game, DIR .. "/u1c_03_pc_lit_menu_open.png")

  U.tap(game, "down"); U.wait(12)
  U.tap(game, "down"); U.wait(12)
  U.tap(game, "a")
  local closedOk = waitFor(function()
    local Space = package.loaded["src.core.game3.scripting.space"]
    local running = Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
    return not PcMenu.isOpen() and not running and not (Message and Message.isOpen and Message.isOpen())
  end, 120)
  U.wait(20)
  result(closedOk, "TURN OFF closes the PC")
  result(pcMid() == 0x28F, string.format("PC screen dark again after turn-off (got %s)", tostring(pcMid())))
  U.shot(game, DIR .. "/u1c_04_pc_dark_after_turn_off.png")

  finish()
end

-- engine/pokemon/bills_pc.asm
--   POKEPORT_VERSION=crystal POKEPORT_IDENTITY=crystal-sep04 POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_billspc_deposit_bug2238.lua \
-- ../pokegold/engine/pokemon/bills_pc.asm:1439-1490, home/pokemon.asm:101-107, home/pokemon.asm:124-127
local U = require("tests.drivers.util")

local Boxes = require("src.core.gen2.Boxes")
local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local Screens = require("src.ui.Screens")

return function(game)
  local version = GameVersion.get()
  local crystal = GameVersion.engine(version) == "crystal"
  local out = (os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bsa2238") .. "/2238_" .. version
  local fails = 0
  local function say(line) print("[2238] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function finish()
    say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    love.event.quit(fails == 0 and 0 or 1)
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  local function loadShot(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local data = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = data:getWidth(), data:getHeight()
    local scale = math.max(1, math.floor(math.min(w / 160, h / 144)))
    local ox = math.floor((w - 160 * scale) / 2)
    local oy = math.floor((h - 144 * scale) / 2)
    return { data = data, scale = scale, ox = ox, oy = oy }
  end
  local function px(shot, x, y)
    local s = shot.scale
    local r, g, b = shot.data:getPixel(shot.ox + x * s + math.floor(s / 2),
      shot.oy + y * s + math.floor(s / 2))
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
  end
  local function dark(shot, x, y)
    local r, g, b = px(shot, x, y)
    return r + g + b < 3 * 64
  end
  local function anyDark(shot, x0, x1, y0, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        if dark(shot, x, y) then return true, x, y end
      end
    end
    return false
  end
  local function uniform(shot, x0, x1, y0, y1)
    local r0, g0, b0 = px(shot, x0, y0)
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b = px(shot, x, y)
        if r ~= r0 or g ~= g0 or b ~= b0 then return false end
      end
    end
    return true, r0, g0, b0
  end
  local function frameOnRow1(shot, label)
    if crystal then
      ok(dark(shot, 72, 29) and dark(shot, 150, 29), label .. ": top line y=29 x=72..150")
      ok(dark(shot, 72, 41), label .. ": bottom line y=41")
      ok(dark(shot, 70, 31) and dark(shot, 152, 31), label .. ": sides x=70 / x=152")
      ok(dark(shot, 71, 30) and dark(shot, 151, 40), label .. ": rounded corner pixels")
      ok(not dark(shot, 70, 29) and not dark(shot, 70, 30), label .. ": corner cell (70,29) open")
      ok(not anyDark(shot, 70, 152, 24, 28), label .. ": nothing above y=29 (no 80x16 frame)")
    else
      ok(dark(shot, 71, 25) and dark(shot, 150, 25), label .. ": top line y=25 x=71..150")
      ok(dark(shot, 71, 40) and dark(shot, 71, 30), label .. ": left side x=71 down to y=40")
      ok(dark(shot, 71, 25) and dark(shot, 150, 40), label .. ": square corners")
      ok(not dark(shot, 72, 29) and not dark(shot, 70, 31), label .. ": no 83x13 crystal frame")
    end
  end

  U.wait(60)
  if not (game.world and game.world.map) then
    game:startNewGame({ intro = false })
    U.wait(90)
  end
  if not (game.world and game.world.map) then
    say("FAIL the " .. version .. " world did not boot")
    return finish()
  end
  local save, data = game.save, game.data

  save.party = {}
  save.party[1] = Mon.new(data, "TYRANITAR", 55)
  for _ = 1, 4 do save.party[#save.party + 1] = Mon.new(data, "CYNDAQUIL", 10) end
  save.currentBox = 1
  local box = Boxes.box(save, 1)
  for i = #box, 1, -1 do box[i] = nil end
  if not save.party[1] then
    say("FAIL no TYRANITAR in this cache")
    return finish()
  end

  Screens.push(game, "Gen2BoxMenu", {
    save = save, mode = "deposit",
    onClose = function() game.stack:pop() end,
  })
  U.wait(8)
  local menu = game.stack:top()
  ok(menu and menu.submenuRows ~= nil, "the deposit list is up")
  ok(menu:isCrystal() == crystal, "engine gate reads " .. tostring(crystal))

  local p1 = out .. "_01_list_frame.png"
  U.shot(game, p1)
  local s1 = loadShot(p1)
  if not s1 then say("FAIL no shot") return finish() end
  frameOnRow1(s1, "01 list")
  ok(not anyDark(s1, 67, 155, 23, 23), "01 list: row 2 y=23 has no corner stubs")
  ok(dark(s1, 67, 21) and dark(s1, 155, 21) and not dark(s1, 66, 22) and not dark(s1, 156, 22),
    "01 list: row 2 is the header's own '└ ─ ┘' (inset one pixel at 66/156)")

  tap("a")
  ok(menu.phase == "submenu", "A opens the submenu")
  local p2 = out .. "_02_submenu_no_frame.png"
  U.shot(game, p2)
  local s2 = loadShot(p2)
  local hit, hx, hy = anyDark(s2, 70, 152, 24, 29)
  ok(not hit, "02 submenu: no frame pixels in y=24..29" .. (hit and (" (dark at " .. hx .. "," .. hy .. ")") or ""))
  ok(dark(s2, 72, 32) or anyDark(s2, 72, 152, 32, 47), "02 submenu: the DEPOSIT row is drawn")

  game.input.pressQueue[#game.input.pressQueue + 1] = "a"
  game.input.state.a = true
  U.wait(2)
  game.input.state.a = false
  U.wait(1)
  if crystal then
    ok(menu.cryWait ~= nil, "03 cry: Crystal is waiting on the cry")
    ok(menu.message == nil and menu.panelCleared == nil, "03 cry: no Stored yet, panel intact")
    local pm = menu:panelMon()
    ok(pm and pm.species == "TYRANITAR", "03 cry: panelMon is the deposited TYRANITAR")
    local p3 = out .. "_03_cry_pic_held.png"
    U.shot(game, p3)
    local s3 = loadShot(p3)
    ok(menu.cryWait ~= nil, "03 cry: still waiting after the shot")
    ok(not uniform(s3, 8, 63, 32, 87), "03 cry: the pic block is still painted")
    ok(anyDark(s3, 8, 60, 96, 111), "03 cry: level / name still on the panel")
    ok(anyDark(s3, 72, 152, 48, 63), "03 cry: submenu still up")
    ok(menu:prompt():find("What") ~= nil, "03 cry: prompt still What's up?")
    ok(not anyDark(s3, 70, 152, 24, 29), "03 cry: no frame under the submenu")
    for _ = 1, 300 do
      if menu.cryWait == nil then break end
      U.wait(1)
    end
    ok(menu.cryWait == nil, "03 cry: the wait released")
  else
    ok(menu.cryWait == nil, "03 gold: no cry wait")
    ok(menu.message ~= nil and menu.panelCleared == true, "03 gold: Stored printed at once, panel cleared")
    local p3 = out .. "_03_gold_no_cry_wait.png"
    U.shot(game, p3)
  end

  ok(menu.message ~= nil and tostring(menu.message):find("Stored") ~= nil,
    "04 stored: message is " .. tostring(menu.message))
  local p4 = out .. "_04_stored_box.png"
  U.shot(game, p4)
  local s4 = loadShot(p4)
  ok(uniform(s4, 8, 63, 32, 87), "04 stored: pic block blank")
  ok(not anyDark(s4, 0, 63, 96, 103), "04 stored: no box border at tile row 12")
  ok(anyDark(s4, 8, 63, 120, 127), "04 stored: box top border at tile row 15")
  ok(anyDark(s4, 8, 100, 128, 135), "04 stored: text at row 16")
  ok(not anyDark(s4, 70, 152, 24, 29), "04 stored: no frame")

  for _ = 1, 120 do
    if menu.message == nil then break end
    U.wait(1)
  end
  U.wait(2)
  ok(menu.message == nil and menu.phase == nil, "05 back: list restored")
  ok(menu.index == 1, "05 back: cursor on row 1")
  local p5 = out .. "_05_back_list.png"
  U.shot(game, p5)
  local s5 = loadShot(p5)
  frameOnRow1(s5, "05 back")
  ok(#save.party == 4 and #Boxes.box(save, 1) == 1, "05 back: TYRANITAR in BOX1")

  finish()
end

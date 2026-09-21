local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_braille"

local RUIN_VALLEY = "FR_SIX_ISLAND_RUIN_VALLEY"
local RUBY_PATH_B5F = "FR_MT_EMBER_RUBY_PATH_B5F"

local PRET = "../pokefirered"
local BRAILLE_INC = PRET .. "/data/text/braille.inc"
local WALL_INC = PRET .. "/data/maps/MtEmber_RubyPath_B5F/scripts.inc"
local DOOR_INC = PRET .. "/data/maps/SixIsland_RuinValley/scripts.inc"

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function pretLiterals()
  local src = slurp(BRAILLE_INC)
  if not src then return nil end
  local byLabel = {}
  for label, body in src:gmatch("(Braille_Text_[%w_]+)::%s*\n%s*%.braille%s+\"(.-)%$\"") do
    byLabel[label] = body
  end
  return byLabel
end

-- pokefirered/include/characters.h:285
local BRAILLE_PUNCT = {
  SPACE = " ", COMMA = ",", PERIOD = ".", COLON = ":", APOSTROPHE = "'",
  SLASH = "/", SEMICOLON = ";", EXCL_MARK = "!", QUESTION_MARK = "?",
  NUMBER = "#", HYPHEN = "-", PAREN = "(", DBL_QUOTE_RIGHT = "\"",
}

local function pretCodes()
  local src = slurp(PRET .. "/include/characters.h")
  if not src then return nil end
  local codes, n = {}, 0
  for name, hex in src:gmatch("#define%s+BRAILLE_CHAR_([%w_]+)%s+(0x%x+)") do
    local ch = (#name == 1) and name or BRAILLE_PUNCT[name]
    if ch then
      codes[ch] = tonumber(hex)
      n = n + 1
    end
  end
  if n == 0 then return nil end
  return codes
end

local function pretPages(incPath, byLabel)
  local src = slurp(incPath)
  if not (src and byLabel) then return nil end
  local pages = {}
  for label in src:gmatch("braillemessage[_%a]*%s+(Braille_Text_[%w_]+)") do
    if not byLabel[label] then return nil end
    pages[#pages + 1] = byLabel[label]
  end
  if #pages == 0 then return nil end
  return pages
end

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_braille")
    love.event.quit(0)
  else
    print("FAIL stitchimp_braille failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Braille = require("src.ui.game3.braille")
  local Collision = require("src.core.game3.collision")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function stepTo(x, y)
    for _ = 1, 30 do
      if Player.cellX == x and Player.cellY == y then break end
      local btn
      if Player.cellX < x then btn = "right"
      elseif Player.cellX > x then btn = "left"
      elseif Player.cellY < y then btn = "down"
      else btn = "up" end
      U.hold(game, btn, 10)
      U.wait(14)
    end
    return Player.cellX == x and Player.cellY == y
  end

  local function codesOf(text)
    local out = {}
    for _, line in ipairs(Braille.encode(text or "")) do
      for _, code in ipairs(line) do
        out[#out + 1] = string.format("%02X", code or 0xFF)
      end
    end
    return table.concat(out, " ")
  end

  local pretChar = pretCodes()
  local function pretCodesOf(text)
    if not pretChar then return nil end
    local out = {}
    for ch in tostring(text or ""):gmatch("[^\n]") do
      local code = pretChar[ch]
      if not code then return nil end
      out[#out + 1] = string.format("%02X", code)
    end
    return table.concat(out, " ")
  end

  local function checkCodes(text, label)
    local want = pretCodesOf(text)
    if not want then
      print("[driver] skip " .. label .. ": no " .. PRET .. "/include/characters.h")
      return
    end
    result(codesOf(text) == want,
      label .. " encodes to pret's braille codes " .. want .. ", got " .. codesOf(text))
  end

  local function allDrawable(text)
    for ch in tostring(text or ""):gmatch("[^\n]") do
      if Braille.CODE[ch] == nil then return false, ch end
    end
    return true
  end

  local function reachBraille(taps)
    for _ = 1, taps do
      if Braille.isOpen() then return true end
      U.tap(game, "a")
      U.wait(20)
    end
    return Braille.isOpen()
  end

  local function clearScript()
    for _ = 1, 60 do
      if not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) then break end
      U.tap(game, "a")
      U.wait(14)
    end
    U.wait(20)
  end

  result(Braille.hasSheet(), "the braille glyph sheet is in the cache")

  local byLabel = pretLiterals()
  local doorPages = byLabel and pretPages(DOOR_INC, byLabel)
  local wallPages = byLabel and pretPages(WALL_INC, byLabel)
  if not (doorPages and wallPages) then
    print("[driver] skip the pret text comparisons: no " .. BRAILLE_INC ..
      " / map scripts.inc to read the literals from")
  end

  -- data/maps/SixIsland_RuinValley/scripts.inc:24-31
  goTo(RUIN_VALLEY, 24, 25, "up")
  result(Player.cellX == 24 and Player.cellY == 25,
    "standing south of the Ruin Valley dotted-hole door at (24,25)")
  U.hold(game, "up", 20)
  U.wait(10)
  U.tap(game, "a")
  U.wait(40)
  print("[driver] Ruin Valley door prompt: [" .. (Message.currentPage() or "") .. "]")
  reachBraille(8)
  local page = Message.currentPage() or ""
  print("[driver] Ruin Valley braille page: [" .. page .. "] codes " .. codesOf(page))
  result(Braille.isOpen(), "the Ruin Valley door opened the braille frame")
  if doorPages then
    result(page == doorPages[1],
      "the door reads pret's Braille_Text_Cut [" .. doorPages[1] .. "], got [" .. page .. "]")
  end
  local okDraw, badCh = allDrawable(page)
  result(okDraw, "every glyph is a real braille character, not a fallback: " .. tostring(badCh))
  -- include/characters.h:288,323,315
  checkCodes(page, "the dotted-hole door")
  U.shot(game, DIR .. "/stitchimp_braille_01_ruin_valley_cut.png")
  clearScript()

  -- data/maps/MtEmber_RubyPath_B5F/scripts.inc:4-16
  goTo(RUBY_PATH_B5F, 7, 5, "up")
  result(stepTo(7, 3), "walked north to the Ruby Path B5F braille wall, standing at ("
    .. Player.cellX .. "," .. Player.cellY .. ") facing " .. tostring(Player.facing))
  if Collision.isWalkable(7, 2) then
    print("[driver] HANDOFF FR_MT_EMBER_RUBY_PATH_B5F (7,2) is walkable in the port and "
      .. "impassable on the cart (data/layouts/MtEmber_RubyPath_B5F/map.bin cell 7,2 has "
      .. "collision 1), so holding UP walks the player onto the braille wall instead of "
      .. "facing it.")
  end
  U.tap(game, "a")
  U.wait(45)
  local shown = {}
  while Braille.isOpen() and #shown < 24 do
    local body = Message.currentPage() or ""
    shown[#shown + 1] = body
    print("[driver] Ruby Path page " .. #shown .. ": [" .. body .. "] codes " .. codesOf(body))
    if #shown == 1 then
      U.shot(game, DIR .. "/stitchimp_braille_02_ruby_path_first_page.png")
    end
    U.shot(game, DIR .. "/stitchimp_braille_03_ruby_path_last_page.png")
    U.tap(game, "a")
    U.wait(45)
  end
  result(#shown > 0, "the Ruby Path wall printed " .. #shown .. " braille pages")
  if wallPages then
    local wrong = nil
    for i = 1, math.max(#wallPages, #shown) do
      if shown[i] ~= wallPages[i] then
        wrong = wrong or (i .. ": wanted [" .. tostring(wallPages[i]) ..
          "] got [" .. tostring(shown[i]) .. "]")
      end
    end
    result(wrong == nil, "the Ruby Path pages read pret's " .. #wallPages ..
      " braillemessage literals in order: " .. tostring(wrong))
    -- data/text/braille.inc:47
    checkCodes(shown[1] or "", "the first Ruby Path page")
  end
  local noFallback = true
  for _, body in ipairs(shown) do
    if not allDrawable(body) then noFallback = false end
  end
  result(noFallback, "no page fell back to the question mark glyph")

  clearScript()
  result(not (Space.vm and Space.vm:isRunning()),
    "the braille wall released control at the end of the sequence")

  finish()
end

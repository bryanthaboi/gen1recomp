-- engine/events/prof_oaks_pc.asm:14
local U = require("tests.drivers.util")
local RomText = require("src.core.RomText")

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-oak-pc-rating-s7"

  U.wait(60)
  local w = game.world
  if not check(w and w.map and game.save and game.stack, "gen2 field booted") then
    return love.event.quit(1)
  end

  local SEEN, CAUGHT = 210, 205
  local Mon = require("src.battle.gen2.Mon")
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
  save.pokedex = { seen = {}, caught = {} }
  for i = 1, SEEN do save.pokedex.seen["DEX" .. i] = true end
  for i = 1, CAUGHT do save.pokedex.caught["DEX" .. i] = true end
  local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")
  w:setEngineFlag(w:engineFlagId("ENGINE_POKEDEX"), true)

  w:warpToMapId("CHERRYGROVE_POKECENTER_1F", 4, 4, "up")
  U.wait(30)
  local pcX, pcY
  for cy = 0, w.map.heightCells - 1 do
    for cx = 0, w.map.widthCells - 1 do
      if w.map:cellCollision(cx, cy) == 0x93 then pcX, pcY = cx, cy end
    end
  end
  if not check(pcX ~= nil, "the Pokecenter has a COLL_PC tile") then
    return love.event.quit(1)
  end
  w:warpToMapId("CHERRYGROVE_POKECENTER_1F", pcX, pcY + 1, "up")
  U.wait(30)

  local function topId()
    local top = game.stack:top()
    return top and top.screenId or nil
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end
  local pc
  local function typed()
    return pc and pc.message and not (pc.typer and not pc.typer:done())
  end
  local function press(button)
    waitFor(function() return not (pc and pc.typer and not pc.typer:done()) end)
    U.tap(game, button)
    U.wait(4)
  end

  U.tap(game, "a")
  if not check(waitFor(function() return topId() == "Gen2CenterPcMenu" end),
      "A at the PC opens the whose-PC menu") then
    return love.event.quit(1)
  end
  pc = game.stack:top()
  press("a")
  check(pc.entries[3] and pc.entries[3].id == "oaks"
    and pc.entries[3].label == game.data.text["PokemonCenterPC.String_OaksPC"],
    "row 3 is PokemonCenterPC.String_OaksPC: " .. tostring(pc.entries[3] and pc.entries[3].label))
  press("down")
  press("down")
  press("a")
  press("a")
  press("a")
  if not check(waitFor(function() return pc.confirm ~= nil end), "_OakPCText1 asks for the yes/no") then
    return love.event.quit(1)
  end
  press("a")

  local text = game.data.text
  local function flat(label, ...)
    local body = RomText(game.data, label, nil, ...)
    return (body:gsub("{DONE}", ""):gsub("{PROMPT}", ""):gsub("[\f\v]", "\n"))
  end
  local function shows(page, body)
    return body:find(table.concat(page, "\n"), 1, true) ~= nil
  end

  local pages, ratingPage, completionShot, ratingShot = {}, nil, false, false
  local Specials = require("src.script.gen2.Specials")
  local rating = Specials.findOakRating(Specials.oakRatings(game.data), CAUGHT)
  for _ = 1, 12 do
    if not waitFor(typed, 600) then break end
    local page = pc.message.pages[pc.message.page]
    pages[#pages + 1] = page
    if #pages == 1 then
      completionShot = U.still(game, dir .. "/s7_01_oak_completion_level.png")
    elseif table.concat(page, "\n") == flat(rating.text):match("^[^\n]*\n[^\n]*") and not ratingShot then
      ratingPage = page
      ratingShot = U.still(game, dir .. "/s7_02_oak_rating.png")
    end
    press("a")
    if not pc.message then break end
  end

  local all = table.concat({ flat("_OakPCText2"), flat("_OakPCText3", SEEN, CAUGHT),
    flat(rating.text), flat("_OakPCText4") }, "\n")
  local stray = {}
  for i, page in ipairs(pages) do
    if not shows(page, all) then stray[#stray + 1] = i .. ":" .. table.concat(page, "/") end
  end
  check(#pages >= 4, "the rating flow printed " .. #pages .. " pages")
  check(#stray == 0, "every page is a run of data.text lines: " .. table.concat(stray, " "))
  check(pages[1] and table.concat(pages[1], "\n") == flat("_OakPCText2"),
    "page 1 is _OakPCText2: " .. tostring(pages[1] and table.concat(pages[1], "/")))
  check(pages[2] and table.concat(pages[2], "\n") == flat("_OakPCText3", SEEN, CAUGHT):match("^[^\n]*\n[^\n]*"),
    "page 2 is _OakPCText3 with the counts: " .. tostring(pages[2] and table.concat(pages[2], "/")))
  check(rating.text == "OakRating15" and rating.max == 214 and ratingPage ~= nil,
    "205 caught reaches events.oakRatings' OakRating15 row out of data.text: " .. tostring(text[rating.text]))
  check(completionShot, "completion-level shot written")
  check(ratingShot, "rating shot written")
  check(pc.message == nil and not pc.closed and topId() == "Gen2CenterPcMenu",
    "_OakPCText4 drops back to the whose-PC menu")

  print(failed == 0 and "PASS gen2_oak_pc_rating_s7"
    or ("FAIL gen2_oak_pc_rating_s7 (%d)"):format(failed))
  love.event.quit(failed == 0 and 0 or 1)
end

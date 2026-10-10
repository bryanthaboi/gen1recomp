-- engine/menus/players_pc.asm:151-173
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")
  local Font = require("src.render.Font")

  local ok = true
  local function check(label, cond)
    if not cond then ok = false end
    U.log(cond and "PASS" or "FAIL", label)
  end
  local function hasLabel(menu, needle)
    if getmetatable(menu) ~= Menu then return false end
    for _, it in ipairs(menu.items or {}) do
      if type(it.label) == "string" and it.label:find(needle, 1, true) then return true end
    end
    return false
  end
  local function mash(cond)
    for _ = 1, 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end
  local function boxOrder(state)
    local seen = {}
    local real = Font.drawBox
    Font.drawBox = function(tx, ty, ...)
      seen[#seen + 1] = tx .. "," .. ty
      return real(tx, ty, ...)
    end
    local good, err = pcall(state.draw, state)
    Font.drawBox = real
    if not good then error(err, 0) end
    return table.concat(seen, " ")
  end
  local function done()
    love.event.quit(ok and 0 or 1)
  end

  game.save.pcItems = { POTION = 3 }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  U.tap(game, "a")
  check("pc main menu opens", mash(function() return hasLabel(game.stack:top(), "LOG OFF") end))
  U.wait(8)
  U.tap(game, "down")
  U.wait(3)
  U.tap(game, "a")
  check("player pc opens", mash(function() return hasLabel(game.stack:top(), "WITHDRAW ITEM") end))
  U.wait(8)
  U.tap(game, "a")
  U.wait(10)
  local list = game.stack:top()
  check("withdraw list open", list and list.kind == "pc_item_withdraw")
  if not (list and list.kind == "pc_item_withdraw") then return done() end
  check("prompt box under the list", boxOrder(list):find("0,12 4,2", 1, true) ~= nil)
  U.still(game, DIR .. "/2840_01_withdraw_list_over_prompt.png")

  U.tap(game, "a")
  U.wait(10)
  check("How many? box over the list", boxOrder(list):find("4,2 0,12", 1, true) ~= nil)
  U.still(game, DIR .. "/2840_02_how_many_over_list.png")
  done()
end

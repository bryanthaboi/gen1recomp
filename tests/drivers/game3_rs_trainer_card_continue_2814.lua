local U = require("tests.drivers.util")

local MARKER = "drv2814_seeded"
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "card2814 " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "card2814 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function cardChecks(session, tag)
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local C = require("src.core.game3.constants").of(session.version)
  local dex, b1 = C:require("flags", "FLAG_SYS_POKEDEX_GET"), C:require("flags", "FLAG_BADGE01_GET")
  check(session.store == nil, tag .. "_no_fabricated_session_store")
  check(Flags.getFlag(Space.store, nil, dex) and Flags.getFlag(Space.store, nil, b1) and Flags.getFlag(Space.store, nil, b1 + 1),
    tag .. "_live_store_has_dex_and_badges")
  if session.version == "ruby" or session.version == "sapphire" then
    local card = require("src.ui.game3.rs.trainer_card_policy").generate(session)
    check(card.hasPokedex == true, tag .. "_card_hasPokedex")
    check(card.badges[1] == true and card.badges[2] == true and card.badges[3] == false, tag .. "_card_badges_1_2")
  end
end

local function bootReady(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  return check(game.phase == "boot" and game.boot ~= nil, "boot_ready")
end

local function seed(game)
  game:_handleBootAction({ action = "new_game", name = "TAI" })
  U.wait(180)
  local session = require("src.core.game3.runtime").getSession()
  if not check(session ~= nil, "seed_field_session_ready") then return end
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local C = require("src.core.game3.constants").of(session.version)
  Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_SYS_POKEDEX_GET"), true)
  Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_SYS_CLOCK_SET"), true)
  for i = 0, 1 do Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_BADGE01_GET") + i, true) end
  cardChecks(session, "seed")
  if check(game:saveGame() ~= false, "seed_save_written") then
    love.filesystem.write(MARKER, "1")
    print("card2814 seeded; run again to continue")
  end
end

local function continueAndOpen(game)
  game:_handleBootAction({ action = "continue" })
  U.wait(180)
  local session = require("src.core.game3.runtime").getSession()
  if not check(session ~= nil, "continue_field_session_ready") then return end
  cardChecks(session, "continue")
  local Card = require("src.ui.game3.screens").get("trainer_card", session)
  Card.show({ session = session })
  U.wait(120)
  local shots = os.getenv("POKEPORT_SHOT_DIR")
  if shots then U.still(game, shots .. "/2814_card_front_" .. tostring(session.version) .. ".png") end
  love.filesystem.remove(MARKER)
end

return function(game)
  if not bootReady(game) then return finish() end
  if love.filesystem.getInfo(MARKER) then
    continueAndOpen(game)
  else
    seed(game)
  end
  finish()
end

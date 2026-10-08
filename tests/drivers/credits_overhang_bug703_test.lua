-- engine/movie/credits.asm:1
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  -- the roll ends in an autosave; put the user's save back afterwards
  local prevSave = love.filesystem.read("save.lua")

  U.teleport(game, "HALL_OF_FAME", 4, 2, "right")
  game.save.party = { { species = "PIKACHU", level = 81, hp = 100,
                         stats = { hp = 100 }, moves = {} } }
  game.overworld.runner:run({ { "record_hall_of_fame" } })
  U.wait(2)

  -- A through the induction until the credits state is on top; the full
  -- hall-of-fame walk takes well over 60 taps, so give it real room
  local Credits = require("src.ui.Credits")
  local credits
  for _ = 1, 2000 do
    local top = game.stack:top()
    if getmetatable(top) == Credits then credits = top break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not check("credits state reached", credits ~= nil) then
    love.event.quit(1)
    return
  end

  -- engine/movie/credits.asm:29
  -- no screenshots inside this loop: U.shot yields extra fixed steps of its
  -- own and would silently skew the count
  local musicStart, theEndAt, prepFrames = nil, nil, 0
  for f = 1, 7000 do
    U.wait(1)
    local phase = credits.phase
    if not musicStart and phase ~= "white" then musicStart = f end
    if phase == "mon_prep" then prepFrames = prepFrames + 1 end
    if phase == "end_hold" then theEndAt = f break end
  end

  check("mon_prep ran 776 frames across the 15 mon screens",
        prepFrames == 776)
  check("THE END finishes fading 5795 frames after the music starts",
        musicStart ~= nil and theEndAt ~= nil
          and theEndAt - musicStart == 5795)
  U.log("music started at driver frame", musicStart,
        "THE END done at", theEndAt, "mon_prep frames", prepFrames)
  U.shot(game, DIR .. "/bug703_the_end.png")

  U.wait(205)

  if prevSave then
    love.filesystem.write("save.lua", prevSave)
  else
    love.filesystem.remove("save.lua")
  end
  love.event.quit(failed and 1 or 0)
end

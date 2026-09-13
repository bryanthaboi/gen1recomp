-- POKEPORT_IDENTITY=red-sep04 POKEPORT_SHOT_DIR=/tmp/shots/2274 POKEPORT_DRIVER=tests/drivers/seafoam_hole_current_2274.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")

  local FROM, HX, HY = "SEAFOAM_ISLANDS_B2F", 19, 6
  local TO, LX, LY = "SEAFOAM_ISLANDS_B3F", 18, 7

  local failures = 0
  local function check(label, ok)
    if ok then
      U.log("PASS", label)
    else
      U.log("FAIL", label)
      failures = failures + 1
    end
    return ok
  end

  if not game.save.party or #game.save.party == 0 then
    game.save.party = { Pokemon.new(game.data, "LAPRAS", 40),
                        Pokemon.new(game.data, "SNORLAX", 45) }
  end
  game.save.flags = game.save.flags or {}
  for k in pairs(game.save.flags) do
    if k:match("^EVENT_SEAFOAM[34]_BOULDER") then game.save.flags[k] = nil end
  end

  local realPlayMap = Music.playMap
  local musicLog = {}
  Music.playMap = function(data, mapId, onBike, surfing, ...)
    musicLog[#musicLog + 1] = { mapId = mapId, surfing = surfing and true or false,
                                t = U.frame() }
    return realPlayMap(data, mapId, onBike, surfing, ...)
  end

  local function fall(shots)
    U.teleport(game, FROM, HX, HY + 1, "up")
    U.wait(10)
    musicLog = {}
    U.hold(game, "up", 18)
    local rec = { dropFrames = 0, badDrop = 0, earlySurf = 0, earlyMoves = 0,
                  slideFrames = 0, slideSpin = 0 }
    for _ = 1, 900 do
      local ow = game.overworld
      local p = ow and ow.player
      if ow and ow.map.id == TO then
        if not rec.arrival then
          rec.arrival = U.frame()
          rec.ax, rec.ay = p.cellX, p.cellY
        end
        local t = U.frame() - rec.arrival
        local landing = not rec.landedAt
                        and (ow.transitioning or ow.holeArrive or ow.spinArrive
                             or game.stack:top() ~= ow)
        if landing then
          if p.surfing then rec.earlySurf = rec.earlySurf + 1 end
          if #ow.scriptMoves > 0 or p.cellX ~= LX or p.cellY ~= LY then
            rec.earlyMoves = rec.earlyMoves + 1
          end
          if ow.holeArrive and not rec.holdAt then rec.holdAt = t end
          if p.spinning and not ow.holeArrive then
            rec.dropStart = rec.dropStart or t
            rec.dropEnd = t
            rec.dropFrames = rec.dropFrames + 1
            local _, _, _, facing, phase, flip = p:pose()
            if facing ~= "down" or phase ~= 1 or not flip then
              rec.badDrop = rec.badDrop + 1
            end
          end
        else
          if not rec.landedAt then
            rec.landedAt = t
            rec.landedAbs = U.frame()
          end
          if p.surfing and not rec.surfAt then rec.surfAt = t end
          if #ow.scriptMoves > 0 or p.moving then
            rec.slideStart = rec.slideStart or t
            rec.slideFrames = rec.slideFrames + 1
            if p.spinning or ow.spinnerSliding then rec.slideSpin = rec.slideSpin + 1 end
            if t - rec.slideStart > 60 then break end
          elseif rec.slideStart then
            break
          end
        end
        for _, s in ipairs(shots or {}) do
          if not s.done and s.at and t >= s.at then
            s.done = true
            U.shot(game, DIR .. "/" .. s.name)
            U.log("captured", DIR .. "/" .. s.name)
          end
        end
      end
      U.wait(1)
    end
    rec.music = musicLog
    return rec
  end

  local rec = fall(nil)

  check("2274 fell to B3F (18,7)", rec.arrival ~= nil and rec.ax == LX and rec.ay == LY)
  check("2274 on foot through the hold and drop", rec.earlySurf == 0)
  check("2274 current waits for the landing", rec.earlyMoves == 0)
  check(("2274 drop faces down without spinning (%d frames)"):format(rec.dropFrames),
        rec.dropFrames > 0 and rec.badDrop == 0)
  check("2274 surf mounts on the landing frame",
        rec.surfAt ~= nil and rec.landedAt ~= nil and rec.surfAt == rec.landedAt)
  check("2274 current starts after the landing",
        rec.slideStart ~= nil and rec.landedAt ~= nil and rec.slideStart >= rec.landedAt)
  check(("2274 current does not spin (%d slide frames)"):format(rec.slideFrames),
        rec.slideFrames > 0 and rec.slideSpin == 0)
  local early, late = 0, 0
  for _, m in ipairs(rec.music) do
    if m.surfing then
      if rec.landedAbs and m.t >= rec.landedAbs then late = late + 1 else early = early + 1 end
    end
  end
  check("2274 no surf music before the landing", early == 0)
  check("2274 surf music after the landing", late > 0)

  if rec.holdAt and rec.dropStart and rec.landedAt and rec.slideStart then
    fall({
      { at = rec.holdAt + 25, name = "2274_01_hold_no_player.png" },
      { at = rec.dropStart + math.floor((rec.dropEnd - rec.dropStart) / 2),
        name = "2274_02_drop_walking_down.png" },
      { at = rec.landedAt, name = "2274_03_landed_surf_sprite.png" },
      { at = rec.slideStart + 20, name = "2274_04_current_no_spin.png" },
    })
  else
    check("2274 frame marks for the shooting pass", false)
  end

  Music.playMap = realPlayMap
  love.event.quit(failures == 0 and 0 or 1)
  while true do coroutine.yield() end
end

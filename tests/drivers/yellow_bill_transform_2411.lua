-- engine/events/hidden_events/bills_house_pc.asm:14-63, scripts/BillsHouse.asm:144-183,
-- data/pikachu/pikachu_emotions.asm:185, audio/pikachu_pcm.asm:15
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")
  local Music = require("src.core.Music")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots2411"
  local failures = 0
  local function check(label, ok, detail)
    U.log((ok and "PASS " or "FAIL ") .. label .. (detail and ("  " .. detail) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    U.log(failures == 0 and "DONE all checks passed"
                        or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local yellow = GameVersion.isYellow()
  local MAP = "BILLS_HOUSE"

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  local flags = game.save.flags
  flags.EVENT_GOT_STARTER = true
  flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  flags.EVENT_MET_BILL, flags.EVENT_MET_BILL_2 = nil, nil
  flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
  flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
  game.save.pikachuMapScriptActive = nil

  local ow
  local function objectAt(name)
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
  end
  local function follower()
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
  end

  do
    local wx, wy
    for _, w in ipairs(game.data.maps.ROUTE_25.warps or {}) do
      if w.destMap == MAP then wx, wy = w.x, w.y end
    end
    if not check("Route 25 has Bill's front door", wx ~= nil) then finish() end
    U.teleport(game, "ROUTE_25", wx, wy + 1, "up")
    U.wait(20)
    for _ = 1, 300 do
      ow = game.overworld
      if ow and ow.map and ow.map.id == MAP then break end
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
      coroutine.yield()
    end
    game.input.state.up = false
    for _ = 1, 240 do
      ow = game.overworld
      if ow and ow.map and ow.map.id == MAP and not ow.transitioning then break end
      coroutine.yield()
    end
  end
  U.wait(20)
  ow = game.overworld
  if not check("inside Bill's House", ow and ow.map and ow.map.id == MAP) then finish() end
  if yellow then
    check("Pikachu scene armed (following)", ow.pikachuBillsScene == true)
    for _ = 1, 900 do
      if ow.emote and ow.emote.pikaPic then break end
      U.wait(1)
    end
    for _ = 1, 900 do
      if not ow.emote then break end
      U.wait(1)
    end
  end
  U.wait(10)

  local f = 0
  local ev = {}
  local function mark(name)
    if not ev[name] then
      ev[name] = f
      U.log(string.format("t=%4d %s", f, name))
    end
  end
  local watching = {}
  local sfxCount = {}
  local realPlay, realPika, realPlayMap = Sound.play, Sound.playPikaCry, Music.playMap
  Sound.play = function(data, name, ...)
    local src = realPlay(data, name, ...)
    if name == "Switch" or name == "Tink" or name == "Shrink" or name == "Get_Item1" then
      sfxCount[name] = (sfxCount[name] or 0) + 1
      local key = name .. (name == "Tink" and ("#" .. sfxCount[name]) or "")
      mark(key .. " start")
      if src then watching[#watching + 1] = { key = key, src = src } end
    end
    return src
  end
  Sound.playPikaCry = function(data, n, ...)
    local src = realPika(data, n, ...)
    mark("pika cry " .. tostring(n) .. " start")
    if src then watching[#watching + 1] = { key = "pika cry " .. tostring(n), src = src } end
    return src
  end
  Music.playMap = function(...)
    mark("map music restart")
    return realPlayMap(...)
  end
  local function restore()
    Sound.play, Sound.playPikaCry, Music.playMap = realPlay, realPika, realPlayMap
  end

  local exclamation
  for i, b in ipairs(game.data.field and game.data.field.emotionBubbles
                     and game.data.field.emotionBubbles.bubbles or {}) do
    if b.name == "EXCLAMATION_BUBBLE" then exclamation = i end
  end

  local function tick()
    f = f + 1
    U.wait(1)
    for i = #watching, 1, -1 do
      local w = watching[i]
      local ok, playing = pcall(w.src.isPlaying, w.src)
      if not (ok and playing) then
        mark(w.key .. " end")
        table.remove(watching, i)
      end
    end
    if objectAt("BILLSHOUSE_BILL1") then mark("Bill appears") end
    local e = ow.emote
    if e and exclamation and e.bubble == exclamation then mark("Pikachu ! bubble") end
    if e and e.pikaPic and ev["Bill appears"] then mark("pikapic box") end
    local bill = objectAt("BILLSHOUSE_BILL1")
    if bill and bill.moving then mark("Bill starts walking") end
  end

  flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
  flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
  ow:billsHousePC()
  for _ = 1, 400 do
    if ow.runner and ow.runner:isRunning() then break end
    if #(ow.pendingScripts or {}) > 0 then break end
    table.insert(game.input.pressQueue, "a")
    tick()
    game.input.state.a = false
    tick()
  end
  f = 0
  mark("prompt closed")
  local shotBill, shotBubble, shotPic = false, false, false
  for _ = 1, 2400 do
    tick()
    if ev["Bill appears"] and not shotBill then
      shotBill = true
      local before = U.frame()
      U.shot(game, SHOT_DIR .. "/2411_bill_appears.png")
      f = f + (U.frame() - before)
    end
    if ev["Pikachu ! bubble"] and not shotBubble then
      shotBubble = true
      local before = U.frame()
      U.shot(game, SHOT_DIR .. "/2411_pikachu_exclamation.png")
      f = f + (U.frame() - before)
    end
    if ev["pikapic box"] and not shotPic then
      shotPic = true
      local before = U.frame()
      U.shot(game, SHOT_DIR .. "/2411_pikapic_after_cry.png")
      f = f + (U.frame() - before)
    end
    if ev["Bill starts walking"] then break end
  end
  restore()

  local function gap(a, b) return ev[a] and ev[b] and (ev[b] - ev[a]) end
  local function within(label, a, b, want, tol, cart)
    local g = gap(a, b)
    check(label, g ~= nil and math.abs(g - want) <= tol,
          string.format("got=%s want=%d+-%d cart=%s", tostring(g), want, tol, cart))
  end
  local function after(label, a, b, cart)
    local g = gap(a, b)
    check(label, g ~= nil and g >= 0, string.format("gap=%s cart=%s", tostring(g), cart))
  end

  within("Tink #1 starts 92 frames after Switch ends", "Switch end", "Tink#1 start", 92, 10, "1.82s")
  within("Shrink starts 80 frames after Tink #1 ends", "Tink#1 end", "Shrink start", 80, 10, "1.40s")
  within("Tink #2 starts 48 frames after Shrink ends", "Shrink end", "Tink#2 start", 48, 10, "0.99s")
  within("Get_Item1 starts 32 frames after Tink #2 ends", "Tink#2 end", "Get_Item1 start", 32, 10, "0.60s")
  within("map music restarts when Get_Item1 ends", "Get_Item1 end", "map music restart", 0, 4, "0.22s")
  after("Bill appears only after Get_Item1 ends", "Get_Item1 end", "Bill appears", "+0.25s")
  within("Bill appears with the music restart", "map music restart", "Bill appears", 0, 2, "0.03s")
  if yellow then
    within("Pikachu ! ~20 frames after Bill appears", "Bill appears", "Pikachu ! bubble", 20, 3, "0.33s")
    within("PikachuCry9 after the 60-frame bubble", "Pikachu ! bubble", "pika cry 9 start", 60, 3, "~0.97s")
    after("pikapic box only after the cry ends", "pika cry 9 end", "pikapic box", "13.6 -> 13.7")
    after("Bill walks only after the box closes", "pikapic box", "Bill starts walking", "after box")
  else
    within("Bill walks 8 frames after appearing", "Bill appears", "Bill starts walking", 8, 2, "BillsHouse.asm:81")
  end
  finish()
end

local U = require("tests.drivers.util")

local M = {}

M.CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
M.TRADE_CENTER = "FR_TRADE_CENTER"
M.COLOSSEUM = "FR_BATTLE_COLOSSEUM_2P"
-- pokefirered/include/constants/flags.h:1375
M.FLAG_SYS_POKEDEX_GET = 0x829

local function now() return love.timer.getTime() end
M.now = now

function M.new(game, tag, dir)
  local W = { game = game, tag = tag, dir = dir, failures = 0, partners = {} }

  function W.result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then W.failures = W.failures + 1 end
    return ok
  end

  function W.finish()
    local Link = package.loaded["src.core.game3.link"]
    if Link then pcall(Link.reset) end
    for _, P in ipairs(W.partners) do
      if P.C then pcall(P.C.disconnect) end
    end
    local Connect = package.loaded["src.online.Connect"]
    if Connect and Connect.disconnect then pcall(Connect.disconnect) end
    local Client = package.loaded["src.online.Client"]
    if Client then pcall(Client.disconnect) end
    if W.failures == 0 then
      print("PASS " .. tag)
      love.event.quit(0)
    else
      print("FAIL " .. tag .. " failures=" .. W.failures)
      love.event.quit(1)
    end
  end

  function W.boot()
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "RED" })
    U.wait(240)
    W.Runtime = require("src.core.game3.runtime")
    W.Map = require("src.core.game3.map")
    W.Space = require("src.core.game3.scripting.space")
    W.Flags = require("src.core.game3.scripting.flags")
    W.Player = require("src.core.game3.player")
    W.Message = require("src.ui.game3.message")
    W.Choice = require("src.ui.game3.choice")
    W.SaveMenu = require("src.ui.game3.save_menu")
    W.Party = require("src.core.game3.party")
    W.RomText = require("src.core.game3.rom_text")
    W.Link = require("src.core.game3.link")
    W.Strings = require("src.core.Strings")
    W.Client = require("src.online.Client")
    W.Direct = require("src.ui.game3.link_menu").Direct
    W.PinEntry = require("src.ui.game3.pin_entry")
    W.session = W.Runtime.getSession()
    return W.session ~= nil
  end

  function W.ctx() return W.Space.vm and W.Space.vm.ctx end

  function W.place(x, y, facing)
    local P = W.Player
    P.cellX, P.cellY = x, y
    P.px, P.py = x * 16, y * 16
    P.targetX, P.targetY = x, y
    P.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end

  function W.pump()
    if W.relay then W.relay:pump() end
    for _, P in ipairs(W.partners) do
      if P.C then P.C.update(1 / 60) end
    end
  end

  function W.wait(n)
    for _ = 1, n do
      W.pump()
      U.wait(1)
    end
  end

  function W.waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      W.pump()
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end

  function W.tap(btn, settle)
    U.tap(game, btn)
    W.wait(settle or 4)
  end

  function W.pageHas(text)
    local page = W.Message.isOpen() and W.Message.currentPage() or ""
    local flat = function(s) return (tostring(s):gsub("%s+", " ")) end
    return flat(page):find(flat(text), 1, true) ~= nil
  end

  local function messageNeedsA()
    local M = W.Message
    if not (M.isOpen() and M.isWaiting()) then return false end
    local lastPage = (M._page or 1) >= #(M._pages or {})
    return not (M._stay and lastPage)
  end

  function W.drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if W.Direct.isOpen() or W.PinEntry.isOpen() then
        W.wait(2)
      elseif W.Choice.active or W.SaveMenu.isOpen() or messageNeedsA() then
        U.tap(game, "a")
        W.wait(6)
      else
        W.wait(2)
      end
    end
    W.wait(2)
    return cond()
  end

  function W.live()
    return W.Link.liveProfile()
  end

  function W.withRuleset(rulesetId)
    local p = {}
    for k, v in pairs(W.live()) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end

  function W.relayAddr()
    return os.getenv("POKEPORT_RELAY_ADDR")
  end

  function W.useRelay()
    local addr = W.relayAddr()
    if addr and addr ~= "" then
      W.mode = "real"
      W.Client.configure({ relayAddress = addr })
      return
    end
    W.mode = "fake"
    local Relay = require("tests.support.fake_relay")
    W.relay = Relay.new({ clock = function() return now() end })
    W.me = W.relay:seat("a0000001", "RED")
    W.Client.configure({ relayAddress = "fake:1", connect = function() return W.me.transport end })
  end

  function W.partner(id, name, avatar)
    local P = { id = id, name = name, avatar = avatar, seq = 0 }
    if W.mode == "fake" then
      local s = W.relay:seat(id, name)
      P.s = s
      W.relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { W.withRuleset("g3_link") },
        presence = { where = "launcher", status = "idle", version = avatar.version } })
      function P.queue(opts)
        local msg = { type = "direct_queue" }
        for k, v in pairs(opts) do msg[k] = v end
        W.relay:handle(s, msg)
      end
      function P.send(msg)
        P.seq = P.seq + 1
        W.relay:handle(s, { type = "room_msg", seq = P.seq, clientSeq = P.seq, msg = msg })
      end
      function P.online() return true end
      function P.room()
        local rid = s.room
        return rid and W.relay.rooms[rid] or nil
      end
      function P.seat()
        local room = P.room()
        return room and W.relay:seatOf(room, id) or nil
      end
    else
      local shared = package.loaded["src.online.Client"]
      package.loaded["src.online.Client"] = nil
      local C = require("src.online.Client")
      package.loaded["src.online.Client"] = shared
      C.reset()
      C.configure({ relayAddress = W.relayAddr() })
      C.connect({ name = name, profiles = { W.withRuleset("g3_link"), W.withRuleset("g3_single") },
        presence = { where = "launcher", status = "idle", version = avatar.version } })
      P.C = C
      W.partners[#W.partners + 1] = P
      local Json = require("src.link.Json")
      C.on("room", function(r)
        if type(r) ~= "table" then return end
        local names = {}
        for _, p in ipairs(r.players or {}) do names[#names + 1] = tostring(p.name) .. "@" .. tostring(p.seat) end
        print("[driver] " .. name .. " room " .. tostring(r.room) .. " stage=" .. tostring(r.stage)
          .. " players=" .. table.concat(names, ","))
      end)
      C.on("error", function(e) print("[driver] " .. name .. " error " .. Json.encode(e or {})) end)
      function P.queue(opts) C.queueDirect(opts) end
      function P.send(msg)
        local rs = C.roomSession()
        if rs then rs:send(msg) end
      end
      function P.online() return C.state() == "online" end
      function P.room() return C.room() end
      function P.seat() return C.seat() end
    end
    return P
  end

  function W.sendHello(P, seat)
    local lk = W.Link.link
    local hello = {}
    for k, v in pairs(lk.myHello) do hello[k] = v end
    hello.name = P.name
    hello.game3 = { cacheVersion = lk.myHello.game3.cacheVersion,
      nativeVersion = lk.myHello.game3.nativeVersion, linkType = lk.linkType,
      trainerId = P.avatar.trainerId, gender = P.avatar.gender, seat = seat }
    P.send(hello)
  end

  function W.shot(name)
    return U.still(game, W.dir .. "/" .. name .. ".png")
  end

  function W.frame(name)
    return U.shot(game, W.dir .. "/" .. name .. ".png")
  end

  return W
end

return M

-- Unit coverage for event:discord.join_requested (DiscordPresence Ask-to-Join).
-- Mods subscribe through Runtime; the engine emits before it hands the invite
-- token to the launcher.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local DiscordPresence = require("src.core.DiscordPresence")

local joined = {}
local savedClient = package.loaded["src.online.Client"]
package.loaded["src.online.Client"] = {
  joinRoom = function(code, as)
    joined[#joined + 1] = { code = code, as = as }
  end,
}

local function freshGame(withLauncher)
  local items = {}
  local game = {
    returned = nil,
    stack = {
      items = items,
      top = function(self) return self.items[#self.items] end,
      push = function(self, screen) self.items[#self.items + 1] = screen end,
    },
  }
  if withLauncher ~= false then
    game.returnToLauncher = function(opts) game.returned = opts end
  end
  return game
end

local bus = Events.new()
local savedEvents, savedHooks = Runtime.events, Runtime.hooks
Runtime.events = bus

local function listen()
  local seen = {}
  bus:on("discord.join_requested", function(ev)
    seen[#seen + 1] = ev
  end, 0, "discord_join_test")
  return seen
end

local TOKEN = ("0123456789abcdef"):rep(2)
do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()
  joined = {}
  DiscordPresence.handleJoinRequest("i:" .. TOKEN)
  T.eq(#seen, 1, "an invite join emits discord.join_requested")
  T.eq(seen[1].invite, TOKEN, "payload carries the invite token")
  T.eq(seen[1].kind, "i", "payload carries kind tag i")
  T.eq(game.returned and game.returned.tab, "online",
    "a running game returns to the launcher's online tab")
  T.eq(game.returned and game.returned.invite, TOKEN,
    "the launcher is handed the token")
  T.eq(#joined, 0, "the launcher joins, not DiscordPresence")
  T.eq(game.stack:top(), nil, "no in-game link screen is pushed any more")
  bus:removeOwner("discord_join_test")
end

do
  local st = DiscordPresence._state
  st.game = nil
  st.activity = "menu"
  local seen = listen()
  local handed
  DiscordPresence.joinHandler = function(token) handed = token end
  DiscordPresence.handleJoinRequest(TOKEN)
  T.eq(#seen, 1, "a bare token still emits discord.join_requested")
  T.eq(handed, TOKEN, "the launcher's join handler takes it")
  DiscordPresence.joinHandler = nil
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()
  DiscordPresence.handleJoinRequest("m:HOST01")
  T.eq(#seen, 1, "an old room-code secret still emits the event")
  T.eq(seen[1].code, "HOST01", "with the code for mods")
  T.eq(game.returned, nil, "but nothing joins a room code any more")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame(false) -- a build with no returnToLauncher
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()

  joined = {}
  DiscordPresence.handleJoinRequest("m:NOWAY")
  T.eq(#seen, 1, "the event still fires so a mod can act on it")
  T.eq(#joined, 0, "a game that cannot reach the launcher joins nothing")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "battle"
  local seen = listen()

  joined = {}
  DiscordPresence.handleJoinRequest("m:NOPE")
  T.eq(#seen, 0, "battle activity suppresses join dispatch")
  T.eq(#joined, 0, "battle activity joins no room")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  game.stack:push({ stage = true, net = {} }) -- already in a link session
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()

  joined = {}
  DiscordPresence.handleJoinRequest("m:NOPE")
  T.eq(#seen, 0, "active link session suppresses join dispatch")
  T.eq(#joined, 0, "active link session joins no room")
  T.eq(#game.stack.items, 1, "active link session is not replaced")
  bus:removeOwner("discord_join_test")
end

DiscordPresence._state.game = nil
DiscordPresence._state.activity = "menu"
Runtime.events, Runtime.hooks = savedEvents, savedHooks
package.loaded["src.online.Client"] = savedClient

T.finish("discord_join_requested")

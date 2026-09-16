-- Items on the link cable (RFC 0021).
--
-- Cable rules say no items, and LinkBattle keeps that default.  A mode
-- that opts in (`opts.items = true` on newHost/newGuest) gets the bag
-- back, and this is the one place that says what an item does to the
-- OTHER machine: the user's own bag already applied the effect to the
-- user's lockstep copies before the turn went on the wire, so the peer
-- (and any spectator) applies the same effect to its own copies of that
-- side, through the same ItemEffects.use, before the turn's moves.
--
-- Two facades make that reuse possible without a second dispatcher.
-- ItemEffects reads the user as `battle.player` and the user's bench as
-- `save.party`; from the peer's chair the user is `battle.enemy` and the
-- bench is `theirParty`, so the call sees a battle whose player is the
-- peer's battler and a save whose party is the peer's copies.  Nothing
-- is consumed here -- the bag that was spent is the user's, on the
-- user's machine -- and every effect reachable in a battle is
-- deterministic (no roll in ItemEffects), so both simulations arrive at
-- the same state and the per-turn hash agrees.

local ItemEffects = require("src.inventory.ItemEffects")
local Logger = require("src.core.Logger")

local LinkItems = {}

-- The wire message for an item the local player just used: the item id,
-- the slot of the mon it was used on (nil for an item with no target --
-- an X item, the flute), and the move it picked (the ETHERs).
function LinkItems.wire(itemId, party, target, moveIndex)
  local index
  if target then
    for i, mon in ipairs(party or {}) do
      if mon == target then index = i end
    end
  end
  return { type = "action", kind = "item", item = itemId, index = index,
           move = moveIndex }
end

-- Apply a wire item to one side of the battle `s` as that side's owner
-- would have.  `side` = { battler, party, opponent, opponentParty, name }:
-- the user's active battler and bench (our copies), the other side's, and
-- the user's name for the "X used POTION!" line.  Returns the lines to
-- print, in order: the used line, the effect line, and anything the
-- effect prints after (the X item's "rose!").
function LinkItems.apply(s, msg, side)
  local itemId = msg and msg.item
  if type(itemId) ~= "string" or not side then return {} end
  local party = side.party or {}
  local target
  local index = tonumber(msg.index)
  if index then target = party[math.floor(index)] end
  local move = tonumber(msg.move)
  if move then move = math.floor(move) end

  -- the user's chair: their battler is "the player", their bench "the party"
  local battleView = setmetatable({
    player = side.battler,
    enemy = side.opponent,
    playerParty = party,
    enemyParty = side.opponentParty,
  }, { __index = s })
  local save = s.game and s.game.save or {}
  local saveView = setmetatable({
    party = party,
    inventory = {},
    player = setmetatable({ name = side.name or "FOE" },
                          { __index = save.player or {} }),
  }, { __index = save })

  local ok, result, payload, extra = pcall(ItemEffects.use, s.data, saveView,
                                           itemId, target, battleView, move)
  if not ok then
    Logger.warn("link: could not apply the peer's %s: %s", tostring(itemId),
                tostring(result))
    return {}
  end
  local lines = {}
  -- the user's own screen printed "RED used POTION!" from the bag (or not
  -- at all: the medicines print only their effect); the other side has no
  -- bag to have read it from, so the used line leads unless the effect
  -- already printed one (the X items and the flute do)
  local first = type(payload) == "table" and payload[1] and tostring(payload[1]) or ""
  if result ~= "failed" and not first:find("used", 1, true) then
    local def = s.data and s.data.items and s.data.items[itemId]
    lines[#lines + 1] = ItemEffects.itemUseLine(s.data, saveView,
                                                (def and def.name) or itemId)
  end
  if type(payload) == "table" then
    for _, line in ipairs(payload) do lines[#lines + 1] = line end
  end
  if type(extra) == "table" and type(extra.afterMessages) == "table" then
    for _, line in ipairs(extra.afterMessages) do lines[#lines + 1] = line end
  end
  -- a cure clears mon.status before any text; the HUD follows at once,
  -- as it does for the user (BattleState:itemUsed).  HP is left to the
  -- bar, which drains toward mon.hp on its own -- the peer sees the heal
  -- fill the way the user saw it fill in their party menu.
  if s.syncShownStatus then s:syncShownStatus() end
  return lines, result
end

return LinkItems

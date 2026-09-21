-- #2364: a hidden item came back after the start menu was opened and closed.
--
-- Reporter steps (FireRed, Viridian Forest): pick up the hidden Antidote,
-- open the start menu, close it, walk back -- the Antidote is collectable
-- again, for as many times as you like.
--
-- Cause: hidden-item flags are ordinary save flags, and the engine keeps
-- exactly one authoritative table for those -- Space.store, built by
-- Space.activate -> load_sidecar.  Every gameplay script reads and writes
-- that store; session.flags is only the serialization mirror of it.
-- field.lua's hidden-item lookup, pickup and Itemfinder all resolved their
-- store with `session and (session.store or session)`, and an FRLG session
-- has no `.store` field (save_schema_firered.lua persists flags/vars only),
-- so they silently fell through to session.flags and never touched
-- Space.store.
--
-- The bug stayed invisible until something re-synced the mirror: opening the
-- start menu runs Hud.openStartMenu -> Space.persistSession ->
-- persist_sidecar, whose `session.flags = Flags.serialize(Space.store).flags`
-- overwrote session.flags with the stale store snapshot and erased the flag.
--
-- So these checks drive the real field.lua/space.lua and pin the contract the
-- fix restores: the pickup flag lands in Space.store, and the persist that
-- the menu performs puts it *back* into session.flags instead of dropping it.
--
--   luajit tests/engine/game3_hidden_item_respawn_bug2364.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit") -- installs the love stub as global `love`

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Bag = require("src.core.game3.bag")
local Field = require("src.core.game3.field")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")

-- pret/pokefirered: Viridian Forest's hidden ANTIDOTE (item 14) sits at
-- (12,20); BgEvents carry hiddenItemId 1, so its flag is
-- FLAG_HIDDEN_ITEMS_START (0x3E8) + 1.
local MAP_ID = "MAP_VIRIDIAN_FOREST"
local ITEM_X, ITEM_Y = 12, 20
local ITEM_FLAG = 0x3E9

local function freshGame()
  return {
    data = {
      maps = {
        [MAP_ID] = {
          bgEvents = {
            { type = "hidden_item", kind = 7, x = ITEM_X, y = ITEM_Y, elevation = 0,
              item = 14, quantity = 1, hiddenItemId = 1, flag = ITEM_FLAG },
          },
        },
      },
    },
  }
end

-- FRLG session shape: flags/vars, no `.store` -- that absence is the bug.
local function freshSession()
  return {
    name = "RED", map = MAP_ID, flags = {}, vars = {},
    bag = Bag.new(), playerX = ITEM_X, playerY = ITEM_Y - 1,
  }
end

-- What Space.activate -> load_sidecar builds on map entry.
local function activateStore(game, session)
  Space.store = Flags.newStore()
  Flags.loadInto(Space.store, { flags = session.flags, vars = session.vars })
end

-- Reopening the map: a brand new store, re-seeded from the session mirror.
local function reenterMap(game, session)
  activateStore(game, session)
end

local function setUp(game, session)
  Field._session = session
  Field._game = game
  game.session = session
  -- Space.resolve_session checks Runtime.getSession() then resolve_game(mod)
  Space._mod = { game = game }
  Space.active = true
  activateStore(game, session)
end

-- ---------------------------------------------------------------- pickup
do
  local game, session = freshGame(), freshSession()
  setUp(game, session)

  local hidden = Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0)
  T.check(hidden ~= nil, "the hidden Antidote is present before pickup")
  T.check(Field.pickUpHiddenItem(game, hidden) == true, "picking it up reports success")

  T.check(Flags.getFlag(Space.store, nil, ITEM_FLAG) == true,
    "the pickup flag is written to the authoritative Space.store")
  T.check(Flags.getFlag(session, nil, ITEM_FLAG) == true,
    "the pickup flag is mirrored into session.flags")
end

-- ------------------------------- the reported bug: open/close start menu
do
  local game, session = freshGame(), freshSession()
  setUp(game, session)

  Field.pickUpHiddenItem(game, Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0))

  -- Hud.openStartMenu calls exactly this (src/ui/game3/hud.lua); the menu
  -- itself needs a live graphics context, so the suite drives the function
  -- it delegates to. The save menu and src/runtime.lua persist the same way.
  Space.persistSession()

  T.check(Flags.getFlag(session, nil, ITEM_FLAG) == true,
    "the flag survives the start-menu persist (this is the regression)")
  T.check(Flags.getFlag(Space.store, nil, ITEM_FLAG) == true,
    "the flag survives in Space.store too")

  T.check(Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0) == nil,
    "the hidden Antidote does not reappear after opening and closing the menu")
  T.check(Field.pickUpHiddenItem(game, { flag = ITEM_FLAG, item = 14, quantity = 1 }) == false,
    "a second pickup attempt is refused")

  local found, kind, _, data = Field.useItemfinder(session, false)
  T.check(found == false and data == nil,
    "the ITEMFINDER reports nothing buried there (kind " .. tostring(kind) .. ")")

  -- And after leaving and re-entering the map, which rebuilds the store from
  -- the session mirror.
  reenterMap(game, session)
  T.check(Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0) == nil,
    "still collected after re-entering the map")
end

-- --------------------------------------------- no over-correction elsewhere
do
  local game, session = freshGame(), freshSession()
  setUp(game, session)

  -- A different hidden item on the same map must be unaffected.
  game.data.maps[MAP_ID].bgEvents[#game.data.maps[MAP_ID].bgEvents + 1] = {
    type = "hidden_item", kind = 7, x = 3, y = 4, elevation = 0,
    item = 14, quantity = 1, hiddenItemId = 2, flag = 0x3EA,
  }

  Field.pickUpHiddenItem(game, Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0))
  Space.persistSession()

  T.check(Field.hiddenItemAt(game, 3, 4, 0) ~= nil,
    "an unpicked hidden item on the same map is still collectable")
  T.check(Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0) == nil,
    "the picked one stays gone")
end

-- ---------------------------------- headless callers keep the old fallback
do
  -- Some callers (and the pre-existing #2314 suite) wire Field._session with
  -- no active Space store at all; flag_store must still resolve to the
  -- session table so those keep working.
  local savedStore = Space.store
  Space.store = nil

  local game, session = freshGame(), freshSession()
  Field._session = session
  Field._game = game
  game.session = session

  local hidden = Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0)
  T.check(hidden ~= nil, "no active Space store: the item is still found")
  T.check(Field.pickUpHiddenItem(game, hidden) == true, "no active Space store: pickup succeeds")
  T.check(Flags.getFlag(session, nil, ITEM_FLAG) == true,
    "no active Space store: the flag lands on the session fallback")
  T.check(Field.hiddenItemAt(game, ITEM_X, ITEM_Y, 0) == nil,
    "no active Space store: the item is collected")

  Space.store = savedStore
end

Field._session, Field._game, Field._mod = nil, nil, nil
Space._mod, Space.active = nil, false
Space.store = nil

T.finish("game3_hidden_item_respawn_bug2364")

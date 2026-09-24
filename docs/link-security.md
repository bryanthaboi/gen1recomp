# Link play: threat model and what the code actually guarantees

Link play is the only part of this game that reads bytes written by
somebody else. This is what it defends against, what it does not, and
where each guarantee lives.

## Where link play lives now

Two separate things, one wire stack:

- **In-game link is LAN only.** `src/link/LinkState.lua` is the START menu /
  Cable Club path over ENet on the local network. It has no relay, no room
  codes and no bracket: the in-game ONLINE and TOURNAMENT rows are gone and
  `src/link/Tournament.lua` no longer exists.
- **Online play lives in the launcher**, over relay protocol v2 against
  `../pokeserver`. `src/online/Client.lua` holds one persistent TCP
  connection for the life of the process (`main.lua` pumps it every frame,
  whether the launcher or a booted game is on screen). Presence, rooms,
  spectators and tournaments are objects addressed inside that one
  connection. A tournament is a room of rooms: the relay creates each
  bracket match as an ordinary v2 room and attaches every non-playing
  entrant to it as a spectator.
- A battle never runs in the launcher. The launcher **arena boots** the
  game (`src/online/ArenaBoot.lua` -> `Game:load` / `Game2:load` ->
  `src/ui/ArenaState.lua` or `src/ui/gen2/ArenaState.lua`), which skips
  splash, title and overworld, runs `LinkBattle` / `LinkBattle2` on the room
  session, and returns to the launcher with the room still selected.

## The arena profile

The compatibility contract is one table, computed in the launcher without
booting a game (`src/online/ArenaData.lua`), attached to every lobby entry
and room, and checked twice:

| Field | What it pins |
| --- | --- |
| `engine` | 1 or 2: which battle engine the room runs |
| `version` | which generated cache boots (`red` ... `crystal`) |
| `engineVersion`, `apiVersion` | exact string match, no skew |
| `fingerprint` | `Fingerprint.compute` over the *arena* dataset |
| `rulesetId` | the host-dealt rulebook (see below) |
| `kind` | `vanilla` (all mods off) or `cart` (a sealed cart) |
| `cart` | `{ id, version, hash }`, the `CartManifest.hash` of that cart |
| `rule` | party size and level bounds, not part of the identity |

**The relay enforces it on join.** `room_join` walks
`PROFILE_MATCH_FIELDS` (`../pokeserver/relay.js:66`) in order -- `engine`,
`version`, `engineVersion`, `fingerprint`, `rulesetId`, `kind`, `cart.hash`
-- and refuses the first field that differs with
`join_error { reason: "profile_mismatch", field, detail }`. `room_ready` runs
the party against `rule` the same way and answers `party_ineligible`.
Spectators are held to the profile too: a spectator runs the same engine to
render the battle.

**The client checks it before it will join or boot.** The ONLINE tab runs
`ArenaData.equal` (everything except `rule`) against its own profile for
every lobby row and greys out the ones it cannot play, with
`ArenaData.describeMismatch` naming the first differing field so the reason
is *what* differs rather than "incompatible"
(`src/import/OnlinePanel.lua`). The battle it then boots is constructed
with `strict = true` (`ArenaBoot.battleOpts`), so a mon that cannot be
rebuilt from real species data refuses the battle instead of being
approximated into a desync.

A `vanilla` arena boots the mod loader in `disableAll` mode and a `cart`
arena in `cartOnly` (`Loader.ARENA_MODES`, `src/mods/Loader.lua:618`).
Neither reads or writes `options.safeMode` or `options.modsByVersion`, so an
arena never disturbs the player's own enable state. `disableAll` keeps
verified translations and only those: `_arenaDisableAll` keeps a mod that
declares `language = true`, `affects_link = false` and no permissions, and
`_arenaVerifyTranslations` then re-checks the survivors through
`Handshake.onlineBlockers` and rolls back anything that does not qualify.
`cartOnly` refuses to boot when the cart plan is not `enforced` or the
slot's seal is broken; `sealed+` and `open` carts are refused outright,
because a player-togglable pin set is not a fixed identity.

## Desync: the ruleset and the RNG counter

Nearly every reported desync was turn 1 or 2 with **identical engine
versions on both sides**. The cause was local: `BattleState` picked its
ruleset from `game.save.options.ruleset`, an ordinary OPTIONS row, and
`gen1_faithful` spends one RNG draw on the 1/256 miss that `modern_clean`
does not. Both machines share one Park-Miller stream, so a single skipped
draw offsets it permanently and the very next number is the damage factor.

The fix is three parts, all of them in the wire:

- The **host deals the ruleset**. `LinkBattle` takes `opts.ruleset` and
  overwrites `self.ruleset` from it the way it already overwrote `rng`
  (`src/link/LinkBattle.lua:275`, spectator at `:824`). In an arena that id
  comes from the profile.
- The hello **carries** it (`Handshake.ruleset`, `src/link/Handshake.lua:180`)
  and `checkCompat` refuses a mismatch as `ruleset_skew`, so a LAN pairing
  cannot start split either.
- The rulesets registry is part of the **Gen 1 fingerprint surface**
  (`src/link/Fingerprint.lua:319`), so a retuned rulebook is caught even when
  both sides name the same id.

The other half of the diagnosis was that the state signature could not see a
draw-count split, so a desync was blamed on the wrong turn. The RNG draw
counter is now hashed into the `actives` component
(`src/link/LinkBattle.lua:196`; Gen 2 stamps it on the battle at
`src/link/LinkBattle2.lua:256` and hashes it in
`src/battle/gen2/Battle.lua:5173`), so the two sides disagree on the exact
turn the streams part.

## The boundary

Everything a peer or the relay sends arrives as one JSON object per line.
There is exactly one place it becomes a message:

    src/link/Net.lua        reads bytes, frames lines, decodes JSON
    src/link/Wire.lua       rebuilds each line as a typed message
    src/link/Session.lua    the only path from a transport into a mode

`Session:update` runs `Wire.sanitize` on every message before anything
else sees it. A schema returns a **new** table holding only the fields it
names, at the Lua types it names, so the rest of `src/link/` can read
`msg.slot`, `msg.parts.actives` or `msg.mons[i].dvs.hp` directly and be
right by construction. A message with no schema (a mod's, or a future
build's) keeps a bounded, scalar-only copy of its payload instead of
being dropped.

The v2 types go through the same door: `SCHEMAS.lobby_*`, `room_*` and
`tour_*` live beside the link ones in `Wire.lua`, and `room_msg` sanitizes its
inner lockstep message as well as its envelope, so `Client.roomSession()`
hands `LinkBattle` the same shape a LAN `Session` does.

A message that fails its schema is **dropped and logged**, never fatal.
Latching a terminal failure would hand a hostile peer a cheaper
disconnect than sending nothing at all.

### Why the bounds are loose

Wire's numeric bounds are deliberately wider than the game's own clamps in
`Protocol.unpackMon`. Both peers run identical clamps over identical
packets; a bound that bit an honest value would change one side's copy of
a mon and desync the lockstep. Wire's job is types and sizes. Rules are
`Protocol`'s job, and it keeps its own clamps for the callers that reach
it without a Session (the mod API, `tests/`).

### Containment behind it

Assume something still gets through:

- `Game:step` pcalls the link pump, and xpcalls `stack:update` **only
  while a link session is active** (`src/core/Game.lua:329`). A throw
  reaches `Game:breakLink` (`:276`), which closes the connection, unwinds
  to the overworld and says so. Transport failure and a caught Lua error are
  distinguished on purpose: the player is told "The link was broken." for
  one and "Something broke during the link." for the other, and the log
  line differs, so an engine bug inside a link battle no longer reads as a
  network fault. Outside link play the stack is unguarded on purpose: a
  blanket pcall would swallow real engine bugs and leave the game silently
  wrong instead of loudly broken.
- `Net` caps a line at 256KB (`Net.MAX_LINE`) and its per-frame read at
  512KB (`Net.MAX_RX_PER_FRAME`), so a peer that never sends a newline ends
  as a clean disconnect.
- `Json.decode` refuses documents nested past 64 levels (`Json.MAX_DEPTH`),
  and takes an optional length cap that the link path passes and the
  mod-manifest path does not.

## The relay (`../pokeserver`)

- A line that is not a JSON **object** with a string `type` is dropped
  before any handler runs, and `onLine` is wrapped in try/catch.
  `server.js` installs `uncaughtException`/`unhandledRejection` handlers:
  one bad packet must never take every live match down with the process.
- Line buffers are capped, lines per second are capped, connections per
  IP and in total are capped, and an unbound connection that never hosts,
  joins or binds as a lobby is swept after 30s.
- `SERVER_ONLY` (`relay.js:168`) is the set of message types the server is
  the only legitimate author of. It covers every v2 one (`lobby_welcome`,
  `lobby_list`, `lobby_delta`, `room_state`, `room_replay`,
  `room_deadline`, `room_result`, `room_closed`, `tour_state`,
  `tour_match`, `tour_match_spectate`, `tour_bye`, `tour_deadline`,
  `tour_over`, `tour_closed`, `trade_commit`, `trade_abort`, the invite,
  plaza and group ones, ...). A peer that sends one has it dropped rather
  than forwarded, so a bracket opponent cannot forge a result or fake "your
  opponent left".
- `room_msg` only carries an inner `msg.type` from the engine's allowlist
  (engine 1/2: `hello`, `party`, `action`, `hash`, `replace`, `bye`,
  `forfeit`, `records`, `pick`, `confirm`, `trade_confirm`; engine 3: the
  `game3_*` set, each with a byte cap), only from a seated player, and only
  while the room is `battling`. Its `seq` must rise, so a resumed client's
  replayed tail is idempotent.
- Names, notes, room ids and profile strings are reduced to a printable
  subset and capped on the way in (10 characters for a trainer name, 16 for
  a lobby display name, 40 for an advertisement note), because they are
  rendered by the dashboard and broadcast to every participant.

`pokeserver/test/hostile.js` is the regression net for all of that.

### Identity: tickets

Going online verified takes a ticket, not a credential.
`POST /lobby/ticket` on the HTTPS port (`lobby.js`) authenticates with the
usual sync headers, mints 32 hex characters bound to
`{ account, displayName }`, valid for 60 seconds and **single use**, and the
client presents that on the plaintext relay in `lobby_hello`. The relay
redeems it in process (both modules live in `server.js`) and never sees the
device token: nothing on port 7778 can be replayed into an account. The
ticket store is memory only, so a restart invalidates every outstanding
ticket and clients simply mint another. A client with no ticket still
connects and still plays, as a guest, listed `verified: false`.

### Heartbeat, resume and the replay bound

- `ping`/`pong` runs both ways. The relay pings a connection idle for 20s
  and drops one idle for 60s, on top of TCP keepalive; the client's own
  heartbeat interval arrives in `lobby_welcome`.
- A dropped socket keeps its seat for **2 minutes**. A new connection sends
  `resume { session, ack }` and gets its room, its match and the traffic it
  missed back. `room_replay` also names `yourSeq`, the highest `seq` the
  relay logged from that client, so the client re-sends only its own lost
  tail.
- The room's message log is bounded at **512 messages or 256 KiB**,
  whichever comes first, since the last `room_ready` pair. A spectator that
  arrives while the log is intact gets `room_replay` and then live traffic;
  one that arrives after the bound already dropped messages is refused with
  `spectate_late` rather than being fed a battle it cannot reconstruct.

## What is NOT defended

**Party legality is trust-the-client.** Online rooms, spectating and
tournaments live in the launcher, where play meets strangers, and
`Handshake.onlineAllowed` is a Lua function in the same VM the mods load
into. It cannot be made tamper-proof in-process, and pretending otherwise
would only cost honest mod authors. What lockstep and
`Protocol.unpackMon`'s recompute-from-species-data *do* guarantee is that
a cheater cannot invent stats, moves, or a shiny: every derived value is
rebuilt locally from real species data. The relay checks party size and
level bounds against the room's `rule`, and that is the only rule it
enforces. A player can still send a legal party they farmed or edited.
That is the honest boundary.

**Match results are trust-the-client too**, and this is where the relay
stopped being silent. Both sides report; agreement resolves the match, a
lone report waits out a grace window, a lone forfeit resolves at once, and
a stalled match resolves on its deadline. Two **disagreeing** reports are
counted as a dispute (`totals.disputes` and the room's or tournament's own
counter, both in the dashboard snapshot), logged with both sides' reports
verbatim, and settled **deterministically**, never by coin flip: a forfeit
or a gone player decides it, otherwise the earliest report wins
(`roomTiebreak`, `relay.js:1761`). The outcome carries `how` --
`reported`, `agreed`, `forfeit`, `timeout`, `disputed`, `disconnect` or
`closed` -- so a tournament organizer can see which matches were argued.

The same is true of the arena profile. A patched client can lie about its
fingerprint or its cart hash; what it cannot do is lie without the relay
having a record of it, since the relay sees every profile and compares the
two sides of every room. A sealed cart's hash proves the manifest, the
pins' sha256 prove the archives, and the fingerprint proves the merged
data -- against an honest client.

Client-side attestation is deliberately not built. This is an
open-source Lua game: it would be theater, and it would break honest
mods.

**The relay has no TLS.** Port 7778 is plaintext, so party contents,
trades and trainer names are visible to anyone on the network path. Tickets
keep account credentials off it (above), and there is nothing secret in a
Pokemon party, but it is a real property of the system and not an
oversight. Fixing it means a TLS terminator in front of the relay and a
client that speaks it, which is a version break for every shipped build.

**Presence is not durable.** The lobby, every room and every outstanding
ticket live in the relay process. A restart clears them and clients
reconnect and re-advertise within one heartbeat. Nothing about a match is
persisted, so nothing about a match can be audited after the fact beyond
the log lines.

**The dashboard has no default password.** `DASHBOARD_PASSWORD` is
required; with it unset the relay runs and the dashboard simply does not
start. It is still Basic Auth over plain HTTP, so it belongs behind an
IP restriction or an SSH tunnel (`pokeserver/DEPLOY.md`).

## Tests

    luajit tests/link_hostile.lua      v1 message types x every wrong type
    luajit tests/link_desync_fuzz.lua  fuzz: baseline, mutation, ruleset split
    luajit tests/run_link_tests.lua    the above, plus online_client and link2_*
    cd ../pokeserver && npm test       relay smoke, brackets, lobby, tour

What guards which claim:

- **Ruleset desync**: `run_link_tests.lua` asserts the draw-count difference
  between `gen1_faithful` and `modern_clean` directly, then runs a loopback
  battle where the guest's own `modern_clean` OPTIONS row is overridden by
  the host's dealt ruleset. `link_desync_fuzz.lua`'s ruleset-split mode
  deliberately configures the two sides differently and fails if the two
  `LinkBattle`s ever end up holding different rulebooks.
- **Wire hostility**: `link_hostile.lua` builds a corpus from a template per
  v1 message type, replaces each field (and several nested ones) with every
  wrong Lua type, and drives the survivors through the real trade session, a
  real lockstep battle and a real spectator battle, **including their draws**
  -- because the two nastiest payloads are delayed-fuse ones that crash on
  render rather than on receipt. The v2 envelopes are covered on the client
  side by `tests/online_client.lua`, which sanitizes oversized `lobby_list`,
  `room_replay`, `room_state` and `tour_state` payloads and asserts a stream
  of malformed server messages is counted and dropped without throwing or
  changing connection state.
- **Client, rooms, resume, tournaments**: `tests/online_client.lua` (run from
  `run_link_tests.lua`) covers the handshake, lobby, advertising, rooms,
  `match_start`, the room session, reconnect and resume replay, spectating,
  results, a full tournament run and the lockstep path, against a fake relay
  and, when a socket library is present, a real one.
- **Gen 2 lockstep**: `tests/link2_lockstep.lua` and
  `tests/link2_desync_fuzz.lua`.
- **Relay**: `../pokeserver/test/lobby.js` (bind, presence, rooms,
  spectating, the lockstep stream, deadlines, resume, a real HTTP ticket
  from a real sync account, and a v1 room in the same process),
  `test/tour.js` (a 5-player v2 bracket with byes, child rooms, spectator
  fan-out, the server-side shot clock, disconnects and creator handoff),
  `test/hostile.js`, plus `test/smoke.js`, `test/keepalive.js`,
  `test/tournament16.js` and `test/tournament5.js` for the v1 path.
- **End to end**: the LÖVE drivers. `tests/drivers/online_relay_smoke.lua`
  runs two `Client`s through a real pokeserver over TCP: room create, join,
  ready, a full Gen 1 `LinkBattle` over `roomSession()`, both reports and the
  relay's `room_result`. `tests/drivers/online_tour_smoke.lua` runs five
  clients through a v2 tournament including a bye, an outside spectator, a
  mid-battle socket kill with resume and replay, and a forfeit.
  `tests/drivers/arena_boot_loopback.lua` and
  `arena_boot_gen2_loopback.lua` (with their `*_spec.lua` payloads) boot
  straight into an arena battle, play it against a headless guest and
  screenshot the battle and the launcher it returns to.

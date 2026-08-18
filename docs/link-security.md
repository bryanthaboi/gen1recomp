# Link play: threat model and what the code actually guarantees

Link play is the only part of this game that reads bytes written by
somebody else. This is what it defends against, what it does not, and
where each guarantee lives.

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

- `Game:step` pcalls the link pump, and pcalls `stack:update` **only
  while a link session is active**. On a throw, `Game:breakLink` closes
  the connection, unwinds to the overworld and says "The link was
  broken." Outside link play the stack is unguarded on purpose: a blanket
  pcall would swallow real engine bugs and leave the game silently wrong
  instead of loudly broken.
- `Net` caps `rxBuf` at 256KB and its per-frame read at 512KB, so a peer
  that never sends a newline ends as a clean disconnect.
- `Json.decode` refuses documents nested past 64 levels, and takes an
  optional length cap that the link path passes and the mod-manifest path
  does not.

## The relay (`../pokeserver`)

- A line that is not a JSON **object** with a string `type` is dropped
  before any handler runs, and `onLine` is wrapped in try/catch.
  `server.js` installs `uncaughtException`/`unhandledRejection` handlers:
  one bad packet must never take every live match down with the process.
- Line buffers are capped, lines per second are capped, connections per
  IP and in total are capped, and an unbound connection that never hosts
  or joins is swept after 30s.
- `SERVER_ONLY` is the set of message types the server is the only
  legitimate author of (`peer_gone`, `bracket_update`, `match_start`,
  `tournament_over`, `spectate`, ...). A peer that sends one has them
  dropped rather than forwarded, so a bracket opponent cannot forge a
  tournament result or fake "your opponent left".
- Trainer names are reduced to a printable subset and capped at the same
  10 characters the game enforces, on the way in, because they are
  rendered by the dashboard and broadcast to every participant.

`pokeserver/test/hostile.js` is the regression net for all of that.

## What is NOT defended

**Party legality is trust-the-client.** Online play meets strangers, and
`Handshake.onlineAllowed` is a Lua function in the same VM the mods load
into. It cannot be made tamper-proof in-process, and pretending otherwise
would only cost honest mod authors. What lockstep and
`Protocol.unpackMon`'s recompute-from-species-data *do* guarantee is that
a cheater cannot invent stats, moves, or a shiny: every derived value is
rebuilt locally from real species data. They can send a legal party they
farmed or edited. That is the honest boundary.

What the relay does instead is **observe and record**. It already sees
every `hello`, so it keeps each connection's self-reported
`engineVersion`, `fingerprint` and `linkModified`, compares the two sides
of a room or a live tournament match, and logs and surfaces a
`modded` / `fingerprint_mismatch` / `version_skew` flag on the dashboard.
A patched client can still lie; what it cannot do is lie without the
tournament organizer having a record of it.

Client-side attestation is deliberately not built. This is an
open-source Lua game: it would be theater, and it would break honest
mods.

**The relay has no TLS.** Port 7778 is plaintext, so party contents,
trades and trainer names are visible to anyone on the network path. There
is nothing secret in a Pokemon party, but it is a real property of the
system and not an oversight. Fixing it means a TLS terminator in front of
the relay and a client that speaks it, which is a version break for every
shipped build.

**The dashboard has no default password.** `DASHBOARD_PASSWORD` is
required; with it unset the relay runs and the dashboard simply does not
start. It is still Basic Auth over plain HTTP, so it belongs behind an
IP restriction or an SSH tunnel (`pokeserver/DEPLOY.md`).

## Tests

    luajit tests/link_hostile.lua        every message type x every wrong type
    luajit tests/link_desync_fuzz.lua    lockstep fuzz, plus a mutation mode
    luajit tests/run_link_tests.lua      both of the above, plus the rest
    cd ../pokeserver && npm test         relay smoke, 16-player bracket, hostile

`tests/link_hostile.lua` builds its corpus from a template per message
type, replaces each field (and several nested ones) with every wrong Lua
type, and drives the survivors through the real trade session, a real
lockstep battle, a real spectator battle, and the tournament screen
**including its draw** -- because the two nastiest payloads are
delayed-fuse ones that crash on render rather than on receipt.

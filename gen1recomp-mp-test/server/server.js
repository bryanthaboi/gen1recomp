#!/usr/bin/env node
'use strict';

// gen1recomp multiplayer relay -- a self-hosted replacement for ../pokeserver.
//
// Speaks protocol v2 (src/online/Protocol2.lua) over newline-framed JSON on
// PORT, plus a small HTTP control surface on HTTP_PORT.  No dependencies.
//
// The authoritative contract is the client's own validator table
// (src/online/Protocol2.lua, VALIDATORS): every message this server emits must
// satisfy the matching validator or the client silently drops it.  The
// end-to-end acceptance test is tests/drivers/online_relay_smoke.lua, which
// spawns this file and drives two real clients through a full battle.

const net = require('net');
const http = require('http');
const crypto = require('crypto');

// ---------------------------------------------------------------- config

const PORT = Number(process.env.PORT || 7778);
const HTTP_PORT = Number(process.env.HTTP_PORT || 7779);
const BIND = process.env.BIND || '0.0.0.0';

// POC switch: every seat is renamed to `test_<n>` on arrival, so a tester
// never has to pick (or remember) a name.  Off by default; the container
// turns it on.  Names still come from the client when it is off, and the
// relay only invents one when the client sends none.
const TEST_NAMES = /^(1|true|yes|on)$/i.test(process.env.RELAY_TEST_NAMES || '');

const MAX_LINE = 256 * 1024;
const MAX_RX_PER_SEC = 600;
const MAX_CONNS = 512;
const MAX_CONNS_PER_IP = 32;
const MAX_NAME = 16;          // Wire MAX_DISPLAY_NAME
const MAX_NOTE = 40;          // docs/link-security.md: advertisement note cap
const HEARTBEAT_MS = 10000;
const IDLE_DROP_MS = 60000;
const RESUME_WINDOW_MS = 120000;
const UNBOUND_SWEEP_MS = 30000;
const REPORT_GRACE_MS = 3000;
const MATCH_DEADLINE_MS = 30 * 60 * 1000;
const LOG_MAX_MSGS = 512;
const LOG_MAX_BYTES = 256 * 1024;

const CODE_CHARSET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 6;        // CodeEntry.LENGTH / CHARSET

const RESULTS = new Set(['win', 'lose', 'draw']);
const INNER_TYPES = new Set(['hello', 'party', 'action', 'hash', 'replace',
                             'bye', 'forfeit']);
const ROOM_STAGES = new Set(['waiting', 'ready', 'battling', 'ended']);

// docs/link-security.md: only the relay may author these.  A peer that sends
// one has it dropped, never forwarded.
const SERVER_ONLY = new Set([
  'peer_gone', 'bracket_update', 'match_start', 'tournament_over', 'spectate',
  'lobby_welcome', 'lobby_list', 'lobby_delta', 'room_state', 'room_replay',
  'room_deadline', 'room_result', 'room_closed', 'match_start_spectate',
  'tour_state', 'tour_match', 'tour_match_spectate', 'tour_bye',
  'tour_deadline', 'tour_over', 'tour_closed',
]);

// Profile identity fields, in the order ArenaData.FIELDS checks them.
// `version` is deliberately absent: the arena fingerprint already covers the
// dataset, so a yellow cart may join a red room (the smoke test asserts this).
const PROFILE_FIELDS = [
  ['engine', 'engine differs'],
  ['engineVersion', 'engine version differs'],
  ['apiVersion', 'mod api differs'],
  ['kind', 'arena kind differs'],
  ['rulesetId', 'ruleset differs'],
  ['fingerprint', 'data differs'],
];

const CART_FIELDS = [
  ['id', 'cart differs'],
  ['version', 'cart version differs'],
  ['hash', 'cart hash differs'],
];

// ---------------------------------------------------------------- helpers

const now = () => Date.now();
const hex = (bytes) => crypto.randomBytes(bytes).toString('hex');

function clampText(value, max) {
  if (typeof value !== 'string') return undefined;
  // printable subset only, per docs/link-security.md
  let out = '';
  for (const ch of value) {
    const code = ch.codePointAt(0);
    if (code >= 0x20 && code !== 0x7f) out += ch;
  }
  out = out.trim();
  if (!out) return undefined;
  return out.length > max ? out.slice(0, max) : out;
}

function num(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function codeCharsetOk(code) {
  if (typeof code !== 'string' || code.length !== CODE_LENGTH) return false;
  for (const ch of code) if (!CODE_CHARSET.includes(ch)) return false;
  return true;
}

function mintCode() {
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i += 1) {
    out += CODE_CHARSET[crypto.randomInt(CODE_CHARSET.length)];
  }
  return out;
}

function describeMismatch(a, b) {
  if (!a || typeof a !== 'object') return 'no profile';
  if (!b || typeof b !== 'object') return 'no profile';
  for (const [key, text] of PROFILE_FIELDS) {
    if (a[key] !== b[key]) return text;
  }
  const ca = a.cart;
  const cb = b.cart;
  if (Boolean(ca) !== Boolean(cb)) return 'cart differs';
  if (ca) {
    for (const [key, text] of CART_FIELDS) {
      if (ca[key] !== cb[key]) return text;
    }
  }
  return null;
}

function profileField(a, b) {
  if (!a || typeof a !== 'object' || !b || typeof b !== 'object') return null;
  for (const [key] of PROFILE_FIELDS) if (a[key] !== b[key]) return key;
  return null;
}

// ---------------------------------------------------------------- state

/** @type {Map<string, object>} seatId -> seat */
const seats = new Map();
/** @type {Map<string, string>} session token -> seatId, for resume */
const sessions = new Map();
/** @type {Map<string, object>} room code -> room */
const rooms = new Map();
/** @type {Map<string, string>} advertised seatId -> entry id */
const lobby = new Map();
/** @type {Map<string, number>} client ip -> connection count */
const ipCounts = new Map();

let nextTestName = 1;
let connections = 0;

function allocTestName() {
  const taken = new Set();
  for (const seat of seats.values()) taken.add(seat.name);
  // A random 4-digit tag keeps two testers from looking alike; fall back to a
  // counted name if every slot in the range happens to be busy.
  for (let i = 0; i < 64; i += 1) {
    const candidate = `test_${crypto.randomInt(1000, 10000)}`;
    if (!taken.has(candidate)) return candidate;
  }
  let n = nextTestName;
  while (taken.has(`test_${n}`)) n += 1;
  nextTestName = n + 1;
  return `test_${n}`;
}

// ---------------------------------------------------------------- wire

function send(seat, msg) {
  if (!seat || !seat.socket || seat.socket.destroyed || seat.closed) return;
  let line;
  try {
    line = `${JSON.stringify(msg)}\n`;
  } catch (err) {
    log(`send failed to encode ${msg && msg.type}: ${err.message}`);
    return;
  }
  seat.txBytes += line.length;
  try {
    seat.socket.write(line);
  } catch (err) {
    log(`send failed on ${seat.id}: ${err.message}`);
  }
}

function sendError(seat, reason, extra) {
  send(seat, Object.assign({ type: 'join_error', reason }, extra || {}));
}

function log(...parts) {
  process.stdout.write(`[relay] ${parts.join(' ')}\n`);
}

// ---------------------------------------------------------------- rooms

function roomStateMsg(room) {
  const players = room.players.map((p) => ({
    id: p.id,
    name: p.name,
    verified: p.verified === true,
    role: p.role,
    ready: p.ready === true,
    online: p.online !== false,
    party: p.party,
    partyDigest: p.partyDigest,
  }));
  const spectators = room.spectators.map((s) => ({
    id: s.id,
    name: s.name,
    verified: s.verified === true,
  }));
  return {
    type: 'room_state',
    code: room.code,
    players,
    spectators,
    stage: room.stage,
    profile: room.profile,
    host: room.host,
    seed: room.seed,
    rule: room.rule,
    intent: room.intent,
    maxSpectators: room.maxSpectators,
    match: room.match,
    deadlines: room.deadline ? [{ kind: room.deadline.kind, at: room.deadline.at }] : [],
  };
}

function roomSeats(room) {
  const out = [];
  for (const p of room.players) {
    const seat = seats.get(p.id);
    if (seat) out.push(seat);
  }
  for (const s of room.spectators) {
    const seat = seats.get(s.id);
    if (seat) out.push(seat);
  }
  return out;
}

function broadcast(room, msg, exceptId) {
  for (const seat of roomSeats(room)) {
    if (exceptId && seat.id === exceptId) continue;
    send(seat, msg);
  }
}

function pushRoomState(room, stage) {
  if (stage) room.stage = stage;
  broadcast(room, roomStateMsg(room));
}

function lobbyEntry(room, seat) {
  return {
    id: seat.id,
    name: seat.name,
    verified: seat.verified === true,
    intent: room.intent,
    profile: room.profile,
    since: room.since,
    note: room.note,
    code: room.code,
    open: room.stage === 'waiting' && room.players.length < 2,
    stage: room.stage,
    players: room.players.length,
    spectators: room.spectators.length,
    maxSpectators: room.maxSpectators,
  };
}

function lobbyDelta(added, removed) {
  if (!added.length && !removed.length) return;
  const msg = { type: 'lobby_delta' };
  if (added.length) msg.added = added;
  if (removed.length) msg.removed = removed;
  for (const seat of seats.values()) {
    if (!seat.hello) continue;
    if (seat.room) continue;
    send(seat, msg);
  }
}

function closeRoom(room, reason, exceptId) {
  if (!room || room.closed) return;
  room.closed = true;
  broadcast(room, { type: 'room_closed', reason, code: room.code }, exceptId);
  rooms.delete(room.code);
  for (const p of room.players) {
    const seat = seats.get(p.id);
    if (seat && seat.room === room) seat.room = null;
  }
  for (const s of room.spectators) {
    const seat = seats.get(s.id);
    if (seat && seat.room === room) seat.room = null;
  }
  if (room.reportTimer) clearTimeout(room.reportTimer);
  if (room.deadlineTimer) clearTimeout(room.deadlineTimer);
  log(`room ${room.code} closed (${reason})`);
}

function sideOf(room, seatId) {
  if (room.players[0] && room.players[0].id === seatId) return 'host';
  if (room.players[1] && room.players[1].id === seatId) return 'guest';
  return null;
}

function resolveMatch(room, how, winnerSide) {
  if (!room.match) return;
  const winner = winnerSide === 'host' ? room.players[0]
    : winnerSide === 'guest' ? room.players[1] : null;
  broadcast(room, {
    type: 'room_result',
    match: room.match,
    winner: winner ? winner.name : undefined,
    winnerId: winner ? winner.id : undefined,
    how,
    code: room.code,
  });
  if (room.reportTimer) { clearTimeout(room.reportTimer); room.reportTimer = null; }
  if (room.deadlineTimer) { clearTimeout(room.deadlineTimer); room.deadlineTimer = null; }
  log(`room ${room.code} match ${room.match} resolved (${how}) winner=${winner ? winner.id : 'none'}`);
  room.match = null;
  room.seed = null;
  room.reports = {};
  room.log = [];
  room.seq = 0;
  room.clientSeq = {};
  for (const p of room.players) { p.ready = false; p.party = undefined; p.partyDigest = undefined; }
  pushRoomState(room, 'waiting');
}

function settleReports(room) {
  const host = room.reports.host;
  const guest = room.reports.guest;
  if (!host && !guest) return;
  if (host && guest) {
    // Agreement is the happy path.  Disagreement is settled deterministically
    // (host wins) rather than by coin flip -- docs/link-security.md's rule.
    const consistent = (host === 'win' && guest === 'lose')
      || (host === 'lose' && guest === 'win')
      || (host === 'draw' && guest === 'draw');
    if (consistent) {
      const winnerSide = host === 'win' ? 'host' : host === 'lose' ? 'guest' : null;
      resolveMatch(room, 'agreed', winnerSide);
    } else {
      resolveMatch(room, 'reported', host === 'win' ? 'host' : 'guest');
    }
    return;
  }
  // One side reported.  Honour it once the grace window passes.
  const side = host ? 'host' : 'guest';
  const claim = host || guest;
  if (room.reportTimer) return;
  room.reportTimer = setTimeout(() => {
    room.reportTimer = null;
    if (!room.match || room.closed) return;
    if (side === 'host' && room.reports.host && !room.reports.guest) {
      resolveMatch(room, 'reported', claim === 'win' ? 'host'
        : claim === 'lose' ? 'guest' : null);
    } else if (side === 'guest' && room.reports.guest && !room.reports.host) {
      resolveMatch(room, 'reported', claim === 'win' ? 'guest'
        : claim === 'lose' ? 'host' : null);
    }
  }, REPORT_GRACE_MS);
  if (room.reportTimer.unref) room.reportTimer.unref();
}

function startMatch(room) {
  const host = room.players[0];
  const guest = room.players[1];
  if (!host || !guest) return;
  room.matchNo += 1;
  room.match = `${room.code}-m${room.matchNo}`;
  room.seed = crypto.randomInt(1, 0x7fffffff);
  room.log = [];
  room.logBytes = 0;
  room.seq = 0;
  room.clientSeq = {};
  room.reports = {};
  room.startedAt = now();
  pushRoomState(room, 'battling');

  const base = {
    seed: room.seed,
    ruleset: room.profile && room.profile.rulesetId,
    rule: room.rule,
    hostName: host.name,
    guestName: guest.name,
    hostParty: host.party,
    guestParty: guest.party,
    match: room.match,
    code: room.code,
  };
  const start = (seat, extra) => {
    if (!seat) return;
    send(seat, Object.assign({}, base, extra));
  };
  start(seats.get(host.id), {
    type: 'match_start', role: 'host', peerName: guest.name, theirParty: guest.party,
  });
  start(seats.get(guest.id), {
    type: 'match_start', role: 'guest', peerName: host.name, theirParty: host.party,
  });
  for (const sp of room.spectators) {
    start(seats.get(sp.id), { type: 'match_start_spectate', role: 'spectator' });
  }
  log(`room ${room.code} match ${room.match} started seed=${room.seed}`);

  if (room.deadlineTimer) clearTimeout(room.deadlineTimer);
  room.deadlineTimer = setTimeout(() => {
    room.deadlineTimer = null;
    if (!room.closed && room.match) resolveMatch(room, 'deadline', null);
  }, MATCH_DEADLINE_MS);
  if (room.deadlineTimer.unref) room.deadlineTimer.unref();
}

function roomReplay(room, seat, from) {
  const side = sideOf(room, seat.id);
  const msgs = [];
  for (const entry of room.log || []) {
    if (entry.seq <= from) continue;
    if (side && entry.side === side) continue;
    if (side) {
      msgs.push({ seq: entry.seq, clientSeq: entry.clientSeq, msg: entry.msg });
    } else {
      msgs.push({ seq: entry.seq, clientSeq: entry.clientSeq, side: entry.side,
                  msg: entry.msg });
    }
  }
  send(seat, {
    type: 'room_replay',
    from,
    msgs,
    yourSeq: (room.clientSeq && room.clientSeq[seat.id]) || 0,
  });
}

function fanout(room, seat, clientSeq, inner) {
  const side = sideOf(room, seat.id);
  if (!side) return;
  room.clientSeq = room.clientSeq || {};
  if (typeof clientSeq === 'number') {
    if (room.clientSeq[seat.id] !== undefined && clientSeq <= room.clientSeq[seat.id]) return;
    room.clientSeq[seat.id] = clientSeq;
  }
  room.seq += 1;
  const entry = { seq: room.seq, clientSeq, side, msg: inner };
  room.log.push(entry);
  const size = JSON.stringify(entry).length;
  room.logBytes = (room.logBytes || 0) + size;
  while (room.log.length > LOG_MAX_MSGS || room.logBytes > LOG_MAX_BYTES) {
    const dropped = room.log.shift();
    room.logBytes -= JSON.stringify(dropped).length;
  }

  for (const p of room.players) {
    if (p.id === seat.id) continue;
    const target = seats.get(p.id);
    if (target) send(target, { type: 'room_msg', seq: entry.seq, clientSeq, msg: inner });
  }
  for (const sp of room.spectators) {
    const target = seats.get(sp.id);
    if (target) {
      send(target, { type: 'room_msg', seq: entry.seq, clientSeq, side, msg: inner });
    }
  }

  if (inner && inner.type === 'forfeit') {
    room.reports[side] = 'lose';
    resolveMatch(room, 'forfeit', side === 'host' ? 'guest' : 'host');
  }
}

// ---------------------------------------------------------------- handlers

function handleHello(seat, msg) {
  const requested = clampText(msg.name, MAX_NAME);
  let verified = false;
  let name = requested;
  const ticket = typeof msg.ticket === 'string' ? msg.ticket : null;
  if (ticket) {
    const bound = redeemTicket(ticket);
    if (bound) {
      verified = true;
      name = bound.displayName || name;
    } else {
      // A bad ticket is not fatal: the client still connects and still plays,
      // as a guest.  docs/link-security.md: guests are first-class.
      log(`seat ${seat.id} presented an unknown ticket; falling back to guest`);
    }
  }
  if (!name || TEST_NAMES) name = allocTestName();
  seat.name = name;
  seat.verified = verified;
  seat.hello = true;
  seat.resumeToken = hex(16);
  sessions.set(seat.resumeToken, seat.id);
  seat.sessionExpiresAt = null;
  send(seat, {
    type: 'lobby_welcome',
    session: seat.resumeToken,
    you: { id: seat.id, name: seat.name, verified, session: seat.resumeToken },
    heartbeatMs: HEARTBEAT_MS,
    serverTime: now(),
    resumed: false,
    online: seats.size,
  });
  send(seat, lobbyListMsg());
  log(`seat ${seat.id} hello as ${seat.name}${verified ? ' (verified)' : ' (guest)'}`);
}

function lobbyListMsg() {
  const entries = [];
  for (const [seatId, entry] of lobby.entries()) {
    const room = rooms.get(entry.code);
    const seat = seats.get(seatId);
    if (!room || !seat || room.closed) continue;
    entries.push(lobbyEntry(room, seat));
  }
  return { type: 'lobby_list', entries, online: seats.size };
}

function handleResume(seat, msg) {
  const token = typeof msg.session === 'string' ? msg.session : null;
  const seatId = token ? sessions.get(token) : null;
  const old = seatId ? seats.get(seatId) : null;
  if (!old || old === seat) {
    sendError(seat, 'resume_unknown');
    return;
  }
  // Move the identity onto the new socket.
  if (old.socket && !old.socket.destroyed) {
    try { old.socket.destroy(); } catch (err) { /* already gone */ }
  }
  seats.delete(old.id);
  old.id = seat.id;
  old.socket = seat.socket;
  old.hello = true;
  old.closed = false;
  seats.set(old.id, old);
  sessions.set(token, old.id);
  seat.superseded = true;

  send(old, {
    type: 'lobby_welcome',
    session: token,
    you: { id: old.id, name: old.name, verified: old.verified === true, session: token },
    heartbeatMs: HEARTBEAT_MS,
    serverTime: now(),
    resumed: true,
  });
  if (old.room && !old.room.closed) {
    send(old, roomStateMsg(old.room));
    roomReplay(old.room, old, Math.max(0, num(msg.ack, 0)));
  }
  log(`seat ${old.id} resumed`);
}

function handleRoomCreate(seat, msg) {
  if (seat.room) sendError(seat, 'already_in_room');
  if (!msg.profile) { sendError(seat, 'bad_profile'); return; }
  let code = mintCode();
  while (rooms.has(code)) code = mintCode();
  const room = {
    code,
    intent: 'battle',
    profile: msg.profile,
    rule: msg.profile.rule,
    note: clampText(msg.note, MAX_NOTE),
    maxSpectators: Math.max(0, num(msg.maxSpectators, 8)),
    host: seat.id,
    players: [],
    spectators: [],
    stage: 'waiting',
    seed: null,
    match: null,
    matchNo: 0,
    log: [],
    logBytes: 0,
    seq: 0,
    clientSeq: {},
    reports: {},
    since: now(),
    closed: false,
  };
  rooms.set(code, room);
  seat.room = room;
  if (msg.playing !== false) {
    room.players.push({
      id: seat.id, name: seat.name, verified: seat.verified === true, role: 'host',
    });
  }
  lobby.set(seat.id, { code });
  pushRoomState(room, 'waiting');
  lobbyDelta([lobbyEntry(room, seat)], []);
  log(`seat ${seat.id} created room ${code}`);
}

function handleRoomJoin(seat, msg) {
  const code = typeof msg.code === 'string' ? msg.code.toUpperCase() : '';
  const room = codeCharsetOk(code) ? rooms.get(code) : null;
  if (!room || room.closed) { sendError(seat, 'not_found', { detail: code }); return; }
  const as = msg.as === 'spectator' ? 'spectator' : 'player';

  if (!msg.profile || typeof msg.profile !== 'object') {
    sendError(seat, 'bad_profile');
    return;
  }
  const mismatch = describeMismatch(room.profile, msg.profile);
  if (mismatch) {
    sendError(seat, 'profile_mismatch',
              { field: profileField(room.profile, msg.profile), detail: mismatch });
    return;
  }

  if (seat.room && seat.room !== room) { sendError(seat, 'already_in_room'); return; }

  // Drop any previous seat for this identity (a spectator re-joining).
  room.players = room.players.filter((p) => p.id !== seat.id);
  room.spectators = room.spectators.filter((s) => s.id !== seat.id);

  if (as === 'player') {
    if (room.stage !== 'waiting' && room.stage !== 'ready') {
      sendError(seat, 'rule_violation', { detail: 'the match has started' });
      return;
    }
    if (room.players.length >= 2) { sendError(seat, 'full'); return; }
    room.players.push({
      id: seat.id, name: seat.name, verified: seat.verified === true,
      role: room.players.length === 0 ? 'host' : 'guest',
    });
    if (!room.host) room.host = seat.id;
  } else {
    if (room.spectators.length >= room.maxSpectators) {
      sendError(seat, 'spectators_full');
      return;
    }
    if (room.stage === 'battling' && room.log.length >= LOG_MAX_MSGS) {
      sendError(seat, 'spectate_late');
      return;
    }
    room.spectators.push({
      id: seat.id, name: seat.name, verified: seat.verified === true,
    });
  }
  seat.room = room;
  pushRoomState(room);
  if (as === 'spectator' && room.stage === 'battling') roomReplay(room, seat, 0);
  log(`seat ${seat.id} joined ${code} as ${as}`);
}

function handleRoomReady(seat, msg) {
  const room = seat.room;
  if (!room || room.closed) return;
  const player = room.players.find((p) => p.id === seat.id);
  if (!player) return;
  const party = Array.isArray(msg.party) ? msg.party : [];
  const rule = room.rule || {};
  const size = num(rule.partySize, null);
  if (size !== null && party.length !== size) {
    sendError(seat, 'party_ineligible',
              { detail: `party of ${party.length} for a ${size}-mon rule` });
    return;
  }
  for (const mon of party) {
    const level = num(mon && mon.level, null);
    if (level === null) continue;
    if (rule.minLevel !== undefined && level < num(rule.minLevel, 0)) {
      sendError(seat, 'party_ineligible', { detail: 'level too low' });
      return;
    }
    if (rule.maxLevel !== undefined && level > num(rule.maxLevel, 100)) {
      sendError(seat, 'party_ineligible', { detail: 'level too high' });
      return;
    }
  }
  player.ready = true;
  player.party = party;
  player.partyDigest = typeof msg.partyDigest === 'string' ? msg.partyDigest : undefined;
  if (room.players.length >= 2 && room.players.every((p) => p.ready)) {
    startMatch(room);
  } else {
    pushRoomState(room, 'ready');
  }
}

function handleRoomMsg(seat, msg) {
  const room = seat.room;
  if (!room || room.closed) return;
  if (!sideOf(room, seat.id)) return;            // seated players only
  if (room.stage !== 'battling') return;
  const inner = msg.msg;
  if (!inner || typeof inner !== 'object' || typeof inner.type !== 'string') return;
  if (!INNER_TYPES.has(inner.type)) return;
  if (SERVER_ONLY.has(inner.type)) return;
  fanout(room, seat, num(msg.seq, null), inner);
}

function handleRoomReport(seat, msg) {
  const room = seat.room;
  if (!room || room.closed || !room.match) return;
  if (msg.match && msg.match !== room.match) return;   // stale
  const side = sideOf(room, seat.id);
  if (!side) return;
  const result = RESULTS.has(msg.result) ? msg.result : 'lose';
  room.reports[side] = result;
  settleReports(room);
}

function handleForfeit(seat, msg) {
  const room = seat.room;
  if (!room || room.closed || !room.match) return;
  if (msg.match && msg.match !== room.match) return;
  const side = sideOf(room, seat.id);
  if (!side) return;
  room.reports[side] = 'lose';
  resolveMatch(room, 'forfeit', side === 'host' ? 'guest' : 'host');
}

function handleRoomLeave(seat) {
  const room = seat.room;
  if (!room || room.closed) return;
  room.players = room.players.filter((p) => p.id !== seat.id);
  room.spectators = room.spectators.filter((s) => s.id !== seat.id);
  seat.room = null;
  lobby.delete(seat.id);
  if (room.players.length === 0) {
    closeRoom(room, 'closed', seat.id);
    return;
  }
  if (room.match && room.players.length < 2) {
    // The opponent walked out mid-battle: the remaining player wins.
    resolveMatch(room, 'forfeit', sideOf(room, room.players[0].id));
  }
  room.host = room.players[0].id;
  pushRoomState(room, room.stage === 'battling' ? 'waiting' : room.stage);
}

function handleRoomKick(seat, msg) {
  const room = seat.room;
  if (!room || room.closed) return;
  if (room.host !== seat.id) { sendError(seat, 'not_creator'); return; }
  const targetId = typeof msg.id === 'string' ? msg.id : null;
  if (!targetId || targetId === seat.id) return;
  const target = seats.get(targetId);
  if (target) {
    target.room = null;
    send(target, { type: 'room_closed', reason: 'kicked', code: room.code });
  }
  room.players = room.players.filter((p) => p.id !== targetId);
  room.spectators = room.spectators.filter((s) => s.id !== targetId);
  pushRoomState(room);
}

function handleRoomClose(seat) {
  const room = seat.room;
  if (!room || room.closed) return;
  closeRoom(room, 'closed', seat.id);
  seat.room = null;
}

function handleAdvertise(seat, msg) {
  if (!msg.profile) { sendError(seat, 'bad_profile'); return; }
  const entry = {
    id: seat.id,
    name: seat.name,
    verified: seat.verified === true,
    intent: msg.intent,
    profile: msg.profile,
    since: now(),
    note: clampText(msg.note, MAX_NOTE),
    open: true,
  };
  seat.advertised = entry;
  lobbyDelta([entry], []);
}

function handleUnadvertise(seat) {
  seat.advertised = null;
  lobbyDelta([], [seat.id]);
}

function handleClientMessage(seat, msg) {
  if (SERVER_ONLY.has(msg.type)) {
    log(`seat ${seat.id} tried to author server-only ${msg.type}; dropped`);
    return;
  }
  switch (msg.type) {
    case 'lobby_hello': return handleHello(seat, msg);
    case 'resume': return handleResume(seat, msg);
    case 'ping': return send(seat, { type: 'pong', t: msg.t });
    case 'pong': return undefined;
    case 'lobby_query': return send(seat, lobbyListMsg());
    case 'advertise': return handleAdvertise(seat, msg);
    case 'unadvertise': return handleUnadvertise(seat);
    case 'room_create': return handleRoomCreate(seat, msg);
    case 'room_join': return handleRoomJoin(seat, msg);
    case 'room_ready': return handleRoomReady(seat, msg);
    case 'room_msg': return handleRoomMsg(seat, msg);
    case 'room_ack': return undefined;
    case 'room_report': return handleRoomReport(seat, msg);
    case 'forfeit': return handleForfeit(seat, msg);
    case 'room_leave': return handleRoomLeave(seat);
    case 'room_kick': return handleRoomKick(seat, msg);
    case 'room_close': return handleRoomClose(seat);
    case 'tour_join':
    case 'tour_create':
      return sendError(seat, 'tour_not_found');
    case 'tour_leave':
    case 'tour_start':
    case 'tour_kick':
    case 'tour_close':
      return undefined;
    default:
      log(`seat ${seat.id} sent unknown type ${msg.type}`);
      return undefined;
  }
}

// ---------------------------------------------------------------- connections

function dropSeat(seat, reason) {
  if (seat.closed) return;
  seat.closed = true;
  connections -= 1;
  const count = (ipCounts.get(seat.ip) || 1) - 1;
  if (count <= 0) ipCounts.delete(seat.ip); else ipCounts.set(seat.ip, count);

  if (seat.room && !seat.room.closed) {
    const room = seat.room;
    const wasPlayer = room.players.some((p) => p.id === seat.id);
    const keepSeat = wasPlayer && room.stage === 'battling';
    if (keepSeat) {
      // Hold the seat for RESUME_WINDOW_MS so a reconnect can resume the match.
      for (const p of room.players) if (p.id === seat.id) p.online = false;
      seat.holdTimer = setTimeout(() => {
        if (seat.closed && seat.room === room) {
          handleRoomLeave(seat);
        }
      }, RESUME_WINDOW_MS);
      if (seat.holdTimer.unref) seat.holdTimer.unref();
    } else {
      handleRoomLeave(seat);
    }
  }
  if (seat.advertised) lobbyDelta([], [seat.id]);
  seats.delete(seat.id);
  if (seat.resumeToken) sessions.delete(seat.resumeToken);
  if (seat.timer) clearInterval(seat.timer);
  if (!seat.superseded) log(`seat ${seat.id} gone (${reason})`);
}

function handleLine(seat, line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (err) {
    log(`seat ${seat.id} sent bad JSON; dropped`);
    return;
  }
  if (!msg || typeof msg !== 'object' || Array.isArray(msg)) return;
  if (typeof msg.type !== 'string') return;
  try {
    handleClientMessage(seat, msg);
  } catch (err) {
    log(`handler error on ${msg.type} from ${seat.id}: ${err && err.stack}`);
  }
}

function onConnection(socket) {
  const ip = (socket.remoteAddress || 'unknown').replace(/^::ffff:/, '');
  if (connections >= MAX_CONNS) { socket.destroy(); return; }
  if ((ipCounts.get(ip) || 0) >= MAX_CONNS_PER_IP) { socket.destroy(); return; }
  ipCounts.set(ip, (ipCounts.get(ip) || 0) + 1);
  connections += 1;

  socket.setNoDelay(true);
  const seat = {
    id: hex(6),
    ip,
    socket,
    buf: '',
    hello: false,
    name: null,
    verified: false,
    room: null,
    advertised: null,
    closed: false,
    superseded: false,
    lastSeen: now(),
    rxBytes: 0,
    txBytes: 0,
    windowStart: now(),
    windowCount: 0,
    timer: null,
  };
  seats.set(seat.id, seat);
  log(`seat ${seat.id} connected from ${ip}`);

  socket.on('data', (chunk) => {
    seat.lastSeen = now();
    seat.rxBytes += chunk.length;
    const t = now();
    if (t - seat.windowStart > 1000) { seat.windowStart = t; seat.windowCount = 0; }
    seat.windowCount += 1;
    if (seat.windowCount > MAX_RX_PER_SEC) {
      log(`seat ${seat.id} exceeded the line budget; dropping`);
      socket.destroy();
      return;
    }
    seat.buf += chunk.toString('utf8');
    if (seat.buf.length > MAX_LINE) {
      log(`seat ${seat.id} exceeded MAX_LINE; dropping`);
      socket.destroy();
      return;
    }
    let nl = seat.buf.indexOf('\n');
    while (nl !== -1) {
      const line = seat.buf.slice(0, nl);
      seat.buf = seat.buf.slice(nl + 1);
      if (line.length) handleLine(seat, line);
      nl = seat.buf.indexOf('\n');
    }
  });
  socket.on('error', () => { /* surfaced through close */ });
  socket.on('close', () => dropSeat(seat, 'socket closed'));

  seat.timer = setInterval(() => {
    if (seat.closed) return;
    const t = now();
    if (!seat.hello && t - seat.lastSeen > UNBOUND_SWEEP_MS) {
      socket.destroy();
      return;
    }
    if (t - seat.lastSeen > IDLE_DROP_MS) {
      log(`seat ${seat.id} idle; dropping`);
      socket.destroy();
      return;
    }
    send(seat, { type: 'ping', t });
  }, HEARTBEAT_MS);
  if (seat.timer.unref) seat.timer.unref();
}

// ---------------------------------------------------------------- tickets

const tickets = new Map();

function mintTicket(displayName) {
  const token = hex(16);
  tickets.set(token, { displayName, expiresAt: now() + 60000 });
  return token;
}

function redeemTicket(token) {
  const entry = tickets.get(token);
  if (!entry) return null;
  tickets.delete(token);                     // single use
  if (entry.expiresAt < now()) return null;  // 60 s window
  return entry;
}

setInterval(() => {
  const t = now();
  for (const [token, entry] of tickets.entries()) {
    if (entry.expiresAt < t) tickets.delete(token);
  }
}, 30000).unref();

// ---------------------------------------------------------------- http

const httpServer = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const json = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(`${JSON.stringify(body)}\n`);
  };
  if (url.pathname === '/health') {
    return json(200, {
      ok: true,
      protocol: 2,
      players: seats.size,
      rooms: rooms.size,
      testNames: TEST_NAMES,
      uptimeMs: Math.round(process.uptime() * 1000),
    });
  }
  if (url.pathname === '/players') {
    const out = [];
    for (const seat of seats.values()) {
      if (!seat.hello) continue;
      out.push({
        id: seat.id,
        name: seat.name,
        verified: seat.verified === true,
        room: seat.room ? seat.room.code : null,
      });
    }
    return json(200, { players: out });
  }
  if (url.pathname === '/rooms') {
    const out = [];
    for (const room of rooms.values()) {
      out.push({
        code: room.code,
        stage: room.stage,
        players: room.players.map((p) => ({ id: p.id, name: p.name, ready: p.ready === true })),
        spectators: room.spectators.length,
      });
    }
    return json(200, { rooms: out });
  }
  if (url.pathname === '/lobby/ticket' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; if (body.length > 4096) req.destroy(); });
    req.on('end', () => {
      let name;
      try { name = JSON.parse(body || '{}').displayName; } catch (err) { name = undefined; }
      const token = mintTicket(clampText(name, MAX_NAME));
      json(200, { ticket: token, expiresInMs: 60000 });
    });
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('gen1recomp relay: try /health, /players, /rooms\n');
});

// ---------------------------------------------------------------- boot

const tcpServer = net.createServer(onConnection);

tcpServer.on('error', (err) => {
  log(`tcp server error: ${err.message}`);
  process.exit(1);
});
httpServer.on('error', (err) => {
  log(`http server error: ${err.message}`);
});

process.on('uncaughtException', (err) => log(`uncaught: ${err && err.stack}`));
process.on('unhandledRejection', (err) => log(`unhandled: ${err}`));

tcpServer.listen(PORT, BIND, () => {
  log(`relay listening on ${BIND}:${PORT} (protocol v2, ${MAX_NAME}-char names)`);
  log(`name mode: ${TEST_NAMES ? 'every seat becomes test_<random>' : 'client-supplied, test_<n> when absent'}`);
});
httpServer.listen(HTTP_PORT, BIND, () => {
  log(`control surface on ${BIND}:${HTTP_PORT}`);
});

const shutdown = () => {
  log('shutting down');
  for (const seat of seats.values()) {
    if (seat.timer) clearInterval(seat.timer);
    try { seat.socket.destroy(); } catch (err) { /* ignore */ }
  }
  tcpServer.close();
  httpServer.close();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

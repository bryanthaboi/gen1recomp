-- Handshake v2 (D8): the `hello` both peers exchange on pairing and the
-- compatibility verdict drawn from the two of them.
--
-- v1 builds sent `{type="hello", name, mode}` and nothing else.  Every field
-- here is additive, and a peer that omits `protocol` is by construction a
-- pre-mod build running unmodified content -- so a missing `protocol` reads
-- as "peer is vanilla" and the v1 code path is taken verbatim.  That keeps
-- old installs byte-compatible instead of locking them out.

local Fingerprint = require("src.link.Fingerprint")
local Schemas = require("src.mods.Schemas")
local Version = require("src.core.Version")

local Handshake = {}

Handshake.PROTOCOL = Version.linkProtocol or 2

-- writing into any of these changes what a lockstep turn or a rebuilt trade
-- mon looks like, which is what a v1 peer cannot know about us.  Registry
-- NAMES, not Data paths, so one list covers both generations: `statuses` means
-- data.statuses on Red and data.gen2Statuses on Gold (Schemas.GEN2), and
-- mod.content.statuses is the one thing a mod ever names.
--
-- held_items is Gen 2-only and is here for the same reason the rest are: a
-- Gold mod that changes what LEFTOVERS heals has changed the battle, and the
-- item travels on a traded mon.  On Red the registry is gated to false
-- (Schemas.GEN1), so no op can land in it and the row costs a Gen 1 boot
-- nothing.
--
-- growth_rates is here because it is the one link-surface registry whose
-- records the fingerprint cannot hash: a curve is an expForLevel FUNCTION
-- (src/mods/Schemas.lua R.growth_rates), and writeValue serializes a function
-- as "?".  It decides what level a traded mon's experience buys -- Gen 1 reads
-- it through src/pokemon/Growth.lua and Gold through Mon.growthFor, which
-- prefers the merged registry over the extractor's own coefficient rows -- so
-- two peers that disagree about a curve rebuild the same traded mon at
-- different levels.  Without this row a mod declaring affects_link = false
-- could rewrite every curve and be caught by neither the digest (modKey skips
-- it on its own say-so) nor the online gate.
local LINK_SURFACE = {
  pokemon = true, moves = true, type_chart = true, statuses = true,
  move_effects = true, balls = true, rulesets = true, constants = true,
  link_fields = true, held_items = true, growth_rates = true,
}

Handshake.LINK_SURFACE = LINK_SURFACE

local function loader(game)
  return game and game.mods or nil
end

-- every enabled mod, sorted so both peers see one order.  The whole set
-- rides the wire because the incompatibility screen diffs these arrays to
-- name what is missing; only the affects-link ones fold into the digest.
function Handshake.mods(game)
  local mods = {}
  local mod = loader(game)
  if not mod or not mod.status then return mods end
  local ok, status = pcall(mod.status, mod)
  if not ok or not status then return mods end
  for _, manifest in ipairs(status.loaded or {}) do
    mods[#mods + 1] = { id = manifest.id, version = manifest.version,
                        affectsLink = manifest.affects_link ~= false,
                        language = manifest.language == true }
  end
  table.sort(mods, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return mods
end

-- cheap answer to "can I link with a peer that assumes vanilla?": true as
-- soon as one enabled mod either declares affects_link or has written a
-- record into a link-surface registry
function Handshake.linkModified(game)
  local mod = loader(game)
  if not mod then return false end
  for _, entry in ipairs(Handshake.mods(game)) do
    if entry.affectsLink then return true end
  end
  for name, registry in pairs(mod.content or {}) do
    if LINK_SURFACE[name] then
      for _, list in pairs(registry.ops or {}) do
        for _, entry in ipairs(list) do
          if entry.owner and entry.owner ~= Schemas.ENGINE then return true end
        end
      end
    end
  end
  return false
end

-- #501: the registries a declared translation may write, and nothing else.
-- `text` is the ROM's dialogue, `strings` the engine's own authored text
-- (src/mods/Schemas.lua R.text / R.strings) and `font` the glyphs a
-- language with accents needs.  None of the three is hashed into the
-- fingerprint (src/link/Fingerprint.lua header), so two peers reading the
-- same game in different languages stay in lockstep -- which is also what
-- the cable did: TradeCenter_PrintPartyListNames (pokered
-- engine/link/cable_club.asm) names the peer's party out of the local
-- ROM's table, only the trainer name and the party bytes travel.
-- text_pointers is deliberately out: its rows carry mart inventories and
-- nurse/pc flags, which are gameplay, not language.
local LANGUAGE_REGISTRIES = { text = true, strings = true, font = true }

Handshake.LANGUAGE_REGISTRIES = LANGUAGE_REGISTRIES

-- The manifest's `language = true` is the author's claim; this is the
-- check.  A mod counts as a translation only if every op it appended
-- landed in a language registry, it subscribed no code (a hook or listener
-- runs inside the battle the two peers are lockstepping) and it asked for
-- no permission.  Online play meets strangers, so nothing here may rest on
-- the manifest alone.  A patched client can still lie about its own mods --
-- the fingerprint, not this, is what keeps the shared simulation honest;
-- this gate is what keeps an honest install from being told to turn its
-- language off.
local function translationOnly(mod, id)
  local record = mod.mods and mod.mods[id]
  local manifest = record and record.manifest
  if manifest and #(manifest.permissions or {}) > 0 then return false end
  for name, registry in pairs(mod.content or {}) do
    if not LANGUAGE_REGISTRIES[name] then
      for _, list in pairs(registry.ops or {}) do
        for _, entry in ipairs(list) do
          if entry.owner == id then return false end
        end
      end
    end
  end
  for _, chain in pairs((mod.hooks and mod.hooks.chains) or {}) do
    for _, entry in ipairs(chain) do
      if entry.owner == id then return false end
    end
  end
  for _, list in pairs((mod.events and mod.events.listeners) or {}) do
    for _, entry in ipairs(list) do
      if entry.owner == id then return false end
    end
  end
  return true
end

-- the enabled mods that keep this install out of online play, in the
-- id order Handshake.mods sorts: everything except verified translations.
-- LinkState:offerVanillaRestart names these and switches off exactly these.
function Handshake.onlineBlockers(game)
  local mod = loader(game)
  local blockers = {}
  for _, entry in ipairs(Handshake.mods(game)) do
    local allowed = entry.language and not entry.affectsLink
      and mod ~= nil and translationOnly(mod, entry.id)
    if not allowed then blockers[#blockers + 1] = entry end
  end
  return blockers
end

-- online play (the relay-based online match / tournament flows in
-- LinkState/Tournament) meets strangers, not a coordinating friend, so it
-- skips the LAN path's per-peer compatibility negotiation entirely and
-- just requires a vanilla simulation on both ends: no mod-added Pokemon, no
-- surprises.  #501 carves out translations, because a language is not a
-- simulation: a mod that only rewrites text is invisible to the wire and
-- may stay on, so an English player and a Spanish one can meet the way two
-- regional carts always could.  Mods only ever get baked in at boot
-- (Loader:load), so this is a gate on attempting to go online, not a live
-- mod toggle -- the player disables mods via the mod manager and relaunches.
function Handshake.onlineAllowed(game)
  return #Handshake.onlineBlockers(game) == 0
end

-- Which generation this install is running, read off the merged dataset rather
-- than off GameVersion, so a headless harness that hands over a fixture gets an
-- answer about THAT dataset (Fingerprint.generationOf spells out the two
-- signals it reads).  A game with no data at all is Gen 1, which is what every
-- pre-Gold build was.
function Handshake.generation(game)
  return Fingerprint.generationOf(game and game.data)
end

-- mode is nil on the guest: it pairs and announces itself before the host
-- has picked, and compatibility is decided from the two hellos, not the mode
function Handshake.hello(game, mode)
  local mods = Handshake.mods(game)
  local generation = Handshake.generation(game)
  return {
    type = "hello",
    protocol = Handshake.PROTOCOL,
    name = game and game.save and game.save.player and game.save.player.name,
    mode = mode,
    engineVersion = Version.engine,
    apiVersion = Version.modApi,
    -- additive, like every other field here: a peer that omits `generation` is
    -- Gen 1 by construction, because no build that shipped without this field
    -- could link as anything else (docs/gen2-link-design.md section 4)
    generation = generation,
    fingerprint = Fingerprint.compute(game and game.data, mods, generation),
    linkModified = Handshake.linkModified(game),
    mods = mods,
  }
end

local function major(semver)
  return tonumber(tostring(semver or ""):match("^(%d+)")) or 0
end

-- full        identical link surfaces: nothing to negotiate, lockstep is safe
-- vanilla_peer  an old build, and we are unmodified, so it is right about us
-- engine_skew both v2 on the same major, but different releases: trade
--             still negotiates, battle is refused (see below)
-- subset      both v2 but the surfaces differ: negotiated trade, no battle
-- refused     an old build we would silently corrupt, a different engine, or a
--             peer running the other generation
function Handshake.checkCompat(localHello, remoteHello)
  localHello = localHello or {}
  -- Generation first, ahead of the v1 branch below: a Gold install meeting a
  -- pre-Gold build has to refuse it as the wrong GAME, not read its missing
  -- `protocol` as "peer is vanilla Red and is right about us".
  --
  -- The cart's answer to a cross-generation cable was the Time Capsule, and it
  -- is not a compatibility mode: CheckTimeCapsuleCompatibility
  -- (pokegold engine/link/link.asm:1970) refuses any Johto species, any move
  -- past STRUGGLE and any mon holding mail, and only then does
  -- Link_PrepPartyData_Gen1 rewrite the whole party into Red's 44-byte struct
  -- with the Special stat recomputed out of KantoMonSpecials.  Until somebody
  -- writes that conversion and its two validators, refusing the pairing is the
  -- honest answer -- docs/gen2-link-design.md section 6.
  local localGen = localHello.generation or 1
  local remoteGen = (remoteHello and remoteHello.generation) or 1
  if localGen ~= remoteGen then
    return "refused", "generation_mismatch"
  end
  if not remoteHello or not remoteHello.protocol then
    if localHello.linkModified then
      return "refused", "peer_v1_modified"
    end
    return "vanilla_peer", nil
  end
  if major(remoteHello.engineVersion) ~= major(localHello.engineVersion) then
    return "refused", "engine_mismatch"
  end
  -- A lockstep battle needs the same engine RELEASE, not just the same
  -- major: the fingerprint only covers the data/mod link surface, and
  -- battle logic changes between minor releases (parity fixes, move
  -- effect rework...), so two honest vanilla installs a release apart
  -- pair as "full" and then diverge a few turns in -- the mid-battle
  -- "same mods?" desync draw of #758.  Trade doesn't lockstep a
  -- simulation, so it stays negotiable across releases.
  if tostring(remoteHello.engineVersion) ~= tostring(localHello.engineVersion) then
    return "engine_skew", "engine_release_mismatch"
  end
  if remoteHello.fingerprint == localHello.fingerprint then
    return "full", nil
  end
  return "subset", "fingerprint_mismatch"
end

-- only two v2 peers that agreed on a verdict may reject a mon outright; a v1
-- peer keeps the old substitute-a-move behaviour it was built against
function Handshake.strict(verdict)
  return verdict == "full" or verdict == "subset" or verdict == "engine_skew"
end

function Handshake.battleAllowed(verdict)
  return verdict == "full" or verdict == "vanilla_peer" or verdict == nil
end

function Handshake.tradeAllowed(verdict)
  return verdict ~= "refused"
end

-- ------- incompatibility report

local function index(mods)
  local byId = {}
  if type(mods) ~= "table" then return byId end
  for _, mod in ipairs(mods) do
    if type(mod) == "table" then byId[tostring(mod.id)] = mod end
  end
  return byId
end

-- the two mod arrays diffed, so the screen can name the difference instead
-- of the old silent mid-battle draw
function Handshake.modDiff(localHello, remoteHello)
  local mine = index(localHello and localHello.mods)
  local theirs = index(remoteHello and remoteHello.mods)
  local onlyMine, onlyTheirs, differing = {}, {}, {}
  for id, mod in pairs(mine) do
    local peer = theirs[id]
    if not peer then
      onlyMine[#onlyMine + 1] = mod
    elseif tostring(peer.version) ~= tostring(mod.version) then
      differing[#differing + 1] = { id = id, mine = mod.version,
                                    theirs = peer.version }
    end
  end
  for id, mod in pairs(theirs) do
    if not mine[id] then onlyTheirs[#onlyTheirs + 1] = mod end
  end
  local byId = function(a, b) return tostring(a.id) < tostring(b.id) end
  table.sort(onlyMine, byId)
  table.sort(onlyTheirs, byId)
  table.sort(differing, byId)
  return { onlyMine = onlyMine, onlyTheirs = onlyTheirs, differing = differing }
end

local WIDTH = 19 -- characters that fit one 160px line at 8px per glyph

local function wrap(lines, text)
  while #text > WIDTH do
    local cut = text:sub(1, WIDTH + 1):match("^.*()%s")
    if not cut or cut <= 1 then cut = WIDTH + 1 end
    lines[#lines + 1] = text:sub(1, cut - 1)
    text = text:sub(cut + 1)
  end
  if #text > 0 then lines[#lines + 1] = text end
end

local function listMods(lines, heading, mods)
  if #mods == 0 then return end
  wrap(lines, heading)
  for i, mod in ipairs(mods) do
    if i > 3 then
      wrap(lines, ("and %d more."):format(#mods - 3))
      return
    end
    wrap(lines, (" %s %s"):format(tostring(mod.id):upper():sub(1, 12),
                                  tostring(mod.version or "?")))
  end
end

-- lines for the incompatibility screen: what differs, then what still works
function Handshake.describe(localHello, remoteHello, verdict, mode)
  local lines = {}
  local peerName = remoteHello and remoteHello.name
  local peer = type(peerName) == "string" and peerName or "THEY"
  if verdict == "refused" then
    -- checked before the v1 arm for the same reason checkCompat checks it
    -- first: a Gen 1 peer meeting a Gen 2 one has no `protocol` to read yet
    -- would be named as "an older version", which is the wrong sentence and
    -- sends the player looking for an update that does not exist
    if ((localHello and localHello.generation) or 1)
        ~= ((remoteHello and remoteHello.generation) or 1) then
      wrap(lines, "The other game is")
      wrap(lines, "from a different")
      wrap(lines, "generation.")
      wrap(lines, "These two games")
      wrap(lines, "can't link.")
      return lines
    end
    if not (remoteHello and remoteHello.protocol) then
      wrap(lines, "The other game is")
      wrap(lines, "an older version")
      wrap(lines, "with no mods.")
      wrap(lines, "Your mods can't")
      wrap(lines, "link with it.")
    else
      wrap(lines, "The two games are")
      wrap(lines, "different engine")
      wrap(lines, "versions.")
    end
    return lines
  end
  if verdict == "engine_skew" then
    -- name both releases so two friends can tell WHO updates: this used
    -- to surface three turns in as a desync draw blaming mods (#758)
    wrap(lines, "Your game versions")
    wrap(lines, "differ:")
    wrap(lines, (" you: v%s"):format(tostring(localHello.engineVersion)))
    wrap(lines, (" %s: v%s"):format(peer:sub(1, 8),
                                    tostring(remoteHello.engineVersion)))
    if mode == "battle" then
      wrap(lines, "Battle needs the")
      wrap(lines, "same version on")
      wrap(lines, "both games.")
    else
      wrap(lines, "Trading is limited")
      wrap(lines, "to shared POKéMON.")
    end
    return lines
  end
  wrap(lines, "Your games differ.")
  local diff = Handshake.modDiff(localHello, remoteHello)
  listMods(lines, peer .. " has:", diff.onlyTheirs)
  listMods(lines, "You have:", diff.onlyMine)
  for i, row in ipairs(diff.differing) do
    if i > 2 then break end
    wrap(lines, ("%s %s vs %s"):format(tostring(row.id):upper():sub(1, 8),
                                       tostring(row.mine), tostring(row.theirs)))
  end
  if #diff.onlyMine == 0 and #diff.onlyTheirs == 0 and #diff.differing == 0 then
    wrap(lines, "The game data is")
    wrap(lines, "not the same.")
  end
  if mode == "battle" then
    wrap(lines, "Link battle needs")
    wrap(lines, "the same mods.")
  else
    wrap(lines, "Trading is limited")
    wrap(lines, "to shared POKéMON.")
  end
  return lines
end

return Handshake

local P = {}
local function clamp(v, cap) return math.min(cap, math.max(0, math.floor(tonumber(v) or 0))) end
function P.generate(session, version)
  local s = session or {}
  version = version or require("src.core.game3.constants").versionOf(s)
  assert(version == "ruby" or version == "sapphire", "native RS trainer card requires RS version")
  local C = require("src.core.game3.constants").of(version)
  local Dex = require("src.core.game3.dex")
  local Policy = require("src.core.game3.profiles.rs.pokedex")
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Runtime = package.loaded["src.core.game3.runtime"]
  local current = Runtime and Runtime.getSession and Runtime.getSession()
  local live = s.store == nil and (current == nil or current == s) and Space and Space.getStore and Space.getStore() or nil
  local store, stats = s.store or live or s, s.gameStats or {}
  local tower = s.battleTower or {}
  local function flag(name)
    local id, flags = C:require("flags", name), store.flags or {}
    local v = flags[id]
    if v == nil then v = flags[tostring(id)] end
    if v == nil then v = flags[string.format("0x%X", id)] end
    if v == nil then v = flags[name] end
    return v == true or v == 1
  end
  -- save_menu_util.c:118
  local _, caught = Policy.counts(s, Dex.nationalEnabled({version = version, dex = s.dex, flags = store.flags, vars = store.vars}))
  local paints = 0
  for i = 9, 13 do if (tonumber((s.contestWinners or {})[i] and s.contestWinners[i].species) or 0) ~= 0 then paints = paints + 1 end end
  local hof = tonumber(stats[10]) ~= nil and tonumber(stats[10]) ~= 0 and clamp(stats[1], 4294967295) or 0
  local c = {version = version, cardType = "rs", name = tostring(s.name or s.playerName or ""),
    gender = s.gender or s.playerGender, trainerId = require("src.core.game3.link.rs").trainerId(s) % 65536,
    money = clamp(s.money, 4294967295), playTimeHours = clamp(s.playTimeHours, 65535), playTimeMinutes = clamp(s.playTimeMinutes, 65535),
    hasPokedex = flag("FLAG_SYS_POKEDEX_GET"), pokedexSeen = caught, caughtMonsCount = caught,
    completedHoennPokedex = Policy.completedHoenn(s), hasAllPaintings = paints > 4,
    hofDebutHours = math.floor(hof / 65536), hofDebutMinutes = math.floor(hof / 256) % 256, hofDebutSeconds = hof % 256,
    linkBattleWins = clamp(stats[23], 9999), linkBattleLosses = clamp(stats[24], 9999), pokemonTrades = clamp(stats[21], 65535),
    contestsWithFriends = clamp(stats[35], 999), pokeblocksWithFriends = clamp(stats[34], 65535),
    battleTowerWins = clamp(tower.totalBattleTowerWins, 9999), battleTowerLosses = clamp(tower.bestBattleTowerWinStreak, 9999),
    easyChatProfile = s.easyChatProfile, badges = {}}
  c.stars = (hof ~= 0 and 1 or 0) + (c.completedHoennPokedex and 1 or 0) + (c.battleTowerLosses > 49 and 1 or 0) + (paints > 4 and 1 or 0)
  for i = 1, 8 do c.badges[i] = flag(string.format("FLAG_BADGE0%d_GET", i)) end
  return c
end

-- trainer_card.c:808
function P.flipOffsets(top, down)
  local bottom, height = 160 - top, 160 - 2 * top
  local r6 = (-top * 65536) % 4294967296
  local r5 = (math.floor(0xA00000 / height) + 0xFFFF0000) % 4294967296
  local last = (r6 + r5 * height) % 4294967296
  local delta = math.floor(r5 / height)
  r5 = down and (r5 * 2) % 4294967296 or math.floor(r5 / 2)
  local out = {}
  for y = 0, 159 do
    if y < top then out[y + 1] = (-y - 4) % 65536
    elseif y < bottom then
      out[y + 1] = (math.floor(r6 / 65536) - 4) % 65536
      r6 = (r6 + r5) % 4294967296
      r5 = (r5 + (down and -delta or delta)) % 4294967296
    else out[y + 1] = (math.floor(last / 65536) - 4) % 65536 end
  end
  return out
end
return P

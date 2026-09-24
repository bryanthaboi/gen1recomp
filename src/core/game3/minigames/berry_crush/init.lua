local R = require("src.core.game3.minigames.berry_crush.rules")
local Sim = require("src.core.game3.minigames.berry_crush.sim")

local G = {}

G.id = "crush"
-- pokefirered/src/berry_crush.c:991
G.MIN = 2
G.MAX = R.MAX_PLAYERS
-- pokefirered/src/berry_crush.c:455
G.DROPPED_TEXT = "gText_BerryCrush_MemberDroppedOut"
-- pokefirered/src/berry_crush.c:1530
G.OWN_COUNTDOWN = true
G.DIR = "berry_crush"
G.KEYS = {
  "bg", "container_cap", "crusher_top", "text_windows", "crusher",
  "crusher_base", "impact", "sparkle", "timer_digits",
}
-- pokefirered/src/berry_crush.c:562
G.NAME_PALETTE_BANK = 8

G.Rules = R
G.Sim = Sim

local function readPalette(cache, manifest, name)
  local Art = require("src.ui.game3.minigames.common_art")
  local meta = type(manifest._palettes) == "table" and manifest._palettes[name]
  if type(meta) ~= "table" or type(meta.file) ~= "string" then
    return nil, G.DIR .. "/manifest.lua has no " .. name .. " palette"
  end
  local bytes = cache:read(Art.ROOT .. G.DIR .. "/" .. meta.file)
  local banks = tonumber(meta.banks) or 0
  if type(bytes) ~= "string" or banks < 1 or #bytes < banks * 48 then
    return nil, G.DIR .. "/" .. meta.file .. " is missing from the cache"
  end
  return bytes, banks
end

function G.loadArt(cache)
  local Art = require("src.ui.game3.minigames.common_art")
  cache = cache or Art.cache()
  local art, err = Art.load(G.DIR, G.KEYS, cache)
  if not art then return nil, err end
  local tables, terr = Art.tables(G.DIR, cache)
  if not tables then return nil, terr end
  art.tables = tables
  local bytes, banks = readPalette(cache, art.manifest, "crusher")
  if not bytes then return nil, banks end
  if banks <= G.NAME_PALETTE_BANK then return nil, G.DIR .. "/crusher.pal has no bank 8" end
  local pal = { [0] = { 0, 0, 0, 0 } }
  local base = G.NAME_PALETTE_BANK * 48
  for i = 1, 15 do
    local o = base + i * 3
    pal[i] = { bytes:byte(o + 1) / 255, bytes:byte(o + 2) / 255, bytes:byte(o + 3) / 255, 1 }
  end
  art.namePal = pal
  return art
end

-- pokefirered/src/text.c:721
local MUSIC_EXT = { [0x0B] = true, [0x17] = true, [0x18] = true }

local function gameSession()
  local MG = package.loaded["src.core.game3.minigames.common"]
  return MG and MG.gameSession and MG.gameSession() or nil
end

G.hooks = {
  session = gameSession,
  playSe = function(id)
    pcall(function() require("src.core.game3.audio").playSe(id) end)
  end,
  playSong = function(id)
    pcall(function() require("src.core.game3.audio").playSong(id) end)
  end,
  textSpeed = function()
    local ok, v = pcall(function() return require("src.core.game3.options").textSpeed(gameSession()) end)
    return ok and v or 1
  end,
  pauseMusic = function()
    pcall(function() require("src.core.game3.audio").pauseBgm() end)
  end,
  resumeMusic = function()
    pcall(function() require("src.core.game3.audio").resumeBgm() end)
  end,
  text = function(key, vars)
    local RomText = require("src.core.game3.rom_text")
    local TextIR = require("src.core.game3.scripting.text_ir")
    local ctx = { stringVars = vars, maxWidth = 208 }
    local ir = RomText.translate(RomText.ir(key), ctx, key)
    local out, last = {}, nil
    for _, seg in ipairs(ir) do
      if seg.t == "ext" and MUSIC_EXT[seg.cmd] then
        local bytes = { 0xFC, seg.cmd }
        for _, a in ipairs(seg.args or {}) do bytes[#bytes + 1] = a end
        out[#out + 1] = { t = "text", s = string.char((table.unpack or unpack)(bytes)) }
      else
        out[#out + 1] = seg
        if seg.t ~= "eos" then last = seg.t end
      end
    end
    local box = TextIR.toTextBox(out, ctx)
    -- pokefirered/src/text.c:863
    if last == "para" then box = box .. "\f" end
    return box
  end,
  plain = function(key, vars)
    return require("src.core.game3.rom_text").plain(key, { stringVars = vars })
  end,
  berryName = function(berry)
    local name = require("src.core.game3.items_data").displayName(R.FIRST_BERRY + (tonumber(berry) or 0))
    return (tostring(name or ""):gsub(" BERRY$", ""))
  end,
  removeItem = function(session, itemId)
    local bag = type(session) == "table" and session.bag or nil
    if bag then require("src.core.game3.bag").remove(bag, itemId, 1) end
  end,
  updateRecord = function(session, playerCount, speed)
    return require("src.ui.game3.minigame_records").updateBerryCrush(session, playerCount, speed)
  end,
  givePowder = function(session, amount)
    return require("src.ui.game3.minigame_records").giveBerryPowder(session, amount)
  end,
  -- pokefirered/src/berry_crush.c:2265
  hasBerry = function(session)
    local bag = type(session) == "table" and session.bag or nil
    return bag ~= nil and #require("src.core.game3.bag").listPocket(bag, "BERRY_POUCH") > 0
  end,
  -- pokefirered/src/berry_crush.c:2227
  save = function()
    local rt = package.loaded["src.core.game3.runtime"]
    local game = type(rt) == "table" and rt._game or nil
    if game and type(game.saveGame) == "function" then
      local ok, written = pcall(game.saveGame, game)
      if not ok or written == false then print("[minigame] berry crush save failed: " .. tostring(written)) end
    end
  end,
  incrementGameStat = function(session, statId)
    if type(session) ~= "table" then return end
    require("src.core.game3.slot_machine").incrementGameStat(session, statId)
  end,
  pickBerry = function(sim, done)
    require("src.ui.game3.minigames.berry_crush.pouch").open(sim:session(), done)
  end,
  newCountdown = function(sim)
    local Countdown = require("src.ui.game3.minigames.common_countdown")
    return Countdown.new(120, 80, { playSe = function(id) sim:se(id) end })
  end,
  tick = function(dt)
    local W = package.loaded["src.ui.game3.wireless_icon"]
    if W and W.update then W.update(dt) end
  end,
}

function G.new(ctx)
  return Sim.new(G, ctx)
end

function G.applyResults()
  return false
end

return G

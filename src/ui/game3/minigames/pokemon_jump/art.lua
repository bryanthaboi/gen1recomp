local Art = require("src.ui.game3.minigames.common_art")

local PJArt = {}

PJArt.DIR = "pokemon_jump"
PJArt.KEYS = {
  "bg", "venusaur", "bonuses", "star",
  "vine1", "vine2", "vine3", "vine4",
  "vine1_pal2", "vine2_pal2", "vine3_pal2", "vine4_pal2",
}
PJArt.TABLES = {
  "jump_mons", "vine_base_speeds", "vine_speed_delays", "sound_effects", "jump_offsets",
  "score_bonuses", "prize_items", "prize_quantity", "venusaur_states", "player_name_window_coords",
  "mon_x_coords", "vine_y", "vine_x", "window_templates",
}

local function palette(cache, manifest, name, slot)
  local pal = type(manifest._palettes) == "table" and manifest._palettes[name]
  if type(pal) ~= "table" or type(pal.file) ~= "string" then
    return nil, PJArt.DIR .. "/manifest.lua has no " .. name .. " palette"
  end
  local bank = 0
  if slot ~= nil then
    bank = type(pal.slots) == "table" and tonumber(pal.slots[slot]) or nil
    if bank == nil then return nil, PJArt.DIR .. "/" .. pal.file .. " has no " .. slot .. " slot" end
  end
  local raw = cache:read(Art.ROOT .. PJArt.DIR .. "/" .. pal.file)
  if type(raw) ~= "string" or #raw < (bank + 1) * 48 then
    return nil, PJArt.DIR .. "/" .. pal.file .. " is missing from the cache"
  end
  local out = {}
  for i = 0, 15 do
    local o = bank * 48 + i * 3
    out[i] = { raw:byte(o + 1) / 255, raw:byte(o + 2) / 255, raw:byte(o + 3) / 255, 1 }
  end
  return out
end

function PJArt.load(cache)
  cache = cache or Art.cache()
  local art, err = Art.load(PJArt.DIR, PJArt.KEYS, cache)
  if not art then return nil, err end
  local tables, terr = Art.tables(PJArt.DIR, cache)
  if not tables then return nil, terr end
  for _, key in ipairs(PJArt.TABLES) do
    if tables[key] == nil then return nil, PJArt.DIR .. "/tables.lua has no " .. key end
  end
  art.tables = tables
  local interface, perr = palette(cache, art.manifest, "bg", "interface")
  if not interface then return nil, perr end
  art.interface = interface
  local link, lerr = Art.load("link", { "minigame_digits" }, cache)
  if not link then return nil, lerr end
  art.digits = link.minigame_digits
  return art
end

return PJArt

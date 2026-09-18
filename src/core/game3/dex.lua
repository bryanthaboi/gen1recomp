-- Pokédex quarantine (H9): host bits 1–251; species 252+ in national_dex sidecar.

local Dex = {}

Dex.HOST_MAX = 251
Dex.KANTO_MAX = 151
Dex.NATIONAL_MAX = 386

function Dex.new()
  return {
    seen = {},   -- [species] = true
    caught = {}, -- [species] = true
    owned = {},  -- alias for caught
  }
end

local function resolve_species_id(species)
  if species == nil then return nil end
  local n = tonumber(species)
  if n and n >= 1 then return n end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okP and Pokemon then
    if Pokemon.speciesFromName then
      local id = Pokemon.speciesFromName(tostring(species))
      if id and tonumber(id) then return tonumber(id) end
    elseif Pokemon.byName then
      local id = Pokemon.byName(tostring(species))
      if id and tonumber(id) then return tonumber(id) end
    end
  end
  return nil
end

local function bit_get(arr, species)
  if type(arr) ~= "table" then return false end
  local sp = resolve_species_id(species)
  if sp and arr[sp] == true then return true end
  if arr[species] == true then return true end
  local v = (sp and arr[sp]) or arr[species]
  if v and v ~= 0 and v ~= false then return true end
  return false
end

local function bit_set(arr, species, on)
  if not arr then return end
  local sp = resolve_species_id(species)
  if sp then
    arr[sp] = on and true or nil
  else
    arr[species] = on and true or nil
  end
end

--- Import host dex (1–251) into game3 dex.
function Dex.mergeFromHost(dex, hostSave)
  if not dex or not hostSave then return end
  dex.seen = dex.seen or {}
  dex.caught = dex.caught or {}
  dex.owned = dex.owned or dex.caught
  local pd = hostSave.pokedex or hostSave.pokeDex or {}
  local seen = pd.seen or hostSave.seen or {}
  local caught = pd.caught or pd.owned or hostSave.caught or {}
  for sp = 1, Dex.HOST_MAX do
    if bit_get(seen, sp) then
      bit_set(dex.seen, sp, true)
    end
    if bit_get(caught, sp) then
      bit_set(dex.caught, sp, true)
      bit_set(dex.owned, sp, true)
    end
  end
end

--- Restore National sidecar (252+) into game3 dex.
function Dex.restoreNational(dex, sidecar)
  if not dex or type(sidecar) ~= "table" then return end
  dex.seen = dex.seen or {}
  dex.caught = dex.caught or {}
  dex.owned = dex.owned or dex.caught
  local nd = sidecar.national_dex or sidecar
  local seen = nd.seen or {}
  local caught = nd.caught or {}
  for sp, on in pairs(seen) do
    local n = tonumber(sp)
    if n and n > Dex.HOST_MAX and on then bit_set(dex.seen, n, true) end
  end
  for sp, on in pairs(caught) do
    local n = tonumber(sp)
    if n and n > Dex.HOST_MAX and on then
      bit_set(dex.caught, n, true)
      bit_set(dex.owned, n, true)
    end
  end
end

function Dex.setSeen(dex, species)
  if not dex then return end
  dex.seen = dex.seen or {}
  local sp = resolve_species_id(species) or species
  if not sp then return end
  bit_set(dex.seen, sp, true)
end

function Dex.setCaught(dex, species)
  if not dex then return end
  dex.seen = dex.seen or {}
  dex.caught = dex.caught or {}
  dex.owned = dex.owned or dex.caught
  local sp = resolve_species_id(species) or species
  if not sp then return end
  bit_set(dex.seen, sp, true)
  bit_set(dex.caught, sp, true)
  bit_set(dex.owned, sp, true)
end

function Dex.isSeen(dex, species)
  if not dex then return false end
  return bit_get(dex.seen, species)
end

function Dex.isCaught(dex, species)
  if not dex then return false end
  return bit_get(dex.caught, species) or bit_get(dex.owned, species)
end

function Dex.isOwned(dex, species)
  return Dex.isCaught(dex, species)
end

--- Register an encounter; returns whether it was already seen.
function Dex.registerEncounter(dex, species, session)
  if not dex or not species then return false end
  local sp = tonumber(species) or 1
  if sp > (Dex.KANTO_MAX or 151) then
    local PokedexData = require("src.core.game3.pokedex_data")
    if not PokedexData.isNationalUnlocked(session, dex) then
      return true -- cannot register non-Kanto species before National Dex
    end
  end
  local wasSeen = Dex.isSeen(dex, species)
  Dex.setSeen(dex, species)
  return wasSeen
end

--- Register a capture; returns whether it was already caught.
function Dex.registerCapture(dex, species, session)
  if not dex or not species then return false end
  local sp = tonumber(species) or 1
  if sp > (Dex.KANTO_MAX or 151) then
    local PokedexData = require("src.core.game3.pokedex_data")
    if not PokedexData.isNationalUnlocked(session, dex) then
      return true -- cannot register non-Kanto species before National Dex
    end
  end
  local wasCaught = Dex.isCaught(dex, species)
  Dex.setCaught(dex, species)
  return wasCaught
end

--- Count seen Pokémon in Kanto (1..151) or National mode.
function Dex.countSeen(dex, mode)
  if not dex then return 0 end
  mode = (mode or "kanto"):lower()
  local maxSp = (mode == "national") and Dex.NATIONAL_MAX or Dex.KANTO_MAX
  local count = 0
  for sp = 1, maxSp do
    if Dex.isSeen(dex, sp) then
      count = count + 1
    end
  end
  -- Also count any seen above NATIONAL_MAX in national mode
  if mode == "national" and type(dex.seen) == "table" then
    for sp, on in pairs(dex.seen) do
      local n = tonumber(sp)
      if n and n > Dex.NATIONAL_MAX and on then
        count = count + 1
      end
    end
  end
  return count
end

--- Count caught Pokémon in Kanto (1..151) or National mode.
function Dex.countCaught(dex, mode)
  if not dex then return 0 end
  mode = (mode or "kanto"):lower()
  local maxSp = (mode == "national") and Dex.NATIONAL_MAX or Dex.KANTO_MAX
  local count = 0
  for sp = 1, maxSp do
    if Dex.isCaught(dex, sp) then
      count = count + 1
    end
  end
  if mode == "national" then
    local cTable = dex.caught or dex.owned or {}
    for sp, on in pairs(cTable) do
      local n = tonumber(sp)
      if n and n > Dex.NATIONAL_MAX and on then
        count = count + 1
      end
    end
  end
  return count
end

function Dex.countOwned(dex, mode)
  return Dex.countCaught(dex, mode)
end

--- Split for returnToHost: hostUpdates (1–251) + national sidecar (252+).
function Dex.splitForHost(dex)
  local hostSeen, hostCaught = {}, {}
  local natSeen, natCaught = {}, {}
  if not dex then
    return { seen = hostSeen, caught = hostCaught },
      { seen = natSeen, caught = natCaught }
  end
  for sp, on in pairs(dex.seen or {}) do
    local n = tonumber(sp)
    if n and on then
      if n <= Dex.HOST_MAX then hostSeen[n] = true
      else natSeen[n] = true end
    end
  end
  for sp, on in pairs(dex.caught or {}) do
    local n = tonumber(sp)
    if n and on then
      if n <= Dex.HOST_MAX then hostCaught[n] = true
      else natCaught[n] = true end
    end
  end
  return { seen = hostSeen, caught = hostCaught },
    { seen = natSeen, caught = natCaught }
end

--- Merge hostUpdates into save without touching indices > 251.
function Dex.applyHostUpdates(save, hostUpdates)
  if not save or not hostUpdates then return end
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  for sp, on in pairs(hostUpdates.seen or {}) do
    local n = tonumber(sp)
    if n and n >= 1 and n <= Dex.HOST_MAX and on then
      save.pokedex.seen[n] = true
    end
  end
  for sp, on in pairs(hostUpdates.caught or {}) do
    local n = tonumber(sp)
    if n and n >= 1 and n <= Dex.HOST_MAX and on then
      save.pokedex.caught[n] = true
    end
  end
end

return Dex

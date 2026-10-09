local Builds = require("src.import.gba.rs_builds")
local M = {}
local ROOT, MARKER = "data/generated/gba/", "rom-cache.complete"

local PACKS = {
  {"hall_of_fame", {hofVersion = 1, format_version = 1}},
  {"credits_rse", {creditsVersion = 2, format_version = 1, pageCount = 52,
    entriesPerPage = 5, numMonSlides = 68, theEnd = "the_end.rgba", theEndBlank = "the_end_blank.rgba"}},
  {"reset_rtc"}, {"rse_roulette", {rouletteVersion = 1}},
  {"rse/pokeblock", {packVersion = 1}}, {"rse/move_relearner", {packVersion = 1}},
  {"decorations", {packVersion = 1}}, {"secret_base", {packVersion = 2, baseVersion = 2}},
  {"safari", {safariVersion = 1}}, {"items/shop", {shopVersion = 2, format_version = 1}},
  {"rse/contest_painting", {paintingVersion = 1}},
  {"rse_slot_machine", {slotVersion = 3}},
  {"rse/region_map"}, {"rse/misc"}, {"rse/rs_tv"}, {"rse/battle_tower"},
  {"rse/battle_tower_records"}, {"rse/secret_base_battle", {roomDecorationVersion = 1}},
  {"rse/fan_club"}, {"rse/contest"}, {"rse/contest_data"}, {"rse/rs_contest_gfx"},
  {"rse/berry_blender"}, {"cable_car"}, {"birch"}, {"starter_choose"}, {"wallclock"},
  {"naming", {version = 3}}, {"rse/menus"}, {"rse/common_ui"}, {"rse/bag"},
  {"rse/berry_tag"}, {"rse/party"}, {"rse/summary"}, {"rse/mail"}, {"rse/easy_chat"},
  {"rse/trendy_phrase"}, {"rse/easy_chat_editor", {editorVersion = 2}}, {"rse/rs_egg_hatch"},
  {"pokemon/storage", {version = 6}}, {"rse/pokedex", {packVersion = 1}}, {"rse/pokedex_detail"}, {"rse/diploma"},
  {"rse/trainer_card"}, {"rse/trade"}, {"rse/pokenav"}, {"rse/pokenav_detail"},
  {"rse/pokenav_shell"}, {"rse/pokenav_condition"}, {"rse/pokenav_ribbons"}, {"rs/assets"},
}

local MODULES = {
  {"pokemon/battle/manifest.lua", {format = require("src.import.gba.battle_chrome_extract").FORMAT_VERSION, layout = "rse", assetLayout = "rs",
    elementsLayoutVersion = 1, elementsTableTiles = 66, elementsTiles = 118, elementsSourceBytes = 3776}, false, true},
  {"trainers/manifest.lua", {version = 5, backPicCompression = "lz77", backPicCount = 3, backPicFrames = 4}},
  {"decorations/decorations.lua", {assetLayout = "rs", packVersion = 1, format_version = 1}},
  {"safari/rse_tables.lua", {assetLayout = "rs", safariVersion = 1}},
  {"easy_chat/words.lua", {assetLayout = "rs", format_version = 1}},
  {"wild_extra.lua", {assetLayout = "rs"}},
  {"region_map/map_sections.lua", {layout = "rs", format_version = 1}},
  {"pokemon/battle_anims/pack.lua", {assetLayout = "rs", version = 5}},
  {"pokemon/battle_transition/manifest.lua", {assetLayout = "rs", gameLayout = "rs", format = 1}},
  {"intro/rs/manifest.lua", {layout = "rs", format = 1}, true},
  {"intro/rs/scenery/manifest.lua", {layout = "rs", format = 1}, true},
  {"title/manifest.lua", {layout = "rs", format = 1}, true},
}
M.MODULES = MODULES

local function read(fs, path)
  local fn = fs and (fs.read or fs.readAt)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, path)
  return ok and type(value) == "string" and value or nil
end
local function exists(fs, path)
  local fn = fs and (fs.exists or fs.existsAt)
  if type(fn) == "function" then
    local ok, value = pcall(fn, path)
    return ok and value == true
  end
  if fs and type(fs.getInfo) == "function" then
    local ok, info = pcall(fs.getInfo, path, "file")
    return ok and info ~= nil and (info.type == nil or info.type == "file")
  end
  return false
end
local function parse(fs, path)
  local body = read(fs, path)
  if not body then return nil, "missing/unreadable generated module" end
  local chunk = load(body, "@" .. path, "t", {})
  if not chunk then return nil, "invalid generated Lua" end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return nil, "generated module is not a table" end
  return data
end
local function selectedBuild(version, fs, sha1)
  if sha1 == nil then
    local marker = read(fs, MARKER)
    sha1 = marker and marker:match("^rom%-cache%-v%d+%-" .. version .. ":([%x]+)$")
  end
  if type(sha1) ~= "string" then return nil end
  sha1 = sha1:lower()
  for _, row in ipairs(Builds[version]) do if row.sha1 == sha1 then return row.build end end
end
local function checkFields(data, fields)
  for name, expected in pairs(fields or {}) do
    if data[name] ~= expected then return false, "invalid " .. name end
  end
  return true
end
local function relativePath(path)
  return type(path) == "string" and path ~= "" and path:sub(1, 1) ~= "/"
    and not path:find("\\", 1, true) and not path:find(":", 1, true)
    and not path:find("[%z\1-\31]") and not path:find("//", 1, true)
    and not ("/" .. path .. "/"):find("/../", 1, true)
    and not ("/" .. path .. "/"):find("/./", 1, true)
end
local function checkFiles(fs, data, path, sub)
  local selected = {}
  if type(data.files) ~= "table" then return false, path, "missing manifest files table" end
  local count = #data.files
  for k in pairs(data.files) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > count then
      return false, path, "invalid manifest files array"
    end
  end
  for i = 1, count do
    local rel = data.files[i]
    if not relativePath(rel) then
      return false, path, "invalid manifest file path"
    end
    if not selected.root then
      local at = rel:find("/" .. sub .. "/", 1, true)
      if not at or at == 1 then return false, path, "invalid manifest pack directory" end
      selected.root = rel:sub(1, at - 1)
    end
    local prefix = selected.root .. "/" .. sub .. "/"
    if rel:sub(1, #prefix) ~= prefix or #rel <= #prefix then
      return false, path, "manifest file outside selected pack root"
    end
    if not exists(fs, rel) then return false, rel, "missing manifest file" end
  end
  return true
end

function M.check(version, fs, sha1)
  if not Builds[version] then return true end
  local build = selectedBuild(version, fs, sha1)
  if not build then return false, MARKER, "missing/unsupported native build identity" end
  for _, spec in ipairs(PACKS) do
    local path = ROOT .. spec[1] .. "/manifest.lua"
    local data, reason = parse(fs, path)
    if not data then return false, path, reason end
    if data.assetLayout ~= "rs" or data.build ~= build or data.game ~= version or data.format ~= 1 then
      return false, path, "native asset layout/build/edition/format mismatch"
    end
    local ok, why = checkFields(data, spec[2])
    if not ok then return false, path, why end
    local complete, missing, error = checkFiles(fs, data, path, spec[1])
    if not complete then return false, missing, error end
  end
  for _, spec in ipairs(MODULES) do
    local path = ROOT .. spec[1]
    local data, reason = parse(fs, path)
    if not data then return false, path, reason end
    if data.build ~= build then return false, path, "native build mismatch" end
    if spec[4] and data.game ~= version then return false, path, "native edition mismatch" end
    local ok, why = checkFields(data, spec[2])
    if not ok then return false, path, why end
    if spec[3] then
      if data.game ~= version then return false, path, "native edition mismatch" end
      local sub = spec[1]:sub(1, #spec[1] - #"/manifest.lua")
      local complete, missing, error = checkFiles(fs, data, path, sub)
      if not complete then return false, missing, error end
    end
  end
  local chrome = ROOT .. "chrome/native_fonts.lua"
  local data, reason = parse(fs, chrome)
  if not data then return false, chrome, reason end
  if data.layout ~= "rs" or data.formatVersion ~= 2 then return false, chrome, "native font schema mismatch" end
  for gender = 0, 2 do
    local path = ROOT .. "trainers/back_" .. gender .. ".rgba"
    local bytes = read(fs, path)
    if not bytes or #bytes ~= 64 * 64 * 4 * 4 then return false, path, "invalid native trainer back strip" end
  end
  for _, name in ipairs({ "elements.rgba", "elements_exp.rgba" }) do
    local path = ROOT .. "pokemon/battle/" .. name
    local bytes = read(fs, path)
    if not bytes or #bytes ~= 320 * 24 * 4 then return false, path, "invalid native battle element atlas" end
  end
  for _, spec in ipairs({ { "healthbox_safari.rgba", 128 * 64 * 4 },
      { "healthbox_doubles_player.rgba", 128 * 32 * 4 },
      { "healthbox_doubles_opponent.rgba", 128 * 32 * 4 } }) do
    local path = ROOT .. "pokemon/battle/" .. spec[1]
    local bytes = read(fs, path)
    if not bytes or #bytes ~= spec[2] then return false, path, "invalid native battle healthbox sheet" end
  end
  return true
end
return M

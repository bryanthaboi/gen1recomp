-- traduccion_es: the game in Spanish, straight from the player's own
-- EUR cartridge dump.
--
-- Two layers, applied in this order:
--
--   1. Automatic. If a Spanish Red/Blue dump (the EUR release Nintendo
--      shipped) sits in the imports/ folder -- the same folder ROMs are
--      already dropped into for importing -- its official script is decoded
--      at load time and registered over the US extraction: dialogue, move
--      names, item names, trainer classes, species names. The mod ships
--      addresses and a byte->glyph charmap only (rom/spec_es.lua); the
--      Spanish text itself always comes from the player's own cartridge,
--      the same recipes-not-content posture the engine holds itself to.
--
--   2. Manual. The lang/ catalogs, exactly as `modkit translation`
--      scaffolds them. Engine-authored lines (menus, battle system text)
--      are not in the ROM, so lang/strings.lua is hand-translated; any
--      other entry filled in here wins over the automatic layer, which
--      makes lang/dialogue.lua the place to hand-fix a line.
--
-- Anything neither layer covers keeps rendering in English, so the mod is
-- playable at every stage of completeness.
--
-- Read TRANSLATING.md before editing lang/; the font is the part people
-- get wrong.
return function(mod)
  -- mod:read is the supported way into your own directory; catalogs and
  -- the rom/ modules are plain Lua, so read and run them rather than
  -- require()ing them.
  local function readLua(rel)
    local body = mod:read(rel)
    if not body then return nil, rel .. " is missing" end
    local chunk, err = loadstring(body, rel)
    if not chunk then return nil, rel .. ": " .. tostring(err) end
    local ok, result = pcall(chunk)
    if not ok then return nil, rel .. ": " .. tostring(result) end
    return result
  end

  local function catalog(name)
    local table_, err = readLua("lang/" .. name .. ".lua")
    if type(table_) ~= "table" then
      if err then mod.log:warn("%s", err) end
      return {}
    end
    return table_
  end

  -- An empty value means "not translated yet", never "translate to blank".
  local function each(name, apply)
    local n = 0
    for key, value in pairs(catalog(name)) do
      if type(value) == "string" and value ~= "" then
        apply(key, value)
        n = n + 1
      end
    end
    return n
  end

  -- ---- graphics straight from the cartridge -------------------------
  -- The dump carries the pixel art the Spanish release drew, so nothing
  -- is approximated by hand: the accented glyph tiles come out of the
  -- cartridge's own font, and the HUD sheets (":N" level tag, "PS" bar
  -- label) plus the "Edicion Roja" title ribbon are re-derived with the
  -- exact recipes the importer's extraction uses. Sheets that mirror a
  -- cache path land in save/mod-derived/<id>/, which Assets.resolve
  -- prefers for enabled mods (the assets_transforms channel); the accent
  -- tiles become a font page at 0x100+ whose charmap rows re-home the
  -- cartridge's own byte codes.
  local function deriveGraphics(dump, spec)
    if not (love and love.filesystem and love.image) then
      return nil, "no image runtime (headless)"
    end
    local okIW, ImageWriter = pcall(require, "src.import.ImageWriter")
    if not okIW then return nil, "ImageWriter unavailable" end
    local gfx = spec.gfx
    if not gfx then return nil, "spec carries no gfx table" end

    local function bytesOf(bank, address, length)
      local base = bank == 0 and address
        or bank * 0x4000 + address - 0x4000
      local out = {}
      for i = 1, length do out[i] = dump.data:byte(base + i) end
      return out
    end

    local root = "save/mod-derived/" .. mod.id
    love.filesystem.createDirectory(root .. "/battle")
    love.filesystem.createDirectory(root .. "/title")
    love.filesystem.createDirectory(root .. "/fonts")
    local function put(image, rel)
      image:encode("png", root .. "/" .. rel)
    end

    -- HUD sheets, same symbols/sizes/flags as RomExtractor's extraction
    put(ImageWriter.decode2bpp(
      bytesOf(gfx.hpbar.bank, gfx.hpbar.address, 480), 120, 16, true),
      "battle/font_battle_extra.png")
    local huds = { gfx.hud1, gfx.hud2, gfx.hud3 }
    for index, sheet in ipairs(huds) do
      put(ImageWriter.decode1bpp(
        bytesOf(sheet.bank, sheet.address, 24), 24, 8, true),
        "battle/battle_hud_" .. index .. ".png")
    end
    -- The title ribbon ("Edicion Roja" / "Edicion Azul") is continuous
    -- art, unlike the two-fragment US sheet the title screen repositions,
    -- so it goes through boot.title.versionRibbon -- the explicit-ribbon
    -- seam TitleState draws whole and centered.
    put(ImageWriter.decode1bpp(
      bytesOf(gfx.version.bank, gfx.version.address, 80), 80, 8),
      "title/version_es.png")
    mod.content.field:patch("boot", { title = {
      versionRibbon = root .. "/title/version_es.png",
    } })

    -- accent tiles: every multi-byte glyph the cartridge maps in the
    -- 0x80+ range that the US font never drew (é stays on the US tile),
    -- cut from the cartridge's FontGraphics and re-homed at 0x100+
    local wanted = {}
    for byte, glyph in pairs(spec.charmap) do
      if type(byte) == "number" and byte >= 0x80 and byte <= 0xFF
          and #glyph > 1 and glyph:byte(1) >= 0xC2 and glyph ~= "é" then
        wanted[#wanted + 1] = { byte = byte, seq = glyph }
      end
    end
    table.sort(wanted, function(a, b) return a.byte < b.byte end)
    if #wanted > 0 then
      local strip = {}
      for index, entry in ipairs(wanted) do
        local tile = bytesOf(gfx.font.bank,
          gfx.font.address + (entry.byte - 0x80) * 8, 8)
        for i = 1, 8 do strip[(index - 1) * 8 + i] = tile[i] end
      end
      put(ImageWriter.decode1bpp(strip, #wanted * 8, 8, true),
        "fonts/es_accents.png")
      mod.content.font:register("es_accents", {
        image = root .. "/fonts/es_accents.png",
        base = 0x100, glyphsPerRow = #wanted,
      })
      for index, entry in ipairs(wanted) do
        mod.content.font:register("charmap:" .. entry.seq,
          { seq = entry.seq, code = 0x100 + index - 1 })
      end
    end
    return #wanted
  end

  -- A hand-drawn glyph page can replace the TTF later; register it before
  -- anything asks for a glyph on it. See TRANSLATING.md.
  for id, page in pairs(catalog("font")) do
    mod.content.font:register(id, page)
  end
  for seq, code in pairs(catalog("charmap")) do
    mod.content.font:register("charmap:" .. seq, { seq = seq, code = code })
  end

  local counts = {}
  local missingDump = nil

  -- ---- layer 1: the player's own cartridge --------------------------
  local function nameCount(names)
    local n = 0
    for _ in pairs(names or {}) do n = n + 1 end
    return n
  end

  -- Patch a name registry, skipping ids the merged view does not carry
  -- and names the ROM left identical (PIKACHU is PIKACHU everywhere).
  local function patchNames(registry, names, field)
    local n = 0
    for id, name in pairs(names or {}) do
      local record = registry:get(id)
      if record and record[field] ~= name then
        registry:patch(id, { [field] = name })
        n = n + 1
      end
    end
    return n
  end

  local function findSpanishDump(spec)
    if not (love and love.filesystem and love.data) then
      return nil, "no filesystem available (headless load)"
    end
    local wanted = {}
    for _, rom in ipairs(spec.roms) do wanted[rom.sha1] = rom end
    local info = love.filesystem.getInfo("imports")
    if not info then return nil, "no imports/ folder yet" end
    local found = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems("imports")) do
      if name:lower():find("%.gbc?$") then
        local data = love.filesystem.read("imports/" .. name)
        if data then
          local sha1 = love.data.encode(
            "string", "hex", love.data.hash("sha1", data))
          local rom = wanted[sha1]
          if rom then found[#found + 1] = { rom = rom, data = data } end
        end
      end
    end
    if #found == 0 then return nil, "no Spanish dump in imports/" end
    -- Prefer the dump matching the running game: Red text over a Blue
    -- cartridge differs in a handful of version lines, so a cross-version
    -- dump is a fallback, not a first choice. Yellow shares neither
    -- labels nor layout with these dumps, so it gets no cartridge layer
    -- at all until a Spanish-Yellow spec exists.
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    local current = ok and GameVersion.current or nil
    if current and current ~= "red" and current ~= "blue" then
      return nil, "no Spanish spec for version " .. tostring(current)
    end
    for _, candidate in ipairs(found) do
      if candidate.rom.game == current then return candidate end
    end
    return found[1]
  end

  local function cartridgeLayer()
    local spec, err = readLua("rom/spec_es.lua")
    if not spec then
      mod.log:warn("cannot load the address spec: %s", tostring(err))
      return
    end
    local decoder, decErr = readLua("rom/decoder.lua")
    if not decoder then
      mod.log:warn("cannot load the decoder: %s", tostring(decErr))
      return
    end
    local dump, why = findSpanishDump(spec)
    if not dump then
      mod.log:info("no EUR dump found (%s) -- dialogue stays in English. "
        .. "Copy your Spanish Red/Blue .gb/.gbc into the imports/ folder "
        .. "and restart.", tostring(why))
      missingDump = tostring(why)
      -- Derived sheets persist across boots and Assets prefers them
      -- version-blind, so a session the cartridge does not apply to
      -- (Yellow, or the dump was removed) sheds them; the next Red/Blue
      -- boot re-derives in milliseconds.
      if love and love.filesystem then
        local root = "save/mod-derived/" .. mod.id
        for _, rel in ipairs({
          "battle/font_battle_extra.png", "battle/battle_hud_1.png",
          "battle/battle_hud_2.png", "battle/battle_hud_3.png",
          "title/version_es.png", "fonts/es_accents.png",
        }) do
          love.filesystem.remove(root .. "/" .. rel)
        end
      end
      return
    end
    local ok, catalogs, stats = pcall(decoder.catalogs, dump.data, spec)
    if not ok then
      mod.log:warn("decoding %s failed: %s", dump.rom.label,
        tostring(catalogs))
      return
    end
    for label, text in pairs(catalogs.dialogue) do
      mod.content.text:override(label, text)
    end
    counts.rom_dialogue = nameCount(catalogs.dialogue)
    counts.rom_moves = patchNames(
      mod.content.moves, catalogs.names.moves, "name")
    counts.rom_items = patchNames(
      mod.content.items, catalogs.names.items, "name")
    counts.rom_trainers = patchNames(
      mod.content.trainers, catalogs.names.trainers, "name")
    counts.rom_species = patchNames(
      mod.content.pokemon, catalogs.names.species, "name")
    -- the cartridge's own dex table: Spanish kind ("RATÓN") plus the
    -- official metric height/weight -- the engine's dex page prefers the
    -- metric fields whenever an entry carries them
    local dex = 0
    for id, entry in pairs(catalogs.dex or {}) do
      if mod.content.pokemon:get(id) then
        mod.content.pokemon:patch(id, { dexEntry = {
          kind = entry.kind,
          heightM = entry.heightM, weightKg = entry.weightKg,
        } })
        dex = dex + 1
      end
    end
    counts.rom_dex = dex
    -- type display names (FUEGO, AGUA, ...): the engine registers every
    -- type record itself, so the cartridge name lands as a patch on top
    -- -- gameplay-identical, display-only
    local types = 0
    for id, name in pairs(catalogs.types or {}) do
      mod.content.type_chart:patch(id, { name = name })
      types = types + 1
    end
    counts.rom_types = types
    -- the cartridge's own preset names for the naming screen
    if dump.rom.presets then
      mod.content.field:patch("boot", { namePresets = {
        player = dump.rom.presets.player,
        rival = dump.rom.presets.rival,
      } })
    end
    local glyphs, gfxErr = deriveGraphics(dump, spec)
    if glyphs then
      mod.log:info("cartridge graphics derived: HUD sheets, title "
        .. "ribbon and %d accent glyphs", glyphs)
    else
      mod.log:warn("cartridge graphics skipped: %s", tostring(gfxErr))
    end
    if #stats.skipped > 0 then
      mod.log:warn("%d entries could not be decoded (first: %s) -- those "
        .. "lines stay in English", #stats.skipped, stats.skipped[1])
    end
    mod.log:info("%s: %d lines of official script applied",
      dump.rom.label, counts.rom_dialogue)
  end

  cartridgeLayer()

  -- ---- layer 2: the lang/ catalogs ----------------------------------
  counts.dialogue = each("dialogue", function(id, value)
    mod.content.text:override(id, value)
  end)
  counts.strings = each("strings", function(source, value)
    mod.content.strings:override(source, value)
  end)
  counts.species = each("species_names", function(id, value)
    mod.content.pokemon:patch(id, { name = value })
  end)
  counts.moves = each("move_names", function(id, value)
    mod.content.moves:patch(id, { name = value })
  end)
  counts.items = each("item_names", function(id, value)
    mod.content.items:patch(id, { name = value })
  end)
  counts.trainers = each("trainer_names", function(id, value)
    mod.content.trainers:patch(id, { name = value })
  end)
  counts.statuses = each("status_labels", function(id, value)
    mod.content.statuses:patch(id, { label = value })
  end)

  mod.events:on("game.ready", function(ev)
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    mod.log:info("Español: %d strings translated", total)
    -- The mod's whole point is the cartridge, so a boot without one gets
    -- an in-game pointer instead of a silent half-translation. Written
    -- without accents on purpose: their glyphs also come from the dump.
    local game = ev and ev.game
    if missingDump and game and game.stack and mod.ui.TextBox then
      game.stack:push(mod.ui.TextBox.new(game,
        "TRADUCCION\nESPANOLA:\vfalta el cartucho.\f"
        .. "Copia tu ROM\n(Edicion Roja o\vAzul) a la carpeta\v"
        .. "imports/ del juego\vy reinicia.\f"
        .. "Spanish dump not\nfound in imports/."))
    end
  end)
end

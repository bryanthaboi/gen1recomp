-- Driver: renders the launcher's FIND MODS tab against a canned index whose
-- listings carry the feed's `downloads` object, so the card line, the sort
-- popup and the per-mod popup can be eyeballed with real numbers, real
-- unknowns and a real zero in the same list.
--   SHOT_DIR=/tmp/finddl POKEPORT_DRIVER=tests/drivers/launcher_find_downloads_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")

  local dir = os.getenv("SHOT_DIR") or "/tmp/finddl"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local imp = RomImporter.new(function() end, { launcher = true })

  local function mod(id, title, downloads)
    return {
      id = id, title = title, author = "someone", version = "1.0.0",
      summary = "A canned listing for the screenshot.",
      categories = { "GAMEPLAY" }, tags = {}, games = {},
      update_check = "ok",
      downloads = downloads,
      latest = { version = "1.0.0", zip = {
        url = "https://example.invalid/" .. id .. ".zip" } },
    }
  end

  -- the canned listing IS the fixture: never let the tab go and fetch the
  -- player's real sources over it
  -- new() prewarms a real fetch; drop the in-flight handle and the pump
  imp._refreshFindSources = function() end
  imp._refreshFind = function() end
  imp._pumpFindFetch = function() end
  imp._findFetch = nil
  imp.findSources = { { feed = "https://example.invalid/data/index.json",
                        base = "https://example.invalid/",
                        label = "example/index" } }
  imp.findIndex = { schemaVersion = 1, categories = { "GAMEPLAY" }, mods = {
    mod("busy", "Busy Mod",
        { total = 1578, recent = 388, window_days = 30,
          as_of = "2026-08-18T05:17:00.000Z" }),
    mod("huge", "Huge Mod",
        { total = 1234567, recent = 24000, window_days = 30,
          as_of = "2026-08-18T05:17:00.000Z" }),
    mod("young", "Young Mod",
        { total = 42, as_of = "2026-08-18T05:17:00.000Z" }),
    mod("counted-zero", "Counted Zero Mod", { total = 0 }),
    mod("unknown", "Unknown Mod", nil),
  } }
  imp.findLoaded = true
  imp:_switchTab("find")
  U.wait(3)

  local pending = nil
  love.draw = function()
    imp:draw()
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 90 do
      if not pending then break end
      imp:update(1 / 60)
      coroutine.yield()
    end
    U.wait(3)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end

  local ModUpdate = require("src.mods.ModUpdate")
  for _, e in ipairs(imp.findIndex.mods) do
    local s = imp:_findStats(e)
    U.log(("  %-13s %s | trending=%s"):format(e.id,
      ModUpdate.downloadsShort(s and s.total),
      tostring(s and ModUpdate.trendingLine(s.recent, s.windowDays))))
  end

  for _, key in ipairs({ "popularity", "trending", "name" }) do
    imp.modSort = key
    imp._findSortCache = nil
    U.wait(2)
    shot("find_sort_" .. key .. ".png")
    local order = {}
    for _, e in ipairs(imp._findSortCache.list) do order[#order + 1] = e.id end
    U.log("sort " .. key .. ":", table.concat(order, ", "))
  end

  imp.modSort = "popularity"
  imp._sortPopup = "find"
  U.wait(2)
  shot("find_sort_popup.png")
  imp._sortPopup = nil

  imp._findEntry = imp.findIndex.mods[1]
  U.wait(2)
  shot("find_entry_counted.png")
  imp._findEntry = imp.findIndex.mods[5]
  U.wait(2)
  shot("find_entry_unknown.png")
  imp._findEntry = nil

  -- the installed-mods tab shares the persisted sort key; Trending there has
  -- nothing to sort by, so it must degrade rather than reorder on nothing
  imp.modSort = "trending"
  imp:_switchTab("mods")
  U.wait(3)
  shot("mods_tab_trending_fallback.png")

  U.log("done")
  love.event.quit()
end

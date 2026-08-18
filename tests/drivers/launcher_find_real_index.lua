-- Driver: opens FIND MODS against the player's real index sources, lets the
-- prewarm fetch land, and reports what the panel resolved without asking
-- GitHub anything -- the check behind "sorting only covers the pages I
-- visited".  Shoots the first and last page of the download sort.
--   SHOT_DIR=/tmp/findreal POKEPORT_DRIVER=tests/drivers/launcher_find_real_index.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ModUpdate = require("src.mods.ModUpdate")

  local fetched = 0
  local realBegin = ModUpdate.beginFetchReleases
  ModUpdate.beginFetchReleases = function(...)
    fetched = fetched + 1
    return realBegin(...)
  end

  local RomImporter = require("src.import.RomImporter")
  local dir = os.getenv("SHOT_DIR") or "/tmp/findreal"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local imp = RomImporter.new(function() end, { launcher = true })
  imp:_switchTab("find")
  for _ = 1, 900 do
    imp:update(1 / 60)
    coroutine.yield()
    if imp.findLoaded and not imp._findFetch then break end
  end

  local mods = (imp.findIndex and imp.findIndex.mods) or {}
  U.log("index mods:", #mods)
  U.log("stale copy:", tostring(imp.findIndex and imp.findIndex.stale))

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

  local counted, dated, unknown = 0, 0, 0
  for _, e in ipairs(mods) do
    local s = imp:_findStatsCached(e)
    if s and s.total then counted = counted + 1 else unknown = unknown + 1 end
    if s and s.latest then dated = dated + 1 end
  end
  U.log(("counts=%d dated=%d unknown=%d  github requests=%d")
    :format(counted, dated, unknown, fetched))

  imp.modSort = "popularity"
  imp._findSortCache = nil
  U.wait(3)
  shot("real_page1.png")
  local sorted = imp._findSortCache and imp._findSortCache.list or {}
  for i = 1, math.min(3, #sorted) do
    local s = imp:_findStatsCached(sorted[i])
    U.log(("  #%d %s %s"):format(i, sorted[i].title,
      ModUpdate.downloadsShort(s and s.total)))
  end
  for i = math.max(1, #sorted - 2), #sorted do
    local s = imp:_findStatsCached(sorted[i])
    U.log(("  #%d %s %s"):format(i, sorted[i].title,
      ModUpdate.downloadsShort(s and s.total)))
  end

  -- the last page is the one a page-by-page resolve would have left unsorted
  imp._pages["find"] = 99
  U.wait(3)
  U.log("github requests after sorting:", fetched)
  shot("real_last_page.png")

  U.log("done")
  love.event.quit()
end

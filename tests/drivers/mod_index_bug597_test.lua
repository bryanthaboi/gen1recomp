-- Manual check that pulling a mod index works without curl (#597): every
-- remote fetch now goes through src/core/HostShell.lua, which prefers curl and
-- falls back to love.system.httpDownload (the Android GameActivity bridge).
-- Not a map moment, it lives in the launcher's FIND MODS panel, so this driver
-- runs the same transport calls that panel makes and then leaves F9 as a
-- refetch key; the player position is only there to give the window something
-- to be (pokered data/maps/objects/PalletTown.asm: (10, 8) is clear of the
-- three object_events and of the three warps).
--   POKEPORT_DRIVER=tests/drivers/mod_index_bug597_test.lua POKEPORT_IDENTITY=bug597 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Do not set POKEPORT_SPEED: fast-forward desyncs audio and logic ordering,
-- and it would also step this driver several times per rendered frame while a
-- blocking fetch is in flight.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local HostShell = require("src.core.HostShell")
  local ModIndex = require("src.mods.ModIndex")
  local ModUpdate = require("src.mods.ModUpdate")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Source-text checks, because the failure this fixes is a string a human
  -- reads on a device: the old red "curl is not available on this platform"
  -- must be gone from both callers, replaced by the transport-neutral wording.
  local function fileHas(path, needle)
    local ok, body = pcall(love.filesystem.read, path)
    return ok and type(body) == "string" and body:find(needle, 1, true) ~= nil
  end

  check("HostShell exposes the shared transport",
        type(HostShell.canFetch) == "function"
          and type(HostShell.httpGet) == "function"
          and type(HostShell.httpDownload) == "function")
  check("ModIndex no longer speaks of curl to the player",
        not fileHas("src/mods/ModIndex.lua", "curl is not available")
          and fileHas("src/mods/ModIndex.lua", "no network transport"))
  check("ModUpdate no longer speaks of curl to the player",
        not fileHas("src/mods/ModUpdate.lua", "curl is not available")
          and fileHas("src/mods/ModUpdate.lua", "no network transport"))
  check("ModUpdate.haveCurl still answers (the panel's old gate)",
        type(ModUpdate.haveCurl) == "function")

  -- The Android half only reaches a device through a rebuilt liblove/APK, so
  -- confirm the vendored tree really carries the bridge before anyone blames
  -- the phone for a stale build.
  check("GameActivity.httpDownload is in the vendored Android tree",
        fileHas("mobile/android/love/src/main/java/org/love2d/android/GameActivity.java",
                "public static boolean httpDownload"))
  check("liblove registers love.system.httpDownload",
        fileHas("mobile/android/love/src/jni/love/src/modules/system/wrap_System.cpp",
                '{ "httpDownload", w_httpDownload }'))

  local haveCurl = HostShell.haveCurl()
  check("this machine has a transport (desktop: curl)", HostShell.canFetch())
  U.log("transport here:", haveCurl and "curl" or "the Android bridge / none")

  -- Sources come from options.modIndexes, i.e. whatever the human added in the
  -- launcher.  POKEPORT_INDEX_URL is the way to point a fresh identity at a
  -- feed without adding it first.
  local sources = ModIndex.sources()
  local envUrl = os.getenv("POKEPORT_INDEX_URL")
  local source = sources[1]
  if envUrl and envUrl ~= "" then
    source = ModIndex.resolveSource(envUrl) or source
  end
  check("a mod index is configured", source ~= nil)
  if source then U.log("index:", source.label or source.feed) end

  local index, fetchErr, meta, seconds
  if source then
    -- force = true is exactly what the panel's Refresh button does, and both
    -- transports block the calling thread, so this frame will be a long one.
    local t0 = love.timer.getTime()
    index, fetchErr, meta = ModIndex.fetch(source, { force = true })
    seconds = love.timer.getTime() - t0
    check("the feed fetched and parsed", index ~= nil and fetchErr == nil)
    if index then
      check("the listing has mods in it", #(index.mods or {}) > 0)
      U.log(("%d mods in %.1fs%s"):format(#(index.mods or {}), seconds,
            (meta and meta.fromCache) and " (from cache, so the live fetch failed)" or ""))
    else
      U.log("fetch error:", tostring(fetchErr))
    end
  end

  -- Thumbnails are the second half of the bug: the cards can list while every
  -- picture stays blank if the download writes but the rename or size check
  -- loses the file.
  if index then
    local shot
    for _, entry in ipairs(index.mods or {}) do
      local url = ModIndex.joinUrl(entry._base, entry.thumbnail)
      if url then
        local path, err = ModIndex.downloadThumbnail(url, entry.id)
        local info = path and love.filesystem.getInfo(path)
        check("a thumbnail downloaded with bytes in it",
              path ~= nil and info ~= nil and (info.size or 0) > 0)
        if not path then U.log("thumbnail error:", tostring(err)) end
        shot = path
        break
      end
    end
    if not shot then U.log("no entry in this index carries a thumbnail") end
  end

  -- Give the window something to be, and prove it is drawing at all.
  local MAP, STAND = "PALLET_TOWN", { x = 10, y = 8, facing = "down" }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the grass under us; any free neighbour will do
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.teleport(game, MAP, cx, cy, "down")
        U.wait(10)
        break
      end
    end
  end
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  check("the window rendered", U.shot(game, SHOT_DIR .. "/bug597_modindex.png"))

  U.log("The fetch above already ran; F9 runs it again, timed, so you can")
  U.log("watch a Refresh cost a second or two rather than stall. The real")
  U.log("check is the launcher: quit this window, run scripts/run.sh, and in")
  U.log("Mods > Find mods add an index URL -- cards should fill in within a")
  U.log("couple of seconds with their thumbnails drawn, same as before.")
  U.log("Near-misses: cards list but every thumbnail stays blank (the .part")
  U.log("file never got renamed), or on a phone the message reads \"no network")
  U.log("transport on this platform\", which means the APK still has the old")
  U.log("liblove and needs a full scripts/build_android.sh, not a repackage.")

  local held = false
  while true do
    local down = love.keyboard and love.keyboard.isDown("f9")
    if down and not held and source then
      local t0 = love.timer.getTime()
      local again, err = ModIndex.fetch(source, { force = true })
      local dt = love.timer.getTime() - t0
      if again then
        U.log(("refetch: %d mods in %.1fs"):format(#(again.mods or {}), dt))
      else
        U.log(("refetch failed after %.1fs: %s"):format(dt, tostring(err)))
      end
    end
    held = down
    coroutine.yield()
  end
end

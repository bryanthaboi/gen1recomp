-- Manual check of the mod manager's PROFILES tab: seeded PROFILE 1, applying a
-- profile back over a staged toggle, and EXPORT.. writing a .g1rmodlist (#593).
-- The manager has no pokered analogue; the stand cell comes from pokered
-- data/maps/objects/PalletTown.asm (warp_event 5, 5 is Red's front door, so the
-- cell below it is the doorstep), with a walkable-neighbour fallback.
--   POKEPORT_DRIVER=tests/drivers/mod_profiles_bug593_test.lua POKEPORT_IDENTITY=bug593 POKEPORT_DEV=1 love .
-- Do not set POKEPORT_SPEED: fast-forward scales the logic clock only, so taps,
-- the notice timer and the confirm blip stop lining up.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local ModProfile = require("src.mods.ModProfile")

  local MAP = "PALLET_TOWN"
  local STAND = { x = 5, y = 6, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- park somewhere ordinary first: the manager is opened over the overworld in
  -- real play (F10, src/core/Game.lua:446) and draws on top of it
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit or a mod moved the doorstep: any free neighbour will do,
    -- nothing here depends on the exact cell
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("doorstep (%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, "up")
        U.wait(10)
        break
      end
    end
  end

  local opts = (game.save and game.save.options) or {}
  local status = (game.mods and game.mods.status and game.mods:status())
    or game.modStatus or { available = {} }
  -- two installed mods is the floor for this check: with one mod a profile
  -- swap cannot be told apart from the mod simply staying on
  check("at least two mods installed under mods/", #(status.available or {}) >= 2)
  for _, m in ipairs(status.available or {}) do
    U.log("installed mod:", m.id, m.enabled and "on" or "off")
  end
  check("sfxVol is not zero, so the A press blips", (opts.sfxVol or 0) > 0)

  -- open the manager the way F10 does (Game:keypressed pushes the same id)
  Screens.push(game, "ManagerState")
  U.wait(10)
  local mgr = game.stack:top()
  check("the mod manager is on top of the stack", mgr and mgr.screenId == "ManagerState")
  if not (mgr and mgr.screenId == "ManagerState") then
    while true do coroutine.yield() end
  end

  -- right once: MODS -> PROFILES
  U.tap(game, "right")
  U.wait(6)
  local rows = mgr:rowsForScreen()
  check("right lands on the PROFILES tab", mgr.tab == 2)
  local labels = {}
  for i, r in ipairs(rows) do labels[i] = r.label end
  U.log("profile rows:", table.concat(labels, " / "))

  local first = rows[1]
  check("PROFILE 1 was seeded from the setup that was already live",
        first and first.profile ~= nil and first.label == "PROFILE 1")
  check("it is marked active with the ! gutter glyph",
        first and first.glyph == "!" and opts.activeProfile == "PROFILE 1")
  -- the near-miss: profileRows grew by EXPORT.. and IMPORT.., so a snapCursor
  -- or moveCursor still assuming the old three-row tail parks the cursor on the
  -- wrong row and A fires the wrong action
  check("the cursor sits on the first profile, not somewhere down the tail",
        mgr.cursor == 1 and (mgr:focusedRow() or {}).label == "PROFILE 1")
  local tail = {}
  for i = #rows - 3, #rows do tail[#tail + 1] = rows[i] and rows[i].label end
  check("the tail reads SAVE CURRENT AS.. / EXPORT.. / IMPORT.. / [AD-HOC]",
        tail[1] == "SAVE CURRENT AS.." and tail[2] == "EXPORT.."
        and tail[3] == "IMPORT.." and (tail[4] or ""):find("AD-HOC", 1, true) ~= nil)

  -- stage a mod off on the MODS tab so applying PROFILE 1 has something to undo.
  -- Pick one nothing else depends on and that is not experimental, so the toggle
  -- commits straight away instead of opening the cascade or confirm overlay.
  local target
  for _, m in ipairs(status.available or {}) do
    if m.enabled and not m.experimental then
      local needed = false
      for _, other in ipairs(status.available or {}) do
        for _, spec in ipairs(other.dependencySpecs or {}) do
          if spec.id == m.id then needed = true end
        end
      end
      if not needed then target = m break end
    end
  end
  check("found an enabled mod with no dependents to toggle", target ~= nil)

  -- refresh() rebuilds status.available, so hold the id and re-look it up
  -- through mgr.byId rather than keeping the manifest table from before
  local targetId = target and target.id
  local function live()
    return targetId and mgr.byId[targetId] or nil
  end

  if targetId then
    U.tap(game, "left")
    U.wait(6)
    for _ = 1, 40 do
      local row = mgr:focusedRow()
      if row and row.mod and row.mod.id == targetId then break end
      U.tap(game, "down")
      U.wait(2)
    end
    local row = mgr:focusedRow()
    check("cursor reached " .. targetId .. " on the MODS tab",
          row and row.mod and row.mod.id == targetId)
    U.tap(game, "select")
    U.wait(6)
    check("SELECT staged " .. targetId .. " off",
          mgr.overlay == nil and (live() or {}).enabled == false)

    U.tap(game, "right")
    U.wait(6)
    check("back on PROFILES with the cursor on PROFILE 1",
          mgr.tab == 2 and mgr.cursor == 1
          and (mgr:focusedRow() or {}).label == "PROFILE 1")
    U.tap(game, "a")
    U.wait(10)
    check("applying PROFILE 1 re-staged " .. targetId,
          (live() or {}).enabled == true)
    U.log("footer notice reads:", tostring(mgr.notice))
    check("the footer says PROFILE STAGED", mgr.notice == "PROFILE STAGED")
  end

  -- walk down to EXPORT.. by taps, so a cursor that skips shows up here.
  -- From the top of the list that is every profile row after the first plus
  -- SAVE CURRENT AS.., i.e. #profiles + 1 presses.
  local profileCount = 0
  for _, r in ipairs(mgr:rowsForScreen()) do
    if r.profile then profileCount = profileCount + 1 end
  end
  local wantSteps = profileCount + 1
  local steps = 0
  for _ = 1, 10 do
    local row = mgr:focusedRow()
    if row and row.exportProfile then break end
    U.tap(game, "down")
    U.wait(2)
    steps = steps + 1
  end
  local exportRow = mgr:focusedRow()
  check(("EXPORT.. is %d presses below PROFILE 1"):format(wantSteps),
        exportRow ~= nil and exportRow.exportProfile == true and steps == wantSteps)
  U.tap(game, "a")
  U.wait(10)
  U.log("footer notice reads:", tostring(mgr.notice))
  check("the footer says SAVED PROFILE 1", mgr.notice == "SAVED PROFILE 1")

  local rel = ModProfile.fileFor("PROFILE 1")
  local info = love.filesystem.getInfo and love.filesystem.getInfo(rel)
  check(rel .. " exists in the save dir", info ~= nil)
  if info then
    local body = love.filesystem.read(rel)
    local back = ModProfile.decode(body)
    check("the exported file decodes back to PROFILE 1",
          back ~= nil and back.name == "PROFILE 1")
    U.log("wrote", love.filesystem.getSaveDirectory() .. "/" .. rel,
          info.size and (info.size .. " bytes") or "")
  end

  -- leave the cursor at the top of the list for whoever takes over
  for _ = 1, steps do
    U.tap(game, "up")
    U.wait(2)
  end
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  U.shot(game, SHOT_DIR .. "/bug593_profiles.png")
  U.log("captured", SHOT_DIR .. "/bug593_profiles.png")

  U.log("The PROFILES tab is open with the cursor back on PROFILE 1, and the")
  U.log("steps above already ran once: a mod was switched off, PROFILE 1 put it")
  U.log("back, and EXPORT.. wrote the file. Redo it by hand: LEFT for MODS,")
  U.log("SELECT to flip a mod, RIGHT, A on PROFILE 1. The row should carry the")
  U.log("! glyph and the footer should flash PROFILE STAGED. The failure to")
  U.log("watch for is the cursor landing a row off after a tab switch or a")
  U.log("delete, so A on what looks like [AD-HOC] fires EXPORT.. instead.")

  while true do
    coroutine.yield()
  end
end

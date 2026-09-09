-- Look at the Pokedex entry pic (#307).
-- `local ok, img = path and pcall(love.graphics.newImage, path)` is one
-- expression, not a guarded pcall: img was always nil and every dex page drew
-- an empty pic box.  parity_dex_pic.lua asserts the image loads; placement
-- (top-left of the page, bottom-aligned to y=60) is the half only an eye can judge.
--   POKEPORT_DRIVER=tests/drivers/dex_pic_bug307_test.lua POKEPORT_IDENTITY=bug307 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Sprites = require("src.pokemon.Sprites")

  -- the starters are the reported case (Oak's lab preview); PIDGEY is an
  -- ordinary list entry as the control
  local CASES = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIDGEY" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- an unresolved path, a PNG missing from the cache and the truncation bug
  -- itself all render as the same empty box
  local DexEntryMenu = require("src.ui.DexEntryMenu")
  for _, species in ipairs(CASES) do
    local path = Sprites.path(game.data, species, "front", { kind = "dex" })
    check(species .. " resolves a dex front-pic path",
          type(path) == "string" and path ~= "")
    local page = DexEntryMenu.new(game, { species = species, forceOwned = true })
    local held = page.sprite ~= nil
    check(species .. " dex page holds its pic", held)
    if held and page.sprite.getDimensions then
      local w, h = page.sprite:getDimensions()
      U.log("   " .. species .. " pic is", w .. "x" .. h,
            "drawn at x=8, y=" .. math.max(0, 60 - h))
    end
  end

  -- mark the cases seen so the list can reach them
  local dex = game.save.pokedex
  if dex then
    for _, species in ipairs(CASES) do
      dex.seen[species] = true
      dex.owned[species] = true
    end
    U.log("flagged", #CASES, "species as seen+owned so the list can open them")
  end

  -- screenshots, one page at a time
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  for _, species in ipairs(CASES) do
    while game.stack:top() do game.stack:pop() end
    Screens.push(game, "DexEntryMenu", { species = species, forceOwned = true })
    U.wait(60)
    U.shot(game, SHOT_DIR .. "/dex_" .. species:lower() .. ".png")
    U.log("captured", SHOT_DIR .. "/dex_" .. species:lower() .. ".png")
  end

  -- leave a live page up for the hand-off
  while game.stack:top() do game.stack:pop() end
  Screens.push(game, "DexEntryMenu", { species = "BULBASAUR", forceOwned = true })
  U.wait(10)

  U.log("A BULBASAUR dex entry is open; shots of all four cases are in " .. SHOT_DIR)
  U.log("The front sprite belongs in the top-left, standing on the line above")
  U.log("HT/WT, not floating or overlapping the text.  Under #307 that whole")
  U.log("side was blank white.  A or B closes the page.")

  while true do
    coroutine.yield()
  end
end

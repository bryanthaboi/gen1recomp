--   POKEPORT_VERSION=gold POKEPORT_IDENTITY=gold-sep04 \
--     POKEPORT_DRIVER=tests/drivers/gold_pokemon_sprite_hook_bug2217.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-2217 love .
local U = require("tests.drivers.util")

local Hooks = require("src.mods.Hooks")
local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

local OWNER = "driver_sprite_hook_2217"

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-2217"
  local failures = 0
  local function check(ok, what)
    if ok then
      print("[driver] ok   " .. what)
    else
      failures = failures + 1
      print("[driver] FAIL " .. what)
    end
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local save = game.save
  save.player.name = "GOLD"
  save.player.id = 12345
  local function build(species, level)
    local mon = Mon.new(game.data, species, level, {
      dvs = { attack = 15, defense = 15, speed = 15, special = 15 },
    })
    assert(mon, "no base data for " .. species)
    mon.nickname = mon.name
    mon.otName = save.player.name
    mon.otId = save.player.id
    return mon
  end
  save.party = { build("CYNDAQUIL", 22), build("TOTODILE", 18) }

  if not (Runtime.hooks and Runtime.hooks.wrap) then
    Runtime.hooks = Hooks.new()
  end
  local hooks = Runtime.hooks

  local swap = game.data.pokemon.TOTODILE.spriteFront
  local seen, ctxOf = {}, {}
  hooks:wrap("pokemon.sprite", function(nextFn, path, ctx)
    seen[ctx.kind] = (seen[ctx.kind] or 0) + 1
    ctxOf[ctx.kind] = ctxOf[ctx.kind] or ctx
    if ctx.kind == "summary" and ctx.species == "CYNDAQUIL" then
      return swap
    end
    return nextFn(path, ctx)
  end, 0, OWNER)

  local screen = SummaryMenu.new(game, {
    party = save.party, index = 1, save = save,
  })
  game.stack:push(screen)
  U.wait(8)
  U.shot(game, ("%s/2217_01_summary_replaced_sprite.png"):format(out))

  check((seen.summary or 0) > 0,
    "pokemon.sprite fires with kind summary (" ..
    tostring(seen.summary or 0) .. " calls)")
  local ctx = ctxOf.summary
  check(ctx and ctx.species == "CYNDAQUIL" and ctx.side == "front"
    and ctx.mon == save.party[1] and ctx.data == game.data
    and ctx.shiny == false,
    "summary ctx carries species/side/mon/data/shiny")
  local path = screen:picPath(save.party[1])
  check(path == swap, "the summary draws the wrapper's path")

  game.stack:pop()
  hooks:removeOwner(OWNER)
  U.wait(2)

  print(("[driver] shots in %s"):format(out))
  if failures > 0 then
    print(("[driver] FAILED (%d)"):format(failures))
    love.event.quit(1)
  else
    print("[driver] PASS summary_sprite_hook")
    love.event.quit(0)
  end
end

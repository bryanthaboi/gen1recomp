return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"
  pcall(function() io.stdout:setvbuf("no") end)
  local ok = true

  local function groupOf(n)
    local d = n.sprite and n.sprite.def
    local _, group = PaletteFX.spriteObp(d, n.sprite and n.sprite.seed)
    return group, d and d.source
  end

  local function expect(label, n, want)
    if not n then
      print("FAIL " .. label .. " npc not found")
      ok = false
      return
    end
    local group, src = groupOf(n)
    local pass = group == want
    print((pass and "PASS " or "FAIL ") .. label .. " group " .. tostring(group)
      .. " want " .. want .. " seed " .. tostring(n.sprite and n.sprite.seed) .. " " .. tostring(src))
    ok = ok and pass
  end

  local function bySource(ow, idx)
    local tag = "[" .. idx .. "]"
    for _, n in ipairs(ow.npcs or {}) do
      local d = n.sprite and n.sprite.def
      if d and d.source and d.source:find(tag, 1, true) then return n end
    end
  end

  U.newGame(game)
  U.wait(30)
  PaletteFX.setMode("redpp")
  game.save.flags.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES = nil
  game.save.flags.EVENT_GOT_HELIX_FOSSIL = true
  U.teleport(game, "MT_MOON_B2F", 3, 4, "down")
  local ow = game.overworld
  U.hold(game, "down", 20)
  U.wait(2)
  local jessie, james
  for _ = 1, 1500 do
    for _, n in ipairs(ow.npcs or {}) do
      local name = n.def and n.def.name
      if name == "MTMOONB2F_JESSIE" then jessie = n end
      if name == "MTMOONB2F_JAMES" then james = n end
    end
    if jessie and james then break end
    U.wait(1)
  end
  U.wait(60)
  print("mode " .. tostring(PaletteFX.mode))
  expect("mt moon b2f jessie SPR_PAL_ORANGE", jessie, 0)
  expect("mt moon b2f james SPR_PAL_BLUE", james, 1)
  local rocket = bySource(ow, 23)
  if rocket then
    local rg = groupOf(rocket)
    local pass = rg ~= 0 and rg ~= 1
    print((pass and "PASS " or "FAIL ") .. "mt moon b2f rocket group " .. tostring(rg) .. " differs from jessie/james")
    ok = ok and pass
  end
  U.still(game, DIR .. "/3071_04_mtmoon_b2f_jessie_red_james_blue.png")

  U.teleport(game, "PEWTER_POKECENTER", 3, 4, "up")
  ow = game.overworld
  U.wait(30)
  expect("pewter pokecenter jigglypuff PINKMON", bySource(ow, 65), 8)
  expect("pewter pokecenter chansey PINKMON", bySource(ow, 67), 8)
  U.still(game, DIR .. "/F8_01_pewter_pokecenter_jigglypuff_chansey_pink.png")

  U.teleport(game, "POKEMON_FAN_CLUB", 3, 6, "up")
  ow = game.overworld
  U.wait(30)
  expect("fan club clefairy PINKMON", bySource(ow, 66), 8)
  U.still(game, DIR .. "/F8_02_fan_club_clefairy_pink.png")

  print(ok and "PASS jessie_james_advanced_obp_bug3071" or "FAIL jessie_james_advanced_obp_bug3071")
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end

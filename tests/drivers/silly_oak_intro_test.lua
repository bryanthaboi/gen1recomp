-- Driver: NEW GAME through the silly Oak intro (example_silly_oak must be
-- installed under mods/).  Mashes text, picks every menu option in a fixed
-- pattern, screenshots key beats, then asserts mod.save answers.
--
-- Setup:
--   cp -r mods/examples/example_silly_oak mods/
--   SHOT_DIR=/tmp/silly_oak POKEPORT_DRIVER=tests/drivers/silly_oak_intro_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function top() return game.stack:top() end
  local function speechState()
    for _, s in ipairs(game.stack.states or {}) do
      if s.oakPic ~= nil or (s.steps and s.answers) then return s end
    end
  end
  local function topName()
    local s = top()
    if not s then return "?" end
    return s.screenId or (s.__index and tostring(s.__index)) or tostring(s)
  end
  local function isMenu(s)
    return s and s.items and s.index and s.tx ~= nil
  end
  local function isNaming(s)
    return s and s.glyphs ~= nil and s.title ~= nil
  end
  local function isChoiceBox(s)
    return s and s.onChoose and s.index ~= nil and not s.items
  end

  -- confirm the mod actually loaded
  local loaded = false
  if game.modStatus and game.modStatus.loaded then
    for _, m in ipairs(game.modStatus.loaded) do
      if m.id == "example_silly_oak" then loaded = true break end
    end
  end
  if not loaded and game.mods and game.mods.mods then
    local m = game.mods.mods.example_silly_oak
    loaded = m and m.enabled and not m.failed
  end
  U.log("example_silly_oak loaded:", tostring(loaded))
  if not loaded then
    U.log("FAIL: copy the mod up first:")
    U.log("  cp -r mods/examples/example_silly_oak mods/")
    return
  end

  U.wait(5)
  U.tap(game, "start") -- skip intro movie
  U.wait(15)
  U.tap(game, "a") -- title -> menu
  U.wait(8)
  -- with an existing save the menu is CONTINUE / NEW GAME / OPTION;
  -- always land on NEW GAME (row 2 when a save exists, else row 1)
  local ok, saved = pcall(function()
    return require("src.core.SaveData").load() ~= nil
  end)
  if ok and saved then
    U.tap(game, "down")
    U.wait(5)
  end
  U.tap(game, "a") -- NEW GAME
  U.wait(20)

  -- confirm we actually entered OakSpeech, not CONTINUE into the world
  local entered = false
  for _ = 1, 60 do
    if speechState() then entered = true break end
    if game.overworld and top() == game.overworld then break end
    U.wait(1)
  end
  if not entered then
    U.log("FAIL: never entered OakSpeech (did we hit CONTINUE?)")
    U.log("top:", topName())
    return
  end

  U.shot(game, DIR .. "/silly_01_start.png")

  -- walk the speech: A advances text; menus get a deliberate pick pattern
  local picks = {
    -- silly_toast YES/NO: pick YES (index 1)
    toast = 1,
    -- naming player: take preset 1 (RED) via NEW NAME menu -> first preset
    -- snack: OLD ROD (index 3)
    snack = 3,
    -- trusts rival: NO (index 2)
    trust = 2,
    -- pineapple YES/NO: pick NO
    pineapple = 2,
  }
  local saw = {
    toast_kid = false, mew = false, snack = false, trust = false,
    pineapple = false, shrink = false,
  }
  local snackPicked, trustPicked = false, false
  local toastAnswered, pineappleAnswered = false, false
  local shot = {}

  for _ = 1, 900 do
    local speech = speechState()
    local s = top()

    if speech and speech.shrink then
      saw.shrink = true
      if not shot.shrink then
        shot.shrink = true
        U.shot(game, DIR .. "/silly_05_shrink.png")
      end
      break
    end

    -- track which injected beats we hit + screenshot once each
    if speech and speech.steps and speech.step then
      local cur = speech.steps[speech.step]
      if cur then
        if cur.id == "silly_toast_kid" then
          saw.toast_kid = true
          if not shot.toast_kid then
            shot.toast_kid = true
            U.shot(game, DIR .. "/silly_04_toast_kid.png")
          end
        end
        if cur.id == "silly_mew" then
          saw.mew = true
          if not shot.mew then
            shot.mew = true
            U.shot(game, DIR .. "/silly_04b_mew.png")
          end
        end
        if cur.id == "silly_snack" then saw.snack = true end
        if cur.id == "silly_trust" then saw.trust = true end
        if cur.id == "silly_pineapple" then saw.pineapple = true end
      end
    end

    if isChoiceBox(s) then
      -- YES/NO: move to desired row then A
      local want
      local cur = speech and speech.steps and speech.steps[speech.step]
      if cur and cur.id == "silly_toast" then
        want = picks.toast
        toastAnswered = true
      elseif cur and cur.id == "silly_pineapple" then
        want = picks.pineapple
        pineappleAnswered = true
      else
        want = 1
      end
      if s.index ~= want then
        U.tap(game, "down")
        U.wait(2)
      end
      U.tap(game, "a")
      U.wait(4)
    elseif isMenu(s) and not isNaming(s) then
      -- multi choice or naming presets
      local cur = speech and speech.steps and speech.steps[speech.step]
      local want = 1
      if cur and cur.id == "silly_snack" then
        want = picks.snack
        snackPicked = true
        if not shot.snack then
          shot.snack = true
          U.shot(game, DIR .. "/silly_02_snack.png")
        end
      elseif cur and cur.id == "silly_trust" then
        want = picks.trust
        trustPicked = true
        if not shot.trust then
          shot.trust = true
          U.shot(game, DIR .. "/silly_03_trust.png")
        end
      elseif s.items and s.items[1] and s.items[1].label == "NEW NAME" then
        -- naming preset menu: pick first preset (row 2)
        want = 2
      end
      while s.index < want do
        U.tap(game, "down")
        U.wait(2)
        s = top()
        if not isMenu(s) then break end
      end
      U.tap(game, "a")
      U.wait(4)
    else
      U.tap(game, "a")
      U.wait(2)
    end

    if game.overworld and top() == game.overworld then break end
  end

  -- finish shrink + land in overworld
  for _ = 1, 150 do
    if game.overworld and top() == game.overworld then break end
    U.wait(1)
  end
  U.wait(10)
  U.shot(game, DIR .. "/silly_06_overworld.png")

  local bucket = (game.save and game.save.modData
                  and game.save.modData.example_silly_oak)
              or (game.mods and game.mods.modSave
                  and game.mods.modSave.example_silly_oak)
              or {}

  U.log("saw toast_kid:", tostring(saw.toast_kid),
        "mew:", tostring(saw.mew),
        "snack:", tostring(saw.snack),
        "trust:", tostring(saw.trust),
        "pineapple:", tostring(saw.pineapple),
        "shrink:", tostring(saw.shrink))
  U.log("answers:",
        "likes_toast=", tostring(bucket.likes_toast),
        "snack=", tostring(bucket.snack),
        "trusts_rival=", tostring(bucket.trusts_rival),
        "pineapple=", tostring(bucket.pineapple_on_pizza),
        "quiz_done=", tostring(bucket.quiz_done))
  U.log("player=", game.save and game.save.player and game.save.player.name,
        "rival=", game.save and game.save.player and game.save.player.rival)
  U.log("top:", topName(),
        "map:", game.overworld and game.overworld.map
                and game.overworld.map.id or "?")

  local function need(cond, msg)
    if not cond then U.log("FAIL:", msg) else U.log("ok:", msg) end
  end
  need(saw.toast_kid, "custom Toast Kid sprite beat ran")
  need(saw.mew, "MEW sprite beat ran")
  need(saw.snack or snackPicked, "snack choice ran")
  need(saw.trust or trustPicked, "rival trust choice ran")
  need(saw.pineapple or pineappleAnswered, "pineapple yes/no ran")
  need(bucket.likes_toast == true, "likes_toast saved true")
  need(bucket.snack == "OLD ROD", "snack saved OLD ROD")
  need(bucket.trusts_rival == false, "trusts_rival saved false")
  need(bucket.pineapple_on_pizza == false, "pineapple saved false")
  need(bucket.quiz_done == true, "quiz_done set")
  need(game.overworld and top() == game.overworld, "landed in overworld")
end

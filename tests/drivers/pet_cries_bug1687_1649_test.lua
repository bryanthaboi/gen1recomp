-- Talks to all six pet Pokemon for you and lets each one cry: #1687
-- (S.S. Anne WIGGLYTUFF + MACHOKE) and #1649 (Vermilion PIDGEY, Vermilion
-- City MACHOP, Fan Club PIKACHU + SEEL).  pokered/scripts/*.asm, e.g.
-- VermilionPidgeyHouse.asm:15 text_far then PlayCry at :19.  Never add
-- POKEPORT_SPEED: only the logic clock scales, so the cry lands in the
-- wrong place relative to the typing this run exists to judge.
--   POKEPORT_DRIVER=tests/drivers/pet_cries_bug1687_1649_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=red POKEPORT_IDENTITY=petcries SHOT_DIR=/tmp/petcries love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local Runtime = require("src.mods.Runtime")
  local GameVersion = require("src.core.GameVersion")
  local init = require("data.scripts.init")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local yellow = GameVersion.isYellow()
  local failures = 0

  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- own tick counter: the ordering claim is "cry after the last character",
  -- so the cry and the end of typing have to be stamped on the same clock
  local ticks = 0
  local function step() ticks = ticks + 1; coroutine.yield() end
  local function waitTicks(n) for _ = 1, n do step() end end
  local function tap(btn) U.tap(game, btn); ticks = ticks + 1 end

  -- sound.played is the engine's own cue feed (src/core/Sound.lua played()),
  -- which is the only way a script can tell "no cry" from "a cry nobody
  -- could hear"; both sound identical on a quiet machine.
  local cries = {}
  local heard = false
  if type(Runtime.events.on) == "function" then
    Runtime.events:on("sound.played", function(p)
      if p and p.kind == "cry" then
        heard = true
        cries[#cries + 1] = { name = p.name, species = p.species, tick = ticks }
      end
    end, 0, "driver")
  end

  -- pokered/data/maps/objects, all cell coordinates: VermilionPidgeyHouse
  -- PIDGEY (3,5), VermilionCity MACHOP (29,9), PokemonFanClub PIKACHU (6,4)
  -- and SEEL (1,4), SSAnne1FRooms WIGGLYTUFF (3,11), SSAnneB1FRooms MACHOKE
  -- (11,12).  The two S.S. Anne rooms maps slide their objects between
  -- cabins at load (src/world/SsAnneLayout.lua), so every position below is
  -- read back off the live map instead of trusted from the list.
  local PETS = {
    { map = "VERMILION_PIDGEY_HOUSE", object = "VERMILIONPIDGEYHOUSE_PIDGEY",
      const = "TEXT_VERMILIONPIDGEYHOUSE_PIDGEY", species = "PIDGEY",
      label = "_VermilionPidgeyHousePidgeyText",
      control = "VERMILIONPIDGEYHOUSE_YOUNGSTER" },
    { map = "SS_ANNE_1F_ROOMS", object = "SSANNE1FROOMS_WIGGLYTUFF",
      const = "TEXT_SSANNE1FROOMS_WIGGLYTUFF", species = "WIGGLYTUFF",
      label = "_SSAnne1FRoomsWigglytuffText",
      control = "SSANNE1FROOMS_LITTLE_GIRL" },
    { map = "SS_ANNE_B1F_ROOMS", object = "SSANNEB1FROOMS_MACHOKE",
      const = "TEXT_SSANNEB1FROOMS_MACHOKE", species = "MACHOKE",
      label = "_SSAnneB1FRoomsMachokeText" },
    { map = "POKEMON_FAN_CLUB", object = "POKEMONFANCLUB_SEEL",
      const = "TEXT_POKEMONFANCLUB_SEEL", species = "SEEL",
      label = "_PokemonFanClubSeelText" },
    -- two boxes, cry on the first (VermilionCity.asm:224, PlayCry at :228)
    { map = "VERMILION_CITY", object = "VERMILIONCITY_MACHOP",
      const = "TEXT_VERMILIONCITY_MACHOP", species = "MACHOP",
      label = "_VermilionCityMachopText", extraBoxes = 1 },
  }
  if yellow then
    -- pokeyellow/data/maps/objects/PokemonFanClub.asm: the pet is a CLEFAIRY
    PETS[#PETS + 1] = { map = "POKEMON_FAN_CLUB",
      object = "POKEMONFANCLUB_CLEFAIRY",
      const = "TEXT_POKEMONFANCLUB_CLEFAIRY", species = "CLEFAIRY",
      label = "_PokemonFanClubClefairyText" }
  else
    PETS[#PETS + 1] = { map = "POKEMON_FAN_CLUB",
      object = "POKEMONFANCLUB_PIKACHU",
      const = "TEXT_POKEMONFANCLUB_PIKACHU", species = "PIKACHU",
      label = "_PokemonFanClubPikachuText" }
  end

  -- ---------------------------------------------------------------- checks
  -- Everything below produces the same silence the bug did, so it is worth
  -- knowing before anyone bothers listening.
  local vol = game.save and game.save.options and game.save.options.sfxVol
  U.log("sfx volume is", tostring(vol), "of 7")
  if not vol or vol == 0 then
    check("sfx volume is above zero (a muted run sounds exactly like the bug)",
          false)
  end
  if yellow and game.save.options.pikaVol == 0 then
    U.log("pikaVol is 0: Yellow's Pikachu clips are muted independently")
  end

  for _, pet in ipairs(PETS) do
    local tag = pet.species .. " on " .. pet.map
    local script = init.talkScript(pet.map, pet.const)
    if check(tag .. " has a ported talk script", type(script) == "table") then
      local cryAt
      for i, row in ipairs(script) do
        if type(row) == "table" and row[1] == "play_cry" then cryAt = i end
      end
      if check(tag .. " has a play_cry row", cryAt ~= nil) then
        check(tag .. " cries " .. pet.species, script[cryAt][2] == pet.species)
        check(tag .. " uses the waitForButton form", script[cryAt][3] == true)
        local next_ = script[cryAt + 1]
        check(tag .. " arms " .. pet.label .. " on the very next row",
              type(next_) == "table" and next_[1] == "show_text"
                and next_[2] == pet.label)
      end
    end
    check(tag .. " has a cry program in this cache",
          game.data.audio.cries and game.data.audio.cries[pet.species] ~= nil)
    check(pet.label .. " resolves to text",
          type(game.data.text[pet.label]) == "string")
  end

  -- Sound.playCry sends PIKACHU to the PCM clips whenever the cache carries
  -- them; that voiced "Pikachuuu" is Yellow's, and hearing it in Red is the
  -- failure #1649 warned about up front.
  if not yellow then
    check("this cache has no Pikachu voice clips (Red must get the chip cry)",
          game.data.audio.pikaCries == nil)
  end

  if failures > 0 then
    U.log(failures, "checks failed above, so do not bother listening yet;")
    U.log("a missing row or an unresolved label sounds exactly like the bug.")
  end

  -- ---------------------------------------------------------------- walking
  local function findNpc(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- {dx, dy, facing}: the offset from the pet to the cell to stand on plus
  -- the direction that looks back at it, so +1 on y means stand below.
  local SIDES = {
    { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
  }

  local function approach(ow, npc)
    for _, s in ipairs(SIDES) do
      local cx, cy = npc.cellX + s[1], npc.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        return cx, cy, s[3]
      end
    end
    return nil
  end

  -- PIDGEY and MACHOP are WALK objects and drift off their spawn cell, so
  -- pin them once the final teleport has rebuilt the npc list.
  local function pin(npc)
    npc.wanders = false
    npc:resetToSpawn()
    npc.wanders = false
  end

  local function standAt(mapId, objName)
    local def
    for _, o in ipairs((game.data.maps[mapId] or {}).objects or {}) do
      if o.name == objName then def = o end
    end
    if not def then return nil end
    -- first hop just mounts the map so the live cells can be read
    U.teleport(game, mapId, def.x, math.max(0, def.y + 1), "up")
    waitTicks(6)
    local ow = game.overworld
    local npc = ow and findNpc(ow, objName)
    if not npc then return nil end
    pin(npc)
    local cx, cy, facing = approach(ow, npc)
    if not cx then return nil end
    U.teleport(game, mapId, cx, cy, facing)
    waitTicks(6)
    ow = game.overworld
    npc = findNpc(ow, objName)
    if not npc then return nil end
    pin(npc)
    local fx, fy = ow.player:facingCell()
    if ow:npcAtCell(fx, fy) ~= npc then return nil end
    return npc
  end

  -- Opens the box, holds still while it types and cries, then reports where
  -- the cry landed against the last typed character.
  local function talk(name)
    local before = #cries
    tap("a")
    local box, armed, doneTick
    for _ = 1, 300 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then
        box = top
        -- box.auto is cleared the moment the cry finishes, so snapshot it
        if armed == nil then armed = top.auto or false end
        if top.done and not doneTick then doneTick = ticks end
      end
      if doneTick and #cries > before then break end
      step()
    end
    if not check(name .. ": pressing A opened a text box", box ~= nil) then
      return nil
    end
    local lines = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    U.log("box reads:", table.concat(lines, " / "))
    return box, armed, doneTick, before
  end

  U.log("about to walk to each pet and talk to it; turn the volume up now.")
  waitTicks(180)

  for _, pet in ipairs(PETS) do
    local tag = pet.species .. " on " .. pet.map
    U.log("walking to the", pet.species)
    local npc = standAt(pet.map, pet.object)
    if not check(tag .. ": standing face to face with it", npc ~= nil) then
      U.log("skipping", pet.species, "-- could not reach it")
    else
      local box, armed, doneTick, before = talk(tag)
      if box then
        -- the dropped `true` shows up here: without it the box pops itself
        -- when the cry ends and never blinks its arrow
        check(tag .. ": the box was armed with a cry",
              type(armed) == "table" and type(armed.sound) == "function")
        check(tag .. ": the cry keeps the A/B wait (waitForButton)",
              type(armed) == "table" and armed.wait == true)
        local fired = cries[before + 1]
        if check(tag .. ": a cry actually played", fired ~= nil) then
          check(tag .. ": the cry was " .. pet.species,
                fired.species == pet.species)
          -- near miss: a cry that fires as the line starts typing
          check(tag .. ": it played after the last character, not before",
                doneTick ~= nil and fired.tick >= doneTick)
          if pet.species == "PIKACHU" and not yellow then
            check("PIKACHU used the chip cry, not Yellow's voice clip",
                  fired.name == "PIKACHU")
          end
          check(tag .. ": exactly one cry for this box",
                #cries == before + 1)
        end
        waitTicks(90)
        U.shot(game, SHOT_DIR .. "/pet_cry_" .. pet.species:lower() .. ".png")
        check(tag .. ": the box is still up waiting for A",
              getmetatable(game.stack:top()) == TextBox)
        for _ = 1, (pet.extraBoxes or 0) + 1 do
          tap("a")
          waitTicks(40)
        end
        if pet.extraBoxes then
          U.log("the MACHOP's second box is the stomping line; it has no cry")
        end
        waitTicks(30)
      end
    end

    -- a neighbour that is meant to stay silent, so a run with no audio
    -- device at all cannot pass itself off as a working cry
    if pet.control then
      local silent = standAt(pet.map, pet.control)
      if silent then
        local mark = #cries
        talk(pet.control .. " (control)")
        check(pet.control .. ": the silent neighbour played no cry",
              #cries == mark)
        tap("a")
        waitTicks(30)
        tap("a")
        waitTicks(20)
      end
    end
  end

  -- ---------------------------------------------------------------- verdict
  U.log("talked to all", #PETS, "pets;", #cries, "cries fired.")
  if not heard then
    U.log("no cry reached the mixer at all, which is the #1687 / #1649 bug")
  end
  U.log(failures == 0 and "all checks passed" or (failures .. " checks FAILED"))
  U.log("what you should have heard, once per pet: the box types the line,")
  U.log("then a short cry, and only then the down arrow starts blinking.")
  U.log("a cry that starts while the line is still typing is wrong, and so")
  U.log("is a box that closes itself when the cry ends instead of waiting.")
  U.log("in Red the Fan Club PIKACHU is a short chip cry; the long voiced")
  U.log("\"Pikachuuu\" belongs to Yellow, where the pet is a CLEFAIRY.")
  U.log("re-run with POKEPORT_VERSION=blue and POKEPORT_VERSION=yellow.")
  U.log("screenshots are in", SHOT_DIR)

  -- parked in front of the last pet, so another A press repeats its cry
  while true do
    coroutine.yield()
  end
end

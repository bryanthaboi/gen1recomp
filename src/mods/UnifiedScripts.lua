local UnifiedScripts = {}
local unpack = table.unpack or unpack
local ALIASES = { text = "show_text", setflag = "set_flag", clearflag = "clear_flag" }
local DIRS = { up = true, down = true, left = true, right = true }
local ARITY = {
  label = 2, jump = 2, jump_if_true = 2, jump_if_false = 2, ["end"] = 1,
  wait = 2, wait_flag = 3, check_flag = 2, set_flag = 2, clear_flag = 2,
  check_item = 2, check_money = 2, check_dex_owned = 2, check_battle_result = 5,
  set_field = 3, set_option = 3, give_money = 2, take_money = 2, take_coins = 2,
  give_item = 7, take_item = 3, heal_party = 1, mark_seen = 2,
  ask = 3, choice = 3, show_text = 4, warp = 5, start_battle = 4,
  move_player = 3, move_npc = 4, move_npc_to = 4, face = 2,
  face_object = 4, face_npc = 1, face_player = 1, face_player_dir = 2,
  place_npc = 5, show_object = 3, hide_object = 3, replace_block = 4,
  play_sound = 2, play_music = 3, stop_music = 1, play_cry = 3, give_pokemon = 5,
  open_mart = 2, static_battle = 4, remember_outdoor = 4,
  play_once = 2, text_sound = 2, wait_sound = 1, engage_music = 2,
  fade_music = 2, play_default_music = 1,
}
local ADAPTED = {
  emote = { 4, [2] = true, [3] = true },
  fade = { 3, [2] = true, [3] = true },
  walk_npc = { 4, [2] = true, [3] = true },
  text_opts = { 2, [2] = true, [3] = true },
  pan_camera = { 4, [3] = true },
  push_screen = { 3, [2] = true, [3] = true },
  trade = { 3, [2] = true, [3] = true },
  march_in_place = { 3, [3] = true },
}
local BUBBLES = {
  [2] = { shock = 0, question = 1, happy = 2 },
  [3] = { shock = "exclamation", question = "question", happy = "smile" },
}

local function pack(...) return { n = select("#", ...), ... } end
local function integer(value, low, high)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value % 1 == 0
    and (not low or value >= low) and (not high or value <= high)
end
local function name(value)
  return type(value) == "string" and #value > 0 and #value <= 256 and not value:find("%c")
end
local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for k, v in pairs(value) do result[copy(k, seen)] = copy(v, seen) end
  return result
end
local function expect(ok, reason)
  if not ok then error(reason or "script operation failed", 0) end
  return ok
end

function UnifiedScripts.new(env)
  local req = env.req or require
  local generation, version, modId = env.generation, env.version, env.modId
  local queued
  local function g3(module) return req("src.core.game3." .. module) end

  local function nativeId(game, value, kind)
    local data = game.data or {}
    if generation == 3 then
      local compat = req("src.mods.Gen3Compat")
      local id
      if kind == "species" then id = compat.speciesId(value) else id = compat.itemId(value) end
      local source = kind == "species" and g3("pokemon") or g3("items_data")
      if not id and type(value) == "string" then
        local selected = { gen3Pokemon = g3("pokemon"), gen3Items = g3("items_data") }
        id = req("src.mods.UnifiedRecords").nativeId(value, kind, generation, selected)
      end
      local rows = kind == "species" and source._names or source._byId
      if not integer(id, 1, 65535) or not rows or not rows[id] then
        return nil, "unknown " .. kind .. ": " .. tostring(value)
      end
      return id
    end
    local rows = kind == "species" and data.pokemon or data.items
    if type(value) == "number" then
      if not integer(value, 1, 65535) then return nil, "invalid " .. kind end
      for key, def in pairs(rows or {}) do
        if type(def) == "table" and (def.index == value or def.id == value
            or (kind == "species" and def.dex == value)) then return key end
      end
      return nil, "unknown native " .. kind .. " id: " .. tostring(value)
    end
    return req("src.mods.UnifiedRecords").nativeId(value, kind, generation, data)
  end

  local function command(game, verb)
    local Commands = req("src.script.Commands")
    local fn, meta = Commands.resolve(game.data, verb)
    if fn and fn ~= Commands[verb] then return fn, meta, true end
    if generation == 1 then return fn, meta, false end
  end

  local function entity(ow, ref)
    if generation == 3 then
      if ref == "player" then return g3("player"), 0xFF end
      local Objects = g3("objects")
      local id = ref
      if type(ref) == "string" then
        for _, def in ipairs(Objects._defs or {}) do
          if def.name == ref or def.id == ref then id = def.localId or def.index; break end
        end
      end
      return Objects.find(id), id
    end
    if ref == "player" then return ow.player, 0 end
    if generation == 2 then return ow:objectEntity(ref), ref end
    return ow:npcByIndex(ref), ref
  end

  local function trainer(game, ow, a, b)
    if generation == 1 then
      local def = game.data and game.data.trainers and game.data.trainers[a]
      if def and def.parties and def.parties[b or 1] then return def end
    elseif generation == 2 then
      return ow:trainerParty(a, b)
    else
      local Trainers = g3("scripting.trainers")
      local id = tonumber(a)
      if not id and type(a) == "string" then
        local constants = g3("constants").of(version)
        local rows = constants.trainers
        id = rows and rows.byName and (rows.byName[a] or rows.byName["TRAINER_" .. tostring(a)])
      end
      local def = id and Trainers.get(id)
      if def and def.party and #def.party > 0 then return def, id end
    end
    return nil, "trainer content unavailable: " .. tostring(a)
  end

  local function mart(game, ow, ref, def)
    local data = game.data or {}
    def = def or ow.map and ow.map.def
    local ok, entry = pcall(function()
      if type(data.textEntry) == "function" and def and def.label then
        return data:textEntry(def.label, ref)
      end
    end)
    expect(ok and type(entry) == "table" and type(entry.mart) == "table"
      and #entry.mart > 0, "native mart content unavailable: " .. tostring(ref))
    if generation == 1 then return entry.mart end
    local items = {}
    for i, item in ipairs(entry.mart) do
      local id, err = nativeId(game, item, "item")
      items[i] = expect(id, err)
    end
    return items
  end

  local function audioId(value)
    if generation == 3 and value == "Get_Item1" then
      return g3("audio").role("obtainItem") or "MUS_OBTAIN_ITEM"
    end
    return value
  end

  local function preflight(game, api, rows, extra)
    expect(type(rows) == "table" and (extra == nil or type(extra) == "table"),
      "invalid script rows or options")
    for key, value in pairs(extra or {}) do
      expect(key == "onDone" and type(value) == "function", "invalid script option")
    end
    local count, entries = #rows, 0
    expect(count <= 1024, "too many script rows")
    for key in pairs(rows) do
      expect(integer(key, 1, count), "invalid script row list")
      entries = entries + 1
    end
    expect(entries == count, "invalid script row list")
    local snapshot, labels, plans = copy(rows), {}, {}
    local ow = api:overworld()
    expect(ow, "no overworld")
    local warped, map = false, ow.map and ow.map.def
    for i, row in ipairs(snapshot) do
      expect(type(row) == "table" and type(row[1]) == "string", "invalid script row")
      local verb = ALIASES[row[1]] or row[1]
      row[1] = verb
      local fn, meta, custom = command(game, verb)
      local adapted = generation ~= 1 and ADAPTED[verb] and ADAPTED[verb][generation] and ADAPTED[verb]
      expect(ARITY[verb] or adapted or fn, (req("src.script.Commands")[verb]
        and "native content adapter unavailable: " or "unsupported script command: ") .. verb)
      local limit = custom and 64 or ARITY[verb] or adapted and adapted[1] or 64
      for key in pairs(row) do
        expect(integer(key, 1, limit), "invalid script row option: " .. verb)
      end
      local p = { fn = fn, meta = meta, custom = custom }
      plans[i] = p
      local a, b, c, d = row[2], row[3], row[4], row[5]
      if verb == "label" then
        expect(name(a) and labels[a] == nil, "invalid or duplicate script label: " .. tostring(a))
        labels[a] = i
      elseif custom then
      elseif verb == "warp" then
        local ok, err = env.warpArgs(game, a, b, c, d)
        expect(ok, err)
        warped, map = true, env.mapDef(game, a)
      elseif verb == "remember_outdoor" then
        local ok, err = env.warpArgs(game, a, b, c)
        expect(ok, err)
      elseif verb == "open_mart" then
        expect(name(a) or integer(a, 0), "invalid mart text constant")
        mart(game, ow, a, map)
        if generation == 2 then expect(type(ow.openMart) == "function", "native mart adapter unavailable")
        elseif generation == 3 then expect(type(req("src.ui.game3.shop_menu").show) == "function", "native mart adapter unavailable") end
      elseif verb == "start_battle" or verb == "static_battle" then
        if verb == "static_battle" then
          if c ~= nil then local id, err = env.flagId(c); expect(id ~= nil, err) end
          a, b, c = "wild", a, b
        end
        expect(a == "wild" or a == "trainer", "invalid script battle")
        if a == "wild" then
          p.species = expect(nativeId(game, b, "species"), "unknown battle species")
          expect(integer(c, 1, 100), "invalid battle level")
          local ids = game.data or {}
          if generation == 3 then ids = setmetatable({ gen3Pokemon = g3("pokemon") }, { __index = ids }) end
          p.publicSpecies = type(b) == "string" and b
            or req("src.mods.UnifiedRecords").id(p.species, "species", generation, ids)
        else
          local def, id = trainer(game, ow, b, c)
          p.trainer, p.trainerId = expect(def, id), id
        end
      elseif verb == "set_flag" or verb == "clear_flag" or verb == "wait_flag" then
        local id, err = env.flagId(a)
        expect(id ~= nil, err)
        local save = env.saveOf(game)
        if type(a) == "string" and a:match("^mod[:%.]") then
          expect(save and (save.modData == nil or type(save.modData) == "table"), "invalid mod save store")
          local bucket = save.modData and save.modData[modId]
          expect(bucket == nil or type(bucket) == "table", "invalid mod save store")
          expect(not bucket or bucket.worldFlags == nil or type(bucket.worldFlags) == "table", "invalid mod flag store")
        end
        expect(verb ~= "wait_flag" or b == nil or integer(b, 0), "invalid flag timeout")
      elseif verb == "check_flag" then
        local private = type(a) == "string" and a:match("^mod:(.+)$")
        if private then expect(name(private), "invalid mod field")
        else local id, err = env.flagId(a); expect(id ~= nil, err) end
      elseif verb == "wait" then
        expect(integer(a, 0), "invalid wait frames")
      elseif verb == "show_text" or verb == "ask" then
        expect(type(a) == "string" and #a <= 65536, "invalid script text")
        expect(b == nil or type(b) == "table", "invalid text substitutions")
        for token, value in pairs(b or {}) do
          expect(name(token) and (type(value) == "string" or type(value) == "number"),
            "invalid text substitution")
        end
        expect(c == nil or generation == 1 and type(c) == "table", "native text options adapter unavailable")
      elseif verb == "choice" then
        expect(type(a) == "table" and #a > 0 and #a <= 64, "invalid choice labels")
        for key, value in pairs(a) do
          expect(integer(key, 1, #a) and type(value) == "string", "invalid choice label")
        end
        expect(b == nil or type(b) == "table", "invalid choice options")
        for key, value in pairs(b or {}) do
          expect((key == "default" or key == "cancel") and integer(value, 1, #a),
            "invalid choice option")
        end
      elseif verb == "set_field" or verb == "set_option" then
        expect(name(a) and not a:match("^mod%."), "invalid or foreign script field")
        expect(not a:find(":", 1, true) or a:match("^mod:.+"), "foreign script field")
        expect(a ~= "mod:", "invalid mod field")
        local save = env.saveOf(game)
        if a:match("^mod:") then
          expect(save and (save.modData == nil or type(save.modData) == "table"), "invalid mod save store")
          local bucket = save.modData and save.modData[modId]
          expect(bucket == nil or type(bucket) == "table", "invalid mod save store")
        end
      elseif verb == "give_money" or verb == "take_money" or verb == "take_coins"
          or verb == "check_money" or verb == "check_dex_owned" then
        expect(a == nil and verb == "check_dex_owned" or integer(a, 0), "invalid script amount")
      elseif verb == "give_item" or verb == "take_item" or verb == "check_item" then
        local id, err = nativeId(game, a, "item")
        p.item = expect(id, err)
        expect(b == nil or integer(b, 1, 999), "invalid item count")
        if verb == "give_item" then
          expect(c == nil or c == false or type(c) == "string", "invalid gift text")
          expect(d == nil or type(d) == "string", "invalid bag full text")
        end
      elseif verb == "give_pokemon" or verb == "mark_seen" or verb == "play_cry" then
        local id, err = nativeId(game, a, "species")
        p.species = expect(id, err)
        if verb == "give_pokemon" then
          expect(integer(b, 1, 100), "invalid gift level")
          expect(c == nil or type(c) == "boolean", "invalid nickname option")
          expect(d == nil or type(d) == "boolean", "invalid gift text option")
        elseif verb == "play_cry" then
          expect(b == nil or type(b) == "boolean", "invalid cry button option")
        end
      elseif verb == "check_battle_result" then
        for n = 2, #row do
          expect(row[n] == "win" or row[n] == "lose" or row[n] == "run" or row[n] == "caught",
            "invalid battle result")
        end
      elseif verb == "move_player" or verb == "move_npc" then
        local dir, tiles = a, b
        if verb == "move_npc" then
          expect((name(a) or integer(a, 0)) and (warped or entity(ow, a)), "native NPC unavailable")
          dir, tiles = b, c
        end
        expect(DIRS[dir] and (tiles == nil or integer(tiles, 0, 1024)), "invalid script movement")
      elseif verb == "move_npc_to" or verb == "place_npc" then
        expect((name(a) or integer(a, 0)) and (warped or entity(ow, a))
          and integer(b, 0) and integer(c, 0), "invalid NPC position")
        expect(d == nil or DIRS[d], "invalid NPC facing")
      elseif verb == "face_object" then
        expect((name(a) or integer(a, 0)) and (warped or entity(ow, a)) and DIRS[b], "invalid object facing")
        expect(c == nil or type(c) == "table", "invalid facing options")
      elseif verb == "face" or verb == "face_player_dir" then
        expect(DIRS[a], "invalid facing")
        if verb == "face" then expect(ow.talkNpc or ow.runner and ow.runner.ctx and ow.runner.ctx.npc,
          "script NPC unavailable") end
      elseif verb == "face_npc" or verb == "face_player" then
        expect(ow.talkNpc or ow.runner and ow.runner.ctx and ow.runner.ctx.npc, "script NPC unavailable")
      elseif verb == "show_object" or verb == "hide_object" then
        local def = env.mapDef(game, a)
        expect(def and (name(b) or integer(b, 0)), "invalid script object")
        local found = false
        for _, obj in pairs(def.objects or {}) do
          if obj.name == b or obj.id == b or obj.index == b or obj.localId == b then found = true; break end
        end
        expect(found, "native object unavailable: " .. tostring(b))
      elseif verb == "replace_block" then
        expect(integer(a, 0) and integer(b, 0) and integer(c, 0), "invalid script block")
        local location = api:current()
        local def = map or location and env.mapDef(game, location.mapId)
        local layout = generation == 3 and def and def.midLayout or def
        if generation == 3 then
          local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
          local ok, err = g3("mod_layout").checkMetatile(pair, c)
          expect(ok, err)
        end
        expect(layout and (not layout.width or a < layout.width)
          and (not layout.height or b < layout.height), "script block coordinates out of bounds")
      elseif verb == "fade_music" then
        expect(a == nil or integer(a, 0), "invalid music fade")
      elseif verb == "play_sound" or verb == "play_music" or verb == "play_once"
          or verb == "text_sound" or verb == "engage_music" then
        expect(name(a) or integer(a, 0), "invalid audio id")
        expect(b == nil or type(b) == "table", "invalid music options")
        if generation == 3 then
          local Audio = g3("audio")
          expect(Audio.songInfo(audioId(a)) or Audio.resolveSong(audioId(a)), "native audio unavailable: " .. tostring(a))
        else
          local audio = game.data and game.data.audio
          local rows = audio and ((verb == "play_music" or verb == "play_once"
            or verb == "engage_music") and audio.songs or audio.sfx)
          expect(rows and rows[a], "native audio unavailable: " .. tostring(a))
        end
      elseif adapted then
        if verb == "emote" then
          expect(a == "player" or (name(a) or integer(a, 0)) and (warped or entity(ow, a)),
            "native emote target unavailable")
          expect(BUBBLES[generation][b] ~= nil, "invalid emote bubble")
          expect(c == nil or integer(c, 1, 3600), "invalid emote frames")
        elseif verb == "fade" then
          expect(a == "out" or a == "in", "invalid fade direction")
          expect(b == nil or b == "black" or b == "white", "invalid fade color")
        elseif verb == "walk_npc" then
          expect(a == "player" or (name(a) or integer(a, 0)) and (warped or entity(ow, a)),
            "native NPC unavailable")
          expect(type(b) == "table" and #b <= 1024, "invalid script movement")
          for key, dir in pairs(b) do
            expect(integer(key, 1, #b) and DIRS[dir], "invalid script movement")
          end
          expect(c == nil or type(c) == "table", "invalid walk options")
          for key, value in pairs(c or {}) do
            expect(key == "wait" and type(value) == "boolean", "invalid walk option")
          end
        elseif verb == "text_opts" then
          expect(type(a) == "table" and a.auto == true, "invalid text options")
          for key in pairs(a) do expect(key == "auto", "native text option unavailable: " .. tostring(key)) end
        elseif verb == "pan_camera" then
          if a == "reset" then expect(b == nil and c == nil, "invalid camera reset")
          else
            expect(integer(a, -64, 64) and integer(b, -64, 64) and c == nil, "invalid camera pan")
          end
          expect(type(g3("camera_object").spawn) == "function", "native camera adapter unavailable")
        elseif verb == "push_screen" then
          expect(name(a), "invalid screen")
          expect(b == nil or type(b) == "table", "invalid screen arguments")
          if generation == 3 then
            expect(game.data.screens and game.data.screens[a], "native screen unavailable: " .. tostring(a))
            expect(type(req("src.ui.game3.mod_ui").push) == "function", "native screen adapter unavailable")
          else
            expect(game.data.screens and game.data.screens[a] or pcall(req("src.ui.Screens").get, game, a),
              "native screen unavailable: " .. tostring(a))
          end
        elseif verb == "trade" then
          expect(integer(a, 0) and b == nil, "invalid native trade")
          if generation == 3 then
            local ok, entry = pcall(function() return g3("scripting.natives_trade").entry(a) end)
            expect(ok and entry, "native trade unavailable: " .. tostring(a))
            expect(type(g3("trade_scene").play) == "function", "native trade adapter unavailable")
          else
            expect(type(ow.openNpcTrade) == "function"
              and pcall(req("src.ui.Screens").get, game, "Gen2TradeMenu"), "native trade adapter unavailable")
          end
        elseif verb == "march_in_place" then
          expect((name(a) or integer(a, 0)) and (warped or entity(ow, a)), "native NPC unavailable")
          expect(type(b) == "boolean", "invalid march option")
          local Objects = g3("objects")
          expect(type(Objects.setWalkInPlace) == "function" and (Objects.walkInPlaceType("down")
            or Objects.walkInPlaceType("up")), "native walk-in-place unavailable")
        end
        if verb == "walk_npc" or verb == "pan_camera" then
          expect(generation == 3 and type(g3("objects").applyMovement) == "function"
            or generation == 2 and type(ow.beginMovement) == "function", "native movement adapter unavailable")
        end
      elseif not ARITY[verb] then
        expect(fn, "native adapter unavailable: " .. verb)
        if verb == "push_screen" then
          expect(name(a), "invalid screen")
          expect(game.data.screens and game.data.screens[a] or pcall(req("src.ui.Screens").get, game, a),
            "native screen unavailable: " .. tostring(a))
        elseif verb == "trade" then
          expect(game.data.field and game.data.field.trades and game.data.field.trades[a],
            "native trade unavailable: " .. tostring(a))
        end
      end
      if not custom and generation ~= 1 then
        if verb == "give_item" or verb == "take_item" or verb == "check_item" then
          expect(generation ~= 3 or env.saveOf(game).bag, "native bag unavailable")
          expect(req(generation == 3 and "src.core.game3.bag" or "src.inventory.Bag"), "native bag unavailable")
        elseif verb == "move_player" or verb == "move_npc" or verb == "move_npc_to" then
          expect(generation == 3 and type(g3("objects").applyMovement) == "function"
            or generation == 2 and type(ow.beginMovement) == "function", "native movement adapter unavailable")
        end
      end
      if not custom then
        if verb == "show_text" or verb == "ask" then
          if generation == 3 then
            local Message = req("src.ui.game3.message")
            expect(type(Message[verb == "ask" and "showStay" or "show"]) == "function", "native message adapter unavailable")
            if verb == "ask" then expect(type(req("src.ui.game3.choice").yesNo) == "function", "native choice adapter unavailable") end
          elseif generation == 2 then
            expect(type(ow.showText) == "function" and (verb ~= "ask" or type(ow.askYesNo) == "function"),
              "native message adapter unavailable")
          end
        elseif verb == "choice" then
          expect(req(generation == 3 and "src.ui.game3.choice" or "src.ui.Menu"), "native choice adapter unavailable")
        elseif verb == "give_pokemon" then
          expect(req(generation == 3 and "src.core.game3.party"
            or generation == 2 and "src.battle.gen2.Mon" or "src.pokemon.Pokemon"), "native gift adapter unavailable")
        elseif verb == "heal_party" then
          expect(generation ~= 2 or type(ow.healParty) == "function", "native heal adapter unavailable")
          if generation == 3 then expect(type(g3("party").healAll) == "function", "native heal adapter unavailable") end
        end
      end
    end
    for _, row in ipairs(snapshot) do
      if row[1] == "jump" or row[1] == "jump_if_true" or row[1] == "jump_if_false" then
        local target = row[2]
        expect(target == "end" or target == math.huge or integer(target, 1, count)
          or type(target) == "string" and labels[target], "missing or invalid script jump target")
      end
    end
    if generation == 1 then
      local problems = req("src.script.ScriptRunner").validate(snapshot, function(verb)
        return ARITY[verb] ~= nil or command(game, verb) ~= nil
      end)
      expect(#problems == 0, table.concat(problems, "; "))
    end
    return snapshot, labels, plans
  end

  local function queue(game, api, submitted, extra)
    local checked = pack(pcall(preflight, game, api, submitted, extra))
    if not checked[1] then return nil, tostring(checked[2]) end
    local rows, labels, plans = checked[2], checked[3], checked[4]
    local runtime = req("src.mods.Runtime")
    local hooks, ow, save = runtime.hooks, api:overworld(), env.saveOf(game)
    local location = api:current()
    if not hooks or type(hooks.wrap) ~= "function" then return nil, "script continuation unavailable" end
    if not ow or not location then return nil, "no overworld" end
    if not save then return nil, "no save" end
    if queued then
      if queued:isRunning() then return nil, "a script is already running" end
      if queued then return nil, "a script is already running" end
    end
    local lockWorld = generation == 3 and api:_field() or ow
    if not lockWorld then return nil, "no overworld" end
    local previous = lockWorld._modScriptLock
    if previous and previous.isRunning then previous:isRunning() end
    if lockWorld._modScriptLock then return nil, "a script is already running" end
    local ready, reason = env.ready(game, api)
    if not ready then return nil, reason end
    local token = { game = game, ow = ow, save = save, hooks = hooks, mapId = location.mapId,
      lockWorld = lockWorld, locks = generation == 3 and lockWorld._locks or nil,
      epoch = hooks.ownerEpoch and hooks:ownerEpoch(modId), ownedUI = {} }
    local ctx, runner, finish, schedule
    token.strVars = {}
    if generation == 1 then
      local made, value = pcall(function() return req("src.script.ScriptRunner").new(game, ow) end)
      if not made then return nil, "native runner unavailable: " .. tostring(value) end
      runner = value
    else runner = {} end
    queued = token
    lockWorld._modScriptLock = token
    if generation == 3 then lockWorld.lock(token); token.locks = lockWorld._locks end

    local function report(message)
      runtime.reportError(modId, message)
    end
    local function emit(event, payload)
      if runtime.wants(event) then runtime.emit(event, payload) end
    end
    local function ownUI(fn, ...)
      local states, before = game.stack and game.stack.states, {}
      for _, state in ipairs(states or {}) do before[state] = true end
      local result = pack(pcall(fn, ...))
      for _, state in ipairs(states or {}) do
        if not before[state] then token.ownedUI[state] = true end
      end
      if not result[1] then error(result[2], 0) end
      return unpack(result, 2, result.n)
    end
    finish = function(err)
      if token.done then return end
      token.done = true
      if token.unsubscribe then
        local remove = token.unsubscribe
        token.unsubscribe, token.subscription = nil, nil
        pcall(remove)
      end
      if runner then runner.co, runner.waitingFrames, runner.waitingCheck = nil, nil, nil end
      if lockWorld._modScriptLock == token then lockWorld._modScriptLock = nil end
      if token.locks and token.locks[token] then token.locks[token] = nil end
      if generation == 3 then
        local Naming = token.naming
        if Naming and Naming._state == token.namingState then Naming.dismiss() end
        local Shop = token.shop
        if Shop and Shop._onClose == token.shopDone then
          Shop._onClose = nil
          Shop.close()
        end
        local Choice = token.choice
        if Choice and Choice.done == token.choiceDone then Choice.reset() end
        local Message = token.message
        if Message and Message._done == token.messageDone then Message.close() end
        local stack = game.stack
        if token.screen and stack and stack.top and stack:top() == token.screen then stack:pop() end
        if token.partyMenu and token.partyMenu.isOpen() then token.partyMenu.close() end
      else
        local states = game.stack and game.stack.states
        for i, state in ipairs(states or {}) do
          if token.ownedUI[state] and state.choicePushed and states[i + 1]
              and getmetatable(states[i + 1]) == req("src.ui.ChoiceBox") then
            token.ownedUI[states[i + 1]] = true
          end
        end
        local removedText = false
        for i = #(states or {}), 1, -1 do
          local state = states[i]
          if token.ownedUI[state] then
            removedText = removedText or state.text ~= nil
            table.remove(states, i)
          end
        end
        if token.ownedUI[ow.fadeOverlay] then ow.fadeOverlay = nil end
        if token.ownedUI[ow.stayedTextBox] then ow.stayedTextBox = nil; ow.textbox = nil end
        if removedText then ow.textbox = nil end
        if token.ownsChoice then ow.choicebox = nil end
        if token.moveState and ow.moveState == token.moveState then ow.moveState = nil end
        for i = #(ow.scriptMoves or {}), 1, -1 do
          if token.moves and token.moves[ow.scriptMoves[i]] then table.remove(ow.scriptMoves, i) end
        end
      end
      if queued == token then queued = nil end
      local ok, why = pcall(emit, "script.ended", { ctx = ctx, completed = err == nil })
      if not ok then report("world script event failed: " .. tostring(why)) end
      ok, why = pcall(function() if extra and extra.onDone then extra.onDone(err == nil, err) end end)
      if not ok then report("world script callback failed: " .. tostring(why)) end
    end
    token.finish = finish

    local function valid()
      if token.done then return false end
      local current, native = env.resolve()
      if queued ~= token or current ~= game or env.saveOf(current) ~= save
          or runtime.hooks ~= hooks or not native or native:overworld() ~= ow
          or lockWorld._modScriptLock ~= token
          or hooks.ownerEpoch and hooks:ownerEpoch(modId) ~= token.epoch then
        finish("world changed")
        return false
      end
      if generation == 3 and (native:_field() ~= lockWorld
          or lockWorld._session and lockWorld._session ~= save
          or g3("runtime").getSession() ~= save
          or lockWorld._locks ~= token.locks and not token.destination) then
        finish("world changed")
        return false
      end
      local live, dest = native:current(), token.destination
      if not live or live.mapId ~= token.mapId and (not dest or live.mapId ~= dest.mapId) then
        finish("world changed")
        return false
      end
      if token.subscription and hooks.chains then
        local found = false
        for _, entry in ipairs(hooks.chains["core.update"] or {}) do
          if entry.callback == token.subscription then found = true; break end
        end
        if not found then finish("script continuation removed"); return false end
      end
      return true, native, live
    end
    function token:isRunning()
      local ok, live = pcall(valid)
      if not ok then finish("world changed"); return false end
      return live == true
    end

    ctx = { game = game, overworld = ow, save = save, runner = runner,
      source = { modId = modId, mapId = token.mapId, strict = true }, mapId = token.mapId,
      npc = ow.talkNpc or ow.runner and ow.runner.ctx and ow.runner.ctx.npc }
    runner.ctx, runner.game, runner.overworld = ctx, game, ow
    function runner:isRunning() return token:isRunning() end
    function runner:yield() return coroutine.yield() end
    function runner:resume(...)
      if not token.done and not self.pending then self.pending = pack(...) end
    end
    function runner:waitFrames(frames)
      expect(integer(frames, 0), "invalid wait frames")
      self.waitingFrames = frames
      return self:yield()
    end
    local function scriptFlag(native, flagName)
      local private = type(flagName) == "string" and flagName:match("^mod:(.+)$")
      local bucket = private and save.modData and save.modData[modId]
      if bucket and bucket[private] ~= nil then return not not bucket[private] end
      return env.flag(game, native, flagName)
    end

    local function once(fn)
      local completed = false
      return function(...)
        if completed or not token:isRunning() then return end
        completed = true
        return fn(...)
      end
    end
    local function text(value, subs)
      local data = game.data or {}
      local source = generation == 3 and (data.gen3Text or data.text)
        or generation == 2 and (data.gen2Text or data.text) or data.text
      local result = (source and source[value]) or (data.text and data.text[value]) or value
      if generation == 3 and type(result) == "table" then
        local IR = g3("scripting.text_ir")
        result = IR.toSource(result, { dialect = (version == "ruby" or version == "sapphire") and "rs"
          or req("src.core.GameVersion").layout(version) },
          { named = true, nl = "\n", para = "\f", scroll = "\v" }):gsub("%%%%", "%%")
      end
      for key, replacement in pairs(subs or {}) do
        local pattern = key:gsub("(%W)", "%%%1")
        result = result:gsub("{" .. pattern .. ":?[%w_]*}", function() return tostring(replacement) end)
      end
      return result
    end
    local GEN2_GIFT_TEXT = {
      _GotMonText = "ReceivedItemText",
      _DoYouWantToNicknameText = "_AskGiveNicknameText",
      _SentToBoxText = "_BallSentToPCText",
    }
    local RSE_GIFT_TAIL = "LittlerootTown_ProfessorBirchsLab_Text_LikeYouToHavePokemon"
    local function giftText(key, monName, box)
      local data = game.data or {}
      if generation == 2 then
        local label = GEN2_GIFT_TEXT[key]
        if label and data.text and type(data.text[label]) == "string" then
          return text(label, { STRBUF = monName })
        end
        error("native gift text content unavailable: " .. key, 0)
      end
      local source = generation == 3 and (data.gen3Text or data.text) or data.text
      if source and type(source[key]) == "string" then
        return text(key, { RAM = monName, PLAYER = save.name or save.playerName or "",
          BOXMONNICKS = monName, BOXMON = monName, BOX = box or "",
          STRBUF = box or "", STRINGBUFFER = box or "" })
      end
      if generation == 3 then
        local RomText = g3("rom_text")
        if key == "_SentToBoxText" then return g3("storage").pcTransferMessage(save, monName) end
        local ctx3 = { playerName = save.name or save.playerName,
          rivalName = save.rivalName, stringVars = { monName, monName }, opponentMon1 = monName }
        if key == "_GotMonText" then
          if RomText.has("Text_PlayerObtainedTheMon") then
            return RomText.box("Text_PlayerObtainedTheMon", ctx3)
          end
          if RomText.has(RSE_GIFT_TAIL) then
            local IR = g3("scripting.text_ir")
            local whole, tail, from = RomText.ir(RSE_GIFT_TAIL), {}, 1
            for i, seg in ipairs(whole) do
              if seg.t == "para" then from = i + 1 end
            end
            for i = from, #whole do tail[#tail + 1] = whole[i] end
            return IR.toTextBox(RomText.translate(tail, ctx3, RSE_GIFT_TAIL), ctx3)
          end
        else
          for _, label in ipairs({ "Text_GiveNicknameToReceivedMon", "gText_UnusedNicknameReceivedPokemon",
              "gText_NicknameReceivedPokemon" }) do
            if RomText.has(label) then return RomText.box(label, ctx3) end
          end
        end
        if key == "_DoYouWantToNicknameText" then
          return g3("battle.battle_text").get("STRINGID_GIVENICKNAMECAPTURED", { opponentMon1 = monName })
        end
      end
      error("native gift text content unavailable: " .. key, 0)
    end
    local function show(value, subs, ask, opts)
      if generation == 1 then
        local Commands = req("src.script.Commands")
        return ownUI(ask and Commands.ask or Commands.show_text, ctx, value, subs, opts)
      end
      local body = text(value, subs)
      local cry, cryWait, sound, engage = ctx.pendingCry, ctx.pendingCryWait,
        ctx.pendingTextSound, ctx.pendingEngageMusic
      local auto = ctx.pendingTextAuto
      ctx.pendingCry, ctx.pendingCryWait, ctx.pendingTextSound, ctx.pendingEngageMusic = nil, nil, nil, nil
      ctx.pendingTextAuto = nil
      if generation == 2 then
        if cry or sound or engage or auto then
          local TextBox, Sound, Music = req("src.render.TextBox"), req("src.core.Sound"), req("src.core.Music")
          local options = { auto = { delay = 0, wait = not auto and (not cry or cryWait) or false } }
          if cry then options.auto.sound = function() return Sound.playCry(game.data, cry) end end
          if sound then options = TextBox.soundOpts(game, sound, options) end
          if engage then options.auto.afterSound = function() Music.play(game.data, engage) end end
          if ask then
            token.ownsChoice = true
            options.auto.wait = true
            options.choice = once(function(yes)
              ow.textbox = nil; ctx.lastCheck = yes; runner:resume()
            end)
          end
          ownUI(function()
            ow.textbox = true
            game.stack:push(TextBox.new(game, body, once(function()
              ow.textbox = nil; runner:resume()
            end), options))
          end)
        elseif ask then
          token.ownsChoice = true
          ownUI(function()
            ow:showText(body, once(function()
              ownUI(function() ow:askYesNo(once(function(yes)
                ctx.lastCheck = yes; runner:resume()
              end)) end)
            end), true)
          end)
        else
          ownUI(function() ow:showText(body, once(function() runner:resume() end)) end)
        end
      else
        local Message = req("src.ui.game3.message")
        expect(not Message.isOpen(), "world is busy")
        local completed = once(function() if not ask then runner:resume() end end)
        token.message = Message
        local armed = cry or sound or engage or auto
        local IR = g3("scripting.text_ir")
        body = IR.toAscii(IR.fromAscii(body), { playerName = save.name or save.playerName,
          rivalName = save.rivalName, stringVars = token.strVars })
        if ask or armed then Message.showStay(body, { done = completed })
        else Message.show(body, completed) end
        token.messageDone = Message._done
        if ask or armed then
          local started, busy = false, nil
          runner.waitingCheck = function()
            if Message.isWaiting() and (not Message._pages or Message._page == #Message._pages) then
              if not started then
                started = true
                local Audio = g3("audio")
                if cry then Audio.playCry(cry) end
                if sound then expect(Audio.playFanfare(audioId(sound)), "native text sound unavailable") end
                busy = function()
                  return cry and not Audio.isCryFinished() or sound and not Audio.isFanfareFinished()
                end
              end
              if busy() then return false end
              if engage then g3("audio").playSong(engage); engage = nil end
              runner.waitingCheck = nil
              if not ask then
                if auto or cry and not cryWait then Message.close() else Message._stay = false end
                return false
              end
              local Choice = req("src.ui.game3.choice")
              expect(not Choice.isOpen(), "world is busy")
              local callback = once(function(yes)
                ctx.lastCheck = yes
                if Message._done == token.messageDone then Message.close() end
                runner:resume()
              end)
              token.choice, token.choiceDone = Choice, callback
              Choice.yesNo(callback)
            end
            return false
          end
        end
      end
      runner:yield()
    end

    local function choose(labels, opts)
      opts = opts or {}
      local callback = once(function(index)
        ctx.lastChoice = { index = index, label = labels[index] }
        ctx.lastCheck = index == 1
        runner:resume()
      end)
      if generation == 3 then
        local Choice = req("src.ui.game3.choice")
        expect(not Choice.isOpen(), "world is busy")
        local nativeCallback = once(function(index)
          callback(index == 127 and (opts.cancel or #labels) or index + 1)
        end)
        token.choice, token.choiceDone = Choice, nativeCallback
        Choice.multi(labels, (opts.default or 1) - 1, nativeCallback)
      else
        local items = {}
        for i, label in ipairs(labels) do
          local index = i
          items[i] = { label = label, onSelect = function() callback(index) end }
        end
        local menu = req("src.ui.Menu").new(game, items, {
          onCancel = function() callback(opts.cancel or #labels) end,
        })
        menu.index = opts.default or 1
        token.ownedUI[menu] = true
        game.stack:push(menu)
      end
      runner:yield()
    end

    local function move(ref, dirs, nowait)
      local target, id = entity(ow, ref)
      expect(target, "native movement target unavailable")
      if #dirs == 0 then return end
      local callback = once(function() if not nowait then runner:resume() end end)
      if generation == 3 then
        local stream, bytes = {}, { down = 0x10, up = 0x11, left = 0x12, right = 0x13 }
        for _, dir in ipairs(dirs) do stream[#stream + 1] = bytes[dir] end
        stream[#stream + 1] = 0xFE
        g3("objects").applyMovement(id, stream, callback)
      elseif generation == 2 then
        local Movement, stream = req("src.script.gen2.Movement"), {}
        for _, dir in ipairs(dirs) do stream[#stream + 1] = Movement.stepByte(dir) end
        stream[#stream + 1] = Movement.STEP_END
        ow:beginMovement(id, stream, callback)
        token.moveState = ow.moveState
      else
        local i = 0
        local function step()
          if not token:isRunning() then return end
          i = i + 1
          if not dirs[i] then return callback() end
          ow:scriptMove(target, dirs[i], 1, step)
          token.moves = token.moves or {}
          for _, entry in ipairs(ow.scriptMoves or {}) do
            if entry.entity == target then token.moves[entry] = true end
          end
        end
        step()
      end
      if not nowait then runner:yield() end
    end

    local function pathTo(target, tx, ty)
      local map = ow.map
      local collision = generation == 3 and g3("collision") or nil
      local function walkable(x, y)
        if collision then return collision.inBounds(x, y) and collision.isWalkable(x, y) end
        return map and map.inBounds and map:inBounds(x, y) and map:isWalkableCell(x, y)
      end
      local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
      local start = key(target.cellX, target.cellY)
      local pending, previous, at = { { target.cellX, target.cellY } }, { [start] = false }, 1
      local directions = { { 0, -1, "up" }, { 0, 1, "down" }, { -1, 0, "left" }, { 1, 0, "right" } }
      while pending[at] and at <= 16384 do
        local x, y = unpack(pending[at]); at = at + 1
        if x == tx and y == ty then
          local result, k = {}, key(x, y)
          while previous[k] do
            table.insert(result, 1, previous[k][2]); k = previous[k][1]
          end
          return result
        end
        for _, dir in ipairs(directions) do
          local nx, ny = x + dir[1], y + dir[2]
          local k = key(nx, ny)
          if previous[k] == nil and walkable(nx, ny) then
            previous[k] = { key(x, y), dir[3] }; pending[#pending + 1] = { nx, ny }
          end
        end
      end
      error("native movement path unavailable", 0)
    end

    local function itemCount(id)
      if generation == 3 then return g3("bag").get(save.bag, id) end
      return save.inventory and save.inventory[id] or 0
    end
    local function gift(p, level, skipNickname, gotText)
      if generation == 1 then
        return ownUI(req("src.script.Commands").give_pokemon, ctx, p.species, level, skipNickname, gotText)
      end
      local giftData = { ctx = ctx, species = p.species, level = level, isEgg = false }
      if game.mods and game.mods.events then game.mods.events:emit("pokemon.before_give", giftData)
      else runtime.emit("pokemon.before_give", giftData) end
      if giftData.cancelled or giftData.cancel or giftData.veto or giftData.species == false then
        ctx.lastCheck = false; return
      end
      local id, err = nativeId(game, giftData.species, "species")
      expect(id, err); expect(integer(giftData.level, 1, 100), "invalid gift level")
      local speciesName = generation == 3 and g3("pokemon").name(id)
        or game.data.pokemon[id].name or id
      token.strVars[1], token.strVars[2] = speciesName, speciesName
      local received = gotText and giftText("_GotMonText", speciesName)
      local question = not giftData.nickname and not skipNickname
        and giftText("_DoYouWantToNicknameText", speciesName)
      local mon
      if generation == 3 then
        local ok, code, given, box, slot = g3("party").giveMon(save, id, giftData.level, giftData.nickname, { toPC = true })
        ctx.lastCheck, ctx.addedToParty, ctx.boxNum = ok, code == 0, box
        mon = box and g3("storage").getBoxMon(save.storage, box, slot) or given
      else
        local Mon, Boxes = req("src.battle.gen2.Mon"), req("src.core.gen2.Boxes")
        local box
        if #(save.party or {}) >= 6 then
          for i = 1, Boxes.NUM_BOXES do
            if #(save.boxes and save.boxes[i] or {}) < Boxes.MONS_PER_BOX then box = i; break end
          end
          if not box then ctx.lastCheck = false; return end
          giftText("_SentToBoxText", speciesName, box)
        end
        mon = Mon.new(game.data, id, giftData.level)
        expect(mon, "native gift constructor failed")
        Mon.stampOT(save, mon)
        if giftData.nickname then mon.nickname = giftData.nickname end
        if box then
          local storage = Boxes.box(save, box)
          storage[#storage + 1] = Boxes.enterBox(mon, game.data)
        else
          save.party = save.party or {}; req("src.pokemon.Party").add(save.party, mon)
        end
        save.pokedex = save.pokedex or { seen = {}, caught = {} }
        save.pokedex.seen = save.pokedex.seen or {}; save.pokedex.caught = save.pokedex.caught or {}
        save.pokedex.seen[id], save.pokedex.caught[id] = true, true
        ctx.lastCheck, ctx.addedToParty, ctx.boxNum = true, not box, box
      end
      if not ctx.lastCheck then return end
      game.stringBuffer = speciesName
      if received then
        local sound = "Get_Item1"
        if generation == 2 and not (game.data.audio and game.data.audio.sfx and game.data.audio.sfx[sound]) then
          sound = "Sfx_CaughtMon"
        end
        ctx.pendingTextSound = sound; show(received)
      end
      if not giftData.nickname and not skipNickname then
        show(question, nil, true)
        if ctx.lastCheck then
          local done = once(function(nick)
            if nick and #nick > 0 then mon.nickname = nick end
            runner:resume()
          end)
          if generation == 3 then
            local Naming = req("src.ui.game3.naming")
            expect(not Naming.isOpen(), "world is busy")
            token.naming = Naming
            token.namingState = Naming.open({ template = "CAUGHT_MON", maxLen = 10,
              species = id, gender = mon.gender, personality = mon.personality,
              initialText = "", seed = "", title = Naming.monTitle(speciesName), sentToPc = false,
              session = save, game = game, onDone = done })
          else
            expect(ownUI(ow.renameMon, ow, mon, done, { blank = true }), "native naming unavailable")
          end
          runner:yield()
        end
        ctx.lastCheck = true
      end
      if ctx.boxNum then
        local nick = mon.nickname and mon.nickname ~= "" and mon.nickname or speciesName
        game.boxMonNicks, game.stringBuffer = nick, tostring(ctx.boxNum)
        show(giftText("_SentToBoxText", nick, ctx.boxNum))
      end
    end

    local function adapted(verb, a, b, c)
      if verb == "text_opts" then
        ctx.pendingTextAuto = true
      elseif verb == "walk_npc" then
        local dirs = {}
        for i, dir in ipairs(b) do dirs[i] = dir end
        move(a, dirs, c and c.wait == false)
      elseif verb == "emote" then
        local frames = c or 60
        if generation == 2 then
          -- engine/overworld/scripting.asm:1065
          local _, id = entity(ow, a)
          ow:showEmote(BUBBLES[2][b], id, frames)
          expect(ow.emote, "native emote unavailable")
          runner.waitingCheck = function() return ow.emote == nil end
          runner:yield()
        else
          -- pokefirered/src/event_object_movement.c:7068
          local _, id = entity(ow, a)
          local done = once(function() runner:resume() end)
          g3("objects").startTrack(id, { { kind = "emote", emoteType = BUBBLES[3][b], frames = frames } }, done)
          runner:yield()
        end
      elseif verb == "fade" then
        local white = b == "white"
        if generation == 2 then
          -- data/events/special_pointers.asm:60
          ow:screenFade((a == "out" and "out" or "in") .. (white and "White" or "Black"))
        else
          -- pokeemerald/src/scrcmd.c:627
          local Fade = req("src.ui.game3.fade")
          local done = once(function() runner:resume() end)
          Fade.begin(a == "out" and (white and Fade.MODE.TO_WHITE or Fade.MODE.TO_BLACK)
            or (white and Fade.MODE.FROM_WHITE or Fade.MODE.FROM_BLACK), 1, done)
          runner:yield()
        end
      elseif verb == "pan_camera" then
        -- pokefirered/src/field_specials.c:318
        local Camera = g3("camera_object")
        if a == "reset" then
          Camera.remove(game)
          return
        end
        expect(Camera.spawn(game), "native camera object unavailable")
        local dirs = {}
        for _ = 1, math.abs(a) do dirs[#dirs + 1] = a < 0 and "left" or "right" end
        for _ = 1, math.abs(b) do dirs[#dirs + 1] = b < 0 and "up" or "down" end
        move(Camera.LOCALID, dirs)
      elseif verb == "march_in_place" then
        local _, id = entity(ow, a)
        expect(g3("objects").setWalkInPlace(id, b), "native walk-in-place unavailable")
      elseif verb == "push_screen" and generation == 3 then
        local state = req("src.ui.game3.mod_ui").push(game, a, b)
        token.screen = state
        runner.waitingCheck = function()
          local stack = game.stack
          if stack.top then stack:top() end
          for _, entry in ipairs(stack.entries or {}) do
            if entry.state == state then return false end
          end
          return true
        end
        runner:yield()
      elseif verb == "push_screen" then
        local stack = game.stack
        local state = ownUI(req("src.ui.Screens").push, game, a, b)
        runner.waitingCheck = function()
          for _, live in ipairs(stack.states) do
            if live == state then return false end
          end
          return true
        end
        runner:yield()
      elseif verb == "trade" and generation == 3 then
        -- pokefirered/src/trade_scene.c:2774
        local Trade, PartyMenu = g3("scripting.natives_trade"), req("src.ui.game3.party_menu")
        local rse = g3("profile").family(save) == "rse"
        local entry = Trade.entry(a)
        local picked
        local pickDone = once(function() token.partyMenu = nil; runner:resume() end)
        token.partyMenu = PartyMenu
        PartyMenu.show(save.party, nil, {
          mode = "choose", session = save,
          menuType = rse and g3("rs.party_selection").NPC_TRADE or nil,
          onSelect = function(slot)
            local s = tonumber(slot)
            if s and s >= 1 then picked = s - 1 end
          end,
          onClose = function() pickDone() end,
        })
        runner:yield()
        local mon = picked and save.party[picked + 1]
        local species = mon and tonumber(mon.species or mon.speciesId)
        if not mon or g3("pokemon").isEgg(mon) or species ~= entry.requestedSpecies then
          ctx.lastCheck = false
          return
        end
        local offered = (rse and g3("scripting.natives_rs_npc_trade") or Trade).createTradeMon(a, Trade.levelOfSlot(picked))
        expect(offered, "native trade mon unavailable")
        Trade._offered = offered
        local scene = Trade.sceneTask({ stringVars = {} }, nil, a, picked)
        runner.waitingCheck = function() return scene() end
        runner:yield()
        ctx.lastCheck = true
      elseif verb == "trade" then
        -- engine/overworld/scripting.asm:600
        local done = once(function() runner:resume() end)
        expect(ownUI(ow.openNpcTrade, ow, a, done) ~= false, "native trade unavailable")
        runner:yield()
      end
    end

    local function dispatch(row, p, native)
      local verb, a, b, c, d = row[1], row[2], row[3], row[4], row[5]
      if p.custom then return ownUI(p.fn, ctx, unpack(row, 2, #row)) end
      if generation == 1 and (verb == "open_mart" or verb == "static_battle"
          or verb == "remember_outdoor" or verb == "play_once" or verb == "text_sound"
          or verb == "wait_sound" or verb == "engage_music" or verb == "fade_music"
          or verb == "play_default_music") then
        return ownUI(req("src.script.Commands")[verb], ctx, unpack(row, 2, #row))
      end
      if verb == "label" then return end
      if verb == "end" then return math.huge end
      if verb == "jump" or verb == "jump_if_true" and ctx.lastCheck
          or verb == "jump_if_false" and not ctx.lastCheck then return a end
      if verb == "jump_if_true" or verb == "jump_if_false" then return end
      if verb == "wait" then return runner:waitFrames(a) end
      if verb == "wait_flag" then
        local left = b
        runner.waitingCheck = function()
          local value, err = scriptFlag(native, a)
          expect(value ~= nil, err)
          if value then return true, true end
          if left then left = left - 1; if left <= 0 then return true, false end end
          return false
        end
        ctx.lastCheck = runner:yield()
      elseif verb == "set_flag" or verb == "clear_flag" then
        local ok, err = env.flag(game, native, a, verb == "set_flag", true); expect(ok, err)
      elseif verb == "check_flag" then
        local value, err = scriptFlag(native, a); expect(value ~= nil, err); ctx.lastCheck = value
      elseif verb == "show_text" or verb == "ask" then
        show(a, b, verb == "ask", c)
      elseif verb == "choice" then
        choose(a, b)
      elseif verb == "open_mart" then
        local items = mart(game, ow, a)
        local done = once(function() runner:resume() end)
        if generation == 3 then
          local Shop = req("src.ui.game3.shop_menu")
          expect(not Shop.isOpen(), "world is busy")
          token.shop, token.shopDone = Shop, done
          Shop.show({ items = items, session = save, onClose = done })
        else
          local world = setmetatable({ marts = { lists = { items } } }, { __index = ow })
          expect(ownUI(ow.openMart, world, 0, 0, done), "native mart unavailable")
        end
        runner:yield()
      elseif verb == "remember_outdoor" then
        local _, mapId = env.mapDef(game, a)
        save.lastOutdoor = { id = mapId, x = b, y = c }
        if generation == 3 then save.escapeWarp = { map = mapId, warpId = 255, x = b, y = c }
        elseif ow.rememberOutdoor then ow:rememberOutdoor(mapId, b, c)
        else ow.lastOutdoor = save.lastOutdoor end
      elseif verb == "warp" then
        local _, mapId = env.mapDef(game, a)
        token.destination = { mapId = mapId, x = b, y = c, facing = d }
        local ok, err = native:warpTo(a, b, c, d); expect(ok, err)
      elseif verb == "start_battle" or verb == "static_battle" then
        local beatFlag
        if verb == "static_battle" then beatFlag, a, b, c = c, "wild", a, b end
        local done = once(function(result)
          ctx.lastBattleResult, ctx.lastCheck = result, result == "win"; runner:resume()
        end)
        if a == "wild" then
          local ok, err = env.wild(game, native, p.publicSpecies, c, done); expect(ok, err)
        elseif generation == 1 then
          return ownUI(req("src.script.Commands").start_battle, ctx, a, b, c)
        elseif generation == 2 then
          expect(ow:startScriptedBattle(p.trainer, nil, done) ~= false, "native trainer battle failed")
        else
          local foe = g3("scripting.trainers").foeFromId(p.trainerId)
          expect(foe, "native trainer content unavailable")
          local ok, err = g3("battle_bridge").start(nil, game, foe, {
            wild = false, trainerId = p.trainerId, done = done,
            cancel = function(why) finish(why or "battle cancelled") end,
            failed = function(why) finish(why or "battle failed") end,
          }); expect(ok, err)
        end
        runner:yield()
        if verb == "static_battle" and ctx.lastBattleResult ~= "lose" then
          if beatFlag then
            local ok, err = env.flag(game, native, beatFlag, true, true); expect(ok, err)
          end
          local def = ctx.npc and ctx.npc.def
          local ref = def and (def.name or def.localId or def.index or def.id)
          if ref then
            local ok, err = native:toggleObject(ctx.mapId, ref, false); expect(ok, err)
          end
        end
      elseif verb == "set_field" then
        local private = a:match("^mod:(.+)$")
        if private then
          save.modData = save.modData or {}; save.modData[modId] = save.modData[modId] or {}
          save.modData[modId][private] = b
        else save[a] = b end
      elseif verb == "set_option" then
        save.options = save.options or {}; save.options[a] = b
      elseif verb == "give_money" or verb == "take_money" or verb == "check_money" then
        local have = generation == 2 and ow:money(0) or save.money or 0
        if verb == "check_money" then ctx.lastCheck = have >= a
        else
          local value = math.max(0, have + (verb == "give_money" and a or -a))
          if generation ~= 1 then value = math.min(999999, value) end
          if generation == 2 then ow:setMoney(0, value) else save.money = value end
        end
      elseif verb == "take_coins" then
        if generation == 2 then ow:setCoins(math.max(0, ow:coins() - a))
        elseif generation == 3 then g3("bag").Coins.set(save, math.max(0, g3("bag").Coins.get(save) - a))
        else save.coins = math.max(0, (save.coins or 0) - a) end
      elseif verb == "check_item" then ctx.lastCheck = itemCount(p.item) > 0
      elseif verb == "give_item" then
        if generation == 1 then
          return ownUI(req("src.script.Commands").give_item, ctx, p.item, b, c, d, row[6], row[7])
        end
        local ok
        if generation == 3 then
          local row = g3("items_data")._byId[p.item]
          token.strVars[1] = row and row.name or tostring(a)
          ok = g3("bag").add(save.bag, p.item, b or 1)
        else ok = req("src.inventory.Bag").add(save, p.item, b or 1, game.data) end
        if not ok then show(d or "You can't carry any more items!"); return math.huge end
        if c ~= false then show(c or "You received " .. tostring(a) .. "!") end
      elseif verb == "take_item" then
        local count = math.min(b or 1, itemCount(p.item))
        if count > 0 then
          if generation == 3 then g3("bag").remove(save.bag, p.item, count)
          else req("src.inventory.Bag").remove(save, p.item, count, game.data) end
        end
      elseif verb == "give_pokemon" then gift(p, b, c, d)
      elseif verb == "heal_party" then
        if generation == 3 then g3("party").healAll(save.party)
        elseif generation == 2 then ow:healParty()
        else req("src.script.Commands").heal_party(ctx) end
      elseif verb == "mark_seen" then
        if generation == 3 then save.dex = save.dex or {}; g3("dex").setSeen(save.dex, p.species)
        else
          save.pokedex = save.pokedex or {}; save.pokedex.seen = save.pokedex.seen or {}
          save.pokedex.seen[p.species] = true
        end
      elseif verb == "check_dex_owned" then
        local dex = generation == 3 and save.dex or save.pokedex
        local count = 0
        if generation == 3 then count = g3("dex").countOwned(dex)
        else
          for _, value in pairs(dex and (dex.owned or dex.caught) or {}) do if value then count = count + 1 end end
        end
        ctx.lastCheck = count >= (a or 1)
      elseif verb == "check_battle_result" then
        ctx.lastCheck = false
        local result = ctx.lastBattleResult
        if not result and generation == 2 then
          local outcome = ow.lastBattleResult
          result = outcome == 0 and "win" or outcome == 1 and "lose" or outcome
        elseif not result and generation == 3 and save.battleOutcome ~= nil then
          local Natives = g3("scripting.natives")
          for _, outcome in ipairs({ "win", "lose", "run", "caught" }) do
            if save.battleOutcome == Natives.outcome_to_code(outcome) then result = outcome; break end
          end
        end
        for i = 2, #row do if result == row[i] then ctx.lastCheck = true end end
      elseif verb == "move_player" or verb == "move_npc" then
        local ref, dir, count = "player", a, b
        if verb == "move_npc" then ref, dir, count = a, b, c end
        local dirs = {}; for i = 1, count or 1 do dirs[i] = dir end
        move(ref, dirs)
      elseif verb == "move_npc_to" then
        if generation == 1 then return ownUI(req("src.script.Commands").move_npc_to, ctx, a, b, c) end
        move(a, pathTo(expect(entity(ow, a), "native NPC unavailable"), b, c))
      elseif verb == "place_npc" then
        local target, id = entity(ow, a); expect(target, "native NPC unavailable")
        if generation == 3 then g3("objects").setObjectXY(id, b, c)
        elseif generation == 2 then ow:moveObject(id, b, c)
        else req("src.script.Commands").place_npc(ctx, a, b, c, d) end
        if d then target.facing = d end
      elseif verb == "face_object" or verb == "face_player_dir" or verb == "face" then
        local target, dir
        if verb == "face_object" then target, dir = entity(ow, a), b
        elseif verb == "face" then target, dir = ctx.npc, a
        else target, dir = entity(ow, "player"), a end
        expect(target, "native facing target unavailable")
        if target.scriptFace then target:scriptFace(dir) else target.facing = dir end
        if c and c.hold then target.timer = c.hold end
      elseif verb == "face_npc" or verb == "face_player" then
        local player = entity(ow, "player")
        local target, other = ctx.npc, player
        if verb == "face_npc" then target, other = player, ctx.npc end
        expect(target and other, "script NPC unavailable")
        local dx, dy = other.cellX - target.cellX, other.cellY - target.cellY
        local dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
        if target.scriptFace then target:scriptFace(dir) else target.facing = dir end
      elseif verb == "show_object" or verb == "hide_object" then
        local ok, err = native:toggleObject(a, b, verb == "show_object"); expect(ok, err)
      elseif verb == "replace_block" then
        if generation == 3 then
          local Field = g3("field")
          local ok, err = g3("mod_layout").checkMetatile(Field.currentPair(), c)
          expect(ok, err)
          Field.setMetatile(a, b, c)
        else local ok, err = native:replaceBlock(a, b, c); expect(ok, err) end
      elseif verb == "play_sound" or verb == "play_music" or verb == "stop_music" or verb == "play_cry"
          or verb == "play_once" or verb == "text_sound" or verb == "wait_sound"
          or verb == "engage_music" or verb == "fade_music" or verb == "play_default_music" then
        if generation == 1 then return ownUI(req("src.script.Commands")[verb], ctx, p.species or a, b) end
        if verb == "play_cry" then
          ctx.pendingCry, ctx.pendingCryWait = p.species, b
          return
        elseif verb == "text_sound" then ctx.pendingTextSound = a; return
        elseif verb == "engage_music" then ctx.pendingEngageMusic = a; return end
        if generation == 3 then
          local Audio = g3("audio")
          if verb == "play_sound" then ctx.lastSfxSrc = Audio.playSe(a)
          elseif verb == "play_music" then Audio.playSong(a, b)
          elseif verb == "stop_music" then Audio.playSong(0)
          elseif verb == "fade_music" then Audio.fadeOutBgm(a or 10)
          elseif verb == "play_default_music" then Audio.restoreMapSong()
          elseif verb == "play_once" then
            expect(Audio.playFanfare(audioId(a)), "native fanfare unavailable")
            runner.waitingCheck = function() return Audio.isFanfareFinished() end
            runner:yield()
          elseif verb == "wait_sound" then
            local left = 600
            runner.waitingCheck = function()
              left = left - 1
              return left <= 0 or not Audio.isSePlaying()
            end
            runner:yield()
          end
        elseif verb == "play_sound" then ctx.lastSfxSrc = req("src.core.Sound").play(game.data, a)
        elseif verb == "play_music" then req("src.core.Music").play(game.data, a, nil, b)
        elseif verb == "stop_music" then req("src.core.Music").stop()
        elseif verb == "fade_music" then req("src.core.Music").fadeOut(a or 10)
        elseif verb == "play_default_music" then ow:playMapMusic()
        else return ownUI(req("src.script.Commands")[verb], ctx, a) end
      elseif ADAPTED[verb] and ADAPTED[verb][generation] then
        return adapted(verb, a, b, c)
      else
        expect(p.fn, "native adapter unavailable: " .. verb)
        return ownUI(p.fn, ctx, unpack(row, 2, #row))
      end
    end

    local index = 1
    local function resumeRow(...)
      local states, before = game.stack and game.stack.states, {}
      for _, state in ipairs(states or {}) do before[state] = true end
      local result = pack(coroutine.resume(runner.co, ...))
      for _, state in ipairs(states or {}) do if not before[state] then token.ownedUI[state] = true end end
      if not result[1] then return finish("world operation failed: " .. tostring(result[2])) end
      if token.done then return end
      if coroutine.status(runner.co) == "dead" then
        runner.co, runner.pending, runner.waitingFrames, runner.waitingCheck = nil, nil, nil, nil
        local target = result[2]
        if type(target) == "string" then
          index = target == "end" and math.huge or expect(labels[target], "missing script label: " .. target)
        elseif type(target) == "number" then
          expect(target == math.huge or integer(target, 1, #rows), "invalid script jump target")
          index = target
        else index = index + 1 end
      end
    end
    local function step(native)
      local row = rows[index]
      if not row then
        for _, callback in ipairs(ctx.afterScript or {}) do callback() end
        return finish()
      end
      runner.pc, runner.script = index, rows
      runner.co = coroutine.create(function()
        if generation == 1 and not ARITY[row[1]] and not plans[index].custom then
          return runner:exec({ row }, ctx)
        end
        local function invoke(hctx, _, args)
          expect(hctx == ctx, "script context cannot change ownership")
          return dispatch({ row[1], unpack(args, 1, args.n or #args) }, plans[index], native)
        end
        local args = { n = math.max(0, #row - 1), unpack(row, 2, #row) }
        if runtime.wantsHook("script.command") then return runtime.call("script.command", invoke, ctx, row[1], args) end
        return invoke(ctx, row[1], args)
      end)
      resumeRow()
    end
    local function tick(updatedGame)
      local live, native, locationNow = valid()
      if not live then return end
      if updatedGame ~= game then return schedule() end
      if runner.waitingFrames then
        runner.waitingFrames = runner.waitingFrames - 1
        if runner.waitingFrames <= 0 then runner.waitingFrames = nil; runner:resume() end
      end
      if runner.waitingCheck then
        local done, value = runner.waitingCheck()
        if done then runner.waitingCheck = nil; runner:resume(value) end
      end
      local overlay = generation == 1 and ow.fadeOverlay
      local fading = overlay and game.stack:top() == overlay and token.ownedUI[overlay]
      if fading or env.ready(game, native, token) then
        local dest = token.destination
        if dest then
          if locationNow.mapId ~= dest.mapId or locationNow.x ~= dest.x or locationNow.y ~= dest.y
              or dest.facing and locationNow.facing ~= dest.facing then return schedule() end
          token.mapId, token.destination = dest.mapId, nil
          ctx.mapId, ctx.source.mapId = dest.mapId, dest.mapId
          if generation == 3 and lockWorld._locks ~= token.locks then
            if token.locks then token.locks[token] = nil end
            lockWorld.lock(token); token.locks = lockWorld._locks
          end
        end
        if runner.co then
          if runner.pending then
            local args = runner.pending; runner.pending = nil
            resumeRow(unpack(args, 1, args.n))
            if not token.done and not runner.co then step(native) end
          end
        else step(native) end
      end
      schedule()
    end
    schedule = function()
      if token.done or token.unsubscribe then return end
      local fired = false
      local callback
      callback = function(nextFn, ...)
        if fired then return nextFn(...) end
        fired = true
        local updatedGame = ...
        local result = pack(pcall(nextFn, ...))
        if token.unsubscribe then token.unsubscribe(); token.unsubscribe, token.subscription = nil, nil end
        if not result[1] then finish("world update failed"); error(result[2], 0) end
        local ok, err = pcall(tick, updatedGame)
        if not ok then finish("world operation failed: " .. tostring(err)) end
        return unpack(result, 2, result.n)
      end
      token.subscription = callback
      token.unsubscribe = hooks:wrap("core.update", callback, math.huge, modId)
    end
    local ok, err = pcall(function()
      schedule()
      emit("script.started", { ctx = ctx })
      step(api)
    end)
    if not ok then
      local why = "world operation failed: " .. tostring(err)
      finish(why); return nil, why
    end
    return true
  end

  local function cancel(reason)
    local token = queued
    if not token or token.done then return false end
    token.finish(type(reason) == "string" and reason or "script cancelled")
    return true
  end
  return queue, cancel
end

return UnifiedScripts

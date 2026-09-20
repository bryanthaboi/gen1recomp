-- Host adapters for game3 yields (message, lock, movement, freeze).

local MapIds = require("src.core.game3.map_ids")
local Movement = require("src.core.game3.scripting.movement")
local Flags = require("src.core.game3.scripting.flags")
local Opcodes = require("src.core.game3.scripting.opcodes")
local Strings = require("src.core.Strings")

local Adapters = {}

--- Build a test/stub adapter set. opts may override any method.
function Adapters.stub(opts)
  opts = opts or {}
  local boxOpen = false
  local frozen = {}
  local facing = {}
  local logs = {}
  local a
  a = {}
  a.boxOpen = function() return boxOpen end
  a.logs = logs
  a.frozen = frozen
  a.facing = facing
  a.playerName = opts.playerName or "RED"
  a.rivalName = opts.rivalName or "BLUE"
  a.lookupText = opts.lookupText
  a.lookupMovement = opts.lookupMovement
  a.lookupScript = opts.lookupScript
  a.log = function(msg)
    logs[#logs + 1] = msg
    if opts.verbose then print(msg) end
  end
  -- Sync open for unit tests that don't yield.
  a.openMessage = function(text)
    boxOpen = true
    a.lastMessage = text
    if opts.onMessage then opts.onMessage(text) end
  end
  -- Async open: call done when "player" finishes reading (instant in stub).
  a.openMessageAsync = function(text, done)
    boxOpen = true
    a.lastMessage = text
    if opts.onMessage then opts.onMessage(text) end
    if done then done() end
  end
  a.closeMessage = function()
    boxOpen = false
    if opts.onClose then opts.onClose() end
  end
  a.waitButton = function(cb)
    if cb then cb() end
    return true
  end
  a.freezeLocal = function(localId, snap)
    frozen[localId] = snap or true
  end
  a.unfreezeLocal = function(localId, snap)
    frozen[localId] = nil
    if snap and snap.facing then facing[localId] = snap.facing end
  end
  a.facePlayer = function(localId)
    facing[localId] = "toward_player"
  end
  a.listActiveLocalIds = function()
    return opts.activeLocalIds or {}
  end
  a.nurseHeal = opts.nurseHeal or function(done) if done then done() end end
  a.openPc = opts.openPc or function(done) if done then done() end end
  a.openShop = opts.openShop or function(_items, done) if done then done() end end
  a.askYesNo = opts.askYesNo or function(cb) if cb then cb(true) end end
  a.fadeScreen = opts.fadeScreen or function(_mode, _speed, done) if done then done() end end
  a.openNaming = opts.openNaming or function(_opts, done) if done then done("RED") end end
  a.openEasyChat = opts.openEasyChat or function(o, done)
    local def = { 2601, 4128, 526, 2611 }
    if done then done(true, (o and o.words) or def) end
  end
  a.hallOfFame = opts.hallOfFame or function(done)
    local HallOfFame = require("src.ui.game3.hall_of_fame")
    HallOfFame.start({
      session = opts.session or (opts.game and opts.game.session),
      onDone = function()
        if done then done() end
      end,
    })
  end
  a.bufferName = opts.bufferName or function(op, src)
    if op == "bufferspeciesname" then
      local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
      if ok and Pokemon then
        if not Pokemon._names then Pokemon.install(nil) end
        return Pokemon.name(tonumber(src) or src)
      end
    end
    if op == "bufferitemname" or op == "bufferitemnameplural" then
      local ok, ItemsData = pcall(require, "src.core.game3.items_data")
      if ok and ItemsData then
        return ItemsData.displayName(src)
      end
    end
    if op == "bufferstdstring" then
      local STD = {
        [24] = Strings("ITEMS POCKET"),
        [25] = Strings("KEY ITEMS POCKET"),
        [26] = Strings("POKé BALLS POCKET"),
        [27] = Strings("TM CASE"),
        [28] = Strings("BERRY POUCH"),
      }
      return STD[tonumber(src) or -1]
    end
    return nil
  end
  a.leadMonName = opts.leadMonName or function() return "POKéMON" end
  a.openMessageStay = opts.openMessageStay or function(text, done)
    a.openMessageAsync(text, done)
  end
  a.applyMovement = opts.applyMovement
  a.pollMovement = opts.pollMovement
  a.resolveGraphics = opts.resolveGraphics
  a.getPlayerFacing = opts.getPlayerFacing or function() return "down" end
  for k, v in pairs(opts) do
    if type(v) == "function" or a[k] == nil then
      a[k] = v
    end
  end
  if opts.openMessage then
    local user = opts.openMessage
    a.openMessage = function(text)
      boxOpen = true
      a.lastMessage = text
      return user(text)
    end
  end
  if opts.closeMessage then
    local user = opts.closeMessage
    a.closeMessage = function()
      boxOpen = false
      return user()
    end
  end
  return a
end

function Adapters.resolveNpcColor(ctx, store)
  local Ctx = require("src.core.game3.scripting.ctx")
  local sv = ctx and ctx.specialVars or {}
  local tc = sv[Ctx.VAR_TEXT_COLOR]
  if tc == nil then tc = Ctx.TEXT_COLOR_DEFAULT end
  -- src/field_specials.c:1548
  if tc ~= Ctx.TEXT_COLOR_DEFAULT then return tc end
  local sel = ctx and tonumber(ctx.selectedLocalId) or 0
  if sel == 0 then return 3 end
  local gfx = nil
  local Objects = package.loaded["src.core.game3.objects"]
  local obj = Objects and Objects.find and not (Objects.isPlayer and Objects.isPlayer(sel)) and Objects.find(sel)
  if obj then
    gfx = obj.graphicsId or (obj.def and (obj.def.graphicsId or obj.def.graphics))
  end
  gfx = tonumber(gfx) or tonumber(ctx.selectedGfx)
  if gfx and gfx >= 240 and gfx <= 255 then
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local v = Flags.getVar(store or (Space and Space.store), ctx, Ctx.GFX_VAR_LO + (gfx - 240))
    gfx = (type(v) == "number" and v > 0) and v or gfx
  end
  local FrlgFont = require("src.ui.game3.frlg_font")
  return FrlgFont.getNpcTextColor(gfx)
end

local function current_npc_color()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local ctx = Space and Space.vm and Space.vm.ctx
  if not ctx then return nil end
  return Adapters.resolveNpcColor(ctx, Space.store)
end

local function tick_vm()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm then Space.vm:tick() end
end

--- Live Love2D / Gen2 host adapter.
function Adapters.host(mod, game, world)
  local HouseNpcs = require("src.core.game3.house_npcs_stub")
  local boxOpen = false
  -- Parallel FRLG applymovement tracks (Gen2 World.moveState is single-slot).
  local moveTracks = {}

  local function resolveGame()
    return game or (world and world.game) or (mod and mod.game)
  end

  local function resolveWorld()
    if world and (world.showText or world.openPc or world.startHealMachineAnim
        or world.player or world.setMap) then
      return world
    end
    local g = resolveGame()
    if g and g.overworld and (g.overworld.showText or g.overworld.player) then
      return g.overworld
    end
    return world
  end

  local function npcLocalId(npc)
    if not npc then return nil end
    local d = npc.def
    return (d and (d.localId or d.index)) or npc.localId or npc.index
  end

  local function findNpc(localId)
    local want = tonumber(localId) or localId
    -- Prefer game3 EventObjects while they own the map.
    local okO, Objects = pcall(require, "src.core.game3.objects")
    if okO and Objects and Objects.hasMap and Objects.hasMap() then
      local eo = Objects.find(want)
      if eo then return eo end
    end
    local w = resolveWorld()
    if not w then return nil end
    if want == Opcodes.LOCALID_PLAYER or want == 0 then
      return w.player
    end
    if w.talkNpc and npcLocalId(w.talkNpc) == want then
      return w.talkNpc
    end
    for _, npc in ipairs(w.npcs or {}) do
      if npcLocalId(npc) == want then return npc end
    end
    for _, npc in pairs(w.npcPool or {}) do
      if npcLocalId(npc) == want then return npc end
    end
    return nil
  end

  local function useGame3Objects()
    local okO, Objects = pcall(require, "src.core.game3.objects")
    return okO and Objects and Objects.hasMap and Objects.hasMap() and Objects
  end

  local function useGame3Tracks()
    local G3 = useGame3Objects()
    if G3 and G3.hasActiveTracks and G3.hasActiveTracks() then return G3 end
    return nil
  end

  local function spaceStore()
    local Space = package.loaded["src.core.game3.scripting.space"]
    return Space and Space.store
  end

  local function advanceMoveTracks()
    for lid, tr in pairs(moveTracks) do
      if not tr.done then
        local ent = tr.entity
        if not ent then
          ent = findNpc(lid)
          tr.entity = ent
        end
        if tr.sleep and tr.sleep > 0 then
          tr.sleep = tr.sleep - 1
        elseif not (ent and ent.moving) then
          local act = tr.actions[tr.i]
          if not act then
            tr.done = true
            if tr.onDone then
              local cb = tr.onDone
              tr.onDone = nil
              cb()
            end
          else
            tr.i = tr.i + 1
            if act.kind == "step" then
              if ent and ent.scriptStep then ent:scriptStep(act.dir) end
            elseif act.kind == "turn" then
              if ent and ent.scriptFace then
                ent:scriptFace(act.dir)
              elseif ent then
                ent.facing = act.dir
              end
            elseif act.kind == "sleep" then
              tr.sleep = act.frames or 1
            elseif act.kind == "hide" then
              if ent then
                ent.hidden = true
                ent.visible = false
              end
            elseif act.kind == "show" then
              if ent then
                ent.hidden = false
                ent.visible = true
              end
            end
          end
        end
      end
    end
  end

  local a
  a = {
    log = function(msg)
      if mod and mod.log then mod.log:info(msg) else print(msg) end
    end,
    playerName = function()
      local g = resolveGame()
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session and session.name then return session.name end
      if g and g.session and g.session.name then return g.session.name end
      local p = g and g.save and g.save.player
      return (p and (p.name or p.playerName)) or (g and g.save and g.save.name) or "PLAYER"
    end,
    rivalName = function()
      local g = resolveGame()
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session and session.rivalName and session.rivalName ~= "" then
        return session.rivalName
      end
      if g and g.session and g.session.rivalName and g.session.rivalName ~= "" then
        return g.session.rivalName
      end
      local save = g and g.save
      if save and save.rivalName and save.rivalName ~= "" then return save.rivalName end
      local p = save and save.player
      return (p and p.rivalName) or "RIVAL"
    end,
    openMessage = function(text)
      boxOpen = true
    end,
    openMessageAsync = function(text, done)
      boxOpen = true
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Hud = require("src.ui.game3.hud")
        local g = resolveGame()
        a.log("[game3] dialog via game3 HUD (not Gen2 showText)")
        local npcColor = current_npc_color()
        Hud.openMessage(g, text, {
          npcColor = npcColor,
          done = function()
            boxOpen = false
            if done then done() end
            tick_vm()
          end,
        })
        return
      end
      local g = resolveGame()
      local w = resolveWorld()
      local function finish()
        if done then done() end
        tick_vm()
      end
      if w and w.showText then
        w:showText(text, finish)
        return
      end
      if HouseNpcs and HouseNpcs.pushText then
        HouseNpcs.pushText(g, text, finish)
      else
        finish()
      end
    end,
    -- Hold the box open for yesnobox / MSGBOX_YESNO.
    openMessageStay = function(text, done)
      boxOpen = true
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Hud = require("src.ui.game3.hud")
        local g = resolveGame()
        a.log("[game3] stay-dialog via game3 HUD")
        local npcColor = current_npc_color()
        Hud.openMessageStay(g, text, {
          npcColor = npcColor,
          done = function()
            if done then done() end
            tick_vm()
          end,
        })
        return
      end
      local g = resolveGame()
      local w = resolveWorld()
      local function finish()
        if done then done() end
        tick_vm()
      end
      if w and w.showText then
        w:showText(text, finish, true)
        return
      end
      if w then w.lastText = text end
      if HouseNpcs and HouseNpcs.pushText then
        HouseNpcs.pushText(g, text, finish)
      else
        finish()
      end
    end,
    closeMessage = function()
      boxOpen = false
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Message = require("src.ui.game3.message")
        Message.close()
        return
      end
      local g = resolveGame()
      local w = resolveWorld()
      if w and w.stayedTextBox and g and g.stack then
        if g.stack:top() == w.stayedTextBox then
          g.stack:pop()
        end
        w.stayedTextBox = nil
      end
    end,
    waitButton = function(cb)
      if cb then cb() end
      return true
    end,
    armWaitButton = function(cb)
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Hud = require("src.ui.game3.hud")
        Hud.armWaitButton(function()
          -- Close the message box after button press (pret WaitForFieldInput).
          -- Stay-mode messages (field item pickups, signs) remain open until
          -- explicitly dismissed; without this they persist after the script ends.
          local Message = package.loaded["src.ui.game3.message"]
          if Message and Message.isOpen and Message.isOpen() then
            Message.close()
          end
          if cb then cb() end
          tick_vm()
        end)
        return
      end
      if cb then cb() end
      tick_vm()
    end,
    -- Gen1 pokecenter uses HEAL/CANCEL; Gen2 askYesNo is YES/NO over stayed text.
    askYesNo = function(cb, layout)
      local function finish(yes)
        if cb then cb(yes and true or false) end
        tick_vm()
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Choice = require("src.ui.game3.choice")
        local Hud = require("src.ui.game3.hud")
        Hud.ensure(resolveGame(), "message")
        a.log("[game3] yes/no via game3 Choice (not Gen2 askYesNo)")
        Choice.yesNo(finish, layout)
        -- Do NOT autoPick — player must answer on HUD.
        return
      end
      local w = resolveWorld()
      if w and type(w.askYesNo) == "function" then
        w:askYesNo(finish)
        return
      end
      local g = resolveGame()
      if g and g.stack then
        local TextBox = require("src.render.TextBox")
        local Theme = require("src.ui.Theme")
        local Strings = require("src.core.Strings")
        local question = (w and w.lastText) or ""
        g.stack:push(TextBox.new(g, question, nil, {
          instant = true,
          choice = finish,
          choiceLabels = { Strings("HEAL"), Strings("CANCEL") },
          choiceBox = Theme.healCancelBox,
        }))
        return
      end
      finish(true)
    end,
    showMonPic = function(species, x, y)
      local MonPic = require("src.ui.game3.mon_pic")
      MonPic.show(species, x, y)
    end,
    hideMonPic = function()
      local MonPic = require("src.ui.game3.mon_pic")
      MonPic.hide()
    end,
    giveMon = function(species, level, _, _, _, nickname)
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if not session then return false end
      local Party = require("src.core.game3.party")
      return Party.giveMon(session, species, level, nickname)
    end,
    freezeLocal = function(localId, snap)
      local G3 = useGame3Objects()
      if G3 then
        local eo = G3.find(localId)
        if eo and snap and eo.facing then snap.facing = eo.facing end
        G3.freeze(localId)
        return
      end
      local npc = findNpc(localId)
      if not npc then return end
      if snap then snap.facing = npc.facing end
      npc.frozen = true
      local w = resolveWorld()
      if w and w.freezeNpc then
        w:freezeNpc(npc)
      elseif w then
        w.frozeNpcs = true
      end
    end,
    unfreezeLocal = function(localId, _snap)
      local G3 = useGame3Objects()
      if G3 then
        G3.unfreeze(localId)
        return
      end
      local w = resolveWorld()
      -- Gen2: World:step clears frozeNpcs when !busy (includes game3 VM).
      if w and w.frozeNpcs and type(w.freezeNpc) == "function" then
        return
      end
      local npc = findNpc(localId)
      if npc then npc.frozen = false end
    end,
    facePlayer = function(localId)
      local G3 = useGame3Objects()
      if G3 then
        G3.facePlayer(localId, resolveGame())
        return
      end
      local w = resolveWorld()
      local npc = findNpc(localId) or (w and w.talkNpc)
      local player = w and w.player
      if npc and player and npc.facePlayer then
        npc:facePlayer(player)
      end
    end,
    listActiveLocalIds = function()
      local G3 = useGame3Objects()
      if G3 then return G3.listActive() end
      local ids = {}
      local w = resolveWorld()
      for _, npc in ipairs((w and w.npcs) or {}) do
        local lid = npcLocalId(npc)
        if lid then ids[#ids + 1] = lid end
      end
      return ids
    end,
    messageOpen = function() return boxOpen end,
    nurseHeal = function(done)
      local function finish()
        if done then done() end
        tick_vm()
      end
      -- pret special HealPlayerParty is silent (no nurse dialogue). Dialogue
      -- lives in the surrounding script; never call Gen1 OC.nurseHeal here —
      -- that method needs an OverworldState self + Game upvalue.
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local session = Runtime.getSession and Runtime.getSession()
        local Party = require("src.core.game3.party")
        if session and session.party then
          Party.healAll(session.party)

        end
        local Player = require("src.core.game3.player")
        Player.syncToHost(resolveGame())
        local w = resolveWorld()
        if w and w.healParty then
          pcall(function() w:healParty() end)
        end
        finish()
        return
      end
      local w = resolveWorld()
      if w and w.startHealMachineAnim then
        w:startHealMachineAnim(nil, function()
          if w.healParty then w:healParty() end
          finish()
        end)
        if w.healAnim then
          w.healAnim.px = (w.healAnim.px or 0) + 16
        end
        return
      end
      if w and type(w.nurseHeal) == "function" then
        w:nurseHeal(finish)
        return
      end
      finish()
    end,
    doFieldEffect = function(id)
      local FieldEffects = require("src.core.game3.field_effects")
      if FieldEffects.doFieldEffect then
        FieldEffects.doFieldEffect(id)
      end
    end,
    waitFieldEffect = function(id, done)
      local FieldEffects = require("src.core.game3.field_effects")
      local function finish()
        if done then done() end
        tick_vm()
      end
      if FieldEffects.waitFieldEffect then
        FieldEffects.waitFieldEffect(id, finish)
        return
      end
      finish()
    end,
    openPc = function(done, pcOpts)
      local function finish()
        local okMsg, Message = pcall(require, "src.ui.game3.message")
        if okMsg and Message and Message.close then Message.close() end
        if done then done() end
        tick_vm()
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        if a.closeMessage then a.closeMessage() end
        local okMsg, Message = pcall(require, "src.ui.game3.message")
        if okMsg and Message and Message.close then Message.close() end
        local okHud, Hud = pcall(require, "src.ui.game3.hud")
        if okHud and Hud and Hud.clearWaitButton then Hud.clearWaitButton() end
        a.log("[game3] openPc via game3 PcMenu")
        local PcMenu = require("src.ui.game3.pc_menu")
        local bedroom = type(pcOpts) == "table" and pcOpts.bedroom == true
        PcMenu.show({
          session = Runtime.getSession(),
          onClose = finish,
          startMode = bedroom and "player_pc" or nil,
          closeOnExit = bedroom,
        })
        return
      end
      local w = resolveWorld()
      if w and w.openPc then
        w:openPc({ onDone = finish })
        return
      end
      local OC = require("src.world.OverworldController")
      if type(OC.openPC) == "function" then
        OC.openPC(finish)
        return
      end
      finish()
    end,
    openShop = function(martKey, done)
      local function finish()
        local okMB, MoneyBox = pcall(require, "src.ui.game3.money_box")
        if okMB and MoneyBox and MoneyBox.hide then MoneyBox.hide() end
        if done then done() end
        tick_vm()
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local Marts = require("src.core.game3.marts")
      Marts.ensure()
      local items = Marts.itemsFor(martKey)
      if not items or #items < 1 then
        a.log("[game3] openShop: no mart list for " .. tostring(martKey))
        finish()
        return
      end
      a.log("[game3] openShop items=" .. tostring(#items))
      if a.closeMessage then a.closeMessage() end
      local okMsg, Message = pcall(require, "src.ui.game3.message")
      if okMsg and Message and Message.close then Message.close() end
      local ShopMenu = require("src.ui.game3.shop_menu")
      ShopMenu.show({
        items = items,
        session = session,
        onClose = finish,
      })
    end,
    removeObject = function(localId)
      local G3 = useGame3Objects()
      if G3 then
        local eo = G3.find(localId)
        local flag = eo and eo.def and (eo.def.flag or eo.def.flagId)
        if flag and flag ~= 0 and flag ~= 0xFFFF and flag ~= 65535 then
          local store = spaceStore()
          if store then
            Flags.setFlag(store, nil, flag, true)
          end
        end
        G3.removeObject(localId)
        return
      end
      -- pret RemoveObjectEventByLocalIdAndMap: FlagSet(object's event flag)
      -- then despawn. Without the flag, Bill respawns on the next outdoor load.
      local npc = findNpc(localId)
      local flag = npc and npc.def and (npc.def.flag or npc.def.flagId)
      if flag and flag ~= 0 and flag ~= 0xFFFF and flag ~= 65535 then
        local store = spaceStore()
        if store then
          Flags.setFlag(store, nil, flag, true)
        end
      end
      if npc then
        npc.hidden = true
        npc.visible = false
        if npc.def then npc.def.hidden = true end
      end
      moveTracks[tonumber(localId) or localId] = nil
    end,
    addObject = function(localId)
      local G3 = useGame3Objects()
      if G3 then
        G3.addObject(localId)
        return true
      end
      return false
    end,
    -- Hide-flag ↔ EventObject visibility (removeobject + clearflag lab Oak).
    onFlagChanged = function(flagId, hidden)
      local G3 = useGame3Objects()
      if G3 and G3.syncFlagVisibility then
        G3.syncFlagVisibility(flagId, hidden and true or false)
      end
    end,
    hideObject = function(localId)
      local G3 = useGame3Objects()
      if G3 then
        G3.hideObject(localId)
        return
      end
      local npc = findNpc(localId)
      if npc then
        npc.hidden = true
        npc.visible = false
      end
    end,
    showObject = function(localId)
      local G3 = useGame3Objects()
      if G3 then
        G3.showObject(localId)
        return
      end
      local npc = findNpc(localId)
      if npc then
        npc.hidden = false
        npc.visible = true
      end
    end,
    turnObject = function(localId, dir)
      local G3 = useGame3Objects()
      if G3 then
        G3.turnObject(localId, dir)
        return
      end
      local npc = findNpc(localId)
      local dirs = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }
      -- FRLG DIR_*: 1=down 2=up 3=left 4=right (also 0 sometimes)
      local facing = dirs[tonumber(dir) or 0] or dirs[((tonumber(dir) or 1) % 4) + 1]
      if npc and facing then
        if npc.scriptFace then
          npc:scriptFace(facing)
        else
          npc.facing = facing
          if npc.dir ~= nil then npc.dir = facing end
        end
      end
    end,
    setObjectState = function(op, row)
      local lid = row and (row.localId or row[1])
      local G3 = useGame3Objects()
      if G3 then
        if op == "setobjectxyperm" or op == "setobjectxy" then
          G3.setObjectXY(lid, row[2], row[3])
        elseif op == "setobjectmovementtype" then
          G3.setMovementType(lid, row[2])
        elseif op == "copyobjectxytoperm" then
          if G3.copyObjectXYToPerm then
            G3.copyObjectXYToPerm(lid)
          end
        end
        return
      end
      local npc = findNpc(lid)
      if not npc then return end
      if op == "setobjectxyperm" or op == "setobjectxy" then
        local x, y = tonumber(row[2]), tonumber(row[3])
        if x and y then
          npc.cellX, npc.cellY = x, y
          if npc.x then npc.x = x * 16 end
          if npc.y then npc.y = y * 16 end
          if npc.def then
            npc.def.x, npc.def.y = x, y
          end
        end
      elseif op == "copyobjectxytoperm" then
        if npc.cellX and npc.cellY and npc.def then
          npc.def.x, npc.def.y = npc.cellX, npc.cellY
        end
      elseif op == "setobjectmovementtype" then
        -- Cosmetic on host; facing types 7–10 are FACE_*.
        local mt = tonumber(row[2]) or 0
        local face = ({ [7] = "up", [8] = "down", [9] = "left", [10] = "right" })[mt]
        if face then
          if npc.scriptFace then npc:scriptFace(face) else npc.facing = face end
        end
      end
    end,
    applyMovement = function(localId, stream, done)
      -- On Sevii, always drive game3 EventObjects / Player — never host scriptStep.
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local Objects = require("src.core.game3.objects")
        local w = resolveWorld()
        if w and w.frozeNpcs ~= nil then w.frozeNpcs = true end
        Objects.applyMovement(localId, stream, done)
        return
      end
      local G3 = useGame3Objects()
      if G3 then
        local w = resolveWorld()
        if w and w.frozeNpcs ~= nil then w.frozeNpcs = true end
        G3.applyMovement(localId, stream, done)
        return
      end
      local lid = tonumber(localId) or localId
      local actions = Movement.actionsFromBytes(stream)
      local ent = findNpc(lid)
      local w = resolveWorld()
      if w and w.frozeNpcs ~= nil then w.frozeNpcs = true end
      if ent then ent.frozen = true end
      moveTracks[lid] = {
        entity = ent,
        actions = actions,
        i = 1,
        sleep = 0,
        done = false,
        onDone = done,
      }
      advanceMoveTracks()
    end,
    pollMovement = function(localId, _entry)
      -- Prefer EventObjects whenever they own the map — not only when a track
      -- is already active (hasActiveTracks false → moveTracks treated missing
      -- as done and skipped Bill / Oak waits).
      local okO, Objects = pcall(require, "src.core.game3.objects")
      if okO and Objects and Objects.hasMap and Objects.hasMap() then
        return Objects.pollMovement(localId)
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        if okO and Objects then return Objects.pollMovement(localId) end
      end
      advanceMoveTracks()
      local lid = tonumber(localId) or localId
      if lid == 0 then
        for _, tr in pairs(moveTracks) do
          if not tr.done then return false end
        end
        return true
      end
      local tr = moveTracks[lid]
      return not tr or tr.done == true
    end,
    clearMovements = function()
      local G3 = useGame3Objects()
      if G3 then G3.clearMovements() end
      moveTracks = {}
    end,
    -- FRLG item index → host / game3 bag (H2 quarantine when Game3 active).
    modifyItem = function(op, itemId, qty)
      local Items = require("src.core.game3.items")
      local ItemsData = require("src.core.game3.items_data")
      local Game3Bag = require("src.core.game3.bag")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = (Runtime and Runtime.getSession and Runtime.getSession())
        or (package.loaded["src.core.game3.field"] and package.loaded["src.core.game3.field"]._session)
      qty = math.max(1, tonumber(qty) or 1)

      local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
      local id = Items.resolveHostId(itemId)
      if not id and num then
        id = Items.FRLG_TO_HOST[num]
      end
      if not id then
        id = (type(itemId) == "string" and itemId) or (num and ("FRLG_" .. tostring(num))) or tostring(itemId)
      end

      -- Native FR session bag: store numeric FRLG ids (pret ItemSlot shape).
      if session and session.bag then
        local storeId = num or id
        if op == "removeitem" then
          return Game3Bag.remove(session.bag, storeId, qty)
        end
        local ok = select(1, Game3Bag.add(session.bag, storeId, qty))
        if ok and (id == "TOWN_MAP" or num == 361) then
          local tmOk, TownMap = pcall(require, "src.core.game3.town_map_stub")
          if tmOk and TownMap.unlockSeviiMap then TownMap.unlockSeviiMap(mod) end
        end
        if ok and ItemsData.pocketOf(storeId)=="KEY_ITEMS" then
          local Q=require("src.core.game3.quest_log_recorder")
          Q.event(session,"ObtainedItemInLocation",{Q.location(resolveGame(),session),ItemsData.displayName(storeId)})
        end
        return ok
      end

      if not id or (type(itemId) == "string" and itemId:match("^%d+$") and not Items.FRLG_TO_HOST[tonumber(itemId)]) then
        a.log("[game3] unmapped FRLG item " .. tostring(itemId))
        return false
      end
      if Items.FORCE_QUARANTINE[id] or not Items.HOST_SAFE[id] then
        a.log("[game3] quarantine item " .. tostring(id) .. " with no session bag")
        return false
      end

      local g = resolveGame()
      if not g or not g.save then return false end
      local Bag = require("src.inventory.Bag")
      if op == "removeitem" then
        if Bag.remove then return Bag.remove(g.save, id, qty) and true or false end
        local inv = g.save.inventory or {}
        local have = inv[id] or 0
        if have < qty then return false end
        inv[id] = have - qty
        return true
      end
      local ok = Bag.add(g.save, id, qty)
      if ok and id == "TOWN_MAP" then
        local tmOk, TownMap = pcall(require, "src.core.game3.town_map_stub")
        if tmOk and TownMap.unlockSeviiMap then
          TownMap.unlockSeviiMap(mod)
        end
      end
      return ok and true or false
    end,
    checkItemSpace = function(itemId, qty)
      local ItemsData = require("src.core.game3.items_data")
      local Game3Bag = require("src.core.game3.bag")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      qty = math.max(1, tonumber(qty) or 1)
      local id = ItemsData.toNumericId(itemId) or itemId
      if session and session.bag then
        return Game3Bag.canAdd(session.bag, id, qty)
      end
      return true
    end,
    checkItem = function(itemId, qty)
      local ItemsData = require("src.core.game3.items_data")
      local Game3Bag = require("src.core.game3.bag")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      qty = math.max(1, tonumber(qty) or 1)
      local id = ItemsData.toNumericId(itemId) or itemId
      if session and session.bag then
        return Game3Bag.has(session.bag, id, qty)
      end
      return false
    end,
    checkItemType = function(itemId)
      local ItemsData = require("src.core.game3.items_data")
      return ItemsData.pocketResult(itemId)
    end,
    -- Intentionally no `delay` adapter: ops_a uses a soft per-frame countdown.
    -- A sync delay+tick_vm re-entered resume and skipped waitmovement (Oak lead).
    waitDoorAnim = function(done)
      local Doors = require("src.core.game3.doors")
      if not Doors.isBusy() then
        if done then done() end
      end
    end,
    doorAnim = function(op, x, y)
      local Doors = require("src.core.game3.doors")
      local Space = package.loaded["src.core.game3.scripting.space"]
      local mapId = Space and Space.currentMapId
      if op == "opendoor" then
        Doors.open(mapId, x, y)
      elseif op == "closedoor" then
        Doors.close(mapId, x, y)
      end
    end,
    fadeScreen = function(mode, speed, done)
      local Fade = require("src.ui.game3.fade")
      Fade.begin(tonumber(mode) or 0, tonumber(speed) or 1, function()
        if done then done() end
        tick_vm()
      end)
    end,
    openNaming = function(opts, done)
      local Naming = require("src.ui.game3.naming")
      local Fade = require("src.ui.game3.fade")
      local Message = require("src.ui.game3.message")
      opts = opts or {}
      opts.onDone = function(name)
        if done then done(name) end
        tick_vm()
      end
      -- Field scripts leave the yes/no box open; naming replaces the CB2 on cart.
      if Message.isOpen and Message.isOpen() and Message.close then
        Message.close()
      end
      Fade.clear()
      Naming.open(opts)
    end,
    openEasyChat = function(opts, done)
      local EasyChat = require("src.ui.game3.easy_chat")
      local Fade = require("src.ui.game3.fade")
      local Message = require("src.ui.game3.message")
      opts = opts or {}
      opts.onDone = function(confirmed, words)
        if done then done(confirmed, words) end
        tick_vm()
      end
      if Message.isOpen and Message.isOpen() and Message.close then
        Message.close()
      end
      Fade.clear()
      EasyChat.open(opts)
    end,
    warp = function(group, num, warpId, x, y, done)
      local Versions = require("src.import.gba.versions")
      -- Prefer FR standalone ids; fall back to Sevii ferry maps.
      local mapId = (Versions.frMapFor and Versions.frMapFor(group, num))
        or Versions.seviiMapFor(group, num)
      local w = resolveWorld()
      local finish = function()
        moveTracks = {}
        -- Do not Objects.clearMovements here. Map.load already activated the
        -- destination Space VM; ON_FRAME is pending and must keep any tracks
        -- it creates. Clearing here soft-locked Network Center MeetCelio.
        if done then done() end
        tick_vm()
      end
      if not mapId then
        a.log(string.format("[game3] warp unknown FRLG map %s.%s", tostring(group), tostring(num)))
        finish()
        return
      end
      -- Gen2 World:setMap(mapId, cx, cy, facing) — coords required (nil cx crashes).
      local function as_coord(v)
        v = tonumber(v)
        if not v then return nil end
        -- FRLG dummy coords are -1 / 0xFFFF when only warpId is used.
        if v < 0 or v >= 0x8000 then return nil end
        return v
      end
      local cx, cy = as_coord(x), as_coord(y)
      local wid = tonumber(warpId)
      if (not cx or not cy) and wid and wid ~= 0xFF and wid >= 0 then
        local def = w and w.data and w.data.maps and w.data.maps[mapId]
        if not def and w and w.game and w.game.data and w.game.data.maps then
          def = w.game.data.maps[mapId]
        end
        local warps = def and def.warps
        -- Host warps are 1-based; FRLG warpId is often 0-based.
        local entry = warps and (warps[wid] or warps[wid + 1])
        if entry then
          cx, cy = entry.x, entry.y
        end
      end
      if not cx or not cy then
        local def = w and w.game and w.game.data and w.game.data.maps and w.game.data.maps[mapId]
        local warps = def and def.warps
        if warps and warps[1] then
          cx, cy = warps[1].x, warps[1].y
        end
      end
      if not (cx and cy) then
        a.log(string.format("[game3] warp %s missing coords (id=%s x=%s y=%s)",
          mapId, tostring(warpId), tostring(x), tostring(y)))
        finish()
        return
      end
      local facing = "down"
      do
        local Runtime = package.loaded["src.core.game3.runtime"]
        if Runtime and Runtime.isActive and Runtime.isActive() then
          local Player = require("src.core.game3.player")
          facing = Player.facing or facing
        elseif w and w.player and w.player.facing then
          facing = w.player.facing
        end
      end
      -- Sevii destinations: game3 Map.load rebinds collision + EventObjects
      -- (localIds are per-map; town Bill lid1 ≠ PC Nurse lid1).
      if type(mapId) == "string" and MapIds.isGame3Map(mapId) then
        local Map = require("src.core.game3.map")
        local Runtime = package.loaded["src.core.game3.runtime"]
        local mod = Runtime and Runtime._mod
        Map.load(mod, resolveGame(), mapId, {
          x = cx,
          y = cy,
          facing = facing,
          depth1Connections = true,
        })
      elseif w and w.warpToMapId then
        w:warpToMapId(mapId, cx, cy, facing)
      elseif w and w.setMap then
        w:setMap(mapId, cx, cy, facing)
      else
        local OC = require("src.world.OverworldController")
        if type(OC.loadMap) == "function" then
          OC.loadMap(w, mapId)
        end
      end
      -- Hold waitstate until Gen2 mapSetup fade-in finishes (avoids white+text).
      if w and w.mapSetup then
        a._warpPoll = function()
          if w.mapSetup then return false end
          a._warpPoll = nil
          finish()
          return true
        end
        return
      end
      finish()
    end,
    playSe = function(id, fanfare)
      local Audio = require("src.core.game3.audio")
      if fanfare then
        Audio.playFanfare(id)
      else
        Audio.playSe(id)
      end
    end,
    waitFanfare = function(cb)
      local Audio = require("src.core.game3.audio")
      Audio.waitFanfare(cb)
    end,
    playBgm = function(id)
      require("src.core.game3.audio").playSong(id)
    end,
    fadeBgm = function(op, arg)
      local Audio = require("src.core.game3.audio")
      if op == "savebgm" then
        -- pokefirered/src/scrcmd.c:935
        Audio.setSavedSong(arg)
      elseif op == "fadeoutbgm" then
        Audio.fadeOutBgm(4)
      elseif op == "fadeinbgm" then
        Audio.fadeInBgm(Audio._mapSong or Audio._savedSong, 4)
      else
        Audio.fadeDefaultBgm(4)
      end
    end,
    multichoice = function(row, cb)
      local Choice = require("src.ui.game3.choice")
      local Hud = require("src.ui.game3.hud")
      local Multi = require("src.core.game3.scripting.multichoice")
      local listId = 0
      local n = 3
      if row then
        -- pret:
        -- multichoice left, top, listId, ignoreBPress
        -- multichoicedefault left, top, listId, default, ignoreBPress
        -- multichoicegrid left, top, listId, numColumns, ignoreBPress
        listId = tonumber(row.listId or row[3] or row[1]) or 0
        n = tonumber(row.count or row[4]) or n
      end
      local opts, layout = Multi.resolve(listId, n)
      layout = layout or {}
      local def = 0
      if row and row.op == "multichoicedefault" then
        def = tonumber(row.default or row[4] or row[5]) or 0
      end
      if row then
        -- pokefirered/src/script_menu.c:1195
        local x, y = tonumber(row.x or row.left or row[1]), tonumber(row.y or row.top or row[2])
        if x then layout.left = x + 1 end
        if y then layout.top = y + 1 end
        if row.op == "multichoicegrid" then
          layout.cols = tonumber(row.cols or row.numColumns or row[4]) or 1
          layout.ignoreBPress = row.ignoreBPress or (row[5] and tonumber(row[5]) ~= 0) or false
        else
          -- pokefirered/src/script_menu.c:737
          layout.maxRight = 29
          if row.op == "multichoicedefault" then
            layout.ignoreBPress = row.ignoreBPress or (row[5] and tonumber(row[5]) ~= 0) or false
          else
            layout.ignoreBPress = row.ignoreBPress or (row[4] and tonumber(row[4]) ~= 0) or false
          end
        end
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        Hud.ensure(resolveGame(), "message")
        a.log("[game3] multichoice via game3 Choice list=" .. tostring(listId))
        Choice.multi(opts, def, function(sel)
          if cb then cb(sel) end
          tick_vm()
        end, layout)
        return
      end
      Choice.multi(opts, def, function(sel)
        if cb then cb(sel) end
        tick_vm()
      end, layout)
      Choice.autoPick(def)
    end,
    setMetatile = function(x, y, metatile, impassable)
      local Field = require("src.core.game3.field")
      Field.setMetatile(x, y, metatile, impassable)
    end,
    setWeather = function(id)
      local Weather = require("src.core.game3.weather")
      Weather.set(id)
    end,
    doWeather = function()
      local Weather = require("src.core.game3.weather")
      Weather.doWeather()
    end,
    resetWeather = function()
      local Weather = require("src.core.game3.weather")
      Weather.reset()
    end,
    getPlayerFacing = function()
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        local P = require("src.core.game3.player")
        return P.facing or "down"
      end
      local w = resolveWorld()
      if w and w.player then
        return w.player.facing or "down"
      end
      return "down"
    end,
    showTownMap = function(done)
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = (Runtime and Runtime.getSession and Runtime.getSession()) or (resolveGame() and resolveGame().session)
      local RegionMap = require("src.ui.game3.region_map")
      local Fade = require("src.ui.game3.fade")
      local Message = require("src.ui.game3.message")
      if Message.isOpen and Message.isOpen() and Message.close then
        Message.close()
      end
      Fade.clear()
      a.log("[game3] showTownMap via RegionMap")
      RegionMap.show({
        session = session,
        onClose = function()
          Fade.clear()
          if done then done() end
          tick_vm()
        end,
      })
    end,
    hallOfFame = function(done)
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = (Runtime and Runtime.getSession and Runtime.getSession()) or (resolveGame() and resolveGame().session)
      local HallOfFame = require("src.ui.game3.hall_of_fame")
      a.log("[game3] hallOfFame induction started")
      HallOfFame.start({
        session = session,
        onDone = function()
          if done then done() end
          tick_vm()
        end,
      })
    end,
    startTrainerBattle = function(foe, done, battleOpts)
      local BattleBridge = require("src.core.game3.battle_bridge")
      battleOpts = battleOpts or {}
      BattleBridge.start(mod, resolveGame(), foe, {
        wild = false,
        trainerId = battleOpts.trainerId or (foe and foe.trainerId),
        defeatText = battleOpts.defeatText or (foe and foe.defeatText),
        victoryText = battleOpts.victoryText or (foe and foe.victoryText),
        earlyRival = battleOpts.earlyRival,
        rivalFlags = battleOpts.rivalFlags,
        noWhiteout = battleOpts.noWhiteout,
        double = battleOpts.double,
        done = function(result)
          if done then done(result or "win") end
          tick_vm()
        end,
      })
    end,
    startWildBattle = function(foe, done, battleOpts)
      local BattleBridge = require("src.core.game3.battle_bridge")
      battleOpts = battleOpts or {}
      BattleBridge.startWild(mod, resolveGame(), foe, {
        wildScripted = (foe and foe.wildScripted) or battleOpts.wildScripted,
        legendary = (foe and foe.legendary) or battleOpts.legendary,
        oldManTutorial = (foe and foe.oldManTutorial) or battleOpts.oldManTutorial,
        safari = (foe and foe.safari) or battleOpts.safari,
        roamer = (foe and foe.roamer) or battleOpts.roamer,
        firstBattle = (foe and foe.firstBattle) or battleOpts.firstBattle,
        aiFlags = (foe and foe.aiFlags) or battleOpts.aiFlags,
        done = function(result)
          if done then done(result or "win") end
          tick_vm()
        end,
      })
    end,
    bufferName = function(op, src)
      src = tonumber(src) or src
      if op == "bufferspeciesname" then
        local Pokemon = require("src.core.game3.pokemon")
        if not Pokemon._names then Pokemon.install(nil) end
        return Pokemon.name(src)
      end
      if op == "bufferitemname" or op == "bufferitemnameplural" then
        local ItemsData = require("src.core.game3.items_data")
        return ItemsData.displayName(src)
      end
      if op == "bufferstdstring" then
        -- pret constants/menu.h STDSTRING_*
        local STD = {
          [10] = Strings("ITEMS"),
          [11] = Strings("KEY ITEMS"),
          [12] = Strings("POKé BALLS"),
          [13] = Strings("TMs & HMs"),
          [14] = Strings("BERRIES"),
          [24] = Strings("ITEMS POCKET"),
          [25] = Strings("KEY ITEMS POCKET"),
          [26] = Strings("POKé BALLS POCKET"),
          [27] = Strings("TM CASE"),
          [28] = Strings("BERRY POUCH"),
        }
        return STD[tonumber(src) or -1] or tostring(src)
      end
      if op == "bufferpartymonnick" then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local party = Runtime and Runtime.session and Runtime.session.party
        local slot = (tonumber(src) or 0) + 1
        local mon = party and party[slot]
        if mon then
          local Pokemon = require("src.core.game3.pokemon")
          return Pokemon.displayName(mon)
        end
        local g = resolveGame()
        local hostParty = g and g.save and g.save.party
        mon = hostParty and hostParty[slot]
        if mon then
          local Pokemon = require("src.core.game3.pokemon")
          return Pokemon.displayName(mon)
        end
      end
      return nil
    end,
    leadMonName = function()
      local Runtime = package.loaded["src.core.game3.runtime"]
      local party = Runtime and Runtime.session and Runtime.session.party
      local mon = party and party[1]
      if not mon then
        local g = resolveGame()
        mon = g and g.save and g.save.party and g.save.party[1]
      end
      if mon then
        local Pokemon = require("src.core.game3.pokemon")
        return Pokemon.displayName(mon)
      end
      return "POKéMON"
    end,
  }
  -- waitstate / nativePoll can drain warp fade without a dedicated op field.
  local prevTickHook = a.pollWarp
  a.pollWarp = function()
    if a._warpPoll then return a._warpPoll() end
    if prevTickHook then return prevTickHook() end
    return true
  end
  return a
end

return Adapters

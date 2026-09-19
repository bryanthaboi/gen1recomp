-- Party menu — pret PARTY_LAYOUT_SINGLE (windows + FONT_SMALL + OAM sprites).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local PartyChrome = require("src.ui.game3.party_chrome")
local Pokemon = require("src.core.game3.pokemon")
local Display = require("src.core.game3.display")
local Oam = require("src.core.game3.oam")
local SummaryMenu = require("src.ui.game3.summary_menu")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")

local PartyMenu = {}

PartyMenu.open = false
PartyMenu.cursor = 1
PartyMenu.mode = "list" -- "list" | "action" | "item_action" | "switch" | "summary" | "use" | "give" | "message"
PartyMenu.actionCursor = 1
PartyMenu.itemActionCursor = 1
PartyMenu.switchFrom = nil
PartyMenu.summaryPage = 1
PartyMenu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" }
PartyMenu.ITEM_ACTIONS = { "GIVE", "TAKE", "CANCEL" }
PartyMenu._oam = nil -- per-slot { mon, ball, status } sprite ids
PartyMenu._summaryIcon = nil
PartyMenu._messageText = nil
PartyMenu._onMessageDismiss = nil
PartyMenu._item = nil
PartyMenu._bag = nil

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function nav_up(cur, n)
  if cur == 1 then
    return 7
  elseif cur == 7 then
    return n
  else
    return cur - 1
  end
end

local function nav_down(cur, n)
  if cur == 7 then
    return 1
  elseif cur == n then
    return 7
  else
    return cur + 1
  end
end

local function nav_left(cur, n, lastSlot)
  if cur ~= 1 and cur ~= 7 then
    return 1, cur
  end
  return cur, lastSlot
end

local function nav_right(cur, n, lastSlot)
  if cur == 1 and n > 1 then
    local target = lastSlot or 2
    if target < 2 then target = 2 end
    if target > n then target = n end
    return target, lastSlot
  end
  return cur, lastSlot
end

local function get_mon_stats(mon)
  return {
    maxHp = tonumber(mon and (mon.maxHp or mon.maxhp)) or 1,
    atk = tonumber(mon and (mon.attack or mon.atk)) or 1,
    def = tonumber(mon and (mon.defense or mon.def)) or 1,
    spa = tonumber(mon and (mon.spAtk or mon.spa or mon.spatk)) or 1,
    spd = tonumber(mon and (mon.spDef or mon.spd or mon.spdef)) or 1,
    spe = tonumber(mon and (mon.speed or mon.spe)) or 1,
  }
end

function PartyMenu.showStatGrowth(mon, oldStats, newStats, onDone)
  PartyMenu._statGrowthMon = mon
  PartyMenu._statGrowthOld = oldStats
  PartyMenu._statGrowthNew = newStats
  PartyMenu._statGrowthPage = 1
  PartyMenu._statGrowthDone = onDone
  PartyMenu.mode = "stat_growth"
end

-- pret sSinglePartyMenuWindowTemplate
local SLOT_WIN = {
  { left = 1, top = 3, w = 10, h = 7, kind = "main" },
  { left = 12, top = 1, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 4, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 7, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 10, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 13, w = 18, h = 3, kind = "wide" },
}

-- pret sPartyMenuSpriteCoords[PARTY_LAYOUT_SINGLE]
-- monX, monY, itemX, itemY, statusX, statusY, ballX, ballY  (CENTER coords)
local SLOT_SPRITES = {
  { 16, 40, 20, 50, 56, 52, 16, 34 },
  { 104, 18, 108, 28, 144, 27, 102, 25 },
  { 104, 42, 108, 52, 144, 51, 102, 49 },
  { 104, 66, 108, 76, 144, 75, 102, 73 },
  { 104, 90, 108, 100, 144, 99, 102, 97 },
  { 104, 114, 108, 124, 144, 123, 102, 121 },
}

-- pret sPartyBoxInfoRects — x,y relative to window
local INFO_LEFT = {
  nick = { 24, 11 }, level = { 32, 20 }, gender = { 64, 20 },
  hp = { 38, 36 }, hpMax = { 53, 36 }, hpBar = { 24, 35 },
}
local INFO_RIGHT = {
  nick = { 22, 3 }, level = { 32, 12 }, gender = { 64, 12 },
  hp = { 102, 12 }, hpMax = { 117, 12 }, hpBar = { 88, 10 },
}

-- pokefirered/src/data/party_menu.h:192
local SLOT_WIN_DOUBLE = {
  { left = 1, top = 1, w = 10, h = 7, kind = "main" },
  { left = 1, top = 8, w = 10, h = 7, kind = "main" },
  { left = 12, top = 1, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 5, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 9, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 13, w = 18, h = 3, kind = "wide" },
}

-- pokefirered/src/data/party_menu.h:81
local SLOT_SPRITES_DOUBLE = {
  { 16, 24, 20, 34, 56, 36, 16, 18 },
  { 16, 80, 20, 90, 56, 92, 16, 74 },
  { 104, 18, 108, 28, 144, 27, 102, 25 },
  { 104, 50, 108, 60, 144, 59, 102, 57 },
  { 104, 82, 108, 92, 144, 91, 102, 89 },
  { 104, 114, 108, 124, 144, 123, 102, 121 },
}

local function is_double()
  return PartyMenu._layout == "double"
end

local function slot_win(i)
  return (is_double() and SLOT_WIN_DOUBLE or SLOT_WIN)[i]
end

local function slot_sprites(i)
  return (is_double() and SLOT_SPRITES_DOUBLE or SLOT_SPRITES)[i]
end

-- pokefirered/src/party_menu.c:735
local function slot_info(i)
  if i == 1 or (i == 2 and is_double()) then return INFO_LEFT end
  return INFO_RIGHT
end

local function slot_filled(i)
  local mon = PartyMenu._party and PartyMenu._party[i]
  return mon ~= nil and (tonumber(mon.species or mon.speciesId) or 1) ~= 0
end

-- pokefirered/src/party_menu.c:1499
local function double_next_slot(slot, dir)
  while true do
    slot = slot + dir
    if slot < 1 or slot > 6 then return nil end
    if slot_filled(slot) then return slot end
  end
end

-- pokefirered/src/party_menu.c:1402
local function nav_double(cur, dir)
  local last = PartyMenu._lastSelectedSlot
  if dir == "up" then
    if cur == 1 then return 7 end
    local from = cur
    if cur == 7 then from = 7 end
    return double_next_slot(from, -1) or cur
  elseif dir == "down" then
    if cur == 7 then return 1 end
    return double_next_slot(cur, 1) or 7
  elseif dir == "right" then
    if cur == 1 then
      if last == 4 then
        if slot_filled(4) then return 4 end
      elseif slot_filled(3) then
        return 3
      end
    elseif cur == 2 then
      if last == 6 then
        if slot_filled(6) then return 6 end
      elseif slot_filled(5) then
        return 5
      end
    end
    return cur
  elseif dir == "left" then
    if cur == 3 or cur == 4 then
      PartyMenu._lastSelectedSlot = cur
      return 1
    elseif cur == 5 or cur == 6 then
      PartyMenu._lastSelectedSlot = cur
      return 2
    end
  end
  return cur
end

local function battle_nav_double(input)
  local oldCur = PartyMenu.cursor
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    if input:wasPressed(dir) then
      PartyMenu.cursor = nav_double(PartyMenu.cursor, dir)
      break
    end
  end
  if PartyMenu.cursor ~= oldCur then se(5) end
end

-- pokefirered/src/party_menu.c:5905
local function open_battle_actions_double(prevMode)
  local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
  se(5)
  if not slot_filled(2) or (mon and mon.isEgg) then
    PartyMenu.ACTIONS = { "SUMMARY", "CANCEL" }
  elseif prevMode == "battle_faint" then
    PartyMenu.ACTIONS = { "SEND OUT", "SUMMARY", "CANCEL" }
  else
    PartyMenu.ACTIONS = { "SHIFT", "SUMMARY", "CANCEL" }
  end
  PartyMenu._previousMode = prevMode
  PartyMenu.mode = "action"
  PartyMenu.actionCursor = 1
end

local function party_print(text, px, py, maxW)
  FrlgFont.draw(tostring(text or ""), px, py, {
    maxWidth = maxW or 56,
    colors = FrlgFont.COLOR.PARTY,
    small = true,
  })
end

local function right_align_3(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > 999 then n = 999 end
  return string.format("%3d", n)
end

local function destroy_id(id)
  if id ~= nil then Oam.destroySprite(id) end
end

local function destroy_party_oam()
  local slots = PartyMenu._oam
  if slots then
    for i = 1, 6 do
      local s = slots[i]
      if s then
        destroy_id(s.mon)
        destroy_id(s.ball)
        destroy_id(s.status)
      end
    end
  end
  destroy_id(PartyMenu._summaryIcon)
  PartyMenu._oam = nil
  PartyMenu._summaryIcon = nil
end

local SUB_STATUS = 0
local SUB_BALL = 4
local SUB_MON = 8

local MON_ICON_ANIM_DELAYS = {
  [0] = 6,  -- HP_BAR_FULL (100% HP)
  [1] = 8,  -- HP_BAR_GREEN (>50% HP)
  [2] = 14, -- HP_BAR_YELLOW (>20% HP)
  [3] = 22, -- HP_BAR_RED (>0% HP)
  [4] = 0,  -- HP_BAR_EMPTY (0 HP / fainted: still)
}

local MON_ICON_ANIM_DURATIONS = {
  [0] = 6 / 60,   -- HP_BAR_FULL (100% HP): 6 frames = 0.100s
  [1] = 8 / 60,   -- HP_BAR_GREEN (>50% HP): 8 frames = 0.1333s
  [2] = 14 / 60,  -- HP_BAR_YELLOW (>20% HP): 14 frames = 0.2333s
  [3] = 22 / 60,  -- HP_BAR_RED (>0% HP): 22 frames = 0.3667s
  [4] = 0,        -- HP_BAR_EMPTY (0 HP / fainted: still)
}

local function get_hp_bar_level(hp, maxHp, isEgg)
  if isEgg then return 4 end
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  if hp >= maxHp then return 0 end
  if hp > maxHp * 0.5 then return 1 end
  if hp > maxHp * 0.2 then return 2 end
  if hp > 0 then return 3 end
  return 4
end

local function idle_mon_offset(slotIndex)
  local spr = slot_sprites(slotIndex)
  if spr and spr[1] == 16 then
    return 0, -4
  end
  return -4, 0
end

local function advance_sprite_anim(sprite)
  local animNum = sprite.data[3] or 0
  local duration = MON_ICON_ANIM_DURATIONS[animNum] or (8 / 60)
  if duration <= 0 then
    sprite.data[2] = 0
    return 0
  end

  if love.timer and love.timer.getTime then
    local now = love.timer.getTime()
    local last = sprite._lastAnimTime or now
    local dt = now - last
    sprite._lastAnimTime = now
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    sprite._animElapsed = (sprite._animElapsed or 0) + dt
    while sprite._animElapsed >= duration do
      sprite._animElapsed = sprite._animElapsed - duration
      sprite.data[2] = 1 - (sprite.data[2] or 0)
    end
  else
    local delay = MON_ICON_ANIM_DELAYS[animNum] or 8
    sprite.data[1] = (sprite.data[1] or 0) + 1
    if sprite.data[1] >= delay then
      sprite.data[1] = 0
      sprite.data[2] = 1 - (sprite.data[2] or 0)
    end
  end

  return sprite.data[2] or 0
end

local function SpriteCB_BouncePartyMonIcon(sprite)
  local f = advance_sprite_anim(sprite)
  sprite.x2 = 0
  if (sprite.data[3] or 0) == 4 then
    sprite.y2 = 0
  elseif f == 0 then
    sprite.y2 = -3
  else
    sprite.y2 = 1
  end
  if sprite._quads and sprite._quads[f] then
    sprite.quad = sprite._quads[f]
  end
end

local function SpriteCB_UpdatePartyMonIcon(sprite)
  local f = advance_sprite_anim(sprite)
  local slotIdx = sprite.data[4] or 1
  local x2, y2 = idle_mon_offset(slotIdx)
  sprite.x2 = x2
  sprite.y2 = y2
  if sprite._quads and sprite._quads[f] then
    sprite.quad = sprite._quads[f]
  end
end

local function ensure_slot_sprites(i, mon, selected)
  PartyMenu._oam = PartyMenu._oam or {}
  local slot = PartyMenu._oam[i]
  if not slot then
    slot = {}
    PartyMenu._oam[i] = slot
  end
  local spr = slot_sprites(i)
  if not spr or not mon then
    destroy_id(slot.mon); slot.mon = nil
    destroy_id(slot.ball); slot.ball = nil
    destroy_id(slot.status); slot.status = nil
    return
  end

  local mx, my = spr[1], spr[2]
  local bx, by = spr[7], spr[8]
  local sx, sy = spr[5], spr[6]

  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 1
  local hpLevel = get_hp_bar_level(hp, maxHp, mon.isEgg)

  local icon = Pokemon.icon(Pokemon.speciesOf(mon))
  local q0 = icon and icon.quads and icon.quads[0]
  if not slot.mon then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_32,
      priority = 1,
      image = icon and icon.image,
      quad = q0,
      animPaused = true,
    }, mx, my, SUB_MON))
    slot.mon = id
  else
    Oam.setPos(slot.mon, mx, my)
    local ms = Oam.get(slot.mon)
    if ms then
      ms.image = icon and icon.image
      ms.subpriority = SUB_MON
    end
  end
  if slot.mon then
    local s = Oam.get(slot.mon)
    if s then
      s._quads = icon and icon.quads
      s.data[3] = hpLevel
      s.data[4] = i
    end
    if selected then
      Oam.setCallback(slot.mon, SpriteCB_BouncePartyMonIcon)
      if not slot._wasSelected then
        if s then
          s.data[1] = 0
          s.x2, s.y2 = 0, ((s.data[2] or 0) == 1 and 1 or -3)
        end
      end
      slot._wasSelected = true
    else
      Oam.setCallback(slot.mon, SpriteCB_UpdatePartyMonIcon)
      if slot._wasSelected then
        if s then
          s.data[1] = 0
          local x2, y2 = idle_mon_offset(i)
          s.x2, s.y2 = x2, y2
        end
      end
      slot._wasSelected = false
    end
    Oam.setInvisible(slot.mon, PartyMenu.mode == "summary")
  end

  local balls = PartyChrome.ballEntry()
  local ballFrame = selected and 1 or 0
  local bq = balls and balls.quads and balls.quads[ballFrame]
  if not slot.ball then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_32,
      priority = 1,
      image = balls and balls.image,
      quad = bq,
    }, bx, by, SUB_BALL))
    slot.ball = id
  else
    Oam.setPos(slot.ball, bx, by)
    if balls and balls.image then Oam.setImage(slot.ball, balls.image, bq) end
    local bs = Oam.get(slot.ball)
    if bs then bs.subpriority = SUB_BALL end
  end
  if slot.ball then
    Oam.setOffset(slot.ball, 0, 0)
    Oam.setInvisible(slot.ball, PartyMenu.mode == "summary")
  end

  local statusFr = PartyChrome.statusFrameFor(mon.status)
  local stImg, stQ = PartyChrome.statusEntry(statusFr)
  if statusFr > 0 and stImg then
    if not slot.status then
      local id = select(1, Oam.createSprite({
        dims = Oam.HRECT_32x8,
        priority = 1,
        image = stImg,
        quad = stQ,
      }, sx, sy, SUB_STATUS))
      slot.status = id
    else
      Oam.setPos(slot.status, sx, sy)
      Oam.setImage(slot.status, stImg, stQ)
      local ss = Oam.get(slot.status)
      if ss then ss.subpriority = SUB_STATUS end
    end
    if slot.status then
      Oam.setInvisible(slot.status, PartyMenu.mode == "summary")
    end
  else
    destroy_id(slot.status)
    slot.status = nil
  end
end

local function sync_all_oam()
  local party = PartyMenu._party or {}
  for i = 1, 6 do
    local mon = party[i]
    local selected = (i == PartyMenu.cursor or PartyMenu.switchFrom == i)
    ensure_slot_sprites(i, mon, selected)
  end
end

-- pokefirered/src/party_menu.c:6005
function PartyMenu.battleOrder(st)
  local party = st and st.playerParty or {}
  local n = 0
  for i = 1, 6 do if party[i] then n = i end end
  local order = st._partyOrder
  local valid = type(order) == "table" and #order == n
  if valid then
    local seen = {}
    for i = 1, n do
      local v = order[i]
      if type(v) ~= "number" or v < 1 or v > n or seen[v] then valid = false break end
      seen[v] = true
    end
  end
  local b0 = (st.battlers and st.battlers[0]) or st.player
  local b2 = st.double and st.battlers and st.battlers[2] or nil
  if not valid then
    order = {}
    local used = {}
    for _, b in ipairs({ b0, b2 }) do
      local pi = b and tonumber(b.partyIndex)
      if pi and pi >= 1 and pi <= n and not used[pi] then
        order[#order + 1] = pi
        used[pi] = true
      end
    end
    for i = 1, n do
      if not used[i] then order[#order + 1] = i end
    end
    st._partyOrder = order
  end
  -- pokefirered/src/party_menu.c:5972
  for pos, b in ipairs({ b0, b2 }) do
    local want = b and tonumber(b.partyIndex)
    if want and order[pos] ~= want then
      for j = 1, n do
        if order[j] == want then
          order[pos], order[j] = order[j], order[pos]
          break
        end
      end
    end
  end
  return order
end

-- pokefirered/src/party_menu.c:6199
local function apply_battle_order(party, overlay, opts)
  local order = opts.battleOrder
  if order == nil then
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    if not (st and st.playerParty and st.playerParty == party) then return party, overlay, opts end
    order = PartyMenu.battleOrder(st)
  end
  local view = {}
  for i, pi in ipairs(order) do view[i] = party[pi] end
  local viewOverlay = overlay
  if type(overlay) == "table" then
    viewOverlay = {}
    for i, pi in ipairs(order) do viewOverlay[i] = overlay[pi] end
  end
  local o = {}
  for k, v in pairs(opts) do o[k] = v end
  local active = opts.activeSlot
  for i, pi in ipairs(order) do
    if pi == active then o.activeSlot = i break end
  end
  local onSelect, validate = opts.onSelect, opts.validate
  if onSelect then
    o.onSelect = function(d, mon) return onSelect(d and order[d], mon) end
  end
  if validate then
    o.validate = function(d) return validate(d and order[d]) end
  end
  PartyMenu._order = order
  return view, viewOverlay, o
end

function PartyMenu.show(sessionParty, moveOverlay, opts)
  if type(moveOverlay) == "table" and opts == nil and (moveOverlay.mode or moveOverlay.session or moveOverlay.battle or moveOverlay.onSelect or moveOverlay.activeSlot) then
    opts = moveOverlay
    moveOverlay = nil
  end
  opts = opts or {}
  PartyMenu._order = nil
  if opts.mode == "battle_switch" or opts.mode == "battle_faint" or (opts.mode == "use" and opts.battleOrder) then
    local party0 = sessionParty or (opts.session and opts.session.party)
    local ov0 = moveOverlay or (opts.session and (opts.session.move_overlay or opts.session.moveOverlay))
    if party0 then
      sessionParty, moveOverlay, opts = apply_battle_order(party0, ov0, opts)
    end
  end
  destroy_party_oam()
  PartyMenu.open = true
  PartyMenu._party = sessionParty or (opts.session and opts.session.party)
  PartyMenu._overlay = moveOverlay or (opts.session and (opts.session.move_overlay or opts.session.moveOverlay))
  PartyMenu._session = opts.session
  PartyMenu._bag = opts.bag or (opts.session and (opts.session.bag or opts.session.inventory))
  PartyMenu._item = opts.item
  PartyMenu._activeSlot = opts.activeSlot or 1
  PartyMenu._layout = (opts.layout == "double") and "double" or "single"
  PartyMenu._battle = opts.battle or (opts.mode == "battle_switch" or opts.mode == "battle_faint")
  PartyMenu.cursor = 1
  PartyMenu.mode = opts.mode or "list"
  PartyMenu._previousMode = PartyMenu.mode
  PartyMenu.summaryPage = 1
  PartyMenu.switchFrom = nil
  PartyMenu._onClose = opts.onClose
  PartyMenu._onSelect = opts.onSelect
  PartyMenu._validate = opts.validate
  PartyMenu._messageText = nil
  PartyMenu._onMessageDismiss = nil
  PartyMenu.actionCursor = 1
  PartyMenu.itemActionCursor = 1
  PartyMenu._lastSelectedSlot = 1
  if not Pokemon._names then Pokemon.install(nil) end
  PartyChrome.install(nil)
  Stack.push("party", PartyMenu, { hideBelow = true })
  sync_all_oam()
end

function PartyMenu.close()
  PartyMenu.open = false
  PartyMenu.mode = "list"
  destroy_party_oam()
  Stack.pop("party")
  local cb = PartyMenu._onClose
  PartyMenu._onClose = nil
  if cb then cb() end
end

function PartyMenu.movesFor(slot)
  local mon = PartyMenu._party and PartyMenu._party[slot]
  if not mon then return {} end
  local moves = {}
  local ov = PartyMenu._overlay and PartyMenu._overlay[slot]
  for i = 1, 4 do
    local o = ov and ov[i]
    if o and o.frlgMoveId then
      moves[i] = { id = o.frlgMoveId, pp = o.pp, quarantined = true }
    else
      local rawM = mon.moves and mon.moves[i]
      local mid = type(rawM) == "table" and (rawM.id or rawM.move or rawM.num or rawM.moveId or rawM.name or rawM[1]) or rawM
      local mpp = type(rawM) == "table" and (rawM.pp or (mon.pp and mon.pp[i])) or (mon.pp and mon.pp[i])
      moves[i] = {
        id = mid,
        pp = mpp,
        quarantined = false,
      }
    end
  end
  return moves
end

function PartyMenu.isOpen()
  return PartyMenu.open
end

local function party_count()
  return #(PartyMenu._party or {})
end

local function swap_slots(a, b)
  if not PartyMenu._party or a == b then return end
  if not PartyMenu._battle then
    local Pokemon=require("src.core.game3.pokemon")
    require("src.core.game3.quest_log_recorder").event(PartyMenu._session,"SwitchMon1WithMon2",
      {Pokemon.displayMonName(PartyMenu._party[a]),Pokemon.displayMonName(PartyMenu._party[b])})
  end
  PartyMenu._party[a], PartyMenu._party[b] = PartyMenu._party[b], PartyMenu._party[a]
  if PartyMenu._overlay then
    PartyMenu._overlay[a], PartyMenu._overlay[b] =
      PartyMenu._overlay[b], PartyMenu._overlay[a]
  end
end

function PartyMenu.dismissMessage()
  if PartyMenu.mode == "message" then
    local cb = PartyMenu._onMessageDismiss
    PartyMenu._messageText = nil
    PartyMenu._onMessageDismiss = nil
    PartyMenu.mode = "list"
    if cb then
      cb()
    end
  end
end

function PartyMenu.showMessage(text, onDismiss)
  PartyMenu.mode = "message"
  PartyMenu._messageText = text
  PartyMenu._onMessageDismiss = onDismiss
end

PartyMenu._yesNoPrompt = nil
PartyMenu._yesNoCallback = nil
PartyMenu._yesNoCursor = 1
PartyMenu._forgetPrompt = nil
PartyMenu._forgetMoves = nil
PartyMenu._forgetCallback = nil
PartyMenu._forgetCursor = 1

function PartyMenu.showYesNo(promptText, cb)
  PartyMenu.mode = "yesno"
  PartyMenu._yesNoPrompt = promptText
  PartyMenu._yesNoCallback = cb
  PartyMenu._yesNoCursor = 1
end

function PartyMenu.showForgetPrompt(promptText, moveNames, cb)
  PartyMenu.mode = "forget"
  PartyMenu._forgetPrompt = promptText
  PartyMenu._forgetMoves = moveNames
  PartyMenu._forgetCallback = cb
  PartyMenu._forgetCursor = 1
end

function PartyMenu.reloadSprites()
  destroy_party_oam()
  sync_all_oam()
end

PartyMenu._hpAnim = nil

function PartyMenu.startHpAnim(slot, startHp, targetHp, maxHp, onDone)
  PartyMenu._hpAnim = {
    slot = slot,
    current = startHp,
    target = targetHp,
    maxHp = maxHp,
    speed = math.max(25, math.abs(targetHp - startHp) * 2.5),
    onDone = onDone,
  }
end

function PartyMenu.update(dt)
  local anim = PartyMenu._hpAnim
  if anim then
    dt = dt or (1 / 60)
    if anim.current < anim.target then
      anim.current = math.min(anim.target, anim.current + anim.speed * dt)
    elseif anim.current > anim.target then
      anim.current = math.max(anim.target, anim.current - anim.speed * dt)
    end
    if anim.current == anim.target then
      local cb = anim.onDone
      PartyMenu._hpAnim = nil
      if cb then cb() end
    end
  end

  local LearnMove = package.loaded["src.core.game3.battle.learn_move"]
  if LearnMove and LearnMove.busy and LearnMove.busy() and LearnMove.pump then
    LearnMove.pump()
  end
end

function PartyMenu.handleInput(input)
  local n = party_count()
  if n < 1 then
    if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
      PartyMenu.close()
    end
    return
  end

  -- Fast-forward / complete HP animation on button press
  if PartyMenu._hpAnim then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      local anim = PartyMenu._hpAnim
      anim.current = anim.target
      local cb = anim.onDone
      PartyMenu._hpAnim = nil
      if cb then cb() end
    end
    return
  end

  if PartyMenu.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      PartyMenu.dismissMessage()
    end
    return
  end

  if PartyMenu.mode == "yesno" then
    if input:wasPressed("up") or input:wasPressed("down") then
      PartyMenu._yesNoCursor = (PartyMenu._yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local cb = PartyMenu._yesNoCallback
      local yes = (PartyMenu._yesNoCursor == 1)
      PartyMenu._yesNoCallback = nil
      PartyMenu._yesNoPrompt = nil
      if cb then cb(yes) end
    elseif input:wasPressed("b") then
      se(9)
      local cb = PartyMenu._yesNoCallback
      PartyMenu._yesNoCallback = nil
      PartyMenu._yesNoPrompt = nil
      if cb then cb(false) end
    end
    return
  end

  if PartyMenu.mode == "forget" then
    local moves = PartyMenu._forgetMoves or {}
    local total = #moves
    if total > 0 then
      if input:wasPressed("up") then
        PartyMenu._forgetCursor = ((PartyMenu._forgetCursor - 2) % total) + 1
        se(5)
      elseif input:wasPressed("down") then
        PartyMenu._forgetCursor = (PartyMenu._forgetCursor % total) + 1
        se(5)
      elseif input:wasPressed("a") then
        se(5)
        local cb = PartyMenu._forgetCallback
        local idx = PartyMenu._forgetCursor
        PartyMenu._forgetCallback = nil
        PartyMenu._forgetMoves = nil
        PartyMenu._forgetPrompt = nil
        if cb then cb(idx - 1) end
      elseif input:wasPressed("b") then
        se(9)
        local cb = PartyMenu._forgetCallback
        PartyMenu._forgetCallback = nil
        PartyMenu._forgetMoves = nil
        PartyMenu._forgetPrompt = nil
        if cb then cb(nil) end
      end
    end
    return
  end

  if PartyMenu.mode == "summary" then
    if not SummaryMenu.isOpen() then
      destroy_party_oam()
      SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
        session = PartyMenu._session,
        onClose = function()
          PartyMenu.mode = "list"
          sync_all_oam()
        end,
      })
    end
    SummaryMenu.handleInput(input)
    return
  end

  if PartyMenu.mode == "switch" then
    local oldCur = PartyMenu.cursor
    if input:wasPressed("up") then
      PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
    elseif input:wasPressed("left") then
      PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    elseif input:wasPressed("right") then
      PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    end
    if PartyMenu.cursor ~= oldCur then
      se(5)
    end
    if input:wasPressed("a") then
      if PartyMenu.cursor == 7 then
        se(9)
        PartyMenu.switchFrom = nil
        PartyMenu.mode = "list"
      else
        se(5)
        swap_slots(PartyMenu.switchFrom or PartyMenu.cursor, PartyMenu.cursor)
        PartyMenu.switchFrom = nil
        PartyMenu.mode = "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.switchFrom = nil
      PartyMenu.mode = "list"
    end
    return
  end

  if PartyMenu.mode == "item_action" then
    local actions = PartyMenu.ITEM_ACTIONS
    if input:wasPressed("up") then
      PartyMenu.itemActionCursor = ((PartyMenu.itemActionCursor - 2) % #actions) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.itemActionCursor = (PartyMenu.itemActionCursor % #actions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local act = actions[PartyMenu.itemActionCursor]
      if act == "TAKE" then
        local ok, reason, msgText = ItemUse.takeFromMon(PartyMenu._session, PartyMenu._bag, PartyMenu.cursor)
        if ok then se(5) else se(9) end
        PartyMenu.showMessage(msgText, function()
          PartyMenu.mode = "list"
        end)
      elseif act == "GIVE" then
        local BagMenu = require("src.ui.game3.bag_menu")
        BagMenu.show(PartyMenu._session, {
          bag = PartyMenu._bag,
          onClose = function()
            PartyMenu.mode = "list"
          end,
        })
      else
        se(9)
        PartyMenu.mode = "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.mode = "list"
    end
    return
  end

  if PartyMenu.mode == "stat_growth" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      if PartyMenu._statGrowthPage == 1 then
        se(5)
        PartyMenu._statGrowthPage = 2
      else
        se(5)
        PartyMenu.mode = "message"
        local cb = PartyMenu._statGrowthDone
        PartyMenu._statGrowthDone = nil
        if cb then cb() end
      end
    end
    return
  end

  if PartyMenu.mode == "action" then
    local actions = PartyMenu.ACTIONS
    if input:wasPressed("up") then
      PartyMenu.actionCursor = ((PartyMenu.actionCursor - 2) % #actions) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.actionCursor = (PartyMenu.actionCursor % #actions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local act = actions[PartyMenu.actionCursor]
      if act == "SHIFT" or act == "SEND OUT" or (PartyMenu._previousMode == "battle_switch" and act == "SWITCH") then
        se(5)
        local cb = PartyMenu._onSelect
        local chosen = PartyMenu.cursor
        local why = PartyMenu._validate and PartyMenu._validate(chosen)
        if why then
          local back = PartyMenu._previousMode
          PartyMenu.showMessage(why, function() PartyMenu.mode = back end)
          return
        end
        PartyMenu.close()
        if cb then cb(chosen, PartyMenu._party and PartyMenu._party[chosen]) end
      elseif act == "SUMMARY" then
        local prevMode = PartyMenu._previousMode or "list"
        PartyMenu.mode = "list"
        destroy_party_oam()
        SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
          session = PartyMenu._session,
          onClose = function()
            PartyMenu.mode = prevMode
            sync_all_oam()
          end,
        })
      elseif act == "SWITCH" then
        se(5)
        PartyMenu.switchFrom = PartyMenu.cursor
        PartyMenu.mode = "switch"
      elseif act == "ITEM" then
        se(5)
        PartyMenu.mode = "item_action"
        PartyMenu.itemActionCursor = 1
      elseif PartyMenu._fieldMoveNames and PartyMenu._fieldMoveNames[act] then
        local FieldMoves = require("src.core.game3.field_moves")
        local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
        if act == "SOFTBOILED" or act == "MILK DRINK" then
          local maxHp = mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or 0
          local cost = math.floor(maxHp / 5)
          local curHp = mon and (mon.hp or 0) or 0
          if curHp <= cost or cost <= 0 then
            se(9)
            PartyMenu.showMessage("Not enough HP!", function()
              PartyMenu.mode = "list"
            end)
            return
          end
          se(5)
          PartyMenu._softboiledDonorSlot = PartyMenu.cursor
          PartyMenu.mode = "softboiled"
          return
        else
          local P = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
          local Collision = require("src.core.game3.collision")
          local Objects = require("src.core.game3.objects")
          local Map = require("src.core.game3.map")
          local Space = package.loaded["src.core.game3.scripting.space"]
          local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
          local d = DELTA[P.facing or "down"] or DELTA.down
          local fx, fy = P.cellX + d[1], P.cellY + d[2]
          local facingObj = Objects.at(fx, fy)
          local isWater = Collision.isWater and Collision.isWater(fx, fy)
          local isGrass = Collision.isGrass and Collision.isGrass(fx, fy)
          local mapDef = Map.currentDef()
          local ctx = {
            party = PartyMenu._party,
            mon = mon,
            store = Space and Space.store,
            session = PartyMenu._session,
            facingObject = facingObj,
            isFacingWater = isWater,
            isSurfing = P.surfing == true,
            hasCuttableGrass = isGrass or (Collision.isGrass and Collision.isGrass(P.cellX, P.cellY)),
            mapType = mapDef and mapDef.type,
          }
          local res = FieldMoves.fromMenu(act, ctx)
          if not res or not res.ok then
            se(9)
            PartyMenu.showMessage((res and res.text) or "Can't use that here.", function()
              PartyMenu.mode = "list"
            end)
          else
            se(5)
            PartyMenu.close()
            local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
            if Field.executeFieldMove then
              Field.executeFieldMove(res)
            end
          end
          return
        end
      else
        se(9)
        PartyMenu.mode = PartyMenu._previousMode or "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.mode = PartyMenu._previousMode or "list"
    end
    return
  end

  if PartyMenu.mode == "softboiled" then
    local oldCur = PartyMenu.cursor
    local FieldMoves = require("src.core.game3.field_moves")
    if input:wasPressed("up") then
      PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
    elseif input:wasPressed("left") then
      PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    elseif input:wasPressed("right") then
      PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    end
    if PartyMenu.cursor ~= oldCur then
      se(5)
    end
    if input:wasPressed("a") then
      if PartyMenu.cursor == 7 then
        se(9)
        PartyMenu.mode = "list"
      else
        local userMon = PartyMenu._party and PartyMenu._party[PartyMenu._softboiledDonorSlot]
        local targetMon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
        local ok, userHp, targetHp = FieldMoves.softboiledTransfer(userMon, targetMon)
        if not ok then
          se(9)
          PartyMenu.showMessage("It won't have any effect.", function()
            PartyMenu.mode = "softboiled"
          end)
        else
          se(11)
          PartyMenu.mode = "list"
        end
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.mode = "list"
    end
    return
  end

  if PartyMenu.mode == "battle_switch" or PartyMenu.mode == "battle_faint" then
    local sendOut = PartyMenu.mode == "battle_faint"
    if is_double() then
      battle_nav_double(input)
    else
      local oldCur = PartyMenu.cursor
      if input:wasPressed("up") then
        PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
      elseif input:wasPressed("down") then
        PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
      elseif input:wasPressed("left") then
        PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
      elseif input:wasPressed("right") then
        PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
      end
      if PartyMenu.cursor ~= oldCur then se(5) end
    end
    local cancel = input:wasPressed("b") or (input:wasPressed("a") and PartyMenu.cursor == 7)
    if cancel then
      -- pokefirered/src/party_menu.c:1229
      if sendOut then
        se(26)
      else
        se(5)
        PartyMenu.close()
      end
    elseif input:wasPressed("a") then
      open_battle_actions_double(PartyMenu.mode)
    end
    return
  end

  -- Selection mode for item USE
  if PartyMenu.mode == "use" then
    local oldCur = PartyMenu.cursor
    if is_double() then
      battle_nav_double(input)
      oldCur = PartyMenu.cursor
    elseif input:wasPressed("up") then
      PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
    elseif input:wasPressed("left") then
      PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    elseif input:wasPressed("right") then
      PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    end
    if PartyMenu.cursor ~= oldCur then
      se(5)
    end
    if input:wasPressed("a") then
      if PartyMenu.cursor == 7 then
        se(9)
        if PartyMenu._onSelect then
          PartyMenu._onSelect(nil)
        else
          PartyMenu.close()
        end
        return
      end
      if PartyMenu._onSelect then
        PartyMenu._onSelect(PartyMenu.cursor)
        return
      end
      local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
      if not mon then return end

      if mon.isEgg then
        se(9)
        PartyMenu.showMessage("An EGG can't be used on.", function()
          PartyMenu.mode = "use"
        end)
        return
      end

      -- Case 1: TM / HM
      if ItemsData.isTm(PartyMenu._item) then
        local status, preflightMsg, moveId, moveName = ItemUse.checkTmPreflight(mon, PartyMenu._item)
        if status == "knows" or status == "incompatible" or status == "invalid" then
          se(9)
          PartyMenu.showMessage(preflightMsg, function()
            PartyMenu.mode = "use"
          end)
        elseif status == "ok" then
          se(5)
          PartyMenu.showYesNo(preflightMsg, function(yes)
            if not yes then
              PartyMenu.mode = "use"
              return
            end
            local isHm = ItemsData.isHm(PartyMenu._item)
            local monName = Pokemon.displayMonName(mon)

            if Pokemon.moveSlotCount(mon) < 4 then
              local ok = Pokemon.teachMove(mon, moveId)
              if ok then
                require("src.core.game3.quest_log_recorder").event(PartyMenu._session,
                  isHm and "MonLearnedMoveFromHM" or "MonLearnedMoveFromTM",{monName,moveName})
                if not isHm then
                  Bag.remove(PartyMenu._bag, PartyMenu._item, 1)
                end
                pcall(function() require("src.core.game3.audio").playFanfare(257) end)
                PartyMenu.showMessage(string.format("%s learned\n%s!", monName, moveName), function()
                  PartyMenu.close()
                end)
              else
                PartyMenu.mode = "use"
              end
            else
              -- Full moveset: Forget Move flow
              local LearnMove = require("src.core.game3.battle.learn_move")
              LearnMove.begin({
                mon = mon,
                moveId = moveId,
                displayName = monName,
                pushMsg = function(t, cb) PartyMenu.showMessage(t, cb) end,
                askYesNo = function(a, b)
                  local cb = (type(a) == "function") and a or b
                  local prompt = (type(a) == "string") and a or PartyMenu._messageText or ""
                  PartyMenu.showYesNo(prompt, function(yes)
                    if cb then cb(yes == true) end
                  end)
                end,
                askForget = function(a, b, c)
                  local cb = (type(b) == "function") and b or c
                  local SummaryMenu = require("src.ui.game3.summary_menu")
                  local LearnMove = require("src.core.game3.battle.learn_move")
                  local moveToLearn = (LearnMove and LearnMove._moveId) or moveId
                  destroy_party_oam()
                  SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
                    mode = "select_move",
                    moveToLearn = moveToLearn,
                    onSelectMove = function(slotIdx)
                      sync_all_oam()
                      if cb then cb(slotIdx) end
                    end,
                  })
                end,
                onDone = function(learned)
                  if learned then
                    require("src.core.game3.quest_log_recorder").event(PartyMenu._session,
                      isHm and "MonLearnedMoveFromHM" or "MonLearnedMoveFromTM",{monName,moveName})
                    if not isHm then
                      Bag.remove(PartyMenu._bag, PartyMenu._item, 1)
                    end
                    pcall(function() require("src.core.game3.audio").playFanfare(257) end)
                    PartyMenu.close()
                  else
                    PartyMenu.showMessage(string.format("%s did not learn\n%s.", monName, moveName), function()
                      PartyMenu.mode = "use"
                    end)
                  end
                end,
              })
            end
          end)
        end
        return
      end

      -- Case 2: Rare Candy / Level up item
      if ItemsData.fieldUseKind(PartyMenu._item) == "level" then
        local lvl = tonumber(mon.level) or 1
        local hp = tonumber(mon.hp) or 0
        if lvl >= 100 or hp <= 0 then
          se(9)
          PartyMenu.showMessage("It won't have any effect.", function()
            PartyMenu.mode = "use"
          end)
          return
        end

        se(1)
        local oldStats = get_mon_stats(mon)
        local oldMax = oldStats.maxHp
        local oldHp = hp

        Bag.remove(PartyMenu._bag, PartyMenu._item, 1)
        require("src.core.game3.quest_log_recorder").event(PartyMenu._session,
          "UsedItemOnMonAtThisLocation",{ItemsData.displayName(PartyMenu._item),Pokemon.displayMonName(mon)})
        mon.level = lvl + 1
        Pokemon.applyStats(mon)
        local newStats = get_mon_stats(mon)
        local newMax = newStats.maxHp
        local newHp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
        mon.hp = newHp
        ItemUse.levelUpEvent(mon, mon.level)

        pcall(function() require("src.core.game3.audio").playFanfare(257) end) -- MUS_LEVEL_UP (257)

        local monName = Pokemon.displayMonName(mon)
        local lvlMsg = string.format("%s was elevated to\nLv. %d.", monName, mon.level)
        local slot = PartyMenu.cursor

        local function check_evolution()
          local Evolution = require("src.core.game3.evolution")
          local toSpecies = Evolution.levelTarget(mon, PartyMenu._session)
          if toSpecies then
            destroy_party_oam()
            local EvolutionScene = require("src.ui.game3.evolution_scene")
            local Audio = require("src.core.game3.audio")
            EvolutionScene.start(mon, toSpecies, {
              session = PartyMenu._session,
              bag = PartyMenu._bag,
              canStop = true,
              savedSong = Audio._mapSong,
              onDone = function(result)
                PartyMenu.reloadSprites()
                PartyMenu.mode = "list"
              end,
            })
          else
            if Bag.has(PartyMenu._bag, PartyMenu._item, 1) then
              PartyMenu.mode = "use"
            else
              PartyMenu.close()
            end
          end
        end

        local function after_level_up()
          local spId = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId)
          local newMoves = Pokemon.movesLearnedAt(spId, mon.level)
          if #newMoves > 0 then
            local LearnMove = require("src.core.game3.battle.learn_move")
            local started = LearnMove.beginQueue(mon, { mon.level }, {
              displayName = monName,
              pushMsg = function(t, cb) PartyMenu.showMessage(t, cb) end,
              askYesNo = function(a, b)
                local cb = (type(a) == "function") and a or b
                local prompt = (type(a) == "string") and a or PartyMenu._messageText or ""
                PartyMenu.showYesNo(prompt, function(yes)
                  if cb then cb(yes == true) end
                end)
              end,
              askForget = function(a, b, c)
                local cb = (type(b) == "function") and b or c
                local SummaryMenu = require("src.ui.game3.summary_menu")
                local LearnMove = require("src.core.game3.battle.learn_move")
                destroy_party_oam()
                SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
                  mode = "select_move",
                  moveToLearn = LearnMove._moveId,
                  onSelectMove = function(slotIdx)
                    sync_all_oam()
                    if cb then cb(slotIdx) end
                  end,
                })
              end,
              onDone = function()
                check_evolution()
              end,
            })
            if not started then
              check_evolution()
            end
          else
            check_evolution()
          end
        end

        PartyMenu._messageText = lvlMsg
        local function show_growth()
          PartyMenu.showStatGrowth(mon, oldStats, newStats, after_level_up)
        end

        if newHp > oldHp then
          PartyMenu.startHpAnim(slot, oldHp, newHp, newMax, show_growth)
        else
          show_growth()
        end
        return
      end

      -- Case 3: Evolution Stone
      if ItemsData.isEvolutionStone(PartyMenu._item) then
        local Evolution = require("src.core.game3.evolution")
        local toSpecies = Evolution.itemTarget(mon, PartyMenu._item, PartyMenu._session)
        if not toSpecies then
          se(9)
          PartyMenu.showMessage("It won't have any effect.", function()
            PartyMenu.mode = "use"
          end)
        else
          Bag.remove(PartyMenu._bag, PartyMenu._item, 1)
          destroy_party_oam()
          local EvolutionScene = require("src.ui.game3.evolution_scene")
          local Audio = require("src.core.game3.audio")
          EvolutionScene.start(mon, toSpecies, {
            session = PartyMenu._session,
            bag = PartyMenu._bag,
            canStop = false,
            savedSong = Audio._mapSong,
            onDone = function(result)
              PartyMenu.reloadSprites()
              PartyMenu.mode = "list"
            end,
          })
        end
        return
      end

      -- Case 4: General Medicine / Potions / Status
      local startHp = tonumber(mon and mon.hp) or 0
      local maxHp = tonumber(mon and (mon.maxHp or mon.maxhp)) or 1
      local realSlot = (PartyMenu._order and PartyMenu._order[PartyMenu.cursor]) or PartyMenu.cursor
      local ok, reason, msgText = ItemUse.useField(PartyMenu._session, PartyMenu._bag, PartyMenu._item, realSlot)
      local endHp = tonumber(mon and mon.hp) or startHp
      if ok then
        se(2)
        local hasRemaining = Bag.has(PartyMenu._bag, PartyMenu._item, 1)
        if endHp > startHp then
          PartyMenu.startHpAnim(PartyMenu.cursor, startHp, endHp, maxHp, function()
            PartyMenu.showMessage(msgText, function()
              if hasRemaining then
                PartyMenu.mode = "use"
              else
                PartyMenu.close()
              end
            end)
          end)
        else
          PartyMenu.showMessage(msgText, function()
            if hasRemaining then
              PartyMenu.mode = "use"
            else
              PartyMenu.close()
            end
          end)
        end
      else
        se(9)
        PartyMenu.showMessage(msgText or "It won't have any effect.", function()
          PartyMenu.mode = "use"
        end)
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Selection mode for item GIVE
  if PartyMenu.mode == "give" then
    local oldCur = PartyMenu.cursor
    if input:wasPressed("up") then
      PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
    elseif input:wasPressed("left") then
      PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    elseif input:wasPressed("right") then
      PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    end
    if PartyMenu.cursor ~= oldCur then
      se(5)
    end
    if input:wasPressed("a") then
      if PartyMenu.cursor == 7 then
        se(9)
        PartyMenu.close()
      else
        local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
        if mon and mon.isEgg then
          se(9)
          PartyMenu.showMessage("An EGG can't hold an item.", function()
            PartyMenu.close()
          end)
        else
          local ok, reason, msgText = ItemUse.giveToMon(PartyMenu._session, PartyMenu._bag, PartyMenu._item, PartyMenu.cursor)
          if ok then se(5) else se(9) end
          PartyMenu.showMessage(msgText, function()
            PartyMenu.close()
          end)
        end
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Selection mode for generic choose
  if PartyMenu.mode == "choose" then
    local oldCur = PartyMenu.cursor
    if input:wasPressed("up") then
      PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
    elseif input:wasPressed("left") then
      PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    elseif input:wasPressed("right") then
      PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
    end
    if PartyMenu.cursor ~= oldCur then
      se(5)
    end
    if input:wasPressed("a") then
      if PartyMenu.cursor == 7 then
        se(9)
        PartyMenu.close()
      else
        se(5)
        local cb = PartyMenu._onSelect
        local why = PartyMenu._validate and PartyMenu._validate(PartyMenu.cursor)
        if why then
          local back = PartyMenu._previousMode
          PartyMenu.showMessage(why, function() PartyMenu.mode = back end)
          return
        end
        PartyMenu.close()
        if cb then cb(PartyMenu.cursor, PartyMenu._party and PartyMenu._party[PartyMenu.cursor]) end
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Default list mode
  local oldCur = PartyMenu.cursor
  if input:wasPressed("up") then
    PartyMenu.cursor = nav_up(PartyMenu.cursor, n)
  elseif input:wasPressed("down") then
    PartyMenu.cursor = nav_down(PartyMenu.cursor, n)
  elseif input:wasPressed("left") then
    PartyMenu.cursor, PartyMenu._lastSelectedSlot = nav_left(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
  elseif input:wasPressed("right") then
    PartyMenu.cursor = nav_right(PartyMenu.cursor, n, PartyMenu._lastSelectedSlot)
  end
  if PartyMenu.cursor ~= oldCur then
    se(5)
  end
  if input:wasPressed("a") then
    if PartyMenu.cursor == 7 then
      se(9)
      PartyMenu.close()
      return
    end
    se(5)
    local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
    local FieldMoves = require("src.core.game3.field_moves")
    local actions = {}
    local fmNames = {}
    if mon and not mon.isEgg and mon.moves then
      for _, m in ipairs(mon.moves) do
        local mId = FieldMoves.normalizeMoveId(m)
        local mName = mId and FieldMoves.MOVE_NAME_BY_ID[mId]
        if mName then
          local label = mName:gsub("_", " ")
          if not fmNames[label] then
            actions[#actions + 1] = label
            fmNames[label] = true
          end
        end
      end
    end
    actions[#actions + 1] = "SUMMARY"
    actions[#actions + 1] = "SWITCH"
    if not (mon and mon.isEgg) then
      actions[#actions + 1] = "ITEM"
    end
    actions[#actions + 1] = "CANCEL"
    PartyMenu.ACTIONS = actions
    PartyMenu._fieldMoveNames = fmNames
    PartyMenu.mode = "action"
    PartyMenu.actionCursor = 1
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(9)
    PartyMenu.close()
  end
end

local function hp_bar(hp, maxHp, px, py, width)
  width = width or 48
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  local ratio = math.max(0, math.min(1, hp / maxHp))
  local w = math.floor(width * ratio)
  if w <= 0 then return end
  if ratio > 0.5 then
    love.graphics.setColor(0.25, 0.85, 0.25, 1)
  elseif ratio > 0.2 then
    love.graphics.setColor(0.95, 0.85, 0.15, 1)
  else
    love.graphics.setColor(0.95, 0.2, 0.15, 1)
  end
  love.graphics.rectangle("fill", px, py, w, 3)
  love.graphics.setColor(1, 1, 1, 1)
end

-- BG + text only; OAM sprites flushed by Display.present.
local function draw_filled_slot(i, mon, selected)
  local win = slot_win(i)
  if not win then return end
  local T = Display.TILE or 8
  local baseX, baseY = win.left * T, win.top * T
  local info = slot_info(i)

  PartyChrome.drawSlot(win.kind, win.left, win.top, selected)

  local name = Pokemon.displayName(mon)
  party_print(name, baseX + info.nick[1], baseY + info.nick[2], 56)
  party_print("Lv" .. tostring(mon.level or 0), baseX + info.level[1], baseY + info.level[2], 32)

  local gender = mon.gender or (Pokemon.gender and Pokemon.gender(mon.species, mon.personality))
  local isNidoran = (mon.species == 29 or mon.species == 32)
  if gender and not isNidoran then
    if gender == "M" then
      FrlgFont.draw("♂", baseX + info.gender[1], baseY + info.gender[2], { colors = FrlgFont.COLOR.PARTY_MALE, small = true })
    elseif gender == "F" then
      FrlgFont.draw("♀", baseX + info.gender[1], baseY + info.gender[2], { colors = FrlgFont.COLOR.PARTY_FEMALE, small = true })
    end
  end

  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local anim = PartyMenu._hpAnim
  local displayHp = hp
  if anim and anim.slot == i then
    displayHp = math.floor(anim.current + 0.5)
  end
  party_print(right_align_3(displayHp) .. "/", baseX + info.hp[1], baseY + info.hp[2], 24)
  party_print("/" .. right_align_3(maxHp), baseX + info.hpMax[1], baseY + info.hpMax[2], 24)
  hp_bar(displayHp, maxHp, baseX + info.hpBar[1], baseY + info.hpBar[2], 48)
end

function PartyMenu.draw()
  if not PartyMenu.open then return end
  local party = PartyMenu._party or {}

  if PartyMenu.mode == "summary" or SummaryMenu.isOpen() then
    destroy_party_oam()
    if PartyMenu.mode == "summary" then
      PartyChrome.drawBg()
      SummaryMenu.draw()
    end
    return
  end

  PartyChrome.drawBg()
  sync_all_oam()

  destroy_id(PartyMenu._summaryIcon)
  PartyMenu._summaryIcon = nil

  for i = 1, 6 do
    local mon = party[i]
    local win = slot_win(i)
    if mon then
      draw_filled_slot(i, mon, i == PartyMenu.cursor or PartyMenu.switchFrom == i)
    elseif i > 1 and win and win.kind ~= "main" then
      PartyChrome.drawSlot("empty", win.left, win.top, false)
    end
  end

  if PartyMenu.mode == "message" then
    Window.stdFrame(Window.template(1, 15, 28, 4))
    if PartyMenu._messageText then
      local wrapped = FrlgFont.wrap(PartyMenu._messageText, 216)
      FrlgFont.draw(wrapped, 1 * 8 + 6, 15 * 8 + 4, { maxWidth = 216, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "stat_growth" then
    Window.stdFrame(Window.template(1, 15, 28, 4))
    if PartyMenu._messageText then
      local wrapped = FrlgFont.wrap(PartyMenu._messageText, 216)
      FrlgFont.draw(wrapped, 1 * 8 + 6, 15 * 8 + 4, { maxWidth = 216, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end

    local winX, winY, winW, winH = 19, 1, 10, 11
    Window.stdFrame(Window.template(winX, winY, winW, winH))
    local statNames = { "MAX. HP", "ATTACK", "DEFENSE", "SP. ATK", "SP. DEF", "SPEED" }
    local oldS = PartyMenu._statGrowthOld or {}
    local newS = PartyMenu._statGrowthNew or {}
    local oldList = { oldS.maxHp or 0, oldS.atk or 0, oldS.def or 0, oldS.spa or 0, oldS.spd or 0, oldS.spe or 0 }
    local newList = { newS.maxHp or 0, newS.atk or 0, newS.def or 0, newS.spa or 0, newS.spd or 0, newS.spe or 0 }
    local isPage1 = (PartyMenu._statGrowthPage == 1)

    for idx = 1, 6 do
      local rowY = winY * 8 + 2 + (idx - 1) * 14
      FrlgFont.draw(statNames[idx], winX * 8 + 2, rowY, { colors = FrlgFont.COLOR.NORMAL })
      if isPage1 then
        local diff = newList[idx] - oldList[idx]
        local sign = (diff >= 0) and "+" or "-"
        local diffStr = string.format("%s%2d", sign, math.abs(diff))
        FrlgFont.draw(diffStr, winX * 8 + 52, rowY, { colors = FrlgFont.COLOR.NORMAL })
      else
        local valStr = string.format("%3d", newList[idx])
        FrlgFont.draw(valStr, winX * 8 + 52, rowY, { colors = FrlgFont.COLOR.NORMAL })
      end
    end
  elseif PartyMenu.mode == "yesno" then
    Window.stdFrame(Window.template(1, 15, 28, 4))
    if PartyMenu._yesNoPrompt then
      local wrapped = FrlgFont.wrap(PartyMenu._yesNoPrompt, 216)
      FrlgFont.draw(wrapped, 1 * 8 + 6, 15 * 8 + 4, { maxWidth = 216, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end
    -- Yes/No window overlay at tile X=21, Y=9, W=6, H=4
    local ynX = 21
    local ynY = 9
    Window.stdFrame(Window.template(ynX, ynY, 6, 4))
    local options = { "YES", "NO" }
    for i, opt in ipairs(options) do
      local rowY = (ynY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu._yesNoCursor then
        Window.cursorPx(ynX * 8 + 1, rowY)
      end
      FrlgFont.draw(opt, ynX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "forget" then
    Window.stdFrame(Window.template(1, 17, 15, 2))
    FrlgFont.draw("Which move?", 1 * 8 + 2, 17 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })

    local moves = PartyMenu._forgetMoves or {}
    local popW = 11
    local popH = math.max(4, #moves * 2)
    local popX = 18
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, mv in ipairs(moves) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu._forgetCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(tostring(mv), popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "item_action" then
    Window.stdFrame(Window.template(1, 17, 18, 2))
    FrlgFont.draw("Do what with an item?", 1 * 8 + 2, 17 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })

    local actCount = #PartyMenu.ITEM_ACTIONS
    local popW = 7
    local popH = actCount * 2
    local popX = 22
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(PartyMenu.ITEM_ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu.itemActionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(act, popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "action" then
    Window.stdFrame(Window.template(1, 17, 17, 2))
    FrlgFont.draw("Do what with this PKMN?", 1 * 8 + 2, 17 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })

    local actCount = #PartyMenu.ACTIONS
    local popW = 10
    local popH = actCount * 2
    local popX = 19
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(PartyMenu.ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu.actionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      local isFm = PartyMenu._fieldMoveNames and PartyMenu._fieldMoveNames[act]
      local col = isFm and (FrlgFont.COLOR.BLUE or FrlgFont.COLOR.MALE_NPC) or FrlgFont.COLOR.NORMAL
      FrlgFont.draw(act, popX * 8 + 9, rowY, { colors = col })
    end
  else
    Window.stdFrame(Window.template(1, 17, 21, 2))
    local promptText = "Choose a POKéMON."
    if PartyMenu.mode == "switch" then
      promptText = "Move to where?"
    elseif PartyMenu.mode == "use" then
      if PartyMenu._item and ItemsData.isTm(PartyMenu._item) then
        promptText = "Teach which POKéMON?"
      else
        promptText = "Use on which POKéMON?"
      end
    elseif PartyMenu.mode == "give" then
      promptText = "Give to which POKéMON?"
    end
    FrlgFont.draw(promptText, 1 * 8 + 2, 17 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
    PartyChrome.drawCancelButton(184, 136, PartyMenu.cursor == 7)
  end
end

return PartyMenu

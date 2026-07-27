-- Party menu: list the party, choose a member.
-- Modes:
--   default: A -> submenu (STATS / SWITCH / field moves)
--   opts.onSwitch + opts.battle (voluntary PKMN): A -> SWITCH / STATS /
--     CANCEL (core.asm PartyMenuOrRockOrRun), then onSwitch on SWITCH
--   opts.onSwitch + opts.forceSwitch: A -> onSwitch immediately
--     (ChooseNextMon / SHIFT free-switch)
--   opts.pickOnly + opts.onSwitch: A -> onSwitch (item / script target)
--   opts.onCancel: fired when the menu closes without a pick (B)
-- Pops itself on B.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Theme = require("src.ui.Theme")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")
local Strings = require("src.core.Strings")

local PartyMenu = {}
PartyMenu.__index = PartyMenu
PartyMenu.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function PartyMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local function sameItems(_, items) return items end

-- where DIG escapes work: escape_rope_tilesets.asm (Agatha's room is
-- excluded by map id in ItemUseEscapeRope)
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true,
                       FACILITY = true, INTERIOR = true }

-- Party mon icons (engine/gfx/mon_icons.asm AnimatePartyMon): only the
-- SELECTED mon's icon animates, at a speed set by its HP bar color --
-- 5 / 16 / 32 frames per phase for green / yellow / red (the famous
-- health-speed detail).  BALL and HELIX icons nudge one pixel down
-- instead of switching frames; every other icon swaps to a real second
-- frame (+ICONOFFSET).

-- Rest/alt frame per icon (data/icon_pointers.asm
-- MonPartySpritePointers): the base entries are the RESTING frame,
-- the +ICONOFFSET entries the animated alternate.  The 16x32 icon
-- sheets stack Frame1 (index 0) over Frame2 (index 1, INC_FRAME_2):
-- BUG/GRASS rest on BugIconFrame2/PlantIconFrame2 and animate to
-- Frame1; SNAKE/QUADRUPED are the reverse.  Sprite-reused icons draw
-- from 16x16x6 overworld sheets where index 3 is walk-down (tile 12):
-- MON/FAIRY/BIRD rest on the walk frame and animate to standing
-- (tile 0); WATER (Seel) is the reverse.
PartyMenu.iconFrames = {
  BUG       = { rest = 1, alt = 0 }, -- BugIconFrame2 <-> BugIconFrame1
  GRASS     = { rest = 1, alt = 0 }, -- PlantIconFrame2 <-> PlantIconFrame1
  SNAKE     = { rest = 0, alt = 1 }, -- SnakeIconFrame1 <-> SnakeIconFrame2
  QUADRUPED = { rest = 0, alt = 1 }, -- QuadrupedIconFrame1 <-> Frame2
  MON       = { rest = 3, alt = 0 }, -- MonsterSprite tile 12 <-> tile 0
  FAIRY     = { rest = 3, alt = 0 }, -- FairySprite tile 12 <-> tile 0
  BIRD      = { rest = 3, alt = 0 }, -- BirdSprite tile 12 <-> tile 0
  WATER     = { rest = 0, alt = 3 }, -- SeelSprite tile 0 <-> tile 12
}

-- Which 16x16 frame of `name`'s sheet to draw; `ih` (sheet pixel
-- height) only matters for the fallback, which keeps the old uniform
-- behavior for icons outside the table (BALL/HELIX y-bob instead).
function PartyMenu.frameFor(name, alt, ih)
  local m = PartyMenu.iconFrames[name]
  if m then return alt and m.alt or m.rest end
  return alt and ((ih or 0) >= 64 and 3 or 1) or 0
end

local iconImages = {}
local function drawIcon(game, mon, x, y, selected, counter)
  local icons = game.data.icons
  if not icons then return end
  local def = game.data.pokemon[mon.species]
  -- Per-species override first: the icons registry folds into
  -- icons.bySpecies, and a pokemon record may carry its own `icon` field.
  -- Either is a built-in icon name (resolved through icons.icons) or a
  -- { image = <path>, frames? } table pointing at bundled art. Falling
  -- through to icons.byDex[def.dex] keeps the vanilla dex-indexed default;
  -- without the override a modded or dex-renumbered species could never
  -- change its menu icon.
  local entry = (icons.bySpecies and icons.bySpecies[mon.species])
             or (def and def.icon)
  local name, path
  if type(entry) == "string" then
    name = entry
    path = icons.icons and icons.icons[entry]
  elseif type(entry) == "table" then
    path = entry.image
  end
  if not path then
    name = def and def.dex and icons.byDex and icons.byDex[def.dex]
    path = name and icons.icons and icons.icons[name]
  end
  path = require("src.pokemon.Sprites").iconPath(game.data, mon, path, { name = name })
  if not path then return end
  if iconImages[path] == nil then
    -- resolve through Assets so an overrides/ or transform-derived icon
    -- (e.g. a per-species image at assets/generated/icons/<name>.png) is
    -- picked up the same way battle sprites are
    local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
    iconImages[path] = ok and img or false
  end
  local img = iconImages[path]
  if not img then return end
  local alt = false
  if selected then
    local px = math.floor(mon.hp * 48 / math.max(1, mon.stats.hp))
    local speed = px >= 27 and 5 or px >= 10 and 16 or 32
    alt = math.floor(counter / speed) % 2 == 1
  end
  if alt and (name == "BALL" or name == "HELIX") then
    y = y + 1
    alt = false
  end
  local iw, ih = img:getDimensions()
  if ih > 16 then
    local frame = PartyMenu.frameFor(name, alt, ih)
    love.graphics.draw(img, love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih), x, y)
  else
    love.graphics.draw(img, x, y)
  end
end

function PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PartyMenu)
  self.game = game
  self.index = 1
  self.onSwitch = opts.onSwitch
  self.onCancel = opts.onCancel
  self.pickOnly = opts.pickOnly
  -- TM/HM teaching: opts.tmhm = { move, kind } switches the list to Gen 1's
  -- TM/HM display (ABLE / NOT ABLE per mon instead of the HP bar, and the
  -- "Use TM on which POKeMON?" prompt). Set by BagMenu.pickTargetAndUse. #210
  self.tmhm = opts.tmhm
  self.forceSwitch = opts.forceSwitch
  self.battle = opts.battle
  self.party = opts.party -- link battles pass their clamped copies
  self.swapFrom = nil
  self.submenu = nil
  self.subIndex = 1
  self.blink = 0
  return self
end

function PartyMenu:update(dt)
  -- icon animation counter; 320 = a whole cycle at every HP speed
  self.blink = ((self.blink or 0) + 1) % 320
  local input = self.game.input
  local party = self.party or self.game.save.party

  if self.submenu then
    local n = #self.subItems
    if input:wasPressed("up") then
      self.subIndex = self.subIndex > 1 and self.subIndex - 1 or n
    elseif input:wasPressed("down") then
      self.subIndex = self.subIndex < n and self.subIndex + 1 or 1
    elseif input:wasPressed("b") then
      self.submenu = nil
    elseif input:wasPressed("a") then
      local mon = party[self.index]
      local entry = self.subItems[self.subIndex]
      local action = entry.action
      if not action and entry.onSelect then
        -- hook-injected entries carry a callback instead of an action id
        entry.onSelect(mon, self.game)
      elseif action == "stats" then
        -- battle and field alike return to the party list afterwards
        -- (core.asm .partyMenuWasSelected)
        Screens.push(self.game, "SummaryMenu", mon)
      elseif action == "battle_switch" then
        self.game.stack:pop()
        self.onSwitch(mon)
        return
      elseif action == "cancel" then
        self.game.stack:pop()
        if self.onCancel then self.onCancel() end
        return
      elseif action == "switch" then
        self.swapFrom = self.index
      elseif action == "fly" then
        -- FLY opens the TOWN MAP with a cursor over the visited fly towns,
        -- not a plain text list (engine/menus/town_map.asm LoadTownMap_Fly).
        -- flyTo (OverworldController) validates the fly-warp + runs the
        -- departure/warp, so we just hand it the chosen mapId (#195).
        local ow = self.game.overworld
        self.game.stack:pop() -- close the party menu
        Screens.push(self.game, "TownMap", { fly = true, onFly = function(mapId)
          if ow then ow:flyTo(mapId) end
        end })
        return
      elseif action == "flash" then -- FLASH lights dark tunnels
        -- start_sub_menus.asm .flash: PrintText _FlashLightsAreaText, then
        -- GBPalWhiteOutWithDelay3 + jp .goBackToMap
        local ow = self.game.overworld
        local TextBox = require("src.render.TextBox")
        local Transition = require("src.render.Transition")
        self.game.stack:pop()
        ow.dark = false
        self.game.save.flashLit = true
        self.game.stack:push(TextBox.new(self.game,
          self.game.data.text._FlashLightsAreaText
          or Strings("A blinding FLASH\nlights the area!"), function()
            self.game.stack:push(Transition.whiteFlash(self.game))
          end))
        return
      elseif action == "surf" then
        -- start_sub_menus.asm .surf: SOULBADGE-gated (checked at list time
        -- above), then IsSurfingAllowed (the Cycling Road / Seafoam B4F
        -- current refusals, both of which loop back to the submenu), then
        -- ItemUseSurfboard: while surfing it tries to dismount instead;
        -- otherwise it mounts only if the FACING tile is water, else
        -- SurfingAttemptFailed (_NoSurfingHereText) loops back to the
        -- submenu.  useSurfFieldMove reports which; trySurf does the mount.
        local ow = self.game.overworld
        local reason = ow:useSurfFieldMove()
        local Transition = require("src.render.Transition")
        if reason == "ok" then
          self.game.stack:pop() -- close the party menu (jp .goBackToMap)
          local fx, fy = ow.player:facingCell()
          ow:trySurf(fx, fy)
          return
        end
        if reason == "dismount" then
          -- ItemUseSurfboard .stopSurfing: no text -- the walking state
          -- and music return first (PlayDefaultMusic +
          -- LoadWalkingPlayerSpriteGraphics), the menu closes with the
          -- GBPalWhiteOutWithDelay3 blink, and the simulated pad press
          -- steps the player forward onto land (or across a connection
          -- strip when the shore is the next map's edge)
          self.game.stack:pop()
          ow.player.surfing = false
          require("src.core.Music").setSurfing(self.game.data, false)
          self.game.stack:push(Transition.whiteFlash(self.game, nil, function()
            ow:stepForwardOrCrossEdge(ow.player.facing)
          end))
          return
        end
        local TextBox = require("src.render.TextBox")
        local def = self.game.data.pokemon[mon.species]
        local key = ({ no_badge = "_NewBadgeRequiredText",
                       forced_bike = "_CyclingIsFunText",
                       current = "_CurrentTooFastText",
                       no_place = "_SurfingNoPlaceToGetOffText" })[reason]
                    or "_NoSurfingHereText"
        local txt = (self.game.data.text[key] or Strings("No SURFing here!"))
                    :gsub("{RAM:wNameBuffer}", mon.nickname or def.name)
        if reason == "no_place" then
          -- .cannotStopSurfing prints _SurfingNoPlaceToGetOffText but
          -- never zeroes wActionResultOrTookBattleTurn, so unlike the
          -- other refusals the menu still closes afterwards
          -- (GBPalWhiteOutWithDelay3 + .goBackToMap)
          self.game.stack:pop()
          self.game.stack:push(TextBox.new(self.game, txt, function()
            self.game.stack:push(Transition.whiteFlash(self.game))
          end))
          return
        end
        self.game.stack:push(TextBox.new(self.game, txt))
        return -- .loop: submenu stays open behind the message
      elseif action == "cut" then
        -- start_sub_menus.asm .cut -> predef UsedCut (engine/overworld/cut.asm):
        -- CASCADEBADGE-gated (list time); _NothingToCutText loops back to the
        -- submenu when the FACING tile isn't a cuttable tree.
        local ow = self.game.overworld
        local reason = ow:useCutFieldMove()
        if reason == "ok" then
          self.game.stack:pop() -- close the party menu (CloseTextDisplay)
          local fx, fy = ow.player:facingCell()
          ow:tryCut(fx, fy)
          return
        end
        local TextBox = require("src.render.TextBox")
        local def = self.game.data.pokemon[mon.species]
        local key = (reason == "no_badge") and "_NewBadgeRequiredText"
                                            or "_NothingToCutText"
        local txt = (self.game.data.text[key] or Strings("Nothing to CUT!"))
                    :gsub("{RAM:wNameBuffer}", mon.nickname or def.name)
        self.game.stack:push(TextBox.new(self.game, txt))
        return -- .loop: submenu stays open behind the message
      elseif action == "strength" then
        -- start_sub_menus.asm .strength: RAINBOWBADGE-gated (list time);
        -- predef PrintStrengthText (field_move_messages.asm) sets
        -- BIT_STRENGTH_ACTIVE of wStatusFlags1 -- the sole gate
        -- push_boulder.asm reads -- then prints _UsedStrengthText (no
        -- prompt: after the text, the text_asm tail plays the chosen
        -- mon's cry, Delay3, and it auto-advances) and
        -- _CanMoveBouldersText (`prompt`: waits for A/B).  Back in
        -- .strength, GBPalWhiteOutWithDelay3 blinks the screen white
        -- before CloseTextDisplay returns to the map.
        local ow = self.game.overworld
        local TextBox = require("src.render.TextBox")
        local Transition = require("src.render.Transition")
        local def = self.game.data.pokemon[mon.species]
        local name = mon.nickname or def.name
        self.game.stack:pop() -- close the party menu (jp .goBackToMap)
        ow.strengthActive = true
        local t1 = (self.game.data.text._UsedStrengthText
          or Strings("{RAM:wNameBuffer} used\nSTRENGTH.")):gsub("{RAM:wNameBuffer}", name)
        local t2 = (self.game.data.text._CanMoveBouldersText
          or Strings("{RAM:wNameBuffer} can\nmove boulders.")):gsub("{RAM:wNameBuffer}", name)
        self.game.stack:push(TextBox.new(self.game, t1, function()
          self.game.stack:push(TextBox.new(self.game, t2, function()
            self.game.stack:push(Transition.whiteFlash(self.game))
          end))
        end, { auto = { sound = function()
          return require("src.core.Sound").playCry(self.game.data, mon.species)
        end } }))
        return
      elseif action == "softboiled" then
        -- field SOFTBOILED (StartMenu_Pokemon .softboiled): transfer
        -- 1/5 of the user's max HP to a chosen teammate
        self.softboiledFrom = self.index
      elseif action == "escape" then
        -- DIG / TELEPORT warp to the last Pokémon Center TOWN (wLastBlackoutMap,
        -- special_warps.asm escape warp).  pokered's .dig/.teleport spin the
        -- player up (LeaveMapAnim), white/fade out, then land it; this port
        -- lands OUTSIDE the town PC door like Fly (#196).  beginTeleportOut
        -- centralizes the spin -> fade -> warp so BagMenu's ESCAPE ROPE shares
        -- the exact departure; the fade + warp fire when the spin ends.
        local ow = self.game.overworld
        self.game.stack:pop()
        if ow then ow:beginTeleportOut() end
        return
      end
      self.submenu = nil
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or math.max(1, #party)
  elseif input:wasPressed("down") then
    self.index = self.index < #party and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  elseif input:wasPressed("a") and #party > 0 then
    local mon = party[self.index]
    if self.softboiledFrom then
      local user = party[self.softboiledFrom]
      local heal = math.floor(user.stats.hp / 5)
      if mon == user or mon.hp <= 0 or mon.hp >= mon.stats.hp
         or user.hp <= heal then
        self.softboiledFrom = nil
        local TextBox = require("src.render.TextBox")
        self.game.stack:push(TextBox.new(self.game, Strings("It won't have\nany effect.")))
      else
        user.hp = user.hp - heal
        mon.hp = math.min(mon.stats.hp, mon.hp + heal)
        self.softboiledFrom = nil
        require("src.core.Sound").play(self.game.data, "Heal_HP")
        local def = self.game.data.pokemon[mon.species]
        local TextBox = require("src.render.TextBox")
        self.game.stack:push(TextBox.new(self.game,
          Strings("%s's HP\nwas restored!", mon.nickname or def.name)))
      end
    elseif self.swapFrom then
      if self.swapFrom ~= self.index then
        party[self.swapFrom], party[self.index] = party[self.index], party[self.swapFrom]
        require("src.core.Sound").play(self.game.data, "Swap")
      end
      self.swapFrom = nil
    elseif self.onSwitch and (self.forceSwitch or self.pickOnly or not self.battle) then
      self.game.stack:pop()
      self.onSwitch(mon)
    else
      self.submenu = true
      self.subIndex = 1
      local items
      local ow = self.game.overworld
      if self.battle and self.onSwitch then
        -- SwitchStatsCancelText (core.asm PartyMenuOrRockOrRun)
        items = { { label = Strings("SWITCH"), action = "battle_switch" },
                  { label = Strings("STATS"), action = "stats" },
                  { label = Strings("CANCEL"), action = "cancel" } }
      else
        -- STATS/SWITCH plus this mon's field moves (start_sub_menus.asm
        -- builds the same dynamic list)
        items = { { label = Strings("STATS"), action = "stats" },
                  { label = Strings("SWITCH"), action = "switch" } }
        -- Field moves (HMs/TMs) are usable out of battle even when the mon
        -- is fainted -- Gen 1 does not require HP for Cut/Fly/Surf/etc.
        -- Battle still excludes this list via `not self.battle`. Softboiled
        -- can appear for a fainted user; its heal transfer then no-ops.
        if not self.battle and ow then
          -- FLY/TELEPORT: CheckIfInOutsideMap (OVERWORLD + PLATEAU —
          -- Route 23 / Indigo Plateau outdoor), not OVERWORLD alone (#83)
          local outside = Map.isOutside(ow.map.def,
            FieldDefaults.field(self.game.data, "outsideTilesets"))
          for _, mv in ipairs(mon.moves) do
            if mv.id == "FLY" and outside
               and self.game.save.inventory.THUNDERBADGE then
              table.insert(items, { label = Strings("FLY"), action = "fly" })
            elseif mv.id == "FLASH" and ow.dark
               and self.game.save.inventory.BOULDERBADGE then
              table.insert(items, { label = Strings("FLASH"), action = "flash" })
            elseif mv.id == "CUT" and self.game.save.inventory.CASCADEBADGE then
              -- CUT/SURF/STRENGTH are party-menu field moves too
              -- (start_sub_menus.asm .outOfBattleMovePointers); listed here
              -- with the same list-time badge filter this file already uses
              -- for FLY/FLASH.  The facing-tile/activation check happens on
              -- selection (useCutFieldMove/useSurfFieldMove).
              table.insert(items, { label = Strings("CUT"), action = "cut" })
            elseif mv.id == "SURF" and self.game.save.inventory.SOULBADGE then
              table.insert(items, { label = Strings("SURF"), action = "surf" })
            elseif mv.id == "STRENGTH" and self.game.save.inventory.RAINBOWBADGE then
              table.insert(items, { label = Strings("STRENGTH"), action = "strength" })
            elseif mv.id == "SOFTBOILED" then
              table.insert(items, { label = Strings("SOFTBOILED"), action = "softboiled" })
            elseif mv.id == "TELEPORT" and outside then
              -- TELEPORT works only OUTDOORS (start_sub_menus.asm
              -- .teleport -> CheckIfInOutsideMap); dark maps don't
              -- block it
              table.insert(items, { label = Strings("TELEPORT"), action = "escape" })
            elseif mv.id == "DIG" and DIG_TILESETS[ow.map.def.tileset]
               and ow.map.id ~= "AGATHAS_ROOM" then
              -- DIG runs ItemUseEscapeRope (.dig sets wCurItem =
              -- ESCAPE_ROPE): usable in the dungeon tilesets of
              -- escape_rope_tilesets.asm minus Agatha's room, even in
              -- the dark (Rock Tunnel)
              table.insert(items, { label = Strings("DIG"), action = "escape" })
            end
          end
        end
      end
      local ctx = { battle = self.battle, overworld = ow }
      local hooked = Runtime.call("ui.party.submenu", sameItems,
                                  self.game, items, mon, ctx)
      if type(hooked) == "table" then
        items = hooked
      else
        Logger.error("ui.party.submenu returned %s; keeping the vanilla list",
                     type(hooked))
      end
      self.subItems = items
    end
  end
end

-- The bottom-of-screen context message for the current menu state
-- (pokered engine/menus/party_menu.asm PartyMenuMessage / RedrawPartyMenu_):
-- the party menu always prints a message in the bottom text box.  With the
-- normal message id that is PartyMenuBattleText ("Bring out which POKéMON?")
-- when IsInBattle else PartyMenuNormalText ("Choose a POKéMON."); the swap /
-- item / TM-HM ids print their own strings, which draw() handles inline.
-- Pure (no side effects) so drivers can assert it. #147
function PartyMenu:bottomMessage()
  if self.swapFrom then
    return "Move to where?"
  elseif self.softboiledFrom or self.pickOnly then
    return "Use on which one?"
  elseif self.tmhm then
    return self.game.data.text._PartyMenuUseTMText
      or Strings("Use TM on which\nPOKéMON?")
  elseif self.battle then
    return self.game.data.text._PartyMenuBattleText
      or Strings("Bring out which\nPOKéMON?")
  else
    return self.game.data.text._PartyMenuNormalText
      or Strings("Choose a POKéMON.")
  end
end

-- Name-row pixel Y for party slot i (1-based).
-- pokered party_menu.asm RedrawPartyMenu_: hlcoord 3, 0, then each entry
-- advances 2*SCREEN_WIDTH (16 px).  The bottom message box sits at tile
-- row 12 (y=96); slot 6's HP row is therefore at y=88. #262
function PartyMenu.entryY(i)
  return (i - 1) * 16
end

function PartyMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  local party = self.party or self.game.save.party
  if #party == 0 then
    Font.draw(Strings("No POKéMON!"), 16, 64)
  end
  local HudTiles = require("src.render.HudTiles")
  for i, mon in ipairs(party) do
    local def = self.game.data.pokemon[mon.species]
    local y = PartyMenu.entryY(i)
    love.graphics.setColor(1, 1, 1, 1)
    drawIcon(self.game, mon, 8, y, i == self.index, self.blink or 0)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(mon.nickname or def.name, 24, y)
    -- level at column 13 (<LV> tile + digits, PrintLevel) AND the
    -- status/FNT text at column 17 (PrintStatusCondition), like the
    -- original rows -- statused mons keep their level display
    if mon.level < 100 then
      HudTiles.tile(0x6E, 104, y) -- <LV>
      Font.draw(tostring(mon.level), 112, y)
    else
      -- PrintLevel overwrites the <LV> tile with the third digit
      Font.draw(tostring(mon.level), 104, y)
    end
    if self.tmhm then
      -- TM/HM teaching menu (engine/menus/party_menu.asm PrintPartyMenu):
      -- the second row shows the inline "ABLE" / "NOT ABLE" learnability
      -- strings in place of the HP bar and status, decided by CanLearnTM.
      -- The learnset scan mirrors ItemEffects.use so the display can never
      -- disagree with the actual teach. #210
      local can = false
      for _, m in ipairs(def.tmhm or {}) do
        if m == self.tmhm.move then can = true break end
      end
      -- right-aligned so the shorter "ABLE" shares "NOT ABLE"'s right edge
      if can then
        Font.draw(Strings("ABLE"), 120, y + 8)
      else
        Font.draw(Strings("NOT ABLE"), 88, y + 8)
      end
    else
      if mon.hp <= 0 then
        Font.draw(Strings("FNT"), 136, y)
      elseif mon.status then
        Font.draw(mon.status, 136, y)
      end
      -- the colored tile HP bar (DrawHP2 + SetPartyMenuHPBarColor)
      love.graphics.setColor(1, 1, 1, 1)
      HudTiles.drawHPBar(self.game.data, 5, (y + 8) / 8, mon)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(("%3d/%3d"):format(mon.hp, mon.stats.hp), 104, y + 8)
    end
    -- home/pokemon.asm PartyMenuInit seeds wTopMenuItemY/X with 1/0, so the
    -- cursor sits on the entry's *second* tile row (the level/HP line),
    -- level with the middle of the two-row icon -- not on the name row that
    -- entryY returns.  Drawing it at y put it a tile too high (#278).
    local cursorY = y + 8
    if i == self.index then
      Font.drawCode(Theme.cursor, 0, cursorY)
    end
    if i == self.swapFrom or i == self.softboiledFrom then
      Font.drawCode(Theme.cursorHollow, 0, cursorY) -- the unfilled swap arrow
    end
  end
  if self.swapFrom then
    Font.draw(Strings("Move to where?"), 8, 136)
  elseif self.softboiledFrom then
    Font.draw(Strings("Use on which one?"), 8, 136)
  elseif self.tmhm then
    -- "Use TM on which\nPOKeMON?" in the standard bottom text box
    -- (party_menu.asm keeps the message box for the TM/HM menu); box + line
    -- geometry match TextBox's default (rows 12-17, text on rows 14/16). #210
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    local prompt = self.game.data.text._PartyMenuUseTMText
      or Strings("Use TM on which\nPOKéMON?")
    local ly = 112
    for line in (prompt .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, ly)
      ly = ly + 16
    end
  elseif self.pickOnly then
    Font.draw(Strings("Use on which one?"), 8, 136)
  else
    -- default field party menu (StartMenu) and the battle voluntary-switch
    -- (BattleState:openParty): Gen1 prints PartyMenuNormalText / PartyMenuBattleText
    -- in the standard bottom text box (party_menu.asm PartyMenuMessage), not
    -- plain bottom-row text.  Box + line geometry match the #210 TM/HM case and
    -- TextBox's default (rows 12-17, text on rows 14/16). #147
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    local ly = 112
    for line in (self:bottomMessage() .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, ly)
      ly = ly + 16
    end
  end
  if self.submenu then
    local n = #self.subItems
    Font.drawBox(9, 17 - n * 2 - 1, 11, n * 2 + 1)
    local y0 = (17 - n * 2) * 8
    for si, entry in ipairs(self.subItems) do
      Font.draw(entry.label, 88, y0 + (si - 1) * 16)
    end
    Font.drawCode(Theme.cursor, 80, y0 + (self.subIndex - 1) * 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PartyMenu

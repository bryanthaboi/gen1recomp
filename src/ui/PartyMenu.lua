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
local Status = require("src.battle.Status")

local PartyMenu = {}
PartyMenu.__index = PartyMenu
PartyMenu.isOpaque = true

-- SGB (SetPal_PartyMenu, engine/gfx/palettes.asm:90): the party screen is
-- NOT a one-palette screen.  data/sgb/sgb_packets.asm BlkPacket_PartyMenu
-- splits it into MEWMON over the mon-icon column with GREENBAR everywhere
-- else, plus one block per HP bar row whose palette
-- UpdatePartyMenuBlkPacket (engine/gfx/palettes.asm:299-325) sets from that
-- mon's GetHealthBarColor -- pal 1 GREENBAR / 2 YELLOWBAR / 3 REDBAR
-- (PalPacket_PartyMenu, sgb_packets.asm:219).  Handing the whole screen
-- MEWMON instead painted every bar with MEWMON's shades, which is why a
-- full bar came out black and a low one purple (#274, absorbing #272).
--
-- Two rects differ from the packet's, both because this port draws pixels
-- where the hardware drew OAM over BG:
--   * the icon block is rows 0-11, not the packet's 0-12 -- row 12 is the
--     message box's top edge, which on hardware was BG under an OBJ-free
--     part of the block; here it would take MEWMON instead of the base.
--   * the bar blocks sit one tile right of the packet's 05-11 because this
--     port's bar starts at tile 5 where party_menu.asm:71-76 starts it at
--     4; the span is the same "left cap + six fill tiles".
function PartyMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local base = P.pal(game.data, "GREENBAR")
  if not base then return nil end
  local zones = { P.whole(base) }
  local mew = P.pal(game.data, "MEWMON")
  if mew then zones[#zones + 1] = P.zone(mew, 1, 0, 2, 11) end
  -- the TM/HM list prints ABLE / NOT ABLE where the bar would be, so those
  -- rows have no bar to color (party_menu.asm .teachMoveMenu; #210)
  if not self.tmhm then
    local party = self.party or (game.save and game.save.party) or {}
    for i, mon in ipairs(party) do
      -- While a medicine's bar fill runs the block palette is STALE, not
      -- recomputed: SetPartyMenuHPBarColor (party_menu.asm:80/295) is only
      -- reached from the party-menu redraw loop, never from hp_bar.asm, so
      -- UpdateHPBar2 lengthens the bar under the PRE-heal color and
      -- RedrawPartyMenu snaps it green when the message prints.  Hold the
      -- starting HP here for exactly that window (#252).
      local hp = mon.hp
      if self.heal and self.heal.mon == mon then hp = self.heal.from end
      local bar = P.pal(game.data, P.barPalName(hp, mon.stats.hp))
      if bar then
        zones[#zones + 1] = P.zone(bar, 6, i * 2 - 1, 12, i * 2 - 1)
      end
    end
  end
  return zones
end

local function sameItems(_, items) return items end

local function followerUnavailable(game, mon)
  local ow = game.overworld
  local Follower = require("src.world.PikachuFollower")
  return Follower.isFollowingDisabled(ow)
    and Follower.isStarterPikachu(game.save, mon)
end

local function refuseUnavailable(self)
  self.swapFrom = nil
  local TextBox = require("src.render.TextBox")
  local t = self.game.data and self.game.data.text or {}
  self.game.stack:push(TextBox.new(self.game,
    t._SleepingPikachuText1 or Strings("There isn't any\nresponse...")))
end

-- .newBadgeRequired (start_sub_menus.asm): every badge-gated arm of
-- .outOfBattleMovePointers prints this and jumps back to the open submenu
local function refuseBadge(self)
  local TextBox = require("src.render.TextBox")
  local t = self.game.data and self.game.data.text or {}
  self.game.stack:push(TextBox.new(self.game,
    t._NewBadgeRequiredText or Strings("No! A new BADGE\nis required.")))
end

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
-- (tile 0); WATER (Seel) is the reverse.  Only the frame's LEFT half
-- ever reaches the screen -- see PartyMenu.mirrorsIcon (#276) -- which
-- is why a walk frame does not look like a walk frame here.
PartyMenu.iconFrames = {
  BUG       = { rest = 1, alt = 0 }, -- BugIconFrame2 <-> BugIconFrame1
  GRASS     = { rest = 1, alt = 0 }, -- PlantIconFrame2 <-> PlantIconFrame1
  SNAKE     = { rest = 0, alt = 1 }, -- SnakeIconFrame1 <-> SnakeIconFrame2
  QUADRUPED = { rest = 0, alt = 1 }, -- QuadrupedIconFrame1 <-> Frame2
  MON       = { rest = 3, alt = 0 }, -- MonsterSprite tile 12 <-> tile 0
  FAIRY     = { rest = 3, alt = 0 }, -- FairySprite tile 12 <-> tile 0
  BIRD      = { rest = 3, alt = 0 }, -- BirdSprite tile 12 <-> tile 0
  WATER     = { rest = 0, alt = 3 }, -- SeelSprite tile 0 <-> tile 12
  PIKACHU   = { rest = 0, alt = 3 }, -- Yellow: PikachuSprite tile 0 <-> 12
}

local function gridIndex(index, count, direction)
  if count < 1 then return nil end
  local row, col = math.floor((index - 1) / 2), (index - 1) % 2
  if direction == "left" or direction == "right" then
    local other = row * 2 + (1 - col) + 1
    return other <= count and other or index
  end
  local step = direction == "up" and -1 or direction == "down" and 1
  if not step then return nil end
  local rows = math.ceil(count / 2)
  for offset = 1, rows do
    local other = ((row + step * offset) % rows) * 2 + col + 1
    if other <= count then return other end
  end
  return index
end

-- Which 16x16 frame of `name`'s sheet to draw; `ih` (sheet pixel
-- height) only matters for the fallback, which keeps the old uniform
-- behavior for icons outside the table (BALL/HELIX y-bob instead).
function PartyMenu.frameFor(name, alt, ih)
  local m = PartyMenu.iconFrames[name]
  if m then return alt and m.alt or m.rest end
  return alt and ((ih or 0) >= 64 and 3 or 1) or 0
end

-- HELIX is the one icon WriteMonPartySpriteOAM sends down the asymmetric
-- path (engine/gfx/mon_icons.asm:246 `cp ICON_HELIX << 2 / jr z, .helix`);
-- every other built-in icon is drawn as a mirrored left half (see
-- drawIcon).  A mod that supplies its own image instead of a built-in icon
-- name has no vanilla counterpart, so its art draws whole. #276
function PartyMenu.mirrorsIcon(name)
  return name ~= nil and name ~= "HELIX"
end

local iconImages = {}

-- Party icons are OBJs (engine/gfx/mon_icons.asm WriteMonPartySpriteOAM
-- writes OAM blocks), so they render through OBP0, and GBPalNormal
-- (home/palettes.asm:20-26 `ld a, %11010000 ; 3100 / ldh [rOBP0], a`)
-- holds OBP0 at "3100": OBJ color 1 shows as shade 0, color 2 as shade 1,
-- color 3 as shade 3.  An object never displays shade 2.  This canvas has
-- no OBJ layer, so bake that map into the icon art once per path (the same
-- CPU-remap trick as SpriteRenderer.getObpImage, and the same "#obp" cache
-- key convention) and let the screen's SGB zone color the result.  Without
-- it every color-2 pixel took the zone palette's shade-2 color -- the
-- ADVANCED pack's MEWMON purple {115,33,165}, i.e. the "weirdly colored"
-- party sprites of #274.
local function obpIcon(path)
  if not (love.image and love.image.newImageData) then
    return love.graphics.newImage(Assets.resolve(path)) -- headless stub
  end
  local id = Assets.imageData(path)
  id:mapPixel(function(_, _, r, _, _, a)
    -- the extracted art is the four DMG grays, keyed off the red channel
    -- exactly the way PaletteFX's shade-remap shader keys them
    local v = 0
    if r > 0.5 then v = 1               -- OBJ colors 0 and 1 -> shade 0
    elseif r > 0.17 then v = 170 / 255  -- OBJ color 2 -> shade 1
    end                                 -- OBJ color 3 -> shade 3
    return v, v, v, a
  end)
  return love.graphics.newImage(id)
end

-- `forceAlt` picks the second animation frame outright, for callers with no
-- selection cursor of their own: Trade_AnimCircledMon
-- (engine/movie/trade.asm) cycles the party sprite's two frames the whole
-- time the mon rides the link cable (#750).
function PartyMenu.drawIcon(game, mon, x, y, selected, counter, forceAlt)
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
  -- Built-in icon classes are DMG 2bpp OBJ art and get the OBP0 bake; a
  -- mod's own image (an entry table rather than an icon name) is authored
  -- art with no hardware counterpart, so it loads untouched -- the same
  -- split PartyMenu.mirrorsIcon makes for the OAM mirror.  Both live in one
  -- cache under different keys, so a mod pointing a table entry at a
  -- built-in path still gets its unbaked copy. #274
  local key = name and (path .. "#obp") or path
  if iconImages[key] == nil then
    -- resolve through Assets so an overrides/ or transform-derived icon
    -- (e.g. a per-species image at assets/generated/icons/<name>.png) is
    -- picked up the same way battle sprites are
    local ok, img
    if name then
      ok, img = pcall(obpIcon, path)
    else
      ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
    end
    iconImages[key] = ok and img or false
  end
  local img = iconImages[key]
  if not img then return end
  local alt = forceAlt or false
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
  -- a 16x16 sheet (BALL, HELIX) is its own only frame
  local frame = ih > 16 and PartyMenu.frameFor(name, alt, ih) or 0
  if PartyMenu.mirrorsIcon(name) then
    -- WriteSymmetricMonPartySpriteOAM (engine/items/town_map.asm:494-534)
    -- lays each icon out as 2x2 OAM blocks that use only the frame's LEFT
    -- column of tiles (base+0, base+2): the inner loop writes the same
    -- wOAMBaseTile twice with the attributes alternating 0 / OAM_XFLIP and
    -- only then bumps the tile by 2, because "all the sprites other than
    -- the helix one have a vertical line of symmetry".  MON / FAIRY / BIRD
    -- reuse overworld sheets whose walk-down frame is NOT symmetric, so
    -- drawing the raw 16x16 showed a tucked-back foot the hardware never
    -- displays (#276, absorbing #238).
    local half = love.graphics.newQuad(0, frame * 16, 8, 16, iw, ih)
    love.graphics.draw(img, half, x, y)
    -- sx = -1 about the block's right edge, so the flipped copy lands on
    -- x+8..x+16: the OAM_XFLIP half
    love.graphics.draw(img, half, x + 16, y, 0, -1, 1)
  elseif ih > 16 then
    love.graphics.draw(img, love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih), x, y)
  else
    -- HELIX and any mod art that is a single frame: drawn whole, at
    -- whatever size the file is (unchanged path)
    love.graphics.draw(img, x, y)
  end
  return true
end

function PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PartyMenu)
  self.game = game
  local party = opts.party or (opts.battle and opts.battle.playerParty)
  -- PartyMenuInit (home/pokemon.asm) seeds the cursor from
  -- wPartyAndBillsPCSavedMenuItem rather than from zero, and
  -- HandlePartyMenuInput writes wCurrentMenuItem back into it on every
  -- input, so the party cursor survives closing and reopening the menu.
  -- Only a battle clears it -- InitBattleVariables and end_of_battle.asm
  -- both zero the byte, which BattleState mirrors.  The clamp covers a
  -- party that shrank (deposit / release) while the saved index was
  -- pointing past the end. #768
  local count = #(party or (game.save and game.save.party) or {})
  self.index = math.min(math.max(1, game.partyMenuSavedIndex or 1),
                        math.max(1, count))
  self.onSwitch = opts.onSwitch
  self.onCancel = opts.onCancel
  self.pickOnly = opts.pickOnly
  self.itemUse = opts.itemUse -- USE_ITEM_PARTY_MENU (item_effects.asm:813)
  -- Medicine keeps the picker on screen: item_effects.asm .doneHealing
  -- animates the party HP bar and then prints the message through
  -- RedrawPartyMenu with the menu STILL up, so BagMenu asks for keepOpen and
  -- calls :close() itself once the message is done (#252).
  self.keepOpen = opts.keepOpen
  -- TM/HM teaching: opts.tmhm = { move, kind } switches the list to Gen 1's
  -- TM/HM display (ABLE / NOT ABLE per mon instead of the HP bar, and the
  -- "Use TM on which POKeMON?" prompt). Set by BagMenu.pickTargetAndUse. #210
  self.tmhm = opts.tmhm
  -- Evolution stones: opts.evoStone = item id gives Gen 1's
  -- EVO_STONE_PARTY_MENU ABLE / NOT ABLE display (party_menu.asm:114). #1411
  self.evoStone = opts.evoStone
  self.forceSwitch = opts.forceSwitch
  self.battle = opts.battle
  self.party = party -- link/scoped battles pass their local party view
  self.swapFrom = nil
  self.submenu = nil
  self.subIndex = 1
  self.blink = 0
  return self
end

-- UpdateHPBar2 (engine/gfx/hp_bar.asm, predef'd from item_effects.asm's
-- .doneHealing): UpdateHPBar_AnimateHPBar is documented "for (a) ticks (two
-- waiting frames each)" over a 48-pixel bar, so the shown HP walks
-- maxHP/96 per frame -- the same rate the battle HUD drains at
-- (BattleState:stepHPDrain).  onDone fires on the frame it lands, which is
-- when the caller prints its message. #252
function PartyMenu:animateTo(mon, fromHP, onDone)
  if not (mon and mon.stats) then
    if onDone then onDone() end
    return
  end
  local from = math.max(0, fromHP or mon.hp)
  -- `from` outlives `shown`: sgbPalettes above needs the pre-heal HP for the
  -- whole fill, because the SGB bar color does not move until the redraw.
  self.heal = { mon = mon, from = from, shown = from, onDone = onDone }
end

-- Close a picker the caller kept open (see self.keepOpen).  A TextBox pops
-- itself BEFORE it fires onDone (src/render/TextBox.lua), so this menu is
-- the top state by then; the identity check makes it a no-op for the pickers
-- that already popped themselves, and stops a double close eating the bag
-- underneath. #252
function PartyMenu:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function PartyMenu:gridNavigation()
  if not self.battle
      or not Runtime.wantsHook("ui.party.grid_navigation") then return false end
  return Runtime.call("ui.party.grid_navigation", function() return false end,
                      self) == true
end

function PartyMenu:update(dt)
  -- icon animation counter; 320 = a whole cycle at every HP speed
  self.blink = ((self.blink or 0) + 1) % 320
  -- The bar fill owns the menu while it runs: UpdateHPBar2 is a blocking
  -- predef in item_effects.asm, so no button is read until it lands (#252).
  local heal = self.heal
  if heal then
    heal.shown = math.min(heal.mon.hp,
                          heal.shown + math.max(1, heal.mon.stats.hp) / 96)
    if heal.shown >= heal.mon.hp then
      self.heal = nil
      if heal.onDone then heal.onDone() end
    end
    return
  end
  local input = self.game.input
  local party = self.party or self.game.save.party

  -- HandlePartyMenuInput (home/pokemon.asm) and the field-move submenu
  -- (engine/menus/start_sub_menus.asm .chosePokemon) both run through
  -- HandleMenuInput_, which beeps SFX_PRESS_AB on any A or B press (#570).
  -- game.data is nil under the stub games the UI harnesses drive.
  if self.game.data and (input:wasPressed("a") or input:wasPressed("b")) then
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end

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
      if followerUnavailable(self.game, mon) then
        refuseUnavailable(self)
        return
      end
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
        -- .fly checks THUNDERBADGE first, then CheckIfInOutsideMap
        -- (OVERWORLD + PLATEAU -- Route 23 / Indigo Plateau outdoor -- not
        -- OVERWORLD alone, #83); both refusals loop back to the submenu
        if ow and not ow:partyKnows("FLY") then
          refuseBadge(self)
          return
        end
        if ow and not Map.isOutside(ow.map.def,
             FieldDefaults.field(self.game.data, "outsideTilesets")) then
          local TextBox = require("src.render.TextBox")
          local def = self.game.data.pokemon[mon.species]
          local txt = (self.game.data.text._CannotFlyHereText
                       or Strings("{RAM:wNameBuffer} can't\nFLY here."))
                      :gsub("{RAM:wNameBuffer}", mon.nickname or def.name)
          self.game.stack:push(TextBox.new(self.game, txt))
          return -- .loop: submenu stays open behind the message
        end
        self.game.stack:pop() -- close the party menu
        Screens.push(self.game, "TownMap", { fly = true, onFly = function(mapId)
          if ow then ow:flyTo(mapId) end
        end })
        return
      elseif action == "flash" then -- FLASH lights dark tunnels
        -- start_sub_menus.asm .flash: PrintText _FlashLightsAreaText runs
        -- with the party menu still on screen, and only then
        -- GBPalWhiteOutWithDelay3 + jp .goBackToMap.  So the message reads
        -- over the menu, and the cave is lit when the blink hands the
        -- screen back, never under the text (#385).
        local ow = self.game.overworld
        if ow and not ow:partyKnows("FLASH") then
          refuseBadge(self)
          return
        end
        ow:useFlashFieldMove(function() self:close() end)
        return
      elseif action == "surf" then
        -- start_sub_menus.asm .surf: SOULBADGE-gated (useSurfFieldMove),
        -- then IsSurfingAllowed (the Cycling Road / Seafoam B4F
        -- current refusals, both of which loop back to the submenu), then
        -- ItemUseSurfboard: while surfing it tries to dismount instead;
        -- otherwise it mounts only if the FACING tile is water, else
        -- SurfingAttemptFailed (_NoSurfingHereText) loops back to the
        -- submenu.  useSurfFieldMove reports which; trySurf does the mount.
        local ow = self.game.overworld
        local reason = ow:useSurfFieldMove()
        local Transition = require("src.render.Transition")
        if reason == "ok" then
          -- UseItem prints _SurfingGotOnText with the party menu still up;
          -- GBPalWhiteOutWithDelay3 + jp .goBackToMap only follow it, so
          -- trySurf closes this menu when its text does (#385)
          local fx, fy = ow.player:facingCell()
          ow:trySurf(fx, fy, function() self:close() end)
          return
        end
        if reason == "dismount" then
          -- ItemUseSurfboard .stopSurfing: no text -- the walking state
          -- and music return first (PlayDefaultMusic +
          -- LoadWalkingPlayerSpriteGraphics), the menu closes with the
          -- GBPalWhiteOutWithDelay3 blink, and the simulated pad press
          -- steps the player forward onto land (or across a connection
          -- strip when the shore is the next map's edge)
          ow:stopSurfing(function() self.game.stack:pop() end)
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
          -- (GBPalWhiteOutWithDelay3 + .goBackToMap), and the text prints
          -- over the still-open menu like every other .loop refusal (#385)
          self.game.stack:push(TextBox.new(self.game, txt, function()
            self:close()
            self.game.stack:push(Transition.whiteFlash(self.game))
          end))
          return
        end
        self.game.stack:push(TextBox.new(self.game, txt))
        return -- .loop: submenu stays open behind the message
      elseif action == "cut" then
        -- start_sub_menus.asm .cut -> predef UsedCut (engine/overworld/cut.asm):
        -- CASCADEBADGE-gated (useCutFieldMove); _NothingToCutText loops back
        -- to the submenu when the FACING tile isn't a cuttable tree.
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
        -- start_sub_menus.asm .strength: RAINBOWBADGE-gated;
        -- predef PrintStrengthText (field_move_messages.asm) sets
        -- BIT_STRENGTH_ACTIVE of wStatusFlags1 -- the sole gate
        -- push_boulder.asm reads -- then prints _UsedStrengthText (no
        -- prompt: after the text, the text_asm tail plays the chosen
        -- mon's cry, Delay3, and it auto-advances) and
        -- _CanMoveBouldersText (`prompt`: waits for A/B).  Back in
        -- .strength, GBPalWhiteOutWithDelay3 blinks the screen white
        -- before CloseTextDisplay returns to the map.
        local ow = self.game.overworld
        if ow and ow.useStrengthFieldMove then
          if not ow:partyKnows("STRENGTH") then
            refuseBadge(self)
            return
          end
          ow:useStrengthFieldMove(mon, function() self:close() end)
          return
        elseif ow and ow.useFieldMove then
          ow:useFieldMove("STRENGTH", mon)
          self:close()
          return
        end
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
        if entry.move == "TELEPORT" then
          -- .teleport: TELEPORT works only OUTDOORS (CheckIfInOutsideMap --
          -- OVERWORLD + PLATEAU, #83); dark maps don't block it
          if ow and not Map.isOutside(ow.map.def,
               FieldDefaults.field(self.game.data, "outsideTilesets")) then
            local TextBox = require("src.render.TextBox")
            local def = self.game.data.pokemon[mon.species]
            local txt = (self.game.data.text._CannotUseTeleportNowText
                         or Strings("{RAM:wNameBuffer} can't\nuse TELEPORT now."))
                        :gsub("{RAM:wNameBuffer}", mon.nickname or def.name)
            self.game.stack:push(TextBox.new(self.game, txt))
            return -- .loop: submenu stays open behind the message
          end
        elseif ow and not (DIG_TILESETS[ow.map.def.tileset]
                           and ow.map.id ~= "AGATHAS_ROOM") then
          -- .dig runs ItemUseEscapeRope (it sets wCurItem = ESCAPE_ROPE):
          -- usable in the dungeon tilesets of escape_rope_tilesets.asm minus
          -- Agatha's room, even in the dark (Rock Tunnel); anywhere else
          -- .notUsable -> ItemUseNotTime, the same line BagMenu prints for a
          -- bagged ESCAPE ROPE
          local TextBox = require("src.render.TextBox")
          self.game.stack:push(TextBox.new(self.game,
            self.game.data.text._ItemUseNotTimeText
            or Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                       self.game.save.player.name)))
          return -- .loop: submenu stays open behind the message
        end
        self.game.stack:pop()
        if ow then ow:beginTeleportOut() end
        return
      end
      self.submenu = nil
    end
    return
  end

  local grid
  if self:gridNavigation() then
    local direction = input:wasPressed("left") and "left"
      or input:wasPressed("right") and "right"
      or input:wasPressed("up") and "up"
      or input:wasPressed("down") and "down"
    grid = gridIndex(self.index, #party, direction)
  end
  if grid then
    self.index = grid
    self.game.partyMenuSavedIndex = self.index
  elseif input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or math.max(1, #party)
    self.game.partyMenuSavedIndex = self.index -- HandlePartyMenuInput #768
  elseif input:wasPressed("down") then
    self.index = self.index < #party and self.index + 1 or 1
    self.game.partyMenuSavedIndex = self.index -- HandlePartyMenuInput #768
  elseif input:wasPressed("b") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  elseif input:wasPressed("a") and #party > 0 then
    local mon = party[self.index]
    if followerUnavailable(self.game, mon) then
      refuseUnavailable(self)
      return
    end
    if self.softboiledFrom then
      local user = party[self.softboiledFrom]
      self.softboiledFrom = nil
      self.game.overworld:useSoftboiledFieldMove(user, mon)
    elseif self.swapFrom then
      if self.swapFrom ~= self.index then
        party[self.swapFrom], party[self.index] = party[self.index], party[self.swapFrom]
        require("src.core.Sound").play(self.game.data, "Swap")
      end
      self.swapFrom = nil
    elseif self.onSwitch and (self.forceSwitch or self.pickOnly or not self.battle) then
      -- keepOpen callers (HP medicine) need the menu still drawn while the
      -- bar fills and the message prints, and close it themselves; everyone
      -- else keeps the old pop-then-call order.  Popping first is what made
      -- a POTION snap the picker shut before the item had even run (#252).
      if not self.keepOpen then self.game.stack:pop() end
      self.onSwitch(mon, self)
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
        -- This mon's field moves FIRST, then STATS/SWITCH
        -- (start_sub_menus.asm builds the same dynamic list).  The order is
        -- load bearing: DisplayFieldMoveMonMenu (engine/menus/text_box.asm)
        -- grows the box upward one row per field move and prints the field
        -- move names ABOVE PokemonMenuEntries ("STATS/SWITCH/CANCEL"), and
        -- StartMenu_Pokemon .choseOutOfBattleMove indexes wFieldMoves with
        -- menu items 0..n-1 while STATS/SWITCH sit at the bottom of the
        -- list.  GetMonFieldMoves walks wPartyMon1Moves in slot order, so
        -- the field moves keep the mon's move-list order -- which the loop
        -- below already does. #768
        items = {}
        -- Field moves (HMs/TMs) are usable out of battle even when the mon
        -- is fainted -- Gen 1 does not require HP for Cut/Fly/Surf/etc.
        -- Battle still excludes this list via `not self.battle`. Softboiled
        -- can appear for a fainted user; its heal transfer then no-ops.
        if not self.battle and ow then
          -- GetMonFieldMoves (engine/menus/text_box.asm) matches the mon's
          -- four moves against FieldMoveDisplayData and nothing else -- no
          -- badge, no map, no tileset test.  Every one of those lives in
          -- .outOfBattleMovePointers, i.e. on selection, where the refusal
          -- prints and .loop returns to this still-open submenu (#1022).
          for _, mv in ipairs(mon.moves) do
            if mv.id == "FLY" then
              table.insert(items, { label = Strings("FLY"), action = "fly" })
            elseif mv.id == "FLASH" then
              table.insert(items, { label = Strings("FLASH"), action = "flash" })
            elseif mv.id == "CUT" then
              table.insert(items, { label = Strings("CUT"), action = "cut" })
            elseif mv.id == "SURF" then
              table.insert(items, { label = Strings("SURF"), action = "surf" })
            elseif mv.id == "STRENGTH" then
              table.insert(items, { label = Strings("STRENGTH"), action = "strength" })
            elseif mv.id == "SOFTBOILED" then
              table.insert(items, { label = Strings("SOFTBOILED"), action = "softboiled" })
            elseif mv.id == "TELEPORT" then
              table.insert(items, { label = Strings("TELEPORT"),
                                    action = "escape", move = "TELEPORT" })
            elseif mv.id == "DIG" then
              table.insert(items, { label = Strings("DIG"),
                                    action = "escape", move = "DIG" })
            end
          end
        end
        -- PokemonMenuEntries always closes the list, under the field moves
        -- (text_box.asm .donePrintingNames). #768
        items[#items + 1] = { label = Strings("STATS"), action = "stats" }
        items[#items + 1] = { label = Strings("SWITCH"), action = "switch" }
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
-- item / TM-HM ids print their own strings, and EVO_STONE shares
-- PartyMenuItemUseText (party_menu.asm:229 PartyMenuMessagePointers).
-- Pure (no side effects) so drivers can assert it. #147 #1610
function PartyMenu:bottomMessage()
  if self.swapFrom then
    return self.game.data.text._PartyMenuSwapMonText
      or Strings("Move POKéMON\nwhere?")
  elseif self.tmhm then
    return self.game.data.text._PartyMenuUseTMText
      or Strings("Use TM on which\nPOKéMON?")
  elseif self.softboiledFrom or self.itemUse then
    return self.game.data.text._PartyMenuItemUseText
      or Strings("Use item on which\nPOKéMON?")
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
  local PaletteFX = require("src.render.PaletteFX")
  -- Each bar row carries its own GREENBAR / YELLOWBAR / REDBAR zone (see
  -- sgbPalettes), so the fill must stay the raw DMG shade-2 gray and let
  -- the zone color it -- but only when a zone pass will actually run.
  -- Renderer's blit takes the shader path exactly when the zone list is
  -- non-empty AND PaletteFX.shader() resolves, which is the same pair of
  -- conditions tested here; with no shader the canvas blits unshaded and
  -- drawHPBar's per-pixel tint is the only color the bar can get. #274
  local barZoned = PaletteFX.shader() ~= nil
                   and PaletteFX.pal(self.game.data, "GREENBAR") ~= nil
  for i, mon in ipairs(party) do
    local def = self.game.data.pokemon[mon.species]
    local y = PartyMenu.entryY(i)
    love.graphics.setColor(1, 1, 1, 1)
    PartyMenu.drawIcon(self.game, mon, 8, y, i == self.index, self.blink or 0)
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
    elseif self.evoStone then
      -- party_menu.asm:114 .evolutionStoneMenu: an EVOLVE_ITEM row matching
      -- wEvoStoneItemID, printed in the TM/HM strings' row+1 column+9 slot
      local can = false
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.method == "ITEM" and evo.item == self.evoStone then
          can = true break
        end
      end
      if can then
        Font.draw(Strings("ABLE"), 120, y + 8)
      else
        Font.draw(Strings("NOT ABLE"), 88, y + 8)
      end
    else
      if mon.hp <= 0 then
        Font.draw(Strings("FNT"), 136, y)
      elseif mon.status then
        Font.draw(Status.hudLabelFor(self.game.data.statuses, mon.status), 136, y)
      end
      -- the tile HP bar (DrawHP2 + SetPartyMenuHPBarColor).  grayFill:
      -- tinting the fill AND running it through the row's zone
      -- double-applies -- a green fill has red channel 0, so the tint
      -- zeroes the bar's red and the zone's red-keyed shade shader then
      -- maps every pixel to color 3, i.e. black.  That is the #229 hazard
      -- HudTiles documents; #274 (with #272) is this screen's instance.
      --
      -- While a medicine's UpdateHPBar2 fill runs, this row draws the HP the
      -- animation has reached rather than the final value; drawHPBar reads
      -- only .hp and .stats, so a shim table is enough and the real mon is
      -- never mutated for display (#252).
      local shown = mon
      if self.heal and self.heal.mon == mon then
        shown = { hp = math.floor(self.heal.shown), stats = mon.stats }
      end
      love.graphics.setColor(1, 1, 1, 1)
      HudTiles.drawHPBar(self.game.data, 5, (y + 8) / 8, shown, nil, barZoned)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(("%3d/%3d"):format(shown.hp, mon.stats.hp), 104, y + 8)
    end
    -- home/pokemon.asm PartyMenuInit seeds wTopMenuItemY/X with 1/0, so the
    -- cursor sits on the entry's *second* tile row (the level/HP line),
    -- level with the middle of the two-row icon -- not on the name row that
    -- entryY returns.  Drawing it at y put it a tile too high (#278).
    local cursorY = y + 8
    if i == self.index then
      Font.drawCode(Theme.cursor, 0, cursorY)
    end
    -- the unfilled swap arrow; the filled cursor replaces it in the tilemap
    -- when they share a row (PlaceMenuCursor, home/window.asm:184-185) (#814)
    if (i == self.swapFrom or i == self.softboiledFrom) and i ~= self.index then
      Font.drawCode(Theme.cursorHollow, 0, cursorY)
    end
  end
  -- every message id prints through PrintText, so it lands in the standard
  -- bottom text box, rows 12-17 (party_menu.asm:174). #147 #210 #1610
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local ly = 112
  for line in (self:bottomMessage() .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, 8, ly)
    ly = ly + 16
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

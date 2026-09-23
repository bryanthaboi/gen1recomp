-- pokefirered/src/hall_of_fame.c:709

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local RomText = require("src.core.game3.rom_text")
local HofGfx = require("src.ui.game3.hall_of_fame_gfx")

local HofPc = {}

HofPc.open = false
HofPc._teams = {}
HofPc._team = 0
HofPc._number = 0
HofPc._mon = 1
HofPc._corrupted = false

local MAX_TEAMS = 50 -- pokefirered/src/hall_of_fame.c:29
local SPECIES_EGG = 412 -- pokefirered/include/constants/species.h:421
local SPECIES_NIDORAN_F = 29 -- pokefirered/include/constants/species.h:33
local SPECIES_NIDORAN_M = 32 -- pokefirered/include/constants/species.h:36
local KANTO_SPECIES_END = 151 -- pokefirered/include/constants/species.h:157
local GAME_STAT_ENTERED_HOF = 10 -- pokefirered/include/constants/game_stat.h:14
local BG = { 22 / 31, 24 / 31, 29 / 31 } -- pokefirered/src/hall_of_fame.c:30
local BLEND_COEFF = 12 / 16 -- pokefirered/src/hall_of_fame.c:873
-- pokefirered/src/hall_of_fame.c:136
local WHITE_TEXT = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }

-- pokefirered/src/hall_of_fame.c:152
local FULL_TEAM = { { 120, 40 }, { 56, 40 }, { 184, 40 }, { 120, 88 }, { 200, 88 }, { 40, 88 } }
-- pokefirered/src/hall_of_fame.c:162
local HALF_TEAM = { { 120, 64 }, { 56, 64 }, { 184, 64 } }

local blendShader

local function shader()
  if blendShader == nil then
    local ok, s = pcall(love.graphics.newShader, [[
      extern vec3 target;
      extern number coeff;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(mix(p.rgb, target, coeff), p.a) * color;
      }
    ]])
    blendShader = ok and s or false
  end
  return blendShader or nil
end

local function members(team)
  local list = {}
  for i = 1, 6 do
    local mon = team and team[i]
    if mon and (tonumber(mon.species) or 0) ~= 0 then list[#list + 1] = mon end
  end
  return list
end

local function cry()
  local team = HofPc._teams[HofPc._team]
  local mon = members(team)[HofPc._mon]
  if not mon or tonumber(mon.species) == SPECIES_EGG then return end
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio.stopCry then Audio.stopCry() end
    Audio.playCry(tonumber(mon.species))
  end)
end

local function nationalEnabled(session)
  local ok, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  return ok and PokedexData.isNationalUnlocked(session, session and session.dex) or false
end

-- pokefirered/src/hall_of_fame.c:758
function HofPc.show(opts)
  opts = opts or {}
  local session = opts.session or {}
  HofPc._session = session
  HofPc._onDone = opts.onDone
  HofPc._teams = type(session.hallOfFameTeams) == "table" and session.hallOfFameTeams or {}
  HofPc._corrupted = #HofPc._teams == 0
  HofPc._team = math.min(#HofPc._teams, MAX_TEAMS)
  local stats = session.gameStats or {}
  HofPc._number = tonumber(stats[GAME_STAT_ENTERED_HOF]) or 0
  HofPc._mon = 1
  HofPc._national = nationalEnabled(session)
  HofPc.open = true
  Stack.push("hall_of_fame_pc", HofPc, { hideBelow = true })
  if not HofPc._corrupted then cry() end
end

function HofPc.isOpen()
  return HofPc.open
end

-- pokefirered/src/hall_of_fame.c:937
function HofPc.close()
  if not HofPc.open then return end
  HofPc.open = false
  pcall(function() require("src.core.game3.audio").stopCry() end)
  Stack.pop("hall_of_fame_pc")
  local cb = HofPc._onDone
  HofPc._onDone = nil
  if cb then cb() end
end

function HofPc.reset()
  HofPc.open = false
  HofPc._onDone = nil
  HofPc._session = nil
  HofPc._teams = {}
end

-- pokefirered/src/hall_of_fame.c:886
function HofPc.handleInput(input)
  if not HofPc.open then return end
  if HofPc._corrupted then
    if input:wasPressed("a") then HofPc.close() end -- pokefirered/src/hall_of_fame.c:980
    return
  end
  local count = #members(HofPc._teams[HofPc._team])
  if input:wasPressed("a") then
    if HofPc._team > 1 then
      HofPc._team = HofPc._team - 1
      if HofPc._number ~= 0 then HofPc._number = HofPc._number - 1 end
      HofPc._mon = 1
      cry()
    else
      HofPc.close()
    end
  elseif input:wasPressed("b") then
    HofPc.close()
  elseif input:wasPressed("up") and HofPc._mon > 1 then
    HofPc._mon = HofPc._mon - 1
    cry()
  elseif input:wasPressed("down") and HofPc._mon < count then
    HofPc._mon = HofPc._mon + 1
    cry()
  end
end

local function drawBackground()
  -- pokefirered/src/hall_of_fame.c:1193
  HofGfx.drawStripes()
  -- pokefirered/src/hall_of_fame.c:749
  HofGfx.drawBands(16, 7)
end

-- pokefirered/src/menu.c:163
local function drawTopBar(left, right)
  love.graphics.setColor(FrlgFont.STDPAL[2])
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.setColor(1, 1, 1, 1)
  local white = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
  if left then Window.printPx(left, 2, 2, { colors = white }) end
  if right then
    local ok, PokedexChrome = pcall(require, "src.ui.game3.pokedex_chrome")
    if ok and PokedexChrome.drawControlInfo then PokedexChrome.drawControlInfo(right, 238, 2) end
  end
end

-- pokefirered/src/hall_of_fame.c:993
local function drawMonInfo(mon)
  local x0, y0 = 16, 120
  local sp = tonumber(mon.species) or 0
  local egg = sp == SPECIES_EGG
  local nick = tostring(mon.nickname or "")
  if not egg then
    local dex = (Pokemon.national and Pokemon.national(sp)) or sp
    local digits = (not HofPc._national and dex > KANTO_SPECIES_END) and "???" or string.format("%03d", dex)
    FrlgFont.draw(RomText.plain("gText_Number") .. digits, x0 + 16, y0 + 1, { colors = WHITE_TEXT })
  end
  local w = FrlgFont.measure(nick)
  local nx = egg and (x0 + 0x80 - math.floor(w / 2)) or (x0 + 0x80 - w)
  FrlgFont.draw(nick, nx, y0 + 1, { colors = WHITE_TEXT })
  if egg then return end
  local gender = " "
  if sp ~= SPECIES_NIDORAN_M and sp ~= SPECIES_NIDORAN_F then
    local g = Pokemon.gender(sp, tonumber(mon.personality) or 0)
    if g == "M" then gender = "♂" elseif g == "F" then gender = "♀" end
  end
  -- pokefirered/src/hall_of_fame.c:1066
  FrlgFont.draw("/" .. tostring(Pokemon.name(sp) or "") .. gender, x0 + 0x80, y0 + 1, { colors = WHITE_TEXT })
  FrlgFont.draw(RomText.plain("gText_Level") .. tostring(tonumber(mon.level) or 0), x0 + 0x20, y0 + 0x11,
    { colors = WHITE_TEXT })
  FrlgFont.draw(RomText.plain("gText_IDNumber") .. string.format("%05d", (tonumber(mon.trainerId) or 0) % 65536), x0 + 0x60,
    y0 + 0x11, { colors = WHITE_TEXT })
end

function HofPc.draw()
  if not HofPc.open then return end
  drawBackground()
  if HofPc._corrupted then
    -- pokefirered/src/hall_of_fame.c:969
    drawTopBar(nil, RomText.plain("gText_ABUTTONExit"))
    Window.dialogueFrame()
    Window.printPx(RomText.plain("gText_HOFCorrupted"), 16, 121)
    return
  end
  local list = members(HofPc._teams[HofPc._team])
  local pos = #list > 3 and FULL_TEAM or HALF_TEAM
  local sh = shader()
  for i, mon in ipairs(list) do
    local p = pos[i]
    local pic = p and Pokemon.monFrontPic(mon)
    if pic and pic.image then
      local dim = i ~= HofPc._mon
      if dim and sh then
        love.graphics.setShader(sh)
        sh:send("target", BG)
        sh:send("coeff", BLEND_COEFF)
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(pic.image, p[1] - 32, p[2] - 32)
      if dim and sh then love.graphics.setShader() end
    end
  end
  -- pokefirered/src/hall_of_fame.c:843
  local title = RomText.plain("gText_HOFNumber", { stringVars = { tostring(HofPc._number) } })
  local hint = HofPc._team <= 1 and RomText.plain("gText_UPDOWNPick_ABUTTONBBUTTONCancel")
    or RomText.plain("gText_UPDOWNPick_ABUTTONNext_BBUTTONBack")
  drawTopBar(title, hint)
  local mon = list[HofPc._mon]
  if mon then drawMonInfo(mon) end
end

return HofPc

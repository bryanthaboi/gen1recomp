package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local Catalog = require("src.box.Catalog")
local CacheFs = require("src.import.CacheFs")
local Sprites = require("src.online.OnlineSprites")
local MonAnim = require("src.core.game3.mon_anim")
local GameVersion = require("src.core.GameVersion")
local Data = MonAnim.Data
local bodies, images, draws, quads = {}, {}, {}, 0
local previousRead, previousArt = CacheFs.readAt, Catalog.art
local previousData = Data._cache
Data._cache = { sentinel = true }
CacheFs.readAt = function(path)
  if bodies[path] == false then error("cache blob " .. path .. " is not deflated (stale cache, reimport)", 0) end
  return bodies[path]
end
local front = {
  functions = { [0] = "Anim_VerticalSquishBounce" },
  animIds = { [1] = 0, [308] = 0 }, animDelays = { [1] = 2 },
  species = { [1] = { 0, 1 }, [308] = { 0, 1 } },
  lists = {
    [0] = { cmds = { { frame = 0, duration = 0 }, { op = "end" } } },
    [1] = { cmds = { { frame = 0, duration = 4 }, { frame = 1, duration = 4 },
      { frame = 0, duration = 4 }, { op = "end" } } },
  },
}
bodies["emerald/data/generated/gba/pokemon/front_anims.lua"] = Serializer.encode(front)
local frameBytes = 64 * 64 * 4
bodies["emerald/data/generated/gba/pokemon/front_anim/1.rgba"] = string.rep("A", frameBytes) .. string.rep("B", frameBytes)
bodies["emerald/data/generated/gba/pokemon/front_anim_shiny/1.rgba"] = string.rep("S", frameBytes) .. string.rep("T", frameBytes)
local function image(raw, w, h)
  local obj = { raw = raw, w = w or 64, h = h or 64 }
  function obj:getDimensions() return self.w, self.h end
  function obj:setFilter(a, b) self.filter = { a, b } end
  function obj:release() self.released = true end
  images[#images + 1] = obj
  return obj
end
love.image.newImageData = function(w, h, _, raw)
  return { w = w, h = h, raw = raw, release = function(self) self.released = true end }
end
love.graphics.newImage = function(pixels) return image(pixels.raw, pixels.w, pixels.h) end
love.graphics.newQuad = function(x, y, w, h) quads = quads + 1; return { x = x, y = y, w = w, h = h } end
love.graphics.draw = function(...) draws[#draws + 1] = { ... } end
local ordinary = { front = image("ordinary") }
local shiny = { front = image("shiny") }
local spotted = { front = image("personality-specific spots") }
local artVersion = "emerald"
Catalog.art = function(entry)
  return entry.mon.species == 308 and spotted or entry.display.shiny and shiny or ordinary,
    artVersion, { species = entry.mon.species, personality = entry.mon.personality }
end
local function entry(species, isShiny)
  return { version = "red", generation = 1, mon = { species = species, personality = 1001 },
    display = { national = species, shiny = isShiny } }
end
local Animation = require("src.box.Animation")
local mon = entry(1)
local before = Serializer.encode(mon)
local animation = Animation.new(mon)
T.check(animation ~= nil, "imported Emerald metadata starts the real summary animator")
T.eq(animation.sprite.animationData.version, "emerald", "animator uses an explicit Emerald provider")
T.eq(animation.frames[1].raw:sub(1, 1), "B", "alternate pose comes from the normal Emerald sheet")
T.same(animation.frames[1].filter, { "nearest", "nearest" }, "animated pixels use nearest filtering")
local alternate, transformed = false, false
for _ = 1, 300 do
  Animation.update(animation, 1 / 60)
  if animation.sprite.frame == 1 then
    alternate = true
    love.graphics.setColor(0.2, 0.3, 0.4, 0.5)
    Animation.draw(animation, 10, 20, 128)
    T.eq(draws[#draws][1], animation.frames[1], "detail drawing uses the current animation pose")
    T.same({ love.graphics.getColor() }, { 0.2, 0.3, 0.4, 0.5 }, "animation restores the surrounding UI colour")
    break
  end
end
T.check(alternate, "real sprite command stream advances into the alternate pose")
for _ = 1, 300 do
  Animation.update(animation, 1 / 60)
  local transform = MonAnim.transform(animation.sprite)
  transformed = transformed or transform.y2 ~= 0 or transform.sx ~= 1 or transform.sy ~= 1
  if MonAnim.done(animation.sprite) then break end
end
T.check(transformed, "species callback animates its position or affine scale")
T.check(MonAnim.done(animation.sprite), "summary animation finishes instead of looping forever")
local n = animation.sprite.frames
Animation.update(animation, 1)
T.eq(animation.sprite.frames, n, "finished animations remain on their resting pose")
T.eq(Serializer.encode(mon), before, "animation leaves the stored Pokémon unchanged")
T.eq(GameVersion.get(), "red", "Emerald animation does not switch the active game")
T.eq(Data._cache.sentinel, true, "Emerald animation does not replace the active animation cache")
T.eq(CacheFs.prefix, "", "Emerald animation does not remount the imported cache")

local sparkling = Animation.new(entry(1, true))
T.eq(sparkling.frames[1].raw:sub(1, 1), "T", "shiny alternate poses retain the shiny palette")
local spinda = Animation.new(entry(308))
T.check(spinda ~= nil, "one-frame species still get their species motion")
T.eq(spinda.art.front, spotted.front, "Spinda motion retains its personality-specific spots")
T.eq(next(spinda.frames), nil, "Spinda never substitutes a generic second-frame picture")
local egg = entry(1); egg.mon.isEgg = true
T.eq(Animation.new(egg), nil, "eggs keep their egg picture")
artVersion = "sapphire"
T.eq(Animation.new(mon), nil, "non-Emerald fallback artwork stays valid and static")
artVersion = "emerald"
T.eq(Animation.new(entry(999)), nil, "unsupported animation species safely stays static")
local sheet = bodies["emerald/data/generated/gba/pokemon/front_anim/1.rgba"]
bodies["emerald/data/generated/gba/pokemon/front_anim/1.rgba"] = false
local okCorrupt, corrupt = pcall(Animation.new, mon)
T.check(okCorrupt and corrupt ~= nil and next(corrupt.frames) == nil,
  "an undecodable Emerald animation sheet leaves the box on its still front: " .. tostring(corrupt))
bodies["emerald/data/generated/gba/pokemon/front_anim/1.rgba"] = sheet
Animation.reset()
bodies["emerald/data/generated/gba/pokemon/front_anims.lua"] = nil
T.eq(Animation.new(mon), nil, "older imported caches without animation metadata safely stay static")
T.check(sparkling.released and spinda.released, "refresh releases all current animated pictures")
T.check(animation.released, "finished animation pictures are also released on refresh")
T.eq(Animation.draw(animation, 0, 0, 64), false, "released pictures cannot be drawn")

local icon = { icon = image("icon sheet", 32, 64), iconW = 32, iconH = 32 }
Sprites.drawIcon(icon, 0, 0, 48, 0)
T.eq(draws[#draws][2].y, 0, "icon animation begins at its first pose")
Sprites.drawIcon(icon, 0, 0, 48, 1)
T.eq(draws[#draws][2].y, 32, "icon animation selects its second pose")
Sprites.drawIcon(icon, 0, 0, 48, 2)
T.eq(draws[#draws][2].y, 0, "icon poses loop within the actual sheet")
T.eq(quads, 2, "steady icon animation reuses its quads")
Sprites.drawIcon(icon, 0, 0, 48)
T.eq(draws[#draws][2].y, 0, "existing callers retain the original static icon")
CacheFs.readAt, Catalog.art, Data._cache = previousRead, previousArt, previousData
Animation.reset()
T.finish()

-- The engine's own player-facing text, made overridable.
--
-- Extracted dialogue already had a home: `Data.text`, keyed by pokered's
-- labels, which a mod reaches through `mod.content.text`.  The strings the
-- engine *authors* had none.  Battle messages, item results, menu labels
-- and the link-play screens were literals in Lua, so a translator could
-- reach two thirds of the game and no more (#186, #245).
--
-- Those literals stay where they are, wrapped in `S(...)`, and the English
-- source doubles as the catalog key:
--
--   self:say(S("But, it failed!"))
--   self:say(S("Wild %s\nappeared!", self.enemy.name))
--
-- Keying on the source rather than on an invented id is deliberate.  It
-- keeps the English readable at the point it is used (the alternative
-- scatters a thousand `battle.it_failed` ids that have to be looked up to
-- review a diff), it needs no id registry to stay in sync, and an entry a
-- translation has not covered yet falls through to English instead of
-- rendering a raw id at the player.  The cost is that editing an English
-- string orphans its translations; `tools/modkit.py translation --refresh`
-- reports those as changed keys rather than silently dropping them.
--
-- Same-source-different-meaning is the one case source keys cannot hold on
-- their own ("OFF" as a filter setting vs "OFF" as a toggle, which some
-- languages render differently).  Those sites pass a context:
--
--   S("OFF", "options.musicFilter")   -- key: "options.musicFilter|OFF"
--
-- A mod supplies the catalog through the `strings` registry:
--
--   mod.content.strings:override("But, it failed!", "Echec !")
--
-- With no mod loaded the catalog is empty and `S` is an identity function
-- guarded by one boolean, so a vanilla boot draws byte-identical text.

local Strings = {}

local catalog = nil   -- Data.strings once a mod has put something in it
local missing = {}    -- format-arity complaints, reported once each

-- Called from Game after the mod merge, and again on dev-mode hot reload.
-- Holding the table (not a copy) means a mod that registers late still
-- takes effect without a second load.
function Strings.load(data)
  local t = data and data.strings
  catalog = nil
  if type(t) ~= "table" then return end
  for _ in pairs(t) do
    catalog = t
    return
  end
end

function Strings.active()
  return catalog ~= nil
end

-- The lookup itself.  `context` is optional and only disambiguates sources
-- that collide; the plain key is tried after it, so a translation that does
-- not care about the distinction can supply one entry for both.
function Strings.lookup(source, context)
  if not catalog then return source end
  if context then
    local hit = catalog[context .. "|" .. source]
    if type(hit) == "string" then return hit end
  end
  local hit = catalog[source]
  if type(hit) == "string" then return hit end
  return source
end

-- Count `%`-directives so a translation that drops or adds one is caught
-- here rather than as a mid-battle `string.format` error.
local function specifiers(s)
  local n = 0
  for spec in s:gmatch("%%(.)") do
    if spec ~= "%" then n = n + 1 end
  end
  return n
end

-- S(source)                -> translated source
-- S(source, ...)           -> translated source, string.format'ed
-- S(source, context)       -> context-disambiguated lookup, no formatting
--
-- The two-argument forms are told apart by whether the source carries any
-- format directives: a source with no `%s` cannot be formatting, so a lone
-- string second argument is a context.
function Strings.get(source, ...)
  local argc = select("#", ...)
  if argc == 0 then return Strings.lookup(source) end

  local wants = specifiers(source)
  if wants == 0 and argc == 1 and type((...)) == "string" then
    return Strings.lookup(source, (...))
  end

  local text = Strings.lookup(source)
  -- A translation with the wrong arity would raise inside string.format,
  -- which in a battle means a crash the player cannot escape.  Fall back to
  -- the English source, which is known to match, and say so once.
  if specifiers(text) ~= wants then
    if not missing[source] then
      missing[source] = true
      require("src.core.Logger").warn(
        "strings: translation of %q has %d format directives, source has %d"
        .. " -- using the source", source, specifiers(text), wants)
    end
    text = source
  end
  local ok, out = pcall(string.format, text, ...)
  if not ok then return source end
  return out
end

-- A marker, not a lookup: returns its argument untouched.
--
-- Some templates are declared in a module-level table and formatted much
-- later (BattleState's charge-move lines, for one).  Translating at the
-- declaration would freeze the English, because those tables are built at
-- require time and Strings.load has no catalog yet; the use site therefore
-- calls Strings(template, ...) and looks the source up then.  That works at
-- runtime but leaves the literal invisible to the catalog generator, which
-- only sees what is spelled out at a call site.  Wrapping the declaration in
-- Strings.source puts it back in the harvest while changing nothing at all
-- about when the lookup happens.
function Strings.source(text)
  return text
end

setmetatable(Strings, { __call = function(_, ...) return Strings.get(...) end })

return Strings

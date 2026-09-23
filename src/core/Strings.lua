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
-- string.format fills directives in argument order, so a translation whose
-- language puts the values the other way round cannot say so with `%s`
-- alone.  It numbers them instead, the way POSIX printf does:
--
--   S("%s's %s\nrose!", name, stat)  -- English: "PIKACHU's ATTACK\nrose!"
--   -> "%2$s de\n%1$s monte!"         -- French:  "ATTACK de\nPIKACHU monte!"
--
-- A translation numbers all of its directives or none, and numbers only
-- arguments the source has (it may leave one out, as the official
-- translations sometimes drop a name); anything else falls back to the
-- English.
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

-- A translation that numbers its directives ("%2$s ... %1$s"): the plain
-- format string and the argument order it asks for.  nil when nothing is
-- numbered; false when numbered and plain directives are mixed.
local function positional(text)
  if not text:find("%%%d+%$") then return nil end
  local out, order = {}, {}
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c ~= "%" then
      out[#out + 1] = c
      i = i + 1
    elseif text:sub(i + 1, i + 1) == "%" then
      out[#out + 1] = "%%"
      i = i + 2
    else
      local index, spec, stop = text:match("^%%(%d+)%$([-+ #0]*%d*%.?%d*%a)()", i)
      if not index then return false end
      order[#order + 1] = tonumber(index)
      out[#out + 1] = "%" .. spec
      i = stop
    end
  end
  if #order == 0 then return nil end
  return table.concat(out), order
end

-- Every numbered directive names one of the source's arguments.
local function withinArguments(order, wants)
  for _, index in ipairs(order) do
    if index < 1 or index > wants then return false end
  end
  return true
end

local function complain(source, fmt, ...)
  if missing[source] then return end
  missing[source] = true
  require("src.core.Logger").warn(fmt, ...)
end

local function render(source, text, ...)
  local wants = specifiers(source)
  -- A translation with the wrong arity would raise inside string.format,
  -- which in a battle means a crash the player cannot escape.  Fall back to
  -- the English source, which is known to match, and say so once.
  local plain, order = positional(text)
  if plain == false or (plain and not withinArguments(order, wants)) then
    complain(source, "strings: translation of %q numbers its format directives"
      .. " wrongly for %d argument(s) -- using the source", source, wants)
    plain, text = nil, source
  elseif not plain and specifiers(text) ~= wants then
    complain(source, "strings: translation of %q has %d format directives, source has %d"
      .. " -- using the source", source, specifiers(text), wants)
    text = source
  end
  local ok, out
  if plain then
    local args, picked = { ... }, {}
    for k, index in ipairs(order) do picked[k] = args[index] end
    ok, out = pcall(string.format, plain, (table.unpack or unpack)(picked, 1, #order))
  else
    ok, out = pcall(string.format, text, ...)
  end
  if ok then return out end
  -- A translation the checks above let through can still fail to format (a
  -- %d handed a string); the English source is known to match its arguments.
  ok, out = pcall(string.format, source, ...)
  if ok then return out end
  return source
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

  return render(source, Strings.lookup(source), ...)
end

function Strings.translate(source, context, ...)
  if not catalog then return nil end
  local text = Strings.lookup(source, context)
  if text == source then return nil end
  return render(source, text, ...)
end

function Strings.translateLabel(label, source, ...)
  if not catalog then return nil end
  local text = catalog[label]
  if type(text) ~= "string" or text == "" then return nil end
  return render(source, text, ...)
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

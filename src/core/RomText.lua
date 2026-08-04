-- The line the game itself prints, with the engine's wording as backup.
--
-- pokered prints most of what the player reads -- battle messages, item
-- results, field prompts -- and the importer extracts every one of those
-- labels.  Writing the sentence again in Lua meant the screen showed a
-- near-miss of the game's own wording while the cache held the real line,
-- and on a localized import it showed English over translated data.
--
-- Callers pass the pokered label plus the literal they used to print, so
-- the literal stays catalog-backed (Strings) for a cache built before the
-- label, for a total conversion that dropped it, and for the pure-module
-- tests that run without a dataset.
--
-- The slots the extracted text carries ({USER}, {TARGET}, the {RAM:...}
-- buffers) are NOT in the token registry TextBox.substitute serves -- that
-- one only resolves {PLAYER}, {RIVAL} and three string buffers -- so they
-- are filled here, in argument order, before the box ever sees the string.
--
-- {PLAYER}/{RIVAL} are the two the registry CAN fill later, so they are
-- only consumed here when the caller clearly supplies them: an argument
-- count matching every slot.  Matching just the other slots leaves those
-- two alone for that pass.  Anything else means the extracted line cannot
-- carry what the call has to say -- a few labels stop at a dynamic marker
-- the decoder does not follow, e.g. _EnemysWeakText extracts as "The
-- enemy's weak!\nGet'm! " with nowhere to put the name -- so the engine's
-- own wording stands in rather than printing a sentence with a hole in it.

local Strings = require("src.core.Strings")

return function(data, label, fallback, ...)
  local text = data and data.text and data.text[label]
  if not text then return Strings(fallback, ...) end
  local args = { ... }
  if #args == 0 then return text end

  local slots, named = 0, 0
  for token in text:gmatch("%b{}") do
    slots = slots + 1
    if token == "{PLAYER}" or token == "{RIVAL}" then named = named + 1 end
  end
  local fillNamed
  if #args == slots then
    fillNamed = true
  elseif #args == slots - named then
    fillNamed = false
  else
    return Strings(fallback, ...)
  end

  local index = 0
  return (text:gsub("%b{}", function(token)
    if not fillNamed and (token == "{PLAYER}" or token == "{RIVAL}") then
      return token
    end
    index = index + 1
    local value = args[index]
    if value == nil then return token end
    return tostring(value)
  end))
end

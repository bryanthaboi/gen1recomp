-- Shared slot-scrub entry widget: the digit-scrub interaction LinkState's
-- own `ipDigits`/`addrPos` already uses for IP entry, over the Crockford-32
-- style alphabet pokeserver room/tournament codes are drawn from
-- (23456789ABCDEFGHJKMNPQRSTUVWXYZ -- no 0/O/1/I/L, so a code read aloud or
-- handwritten never has to be checked twice).
--
-- The Gen 1 naming grid cannot stand in for this: it has no digits at all
-- (data/text/alphabets.asm is letters and punctuation), so a room code or
-- an address typed there would be unenterable.  That is what this exists
-- for.
--
-- new() takes an optional {length=, charset=} so the same interaction can
-- carry something other than a room code -- a dotted IP over "0123456789.",
-- say.  Both default to the room-code shape, so existing callers are
-- unaffected and CodeEntry.LENGTH / CodeEntry.CHARSET still describe them.

local CodeEntry = {}

CodeEntry.CHARSET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CodeEntry.LENGTH = 6

-- state carries its own length/charset so a caller holding two widgets of
-- different shapes cannot have one read the other's alphabet
function CodeEntry.new(opts)
  local charset = (opts and opts.charset) or CodeEntry.CHARSET
  local length = (opts and opts.length) or CodeEntry.LENGTH
  local chars = {}
  for i = 1, length do chars[i] = 1 end -- index into charset, 1-based
  return { chars = chars, pos = 1, charset = charset, length = length }
end

-- Seed the slots from an existing string: prefilling the LAN address means
-- the player scrubs the last octet instead of all twelve digits.  Anything
-- not in the charset lands on slot 1's character.
-- Slots past the end of the seed -- and any character the charset does not
-- carry -- land on the charset's blank where it has one, so seeding a
-- 15-slot address widget with "192.168.1.40" reads back as that address and
-- not as "192.168.1.40000".  A charset with no blank (the room code's) has
-- nowhere to put one, so those fall back to the first character as before.
function CodeEntry.fromText(text, opts)
  local state = CodeEntry.new(opts)
  local blank = state.charset:find(" ", 1, true) or 1
  for i = 1, state.length do
    local ch = tostring(text or ""):sub(i, i)
    state.chars[i] = (ch ~= "" and state.charset:find(ch, 1, true)) or blank
  end
  return state
end

local function charsetOf(state) return state.charset or CodeEntry.CHARSET end
local function lengthOf(state) return state.length or CodeEntry.LENGTH end

function CodeEntry.up(state)
  local n = #charsetOf(state)
  state.chars[state.pos] = state.chars[state.pos] % n + 1
end

function CodeEntry.down(state)
  local n = #charsetOf(state)
  state.chars[state.pos] = (state.chars[state.pos] - 2) % n + 1
end

function CodeEntry.left(state)
  state.pos = math.max(1, state.pos - 1)
end

function CodeEntry.right(state)
  state.pos = math.min(lengthOf(state), state.pos + 1)
end

-- the character in slot i, which is what a draw loop wants
function CodeEntry.charAt(state, i)
  local charset = charsetOf(state)
  return charset:sub(state.chars[i], state.chars[i])
end

function CodeEntry.text(state)
  local out = {}
  for i = 1, lengthOf(state) do out[i] = CodeEntry.charAt(state, i) end
  return table.concat(out)
end

return CodeEntry

-- Regression coverage for #601 "Wrong dialogue when interacting with Prof.
-- Oak's last ball" (T2, ROM-free).
--
-- pret/pokered scripts/OaksLab.asm OaksLabSelectedPokeBallScript: once
-- EVENT_GOT_STARTER is set, EVERY ball's text handler jumps to
-- OaksLabLastMonScript -- Oak turns to face the player and reads
-- "_OaksLabLastMonText" ("That's PROF.OAK's last #MON!") instead of
-- re-offering the starter.  The buggy port fell through to
-- _OaksLabThoseArePokeBallsText ("Those are POKé BALLs...") on every ball
-- once a starter had been picked.  The fix also spells the ROM's "#MON"
-- ligature out as "Pokémon".
--
-- The three ball scripts share one table (starterBall), so this suite
-- drives that table through a mini ScriptRunner-compatible executor:
-- flag checks, jumps, "end" halts and text rows are executed, UI-heavy
-- commands (push_screen, ask, give_pokemon, npc moves) are no-ops with
-- ask recording the offer text.  It then asserts the whole flow:
--   * GOT_STARTER + talk -> Oak faces down + "last Pokémon!" line, ends
--   * no GOT_STARTER, not escorted in -> "Those are POKé BALLs"
--   * no GOT_STARTER, escorted in -> the dex/ask offer (unchanged path)
-- plus MapScripts.validateContribution stays clean (the pre-fix table
-- carried nine out-of-range "jump 21" findings -- its run-time "end").

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local MapScripts = require("src.script.MapScripts")

local contribution = dofile("data/scripts/oaks_lab.lua")
local problems = MapScripts.validateContribution(contribution)
T.eq(#problems, 0, "oaks_lab contribution validates cleanly")
for _, p in ipairs(problems) do
  T.check(false, "unexpected finding: " .. p)
end

local BALL = "TEXT_OAKSLAB_CHARMANDER_POKE_BALL"

-- ---- mini executor over the talk rows (ScriptRunner semantics: a jump
-- command returns the next row index or "end" to halt)

local function run(script, flags, answer)
  local pc, texts, offers = 1, {}, {}
  local lastCheck = nil
  while pc <= #script do
    local row = script[pc]
    local verb = row[1]
    if verb == "check_flag" then
      lastCheck = flags[row[2]] == true
    elseif verb == "jump_if_true" then
      if lastCheck then
        if row[2] == "end" then break end
        pc = row[2] goto next
      end
    elseif verb == "jump_if_false" then
      if not lastCheck then
        if row[2] == "end" then break end
        pc = row[2] goto next
      end
    elseif verb == "jump" then
      if row[2] == "end" then break end
      pc = row[2]
      goto next
    elseif verb == "show_text" then
      texts[#texts + 1] = row[2]
    elseif verb == "ask" then
      offers[#offers + 1] = row[2]
      if answer == false then
        pc = pc + 1 -- decline: the next row's jump_if_false decides
        goto next
      end
    end
    -- push_screen / give_pokemon / set_flag / hide_object / move_npc_to /
    -- face_object: no-op here (set_flag is exercised via the fixture
    -- flags table instead of being run)
    pc = pc + 1
    ::next::
  end
  return texts, offers
end

local function concat(list)
  return table.concat(list, "\n")
end

-- ---- leftover ball after the pick: Oak faces down + the last-mon line
local got = { EVENT_GOT_STARTER = true, EVENT_FOLLOWED_OAK_INTO_LAB = true }
local texts, offers = run(contribution.talk[BALL], got, true)
T.eq(#offers, 0, "no starter offer after the pick")
local box = concat(texts)
T.check(box:find("last Pokémon!", 1, true) ~= nil,
  "leftover ball says the last-mon line (got: " .. box .. ")")
T.check(box:find("Those are", 1, true) == nil,
  "leftover ball no longer says 'Those are POKé BALLs'")
T.check(box:find("#MON", 1, true) == nil,
  "the ROM #MON ligature is spelled out as Pokémon")

-- the pokered beat also turns Oak to face the player: find the
-- face_object row in the leftover-ball path (content-based, so a jingle
-- row added for #668 doesn't shift the hard-coded index)
local oakFaceRow
for i, row in ipairs(contribution.talk[BALL]) do
  if row[1] == "face_object" and row[2] == 5 and row[3] == "down" then
    oakFaceRow = i
    break
  end
end
T.check(oakFaceRow ~= nil,
  "a face_object row turns Oak down before the line (OaksLabLastMonScript)")

-- ---- pre-escort: still the vanilla "Those are POKé BALLs" line
local pre = { EVENT_GOT_STARTER = false, EVENT_FOLLOWED_OAK_INTO_LAB = false }
local t2, o2 = run(contribution.talk[BALL], pre, true)
T.eq(#o2, 0, "no offer before Oak escorts the player in")
T.check(concat(t2):find("ThoseArePokeBalls", 1, true) ~= nil,
  "pre-escort balls keep the 'Those are POKé BALLs' line")

-- ---- escorted in but no pick yet: the dex + "You want X?" offer
local mid = { EVENT_GOT_STARTER = false, EVENT_FOLLOWED_OAK_INTO_LAB = true }
local t3, o3 = run(contribution.talk[BALL], mid, true)
T.eq(#o3, 1, "the starter offer still runs before the pick")
T.check(concat(t3):find("last Pokémon!", 1, true) == nil,
  "no last-mon line before the pick")

-- ---- all three balls share the same table shape (last-mon beat present)
-- content-based again: locate the leftover-ball "Pokémon" line wherever
-- it sits, instead of pinning a row number (#668 added two jingle rows)
for _, key in ipairs({
  "TEXT_OAKSLAB_CHARMANDER_POKE_BALL",
  "TEXT_OAKSLAB_SQUIRTLE_POKE_BALL",
  "TEXT_OAKSLAB_BULBASAUR_POKE_BALL",
}) do
  local script = contribution.talk[key]
  local lastMon
  if script then
    for _, row in ipairs(script) do
      if row[1] == "show_text" and type(row[2]) == "string"
          and row[2]:find("Pokémon", 1, true) then
        lastMon = row[2]
        break
      end
    end
  end
  T.check(lastMon ~= nil, key .. " carries the last-mon line")
end

T.finish("oaks_lab_last_ball_bug601")

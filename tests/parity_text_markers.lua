-- Parity test: text that has to wait for the player.
-- Self-contained: run via `luajit tests/parity_text_markers.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- The extractor emits three different break markers and they are not
-- interchangeable (src/render/TextBox.lua): \n opens the box's second line,
-- \v scrolls one line in after the down-arrow and a button press
-- (pokered ContText), and \f breaks the page, clearing and waiting.
--
-- Hand-written strings that spell `cont` or `para` as a plain \n put more
-- lines on a page than the two-line box can hold and give the player
-- nothing to press, so the text pours past by itself.  Two of those shipped:
--
--   #239 the trainer-battle run refusal, which lost "trainer battle!"
--   #250 the Viridian caterpillar description, which scrolled six lines by
--
-- Pagination is what the box actually consumes, so asserting on it (rather
-- than on the raw string) is what ties these to the observable symptom.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity text markers")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local TextBox = require("src.render.TextBox")

-- a page the box can actually show, and every line past the second on it
-- reached there by a \v the player has to release
local function pageIsPlayable(page, conts)
  if #page <= 2 then return true end
  for i = 3, #page do
    if not (conts and conts[i]) then return false end
  end
  return true
end

local function assertPlayable(label, text)
  local pages = TextBox.paginate(text)
  for i, page in ipairs(pages) do
    check(pageIsPlayable(page, pages.contBefore and pages.contBefore[i]),
          ("%s: page %d never runs past the box unattended"):format(label, i))
  end
  return pages
end

-- === #239: "No! There's no running from a trainer battle!" ===
-- The generated string is the authority; the port's literal is only a
-- fallback for a cache that predates it.
do
  local generated = Data.text._NoRunningText
  check(type(generated) == "string", "_NoRunningText is in the generated text")
  if generated then
    local pages = assertPlayable("_NoRunningText", generated)
    eq(#pages, 1, "the refusal is one page")
    eq(#pages[1], 3, "the refusal is three lines in a two-line box")
    check(pages.contBefore[1][3] == true,
          "'trainer battle!' scrolls in on a button press, not on its own (#239)")
    check(generated:find("trainer battle!", 1, true) ~= nil,
          "the third line is the part the bug swallowed")
  end

  -- the in-code fallback has to carry the same markers, or a pre-#239 cache
  -- reintroduces the bug
  local fallback = "No! There's no\nrunning from a\vtrainer battle!"
  local pages = assertPlayable("run-refusal fallback", fallback)
  eq(#pages[1], 3, "the fallback is three lines too")
  check(pages.contBefore[1][3] == true, "the fallback waits on line 3")
end

-- === #250: the CATERPIE / WEEDLE description ===
-- pokered/text/ViridianCity.asm declares this one without the leading
-- underscore the extractor keys on, so it is not in data/generated/text.lua
-- and the port carries a literal.  That makes the literal load-bearing.
do
  check(Data.text.ViridianCityYoungster2CaterpieAndWeedleDescriptionText == nil
        and Data.text._ViridianCityYoungster2CaterpieAndWeedleDescriptionText == nil,
        "the description really is absent from generated text (hence a literal)")

  local desc = "CATERPIE has no\npoison, but\vWEEDLE does.\fWatch out for its\nPOISON STING!"
  local pages = assertPlayable("caterpillar description", desc)
  eq(#pages, 2, "para breaks the description into two pages (#250)")
  eq(#pages[1], 3, "page 1 is text + line + cont")
  eq(#pages[2], 2, "page 2 is para + line")
  check(pages.contBefore[1][3] == true, "'WEEDLE does.' waits for a button")

  -- and the shape the bug had: one page, six lines, nothing to press
  local broken = "CATERPIE has no\npoison, but\nWEEDLE does.\n\nWatch out for its\nPOISON STING!"
  local brokenPages = TextBox.paginate(broken)
  eq(#brokenPages, 1, "the old spelling collapsed to a single page")
  check(#brokenPages[1] > 2, "the old spelling overfilled that page")
  check(not pageIsPlayable(brokenPages[1], brokenPages.contBefore[1]),
        "the old spelling is exactly what this suite is here to catch")
end

-- the ask that precedes it uses the generated string, which already carries
-- \v, so it is a live example of the marker done right
do
  local ask = Data.text._ViridianCityYoungster2YouWantToKnowAboutText
  check(type(ask) == "string", "the caterpillar question is in generated text")
  if ask then assertPlayable("caterpillar question", ask) end
end

S.finish()

-- Driver: TTF text mode through the bundled Plain Pixel font.  Teleports
-- straight into the overworld (no intro) and shows one dialogue line per
-- language back to back, shooting each: lang_english.png, lang_french.png,
-- lang_german.png, lang_spanish.png, lang_russian.png, lang_japanese.png,
-- lang_chinese.png in SHOT_DIR.  Judge glyph coverage, spacing, baseline,
-- and that the tile box border survives every one of them.
--   POKEPORT_DRIVER=tests/drivers/plainpixel_font_test.lua \
--     POKEPORT_IDENTITY=ttfdemo POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Font = require("src.render.Font")
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions -----------------------------------------------------
  check("the bundled TTF is present",
        love.filesystem.getInfo(Font.PLAINPIXEL) ~= nil)
  local okLoad, ttf = pcall(love.graphics.newFont, Font.PLAINPIXEL,
                            Font.PLAINPIXEL_SIZE)
  check("real LOVE can load it", okLoad and ttf ~= nil)

  game.save.player.name = "bryan"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  -- what a translation's register("ttf", {}) merges to
  game.data.font.ttf = {}
  Font.invalidate()
  check("ttf active after the merge", Font.ttfActive())

  local LINES = {
    { "english", "The quick brown fox\njumps over the lazy dog!" },
    { "french", "Un \195\169clair enveloppe le\nPOK\195\169MON sauvage! \195\135a alors!" },
    { "german", "Gr\195\182\195\159e und Gewicht des\nPOK\195\169MON \195\188berpr\195\188ft!" },
    { "spanish", "\194\161El POK\195\169MON enemigo\nest\195\161 paralizado! \194\191Y ahora?" },
    { "russian", "\208\148\208\184\208\186\208\184\208\185 "
        .. "\208\159\208\158\208\154\208\149\208\156\208\158\208\157 "
        .. "\208\191\208\190\209\143\208\178\208\184\208\187\209\129\209\143!" },
    { "japanese", "\227\129\147\227\130\147\227\129\171\227\129\161\227\129\175! "
        .. "\227\131\157\227\130\177\227\131\162\227\131\179\227\129\174\n"
        .. "\227\129\155\227\129\139\227\129\132\227\129\184 "
        .. "\227\130\136\227\129\134\227\129\147\227\129\157!" },
    -- NB: Plain Pixel 0.009's CJK block is partial (e.g. U+62D3, U+5922
    -- draw as tofu); stick to characters it covers
    { "chinese", "\228\189\160\229\165\189! \230\136\145\230\152\175"
        .. "\229\164\167\229\178\169\229\141\154\229\163\171!" },
  }

  for _, entry in ipairs(LINES) do
    local name, text = entry[1], entry[2]
    local done = false
    local box = TextBox.new(game, text, function() done = true end)
    game.stack:push(box)
    -- let the typewriter finish the page before shooting it
    for _ = 1, 300 do
      if box.waiting or box.done then break end
      U.wait(1)
    end
    U.wait(5)
    U.shot(game, DIR .. "/lang_" .. name .. ".png")
    for _ = 1, 20 do
      if done then break end
      U.tap(game, "a")
      U.wait(10)
    end
    U.wait(5)
    check("dismissed " .. name, done)
  end

  game.data.font.ttf = nil
  Font.invalidate()
  check("clearing the entry restores tile mode", not Font.ttfActive())

  U.log("shots in", DIR)
  U.log("DONE")
  love.event.quit(0)
end

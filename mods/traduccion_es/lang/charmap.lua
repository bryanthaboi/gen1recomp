-- Which byte sequence draws which glyph code.
--
-- Sequences are matched longest-first, so a multi-byte character and a
-- multi-character ligature both work: "ch" can be one glyph even though
-- "c" is also mapped.  Codes here must land inside a page declared in
-- lang/font.lua.
return {
  -- ["A"] = 0x100,
  -- ["B"] = 0x101,
}

local TextIR = require("src.core.game3.scripting.text_ir")

local RomText = {}

function RomText.ir(key)
  local Space = require("src.core.game3.scripting.space")
  local bundle = Space.ensureBundle()
  local ir = bundle and bundle.text and bundle.text[key]
  return assert(ir, "ROM text " .. tostring(key) .. " is not in the script cache")
end

function RomText.box(key, ctx)
  return TextIR.toTextBox(RomText.ir(key), ctx or {})
end

function RomText.plain(key, ctx)
  return TextIR.toPlain(RomText.ir(key), ctx or {})
end

return RomText

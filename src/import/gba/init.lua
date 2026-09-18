-- Package init for sevii.gba (optional; modules are required by full path).

return {
  Versions = require("src.import.gba.versions"),
  Extract = require("src.import.gba.extract_island1"),
  Register = require("src.import.gba.register"),
  Space = require("src.core.game3.scripting.space"),
  Vm = require("src.core.game3.scripting.vm"),
  Spec = "src.import.gba.SPEC",
}

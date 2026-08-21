-- Launcher SKINS tab (#1386): the tab next to Find that lists skins, imports
-- a dropped .zip and opens the desktop Skin Studio.  The rendered panel is
-- exercised by tests/drivers/launcher_skins_tab_shot.lua; this pins the
-- archive installer and the launcher wiring around it.
--   luajit tests/engine/launcher_skins_tab.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local TouchSkin = require("src.core.TouchSkin")

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

-- ------------------------------------------------------ archive installer

eq(select(1, TouchSkin.installArchive("skin.zip", nil)), nil,
   "an empty archive is refused")
eq(select(1, TouchSkin.installArchive("skin.zip", "")), nil,
   "a zero-byte archive is refused")
eq(select(1, TouchSkin.installArchive("notes.txt", "data")), nil,
   "a non-zip is refused")
eq(select(1, TouchSkin.installArchive("", "data")), nil,
   "a nameless drop is refused")

-- A zip carrying no skin file must not leave a stray archive behind: the
-- list would keep trying to mount it on every visit to the tab.
local junk = "PK\3\4 not really a skin"
local id, err = TouchSkin.installArchive("bogus.zip", junk)
eq(id, nil, "a zip with no skin.lua or .cfg is refused")
check(tostring(err):find("bogus.zip", 1, true) ~= nil,
      "and the error names the file")
eq(love.filesystem.read(TouchSkin.USER_ROOT .. "/bogus.zip"), nil,
   "the rejected archive is cleaned up, not left to fail on every listing")

-- the id a good archive would land under is the file name without .zip
check(TouchSkin.find("bogus") == nil, "a refused archive lists nothing")

-- ------------------------------------------------------- launcher wiring

local view = read("src/import/LauncherView.lua")
local imp = read("src/import/RomImporter.lua")

check(view:find('id = "skins"', 1, true) ~= nil,
      "LauncherView registers a skins tab")
check(view:find('id = "bug"', 1, true) ~= nil,
      "LauncherView registers a bug tab")
check(view:find("drawSkinGlyph", 1, true) ~= nil,
      "the skins tab draws its own glyph rather than shipping an asset")
check(view:find('assets/launcher/bug.png', 1, true) ~= nil,
      "the bug tab uses the standard bug report asset")
-- the tab has to be next to Find, which is what the request was
local order = view:match("local HEADER_TABS = %{(.-)%}\n")
check(order ~= nil, "HEADER_TABS found")
if order then
  local findAt = order:find('id = "find"', 1, true)
  local skinsAt = order:find('id = "skins"', 1, true)
  local bugAt = order:find('id = "bug"', 1, true)
  check(findAt and skinsAt and skinsAt > findAt,
        "the skins tab sits immediately after Find")
  check(skinsAt and bugAt and bugAt > skinsAt,
        "the bug tab sits after Skins")
end
check(view:find('imp.tab == "skins"', 1, true) ~= nil,
      "the panel dispatch routes the skins tab")
check(view:find("buildSkinsPanel", 1, true) ~= nil, "and a panel builds it")
check(view:find('imp.tab == "bug"', 1, true) ~= nil,
      "the panel dispatch routes the bug tab")
check(view:find("buildBugPanel", 1, true) ~= nil, "and the bug panel builds it")
check(view:find('Kit.toggle', 1, true) ~= nil,
      "the bug panel uses a switch for safe mode")
check(view:find('bug-report', 1, true) ~= nil,
      "the bug panel has a report action")
-- the panel must not offer the studio when the host did not supply it
check(view:find("if imp.onOpenSkinStudio then", 1, true) ~= nil,
      "the Studio button is hidden without a host hook (mobile)")
-- the studio boots a game on Play, so it needs a cartridge, not the tab id
check(view:find("imp.modScope or \"red\"", 1, true) ~= nil,
      "the studio is handed a real game version, never the skins tab id")

check(imp:find('if self.tab == "skins" then', 1, true) ~= nil,
      "a dropped zip on the skins tab installs a skin")
check(imp:find("_installSkinZip", 1, true) ~= nil, "skin zip installer exists")
check(imp:find("_installMod", 1, true) ~= nil,
      "and a zip elsewhere still installs a mod")
local cycle = imp:match("local order = %{(.-)%}")
check(cycle and cycle:find('"skins"', 1, true) ~= nil,
      "shoulder-button tab cycling reaches the skins tab")
check(cycle and cycle:find('"bug"', 1, true) ~= nil,
      "shoulder-button tab cycling reaches the bug tab")
local switch = imp:match("function RomImporter:_switchTab%(id%)(.-)\nend")
check(switch and switch:find("_ensureSkins(true)", 1, true) ~= nil,
      "switching to the tab re-reads the skin list")
check(imp:find('function RomImporter:_safeModeEnabled', 1, true) ~= nil
    and imp:find('function RomImporter:_toggleSafeMode', 1, true) ~= nil,
      "the importer owns the safe mode state")
check(imp:find('function RomImporter:_reportIssue', 1, true) ~= nil,
      "the importer owns issue report opening")

T.finish("launcher_skins_tab")

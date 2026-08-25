package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")
local TouchSkin = require("src.core.TouchSkin")

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function launcher()
  return RomImporter.new(function() end, { launcher = true })
end

eq(RomImporter.skinUrlName("https://example.com/pads/gbc.zip"), "gbc.zip",
   "a direct .zip keeps its name")
eq(RomImporter.skinUrlName("https://example.com/pads/Neon.deltaskin"),
   "Neon.deltaskin", "and so does a .deltaskin")
eq(RomImporter.skinUrlName("https://example.com/overlay.cfg"), "overlay.cfg",
   "a bare RetroArch cfg is kept as a cfg")
eq(RomImporter.skinUrlName("https://example.com/pads/gbc.zip?raw=1"), "gbc.zip",
   "a query string is not part of the name")
eq(RomImporter.skinUrlName("https://example.com/pads/gbc.zip#frag"), "gbc.zip",
   "nor is a fragment")
eq(RomImporter.skinUrlName("https://example.com/download"), "download.zip",
   "an extension-less link is treated as an archive")
eq(RomImporter.skinUrlName("https://example.com/a b/../pad.tar"), "pad.zip",
   "an unknown extension is replaced, and the name is sanitized")
check(RomImporter.skinUrlName("https://example.com/"):match("^[%w%._%-]+$"),
      "the download name can never escape the skins folder")

local name, payload = RomImporter.wrapSkinPayload("overlay.cfg",
  "overlays = 1\noverlay0_descs = 0\n")
eq(name, "overlay.zip", "a downloaded .cfg is wrapped into an archive")
eq(payload:sub(1, 2), "PK", "which is a real zip")
check(payload:find("overlays = 1", 1, true) ~= nil,
      "carrying the cfg text inside it")
check(payload:find("overlay.cfg", 1, true) ~= nil,
      "under the name RetroArch parsing expects")

local zipName, zipData = RomImporter.wrapSkinPayload("pad.zip", "PK\3\4stuff")
eq(zipName, "pad.zip", "a zip is passed through untouched")
eq(zipData, "PK\3\4stuff", "bytes and all")
eq(select(1, RomImporter.wrapSkinPayload("pad.deltaskin", "PK\3\4x")),
   "pad.deltaskin", "and so is a .deltaskin")
local pkName, pkData = RomImporter.wrapSkinPayload("overlay.cfg", "PK\3\4real")
eq(pkName, "overlay.zip", "a .cfg link that serves zip bytes is renamed, not refused")
eq(pkData, "PK\3\4real", "and its bytes are left alone")

local imp = launcher()
check(not imp:_addSkinFromUrl(""), "an empty link is refused")
check(imp._skinNotice and not imp._skinNotice.ok, "with a visible error")
eq(imp._skinFetch, nil, "and no download is started")
check(not imp:_addSkinFromUrl("file:///etc/passwd"),
      "a non-http link is refused")
eq(imp._skinFetch, nil, "and still starts nothing")
check(not imp:_addSkinFromUrl("skins/local.zip"),
      "a bare path is not a link either")

local Fetch = require("src.net.Fetch")
local realDownload, realPoll, realRelease = Fetch.download, Fetch.poll,
  Fetch.release
local asked
Fetch.download = function(url, dest) asked = { url = url, dest = dest } return 7 end
Fetch.poll = function() return { status = "pending", progress = 0.5 } end
Fetch.release = function() end

imp = launcher()
imp.skinUrl = "https://example.com/pads/neon.deltaskin"
check(imp:_addSkinFromUrl(), "a good link starts a download")
check(imp._skinFetch ~= nil, "and parks the job on the importer")
eq(asked.url, "https://example.com/pads/neon.deltaskin", "the url is fetched")
check(asked.dest:find("neon.deltaskin", 1, true) ~= nil,
      "into a file named after the link")
check(asked.dest:find("%.%.") == nil, "with no traversal in the path")
check(not imp:_addSkinFromUrl("https://example.com/other.zip"),
      "a second add while one is in flight is ignored")

imp:_pumpSkinFetch()
check(imp._skinFetch ~= nil, "a pending download stays in flight")

local installed
imp._installSkinData = function(_, n, d) installed = { name = n, data = d } return "neon" end
Fetch.poll = function()
  return { status = "ok", path = "skins/_download/neon.deltaskin" }
end
love.filesystem.write("skins/_download/neon.deltaskin", "PK\3\4payload")
imp:_pumpSkinFetch()
eq(imp._skinFetch, nil, "a finished download is released")
check(installed ~= nil, "and its bytes go to the installer")
eq(installed.name, "neon.deltaskin", "under the downloaded name")
eq(love.filesystem.read("skins/_download/neon.deltaskin"), nil,
   "the temporary download is cleaned up")
eq(imp.skinUrl, "", "and the field is cleared for the next one")

imp = launcher()
imp._installSkinData = function() return nil end
Fetch.download = function() return 8 end
Fetch.poll = function() return { status = "error", err = "404" } end
imp:_addSkinFromUrl("https://example.com/missing.zip")
imp:_pumpSkinFetch()
eq(imp._skinFetch, nil, "a failed download is released too")
check(imp._skinNotice and not imp._skinNotice.ok, "and reported")
check(tostring(imp._skinNotice.text):find("404", 1, true) ~= nil,
      "with the reason attached")

Fetch.download, Fetch.poll, Fetch.release = realDownload, realPoll, realRelease

imp = launcher()
eq(imp:_installSkinData("pad.zip", ""), nil, "an empty payload is refused")
check(imp._skinNotice and not imp._skinNotice.ok, "and says so")
eq(imp:_installSkinData("notes.txt", "hello"), nil, "a non-archive is refused")

love.filesystem.write("skins/warny.zip/overlay.cfg", [[
overlays = 1
overlay0_name = "warny"
overlay0_normalized = true
overlay0_descs = 2
overlay0_desc0 = "a,0.5,0.5,rect,0.05,0.05"
]])
imp = launcher()
eq(imp:_installSkinData("warny.zip", "PK\3\4stub"), "warny", "a skin installs")
check(imp._skinNotice.ok, "with an ok notice")
check(tostring(imp._skinNotice.text):find("missing desc", 1, true) ~= nil,
      "that repeats what the importer had to complain about")

love.filesystem.write("skins/vecty.deltaskin/info.json", [[
{ "name": "Vecty", "gameTypeIdentifier": "com.rileytestut.delta.game.gbc",
  "representations": { "iphone": { "standard": { "portrait": {
    "assets": { "resizable": "iphone_portrait.pdf" },
    "mappingSize": {"width":320,"height":480},
    "items": [ { "inputs": ["a"], "frame": {"x":0,"y":0,"width":32,"height":32} } ]
  } } } } }
]])
imp = launcher()
eq(imp:_installSkinData("vecty.deltaskin", "PK\3\4stub"), nil,
   "a PDF-only Delta skin does not install silently")
check(imp._skinNotice and not imp._skinNotice.ok, "the tab reports the refusal")
check(tostring(imp._skinNotice.text):find("PDF artwork", 1, true) ~= nil,
      "and says why, instead of listing a skin with no buttons")

local function dropped(fileName)
  return { getFilename = function() return fileName end,
           open = function() return false end }
end

local routed
local function routeDrop(tab, fileName)
  routed = nil
  local drop = launcher()
  drop.tab = tab
  drop._installSkinZip = function() routed = "skin" end
  drop._installMod = function() routed = "mod" end
  drop.startData = function() routed = "rom" end
  drop:filedropped(dropped(fileName))
  return routed
end

eq(routeDrop("mods", "pad.deltaskin"), "skin",
   "a dropped .deltaskin installs as a skin from any tab")
eq(routeDrop("skins", "pad.deltaskin"), "skin", "and from the skins tab")
eq(routeDrop("skins", "Neon.DeltaSkin"), "skin", "whatever its case")
eq(routeDrop("skins", "pad.zip"), "skin", "a zip on the skins tab is still a skin")
eq(routeDrop("mods", "pad.zip"), "mod", "and a mod anywhere else")

check(TouchSkin.saveTo(TouchSkin.newSkin("uxskin"), "uxskin") ~= nil,
      "a skin to list")
imp = launcher()
local entries = imp:_ensureSkins(true)
check(#entries > 0, "the installed skins are listed")
local byId = {}
for _, entry in ipairs(entries) do
  byId[entry.id] = entry
  check(type(entry.format) == "string",
        entry.id .. " reports the format it was parsed from")
end
eq(byId.uxskin and byId.uxskin.format, "native",
   "a skin.lua skin is badged as the native format")

imp = launcher()
eq(imp:_exportSkin("no-such-skin", "native"), nil, "exporting a ghost fails")
check(imp._skinNotice and not imp._skinNotice.ok, "with an error notice")

local first = entries[1]
imp = launcher()
local path = imp:_exportSkin(first.id, "delta")
check(path ~= nil and path:match("%.deltaskin$") ~= nil,
      "a bundled skin exports as a .deltaskin")
check(imp._skinNotice.ok, "and the tab reports where it landed")
check(tostring(imp._skinNotice.text):find(path, 1, true) ~= nil,
      "naming the path, which is the whole mobile story")
check(imp._skinExport ~= nil and imp._skinExport.path == path,
      "the export is remembered so Show file can reveal it")
path = imp:_exportSkin(first.id, "retroarch")
check(path ~= nil and path:match("%.zip$") ~= nil,
      "and as a RetroArch .zip")
path = imp:_exportSkin(first.id, "native")
check(path ~= nil and path:match("%.zip$") ~= nil, "and as a gen1recomp .zip")

window(420, 900)
imp = launcher()
imp.tab = "skins"
LauncherView.draw(imp)
LauncherView.draw(imp)
check(true, "the skins tab draws with the URL row")
imp._skinActions = { id = entries[1].id }
LauncherView.draw(imp)
check(imp._skinActions ~= nil, "the actions sheet stays up while it draws")
imp._skinFetch = { name = "neon.zip" }
LauncherView.draw(imp)
imp._skinFetch = nil

window(320, 640)
LauncherView.draw(imp)
LauncherView.draw(imp)
check(true, "and on a phone-width window, where Paste gives up its room")

local view = read("src/import/LauncherView.lua")
local rom = read("src/import/RomImporter.lua")

check(view:find('"skins-url"', 1, true) ~= nil,
      "the skins tab carries an add-by-URL field")
check(view:find('"skins-url-add"', 1, true) ~= nil, "with a button to submit it")
check(view:find('"skins-url-paste"', 1, true) ~= nil,
      "and a paste button, because a phone cannot type a URL")
check(view:find("_addSkinFromUrl", 1, true) ~= nil,
      "which reaches the importer's downloader")
check(view:find("Loader.inline", 1, true) ~= nil,
      "and the row shows progress while it runs")
check(view:find("SKIN_FORMAT_LABEL", 1, true) ~= nil,
      "rows carry a format badge")
check(view:find("buildSkinActionsModal", 1, true) ~= nil,
      "the gear opens an actions sheet")
check(view:find("_exportSkin", 1, true) ~= nil, "which can export the skin")
check(view:find("skinact-exp-delta", 1, true) ~= nil,
      "including as a Delta skin")
local modals = view:match("local function modalUp%(imp%)(.-)\nend")
check(modals and modals:find("_skinActions", 1, true) ~= nil,
      "the sheet raises the modal shield like every other popup")
check(view:find("imp.onOpenSkinStudio(imp.modScope or \"red\", id)", 1, true)
      ~= nil, "and still hands the studio a real game version")

check(rom:find("deltaskin", 1, true) ~= nil,
      "the desktop file picker offers .deltaskin")
check(rom:find("_pumpSkinFetch", 1, true) ~= nil,
      "the skin download is pumped from update()")
local update = rom:match("function RomImporter:update%(dt%)(.-)\nend\n")
check(update and update:find("_pumpSkinFetch", 1, true) ~= nil,
      "from inside update itself, not just declared")
check(TouchSkin.ARCHIVE_EXTS.deltaskin == true,
      "and the installer accepts the extension")

-- Turning skins off must leave the pad on. `enabled` is the pad's own switch,
-- and the button that calls this only exists while a skin is active, which
-- already requires the pad to be enabled.
do
  local SaveData = require("src.core.SaveData")
  local TouchControls = require("src.core.TouchControls")

  local opts = SaveData.loadOptions()
  opts.touchControls = { enabled = true, skin = "some_skin" }
  SaveData.saveOptions(opts)

  local imp = RomImporter.new(function() end, { launcher = true })
  imp:_disableSkins()

  local after = SaveData.loadOptions().touchControls
  eq(after.skin, nil, "turning skins off clears the selected skin")
  check(after.enabled ~= false, "and leaves the touch pad enabled")

  local cfg = TouchControls.normalizeConfig(after)
  check(cfg.enabled, "so the pad is on after normalizing")
  eq(cfg.skin, nil, "with no skin behind it")

  check(imp._skinNotice ~= nil and imp._skinNotice.ok == true,
    "and the notice reports success")
  check(tostring(imp._skinNotice.text):find("built-in pad", 1, true) ~= nil,
    "promising the built-in pad, which is now what happens")
end

T.finish("launcher_skins_ux")

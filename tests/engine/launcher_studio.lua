-- Cartridge Studio: responsive saves and scrollable game/save pickers.
-- luajit tests/engine/launcher_studio.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
love.graphics.setLineJoin = function() end
love.graphics.newShader = function() return {} end
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local View = require("src.import.LauncherView")
local Transition = require("src.ui.kit.Transition")
local Importer = require("src.import.RomImporter")
local width, height = 390, 844
love.graphics.getDimensions = function() return width, height end
love.graphics.getPixelDimensions = love.graphics.getDimensions
love.mouse.getPosition = function() return -100, -100 end
local now = 100
love.timer.getTime = function() return now end

local function fixture()
  local imp = Importer.new(function() end, { launcher = true, onEditSave = function() end })
  imp.tab, imp.ready.leafgreen = "leafgreen", true
  imp._ensureSlots, imp._ensureMods = function() end, function() end
  imp.slots.leafgreen = {}
  for i = 1, 24 do
    imp.slots.leafgreen[i] = { id = tostring(i), label = "Save " .. i, exists = true,
      meta = { badges = 8, timeText = "202:02", dexCount = 151 } }
  end
  imp.activeSlot.leafgreen = "1"
  imp.mods = {{ id = "test", name = "A mod with a very long name for mobile",
    version = "1.0.0", status = "ok", badge = "GAMEPLAY", targets = "RED/BLUE",
    enabledByVersion = {red = true, blue = true}, description = "A test mod." }}
  imp._selectSlot = function(self, scope, id)
    self.selected = {scope = scope, id = id}
    self.activeSlot[scope] = id
  end
  imp._toggleMod = function(self, id, _, version) self.toggled = {id = id, version = version} end
  return imp
end

local function draw(imp)
  Kit.audit = {}
  View.draw(imp)
  Transition.reset()
  View.draw(imp)
  local rects = Kit.audit
  Kit.audit = nil
  return rects
end

local function activate(imp, key)
  now = now + 1
  Kit.setFocus(key)
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  Transition.reset()
end

for _, size in ipairs({{320,640}, {360,780}, {390,844}, {768,1024}, {1024,768}}) do
  width, height = size[1], size[2]
  local imp = fixture()
  draw(imp)
  imp._pageScroll = 1e6
  imp._tabScroll.leafgreen = 1e6
  local rects = draw(imp)
  local actions = {}
  for _, r in ipairs(rects) do
    if r.label == "Export" or r.label == "Rename" or r.label == "Edit save"
        or r.label == "Delete" or r.label == "+ New save slot" then
      actions[r.label] = true
      T.check(r.x >= 0 and r.x + r.w <= width, r.label .. " fits " .. width)
      T.check(r.w >= Kit.tapMin() and r.h >= Kit.tapMin(), r.label .. " is touch-sized")
      T.check(r.y >= 0 and r.y + r.h <= height, r.label .. " is reachable at " .. width)
    end
  end
  for _, name in ipairs({"Export", "Rename", "Edit save", "Delete", "+ New save slot"}) do
    T.check(actions[name], "loaded save exposes " .. name)
  end
end

width, height = 390, 844
local imp = fixture()
draw(imp)
activate(imp, "sav-browse-leafgreen")
T.check(imp._savePicker ~= nil, "Other saves opens the picker")
draw(imp)
T.eq(View.modalKey(imp), "_savePicker", "save picker shields the launcher")
local state = imp._savePicker
T.check(state.maxScroll > 0, "long save list overflows")
local r = state.rect
local oldPage, oldTab = imp._pageScroll, imp._tabScroll.leafgreen
View.touchpressed(imp, 1, r.x + 15, r.y + 100)
View.touchmoved(imp, 1, r.x + 15, r.y + 20)
draw(imp)
View.touchreleased(imp, 1, r.x + 15, r.y + 20)
T.check(state.scroll > 0, "touch drag scrolls the save list")
T.eq(imp._pageScroll, oldPage, "modal drag leaves background page still")
T.eq(imp._tabScroll.leafgreen, oldTab, "modal drag leaves background tab still")
T.eq(imp.selected, nil, "drag does not select a save")
activate(imp, "_savePicker-row-24")
T.eq(imp.selected and imp.selected.id, "24", "keyboard can select a save below the fold")
T.eq(imp.selected and imp.selected.scope, "leafgreen", "selection stays in the game's scope")
T.eq(imp._savePicker, nil, "selection closes picker")

imp._savePicker = {scope = "leafgreen", version = "leafgreen", scroll = 0}
draw(imp)
imp:keypressed("escape")
T.eq(imp._savePicker, nil, "Escape closes picker")
imp._savePicker = {scope = "leafgreen", version = "leafgreen", scroll = 0}
draw(imp)
local played = false
imp.play = function() played = true end
imp:gamepadpressed(nil, "start")
T.eq(played, false, "Start cannot launch behind picker")
imp:gamepadpressed(nil, "b")
T.eq(imp._savePicker, nil, "controller Back closes picker")

imp.tab = "mods"
imp._pageScroll = 0
draw(imp)
activate(imp, "mod-games-test")
T.check(imp._modGames ~= nil, "mod selector opens game picker")
draw(imp)
activate(imp, "_modGames-row-2")
T.eq(imp.toggled and imp.toggled.version, "blue", "picker toggles the named game only")
T.eq(imp.toggled and imp.toggled.id, "test", "picker preserves mod identity")
imp.toggled, imp.safeMode = nil, true
draw(imp)
activate(imp, "_modGames-row-1")
T.eq(imp.toggled, nil, "safe mode blocks game toggles")
imp:keypressed("escape")
T.eq(imp._modGames, nil, "Escape closes game picker")

local function luminance(c)
  local function linear(v)
    v = v / 255
    return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055)^2.4
  end
  return 0.2126 * linear(c[1]) + 0.7152 * linear(c[2]) + 0.0722 * linear(c[3])
end
for _, kind in ipairs({"accent", "ghost", "good", "danger"}) do
  local spec = Kit.KINDS[kind]
  local fg, bg = luminance(spec.ink), luminance(spec.fill)
  local contrast = (math.max(fg, bg) + 0.05) / (math.min(fg, bg) + 0.05)
  T.check(contrast >= 4.5, kind .. " labels have at least 4.5:1 contrast")
end
T.eq(Kit.KINDS.accent.ink, Theme.PAL.heading, "blue buttons use light text")

-- Check rendered labels, not just hit boxes: fractional padding used to
-- truncate labels even when the measured control looked wide enough.
local originalEllipsize = Kit.ellipsize
local watch = {Import=true, Details=true, ["Other saves (24)"]=true,
  ["Other saves"]=true, Export=true, Rename=true, ["Edit save"]=true, Delete=true}
for _, size in ipairs({{320,640},{390,844},{1024,768}}) do
  width, height = size[1], size[2]
  Kit.ellipsize = function(font, label, maxW)
    local shown = originalEllipsize(font, label, maxW)
    if watch[label] then T.eq(shown, label, label .. " renders fully at " .. width) end
    return shown
  end
  local subject = fixture()
  draw(subject)
  subject.tab = "mods"
  draw(subject)
end
Kit.ellipsize = originalEllipsize
width, height = 390, 844
for _, version in ipairs({"red","yellow","gold","silver","crystal","firered","leafgreen"}) do
  local subject = fixture()
  subject._saveExport = {scope=version,version=version,slotId="3",label="ASH"}
  local labels = {}
  for _, rect in ipairs(draw(subject)) do labels[rect.label or ""] = true end
  T.check(labels["Original save (.lua)"], version .. " offers original export")
  T.eq(labels["Cartridge save (.sav)"] == true, true, version .. " conversion capability")
  subject.exportSave = function(self, v, format, scope, id)
    self.exported = {v,format,scope,id}
  end
  activate(subject, "export-save-lua")
  T.eq(subject.exported and subject.exported[4], "3", "exports chosen slot")
  T.eq(subject.exported and subject.exported[2], "lua", "dispatches native format")
end

local subject = fixture()
local art = {getDimensions=function() return 800,400 end}
subject._findEntry = {id="preview",title="Preview Mod",version="1.0.0"}
subject._findInstalledMap = function()return {}end
subject._findStats = function()return nil end
subject._findThumb = function()return art end
local originalDraw, artwork = love.graphics.draw
love.graphics.draw = function(img,x,y,r,sx,sy)
  if img == art then artwork={x=x,y=y,w=800*sx,h=400*sy,sx=sx,sy=sy}
  else return originalDraw(img,x,y,r,sx,sy) end
end
local rects=draw(subject)
T.check(artwork and artwork.h > 100, "mod popup displays a large image")
T.eq(artwork.sx,artwork.sy,"mod image preserves aspect ratio")
for _, rect in ipairs(rects) do
  if rect.label == "Details" or rect.label == "Close" then
    T.check(rect.y >= artwork.y + artwork.h, "actions stay below image")
    T.check(rect.y+rect.h <= height, "image leaves actions on screen")
  end
end
love.graphics.draw=originalDraw

-- Native exports preserve exact bytes and use the same portable filesystem
-- as saves, including custom-cart scope and write failures.
local SaveData = require("src.core.SaveData")
local SaveIO = require("src.import.SaveFileIO")
local Convert = require("src.save_convert.SaveConvert")
local saved = {}
for _, key in ipairs({"readSlotSource","readCartSlotSource","portableFs","portableBaseDir"}) do
  saved[key] = SaveData[key]
end
local source = "return { player = { name = 'ASH' } }\n-- original formatting\n"
local files, readScope = {}, nil
local fs = {createDirectory=function()return true end,
  write=function(path,bytes)files[path]=bytes return true end}
SaveData.portableFs=function()return fs end
SaveData.portableBaseDir=function()return "/portable" end
SaveData.readSlotSource=function(version,id)readScope={version,id};return source end
SaveData.readCartSlotSource=function(cart,id)readScope={cart,id};return source end
local ok,path=SaveIO.exportLuaSlot("leafgreen","slot3")
T.check(ok,"Gen 3 original export succeeds")
T.eq(files["exports/leafgreen/gen1recomp-leafgreen-slot3.lua"],source,"original export preserves exact source")
T.eq(path,"/portable/exports/leafgreen/gen1recomp-leafgreen-slot3.lua","export uses portable root")
ok,path=SaveIO.exportLuaSlot("red","slot2","custom")
T.check(ok,"custom cart native export succeeds")
T.eq(readScope[1],"custom","custom export reads its own scope")
T.eq(readScope[2],"slot2","custom export reads chosen slot")
fs.write=function()return false,"disk full" end
ok,path=SaveIO.exportLuaSlot("red","slot2")
T.eq(ok,false,"failed export is reported")
T.check(path:find("disk full",1,true),"export failure preserves reason")
SaveData.readSlotSource=function()return nil end
ok=SaveIO.exportLuaSlot("red","empty")
T.eq(ok,false,"empty slot cannot be exported")
for key,fn in pairs(saved)do SaveData[key]=fn end
local bytes,err=Convert.exportSav({},"firered")
T.eq(bytes,nil,"Gen 3 never falls through to Gen 1 encoder")
local Gen3Save=require("src.save_convert.Gen3Save")
T.check(err==Gen3Save.MSG.noData or err==Gen3Save.MSG.noMap,"an empty Gen 3 table is refused with a reason")

-- Settings keep a fixed footer while touch and keyboard reach long lists.
width,height=390,844
local subject=fixture()
local settingsRows,steps={},0
for i=1,40 do settingsRows[i]={label="OPTION " .. i,
  value=function()return "MEDIUM" end, step=function()steps=steps+1;return true end} end
subject._settings={opts={},sections={{title="Launcher Options",rows={settingsRows[1]}},
  {title="Game Options",rows=settingsRows}},save=function()end}
draw(subject)
local st=subject._settings
T.check(st.maxScroll>0,"settings scroll when options overflow")
local rect=st.rect
local background=subject._tabScroll.leafgreen
View.touchpressed(subject,42,rect.x+10,rect.y+120)
View.touchmoved(subject,42,rect.x+10,rect.y+30)
View.touchreleased(subject,42,rect.x+10,rect.y+30)
T.check(st.scroll>0,"touch scrolls settings")
T.eq(subject._tabScroll.leafgreen,background,"settings drag does not scroll launcher")
Kit._ringShown=true
Kit.setFocus("set-43-next")
draw(subject)
T.check(st.scroll>st.maxScroll/2,"keyboard focus reveals distant settings")
activate(subject,"set-43-next")
T.eq(steps,1,"revealed setting remains actionable")
local footer
for _,r in ipairs(draw(subject))do if r.label=="Done" then footer=r end end
T.check(footer and footer.y+footer.h<=height,"Done remains on screen at bottom of settings")
activate(subject,"settings-done")
T.eq(subject._settings,nil,"Done closes settings")

T.finish("launcher studio")

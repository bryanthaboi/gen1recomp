package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.harness')
love = require('tests.love_stub')
local SaveData = require('src.core.SaveData')
local files, writes, w, h, flags, fail = {}, 0, 960, 720, {fullscreen=false,display=1}, false
local desktopW, desktopH, osName = 1920, 1080, 'Linux'
local fs = {read=function(p)return files[p]end, write=function(p,b)files[p]=b;writes=writes+1;return true end}
SaveData.portableFs=function()return fs end
love.system.getOS=function()return osName end
love.window={getMode=function()return w,h,flags end,
  getDesktopDimensions=function()return desktopW,desktopH end,
  setMode=function(nw,nh,nf)
    if fail then return false end
    flags={};for k,v in pairs(nf)do flags[k]=v end
    w,h=nw,nh
    if flags.fullscreen then w,h=desktopW,desktopH end
    return true
  end}
local function reload()
  package.loaded['src.import.LauncherWindow']=nil
  return require('src.import.LauncherWindow')
end
local Window=reload()
Window.activate()
T.eq(Window.mode(),'windowed','defaults to windowed')
w,h=1234,876
local before=writes
Window.observe(0.1)
T.eq(writes,before,'resize writes are debounced')
Window.observe(0.4)
T.eq(writes,before+1,'resize persists after settling')
Window=reload();w,h=960,720;Window.activate()
T.eq(w,1234,'next launch restores width')
T.eq(h,876,'next launch restores height')
Window.toggle()
T.eq(flags.fullscreen,true,'fullscreen applies immediately')
Window.observe(1)
Window=reload();Window.activate()
T.eq(Window.mode(),'fullscreen','fullscreen survives restart')
Window.toggle()
T.eq(w,1234,'fullscreen keeps remembered window width')
T.eq(h,876,'fullscreen keeps remembered window height')
desktopW,desktopH=800,600
Window=reload();Window.activate()
T.check(w<=800 and h<=600,'larger saved window fits smaller display')
T.check(w<800 and h<600,'leaves room for desktop window chrome')
local previous=Window.mode()
fail=true
T.eq(Window.toggle(),false,'failed mode switch reports failure')
T.eq(Window.mode(),previous,'failed mode switch does not change preference')
fail=false
files['launcher-window.cfg']='not a valid config'
Window=reload();Window.activate()
T.eq(Window.mode(),'windowed','invalid preferences safely default')
osName='Android';before=writes
Window=reload();Window.activate();Window.observe(1);Window.toggle()
T.eq(writes,before,'fixed mobile display does not write window preferences')
T.finish('launcher window')

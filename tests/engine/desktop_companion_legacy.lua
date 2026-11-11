local replay=require("tests.companion_replay")
local fixtures=require("tests.data.desktop_companion_legacy_v040")
package.loaded["src.render.PixelFilter"]=nil
package.preload["src.render.PixelFilter"]=function() error("legacy output must not load the new filtering module") end
local Companion=require("src.render.DesktopCompanion")
local count=0
for _,case in ipairs(fixtures.cases) do
  local actual=replay(Companion,case)
  for _,key in ipairs({"x","y","sx","sy","min","mag","events"}) do
    assert(actual[key]==case[key],"upstream legacy output changed: "..case.mode.." "..key.." "..tostring(actual[key]).." != "..tostring(case[key]))
  end
  count=count+1
end
print(count.." desktop legacy frames match exact upstream draw arguments, sampling and touch events")

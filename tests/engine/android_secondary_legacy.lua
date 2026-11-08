local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local source=read("mobile/android/love/src/main/java/org/love2d/android/GameActivity.java")
local first=assert(source:find("    private static class FrameView extends View {",1,true))
local legacy=assert(source:sub(first):match("^(.*)\n}%s*$"))
assert(legacy==read("tests/data/android_secondary_frameview_v040.txt"),
  "legacy bitmap draw, rounding, sampling and touch code must remain identical to upstream v0.4.0")
local old=assert(source:find("public static boolean presentSecondaryFrame(",1,true))
local new=assert(source:find("public static boolean presentSecondaryFrameScaled(",old,true))
local entry=source:sub(old,new-1)
assert(entry:find("FrameFilter.NEAREST, false",1,true),"the original entry must select legacy output")
assert(not entry:find("presentSecondaryFrameFiltered",1,true),"the original entry must not call the filtered entry")
assert(source:find("if (explicit) p.updateFrame",1,true)
  and source:find("else p.updateFrame(rgba, width, height, scaling == FramePlacement.COVER)",1,true),
  "legacy and explicit presentation dispatch must remain separate")
assert(source:find("router.close();",1,true),"detached containers stop queued backend creation")
assert(source:find("if (secondaryFrameExplicit)",1,true),"recreated windows retain the chosen backend")
print("Android legacy view is byte-identical to upstream; old entry, replay and explicit routing isolated")

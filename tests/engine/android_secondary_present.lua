local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function check(value, message)
  if not value then error(message, 2) end
end

local java = read(
  "mobile/android/love/src/main/java/org/love2d/android/GameActivity.java")
local cpp = read("mobile/android/love/src/jni/love/src/common/android.cpp")

check(java:find("hasSecondaryDisplayCandidate", 1, true)
    and java:find("findSecondaryDisplay(self, false)", 1, true)
    and java:find("now %- secondaryDetectionAt < 500"),
  "Android exposes cached physical detection before Presentation is ready")
check(java:find("presentSecondaryFrame", 1, true)
    and java:find("secondaryFrame = new byte", 1, true)
    and java:find("rgba.get(secondaryFrame", 1, true),
  "extended presentation reuses a retained frame buffer")
check(java:find("java.nio.ByteBuffer.wrap(secondaryFrame)", 1, true),
  "a recreated Presentation receives the retained frame")
check(java:find("0xFF000000 | (color & 0x00FFFFFF)", 1, true),
  "RGB companion backgrounds become opaque Android colors")
check(java:find("placement.update(vw, vh, fw, fh, scaling)", 1, true)
    and java:find("new android.graphics.RectF()", 1, true),
  "FrameView uses one proportional placement for drawing and pointer mapping")
check(cpp:find("love_android_secondary_detected", 1, true)
    and cpp:find("love_android_present_secondary", 1, true)
    and cpp:find("love_android_secondary_target", 1, true)
    and cpp:find('"(Ljava/nio/ByteBuffer;IIIZ)Z"', 1, true),
  "JNI exports the optional detected, routing, and presentation calls")

print("android secondary presentation: ok")

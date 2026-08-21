-- iOS required imports travel through the same document-picker contract as
-- Android. Keep the Swift bridge and liblove patch aligned: a build that has
-- only one side would show the import button but fail on device.
local function read(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

local function check(value, message)
  if not value then error(message, 2) end
end

local bridge = read("mobile/ios/native/GRPickerBridge.swift")
check(bridge:find('case "required_import":', 1, true)
    and bridge:find('destName = "picked_required_import.bin"', 1, true),
  "iOS routes required imports to their own staged filename")
check(bridge:find("types.append(.data)", 1, true)
    and bridge:find("types.append(.item)", 1, true),
  "iOS required imports accept user-owned binary ROM files")
check(bridge:find('"rom,mod,sav,stadium,required_import"', 1, true),
  "iOS advertises required_import to Lua before opening the picker")

local patch = read("mobile/ios/patch_love_src.py")
check(patch:find("int w_pickFileKinds", 1, true)
    and patch:find('{ "pickFileKinds", w_pickFileKinds }', 1, true),
  "iOS liblove patch exposes the picker capability query")
check(patch:find('("GRPickerBridge.swift", ID_FILE_PICKER', 1, true),
  "iOS build patch compiles the required-import picker bridge")

local bootstrap = read("mobile/ios/native/GRBootstrap.m")
check(bootstrap:find("struct utsname", 1, true)
    and bootstrap:find("SIMULATOR_MODEL_IDENTIFIER", 1, true),
  "iOS native bridge reads the hardware model on device and simulator")
check(patch:find("int w_getDeviceModel", 1, true)
    and patch:find('{ "getDeviceModel", w_getDeviceModel }', 1, true),
  "iOS liblove patch exposes the hardware model to Lua")

print("ios_required_import_picker_test: ok")

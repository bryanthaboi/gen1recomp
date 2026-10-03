-- Platform capability detection for console, mobile and desktop builds.

local Platform = {}

local cached

local function compute()
  local osName = (love and love.system and love.system.getOS and love.system.getOS())
    or "Unknown"
  local nx = osName == "NX"
  local uwp = osName == "UWP"
  local ps4 = osName == "PS4"
  local mobile = osName == "Android" or osName == "iOS"
  local nativePicker = love and love.system
    and type(love.system.pickFile) == "function"
  local nativeHttp = love and love.system
    and type(love.system.httpDownload) == "function"
  return {
    os = osName,
    nx = nx,
    uwp = uwp,
    ps4 = ps4,
    mobile = mobile,
    console = nx or uwp or ps4,
    hasNativePicker = nativePicker,
    canSpawnProcess = osName == "OS X" or osName == "Windows" or osName == "Linux",
    romImportMode = (nx or ps4) and "save-directory"
      or (nativePicker and "native-picker")
      or "desktop",
    networkValidated = not nx and not uwp and not ps4,
    -- networkValidated is the self-updater's gate and stays a per-platform
    -- policy call: a console package cannot replace itself on disk, so that
    -- answer never depends on whether a transport exists.  Fetching a mod
    -- index or a mod zip is the narrower question, and #876 showed the two
    -- had been conflated, so Xbox lost the mod catalog for the updater's
    -- reason.  Desktop answers it with curl through HostShell; the mobile and
    -- console ports answer it with the native love.system.httpDownload bridge
    -- (#597).  The UWP LOVE backend does not export that bridge yet, so this
    -- still resolves false on Xbox and the launcher still says so, but the
    -- day the backend grows one, nothing here or in RomImporter has to change.
    canFetchRemote = (not nx and not uwp and not ps4) or nativeHttp,
    -- How a gamepad drives the launcher when it is the only input: the Switch
    -- moves a virtual cursor, Xbox and PS4 move a focus ring (the highlighted
    -- control is the selected one; Y/Triangle still toggles the cursor).  nil
    -- on desktop and handhelds, where the cursor stays latent until used.
    padNavigation = (nx and "pointer") or ((uwp or ps4) and "focus") or nil,
    -- The system owns leaving the app (iOS Home, PS button): no Quit button.
    systemQuit = osName == "iOS" or ps4,
    -- How files reach a save-directory inbox, for the hints under its path.
    inboxTransfer = (nx and "mtp") or (ps4 and "ftp") or nil,
  }
end

function Platform.detect()
  if not cached then cached = compute() end
  return cached
end

function Platform.isNX()
  return Platform.detect().nx
end

function Platform.isUWP()
  return Platform.detect().uwp
end

function Platform.isPS4()
  return Platform.detect().ps4
end

function Platform.romImportMode()
  return Platform.detect().romImportMode
end

function Platform.padNavigation()
  return Platform.detect().padNavigation
end

function Platform.systemQuit()
  return Platform.detect().systemQuit and true or false
end

function Platform.inboxTransfer()
  return Platform.detect().inboxTransfer
end

function Platform.canSpawnProcess()
  return Platform.detect().canSpawnProcess
end

function Platform.networkValidated()
  return Platform.detect().networkValidated
end

function Platform.canFetchRemote()
  return Platform.detect().canFetchRemote
end

-- Tests may swap love.system between cases.
function Platform._resetForTests()
  cached = nil
end

return Platform

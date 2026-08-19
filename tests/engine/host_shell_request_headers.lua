package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

local MARK = "\n__gen1recomp_http__"
local SAVE_DIR = "/tmp/pokeport-stub-save"
local TOKEN = "0123456789abcdef0123456789abcdef"
local BODY = '{"blob":"return {}"}'

local realOpen = io.open
local realPopen = io.popen
local realRemove = os.remove
local realHaveCurl = HostShell.haveCurl

local files, removed = {}, {}
local popenCommand

HostShell.haveCurl = function() return true end
os.remove = function(path)
  removed[path] = true
  return true
end
io.open = function(path, mode)
  local entry = { path = path, mode = mode, text = "" }
  files[#files + 1] = entry
  return {
    write = function(_, value)
      entry.text = entry.text .. value
      return true
    end,
    close = function() return true end,
  }
end
io.popen = function(command)
  popenCommand = command
  return {
    read = function() return '{"ok":true}' .. MARK .. "200" end,
    close = function() return true end,
  }
end

local body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT",
  body = BODY,
  headers = {
    ["x-sync-account"] = "aa11bb22cc33dd44",
    ["x-sync-token"] = TOKEN,
    ["Content-Type"] = "application/json",
  },
})

io.open = realOpen
io.popen = realPopen
os.remove = realRemove
HostShell.haveCurl = realHaveCurl

eq(code, 200, "the request completes: " .. tostring(err))
eq(body, '{"ok":true}', "and the response body comes back without the marker")

check(popenCommand:find(TOKEN, 1, true) == nil,
  "the device token never reaches the command line")
check(popenCommand:find("aa11bb22cc33dd44", 1, true) == nil,
  "and neither does the account id")
check(popenCommand:find(BODY, 1, true) == nil,
  "the save blob stays out of the command line too")

local headerFile, bodyFile
for _, entry in ipairs(files) do
  if entry.text:find("x-sync-token", 1, true) then headerFile = entry end
  if entry.text == BODY then bodyFile = entry end
end
check(headerFile ~= nil, "the headers are staged in a file")
check(bodyFile ~= nil, "and so is the body")
eq(headerFile.mode, "wb", "the header file is written as bytes")
check(headerFile.text:find("x%-sync%-token: " .. TOKEN) ~= nil,
  "with one header per line for curl to read")
check(headerFile.text:find("User%-Agent: ") ~= nil,
  "including the user agent curl would otherwise take on argv")
check(popenCommand:find("-H '@" .. headerFile.path .. "'", 1, true) ~= nil,
  "and curl is pointed at that file")

check(headerFile.path:find(SAVE_DIR, 1, true) == 1,
  "staging happens in the user-private save directory, not shared /tmp")
check(bodyFile.path:find(SAVE_DIR, 1, true) == 1,
  "for the body as well")
check(headerFile.path ~= bodyFile.path,
  "two concurrent requests cannot collide on one name")
eq(removed[headerFile.path], true, "the staged headers are deleted afterwards")
eq(removed[bodyFile.path], true, "and so is the staged body")

T.finish("host shell request headers")

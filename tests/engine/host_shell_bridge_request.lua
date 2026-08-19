package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

local TOKEN = "0123456789abcdef0123456789abcdef"
local BODY = '{"blob":"return {}"}'

HostShell.haveCurl = function() return false end
love.system.getOS = function() return "Android" end

local calls = {}
local reply = "STATUS 200\n" .. '{"ok":true}'

love.system.httpRequest = function(url, method, headers, body, userAgent)
  calls[#calls + 1] = { url = url, method = method, headers = headers,
                        body = body, userAgent = userAgent }
  if type(reply) == "function" then return reply() end
  return reply
end

check(HostShell.canHttpRequest(),
  "the bridge counts as a request transport where curl does not exist")

local body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT",
  body = BODY,
  headers = {
    ["x-sync-account"] = "aa11bb22cc33dd44",
    ["x-sync-token"] = TOKEN,
    ["Content-Type"] = "application/json",
  },
})

eq(code, 200, "a bridge request completes: " .. tostring(err))
eq(body, '{"ok":true}', "and the body arrives with the status line stripped")
eq(err, nil, "with no error alongside it")

eq(#calls, 1, "the bridge is called once")
local sent = calls[1]
eq(sent.url, "https://sync.example/sync/save", "the url goes through untouched")
eq(sent.method, "PUT", "and so does the method curl would have taken with -X")
eq(sent.body, BODY, "the save blob rides the body argument, not the url")
eq(sent.userAgent, "gen1recomp", "with the default user agent")

local seen = {}
for i = 1, #sent.headers, 2 do seen[sent.headers[i]] = sent.headers[i + 1] end
eq(seen["x-sync-token"], TOKEN, "auth headers arrive as flat name, value pairs")
eq(seen["x-sync-account"], "aa11bb22cc33dd44", "for the account id too")
eq(seen["Content-Type"], "application/json", "and for the content type")
eq(seen["User-Agent"], nil,
  "the user agent stays its own argument rather than a duplicate header")

calls = {}
reply = "STATUS 409\n" .. '{"error":"the save moved on"}'
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT", body = BODY, headers = { ["Accept"] = "application/json" },
})
eq(code, 409, "a conflict comes back as a status, not as a transport failure")
eq(body, '{"error":"the save moved on"}',
  "and its body survives, which is the whole point of the request arm")
eq(err, nil, "a 4xx is the caller's to interpret")

calls = {}
reply = "ERROR the reply was too large\n"
body, err, code = HostShell.httpRequest("https://sync.example/sync/state", {
  method = "GET",
})
eq(code, nil, "an ERROR envelope has no status")
eq(body, nil, "and no body")
check(err and err:find("the reply was too large", 1, true) ~= nil,
  "the bridge's own complaint reaches the caller: " .. tostring(err))
check(err and err:find("https://sync.example/sync/state", 1, true) ~= nil,
  "named with the url that failed")

calls = {}
reply = "STATUS 200\n" .. '{"ok":true}'
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT", body = BODY,
  headers = { ["x-sync-token"] = TOKEN .. "\r\nx-sync-account: stolen" },
})
eq(code, nil, "a header value carrying CRLF is refused")
eq(err, "bad request header", "with the same complaint the curl branch gives")
eq(#calls, 0, "and the bridge is never reached")

calls = {}
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PATCH", body = BODY,
})
eq(code, nil, "a method the bridge cannot express is refused")
check(err and err:find("PATCH", 1, true) ~= nil,
  "naming the method: " .. tostring(err))
eq(#calls, 0, "without calling the bridge")

calls = {}
reply = function() return nil end
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT", body = BODY,
})
eq(code, nil, "an old app under a newer engine returns nothing")
check(err and err:find("update the app", 1, true) ~= nil,
  "and degrades to an update notice rather than a crash: " .. tostring(err))

love.system.httpRequest = nil
love.system.httpDownload = function() return false end
check(not HostShell.canHttpRequest(),
  "a build with only the download bridge cannot make signed requests")
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT", body = BODY,
})
eq(code, nil, "so the request does not go out")
check(err and err:find("update the app", 1, true) ~= nil,
  "and says what to do about it: " .. tostring(err))

love.system.httpDownload = nil
body, err, code = HostShell.httpRequest("https://sync.example/sync/save", {
  method = "PUT", body = BODY,
})
eq(err, "no request transport on this platform",
  "a platform with no bridge at all keeps its old answer")

T.finish("host shell bridge request")

-- The native TLS binary is platform-built, but this Lua adapter owns library
-- discovery and the public polling API. Test that boundary without a network.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("gen1 tls adapter")

local oldLove, oldFfi = love, package.loaded.ffi
love = nil
package.loaded["src.net.Gen1Tls"] = nil
local Gen1Tls = require("src.net.Gen1Tls")
T.eq(Gen1Tls.install(), false, "install fails closed without love.system")

local existing = function() end
love = { system = { tlsOpen = existing } }
T.eq(Gen1Tls.install(), true, "existing platform TLS bridge is retained")
T.eq(love.system.tlsOpen, existing, "existing bridge is not replaced")

local calls = {}
local recvBuffer, errBuffer
local lib = {
  gen1tls_open = function(host, port)
    calls.open = { host, port }
    return 17
  end,
  gen1tls_status = function(handle) calls.status = handle return 1 end,
  gen1tls_send = function(handle, data, length)
    calls.send = { handle, data, length }
    return length
  end,
  gen1tls_receive = function(handle, buffer, maximum)
    calls.receive = { handle, maximum }
    buffer.value = "response"
    return 8
  end,
  gen1tls_error = function(handle, buffer, maximum)
    calls.error = { handle, maximum }
    buffer.value = "broken"
    return 1
  end,
  gen1tls_close = function(handle) calls.close = handle end,
}
local ffi = {
  cdef = function(definition) calls.cdef = definition end,
  load = function(name)
    calls.loads = calls.loads or {}
    calls.loads[#calls.loads + 1] = name
    if name == "libgen1tls.so" then return lib end
    error("not found")
  end,
  new = function(kind)
    local buffer = { kind = kind }
    if kind == "char[65536]" then recvBuffer = buffer else errBuffer = buffer end
    return buffer
  end,
  string = function(buffer, length)
    if length then return buffer.value:sub(1, length) end
    return buffer.value
  end,
}
package.loaded.ffi = ffi
love = {
  filesystem = { getSourceBaseDirectory = function() return "/missing" end },
  system = { getOS = function() return "Linux" end },
}
T.eq(Gen1Tls.install(), true, "Linux native library installs the polling API")
T.check(calls.cdef:find("gen1tls_open", 1, true) ~= nil,
  "native ABI is declared")
T.eq(love.system.tlsOpen("example.test", "443"), 17, "open forwards native handle")
T.eq(calls.open[1], "example.test", "open forwards host")
T.eq(calls.open[2], 443, "open normalizes port")
T.eq(love.system.tlsStatus(17), 1, "status forwards native result")
T.eq(love.system.tlsSend(17, "abc"), 3, "send forwards native byte count")
T.eq(calls.send[3], 3, "send measures payload bytes")
T.eq(love.system.tlsReceive(17, 999999), "response",
  "receive returns the native payload")
T.eq(calls.receive[2], 65536, "receive caps writes to its allocated buffer")
T.eq(recvBuffer.value, "response", "receive uses the allocated receive buffer")
T.eq(love.system.tlsReceive(17, 0), "", "non-positive receive is a safe no-op")
T.eq(love.system.tlsError(17), "broken", "native error text is exposed")
T.eq(errBuffer.value, "broken", "error uses the allocated error buffer")
love.system.tlsClose(17)
T.eq(calls.close, 17, "close forwards the handle")

package.loaded["src.net.Gen1Tls"] = nil
package.loaded.ffi = {
  cdef = function() end,
  load = function() error("no native library") end,
  new = function() error("must not allocate without a library") end,
}
love = { system = { getOS = function() return "Windows" end } }
local unavailable = require("src.net.Gen1Tls")
T.eq(unavailable.install(), false, "missing native library fails closed")
T.eq(love.system.tlsOpen, nil, "failed install exposes no partial API")

love, package.loaded.ffi = oldLove, oldFfi
package.loaded["src.net.Gen1Tls"] = nil
T.finish()

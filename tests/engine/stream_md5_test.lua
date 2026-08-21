-- Incremental MD5 vectors used by large required-import streaming.
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Plain Lua runners may expose bit32 while production LuaJIT exposes bit.
if not rawget(_G, "bit") and not rawget(_G, "bit32") then
  local ok, bit32 = pcall(require, "bit32")
  if ok then _G.bit32 = bit32 end
end

local T = require("tests.modkit")
local MD5 = require("src.mods.StreamMD5")

local vectors = {
  { "", "d41d8cd98f00b204e9800998ecf8427e" },
  { "a", "0cc175b9c0f1b6a831c399e269772661" },
  { "abc", "900150983cd24fb0d6963f7d28e17f72" },
  { "message digest", "f96b697d7cb7938d525a2f31aaf161d0" },
  { "abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b" },
}

for _, row in ipairs(vectors) do
  local ctx = MD5.new()
  for i = 1, #row[1], 3 do ctx:update(row[1]:sub(i, i + 2)) end
  T.eq(ctx:final(), row[2], "incremental MD5 vector: " .. row[1])
end

-- Cross a large number of block boundaries without building one giant string.
local million = MD5.new()
for _ = 1, 1000 do million:update(string.rep("a", 1000)) end
T.eq(million:final(), "7707d6ae4e027c70eea2a935c2296f21",
  "RFC 1321 million-a vector")

T.finish("stream_md5")

require("love.thread")
require("love.filesystem")
require("love.system")

local id, commands, channelName = ...
local out = love.thread.getChannel(channelName or "host_picker_result")

local HostShell
do
  local ok, chunk = pcall(love.filesystem.load, "src/core/HostShell.lua")
  if ok and type(chunk) == "function" then
    local ok2, mod = pcall(chunk)
    if ok2 then HostShell = mod end
  end
end

local output
if HostShell and type(commands) == "table" then
  for _, command in ipairs(commands) do
    local pipe = HostShell.popen(command)
    if pipe then
      local ok, result = pcall(pipe.read, pipe, "*a")
      HostShell.pclose(pipe)
      if ok and type(result) == "string" then
        result = result:gsub("^%s+", ""):gsub("%s+$", "")
        if result ~= "" then
          output = result
          break
        end
      end
    end
  end
end

out:push({ id = id, output = output })

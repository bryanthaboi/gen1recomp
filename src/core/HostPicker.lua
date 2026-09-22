local HostShell = require("src.core.HostShell")

local HostPicker = {}

HostPicker.RESULT = "host_picker_result"
HostPicker.WORKER = "src/core/host_picker_worker.lua"

HostPicker.WIN_OPEN_DIALOG = table.concat({
  "Add-Type -AssemblyName System.Windows.Forms;",
  "$o=New-Object System.Windows.Forms.Form;",
  "$o.TopMost=$true;",
  "$o.ShowInTaskbar=$false;",
  "$d=New-Object System.Windows.Forms.OpenFileDialog;",
})
HostPicker.WIN_SHOW = "if($d.ShowDialog($o) -eq 'OK'){"

local jobs = {}
local nextId = 0
local resCh

function HostPicker.available()
  return (love and love.thread and love.thread.newThread
    and love.thread.getChannel) and true or false
end

function HostPicker.start(commands)
  if type(commands) == "string" then commands = { commands } end
  if type(commands) ~= "table" or #commands == 0 then return nil end
  if not HostPicker.available() then return nil end
  local okCh, ch = pcall(love.thread.getChannel, HostPicker.RESULT)
  if not (okCh and ch) then return nil end
  resCh = ch
  local okTh, th = pcall(love.thread.newThread, HostPicker.WORKER)
  if not (okTh and th) then return nil end
  HostShell.releasePointerGrab()
  nextId = nextId + 1
  local id = nextId
  if not pcall(function() th:start(id, commands, HostPicker.RESULT) end) then
    return nil
  end
  jobs[id] = { thread = th }
  return id
end

local function drain()
  if not resCh then return end
  local msg = resCh:pop()
  while msg ~= nil do
    if type(msg) == "table" and msg.id and jobs[msg.id] then
      jobs[msg.id].done = true
      jobs[msg.id].output = msg.output
    end
    msg = resCh:pop()
  end
end

function HostPicker.poll(id)
  local job = jobs[id]
  if not job then return "done", nil end
  drain()
  if job.done then
    jobs[id] = nil
    return "done", job.output
  end
  local th = job.thread
  local err = th and th.getError and th:getError()
  if err then
    jobs[id] = nil
    return "done", nil, err
  end
  return "pending"
end

function HostPicker.pending()
  for _ in pairs(jobs) do return true end
  return false
end

function HostPicker._reset()
  jobs = {}
  resCh = nil
end

return HostPicker

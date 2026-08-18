local Logger = require("src.core.Logger")
local Wire = require("src.link.Wire")

local Session = {}
Session.__index = Session

local VALID_ROLES = { host = true, guest = true }
local REQUIRED_METHODS = { "update", "poll", "send", "close" }

function Session.new(transport, options)
  assert(type(transport) == "table", "Session.new requires a transport")
  assert(type(options) == "table", "Session.new requires options")
  assert(VALID_ROLES[options.role], "Session role must be host or guest")
  assert(type(options.kind) == "string" and options.kind ~= "",
    "Session kind must be a non-empty string")
  for _, method in ipairs(REQUIRED_METHODS) do
    assert(type(transport[method]) == "function",
      "Session transport requires " .. method)
  end

  local self = setmetatable({
    _transport = transport,
    _role = options.role,
    _kind = options.kind,
    _inbox = {},
    _status = "connecting",
    _terminal = nil,
    _transportCloseCalled = false,
    dropped = 0,
    paired = false,
    closed = false,
    error = nil,
    code = nil,
    address = nil,
    target = nil,
  }, Session)
  self:_syncMetadata()
  self:_refreshStatus()
  return self
end

function Session:_syncMetadata()
  local transport = self._transport
  self.paired = transport.paired == true
  self.code = transport.code
  self.address = transport.address
  self.target = transport.target
end

function Session:_refreshStatus()
  if not self._terminal then
    self._status = self.paired and "paired" or "connecting"
    self.closed = false
    self.error = nil
    return
  end
  if #self._inbox > 0 then
    self._status = "draining"
    self.closed = false
    self.error = nil
    return
  end
  self._status = self._terminal.status
  self.closed = true
  self.error = self._terminal.status == "failed"
    and (self._terminal.detail or self._terminal.reason) or nil
end

function Session:_latchTerminal(status, reason, detail)
  if self._terminal then return false end
  self._terminal = { status = status, reason = reason, detail = detail }
  self:_refreshStatus()
  return true
end

function Session:_closeTransport()
  if self._transportCloseCalled then return true end
  self._transportCloseCalled = true
  local ok, detail = pcall(self._transport.close, self._transport)
  return ok, ok and nil or tostring(detail)
end

function Session:getRole() return self._role end
function Session:getKind() return self._kind end
function Session:getStatus() return self._status end
function Session:getFailure()
  if not self._terminal or self._terminal.status ~= "failed" then
    return nil, nil
  end
  return self._terminal.reason, self._terminal.detail
end
function Session:hasPending() return #self._inbox > 0 end

function Session:send(message)
  if self._terminal then return nil end
  return self._transport:send(message)
end

function Session:update()
  if self._terminal then
    self:_refreshStatus()
    return
  end

  local failureReason, failureDetail
  local updateOk, updateDetail = pcall(self._transport.update, self._transport)
  self:_syncMetadata()
  if not updateOk then
    failureReason, failureDetail = "transport_error", tostring(updateDetail)
  elseif self._transport.error then
    failureReason = "transport_error"
    failureDetail = tostring(self._transport.error)
  end

  local pollOk, messages = pcall(self._transport.poll, self._transport)
  if not pollOk then
    if not failureReason then
      failureReason, failureDetail = "transport_error", tostring(messages)
    end
  elseif type(messages) ~= "table" then
    if not failureReason then
      failureReason, failureDetail = "transport_error",
        "transport poll returned non-table"
    end
  else
    for index = 1, #messages do
      local raw = messages[index]
      local ok, message = pcall(Wire.sanitize, raw)
      if ok and message then
        self._inbox[#self._inbox + 1] = message
      else
        self.dropped = (self.dropped or 0) + 1
        local label = type(raw) == "table" and tostring(raw.type) or type(raw)
        Logger.warn("link: dropped malformed message (%s)", label)
      end
    end
  end

  self:_syncMetadata()
  if failureReason then
    self:_latchTerminal("failed", failureReason, failureDetail)
    self:_closeTransport()
  elseif self._transport.closed then
    local closeOk, closeDetail = self:_closeTransport()
    if closeOk then
      self:_latchTerminal("closed")
    else
      self:_latchTerminal("failed", "transport_error", closeDetail)
    end
  end
  self:_refreshStatus()
end

local function finishRead(self)
  self:_refreshStatus()
end

function Session:take(messageType)
  assert(type(messageType) == "string", "Session.take requires a message type")
  for index, message in ipairs(self._inbox) do
    if message.type == messageType then
      local found = table.remove(self._inbox, index)
      finishRead(self)
      return found
    end
  end
  return nil
end

function Session:pollOne()
  if #self._inbox == 0 then return nil end
  local message = table.remove(self._inbox, 1)
  finishRead(self)
  return message
end

function Session:poll()
  local messages = self._inbox
  self._inbox = {}
  finishRead(self)
  return messages
end

function Session:close()
  if self._status == "closed" or self._status == "failed" then return end
  if self._terminal then
    self:_closeTransport()
    self:_refreshStatus()
    return
  end
  local ok, detail = self:_closeTransport()
  if ok then
    self:_latchTerminal("closed")
  else
    self:_latchTerminal("failed", "transport_error", detail)
  end
  self:_syncMetadata()
  self:_refreshStatus()
end

return Session

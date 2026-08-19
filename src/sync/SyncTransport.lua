local Transport = {}
Transport.__index = Transport

function Transport.new(fetch)
  return setmetatable({ fetch = fetch or require("src.net.Fetch") }, Transport)
end

function Transport:begin(req)
  return self.fetch.request(req.url, {
    method = req.method,
    body = req.body,
    headers = req.headers,
    maxSeconds = req.maxSeconds,
  })
end

function Transport:poll(handle)
  local st = self.fetch.poll(handle)
  if st.status == "pending" then return { status = "pending" } end
  if st.status == "cancelled" then
    return { status = "error", err = "sync request cancelled" }
  end
  if st.status ~= "ok" then
    return { status = "error", err = st.err or "sync request failed" }
  end
  return { status = "ok", body = st.body or "", code = tonumber(st.code) }
end

function Transport:release(handle)
  if handle ~= nil and self.fetch.release then self.fetch.release(handle) end
end

function Transport:cancel(handle)
  if handle ~= nil and self.fetch.cancel then self.fetch.cancel(handle) end
end

function Transport:available()
  return self.fetch.available and self.fetch.available() or false
end

return Transport

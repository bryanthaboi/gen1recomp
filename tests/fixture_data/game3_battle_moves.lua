local M = {}

M.ROWS = {
  [1] = { pp = 35, power = 40, accuracy = 100, type = 0 },
  [22] = { pp = 10, power = 35, accuracy = 100, type = 12 },
  [33] = { pp = 35, power = 35, accuracy = 95, type = 0 },
  [57] = { pp = 15, power = 95, accuracy = 100, type = 11 },
  [84] = { pp = 30, power = 40, accuracy = 100, type = 13 },
  [92] = { pp = 10, power = 0, accuracy = 85, type = 3 },
  [98] = { pp = 30, power = 40, accuracy = 100, type = 0, priority = 1 },
  [150] = { pp = 40, power = 0, accuracy = 0, type = 0 },
}

function M.source()
  local out = { "return { moves = {" }
  for id, row in pairs(M.ROWS) do
    local fields = {}
    for k, v in pairs(row) do fields[#fields + 1] = ("%s = %d"):format(k, v) end
    out[#out + 1] = ("  [%d] = { %s },"):format(id, table.concat(fields, ", "))
  end
  out[#out + 1] = "} }"
  return table.concat(out, "\n")
end

function M.install()
  if require("tests.game3_cache").mount() then return false end
  require("src.core.game3.pokemon").battleMove = function(id) return M.ROWS[tonumber(id)] end
  return true
end

return M

local input = ...
local total = 0
for _, value in ipairs(input.values or {}) do total = total + value end
return { total = total, label = input.label }

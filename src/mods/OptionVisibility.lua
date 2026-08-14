-- Declarative visibility rules for per-mod option rows.
--
-- The launcher and the in-game mod manager both render the same option
-- schema, but they read values from different owners.  Keep the condition
-- evaluator independent of either UI and let callers supply a value getter.

local OptionVisibility = {}

local function matches(condition, get, defaults)
  if condition == nil or type(condition) ~= "table" then return true end

  if type(condition.all) == "table" then
    for _, child in ipairs(condition.all) do
      if not matches(child, get, defaults) then return false end
    end
    return true
  end

  if type(condition.key) ~= "string" or condition.key == "" then
    return true
  end

  local default = condition.default
  if default == nil and defaults then default = defaults[condition.key] end
  local actual = get(condition.key, default)
  if condition.notEquals ~= nil then
    return actual ~= condition.notEquals
  end

  local expected = condition.equals
  if expected == nil then expected = condition.value end
  return actual == expected
end

function OptionVisibility.isVisible(row, get, defaults)
  if type(row) ~= "table" then return false end
  if type(get) ~= "function" then return true end
  return matches(row.visibleIf, get, defaults)
end

return OptionVisibility

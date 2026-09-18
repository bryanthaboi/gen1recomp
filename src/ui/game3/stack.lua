-- Modal UI stack for game3 (pret start-menu / submenu layering).
-- Top of stack receives input; lower layers stay open but are not drawn
-- unless drawUnder is set (rare — default hides under full-screen menus).

local Stack = {}

Stack._layers = {}

function Stack.clear()
  Stack._layers = {}
end

function Stack.depth()
  return #Stack._layers
end

function Stack.top()
  local n = #Stack._layers
  if n < 1 then return nil end
  return Stack._layers[n]
end

--- Push a layer. id is a stable string; mod is the menu module table.
-- opts.drawUnder: if true, still draw layers below this one.
function Stack.push(id, mod, opts)
  opts = opts or {}
  -- Replace existing same-id layer (re-open).
  for i = #Stack._layers, 1, -1 do
    if Stack._layers[i].id == id then
      table.remove(Stack._layers, i)
    end
  end
  Stack._layers[#Stack._layers + 1] = {
    id = id,
    mod = mod,
    drawUnder = opts.drawUnder and true or false,
    hideBelow = opts.hideBelow ~= false, -- default hide layers underneath
  }
end

function Stack.pop(id)
  if id then
    for i = #Stack._layers, 1, -1 do
      if Stack._layers[i].id == id then
        table.remove(Stack._layers, i)
        return true
      end
    end
    return false
  end
  if #Stack._layers < 1 then return false end
  table.remove(Stack._layers)
  return true
end

function Stack.has(id)
  for _, layer in ipairs(Stack._layers) do
    if layer.id == id then return true end
  end
  return false
end

--- Layers to draw bottom→top (respecting hideBelow on higher layers).
function Stack.drawOrder()
  local layers = Stack._layers
  local n = #layers
  if n < 1 then return {} end
  local first = 1
  for i = n, 1, -1 do
    if layers[i].hideBelow and i > 1 then
      first = i
      break
    end
  end
  -- If top has drawUnder, include below anyway.
  if layers[n].drawUnder then
    first = 1
  end
  local out = {}
  for i = first, n do
    out[#out + 1] = layers[i]
  end
  return out
end

function Stack.busy()
  return #Stack._layers > 0
end

return Stack

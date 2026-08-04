---@class ModuleLoader
local ModuleLoader = {}

-- Module registry to track loaded vs. stub modules
ModuleLoader._registry = {}
ModuleLoader._ErrorHandler = nil

--- Initialize ModuleLoader with dependencies
---@param deps table
function ModuleLoader.init(deps)
  ModuleLoader._ErrorHandler = deps.ErrorHandler
end

--- Create a null-object stub for a missing optional module
--- Provides safe defaults that won't cause runtime errors
---@param moduleName string
---@return table
local function createNullObject(moduleName)
  local stub = {
    _isStub = true,
    _moduleName = moduleName,
  }

  -- Common method stubs that return safe defaults
  local metatable = {
    __index = function(_, key)
      -- Common initialization method
      if key == "init" then
        return function()
          return stub
        end
      end

      -- Common constructor method
      if key == "new" then
        return function()
          return stub
        end
      end

      -- Common draw method
      if key == "draw" then
        return function() end
      end

      -- Common update method
      if key == "update" then
        return function() end
      end

      -- Common render method
      if key == "render" then
        return function() end
      end

      -- Common cleanup method
      if key == "destroy" then
        return function() end
      end

      -- Common cleanup method
      if key == "cleanup" then
        return function() end
      end

      -- Common clear method
      if key == "clear" then
        return function() end
      end

      -- Common reset method
      if key == "reset" then
        return function() end
      end

      -- Common get method
      if key == "get" then
        return function()
          return nil
        end
      end

      -- Common set method
      if key == "set" then
        return function() end
      end

      -- Common load method
      if key == "load" then
        return function()
          return stub
        end
      end

      -- Common cache-related methods
      if key == "cache" or key == "getCache" or key == "clearCache" then
        return function()
          return {}
        end
      end

      -- For any unknown method, return a no-op function that accepts any arguments
      -- This allows safe method calls on stub objects (e.g., Performance:startFrame())
      return function()
        return stub
      end
    end,

    -- Make function calls safe (in case the stub itself is called)
    __call = function()
      return stub
    end,
  }

  setmetatable(stub, metatable)
  return stub
end

--- Safely require a module with graceful fallback for optional modules
--- Returns the module if it exists, or a null-object stub if it's optional and missing
--- Throws an error if a required module is missing
---@param modulePath string Full path to the module (e.g., "modules.Performance")
---@param isOptional boolean If true, returns null-object on failure; if false, throws error
---@return table module The loaded module or a null-object stub
function ModuleLoader.safeRequire(modulePath, isOptional)
  -- Check if already loaded
  if ModuleLoader._registry[modulePath] then
    return ModuleLoader._registry[modulePath]
  end

  -- Attempt to load the module
  local success, result = pcall(require, modulePath)

  if success then
    -- Module loaded successfully
    ModuleLoader._registry[modulePath] = result
    return result
  else
    -- Module failed to load
    if isOptional then
      -- Create null-object stub for optional module
      local stub = createNullObject(modulePath)
      ModuleLoader._registry[modulePath] = stub

      -- Log warning about missing optional module
      if ModuleLoader._ErrorHandler then
        ModuleLoader._ErrorHandler:warn("ModuleLoader", "MOD_001", {
          modulePath = modulePath,
        })
      end

      return stub
    else
      -- Required module is missing - throw error
      error(string.format("Required module '%s' not found: %s", modulePath, tostring(result)))
    end
  end
end

--- Check if a module is actually loaded (not a stub)
---@param modulePath string Full path to the module
---@return boolean isLoaded True if module is loaded, false if it's a stub or not loaded
function ModuleLoader.isModuleLoaded(modulePath)
  local module = ModuleLoader._registry[modulePath]
  if not module then
    return false
  end

  -- Check if it's a stub
  return not module._isStub
end

--- Get list of all loaded modules
---@return table modules List of module paths that are actually loaded (not stubs)
function ModuleLoader.getLoadedModules()
  local loaded = {}
  for path, module in pairs(ModuleLoader._registry) do
    if not module._isStub then
      table.insert(loaded, path)
    end
  end
  return loaded
end

--- Get list of all stub modules
---@return table stubs List of module paths that are stubs
function ModuleLoader.getStubModules()
  local stubs = {}
  for path, module in pairs(ModuleLoader._registry) do
    if module._isStub then
      table.insert(stubs, path)
    end
  end
  return stubs
end

--- Clear the module registry (useful for testing)
function ModuleLoader._clearRegistry()
  ModuleLoader._registry = {}
end

return ModuleLoader

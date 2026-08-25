-- Local find/replace patches applied to a preset's raw .slang/.inc source on
-- disk, before ShaderFX.convert() hands it to the bridge -- only librashader's
-- own parser can discover a new #pragma parameter, so nothing downstream can
-- add one. Ships with an empty table on purpose; see docs/shaderfx.md.

local Logger = require("src.core.Logger")

local M = {}

-- entry.name -> { { relPath = <relative to the .slangp's own directory>,
--                  patches = { { old = <literal>, new = <literal> }, ... } } }
M.PATCHES = {}

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]*$") or "."
end

-- Plain (non-pattern) substring replace: GLSL source is full of Lua pattern
-- magic characters, so gsub on literal source text is not safe here.
local function replaceOnce(text, old, new)
  local s, e = text:find(old, 1, true)
  if not s then return text, false end
  return text:sub(1, s - 1) .. new .. text:sub(e + 1), true
end

-- Applies every registered patch for `entry` to the real files on disk. A patch
-- whose anchor is gone (already applied, or upstream changed) is skipped.
function M.apply(entry)
  local list = M.PATCHES[entry.name]
  if not list then return end
  local base = dirname(entry.fullPath)
  for _, file in ipairs(list) do
    local path = base .. "/" .. file.relPath
    local f = io.open(path, "rb")
    if not f then
      Logger.warn("ShaderSourcePatches: %s: cannot open %s", entry.name, path)
    else
      local text = f:read("*a")
      f:close()
      local changed = false
      for _, p in ipairs(file.patches) do
        local already = text:find(p.new, 1, true) ~= nil
        if not already then
          local newText, ok = replaceOnce(text, p.old, p.new)
          if ok then
            text = newText
            changed = true
          else
            Logger.warn("ShaderSourcePatches: %s: patch anchor not found in %s (upstream changed?)",
              entry.name, file.relPath)
          end
        end
      end
      if changed then
        local wf, werr = io.open(path, "wb")
        if not wf then
          Logger.warn("ShaderSourcePatches: %s: cannot write %s: %s", entry.name, path, tostring(werr))
        else
          wf:write(text)
          wf:close()
        end
      end
    end
  end
end

return M

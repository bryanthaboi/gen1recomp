-- Mechanical GLSL rewrites over librashader's emitted output: it emits a
-- standalone void main()/gl_FragData[0]/gl_Position shape, LOVE requires the
-- effect()/position() convention. Not a GLSL parser -- every rule here exists
-- because a real preset failed without it. See docs/shaderfx.md.
local Fixup = {}

local function stripVersion(src)
  return (src:gsub("#version%s+%d+%s*\n", ""))
end

-- ES 1.00 has no array-constructor syntax at all; SPIRV-Cross emits it anyway.
-- Splitting needs paren-depth awareness, since an element can be vec2(a, b).
local function splitTopLevelCommas(s)
  local parts, depth, start = {}, 0, 1
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "(" then
      depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
    elseif c == "," and depth == 0 then
      parts[#parts + 1] = s:sub(start, i - 1)
      start = i + 1
    end
  end
  parts[#parts + 1] = s:sub(start)
  return parts
end

local function elementAssignLines(name, elemsStr)
  local lines = {}
  for i, elem in ipairs(splitTopLevelCommas(elemsStr)) do
    lines[#lines + 1] = ("%s[%d] = %s;"):format(name, i - 1, elem:match("^%s*(.-)%s*$"))
  end
  return lines
end

local function rewriteArrayLiterals(src)
  local injections = {}
  -- const, global scope: relocate the per-element assignments into main().
  src = src:gsub(
    "const%s+([%w_]+)%s+([%w_]+)%s*%[%s*(%d+)%s*%]%s*=%s*[%w_]+%s*%[%s*%]%s*(%b())%s*;",
    function(typ, name, size, parenElems)
      for _, line in ipairs(elementAssignLines(name, parenElems:sub(2, -2))) do
        injections[#injections + 1] = "    " .. line
      end
      return ("%s %s[%s];"):format(typ, name, size)
    end)
  if #injections > 0 then
    src = src:gsub("(void%s+main%s*%(%s*%)%s*{)",
      "%1\n" .. table.concat(injections, "\n"), 1)
  end
  -- non-const, local declaration+initializer: rewrite in place.
  src = src:gsub(
    "([%w_]+)%s+([%w_]+)%s*%[%s*(%d+)%s*%]%s*=%s*[%w_]+%s*%[%s*%]%s*(%b())%s*;",
    function(typ, name, size, parenElems)
      local lines = elementAssignLines(name, parenElems:sub(2, -2))
      return ("%s %s[%s];\n    "):format(typ, name, size) .. table.concat(lines, "\n    ")
    end)
  -- bare reassignment of an already-declared array: rewrite in place.
  src = src:gsub(
    "([%w_]+)%s*=%s*[%w_]+%s*%[%s*%]%s*(%b())%s*;",
    function(name, parenElems)
      return table.concat(elementAssignLines(name, parenElems:sub(2, -2)), "\n    ")
    end)
  -- array-to-array copy (`float param_1[7] = coeffs;`): ES 1.00 has no
  -- whole-array assignment either, so copy element by element.
  src = src:gsub(
    "([%w_]+)%s+([%w_]+)%s*%[%s*(%d+)%s*%]%s*=%s*([%w_]+)%s*;",
    function(typ, name, size, srcName)
      local lines = {}
      for i = 0, tonumber(size) - 1 do
        lines[#lines + 1] = ("%s[%d] = %s[%d];"):format(name, i, srcName, i)
      end
      return ("%s %s[%s];\n    "):format(typ, name, size) .. table.concat(lines, "\n    ")
    end)
  return src
end
Fixup.rewriteArrayLiterals = rewriteArrayLiterals

-- ES 1.00 has no `%` operator. `%` is only ever defined for integer operands,
-- so float mod() is exact here; balanced-paren operand shapes are tried first.
local function rewriteIntegerModulo(src)
  local function convert(l, r)
    return ("int(mod(float(%s), float(%s)))"):format(l, r)
  end
  src = src:gsub("(%b())%s*%%%s*(%b())", convert)
  src = src:gsub("(%b())%s*%%%s*([%w_]+)", convert)
  src = src:gsub("([%w_]+)%s*%%%s*(%b())", convert)
  src = src:gsub("([%w_]+)%s*%%%s*([%w_]+)", convert)
  return src
end
Fixup.rewriteIntegerModulo = rewriteIntegerModulo

-- SPIRV-Cross hardcodes an unguarded `precision highp` pair with no toggle;
-- claim highp only where the driver actually offers fragment highp.
local function guardPrecision(src)
  src = src:gsub("precision%s+highp%s+float%s*;%s*\nprecision%s+highp%s+int%s*;%s*\n", "")
  local guard = [[
#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
precision highp int;
#endif
#endif
]]
  return guard .. src
end

-- LOVE's Shader:send cannot address a member of a struct-typed uniform, so the
-- struct is deleted and its members re-declared: scalars packed 4-at-a-time
-- into vec4 slots (ES 1.00 guarantees only 16 fragment uniform vectors),
-- vectors kept whole. `specialMembers` substitutes a member to fixed text
-- instead of declaring it at all (see UBO_SPECIAL_MEMBERS).
local SCALAR_TYPES = { float = true, int = true, bool = true }
local COMPONENTS = { "x", "y", "z", "w" }

local function flattenStruct(src, structName, packedPrefix, specialMembers)
  packedPrefix = packedPrefix or "LIBRA_PACKED_"
  specialMembers = specialMembers or {}
  local body = src:match("struct%s+" .. structName .. "%s*{(.-)}%s*;")
  if not body then return src, {} end
  local instance = src:match("uniform%s+" .. structName .. "%s+([%w_]+)%s*;")
  assert(instance, "flattenStruct: found struct " .. structName .. " but no instance uniform")

  src = src:gsub("struct%s+" .. structName .. "%s*{.-}%s*;%s*\n", "")
  src = src:gsub("uniform%s+" .. structName .. "%s+" .. instance .. "%s*;%s*\n", "")

  local members = {}
  for typ, name in body:gmatch("([%w_]+)%s+([%w_]+)%s*;") do
    members[#members + 1] = { type = typ, name = name }
  end
  -- Declaration order matters here: packing scalars 4-at-a-time only minimizes
  -- group count against the struct's own vec4-then-scalars layout.

  local decls, manifest, specialSubs = {}, {}, {}
  local scalarGroup, packIndex = {}, 0

  local function flushGroup()
    if #scalarGroup == 0 then return end
    local uniformName = packedPrefix .. packIndex
    decls[#decls + 1] = ("uniform vec4 %s;"):format(uniformName)
    for i, m in ipairs(scalarGroup) do
      manifest[#manifest + 1] = { name = m.name, uniform = uniformName, component = COMPONENTS[i], type = m.type }
    end
    packIndex, scalarGroup = packIndex + 1, {}
  end

  for _, m in ipairs(members) do
    if specialMembers[m.name] then
      specialSubs[#specialSubs + 1] = { name = m.name, replacement = specialMembers[m.name] }
    elseif SCALAR_TYPES[m.type] then
      scalarGroup[#scalarGroup + 1] = m
      if #scalarGroup == 4 then flushGroup() end
    else
      flushGroup()
      decls[#decls + 1] = ("uniform %s %s;"):format(m.type, m.name)
      manifest[#manifest + 1] = { name = m.name, uniform = m.name }
    end
  end
  flushGroup()

  -- longest-name-first so a substitution can't land inside a longer member name
  -- sharing a prefix; a separate order from the packing above. A packed slot
  -- only stores floats, so an int/bool member needs a cast back on every read.
  local subs = {}
  for _, entry in ipairs(manifest) do
    local replacement = entry.component and (entry.uniform .. "." .. entry.component) or entry.uniform
    if entry.component and (entry.type == "int" or entry.type == "bool") then
      replacement = ("%s(%s)"):format(entry.type, replacement)
    end
    subs[#subs + 1] = { name = entry.name, replacement = replacement }
  end
  for _, entry in ipairs(specialSubs) do subs[#subs + 1] = entry end
  table.sort(subs, function(a, b) return #a.name > #b.name end)
  for _, entry in ipairs(subs) do
    src = src:gsub(instance .. "%." .. entry.name, entry.replacement)
  end

  return table.concat(decls, "\n") .. "\n" .. src, manifest
end
Fixup.flattenStruct = flattenStruct

-- Turns a flat {member = value} table into the {uniform = value_or_vec4} shape
-- the packed shader expects. A missing value packs as 0 in its component.
function Fixup.packValues(manifest, values)
  local packed = {}
  local slot = { x = 1, y = 2, z = 3, w = 4 }
  for _, entry in ipairs(manifest) do
    if entry.component then
      packed[entry.uniform] = packed[entry.uniform] or { 0, 0, 0, 0 }
      packed[entry.uniform][slot[entry.component]] = values[entry.name] or 0
    else
      packed[entry.uniform] = values[entry.name]
    end
  end
  return packed
end

-- GLSL ES 1.00 guarantees only 16 fragment uniform *vectors* and every scalar
-- costs a whole one; samplers do not come out of that budget.
Fixup.SLOTS = { float = 1, int = 1, bool = 1, vec2 = 1, vec3 = 1, vec4 = 1, mat3 = 3, mat4 = 4 }

function Fixup.countUniformSlots(src)
  -- Lua's %w does NOT match underscore, unlike regex \w, and every name here is
  -- full of them, so this must be [%w_]+ or whole declarations go uncounted.
  local total = 0
  for typ in src:gmatch("uniform%s+([%w_]+)%s+[%w_]+%s*;") do
    if typ ~= "sampler2D" and typ ~= "Image" then
      total = total + (Fixup.SLOTS[typ] or 1)
    end
  end
  return total
end

-- LIBRA_UBO_* (the uniform-buffer block) has the same
-- LOVE-can't-address-a-struct-member problem as LIBRA_PUSH_*, so it is
-- flattened the same way, with MVP alone special-cased. Deleting the block
-- outright instead left every other member reference dangling.

-- LOVE forward-declares effect()'s prototype under its own header's precision
-- default, which can mismatch guardPrecision's; pin the parameter list to a
-- #define so the caller can try each variant in order.
Fixup.PREC_HEADS = { "#define EFFECT_PREC mediump\n", "#define EFFECT_PREC\n" }

-- MVP is meaningless in the fragment stage but gets declared anyway; special-
-- casing it keeps a dead field from becoming a uniform nothing would send.
local UBO_SPECIAL_MEMBERS = { MVP = "transform_projection" }

function Fixup.fragment(src)
  src = stripVersion(src)
  src = rewriteArrayLiterals(src)
  src = rewriteIntegerModulo(src)
  local pushManifest, uboManifest
  src, pushManifest = flattenStruct(src, "LIBRA_PUSH_FRAGMENT")
  src, uboManifest = flattenStruct(src, "LIBRA_UBO_FRAGMENT", "LIBRA_UBO_PACKED_", UBO_SPECIAL_MEMBERS)
  local manifest = pushManifest
  for _, entry in ipairs(uboManifest) do manifest[#manifest + 1] = entry end
  src = guardPrecision(src)
  src = src:gsub("void%s+main%s*%(%s*%)",
    "vec4 effect(EFFECT_PREC vec4 love_UnusedColor, Image love_UnusedTex, "
    .. "EFFECT_PREC vec2 love_UnusedTc, EFFECT_PREC vec2 love_UnusedSc)")
  -- gl_FragData isn't available in LOVE's effect() convention. Rewrite EVERY
  -- occurrence, whatever operator follows: real presets (ds-hybrid-sabr) write
  -- it once with `=` and later accumulate with `+=`.
  src = src:gsub("gl_FragData%[0%]", "gbFragColor")
  src = src:gsub(
    "(vec4 effect%(EFFECT_PREC vec4 love_UnusedColor, Image love_UnusedTex, "
    .. "EFFECT_PREC vec2 love_UnusedTc, EFFECT_PREC vec2 love_UnusedSc%)%s*\n{)",
    "%1\n    vec4 gbFragColor;")
  -- a bare early-exit `return;` needs a value now -- gbFragColor already
  -- holds whatever was assigned just before it on every real shape seen.
  src = src:gsub("return%s*;", "return gbFragColor;")
  local lastBrace = src:match("()}%s*$")
  assert(lastBrace, "fragment fixup: could not find effect()'s closing brace")
  src = src:sub(1, lastBrace - 1) .. "    return gbFragColor;\n" .. src:sub(lastBrace)
  return src, manifest
end

function Fixup.vertex(src)
  src = stripVersion(src)
  src = rewriteArrayLiterals(src)
  src = rewriteIntegerModulo(src)
  local pushManifest, uboManifest
  src, pushManifest = flattenStruct(src, "LIBRA_PUSH_VERTEX")
  -- MVP means "multiply the incoming vertex by it", which on an ordinary
  -- full-screen LOVE draw is transform_projection, so it substitutes rather
  -- than being packed. A distinct prefix keeps the UBO's packed groups off
  -- LIBRA_PUSH_*'s own numbering.
  src, uboManifest = flattenStruct(src, "LIBRA_UBO_VERTEX", "LIBRA_UBO_PACKED_", UBO_SPECIAL_MEMBERS)
  local manifest = pushManifest
  for _, entry in ipairs(uboManifest) do manifest[#manifest + 1] = entry end
  -- LOVE supplies VertexPosition/VertexTexCoord itself.
  src = src:gsub("attribute%s+vec4%s+Position%s*;%s*\n", "")
  src = src:gsub("attribute%s+vec2%s+TexCoord%s*;%s*\n", "")
  src = src:gsub("void%s+main%s*%(%s*%)",
    "vec4 position(mat4 transform_projection, vec4 vertex_position)")
  -- gl_Position isn't available in LOVE's position() convention; carry it in a
  -- local named to share no substring with "Position".
  src = src:gsub("gl_Position%s*=%s*([^;]+);", "gbClipPos = %1;")
  -- Whole-identifier frontier match, not a blind gsub: a preset's own local
  -- `vec2 vTexCoord;` would otherwise be mangled (dot.slangp pass0).
  src = src:gsub("%f[%w]Position%f[%W]", "vertex_position")
  src = src:gsub("%f[%w]TexCoord%f[%W]", "VertexTexCoord%.xy")
  src = src:gsub(
    "(vec4 position%(mat4 transform_projection, vec4 vertex_position%)%s*\n{)",
    "%1\n    vec4 gbClipPos;")
  -- append the return just before the function's final closing brace
  local lastBrace = src:match("()}%s*$")
  assert(lastBrace, "vertex fixup: could not find main()'s closing brace")
  src = src:sub(1, lastBrace - 1) .. "    return gbClipPos;\n" .. src:sub(lastBrace)
  return src, manifest
end

return Fixup

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end,
  error = function() end,
  warn = function() end,
}

local ShaderFX = require("src.render.ShaderFX")

local ROOT = "/tmp/pokeport-shaderfx-lut-paths"
local DESK = ROOT .. "/desktop/shaders/handheld"
local NX = ROOT .. "/switch/shaders/handheld"
os.execute("mkdir -p " .. DESK .. " " .. NX)

local pwd = io.popen("cd " .. ROOT .. " && pwd -P")
local CANON = pwd and pwd:read("*l") or ROOT
if pwd then pwd:close() end

local deskEntry = { name = "lut.slangp", fullPath = DESK .. "/lut.slangp" }
local realTranslate = ShaderFX.translate
ShaderFX.translate = function()
  return {
    pass_count = 0, passes = {}, parameter_overrides = {},
    textures = {
      { name = "Inside", path = CANON .. "/desktop/shaders/handheld/shaders/resources/palette.png",
        wrap_mode = "clamp_to_edge", filter_mode = "linear", mipmap = false },
      { name = "Sibling", path = CANON .. "/desktop/shaders/border/frame.png",
        wrap_mode = "clamp_to_edge", filter_mode = "linear", mipmap = false },
      { name = "Dotted", path = CANON .. "/desktop/shaders/handheld/shaders/../shaders/resources/./mask.png",
        wrap_mode = "clamp_to_edge", filter_mode = "linear", mipmap = false },
    },
  }
end

local ok, err = ShaderFX.convert(deskEntry, false)
eq(ok, true, "the stubbed convert writes an artifact (" .. tostring(err) .. ")")
ShaderFX.translate = realTranslate

local f = io.open(ShaderFX.artifactPath(deskEntry), "rb")
local artifact = f and f:read("*a") or ""
if f then f:close() end
check(artifact:find("palette.png", 1, true) ~= nil, "the artifact lists the LUTs")
check(artifact:find(ROOT, 1, true) == nil and artifact:find(CANON, 1, true) == nil,
  "the written artifact carries no absolute path of the machine that converted it")

local copied = io.open(NX .. "/lut.lua", "wb")
copied:write(artifact)
copied:close()

local nxEntry = { name = "lut.slangp", fullPath = NX .. "/lut.slangp" }
local state, loadErr = ShaderFX.load(nxEntry)
check(state ~= nil, "the copied artifact loads (" .. tostring(loadErr) .. ")")
local tex = state and state.preset.textures or {}
eq(tex[1] and tex[1].path, NX .. "/shaders/resources/palette.png",
  "a LUT under the preset folder resolves beside the copied preset")
eq(tex[2] and tex[2].path, NX .. "/../border/frame.png",
  "a LUT in a sibling folder resolves relative to the copied preset")
eq(tex[3] and tex[3].path, NX .. "/shaders/resources/mask.png",
  "dot segments are folded before the path is stored")

local legacy = io.open(NX .. "/lut.lua", "wb")
legacy:write('return {pass_count=0,passes={},parameter_overrides={},textures={{name="Old",path="'
  .. DESK .. '/old.png",wrap_mode="clamp_to_edge",filter_mode="linear",mipmap=false}}}\n')
legacy:close()
state = ShaderFX.load(nxEntry)
eq(state and state.preset.textures[1].path, DESK .. "/old.png",
  "an older artifact's absolute LUT path is left as written")

os.remove(NX .. "/lut.lua")
os.remove(DESK .. "/lut.lua")

T.finish("shaderfx LUT paths relative to the preset")

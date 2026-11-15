#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local LayoutNative = require("src.core.game3.layout_native")

local cells = { { mid = 1, coll = 0, elev = 3 }, { mid = 2, coll = 0, elev = 3 } }
local bare = LayoutNative.fromDecoded({ width = 2, height = 1, cells = cells }, "T_NO_BORDER", "p")
check(bare:midAt(1, 0) == 2, "an in-bounds cell still reads without a border")
local ok, err = pcall(bare.midAt, bare, -1, 0)
check(not ok and tostring(err):find("has no border metatile", 1, true) ~= nil,
  "a layout with no border metatiles raises at a border cell: " .. tostring(err))
ok, err = pcall(bare.cellAt, bare, 2, 0)
check(not ok and tostring(err):find("has no border metatile", 1, true) ~= nil,
  "cellAt raises at a border cell of a layout with no border: " .. tostring(err))

local bordered = LayoutNative.fromDecoded({ width = 2, height = 1, cells = cells,
  borderWidth = 2, borderHeight = 2, borderMids = { 5, 6, 7, 8 } }, "T_BORDER", "p")
local okB, mid = pcall(bordered.midAt, bordered, -1, 0)
check(okB and type(mid) == "number" and mid >= 5 and mid <= 8, "a layout with a border reads its border metatiles")

T.finish("game3 layout border strict")

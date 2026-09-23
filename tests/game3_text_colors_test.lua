-- Test suite for GBA 1:1 text colors, stdpal_0 palette, 3-slot colors, and control codes.

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "assert_eq failed", tostring(b), tostring(a)))
  end
end

local function assert_near(a, b, eps, msg)
  eps = eps or 0.001
  if math.abs(a - b) > eps then
    error(string.format("%s: expected %s, got %s (diff %s)", msg or "assert_near failed", tostring(b), tostring(a), tostring(math.abs(a - b))))
  end
end

print("=== [TEST 1] STDPAL Palette & COLOR_IDS 1:1 Verification ===")
local FrlgFont = require("src.ui.game3.frlg_font")

assert_eq(FrlgFont.COLOR_IDS.TRANSPARENT, 0, "COLOR_IDS.TRANSPARENT is 0")
assert_eq(FrlgFont.COLOR_IDS.WHITE, 1, "COLOR_IDS.WHITE is 1")
assert_eq(FrlgFont.COLOR_IDS.DARK_GRAY, 2, "COLOR_IDS.DARK_GRAY is 2")
assert_eq(FrlgFont.COLOR_IDS.LIGHT_GRAY, 3, "COLOR_IDS.LIGHT_GRAY is 3")
assert_eq(FrlgFont.COLOR_IDS.RED, 4, "COLOR_IDS.RED is 4")
assert_eq(FrlgFont.COLOR_IDS.LIGHT_RED, 5, "COLOR_IDS.LIGHT_RED is 5")
assert_eq(FrlgFont.COLOR_IDS.GREEN, 6, "COLOR_IDS.GREEN is 6")
assert_eq(FrlgFont.COLOR_IDS.LIGHT_GREEN, 7, "COLOR_IDS.LIGHT_GREEN is 7")
assert_eq(FrlgFont.COLOR_IDS.BLUE, 8, "COLOR_IDS.BLUE is 8")
assert_eq(FrlgFont.COLOR_IDS.LIGHT_BLUE, 9, "COLOR_IDS.LIGHT_BLUE is 9")

-- Check exact normalized RGB values matching stdpal_0.pal
assert_eq(FrlgFont.STDPAL[0][4], 0, "STDPAL[0] alpha is 0 (Transparent)")
assert_near(FrlgFont.STDPAL[1][1], 1.0, 0.001, "STDPAL[1] White red")
assert_near(FrlgFont.STDPAL[2][1], 98 / 255, 0.001, "STDPAL[2] Dark Gray red (98/255)")
assert_near(FrlgFont.STDPAL[3][1], 213 / 255, 0.001, "STDPAL[3] Light Gray red (213/255)")
assert_near(FrlgFont.STDPAL[4][1], 230 / 255, 0.001, "STDPAL[4] Red red (230/255)")
assert_near(FrlgFont.STDPAL[5][1], 255 / 255, 0.001, "STDPAL[5] Light Red red (255/255)")
assert_near(FrlgFont.STDPAL[6][1], 32 / 255, 0.001, "STDPAL[6] Green red (32/255)")
assert_near(FrlgFont.STDPAL[7][1], 148 / 255, 0.001, "STDPAL[7] Light Green red (148/255)")
assert_near(FrlgFont.STDPAL[8][1], 49 / 255, 0.001, "STDPAL[8] Blue red (49/255)")
assert_near(FrlgFont.STDPAL[9][1], 164 / 255, 0.001, "STDPAL[9] Light Blue red (164/255)")
print("[ok] STDPAL 1:1 verified")

print("=== [TEST 2] 3-Slot Color Architecture (fg, shadow, bg) ===")
assert_eq(FrlgFont.COLOR.NORMAL.fg, FrlgFont.STDPAL[2], "NORMAL fg is DARK_GRAY")
assert_eq(FrlgFont.COLOR.NORMAL.shadow, FrlgFont.STDPAL[3], "NORMAL shadow is LIGHT_GRAY")
assert_eq(FrlgFont.COLOR.NORMAL.bg, FrlgFont.STDPAL[0], "NORMAL bg is TRANSPARENT")

-- Two-tone Pokémon gender symbols: Light fg + Dark shadow
assert_eq(FrlgFont.COLOR.MALE.fg, FrlgFont.STDPAL[9], "MALE fg is LIGHT_BLUE")
assert_eq(FrlgFont.COLOR.MALE.shadow, FrlgFont.STDPAL[8], "MALE shadow is BLUE")
assert_eq(FrlgFont.COLOR.MALE.bg, FrlgFont.STDPAL[0], "MALE bg is TRANSPARENT")

assert_eq(FrlgFont.COLOR.FEMALE.fg, FrlgFont.STDPAL[5], "FEMALE fg is LIGHT_RED")
assert_eq(FrlgFont.COLOR.FEMALE.shadow, FrlgFont.STDPAL[4], "FEMALE shadow is RED")
assert_eq(FrlgFont.COLOR.FEMALE.bg, FrlgFont.STDPAL[0], "FEMALE bg is TRANSPARENT")

-- NPC Dialogue colors: Dark fg + Light Gray shadow
assert_eq(FrlgFont.COLOR.MALE_NPC.fg, FrlgFont.STDPAL[8], "MALE_NPC fg is BLUE")
assert_eq(FrlgFont.COLOR.MALE_NPC.shadow, FrlgFont.STDPAL[3], "MALE_NPC shadow is LIGHT_GRAY")

assert_eq(FrlgFont.COLOR.FEMALE_NPC.fg, FrlgFont.STDPAL[4], "FEMALE_NPC fg is RED")
assert_eq(FrlgFont.COLOR.FEMALE_NPC.shadow, FrlgFont.STDPAL[3], "FEMALE_NPC shadow is LIGHT_GRAY")

assert_eq(FrlgFont.COLOR.WHITE.fg, FrlgFont.STDPAL[1], "WHITE fg is WHITE")
assert_eq(FrlgFont.COLOR.WHITE.shadow, FrlgFont.STDPAL[2], "WHITE shadow is DARK_GRAY")
print("[ok] 3-slot architecture verified")

print("=== [TEST 3] sTextColorTable & NPC Text Color Lookups ===")
-- Female NPCs: Nurse (64), Cable Club Receptionist (65), Daisy (76), Mom (88), Lass (22), Beauty (29)
assert_eq(FrlgFont.getNpcTextColor(64), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Nurse Joy is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(65), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Cable Club Receptionist is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(76), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Daisy is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(88), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Mom is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(22), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Lass is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(29), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Beauty is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(81), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Misty is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(83), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Erika is FEMALE")
assert_eq(FrlgFont.getNpcTextColor(85), FrlgFont.NPC_TEXT_COLOR.FEMALE, "Sabrina is FEMALE")

-- Male NPCs: Prof Oak (71), Blue (72), Bill (73), Clerk (68), Youngster (18), Brock (80), Giovanni (87)
assert_eq(FrlgFont.getNpcTextColor(71), FrlgFont.NPC_TEXT_COLOR.MALE, "Prof Oak is MALE")
assert_eq(FrlgFont.getNpcTextColor(72), FrlgFont.NPC_TEXT_COLOR.MALE, "Blue is MALE")
assert_eq(FrlgFont.getNpcTextColor(73), FrlgFont.NPC_TEXT_COLOR.MALE, "Bill is MALE")
assert_eq(FrlgFont.getNpcTextColor(68), FrlgFont.NPC_TEXT_COLOR.MALE, "Clerk is MALE")
assert_eq(FrlgFont.getNpcTextColor(18), FrlgFont.NPC_TEXT_COLOR.MALE, "Youngster is MALE")
assert_eq(FrlgFont.getNpcTextColor(80), FrlgFont.NPC_TEXT_COLOR.MALE, "Brock is MALE")
assert_eq(FrlgFont.getNpcTextColor(87), FrlgFont.NPC_TEXT_COLOR.MALE, "Giovanni is MALE")

-- Neutral Objects: Item Ball (92), Sign (103), Rock Smash Rock (96), Cut Tree (95)
assert_eq(FrlgFont.getNpcTextColor(92), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "Item ball is NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(103), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "Sign is NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(96), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "Rock is NEUTRAL")

-- Pokémon Sprites: Pikachu (120), Snorlax (109), Clefairy (113)
assert_eq(FrlgFont.getNpcTextColor(120), FrlgFont.NPC_TEXT_COLOR.MON, "Pikachu is MON")
assert_eq(FrlgFont.getNpcTextColor(109), FrlgFont.NPC_TEXT_COLOR.MON, "Snorlax is MON")

-- Fallbacks (nil, negative, out of range)
assert_eq(FrlgFont.getNpcTextColor(nil), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "nil defaults to NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(-1), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "-1 defaults to NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(999), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "out of range defaults to NEUTRAL")

-- colorForNpc helper
local nurseColor = FrlgFont.colorForNpc(64)
assert_eq(nurseColor.fg, FrlgFont.STDPAL[4], "Nurse color fg is RED")
local oakColor = FrlgFont.colorForNpc(71)
assert_eq(oakColor.fg, FrlgFont.STDPAL[8], "Oak color fg is BLUE")
local signColor = FrlgFont.colorForNpc(103)
assert_eq(signColor.fg, FrlgFont.STDPAL[2], "Sign color fg is DARK_GRAY")
print("[ok] sTextColorTable lookups verified")

print("=== [TEST 4] Bytecode & Macro Token Scanning (Null Bytes & Variable Length) ===")
-- Scan string with embedded {FONT_FEMALE} and {COLOR BLUE}
local testStr = "{FONT_FEMALE}Hello {COLOR BLUE}World!"
local tokens = {}
for ttype, val, colors in FrlgFont.scanTokens(testStr, FrlgFont.COLOR.NORMAL) do
  tokens[#tokens + 1] = { ttype = ttype, val = val, fg = colors.fg }
end

assert_eq(tokens[1].ttype, "ctrl", "first token is ctrl FONT_FEMALE")
assert_eq(tokens[1].fg, FrlgFont.STDPAL[4], "colors became FEMALE (red)")
assert_eq(tokens[2].ttype, "char", "second token is 'H'")
assert_eq(tokens[2].val, "H", "char value is 'H'")

-- Check character count ignoring control tags
local charCount = FrlgFont.countChars(testStr)
assert_eq(charCount, 12, "countChars counts only 'Hello World!' (12 chars)")

-- Test raw 0xFC bytecodes with null byte \x00
-- FONT_MALE: \xFC \x04 \x08 \x00 \x03
local rawStr = "\xFC\x04\x08\x00\x03Test\xFC\x01\x04Red"
local rawTokens = {}
for ttype, val, colors in FrlgFont.scanTokens(rawStr, FrlgFont.COLOR.NORMAL) do
  rawTokens[#rawTokens + 1] = { ttype = ttype, val = val, fg = colors.fg, bg = colors.bg, shadow = colors.shadow }
end

assert_eq(rawTokens[1].ttype, "ctrl", "raw token 1 is ctrl")
assert_eq(rawTokens[1].fg, FrlgFont.STDPAL[8], "raw fg set to Blue (8)")
assert_eq(rawTokens[1].bg, FrlgFont.STDPAL[0], "raw bg set to Transparent (0)")
assert_eq(rawTokens[1].shadow, FrlgFont.STDPAL[3], "raw shadow set to Light Gray (3)")
assert_eq(rawTokens[2].val, "T", "first letter after raw control code is 'T'")

assert_eq(FrlgFont.countChars(rawStr), 7, "rawStr char count is 7 ('TestRed')")
print("[ok] Token scanner handles null bytes and variable length bytecode cleanly")

print("=== [TEST 5] TextIR Tag Expansion & Word Wrapping ===")
local TextIR = require("src.core.game3.scripting.text_ir")
local ir = TextIR.fromAscii("{FONT_FEMALE}Nurse Joy: Welcome to\\nthe POKéMON CENTER!\\pWe restore your POKéMON.")
local textBoxStr = TextIR.toTextBox(ir, { maxWidth = 208 })

-- Must contain two pages split by \f
assert(textBoxStr:find("\f"), "toTextBox created multi-page text with \\f")
assert(textBoxStr:find("{FONT_FEMALE}"), "toTextBox preserved {FONT_FEMALE} tag")
print("[ok] TextIR tag preservation and box formatting verified")

print("=== [TEST 6] Message.show Ambient Color Resolution ===")
local Message = require("src.ui.game3.message")

-- Nurse Joy dialogue
Message.show("Welcome to the Pokémon Center!", { gfxId = 64 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[4], "Message with Nurse Joy gfxId gets RED text")

-- Prof Oak dialogue
Message.show("Hello there! Welcome to the world of POKéMON!", { gfxId = 71 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[8], "Message with Oak gfxId gets BLUE text")

-- Sign dialogue
Message.show("TRAINER TIPS", { gfxId = 103 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[2], "Message with Sign gets DARK_GRAY text")

-- Battle message
Message.show("A wild PIDGEY appeared!", { frame = "battle" })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[1], "Battle message gets WHITE text")

Message.close()
print("[ok] Message.show color resolution verified")

print("=== [TEST 7] NPC_TEXT_COLOR enum + full sTextColorTable (pret numbering) ===")
-- include/constants/vars.h:340
assert_eq(FrlgFont.NPC_TEXT_COLOR.MALE, 0, "MALE is 0")
assert_eq(FrlgFont.NPC_TEXT_COLOR.FEMALE, 1, "FEMALE is 1")
assert_eq(FrlgFont.NPC_TEXT_COLOR.MON, 2, "MON is 2")
assert_eq(FrlgFont.NPC_TEXT_COLOR.NEUTRAL, 3, "NEUTRAL is 3")
assert_eq(FrlgFont.NPC_TEXT_COLOR.DEFAULT, 255, "DEFAULT is 255")

-- src/dynamic_placeholder_text_util.c:9
local PRET_TABLE = {
  0x00, 0x00, 0x00, 0x10, 0x11, 0x11, 0x11, 0x10, 0x10, 0x00, 0x00, 0x11,
  0x01, 0x00, 0x11, 0x10, 0x00, 0x10, 0x10, 0x00, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x11, 0x01, 0x00, 0x00,
  0x00, 0x10, 0x11, 0x00, 0x10, 0x10, 0x10, 0x00, 0x01, 0x00, 0x33, 0x33,
  0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x23, 0x22, 0x22, 0x22, 0x22, 0x22,
  0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
  0x22, 0x22, 0x22, 0x32,
}
assert_eq(#PRET_TABLE, 76, "pret table has 76 bytes")
for gfx = 0, 151 do
  local b = PRET_TABLE[math.floor(gfx / 2) + 1]
  local want = (gfx % 2 == 0) and (b % 16) or math.floor(b / 16)
  assert_eq(FrlgFont.getNpcTextColor(gfx), want, "gfx " .. gfx .. " color")
end
assert_eq(FrlgFont.getNpcTextColor(152), 3, "past table is NEUTRAL (3)")
assert_eq(FrlgFont.getNpcTextColor(108), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "SEAGALLOP is NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(150), FrlgFont.NPC_TEXT_COLOR.MON, "DEOXYS_N is MON")
assert_eq(FrlgFont.getNpcTextColor(151), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "SS_ANNE is NEUTRAL")
assert_eq(FrlgFont.getNpcTextColor(95), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "CUT_TREE is NEUTRAL")
print("[ok] enum and all 152 table entries match pret")

print("=== [TEST 8] Message.show npcColor (field_message_box.c:103) ===")
Message.show("x", { npcColor = 0 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[8], "npcColor MALE is BLUE")
Message.show("x", { npcColor = 1 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[4], "npcColor FEMALE is RED")
Message.show("x", { npcColor = 2 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[2], "npcColor MON is DARK_GRAY")
Message.show("x", { npcColor = 3 })
assert_eq(Message._colors.fg, FrlgFont.STDPAL[2], "npcColor NEUTRAL is DARK_GRAY")
Message.close()
print("[ok] npcColor maps to pret printer colors")

print("=== [TEST 9] VAR_TEXT_COLOR / ContextNpcGetTextColor resolver ===")
pcall(function() require("src.core.GameVersion").set("firered") end)
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Adapters = require("src.core.game3.scripting.adapters")
local Vm = require("src.core.game3.scripting.vm")

local c0 = Ctx.new()
assert_eq(c0.specialVars[0x8012], 255, "fresh ctx VAR_TEXT_COLOR is DEFAULT")
c0.specialVars[0x8012] = 1
Ctx.wipeSpecial(c0)
assert_eq(c0.specialVars[0x8012], 255, "wipeSpecial reseeds DEFAULT")

local realObjects = package.loaded["src.core.game3.objects"]
local fakeObjs = {
  [1] = { localId = 1, graphicsId = 64 },  -- NURSE
  [2] = { localId = 2, graphicsId = 71 },  -- PROF_OAK
  [3] = { localId = 3, graphicsId = 92 },  -- ITEM_BALL
  [4] = { localId = 4, graphicsId = 120 }, -- PIKACHU
  [5] = { localId = 5, graphicsId = 240 }, -- OBJ_EVENT_GFX_VAR_0
}
package.loaded["src.core.game3.objects"] = {
  find = function(lid) return fakeObjs[tonumber(lid)] end,
  isPlayer = function(lid) return tonumber(lid) == 255 end,
}

local r = Ctx.new()
assert_eq(Adapters.resolveNpcColor(r), 3, "no selection + DEFAULT is NEUTRAL")
Ctx.selectObject(r, 1)
assert_eq(Adapters.resolveNpcColor(r), 1, "nurse selected is FEMALE")
Ctx.selectObject(r, 2)
assert_eq(Adapters.resolveNpcColor(r), 0, "oak selected is MALE")
Ctx.selectObject(r, 3)
assert_eq(Adapters.resolveNpcColor(r), 3, "item ball selected is NEUTRAL")
Ctx.selectObject(r, 4)
assert_eq(Adapters.resolveNpcColor(r), 2, "pikachu selected is MON")
Ctx.selectObject(r, 1)
r.specialVars[0x8012] = 0
assert_eq(Adapters.resolveNpcColor(r), 0, "explicit textcolor beats sprite")
r.specialVars[0x8012] = 255
Ctx.selectObject(r, 5)
local gfxStore = Flags.newStore()
Flags.setVar(gfxStore, r, 0x4010, 64)
assert_eq(Adapters.resolveNpcColor(r, gfxStore), 1, "OBJ_EVENT_GFX_VAR_0 resolves through VAR_OBJ_GFX_ID_0")
Ctx.selectObject(r, 1)
fakeObjs[1] = nil
assert_eq(Adapters.resolveNpcColor(r), 1, "removed object keeps its cached sprite color")
fakeObjs[1] = { localId = 1, graphicsId = 64 }
Ctx.selectObject(r, 0)
assert_eq(Adapters.resolveNpcColor(r), 3, "cleared selection is NEUTRAL")
print("[ok] resolver mirrors field_specials.c:1548")

print("=== [TEST 10] textcolor saves prev, restore, release keeps color ===")
local TextIR2 = require("src.core.game3.scripting.text_ir")
local seen = {}
local vmRef
local adapters = Adapters.stub({
  onMessage = function() seen[#seen + 1] = Adapters.resolveNpcColor(vmRef.ctx) end,
})
local scripts = {}
-- data/scripts/obtain_item.inc:6
scripts.EventScript_RestorePrevTextColor = {
  { op = "copyvar", [1] = 0x8012, [2] = 0x8013 },
  { op = "return" },
}
scripts.test_npc = {
  { op = "message", ptr = "T" },
  { op = "textcolor", color = 3 },
  { op = "message", ptr = "T" },
  { op = "call", target = "EventScript_RestorePrevTextColor" },
  { op = "message", ptr = "T" },
  { op = "textcolor", color = 0 },
  { op = "closemessage" },
  { op = "release" },
  { op = "message", ptr = "T" },
  { op = "end" },
}
scripts.test_sign = {
  { op = "message", ptr = "T" },
  { op = "end" },
}
vmRef = Vm.new({ scripts = scripts, text = { T = TextIR2.fromAscii("hi") }, adapters = adapters })
vmRef:startTalk("test_npc", 1, 1)
assert_eq(seen[1], 1, "nurse line is FEMALE")
assert_eq(seen[2], 3, "forced NEUTRAL line")
assert_eq(seen[3], 1, "RestorePrevTextColor returns to DEFAULT, nurse FEMALE again")
assert_eq(seen[4], 0, "closemessage/release keep textcolor")
assert_eq(vmRef.ctx.specialVars[0x8012], 255, "script end resets VAR_TEXT_COLOR to DEFAULT")
assert_eq(vmRef.ctx.selectedLocalId, nil, "script end clears selection")

seen = {}
vmRef:startTalk("test_sign", 0, 1)
assert_eq(seen[1], 3, "sign/trigger (LAST_TALKED 0) is NEUTRAL")
print("[ok] textcolor / RestorePrevTextColor / reset rules")

print("=== [TEST 11] std bookends (obtain_item.inc:10, std_msgbox.inc:29) ===")
seen = {}
scripts.test_received = {
  { op = "textcolor", color = 0 },
  { op = "message", ptr = "T" },
  { op = "textcolor", color = 3 },
  { op = "message", ptr = "T" },
  { op = "call", target = "EventScript_RestorePrevTextColor" },
  { op = "message", ptr = "T" },
  { op = "end" },
}
vmRef:startTalk("test_received", 3, 1)
assert_eq(seen[1], 0, "cutscene speaker MALE")
assert_eq(seen[2], 3, "{PLAYER} received line NEUTRAL")
assert_eq(seen[3], 0, "speaker MALE restored")
print("[ok] std bookends match pret")

print("=== [TEST 12] trainerbattle stamps trainer as selected (battle_setup.c:778) ===")
local store = vmRef.store
Flags.setFlag(store, vmRef.ctx, Flags.trainerFlagId(102), true)
scripts.test_trainer = {
  { op = "trainerbattle", type = 0, trainer = 102, localId = 1, [1] = 102, [2] = 1 },
  { op = "message", ptr = "T" },
  { op = "end" },
}
seen = {}
vmRef:startTalk("test_trainer", 0, 1)
assert_eq(seen[1], 1, "post-battle text keeps the trainer's sprite color")
print("[ok] trainerbattle keeps trainer color")

package.loaded["src.core.game3.objects"] = realObjects

print("\nALL TEXT COLORS & ROM PARITY TESTS PASSED CLEANLY!")

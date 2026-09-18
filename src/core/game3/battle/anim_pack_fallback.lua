-- Builtin fallback anim pack when cache extract is missing.
-- Provides generic Tackle-like IR for all moves + a few named labels.

local GENERIC = {
  { op = "loadspritegfx", tag = "IMPACT" },
  { op = "monbg", battler = "target" },
  { op = "createsprite", template = "gHorizontalLungeSpriteTemplate", animBattler = "attacker", subpriority = 2, args = { 4, 4 } },
  { op = "delay", frames = 6 },
  { op = "createsprite", template = "gBasicHitSplatSpriteTemplate", animBattler = "attacker", subpriority = 2, tag = "IMPACT", args = { 0, 0, "target", 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "target", 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "end" },
}

local STATUS = {
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "attacker", 2, 0, 10, 1 } },
  { op = "waitforvisualfinish" },
  { op = "end" },
}

local pack = {
  version = 1,
  moves = {},
  status = {
    PSN = STATUS,
    BRN = STATUS,
    SLP = STATUS,
    PAR = STATUS,
    FRZ = STATUS,
  },
  general = {},
  special = {},
  labels = {},
  tags = {},
}

-- Move id 33 = Tackle in FRLG; fill a range so lookups work
for id = 0, 355 do
  pack.moves[id] = GENERIC
end

return pack

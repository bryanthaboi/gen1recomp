-- FRLG OBJ_EVENT_GFX_* numeric ids → Gen2 host SPRITE_* names.
-- Sourced from pret pokefirered include/constants/event_objects.h

local GfxIds = {}

GfxIds.TO_SPRITE = {
  [0] = "SPRITE_CHRIS",            -- RED (player male)
  [7] = "SPRITE_KRIS",             -- GREEN / Leaf (player female)
  [16] = "SPRITE_YOUNGSTER",       -- LITTLE_BOY
  [17] = "SPRITE_LASS",            -- LITTLE_GIRL
  [18] = "SPRITE_YOUNGSTER",
  [19] = "SPRITE_YOUNGSTER",       -- BOY
  [22] = "SPRITE_LASS",
  [23] = "SPRITE_TEACHER",         -- WOMAN_1
  [24] = "SPRITE_COOLTRAINER_F",   -- CRUSH_GIRL
  [25] = "SPRITE_POKEFAN_M",       -- MAN
  [26] = "SPRITE_ROCKER",
  [27] = "SPRITE_FISHER",          -- FAT_MAN
  [29] = "SPRITE_BEAUTY",
  [30] = "SPRITE_POKEFAN_M",       -- BALDING_MAN
  [31] = "SPRITE_TEACHER",         -- WOMAN_3
  [32] = "SPRITE_GRAMPS",          -- OLD_MAN_1
  [33] = "SPRITE_GRAMPS",
  [35] = "SPRITE_GRANNY",
  [39] = "SPRITE_YOUNGSTER",       -- CAMPER
  [40] = "SPRITE_LASS",            -- PICNICKER
  [41] = "SPRITE_COOLTRAINER_M",
  [42] = "SPRITE_COOLTRAINER_F",
  [48] = "SPRITE_SCIENTIST",       -- OAK lab aide
  [54] = "SPRITE_BLACK_BELT",
  [55] = "SPRITE_SCIENTIST",
  [56] = "SPRITE_POKEFAN_M",       -- HIKER
  [57] = "SPRITE_FISHER",
  [61] = "SPRITE_GENTLEMAN",
  [62] = "SPRITE_SAILOR",
  [64] = "SPRITE_NURSE",
  [65] = "SPRITE_LINK_RECEPTIONIST",
  [68] = "SPRITE_CLERK",
  [69] = "SPRITE_OFFICER",         -- MG_DELIVERYMAN fallback
  [71] = "SPRITE_OAK",
  [72] = "SPRITE_BLUE",
  [73] = "SPRITE_BILL",
  [76] = "SPRITE_MOM",             -- rival's sister / Daisy-ish
  [88] = "SPRITE_MOM",             -- player's PC / mom-adjacent
  [89] = "SPRITE_SUPER_NERD",      -- CELIO
  [92] = "SPRITE_POKE_BALL",
}

-- FRLG MOVEMENT_TYPE_* → host movement/range/radius (Gen1 strings or LOOK).
GfxIds.MOVEMENT = {
  [0x01] = { movement = "LOOK", range = "DOWN" },           -- LOOK_AROUND
  [0x02] = { movement = "WALK", range = "ANY_DIR" },        -- WANDER_AROUND
  [0x03] = { movement = "WALK", range = "UP_DOWN" },
  [0x04] = { movement = "WALK", range = "UP_DOWN" },
  [0x05] = { movement = "WALK", range = "LEFT_RIGHT" },
  [0x06] = { movement = "WALK", range = "LEFT_RIGHT" },
  [0x07] = { movement = "STAY", range = "UP" },
  [0x08] = { movement = "STAY", range = "DOWN" },
  [0x09] = { movement = "STAY", range = "LEFT" },
  [0x0A] = { movement = "STAY", range = "RIGHT" },
  [0x0D] = { movement = "LOOK", range = "DOWN" },           -- FACE_DOWN_AND_UP
  [0x0E] = { movement = "LOOK", range = "LEFT" },           -- FACE_LEFT_AND_RIGHT
  [0x17] = { movement = "LOOK", range = "DOWN" },           -- ROTATE_CCW
  [0x18] = { movement = "LOOK", range = "DOWN" },           -- ROTATE_CW
  [0x19] = { movement = "WALK", range = "UP_DOWN" },
  [0x1A] = { movement = "WALK", range = "UP_DOWN" },
  [0x1B] = { movement = "WALK", range = "LEFT_RIGHT" },
  [0x1C] = { movement = "WALK", range = "LEFT_RIGHT" },
  [0x4D] = { movement = "RAISE_HAND", range = "DOWN" },
  [0x4E] = { movement = "RAISE_HAND", range = "DOWN" },
  [0x4F] = { movement = "RAISE_HAND", range = "DOWN" },
}

function GfxIds.spriteFor(graphicsId)
  return GfxIds.TO_SPRITE[tonumber(graphicsId) or -1] or "SPRITE_YOUNGSTER"
end

function GfxIds.hostMovement(movementType, rangeX, rangeY)
  local mt = tonumber(movementType) or 0
  local spec = GfxIds.MOVEMENT[mt] or { movement = "STAY", range = "DOWN" }
  local out = {
    movement = spec.movement,
    range = spec.range,
  }
  if out.movement == "WALK" then
    local rx = math.max(1, tonumber(rangeX) or 1)
    local ry = math.max(1, tonumber(rangeY) or 1)
    out.radius = { x = rx, y = ry }
  end
  return out
end

return GfxIds

-- home/map_objects.asm

local CollPermissions = {}

CollPermissions.LAND = 0x00
CollPermissions.WATER = 0x01
CollPermissions.WALL = 0x0f

local TABLE = {
   0,  0,  0,  0,  0,  0,  0, 15,  0,  0,  0,  0,  0,  0,  0, 15,
   0,  0, 15,  0,  0, 15,  0,  0,  0,  0, 15,  0,  0, 15,  0,  0,
   1,  1,  1,  0,  1,  1,  1, 15,  1,  1,  1,  0,  1,  1,  1, 15,
   1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0, 15,  0,  0,  0,  0,  0,  0,  0, 15,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
  15, 15, 15, 15, 15,  0,  0,  0, 15, 15, 15, 15, 15,  0,  0,  0,
  15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 15,
}

function CollPermissions.of(coll)
  if coll == nil or coll < 0 then return CollPermissions.WALL end
  return TABLE[(coll % 256) + 1] or CollPermissions.WALL
end

function CollPermissions.isLand(coll)
  return CollPermissions.of(coll) == CollPermissions.LAND
end

function CollPermissions.isWater(coll)
  return CollPermissions.of(coll) == CollPermissions.WATER
end

function CollPermissions.isWall(coll)
  return CollPermissions.of(coll) == CollPermissions.WALL
end

function CollPermissions.isWalkable(coll)
  return CollPermissions.of(coll) == CollPermissions.LAND
end

function CollPermissions.isLedge(coll)
  if coll == nil or coll < 0 then return false end
  return math.floor((coll % 256) / 16) == 0xa
end

return CollPermissions

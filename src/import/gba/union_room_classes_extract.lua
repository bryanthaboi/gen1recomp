-- src/pokemon.c:1666, :6197, :6206

local Versions = require("src.import.gba.versions")

local UnionRoomClassesExtract = {}

UnionRoomClassesExtract.CACHE_SUB = "trainers"
UnionRoomClassesExtract.FILE = "union_room_classes.lua"

function UnionRoomClassesExtract.extract(rom)
  local out = { facilityClass = {}, trainerClass = {}, trainerPic = {} }
  for i = 0, Versions.UNION_ROOM_CLASS_COUNT - 1 do
    local facility = rom:u16(Versions.UNION_ROOM_FACILITY_CLASSES + i * 2)
    out.facilityClass[i] = facility
    out.trainerClass[i] = rom:get(Versions.FACILITY_CLASS_TO_TRAINER_CLASS + facility)
    out.trainerPic[i] = rom:get(Versions.FACILITY_CLASS_TO_PIC_INDEX + facility)
  end
  return out
end

function UnionRoomClassesExtract.run(rom, cache, opts)
  opts = opts or {}
  local serialize = require("src.import.gba.extract_scripts").serialize_lua
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. UnionRoomClassesExtract.CACHE_SUB
  local pack = UnionRoomClassesExtract.extract(rom)
  cache:write(root .. "/" .. UnionRoomClassesExtract.FILE, "return " .. serialize(pack) .. "\n")
  return pack
end

return UnionRoomClassesExtract

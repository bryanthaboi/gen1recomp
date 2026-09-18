-- FRLG Sevii region-map pages for Gen2 Pokegear (cursor + page toggle).
local M = {}
M.IMAGE_W = 240
M.IMAGE_H = 160
M.PAGES = {
  {
    id = "sevii123",
    label = "SEVII 1-3",
    image = "assets/sevii_region_123.png",
    landmarks = {
      { mapsec = "MAPSEC_ONE_ISLAND", name = "ONE ISLAND", px = 44, py = 76, hostMap = "SEVII_ONE_ISLAND" },
      { mapsec = "MAPSEC_TWO_ISLAND", name = "TWO ISLAND", px = 108, py = 84, hostMap = nil },
      { mapsec = "MAPSEC_THREE_ISLAND", name = "THREE ISLAND", px = 180, py = 108, hostMap = nil },
      { mapsec = "MAPSEC_KINDLE_ROAD", name = "KINDLE ROAD", px = 52, py = 56, hostMap = "SEVII_ONE_ISLAND_KINDLE_ROAD" },
      { mapsec = "MAPSEC_TREASURE_BEACH", name = "TREASURE BEACH", px = 44, py = 88, hostMap = "SEVII_ONE_ISLAND_TREASURE_BEACH" },
      { mapsec = "MAPSEC_CAPE_BRINK", name = "CAPE BRINK", px = 108, py = 72, hostMap = nil },
      { mapsec = "MAPSEC_BOND_BRIDGE", name = "BOND BRIDGE", px = 160, py = 108, hostMap = nil },
      { mapsec = "MAPSEC_THREE_ISLE_PORT", name = "THREE ISLE PORT", px = 184, py = 116, hostMap = nil },
    },
  },
  {
    id = "sevii45",
    label = "SEVII 4-5",
    image = "assets/sevii_region_45.png",
    landmarks = {
      { mapsec = "MAPSEC_FOUR_ISLAND", name = "FOUR ISLAND", px = 60, py = 44, hostMap = nil },
      { mapsec = "MAPSEC_FIVE_ISLAND", name = "FIVE ISLAND", px = 164, py = 100, hostMap = nil },
      { mapsec = "MAPSEC_RESORT_GORGEOUS", name = "RESORT GORGEOUS", px = 172, py = 84, hostMap = nil },
      { mapsec = "MAPSEC_WATER_LABYRINTH", name = "WATER LABYRINTH", px = 156, py = 92, hostMap = nil },
      { mapsec = "MAPSEC_FIVE_ISLE_MEADOW", name = "FIVE ISLE MEADOW", px = 172, py = 104, hostMap = nil },
      { mapsec = "MAPSEC_MEMORIAL_PILLAR", name = "MEMORIAL PILLAR", px = 180, py = 116, hostMap = nil },
    },
  },
  {
    id = "sevii67",
    label = "SEVII 6-7",
    image = "assets/sevii_region_67.png",
    landmarks = {
      { mapsec = "MAPSEC_SIX_ISLAND", name = "SIX ISLAND", px = 172, py = 52, hostMap = nil },
      { mapsec = "MAPSEC_SEVEN_ISLAND", name = "SEVEN ISLAND", px = 76, py = 76, hostMap = nil },
      { mapsec = "MAPSEC_OUTCAST_ISLAND", name = "OUTCAST ISLAND", px = 156, py = 24, hostMap = nil },
      { mapsec = "MAPSEC_GREEN_PATH", name = "GREEN PATH", px = 164, py = 36, hostMap = nil },
      { mapsec = "MAPSEC_WATER_PATH", name = "WATER PATH", px = 180, py = 52, hostMap = nil },
      { mapsec = "MAPSEC_RUIN_VALLEY", name = "RUIN VALLEY", px = 168, py = 72, hostMap = nil },
      { mapsec = "MAPSEC_TRAINER_TOWER", name = "TRAINER TOWER", px = 76, py = 64, hostMap = nil },
      { mapsec = "MAPSEC_CANYON_ENTRANCE", name = "CANYON ENTRANCE", px = 76, py = 84, hostMap = nil },
      { mapsec = "MAPSEC_SEVAULT_CANYON", name = "SEVAULT CANYON", px = 84, py = 92, hostMap = nil },
      { mapsec = "MAPSEC_TANOBY_RUINS", name = "TANOBY RUINS", px = 84, py = 108, hostMap = nil },
    },
  },
}
return M

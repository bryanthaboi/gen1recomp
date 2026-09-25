-- home/overworld.asm:2016
return function(data, mapId)
  local map = data and data.maps and data.maps[mapId]
  if not map then return data end
  if not map.sram then
    map.sram = {
      header = { 0, map.height or 4, map.width or 5,
                 0x00, 0xC0, 0x00, 0xC0, 0x00, 0xC0, 0x00 },
      connections = {},
      objects = { 0x0E, 0, 0, 0 },
    }
  end
  data.tilesets = data.tilesets or {}
  if map.tileset then
    local ts = data.tilesets[map.tileset]
    if not ts then
      ts = {}
      data.tilesets[map.tileset] = ts
    end
    ts.header = ts.header or { 0x0C, 0x11, 0x40, 0x22, 0x40,
      0x33, 0x40, 0x44, 0x55, 0x66, 0x77, 0x02 }
  end
  data.audio = data.audio or {}
  data.audio.mapSongs = data.audio.mapSongs or {}
  data.audio.songs = data.audio.songs or {}
  data.audio.mapSongs[mapId] = data.audio.mapSongs[mapId] or "Music_Fixture"
  data.audio.songs.Music_Fixture = data.audio.songs.Music_Fixture
    or { address = 0x4000 + 3 * 0xBD, bank = 2 }
  data.encounters = data.encounters or {}
  return data
end

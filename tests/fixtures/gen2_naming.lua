local Fixture = {}

function Fixture.menuGfx()
  return {
    border = "assets/generated/naming/border.png",
    middleLine = "assets/generated/naming/middleline.png",
    underLine = "assets/generated/naming/underline.png",
    cursor = "assets/generated/naming/cursor.png",
  }
end

function Fixture.diploma()
  local pal = { { 255, 255, 255 }, { 156, 156, 156 }, { 82, 82, 82 }, { 0, 0, 0 } }
  local palettes = {}
  for slot = 1, 8 do palettes[slot] = pal end
  return { bgPalette = pal, palettes = palettes }
end

function Fixture.fill(data)
  data.gen2MenuGfx = data.gen2MenuGfx or {}
  for key, path in pairs(Fixture.menuGfx()) do
    if data.gen2MenuGfx[key] == nil then data.gen2MenuGfx[key] = path end
  end
  data.gen2Diploma = data.gen2Diploma or Fixture.diploma()
  return data
end

function Fixture.game()
  return { data = Fixture.fill({}) }
end

return Fixture

local Fixture = {}

function Fixture.splash()
  local pal = { { 255, 255, 255 }, { 255, 255, 255 }, { 206, 247, 0 }, { 206, 247, 0 } }
  return {
    presents = "assets/generated/splash/presents.png",
    logo = "assets/generated/splash/logo.png",
    star = "assets/generated/splash/star.png",
    sparkle = "assets/generated/splash/sparkle.png",
    obPalette = pal, bgPalette = pal,
  }
end

function Fixture.data(extra)
  local out = {
    playerPic = "assets/generated/intro/cal.png",
    shrink1 = "assets/generated/intro/shrink1.png",
    shrink2 = "assets/generated/intro/shrink2.png",
    oakPic = "assets/generated/intro/oak.png",
    marillPic = "assets/generated/battle/front/marill.png",
    demoSpecies = "MARILL",
    music = "Music_Route30",
    splash = Fixture.splash(),
    text = {},
  }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

return Fixture

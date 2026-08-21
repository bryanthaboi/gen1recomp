return {
  ledges = {},
  hiddenItems = {},
  waterTilesets = {},
  cutTreeSwaps = {},
  forcedMovement = { tiles = {}, clearMaps = {} },
  playerSprites = {
    walk = "SPRITE_FIX_PLAYER",
    surf = "SPRITE_FIX_PLAYER",
    bike = "SPRITE_FIX_PLAYER",
    fly = "SPRITE_FIX_PLAYER",
  },
  flyWarps = {
    FIX_TOWN = { x = 5, y = 6 },
  },
  flyOrder = { "FIX_TOWN" },
  townMap = {
    locations = {
      FIX_TOWN = { x = 4, y = 4, name = "FIX TOWN" },
      FIX_ROUTE = { x = 4, y = 3, name = "FIX ROUTE" },
    },
  },
  boot = {
    startMap = "FIX_TOWN", startX = 5, startY = 6, startFacing = "down",
    playerName = "FIX", rivalName = "RIV",
    startMoney = 3000,
    lastHeal = { map = "FIX_TOWN", x = 5, y = 6 },
  },
}

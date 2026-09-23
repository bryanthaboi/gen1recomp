function love.load(args)
  local root, romPath = assert(args[1], "repository path required"), assert(args[2], "ROM path required")
  package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
  local file = assert(io.open(romPath, "rb"))
  local rom = file:read("*a"); file:close()
  local Pmd = require("src.import.pmd.PmdImport")
  local Importers = require("src.import.Importers")
  local job = Pmd.job(rom, love.filesystem)
  local last = 0
  while coroutine.status(job) ~= "dead" do
    local ok, result = coroutine.resume(job)
    assert(ok, result)
    if result.done and result.done >= last + 50 then
      last = math.floor(result.done); print("PMD: " .. last .. "/423")
    end
  end
  local pack = assert(Importers.readPack("pmd_red", "sprites", love.filesystem))
  local count = 0
  for _, entry in pairs(pack.entries) do
    local metadata = assert(Importers.readMetadata("pmd_red", "sprites", entry, love.filesystem))
    assert(#metadata.animations > 0 and #metadata.sequences > 0)
    local bytes = assert(love.filesystem.read("asset_packs/pmd_red/sprites/" .. entry.file))
    assert(#bytes == entry.size)
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, entry.file))
    assert(image:getWidth() == entry.width and image:getHeight() == entry.height)
    image:release()
    count = count + 1
  end
  assert(count == 423)
  print("PMD PASS: 423 PNG sheets encoded, written, read back and dimension checked")
  print("OUTPUT: " .. love.filesystem.getSaveDirectory())
  love.event.quit(0)
end

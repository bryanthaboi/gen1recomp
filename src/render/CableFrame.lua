-- CableClub_TextBoxBorder -- engine/link/cable_club.asm:938

local CableFrame = {}

local frame = nil

local function tryImage(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  if ok and img then return img end
  local ok2, img2 = pcall(love.graphics.newImage, path)
  return ok2 and img2 or nil
end

-- engine/link/cable_club.asm:975
function CableFrame.load()
  if frame == nil then
    local img = tryImage("assets/generated/trainer_card/trainer_info.png")
    if not img then
      frame = false
    else
      local quads = {}
      for i = 0, 8 do
        quads[i] = love.graphics.newQuad((i % 3) * 8, math.floor(i / 3) * 8,
                                         8, 8, img:getDimensions())
      end
      frame = { img = img, quads = quads }
    end
  end
  return frame or nil
end

function CableFrame.invalidate()
  frame = nil
end

-- tile $7e, the blank pattern -- engine/link/cable_club.asm:603
function CableFrame.fill(tx, ty, tw, th)
  local f = CableFrame.load()
  love.graphics.setColor(1, 1, 1, 1)
  if not f then
    love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
    return
  end
  for j = 0, th - 1 do
    for i = 0, tw - 1 do
      love.graphics.draw(f.img, f.quads[8], (tx + i) * 8, (ty + j) * 8)
    end
  end
end

function CableFrame.box(tx, ty, tw, th)
  local f = CableFrame.load()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  if not f then
    require("src.render.Font").drawBox(tx, ty, tw, th)
    return
  end
  local img, q = f.img, f.quads
  local x1, y1 = (tx + tw - 1) * 8, (ty + th - 1) * 8
  love.graphics.draw(img, q[2], tx * 8, ty * 8)
  love.graphics.draw(img, q[4], x1, ty * 8)
  love.graphics.draw(img, q[6], tx * 8, y1)
  love.graphics.draw(img, q[7], x1, y1)
  for i = 1, tw - 2 do
    love.graphics.draw(img, q[3], (tx + i) * 8, ty * 8)
    love.graphics.draw(img, q[0], (tx + i) * 8, y1)
  end
  for j = 1, th - 2 do
    love.graphics.draw(img, q[5], tx * 8, (ty + j) * 8)
    love.graphics.draw(img, q[1], x1, (ty + j) * 8)
  end
end

return CableFrame

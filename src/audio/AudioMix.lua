local AudioMix = {}

local sent

function AudioMix.set(mix)
  mix = mix and true or false
  if sent == mix then return false end
  if not (love and love.audio and love.audio.setMixWithSystem) then
    return false
  end
  if pcall(love.audio.setMixWithSystem, mix) then sent = mix end
  return true
end

function AudioMix.current()
  return sent
end

function AudioMix._resetForTest()
  sent = nil
end

return AudioMix

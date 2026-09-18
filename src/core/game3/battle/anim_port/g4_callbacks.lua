local P = require("src.core.game3.battle.anim_port.g4_pret")
local T = require("src.core.game3.battle.anim_port.g4_templates")

return function(host)
  local C = { P = P, T = T, host = host }

  -- pokefirered/src/battle_main.c:304
  local PLAYER_THROW_X = { [0] = -32, -16, -16, -32, -32, 0, 0, 0 }
  -- pokefirered/src/data/trainer_graphics/back_pic_anims.h:1
  local BACK_THROW = {
    red = { [1] = { { f = 1, d = 20 }, { f = 2, d = 6 }, { f = 3, d = 6 }, { f = 4, d = 24 }, { f = 0, d = 1 }, { e = true } } },
    oldman = { [1] = { { f = 1, d = 24 }, { f = 2, d = 9 }, { f = 3, d = 24 }, { f = 0, d = 9 }, { e = true } } },
  }

  -- pokefirered/src/battle_main.c:2172
  function C.startPlayerThrow(vm)
    local ctx = vm.ctx or {}
    local pseudo = {
      _g4a = (ctx.oldManThrow and BACK_THROW.oldman) or BACK_THROW.red,
      data = {},
    }
    P.startAnim(pseudo, 1)
    vm._playerThrow = pseudo
    local stage = P.stage()
    local tp = stage and stage.trainer and stage.trainer.player
    vm:addSpriteHook(function(v)
      if v._playerThrow ~= pseudo then return false end
      if pseudo.done then return true end
      if pseudo.started then
        if (pseudo.animDelayCounter or 0) == 0 and tp then
          tp.ox = (PLAYER_THROW_X[pseudo.animCmdIndex or 0] or -32) + 32
        end
        if pseudo.animEnded then
          pseudo.done = true
          return true
        end
      end
      pseudo.started = true
      P.animate(pseudo)
      local c = pseudo._g4a[pseudo.animNum or 0][(pseudo.animCmdIndex or 0) + 1]
      if tp and c and c.f then tp.frame = c.f end
      return true
    end)
  end

  function C.playerThrowIndex(vm)
    local p = vm._playerThrow
    return p and p.animCmdIndex or -1
  end

  function C.playerThrowEnded(vm)
    local p = vm._playerThrow
    return (not p) or p.animEnded == true
  end

  function C.resetPlayerThrow(vm)
    local stage = P.stage()
    local tp = stage and stage.trainer and stage.trainer.player
    if tp then
      tp.frame = 0
      tp.ox = 0
    end
    vm._playerThrow = nil
  end

  local TABLE = {}
  local function merge(mod)
    for k, fn in pairs(mod) do TABLE[k] = fn end
  end
  merge(require("src.core.game3.battle.anim_port.g4_cb_a")(C))
  merge(require("src.core.game3.battle.anim_port.g4_cb_b")(C))

  local OUT = {}
  for name, fn in pairs(TABLE) do
    OUT[name] = function(s)
      if not s._g4init then
        s._g4init = true
        local vm = s._vm
        if not vm then
          local ok, Anim = pcall(require, "src.core.game3.battle.anim")
          vm = ok and Anim and Anim.vm and Anim.vm()
          if not vm then vm = require("src.core.game3.battle.anim_vm").new() end
          s._vm = vm
        end
        P.setupTemplate(s, T[s.template or ""] or T.EMPTY)
        for i = 0, 7 do s.data[i] = 0 end
        s.ox, s.oy = 0, 0
        s.visible = true
        if vm then
          s.x = P.coord(vm, P.tgt(vm), P.X_2)
          s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
        end
        s._pz = true
        P.setPriority(s, s.oamPriority or 2, s.subpriority or 0)
      end
      return fn(s)
    end
  end
  OUT._g4 = C
  return OUT
end

local Ops = require("Ops")
local Gen = require("Gen")
local PAL = require("Theme").PAL
local M = {}
local Touch = require("TouchEditor")
function M.draw(S, Kit, x, y, w, h)
  Kit.card(x, y, w, h)
  local pad, gap, row = 14 * Kit.scale, 10 * Kit.scale, Kit.controlH()
  local cx, inner = x + pad, w - 2 * pad
  local g = Gen.ofState(S)
  local fields = {
    {
      "name",
      "Trainer name",
      (S.save.player and S.save.player.name) or S.save.name or S.save.playerName or "",
    },
    { "id", "Trainer ID", (S.save.player and S.save.player.id) or S.save.trainerId or 0 },
    { "money", "Money", Gen.money(S.save) },
    { "coins", "Coins", Gen.coins(S.save) },
  }
  if g == 3 then
    table.insert(fields, 3, { "secretId", "Secret ID", S.save.secretId or 0 })
  end
  if Gen.hasBuenaPoints(S.save, S.version) then
    fields[#fields + 1] = { "buenaPoints", "Buena points", Gen.buenaPoints(S.save, S.version) }
  end
  if Gen.hasBerryPowder(S.save, S.version) then
    fields[#fields + 1] = { "berryPowder", "Berry Powder", Gen.berryPowder(S.save, S.version) }
  end
  if Gen.hasVolcanicAsh(S.save, S.version) then
    fields[#fields + 1] = { "volcanicAsh", "Volcanic Ash", Gen.volcanicAsh(S.save, S.version) }
  end
  if Gen.hasBattlePoints(S.save, S.version) then
    fields[#fields + 1] = { "battlePoints", "Battle Points", Gen.battlePoints(S.save, S.version) }
  end
  local contentH = S._trainerHeight or 0
  S.trainerScroll = Kit.scrollPixels(x, y, w, h, S.trainerScroll or 0, contentH)
  Kit.pushClip(x, y, w, h)
  local cy = y + pad - S.trainerScroll
  S.trainerDrafts = S.trainerDrafts or {}
  for _, f in ipairs(fields) do
    if f[1] ~= "name" then
      local hi = ({ id = 65535, secretId = 65535, money = 999999, coins = 9999, buenaPoints = 30,
        berryPowder = Gen.BERRY_POWDER_MAX, volcanicAsh = Gen.VOLCANIC_ASH_MAX,
        battlePoints = Gen.BATTLE_POINTS_MAX })[f[1]]
      cy = cy
        + Touch.value(
          S,
          Kit,
          "trainer-" .. f[1],
          f[2],
          f[3],
          {
            lo = 0,
            hi = hi,
            help = f[1] == "money" and "Your wallet. Max fills it."
              or f[1] == "coins" and "Game Corner coins. Max fills the coin case."
              or f[1] == "buenaPoints" and "Blue Card points for Buena's prizes. Choose 0 to 30."
              or f[1] == "berryPowder" and "Powder from Berry Crush, spent at the Berry Powder shop. Choose 0 to 99999."
              or f[1] == "volcanicAsh" and "Ash collected in the Soot Sack, spent at the Glass Workshop. Choose 0 to 9999."
              or f[1] == "battlePoints" and "Battle Frontier points, spent at the Exchange Service Corner. Choose 0 to 9999."
              or "Part of your trainer identity. Changing it can affect who owns a Pokémon.",
          },
          cx,
          cy,
          inner,
          function(v)
            return Ops.setTrainerProperty(S, f[1], v)
          end
        )
        + gap
    else
      Kit.text("small", f[2], cx, cy, PAL.text)
      cy = cy + Kit.textHeight("small") + gap
      local key = "trainer-" .. f[1]
      local setW = math.max(row, 64 * Kit.scale)
      local function apply(v)
        if Ops.setTrainerProperty(S, f[1], v) then
          S.trainerDrafts[f[1]] = nil
        end
      end
      S.trainerDrafts[f[1]] = Kit.textfield(
        key,
        cx,
        cy,
        inner - setW - gap,
        row,
        S.trainerDrafts[f[1]] or tostring(f[3]),
        "Name",
        { onSubmit = apply }
      )
      if
        Kit.button(cx + inner - setW, cy, setW, row, "Set", { kind = "accent", font = "small" })
      then
        apply(S.trainerDrafts[f[1]])
        Kit.blur()
      end
      cy = cy + row + gap
    end
  end
  if Gen.hasPlayerGender(S.save, S.version) then
    local half = (inner - gap) / 2
    for i, v in ipairs({ "male", "female" }) do
      if
        Kit.chip(
          cx + (i - 1) * (half + gap),
          cy,
          half,
          row,
          v:upper(),
          Gen.playerGender(S.save) == v
        )
      then
        Ops.setPlayerGender(S, v)
      end
    end
  end
  S._trainerHeight = cy
    - (y + pad - S.trainerScroll)
    + 2 * pad
    + (Gen.hasPlayerGender(S.save, S.version) and row + gap or 0)
  Kit.popClip()
  Kit.scrollbar(x, y, w, h, S.trainerScroll, S._trainerHeight, h)
end
return M

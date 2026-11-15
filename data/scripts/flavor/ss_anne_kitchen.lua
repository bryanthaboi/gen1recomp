-- SS Anne kitchen cook flavor dialogue.
-- pokered/scripts/SSAnneKitchen.asm SSAnneKitchenCook7Text

local function push(game, s, done)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, done))
end

return {
  SS_ANNE_KITCHEN = {
    talk = {
      -- scripts/SSAnneKitchen.asm:39
      TEXT_SSANNEKITCHEN_COOK7 = function(game, ow, npc, done)
        local t = game.data.text
        push(game, t._SSAnneKitchenCook7MainCourseIsText, function()
          local roll = math.random(1, 4)
          local dish
          if roll <= 2 then
            -- bit 7 of hRandomAdd set (~50%)
            dish = t.SSAnneKitchenCook7SalmonDuSaladText
          elseif roll == 3 then
            -- bit 4 set, bit 7 clear (~25%)
            dish = t.SSAnneKitchenCook7EelsAuBarbecueText
          else
            -- neither bit set (~25%)
            dish = t.SSAnneKitchenCook7PrimeBeefSteakText
          end
          push(game, dish, done)
        end)
      end,
    },
  },
}

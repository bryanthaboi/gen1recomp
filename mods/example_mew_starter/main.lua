-- Example native mod.  It demonstrates both a runtime event and a content
-- override without requiring any private engine module.
return function(mod)
  local mew = mod.content.pokemon:get("MEW")
  assert(mew, "Mew is missing from the imported base data")

  -- Keep every vanilla Mew field, changing only the battle sprite paths.
  local invertedMew = {}
  for key, value in pairs(mew) do invertedMew[key] = value end
  invertedMew.spriteFront = mod.path .. "/assets/mew_front_inverted.png"
  invertedMew.spriteBack = mod.path .. "/assets/mew_back_inverted.png"
  invertedMew.spriteFront64 = mod.path .. "/assets/mew_front_inverted_64.png"
  invertedMew.spriteBack64 = mod.path .. "/assets/mew_back_inverted_64.png"
  mod.content.pokemon:override("MEW", invertedMew)

  local function firstStarter(ctx)
    local map = ctx.overworld and ctx.overworld.map
    local save = ctx.save
    return map and map.id == "OAKS_LAB" and not save.flags.EVENT_GOT_STARTER
      and #(save.party or {}) == 0
  end

  if mod.generation == 3 then
    local PLAYER_STARTER_SPECIES, CHARMANDER, MEW = 0x4002, 4, 151
    mod.hooks:wrap("script.command", function(next, ctx, op, row)
      if op == "setvar" and (row.var or row[1]) == PLAYER_STARTER_SPECIES
         and (row.value or row[2]) == CHARMANDER and firstStarter(ctx) then
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        copy.value, copy[2] = MEW, MEW
        return next(ctx, op, copy)
      end
      return next(ctx, op, row)
    end)

    local confirm = mod.content.text:get("g3:0818e194")
    if type(confirm) == "table" then
      local hoghead = {}
      for i, token in ipairs(confirm) do
        local t = {}
        for k, v in pairs(token) do t[k] = v end
        if type(t.s) == "string" then
          t.s = t.s:gsub("FIRE POKéMON CHARMANDER", "PSYCHIC POKéMON HOGHEAD")
            :gsub("CHARMANDER", "HOGHEAD")
        end
        hoghead[i] = t
      end
      mod.content.text:override("g3:0818e194", hoghead)
    end
  end

  mod.events:on("pokemon.before_give", function(gift)
    -- Only change the Oak's Lab Charmander gift; wild encounters and other
    -- story gifts remain vanilla.
    local starter = gift.species == "CHARMANDER"
      or (mod.generation == 3 and gift.species == "MEW")
    if starter and firstStarter(gift.ctx) then
      gift.species = "MEW"
      gift.level = 20
      gift.nickname = "HOGHEAD"
      mod.log:info("replaced Oak's Lab Charmander starter with level 20 Mew")
    end
  end)
end

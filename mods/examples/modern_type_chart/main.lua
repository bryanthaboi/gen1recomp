return function(mod)
  local moves = {
    { "GUST",        { type = "FLYING",  category = "special" } },
    { "KARATE_CHOP", { type = "FIGHTING", category = "physical" } },
    { "SAND_ATTACK", { type = "GROUND",   category = "status" } },
    { "BITE",        { type = "DARK",     category = "physical" } },
  }
  for _, change in ipairs(moves) do
    if mod.content.moves:get(change[1]) then
      mod.content.moves:patch(change[1], change[2])
    else
      mod.log:warn("%s is missing; type update skipped", change[1])
    end
  end

  local chart = mod.content.type_chart
  local function set(id, value)
    if chart:get(id) then chart:patch(id, value) else chart:register(id, value) end
  end

  set("DARK", { name = "DARK", category = "special" })
  for _, matchup in ipairs({
    { "DARK>FIGHTING", 5 }, { "DARK>GHOST", 20 },
    { "DARK>PSYCHIC_TYPE", 20 }, { "DARK>DARK", 5 },
    { "FIGHTING>DARK", 20 }, { "BUG>DARK", 20 },
    { "GHOST>DARK", 5 }, { "PSYCHIC_TYPE>DARK", 0 },
    { "GHOST>PSYCHIC_TYPE", 20 },
  }) do
    set(matchup[1], { multiplier = matchup[2] })
  end
end

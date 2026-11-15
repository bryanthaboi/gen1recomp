local Fixture = {}

-- ../pokegold/engine/overworld/wildmons.asm:488
Fixture.ROAM_MONS_GOLD = {
  { species = "RAIKOU", level = 40, map = "ROUTE_42" },
  { species = "ENTEI", level = 40, map = "ROUTE_37" },
  { species = "SUICUNE", level = 40, map = "ROUTE_38" },
}

-- ../pokecrystal/engine/overworld/wildmons.asm:493
Fixture.ROAM_MONS_CRYSTAL = {
  { species = "RAIKOU", level = 40, map = "ROUTE_42" },
  { species = "ENTEI", level = 40, map = "ROUTE_37" },
}

-- ../pokecrystal/data/wild/roammon_maps.asm:17
Fixture.ROAM_MAPS = {
  { map = "ROUTE_29", to = { "ROUTE_30", "ROUTE_46" } },
  { map = "ROUTE_30", to = { "ROUTE_29", "ROUTE_31" } },
  { map = "ROUTE_31", to = { "ROUTE_30", "ROUTE_32", "ROUTE_36" } },
  { map = "ROUTE_32", to = { "ROUTE_36", "ROUTE_31", "ROUTE_33" } },
  { map = "ROUTE_33", to = { "ROUTE_32", "ROUTE_34" } },
  { map = "ROUTE_34", to = { "ROUTE_33", "ROUTE_35" } },
  { map = "ROUTE_35", to = { "ROUTE_34", "ROUTE_36" } },
  { map = "ROUTE_36", to = { "ROUTE_35", "ROUTE_31", "ROUTE_32", "ROUTE_37" } },
  { map = "ROUTE_37", to = { "ROUTE_36", "ROUTE_38", "ROUTE_42" } },
  { map = "ROUTE_38", to = { "ROUTE_37", "ROUTE_39", "ROUTE_42" } },
  { map = "ROUTE_39", to = { "ROUTE_38" } },
  { map = "ROUTE_42", to = { "ROUTE_43", "ROUTE_44", "ROUTE_37", "ROUTE_38" } },
  { map = "ROUTE_43", to = { "ROUTE_42", "ROUTE_44" } },
  { map = "ROUTE_44", to = { "ROUTE_42", "ROUTE_43", "ROUTE_45" } },
  { map = "ROUTE_45", to = { "ROUTE_44", "ROUTE_46" } },
  { map = "ROUTE_46", to = { "ROUTE_45", "ROUTE_29" } },
}

function Fixture.encounters(edition, extra)
  local out = {
    roamMaps = Fixture.ROAM_MAPS,
    roamMons = edition == "crystal" and Fixture.ROAM_MONS_CRYSTAL
      or Fixture.ROAM_MONS_GOLD,
  }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

return Fixture

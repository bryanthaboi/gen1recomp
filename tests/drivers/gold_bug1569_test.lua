-- #1569 givepoke names (scripting.asm:1817, move_mon.asm:1698-1736)
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_bug1569_test.lua love .

local U = require("tests.drivers.util")

local function findGivepoke(scripts)
  for key, rows in pairs(scripts) do
    if type(rows) == "table" then
      for _, row in ipairs(rows) do
        if row.op == "givepoke" and (row.trainer or 0) ~= 0 then
          return key, row
        end
      end
    end
  end
  return nil
end

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.vm, "gold world did not boot")

  local failed = false
  local key, row = findGivepoke(world.scripts or {})
  if not row then
    U.log("FAIL no trainer-form givepoke in the extracted scripts")
    failed = true
  else
    U.log("givepoke row from", tostring(key))
    if row.name ~= "KENYA" then
      U.log("FAIL nickname is", tostring(row.name), "want KENYA")
      failed = true
    end
    if row.otName ~= "RANDY" then
      U.log("FAIL OT name is", tostring(row.otName), "want RANDY")
      failed = true
    end
  end

  game.save.party = {}
  local give = world.vm.givePokeFn
  assert(give, "the VM has no givePoke hook")
  local mon = give(row and row.species or 21, row and row.level or 10, 0,
    { nickname = "KENYA", otName = "RANDY" })
  if not mon then
    U.log("FAIL givePoke made no mon")
    failed = true
  else
    if mon.nickname ~= "KENYA" then
      U.log("FAIL mon nickname is", tostring(mon.nickname))
      failed = true
    end
    if mon.otName ~= "RANDY" or mon.ot ~= "RANDY" then
      U.log("FAIL mon OT is", tostring(mon.ot), tostring(mon.otName))
      failed = true
    end
    if mon.otId ~= 1001 then
      U.log("FAIL mon OT id is", tostring(mon.otId), "want RANDY_OT_ID 1001")
      failed = true
    end
    if mon.species ~= "SPEAROW" then
      U.log("FAIL species is", tostring(mon.species))
      failed = true
    end
  end

  U.log(failed and "RESULT FAIL" or "RESULT PASS")
  love.event.quit(failed and 1 or 0)
end

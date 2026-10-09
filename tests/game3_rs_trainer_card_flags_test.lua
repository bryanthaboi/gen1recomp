#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.core.game3.dex"] = { nationalEnabled = function() return false end }
package.loaded["src.core.game3.profiles.rs.pokedex"] = {
  counts = function() return 0, 0 end,
  completedHoenn = function() return false end,
}
local Flags = require("src.core.game3.scripting.flags")
local Policy = require("src.ui.game3.rs.trainer_card_policy")
local C = require("src.core.game3.constants").of("sapphire")

local DEX = C:require("flags", "FLAG_SYS_POKEDEX_GET")
local BADGE1 = C:require("flags", "FLAG_BADGE01_GET")
check(DEX == 0x801, "pokeruby FLAG_SYS_POKEDEX_GET is 0x801")
check(BADGE1 == 0x807, "pokeruby FLAG_BADGE01_GET is 0x807")

local function owned(card)
  local list = {}
  for i = 1, 8 do if card.badges[i] then list[#list + 1] = i end end
  return table.concat(list, ",")
end

for _, version in ipairs({ "ruby", "sapphire" }) do
  local live = Flags.newStore()
  Flags.setFlag(live, nil, DEX, true)
  Flags.setFlag(live, nil, BADGE1, true)
  Flags.setFlag(live, nil, BADGE1 + 3, true)
  local saved = Flags.serialize(live)
  local session = { version = version, name = "MAY", flags = saved.flags, vars = saved.vars }
  local card = Policy.generate(session)
  check(card.hasPokedex == true, version .. " serialized session.flags: pokedex row shown")
  check(owned(card) == "1,4", version .. " serialized session.flags: badges 1,4 (" .. owned(card) .. ")")

  local store = Flags.newStore()
  Flags.setFlag(store, nil, DEX, true)
  for i = 0, 7 do Flags.setFlag(store, nil, BADGE1 + i, true) end
  package.loaded["src.core.game3.scripting.space"] = { store = store, getStore = function() return store end }
  local stale = { version = version, name = "MAY", flags = {} }
  card = Policy.generate(stale)
  check(card.hasPokedex == true, version .. " live script store: pokedex row shown")
  check(owned(card) == "1,2,3,4,5,6,7,8", version .. " live script store: all badges (" .. owned(card) .. ")")

  local withEmpty = { version = version, name = "MAY", flags = saved.flags, vars = saved.vars, store = { flags = {}, vars = {} } }
  card = Policy.generate(withEmpty)
  check(card.hasPokedex == true, version .. " empty session.store + live store: pokedex row shown")
  check(owned(card) == "1,2,3,4,5,6,7,8", version .. " empty session.store + live store: live badges (" .. owned(card) .. ")")
  package.loaded["src.core.game3.scripting.space"] = nil

  card = Policy.generate(withEmpty)
  check(card.hasPokedex == true, version .. " empty session.store, no live store: session.flags pokedex")
  check(owned(card) == "1,4", version .. " empty session.store, no live store: session.flags badges 1,4 (" .. owned(card) .. ")")
end

if failed > 0 then
  print(string.format("%d failure(s)", failed))
  os.exit(1)
end
print("all ok")

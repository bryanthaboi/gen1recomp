-- Progress gates from pret/pokefirered src/help_system.c. Numeric IDs are ROM submenu IDs.
local Flags = require("src.core.game3.scripting.flags")
local Rules = {}
local gates = {
  [1] = {
    [1] = true, -- HELP_PLAYING_FOR_FIRST_TIME
    [2] = true, -- HELP_WHAT_SHOULD_I_BE_DOING
    [3] = true, -- HELP_CANT_GET_OUT_OF_ROOM
    [5] = true, -- HELP_TALKED_TO_EVERYONE_NOW_WHAT
    [8] = true, -- HELP_OUT_OF_THINGS_TO_DO
    [34] = true, -- HELP_NOTHING_I_WANT_TO_KNOW
    [38] = true, -- HELP_WHATS_A_MON
    [41] = true, -- HELP_WHAT_DO_I_DO_IN_SAFARI
    [42] = true, -- HELP_WHAT_ARE_SAFARI_RULES
    [43] = true, -- HELP_WANT_TO_END_SAFARI
    [4] = "FLAG_VISITED_OAKS_LAB", -- HELP_CANT_FIND_PERSON_I_WANT
    [6] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_SOMEONE_BLOCKING_MY_WAY
    [10] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_WHAT_ARE_MY_ADVENTURE_BASICS
    [16] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_HOW_DO_I_PREPARE_FOR_BATTLE
    [19] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_WHAT_IS_STATUS_PROBLEM
    [22] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_RAN_OUT_OF_POTIONS
    [35] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_WHATS_POKEMON_CENTER
    [36] = "FLAG_WORLD_MAP_VIRIDIAN_CITY", -- HELP_WHATS_POKEMON_MART
    [7] = "FLAG_WORLD_MAP_VERMILION_CITY", -- HELP_I_CANT_GO_ON
    [11] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_HOW_ARE_ROADS_FORESTS_DIFFERENT
    [24] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_WHATS_A_TRAINER
    [9] = "FLAG_SYS_POKEMON_GET", -- HELP_WHAT_HAPPENED_TO_ITEM_I_GOT
    [14] = "FLAG_SYS_POKEMON_GET", -- HELP_WHEN_CAN_I_USE_ITEM
    [13] = "FLAG_SYS_POKEMON_GET", -- HELP_HOW_DO_I_PROGRESS
    [15] = "FLAG_SYS_POKEMON_GET", -- HELP_WHATS_A_BATTLE
    [17] = "FLAG_SYS_POKEMON_GET", -- HELP_WHAT_IS_A_MONS_VITALITY
    [18] = "FLAG_SYS_POKEMON_GET", -- HELP_MY_MONS_ARE_HURT
    [20] = "FLAG_SYS_POKEMON_GET", -- HELP_WHAT_HAPPENS_IF_ALL_MY_MONS_FAINT
    [26] = "FLAG_SYS_POKEMON_GET", -- HELP_WHERE_DO_MONS_APPEAR
    [29] = "FLAG_SYS_POKEMON_GET", -- HELP_WHAT_MOVES_SHOULD_I_USE
    [31] = "FLAG_SYS_POKEMON_GET", -- HELP_WANT_TO_MAKE_MON_STRONGER
    [37] = "FLAG_SYS_POKEMON_GET", -- HELP_WANT_TO_END_GAME
    [21] = "FLAG_SYS_POKEDEX_GET", -- HELP_CANT_CATCH_MONS
    [23] = "FLAG_SYS_POKEDEX_GET", -- HELP_CAN_I_BUY_POKEBALLS
    [12] = "FLAG_BADGE01_GET", -- HELP_HOW_ARE_CAVES_DIFFERENT
    [33] = "FLAG_BADGE01_GET", -- HELP_WHAT_DO_I_DO_IN_CAVE
    [25] = "FLAG_BADGE01_GET", -- HELP_HOW_DO_I_WIN_AGAINST_TRAINER
    [32] = "FLAG_BADGE01_GET", -- HELP_FOE_MONS_TOO_STRONG
    [27] = "FLAG_BADGE01_GET", -- HELP_WHAT_ARE_MOVES
    [30] = "FLAG_BADGE01_GET", -- HELP_WANT_TO_ADD_MORE_MOVES
    [28] = "hm", -- HELP_WHAT_ARE_HIDDEN_MOVES
    [40] = "hm", -- HELP_WHAT_DOES_HIDDEN_MOVE_DO
    [39] = "FLAG_GOT_FAME_CHECKER", -- HELP_WHAT_IS_THAT_PERSON_LIKE
    [44] = "FLAG_WORLD_MAP_PEWTER_CITY", -- HELP_WHAT_IS_A_GYM
  },
  [2] = {
    [6] = true, -- HELP_USING_BAG
    [10] = true, -- HELP_USING_PLAYER
    [11] = true, -- HELP_USING_SAVE
    [12] = true, -- HELP_USING_OPTION
    [19] = true, -- HELP_ENTERING_NAME
    [20] = true, -- HELP_USING_PC
    [21] = true, -- HELP_USING_BILLS_PC
    [22] = true, -- HELP_USING_WITHDRAW
    [23] = true, -- HELP_USING_DEPOSIT
    [24] = true, -- HELP_USING_MOVE
    [25] = true, -- HELP_MOVING_ITEMS
    [26] = true, -- HELP_USING_PLAYERS_PC
    [27] = true, -- HELP_USING_WITHDRAW_ITEM
    [28] = true, -- HELP_USING_DEPOSIT_ITEM
    [29] = true, -- HELP_USING_MAILBOX
    [31] = true, -- HELP_OPENING_MENU
    [36] = true, -- HELP_USING_BAG2
    [38] = true, -- HELP_USING_HOME_PC
    [39] = true, -- HELP_USING_ITEM_STORAGE
    [40] = true, -- HELP_USING_WITHDRAW_ITEM2
    [41] = true, -- HELP_USING_DEPOSIT_ITEM2
    [42] = true, -- HELP_USING_MAILBOX2
    [45] = true, -- HELP_USING_BALL
    [46] = true, -- HELP_USING_BAIT
    [47] = true, -- HELP_USING_ROCK
    [1] = "FLAG_SYS_POKEDEX_GET", -- HELP_USING_POKEDEX
    [30] = "FLAG_SYS_POKEDEX_GET", -- HELP_USING_PROF_OAKS_PC
    [37] = "FLAG_SYS_POKEDEX_GET", -- HELP_READING_POKEDEX
    [14] = "map", -- HELP_USING_TOWN_MAP
    [2] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_POKEMON
    [3] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_SUMMARY
    [5] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_ITEM
    [7] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_AN_ITEM
    [8] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_KEYITEM
    [9] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_POKEBALL
    [13] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_POTION
    [32] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_FIGHT
    [33] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_POKEMON2
    [35] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_SUMMARY2
    [43] = "FLAG_SYS_POKEMON_GET", -- HELP_USING_RUN
    [44] = "FLAG_SYS_POKEMON_GET", -- HELP_REGISTER_KEY_ITEM
    [4] = "caught", -- HELP_USING_SWITCH
    [34] = "caught", -- HELP_USING_SHIFT
    [15] = "FLAG_BADGE01_GET", -- HELP_USING_TM
    [16] = "hm", -- HELP_USING_HM
    [17] = "hm", -- HELP_USING_MOVE_OUTSIDE_OF_BATTLE
    [18] = "FLAG_GOT_BICYCLE", -- HELP_RIDING_BICYCLE
    [48] = "FLAG_SYS_GAME_CLEAR", -- HELP_USING_HALL_OF_FAME
  },
  [3] = {
    [14] = true, -- HELP_TERM_MONEY
    [17] = true, -- HELP_TERM_ID_NO
    [22] = true, -- HELP_TERM_ITEMS
    [23] = true, -- HELP_TERM_KEYITEMS
    [24] = true, -- HELP_TERM_POKEBALLS
    [25] = true, -- HELP_TERM_POKEDEX
    [26] = true, -- HELP_TERM_PLAY_TIME
    [27] = true, -- HELP_TERM_BADGES
    [28] = true, -- HELP_TERM_TEXT_SPEED
    [29] = true, -- HELP_TERM_BATTLE_SCENE
    [30] = true, -- HELP_TERM_BATTLE_STYLE
    [31] = true, -- HELP_TERM_SOUND
    [32] = true, -- HELP_TERM_BUTTON_MODE
    [33] = true, -- HELP_TERM_FRAME
    [34] = true, -- HELP_TERM_CANCEL
    [35] = true, -- HELP_TERM_TM
    [38] = true, -- HELP_TERM_EVOLUTION
    [1] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_HP
    [2] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_EXP
    [4] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_ATTACK
    [5] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_DEFENSE
    [6] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_SPATK
    [7] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_SPDEF
    [8] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_SPEED
    [9] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_LEVEL
    [10] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_TYPE
    [11] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_OT
    [12] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_ITEM
    [13] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_ABILITY
    [16] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_NATURE
    [19] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_POWER
    [20] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_ACCURACY
    [21] = "FLAG_SYS_POKEMON_GET", -- HELP_TERM_FNT
    [36] = "hm", -- HELP_TERM_HM
    [37] = "hm", -- HELP_TERM_HM_MOVE
    [3] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_TERM_MOVES
    [15] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_TERM_MOVE_TYPE
    [18] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_TERM_PP
    [39] = "FLAG_WORLD_MAP_VIRIDIAN_FOREST", -- HELP_TERM_STATUS_PROBLEM
  },
  [4] = {
    [5] = "FLAG_BADGE01_GET", -- HELP_GAME_FUNDAMENTALS_2
    [6] = "FLAG_BADGE02_GET", -- HELP_GAME_FUNDAMENTALS_3
  },
}

function Rules.flag(session, name)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store or session
  local id = Flags.IDS[name]
  if not id then return false end
  return Flags.getFlag(store, nil, id)
end

function Rules.enabled(topic, id, session)
  local gate = gates[topic] and gates[topic][id]
  if gate == nil then return topic >= 3 end
  if gate == true then return true end
  if gate == "hm" then
    for i=1,6 do if Rules.flag(session, "GOT_HM0"..i) then return true end end
    return Rules.flag(session, "HIDE_FOUR_ISLAND_ICEFALL_CAVE_1F_HM07")
  elseif gate == "map" then
    return session and session.bag and require("src.core.game3.bag").has(session.bag,361,1) or false
  elseif gate == "caught" then
    local Dex = require("src.core.game3.dex")
    return Dex.countCaught(session and (session.dex or session.pokedex), "kanto") > 1
  end
  return Rules.flag(session,gate)
end

return Rules

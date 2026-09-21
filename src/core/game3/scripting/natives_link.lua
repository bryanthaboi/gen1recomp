local Link = require("src.core.game3.link.init")
local Union = require("src.core.game3.link.union_room")
local LinkBattle = require("src.core.game3.link.battle")
local LinkTrade = require("src.core.game3.link.trade")
local Std = require("src.core.game3.scripting.stdscripts")

local NativesLink = {}

NativesLink.SPECIAL = {
  SetCableClubWarp = 0x01,
  DoCableClubWarp = 0x02,
  ReturnFromLinkRoom = 0x03,
  CleanupLinkRoomState = 0x04,
  ExitLinkRoom = 0x05,
  Script_ShowLinkTrainerCard = 0x2A,
  TryBattleLinkup = 0x1C,
  TryTradeLinkup = 0x1D,
  TryRecordMixLinkup = 0x1E,
  CloseLink = 0x1F,
  EnterColosseumPlayerSpot = 0x20,
  EnterTradeSeat = 0x21,
  StartWiredCableClubTrade = 0x22,
  CableClub_AskSaveTheGame = 0x23,
  HasEnoughMonsForDoubleBattle = 0x3D,
  Field_AskSaveTheGame = 0x5D,
  LoadPlayerBag = 0x14B,
  IsWirelessAdapterConnected = 0x16A,
  TryBecomeLinkLeader = 0x16B,
  TryJoinLinkGroup = 0x16C,
  RunUnionRoom = 0x16D,
  ShowWirelessCommunicationScreen = 0x16E,
  InitUnionRoom = 0x182,
  BufferUnionRoomPlayerName = 0x183,
  Script_ResetUnionRoomTrade = 0x1B3,
}

NativesLink.Link = Link
NativesLink.Union = Union
NativesLink.Battle = LinkBattle
NativesLink.Trade = LinkTrade

for name, id in pairs(NativesLink.SPECIAL) do
  if Std.SPECIAL[name] == nil then Std.SPECIAL[name] = id end
  if Std.SPECIAL_NAME_BY_ID[id] == nil then Std.SPECIAL_NAME_BY_ID[id] = name end
end

local S = NativesLink.SPECIAL

NativesLink.HANDLERS = {
  -- pokefirered/src/field_control_avatar.c:1173
  [S.SetCableClubWarp] = function(ctx)
    Link.setCableClubWarp(ctx)
    return false
  end,
  -- pokefirered/src/field_fadetransition.c:646
  [S.DoCableClubWarp] = function(ctx, adapters)
    return Link.doCableClubWarp(ctx, adapters)
  end,
  -- pokefirered/src/field_fadetransition.c:685
  [S.ReturnFromLinkRoom] = function(ctx, adapters)
    Link.returnFromLinkRoom(ctx, adapters)
    return false
  end,
  -- pokefirered/src/cable_club.c:809
  [S.CleanupLinkRoomState] = function(ctx, adapters)
    Link.cleanupLinkRoomState(ctx, adapters)
    return false
  end,
  -- pokefirered/src/cable_club.c:821
  [S.ExitLinkRoom] = function(ctx, adapters)
    Link.exitLinkRoom(ctx, adapters)
    return false
  end,
  -- pokefirered/src/cable_club.c:493
  [S.TryBattleLinkup] = function(ctx, adapters)
    return LinkBattle.tryBattleLinkup(ctx, adapters)
  end,
  -- pokefirered/src/cable_club.c:525
  [S.TryTradeLinkup] = function(ctx, adapters)
    return LinkTrade.tryTradeLinkup(ctx, adapters)
  end,
  -- pokefirered/src/cable_club.c:945
  [S.EnterTradeSeat] = function(ctx, adapters)
    return LinkTrade.enterTradeSeat(ctx, adapters)
  end,
  -- pokefirered/src/cable_club.c:958
  [S.StartWiredCableClubTrade] = function(ctx, adapters)
    return LinkTrade.startWiredCableClubTrade(ctx, adapters)
  end,
  -- pokefirered/src/cable_club.c:532
  [S.TryRecordMixLinkup] = function(ctx, adapters)
    return LinkBattle.tryRecordMixLinkup(ctx, adapters)
  end,
  -- pokefirered/src/script_pokemon_util.c:90
  [S.HasEnoughMonsForDoubleBattle] = function(ctx)
    return LinkBattle.hasEnoughMonsForDoubleBattle(ctx)
  end,
  -- pokefirered/src/link.c:419
  [S.CloseLink] = function()
    Link.closeLink("close_link")
    return false
  end,
  -- pokefirered/src/cable_club.c:964
  [S.EnterColosseumPlayerSpot] = function(ctx, adapters)
    return LinkBattle.enterColosseumPlayerSpot(ctx, adapters)
  end,
  -- pokefirered/src/cable_club.c:621
  [S.CableClub_AskSaveTheGame] = function(ctx, adapters)
    return Link.askSaveTheGame(ctx, adapters)
  end,
  -- pokefirered/src/start_menu.c:620
  [S.Field_AskSaveTheGame] = function(ctx, adapters)
    return Link.askSaveTheGame(ctx, adapters)
  end,
  -- pokefirered/src/load_save.c:208
  [S.LoadPlayerBag] = function()
    Link.loadPlayerBag()
    return false
  end,
  -- pokefirered/src/link.c:243
  [S.IsWirelessAdapterConnected] = function(ctx)
    return Link.isWirelessAdapterConnected(ctx)
  end,
  -- pokefirered/src/union_room.c:382
  [S.TryBecomeLinkLeader] = function(ctx, adapters)
    return Union.tryBecomeLinkLeader(ctx, adapters)
  end,
  -- pokefirered/src/union_room.c:1126
  [S.TryJoinLinkGroup] = function(ctx, adapters)
    return Union.tryJoinLinkGroup(ctx, adapters)
  end,
  -- pokefirered/src/union_room.c:2579
  [S.RunUnionRoom] = function(ctx, adapters)
    Union.run(ctx, adapters)
    return false, 0
  end,
  -- pokefirered/src/wireless_communication_status_screen.c:195
  [S.ShowWirelessCommunicationScreen] = function(ctx, adapters)
    return Link.showWirelessCommunicationScreen(ctx, adapters)
  end,
  -- pokefirered/src/union_room.c:3515
  [S.InitUnionRoom] = function(ctx)
    Union.init(ctx)
    return false, 0
  end,
  -- pokefirered/src/union_room.c:3606
  [S.BufferUnionRoomPlayerName] = function(ctx, adapters)
    return Union.bufferPlayerName(ctx, adapters)
  end,
  -- pokefirered/src/union_room.c:4595
  [S.Script_ResetUnionRoomTrade] = function()
    Union.resetTrade()
    return false, 0
  end,
  -- pokefirered/src/cable_club.c:980
  [S.Script_ShowLinkTrainerCard] = function(ctx, adapters)
    return Link.showLinkTrainerCard(ctx, adapters)
  end,
}

-- pokefirered/src/union_room.c:3606 natives_queries sorts after this module, so its
local okQ, Queries = pcall(require, "src.core.game3.scripting.natives_queries")
if okQ and type(Queries) == "table" and type(Queries.HANDLERS) == "table" then
  Queries.HANDLERS[S.BufferUnionRoomPlayerName] =
    NativesLink.HANDLERS[S.BufferUnionRoomPlayerName]
end

return NativesLink

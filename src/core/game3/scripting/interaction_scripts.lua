-- pret field_control_avatar.c:GetInteractedMetatileScript. Original MB values,
-- not translated COLL bytes: different pieces of furniture share collision.
local I={behaviors={}}
I.FLAVOR={
  {0x81,'Bookshelf'}, {0x82,'PokeMartShelf'}, {0x90,'Food'},
  {0xA1,'VideoGame'}, {0x97,'Computer'}, {0xA0,'ImpressiveMachine'},
  {0x93,'Blueprints'}, {0xA2,'Burglary'}, {0x86,'PlayerFacingTVScreen',true},
  {0x89,'Cabinet'}, {0x8A,'Kitchen'}, {0x8B,'Dresser'}, {0x8C,'Snacks'},
  {0x94,'Painting'}, {0x95,'PowerPlantMachine'}, {0x96,'Telephone'},
  {0x98,'AdvertisingPoster'}, {0x99,'TastyFood'}, {0x9A,'TrashBin'},
  {0x9B,'Cup'}, {0x9C,'PolishedWindow'}, {0x9D,'BeautifulSkyWindow'},
  {0x9E,'BlinkingLights'}, {0x9F,'NeatlyLinedUpTools'},
  {0x88,'PokemartSign',true}, {0x87,'PokecenterSign',true},
  {0x91,'Indigo_UltimateGoal'}, {0x92,'Indigo_HighestAuthority'},
}
-- src/field_control_avatar.c:538,:572-577
I.CODE={
  {0xA3,'TrainerTower_EventScript_ShowTime'},
  {0x8D,'CableClub_EventScript_ShowWirelessCommunicationScreen',true},
  {0x8F,'EventScript_Questionnaire'},
  {0x8E,'CableClub_EventScript_ShowBattleRecords',true},
}
local byBehavior={}
for _,row in ipairs(I.FLAVOR) do byBehavior[row[1]]={'EventScript_'..row[2],row[3]} end
for _,row in ipairs(I.CODE) do byBehavior[row[1]]={row[2],row[3]} end
function I.scriptFor(behavior,facing)
  if behavior==0x83 then return 'EventScript_PC' end
  if behavior==0x85 then return 'EventScript_WallTownMap' end
  local row=byBehavior[behavior]
  if not row or (row[2] and facing~='up' and facing~=2) then return nil end
  return row[1]
end
-- BG_EVENT_PLAYER_FACING_* uses a different order from DIR_*.
local directions={[1]=2,[2]=1,[3]=4,[4]=3}
function I.backgroundMatches(event,x,y,elevation,direction)
  if event.x~=x or event.y~=y then return false end
  if event.elevation and event.elevation~=0 and event.elevation~=elevation then return false end
  local wanted=directions[event.kind]
  return not wanted or wanted==direction
end
function I.install(pack)
  I.behaviors=pack and pack.behaviors or {}
end
return I

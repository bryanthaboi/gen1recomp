-- The save editor's whole mutable world.  Ops.lua is the only module allowed
-- to change the `save` sub-tree (and it always sets dirty + status together);
-- everything else here is view state -- which tab, which row, which page.

local State = {}

function State.new()
  return {
    -- loaded content
    data = nil,
    cat = nil,          -- sorted species / items / moves id lists (Catalog)
    events = nil,       -- scraped EVENT_* / MOD_* flag names (Catalog)
    save = nil,
    path = nil,
    validation = nil,   -- what the running game would quarantine, on a copy

    -- file state
    dirty = false,
    loadError = false,  -- true when the save file exists but failed to decode
    allowSave = true,   -- false while loadError, until a successful Reload
    _quitArmed = false,
    _openArmed = false,

    -- Which game this save belongs to, so the title bar can show the RED /
    -- BLUE chip and the launcher can hand the editor the right slot.  Set by
    -- App.load's opts; nil in a bare `love . --editor` run.
    version = nil,
    slotId = nil,
    modRoots = nil,
    -- Hosted inside the launcher process (Edit on a save row) rather than a
    -- standalone `--editor` window: Close returns to the launcher instead of
    -- quitting, and App calls onClose() to do it.
    embedded = false,
    onClose = nil,

    -- chrome
    tab = "party",      -- party|boxes|items|events|map|dex
    status = "",
    armed = nil,        -- id of the destructive button awaiting confirmation
    armedAt = nil,      -- when it was armed (Ops.ARM_SECONDS to commit)

    -- party / inspector
    selectedParty = 1,
    partyOffset = 0,       -- roster scroll position (#715)
    inspectorScroll = 0,   -- MonEditor body pixel scroll (#715)
    editingMon = nil,   -- reference into party or a box
    nicknameDraft = nil,    -- text being typed in the inspector's nickname field
    nicknameMon = nil,      -- the mon the draft belongs to (nil for none)
    -- species picker overlay: nil when closed, otherwise { query, offset }
    -- plus mode = "box-add" when it is adding to a box instead of changing a
    -- species (Ops.openBoxAddPicker).  Modal in the literal sense -- App
    -- shields every widget under it for the frame -- because Kit hit-tests
    -- without a z-order (#541).
    speciesPicker = nil,

    -- item picker overlay: nil when closed, otherwise
    -- { query, offset, dest = "bag"|"pc" }.  Same modal contract as
    -- speciesPicker above -- adding an item is now a full-screen picker
    -- rather than a card competing for height inside the Items tab.
    itemPicker = nil,

    -- boxes
    selectedBox = 1,
    selectedBoxSlot = 1,
    dockOffset = 0,     -- party dock scroll position (#715)

    -- items
    itemQuery = "",
    selectedItemId = nil,
    selectedBagId = nil,
    selectedPcId = nil,
    itemPickOffset = 0, -- scroll position in the ADD ITEM list (#595)
    bagOffset = 0,
    pcOffset = 0,
    itemsScroll = 0,    -- stacked-layout pixel scroll (#715)

    -- events
    eventsTab = "flags",
    eventFilter = "",
    eventsOffset = 0,

    -- dex
    dexSort = "dex",  -- how the DEX grid is ordered: "dex" (by number) | "name" (A-Z)
    dexOffset = 0,

    -- map
    mapId = nil,
    mapQuery = "",
    mapListOffset = 0,
    mapCamX = 0,
    mapCamY = 0,
    mapZoom = 2,
    mapClickCell = nil,
  }
end

function State.markDirty(s)
  s.dirty = true
end

return State

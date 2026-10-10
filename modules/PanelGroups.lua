local _, ns = ...
local L = ns.L

-- Sidebar groups that feature modules file their sections under. Shared by all features,
-- so the list and its order live here rather than in any one module.
---@type table<string, PanelGroup>
local PanelGroups = {
    COMBAT_MONITORING = { order = 1, title = L.PANEL_GROUP_COMBAT_MONITORING },
    RAID_LEADER = { order = 2, title = L.PANEL_GROUP_RAID_LEADER },
    VENOMOUS_ABYSS = { order = 3, title = L.PANEL_GROUP_VENOMOUS_ABYSS },
}
ns.PanelGroups = PanelGroups

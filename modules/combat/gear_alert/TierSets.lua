local _, ns = ...
local Internals = ns.Modules.Internals("GearAlert")

-- Current-season class tier item-set IDs. Not discovered at runtime: C_LootJournal lists
-- historical sets, and item setID alone cannot tell a season. Mythic+ season 18 is Midnight S2
-- (C_MythicPlus.GetCurrentSeason). Set IDs are Blizzard item-set records for that season.

local REQUIRED_PIECES = 4

---@class TierSetSeasonCatalog
---@field required integer
---@field setsByClass table<string, integer[]>

---@type table<integer, TierSetSeasonCatalog>
local CATALOG = {
    [18] = {
        required = REQUIRED_PIECES,
        setsByClass = {
            DEATHKNIGHT = { 2055 },
            DEMONHUNTER = { 2056 },
            DRUID = { 2057 },
            EVOKER = { 2058 },
            HUNTER = { 2059 },
            MAGE = { 2060 },
            MONK = { 2061 },
            PALADIN = { 2062 },
            PRIEST = { 2063 },
            ROGUE = { 2064 },
            SHAMAN = { 2065 },
            WARLOCK = { 2066 },
            WARRIOR = { 2067 },
        },
    },
}

Internals.REQUIRED_PIECES = REQUIRED_PIECES
Internals.Catalog = CATALOG

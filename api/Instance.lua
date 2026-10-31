local _, ns = ...

local Instance = {}
ns.Api.Instance = Instance

-- Mythic Keystone / Mythic (M0) dungeon difficulties.
local DIFFICULTY_MYTHIC_KEYSTONE = 8
local DIFFICULTY_MYTHIC_DUNGEON = 23
-- Primary raid difficulties (ENCOUNTER_START / GetInstanceInfo).
local DIFFICULTY_HEROIC_RAID = 15
local DIFFICULTY_MYTHIC_RAID = 16

Instance.DIFFICULTY_MYTHIC_KEYSTONE = DIFFICULTY_MYTHIC_KEYSTONE
Instance.DIFFICULTY_MYTHIC_DUNGEON = DIFFICULTY_MYTHIC_DUNGEON
Instance.DIFFICULTY_HEROIC_RAID = DIFFICULTY_HEROIC_RAID
Instance.DIFFICULTY_MYTHIC_RAID = DIFFICULTY_MYTHIC_RAID

---@class InstanceInfo
---@field name string
---@field instanceType string  "none"|"party"|"raid"|"arena"|"pvp"|"scenario"
---@field difficultyID number
---@field instanceID number

-- Instance map IDs for the current Encounter Journal tier (current expansion).
local currentRaidIds = nil
local currentDungeonIds = nil
-- Seasonal Mythic+ rotation: instance IDs and localized names from C_ChallengeMode + EJ.
local seasonalMythicIds = nil
local seasonalMythicNames = nil

local function ClearContentCache()
    currentRaidIds = nil
    currentDungeonIds = nil
end

local function ClearSeasonalCache()
    seasonalMythicIds = nil
    seasonalMythicNames = nil
end

---Fills `into` with instance map IDs from one EJ tier.
---@param tierIndex number
---@param isRaid boolean
---@param into table<number, boolean>
---@param namesToIds table<string, number>|nil  When set, also records name -> mapID for dungeon lookups.
local function CollectTierMapIds(tierIndex, isRaid, into, namesToIds)
    EJ_SelectTier(tierIndex)
    local index = 1
    while index < 100 do
        local journalID, name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceByIndex(index, isRaid)
        if not journalID then
            break
        end
        if type(mapID) == "number" and mapID > 0 then
            into[mapID] = true
            if namesToIds and type(name) == "string" then
                namesToIds[name] = mapID
            end
        end
        index = index + 1
    end
end

local function CollectCurrentTierMapIds(isRaid, into)
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_SelectTier) ~= "function" then
        return
    end
    if type(EJ_GetInstanceByIndex) ~= "function" then
        return
    end

    local numTiers = EJ_GetNumTiers()
    if type(numTiers) ~= "number" or numTiers < 1 then
        return
    end

    local previousTier = type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier() or nil
    CollectTierMapIds(numTiers, isRaid, into, nil)

    if previousTier then
        EJ_SelectTier(previousTier)
    end
end

local function EnsureContentCache()
    if currentRaidIds and currentDungeonIds then
        return
    end
    currentRaidIds = {}
    currentDungeonIds = {}
    CollectCurrentTierMapIds(true, currentRaidIds)
    CollectCurrentTierMapIds(false, currentDungeonIds)
end

---Resolves seasonal challenge-map names to instance IDs via the Encounter Journal.
---@param seasonalNames table<string, boolean>
---@param intoIds table<number, boolean>
local function ResolveSeasonalNamesViaJournal(seasonalNames, intoIds)
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_SelectTier) ~= "function" then
        return
    end
    if type(EJ_GetInstanceByIndex) ~= "function" then
        return
    end

    local numTiers = EJ_GetNumTiers()
    if type(numTiers) ~= "number" or numTiers < 1 then
        return
    end

    local previousTier = type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier() or nil
    local nameToId = {}
    for tier = 1, numTiers do
        CollectTierMapIds(tier, false, {}, nameToId)
    end
    if previousTier then
        EJ_SelectTier(previousTier)
    end

    for name in pairs(seasonalNames) do
        local mapID = nameToId[name]
        if mapID then
            intoIds[mapID] = true
        end
    end
end

local function EnsureSeasonalCache()
    if seasonalMythicIds and seasonalMythicNames then
        return
    end
    seasonalMythicIds = {}
    seasonalMythicNames = {}
    if not C_ChallengeMode or type(C_ChallengeMode.GetMapTable) ~= "function" then
        return
    end
    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" then
        return
    end
    for _, challengeMapID in ipairs(maps) do
        if C_ChallengeMode.GetMapUIInfo then
            local name, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
            if type(name) == "string" and name ~= "" then
                seasonalMythicNames[name] = true
            end
            -- mapID may be an instance ID on some clients; keep it when present.
            if type(mapID) == "number" and mapID > 0 then
                seasonalMythicIds[mapID] = true
            end
        end
    end
    ResolveSeasonalNamesViaJournal(seasonalMythicNames, seasonalMythicIds)
end

---Info for the instance the player is currently in.
---@return InstanceInfo
function Instance.GetInfo()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    return {
        name = name,
        instanceType = instanceType or "none",
        difficultyID = difficultyID or 0,
        instanceID = instanceID or 0,
    }
end

---Localized subzone name for the player's current indoor area, or "" if none.
---@return string
function Instance.GetSubZoneText()
    local text = GetSubZoneText()
    if type(text) ~= "string" then
        return ""
    end
    return text
end

---Whether a Mythic+ run timer is active in the current instance.
---@return boolean
function Instance.IsChallengeModeActive()
    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
        return C_ChallengeMode.IsChallengeModeActive() == true
    end
    return false
end

---Whether `instanceID` is a current-expansion raid (Encounter Journal current tier).
---@param instanceID number
---@return boolean
function Instance.IsCurrentExpansionRaid(instanceID)
    EnsureContentCache()
    return currentRaidIds[instanceID] == true
end

---Whether `instanceID` is a current-expansion dungeon (Encounter Journal current tier).
---@param instanceID number
---@return boolean
function Instance.IsCurrentExpansionDungeon(instanceID)
    EnsureContentCache()
    return currentDungeonIds[instanceID] == true
end

---Whether the instance is in the current Mythic+ seasonal dungeon rotation.
---@param instanceID number
---@param instanceName string|nil
---@return boolean
function Instance.IsSeasonalMythicDungeon(instanceID, instanceName)
    EnsureSeasonalCache()
    if seasonalMythicIds[instanceID] then
        return true
    end
    return type(instanceName) == "string" and seasonalMythicNames[instanceName] == true
end

---Whether the instance difficulty is Mythic (M0) or Mythic Keystone.
---@param difficultyID number
---@return boolean
function Instance.IsMythicDungeonDifficulty(difficultyID)
    return difficultyID == DIFFICULTY_MYTHIC_DUNGEON or difficultyID == DIFFICULTY_MYTHIC_KEYSTONE
end

---Rebuilds cached current-expansion and seasonal instance lists.
function Instance.RefreshCaches()
    ClearContentCache()
    ClearSeasonalCache()
    EnsureContentCache()
    EnsureSeasonalCache()
end

---Calls `callback` when the player enters the world (login, reload, zoning).
---@param callback fun()
function Instance.OnEnteringWorld(callback)
    ns.Api.GameEvents.Listen("PLAYER_ENTERING_WORLD", callback)
end

---Calls `callback` when the indoor subzone changes.
---@param callback fun()
function Instance.OnZoneChangedIndoors(callback)
    ns.Api.GameEvents.Listen("ZONE_CHANGED_INDOORS", callback)
end

---Calls `callback` when the player enters a new area (including instance zoning).
---@param callback fun()
function Instance.OnZoneChangedNewArea(callback)
    ns.Api.GameEvents.Listen("ZONE_CHANGED_NEW_AREA", callback)
end

---Calls `callback` when a Mythic+ run starts.
---@param callback fun()
function Instance.OnChallengeModeStart(callback)
    ns.Api.GameEvents.Listen("CHALLENGE_MODE_START", callback)
end

---Calls `callback` when a Mythic+ run completes.
---@param callback fun()
function Instance.OnChallengeModeCompleted(callback)
    ns.Api.GameEvents.Listen("CHALLENGE_MODE_COMPLETED", callback)
end

---Calls `callback` when a Mythic+ run is reset.
---@param callback fun()
function Instance.OnChallengeModeReset(callback)
    ns.Api.GameEvents.Listen("CHALLENGE_MODE_RESET", callback)
end

local _, ns = ...
local L = ns.L
local Util = ns.Util
local CombatLogApi = ns.Api.CombatLog
local Instance = ns.Api.Instance
local Timer = ns.Api.Timer

-- Re-check shortly after zoning; instance/EJ data can lag behind PLAYER_ENTERING_WORLD.
local ENTERING_WORLD_RETRY = 1
-- Match Assets.Colors.SUCCESS for chat feedback.
local CHAT_SUCCESS = "ff59cc66"

---@alias CombatLogLocations "RAIDS"|"DUNGEONS"|"ALL"

local LOCATION_RAIDS = "RAIDS"
local LOCATION_DUNGEONS = "DUNGEONS"
local LOCATION_ALL = "ALL"

---@class CombatLogModule: Module
local CombatLog = ns.Modules.New("CombatLog", {
    defaults = {
        enabled = false,
        ---@type CombatLogLocations
        locations = LOCATION_ALL,
    },
})

CombatLog.LOCATION_RAIDS = LOCATION_RAIDS
CombatLog.LOCATION_DUNGEONS = LOCATION_DUNGEONS
CombatLog.LOCATION_ALL = LOCATION_ALL

---@type CombatLogLocations[]
CombatLog.LOCATIONS = { LOCATION_ALL, LOCATION_RAIDS, LOCATION_DUNGEONS }

local monitoringStarted = false
local enteringWorldRetryGeneration = 0

---@param locations CombatLogLocations
---@return boolean
local function IsValidLocations(locations)
    return locations == LOCATION_RAIDS or locations == LOCATION_DUNGEONS or locations == LOCATION_ALL
end

---@return boolean
local function RaidsEnabled()
    local locations = CombatLog.db.locations
    return locations == LOCATION_ALL or locations == LOCATION_RAIDS
end

---@return boolean
local function DungeonsEnabled()
    local locations = CombatLog.db.locations
    return locations == LOCATION_ALL or locations == LOCATION_DUNGEONS
end

---@return boolean
local function IsEligibleRaid()
    if not RaidsEnabled() then
        return false
    end
    local info = Instance.GetInfo()
    if info.instanceType ~= "raid" then
        return false
    end
    return Instance.IsCurrentExpansionRaid(info.instanceID)
end

---@return boolean
local function IsEligibleMythicDungeon()
    if not DungeonsEnabled() then
        return false
    end
    local info = Instance.GetInfo()
    if info.instanceType ~= "party" then
        return false
    end
    -- Keystone difficulty is only available on seasonal M+ dungeons.
    if info.difficultyID == Instance.DIFFICULTY_MYTHIC_KEYSTONE then
        return true
    end
    if info.difficultyID ~= Instance.DIFFICULTY_MYTHIC_DUNGEON then
        return false
    end
    return Instance.IsCurrentExpansionDungeon(info.instanceID)
        or Instance.IsSeasonalMythicDungeon(info.instanceID, info.name)
end

---Whether the feature is on and the player is in a context that should keep logging on.
---@return boolean
local function IsEligibleContext()
    return CombatLog:IsEnabled() and (IsEligibleRaid() or IsEligibleMythicDungeon())
end

---Checks combat logging and turns it on when needed. Prints chat feedback only when enabling.
function CombatLog:EnsureLogging()
    if not IsEligibleContext() then
        return
    end

    local isLogging = CombatLogApi.IsLogging()
    if isLogging == true then
        return
    end
    -- Unknown (rate-limited): do not treat as disabled; deferred PEW retry may resolve it.
    if isLogging == nil then
        return
    end

    local result = CombatLogApi.SetLogging(true)
    if result == true then
        Util.Print("|c" .. CHAT_SUCCESS .. L.COMBAT_LOG_LOGGING_ENABLED .. "|r")
    end
end

---Starts or refreshes auto-enable from the current instance context.
function CombatLog:UpdateMonitoring()
    self:EnsureLogging()
end

---@return boolean
function CombatLog:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function CombatLog:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    self:UpdateMonitoring()
end

---@return CombatLogLocations
function CombatLog:GetLocations()
    local locations = self.db.locations
    if IsValidLocations(locations) then
        return locations
    end
    return LOCATION_ALL
end

---@param locations CombatLogLocations
function CombatLog:SetLocations(locations)
    if not IsValidLocations(locations) or self.db.locations == locations then
        return
    end
    self.db.locations = locations
    self:UpdateMonitoring()
end

local function OnEnteringWorld()
    Instance.RefreshCaches()
    CombatLog:UpdateMonitoring()
    -- One deferred retry for late instance/EJ data after login, reload, or zoning.
    enteringWorldRetryGeneration = enteringWorldRetryGeneration + 1
    local generation = enteringWorldRetryGeneration
    Timer.After(ENTERING_WORLD_RETRY, function()
        if generation ~= enteringWorldRetryGeneration then
            return
        end
        Instance.RefreshCaches()
        CombatLog:UpdateMonitoring()
    end)
end

---Registers game events and evaluates the initial monitoring state. Called from OnEnable.
function CombatLog:StartMonitoring()
    if monitoringStarted then
        self:UpdateMonitoring()
        return
    end
    monitoringStarted = true

    Instance.OnEnteringWorld(OnEnteringWorld)

    Instance.RefreshCaches()
    self:UpdateMonitoring()
end

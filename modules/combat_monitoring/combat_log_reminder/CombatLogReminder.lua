local _, ns = ...
local L = ns.L
local Util = ns.Util
local CombatLog = ns.Api.CombatLog
local Encounter = ns.Api.Encounter
local Instance = ns.Api.Instance
local Timer = ns.Api.Timer

local SCALE_MIN = 0.5
local SCALE_MAX = 2.0
local SCALE_STEP = 0.05
local POLL_INTERVAL = 5
-- Re-check shortly after zoning; instance/EJ data can lag behind PLAYER_ENTERING_WORLD.
local ENTERING_WORLD_RETRY = 1
-- Match Assets.Colors.SUCCESS / ERROR for click feedback in chat.
local CHAT_SUCCESS = "ff59cc66"
local CHAT_ERROR = "ffe5484d"

---@class CombatLogReminderPosition
---@field point string
---@field relativePoint string
---@field x number
---@field y number

---@class CombatLogReminder: Module
---@field OnDisplayChanged fun(self: CombatLogReminder)|nil  Defined by the UI file; called when visibility inputs change.
local CombatLogReminder = ns.Modules.New("CombatLogReminder", {
    defaults = {
        enabled = false,
        remindRaids = true,
        remindMythicDungeons = true,
        scale = 1,
        ---@type CombatLogReminderPosition
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 180 },
    },
})

CombatLogReminder.SCALE_MIN = SCALE_MIN
CombatLogReminder.SCALE_MAX = SCALE_MAX
CombatLogReminder.SCALE_STEP = SCALE_STEP

-- Last definitive LoggingCombat() result; nil until the first successful query.
local knownLogging = nil
-- Active LoggingCombat poll; nil when not in an eligible reminder context.
local pollTicker = nil
local monitoringStarted = false
local enteringWorldRetryGeneration = 0

---@param position CombatLogReminderPosition
local function IsValidPosition(position)
    return type(position) == "table"
        and type(position.point) == "string"
        and type(position.relativePoint) == "string"
        and type(position.x) == "number"
        and type(position.y) == "number"
end

local function NotifyDisplayChanged()
    if CombatLogReminder.OnDisplayChanged then
        CombatLogReminder:OnDisplayChanged()
    end
end

local function ClampScale(scale)
    local rounded = math.floor(scale / SCALE_STEP + 0.5) * SCALE_STEP
    return math.min(math.max(rounded, SCALE_MIN), SCALE_MAX)
end

---Queries LoggingCombat; keeps the last known boolean across rate limits.
local function RefreshLoggingState()
    local result = CombatLog.IsLogging()
    if result ~= nil then
        knownLogging = result
    end
end

---@return boolean
local function IsEligibleRaid()
    if not CombatLogReminder.db.remindRaids then
        return false
    end
    local info = Instance.GetInfo()
    if info.instanceType ~= "raid" then
        return false
    end
    if not Instance.IsCurrentExpansionRaid(info.instanceID) then
        return false
    end
    if Encounter.IsInProgress() then
        return false
    end
    return true
end

---@return boolean
local function IsEligibleMythicDungeon()
    if not CombatLogReminder.db.remindMythicDungeons then
        return false
    end
    local info = Instance.GetInfo()
    if info.instanceType ~= "party" then
        return false
    end
    if Instance.IsChallengeModeActive() then
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

---Whether the feature is on and the player is in a context that may need the reminder.
---@return boolean
local function IsReminderContext()
    return CombatLogReminder:IsEnabled() and (IsEligibleRaid() or IsEligibleMythicDungeon())
end

local function StopPolling()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

local function StartPolling()
    if pollTicker then
        return
    end
    -- Immediate check so the warning does not wait a full poll interval.
    RefreshLoggingState()
    pollTicker = Timer.NewTicker(POLL_INTERVAL, function()
        RefreshLoggingState()
        NotifyDisplayChanged()
    end)
end

---Starts or stops LoggingCombat polling from the current reminder context.
function CombatLogReminder:UpdateMonitoring()
    if IsReminderContext() then
        StartPolling()
    else
        StopPolling()
    end
    NotifyDisplayChanged()
end

---@return boolean
function CombatLogReminder:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function CombatLogReminder:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    self:UpdateMonitoring()
end

---@return boolean
function CombatLogReminder:GetRemindRaids()
    return self.db.remindRaids == true
end

---@param enabled boolean
function CombatLogReminder:SetRemindRaids(enabled)
    enabled = enabled == true
    if self.db.remindRaids == enabled then
        return
    end
    self.db.remindRaids = enabled
    self:UpdateMonitoring()
end

---@return boolean
function CombatLogReminder:GetRemindMythicDungeons()
    return self.db.remindMythicDungeons == true
end

---@param enabled boolean
function CombatLogReminder:SetRemindMythicDungeons(enabled)
    enabled = enabled == true
    if self.db.remindMythicDungeons == enabled then
        return
    end
    self.db.remindMythicDungeons = enabled
    self:UpdateMonitoring()
end

---@return number
function CombatLogReminder:GetScale()
    return ClampScale(self.db.scale)
end

---@param scale number
function CombatLogReminder:SetScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.scale = ClampScale(scale)
end

---@return CombatLogReminderPosition
function CombatLogReminder:GetPosition()
    return self.db.position
end

---@param position CombatLogReminderPosition
function CombatLogReminder:SetPosition(position)
    assert(IsValidPosition(position), "Bad window position")
    local saved = self.db.position
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---Last known combat-logging state: true/false, or nil if never successfully queried.
---@return boolean|nil
function CombatLogReminder:GetKnownLogging()
    return knownLogging
end

---Whether the LoggingCombat poll ticker is currently running.
---@return boolean
function CombatLogReminder:IsPolling()
    return pollTicker ~= nil
end

---Attempts to enable combat logging. Keeps the last known state across rate limits.
---Prints chat feedback; call only from a user click, not from polling.
---@return boolean succeeded  True only when the API confirms logging is on.
function CombatLogReminder:EnableLogging()
    local result = CombatLog.SetLogging(true)
    if result ~= nil then
        knownLogging = result
    end
    if result == true then
        Util.Print("|c" .. CHAT_SUCCESS .. L.COMBAT_LOG_REMINDER_LOGGING_ENABLED .. "|r")
    elseif result == nil then
        Util.Print("|c" .. CHAT_ERROR .. L.COMBAT_LOG_REMINDER_LOGGING_ENABLE_FAILED .. "|r")
    end
    NotifyDisplayChanged()
    return result == true
end

---Whether the warning window should be shown.
---@return boolean
function CombatLogReminder:ShouldRemind()
    if not self:IsEnabled() then
        return false
    end
    -- Unknown logging state must not be treated as disabled.
    if knownLogging ~= false then
        return false
    end
    return IsEligibleRaid() or IsEligibleMythicDungeon()
end

local function OnContextMaybeChanged()
    CombatLogReminder:UpdateMonitoring()
end

local function OnEnteringWorld()
    Instance.RefreshCaches()
    CombatLogReminder:UpdateMonitoring()
    -- One deferred retry for late instance/EJ data after login, reload, or zoning.
    enteringWorldRetryGeneration = enteringWorldRetryGeneration + 1
    local generation = enteringWorldRetryGeneration
    Timer.After(ENTERING_WORLD_RETRY, function()
        if generation ~= enteringWorldRetryGeneration then
            return
        end
        Instance.RefreshCaches()
        CombatLogReminder:UpdateMonitoring()
    end)
end

---Registers game events and evaluates the initial monitoring state. Called from OnEnable.
function CombatLogReminder:StartMonitoring()
    if monitoringStarted then
        self:UpdateMonitoring()
        return
    end
    monitoringStarted = true

    Instance.OnEnteringWorld(OnEnteringWorld)
    Encounter.OnStart(OnContextMaybeChanged)
    Encounter.OnEnd(OnContextMaybeChanged)
    Instance.OnChallengeModeStart(OnContextMaybeChanged)
    Instance.OnChallengeModeCompleted(OnContextMaybeChanged)
    Instance.OnChallengeModeReset(OnContextMaybeChanged)

    Instance.RefreshCaches()
    self:UpdateMonitoring()
end

function CombatLogReminder:OnInit()
    self.db.scale = ClampScale(self.db.scale)
end

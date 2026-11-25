local _, ns = ...
local Internals = ns.Modules.Internals("GearAlert")
local Position = ns.Position
local Equipment = ns.Api.Equipment
local Player = ns.Api.Player
local Instance = ns.Api.Instance
local Timer = ns.Api.Timer
local L = ns.L

-- Compact equipment-warning card; sits above the combat timer's default center offset.
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 }
local SCAN_DELAY = 1
local ITEM_RETRY_DELAY = 0.5
local ITEM_RETRY_LIMIT = 5

---@class GearAlertPosition
---@field point string
---@field relativePoint string
---@field x number
---@field y number

---@class GearAlertPayload
---@field type string
---@field equipped number|nil
---@field required number|nil
---@field missingSlotNames string[]|nil  Localized armor slots without a current-season set piece.
---@field itemLevel number|nil
---@field averageItemLevel number|nil
---@field itemLink string|nil  Equipped item link for low-level rows.
---@field slot integer|nil
---@field slotName string|nil  Localized inventory slot label.

---@class GearAlert: Module
local GearAlert = ns.Modules.New("GearAlert", {
    defaults = {
        -- When true, the four-piece set subfeature is on.
        fourPieceCheckEnabled = true,
        -- When true, the low-level item subfeature is on.
        lowLevelCheckEnabled = true,
        ---@type GearAlertPosition
        position = {
            point = DEFAULT_POSITION.point,
            relativePoint = DEFAULT_POSITION.relativePoint,
            x = DEFAULT_POSITION.x,
            y = DEFAULT_POSITION.y,
        },
        -- Character-keyed four-piece history. Account SavedVariables; not shared across characters.
        ---@type table<string, { tierSetHistory: table<integer, { hadFourPiece: boolean }> }>
        characters = {},
    },
})

GearAlert.SCAN_DELAY = SCAN_DELAY

local monitoringStarted = false
local scanToken = 0
local pendingScan
local pendingRetry
local lastState
local wantAlert = false
---@type fun(text: string)|nil
local statusListener
---@type fun(findings: GearAlertPayload[]|nil)|nil
local findingListener

---Factory default anchor. A new table every call so callers cannot mutate saved data.
---@return GearAlertPosition
function GearAlert.DefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

---@return boolean
function GearAlert:IsFourPieceCheckEnabled()
    return self.db.fourPieceCheckEnabled == true
end

---@param enabled boolean
function GearAlert:SetFourPieceCheckEnabled(enabled)
    self.db.fourPieceCheckEnabled = enabled == true
end

---@return boolean
function GearAlert:IsLowLevelCheckEnabled()
    return self.db.lowLevelCheckEnabled == true
end

---@param enabled boolean
function GearAlert:SetLowLevelCheckEnabled(enabled)
    self.db.lowLevelCheckEnabled = enabled == true
end

---@return GearAlertPosition
function GearAlert:GetPosition()
    return self.db.position
end

---@param position GearAlertPosition
function GearAlert:SetPosition(position)
    assert(Position.IsValid(position), "Bad window position")
    local saved = self.db.position
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return string|nil
local function CharacterKey()
    return Player.GetGUID() or Player.GetFullName()
end

---@return table|nil
function GearAlert:GetTierSetHistory()
    local key = CharacterKey()
    if not key then
        return nil
    end
    if type(self.db.characters) ~= "table" then
        self.db.characters = {}
    end
    local entry = self.db.characters[key]
    if type(entry) ~= "table" then
        entry = { tierSetHistory = {} }
        self.db.characters[key] = entry
    end
    if type(entry.tierSetHistory) ~= "table" then
        entry.tierSetHistory = {}
    end
    return entry.tierSetHistory
end

---@param state TierSetState|nil
---@return boolean
function GearAlert:HasFourPieceHistory(state)
    state = state or lastState
    if not state or type(state.seasonID) ~= "number" then
        state = { seasonID = Equipment.GetCurrentSeasonID() }
    end
    return Internals.HistoryHadFourPiece(self:GetTierSetHistory(), state)
end

---@param state TierSetState|nil
---@return string
function GearAlert:FormatMenuStatus(state)
    if self:HasFourPieceHistory(state) then
        return L.GEAR_ALERT_HISTORY_DONE
    end
    return L.GEAR_ALERT_HISTORY_NONE
end

function GearAlert:GetMenuStatusText()
    return self:FormatMenuStatus(lastState)
end

---@param callback fun(text: string)|nil
function GearAlert:SetStatusListener(callback)
    statusListener = callback
end

---@param callback fun(findings: GearAlertPayload[]|nil)|nil
function GearAlert:SetFindingListener(callback)
    findingListener = callback
end

local function NotifyStatus()
    if statusListener then
        statusListener(GearAlert:GetMenuStatusText())
    end
end

---@return TierSetState
function GearAlert:GetCurrentState()
    return Internals.Evaluate(Internals.CollectScan())
end

---Current-expansion raid, or a Mythic / Mythic+ dungeon of the current expansion.
---@return boolean
local function IsEligibleInstance()
    local info = Instance.GetInfo()
    if info.instanceType == "raid" then
        return Instance.IsCurrentExpansionRaid(info.instanceID)
    end
    if info.instanceType ~= "party" then
        return false
    end
    if not Instance.IsMythicDungeonDifficulty(info.difficultyID) then
        return false
    end
    return Instance.IsCurrentExpansionDungeon(info.instanceID)
end

---@param list table|nil
---@return boolean
local function ListHasPending(list)
    if type(list) ~= "table" then
        return false
    end
    for _, entry in ipairs(list) do
        if entry.status == "pending" then
            return true
        end
    end
    return false
end

---@return boolean
local function ScanHasPending(scan)
    if type(scan) ~= "table" then
        return false
    end
    return ListHasPending(scan.slots) or ListHasPending(scan.bags)
end

local function RequestPendingItems(scan)
    if type(scan) ~= "table" then
        return
    end
    local function Request(list)
        if type(list) ~= "table" then
            return
        end
        for _, entry in ipairs(list) do
            if entry.status == "pending" then
                Equipment.RequestItem(entry.itemID)
            end
        end
    end
    Request(scan.slots)
    Request(scan.bags)
end

local function CancelRetry()
    if pendingRetry then
        pendingRetry:Cancel()
        pendingRetry = nil
    end
end

---@param token integer
---@param retries integer
local function ApplyScan(token, retries)
    if token ~= scanToken then
        return
    end
    local scan = Internals.CollectScan()
    local gearScan = Internals.CollectGearScan()
    local state = Internals.Evaluate(scan)
    lastState = state
    Internals.RecordHistory(GearAlert:GetTierSetHistory(), state)
    NotifyStatus()
    if (ScanHasPending(scan) or ScanHasPending(gearScan)) and retries < ITEM_RETRY_LIMIT then
        RequestPendingItems(scan)
        RequestPendingItems(gearScan)
        pendingRetry = Timer.NewTimer(ITEM_RETRY_DELAY, function()
            pendingRetry = nil
            ApplyScan(token, retries + 1)
        end)
        return
    end
    CancelRetry()
    if not wantAlert then
        return
    end
    wantAlert = false
    if not findingListener then
        return
    end
    Instance.RefreshCaches()
    local findings = {}
    if GearAlert:IsLowLevelCheckEnabled() then
        local lowLevel = Internals.CheckLowLevel(Internals.EvaluateLowLevel(gearScan))
        for index = 1, #lowLevel do
            findings[#findings + 1] = lowLevel[index]
        end
    end
    if GearAlert:IsFourPieceCheckEnabled() then
        local missing = Internals.CheckMissing(GearAlert:GetTierSetHistory(), state)
        if missing then
            findings[#findings + 1] = missing
        end
    end
    if #findings == 0 or not IsEligibleInstance() then
        findings = nil
    end
    findingListener(findings)
end

local function CancelPendingScan()
    if pendingScan then
        pendingScan:Cancel()
        pendingScan = nil
    end
end

---@param alert boolean|nil
local function ScheduleScan(alert)
    if alert then
        wantAlert = true
    end
    scanToken = scanToken + 1
    CancelPendingScan()
    CancelRetry()
    local token = scanToken
    pendingScan = Timer.NewTimer(SCAN_DELAY, function()
        pendingScan = nil
        if token ~= scanToken then
            return
        end
        ApplyScan(token, 0)
    end)
end

function GearAlert:StartMonitoring()
    if monitoringStarted then
        return
    end
    monitoringStarted = true
    Equipment.OnChanged(function()
        ScheduleScan()
    end)
    Player.OnChanged(function()
        ScheduleScan()
    end)
    Instance.OnEnteringWorld(function()
        Instance.RefreshCaches()
        ScheduleScan(true)
    end)
    Equipment.OnItemInfoReceived(function()
        if pendingRetry then
            CancelRetry()
            ApplyScan(scanToken, 0)
        end
    end)
end

function GearAlert:OnInit()
    self.db.fourPieceCheckEnabled = self.db.fourPieceCheckEnabled ~= false
    self.db.lowLevelCheckEnabled = self.db.lowLevelCheckEnabled ~= false
    if not Position.IsValid(self.db.position) then
        self.db.position = GearAlert.DefaultPosition()
    end
    if type(self.db.characters) ~= "table" then
        self.db.characters = {}
    end
end

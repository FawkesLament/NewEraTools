local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Labels = Internals.InterruptChainLabels

local TwinFangs = ns.Modules.Get("TwinFangs")

---@param snapshot TwinFangsInterruptStatus
---@return integer[]
local function AssignmentIndices(snapshot)
    local first = snapshot.index
    local last = snapshot.indexEnd or snapshot.index
    local indices = {}
    for index = first, last do
        if index >= 1 then
            indices[#indices + 1] = index
        end
    end
    return indices
end

---@param name string|nil
---@return string|nil
local function ShortName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name:match("^([^-]+)") or name
end

---@param snapshot TwinFangsInterruptStatus
---@return string|nil
local function AssigneeName(snapshot)
    local chain = TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
    local region = chain and chain[snapshot.region]
    if type(region) ~= "table" then
        return nil
    end
    local currentIndex = snapshot.interruptCount + 1
    local players = region.players
    if type(players) == "table" and players[currentIndex] then
        return ShortName(players[currentIndex].name)
    end
    local backup = region.backup
    if currentIndex > snapshot.chainLength then
        if type(backup) == "table" then
            return ShortName(backup.name)
        end
        if type(backup) == "string" then
            return ShortName(backup)
        end
    end
    return nil
end

---@param snapshot TwinFangsInterruptStatus|nil
---@param isBackup boolean|nil
---@return InterruptChainHUDState|nil
local function HudState(snapshot, isBackup)
    if not snapshot then
        return nil
    end
    local total = snapshot.chainLength
    if total > 6 then
        total = 6
    elseif total < 1 then
        total = 1
    end
    local completed = snapshot.interruptCount
    if completed < 0 then
        completed = 0
    elseif completed > total then
        completed = total
    end
    local myIndices
    if isBackup then
        if snapshot.interruptCount >= snapshot.chainLength then
            completed = math.max(total - 1, 0)
            myIndices = { total }
        else
            myIndices = {}
        end
    else
        myIndices = AssignmentIndices(snapshot)
    end
    return {
        total = total,
        completed = completed,
        myIndices = myIndices,
        label = isBackup and L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP or Labels.RegionLabel(snapshot.region),
        currentAssignee = AssigneeName(snapshot),
        theme = Labels.RegionTheme(snapshot.region),
    }
end

local InterruptRotationTracker = ns.InterruptRotationTracker.Bind({
    layoutId = "TwinFangs:interrupt",
    name = ns.ADDON_NAME .. "TwinFangsInterruptRotationTracker",
    backupName = ns.ADDON_NAME .. "TwinFangsInterruptRotationTrackerBackup",
    label = L.TWIN_FANGS_INTERRUPT_STATUS_TITLE,
    -- Shared Common UI element. Combat visibility is assignment-gated.
    global = true,
    isEnabled = function()
        return true
    end,
    getPosition = function()
        return TwinFangs:GetInterruptRotationTrackerPosition()
    end,
    setPosition = function(position)
        TwinFangs:SetInterruptRotationTrackerPosition(position)
    end,
    getDefaultPosition = function()
        return ns.InterruptRotationTrackerAnchor.DefaultPosition()
    end,
    previewState = function()
        local state = HudState(TwinFangs:GetInterruptStatusPreview())
        local name, classFile = ns.InterruptRotationTracker.PreviewAssignee()
        state.currentAssignee = name
        state.currentAssigneeClass = classFile
        return state
    end,
    getState = function()
        return HudState(TwinFangs:GetInterruptStatus())
    end,
    getBackupState = function()
        return HudState(TwinFangs:GetBackupInterruptStatus(), true)
    end,
})
Internals.InterruptRotationTrackerUI = InterruptRotationTracker

function TwinFangs:OnInterruptStatusChanged()
    InterruptRotationTracker.Update()
end

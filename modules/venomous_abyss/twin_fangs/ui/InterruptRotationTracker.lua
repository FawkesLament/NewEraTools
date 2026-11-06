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
        indices[#indices + 1] = index
    end
    return indices
end

---@param snapshot TwinFangsInterruptStatus|nil
---@param isBackup boolean|nil
---@return StatusHUDState|nil
local function HudState(snapshot, isBackup)
    if not snapshot then
        return nil
    end
    local region = Labels.RegionLabel(snapshot.region)
    local title = region
    if not isBackup then
        title = L.TWIN_FANGS_INTERRUPT_STATUS_REGION_ROLE:format(region, L.TWIN_FANGS_INTERRUPT_STATUS_PRIMARY)
    end
    local detail
    if isBackup then
        detail = L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP
    else
        detail = ns.InterruptRotationTracker.FormatTask(AssignmentIndices(snapshot))
    end
    return {
        title = title,
        text = L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(snapshot.interruptCount + 1),
        detail = detail,
        progress = snapshot.interruptCount + 1,
        maxProgress = snapshot.chainLength,
        severity = ns.StatusHUD.SEVERITY_NORMAL,
    }
end

local InterruptRotationTracker = ns.InterruptRotationTracker.Bind({
    layoutId = "TwinFangs:interrupt",
    name = ns.ADDON_NAME .. "TwinFangsInterruptRotationTracker",
    backupName = ns.ADDON_NAME .. "TwinFangsInterruptRotationTrackerBackup",
    label = L.TWIN_FANGS_INTERRUPT_STATUS_TITLE,
    tone = ns.StatusHUD.TONE_EMPHASIS,
    backupTone = ns.StatusHUD.TONE_STANDBY,
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
        return HudState(TwinFangs:GetInterruptStatusPreview())
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

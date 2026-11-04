local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local PREVIEW_INDEX = 3
local PREVIEW_ROUND = 1
local PREVIEW_CHAIN_LENGTH = 6

---@param snapshot CoiledAltarInterruptStatus|nil
---@return StatusHUDState|nil
local function HudState(snapshot)
    if not snapshot then
        return nil
    end
    local title = L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE
    if snapshot.chainId == Internals.InterruptAssignments.RANGED then
        title = L.COILED_ALTAR_INTERRUPT_CHAIN_RANGED
    end
    local detail
    if snapshot.indexEnd and snapshot.indexEnd > snapshot.index then
        detail = L.COILED_ALTAR_INTERRUPT_STATUS_TASK_RANGE:format(snapshot.index, snapshot.indexEnd)
    else
        detail = L.COILED_ALTAR_INTERRUPT_STATUS_TASK:format(snapshot.index)
    end
    local text = L.COILED_ALTAR_INTERRUPT_STATUS_PENDING
    local progress = 0
    if not snapshot.pending then
        text = L.COILED_ALTAR_INTERRUPT_STATUS_ROUND:format(snapshot.kicks + 1)
        progress = snapshot.kicks + 1
    end
    return {
        title = title,
        text = text,
        detail = detail,
        progress = progress,
        maxProgress = snapshot.chainLength,
        severity = ns.StatusHUD.SEVERITY_NORMAL,
    }
end

---@return StatusHUDState
local function PreviewState()
    return HudState({
        chainId = Internals.InterruptAssignments.MELEE,
        indices = { PREVIEW_INDEX },
        index = PREVIEW_INDEX,
        indexEnd = PREVIEW_INDEX,
        kicks = PREVIEW_ROUND - 1,
        chainLength = PREVIEW_CHAIN_LENGTH,
        casting = false,
    })
end

local InterruptRotationTracker = ns.InterruptRotationTracker.Bind({
    layoutId = "CoiledAltar:interrupt",
    name = ns.ADDON_NAME .. "CoiledAltarInterruptRotationTracker",
    backupName = ns.ADDON_NAME .. "CoiledAltarInterruptRotationTrackerBackup",
    label = L.COILED_ALTAR_INTERRUPT_STATUS_TITLE,
    tone = ns.StatusHUD.TONE_EMPHASIS,
    isEnabled = function()
        return CoiledAltar:IsMechanicReminderEnabled() and CoiledAltar:IsInterruptReminderEnabled()
    end,
    getPosition = function()
        return CoiledAltar:GetInterruptRotationTrackerPosition()
    end,
    setPosition = function(position)
        CoiledAltar:SetInterruptRotationTrackerPosition(position)
    end,
    getDefaultPosition = function()
        return ns.InterruptRotationTrackerAnchor.DefaultPosition()
    end,
    previewState = PreviewState,
    getState = function()
        if not CoiledAltar:IsMechanicReminderEnabled() or not CoiledAltar:IsInterruptReminderEnabled() then
            return nil
        end
        return HudState(CoiledAltar:GetInterruptStatus())
    end,
    getBackupState = function()
        return nil
    end,
})
Internals.InterruptRotationTrackerUI = InterruptRotationTracker

function CoiledAltar:OnInterruptStateChanged()
    InterruptRotationTracker.Update()
end

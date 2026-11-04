local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local PREVIEW_INDEX = 3
local PREVIEW_ROUND = 1
local PREVIEW_CHAIN_LENGTH = 6

---@return StatusHUDState
local function PreviewState()
    return {
        title = L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE,
        text = L.COILED_ALTAR_INTERRUPT_STATUS_ROUND:format(PREVIEW_ROUND),
        detail = L.COILED_ALTAR_INTERRUPT_STATUS_TASK:format(PREVIEW_INDEX),
        progress = PREVIEW_ROUND,
        maxProgress = PREVIEW_CHAIN_LENGTH,
        severity = ns.StatusHUD.SEVERITY_NORMAL,
    }
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
        return nil
    end,
    getBackupState = function()
        return nil
    end,
})
Internals.InterruptRotationTrackerUI = InterruptRotationTracker

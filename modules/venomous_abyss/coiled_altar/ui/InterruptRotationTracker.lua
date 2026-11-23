local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local PREVIEW_INDEX = 3
local PREVIEW_ROUND = 1
local PREVIEW_CHAIN_LENGTH = 6

---@param snapshot CoiledAltarInterruptStatus|nil
---@return InterruptChainHUDState|nil
local function HudState(snapshot)
    if not snapshot then
        return nil
    end
    local total = snapshot.chainLength
    if total > 6 then
        total = 6
    elseif total < 1 then
        total = 1
    end
    local completed = snapshot.kicks or 0
    if snapshot.pending then
        completed = 0
    elseif completed > total then
        completed = total
    end
    return {
        total = total,
        completed = completed,
        myIndices = snapshot.indices or { snapshot.index },
        label = L.COILED_ALTAR_INTERRUPT_STATUS_TITLE,
    }
end

---@return InterruptChainHUDState
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
    isEnabled = function()
        return CoiledAltar:IsInterruptReminderEnabled()
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
        if not CoiledAltar:IsInterruptReminderEnabled() then
            return nil
        end
        return HudState(CoiledAltar:GetInterruptStatus())
    end,
    getBackupState = function()
        return nil
    end,
})
Internals.InterruptRotationTrackerUI = InterruptRotationTracker

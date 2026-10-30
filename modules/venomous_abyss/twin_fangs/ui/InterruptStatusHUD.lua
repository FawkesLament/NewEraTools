local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local InterruptChain = Internals.InterruptChain
local Spacing = ns.Assets.Spacing

local TwinFangs = ns.Modules.Get("TwinFangs")

---@param regionId string
---@return string
local function RegionLabel(regionId)
    if regionId == InterruptChain.FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    elseif regionId == InterruptChain.FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    elseif regionId == InterruptChain.BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    elseif regionId == InterruptChain.BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

---@param snapshot TwinFangsInterruptStatus|nil
---@param isBackup boolean|nil
---@return StatusHUDState|nil
local function HudState(snapshot, isBackup)
    if not snapshot then
        return nil
    end
    local region = RegionLabel(snapshot.region)
    local title = region
    if not isBackup then
        title = L.TWIN_FANGS_INTERRUPT_STATUS_REGION_ROLE:format(region, L.TWIN_FANGS_INTERRUPT_STATUS_PRIMARY)
    end
    local detail
    if isBackup then
        detail = L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP
    elseif snapshot.indexEnd and snapshot.indexEnd > snapshot.index then
        detail = L.TWIN_FANGS_INTERRUPT_STATUS_TASK_RANGE:format(snapshot.index, snapshot.indexEnd)
    else
        detail = L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(snapshot.index)
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

---@type StatusHUD|nil
local backupWindow
local previewing = false

local function EnsureBackup()
    if backupWindow then
        return backupWindow
    end
    backupWindow = ns.StatusHUD.Create({
        name = ns.ADDON_NAME .. "TwinFangsInterruptBackupStatus",
        tone = ns.StatusHUD.TONE_STANDBY,
    })
    return backupWindow
end

---@param primary StatusHUD
local function SyncBackupHud(primary)
    local state = HudState(TwinFangs:GetBackupInterruptStatus(), true)
    if not state then
        if backupWindow then
            backupWindow:Hide()
        end
        return
    end
    local backup = EnsureBackup()
    backup:SetState(state)
    backup:Show()
    backup:ClearAllPoints()
    if primary:IsShown() then
        backup:SetPoint("TOP", primary, "BOTTOM", 0, -Spacing.SMALL)
    else
        ns.LayoutEditor.ApplyPosition(backup, TwinFangs:GetInterruptStatusHudPosition())
    end
end

local InterruptStatusHUD = ns.StatusHUD.Bind({
    layoutId = "TwinFangs:interrupt",
    name = ns.ADDON_NAME .. "TwinFangsInterruptStatus",
    label = L.TWIN_FANGS_INTERRUPT_STATUS_TITLE,
    tone = ns.StatusHUD.TONE_EMPHASIS,
    -- Edit Mode can always preview this HUD. Combat visibility is assignment-gated.
    isEnabled = function()
        return true
    end,
    getPosition = function()
        return TwinFangs:GetInterruptStatusHudPosition()
    end,
    setPosition = function(position)
        TwinFangs:SetInterruptStatusHudPosition(position)
    end,
    getDefaultPosition = function()
        return Internals.Schema.DefaultInterruptStatusHudPosition()
    end,
    previewState = function()
        return HudState(TwinFangs:GetInterruptStatusPreview())
    end,
    getState = function()
        return HudState(TwinFangs:GetInterruptStatus())
    end,
    onEditBegin = function()
        previewing = true
        if backupWindow then
            backupWindow:Hide()
        end
    end,
    onEditEnd = function()
        previewing = false
    end,
})
Internals.InterruptStatusHudUI = InterruptStatusHUD

local boundUpdate = InterruptStatusHUD.Update
function InterruptStatusHUD.Update()
    boundUpdate()
    if previewing then
        if backupWindow then
            backupWindow:Hide()
        end
        return
    end
    SyncBackupHud(InterruptStatusHUD.Ensure())
end

function InterruptStatusHUD.EnsureBackup()
    return EnsureBackup()
end

function TwinFangs:OnInterruptStatusChanged()
    InterruptStatusHUD.Update()
end

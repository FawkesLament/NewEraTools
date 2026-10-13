local _, ns = ...
local Util = ns.Util
local Assets = ns.Assets
local LayoutEditor = ns.LayoutEditor
local Aura = ns.Api.Aura
local Combat = ns.Api.Combat
local Chrome = ns.AuraTrackerBarChromeUI
local Preview = ns.AuraTrackerBarPreviewUI

local AuraTracker = ns.Modules.Get("AuraTracker")

local SLOT_KEY = "buff"

---@class AuraTrackerBarInstance
---@field trackerId integer
---@field layoutHost Frame|nil
---@field previewBar StatusBar|nil
---@field previewBackground Texture|nil
---@field previewBorder Frame|nil
---@field previewTimeText FontString|nil
---@field previewStackDividerHost Frame|nil
---@field previewStackDividers Texture[]|nil
---@field container Frame|nil
---@field slotFrame Frame|nil
---@field durationBar StatusBar|nil  Shared StatusBar for SetDurationBar or SetApplicationBar.
---@field backgroundTexture Texture|nil
---@field borderFrame Frame|nil
---@field stackDividerHost Frame|nil
---@field stackDividers Texture[]|nil
---@field timeHost Frame|nil
---@field durationText FontString|nil  Shared FontString for SetDurationText or SetApplicationCount.
---@field barBoundMode string|nil  `duration`, `stacks`, or nil when unbound.
---@field barBoundMaxStacks integer|nil
---@field valueTextBoundMode string|nil  `duration`, `stacks`, or nil when unbound.
---@field slotConfigured boolean
---@field initFailed boolean
---@field layoutRegistered boolean
---@field editing boolean
---@field previewElapsed number
---@field lastSpellId integer|nil
---@field layoutLabel string|nil

---@type table<integer, AuraTrackerBarInstance>
local instances = {}
local unsupportedReported = false
local sharedMediaListening = false

local AuraTrackerBarUI = {}
ns.AuraTrackerBarUI = AuraTrackerBarUI

local DestroyInstance
local EnsureInstance
local UpdateInstance
local ApplyAppearanceInstance

---@param trackerId integer
---@return AuraTrackerBarInstance
EnsureInstance = function(trackerId)
    local inst = instances[trackerId]
    if inst then
        return inst
    end
    inst = {
        trackerId = trackerId,
        slotConfigured = false,
        initFailed = false,
        layoutRegistered = false,
        editing = false,
        previewElapsed = 0,
    }
    instances[trackerId] = inst
    return inst
end

---@param inst AuraTrackerBarInstance
---@return boolean
function AuraTrackerBarUI.CanConfigureFrames(inst)
    if Combat.IsLockedDown() then
        return false
    end
    if inst.container and inst.container.CanChangeProtectedState and not inst.container:CanChangeProtectedState() then
        return false
    end
    return true
end

---@param trackerId integer
---@return Frame
local function EnsureLayoutHost(trackerId)
    return Preview.EnsureLayoutHost(EnsureInstance(trackerId))
end

-- ---------------------------------------------------------------------------
-- Layout / appearance (no AuraContainer recreation)
-- ---------------------------------------------------------------------------

---Aura slots stay anchored to the layout host so native duration bindings are preserved.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function ApplyLayout(inst, button)
    local width, height = Chrome.BarSize(inst.trackerId)
    if inst.layoutHost then
        inst.layoutHost:SetSize(width, height)
    end
    button:SetSize(width, height)
    button:ClearAllPoints()
    button:SetPoint("CENTER", inst.layoutHost, "CENTER")
end

---@param inst AuraTrackerBarInstance
---@param button Frame
local function EnsureBorderFrame(inst, button)
    if inst.borderFrame then
        return inst.borderFrame
    end
    -- Overlay the bar: a 1px edge is drawn inside the same rect and would be covered if
    -- the StatusBar sits above this frame.
    local borderFrame = CreateFrame("Frame", nil, button, Assets.Templates.BACKDROP)
    borderFrame:SetAllPoints(button)
    borderFrame:SetBackdrop(Chrome.LineBackdrop(1))
    borderFrame:SetBackdropColor(0, 0, 0, 0)
    borderFrame:EnableMouse(false)
    inst.borderFrame = borderFrame
    return borderFrame
end

---Host above the fill/border so the duration string is not covered.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function EnsureTimeHost(inst, button)
    if inst.timeHost then
        return inst.timeHost
    end
    local timeHost = CreateFrame("Frame", nil, button)
    timeHost:SetAllPoints(button)
    timeHost:EnableMouse(false)
    local durationText = timeHost:CreateFontString(nil, "OVERLAY")
    durationText:SetWordWrap(false)
    durationText:Hide()
    inst.timeHost = timeHost
    inst.durationText = durationText
    return timeHost
end

---Clears the active value-text binding when combat/protection allows.
---@param inst AuraTrackerBarInstance
---@param button Frame
---@return boolean
local function ClearValueTextBinding(inst, button)
    if not inst.valueTextBoundMode or not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return false
    end
    local mode = inst.valueTextBoundMode
    local cleared = pcall(function()
        if mode == AuraTracker.TRACKING_MODE_STACKS then
            button:ClearApplicationCount()
        else
            button:ClearDurationText()
        end
    end)
    if cleared then
        inst.valueTextBoundMode = nil
    end
    return cleared
end

---Binds or clears AuraButton value text (duration or stack count); safe to call repeatedly.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function ApplyValueText(inst, button)
    local trackerId = inst.trackerId
    local host = EnsureTimeHost(inst, button)
    local border = EnsureBorderFrame(inst, button)
    host:SetFrameLevel(border:GetFrameLevel() + 1)
    Chrome.ApplyTimeTextAppearance(trackerId, inst.durationText)

    local desiredMode = AuraTracker:GetTrackingMode(trackerId)
    if not AuraTracker:GetShowTime(trackerId) then
        ClearValueTextBinding(inst, button)
        inst.durationText:Hide()
        return
    end

    inst.durationText:Show()
    if not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return
    end
    if inst.valueTextBoundMode == desiredMode then
        return
    end
    if inst.valueTextBoundMode then
        ClearValueTextBinding(inst, button)
        if inst.valueTextBoundMode then
            return
        end
    end
    local ok = pcall(function()
        if desiredMode == AuraTracker.TRACKING_MODE_STACKS then
            button:SetApplicationCount(inst.durationText, Aura.GetApplicationCountOptions())
        else
            button:SetDurationText(inst.durationText, Aura.GetDurationTextOptions())
        end
    end)
    if ok then
        inst.valueTextBoundMode = desiredMode
    end
end

---Switches the shared StatusBar between SetDurationBar and SetApplicationBar.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function SyncBarBinding(inst, button)
    local bar = inst.durationBar
    if not bar or not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return
    end
    local trackerId = inst.trackerId
    local desiredMode = AuraTracker:GetTrackingMode(trackerId)
    local maxStacks = AuraTracker:GetMaxStacks(trackerId)
    if
        inst.barBoundMode == desiredMode
        and (desiredMode ~= AuraTracker.TRACKING_MODE_STACKS or inst.barBoundMaxStacks == maxStacks)
    then
        return
    end

    if inst.barBoundMode == AuraTracker.TRACKING_MODE_DURATION then
        pcall(function()
            button:ClearDurationBar()
        end)
    elseif inst.barBoundMode == AuraTracker.TRACKING_MODE_STACKS then
        pcall(function()
            button:ClearApplicationBar()
        end)
    end
    inst.barBoundMode = nil
    inst.barBoundMaxStacks = nil

    local ok = pcall(function()
        if desiredMode == AuraTracker.TRACKING_MODE_STACKS then
            button:SetApplicationBar(bar, Aura.GetApplicationBarOptions(maxStacks))
        else
            button:SetDurationBar(bar, Aura.GetDurationBarOptions())
        end
    end)
    if ok then
        inst.barBoundMode = desiredMode
        if desiredMode == AuraTracker.TRACKING_MODE_STACKS then
            inst.barBoundMaxStacks = maxStacks
        end
    end
end

---@param trackerId integer
ApplyAppearanceInstance = function(trackerId)
    local inst = instances[trackerId]
    if not inst then
        return
    end
    if inst.editing then
        Preview.ApplyAppearance(inst)
        -- Restart so mode / maxStacks changes take effect while layout-editing.
        Preview.StartAnimation(inst)
        return
    end
    if not inst.slotFrame or not inst.durationBar or not inst.backgroundTexture then
        return
    end

    ApplyLayout(inst, inst.slotFrame)
    Chrome.ApplyBarChrome(
        trackerId,
        inst.durationBar,
        inst.backgroundTexture,
        EnsureBorderFrame(inst, inst.slotFrame),
        nil
    )
    inst.stackDividerHost = Chrome.EnsureStackDividerHost(inst.slotFrame, inst.stackDividerHost)
    inst.stackDividers = inst.stackDividers or {}
    Chrome.ApplyStackDividers(trackerId, inst.stackDividerHost, inst.stackDividers, inst.durationBar)
    SyncBarBinding(inst, inst.slotFrame)
    ApplyValueText(inst, inst.slotFrame)
end

function AuraTrackerBarUI.ApplyAppearance(trackerId)
    if trackerId then
        ApplyAppearanceInstance(trackerId)
        return
    end
    for id in pairs(instances) do
        ApplyAppearanceInstance(id)
    end
end

-- ---------------------------------------------------------------------------
-- Tracking (AuraContainer / AuraSlot)
-- ---------------------------------------------------------------------------

---Creates the shared StatusBar once; native duration/stacks binding is applied in SyncBarBinding.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function BindProgressBar(inst, button)
    ApplyLayout(inst, button)

    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(AuraTracker:GetTexturePath(inst.trackerId))

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)

    inst.durationBar = bar
    inst.backgroundTexture = background
    SyncBarBinding(inst, button)
    ApplyAppearanceInstance(inst.trackerId)
end

---@param trackerId integer
---@return Frame|nil
local function EnsureContainer(trackerId)
    local inst = EnsureInstance(trackerId)
    if inst.container then
        return inst.container
    end
    if inst.initFailed then
        return nil
    end
    if not Aura.IsSupported() then
        if not unsupportedReported then
            unsupportedReported = true
            Util.Print(ns.L.AURA_TRACKER_UNSUPPORTED)
        end
        inst.initFailed = true
        return nil
    end

    local host = EnsureLayoutHost(trackerId)
    local ok, frame = pcall(
        CreateFrame,
        "AuraContainer",
        ns.ADDON_NAME .. "AuraTracker" .. trackerId,
        host,
        "CustomAuraContainerTemplate"
    )
    if not ok or not frame then
        inst.initFailed = true
        Util.Print(ns.L.AURA_TRACKER_INIT_FAILED)
        return nil
    end

    inst.container = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetAllPoints(host)
    frame:EnableMouse(false)
    frame:Hide()
    return frame
end

---@param inst AuraTrackerBarInstance
---@return boolean
local function ConfigureSlot(inst)
    if not inst.container or inst.slotConfigured then
        return true
    end
    if not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return false
    end

    local spellId = AuraTracker:GetSpellId(inst.trackerId)
    local sortMethod, sortDirection = Aura.GetExpirationSort()
    local auraButton
    local ok, err = pcall(function()
        -- Declare the slot before SetUnit: unit assignment (re)registers UNIT_AURA only when
        -- the container already has content. Bind chrome in initializeFrame so AddAuraSlot's
        -- first UpdateAllAuras already has SetDurationBar / SetApplicationBar attached.
        auraButton = inst.container:AddAuraSlot(SLOT_KEY, Aura.FILTER_HELPFUL, {
            candidateFilters = Aura.BuildIncludeSpellFilters(spellId),
            sortMethod = sortMethod,
            sortDirection = sortDirection,
            initializeFrame = function(button)
                inst.slotFrame = button
                BindProgressBar(inst, button)
            end,
        })
        if not auraButton then
            error("AddAuraSlot returned nil")
        end
        inst.slotFrame = auraButton
        inst.container:SetUnit(Aura.UNIT_PLAYER)
        inst.container:SetEnabled(false)
    end)
    if not ok then
        inst.initFailed = true
        Util.Print(ns.L.AURA_TRACKER_INIT_FAILED .. " (" .. tostring(err) .. ")")
        return false
    end
    inst.slotConfigured = true
    inst.lastSpellId = spellId
    return true
end

---@param inst AuraTrackerBarInstance
---@return boolean
local function ApplySpellFilter(inst)
    if not inst.container or not inst.slotConfigured then
        return true
    end
    if not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return false
    end
    local spellId = AuraTracker:GetSpellId(inst.trackerId)
    if spellId <= 0 then
        return true
    end
    if inst.lastSpellId == spellId then
        return true
    end
    local ok, err = pcall(function()
        inst.container:SetAuraSlotCandidateFilters(SLOT_KEY, Aura.BuildIncludeSpellFilters(spellId))
    end)
    if not ok then
        Util.Print(ns.L.AURA_TRACKER_INIT_FAILED .. " (" .. tostring(err) .. ")")
        return false
    end
    inst.lastSpellId = spellId
    return true
end

---@param trackerId integer
UpdateInstance = function(trackerId)
    if not AuraTracker:HasTracker(trackerId) then
        DestroyInstance(trackerId)
        return
    end

    local inst = EnsureInstance(trackerId)
    if inst.editing then
        return
    end

    -- Keep layout registration alive for enabled trackers even when not currently tracking.
    if AuraTracker:IsEnabled() and AuraTracker:IsTrackerEnabled(trackerId) then
        EnsureLayoutHost(trackerId)
        Preview.RefreshLayoutLabel(inst)
    end

    -- Global auto-hide is situational visibility only; layout-edit preview skips this path via
    -- `inst.editing` above, and per-tracker enablement / activation scope stay in ShouldTrack.
    if not AuraTracker:ShouldTrack(trackerId) or AuraTracker:ShouldHideAuraBars() then
        if inst.layoutHost then
            inst.layoutHost:Hide()
        end
        if inst.container and AuraTrackerBarUI.CanConfigureFrames(inst) then
            pcall(function()
                inst.container:SetEnabled(false)
                inst.container:Hide()
            end)
        end
        return
    end

    if not AuraTrackerBarUI.CanConfigureFrames(inst) then
        return
    end

    EnsureLayoutHost(trackerId)
    local frame = EnsureContainer(trackerId)
    if not frame then
        return
    end
    if not ConfigureSlot(inst) then
        return
    end
    if not ApplySpellFilter(inst) then
        return
    end

    pcall(function()
        LayoutEditor.ApplyPosition(inst.layoutHost, AuraTracker:GetPosition(trackerId))
        inst.layoutHost:Show()
        -- SetUnit after the slot exists so UNIT_AURA is registered; safe to repeat on refresh.
        frame:SetUnit(Aura.UNIT_PLAYER)
        frame:SetEnabled(true)
        frame:UpdateAllAuras()
        frame:Show()
        if inst.slotFrame then
            ApplyLayout(inst, inst.slotFrame)
            ApplyAppearanceInstance(trackerId)
        end
    end)
end

---@param trackerId integer
DestroyInstance = function(trackerId)
    local inst = instances[trackerId]
    if not inst then
        return
    end

    Preview.Teardown(inst)

    if inst.container then
        if AuraTrackerBarUI.CanConfigureFrames(inst) then
            pcall(function()
                inst.container:SetEnabled(false)
                inst.container:Hide()
            end)
        end
    end

    instances[trackerId] = nil
end

function AuraTrackerBarUI.Update(trackerId)
    if trackerId then
        UpdateInstance(trackerId)
    else
        local alive = {}
        for _, id in ipairs(AuraTracker:GetTrackerIds()) do
            alive[id] = true
            UpdateInstance(id)
        end
        for id in pairs(instances) do
            if not alive[id] then
                DestroyInstance(id)
            end
        end
    end

    -- Enable/disable (and activation-scope) changes while layout-editing must show/hide immediately.
    if LayoutEditor.IsEditing() then
        LayoutEditor.Refresh()
    end
end

function AuraTrackerBarUI.SyncList()
    AuraTrackerBarUI.Update(nil)
end

---LibSharedMedia fires this after a successful Register; re-resolve the fill/font if needed.
---@param _ any
---@param mediaType string
local function OnSharedMediaRegistered(_, mediaType)
    if mediaType ~= "statusbar" and mediaType ~= "font" then
        return
    end
    AuraTrackerBarUI.ApplyAppearance(nil)
end

local function ListenForSharedMedia()
    if sharedMediaListening or LibStub == nil then
        return
    end
    local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok or not lsm or not lsm.RegisterCallback then
        return
    end
    sharedMediaListening = true
    lsm.RegisterCallback(AuraTrackerBarUI, "LibSharedMedia_Registered", OnSharedMediaRegistered)
end

---Wires combat-leave flush, optional LSM refresh, layout registration, and the initial update.
function AuraTrackerBarUI.Enable()
    AuraTracker:ListenForCombat()
    AuraTracker:ListenForPlayerContext()
    AuraTracker:ListenForVisibilityContext()
    ListenForSharedMedia()
    for _, trackerId in ipairs(AuraTracker:GetTrackerIds()) do
        if AuraTracker:IsEnabled() and AuraTracker:IsTrackerEnabled(trackerId) then
            EnsureLayoutHost(trackerId)
        end
    end
    AuraTrackerBarUI.Update(nil)
end

local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Util = ns.Util
local LayoutEditor = ns.LayoutEditor
local Aura = ns.Api.Aura
local Combat = ns.Api.Combat
local Unit = ns.Api.Unit
local Chrome = Internals.BarChromeUI
local Preview = Internals.BarPreviewUI
local Appearance = Internals.BarAppearanceUI
local Profile = Internals.Profile
local ProfileReport = Internals.ProfileReport

local AuraTracker = ns.Modules.Get("AuraTracker")
local Schema = Internals.Schema

local SLOT_KEY = "buff"

-- Debug reasons for /neatprof. Constants so the display path does not build strings.
local REASON_SLOT_ON_SHOW = "reason.slotOn.show"
local REASON_SLOT_OFF_MISSING = "reason.slotOff.missing"
local REASON_SLOT_OFF_FRIENDLY = "reason.slotOff.friendly"
local REASON_SLOT_OFF_NOT_TRACKING = "reason.slotOff.notTracking"
local REASON_SLOT_OFF_EDIT = "reason.slotOff.edit"
local REASON_SLOT_OFF_CONFIGURE = "reason.slotOff.configure"
local REASON_SLOT_OFF_SOURCE = "reason.slotOff.source"
local REASON_UPDATE_SHOW = "reason.update.show"
local REASON_UPDATE_GUID = "reason.update.guidChanged"
local REASON_UPDATE_SECRET = "reason.update.retargetSecret"

---@class AuraTrackerBarInstance
---@field trackerId integer
---@field layoutHost Frame|nil
---@field previewBar StatusBar|nil
---@field previewBackground Texture|nil
---@field previewBorder Frame|nil
---@field previewTextHost Frame|nil  Above the preview divider frame so value text stays visible.
---@field previewDurationText FontString|nil
---@field previewStacksText FontString|nil
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
---@field durationText FontString|nil  SetDurationText target; independent of progress mode.
---@field stacksText FontString|nil  SetApplicationCount target; independent of progress mode.
---@field barBoundMode string|nil  `duration`, `stacks`, or nil when unbound.
---@field barBoundMaxStacks integer|nil
---@field durationTextBound boolean|nil
---@field stacksTextBound boolean|nil
---@field slotConfigured boolean
---@field initFailed boolean
---@field layoutRegistered boolean
---@field editing boolean
---@field previewElapsed number
---@field lastSpellId integer|nil  Spell id last passed to the slot's candidate filters.
---@field lastUnit string|nil  Unit token last passed to SetUnit.
---@field lastAuraType string|nil
---@field appliedEnabled boolean|nil  SetEnabled(true) succeeded and has not been cleared.
---@field appliedShown boolean|nil  Container was shown and has not been concealed.
---@field appliedSlotEnabled boolean|nil
---@field boundUnit string|nil  Unit token last shown. Nil after the displayed aura is dropped.
---@field boundGuid string|nil  Plain GUID last shown. Nil when concealed or when the GUID is secret.
---@field seenUnitRescanSerial integer|nil  Target or focus retarget generation last scanned while shown.
---@field appearanceReady boolean|nil  Live chrome painted; false when secret access blocked it.
---@field appliedAppearance table|nil  Saved look last painted onto the live bar. Nil until that paint succeeds.
---@field layoutLabel string|nil

---@type table<integer, AuraTrackerBarInstance>
local instances = {}
local unsupportedReported = false
local sharedMediaListening = false

local AuraTrackerBarUI = {}
Internals.BarUI = AuraTrackerBarUI

local DestroyInstance
local EnsureInstance
local UpdateInstance

---@param started number
---@param outcome string
local function FinishUpdate(started, outcome)
    Profile.Inc(outcome)
    Profile.Stop("bar.updateInstance", started)
end

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
local function CanConfigureFrames(inst)
    if Combat.IsLockedDown() then
        return false
    end
    if inst.container and inst.container.CanChangeProtectedState and not inst.container:CanChangeProtectedState() then
        return false
    end
    return true
end

---@param trackerId integer
---@return string
local function LayoutId(trackerId)
    return "AuraTracker:" .. tostring(trackerId)
end

---Drops the "already showing this configuration" record so the next update reapplies it.
---@param inst AuraTrackerBarInstance
local function MarkContainerConcealed(inst)
    inst.appliedEnabled = false
    inst.appliedShown = false
    inst.appliedSlotEnabled = false
    inst.boundUnit = nil
    inst.boundGuid = nil
end

---Disables the live slot without hiding the layout host, so the edit preview can use that host.
---@param inst AuraTrackerBarInstance
local function HideLiveSlot(inst)
    if not inst.container or not CanConfigureFrames(inst) then
        return
    end
    local concealed = pcall(function()
        if inst.appliedSlotEnabled and inst.container.SetAuraSlotEnabled then
            inst.container:SetAuraSlotEnabled(SLOT_KEY, false)
            Profile.Inc(REASON_SLOT_OFF_EDIT)
        end
        if inst.appliedEnabled ~= false then
            inst.container:SetEnabled(false)
        end
        if inst.appliedShown ~= false then
            inst.container:Hide()
        end
    end)
    if concealed then
        MarkContainerConcealed(inst)
    end
end

---@param inst AuraTrackerBarInstance
local function ResizeLayoutHost(inst)
    if not inst.layoutHost then
        return
    end
    local width, height = Chrome.BarSize(inst.trackerId)
    inst.layoutHost:SetSize(width, height)
end

-- Appearance.lua loads before this file and calls these at runtime.
AuraTrackerBarUI.CanConfigureFrames = CanConfigureFrames
AuraTrackerBarUI.ResizeLayoutHost = ResizeLayoutHost

---@param inst AuraTrackerBarInstance
local function UnregisterLayoutElement(inst)
    if not inst.layoutRegistered then
        return
    end
    LayoutEditor.Unregister(LayoutId(inst.trackerId))
    inst.layoutRegistered = false
end

---@param inst AuraTrackerBarInstance
local function RegisterLayoutElement(inst)
    if inst.layoutRegistered or not inst.layoutHost then
        return
    end
    local trackerId = inst.trackerId
    local label = inst.layoutLabel or AuraTracker:GetDisplayName(trackerId)
    inst.layoutLabel = label
    inst.layoutRegistered = true
    LayoutEditor.Register({
        id = LayoutId(trackerId),
        label = label,
        frame = inst.layoutHost,
        global = true,
        isEnabled = function()
            return AuraTracker:HasTracker(trackerId)
                and AuraTracker:IsEnabled()
                and AuraTracker:IsTrackerEnabled(trackerId)
                and AuraTracker:IsActivationActive(trackerId)
        end,
        getPosition = function()
            return AuraTracker:GetPosition(trackerId)
        end,
        setPosition = function(position)
            AuraTracker:SetPosition(trackerId, position)
        end,
        getDefaultPosition = function()
            return { point = "CENTER", relativePoint = "CENTER", x = 0, y = -80 }
        end,
        onEditBegin = function()
            inst.editing = true
            ResizeLayoutHost(inst)
            Preview.Show(inst)
            LayoutEditor.ApplyPosition(inst.layoutHost, AuraTracker:GetPosition(trackerId))
            HideLiveSlot(inst)
            -- Edit end calls Update, which must not reuse the pre-edit aura instance.
            inst.boundUnit = nil
            inst.boundGuid = nil
            inst.layoutHost:Show()
            inst.layoutHost:Raise()
            Preview.StartAnimation(inst)
        end,
        onEditEnd = function()
            inst.editing = false
            Preview.Hide(inst)
            AuraTrackerBarUI.Update(trackerId)
        end,
    })
end

---@param inst AuraTrackerBarInstance
local function RefreshLayoutLabel(inst)
    if not inst.layoutHost then
        return
    end
    local label = AuraTracker:GetDisplayName(inst.trackerId)
    if inst.layoutRegistered and inst.layoutLabel == label then
        return
    end
    UnregisterLayoutElement(inst)
    inst.layoutLabel = label
    RegisterLayoutElement(inst)
end

---Creates the outer layout host and registers it with LayoutEditor.
---@param trackerId integer
---@return Frame
local function EnsureLayoutHost(trackerId)
    local inst = EnsureInstance(trackerId)
    if inst.layoutHost then
        return inst.layoutHost
    end
    local layoutHost = CreateFrame("Frame", ns.ADDON_NAME .. "AuraTrackerLayout" .. trackerId, UIParent)
    -- MEDIUM keeps Blizzard DIALOG/TOOLTIP menus above the bar.
    layoutHost:SetFrameStrata("MEDIUM")
    layoutHost:EnableMouse(false)
    layoutHost:SetMovable(true)
    layoutHost:SetClampedToScreen(true)
    inst.layoutHost = layoutHost
    ResizeLayoutHost(inst)
    LayoutEditor.ApplyPosition(layoutHost, AuraTracker:GetPosition(trackerId))
    layoutHost:Hide()
    RegisterLayoutElement(inst)
    return layoutHost
end

---Saved appearance fields that have not been painted onto this live bar.
---@param trackerId integer
---@return table<string, boolean>
function AuraTrackerBarUI.PendingAppearanceKeys(trackerId)
    return Appearance.PendingKeys(instances[trackerId])
end

---True when any live bar is still showing an older look than its saved settings.
---@param trackerId integer|nil
---@return boolean
function AuraTrackerBarUI.HasPendingAppearance(trackerId)
    if trackerId then
        return next(AuraTrackerBarUI.PendingAppearanceKeys(trackerId)) ~= nil
    end
    for id in pairs(instances) do
        if AuraTrackerBarUI.HasPendingAppearance(id) then
            return true
        end
    end
    return false
end

---@param trackerId integer|nil
function AuraTrackerBarUI.ApplyAppearance(trackerId)
    if trackerId then
        Appearance.Apply(instances[trackerId])
        return
    end
    for _, inst in pairs(instances) do
        Appearance.Apply(inst)
    end
end

-- ---------------------------------------------------------------------------
-- Tracking (AuraContainer / AuraSlot)
-- ---------------------------------------------------------------------------

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
    local createStarted = Profile.Start()
    local ok, frame = pcall(
        CreateFrame,
        "AuraContainer",
        ns.ADDON_NAME .. "AuraTracker" .. trackerId,
        host,
        "CustomAuraContainerTemplate"
    )
    Profile.Stop("bar.createContainer", createStarted)
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
    if not CanConfigureFrames(inst) then
        return false
    end

    local spellId = AuraTracker:GetSpellId(inst.trackerId)
    local unit = AuraTracker:GetUnit(inst.trackerId)
    local auraType = AuraTracker:GetAuraType(inst.trackerId)
    local sortMethod, sortDirection = Aura.GetExpirationSort()
    local auraButton
    local configureStarted = Profile.Start()
    local ok, err = pcall(function()
        -- Declare the slot before SetUnit: unit assignment (re)registers UNIT_AURA only when
        -- the container already has content. Bind chrome in initializeFrame so AddAuraSlot's
        -- first UpdateAllAuras already has SetDurationBar / SetApplicationBar attached.
        -- One slot covers every supported unit; the filter string and SetUnit select the source.
        auraButton = inst.container:AddAuraSlot(SLOT_KEY, auraType, {
            candidateFilters = Aura.BuildIncludeSpellFilters(spellId),
            sortMethod = sortMethod,
            sortDirection = sortDirection,
            initializeFrame = function(button)
                inst.slotFrame = button
                Appearance.BindProgressBar(inst, button)
            end,
        })
        if not auraButton then
            error("AddAuraSlot returned nil")
        end
        inst.slotFrame = auraButton
        inst.container:SetUnit(unit)
        if inst.container.SetAuraSlotEnabled then
            inst.container:SetAuraSlotEnabled(SLOT_KEY, false)
            Profile.Inc(REASON_SLOT_OFF_CONFIGURE)
        end
        inst.container:SetEnabled(false)
    end)
    Profile.Stop("bar.configureSlot", configureStarted)
    if not ok then
        inst.initFailed = true
        Util.Print(ns.L.AURA_TRACKER_INIT_FAILED .. " (" .. tostring(err) .. ")")
        return false
    end
    inst.slotConfigured = true
    inst.lastSpellId = spellId
    inst.lastUnit = unit
    inst.lastAuraType = auraType
    inst.appliedEnabled = false
    inst.appliedShown = false
    inst.appliedSlotEnabled = false
    return true
end

---Points the existing slot at this tracker's unit and aura type. Does not recreate the bar.
---@param inst AuraTrackerBarInstance
---@return boolean
local function ApplyAuraSource(inst)
    if not inst.container or not inst.slotConfigured then
        return true
    end
    local unit = AuraTracker:GetUnit(inst.trackerId)
    local auraType = AuraTracker:GetAuraType(inst.trackerId)
    if inst.lastUnit == unit and inst.lastAuraType == auraType then
        return true
    end
    local ok, err = pcall(function()
        -- Disable before the token changes. An enabled HARMFUL slot on a friendly unit
        -- ignores includeSpellIDs and can also drop the spell map.
        if inst.container.SetAuraSlotEnabled then
            inst.container:SetAuraSlotEnabled(SLOT_KEY, false)
            Profile.Inc(REASON_SLOT_OFF_SOURCE)
        end
        inst.container:SetEnabled(false)
        if inst.lastAuraType ~= auraType then
            inst.container:SetAuraSlotFilterString(SLOT_KEY, auraType)
        end
        if inst.lastUnit ~= unit then
            local setUnitStarted = Profile.Start()
            inst.container:SetUnit(unit)
            Profile.Stop("native.SetUnit", setUnitStarted)
            -- Token change only. A new GUID behind the same token does not enter here.
            -- Re-push filters once: SetUnit's own refresh can run before the map is restored.
            inst.lastSpellId = nil
        end
    end)
    if not ok then
        Util.Print(ns.L.AURA_TRACKER_INIT_FAILED .. " (" .. tostring(err) .. ")")
        return false
    end
    inst.lastUnit = unit
    inst.lastAuraType = auraType
    MarkContainerConcealed(inst)
    return true
end

---Why a live slot is being turned off outside the display path.
---A removed tracker is not tracking. Do not look it up: `ShouldTrack` requires the saved row.
---@param inst AuraTrackerBarInstance
---@return string
local function UnavailableSlotReason(inst)
    if not AuraTracker:HasTracker(inst.trackerId) then
        return REASON_SLOT_OFF_NOT_TRACKING
    end
    if not AuraTracker:ShouldTrack(inst.trackerId) or AuraTracker:ShouldHideAuraBars() then
        return REASON_SLOT_OFF_NOT_TRACKING
    end
    if not Unit.Exists(AuraTracker:GetUnit(inst.trackerId)) then
        return REASON_SLOT_OFF_MISSING
    end
    return REASON_SLOT_OFF_FRIENDLY
end

---Hides the bar and drops any aura instance so the next unit cannot inherit duration or stacks.
---The frame work does not depend on the saved tracker. The profile reason is recorded after it.
---@param inst AuraTrackerBarInstance
local function ClearTrackingDisplay(inst)
    local hostShown = inst.layoutHost and inst.layoutHost:IsShown()
    if hostShown then
        inst.layoutHost:Hide()
    end
    local containerLive = inst.appliedEnabled or inst.appliedShown or inst.appliedSlotEnabled
    local concealed = true
    local disabledSlot = false
    if inst.container and containerLive then
        disabledSlot = inst.appliedSlotEnabled == true and inst.container.SetAuraSlotEnabled ~= nil
        concealed = pcall(function()
            if disabledSlot then
                inst.container:SetAuraSlotEnabled(SLOT_KEY, false)
            end
            if inst.appliedEnabled then
                inst.container:SetEnabled(false)
            end
            if inst.appliedShown then
                inst.container:Hide()
            end
        end)
    end
    if concealed then
        MarkContainerConcealed(inst)
        if disabledSlot then
            Profile.Inc(UnavailableSlotReason(inst))
        end
    end
end

---@param inst AuraTrackerBarInstance
---@return boolean
local function ApplySpellFilter(inst)
    if not inst.container or not inst.slotConfigured then
        return true
    end
    local spellId = AuraTracker:GetSpellId(inst.trackerId)
    if spellId <= 0 or inst.lastSpellId == spellId then
        return true
    end
    local ok, err = pcall(function()
        local filtersStarted = Profile.Start()
        inst.container:SetAuraSlotCandidateFilters(SLOT_KEY, Aura.BuildIncludeSpellFilters(spellId))
        Profile.Stop("native.SetAuraSlotCandidateFilters", filtersStarted)
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
    local started = Profile.Start()
    if not AuraTracker:HasTracker(trackerId) then
        DestroyInstance(trackerId)
        FinishUpdate(started, "bar.missingTracker")
        return
    end

    local inst = EnsureInstance(trackerId)
    if inst.editing then
        FinishUpdate(started, "bar.editing")
        return
    end

    -- Keep layout registration alive for enabled trackers even when not currently tracking.
    if AuraTracker:IsEnabled() and AuraTracker:IsTrackerEnabled(trackerId) then
        EnsureLayoutHost(trackerId)
        RefreshLayoutLabel(inst)
    end

    -- Global auto-hide is situational visibility only; layout-edit preview skips this path via
    -- `inst.editing` above, and per-tracker enablement / activation scope stay in ShouldTrack.
    if not AuraTracker:ShouldTrack(trackerId) or AuraTracker:ShouldHideAuraBars() then
        ClearTrackingDisplay(inst)
        FinishUpdate(started, "bar.notTracking")
        return
    end

    -- Slot creation anchors frames, so it waits for combat. A slot that already exists can
    -- retarget during combat: SetUnit is not an anchor change.
    if (not inst.container or not inst.slotConfigured) and not CanConfigureFrames(inst) then
        FinishUpdate(started, "bar.combatBlocked")
        return
    end

    EnsureLayoutHost(trackerId)
    local frame = EnsureContainer(trackerId)
    if not frame then
        FinishUpdate(started, "bar.noContainer")
        return
    end
    if not ConfigureSlot(inst) then
        FinishUpdate(started, "bar.configureFailed")
        return
    end
    if not ApplyAuraSource(inst) then
        FinishUpdate(started, "bar.sourceFailed")
        return
    end

    -- Friendly or missing target/focus: keep includeSpellIDs, but do not leave the slot
    -- enabled. On 12.1.0 an enabled HARMFUL slot ignores the spell filter and shows every debuff.
    if not AuraTracker:CanDisplayAura(trackerId) then
        ClearTrackingDisplay(inst)
        FinishUpdate(started, "bar.cannotDisplay")
        return
    end

    local unit = AuraTracker:GetUnit(trackerId)
    local guid = AuraTracker:GetDisplayedUnitGUID(trackerId)
    -- Same token, different plain GUID. SetUnit does not see this, and UNIT_AURA is not
    -- sent for auras the new unit already has. A secret GUID stays nil and is not compared.
    local guidChanged = inst.appliedShown == true and inst.boundUnit == unit and inst.boundGuid ~= guid
    local rescanSerial = (unit == Schema.UNIT_TARGET and (AuraTracker.targetRescanSerial or 0))
        or (unit == Schema.UNIT_FOCUS and (AuraTracker.focusRescanSerial or 0))
        or nil
    local retargetScan = rescanSerial ~= nil and inst.seenUnitRescanSerial ~= rescanSerial
    local showContainer = inst.appliedShown ~= true
    -- A plain GUID that still matches the unit we last scanned does not need another rebuild:
    -- the slot stayed enabled, so UNIT_AURA has been maintaining that unit. The event frame
    -- can still report the previous unit, so a same-GUID pass only records the serial; the
    -- next pass scans if the GUID then differs. A nil GUID cannot be compared, so a retarget
    -- still scans. 12.1.5 refreshes on UNIT_FLAGS / UNIT_FACTION only, not on a target swap
    -- that does not change flags, so a real GUID change still scans here.
    local guidUnproven = guid == nil or inst.boundGuid == nil
    local scan = showContainer or guidChanged or (retargetScan and guidUnproven)

    local shown = pcall(function()
        if CanConfigureFrames(inst) then
            LayoutEditor.ApplyPosition(inst.layoutHost, AuraTracker:GetPosition(trackerId))
        end
        if inst.appliedEnabled ~= true then
            local setEnabledStarted = Profile.Start()
            frame:SetEnabled(true)
            Profile.Stop("native.SetEnabled", setEnabledStarted)
        end
        -- After SetEnabled. A token change clears lastSpellId so this runs once, not per refresh.
        if not ApplySpellFilter(inst) then
            error("spell filter")
        end
        -- Hostile-to-hostile keeps the slot enabled. A full rebuild reassigns its aura.
        -- Missing, friendly, and disabled trackers disable the slot before this point.
        if inst.appliedSlotEnabled ~= true and frame.SetAuraSlotEnabled then
            local slotStarted = Profile.Start()
            frame:SetAuraSlotEnabled(SLOT_KEY, true)
            Profile.Inc(REASON_SLOT_ON_SHOW)
            Profile.Stop("native.SetAuraSlotEnabled", slotStarted)
        end
        if showContainer then
            inst.layoutHost:Show()
            local showStarted = Profile.Start()
            frame:Show()
            Profile.Stop("native.Show", showStarted)
        end
        -- Show's OnShow also scans, but a hidden-frame scan is dropped. Call once the frame
        -- is shown, and again when the unit behind this token changes.
        if scan then
            local updateReason = REASON_UPDATE_SHOW
            if not showContainer and guidChanged then
                updateReason = REASON_UPDATE_GUID
            elseif not showContainer then
                updateReason = REASON_UPDATE_SECRET
            end
            local updateStarted = Profile.Start()
            frame:UpdateAllAuras()
            Profile.Inc(updateReason)
            Profile.Stop("native.UpdateAllAuras", updateStarted)
        end
    end)
    if shown then
        inst.appliedEnabled = true
        inst.appliedShown = true
        if frame.SetAuraSlotEnabled then
            inst.appliedSlotEnabled = true
        end
        inst.boundUnit = unit
        inst.boundGuid = guid
        if rescanSerial ~= nil then
            inst.seenUnitRescanSerial = rescanSerial
        end
    end
    FinishUpdate(started, shown and "bar.display" or "bar.displayFailed")
end

---@param trackerId integer
DestroyInstance = function(trackerId)
    local inst = instances[trackerId]
    if not inst then
        return
    end

    ClearTrackingDisplay(inst)
    Preview.Hide(inst)
    UnregisterLayoutElement(inst)
    if inst.layoutHost then
        inst.layoutHost:EnableMouse(false)
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

    local flushStarted = Profile.Start()
    local function Flush(id)
        local inst = instances[id]
        if inst then
            Appearance.Flush(inst)
        end
    end
    if trackerId then
        Flush(trackerId)
    else
        for id in pairs(instances) do
            Flush(id)
        end
    end
    Profile.Stop(trackerId and "bar.flushOne" or "bar.flushAll", flushStarted)

    -- Enable/disable (and activation-scope) changes while layout-editing must show/hide immediately.
    if LayoutEditor.IsEditing() then
        LayoutEditor.Refresh()
    end
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
    AuraTracker:ListenForUnitContext()
    AuraTracker:ListenForVisibilityContext()
    ListenForSharedMedia()
    Profile.SetNoteProvider(function()
        local containers, shown, enabled = 0, 0, 0
        for _, inst in pairs(instances) do
            if inst.container then
                containers = containers + 1
                local shownOk, isShown = pcall(inst.container.IsShown, inst.container)
                if shownOk and isShown then
                    shown = shown + 1
                end
                local enabledOk, isEnabled = pcall(inst.container.IsEnabled, inst.container)
                if enabledOk and isEnabled then
                    enabled = enabled + 1
                end
            end
        end
        return string.format(ns.L.AURA_TRACKER_PROFILE_STATE, containers, shown, enabled)
    end)
    if not AuraTrackerBarUI.profileCommandRegistered then
        AuraTrackerBarUI.profileCommandRegistered = true
        ns.Api.Slash.Register("NEWERATOOLSAURAPROFILE", { "/neatprof" }, function(input)
            input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if input == "reset" then
                Profile.Reset()
                Util.Print(ns.L.AURA_TRACKER_PROFILE_RESET)
                ProfileReport.RefreshIfShown(Profile.Report())
                return
            end
            local startedNow = not Profile.IsRecording()
            Profile.Record()
            if startedNow then
                ProfileReport.Show(ns.L.AURA_TRACKER_PROFILE_STARTED)
                return
            end
            ProfileReport.Show(Profile.Report())
        end)
    end
    for _, trackerId in ipairs(AuraTracker:GetTrackerIds()) do
        if AuraTracker:IsEnabled() and AuraTracker:IsTrackerEnabled(trackerId) then
            EnsureLayoutHost(trackerId)
        end
    end
    AuraTrackerBarUI.Update(nil)
end

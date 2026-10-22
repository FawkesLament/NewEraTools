local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Assets = ns.Assets
local Aura = ns.Api.Aura
local Chrome = Internals.BarChromeUI
local Preview = Internals.BarPreviewUI
local Profile = Internals.Profile

local AuraTracker = ns.Modules.Get("AuraTracker")
local Schema = Internals.Schema

local Appearance = {}
Internals.BarAppearanceUI = Appearance

---Bar.lua loads after this file and owns these helpers.
---@param inst AuraTrackerBarInstance
---@return boolean
local function CanConfigureFrames(inst)
    return Internals.BarUI.CanConfigureFrames(inst)
end

---@param inst AuraTrackerBarInstance
local function ResizeLayoutHost(inst)
    Internals.BarUI.ResizeLayoutHost(inst)
end

---True when addon code may call methods on the live AuraButton.
---The slot is created in `initializeFrame` before AuraContainer denies tainted access.
---@param inst AuraTrackerBarInstance
---@param button Frame|nil
---@return boolean
local function CanTouchAuraButton(inst, button)
    return CanConfigureFrames(inst) and Aura.CanAccessObject(button)
end

---Aura slots stay anchored to the layout host so native duration bindings are preserved.
---Geometry is skipped while the slot denies tainted access; the host still tracks the saved size.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function ApplyLayout(inst, button)
    ResizeLayoutHost(inst)
    if not CanTouchAuraButton(inst, button) then
        return
    end
    local width, height = Chrome.BarSize(inst.trackerId)
    -- Access can flip between the check and the call. A throw here would abort the settings click.
    pcall(function()
        button:SetSize(width, height)
        button:ClearAllPoints()
        button:SetPoint("CENTER", inst.layoutHost, "CENTER")
    end)
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

---Host above the fill/border so value strings are not covered.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function EnsureTimeHost(inst, button)
    if inst.timeHost then
        if not inst.stacksText then
            local stacksText = inst.timeHost:CreateFontString(nil, "OVERLAY")
            stacksText:SetWordWrap(false)
            stacksText:Hide()
            inst.stacksText = stacksText
        end
        return inst.timeHost
    end
    local timeHost = CreateFrame("Frame", nil, button)
    timeHost:SetAllPoints(button)
    timeHost:EnableMouse(false)
    local durationText = timeHost:CreateFontString(nil, "OVERLAY")
    durationText:SetWordWrap(false)
    durationText:Hide()
    local stacksText = timeHost:CreateFontString(nil, "OVERLAY")
    stacksText:SetWordWrap(false)
    stacksText:Hide()
    inst.timeHost = timeHost
    inst.durationText = durationText
    inst.stacksText = stacksText
    return timeHost
end

---Clears SetDurationText when combat/protection allows.
---@param inst AuraTrackerBarInstance
---@param button Frame
---@return boolean
local function ClearDurationTextBinding(inst, button)
    if not inst.durationTextBound or not CanTouchAuraButton(inst, button) then
        return false
    end
    local cleared = pcall(function()
        button:ClearDurationText()
    end)
    if cleared then
        inst.durationTextBound = nil
    end
    return cleared
end

---Clears SetApplicationCount when combat/protection allows.
---@param inst AuraTrackerBarInstance
---@param button Frame
---@return boolean
local function ClearStacksTextBinding(inst, button)
    if not inst.stacksTextBound or not CanTouchAuraButton(inst, button) then
        return false
    end
    local cleared = pcall(function()
        button:ClearApplicationCount()
    end)
    if cleared then
        inst.stacksTextBound = nil
    end
    return cleared
end

---Binds or clears duration and stack text independently of progress mode.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function ApplyValueText(inst, button)
    local trackerId = inst.trackerId
    local host = EnsureTimeHost(inst, button)
    local border = EnsureBorderFrame(inst, button)
    host:SetFrameLevel(border:GetFrameLevel() + 1)

    local showDuration = AuraTracker:IsTextDisplayEnabled(trackerId, Schema.TEXT_DURATION)
    local showStacks = AuraTracker:IsTextDisplayEnabled(trackerId, Schema.TEXT_STACKS)
    -- Style before bind: SetDurationText / SetApplicationCount immediately refresh display.
    Chrome.ApplyTextDisplayAppearance(trackerId, Schema.TEXT_DURATION, inst.durationText)
    Chrome.ApplyTextDisplayAppearance(trackerId, Schema.TEXT_STACKS, inst.stacksText)

    if not showDuration then
        ClearDurationTextBinding(inst, button)
        inst.durationText:Hide()
    else
        inst.durationText:Show()
    end
    if not showStacks then
        ClearStacksTextBinding(inst, button)
        inst.stacksText:Hide()
    else
        inst.stacksText:Show()
    end

    if not CanTouchAuraButton(inst, button) then
        return
    end

    if showDuration and not inst.durationTextBound then
        local ok = pcall(function()
            button:SetDurationText(inst.durationText, Aura.GetDurationTextOptions())
        end)
        if ok then
            inst.durationTextBound = true
        end
    end
    if showStacks and not inst.stacksTextBound then
        local ok = pcall(function()
            button:SetApplicationCount(inst.stacksText, Aura.GetApplicationCountOptions())
        end)
        if ok then
            inst.stacksTextBound = true
        end
    end
end

---Switches the shared StatusBar between SetDurationBar and SetApplicationBar.
---@param inst AuraTrackerBarInstance
---@param button Frame
local function SyncBarBinding(inst, button)
    local bar = inst.durationBar
    if not bar or not CanTouchAuraButton(inst, button) then
        return
    end
    local trackerId = inst.trackerId
    local desiredMode = AuraTracker:GetProgressMode(trackerId)
    local maxStacks = AuraTracker:GetMaxStacks(trackerId)
    if
        inst.barBoundMode == desiredMode
        and (desiredMode ~= Schema.PROGRESS_MODE_STACKS or inst.barBoundMaxStacks == maxStacks)
    then
        return
    end

    if inst.barBoundMode == Schema.PROGRESS_MODE_DURATION then
        pcall(function()
            button:ClearDurationBar()
        end)
    elseif inst.barBoundMode == Schema.PROGRESS_MODE_STACKS then
        pcall(function()
            button:ClearApplicationBar()
        end)
    end
    inst.barBoundMode = nil
    inst.barBoundMaxStacks = nil

    local ok = pcall(function()
        if desiredMode == Schema.PROGRESS_MODE_STACKS then
            button:SetApplicationBar(bar, Aura.GetApplicationBarOptions(maxStacks))
        else
            button:SetDurationBar(bar, Aura.GetDurationBarOptions())
        end
    end)
    if ok then
        inst.barBoundMode = desiredMode
        if desiredMode == Schema.PROGRESS_MODE_STACKS then
            inst.barBoundMaxStacks = maxStacks
        end
    end
end

---@param inst AuraTrackerBarInstance|nil
function Appearance.Apply(inst)
    local started = Profile.Start()
    if not inst then
        Profile.Stop("bar.applyAppearance", started)
        return
    end
    local trackerId = inst.trackerId
    if inst.editing then
        ResizeLayoutHost(inst)
        Preview.ApplyAppearance(inst)
        -- Restart so mode / maxStacks changes take effect while layout-editing.
        Preview.StartAnimation(inst)
        Profile.Stop("bar.applyAppearance", started)
        return
    end
    if not inst.slotFrame or not inst.durationBar or not inst.backgroundTexture then
        Profile.Stop("bar.applyAppearance", started)
        return
    end

    ApplyLayout(inst, inst.slotFrame)
    -- The fill bar is bound to secret aura progress, so texture and color calls fail the same
    -- way SetSize does on the slot. Host size is already updated; the rest waits until access returns.
    if not CanTouchAuraButton(inst, inst.slotFrame) or not Aura.CanAccessObject(inst.durationBar) then
        -- Secret aura access can block the first paint. A later refresh retries until it sticks.
        inst.appearanceReady = false
        Profile.Stop("bar.applyAppearance", started)
        return
    end
    Chrome.ApplyBarChrome(
        trackerId,
        inst.durationBar,
        inst.backgroundTexture,
        EnsureBorderFrame(inst, inst.slotFrame),
        nil,
        nil
    )
    inst.stackDividerHost = Chrome.EnsureStackDividerHost(inst.slotFrame, inst.stackDividerHost)
    inst.stackDividers = inst.stackDividers or {}
    Chrome.ApplyStackDividers(trackerId, inst.stackDividerHost, inst.stackDividers, inst.durationBar)
    SyncBarBinding(inst, inst.slotFrame)
    ApplyValueText(inst, inst.slotFrame)
    -- Snapshot only after the paint. A blocked attempt leaves the previous snapshot so the
    -- settings page can see which saved fields are still waiting.
    if AuraTracker:HasTracker(trackerId) then
        inst.appliedAppearance = AuraTracker:CaptureDeferredAppearance(trackerId)
    end
    inst.appearanceReady = true
    Profile.Stop("bar.applyAppearance", started)
end

---Saved appearance fields that have not been painted onto this live bar.
---@param inst AuraTrackerBarInstance|nil
---@return table<string, boolean>
function Appearance.PendingKeys(inst)
    if not inst or inst.appearanceReady ~= false or not inst.appliedAppearance then
        return {}
    end
    local trackerId = inst.trackerId
    if not AuraTracker:HasTracker(trackerId) then
        return {}
    end
    return AuraTracker.DiffDeferredAppearance(inst.appliedAppearance, AuraTracker:CaptureDeferredAppearance(trackerId))
end

---Paints a look that combat blocked earlier. One call per update; no extra timer or event.
---@param inst AuraTrackerBarInstance
function Appearance.Flush(inst)
    if inst.editing or inst.appearanceReady ~= false or not inst.slotFrame or not inst.durationBar then
        return
    end
    if not CanConfigureFrames(inst) or not Aura.CanAccessObject(inst.slotFrame) then
        Profile.Inc("bar.flushBlocked")
        return
    end
    if not Aura.CanAccessObject(inst.durationBar) then
        Profile.Inc("bar.flushBlocked")
        return
    end
    Profile.Inc("bar.flushApply")
    Appearance.Apply(inst)
end

---Creates the shared StatusBar once; native duration/stacks binding is applied in SyncBarBinding.
---@param inst AuraTrackerBarInstance
---@param button Frame
function Appearance.BindProgressBar(inst, button)
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
    Appearance.Apply(inst)
end

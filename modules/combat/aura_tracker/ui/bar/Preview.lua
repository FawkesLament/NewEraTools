local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Assets = ns.Assets
local Chrome = Internals.BarChromeUI

local AuraTracker = ns.Modules.Get("AuraTracker")
local Schema = Internals.Schema

-- One full deplete cycle while layout-editing; loops for a living preview.
local PREVIEW_DURATION = 4

local Preview = {}
Internals.BarPreviewUI = Preview

---@param inst AuraTrackerBarInstance
---@param parent Frame
local function EnsurePreviewBorder(inst, parent)
    if inst.previewBorder then
        return inst.previewBorder
    end
    local border = CreateFrame("Frame", nil, parent, Assets.Templates.BACKDROP)
    border:SetAllPoints(parent)
    border:SetBackdrop(Chrome.LineBackdrop(1))
    border:SetBackdropColor(0, 0, 0, 0)
    border:EnableMouse(false)
    inst.previewBorder = border
    return border
end

---Child frames paint over the bar's own font strings, so preview text needs a host above the dividers.
---@param inst AuraTrackerBarInstance
local function EnsurePreviewValueTexts(inst)
    if not inst.previewTextHost then
        local host = CreateFrame("Frame", nil, inst.previewBar)
        host:SetAllPoints(inst.previewBar)
        host:EnableMouse(false)
        inst.previewTextHost = host
    end
    if not inst.previewDurationText then
        local durationText = inst.previewTextHost:CreateFontString(nil, "OVERLAY")
        durationText:SetWordWrap(false)
        inst.previewDurationText = durationText
    end
    if not inst.previewStacksText then
        local stacksText = inst.previewTextHost:CreateFontString(nil, "OVERLAY")
        stacksText:SetWordWrap(false)
        inst.previewStacksText = stacksText
    end
end

---@param inst AuraTrackerBarInstance
local function RaisePreviewTextHost(inst)
    local host = inst.previewTextHost
    if not host or not inst.previewBar then
        return
    end
    local level = inst.previewBar:GetFrameLevel()
    if inst.previewBorder then
        level = math.max(level, inst.previewBorder:GetFrameLevel())
    end
    if inst.previewStackDividerHost then
        level = math.max(level, inst.previewStackDividerHost:GetFrameLevel())
    end
    host:SetFrameLevel(level + 1)
end

---Paints the fake bar. The layout host's size is owned by the live bar.
---@param inst AuraTrackerBarInstance
function Preview.ApplyAppearance(inst)
    local trackerId = inst.trackerId
    if not inst.previewBar or not inst.previewBackground then
        return
    end
    EnsurePreviewValueTexts(inst)
    Chrome.ApplyBarChrome(
        trackerId,
        inst.previewBar,
        inst.previewBackground,
        EnsurePreviewBorder(inst, inst.previewBar),
        inst.previewDurationText,
        inst.previewStacksText
    )
    inst.previewStackDividerHost = Chrome.EnsureStackDividerHost(inst.previewBar, inst.previewStackDividerHost)
    inst.previewStackDividers = inst.previewStackDividers or {}
    Chrome.ApplyStackDividers(trackerId, inst.previewStackDividerHost, inst.previewStackDividers, inst.previewBar)
    RaisePreviewTextHost(inst)
end

---@param inst AuraTrackerBarInstance
local function EnsurePreviewBar(inst)
    if inst.previewBar then
        return inst.previewBar
    end
    local previewBar = CreateFrame("StatusBar", nil, inst.layoutHost)
    previewBar:SetAllPoints(inst.layoutHost)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:EnableMouse(false)

    local previewBackground = previewBar:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetAllPoints(previewBar)
    previewBar:Hide()

    inst.previewBar = previewBar
    inst.previewBackground = previewBackground
    return previewBar
end

---Builds the fake bar on `inst.layoutHost`, paints it, and shows it. Does not start the animation.
---@param inst AuraTrackerBarInstance
function Preview.Show(inst)
    if not inst.layoutHost then
        return
    end
    EnsurePreviewBar(inst)
    Preview.ApplyAppearance(inst)
    inst.previewBar:Show()
end

---Loops a mode-aware preview: progress follows tracking mode; texts update independently.
---@param inst AuraTrackerBarInstance
function Preview.StartAnimation(inst)
    if not inst.previewBar then
        return
    end
    local trackerId = inst.trackerId
    local stacksMode = AuraTracker:IsStacksMode(trackerId)
    local maxStacks = AuraTracker:GetMaxStacks(trackerId)
    EnsurePreviewValueTexts(inst)
    inst.previewElapsed = 0
    if stacksMode then
        inst.previewBar:SetMinMaxValues(0, maxStacks)
        inst.previewBar:SetValue(0)
    else
        inst.previewBar:SetMinMaxValues(0, 1)
        inst.previewBar:SetValue(1)
    end
    inst.previewBar:SetScript("OnUpdate", function(self, elapsed)
        inst.previewElapsed = inst.previewElapsed + elapsed
        local progress = (inst.previewElapsed % PREVIEW_DURATION) / PREVIEW_DURATION
        local remaining = PREVIEW_DURATION * (1 - progress)
        -- Hold each whole stack, then jump. A fractional SetValue would slide the fill.
        local stackCount = math.floor(progress * (maxStacks + 1))
        if stackCount > maxStacks then
            stackCount = maxStacks
        end
        if stacksMode then
            self:SetValue(stackCount)
        else
            self:SetValue(1 - progress)
        end
        if inst.previewDurationText and AuraTracker:IsTextDisplayEnabled(trackerId, Schema.TEXT_DURATION) then
            inst.previewDurationText:SetText(AuraTracker:FormatRemainingTime(remaining))
        end
        if inst.previewStacksText and AuraTracker:IsTextDisplayEnabled(trackerId, Schema.TEXT_STACKS) then
            local shownStacks = stacksMode and stackCount or math.max(1, math.floor(progress * maxStacks + 0.5))
            inst.previewStacksText:SetText(tostring(shownStacks))
        end
    end)
end

---Stops the loop and hides the fake bar. Leaves the layout host alone.
---@param inst AuraTrackerBarInstance
function Preview.Hide(inst)
    if not inst.previewBar then
        return
    end
    inst.previewBar:SetScript("OnUpdate", nil)
    inst.previewBar:Hide()
end

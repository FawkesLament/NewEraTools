local _, ns = ...
local Assets = ns.Assets
local LayoutEditor = ns.LayoutEditor
local Chrome = ns.AuraTrackerBarChromeUI

local AuraTracker = ns.Modules.Get("AuraTracker")

-- One full deplete cycle while layout-editing; loops for a living preview.
local PREVIEW_DURATION = 4

local Preview = {}
ns.AuraTrackerBarPreviewUI = Preview

---@param trackerId integer
---@return string
local function LayoutId(trackerId)
    return "AuraTracker:" .. tostring(trackerId)
end

---@param inst AuraTrackerBarInstance
---@return boolean
local function CanConfigureFrames(inst)
    return ns.AuraTrackerBarUI.CanConfigureFrames(inst)
end

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

---@param inst AuraTrackerBarInstance
local function EnsurePreviewTimeText(inst)
    if inst.previewTimeText then
        return inst.previewTimeText
    end
    local timeText = inst.previewBar:CreateFontString(nil, "OVERLAY")
    timeText:SetWordWrap(false)
    inst.previewTimeText = timeText
    return timeText
end

---@param inst AuraTrackerBarInstance
function Preview.ApplyAppearance(inst)
    local trackerId = inst.trackerId
    if not inst.previewBar or not inst.previewBackground or not inst.layoutHost then
        return
    end
    local width, height = Chrome.BarSize(trackerId)
    inst.layoutHost:SetSize(width, height)
    Chrome.ApplyBarChrome(
        trackerId,
        inst.previewBar,
        inst.previewBackground,
        EnsurePreviewBorder(inst, inst.previewBar),
        EnsurePreviewTimeText(inst)
    )
    inst.previewStackDividerHost = Chrome.EnsureStackDividerHost(inst.previewBar, inst.previewStackDividerHost)
    inst.previewStackDividers = inst.previewStackDividers or {}
    Chrome.ApplyStackDividers(trackerId, inst.previewStackDividerHost, inst.previewStackDividers, inst.previewBar)
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

---Loops a mode-aware preview: duration depletes; stacks fill toward maxStacks.
---@param inst AuraTrackerBarInstance
function Preview.StartAnimation(inst)
    if not inst.previewBar then
        return
    end
    local trackerId = inst.trackerId
    local stacksMode = AuraTracker:IsStacksMode(trackerId)
    local maxStacks = AuraTracker:GetMaxStacks(trackerId)
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
        if stacksMode then
            local value = progress * maxStacks
            self:SetValue(value)
            if inst.previewTimeText and AuraTracker:GetShowTime(trackerId) then
                inst.previewTimeText:SetText(tostring(math.floor(value + 0.5)))
            end
        else
            self:SetValue(1 - progress)
            if inst.previewTimeText and AuraTracker:GetShowTime(trackerId) then
                local remaining = PREVIEW_DURATION * (1 - progress)
                inst.previewTimeText:SetText(AuraTracker:FormatRemainingTime(remaining))
            end
        end
    end)
end

---@param inst AuraTrackerBarInstance
function Preview.StopAnimation(inst)
    if not inst.previewBar then
        return
    end
    inst.previewBar:SetScript("OnUpdate", nil)
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
        onEditBegin = function()
            inst.editing = true
            EnsurePreviewBar(inst)
            Preview.ApplyAppearance(inst)
            LayoutEditor.ApplyPosition(inst.layoutHost, AuraTracker:GetPosition(trackerId))
            if inst.container and CanConfigureFrames(inst) then
                pcall(function()
                    inst.container:SetEnabled(false)
                    inst.container:Hide()
                end)
            end
            inst.previewBar:Show()
            inst.layoutHost:Show()
            inst.layoutHost:Raise()
            Preview.StartAnimation(inst)
        end,
        onEditEnd = function()
            inst.editing = false
            Preview.StopAnimation(inst)
            if inst.previewBar then
                inst.previewBar:Hide()
            end
            ns.AuraTrackerBarUI.Update(trackerId)
        end,
    })
end

---@param inst AuraTrackerBarInstance
function Preview.RefreshLayoutLabel(inst)
    if not inst.layoutHost then
        return
    end
    local label = AuraTracker:GetDisplayName(inst.trackerId)
    if inst.layoutRegistered and inst.layoutLabel == label then
        return
    end
    if inst.layoutRegistered then
        LayoutEditor.Unregister(LayoutId(inst.trackerId))
        inst.layoutRegistered = false
    end
    inst.layoutLabel = label
    RegisterLayoutElement(inst)
end

---Creates the outer layout host and registers it with LayoutEditor. `inst` must already exist.
---@param inst AuraTrackerBarInstance
---@return Frame
function Preview.EnsureLayoutHost(inst)
    if inst.layoutHost then
        return inst.layoutHost
    end
    local trackerId = inst.trackerId
    local layoutHost = CreateFrame("Frame", ns.ADDON_NAME .. "AuraTrackerLayout" .. trackerId, UIParent)
    -- MEDIUM keeps Blizzard DIALOG/TOOLTIP menus above the bar.
    layoutHost:SetFrameStrata("MEDIUM")
    layoutHost:EnableMouse(false)
    layoutHost:SetMovable(true)
    layoutHost:SetClampedToScreen(true)
    local width, height = Chrome.BarSize(trackerId)
    layoutHost:SetSize(width, height)
    LayoutEditor.ApplyPosition(layoutHost, AuraTracker:GetPosition(trackerId))
    layoutHost:Hide()
    inst.layoutHost = layoutHost
    RegisterLayoutElement(inst)
    return layoutHost
end

---Stops preview animation, unregisters LayoutEditor, and hides the layout host.
---@param inst AuraTrackerBarInstance
function Preview.Teardown(inst)
    Preview.StopAnimation(inst)
    if inst.layoutRegistered then
        LayoutEditor.Unregister(LayoutId(inst.trackerId))
        inst.layoutRegistered = false
    end
    if inst.layoutHost then
        inst.layoutHost:Hide()
        inst.layoutHost:EnableMouse(false)
    end
end

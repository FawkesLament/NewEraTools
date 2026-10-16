local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes

-- Matches Widgets' disabled button fade.
local DISABLED_ALPHA = 0.4

local FeatureSection = {}
ns.FeatureSection = FeatureSection

---@class FeatureSectionOptions
---@field title string  Shown in the header to the left of the On/Off toggle.
---@field tooltip string|nil  Shown when hovering the title.
---@field enabled boolean|nil  Whether the feature starts enabled. Defaults to true.
---@field onEnabledChanged fun(enabled: boolean)|nil  After the enabled state changes via the toggle or SetEnabled.
---@field spacingBefore number|nil  Gap above this section in the stack; defaults to the stack's spacing.
---@field onStackHeightChanged fun(stackHeight: number)|nil  After the stack's total height changes.

---@class FeatureSection: Frame
---@field content Frame  Parent for feature-specific widgets; dimmed and non-interactive when disabled.
---@field titleLabel FontString  Header title; callers may anchor a marker beside it.
---@field isFeatureSection boolean
---@field SetEnabled fun(self: FeatureSection, enabled: boolean)
---@field IsEnabled fun(self: FeatureSection): boolean
---@field SetParentFeatureEnabled fun(self: FeatureSection, parentEnabled: boolean)  Nested gating; does not change On/Off.
---@field SetContentHeight fun(self: FeatureSection, height: number)  Height of `content`.
---@field GetHeight fun(self: FeatureSection): number
---@field RefreshContentInteractive fun(self: FeatureSection)  Re-applies enable/disable to content after the caller changes controls.

---Disables clickable descendants without stacking another fade on top of a dimmed parent.
---Nested FeatureSections are gated via SetParentFeatureEnabled so their own On/Off is preserved.
---
---Alpha policy: while the feature is off, interactive children are forced opaque so only
---`content`'s dim shows. While on, enabled children are opaque; children that stay disabled
---(custom SetEnabled locks) get DISABLED_ALPHA. Walking into a locked child uses `enabled=false`
---so nested SetEnabled targets (e.g. dropdown triggers) stay gated but opaque under that fade.
---@param frame Frame
---@param enabled boolean
function FeatureSection.SetSubtreeInteractive(frame, enabled)
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.isFeatureSection then
            child:SetParentFeatureEnabled(enabled)
        elseif child.SetEnabled then
            child:SetEnabled(enabled)
            if not enabled then
                child:SetAlpha(1)
                FeatureSection.SetSubtreeInteractive(child, false)
            elseif not child.IsEnabled or child:IsEnabled() then
                child:SetAlpha(1)
                FeatureSection.SetSubtreeInteractive(child, true)
            else
                child:SetAlpha(DISABLED_ALPHA)
                FeatureSection.SetSubtreeInteractive(child, false)
            end
        else
            FeatureSection.SetSubtreeInteractive(child, enabled)
        end
    end
end

---Creates a feature block parented to `stack.container` and mounted in `stack` immediately.
---SetContentHeight keeps that stack entry in sync. The frame parent is always the stack container.
---@param stack LayoutStack
---@param options FeatureSectionOptions
---@return FeatureSection
function FeatureSection.Create(stack, options)
    assert(
        type(stack) == "table" and type(stack.Add) == "function" and type(stack.SetEntryHeight) == "function",
        "FeatureSection.Create requires a Layout.Stack"
    )
    assert(stack.container ~= nil, "FeatureSection.Create requires stack.container")
    assert(type(options) == "table" and type(options.title) == "string", "FeatureSection requires a title")

    local parent = stack.container
    local section = CreateFrame("Frame", nil, parent) --[[@as FeatureSection]]
    section.isFeatureSection = true
    local inner = Layout.Stack(section)
    local header = inner:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local content = inner:Add(CreateFrame("Frame", nil, section), 0)
    section.content = content

    local enabled = options.enabled ~= false
    -- When nested under another FeatureSection, the parent gates interaction without changing On/Off.
    local parentFeatureEnabled = true
    local contentHeight = 0
    local toggle

    local function NotifyHeight()
        stack:SetEntryHeight(section, inner:GetHeight())
        if options.onStackHeightChanged then
            options.onStackHeightChanged(stack:GetHeight())
        end
    end

    local function ApplyContentInteractive()
        local interactive = enabled and parentFeatureEnabled
        content:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        FeatureSection.SetSubtreeInteractive(content, interactive)
        if toggle then
            toggle:SetEnabled(parentFeatureEnabled)
            toggle:SetAlpha(1)
        end
    end

    local function ApplyContentHeight()
        inner:SetEntryHeight(content, contentHeight)
        NotifyHeight()
    end

    local title = Widgets.CreateLabel(header, Fonts.BODY, options.title)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", header, "LEFT")
    section.titleLabel = title
    if options.tooltip then
        -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
        local hit = CreateFrame("Frame", nil, header)
        hit:SetPoint("TOPLEFT", title, "TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT")
        hit:EnableMouse(true)
        Widgets.AttachTooltip(hit, "ANCHOR_TOP", function(tooltip)
            tooltip:SetText(options.tooltip)
        end)
    end

    toggle = Widgets.CreateSegmentedControl(header, {
        { value = true, text = L.FEATURE_ON },
        { value = false, text = L.FEATURE_OFF },
    }, function(value)
        section:SetEnabled(value)
    end)
    toggle:SetPoint("RIGHT", header, "RIGHT")
    toggle:SetSelected(enabled)

    function section:IsEnabled()
        return enabled
    end

    function section:SetEnabled(value)
        value = value == true
        if enabled == value then
            ApplyContentInteractive()
            return
        end
        enabled = value
        toggle:SetSelected(enabled)
        ApplyContentInteractive()
        if options.onEnabledChanged then
            options.onEnabledChanged(enabled)
        end
    end

    ---Called by a parent FeatureSection so nesting does not overwrite this section's On/Off.
    ---@param parentEnabled boolean
    function section:SetParentFeatureEnabled(parentEnabled)
        parentFeatureEnabled = parentEnabled == true
        ApplyContentInteractive()
    end

    function section:SetContentHeight(height)
        assert(type(height) == "number" and height >= 0, "Bad content height")
        contentHeight = height
        ApplyContentHeight()
    end

    function section:GetHeight()
        return inner:GetHeight()
    end

    function section:RefreshContentInteractive()
        ApplyContentInteractive()
    end

    -- Mount before the first NotifyHeight so SetEntryHeight is always valid.
    stack:Add(section, inner:GetHeight(), options.spacingBefore)

    ApplyContentInteractive()
    ApplyContentHeight()
    return section
end

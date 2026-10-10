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
---@field onHeightChanged fun(height: number)|nil  After the section's total height changes.

---@class FeatureSection: Frame
---@field content Frame  Parent for feature-specific widgets; dimmed and non-interactive when disabled.
---@field SetEnabled fun(self: FeatureSection, enabled: boolean)
---@field IsEnabled fun(self: FeatureSection): boolean
---@field SetContentHeight fun(self: FeatureSection, height: number)  Height of `content`.
---@field GetHeight fun(self: FeatureSection): number
---@field RefreshContentInteractive fun(self: FeatureSection)  Re-applies enable/disable to content after the caller changes controls.

---Disables clickable descendants without stacking another fade on top of a dimmed parent.
---@param frame Frame
---@param enabled boolean
function FeatureSection.SetSubtreeInteractive(frame, enabled)
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.SetEnabled then
            child:SetEnabled(enabled)
            -- Widgets buttons fade on disable; keep them opaque so only the parent dim shows.
            child:SetAlpha(1)
        end
        FeatureSection.SetSubtreeInteractive(child, enabled)
    end
end

---Creates a feature block: title + On/Off on the header, grouped content below.
---@param parent Frame
---@param options FeatureSectionOptions
---@return FeatureSection
function FeatureSection.Create(parent, options)
    assert(type(options) == "table" and type(options.title) == "string", "FeatureSection requires a title")

    local section = CreateFrame("Frame", nil, parent) --[[@as FeatureSection]]
    local stack = Layout.Stack(section)
    local header = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local content = stack:Add(CreateFrame("Frame", nil, section), 0)
    section.content = content

    local enabled = options.enabled ~= false
    local contentHeight = 0
    -- Suppress height callbacks until Create returns, so callers can insert the section into a stack first.
    local ready = false

    local function NotifyHeight()
        if ready and options.onHeightChanged then
            options.onHeightChanged(stack:GetHeight())
        end
    end

    local function ApplyContentInteractive()
        content:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        FeatureSection.SetSubtreeInteractive(content, enabled)
    end

    local function ApplyContentHeight()
        stack:SetEntryHeight(content, contentHeight)
        NotifyHeight()
    end

    local title = Widgets.CreateLabel(header, Fonts.BODY, options.title)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", header, "LEFT")
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

    local toggle = Widgets.CreateSegmentedControl(header, {
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

    function section:SetContentHeight(height)
        assert(type(height) == "number" and height >= 0, "Bad content height")
        contentHeight = height
        ApplyContentHeight()
    end

    function section:GetHeight()
        return stack:GetHeight()
    end

    function section:RefreshContentInteractive()
        ApplyContentInteractive()
    end

    ApplyContentInteractive()
    ApplyContentHeight()
    ready = true
    return section
end

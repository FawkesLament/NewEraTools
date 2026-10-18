local _, ns = ...
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

-- Diameter of the circular count badge; grows with the label so two-digit counts stay round.
local BADGE_SIZE = 16

local CollapsibleSection = {}
ns.CollapsibleSection = CollapsibleSection

---@class CollapsibleSectionOptions
---@field title string  Shown in the clickable header.
---@field hint string|nil  Muted text on the header, to the right of the title.
---@field expanded boolean|nil  Whether the section starts expanded. Defaults to true.
---@field spacingBefore number|nil  Gap above this section in the stack; defaults to the stack's spacing.
---@field onStackHeightChanged fun(stackHeight: number)|nil  After the stack's total height changes.
---@field onExpandedChanged fun(expanded: boolean)|nil  After expand/collapse via the header or SetExpanded.

---@class CollapsibleSection: Frame
---@field content Frame  Parent for section widgets; hidden when collapsed (settings unchanged).
---@field isCollapsibleSection boolean
---@field SetExpanded fun(self: CollapsibleSection, expanded: boolean)
---@field IsExpanded fun(self: CollapsibleSection): boolean
---@field SetBadge fun(self: CollapsibleSection, text: string|nil)  Small circular count after the title; nil/"" hides it.
---@field SetHeaderAction fun(self: CollapsibleSection, frame: Frame)  Right-aligns one compact control on the header.
---@field SetContentHeight fun(self: CollapsibleSection, height: number)  Height of `content` when expanded.
---@field GetHeight fun(self: CollapsibleSection): number

---Creates a collapsible block parented to `stack.container` and mounted in `stack` immediately.
---Collapse only hides content; it never disables controls or changes saved settings.
---@param stack LayoutStack
---@param options CollapsibleSectionOptions
---@return CollapsibleSection
function CollapsibleSection.Create(stack, options)
    assert(
        type(stack) == "table" and type(stack.Add) == "function" and type(stack.SetEntryHeight) == "function",
        "CollapsibleSection.Create requires a Layout.Stack"
    )
    assert(stack.container ~= nil, "CollapsibleSection.Create requires stack.container")
    assert(type(options) == "table" and type(options.title) == "string", "CollapsibleSection requires a title")

    local parent = stack.container
    local section = CreateFrame("Frame", nil, parent) --[[@as CollapsibleSection]]
    section.isCollapsibleSection = true
    local inner = Layout.Stack(section)
    local header = inner:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local content = inner:Add(CreateFrame("Frame", nil, section), 0)
    section.content = content

    local expanded = options.expanded ~= false
    local contentHeight = 0
    local expandButton
    local headerAction
    local headerAction

    local function NotifyHeight()
        stack:SetEntryHeight(section, inner:GetHeight())
        if options.onStackHeightChanged then
            options.onStackHeightChanged(stack:GetHeight())
        end
    end

    local function ApplyExpanded()
        expandButton:SetExpanded(expanded)
        if expanded then
            content:Show()
            inner:SetEntryHeight(content, contentHeight)
        else
            content:Hide()
            inner:SetEntryHeight(content, 0)
        end
        NotifyHeight()
    end

    expandButton = Widgets.CreateExpandButton(header, function()
        section:SetExpanded(not expanded)
    end)
    expandButton:SetLabel(options.title)
    expandButton:SetPoint("LEFT", header, "LEFT")

    local badge = CreateFrame("Frame", nil, header)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("LEFT", expandButton, "RIGHT", Spacing.SMALL, 0)
    badge:Hide()
    local badgeFill = badge:CreateTexture(nil, "BACKGROUND")
    badgeFill:SetAllPoints()
    badgeFill:SetColorTexture(Widgets.UnpackColor(Colors.SURFACE_RAISED))
    local badgeMask = badge:CreateMaskTexture()
    badgeMask:SetAllPoints()
    badgeMask:SetTexture(Assets.Textures.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    badgeFill:AddMaskTexture(badgeMask)
    local badgeLabel = Widgets.CreateLabel(badge, Fonts.TINY_MUTED)
    badgeLabel:SetJustifyH("CENTER")
    badgeLabel:SetPoint("CENTER")

    local hint
    if type(options.hint) == "string" and options.hint ~= "" then
        hint = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, options.hint)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(false)
    end

    ---The badge shares the gap after the title, so the hint follows whichever of them is showing.
    ---A header action keeps the right edge, and the hint stops short of it.
    local function PlaceHint()
        if not hint then
            return
        end
        hint:ClearAllPoints()
        local anchor = badge:IsShown() and badge or expandButton
        hint:SetPoint("LEFT", anchor, "RIGHT", Spacing.MEDIUM, 0)
        if headerAction then
            hint:SetPoint("RIGHT", headerAction, "LEFT", -Spacing.MEDIUM, 0)
        else
            hint:SetPoint("RIGHT", header, "RIGHT")
        end
    end

    function section:IsExpanded()
        return expanded
    end

    function section:SetExpanded(value)
        value = value == true
        if expanded == value then
            ApplyExpanded()
            return
        end
        expanded = value
        ApplyExpanded()
        if options.onExpandedChanged then
            options.onExpandedChanged(expanded)
        end
    end

    ---Right-aligns `frame` on the header. One action at a time; a later call replaces the anchor.
    ---@param frame Frame
    function section:SetHeaderAction(frame)
        assert(
            type(frame) == "table" and type(frame.SetPoint) == "function",
            "CollapsibleSection header action must be a frame"
        )
        frame:SetParent(header)
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", header, "RIGHT")
        headerAction = frame
        PlaceHint()
    end

    ---@param text string|nil
    function section:SetBadge(text)
        if type(text) ~= "string" or text == "" then
            badge:Hide()
            PlaceHint()
            return
        end
        badgeLabel:SetText(text)
        local size = math.max(badgeLabel:GetStringWidth() + Spacing.SMALL, BADGE_SIZE)
        badge:SetSize(size, size)
        badge:Show()
        PlaceHint()
    end

    function section:SetContentHeight(height)
        assert(type(height) == "number" and height >= 0, "Bad content height")
        contentHeight = height
        ApplyExpanded()
    end

    function section:GetHeight()
        return inner:GetHeight()
    end

    PlaceHint()

    -- Mount before the first NotifyHeight so SetEntryHeight is always valid.
    stack:Add(section, inner:GetHeight(), options.spacingBefore)

    ApplyExpanded()
    return section
end

local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local ActionFooter = {}
ns.ActionFooter = ActionFooter

local ICON_SIZE = 14
local DIVIDER_HEIGHT = 1
local ICON_GAP = Spacing.SMALL
local BUTTON_GAP = Spacing.LARGE
-- Air between the hairline and the button, and between a wrapped message and the button.
local CONTENT_GAP = Spacing.MEDIUM
local MESSAGE_LINE = Assets.FontStyles[Fonts.SMALL_MUTED].size

local SEVERITY = {
    warning = { color = Colors.WARNING, icon = Assets.Icons.WARNING },
    error = { color = Colors.ERROR, icon = Assets.Icons.READY_CHECK_NOT_READY },
    success = { color = Colors.SUCCESS, icon = Assets.Icons.READY_CHECK_READY },
    info = { color = Colors.TEXT_MUTED, icon = Assets.Icons.INFO },
}

---@alias ActionFooterSeverity "warning"|"error"|"success"|"info"

---@class ActionFooterMessage
---@field text string
---@field severity ActionFooterSeverity

---@class ActionFooterOptions
---@field text string  Primary action label. The button stays as wide as this text.
---@field onClick fun()
---@field variant ButtonVariant|nil  Passed to CreateButton. Defaults to accent, whose disabled state is neutral.
---@field onHeightChanged fun(height: number)|nil  After the height changes once the footer has been returned.

---@class ActionFooter: Frame
---@field button Button  The parent enables, disables, and clicks this. Disabled accent buttons are neutral.
---@field SetMessage fun(self: ActionFooter, message: ActionFooterMessage|nil)
---@field GetHeight fun(self: ActionFooter): number

---@param label FontString
---@param fallback number
---@return number
local function StringHeight(label, fallback)
    local height = label:GetStringHeight()
    if type(height) == "number" and height > 0 then
        return height
    end
    return fallback
end

---Message on the left, one content-sized action on the right, with a hairline along the top.
---A message that fits stays on the action's row. A longer one wraps on its own line above the button.
---No message leaves only the hairline and the button.
---@param parent Frame
---@param options ActionFooterOptions
---@return ActionFooter
function ActionFooter.Create(parent, options)
    assert(type(options) == "table" and type(options.text) == "string", "ActionFooter requires a label")
    assert(type(options.onClick) == "function", "ActionFooter requires onClick")

    local footer = CreateFrame("Frame", nil, parent) --[[@as ActionFooter]]
    local divider = footer:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(DIVIDER_HEIGHT)
    divider:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    local icon = footer:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:Hide()

    local label = Widgets.CreateLabel(footer, Fonts.SMALL_MUTED)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:Hide()

    local button = Widgets.CreateButton(footer, options.text, options.onClick, options.variant or "accent")
    footer.button = button

    ---@type ActionFooterMessage|nil
    local message
    local height = 0
    local ready = false
    local layingOut = false

    local function ApplyHeight(nextHeight)
        if height == nextHeight then
            return
        end
        height = nextHeight
        footer:SetHeight(height)
        if ready and options.onHeightChanged then
            options.onHeightChanged(height)
        end
    end

    ---@param width number
    ---@param textWidth number
    ---@return boolean
    local function FitsInline(width, textWidth)
        if width <= 0 then
            return true
        end
        local room = width - button:GetWidth() - BUTTON_GAP - ICON_SIZE - ICON_GAP
        return textWidth <= room
    end

    local function Relayout()
        if layingOut then
            return
        end
        layingOut = true

        local contentTop = DIVIDER_HEIGHT + CONTENT_GAP
        button:ClearAllPoints()
        local text = message and message.text or ""
        if text == "" then
            icon:Hide()
            label:Hide()
            label:SetText("")
            button:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -contentTop)
            ApplyHeight(contentTop + Sizes.CONTROL_HEIGHT)
            layingOut = false
            return
        end

        icon:Show()
        label:Show()
        label:SetWordWrap(false)
        label:SetText(text)
        local width = footer:GetWidth() or 0
        if FitsInline(width, label:GetStringWidth()) then
            local room = math.max(width - button:GetWidth() - BUTTON_GAP - ICON_SIZE - ICON_GAP, 1)
            label:SetWidth(room)
            label:SetJustifyV("MIDDLE")
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", footer, "TOPLEFT", 0, -(contentTop + Sizes.CONTROL_HEIGHT / 2))
            label:ClearAllPoints()
            label:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
            button:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -contentTop)
            ApplyHeight(contentTop + Sizes.CONTROL_HEIGHT)
        else
            local textWidth = math.max(width - ICON_SIZE - ICON_GAP, 1)
            label:SetWordWrap(true)
            label:SetJustifyV("TOP")
            label:SetWidth(textWidth)
            local blockHeight = math.max(StringHeight(label, MESSAGE_LINE), ICON_SIZE)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -contentTop)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", icon, "TOPRIGHT", ICON_GAP, 0)
            local buttonTop = contentTop + blockHeight + CONTENT_GAP
            button:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -buttonTop)
            ApplyHeight(buttonTop + Sizes.CONTROL_HEIGHT)
        end

        layingOut = false
    end

    ---@param next ActionFooterMessage|nil
    function footer:SetMessage(next)
        if next == nil or (type(next) == "table" and next.text == "") then
            message = nil
            Relayout()
            return
        end
        assert(type(next) == "table" and type(next.text) == "string", "ActionFooter message requires text")
        local style = SEVERITY[next.severity]
        assert(style ~= nil, "Unknown ActionFooter severity: " .. tostring(next.severity))
        message = { text = next.text, severity = next.severity }
        icon:SetTexture(style.icon)
        label:SetTextColor(Widgets.UnpackColor(style.color))
        Relayout()
    end

    function footer:GetHeight()
        return height
    end

    -- Width arrives when the parent is shown. Height changes must not run this again.
    footer:SetScript("OnSizeChanged", function()
        Relayout()
    end)

    footer:SetMessage(nil)
    ready = true
    return footer
end

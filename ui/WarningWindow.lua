local _, ns = ...
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local TITLE_ROW_HEIGHT = 22
local HINT_ROW_HEIGHT = 16
local FOOTER_ROW_HEIGHT = 14
local ICON_SIZE = 18
-- Outside the tooltip-style edge so text/buttons aren't flush with the border art.
local CONTENT_PADDING = Spacing.LARGE

local WINDOW_BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local WarningWindow = {}
ns.WarningWindow = WarningWindow

---@class WarningWindowOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field title string
---@field hint string
---@field footer string|nil
---@field actionText string|nil  When set, shows a primary action button under the text.
---@field onAction fun()|nil  Called when the action button is clicked.
---@field scale number|nil  Initial scale. Defaults to 1.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onClick fun()|nil  Left-click when the press was not a drag.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field draggable boolean|nil  Whether dragging starts enabled. Defaults to false.
---@field closable boolean|nil  Whether a close button is shown. Defaults to false.
---@field onClose fun()|nil  Called when the close button is clicked.

---@class WarningWindow: FloatingWindow
---@field SetWarningText fun(self: WarningWindow, title: string, hint: string, footer: string|nil)

---Creates a compact amber warning overlay (icon + title + hint + optional footer/action).
---@param options WarningWindowOptions
---@return WarningWindow
function WarningWindow.Create(options)
    assert(type(options) == "table", "WarningWindow.Create requires options")
    assert(type(options.title) == "string", "WarningWindow.Create requires title")
    assert(type(options.hint) == "string", "WarningWindow.Create requires hint")
    local hasAction = type(options.actionText) == "string" and options.actionText ~= ""
    if hasAction then
        assert(type(options.onAction) == "function", "WarningWindow.Create action requires onAction")
    end

    local frame = FloatingWindow.Create({
        name = options.name,
        scale = options.scale,
        position = options.position,
        draggable = options.draggable == true,
        dragEntireFrame = true,
        onClick = options.onClick,
        onPositionChanged = options.onPositionChanged,
        closable = options.closable == true,
        onClose = options.onClose,
    }) --[[@as WarningWindow]]

    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(Widgets.UnpackColor(Colors.BG_WARNING))
    frame:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER_WARNING))

    local stack = Layout.Stack(frame, {
        paddingX = CONTENT_PADDING,
        paddingY = CONTENT_PADDING,
        spacing = Spacing.SMALL,
    })

    -- Close button sits in the FloatingWindow header over the top-right; keep title clear of it.
    local closeInset = options.closable == true and (Sizes.CLOSE_BUTTON + Spacing.SMALL) or 0

    local titleRow = stack:AddRow(TITLE_ROW_HEIGHT)
    local icon = titleRow:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexture(Assets.Icons.WARNING)
    icon:SetPoint("LEFT", titleRow, "LEFT")

    local title = Widgets.CreateLabel(titleRow, Fonts.BODY, options.title)
    title:SetTextColor(Widgets.UnpackColor(Colors.WARNING))
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetPoint("LEFT", icon, "RIGHT", Spacing.SMALL, 0)
    title:SetPoint("RIGHT", titleRow, "RIGHT", -closeInset, 0)

    local hintRow = stack:AddRow(HINT_ROW_HEIGHT)
    local hint = Widgets.CreateLabel(hintRow, Fonts.BODY, options.hint)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetPoint("LEFT", hintRow, "LEFT")
    hint:SetPoint("RIGHT", hintRow, "RIGHT", -closeInset, 0)

    local footerRow = stack:AddRow(FOOTER_ROW_HEIGHT)
    local footer = Widgets.CreateLabel(footerRow, Fonts.TINY_MUTED, options.footer or "")
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)
    footer:SetPoint("LEFT", footerRow, "LEFT")
    footer:SetPoint("RIGHT", footerRow, "RIGHT", -closeInset, 0)

    local actionButton
    local actionRow
    if hasAction then
        -- Extra gap above the button so it doesn't crowd the hint/footer.
        actionRow = stack:AddRow(Sizes.CONTROL_HEIGHT, Spacing.SMALL)
        actionButton = Widgets.CreateButton(actionRow, options.actionText, function()
            options.onAction()
        end, "warning")
        actionButton:SetPoint("CENTER", actionRow, "CENTER")
    end

    local function HasFooterText(text)
        return type(text) == "string" and text ~= ""
    end

    local function ResizeToContent()
        local contentWidth = math.max(
            ICON_SIZE + Spacing.SMALL + title:GetStringWidth(),
            hint:GetStringWidth(),
            HasFooterText(footer:GetText()) and footer:GetStringWidth() or 0,
            actionButton and actionButton:GetWidth() or 0
        ) + closeInset
        frame:SetSize(contentWidth + 2 * CONTENT_PADDING, stack:GetHeight())
    end

    local function ApplyFooter(text)
        if HasFooterText(text) then
            footer:SetText(text)
            footerRow:Show()
            stack:SetEntryHeight(footerRow, FOOTER_ROW_HEIGHT)
        else
            footer:SetText("")
            footerRow:Hide()
            stack:SetEntryHeight(footerRow, 0)
        end
    end

    ---Updates the visible strings and resizes the window to fit.
    ---@param nextTitle string
    ---@param nextHint string
    ---@param nextFooter string|nil
    function frame:SetWarningText(nextTitle, nextHint, nextFooter)
        assert(type(nextTitle) == "string", "Bad warning title")
        assert(type(nextHint) == "string", "Bad warning hint")
        title:SetText(nextTitle)
        hint:SetText(nextHint)
        ApplyFooter(nextFooter)
        ResizeToContent()
    end

    ApplyFooter(options.footer)
    ResizeToContent()
    return frame
end

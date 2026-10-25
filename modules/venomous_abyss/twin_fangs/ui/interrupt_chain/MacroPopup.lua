local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local WINDOW_WIDTH = 420
local HEADER_GAP = Spacing.XLARGE
local DESC_GAP = Spacing.LARGE
local HEADER_OFFSET = Sizes.FLOATING_HEADER_HEIGHT + HEADER_GAP
-- Two lines so the English hint can wrap.
local DESC_HEIGHT = Assets.FontStyles[Fonts.HEADER].size * 2 + Spacing.TINY
local WINDOW_HEIGHT = 200 + 2 * Sizes.FLOATING_HEADER_PAD
local TEXT_INSET = Spacing.SMALL
local SCROLL_GUTTER = Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL
local WHEEL_STEP = 24
local PAYLOAD_HEIGHT = WINDOW_HEIGHT - HEADER_OFFSET - Spacing.LARGE - DESC_HEIGHT - DESC_GAP

local MacroPopup = {}
Internals.InterruptChainMacroPopup = MacroPopup

---@type FloatingWindow|nil
local window
---@type EditBox|nil
local box
---@type ScrollFrame|nil
local scroll
---@type FontString|nil
local measure
---@type string
local payloadText = ""
---@type number
local appliedWidth = -1

---@param text string
---@return integer
local function LineCount(text)
    local count = 1
    for _ in string.gmatch(text, "\n") do
        count = count + 1
    end
    return count
end

local function ApplyText(text)
    text = text or ""
    local width = scroll:GetWidth()
    if width < 1 then
        width = WINDOW_WIDTH - Spacing.LARGE * 2 - SCROLL_GUTTER
    end
    -- A later size pass with the same text must not clear the user's selection.
    if text == payloadText and width == appliedWidth and box:GetText() == text then
        return
    end
    payloadText = text
    appliedWidth = width
    box:SetWidth(width)
    local inner = math.max(width - TEXT_INSET * 2, 1)
    measure:SetWidth(inner)
    measure:SetText(payloadText)
    local textHeight = measure:GetStringHeight()
    if not textHeight or textHeight < 1 then
        local _, fontSize = box:GetFont()
        textHeight = LineCount(payloadText) * (fontSize or Assets.FontStyles[Fonts.PAYLOAD].size)
    end
    box:SetHeight(math.max(textHeight + TEXT_INSET * 2, scroll:GetHeight()))
    box:SetText(payloadText)
    scroll:SetVerticalScroll(0)
end

local function Ensure()
    if window then
        return window
    end
    Widgets.EnsureFonts()
    window = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "TwinFangsMacro",
        fill = Colors.BG,
        closable = true,
        onClose = function()
            window:Hide()
        end,
    })
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, window:GetName())

    local title = Widgets.CreateLabel(window.header, Fonts.TITLE, L.TWIN_FANGS_INTERRUPT_MACRO_WINDOW)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", window.header, "LEFT", Sizes.FLOATING_HEADER_PAD, 0)
    if window.closeButton then
        title:SetPoint("RIGHT", window.closeButton, "LEFT", -Sizes.FLOATING_HEADER_PAD, 0)
    else
        title:SetPoint("RIGHT", window.header, "RIGHT", -Sizes.FLOATING_HEADER_PAD, 0)
    end

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", Spacing.LARGE, -HEADER_OFFSET)
    body:SetPoint("BOTTOMRIGHT", -Spacing.LARGE, Spacing.LARGE)

    local stack = Layout.Stack(body, { spacing = DESC_GAP })

    local descRow = stack:AddRow(DESC_HEIGHT)
    local desc = Widgets.CreateLabel(descRow, Fonts.HEADER, L.TWIN_FANGS_INTERRUPT_MACRO_DESC)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetNonSpaceWrap(true)
    desc:SetPoint("TOPLEFT")
    desc:SetPoint("TOPRIGHT")

    local payload = stack:AddRow(PAYLOAD_HEIGHT)
    scroll = CreateFrame("ScrollFrame", nil, payload)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_GUTTER, 0)
    local scrollBar = CreateFrame("EventFrame", nil, payload, Assets.Templates.SCROLL_BAR)
    scrollBar:SetPoint("TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT")
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(Fonts.PAYLOAD)
    box:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
    box:SetTextInsets(TEXT_INSET, TEXT_INSET, TEXT_INSET, TEXT_INSET)
    box:SetMaxLetters(0)
    scroll:SetScrollChild(box)

    measure = window:CreateFontString(nil, "ARTWORK", Fonts.PAYLOAD)
    measure:Hide()
    measure:SetWordWrap(true)
    measure:SetNonSpaceWrap(true)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        window:Hide()
    end)
    local restoring = false
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or restoring then
            return
        end
        local cursor = self:GetCursorPosition()
        restoring = true
        self:SetText(payloadText)
        restoring = false
        if cursor > 0 then
            self:SetCursorPosition(cursor)
        end
    end)
    box:SetScript("OnMouseWheel", function(_, delta)
        local range = scroll:GetVerticalScrollRange()
        local nextScroll = scroll:GetVerticalScroll() - delta * WHEEL_STEP
        if nextScroll < 0 then
            nextScroll = 0
        elseif nextScroll > range then
            nextScroll = range
        end
        scroll:SetVerticalScroll(nextScroll)
    end)
    scroll:HookScript("OnSizeChanged", function()
        if window:IsShown() then
            ApplyText(payloadText)
        end
    end)
    return window
end

---Opens the payload window and selects all of its text.
---@param text string
function MacroPopup.Show(text)
    local frame = Ensure()
    frame:Show()
    ApplyText(text)
    box:SetFocus()
    box:HighlightText()
end

---Replaces the text while the window is already open.
---@param text string
function MacroPopup.RefreshIfShown(text)
    if window and window:IsShown() then
        ApplyText(text)
        box:HighlightText()
    end
end

function MacroPopup.Hide()
    if window then
        window:Hide()
    end
end

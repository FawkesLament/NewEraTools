local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 400
local TEXT_INSET = Spacing.SMALL
local SCROLL_GUTTER = Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL
local WHEEL_STEP = 24

local ProfileReport = {}
ns.AuraTrackerProfileReport = ProfileReport

---@type FloatingWindow|nil
local window
---@type EditBox|nil
local box
---@type ScrollFrame|nil
local scroll
---@type FontString|nil
local measure
---@type string
local reportText = ""
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
    if text == reportText and width == appliedWidth and box:GetText() == text then
        return
    end
    reportText = text
    appliedWidth = width
    box:SetWidth(width)
    local inner = math.max(width - TEXT_INSET * 2, 1)
    measure:SetWidth(inner)
    measure:SetText(reportText)
    local textHeight = measure:GetStringHeight()
    if not textHeight or textHeight < 1 then
        local _, fontSize = box:GetFont()
        textHeight = LineCount(reportText) * (fontSize or 12)
    end
    box:SetHeight(math.max(textHeight + TEXT_INSET * 2, scroll:GetHeight()))
    box:SetText(reportText)
    scroll:SetVerticalScroll(0)
end

local function Ensure()
    if window then
        return window
    end
    Widgets.EnsureFonts()
    window = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "AuraProfile",
        closable = true,
        onClose = function()
            window:Hide()
        end,
    })
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, window:GetName())

    local title = Widgets.CreateLabel(window.header, Fonts.TITLE, L.AURA_TRACKER_PROFILE_WINDOW)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", window.header, "LEFT", Spacing.MEDIUM, 0)
    if window.closeButton then
        title:SetPoint("RIGHT", window.closeButton, "LEFT", -Spacing.SMALL, 0)
    else
        title:SetPoint("RIGHT", window.header, "RIGHT", -Spacing.MEDIUM, 0)
    end

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", Spacing.LARGE, -(Sizes.CLOSE_BUTTON + Spacing.MEDIUM))
    body:SetPoint("BOTTOMRIGHT", -Spacing.LARGE, Spacing.LARGE)

    scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_GUTTER, 0)
    local scrollBar = CreateFrame("EventFrame", nil, body, Assets.Templates.SCROLL_BAR)
    scrollBar:SetPoint("TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT")
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(Fonts.BODY)
    box:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
    box:SetTextInsets(TEXT_INSET, TEXT_INSET, TEXT_INSET, TEXT_INSET)
    box:SetMaxLetters(0)
    scroll:SetScrollChild(box)

    measure = window:CreateFontString(nil, "ARTWORK", Fonts.BODY)
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
        self:SetText(reportText)
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
            ApplyText(reportText)
        end
    end)
    return window
end

---Opens the report and selects all of its text.
---@param text string
function ProfileReport.Show(text)
    local frame = Ensure()
    frame:Show()
    ApplyText(text)
    box:SetFocus()
    box:HighlightText()
end

---Replaces the text while the window is already open.
---@param text string
function ProfileReport.RefreshIfShown(text)
    if window and window:IsShown() then
        ApplyText(text)
        box:HighlightText()
    end
end

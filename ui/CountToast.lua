local _, ns = ...
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Widgets = ns.Widgets

local FontFiles = Assets.FontFiles
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

-- Compact two-line toast with a count badge. Callers own strings, visibility, and lifetime.
local CountToast = {}
ns.CountToast = CountToast

local ARHEI = "Fonts\\ARHei.ttf"
local TOAST_WIDTH = 300
local TOAST_HEIGHT = 66
local PAD_X = Spacing.LARGE
local ACCENT_WIDTH = 3
local ACCENT_HEIGHT = 34
local LINE_GAP = Spacing.SMALL
local TEXT_GAP = 10
local CLOSE_INSET = Spacing.MEDIUM
local BADGE_GAP = Spacing.MEDIUM
local BADGE_WIDTH = 54
local BADGE_HEIGHT = 32
local TITLE_SIZE = 14
local MESSAGE_SIZE = 16
local COUNT_SIZE = 20

-- Toast palette (#242831, #4A5060, #C48B57, #F0E9DD, #BCC3CF, #E9B579, #39352F).
local COLOR_BG = { r = 36 / 255, g = 40 / 255, b = 49 / 255, a = 1 }
local COLOR_BORDER = { r = 74 / 255, g = 80 / 255, b = 96 / 255, a = 1 }
local COLOR_ACCENT = { r = 196 / 255, g = 139 / 255, b = 87 / 255, a = 1 }
local COLOR_TITLE = { r = 240 / 255, g = 233 / 255, b = 221 / 255 }
local COLOR_MESSAGE = { r = 188 / 255, g = 195 / 255, b = 207 / 255 }
local COLOR_COUNT = { r = 233 / 255, g = 181 / 255, b = 121 / 255 }
local COLOR_BADGE = { r = 57 / 255, g = 53 / 255, b = 47 / 255, a = 1 }

---@class CountToastOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field title string
---@field message string
---@field count string
---@field scale number|nil  Initial scale. Defaults to the main panel scale.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field onClose fun()|nil  Called after the close button hides the toast.

---@class CountToast: FloatingWindow
---@field SetToastText fun(self: CountToast, title: string, message: string, count: string)

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---Follows the header slider. MainPanel loads after this file, so resolve at Create time.
---@param frame CountToast
local function ListenForScale(frame)
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    mainPanel.OnScaleChanged(function(scale)
        frame:SetWindowScale(scale)
    end)
end

---@param parent Frame
---@param path string
---@param size number
---@param color table
---@return FontString
local function CreateToastLabel(parent, path, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(path, size, "")
    label:SetTextColor(Widgets.UnpackColor(color))
    if label.SetShadowOffset then
        label:SetShadowOffset(0, 0)
    end
    label:SetWordWrap(false)
    return label
end

---Creates a draggable two-line toast (title + message + count badge). Starts hidden.
---@param options CountToastOptions
---@return CountToast
function CountToast.Create(options)
    assert(type(options) == "table", "CountToast.Create requires options")
    assert(type(options.title) == "string", "CountToast.Create requires title")
    assert(type(options.message) == "string", "CountToast.Create requires message")
    assert(type(options.count) == "string", "CountToast.Create requires count")

    local scale = options.scale
    if type(scale) ~= "number" then
        scale = MainPanelScale()
    end

    local frame = FloatingWindow.Create({
        name = options.name,
        fill = COLOR_BG,
        scale = scale,
        position = options.position,
        draggable = true,
        dragEntireFrame = true,
        onPositionChanged = options.onPositionChanged,
    }) --[[@as CountToast]]

    Widgets.ApplyBackdrop(frame, COLOR_BG, COLOR_BORDER)
    frame:SetSize(TOAST_WIDTH, TOAST_HEIGHT)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(Widgets.UnpackColor(COLOR_ACCENT))
    accent:SetSize(ACCENT_WIDTH, ACCENT_HEIGHT)
    accent:SetPoint("LEFT", PAD_X, 0)

    local closeButton = Widgets.CreateCloseButton(frame, function()
        frame:Hide()
        if options.onClose then
            options.onClose()
        end
    end)
    closeButton:SetFrameLevel(frame:GetFrameLevel() + 3)
    closeButton:SetPoint("TOPRIGHT", -CLOSE_INSET, -CLOSE_INSET)

    local badge = frame:CreateTexture(nil, "ARTWORK")
    badge:SetColorTexture(Widgets.UnpackColor(COLOR_BADGE))
    badge:SetSize(BADGE_WIDTH, BADGE_HEIGHT)
    badge:SetPoint("RIGHT", -(CLOSE_INSET + Sizes.CLOSE_BUTTON + BADGE_GAP), 0)

    local title = CreateToastLabel(frame, ARHEI, TITLE_SIZE, COLOR_TITLE)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", accent, "TOPRIGHT", TEXT_GAP, 0)
    title:SetPoint("RIGHT", badge, "LEFT", -TEXT_GAP, 0)

    local message = CreateToastLabel(frame, ARHEI, MESSAGE_SIZE, COLOR_MESSAGE)
    message:SetJustifyH("LEFT")
    message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -LINE_GAP)
    message:SetPoint("RIGHT", badge, "LEFT", -TEXT_GAP, 0)

    local countPath = FontFiles and FontFiles.EXPRESSWAY or ARHEI
    local count = CreateToastLabel(frame, countPath, COUNT_SIZE, COLOR_COUNT)
    count:SetJustifyH("CENTER")
    count:SetPoint("CENTER", badge, "CENTER")

    ---Updates the visible strings. Size and anchors stay fixed.
    ---@param nextTitle string
    ---@param nextMessage string
    ---@param nextCount string
    function frame:SetToastText(nextTitle, nextMessage, nextCount)
        assert(type(nextTitle) == "string", "Bad toast title")
        assert(type(nextMessage) == "string", "Bad toast message")
        assert(type(nextCount) == "string", "Bad toast count")
        title:SetText(nextTitle)
        message:SetText(nextMessage)
        count:SetText(nextCount)
    end

    frame:SetToastText(options.title, options.message, options.count)
    ListenForScale(frame)
    return frame
end

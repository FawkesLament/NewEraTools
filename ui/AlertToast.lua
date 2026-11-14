local _, ns = ...
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Widgets = ns.Widgets

local Colors = Assets.Colors

-- Compact list toast: header plus dual-column alert rows. Callers own strings, visibility, and lifetime.
local AlertToast = {}
ns.AlertToast = AlertToast

local TOAST_WIDTH = 320
local HEADER_HEIGHT = 28
local DIVIDER_HEIGHT = 1
local BODY_PAD_Y = 12
local ROW_HEIGHT = 24
local PAD_X = 12
local ACCENT_WIDTH = 2
local ACCENT_HEIGHT = 12
local ACCENT_TEXT_GAP = 8
local COLUMN_GAP = 8
local RIGHT_COLUMN_WIDTH = 148
local CLOSE_SIZE = 20
local TITLE_SIZE = 12
local LEFT_SIZE = 13
local RIGHT_SIZE = 12

---@class AlertToastRow
---@field left string
---@field right string
---@field color table|nil  Accent-bar color `{ r, g, b, a? }`. Defaults to WARNING.

---@class AlertToastOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field title string
---@field rows AlertToastRow[]|nil  Initial rows. Defaults to none.
---@field scale number|nil  Initial scale. Defaults to the main panel scale.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field onClose fun()|nil  Called after the close button hides the toast.

---@class AlertToast: FloatingWindow
---@field SetRows fun(self: AlertToast, rows: AlertToastRow[])

---@param count integer
---@return number
local function ToastHeight(count)
    return HEADER_HEIGHT + DIVIDER_HEIGHT + BODY_PAD_Y + count * ROW_HEIGHT
end

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---Follows the header slider. MainPanel loads after this file, so resolve at Create time.
---@param frame AlertToast
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
---@param size number
---@param color table
---@return FontString
local function CreateToastLabel(parent, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(DAMAGE_TEXT_FONT, size, "")
    label:SetTextColor(Widgets.UnpackColor(color))
    if label.SetShadowOffset then
        label:SetShadowOffset(0, 0)
    end
    label:SetWordWrap(false)
    if label.SetMaxLines then
        label:SetMaxLines(1)
    end
    return label
end

---@param color table|nil
---@return table
local function AccentColor(color)
    if type(color) == "table" and type(color.r) == "number" then
        return color
    end
    return Colors.WARNING
end

---@param rows AlertToastRow[]|nil
---@return AlertToastRow[]
local function NormalizeRows(rows)
    assert(type(rows) == "table", "Bad toast rows")
    local normalized = {}
    for index = 1, #rows do
        local row = rows[index]
        assert(type(row) == "table", "Bad toast row")
        assert(type(row.left) == "string", "Bad toast left text")
        assert(type(row.right) == "string", "Bad toast right text")
        normalized[index] = row
    end
    return normalized
end

---Creates a draggable header-plus-rows toast. Starts hidden.
---@param options AlertToastOptions
---@return AlertToast
function AlertToast.Create(options)
    assert(type(options) == "table", "AlertToast.Create requires options")
    assert(type(options.title) == "string", "AlertToast.Create requires title")

    local scale = options.scale
    if type(scale) ~= "number" then
        scale = MainPanelScale()
    end

    local frame = FloatingWindow.Create({
        name = options.name,
        fill = Colors.BG,
        scale = scale,
        position = options.position,
        draggable = true,
        dragEntireFrame = true,
        onPositionChanged = options.onPositionChanged,
    }) --[[@as AlertToast]]

    Widgets.ApplyBackdrop(frame, Colors.BG, Colors.BORDER_FAINT)
    frame:SetSize(TOAST_WIDTH, ToastHeight(0))
    if frame.header and frame.header.SetHeight then
        frame.header:SetHeight(HEADER_HEIGHT)
    end

    local title = CreateToastLabel(frame, TITLE_SIZE, Colors.TEXT_MUTED)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", PAD_X, -7)
    title:SetText(options.title)

    local closeButton = Widgets.CreateCloseButton(frame, function()
        frame:Hide()
        if options.onClose then
            options.onClose()
        end
    end)
    closeButton:SetFrameLevel(frame:GetFrameLevel() + 3)
    closeButton:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    closeButton:SetPoint("TOPRIGHT", -8, -6)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.BORDER_FAINT))
    divider:SetHeight(DIVIDER_HEIGHT)
    divider:SetPoint("TOPLEFT", PAD_X, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", -PAD_X, -HEADER_HEIGHT)

    ---@type { accent: Texture, left: FontString, right: FontString }[]
    local pool = {}

    ---@param index integer
    ---@return { accent: Texture, left: FontString, right: FontString }
    local function AcquireRow(index)
        local row = pool[index]
        if row then
            return row
        end
        local accent = frame:CreateTexture(nil, "ARTWORK")
        accent:SetSize(ACCENT_WIDTH, ACCENT_HEIGHT)

        local left = CreateToastLabel(frame, LEFT_SIZE, Colors.TEXT)
        left:SetJustifyH("LEFT")

        local right = CreateToastLabel(frame, RIGHT_SIZE, Colors.TEXT_MUTED)
        right:SetJustifyH("RIGHT")
        right:SetWidth(RIGHT_COLUMN_WIDTH)

        row = { accent = accent, left = left, right = right }
        pool[index] = row
        return row
    end

    ---@param widget Texture|FontString
    local function HideWidget(widget)
        if widget.Hide then
            widget:Hide()
        end
    end

    ---@param widget Texture|FontString
    local function ShowWidget(widget)
        if widget.Show then
            widget:Show()
        end
    end

    ---Replaces visible rows and resizes the card to the current count.
    ---@param nextRows AlertToastRow[]
    function frame:SetRows(nextRows)
        local rows = NormalizeRows(nextRows)
        local bodyTop = HEADER_HEIGHT + DIVIDER_HEIGHT + BODY_PAD_Y / 2
        for index = 1, #rows do
            local spec = rows[index]
            local row = AcquireRow(index)
            local rowTop = -(bodyTop + (index - 1) * ROW_HEIGHT)
            local accentTop = rowTop - (ROW_HEIGHT - ACCENT_HEIGHT) / 2
            row.accent:ClearAllPoints()
            row.accent:SetPoint("TOPLEFT", PAD_X, accentTop)
            row.accent:SetColorTexture(Widgets.UnpackColor(AccentColor(spec.color)))
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD_X, rowTop - ROW_HEIGHT / 2)
            row.right:SetText(spec.right)
            row.left:ClearAllPoints()
            row.left:SetPoint("LEFT", row.accent, "RIGHT", ACCENT_TEXT_GAP, 0)
            row.left:SetPoint("RIGHT", row.right, "LEFT", -COLUMN_GAP, 0)
            row.left:SetText(spec.left)
            ShowWidget(row.accent)
            ShowWidget(row.left)
            ShowWidget(row.right)
        end
        for index = #rows + 1, #pool do
            local row = pool[index]
            HideWidget(row.accent)
            HideWidget(row.left)
            HideWidget(row.right)
        end
        frame:SetSize(TOAST_WIDTH, ToastHeight(#rows))
    end

    frame:SetRows(options.rows or {})
    ListenForScale(frame)
    return frame
end

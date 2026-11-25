local _, ns = ...
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Widgets = ns.Widgets

local Colors = Assets.Colors

-- Compact list toast: header plus single-line three-column rows. Callers own strings, visibility, and lifetime.
local AlertToast = {}
ns.AlertToast = AlertToast

local TOAST_WIDTH = 260
local HEADER_HEIGHT = 26
local DIVIDER_HEIGHT = 1
local BODY_PAD_Y = 6
local ROW_HEIGHT = 24
local PAD_X = 12
local LABEL_WIDTH = 40
local DETAIL_GAP = 8
local STATUS_MAX_WIDTH = 72
local CLOSE_SIZE = 16
local FONT_SIZE = 12
local SEVERITY_WIDTH = 2
local SEVERITY_HEIGHT = 12
local IN_DURATION = 0.18
local OUT_DURATION = 0.15
local IN_OFFSET_Y = 6

local SEVERITY_COLORS = {
    danger = Colors.DANGER,
    warning = Colors.WARNING,
}

---@alias AlertToastSeverity "danger"|"warning"

---@class AlertToastRow
---@field label string  Left column: slot name or category.
---@field detail string|nil  Middle column: item name or extra text. Empty or nil hides it.
---@field status string  Right-column status.
---@field severity AlertToastSeverity  Left severity bar color.

---@class AlertToastOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field title string
---@field rows AlertToastRow[]|nil  Initial rows. Defaults to none.
---@field scale number|nil  Initial scale. Defaults to the main panel scale.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field onClose fun()|nil  Called after the close fade finishes and the toast hides.

---@class AlertToast: FloatingWindow
---@field SetRows fun(self: AlertToast, rows: AlertToastRow[])
---@field PlayIn fun(self: AlertToast)

---@param count integer
---@return number
local function ToastHeight(count)
    return HEADER_HEIGHT + DIVIDER_HEIGHT + BODY_PAD_Y * 2 + count * ROW_HEIGHT
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

---@param severity any
---@return AlertToastSeverity
local function NormalizeSeverity(severity)
    assert(severity == "danger" or severity == "warning", "Bad toast severity")
    return severity
end

---@param rows AlertToastRow[]|nil
---@return AlertToastRow[]
local function NormalizeRows(rows)
    assert(type(rows) == "table", "Bad toast rows")
    local normalized = {}
    for index = 1, #rows do
        local row = rows[index]
        assert(type(row) == "table", "Bad toast row")
        assert(type(row.label) == "string", "Bad toast label")
        assert(row.detail == nil or type(row.detail) == "string", "Bad toast detail")
        assert(type(row.status) == "string", "Bad toast status")
        normalized[index] = {
            label = row.label,
            detail = row.detail,
            status = row.status,
            severity = NormalizeSeverity(row.severity),
        }
    end
    return normalized
end

---@param spec AlertToastRow
---@return boolean
local function HasDetail(spec)
    return type(spec.detail) == "string" and spec.detail ~= ""
end

---@param label FontString
---@return number
local function StatusWidth(label)
    local measured = 0
    if label.GetStringWidth then
        measured = label:GetStringWidth() or 0
    end
    if measured <= 0 then
        return STATUS_MAX_WIDTH
    end
    if measured > STATUS_MAX_WIDTH then
        return STATUS_MAX_WIDTH
    end
    return measured
end

---@param group AnimationGroup|nil
---@return boolean
local function IsPlaying(group)
    return group ~= nil and group.IsPlaying ~= nil and group:IsPlaying()
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
        fill = Colors.FEATURE_CARD_BG,
        scale = scale,
        position = options.position,
        draggable = true,
        dragEntireFrame = true,
        onPositionChanged = options.onPositionChanged,
    }) --[[@as AlertToast]]

    Widgets.ApplyBackdrop(frame, Colors.FEATURE_CARD_BG, Colors.FEATURE_CARD_BORDER)
    frame:SetSize(TOAST_WIDTH, ToastHeight(0))
    if frame.header and frame.header.SetHeight then
        frame.header:SetHeight(HEADER_HEIGHT)
    end

    local titleBar = frame:CreateTexture(nil, "BACKGROUND")
    titleBar:SetColorTexture(Widgets.UnpackColor(Colors.MENU_TITLE_BAR))
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(HEADER_HEIGHT)

    local title = CreateToastLabel(frame, FONT_SIZE, Colors.TEXT_MUTED)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", frame, "TOPLEFT", PAD_X, -HEADER_HEIGHT / 2)
    title:SetText(options.title)

    ---@type AnimationGroup|nil
    local playing

    local function StopPlaying()
        if IsPlaying(playing) then
            playing:Stop()
        end
        playing = nil
    end

    local inAnim
    local outAnim
    if frame.CreateAnimationGroup then
        inAnim = frame:CreateAnimationGroup()
        if inAnim.SetToFinalAlpha then
            inAnim:SetToFinalAlpha(true)
        end
        local fadeIn = inAnim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(IN_DURATION)
        fadeIn:SetSmoothing("OUT")
        local slideIn = inAnim:CreateAnimation("Translation")
        -- Delta from y+6 to rest (WoW Y is up).
        slideIn:SetOffset(0, -IN_OFFSET_Y)
        slideIn:SetDuration(IN_DURATION)
        slideIn:SetSmoothing("OUT")

        outAnim = frame:CreateAnimationGroup()
        if outAnim.SetToFinalAlpha then
            outAnim:SetToFinalAlpha(true)
        end
        local fadeOut = outAnim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(OUT_DURATION)
        outAnim:SetScript("OnFinished", function()
            playing = nil
            frame:Hide()
            if frame.SetAlpha then
                frame:SetAlpha(1)
            end
            if options.onClose then
                options.onClose()
            end
        end)
    end

    local closeButton = Widgets.CreateCloseButton(frame, function()
        if not outAnim then
            frame:Hide()
            if options.onClose then
                options.onClose()
            end
            return
        end
        StopPlaying()
        if frame.SetAlpha then
            frame:SetAlpha(1)
        end
        playing = outAnim
        outAnim:Play()
    end)
    closeButton:SetFrameLevel(frame:GetFrameLevel() + 3)
    closeButton:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    closeButton:SetPoint("TOPRIGHT", -8, -(HEADER_HEIGHT - CLOSE_SIZE) / 2)
    title:SetPoint("RIGHT", closeButton, "LEFT", -DETAIL_GAP, 0)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))
    divider:SetHeight(DIVIDER_HEIGHT)
    divider:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)

    ---@type { marker: Texture, label: FontString, detail: FontString, status: FontString }[]
    local pool = {}

    ---@param index integer
    ---@return { marker: Texture, label: FontString, detail: FontString, status: FontString }
    local function AcquireRow(index)
        local row = pool[index]
        if row then
            return row
        end
        local marker = frame:CreateTexture(nil, "ARTWORK")
        marker:SetSize(SEVERITY_WIDTH, SEVERITY_HEIGHT)

        local label = CreateToastLabel(frame, FONT_SIZE, Colors.TEXT)
        label:SetJustifyH("LEFT")
        label:SetWidth(LABEL_WIDTH)

        local detail = CreateToastLabel(frame, FONT_SIZE, Colors.TEXT_MUTED)
        detail:SetJustifyH("LEFT")

        local status = CreateToastLabel(frame, FONT_SIZE, Colors.TEXT)
        status:SetJustifyH("RIGHT")

        row = { marker = marker, label = label, detail = detail, status = status }
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
        local bodyTop = HEADER_HEIGHT + DIVIDER_HEIGHT + BODY_PAD_Y
        local labelLeft = PAD_X + DETAIL_GAP
        for index = 1, #rows do
            local spec = rows[index]
            local row = AcquireRow(index)
            local midY = -(bodyTop + (index - 0.5) * ROW_HEIGHT)

            row.marker:ClearAllPoints()
            row.marker:SetSize(SEVERITY_WIDTH, SEVERITY_HEIGHT)
            row.marker:SetPoint("LEFT", frame, "TOPLEFT", PAD_X, midY)
            row.marker:SetColorTexture(Widgets.UnpackColor(SEVERITY_COLORS[spec.severity]))

            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", frame, "TOPLEFT", labelLeft, midY)
            row.label:SetWidth(LABEL_WIDTH)
            row.label:SetText(spec.label)

            row.status:ClearAllPoints()
            row.status:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD_X, midY)
            row.status:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
            row.status:SetText(spec.status)
            local statusWidth = StatusWidth(row.status)
            row.status:SetWidth(statusWidth)

            row.detail:ClearAllPoints()
            if HasDetail(spec) then
                row.detail:SetPoint("LEFT", frame, "TOPLEFT", labelLeft + LABEL_WIDTH, midY)
                row.detail:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD_X - statusWidth - DETAIL_GAP, midY)
                row.detail:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
                row.detail:SetText(spec.detail)
                ShowWidget(row.detail)
            else
                row.detail:SetText("")
                HideWidget(row.detail)
            end

            ShowWidget(row.marker)
            ShowWidget(row.label)
            ShowWidget(row.status)
        end
        for index = #rows + 1, #pool do
            local row = pool[index]
            HideWidget(row.marker)
            HideWidget(row.label)
            HideWidget(row.detail)
            HideWidget(row.status)
        end
        frame:SetSize(TOAST_WIDTH, ToastHeight(#rows))
    end

    function frame:PlayIn()
        if not inAnim then
            self:Show()
            return
        end
        StopPlaying()
        self:Show()
        playing = inAnim
        inAnim:Play()
    end

    frame:SetRows(options.rows or {})
    ListenForScale(frame)
    return frame
end

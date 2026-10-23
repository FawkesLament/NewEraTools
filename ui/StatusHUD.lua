local _, ns = ...
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local DEFAULT_WIDTH = 320
local TITLE_ROW_HEIGHT = 20
local TEXT_ROW_HEIGHT = 34
local SEGMENT_HEIGHT = 4
local SEVERITY_NORMAL = "normal"
local SEVERITY_WARNING = "warning"
local SEVERITY_URGENT = "urgent"

local SEVERITIES = {
    [SEVERITY_NORMAL] = {
        text = Colors.TEXT,
        fill = Colors.ACCENT,
        empty = Colors.BORDER,
        border = Colors.BORDER_SUBTLE,
    },
    [SEVERITY_WARNING] = {
        text = Colors.TEXT_GOLD,
        fill = Colors.TEXT_GOLD,
        empty = Colors.BORDER,
        border = Colors.BORDER_SUBTLE,
    },
    [SEVERITY_URGENT] = {
        text = Colors.WARNING,
        fill = Colors.WARNING,
        empty = Colors.BORDER,
        border = Colors.BORDER_WARNING,
    },
}

local StatusHUD = {
    SEVERITY_NORMAL = SEVERITY_NORMAL,
    SEVERITY_WARNING = SEVERITY_WARNING,
    SEVERITY_URGENT = SEVERITY_URGENT,
}
ns.StatusHUD = StatusHUD

---@alias StatusHUDSeverity "normal"|"warning"|"urgent"

---@class StatusHUDState
---@field title string
---@field text string
---@field detail string|nil
---@field progress number|nil
---@field maxProgress number|nil
---@field severity StatusHUDSeverity|nil

---@class StatusHUDOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field parent Frame|nil  Defaults to UIParent.
---@field width number|nil

---@class StatusHUD: Frame
---@field SetState fun(self: StatusHUD, state: StatusHUDState)
---@field GetState fun(self: StatusHUD): StatusHUDState

---@class StatusHUDBindOptions
---@field layoutId string
---@field label string
---@field name string
---@field isEnabled fun(): boolean
---@field getPosition fun(): LayoutPosition
---@field setPosition fun(position: LayoutPosition)
---@field getDefaultPosition fun(): LayoutPosition
---@field previewState StatusHUDState|fun(): StatusHUDState
---@field getState fun(): StatusHUDState|nil
---@field global boolean|nil  Defaults to false; StatusHUD is encounter-specific unless set.
---@field parent Frame|nil
---@field width number|nil
---@field onEditBegin fun()|nil
---@field onEditEnd fun()|nil

---@class StatusHUDBinding
---@field LAYOUT_ID string
---@field Create fun(): StatusHUD
---@field Ensure fun(): StatusHUD
---@field Update fun()

---@param value any
---@return integer
local function WholeNumber(value)
    return math.floor(tonumber(value) or 0)
end

---@param severity any
---@return StatusHUDSeverity
local function ResolveSeverity(severity)
    if SEVERITIES[severity] then
        return severity
    end
    return SEVERITY_NORMAL
end

---Creates a compact persistent status card. Callers own visibility and the displayed state.
---@param options StatusHUDOptions|nil
---@return StatusHUD
function StatusHUD.Create(options)
    options = options or {}
    local parent = options.parent or UIParent
    local width = options.width or DEFAULT_WIDTH

    local frame = Widgets.CreateSurface(parent, Colors.BG_TRANSLUCENT, Colors.BORDER_SUBTLE, options.name)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetWidth(width)
    frame:Hide()

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.MEDIUM,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })
    local header = stack:AddRow(TITLE_ROW_HEIGHT)
    local body = stack:AddRow(TEXT_ROW_HEIGHT)
    local progressRow = stack:AddRow(SEGMENT_HEIGHT)

    local title = Widgets.CreateLabel(header, Fonts.STATUS_HUD_TITLE)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetPoint("LEFT", header, "LEFT")
    title:SetPoint("RIGHT", header, "CENTER", -Spacing.SMALL, 0)

    local detail = Widgets.CreateLabel(header, Fonts.STATUS_HUD_TITLE)
    detail:SetJustifyH("RIGHT")
    detail:SetWordWrap(false)
    detail:SetPoint("RIGHT", header, "RIGHT")
    detail:SetPoint("LEFT", header, "CENTER", Spacing.SMALL, 0)

    local text = Widgets.CreateLabel(body, Fonts.STATUS_HUD_TEXT)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetPoint("LEFT", body, "LEFT")
    text:SetPoint("RIGHT", body, "RIGHT")

    ---@type Texture[]
    local segments = {}
    local applied = {
        title = "",
        text = "",
        detail = nil,
        progress = 0,
        maxProgress = 0,
        severity = SEVERITY_NORMAL,
    }

    local function Resize()
        frame:SetSize(width, stack:GetHeight())
    end

    local function LayoutSegments(count)
        local rowWidth = progressRow:GetWidth()
        if not rowWidth or rowWidth <= 0 then
            rowWidth = width - 2 * Spacing.MEDIUM
        end
        local gap = Spacing.TINY
        local segmentWidth = math.max((rowWidth - gap * math.max(count - 1, 0)) / math.max(count, 1), 1)
        for index = 1, count do
            local segment = segments[index]
            segment:ClearAllPoints()
            segment:SetPoint("LEFT", progressRow, "LEFT", (index - 1) * (segmentWidth + gap), 0)
            segment:SetSize(segmentWidth, SEGMENT_HEIGHT)
        end
    end

    ---@param count integer
    local function EnsureSegments(count)
        for index = #segments + 1, count do
            local segment = progressRow:CreateTexture(nil, "ARTWORK")
            segment:SetTexture(Assets.Textures.WHITE)
            segments[index] = segment
        end
        for index = 1, #segments do
            if index <= count then
                segments[index]:Show()
            else
                segments[index]:Hide()
            end
        end
        if count > 0 then
            LayoutSegments(count)
        end
    end

    ---@param filled integer
    ---@param count integer
    ---@param style table
    local function PaintSegments(filled, count, style)
        for index = 1, count do
            local color = index <= filled and style.fill or style.empty
            segments[index]:SetVertexColor(Widgets.UnpackColor(color))
        end
    end

    ---@param state StatusHUDState
    function frame:SetState(state)
        assert(type(state) == "table", "StatusHUD SetState requires a state table")
        assert(type(state.title) == "string", "StatusHUD title must be a string")
        assert(type(state.text) == "string", "StatusHUD text must be a string")
        if state.detail ~= nil then
            assert(type(state.detail) == "string", "StatusHUD detail must be a string")
        end

        local severity = ResolveSeverity(state.severity)
        local style = SEVERITIES[severity]
        local detailText = state.detail
        if detailText == "" then
            detailText = nil
        end
        local maxProgress = WholeNumber(state.maxProgress)
        local progress = WholeNumber(state.progress)
        if maxProgress < 1 then
            maxProgress = 0
            progress = 0
        elseif progress < 0 then
            progress = 0
        elseif progress > maxProgress then
            progress = maxProgress
        end

        title:SetText(state.title)
        text:SetText(state.text)
        text:SetTextColor(Widgets.UnpackColor(style.text))
        if detailText then
            detail:SetText(detailText)
            detail:Show()
        else
            detail:SetText("")
            detail:Hide()
        end

        frame:SetBackdropBorderColor(Widgets.UnpackColor(style.border))

        if maxProgress > 0 then
            progressRow:Show()
            stack:SetEntryHeight(progressRow, SEGMENT_HEIGHT)
            EnsureSegments(maxProgress)
            PaintSegments(progress, maxProgress, style)
        else
            EnsureSegments(0)
            progressRow:Hide()
            stack:SetEntryHeight(progressRow, 0)
        end

        applied.title = state.title
        applied.text = state.text
        applied.detail = detailText
        applied.progress = progress
        applied.maxProgress = maxProgress
        applied.severity = severity
        Resize()
    end

    ---@return StatusHUDState
    function frame:GetState()
        return {
            title = applied.title,
            text = applied.text,
            detail = applied.detail,
            progress = applied.maxProgress > 0 and applied.progress or nil,
            maxProgress = applied.maxProgress > 0 and applied.maxProgress or nil,
            severity = applied.severity,
        }
    end

    progressRow:HookScript("OnSizeChanged", function()
        if applied.maxProgress > 0 then
            LayoutSegments(applied.maxProgress)
        end
    end)

    Resize()
    return frame --[[@as StatusHUD]]
end

---Registers a layout-editable StatusHUD. The caller supplies preview and live state.
---@param config StatusHUDBindOptions
---@return StatusHUDBinding
function StatusHUD.Bind(config)
    assert(type(config) == "table", "StatusHUD.Bind requires options")
    assert(type(config.layoutId) == "string", "StatusHUD.Bind requires layoutId")
    assert(type(config.label) == "string", "StatusHUD.Bind requires label")
    assert(type(config.name) == "string", "StatusHUD.Bind requires name")
    assert(type(config.isEnabled) == "function", "StatusHUD.Bind requires isEnabled")
    assert(type(config.getPosition) == "function", "StatusHUD.Bind requires getPosition")
    assert(type(config.setPosition) == "function", "StatusHUD.Bind requires setPosition")
    assert(type(config.getDefaultPosition) == "function", "StatusHUD.Bind requires getDefaultPosition")
    assert(config.previewState ~= nil, "StatusHUD.Bind requires previewState")

    local LayoutEditor = ns.LayoutEditor
    local window
    local registered = false
    local layoutEditing = false

    ---@class StatusHUDBinding
    local binding = {
        LAYOUT_ID = config.layoutId,
    }

    local function PreviewState()
        local state = config.previewState
        if type(state) == "function" then
            return state()
        end
        return state
    end

    local function Register(frame)
        if registered then
            return
        end
        registered = true
        LayoutEditor.Register({
            id = config.layoutId,
            label = config.label,
            frame = frame,
            global = config.global == true,
            isEnabled = config.isEnabled,
            getPosition = config.getPosition,
            setPosition = config.setPosition,
            getDefaultPosition = config.getDefaultPosition,
            onEditBegin = function()
                layoutEditing = true
                if config.onEditBegin then
                    config.onEditBegin()
                end
                local hud = binding.Ensure()
                hud:SetState(PreviewState())
                hud:Show()
                hud:Raise()
            end,
            onEditEnd = function()
                layoutEditing = false
                if config.onEditEnd then
                    config.onEditEnd()
                end
                binding.Update()
            end,
        })
    end

    function binding.Create()
        local frame = StatusHUD.Create({
            name = config.name,
            parent = config.parent,
            width = config.width,
        })
        LayoutEditor.ApplyPosition(frame, config.getPosition())
        Register(frame)
        return frame
    end

    function binding.Ensure()
        window = window or binding.Create()
        return window
    end

    function binding.Update()
        if layoutEditing then
            return
        end
        window = window or binding.Create()
        LayoutEditor.ApplyPosition(window, config.getPosition())
        local state = config.getState and config.getState() or nil
        if state == nil then
            window:Hide()
            return
        end
        window:SetState(state)
        window:Show()
    end

    return binding
end

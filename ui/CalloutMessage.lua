local _, ns = ...
local Assets = ns.Assets
local Timer = ns.Api.Timer
local Widgets = ns.Widgets

local DEFAULT_DURATION = 10
local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 72
local MESSAGE_ONLY = "%s"
local TIMER_FORMAT = " (%d)"
local TIMER_FORMAT_TENTHS = " (%.1f)"

local CalloutMessage = {}
ns.CalloutMessage = CalloutMessage

---@class CalloutMessageOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field parent Frame|nil  Defaults to UIParent.
---@field width number|nil
---@field height number|nil
---@field font string|nil  Defaults to Assets.Fonts.CALLOUT.
---@field wrap string|nil  Optional SetFormattedText pattern with one `%s` for the message body (e.g. "Go %s drop ball").

---@class CalloutMessageShowOptions
---@field expiresAt number|nil  Absolute Timer.GetTime() when the message hides. Preferred over duration.
---@field duration number|nil  Seconds from now; used when expiresAt is omitted.
---@field appendTimer boolean|nil  When true, appends a countdown as " (n)" or " (n.n)" below 10s.

---@class CalloutMessage: Frame
---@field SetMessage fun(self: CalloutMessage, message: any, options: CalloutMessageShowOptions|nil)
---@field ShowPreview fun(self: CalloutMessage, message: any, remainingSeconds: integer, appendTimer: boolean|nil)
---@field Clear fun(self: CalloutMessage)

---@class CalloutMessageBindOptions
---@field layoutId string
---@field label string
---@field name string
---@field isEnabled fun(): boolean
---@field getText fun(): any|nil
---@field getExpiresAt fun(): number|nil
---@field getPosition fun(): CalloutAnchor
---@field setPosition fun(position: CalloutAnchor)
---@field getDefaultPosition fun(): CalloutAnchor
---@field previewText any|fun(): any
---@field previewDuration number|nil
---@field getAppendTimer fun(): boolean|nil
---@field wrap string|nil
---@field width number|nil
---@field height number|nil
---@field parent Frame|nil
---@field onEditBegin fun()|nil
---@field onEditEnd fun()|nil

---@class CalloutMessageBinding
---@field LAYOUT_ID string
---@field Create fun(): CalloutMessage
---@field Ensure fun(): CalloutMessage
---@field Update fun()

---@param options CalloutMessageOptions
---@return CalloutMessage
function CalloutMessage.Create(options)
    assert(type(options) == "table", "CalloutMessage.Create requires options")
    if options.wrap ~= nil then
        assert(type(options.wrap) == "string", "CalloutMessage.Create wrap must be a string")
    end

    local wrap = options.wrap
    local messageFormat = wrap or MESSAGE_ONLY
    local font = options.font or Assets.Fonts.CALLOUT

    local parent = options.parent or UIParent
    local frame = CreateFrame("Frame", options.name, parent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    if options.width and options.height then
        frame:SetSize(options.width, options.height)
    end
    frame:Hide()

    local label = Widgets.CreateLabel(frame, font)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetPoint("CENTER")

    local token = 0
    local activeMessage = nil
    local expireTime = nil
    local appendTimer = false
    local shownRemaining = nil
    -- When set, countdown loops instead of hiding (layout-edit preview).
    local previewDuration = nil

    local function RemainingTime()
        if not expireTime then
            return nil
        end
        return math.max(0, expireTime - Timer.GetTime())
    end

    ---Whole seconds at 10+, one tenth below 10. Floors tenths so the readout never rounds up.
    ---@param remaining number
    ---@return number
    ---@return string
    local function TimerDisplay(remaining)
        if remaining < 10 then
            local tenths = math.floor(remaining * 10 + 1e-6) / 10
            return tenths, TIMER_FORMAT_TENTHS:format(tenths)
        end
        local whole = math.ceil(remaining)
        return whole, TIMER_FORMAT:format(whole)
    end

    local function ApplyDisplay()
        if activeMessage == nil then
            return
        end
        local text = messageFormat:format(activeMessage)
        if appendTimer then
            local remaining = RemainingTime()
            if remaining == nil then
                return
            end
            local display, suffix = TimerDisplay(remaining)
            if display == shownRemaining then
                return
            end
            shownRemaining = display
            text = text .. suffix
        else
            shownRemaining = nil
        end
        label:SetText(text)
    end

    local function HideMessage()
        token = token + 1
        activeMessage = nil
        expireTime = nil
        previewDuration = nil
        appendTimer = false
        shownRemaining = nil
        frame:Hide()
    end

    ---Live preview countdown (loops); used while repositioning the host frame.
    ---@param message any
    ---@param remainingSeconds integer
    ---@param withTimer boolean|nil
    function frame:ShowPreview(message, remainingSeconds, withTimer)
        assert(message ~= nil, "CalloutMessage preview requires message")
        token = token + 1
        local duration = remainingSeconds or DEFAULT_DURATION
        activeMessage = message
        previewDuration = duration
        appendTimer = withTimer == true
        shownRemaining = nil
        expireTime = Timer.GetTime() + duration
        ApplyDisplay()
        frame:Show()
        frame:Raise()
    end

    ---Shows `message` until `options.expiresAt` (or now + duration). Replaces any active message immediately.
    ---@param message any
    ---@param options CalloutMessageShowOptions|nil
    function frame:SetMessage(message, options)
        if message == nil then
            frame:Clear()
            return
        end
        if options ~= nil then
            assert(type(options) == "table", "CalloutMessage SetMessage options must be a table")
        else
            options = {}
        end
        local now = Timer.GetTime()
        local expiresAt = options.expiresAt
        if expiresAt == nil then
            local duration = options.duration or DEFAULT_DURATION
            assert(type(duration) == "number", "CalloutMessage duration must be a number")
            expiresAt = now + duration
        else
            assert(type(expiresAt) == "number", "CalloutMessage expiresAt must be a number")
        end
        token = token + 1
        local currentToken = token
        activeMessage = message
        previewDuration = nil
        appendTimer = options.appendTimer == true
        shownRemaining = nil
        expireTime = expiresAt
        local remaining = expiresAt - now
        if remaining <= 0 then
            HideMessage()
            return
        end
        ApplyDisplay()
        frame:Show()
        frame:Raise()
        Timer.After(remaining, function()
            if currentToken ~= token then
                return
            end
            HideMessage()
        end)
    end

    function frame:Clear()
        HideMessage()
    end

    frame:SetScript("OnUpdate", function()
        if not frame:IsShown() or activeMessage == nil or not appendTimer then
            return
        end
        if previewDuration and RemainingTime() <= 0 then
            expireTime = Timer.GetTime() + previewDuration
            shownRemaining = nil
        elseif RemainingTime() <= 0 then
            HideMessage()
            return
        end
        ApplyDisplay()
    end)

    return frame --[[@as CalloutMessage]]
end

---Registers a layout-editable HUD callout and keeps it painted from one expiry clock.
---@param config CalloutMessageBindOptions
---@return CalloutMessageBinding
function CalloutMessage.Bind(config)
    assert(type(config) == "table", "CalloutMessage.Bind requires options")
    assert(type(config.layoutId) == "string", "CalloutMessage.Bind requires layoutId")
    assert(type(config.label) == "string", "CalloutMessage.Bind requires label")
    assert(type(config.name) == "string", "CalloutMessage.Bind requires name")
    assert(type(config.isEnabled) == "function", "CalloutMessage.Bind requires isEnabled")
    assert(type(config.getText) == "function", "CalloutMessage.Bind requires getText")
    assert(type(config.getExpiresAt) == "function", "CalloutMessage.Bind requires getExpiresAt")
    assert(type(config.getPosition) == "function", "CalloutMessage.Bind requires getPosition")
    assert(type(config.setPosition) == "function", "CalloutMessage.Bind requires setPosition")
    assert(type(config.getDefaultPosition) == "function", "CalloutMessage.Bind requires getDefaultPosition")
    assert(config.previewText ~= nil, "CalloutMessage.Bind requires previewText")

    local LayoutEditor = ns.LayoutEditor
    local window
    local registered = false
    local layoutEditing = false

    ---@class CalloutMessageBinding
    local binding = {
        LAYOUT_ID = config.layoutId,
    }

    local function PreviewMessage()
        local text = config.previewText
        if type(text) == "function" then
            return text()
        end
        return text
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
            global = false,
            isEnabled = config.isEnabled,
            getPosition = config.getPosition,
            setPosition = config.setPosition,
            getDefaultPosition = config.getDefaultPosition,
            onEditBegin = function()
                layoutEditing = true
                if config.onEditBegin then
                    config.onEditBegin()
                end
                local win = binding.Ensure()
                win:ShowPreview(PreviewMessage(), config.previewDuration or DEFAULT_DURATION, true)
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
        local frame = CalloutMessage.Create({
            name = config.name,
            parent = config.parent,
            width = config.width or DEFAULT_WIDTH,
            height = config.height or DEFAULT_HEIGHT,
            wrap = config.wrap,
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
        local text = config.getText()
        local expiresAt = config.getExpiresAt()
        if text == nil or expiresAt == nil then
            window:Clear()
            return
        end
        local appendTimer = true
        if config.getAppendTimer then
            appendTimer = config.getAppendTimer()
        end
        window:SetMessage(text, { expiresAt = expiresAt, appendTimer = appendTimer })
    end

    return binding
end

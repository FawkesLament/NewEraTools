local _, ns = ...
local Assets = ns.Assets
local Timer = ns.Api.Timer
local Widgets = ns.Widgets

local DEFAULT_DURATION = 10
local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 72
local MESSAGE_ONLY = "%s"
local TIMER_FORMAT_WHOLE = "%d"
local TIMER_FORMAT_TENTHS = "%.1f"
local TIMER_FONT_SCALE = 1.2
local PULSE_DURATION = 0.15
local PULSE_PEAK_SCALE = 1.22

local CalloutMessage = {}
ns.CalloutMessage = CalloutMessage

---@class CalloutMessageAppearance
---@field scale number|nil  Frame scale. Defaults to 1.
---@field fontPath string|nil  Alert-body face path. Defaults to the CALLOUT font style.
---@field fontSize number|nil  Countdown point size. Defaults to 1.2x the CALLOUT face size.
---@field fontColor RgbColor|nil  Alert-body fill color. Defaults to the CALLOUT font style.

---@type CalloutMessageAppearance
local appearance = {}
---@type CalloutMessage[]
local instances = {}

local function CalloutStyle()
    local styles = Assets.FontStyles
    return styles and styles[Assets.Fonts.CALLOUT] or {}
end

---Resolves unset fields to the existing CALLOUT look (ARHei, 56, warning, thick outline) and scale 1.
---@return number
---@return string
---@return number
---@return number
---@return string
---@return RgbColor
local function ResolveAppearance()
    local style = CalloutStyle()
    local current = appearance
    local scale = current.scale
    if type(scale) ~= "number" then
        scale = 1
    end
    local fontPath = current.fontPath
    if type(fontPath) ~= "string" or fontPath == "" then
        fontPath = style.path or STANDARD_TEXT_FONT
    end
    local messageFontSize = style.size or 56
    local timerFontSize = current.fontSize
    if type(timerFontSize) ~= "number" then
        timerFontSize = math.floor(messageFontSize * TIMER_FONT_SCALE + 0.5)
    end
    local fontColor = current.fontColor
    if type(fontColor) ~= "table" then
        fontColor = style.color or { r = 1, g = 1, b = 1 }
    end
    return scale, fontPath, messageFontSize, timerFontSize, style.flags or "", fontColor
end

---Applies shared appearance to every live callout. Nil fields keep the existing CALLOUT look.
---@param next CalloutMessageAppearance|nil
function CalloutMessage.SetAppearance(next)
    if next ~= nil then
        assert(type(next) == "table", "CalloutMessage.SetAppearance requires a table")
        appearance = {
            scale = next.scale,
            fontPath = next.fontPath,
            fontSize = next.fontSize,
            fontColor = next.fontColor,
        }
    else
        appearance = {}
    end
    for i = 1, #instances do
        instances[i]:ApplyAppearance()
    end
end

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
---@field appendTimer boolean|nil  When true, shows a separate countdown and progress bar.

---@class CalloutMessage: Frame
---@field SetMessage fun(self: CalloutMessage, message: any, options: CalloutMessageShowOptions|nil)
---@field ShowPreview fun(self: CalloutMessage, message: any, remainingSeconds: integer, appendTimer: boolean|nil)
---@field ShowSampledPreview fun(self: CalloutMessage, sampler: fun(): (any, number)|nil)
---@field Clear fun(self: CalloutMessage)
---@field ApplyAppearance fun(self: CalloutMessage): boolean|nil  Re-applies the current shared appearance. True when scale changed.

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
---@field previewDuration number|fun(): number|nil|nil
---@field previewTick (fun(): (any, number)|nil)|nil  When set, Edit Mode samples this instead of a looping static preview.
---@field hasPreviewTick (fun(): boolean)|nil
---@field getAppendTimer fun(): boolean|nil
---@field wrap string|nil
---@field global boolean|nil  When true, participates in the common UI editing scope.
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

local function SetHorizontalBlackGradient(tex, leftAlpha, rightAlpha)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, leftAlpha), CreateColor(0, 0, 0, rightAlpha))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha("HORIZONTAL", 0, 0, 0, leftAlpha, 0, 0, 0, rightAlpha)
    else
        tex:SetVertexColor(0, 0, 0, (leftAlpha + rightAlpha) * 0.5)
    end
end

---@param remaining number
---@return number
---@return number
---@return number
local function GetStageColor(remaining)
    if remaining < 3 then
        return 1.0, 0.28, 0.28 -- Stage 3 (< 3s): Coral Red
    elseif remaining < 10 then
        return 1.0, 0.65, 0.15 -- Stage 2 (3s <= t < 10s): Bright Amber
    else
        return 1.0, 1.0, 1.0 -- Stage 1 (>= 10s): Pure White
    end
end

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

    local bgLeft = frame:CreateTexture(nil, "BACKGROUND")
    SetHorizontalBlackGradient(bgLeft, 0, 0.42)

    local bgRight = frame:CreateTexture(nil, "BACKGROUND")
    SetHorizontalBlackGradient(bgRight, 0.42, 0)

    local messageLabel = Widgets.CreateLabel(frame, font)
    messageLabel:SetJustifyH("RIGHT")
    messageLabel:SetJustifyV("MIDDLE")
    messageLabel:SetWordWrap(false)

    local timerLabel = Widgets.CreateLabel(frame, font)
    timerLabel:SetJustifyH("LEFT")
    timerLabel:SetJustifyV("MIDDLE")
    timerLabel:SetWordWrap(false)

    local barTrack = frame:CreateTexture(nil, "BORDER")
    barTrack:SetColorTexture(0, 0, 0, 0.35)

    local barFill = frame:CreateTexture(nil, "ARTWORK")
    barFill:SetColorTexture(1, 1, 1, 0.95)

    local token = 0
    local activeMessage = nil
    local expireTime = nil
    local appendTimer = false
    local shownRemaining = nil
    -- When set, countdown loops instead of hiding (layout-edit preview).
    local previewDuration = nil
    ---@type (fun(): (any, number)|nil)|nil
    local previewSampler = nil
    local currentFontPath, currentFontSize, currentFontFlags = STANDARD_TEXT_FONT, 56, ""
    local currentMessageFontSize = 56
    local currentBarMaxWidth = 200
    local lastLayoutText = nil
    local lastLayoutWithTimer = nil
    local totalDuration = DEFAULT_DURATION
    local lastWholeSecond = nil
    local pulseStartTime = nil
    local currentPulseScale = 1

    -- SetScale keeps the region's origin (bottom-left) fixed; offsets are also in the
    -- frame's own scale. Re-anchor so the visual center stays put.
    local function SetScaleAroundCenter(scale)
        local oldScale = frame:GetScale()
        if math.abs(oldScale - scale) < 0.001 then
            return false
        end
        local x, y = frame:GetCenter()
        frame:SetScale(scale)
        if x then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * oldScale / scale, y * oldScale / scale)
        end
        return true
    end

    local function UpdateLayout(force)
        if not force and lastLayoutText == messageLabel:GetText() and lastLayoutWithTimer == appendTimer then
            return
        end
        lastLayoutText = messageLabel:GetText()
        lastLayoutWithTimer = appendTimer

        local msgWidth = messageLabel:GetStringWidth() or 0
        local layoutSize = math.max(currentMessageFontSize, currentFontSize)
        local gap = math.max(8, math.floor(layoutSize * 0.22 + 0.5))
        local timerSlotWidth = appendTimer and math.floor(currentFontSize * 1.9 + 0.5) or 0
        local totalContentWidth = msgWidth + (appendTimer and (gap + timerSlotWidth) or 0)
        local bgHalfWidth = math.max(120, math.floor(totalContentWidth * 0.5 + layoutSize * 1.2))
        local bgHeight = math.max(32, math.floor(layoutSize * 1.35 + 0.5))
        local barOffsetY = -math.floor(layoutSize * 0.68 + 0.5)
        currentBarMaxWidth = math.max(140, math.floor(totalContentWidth + layoutSize * 0.6))

        messageLabel:ClearAllPoints()
        if appendTimer then
            local msgCenterOffsetX = -math.floor((gap + timerSlotWidth) * 0.5 + 0.5)
            messageLabel:SetPoint("CENTER", frame, "CENTER", msgCenterOffsetX, 0)
            timerLabel:ClearAllPoints()
            timerLabel:SetPoint("LEFT", messageLabel, "RIGHT", gap, 0)
            timerLabel:Show()
        else
            messageLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
            timerLabel:Hide()
        end

        bgLeft:ClearAllPoints()
        bgLeft:SetPoint("RIGHT", frame, "CENTER", 0, 0)
        bgLeft:SetSize(bgHalfWidth, bgHeight)

        bgRight:ClearAllPoints()
        bgRight:SetPoint("LEFT", frame, "CENTER", 0, 0)
        bgRight:SetSize(bgHalfWidth, bgHeight)

        if appendTimer then
            barTrack:ClearAllPoints()
            barTrack:SetPoint("CENTER", frame, "CENTER", 0, barOffsetY)
            barTrack:SetSize(currentBarMaxWidth, 3)
            barTrack:Show()

            barFill:ClearAllPoints()
            barFill:SetPoint("CENTER", barTrack, "CENTER", 0, 0)
            barFill:SetHeight(3)
            barFill:Show()
        else
            barTrack:Hide()
            barFill:Hide()
        end
    end

    function frame:ApplyAppearance()
        local scale, fontPath, messageFontSize, timerFontSize, flags, fontColor = ResolveAppearance()
        currentMessageFontSize = messageFontSize
        local scaled = SetScaleAroundCenter(scale)
        messageLabel:SetFont(fontPath, messageFontSize, flags)
        messageLabel:SetTextColor(fontColor.r, fontColor.g, fontColor.b, fontColor.a or 1)
        messageLabel:SetShadowColor(0, 0, 0, 0.85)
        messageLabel:SetShadowOffset(2, -2)

        -- Countdown always uses the outlined damage face; appearance.fontPath is message-only.
        local timerFontPath = DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
        currentFontPath, currentFontSize, currentFontFlags = timerFontPath, timerFontSize, flags
        timerLabel:SetFont(timerFontPath, timerFontSize, flags)
        timerLabel:SetShadowColor(0, 0, 0, 0.85)
        timerLabel:SetShadowOffset(2, -2)

        local messageText = messageLabel:GetText()
        if messageText and messageText ~= "" then
            messageLabel:SetText(messageText)
        end
        local timerText = timerLabel:GetText()
        if timerText and timerText ~= "" then
            timerLabel:SetText(timerText)
        end
        UpdateLayout(true)
        return scaled
    end
    frame:ApplyAppearance()
    instances[#instances + 1] = frame

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
        return whole, TIMER_FORMAT_WHOLE:format(whole)
    end

    local function ApplyDisplay()
        if activeMessage == nil then
            return
        end
        local text = messageFormat:format(activeMessage)
        messageLabel:SetText(text)
        UpdateLayout(false)
        if not appendTimer then
            shownRemaining = nil
            lastWholeSecond = nil
            pulseStartTime = nil
            return
        end
        local remaining = RemainingTime()
        if remaining == nil then
            return
        end
        if totalDuration == nil or totalDuration <= 0 or remaining > totalDuration then
            totalDuration = remaining
        end

        local display, timerText = TimerDisplay(remaining)
        if display ~= shownRemaining then
            shownRemaining = display
            timerLabel:SetText(timerText)
            local r, g, b = GetStageColor(remaining)
            timerLabel:SetTextColor(r, g, b, 1)
            barFill:SetColorTexture(r, g, b, 0.95)
        end

        local whole = math.ceil(remaining)
        if remaining < 3 and whole >= 1 and whole ~= lastWholeSecond then
            lastWholeSecond = whole
            pulseStartTime = Timer.GetTime()
        elseif remaining >= 3 then
            lastWholeSecond = whole
        end

        local targetScale = 1
        if pulseStartTime then
            local elapsed = Timer.GetTime() - pulseStartTime
            if elapsed < PULSE_DURATION then
                local progress = elapsed / PULSE_DURATION
                targetScale = PULSE_PEAK_SCALE - (PULSE_PEAK_SCALE - 1) * progress
            else
                pulseStartTime = nil
            end
        end
        if math.abs(targetScale - currentPulseScale) > 0.01 then
            currentPulseScale = targetScale
            local pulsedSize = math.floor(currentFontSize * currentPulseScale + 0.5)
            timerLabel:SetFont(currentFontPath, pulsedSize, currentFontFlags)
        end

        local progress = math.max(0, math.min(1, remaining / math.max(0.1, totalDuration)))
        local fillWidth = math.max(1, currentBarMaxWidth * progress)
        barFill:SetWidth(fillWidth)
    end

    local function HideMessage()
        token = token + 1
        activeMessage = nil
        expireTime = nil
        previewDuration = nil
        previewSampler = nil
        appendTimer = false
        shownRemaining = nil
        totalDuration = nil
        lastWholeSecond = nil
        pulseStartTime = nil
        lastLayoutText = nil
        lastLayoutWithTimer = nil
        frame:Hide()
    end

    local function ApplySampler()
        local sampler = previewSampler
        if not sampler then
            return
        end
        local message, remaining = sampler()
        if message == nil or type(remaining) ~= "number" or remaining <= 0 then
            activeMessage = nil
            expireTime = nil
            shownRemaining = nil
            bgLeft:Hide()
            bgRight:Hide()
            barTrack:Hide()
            barFill:Hide()
            timerLabel:Hide()
            messageLabel:SetText("")
            frame:Show()
            return
        end
        bgLeft:Show()
        bgRight:Show()
        if message ~= activeMessage then
            shownRemaining = nil
        end
        if message ~= activeMessage or totalDuration == nil or remaining > totalDuration then
            totalDuration = remaining
        end
        activeMessage = message
        previewDuration = nil
        appendTimer = true
        expireTime = Timer.GetTime() + remaining
        ApplyDisplay()
        frame:Show()
        frame:Raise()
    end

    ---Live preview countdown (loops); used while repositioning the host frame.
    ---@param message any
    ---@param remainingSeconds integer
    ---@param withTimer boolean|nil
    function frame:ShowPreview(message, remainingSeconds, withTimer)
        assert(message ~= nil, "CalloutMessage preview requires message")
        token = token + 1
        previewSampler = nil
        local duration = remainingSeconds or DEFAULT_DURATION
        activeMessage = message
        previewDuration = duration
        appendTimer = withTimer == true
        shownRemaining = nil
        lastWholeSecond = nil
        pulseStartTime = nil
        totalDuration = duration
        expireTime = Timer.GetTime() + duration
        bgLeft:Show()
        bgRight:Show()
        ApplyDisplay()
        frame:Show()
        frame:Raise()
    end

    ---Edit-mode preview that re-samples text and remaining time every frame.
    ---@param sampler fun(): (any, number)|nil
    function frame:ShowSampledPreview(sampler)
        assert(type(sampler) == "function", "CalloutMessage sampled preview requires a function")
        token = token + 1
        previewSampler = sampler
        previewDuration = nil
        appendTimer = true
        shownRemaining = nil
        totalDuration = nil
        ApplySampler()
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
        previewSampler = nil
        appendTimer = options.appendTimer == true
        shownRemaining = nil
        lastWholeSecond = nil
        pulseStartTime = nil
        expireTime = expiresAt
        local remaining = expiresAt - now
        if remaining <= 0 then
            HideMessage()
            return
        end
        totalDuration = remaining
        bgLeft:Show()
        bgRight:Show()
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
        if previewSampler then
            ApplySampler()
            return
        end
        if not frame:IsShown() or activeMessage == nil or not appendTimer then
            return
        end
        if previewDuration and RemainingTime() <= 0 then
            expireTime = Timer.GetTime() + previewDuration
            shownRemaining = nil
            totalDuration = previewDuration
            lastWholeSecond = nil
            pulseStartTime = nil
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

    local function PreviewDuration()
        local duration = config.previewDuration
        if type(duration) == "function" then
            duration = duration()
        end
        return duration or DEFAULT_DURATION
    end

    local function Register(frame)
        if registered then
            return
        end
        registered = true
        ns.LayoutEditor.Register({
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
                local win = binding.Ensure()
                if config.hasPreviewTick and config.hasPreviewTick() and config.previewTick then
                    win:ShowSampledPreview(config.previewTick)
                    return
                end
                win:ShowPreview(PreviewMessage(), PreviewDuration(), true)
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
        ns.LayoutEditor.ApplyPosition(frame, config.getPosition())
        local rawApply = frame.ApplyAppearance
        function frame:ApplyAppearance()
            local scaled = rawApply(self)
            -- Keep the saved CENTER offset in this scale so leaving edit mode does not jump.
            if scaled and ns.FloatingWindow and self:GetCenter() then
                config.setPosition(ns.FloatingWindow.NormalizePosition(self))
            end
        end
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
        ns.LayoutEditor.ApplyPosition(window, config.getPosition())
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

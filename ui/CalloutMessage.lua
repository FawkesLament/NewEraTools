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
local MAX_VISIBLE_SLOTS = 3
local SECONDARY_SCALE = 0.75
local SLOT_SPACING = 6
local PRIMARY_BG_ALPHA = 0.42
local SECONDARY_BG_ALPHA = 0.22
local DEFAULT_ENTRY_KEY = "__default__"
local PREVIEW_ENTRY_KEY = "__preview__"

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
---@field key string|nil  Stable identity for stacking; omitting replaces the whole queue (legacy).
---@field expiresAt number|nil  Absolute Timer.GetTime() when the message hides. Preferred over duration.
---@field duration number|nil  Seconds from now; used when expiresAt is omitted.
---@field appendTimer boolean|nil  When true, shows a separate countdown and progress bar.

---@class CalloutMessage: Frame
---@field SetMessage fun(self: CalloutMessage, message: any, options: CalloutMessageShowOptions|nil)
---@field ShowPreview fun(self: CalloutMessage, message: any, remainingSeconds: integer, appendTimer: boolean|nil)
---@field ShowSampledPreview fun(self: CalloutMessage, sampler: fun(): (any, number)|nil)
---@field Clear fun(self: CalloutMessage, key: string|nil)
---@field ApplyAppearance fun(self: CalloutMessage): boolean|nil  Re-applies the current shared appearance. True when scale changed.

---@class CalloutMessageBindEntry
---@field key string
---@field text any
---@field expiresAt number
---@field appendTimer boolean|nil

---@class CalloutMessageBindOptions
---@field layoutId string
---@field label string
---@field name string
---@field isEnabled fun(): boolean
---@field getText fun(): any|nil
---@field getExpiresAt fun(): number|nil
---@field getEntries (fun(): CalloutMessageBindEntry[])|nil  When set, paints a keyed stack instead of a single message.
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
---@param isPrimary boolean
---@return number
---@return number
---@return number
local function GetStageColor(remaining, isPrimary)
    if isPrimary then
        if remaining < 3 then
            return 1.0, 0.28, 0.28 -- Stage 3 (< 3s): Coral Red
        elseif remaining < 10 then
            return 1.0, 0.65, 0.15 -- Stage 2 (3s <= t < 10s): Bright Amber
        else
            return 1.0, 1.0, 1.0 -- Stage 1 (>= 10s): Pure White
        end
    else
        if remaining < 3 then
            return 0.85, 0.38, 0.38 -- Muted Red
        elseif remaining < 10 then
            return 0.82, 0.58, 0.28 -- Muted Amber
        else
            return 0.72, 0.72, 0.72 -- Muted Silver
        end
    end
end

---@param fontColor RgbColor
---@return number, number, number, number
local function GetSecondaryMessageColor(fontColor)
    local r = (fontColor.r or 1) * 0.55 + 0.25
    local g = (fontColor.g or 1) * 0.55 + 0.25
    local b = (fontColor.b or 1) * 0.55 + 0.25
    local a = (fontColor.a or 1) * 0.75
    return r, g, b, a
end

---@param size number
---@param rowScale number
---@return number
local function ScaledFontSize(size, rowScale)
    return math.max(12, math.floor(size * rowScale + 0.5))
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

    ---@class CalloutMessageEntry
    ---@field key string
    ---@field message any
    ---@field expiresAt number
    ---@field totalDuration number
    ---@field appendTimer boolean
    ---@field order number

    ---@type CalloutMessageEntry[]
    local activeEntries = {}
    local nextOrder = 0

    -- When set, countdown loops instead of hiding (layout-edit preview).
    local previewDuration = nil
    ---@type (fun(): (any, number)|nil)|nil
    local previewSampler = nil
    local previewMessage = nil
    local previewExpireTime = nil
    local previewTotalDuration = nil
    local previewAppendTimer = false

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

    ---@param isPrimary boolean
    local function CreateRow(isPrimary)
        local rowScale = isPrimary and 1 or SECONDARY_SCALE
        local bgAlpha = isPrimary and PRIMARY_BG_ALPHA or SECONDARY_BG_ALPHA
        local rowFrame = CreateFrame("Frame", nil, frame)
        rowFrame:Hide()

        local bgLeft = rowFrame:CreateTexture(nil, "BACKGROUND")
        SetHorizontalBlackGradient(bgLeft, 0, bgAlpha)

        local bgRight = rowFrame:CreateTexture(nil, "BACKGROUND")
        SetHorizontalBlackGradient(bgRight, bgAlpha, 0)

        local messageLabel = Widgets.CreateLabel(rowFrame, font)
        messageLabel:SetJustifyH("RIGHT")
        messageLabel:SetJustifyV("MIDDLE")
        messageLabel:SetWordWrap(false)

        local timerLabel = Widgets.CreateLabel(rowFrame, font)
        timerLabel:SetJustifyH("LEFT")
        timerLabel:SetJustifyV("MIDDLE")
        timerLabel:SetWordWrap(false)

        local barTrack, barFill
        if isPrimary then
            barTrack = rowFrame:CreateTexture(nil, "BORDER")
            barTrack:SetColorTexture(0, 0, 0, 0.35)

            barFill = rowFrame:CreateTexture(nil, "ARTWORK")
            barFill:SetColorTexture(1, 1, 1, 0.95)
        end

        local row = {
            frame = rowFrame,
            isPrimary = isPrimary,
            boundKey = nil,
            lastLayoutText = nil,
            lastLayoutWithTimer = nil,
            shownRemaining = nil,
            lastWholeSecond = nil,
            pulseStartTime = nil,
            currentPulseScale = 1,
            currentFontPath = STANDARD_TEXT_FONT,
            currentFontSize = 56,
            currentFontFlags = "",
            currentMessageFontSize = 56,
            currentBarMaxWidth = 200,
        }

        local function ResetPulseFont()
            timerLabel:SetFont(row.currentFontPath, row.currentFontSize, row.currentFontFlags)
            row.currentPulseScale = 1
        end

        local function ResetBinding()
            row.shownRemaining = nil
            row.lastWholeSecond = nil
            row.pulseStartTime = nil
            ResetPulseFont()
        end

        ---@param force boolean
        ---@param showTimer boolean
        local function UpdateLayout(force, showTimer)
            if not force and row.lastLayoutText == messageLabel:GetText() and row.lastLayoutWithTimer == showTimer then
                return
            end
            row.lastLayoutText = messageLabel:GetText()
            row.lastLayoutWithTimer = showTimer

            local msgWidth = messageLabel:GetStringWidth() or 0
            local layoutSize = math.max(row.currentMessageFontSize, row.currentFontSize)
            local gap = math.max(8, math.floor(layoutSize * 0.22 + 0.5))
            local timerSlotWidth = showTimer and math.floor(row.currentFontSize * 1.9 + 0.5) or 0
            local totalContentWidth = msgWidth + (showTimer and (gap + timerSlotWidth) or 0)
            local bgHalfWidth = math.max(120, math.floor(totalContentWidth * 0.5 + layoutSize * 1.2))
            local bgHeight = math.max(32, math.floor(layoutSize * 1.35 + 0.5))
            local barOffsetY = -math.floor(layoutSize * 0.68 + 0.5)
            row.currentBarMaxWidth = math.max(140, math.floor(totalContentWidth + layoutSize * 0.6))

            messageLabel:ClearAllPoints()
            if showTimer then
                local msgCenterOffsetX = -math.floor((gap + timerSlotWidth) * 0.5 + 0.5)
                messageLabel:SetPoint("CENTER", rowFrame, "CENTER", msgCenterOffsetX, 0)
                timerLabel:ClearAllPoints()
                timerLabel:SetPoint("LEFT", messageLabel, "RIGHT", gap, 0)
                timerLabel:Show()
            else
                messageLabel:SetPoint("CENTER", rowFrame, "CENTER", 0, 0)
                timerLabel:Hide()
            end

            bgLeft:ClearAllPoints()
            bgLeft:SetPoint("RIGHT", rowFrame, "CENTER", 0, 0)
            bgLeft:SetSize(bgHalfWidth, bgHeight)
            bgLeft:Show()

            bgRight:ClearAllPoints()
            bgRight:SetPoint("LEFT", rowFrame, "CENTER", 0, 0)
            bgRight:SetSize(bgHalfWidth, bgHeight)
            bgRight:Show()

            local extraHeight = 0
            if isPrimary and showTimer then
                extraHeight = 4
                barTrack:ClearAllPoints()
                barTrack:SetPoint("CENTER", rowFrame, "CENTER", 0, barOffsetY)
                barTrack:SetSize(row.currentBarMaxWidth, 3)
                barTrack:Show()

                barFill:ClearAllPoints()
                barFill:SetPoint("CENTER", barTrack, "CENTER", 0, 0)
                barFill:SetHeight(3)
                barFill:Show()
            elseif barTrack then
                barTrack:Hide()
                barFill:Hide()
            end

            rowFrame:SetSize(bgHalfWidth * 2, bgHeight + extraHeight)
        end

        ---@param fontPath string
        ---@param messageFontSize number
        ---@param timerFontSize number
        ---@param flags string
        ---@param fontColor RgbColor
        function row:ApplyAppearance(fontPath, messageFontSize, timerFontSize, flags, fontColor)
            self.currentMessageFontSize = ScaledFontSize(messageFontSize, rowScale)
            local scaledTimerSize = ScaledFontSize(timerFontSize, rowScale)
            messageLabel:SetFont(fontPath, self.currentMessageFontSize, flags)
            if isPrimary then
                messageLabel:SetTextColor(fontColor.r, fontColor.g, fontColor.b, fontColor.a or 1)
            else
                messageLabel:SetTextColor(GetSecondaryMessageColor(fontColor))
            end
            messageLabel:SetShadowColor(0, 0, 0, 0.85)
            messageLabel:SetShadowOffset(2, -2)

            -- Countdown always uses the outlined damage face; appearance.fontPath is message-only.
            local timerFontPath = DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
            self.currentFontPath, self.currentFontSize, self.currentFontFlags = timerFontPath, scaledTimerSize, flags
            timerLabel:SetFont(timerFontPath, scaledTimerSize, flags)
            timerLabel:SetShadowColor(0, 0, 0, 0.85)
            timerLabel:SetShadowOffset(2, -2)
            self.currentPulseScale = 1

            local messageText = messageLabel:GetText()
            if messageText and messageText ~= "" then
                messageLabel:SetText(messageText)
            end
            local timerText = timerLabel:GetText()
            if timerText and timerText ~= "" then
                timerLabel:SetText(timerText)
            end
            UpdateLayout(true, self.lastLayoutWithTimer == true)
        end

        function row:ShowIdle()
            self.boundKey = nil
            ResetBinding()
            bgLeft:Hide()
            bgRight:Hide()
            if barTrack then
                barTrack:Hide()
                barFill:Hide()
            end
            timerLabel:Hide()
            messageLabel:SetText("")
            self.lastLayoutText = nil
            self.lastLayoutWithTimer = nil
            rowFrame:Show()
        end

        function row:Hide()
            self.boundKey = nil
            ResetBinding()
            self.lastLayoutText = nil
            self.lastLayoutWithTimer = nil
            rowFrame:Hide()
        end

        ---@param entry CalloutMessageEntry
        ---@param now number
        function row:Render(entry, now)
            if entry.key ~= self.boundKey then
                self.boundKey = entry.key
                ResetBinding()
            end

            local text = messageFormat:format(entry.message)
            messageLabel:SetText(text)
            local showTimer = entry.appendTimer == true
            UpdateLayout(false, showTimer)
            if not showTimer then
                self.shownRemaining = nil
                self.lastWholeSecond = nil
                self.pulseStartTime = nil
                return
            end

            local remaining = math.max(0, entry.expiresAt - now)
            if entry.totalDuration == nil or entry.totalDuration <= 0 or remaining > entry.totalDuration then
                entry.totalDuration = remaining
            end

            local display, timerText = TimerDisplay(remaining)
            if display ~= self.shownRemaining then
                self.shownRemaining = display
                timerLabel:SetText(timerText)
                local r, g, b = GetStageColor(remaining, isPrimary)
                timerLabel:SetTextColor(r, g, b, 1)
                if barFill then
                    barFill:SetColorTexture(r, g, b, 0.95)
                end
            end

            if isPrimary then
                local whole = math.ceil(remaining)
                if remaining < 3 and whole >= 1 and whole ~= self.lastWholeSecond then
                    self.lastWholeSecond = whole
                    self.pulseStartTime = now
                elseif remaining >= 3 then
                    self.lastWholeSecond = whole
                end

                local targetScale = 1
                if self.pulseStartTime then
                    local elapsed = now - self.pulseStartTime
                    if elapsed < PULSE_DURATION then
                        local progress = elapsed / PULSE_DURATION
                        targetScale = PULSE_PEAK_SCALE - (PULSE_PEAK_SCALE - 1) * progress
                    else
                        self.pulseStartTime = nil
                    end
                end
                if math.abs(targetScale - self.currentPulseScale) > 0.01 then
                    self.currentPulseScale = targetScale
                    local pulsedSize = math.floor(self.currentFontSize * self.currentPulseScale + 0.5)
                    timerLabel:SetFont(self.currentFontPath, pulsedSize, self.currentFontFlags)
                end

                local progress = math.max(0, math.min(1, remaining / math.max(0.1, entry.totalDuration)))
                local fillWidth = math.max(1, self.currentBarMaxWidth * progress)
                barFill:SetWidth(fillWidth)
            end
        end

        return row
    end

    local rows = {}
    for i = 1, MAX_VISIBLE_SLOTS do
        rows[i] = CreateRow(i == 1)
    end
    rows[1].frame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    for i = 2, MAX_VISIBLE_SLOTS do
        rows[i].frame:SetPoint("TOP", rows[i - 1].frame, "BOTTOM", 0, -SLOT_SPACING)
    end

    local function HideSecondaryRows()
        for i = 2, MAX_VISIBLE_SLOTS do
            rows[i]:Hide()
        end
    end

    local function WipeEntries()
        for i = #activeEntries, 1, -1 do
            activeEntries[i] = nil
        end
    end

    ---@param now number
    local function SyncEntries(now)
        if previewSampler or previewDuration then
            return
        end
        local write = 1
        for i = 1, #activeEntries do
            local entry = activeEntries[i]
            if entry.expiresAt > now then
                activeEntries[write] = entry
                write = write + 1
            end
        end
        for i = write, #activeEntries do
            activeEntries[i] = nil
        end

        table.sort(activeEntries, function(a, b)
            if a.expiresAt ~= b.expiresAt then
                return a.expiresAt < b.expiresAt
            end
            return (a.order or 0) < (b.order or 0)
        end)

        if #activeEntries == 0 then
            for i = 1, MAX_VISIBLE_SLOTS do
                rows[i]:Hide()
            end
            frame:Hide()
            return
        end

        for i = 1, MAX_VISIBLE_SLOTS do
            local entry = activeEntries[i]
            if entry then
                rows[i]:Render(entry, now)
                rows[i].frame:Show()
            else
                rows[i]:Hide()
            end
        end
        frame:Show()
    end

    local function ClearPreview()
        previewDuration = nil
        previewSampler = nil
        previewMessage = nil
        previewExpireTime = nil
        previewTotalDuration = nil
        previewAppendTimer = false
    end

    function frame:ApplyAppearance()
        local scale, fontPath, messageFontSize, timerFontSize, flags, fontColor = ResolveAppearance()
        local scaled = SetScaleAroundCenter(scale)
        for i = 1, MAX_VISIBLE_SLOTS do
            rows[i]:ApplyAppearance(fontPath, messageFontSize, timerFontSize, flags, fontColor)
        end
        return scaled
    end
    frame:ApplyAppearance()
    instances[#instances + 1] = frame

    local function ApplySampler()
        local sampler = previewSampler
        if not sampler then
            return
        end
        HideSecondaryRows()
        local message, remaining = sampler()
        if message == nil or type(remaining) ~= "number" or remaining <= 0 then
            previewMessage = nil
            previewExpireTime = nil
            rows[1]:ShowIdle()
            frame:Show()
            return
        end
        if message ~= previewMessage then
            rows[1].shownRemaining = nil
        end
        if message ~= previewMessage or previewTotalDuration == nil or remaining > previewTotalDuration then
            previewTotalDuration = remaining
        end
        previewMessage = message
        previewDuration = nil
        previewAppendTimer = true
        local now = Timer.GetTime()
        previewExpireTime = now + remaining
        rows[1]:Render({
            key = PREVIEW_ENTRY_KEY,
            message = message,
            expiresAt = previewExpireTime,
            totalDuration = previewTotalDuration,
            appendTimer = true,
            order = 0,
        }, now)
        rows[1].frame:Show()
        frame:Show()
        frame:Raise()
    end

    ---Live preview countdown (loops); used while repositioning the host frame.
    ---@param message any
    ---@param remainingSeconds integer
    ---@param withTimer boolean|nil
    function frame:ShowPreview(message, remainingSeconds, withTimer)
        assert(message ~= nil, "CalloutMessage preview requires message")
        previewSampler = nil
        local duration = remainingSeconds or DEFAULT_DURATION
        local now = Timer.GetTime()
        previewMessage = message
        previewDuration = duration
        previewAppendTimer = withTimer == true
        previewTotalDuration = duration
        previewExpireTime = now + duration
        HideSecondaryRows()
        rows[1].boundKey = nil
        rows[1]:Render({
            key = PREVIEW_ENTRY_KEY,
            message = message,
            expiresAt = previewExpireTime,
            totalDuration = duration,
            appendTimer = previewAppendTimer,
            order = 0,
        }, now)
        rows[1].frame:Show()
        frame:Show()
        frame:Raise()
    end

    ---Edit-mode preview that re-samples text and remaining time every frame.
    ---@param sampler fun(): (any, number)|nil
    function frame:ShowSampledPreview(sampler)
        assert(type(sampler) == "function", "CalloutMessage sampled preview requires a function")
        previewSampler = sampler
        previewDuration = nil
        previewAppendTimer = true
        previewTotalDuration = nil
        rows[1].shownRemaining = nil
        HideSecondaryRows()
        ApplySampler()
    end

    ---Shows `message` until `options.expiresAt` (or now + duration).
    ---Keyed calls upsert into the stack; omitting `key` replaces the whole queue.
    ---@param message any
    ---@param options CalloutMessageShowOptions|nil
    function frame:SetMessage(message, options)
        if message == nil then
            frame:Clear(options and options.key)
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
        ClearPreview()
        local remaining = expiresAt - now
        if remaining <= 0 then
            frame:Clear(options.key)
            return
        end

        local key = options.key
        if key ~= nil then
            local found
            for i = 1, #activeEntries do
                if activeEntries[i].key == key then
                    found = activeEntries[i]
                    break
                end
            end
            if found then
                found.message = message
                found.expiresAt = expiresAt
                found.appendTimer = options.appendTimer == true
                if remaining > found.totalDuration then
                    found.totalDuration = remaining
                end
            else
                nextOrder = nextOrder + 1
                activeEntries[#activeEntries + 1] = {
                    key = key,
                    message = message,
                    expiresAt = expiresAt,
                    totalDuration = remaining,
                    appendTimer = options.appendTimer == true,
                    order = nextOrder,
                }
            end
        else
            WipeEntries()
            for i = 1, MAX_VISIBLE_SLOTS do
                rows[i].boundKey = nil
            end
            nextOrder = nextOrder + 1
            activeEntries[1] = {
                key = DEFAULT_ENTRY_KEY,
                message = message,
                expiresAt = expiresAt,
                totalDuration = remaining,
                appendTimer = options.appendTimer == true,
                order = nextOrder,
            }
        end

        SyncEntries(now)
        frame:Raise()
        -- Expire via SyncEntries so one finished slot can promote the next without hiding the frame.
        Timer.After(remaining, function()
            SyncEntries(Timer.GetTime())
        end)
    end

    ---@param key string|nil
    function frame:Clear(key)
        if key ~= nil then
            for i = #activeEntries, 1, -1 do
                if activeEntries[i].key == key then
                    table.remove(activeEntries, i)
                    break
                end
            end
            SyncEntries(Timer.GetTime())
            return
        end
        ClearPreview()
        WipeEntries()
        for i = 1, MAX_VISIBLE_SLOTS do
            rows[i]:Hide()
        end
        frame:Hide()
    end

    frame:SetScript("OnUpdate", function()
        if previewSampler then
            ApplySampler()
            return
        end
        if previewDuration then
            if not frame:IsShown() then
                return
            end
            if not previewAppendTimer then
                return
            end
            local now = Timer.GetTime()
            if previewExpireTime - now <= 0 then
                previewExpireTime = now + previewDuration
                previewTotalDuration = previewDuration
                rows[1].boundKey = nil
                rows[1].shownRemaining = nil
                rows[1].lastWholeSecond = nil
                rows[1].pulseStartTime = nil
            end
            rows[1]:Render({
                key = PREVIEW_ENTRY_KEY,
                message = previewMessage,
                expiresAt = previewExpireTime,
                totalDuration = previewTotalDuration,
                appendTimer = true,
                order = 0,
            }, Timer.GetTime())
            return
        end
        if #activeEntries == 0 then
            return
        end
        SyncEntries(Timer.GetTime())
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
    ---@type table<string, boolean>
    local boundKeys = {}

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
        if config.getEntries then
            local entries = config.getEntries() or {}
            if #entries == 0 then
                boundKeys = {}
                window:Clear()
                return
            end
            local seen = {}
            for index = 1, #entries do
                local entry = entries[index]
                seen[entry.key] = true
                window:SetMessage(entry.text, {
                    key = entry.key,
                    expiresAt = entry.expiresAt,
                    appendTimer = entry.appendTimer == true,
                })
            end
            for key in pairs(boundKeys) do
                if not seen[key] then
                    window:Clear(key)
                end
            end
            boundKeys = seen
            return
        end
        local text = config.getText()
        local expiresAt = config.getExpiresAt()
        if text == nil or expiresAt == nil then
            boundKeys = {}
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

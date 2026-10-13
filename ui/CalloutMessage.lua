local _, ns = ...
local Assets = ns.Assets
local Timer = ns.Api.Timer
local Widgets = ns.Widgets

local DEFAULT_DURATION = 10
local MESSAGE_ONLY = "%s"
local TIMER_FORMAT = " (%d)"

local CalloutMessage = {}
ns.CalloutMessage = CalloutMessage

---@class CalloutMessageOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field parent Frame|nil  Defaults to UIParent.
---@field width number|nil
---@field height number|nil
---@field font string|nil  Defaults to Assets.Fonts.CALLOUT.
---@field wrap string|nil  Optional SetFormattedText pattern with one `%s` for the message body (e.g. "Go %s drop ball").

---@class CalloutMessage: Frame
---@field SetMessage fun(self: CalloutMessage, message: any, duration: number|nil, appendTimer: boolean|nil)
---@field ShowPreview fun(self: CalloutMessage, message: any, remainingSeconds: integer, appendTimer: boolean|nil)
---@field Clear fun(self: CalloutMessage)

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

    local function RemainingSeconds()
        if not expireTime then
            return nil
        end
        return math.max(0, math.ceil(expireTime - Timer.GetTime()))
    end

    local function ApplyDisplay()
        if activeMessage == nil then
            return
        end
        local text = messageFormat:format(activeMessage)
        if appendTimer then
            local remaining = RemainingSeconds()
            if remaining == nil then
                return
            end
            if remaining == shownRemaining then
                return
            end
            shownRemaining = remaining
            text = text .. TIMER_FORMAT:format(remaining)
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

    ---Shows `message` for `duration` seconds (default 10). Replaces any active message immediately.
    ---@param message any
    ---@param duration number|nil
    ---@param withTimer boolean|nil  When true, appends a whole-second countdown as " (n)".
    function frame:SetMessage(message, duration, withTimer)
        if message == nil then
            frame:Clear()
            return
        end
        token = token + 1
        local currentToken = token
        local showDuration = duration or DEFAULT_DURATION
        activeMessage = message
        previewDuration = nil
        appendTimer = withTimer == true
        shownRemaining = nil
        expireTime = Timer.GetTime() + showDuration
        ApplyDisplay()
        frame:Show()
        frame:Raise()
        Timer.After(showDuration, function()
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
        if previewDuration and RemainingSeconds() == 0 then
            expireTime = Timer.GetTime() + previewDuration
            shownRemaining = nil
        end
        ApplyDisplay()
    end)

    return frame --[[@as CalloutMessage]]
end

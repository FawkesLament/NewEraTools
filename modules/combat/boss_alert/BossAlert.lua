local _, ns = ...
local Assets = ns.Assets
local Color = ns.Color
local SharedMedia = ns.SharedMedia
local Util = ns.Util

-- Same range as the combat timer window scale control.
local CALLOUT_SCALE_MIN = 0.8
local CALLOUT_SCALE_MAX = 1.5
local CALLOUT_SCALE_STEP = 0.05

local CALLOUT_COUNTDOWN_FONT_SIZE_MIN = 24
local CALLOUT_COUNTDOWN_FONT_SIZE_MAX = 80
local CALLOUT_COUNTDOWN_FONT_SIZE_STEP = 1

local function CalloutStyle()
    return Assets.FontStyles[Assets.Fonts.CALLOUT]
end

local function DefaultCalloutAlertFontColor()
    local color = CalloutStyle().color
    return { r = color.r, g = color.g, b = color.b }
end

---@return number
local function DefaultCalloutCountdownFontSize()
    return 50
end

---@class BossAlertCallout
---@field scale number
---@field alertFont string
---@field countdownFontSize number
---@field alertFontColor RgbColor
---@field tts boolean

---A fresh callout-feature record, including a new color table, on every call.
---@return BossAlertCallout
local function NewCalloutSettings()
    return {
        -- Scale of the callout message. 1 matches the existing HUD.
        scale = 1,
        alertFont = SharedMedia.FONT_DEFAULT,
        -- Point size of the countdown. The alert body uses the CALLOUT face size and the scale slider.
        countdownFontSize = DefaultCalloutCountdownFontSize(),
        alertFontColor = DefaultCalloutAlertFontColor(),
        -- When true, a new callout message is spoken with the client's TTS voice.
        tts = false,
    }
end

---@class BossAlert: Module
---@field OnCalloutAppearanceChanged fun(self: BossAlert)|nil  Defined by the UI file; called when callout look settings change.
local BossAlert = ns.Modules.New("BossAlert", {
    defaults = {
        callout = NewCalloutSettings(),
    },
})

BossAlert.CALLOUT_SCALE_MIN = CALLOUT_SCALE_MIN
BossAlert.CALLOUT_SCALE_MAX = CALLOUT_SCALE_MAX
BossAlert.CALLOUT_SCALE_STEP = CALLOUT_SCALE_STEP
BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_MIN = CALLOUT_COUNTDOWN_FONT_SIZE_MIN
BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_MAX = CALLOUT_COUNTDOWN_FONT_SIZE_MAX
BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_STEP = CALLOUT_COUNTDOWN_FONT_SIZE_STEP
BossAlert.CALLOUT_ALERT_FONT_DEFAULT = SharedMedia.FONT_DEFAULT

local function NotifyCalloutAppearanceChanged()
    if BossAlert.OnCalloutAppearanceChanged then
        BossAlert:OnCalloutAppearanceChanged()
    end
end

---@return BossAlertCallout
local function CalloutSettings(self)
    local settings = self.db.callout
    if type(settings) ~= "table" then
        settings = NewCalloutSettings()
        self.db.callout = settings
    end
    return settings
end

local function SanitizeCalloutAlertFontColor(settings)
    local alertFontColor = Color.Normalize(settings.alertFontColor) or DefaultCalloutAlertFontColor()
    if type(settings.alertFontColor) ~= "table" then
        settings.alertFontColor = { r = alertFontColor.r, g = alertFontColor.g, b = alertFontColor.b }
        return
    end
    Color.Copy(settings.alertFontColor, alertFontColor)
end

---@return number
function BossAlert:GetCalloutScale()
    return Util.Snap(CalloutSettings(self).scale, CALLOUT_SCALE_MIN, CALLOUT_SCALE_MAX, CALLOUT_SCALE_STEP)
end

---@param scale number
function BossAlert:SetCalloutScale(scale)
    assert(type(scale) == "number", "Bad callout scale")
    scale = Util.Snap(scale, CALLOUT_SCALE_MIN, CALLOUT_SCALE_MAX, CALLOUT_SCALE_STEP)
    local settings = CalloutSettings(self)
    if settings.scale == scale then
        return
    end
    settings.scale = scale
    NotifyCalloutAppearanceChanged()
end

---@return string
function BossAlert:GetCalloutAlertFont()
    local font = CalloutSettings(self).alertFont
    if type(font) ~= "string" or font == "" then
        return SharedMedia.FONT_DEFAULT
    end
    return font
end

---@param font string
function BossAlert:SetCalloutAlertFont(font)
    assert(type(font) == "string" and font ~= "", "Bad callout alert font")
    local settings = CalloutSettings(self)
    if settings.alertFont == font then
        return
    end
    settings.alertFont = font
    NotifyCalloutAppearanceChanged()
end

---@return number
function BossAlert:GetCalloutCountdownFontSize()
    return Util.Snap(
        CalloutSettings(self).countdownFontSize,
        CALLOUT_COUNTDOWN_FONT_SIZE_MIN,
        CALLOUT_COUNTDOWN_FONT_SIZE_MAX,
        CALLOUT_COUNTDOWN_FONT_SIZE_STEP
    )
end

---@param size number
function BossAlert:SetCalloutCountdownFontSize(size)
    assert(type(size) == "number", "Bad callout countdown font size")
    size = Util.Snap(
        size,
        CALLOUT_COUNTDOWN_FONT_SIZE_MIN,
        CALLOUT_COUNTDOWN_FONT_SIZE_MAX,
        CALLOUT_COUNTDOWN_FONT_SIZE_STEP
    )
    local settings = CalloutSettings(self)
    if settings.countdownFontSize == size then
        return
    end
    settings.countdownFontSize = size
    NotifyCalloutAppearanceChanged()
end

---@return RgbColor
function BossAlert:GetCalloutAlertFontColor()
    return Color.Normalize(CalloutSettings(self).alertFontColor) or DefaultCalloutAlertFontColor()
end

---@param color RgbColor
function BossAlert:SetCalloutAlertFontColor(color)
    local next = Color.Normalize(color)
    assert(next ~= nil, "Bad callout alert font color")
    local settings = CalloutSettings(self)
    local saved = settings.alertFontColor
    if type(saved) ~= "table" then
        settings.alertFontColor = { r = next.r, g = next.g, b = next.b }
        NotifyCalloutAppearanceChanged()
        return
    end
    if Color.Equal(saved, next) then
        return
    end
    Color.Copy(saved, next)
    NotifyCalloutAppearanceChanged()
end

---File path for the selected alert-body face. Unset or "default" keeps the existing CALLOUT face.
---@return string
function BossAlert:GetCalloutAlertFontPath()
    return SharedMedia.ResolveFontPath(self:GetCalloutAlertFont()) or CalloutStyle().path
end

function BossAlert:ResetCalloutAppearance()
    local settings = CalloutSettings(self)
    local defaults = NewCalloutSettings()
    settings.scale = defaults.scale
    settings.alertFont = defaults.alertFont
    settings.countdownFontSize = defaults.countdownFontSize
    if type(settings.alertFontColor) ~= "table" then
        settings.alertFontColor = defaults.alertFontColor
    else
        Color.Copy(settings.alertFontColor, defaults.alertFontColor)
    end
    NotifyCalloutAppearanceChanged()
end

---@return boolean
function BossAlert:IsCalloutTtsEnabled()
    return CalloutSettings(self).tts == true
end

---@param enabled boolean
function BossAlert:SetCalloutTtsEnabled(enabled)
    enabled = enabled == true
    local settings = CalloutSettings(self)
    if settings.tts == enabled then
        return
    end
    settings.tts = enabled
end

---Displayed callout body for speech: wrap applied, countdown omitted.
---@param current CalloutManagerMessage|nil
---@return string|nil
local function CalloutSpeechText(current)
    if not current then
        return nil
    end
    local text = current.text
    if not ns.Api.Speech.IsPlainText(text) then
        return nil
    end
    if current.wrap then
        text = current.wrap:format(text)
    end
    if not ns.Api.Speech.IsPlainText(text) then
        return nil
    end
    return text
end

function BossAlert:SpeakCurrentCallout()
    if not self:IsCalloutTtsEnabled() then
        return
    end
    local text = CalloutSpeechText(ns.CalloutManager.GetCurrent())
    if text then
        ns.Api.Speech.Say(text)
    end
end

---Starts speaking new callout messages. Called from OnEnable.
function BossAlert:ListenForCalloutTts()
    ns.CalloutManager.OnChanged(function()
        BossAlert:SpeakCurrentCallout()
    end)
end

---Resolved callout look for CalloutMessage. Unset fields match the existing CALLOUT setup.
---@return CalloutMessageAppearance
function BossAlert:GetCalloutAppearance()
    local color = self:GetCalloutAlertFontColor()
    return {
        scale = self:GetCalloutScale(),
        fontPath = self:GetCalloutAlertFontPath(),
        fontSize = self:GetCalloutCountdownFontSize(),
        fontColor = { r = color.r, g = color.g, b = color.b },
    }
end

function BossAlert:OnInit()
    local settings = CalloutSettings(self)
    settings.scale = Util.Snap(tonumber(settings.scale) or 1, CALLOUT_SCALE_MIN, CALLOUT_SCALE_MAX, CALLOUT_SCALE_STEP)
    if type(settings.alertFont) ~= "string" or settings.alertFont == "" then
        settings.alertFont = SharedMedia.FONT_DEFAULT
    end
    settings.countdownFontSize = Util.Snap(
        tonumber(settings.countdownFontSize) or DefaultCalloutCountdownFontSize(),
        CALLOUT_COUNTDOWN_FONT_SIZE_MIN,
        CALLOUT_COUNTDOWN_FONT_SIZE_MAX,
        CALLOUT_COUNTDOWN_FONT_SIZE_STEP
    )
    SanitizeCalloutAlertFontColor(settings)
    settings.tts = settings.tts == true
end

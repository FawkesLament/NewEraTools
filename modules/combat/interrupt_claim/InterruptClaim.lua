local _, ns = ...
local L = ns.L

local MODIFIER_SHIFT = "shift"
local MODIFIER_CTRL = "ctrl"
local MODIFIER_ALT = "alt"

local MOUSE_LEFT = "left"
local MOUSE_RIGHT = "right"
local MOUSE_MIDDLE = "middle"
local MOUSE_FORWARD = "forward"
local MOUSE_BACK = "back"

local MODIFIER_KEYS = {
    [MODIFIER_SHIFT] = "SHIFT",
    [MODIFIER_CTRL] = "CTRL",
    [MODIFIER_ALT] = "ALT",
}

-- Physical mouse buttons. Forward/back are the side buttons (WoW BUTTON5 / BUTTON4).
local MOUSE_KEYS = {
    [MOUSE_LEFT] = "BUTTON1",
    [MOUSE_RIGHT] = "BUTTON2",
    [MOUSE_MIDDLE] = "BUTTON3",
    [MOUSE_FORWARD] = "BUTTON5",
    [MOUSE_BACK] = "BUTTON4",
}

-- Secure-button attribute suffixes: SecureButton_GetModifiedAttribute maps Button4/Button5 to "4"/"5".
local MOUSE_ATTRIBUTE_SUFFIXES = {
    [MOUSE_LEFT] = "1",
    [MOUSE_RIGHT] = "2",
    [MOUSE_MIDDLE] = "3",
    [MOUSE_FORWARD] = "5",
    [MOUSE_BACK] = "4",
}

local FOCUS_MACRO = "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]"
-- @mouseover is required: the override click never targets, so bare `/tm` would mark the old target.
local MARK_MACRO = "/stopmacro [nogroup:party]\n/tm [@mouseover]%s%d"

local ANNOUNCE_OFF = "off"
local CHANNEL_PARTY = "party"
local CHANNEL_EMOTE = "emote"
local CHANNEL_SAY = "say"

local CHANNEL_SLASH = {
    [CHANNEL_PARTY] = "/p",
    [CHANNEL_EMOTE] = "/e",
    [CHANNEL_SAY] = "/s",
}

local ANNOUNCE_MAX_CHARS = 30
local ANNOUNCE_PLACEHOLDER = "{marker}"
local MACRO_MAX_BODY_LENGTH = ns.Api.Macro.MAX_BODY_LENGTH

---@alias InterruptClaimModifier "shift"|"ctrl"|"alt"
---@alias InterruptClaimMouseButton "left"|"right"|"middle"|"forward"|"back"
---@alias InterruptClaimAnnounceChannel "off"|"party"|"emote"|"say"

---@class InterruptClaim: Module
---@field OnEnabledChanged fun(self: InterruptClaim)|nil  Defined by the UI file; called when the feature toggles.
---@field OnClickChanged fun(self: InterruptClaim)|nil  Defined by the UI file; called when the click binding changes.
---@field OnMarkChanged fun(self: InterruptClaim)|nil  Defined by the UI file; called when marker settings change.
local InterruptClaim = ns.Modules.New("InterruptClaim", {
    defaults = {
        -- When true, the chosen modifier+click focuses the unit under the mouse.
        enabled = false,
        ---@type InterruptClaimModifier
        modifier = MODIFIER_SHIFT,
        ---@type InterruptClaimMouseButton
        mouseButton = MOUSE_LEFT,
        -- When true, the click also applies the chosen raid target.
        markEnabled = false,
        -- Raid target index 1–8 ({rt1} star through {rt8} skull).
        markIndex = 1,
        -- When true, `/tm` uses `~index` so an existing raid target is not replaced.
        preventOverwrite = false,
        ---@type InterruptClaimAnnounceChannel
        announceChannel = ANNOUNCE_OFF,
        announceMessage = L.INTERRUPT_CLAIM_ANNOUNCE_DEFAULT,
    },
})

InterruptClaim.MODIFIER_SHIFT = MODIFIER_SHIFT
InterruptClaim.MODIFIER_CTRL = MODIFIER_CTRL
InterruptClaim.MODIFIER_ALT = MODIFIER_ALT
InterruptClaim.MOUSE_LEFT = MOUSE_LEFT
InterruptClaim.MOUSE_RIGHT = MOUSE_RIGHT
InterruptClaim.MOUSE_MIDDLE = MOUSE_MIDDLE
InterruptClaim.MOUSE_FORWARD = MOUSE_FORWARD
InterruptClaim.MOUSE_BACK = MOUSE_BACK

---@type InterruptClaimModifier[]
InterruptClaim.MODIFIERS = { MODIFIER_SHIFT, MODIFIER_CTRL, MODIFIER_ALT }

---@type InterruptClaimMouseButton[]
InterruptClaim.MOUSE_BUTTONS = { MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_FORWARD, MOUSE_BACK }

InterruptClaim.ANNOUNCE_OFF = ANNOUNCE_OFF
InterruptClaim.CHANNEL_PARTY = CHANNEL_PARTY
InterruptClaim.CHANNEL_EMOTE = CHANNEL_EMOTE
InterruptClaim.CHANNEL_SAY = CHANNEL_SAY

---@type InterruptClaimAnnounceChannel[]
InterruptClaim.ANNOUNCE_CHANNELS = { ANNOUNCE_OFF, CHANNEL_PARTY, CHANNEL_SAY, CHANNEL_EMOTE }

InterruptClaim.ANNOUNCE_MAX_CHARS = ANNOUNCE_MAX_CHARS
InterruptClaim.ANNOUNCE_PLACEHOLDER = ANNOUNCE_PLACEHOLDER

-- Raid-target order matching {rt1}..{rt8} / UI-RaidTargetingIcon_1..8.
---@type string[]
InterruptClaim.MARKERS = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }

---@param modifier any
---@return boolean
local function IsKnownModifier(modifier)
    return MODIFIER_KEYS[modifier] ~= nil
end

---@param mouseButton any
---@return boolean
local function IsKnownMouseButton(mouseButton)
    return MOUSE_KEYS[mouseButton] ~= nil
end

---@param channel any
---@return boolean
local function IsKnownAnnounceChannel(channel)
    return channel == ANNOUNCE_OFF or CHANNEL_SLASH[channel] ~= nil
end

---Next byte after the UTF-8 sequence that starts at `index`.
---@param text string
---@param index integer
---@return integer
local function Utf8Next(text, index)
    local byte = string.byte(text, index)
    if not byte then
        return index + 1
    end
    if byte >= 240 then
        return index + 4
    elseif byte >= 224 then
        return index + 3
    elseif byte >= 192 then
        return index + 2
    end
    return index + 1
end

---@param text string
---@return integer
local function Utf8Len(text)
    local count = 0
    local index = 1
    while index <= #text do
        count = count + 1
        index = Utf8Next(text, index)
    end
    return count
end

---@param text string
---@param maxChars integer
---@return string
local function Utf8Truncate(text, maxChars)
    local count = 0
    local index = 1
    while index <= #text do
        local nextIndex = Utf8Next(text, index)
        if count + 1 > maxChars then
            return string.sub(text, 1, index - 1)
        end
        count = count + 1
        index = nextIndex
    end
    return text
end

---Drops newlines, WoW `|` escapes, and other control characters that could split the macro.
---@param text any
---@return string
local function SanitizeAnnounceMessage(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("|", "")
    text = text:gsub("[%z\1-\31\127]", "")
    text = text:match("^%s*(.-)%s*$") or ""
    return Utf8Truncate(text, ANNOUNCE_MAX_CHARS)
end

---@param message string
---@param markIndex integer
---@return string
local function SubstituteMarker(message, markIndex)
    return (message:gsub(ANNOUNCE_PLACEHOLDER, "{rt" .. markIndex .. "}"))
end

local function NotifyClickChanged()
    if InterruptClaim.OnClickChanged then
        InterruptClaim:OnClickChanged()
    end
end

local function NotifyMarkChanged()
    if InterruptClaim.OnMarkChanged then
        InterruptClaim:OnMarkChanged()
    end
end

---@param index any
---@return boolean
local function IsKnownMarkIndex(index)
    return type(index) == "number" and index >= 1 and index <= #InterruptClaim.MARKERS and index == math.floor(index)
end

---@return boolean
function InterruptClaim:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function InterruptClaim:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    if self.OnEnabledChanged then
        self:OnEnabledChanged()
    end
end

---@return InterruptClaimModifier
function InterruptClaim:GetModifier()
    local modifier = self.db.modifier
    return IsKnownModifier(modifier) and modifier or MODIFIER_SHIFT
end

---@param modifier InterruptClaimModifier
function InterruptClaim:SetModifier(modifier)
    assert(IsKnownModifier(modifier), "Unknown modifier: " .. tostring(modifier))
    if self.db.modifier == modifier then
        return
    end
    self.db.modifier = modifier
    NotifyClickChanged()
end

---@return InterruptClaimMouseButton
function InterruptClaim:GetMouseButton()
    local mouseButton = self.db.mouseButton
    return IsKnownMouseButton(mouseButton) and mouseButton or MOUSE_LEFT
end

---@param mouseButton InterruptClaimMouseButton
function InterruptClaim:SetMouseButton(mouseButton)
    assert(IsKnownMouseButton(mouseButton), "Unknown mouse button: " .. tostring(mouseButton))
    if self.db.mouseButton == mouseButton then
        return
    end
    self.db.mouseButton = mouseButton
    NotifyClickChanged()
end

---Binding key for SetOverrideBindingClick, e.g. "SHIFT-BUTTON1".
---@return string
function InterruptClaim:GetBindingKey()
    return MODIFIER_KEYS[self:GetModifier()] .. "-" .. MOUSE_KEYS[self:GetMouseButton()]
end

---Unit-frame click attribute for the chosen click, e.g. "shift-type1".
---@return string
function InterruptClaim:GetUnitFrameTypeAttribute()
    return self:GetModifier() .. "-type" .. MOUSE_ATTRIBUTE_SUFFIXES[self:GetMouseButton()]
end

---Unit-frame macro attribute paired with `GetUnitFrameTypeAttribute`, e.g. "shift-macrotext1".
---@return string
function InterruptClaim:GetUnitFrameMacroAttribute()
    return self:GetModifier() .. "-macrotext" .. MOUSE_ATTRIBUTE_SUFFIXES[self:GetMouseButton()]
end

---@return boolean
function InterruptClaim:IsMarkEnabled()
    return self.db.markEnabled == true
end

---@param enabled boolean
function InterruptClaim:SetMarkEnabled(enabled)
    enabled = enabled == true
    if self.db.markEnabled == enabled then
        return
    end
    self.db.markEnabled = enabled
    NotifyMarkChanged()
end

---@return integer
function InterruptClaim:GetMarkIndex()
    local index = self.db.markIndex
    return IsKnownMarkIndex(index) and index or 1
end

---@param index integer
function InterruptClaim:SetMarkIndex(index)
    assert(IsKnownMarkIndex(index), "Unknown mark index: " .. tostring(index))
    if self.db.markIndex == index then
        return
    end
    self.db.markIndex = index
    NotifyMarkChanged()
end

---@return boolean
function InterruptClaim:IsPreventOverwrite()
    return self.db.preventOverwrite == true
end

---@param enabled boolean
function InterruptClaim:SetPreventOverwrite(enabled)
    enabled = enabled == true
    if self.db.preventOverwrite == enabled then
        return
    end
    self.db.preventOverwrite = enabled
    NotifyMarkChanged()
end

---@return InterruptClaimAnnounceChannel
function InterruptClaim:GetAnnounceChannel()
    local channel = self.db.announceChannel
    return IsKnownAnnounceChannel(channel) and channel or ANNOUNCE_OFF
end

---@param channel InterruptClaimAnnounceChannel
function InterruptClaim:SetAnnounceChannel(channel)
    assert(IsKnownAnnounceChannel(channel), "Unknown announce channel: " .. tostring(channel))
    if self.db.announceChannel == channel then
        return
    end
    self.db.announceChannel = channel
    NotifyMarkChanged()
end

---Slash command for the chosen channel, e.g. "/p", or nil when announcement is off.
---@return string|nil
function InterruptClaim:GetAnnounceSlash()
    return CHANNEL_SLASH[self:GetAnnounceChannel()]
end

---@return boolean
function InterruptClaim:IsAnnounceEnabled()
    return self:GetAnnounceChannel() ~= ANNOUNCE_OFF
end

---@return string
function InterruptClaim:GetAnnounceMessage()
    return SanitizeAnnounceMessage(self.db.announceMessage)
end

---@return integer
function InterruptClaim:GetAnnounceCharCount()
    return Utf8Len(self:GetAnnounceMessage())
end

---@param message string
function InterruptClaim:SetAnnounceMessage(message)
    message = SanitizeAnnounceMessage(message)
    if self.db.announceMessage == message then
        return
    end
    self.db.announceMessage = message
    NotifyMarkChanged()
end

---Chat line after `{marker}` substitution, or nil when announcement is off.
---@return string|nil
function InterruptClaim:GetAnnounceLine()
    if not self:IsAnnounceEnabled() then
        return nil
    end
    local message = self:GetAnnounceMessage()
    if message == "" then
        return nil
    end
    return self:GetAnnounceSlash() .. " " .. SubstituteMarker(message, self:GetMarkIndex())
end

---Secure-button macro: focus the mouseover unit, and optionally mark it.
---@return string
function InterruptClaim:GetMacroText()
    if not self:IsMarkEnabled() then
        return FOCUS_MACRO
    end
    local prefix = self:IsPreventOverwrite() and "~" or ""
    local text = FOCUS_MACRO .. "\n" .. string.format(MARK_MACRO, prefix, self:GetMarkIndex())
    local announce = self:GetAnnounceLine()
    if announce then
        local withAnnounce = text .. "\n" .. announce
        if #withAnnounce <= MACRO_MAX_BODY_LENGTH then
            return withAnnounce
        end
    end
    return text
end

function InterruptClaim:OnInit()
    self.db.modifier = self:GetModifier()
    self.db.mouseButton = self:GetMouseButton()
    self.db.markIndex = self:GetMarkIndex()
    self.db.announceChannel = self:GetAnnounceChannel()
    self.db.announceMessage = self:GetAnnounceMessage()
end

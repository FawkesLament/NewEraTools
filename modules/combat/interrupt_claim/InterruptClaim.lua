local _, ns = ...
local Combat = ns.Api.Combat
local Macro = ns.Api.Macro
local Nameplate = ns.Api.Nameplate
local TargetFrame = ns.Api.TargetFrame
local L = ns.L

local MODIFIER_SHIFT = "shift"
local MODIFIER_CTRL = "ctrl"
local MODIFIER_ALT = "alt"

local MOUSE_LEFT = "LeftButton"
local MOUSE_RIGHT = "RightButton"

local ANNOUNCE_OFF = "off"
local CHANNEL_PARTY = "party"
local CHANNEL_SAY = "say"
local CHANNEL_EMOTE = "emote"

local MACRO_STATUS_MISSING = "missing"
local MACRO_STATUS_READY = "ready"
local MACRO_STATUS_CONFLICT = "conflict"

---@class InterruptClaim: Module
---@field OnMacrosChanged fun(self: InterruptClaim)|nil  Defined by the UI file; called when macros change.
---@field OnSettingsChanged fun(self: InterruptClaim)|nil  Defined by the UI file; called when settings or macro status change.
---@field ApplyNameplateClicks fun(self: InterruptClaim)|nil  Defined by the UI file; applies or clears plate overlays.
---@field ApplyNameplateAdded fun(self: InterruptClaim, frame: Frame)|nil  Defined by the UI file; binds one newly shown plate.
---@field ApplyNameplateRemoved fun(self: InterruptClaim)|nil  Defined by the UI file; drops overlays for hidden plates.
---@field ApplyTargetFrameClicks fun(self: InterruptClaim)|nil  Defined by the UI file; binds or restores Target Frame clicks.
local InterruptClaim = ns.Modules.New("InterruptClaim", {
    defaults = {
        enabled = false,
        modifier = MODIFIER_SHIFT,
        mouseButton = MOUSE_LEFT,
        bindTargetFrame = false,
        setMarker = false,
        -- Skull; the usual interrupt mark. Kept when the marker checkbox is off.
        marker = 8,
        -- "off" / "party" / "say" / "emote". Legacy boolean + announceChannel is still read.
        announce = ANNOUNCE_OFF,
    },
})

InterruptClaim.MODIFIER_SHIFT = MODIFIER_SHIFT
InterruptClaim.MODIFIER_CTRL = MODIFIER_CTRL
InterruptClaim.MODIFIER_ALT = MODIFIER_ALT
InterruptClaim.MODIFIERS = { MODIFIER_SHIFT, MODIFIER_CTRL, MODIFIER_ALT }

InterruptClaim.MOUSE_LEFT = MOUSE_LEFT
InterruptClaim.MOUSE_RIGHT = MOUSE_RIGHT
InterruptClaim.MOUSE_BUTTONS = { MOUSE_LEFT, MOUSE_RIGHT }

InterruptClaim.ANNOUNCE_OFF = ANNOUNCE_OFF
InterruptClaim.CHANNEL_PARTY = CHANNEL_PARTY
InterruptClaim.CHANNEL_SAY = CHANNEL_SAY
InterruptClaim.CHANNEL_EMOTE = CHANNEL_EMOTE
InterruptClaim.ANNOUNCE_MODES = { ANNOUNCE_OFF, CHANNEL_PARTY, CHANNEL_SAY, CHANNEL_EMOTE }
InterruptClaim.ANNOUNCE_CHANNELS = { CHANNEL_PARTY, CHANNEL_SAY, CHANNEL_EMOTE }

InterruptClaim.MACRO_STATUS_MISSING = MACRO_STATUS_MISSING
InterruptClaim.MACRO_STATUS_READY = MACRO_STATUS_READY
InterruptClaim.MACRO_STATUS_CONFLICT = MACRO_STATUS_CONFLICT

InterruptClaim.MARKER_MIN = 1
InterruptClaim.MARKER_MAX = 8

-- Macro UI names are capped at 16 characters.
local MACRO_NAME = "NETFocus"
local MACRO_ICON_PATH = "Interface\\Icons\\INV_Misc_QuestionMark"

local CHANNEL_SLASH = {
    [CHANNEL_PARTY] = "/p",
    [CHANNEL_SAY] = "/s",
    [CHANNEL_EMOTE] = "/e",
}

local MODIFIERS = {
    [MODIFIER_SHIFT] = true,
    [MODIFIER_CTRL] = true,
    [MODIFIER_ALT] = true,
}

local MOUSE_BUTTONS = {
    [MOUSE_LEFT] = true,
    [MOUSE_RIGHT] = true,
}

local CHANNELS = {
    [CHANNEL_PARTY] = true,
    [CHANNEL_SAY] = true,
    [CHANNEL_EMOTE] = true,
}

local listening = false
local clickListening = false
local combatListening = false
local clicksDirty = false
local macrosDirty = false

---@param modifier any
---@return string
local function SanitizeModifier(modifier)
    if MODIFIERS[modifier] then
        return modifier
    end
    return MODIFIER_SHIFT
end

---@param mouseButton any
---@return string
local function SanitizeMouseButton(mouseButton)
    if MOUSE_BUTTONS[mouseButton] then
        return mouseButton
    end
    return MOUSE_LEFT
end

---@param marker any
---@return integer
local function SanitizeMarker(marker)
    if type(marker) == "number" and marker >= InterruptClaim.MARKER_MIN and marker <= InterruptClaim.MARKER_MAX then
        return marker
    end
    return InterruptClaim.MARKER_MAX
end

---@param channel any
---@return string
local function SanitizeChannel(channel)
    if CHANNELS[channel] then
        return channel
    end
    return CHANNEL_PARTY
end

---@param announce any
---@param legacyChannel any
---@return string
local function SanitizeAnnounce(announce, legacyChannel)
    if announce == true then
        return SanitizeChannel(legacyChannel)
    end
    if announce == ANNOUNCE_OFF or CHANNELS[announce] then
        return announce
    end
    return ANNOUNCE_OFF
end

---@param marker integer
---@return string
local function AnnounceText(marker)
    return string.format(L.INTERRUPT_CLAIM_ANNOUNCE_TEXT, marker)
end

---@param setMarker boolean
---@param marker integer
---@param announce boolean
---@param channel string
---@return string
local function BuildMacroBody(setMarker, marker, announce, channel)
    if not setMarker then
        return "/focus"
    end
    local lines = {
        "/focus",
        "/stopmacro [group:raid]",
        "/tm " .. marker,
    }
    if announce then
        lines[#lines + 1] = CHANNEL_SLASH[channel] .. " " .. AnnounceText(marker)
    end
    return table.concat(lines, "\n")
end

---WoW may return `\r\n` and a trailing newline that the macro UI does not show.
---@param body string|nil
---@return string|nil
local function NormalizeMacroBody(body)
    if type(body) ~= "string" then
        return nil
    end
    return (body:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+$", ""))
end

---@param body string|nil
---@return boolean
local function IsManagedMacroBody(body)
    body = NormalizeMacroBody(body)
    if not body then
        return false
    end
    if body == "/focus" then
        return true
    end
    for marker = InterruptClaim.MARKER_MIN, InterruptClaim.MARKER_MAX do
        if body == BuildMacroBody(true, marker, false, CHANNEL_PARTY) then
            return true
        end
        for _, channel in ipairs(InterruptClaim.ANNOUNCE_CHANNELS) do
            if body == BuildMacroBody(true, marker, true, channel) then
                return true
            end
        end
    end
    return false
end

local function NotifySettingsChanged()
    if InterruptClaim.OnSettingsChanged then
        InterruptClaim:OnSettingsChanged()
    end
end

---@return integer
local function AccountMacroIndex()
    local index = Macro.GetIndexByName(MACRO_NAME)
    if index > 0 and not Macro.IsCharacterSlot(index) then
        return index
    end
    return 0
end

---@return string|nil
local function AccountMacroBody()
    local index = AccountMacroIndex()
    if index == 0 then
        return nil
    end
    local _, _, body = Macro.GetInfo(index)
    return body
end

---Creates or updates the account-wide focus macro.
---@param createIfMissing boolean
---@return boolean ok
---@return "combat"|"no_slot"|"failed"|"conflict"|nil reason
local function WriteFocusMacro(createIfMissing)
    if Combat.IsLockedDown() then
        return false, "combat"
    end
    local body = InterruptClaim.GetFocusMacroBody()
    local index = AccountMacroIndex()
    if index > 0 then
        local name, icon, currentBody = Macro.GetInfo(index)
        if NormalizeMacroBody(currentBody) == NormalizeMacroBody(body) then
            return true
        end
        if not IsManagedMacroBody(currentBody) then
            return false, "conflict"
        end
        local ok = pcall(Macro.Edit, index, name, icon, body)
        if not ok then
            return false, Combat.IsLockedDown() and "combat" or "failed"
        end
        if InterruptClaim:IsEnabled() then
            InterruptClaim:SyncNameplateClicks()
        end
        return true
    end
    if not createIfMissing then
        return true
    end
    local accountCount = Macro.GetNum()
    if accountCount >= Macro.ACCOUNT_SLOTS then
        return false, "no_slot"
    end
    local icon = Macro.GetFileIDFromPath(MACRO_ICON_PATH)
    local ok, created = pcall(Macro.Create, MACRO_NAME, icon, body, false)
    if not ok then
        return false, Combat.IsLockedDown() and "combat" or "failed"
    end
    if type(created) ~= "number" or created <= 0 or Macro.IsCharacterSlot(created) then
        return false, "no_slot"
    end
    if InterruptClaim:IsEnabled() then
        InterruptClaim:SyncNameplateClicks()
    end
    return true
end

---@return string
function InterruptClaim.GetFocusMacroName()
    return MACRO_NAME
end

---@return string
function InterruptClaim.GetFocusMacroBody()
    local announce = InterruptClaim:GetAnnounce()
    return BuildMacroBody(
        InterruptClaim:ShouldSetMarker(),
        InterruptClaim:GetMarker(),
        announce ~= ANNOUNCE_OFF,
        announce
    )
end

---@param marker integer
---@return string
function InterruptClaim.GetRaidMarkerIcon(marker)
    marker = SanitizeMarker(marker)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. marker
end

---@return boolean
function InterruptClaim:HasFocusMacro()
    return AccountMacroIndex() > 0
end

---@return "missing"|"ready"|"conflict"
function InterruptClaim:GetFocusMacroStatus()
    local body = AccountMacroBody()
    if body == nil then
        return MACRO_STATUS_MISSING
    end
    if NormalizeMacroBody(body) == NormalizeMacroBody(self.GetFocusMacroBody()) then
        return MACRO_STATUS_READY
    end
    return MACRO_STATUS_CONFLICT
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
    self:SyncNameplateClicks()
    NotifySettingsChanged()
end

---@return string
function InterruptClaim:GetModifier()
    local modifier = SanitizeModifier(self.db.modifier)
    self.db.modifier = modifier
    return modifier
end

---@param modifier string
function InterruptClaim:SetModifier(modifier)
    modifier = SanitizeModifier(modifier)
    if self:GetModifier() == modifier then
        return
    end
    self.db.modifier = modifier
    self:SyncNameplateClicks()
    NotifySettingsChanged()
end

---@return string
function InterruptClaim:GetMouseButton()
    local mouseButton = SanitizeMouseButton(self.db.mouseButton)
    self.db.mouseButton = mouseButton
    return mouseButton
end

---@param mouseButton string
function InterruptClaim:SetMouseButton(mouseButton)
    mouseButton = SanitizeMouseButton(mouseButton)
    if self:GetMouseButton() == mouseButton then
        return
    end
    self.db.mouseButton = mouseButton
    self:SyncNameplateClicks()
    NotifySettingsChanged()
end

---@return boolean
function InterruptClaim:IsTargetFrameBound()
    return self.db.bindTargetFrame == true
end

---@param enabled boolean
function InterruptClaim:SetBindTargetFrame(enabled)
    enabled = enabled == true
    if self.db.bindTargetFrame == enabled then
        return
    end
    self.db.bindTargetFrame = enabled
    self:SyncNameplateClicks()
    NotifySettingsChanged()
end

---@return boolean
function InterruptClaim:ShouldSetMarker()
    return self.db.setMarker == true
end

---@param enabled boolean
function InterruptClaim:SetSetMarker(enabled)
    enabled = enabled == true
    if self.db.setMarker == enabled then
        return
    end
    self.db.setMarker = enabled
    self:SyncFocusMacro()
    NotifySettingsChanged()
end

---@return integer
function InterruptClaim:GetMarker()
    local marker = SanitizeMarker(self.db.marker)
    self.db.marker = marker
    return marker
end

---@param marker integer
function InterruptClaim:SetMarker(marker)
    marker = SanitizeMarker(marker)
    if self:GetMarker() == marker then
        return
    end
    self.db.marker = marker
    self:SyncFocusMacro()
    NotifySettingsChanged()
end

---@return string
function InterruptClaim:GetAnnounce()
    local announce = SanitizeAnnounce(self.db.announce, self.db.announceChannel)
    self.db.announce = announce
    return announce
end

---@return boolean
function InterruptClaim:ShouldAnnounce()
    return self:ShouldSetMarker() and self:GetAnnounce() ~= ANNOUNCE_OFF
end

---@param announce string
function InterruptClaim:SetAnnounce(announce)
    announce = SanitizeAnnounce(announce, self.db.announceChannel)
    if self:GetAnnounce() == announce then
        return
    end
    self.db.announce = announce
    self:SyncFocusMacro()
    NotifySettingsChanged()
end

---@class InterruptClaimClickBinding
---@field modifier string
---@field mouseButton string
---@field buttonIndex integer
---@field typeAttribute string
---@field macroAttribute string
---@field click string
---@field passThrough string[]
---@field fallbackAttribute string
---@field fallbackType string

---@return InterruptClaimClickBinding
function InterruptClaim:GetClickBinding()
    local modifier = self:GetModifier()
    local mouseButton = self:GetMouseButton()
    local buttonIndex = mouseButton == MOUSE_RIGHT and 2 or 1
    return {
        modifier = modifier,
        mouseButton = mouseButton,
        buttonIndex = buttonIndex,
        typeAttribute = modifier .. "-type" .. buttonIndex,
        macroAttribute = modifier .. "-macro" .. buttonIndex,
        click = mouseButton .. "Down",
        passThrough = mouseButton == MOUSE_RIGHT and { "LeftButton", "MiddleButton", "Button4", "Button5" }
            or { "RightButton", "MiddleButton", "Button4", "Button5" },
        fallbackAttribute = buttonIndex == 2 and "*type2" or "*type1",
        fallbackType = buttonIndex == 2 and "togglemenu" or "target",
    }
end

---True when the feature is on and a NETFocus macro exists (account or character).
---@return boolean
function InterruptClaim:ShouldBindNameplateClicks()
    return self:IsEnabled() and Macro.GetIndexByName(MACRO_NAME) > 0
end

---True when nameplate clicks bind and Target Frame coverage is enabled.
---@return boolean
function InterruptClaim:ShouldBindTargetFrameClicks()
    return self:ShouldBindNameplateClicks() and self:IsTargetFrameBound()
end

---Applies or clears nameplate overlays and optional Target Frame clicks. Defers during combat lockdown.
---@return boolean ok
---@return "combat"|nil reason
function InterruptClaim:SyncNameplateClicks()
    if Combat.IsLockedDown() then
        clicksDirty = true
        return false, "combat"
    end
    local deferred = clicksDirty
    clicksDirty = false
    if self.ApplyNameplateClicks then
        self:ApplyNameplateClicks()
    end
    if self.ApplyTargetFrameClicks then
        self:ApplyTargetFrameClicks()
    end
    if deferred then
        NotifySettingsChanged()
    end
    return true
end

---Rewrites an existing managed NETFocus macro to match current optional behaviors. Does not create.
---@return boolean ok
---@return "combat"|"failed"|"conflict"|nil reason
function InterruptClaim:SyncFocusMacro()
    if Combat.IsLockedDown() then
        if self:HasFocusMacro() then
            macrosDirty = true
        end
        return false, "combat"
    end
    macrosDirty = false
    if not self:HasFocusMacro() then
        return true
    end
    return WriteFocusMacro(false)
end

---Creates the account-wide focus macro when it is missing. Blocked in combat.
---Does not overwrite a macro that already uses the same name.
---@return boolean ok
---@return "combat"|"no_slot"|"failed"|"conflict"|nil reason
function InterruptClaim:CreateFocusMacro()
    return WriteFocusMacro(true)
end

local function ListenForCombat()
    if combatListening then
        return
    end
    combatListening = true
    Combat.OnLeave(function()
        if macrosDirty then
            InterruptClaim:SyncFocusMacro()
            if InterruptClaim.OnMacrosChanged then
                InterruptClaim:OnMacrosChanged()
            end
        end
        if clicksDirty then
            InterruptClaim:SyncNameplateClicks()
        end
    end)
end

---Watches nameplates, Target Frame, and combat. Plate add/remove stay incremental; full
---sync runs on module state changes and after combat when a protected update was deferred.
function InterruptClaim:ListenForNameplateClicks()
    if clickListening then
        return
    end
    clickListening = true
    ListenForCombat()
    Nameplate.OnAdded(function(_, frame)
        if Combat.IsLockedDown() then
            if InterruptClaim:ShouldBindNameplateClicks() then
                clicksDirty = true
            end
            return
        end
        if InterruptClaim.ApplyNameplateAdded then
            InterruptClaim:ApplyNameplateAdded(frame)
        end
    end)
    Nameplate.OnRemoved(function()
        if Combat.IsLockedDown() then
            if InterruptClaim:ShouldBindNameplateClicks() then
                clicksDirty = true
            end
            return
        end
        if InterruptClaim.ApplyNameplateRemoved then
            InterruptClaim:ApplyNameplateRemoved()
        end
    end)
    TargetFrame.OnReady(function()
        InterruptClaim:SyncNameplateClicks()
    end)
end

---Refreshes settings status when the player creates or deletes macros. Called from OnEnable.
function InterruptClaim:ListenForMacros()
    if listening then
        return
    end
    listening = true
    ListenForCombat()
    Macro.OnChanged(function()
        InterruptClaim:SyncFocusMacro()
        InterruptClaim:SyncNameplateClicks()
        if InterruptClaim.OnMacrosChanged then
            InterruptClaim:OnMacrosChanged()
        end
    end)
end

local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local Color = ns.Color
local Util = ns.Util
local Schema = Internals.Schema

-- Stable AddonCheck provider id; version is owned by AddonCheck, not this snapshot.
local ADDON_CHECK_MODULE_ID = "TwinFangs"

-- The Twin Fangs, the sixth boss of The Venomous Abyss.
-- There is no module-wide enable. Each reminder keeps its own saved settings.
---@class TwinFangs: Module
---@field db TwinFangsSettings
---@field OnCalloutChanged fun(self: TwinFangs)|nil  Defined by the UI; callout shown or cleared.
---@field OnInterruptReminderChanged fun(self: TwinFangs)|nil  Defined by the UI; interrupt test button enabled or blocked.
---@field OnNameplateHintChanged fun(self: TwinFangs)|nil  Defined by the UI; nameplate preview button enabled or blocked.
---@field OnNameplateHintPreviewChanged fun(self: TwinFangs)|nil  Defined by the UI; nameplate badges shown or hidden.
---@field OnNameplateHintAppearanceChanged fun(self: TwinFangs)|nil  Defined by the UI; visible badges restyled.
---@field OnNameplateHintShow fun(self: TwinFangs, unit: string, number: integer)|nil  Defined by the UI; live badge attached.
---@field OnNameplateHintHide fun(self: TwinFangs, unit: string)|nil  Defined by the UI; live badge removed.
---@field OnNameplateHintCleared fun(self: TwinFangs)|nil  Defined by the UI; every live badge removed.
---@field OnInterruptStatusChanged fun(self: TwinFangs)|nil  Defined by the UI; interrupt StatusHUD shown, updated, or hidden.
local TwinFangs = ns.Modules.New("TwinFangs", {
    defaults = Schema.NewSettings(),
})

TwinFangs.ADDON_CHECK_MODULE_ID = ADDON_CHECK_MODULE_ID
-- Raid leader is commander for interrupt reminder; everyone else is a member.
ns.RaidRole.Attach(TwinFangs)

local function NotifyNameplateHintChanged()
    if TwinFangs.OnNameplateHintChanged then
        TwinFangs:OnNameplateHintChanged()
    end
end

local function NotifyNameplateHintPreviewChanged()
    if TwinFangs.OnNameplateHintPreviewChanged then
        TwinFangs:OnNameplateHintPreviewChanged()
    end
end

local function NotifyNameplateHintAppearanceChanged()
    if TwinFangs.OnNameplateHintAppearanceChanged then
        TwinFangs:OnNameplateHintAppearanceChanged()
    end
end

-- Session-only; the settings toggle does not show badges until the player starts a preview.
local nameplateHintPreviewing = false

---@param settings TwinFangsNameplateHint
local function SanitizeNameplateHint(settings)
    if not Schema.SIDES[settings.side] then
        settings.side = Schema.SIDE_LEFT
    end
    settings.size =
        Util.Snap(tonumber(settings.size) or Schema.SIZE_DEFAULT, Schema.SIZE_MIN, Schema.SIZE_MAX, Schema.SIZE_STEP)
    settings.offsetX =
        Util.Snap(tonumber(settings.offsetX) or 0, Schema.OFFSET_MIN, Schema.OFFSET_MAX, Schema.OFFSET_STEP)
    settings.offsetY =
        Util.Snap(tonumber(settings.offsetY) or 0, Schema.OFFSET_MIN, Schema.OFFSET_MAX, Schema.OFFSET_STEP)
    settings.opacity = Util.Snap(
        tonumber(settings.opacity) or Schema.OPACITY_DEFAULT,
        Schema.OPACITY_MIN,
        Schema.OPACITY_MAX,
        Schema.OPACITY_STEP
    )
    if type(settings.font) ~= "string" or settings.font == "" then
        settings.font = Schema.FONT_DEFAULT
    end
    settings.fontSize = Util.Snap(
        tonumber(settings.fontSize) or Schema.FONT_SIZE_DEFAULT,
        Schema.FONT_SIZE_MIN,
        Schema.FONT_SIZE_MAX,
        Schema.FONT_SIZE_STEP
    )
    local fontColor = Color.Normalize(settings.fontColor) or Schema.FONT_COLOR_DEFAULT
    if type(settings.fontColor) ~= "table" then
        settings.fontColor = { r = fontColor.r, g = fontColor.g, b = fontColor.b }
    else
        Color.Copy(settings.fontColor, fontColor)
    end
end

---@return boolean
function TwinFangs:IsSoakReminderEnabled()
    return self.db.soakReminder.enabled == true
end

---@param enabled boolean
function TwinFangs:SetSoakReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.soakReminder.enabled == enabled then
        return
    end
    self.db.soakReminder.enabled = enabled
    if not enabled then
        self:CancelSoakCallout()
    end
end

---@return "left"|"middle"|"right"
function TwinFangs:GetSoakGroup()
    return self.db.soakReminder.group
end

---@param group "left"|"middle"|"right"
function TwinFangs:SetSoakGroup(group)
    assert(Schema.GROUPS[group], "Bad soak group")
    self.db.soakReminder.group = group
end

---@return boolean
function TwinFangs:IsInterruptReminderEnabled()
    return self.db.interruptReminder.enabled == true
end

---@param enabled boolean
function TwinFangs:SetInterruptReminderEnabled(enabled)
    enabled = enabled == true
    if self.db.interruptReminder.enabled == enabled then
        return
    end
    self.db.interruptReminder.enabled = enabled
    if not enabled then
        self:SetInterruptStatusTestMode(false)
    end
    if TwinFangs.OnInterruptReminderChanged then
        TwinFangs:OnInterruptReminderChanged()
    end
end

---@return boolean
function TwinFangs:IsInterruptVoiceEnabled()
    return self.db.interruptReminder.voice == true
end

---@param enabled boolean
function TwinFangs:SetInterruptVoiceEnabled(enabled)
    self.db.interruptReminder.voice = enabled == true
end

---@return boolean
function TwinFangs:IsNameplateHintEnabled()
    return self.db.nameplateHint.enabled == true
end

---@param enabled boolean
function TwinFangs:SetNameplateHintEnabled(enabled)
    enabled = enabled == true
    if self.db.nameplateHint.enabled == enabled then
        return
    end
    self.db.nameplateHint.enabled = enabled
    if not enabled then
        self:ClearNameplateHints()
        self:SetNameplateHintPreviewing(false)
    end
    NotifyNameplateHintChanged()
end

---@return boolean
function TwinFangs:IsNameplateHintPreviewing()
    return nameplateHintPreviewing == true
end

---@param enabled boolean
function TwinFangs:SetNameplateHintPreviewing(enabled)
    enabled = enabled == true and self:IsNameplateHintEnabled()
    if nameplateHintPreviewing == enabled then
        return
    end
    nameplateHintPreviewing = enabled
    NotifyNameplateHintPreviewChanged()
end

---@return "left"|"right"|"top"|"bottom"
function TwinFangs:GetNameplateHintSide()
    return self.db.nameplateHint.side
end

---@param side "left"|"right"|"top"|"bottom"
function TwinFangs:SetNameplateHintSide(side)
    assert(Schema.SIDES[side], "Bad nameplate hint side")
    if self.db.nameplateHint.side == side then
        return
    end
    self.db.nameplateHint.side = side
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function TwinFangs:GetNameplateHintSize()
    return self.db.nameplateHint.size
end

---@param size number
function TwinFangs:SetNameplateHintSize(size)
    size = Util.Snap(size, Schema.SIZE_MIN, Schema.SIZE_MAX, Schema.SIZE_STEP)
    if self.db.nameplateHint.size == size then
        return
    end
    self.db.nameplateHint.size = size
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function TwinFangs:GetNameplateHintOffsetX()
    return self.db.nameplateHint.offsetX
end

---@param offset number
function TwinFangs:SetNameplateHintOffsetX(offset)
    offset = Util.Snap(offset, Schema.OFFSET_MIN, Schema.OFFSET_MAX, Schema.OFFSET_STEP)
    if self.db.nameplateHint.offsetX == offset then
        return
    end
    self.db.nameplateHint.offsetX = offset
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function TwinFangs:GetNameplateHintOffsetY()
    return self.db.nameplateHint.offsetY
end

---@param offset number
function TwinFangs:SetNameplateHintOffsetY(offset)
    offset = Util.Snap(offset, Schema.OFFSET_MIN, Schema.OFFSET_MAX, Schema.OFFSET_STEP)
    if self.db.nameplateHint.offsetY == offset then
        return
    end
    self.db.nameplateHint.offsetY = offset
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function TwinFangs:GetNameplateHintOpacity()
    return self.db.nameplateHint.opacity
end

---@param opacity number
function TwinFangs:SetNameplateHintOpacity(opacity)
    opacity = Util.Snap(opacity, Schema.OPACITY_MIN, Schema.OPACITY_MAX, Schema.OPACITY_STEP)
    if self.db.nameplateHint.opacity == opacity then
        return
    end
    self.db.nameplateHint.opacity = opacity
    NotifyNameplateHintAppearanceChanged()
end

---@return string
function TwinFangs:GetNameplateHintFont()
    local font = self.db.nameplateHint.font
    if type(font) ~= "string" or font == "" then
        return Schema.FONT_DEFAULT
    end
    return font
end

---@param font string
function TwinFangs:SetNameplateHintFont(font)
    assert(type(font) == "string" and font ~= "", "Bad nameplate hint font")
    if self.db.nameplateHint.font == font then
        return
    end
    self.db.nameplateHint.font = font
    NotifyNameplateHintAppearanceChanged()
end

---@return number
function TwinFangs:GetNameplateHintFontSize()
    return self.db.nameplateHint.fontSize
end

---@param size number
function TwinFangs:SetNameplateHintFontSize(size)
    size = Util.Snap(size, Schema.FONT_SIZE_MIN, Schema.FONT_SIZE_MAX, Schema.FONT_SIZE_STEP)
    if self.db.nameplateHint.fontSize == size then
        return
    end
    self.db.nameplateHint.fontSize = size
    NotifyNameplateHintAppearanceChanged()
end

---@return RgbColor
function TwinFangs:GetNameplateHintFontColor()
    return Color.Normalize(self.db.nameplateHint.fontColor)
        or {
            r = Schema.FONT_COLOR_DEFAULT.r,
            g = Schema.FONT_COLOR_DEFAULT.g,
            b = Schema.FONT_COLOR_DEFAULT.b,
        }
end

---@param color RgbColor
function TwinFangs:SetNameplateHintFontColor(color)
    local next = Color.Normalize(color)
    assert(next ~= nil, "Bad nameplate hint font color")
    local saved = self.db.nameplateHint.fontColor
    if type(saved) ~= "table" then
        self.db.nameplateHint.fontColor = { r = next.r, g = next.g, b = next.b }
        NotifyNameplateHintAppearanceChanged()
        return
    end
    if Color.Equal(saved, next) then
        return
    end
    Color.Copy(saved, next)
    NotifyNameplateHintAppearanceChanged()
end

function TwinFangs:ResetNameplateHintAppearance()
    local defaults = Schema.NewNameplateHint()
    local saved = self.db.nameplateHint
    saved.side = defaults.side
    saved.size = defaults.size
    saved.offsetX = defaults.offsetX
    saved.offsetY = defaults.offsetY
    saved.opacity = defaults.opacity
    saved.font = defaults.font
    saved.fontSize = defaults.fontSize
    if type(saved.fontColor) ~= "table" then
        saved.fontColor = defaults.fontColor
    else
        Color.Copy(saved.fontColor, defaults.fontColor)
    end
    NotifyNameplateHintAppearanceChanged()
end

---@return CalloutAnchor
function TwinFangs:GetCalloutPosition()
    return ns.CalloutAnchor.GetPosition()
end

---@param position CalloutAnchor
function TwinFangs:SetCalloutPosition(position)
    ns.CalloutAnchor.SetPosition(position)
end

---@return FloatingWindowPosition
function TwinFangs:GetInterruptStatusHudPosition()
    return self.db.interruptStatusHudPosition
end

---@param position FloatingWindowPosition
function TwinFangs:SetInterruptStatusHudPosition(position)
    assert(ns.Position.IsValid(position), "Bad interrupt status HUD position")
    local saved = self.db.interruptStatusHudPosition
    if type(saved) ~= "table" then
        self.db.interruptStatusHudPosition = {
            point = position.point,
            relativePoint = position.relativePoint,
            x = position.x,
            y = position.y,
        }
        return
    end
    saved.point = position.point
    saved.relativePoint = position.relativePoint
    saved.x = position.x
    saved.y = position.y
end

function TwinFangs:OnInit()
    if not Schema.GROUPS[self.db.soakReminder.group] then
        self.db.soakReminder.group = Schema.GROUP_LEFT
    end
    if ns.Position.IsValid(self.db.statusHudPosition) then
        self:SetInterruptStatusHudPosition(self.db.statusHudPosition)
    end
    self.db.statusHudPosition = nil
    if not ns.Position.IsValid(self.db.interruptStatusHudPosition) then
        self.db.interruptStatusHudPosition = Schema.DefaultInterruptStatusHudPosition()
    end
    SanitizeNameplateHint(self.db.nameplateHint)
    local reminder = self.db.interruptReminder
    if type(reminder) ~= "table" then
        reminder = { enabled = false, voice = false, chain = Schema.NewInterruptChain() }
        self.db.interruptReminder = reminder
    end
    reminder.chain = Internals.InterruptChain.SanitizeSaved(reminder.chain)
    -- Raid members must answer config checks; register regardless of UI, role, or encounter.
    ns.AddonCheck.Register(ADDON_CHECK_MODULE_ID, function()
        return TwinFangs:GetAddonCheckConfig()
    end)
end

---Adopts interrupt-chain publications from the raid. Called from OnEnable.
function TwinFangs:ListenForInterruptChain()
    Internals.InterruptChain.Listen()
end

---Keeps the character interrupt macro in sync. Defined by interrupt_chain/Macros.lua.
function TwinFangs:ListenForInterruptMacro() end

---Drops a pending or visible soak reminder. Defined with the encounter listener.
function TwinFangs:CancelSoakCallout() end

---Shows a soak or interrupt callout. A later show drops the current message. Defined with the encounter listener.
function TwinFangs:ShowCallout() end

---Clears the current callout, or only one kind when `kind` is set. Defined with the encounter listener.
function TwinFangs:CancelCallout() end

---Starts the Brood interrupt-status window. Defined by InterruptStatus.lua.
function TwinFangs:BeginInterruptStatusWindow() end

---Hides the interrupt-status window and resets the counts. Defined by InterruptStatus.lua.
function TwinFangs:EndInterruptStatusWindow() end

---Counts party-chat and backup-whisper reports during a Brood window. Defined by InterruptStatus.lua.
function TwinFangs:ListenForInterruptStatus() end

---Panel test mode for the interrupt-status HUD. Defined by InterruptStatus.lua.
function TwinFangs:SetInterruptStatusTestMode() end

---Whether the interrupt-status HUD is in panel test mode. Defined by InterruptStatus.lua.
function TwinFangs:IsInterruptStatusTestMode() end

---Drops live nameplate badges. Defined with the hint listener.
function TwinFangs:ClearNameplateHints() end

---Reattaches live badges after a preview ends. Defined with the hint listener.
function TwinFangs:ReplayNameplateHints() end

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
---@field OnInterruptReminderChanged fun(self: TwinFangs)|nil  Defined by the UI; interrupt test button enabled or blocked.
---@field OnNameplateHintChanged fun(self: TwinFangs)|nil  Defined by the UI; nameplate preview button enabled or blocked.
---@field OnNameplateHintPreviewChanged fun(self: TwinFangs)|nil  Defined by the UI; nameplate badges shown or hidden.
---@field OnNameplateHintAppearanceChanged fun(self: TwinFangs)|nil  Defined by the UI; visible badges restyled.
---@field OnNameplateHintShow fun(self: TwinFangs, unit: string, number: integer)|nil  Defined by the UI; live badge attached.
---@field OnNameplateHintHide fun(self: TwinFangs, unit: string)|nil  Defined by the UI; live badge removed.
---@field OnNameplateHintCleared fun(self: TwinFangs)|nil  Defined by the UI; every live badge removed.
---@field OnInterruptStatusChanged fun(self: TwinFangs)|nil  Defined by the UI; interrupt rotation tracker shown, updated, or hidden.
---@field OnVenomRosterEnabledChanged fun(self: TwinFangs)|nil  Defined by the UI; roster hidden or shown from the settings toggle.
---@field OnVenomRosterAppearanceChanged fun(self: TwinFangs)|nil  Defined by the UI; scale, spacing, and fonts applied in place.
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
function TwinFangs:IsSoakTimelineEnabled()
    return self.db.soakReminder.timeline == true
end

---@param enabled boolean
function TwinFangs:SetSoakTimelineEnabled(enabled)
    enabled = enabled == true
    if self.db.soakReminder.timeline == enabled then
        return
    end
    self.db.soakReminder.timeline = enabled
    if not enabled then
        self:StopSoakTimeline()
    end
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

---@return InterruptRotationTrackerAnchor
function TwinFangs:GetInterruptRotationTrackerPosition()
    return ns.InterruptRotationTrackerAnchor.GetPosition()
end

---@param position InterruptRotationTrackerAnchor
function TwinFangs:SetInterruptRotationTrackerPosition(position)
    ns.InterruptRotationTrackerAnchor.SetPosition(position)
end

---@return FloatingWindowPosition
function TwinFangs:GetSoakTimelinePosition()
    return self.db.soakTimelinePosition
end

---@param position FloatingWindowPosition
function TwinFangs:SetSoakTimelinePosition(position)
    assert(ns.Position.IsValid(position), "Bad soak timeline position")
    local saved = self.db.soakTimelinePosition
    if type(saved) ~= "table" then
        self.db.soakTimelinePosition = {
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

---@param settings TwinFangsVenomRosterSettings
local function SanitizeVenomRoster(settings)
    settings.enabled = settings.enabled ~= false
    settings.scale = nil
    settings.columns = Util.Snap(
        tonumber(settings.columns) or Schema.VENOM_ROSTER_COLUMNS_DEFAULT,
        Schema.VENOM_ROSTER_COLUMNS_MIN,
        Schema.VENOM_ROSTER_COLUMNS_MAX,
        Schema.VENOM_ROSTER_COLUMNS_STEP
    )
    settings.rowHeight = Util.Snap(
        tonumber(settings.rowHeight) or Schema.VENOM_ROSTER_ROW_HEIGHT_DEFAULT,
        Schema.VENOM_ROSTER_ROW_HEIGHT_MIN,
        Schema.VENOM_ROSTER_ROW_HEIGHT_MAX,
        Schema.VENOM_ROSTER_ROW_HEIGHT_STEP
    )
    settings.rowGap = Util.Snap(
        tonumber(settings.rowGap) or Schema.VENOM_ROSTER_ROW_GAP_DEFAULT,
        Schema.VENOM_ROSTER_ROW_GAP_MIN,
        Schema.VENOM_ROSTER_ROW_GAP_MAX,
        Schema.VENOM_ROSTER_ROW_GAP_STEP
    )
    settings.columnGap = Util.Snap(
        tonumber(settings.columnGap) or Schema.VENOM_ROSTER_COLUMN_GAP_DEFAULT,
        Schema.VENOM_ROSTER_COLUMN_GAP_MIN,
        Schema.VENOM_ROSTER_COLUMN_GAP_MAX,
        Schema.VENOM_ROSTER_COLUMN_GAP_STEP
    )
    settings.nameColumnWidth = Util.Snap(
        tonumber(settings.nameColumnWidth) or Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_DEFAULT,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MIN,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MAX,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_STEP
    )
    settings.nameFontSize = Util.Snap(
        tonumber(settings.nameFontSize) or Schema.VENOM_ROSTER_NAME_FONT_SIZE_DEFAULT,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_STEP
    )
    settings.stackFontSize = Util.Snap(
        tonumber(settings.stackFontSize) or Schema.VENOM_ROSTER_STACK_FONT_SIZE_DEFAULT,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_STEP
    )
    if not ns.SharedMedia.IsKnownStatusBarTexture(settings.barTexture) then
        settings.barTexture = Schema.VENOM_ROSTER_BAR_TEXTURE_DEFAULT
    end
    local barColor = Color.Normalize(settings.barColor) or Schema.VENOM_ROSTER_BAR_COLOR_DEFAULT
    if type(settings.barColor) ~= "table" then
        settings.barColor = { r = barColor.r, g = barColor.g, b = barColor.b }
    else
        Color.Copy(settings.barColor, barColor)
    end
    local numberColor = Color.Normalize(settings.numberColor) or Schema.VENOM_ROSTER_NUMBER_COLOR_DEFAULT
    if type(settings.numberColor) ~= "table" then
        settings.numberColor = { r = numberColor.r, g = numberColor.g, b = numberColor.b }
    else
        Color.Copy(settings.numberColor, numberColor)
    end
    settings.backgroundOpacity = Util.Snap(
        tonumber(settings.backgroundOpacity) or Schema.VENOM_ROSTER_BACKGROUND_OPACITY_DEFAULT,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_MIN,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_MAX,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_STEP
    )
    settings.barOpacity = Util.Snap(
        tonumber(settings.barOpacity) or Schema.VENOM_ROSTER_BAR_OPACITY_DEFAULT,
        Schema.VENOM_ROSTER_BAR_OPACITY_MIN,
        Schema.VENOM_ROSTER_BAR_OPACITY_MAX,
        Schema.VENOM_ROSTER_BAR_OPACITY_STEP
    )
end

local function NotifyVenomRosterEnabled()
    if TwinFangs.OnVenomRosterEnabledChanged then
        TwinFangs:OnVenomRosterEnabledChanged()
    end
end

local function NotifyVenomRosterAppearance()
    if TwinFangs.OnVenomRosterAppearanceChanged then
        TwinFangs:OnVenomRosterAppearanceChanged()
    end
end

---@return boolean
function TwinFangs:IsVenomRosterEnabled()
    return self.db.venomRoster.enabled ~= false
end

---@param enabled boolean
function TwinFangs:SetVenomRosterEnabled(enabled)
    enabled = enabled == true
    if self.db.venomRoster.enabled == enabled then
        return
    end
    self.db.venomRoster.enabled = enabled
    NotifyVenomRosterEnabled()
end

---@return number
function TwinFangs:GetVenomRosterColumns()
    return self.db.venomRoster.columns
end

---@param columns number
function TwinFangs:SetVenomRosterColumns(columns)
    columns = Util.Snap(
        columns,
        Schema.VENOM_ROSTER_COLUMNS_MIN,
        Schema.VENOM_ROSTER_COLUMNS_MAX,
        Schema.VENOM_ROSTER_COLUMNS_STEP
    )
    if self.db.venomRoster.columns == columns then
        return
    end
    self.db.venomRoster.columns = columns
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterRowHeight()
    return self.db.venomRoster.rowHeight
end

---@param height number
function TwinFangs:SetVenomRosterRowHeight(height)
    height = Util.Snap(
        height,
        Schema.VENOM_ROSTER_ROW_HEIGHT_MIN,
        Schema.VENOM_ROSTER_ROW_HEIGHT_MAX,
        Schema.VENOM_ROSTER_ROW_HEIGHT_STEP
    )
    if self.db.venomRoster.rowHeight == height then
        return
    end
    self.db.venomRoster.rowHeight = height
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterRowGap()
    return self.db.venomRoster.rowGap
end

---@param gap number
function TwinFangs:SetVenomRosterRowGap(gap)
    gap = Util.Snap(
        gap,
        Schema.VENOM_ROSTER_ROW_GAP_MIN,
        Schema.VENOM_ROSTER_ROW_GAP_MAX,
        Schema.VENOM_ROSTER_ROW_GAP_STEP
    )
    if self.db.venomRoster.rowGap == gap then
        return
    end
    self.db.venomRoster.rowGap = gap
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterColumnGap()
    return self.db.venomRoster.columnGap
end

---@param gap number
function TwinFangs:SetVenomRosterColumnGap(gap)
    gap = Util.Snap(
        gap,
        Schema.VENOM_ROSTER_COLUMN_GAP_MIN,
        Schema.VENOM_ROSTER_COLUMN_GAP_MAX,
        Schema.VENOM_ROSTER_COLUMN_GAP_STEP
    )
    if self.db.venomRoster.columnGap == gap then
        return
    end
    self.db.venomRoster.columnGap = gap
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterNameColumnWidth()
    return self.db.venomRoster.nameColumnWidth
end

---@param width number
function TwinFangs:SetVenomRosterNameColumnWidth(width)
    width = Util.Snap(
        width,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MIN,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MAX,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_STEP
    )
    if self.db.venomRoster.nameColumnWidth == width then
        return
    end
    self.db.venomRoster.nameColumnWidth = width
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterNameFontSize()
    return self.db.venomRoster.nameFontSize
end

---@param size number
function TwinFangs:SetVenomRosterNameFontSize(size)
    size = Util.Snap(
        size,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_STEP
    )
    if self.db.venomRoster.nameFontSize == size then
        return
    end
    self.db.venomRoster.nameFontSize = size
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterStackFontSize()
    return self.db.venomRoster.stackFontSize
end

---@param size number
function TwinFangs:SetVenomRosterStackFontSize(size)
    size = Util.Snap(
        size,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_STEP
    )
    if self.db.venomRoster.stackFontSize == size then
        return
    end
    self.db.venomRoster.stackFontSize = size
    NotifyVenomRosterAppearance()
end

---@return RgbColor
function TwinFangs:GetVenomRosterNumberColor()
    return Color.Normalize(self.db.venomRoster.numberColor)
        or {
            r = Schema.VENOM_ROSTER_NUMBER_COLOR_DEFAULT.r,
            g = Schema.VENOM_ROSTER_NUMBER_COLOR_DEFAULT.g,
            b = Schema.VENOM_ROSTER_NUMBER_COLOR_DEFAULT.b,
        }
end

---@param color RgbColor
function TwinFangs:SetVenomRosterNumberColor(color)
    local next = Color.Normalize(color)
    assert(next ~= nil, "Bad venom roster number color")
    local saved = self.db.venomRoster.numberColor
    if type(saved) ~= "table" then
        self.db.venomRoster.numberColor = { r = next.r, g = next.g, b = next.b }
        NotifyVenomRosterAppearance()
        return
    end
    if Color.Equal(saved, next) then
        return
    end
    Color.Copy(saved, next)
    NotifyVenomRosterAppearance()
end

---@return string
function TwinFangs:GetVenomRosterBarTexture()
    local textureId = self.db.venomRoster.barTexture
    if ns.SharedMedia.IsKnownStatusBarTexture(textureId) then
        return textureId
    end
    return Schema.VENOM_ROSTER_BAR_TEXTURE_DEFAULT
end

---@return string
function TwinFangs:GetVenomRosterBarTexturePath()
    return ns.SharedMedia.ResolveStatusBarTexturePath(self:GetVenomRosterBarTexture())
end

---@param textureId string
function TwinFangs:SetVenomRosterBarTexture(textureId)
    assert(ns.SharedMedia.IsKnownStatusBarTexture(textureId), "Unknown texture: " .. tostring(textureId))
    if self.db.venomRoster.barTexture == textureId then
        return
    end
    self.db.venomRoster.barTexture = textureId
    NotifyVenomRosterAppearance()
end

---@return RgbColor
function TwinFangs:GetVenomRosterBarColor()
    return Color.Normalize(self.db.venomRoster.barColor)
        or {
            r = Schema.VENOM_ROSTER_BAR_COLOR_DEFAULT.r,
            g = Schema.VENOM_ROSTER_BAR_COLOR_DEFAULT.g,
            b = Schema.VENOM_ROSTER_BAR_COLOR_DEFAULT.b,
        }
end

---@param color RgbColor
function TwinFangs:SetVenomRosterBarColor(color)
    local next = Color.Normalize(color)
    assert(next ~= nil, "Bad venom roster bar color")
    local saved = self.db.venomRoster.barColor
    if type(saved) ~= "table" then
        self.db.venomRoster.barColor = { r = next.r, g = next.g, b = next.b }
        NotifyVenomRosterAppearance()
        return
    end
    if Color.Equal(saved, next) then
        return
    end
    Color.Copy(saved, next)
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterBackgroundOpacity()
    return self.db.venomRoster.backgroundOpacity
end

---@param opacity number
function TwinFangs:SetVenomRosterBackgroundOpacity(opacity)
    opacity = Util.Snap(
        opacity,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_MIN,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_MAX,
        Schema.VENOM_ROSTER_BACKGROUND_OPACITY_STEP
    )
    if self.db.venomRoster.backgroundOpacity == opacity then
        return
    end
    self.db.venomRoster.backgroundOpacity = opacity
    NotifyVenomRosterAppearance()
end

---@return number
function TwinFangs:GetVenomRosterBarOpacity()
    return self.db.venomRoster.barOpacity
end

---@param opacity number
function TwinFangs:SetVenomRosterBarOpacity(opacity)
    opacity = Util.Snap(
        opacity,
        Schema.VENOM_ROSTER_BAR_OPACITY_MIN,
        Schema.VENOM_ROSTER_BAR_OPACITY_MAX,
        Schema.VENOM_ROSTER_BAR_OPACITY_STEP
    )
    if self.db.venomRoster.barOpacity == opacity then
        return
    end
    self.db.venomRoster.barOpacity = opacity
    NotifyVenomRosterAppearance()
end

function TwinFangs:ResetVenomRosterAppearance()
    local defaults = Schema.NewVenomRoster()
    local saved = self.db.venomRoster
    saved.columns = defaults.columns
    saved.rowHeight = defaults.rowHeight
    saved.rowGap = defaults.rowGap
    saved.columnGap = defaults.columnGap
    saved.nameColumnWidth = defaults.nameColumnWidth
    saved.nameFontSize = defaults.nameFontSize
    saved.stackFontSize = defaults.stackFontSize
    saved.barTexture = defaults.barTexture
    saved.backgroundOpacity = defaults.backgroundOpacity
    saved.barOpacity = defaults.barOpacity
    if type(saved.barColor) ~= "table" then
        saved.barColor = defaults.barColor
    else
        Color.Copy(saved.barColor, defaults.barColor)
    end
    if type(saved.numberColor) ~= "table" then
        saved.numberColor = defaults.numberColor
    else
        Color.Copy(saved.numberColor, defaults.numberColor)
    end
    NotifyVenomRosterAppearance()
end

---@return FloatingWindowPosition
function TwinFangs:GetVenomRosterPosition()
    return self.db.venomRosterPosition
end

---@param position FloatingWindowPosition
function TwinFangs:SetVenomRosterPosition(position)
    assert(ns.Position.IsValid(position), "Bad venom roster position")
    local saved = self.db.venomRosterPosition
    if type(saved) ~= "table" then
        self.db.venomRosterPosition = {
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
    if type(self.db.soakReminder.timeline) ~= "boolean" then
        self.db.soakReminder.timeline = true
    end
    self.db.statusHudPosition = nil
    self.db.interruptStatusHudPosition = nil
    if not ns.Position.IsValid(self.db.soakTimelinePosition) then
        self.db.soakTimelinePosition = Schema.DefaultSoakTimelinePosition()
    end
    if not ns.Position.IsValid(self.db.venomRosterPosition) then
        self.db.venomRosterPosition = Schema.DefaultVenomRosterPosition()
    end
    if type(self.db.venomRoster) ~= "table" then
        self.db.venomRoster = Schema.NewVenomRoster()
    else
        SanitizeVenomRoster(self.db.venomRoster)
    end
    SanitizeNameplateHint(self.db.nameplateHint)
    local reminder = self.db.interruptReminder
    if type(reminder) ~= "table" then
        reminder = { enabled = false, chain = Schema.NewInterruptChain() }
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

---Drops a pending or visible soak reminder. Defined with the encounter listener.
function TwinFangs:CancelSoakCallout() end

---Shows the triple-hit soak timeline from Feast begin-cast. Defined by the timeline UI.
function TwinFangs:StartSoakTimeline() end

---Hides the live triple-hit soak timeline. Defined by the timeline UI.
function TwinFangs:StopSoakTimeline() end

---Shows a soak or interrupt callout through CalloutManager. Defined with the encounter listener.
function TwinFangs:ShowCallout() end

---Clears this source's callout, or only one kind when `kind` is set. Defined with the encounter listener.
function TwinFangs:CancelCallout() end

---Starts the Brood interrupt-status window. Defined by InterruptStatus.lua.
function TwinFangs:BeginInterruptStatusWindow() end

---Hides the interrupt-status window and resets the counts. Defined by InterruptStatus.lua.
function TwinFangs:EndInterruptStatusWindow() end

---Counts configured-channel reports during a Brood window. Defined by InterruptStatus.lua.
function TwinFangs:ListenForInterruptStatus() end

---Panel test mode for the interrupt rotation tracker. Defined by InterruptStatus.lua.
function TwinFangs:SetInterruptStatusTestMode() end

---Whether the interrupt rotation tracker is in panel test mode. Defined by InterruptStatus.lua.
function TwinFangs:IsInterruptStatusTestMode() end

---Prewarms Venom Roster frames in Pit of Fangs when the feature is on. Defined by the roster UI.
function TwinFangs:PrepareVenomRoster() end

---Activates or deactivates live Venom Roster monitoring. Defined by the roster UI.
function TwinFangs:SetVenomRosterEncounterActive() end

---Drops live nameplate badges. Defined with the hint listener.
function TwinFangs:ClearNameplateHints() end

---Reattaches live badges after a preview ends. Defined with the hint listener.
function TwinFangs:ReplayNameplateHints() end

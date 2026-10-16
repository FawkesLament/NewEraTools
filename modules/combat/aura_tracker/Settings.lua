local _, ns = ...
local Color = ns.Color
local Position = ns.Position
local Util = ns.Util
local Media = ns.AuraTrackerMedia
local Activation = ns.AuraTrackerActivation
local Schema = ns.AuraTrackerSchema

local AuraTracker = ns.Modules.Get("AuraTracker")

local Settings = {}
ns.AuraTrackerSettings = Settings

-- Field writes notify through the same module callbacks the policy file uses.
---@param trackerId integer|nil
local function NotifyTrackerChanged(trackerId)
    if AuraTracker.OnTrackerChanged then
        AuraTracker:OnTrackerChanged(trackerId)
    end
end

---@param trackerId integer
local function NotifyAppearanceChanged(trackerId)
    if AuraTracker.OnAppearanceChanged then
        AuraTracker:OnAppearanceChanged(trackerId)
    end
end

---@param spellId any
---@return integer|nil
local function NormalizeSpellId(spellId)
    if type(spellId) ~= "number" then
        return nil
    end
    local id = math.floor(spellId)
    if id < 0 or id ~= spellId then
        return nil
    end
    return id
end

---@param unit any
---@return string
local function NormalizeUnit(unit)
    if Schema.UNITS[unit] then
        return unit
    end
    return Schema.UNIT_PLAYER
end

---@param auraType any
---@return string
local function NormalizeAuraType(auraType)
    if Schema.AURA_TYPES[auraType] then
        return auraType
    end
    return Schema.AURA_HELPFUL
end

---@param mode any
---@return string
local function NormalizeProgressMode(mode)
    if mode == Schema.PROGRESS_MODE_STACKS then
        return Schema.PROGRESS_MODE_STACKS
    end
    return Schema.PROGRESS_MODE_DURATION
end

---@param kind any
---@return string
local function RequireTextKind(kind)
    assert(Schema.TEXT_KINDS[kind], "Bad text display kind: " .. tostring(kind))
    return kind
end

---@param tracker AuraTrackerInstance
---@param kind string
---@return AuraTrackerTextDisplay
local function RequireTextDisplay(tracker, kind)
    kind = RequireTextKind(kind)
    local displays = tracker.textDisplays
    if type(displays) ~= "table" then
        displays = {}
        tracker.textDisplays = displays
    end
    local display = displays[kind]
    if type(display) ~= "table" then
        display = {}
        displays[kind] = display
    end
    return display
end

---@param trackers AuraTrackerInstance[]
---@param trackerId integer
---@return AuraTrackerInstance|nil
---@return integer|nil
local function FindTracker(trackers, trackerId)
    for index, tracker in ipairs(trackers) do
        if tracker.id == trackerId then
            return tracker, index
        end
    end
    return nil
end

---@param self AuraTracker
---@param trackerId integer
---@return AuraTrackerInstance
local function RequireTracker(self, trackerId)
    local tracker = FindTracker(self.db.trackers, trackerId)
    assert(tracker ~= nil, "Unknown tracker: " .. tostring(trackerId))
    return tracker
end

---@param tracker AuraTrackerInstance
---@param field string
---@param color any
---@param fallback AuraTrackerColor
local function EnsureColorField(tracker, field, color, fallback)
    local normalized = Color.Normalize(color) or fallback
    if type(tracker[field]) ~= "table" then
        tracker[field] = { r = normalized.r, g = normalized.g, b = normalized.b }
    else
        Color.Copy(tracker[field], normalized)
    end
end

---Repairs one saved tracker. Add, duplicate, and OnInit call this.
---@param tracker AuraTrackerInstance
function Settings.Normalize(tracker)
    local defaults = Schema.NewTracker()
    Util.ApplyDefaults(tracker, defaults)

    tracker.enabled = tracker.enabled == true
    tracker.spellId = NormalizeSpellId(tracker.spellId) or 0
    tracker.unit = NormalizeUnit(tracker.unit)
    tracker.auraType = NormalizeAuraType(tracker.auraType)
    Activation.Normalize(tracker)
    tracker.progressMode = NormalizeProgressMode(tracker.progressMode)
    tracker.maxStacks = Util.Snap(
        tracker.maxStacks or defaults.maxStacks,
        Schema.MAX_STACKS_MIN,
        Schema.MAX_STACKS_MAX,
        Schema.MAX_STACKS_STEP
    )
    tracker.width = Util.Snap(tracker.width or defaults.width, Schema.WIDTH_MIN, Schema.WIDTH_MAX, Schema.WIDTH_STEP)
    tracker.height =
        Util.Snap(tracker.height or defaults.height, Schema.HEIGHT_MIN, Schema.HEIGHT_MAX, Schema.HEIGHT_STEP)
    EnsureColorField(tracker, "fillColor", tracker.fillColor, defaults.fillColor)
    EnsureColorField(tracker, "backgroundColor", tracker.backgroundColor, defaults.backgroundColor)
    if type(tracker.texture) ~= "string" or tracker.texture == "" then
        tracker.texture = Schema.DEFAULT_TEXTURE
    end
    tracker.backgroundOpacity =
        Util.Snap(tracker.backgroundOpacity or 1, Schema.OPACITY_MIN, Schema.OPACITY_MAX, Schema.OPACITY_STEP)
    tracker.reverseFill = tracker.reverseFill == true
    tracker.vertical = tracker.vertical == true
    tracker.showBorder = tracker.showBorder == true
    EnsureColorField(tracker, "lineColor", tracker.lineColor, defaults.lineColor)
    tracker.lineThickness = Util.Snap(
        tracker.lineThickness or defaults.lineThickness,
        Schema.LINE_THICKNESS_MIN,
        Schema.LINE_THICKNESS_MAX,
        Schema.LINE_THICKNESS_STEP
    )
    tracker.showStackDividers = tracker.showStackDividers == true
    for kind, kindDefaults in pairs(defaults.textDisplays) do
        local display = RequireTextDisplay(tracker, kind)
        display.enabled = display.enabled == true
        if type(display.font) ~= "string" or display.font == "" then
            display.font = kindDefaults.font
        end
        display.fontSize = Util.Snap(
            display.fontSize or kindDefaults.fontSize,
            Schema.FONT_SIZE_MIN,
            Schema.FONT_SIZE_MAX,
            Schema.FONT_SIZE_STEP
        )
        display.offsetX = Util.Snap(
            display.offsetX or kindDefaults.offsetX,
            Schema.TEXT_OFFSET_MIN,
            Schema.TEXT_OFFSET_MAX,
            Schema.TEXT_OFFSET_STEP
        )
        display.offsetY = Util.Snap(
            display.offsetY or kindDefaults.offsetY,
            Schema.TEXT_OFFSET_MIN,
            Schema.TEXT_OFFSET_MAX,
            Schema.TEXT_OFFSET_STEP
        )
    end
    if not Position.IsValid(tracker.position) then
        tracker.position = {
            point = defaults.position.point,
            relativePoint = defaults.position.relativePoint,
            x = defaults.position.x,
            y = defaults.position.y,
        }
    end
end

---Numeric appearance field: get snaps the stored value.
---@param self AuraTracker
---@param trackerId integer
---@param field string
---@param fallback number
---@param min number
---@param max number
---@param step number
---@return number
local function GetSnapped(self, trackerId, field, fallback, min, max, step)
    return Util.Snap(RequireTracker(self, trackerId)[field] or fallback, min, max, step)
end

---Numeric appearance field: set snaps, no-ops when unchanged, notifies appearance.
---@param self AuraTracker
---@param trackerId integer
---@param field string
---@param value number
---@param min number
---@param max number
---@param step number
---@param badMessage string
local function SetSnapped(self, trackerId, field, value, min, max, step, badMessage)
    assert(type(value) == "number", badMessage)
    local tracker = RequireTracker(self, trackerId)
    local next = Util.Snap(value, min, max, step)
    if tracker[field] == next then
        return
    end
    tracker[field] = next
    NotifyAppearanceChanged(trackerId)
end

---Boolean appearance field.
---@param self AuraTracker
---@param trackerId integer
---@param field string
---@param value boolean
local function SetFlag(self, trackerId, field, value)
    local tracker = RequireTracker(self, trackerId)
    value = value == true
    if tracker[field] == value then
        return
    end
    tracker[field] = value
    NotifyAppearanceChanged(trackerId)
end

---@param self AuraTracker
---@param trackerId integer
---@param field string
---@param color any
---@param badMessage string
local function SetColorField(self, trackerId, field, color, badMessage)
    local next = Color.Normalize(color)
    assert(next ~= nil, badMessage)
    local tracker = RequireTracker(self, trackerId)
    local saved = tracker[field]
    if type(saved) ~= "table" then
        tracker[field] = { r = next.r, g = next.g, b = next.b }
        NotifyAppearanceChanged(trackerId)
        return
    end
    if Color.Equal(saved, next) then
        return
    end
    Color.Copy(saved, next)
    NotifyAppearanceChanged(trackerId)
end

---Fields the live bar paints in one appearance pass. Spell, unit, and activation are not included:
---those retarget an existing slot during combat instead of waiting on this snapshot.
---@param trackerId integer
---@return table
function AuraTracker:CaptureDeferredAppearance(trackerId)
    local fill = self:GetFillColor(trackerId)
    local background = self:GetBackgroundColor(trackerId)
    local line = self:GetLineColor(trackerId)
    local textDisplays = {}
    for _, kind in ipairs({ Schema.TEXT_DURATION, Schema.TEXT_STACKS }) do
        textDisplays[kind] = {
            enabled = self:IsTextDisplayEnabled(trackerId, kind),
            font = self:GetTextDisplayFont(trackerId, kind),
            fontSize = self:GetTextDisplayFontSize(trackerId, kind),
            offsetX = self:GetTextDisplayOffsetX(trackerId, kind),
            offsetY = self:GetTextDisplayOffsetY(trackerId, kind),
        }
    end
    return {
        width = self:GetWidth(trackerId),
        height = self:GetHeight(trackerId),
        vertical = self:GetVertical(trackerId),
        fillColor = { r = fill.r, g = fill.g, b = fill.b },
        texture = self:GetTexture(trackerId),
        backgroundColor = { r = background.r, g = background.g, b = background.b },
        backgroundOpacity = self:GetBackgroundOpacity(trackerId),
        reverseFill = self:GetReverseFill(trackerId),
        showBorder = self:GetShowBorder(trackerId),
        lineColor = { r = line.r, g = line.g, b = line.b },
        lineThickness = self:GetLineThickness(trackerId),
        showStackDividers = self:GetShowStackDividers(trackerId),
        progressMode = self:GetProgressMode(trackerId),
        maxStacks = self:GetMaxStacks(trackerId),
        textDisplays = textDisplays,
    }
end

---Keys whose saved values differ from the last successful live paint. Empty when nothing is waiting.
---@param applied table|nil
---@param current table|nil
---@return table<string, boolean>
function AuraTracker.DiffDeferredAppearance(applied, current)
    local pending = {}
    if type(applied) ~= "table" or type(current) ~= "table" then
        return pending
    end
    local function Mark(key, differs)
        if differs then
            pending[key] = true
        end
    end
    Mark("width", applied.width ~= current.width)
    Mark("height", applied.height ~= current.height)
    Mark("vertical", applied.vertical ~= current.vertical)
    Mark("fillColor", not Color.Equal(applied.fillColor, current.fillColor))
    Mark("texture", applied.texture ~= current.texture)
    Mark("backgroundColor", not Color.Equal(applied.backgroundColor, current.backgroundColor))
    Mark("backgroundOpacity", applied.backgroundOpacity ~= current.backgroundOpacity)
    Mark("reverseFill", applied.reverseFill ~= current.reverseFill)
    Mark("showBorder", applied.showBorder ~= current.showBorder)
    Mark("lineColor", not Color.Equal(applied.lineColor, current.lineColor))
    Mark("lineThickness", applied.lineThickness ~= current.lineThickness)
    Mark("showStackDividers", applied.showStackDividers ~= current.showStackDividers)
    Mark("progressMode", applied.progressMode ~= current.progressMode)
    Mark("maxStacks", applied.maxStacks ~= current.maxStacks)
    for _, kind in ipairs({ Schema.TEXT_DURATION, Schema.TEXT_STACKS }) do
        local previous = applied.textDisplays and applied.textDisplays[kind]
        local saved = current.textDisplays and current.textDisplays[kind]
        local prefix = "text." .. kind .. "."
        if type(previous) ~= "table" or type(saved) ~= "table" then
            Mark(prefix .. "enabled", true)
        else
            Mark(prefix .. "enabled", previous.enabled ~= saved.enabled)
            Mark(prefix .. "font", previous.font ~= saved.font)
            Mark(prefix .. "fontSize", previous.fontSize ~= saved.fontSize)
            Mark(prefix .. "offsetX", previous.offsetX ~= saved.offsetX)
            Mark(prefix .. "offsetY", previous.offsetY ~= saved.offsetY)
        end
    end
    return pending
end

-- ---------------------------------------------------------------------------
-- Per-tracker spell / appearance / position
-- ---------------------------------------------------------------------------

---@param trackerId integer
---@return integer
function AuraTracker:GetSpellId(trackerId)
    return NormalizeSpellId(RequireTracker(self, trackerId).spellId) or 0
end

---Persists a non-negative spell ID. Tracker reconfiguration is handled by the UI.
---@param trackerId integer
---@param spellId integer
function AuraTracker:SetSpellId(trackerId, spellId)
    local tracker = RequireTracker(self, trackerId)
    local id = NormalizeSpellId(spellId)
    assert(id ~= nil, "Bad spell ID")
    if tracker.spellId == id then
        return
    end
    tracker.spellId = id
    NotifyTrackerChanged(trackerId)
end

---@param trackerId integer
---@return string
function AuraTracker:GetUnit(trackerId)
    return NormalizeUnit(RequireTracker(self, trackerId).unit)
end

---`player`, `target`, or `focus`. Independent of aura type; unsupported pairs do not display.
---@param trackerId integer
---@param unit string
function AuraTracker:SetUnit(trackerId, unit)
    assert(Schema.UNITS[unit] == true, "Bad aura unit")
    local tracker = RequireTracker(self, trackerId)
    if tracker.unit == unit then
        return
    end
    tracker.unit = unit
    NotifyTrackerChanged(trackerId)
end

---Writes unit and aura type, then notifies once.
---Separate setters would refresh on the intermediate pair (for example target + helpful), which
---is not a supported source and hides the bar before the real pair is stored.
---@param trackerId integer
---@param unit string
---@param auraType string
function AuraTracker:SetSource(trackerId, unit, auraType)
    assert(Schema.UNITS[unit] == true, "Bad aura unit")
    assert(Schema.AURA_TYPES[auraType] == true, "Bad aura type")
    local tracker = RequireTracker(self, trackerId)
    if tracker.unit == unit and tracker.auraType == auraType then
        return
    end
    tracker.unit = unit
    tracker.auraType = auraType
    NotifyTrackerChanged(trackerId)
end

---@param trackerId integer
---@return string
function AuraTracker:GetAuraType(trackerId)
    return NormalizeAuraType(RequireTracker(self, trackerId).auraType)
end

---`HELPFUL` or `HARMFUL`. Independent of unit; unsupported pairs do not display.
---@param trackerId integer
---@param auraType string
function AuraTracker:SetAuraType(trackerId, auraType)
    assert(Schema.AURA_TYPES[auraType] == true, "Bad aura type")
    local tracker = RequireTracker(self, trackerId)
    if tracker.auraType == auraType then
        return
    end
    tracker.auraType = auraType
    NotifyTrackerChanged(trackerId)
end

---@param trackerId integer
---@return string scope
---@return integer|string|nil target
function AuraTracker:GetActivationScope(trackerId)
    local tracker = RequireTracker(self, trackerId)
    return tracker.activationScope, tracker.activationTarget
end

---Stores a concrete scope target (spec ID / class file / role). Never stores "current" sentinels.
---@param trackerId integer
---@param scope string
---@param target integer|string|nil
function AuraTracker:SetActivationScope(trackerId, scope, target)
    local normalizedScope, normalizedTarget = Activation.Require(scope, target)
    local tracker = RequireTracker(self, trackerId)
    if tracker.activationScope == normalizedScope and tracker.activationTarget == normalizedTarget then
        return
    end
    tracker.activationScope = normalizedScope
    tracker.activationTarget = normalizedTarget
    NotifyTrackerChanged(trackerId)
end

---`duration` (SetDurationBar) or `stacks` (SetApplicationBar). Controls progress fill only.
---@param trackerId integer
---@return string
function AuraTracker:GetProgressMode(trackerId)
    return NormalizeProgressMode(RequireTracker(self, trackerId).progressMode)
end

---@param trackerId integer
---@return boolean
function AuraTracker:IsStacksMode(trackerId)
    return self:GetProgressMode(trackerId) == Schema.PROGRESS_MODE_STACKS
end

---Switches native progress-bar binding; appearance-only notify so combat can defer safely.
---@param trackerId integer
---@param mode string
function AuraTracker:SetProgressMode(trackerId, mode)
    assert(mode == Schema.PROGRESS_MODE_DURATION or mode == Schema.PROGRESS_MODE_STACKS, "Bad progress mode")
    local tracker = RequireTracker(self, trackerId)
    local next = NormalizeProgressMode(mode)
    if tracker.progressMode == next then
        return
    end
    tracker.progressMode = next
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@return integer
function AuraTracker:GetMaxStacks(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "maxStacks",
        Schema.DEFAULT_MAX_STACKS,
        Schema.MAX_STACKS_MIN,
        Schema.MAX_STACKS_MAX,
        Schema.MAX_STACKS_STEP
    )
end

---Upper scale for stacks-mode SetApplicationBar (`maxApplications`).
---@param trackerId integer
---@param maxStacks integer
function AuraTracker:SetMaxStacks(trackerId, maxStacks)
    SetSnapped(
        self,
        trackerId,
        "maxStacks",
        maxStacks,
        Schema.MAX_STACKS_MIN,
        Schema.MAX_STACKS_MAX,
        Schema.MAX_STACKS_STEP,
        "Bad max stacks"
    )
end

---@param trackerId integer
---@return number
function AuraTracker:GetWidth(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "width",
        Schema.DEFAULT_BAR_WIDTH,
        Schema.WIDTH_MIN,
        Schema.WIDTH_MAX,
        Schema.WIDTH_STEP
    )
end

---@param trackerId integer
---@param width number
function AuraTracker:SetWidth(trackerId, width)
    SetSnapped(self, trackerId, "width", width, Schema.WIDTH_MIN, Schema.WIDTH_MAX, Schema.WIDTH_STEP, "Bad width")
end

---@param trackerId integer
---@return number
function AuraTracker:GetHeight(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "height",
        Schema.DEFAULT_BAR_HEIGHT,
        Schema.HEIGHT_MIN,
        Schema.HEIGHT_MAX,
        Schema.HEIGHT_STEP
    )
end

---@param trackerId integer
---@param height number
function AuraTracker:SetHeight(trackerId, height)
    SetSnapped(
        self,
        trackerId,
        "height",
        height,
        Schema.HEIGHT_MIN,
        Schema.HEIGHT_MAX,
        Schema.HEIGHT_STEP,
        "Bad height"
    )
end

---@param trackerId integer
---@return AuraTrackerColor
function AuraTracker:GetFillColor(trackerId)
    return Color.Normalize(RequireTracker(self, trackerId).fillColor)
        or {
            r = Schema.DEFAULT_FILL.r,
            g = Schema.DEFAULT_FILL.g,
            b = Schema.DEFAULT_FILL.b,
        }
end

---@param trackerId integer
---@param color AuraTrackerColor
function AuraTracker:SetFillColor(trackerId, color)
    SetColorField(self, trackerId, "fillColor", color, "Bad fill color")
end

---Stable texture id (built-in or LSM statusbar handle). Falls back when the saved id is unavailable.
---@param trackerId integer
---@return string
function AuraTracker:GetTexture(trackerId)
    local textureId = RequireTracker(self, trackerId).texture
    return Media.IsKnownTexture(textureId) and textureId or Schema.DEFAULT_TEXTURE
end

---File path for the selected fill texture; independent of fill color tinting.
---@param trackerId integer
---@return string
function AuraTracker:GetTexturePath(trackerId)
    return Media.ResolveTexturePath(self:GetTexture(trackerId))
end

---@param trackerId integer
---@param textureId string
function AuraTracker:SetTexture(trackerId, textureId)
    assert(Media.IsKnownTexture(textureId), "Unknown texture: " .. tostring(textureId))
    local tracker = RequireTracker(self, trackerId)
    if tracker.texture == textureId then
        return
    end
    tracker.texture = textureId
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@return AuraTrackerColor
function AuraTracker:GetBackgroundColor(trackerId)
    return Color.Normalize(RequireTracker(self, trackerId).backgroundColor)
        or {
            r = Schema.DEFAULT_BACKGROUND.r,
            g = Schema.DEFAULT_BACKGROUND.g,
            b = Schema.DEFAULT_BACKGROUND.b,
        }
end

---@param trackerId integer
---@param color AuraTrackerColor
function AuraTracker:SetBackgroundColor(trackerId, color)
    SetColorField(self, trackerId, "backgroundColor", color, "Bad background color")
end

---@param trackerId integer
---@return number
function AuraTracker:GetBackgroundOpacity(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "backgroundOpacity",
        1,
        Schema.OPACITY_MIN,
        Schema.OPACITY_MAX,
        Schema.OPACITY_STEP
    )
end

---@param trackerId integer
---@param opacity number
function AuraTracker:SetBackgroundOpacity(trackerId, opacity)
    SetSnapped(
        self,
        trackerId,
        "backgroundOpacity",
        opacity,
        Schema.OPACITY_MIN,
        Schema.OPACITY_MAX,
        Schema.OPACITY_STEP,
        "Bad background opacity"
    )
end

---@param trackerId integer
---@return boolean
function AuraTracker:GetReverseFill(trackerId)
    return RequireTracker(self, trackerId).reverseFill == true
end

---@param trackerId integer
---@param reverse boolean
function AuraTracker:SetReverseFill(trackerId, reverse)
    SetFlag(self, trackerId, "reverseFill", reverse)
end

---@param trackerId integer
---@return boolean
function AuraTracker:GetVertical(trackerId)
    return RequireTracker(self, trackerId).vertical == true
end

---@param trackerId integer
---@param vertical boolean
function AuraTracker:SetVertical(trackerId, vertical)
    SetFlag(self, trackerId, "vertical", vertical)
end

---@param trackerId integer
---@return boolean
function AuraTracker:GetShowBorder(trackerId)
    return RequireTracker(self, trackerId).showBorder == true
end

---@param trackerId integer
---@param show boolean
function AuraTracker:SetShowBorder(trackerId, show)
    SetFlag(self, trackerId, "showBorder", show)
end

---Shared border / stack-divider color.
---@param trackerId integer
---@return AuraTrackerColor
function AuraTracker:GetLineColor(trackerId)
    return Color.Normalize(RequireTracker(self, trackerId).lineColor)
        or {
            r = Schema.DEFAULT_LINE.r,
            g = Schema.DEFAULT_LINE.g,
            b = Schema.DEFAULT_LINE.b,
        }
end

---@param trackerId integer
---@param color AuraTrackerColor
function AuraTracker:SetLineColor(trackerId, color)
    SetColorField(self, trackerId, "lineColor", color, "Bad line color")
end

---Shared border / stack-divider thickness in pixels.
---@param trackerId integer
---@return number
function AuraTracker:GetLineThickness(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "lineThickness",
        Schema.DEFAULT_LINE_THICKNESS,
        Schema.LINE_THICKNESS_MIN,
        Schema.LINE_THICKNESS_MAX,
        Schema.LINE_THICKNESS_STEP
    )
end

---@param trackerId integer
---@param thickness number
function AuraTracker:SetLineThickness(trackerId, thickness)
    SetSnapped(
        self,
        trackerId,
        "lineThickness",
        thickness,
        Schema.LINE_THICKNESS_MIN,
        Schema.LINE_THICKNESS_MAX,
        Schema.LINE_THICKNESS_STEP,
        "Bad line thickness"
    )
end

---@param trackerId integer
---@return boolean
function AuraTracker:GetShowStackDividers(trackerId)
    return RequireTracker(self, trackerId).showStackDividers == true
end

---@param trackerId integer
---@param show boolean
function AuraTracker:SetShowStackDividers(trackerId, show)
    SetFlag(self, trackerId, "showStackDividers", show)
end

---@param trackerId integer
---@param kind string
---@return boolean
function AuraTracker:IsTextDisplayEnabled(trackerId, kind)
    return RequireTextDisplay(RequireTracker(self, trackerId), kind).enabled == true
end

---@param trackerId integer
---@param kind string
---@param enabled boolean
function AuraTracker:SetTextDisplayEnabled(trackerId, kind, enabled)
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    enabled = enabled == true
    if display.enabled == enabled then
        return
    end
    display.enabled = enabled
    NotifyAppearanceChanged(trackerId)
end

---Stable font id (`default` or an LSM font handle). Falls back when the saved id is unavailable.
---@param trackerId integer
---@param kind string
---@return string
function AuraTracker:GetTextDisplayFont(trackerId, kind)
    local fontId = RequireTextDisplay(RequireTracker(self, trackerId), kind).font
    return Media.IsKnownFont(fontId) and fontId or Schema.TEXT_FONT_DEFAULT
end

---File path for the selected text font, or nil to use the game's locale font in UI code.
---@param trackerId integer
---@param kind string
---@return string|nil
function AuraTracker:GetTextDisplayFontPath(trackerId, kind)
    return Media.ResolveFontPath(self:GetTextDisplayFont(trackerId, kind))
end

---@param trackerId integer
---@param kind string
---@param fontId string
function AuraTracker:SetTextDisplayFont(trackerId, kind, fontId)
    assert(Media.IsKnownFont(fontId), "Unknown font: " .. tostring(fontId))
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    if display.font == fontId then
        return
    end
    display.font = fontId
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@param kind string
---@return number
function AuraTracker:GetTextDisplayFontSize(trackerId, kind)
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    return Util.Snap(
        display.fontSize or Schema.DEFAULT_FONT_SIZE,
        Schema.FONT_SIZE_MIN,
        Schema.FONT_SIZE_MAX,
        Schema.FONT_SIZE_STEP
    )
end

---@param trackerId integer
---@param kind string
---@param size number
function AuraTracker:SetTextDisplayFontSize(trackerId, kind, size)
    assert(type(size) == "number", "Bad font size")
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    local next = Util.Snap(size, Schema.FONT_SIZE_MIN, Schema.FONT_SIZE_MAX, Schema.FONT_SIZE_STEP)
    if display.fontSize == next then
        return
    end
    display.fontSize = next
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@param kind string
---@param field "offsetX"|"offsetY"
---@param fallback number
---@return number
local function GetTextOffset(self, trackerId, kind, field, fallback)
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    return Util.Snap(
        display[field] or fallback,
        Schema.TEXT_OFFSET_MIN,
        Schema.TEXT_OFFSET_MAX,
        Schema.TEXT_OFFSET_STEP
    )
end

---@param trackerId integer
---@param kind string
---@param field "offsetX"|"offsetY"
---@param value number
local function SetTextOffset(self, trackerId, kind, field, value)
    assert(type(value) == "number", "Bad text offset")
    local display = RequireTextDisplay(RequireTracker(self, trackerId), kind)
    local next = Util.Snap(value, Schema.TEXT_OFFSET_MIN, Schema.TEXT_OFFSET_MAX, Schema.TEXT_OFFSET_STEP)
    if display[field] == next then
        return
    end
    display[field] = next
    NotifyAppearanceChanged(trackerId)
end

---Horizontal offset from the bar center. Positive moves right.
---@param trackerId integer
---@param kind string
---@return number
function AuraTracker:GetTextDisplayOffsetX(trackerId, kind)
    local defaults = Schema.NewTracker().textDisplays[RequireTextKind(kind)]
    return GetTextOffset(self, trackerId, kind, "offsetX", defaults.offsetX)
end

---@param trackerId integer
---@param kind string
---@param offset number
function AuraTracker:SetTextDisplayOffsetX(trackerId, kind, offset)
    SetTextOffset(self, trackerId, kind, "offsetX", offset)
end

---Vertical offset from the bar center. Positive moves up.
---@param trackerId integer
---@param kind string
---@return number
function AuraTracker:GetTextDisplayOffsetY(trackerId, kind)
    local defaults = Schema.NewTracker().textDisplays[RequireTextKind(kind)]
    return GetTextOffset(self, trackerId, kind, "offsetY", defaults.offsetY)
end

---@param trackerId integer
---@param kind string
---@param offset number
function AuraTracker:SetTextDisplayOffsetY(trackerId, kind, offset)
    SetTextOffset(self, trackerId, kind, "offsetY", offset)
end

---@param trackerId integer
---@return AuraTrackerPosition
function AuraTracker:GetPosition(trackerId)
    return RequireTracker(self, trackerId).position
end

---@param trackerId integer
---@param position AuraTrackerPosition
function AuraTracker:SetPosition(trackerId, position)
    assert(Position.IsValid(position), "Bad bar position")
    local saved = RequireTracker(self, trackerId).position
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---Applies a partial settings table to one tracker (enable, spell, appearance, position).
---@param trackerId integer
---@param settings table
function AuraTracker:UpdateTracker(trackerId, settings)
    assert(type(settings) == "table", "Bad tracker settings")
    RequireTracker(self, trackerId)

    if settings.enabled ~= nil then
        self:SetTrackerEnabled(trackerId, settings.enabled)
    end
    if settings.spellId ~= nil then
        self:SetSpellId(trackerId, settings.spellId)
    end
    if settings.unit ~= nil or settings.auraType ~= nil then
        local tracker = RequireTracker(self, trackerId)
        local unit = settings.unit ~= nil and settings.unit or tracker.unit
        local auraType = settings.auraType ~= nil and settings.auraType or tracker.auraType
        self:SetSource(trackerId, unit, auraType)
    end
    if settings.activationScope ~= nil or settings.activationTarget ~= nil then
        local tracker = RequireTracker(self, trackerId)
        local scope = settings.activationScope
        if scope == nil then
            scope = tracker.activationScope
        end
        local target = settings.activationTarget
        if target == nil and settings.activationScope == nil then
            target = tracker.activationTarget
        end
        self:SetActivationScope(trackerId, scope, target)
    end
    if settings.progressMode ~= nil then
        self:SetProgressMode(trackerId, settings.progressMode)
    end
    if settings.maxStacks ~= nil then
        self:SetMaxStacks(trackerId, settings.maxStacks)
    end
    if settings.width ~= nil then
        self:SetWidth(trackerId, settings.width)
    end
    if settings.height ~= nil then
        self:SetHeight(trackerId, settings.height)
    end
    if settings.fillColor ~= nil then
        self:SetFillColor(trackerId, settings.fillColor)
    end
    if settings.backgroundColor ~= nil then
        self:SetBackgroundColor(trackerId, settings.backgroundColor)
    end
    if settings.texture ~= nil then
        self:SetTexture(trackerId, settings.texture)
    end
    if settings.backgroundOpacity ~= nil then
        self:SetBackgroundOpacity(trackerId, settings.backgroundOpacity)
    end
    if settings.reverseFill ~= nil then
        self:SetReverseFill(trackerId, settings.reverseFill)
    end
    if settings.vertical ~= nil then
        self:SetVertical(trackerId, settings.vertical)
    end
    if settings.showBorder ~= nil then
        self:SetShowBorder(trackerId, settings.showBorder)
    end
    if settings.lineColor ~= nil then
        self:SetLineColor(trackerId, settings.lineColor)
    end
    if settings.lineThickness ~= nil then
        self:SetLineThickness(trackerId, settings.lineThickness)
    end
    if settings.showStackDividers ~= nil then
        self:SetShowStackDividers(trackerId, settings.showStackDividers)
    end
    if type(settings.textDisplays) == "table" then
        for kind, displaySettings in pairs(settings.textDisplays) do
            if Schema.TEXT_KINDS[kind] and type(displaySettings) == "table" then
                if displaySettings.enabled ~= nil then
                    self:SetTextDisplayEnabled(trackerId, kind, displaySettings.enabled)
                end
                if displaySettings.font ~= nil then
                    self:SetTextDisplayFont(trackerId, kind, displaySettings.font)
                end
                if displaySettings.fontSize ~= nil then
                    self:SetTextDisplayFontSize(trackerId, kind, displaySettings.fontSize)
                end
                if displaySettings.offsetX ~= nil then
                    self:SetTextDisplayOffsetX(trackerId, kind, displaySettings.offsetX)
                end
                if displaySettings.offsetY ~= nil then
                    self:SetTextDisplayOffsetY(trackerId, kind, displaySettings.offsetY)
                end
            end
        end
    end
    if settings.position ~= nil then
        self:SetPosition(trackerId, settings.position)
    end
end

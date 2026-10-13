local _, ns = ...
local Activity = ns.Api.Activity
local Combat = ns.Api.Combat
local Instance = ns.Api.Instance
local Player = ns.Api.Player
local Spell = ns.Api.Spell
local Timer = ns.Api.Timer
local Color = ns.Color
local Position = ns.Position
local Util = ns.Util
local Media = ns.AuraTrackerMedia
local L = ns.L

-- Match Assets.Colors.ACCENT / SURFACE / BORDER at the time the bar was first shipped.
local DEFAULT_FILL = { r = 0.310, g = 0.765, b = 0.710 }
local DEFAULT_BACKGROUND = { r = 0.102, g = 0.110, b = 0.133 }
local DEFAULT_LINE = { r = 0.180, g = 0.196, b = 0.231 }
local DEFAULT_TEXTURE = Media.DEFAULT_TEXTURE
local DEFAULT_TIME_FONT = Media.DEFAULT_TIME_FONT
local DEFAULT_TIME_POSITION = "right"
local TRACKING_MODE_DURATION = "duration"
local TRACKING_MODE_STACKS = "stacks"
local SCOPE_ALWAYS = "always"
local SCOPE_SPECIALIZATION = "specialization"
local SCOPE_CLASS = "class"
local SCOPE_ROLE = "role"
local SCOPE_ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local WIDTH_MIN = 40
local WIDTH_MAX = 400
local WIDTH_STEP = 1
local HEIGHT_MIN = 4
local HEIGHT_MAX = 64
local HEIGHT_STEP = 1
local OPACITY_MIN = 0
local OPACITY_MAX = 1
local OPACITY_STEP = 0.05
local FONT_SIZE_MIN = 8
local FONT_SIZE_MAX = 32
local FONT_SIZE_STEP = 1
local DEFAULT_FONT_SIZE = 12
local LINE_THICKNESS_MIN = 1
local LINE_THICKNESS_MAX = 4
local LINE_THICKNESS_STEP = 1
local DEFAULT_LINE_THICKNESS = 1
local MAX_STACKS_MIN = 1
local MAX_STACKS_MAX = 999
local MAX_STACKS_STEP = 1
local DEFAULT_MAX_STACKS = 10
local DEFAULT_POSITION_Y = -80
local POSITION_STACK_STEP = 24

local TIME_POSITION_HORIZONTAL = { left = true, center = true, right = true }
local TIME_POSITION_VERTICAL = { top = true, center = true, bottom = true }
-- When switching orientation, keep the analogous edge (left↔bottom, right↔top).
local TIME_POSITION_TO_VERTICAL = { left = "bottom", center = "center", right = "top" }
local TIME_POSITION_TO_HORIZONTAL = { top = "right", center = "center", bottom = "left" }

---@class AuraTrackerColor
---@field r number
---@field g number
---@field b number

---Where the tracker bar sits, as an anchor on the screen.
---@class AuraTrackerPosition
---@field point string  e.g. "CENTER".
---@field relativePoint string
---@field x number
---@field y number

---@class AuraTrackerInstance
---@field id integer  Stable tracker id; never reused after deletion.
---@field enabled boolean
---@field spellId integer
---@field activationScope string  `always`, `specialization`, `class`, or `role`.
---@field activationTarget integer|string|nil  Spec ID, class file, or role; nil for `always`.
---@field trackingMode string  `duration` or `stacks`.
---@field maxStacks integer  StatusBar scale for stacks mode (`current / maxStacks`).
---@field width number
---@field height number
---@field fillColor AuraTrackerColor
---@field backgroundColor AuraTrackerColor
---@field texture string
---@field backgroundOpacity number
---@field reverseFill boolean
---@field vertical boolean
---@field showBorder boolean
---@field lineColor AuraTrackerColor  Shared color for border and stack dividers.
---@field lineThickness number  Shared thickness for border and stack dividers.
---@field showStackDividers boolean  Stack-mode segment separators; ignored in duration mode.
---@field showTime boolean  Value display visibility (remaining time or stack count).
---@field timeFont string
---@field timeFontSize number
---@field timePosition string
---@field position AuraTrackerPosition

---@class AuraTracker: Module
---@field OnTrackerListChanged fun(self: AuraTracker)|nil  Add/remove; rebuild instance UIs.
---@field OnTrackerChanged fun(self: AuraTracker, trackerId: integer|nil)|nil  Enable/spell; nil = all.
---@field OnAppearanceChanged fun(self: AuraTracker, trackerId: integer)|nil  Appearance-only; no frame recreate.
local AuraTracker = ns.Modules.New("AuraTracker", {
    defaults = {
        enabled = false,
        -- Module-level auto-hide; independent of per-tracker enablement / activation scope.
        hideDuringSkyriding = true,
        hideDuringPetBattles = true,
        hideDuringCinematics = true,
        nextTrackerId = 1,
        ---@type AuraTrackerInstance[]
        trackers = {},
    },
})

AuraTracker.WIDTH_MIN = WIDTH_MIN
AuraTracker.WIDTH_MAX = WIDTH_MAX
AuraTracker.WIDTH_STEP = WIDTH_STEP
AuraTracker.HEIGHT_MIN = HEIGHT_MIN
AuraTracker.HEIGHT_MAX = HEIGHT_MAX
AuraTracker.HEIGHT_STEP = HEIGHT_STEP
AuraTracker.OPACITY_MIN = OPACITY_MIN
AuraTracker.OPACITY_MAX = OPACITY_MAX
AuraTracker.OPACITY_STEP = OPACITY_STEP
AuraTracker.FONT_SIZE_MIN = FONT_SIZE_MIN
AuraTracker.FONT_SIZE_MAX = FONT_SIZE_MAX
AuraTracker.FONT_SIZE_STEP = FONT_SIZE_STEP
AuraTracker.LINE_THICKNESS_MIN = LINE_THICKNESS_MIN
AuraTracker.LINE_THICKNESS_MAX = LINE_THICKNESS_MAX
AuraTracker.LINE_THICKNESS_STEP = LINE_THICKNESS_STEP
AuraTracker.MAX_STACKS_MIN = MAX_STACKS_MIN
AuraTracker.MAX_STACKS_MAX = MAX_STACKS_MAX
AuraTracker.MAX_STACKS_STEP = MAX_STACKS_STEP
AuraTracker.TRACKING_MODE_DURATION = TRACKING_MODE_DURATION
AuraTracker.TRACKING_MODE_STACKS = TRACKING_MODE_STACKS
AuraTracker.SCOPE_ALWAYS = SCOPE_ALWAYS
AuraTracker.SCOPE_SPECIALIZATION = SCOPE_SPECIALIZATION
AuraTracker.SCOPE_CLASS = SCOPE_CLASS
AuraTracker.SCOPE_ROLE = SCOPE_ROLE
AuraTracker.TIME_FONT_DEFAULT = DEFAULT_TIME_FONT

---Default scope for a newly created tracker: current specialization ID when available.
---@return string scope
---@return integer|string|nil target
local function DefaultActivationScope()
    local specializationId = Player.GetSpecializationId()
    if specializationId then
        return SCOPE_SPECIALIZATION, specializationId
    end
    local classFile = Player.GetClassFile()
    if classFile then
        return SCOPE_CLASS, classFile
    end
    return SCOPE_ALWAYS, nil
end

---@return AuraTrackerInstance
local function NewTrackerDefaults()
    -- activationScope / activationTarget are filled in NormalizeTracker so ApplyDefaults
    -- never copies a live specialization ID onto an `always` tracker with a nil target.
    return {
        enabled = true,
        spellId = 0,
        trackingMode = TRACKING_MODE_DURATION,
        maxStacks = DEFAULT_MAX_STACKS,
        width = 200,
        height = 18,
        fillColor = { r = DEFAULT_FILL.r, g = DEFAULT_FILL.g, b = DEFAULT_FILL.b },
        backgroundColor = { r = DEFAULT_BACKGROUND.r, g = DEFAULT_BACKGROUND.g, b = DEFAULT_BACKGROUND.b },
        texture = DEFAULT_TEXTURE,
        backgroundOpacity = 1,
        reverseFill = false,
        vertical = false,
        showBorder = false,
        lineColor = { r = DEFAULT_LINE.r, g = DEFAULT_LINE.g, b = DEFAULT_LINE.b },
        lineThickness = DEFAULT_LINE_THICKNESS,
        showStackDividers = true,
        showTime = true,
        timeFont = DEFAULT_TIME_FONT,
        timeFontSize = DEFAULT_FONT_SIZE,
        timePosition = DEFAULT_TIME_POSITION,
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = DEFAULT_POSITION_Y },
    }
end

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

local function NotifyTrackerListChanged()
    if AuraTracker.OnTrackerListChanged then
        AuraTracker:OnTrackerListChanged()
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

---@param position any
---@param vertical boolean
---@return string
local function NormalizeTimePosition(position, vertical)
    local allowed = vertical and TIME_POSITION_VERTICAL or TIME_POSITION_HORIZONTAL
    if type(position) == "string" and allowed[position] then
        return position
    end
    if type(position) == "string" then
        local mapped = vertical and TIME_POSITION_TO_VERTICAL[position] or TIME_POSITION_TO_HORIZONTAL[position]
        if mapped then
            return mapped
        end
    end
    return vertical and "top" or DEFAULT_TIME_POSITION
end

---@param mode any
---@return string
local function NormalizeTrackingMode(mode)
    if mode == TRACKING_MODE_STACKS then
        return TRACKING_MODE_STACKS
    end
    return TRACKING_MODE_DURATION
end

---@param scope any
---@return string|nil
local function NormalizeActivationScope(scope)
    if scope == SCOPE_ALWAYS or scope == SCOPE_SPECIALIZATION or scope == SCOPE_CLASS or scope == SCOPE_ROLE then
        return scope
    end
    return nil
end

---@param scope string
---@param target any
---@return integer|string|nil
local function NormalizeActivationTarget(scope, target)
    if scope == SCOPE_ALWAYS then
        return nil
    end
    if scope == SCOPE_SPECIALIZATION then
        if type(target) ~= "number" then
            return nil
        end
        local id = math.floor(target)
        if id < 1 or id ~= target then
            return nil
        end
        return id
    end
    if scope == SCOPE_CLASS then
        if type(target) == "string" and target ~= "" then
            return target
        end
        return nil
    end
    if scope == SCOPE_ROLE and SCOPE_ROLES[target] then
        return target
    end
    return nil
end

---Whether a tracker's saved activation scope applies to the given player context.
---Pure matching helper: does not read saved settings or the live player.
---@param tracker { activationScope: string|nil, activationTarget: integer|string|nil }
---@param context PlayerActivationContext
---@return boolean
function AuraTracker.AppliesToPlayer(tracker, context)
    local scope = NormalizeActivationScope(tracker.activationScope) or SCOPE_ALWAYS
    local target = NormalizeActivationTarget(scope, tracker.activationTarget)
    if scope == SCOPE_ALWAYS then
        return true
    end
    if not context then
        return false
    end
    if scope == SCOPE_SPECIALIZATION then
        return target ~= nil and context.specializationId == target
    end
    if scope == SCOPE_CLASS then
        return target ~= nil and context.classFile == target
    end
    if scope == SCOPE_ROLE then
        return target ~= nil and context.role == target
    end
    return false
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

---@param tracker AuraTrackerInstance
local function NormalizeTracker(tracker)
    local defaults = NewTrackerDefaults()
    Util.ApplyDefaults(tracker, defaults)

    tracker.enabled = tracker.enabled == true
    tracker.spellId = NormalizeSpellId(tracker.spellId) or 0
    local scope = NormalizeActivationScope(tracker.activationScope)
    if not scope then
        scope, tracker.activationTarget = DefaultActivationScope()
    end
    tracker.activationScope = scope
    tracker.activationTarget = NormalizeActivationTarget(scope, tracker.activationTarget)
    if scope == SCOPE_SPECIALIZATION and tracker.activationTarget == nil then
        tracker.activationTarget = Player.GetSpecializationId()
    elseif scope == SCOPE_CLASS and tracker.activationTarget == nil then
        tracker.activationTarget = Player.GetClassFile()
    end
    tracker.trackingMode = NormalizeTrackingMode(tracker.trackingMode)
    tracker.maxStacks = Util.Snap(
        tracker.maxStacks or defaults.maxStacks,
        MAX_STACKS_MIN,
        MAX_STACKS_MAX,
        MAX_STACKS_STEP
    )
    tracker.width = Util.Snap(tracker.width or defaults.width, WIDTH_MIN, WIDTH_MAX, WIDTH_STEP)
    tracker.height = Util.Snap(tracker.height or defaults.height, HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP)
    EnsureColorField(tracker, "fillColor", tracker.fillColor, defaults.fillColor)
    EnsureColorField(tracker, "backgroundColor", tracker.backgroundColor, defaults.backgroundColor)
    if type(tracker.texture) ~= "string" or tracker.texture == "" then
        tracker.texture = DEFAULT_TEXTURE
    end
    tracker.backgroundOpacity = Util.Snap(tracker.backgroundOpacity or 1, OPACITY_MIN, OPACITY_MAX, OPACITY_STEP)
    tracker.reverseFill = tracker.reverseFill == true
    tracker.vertical = tracker.vertical == true
    tracker.showBorder = tracker.showBorder == true
    EnsureColorField(tracker, "lineColor", tracker.lineColor, defaults.lineColor)
    tracker.lineThickness = Util.Snap(
        tracker.lineThickness or defaults.lineThickness,
        LINE_THICKNESS_MIN,
        LINE_THICKNESS_MAX,
        LINE_THICKNESS_STEP
    )
    tracker.showStackDividers = tracker.showStackDividers == true
    tracker.showTime = tracker.showTime == true
    if type(tracker.timeFont) ~= "string" or tracker.timeFont == "" then
        tracker.timeFont = DEFAULT_TIME_FONT
    end
    tracker.timeFontSize = Util.Snap(
        tracker.timeFontSize or DEFAULT_FONT_SIZE,
        FONT_SIZE_MIN,
        FONT_SIZE_MAX,
        FONT_SIZE_STEP
    )
    tracker.timePosition = NormalizeTimePosition(tracker.timePosition, tracker.vertical)
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

-- ---------------------------------------------------------------------------
-- Module enable
-- ---------------------------------------------------------------------------

---@return boolean
function AuraTracker:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function AuraTracker:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    -- Module toggle suppresses every instance without changing per-tracker enabled flags.
    NotifyTrackerChanged(nil)
end

-- ---------------------------------------------------------------------------
-- Global visibility (module-level auto-hide)
-- ---------------------------------------------------------------------------

---@param key "hideDuringSkyriding"|"hideDuringPetBattles"|"hideDuringCinematics"
---@param hide boolean
local function SetHideFlag(self, key, hide)
    hide = hide == true
    if self.db[key] == hide then
        return
    end
    self.db[key] = hide
    NotifyTrackerChanged(nil)
end

---@return boolean
function AuraTracker:GetHideDuringSkyriding()
    return self.db.hideDuringSkyriding ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringSkyriding(hide)
    SetHideFlag(self, "hideDuringSkyriding", hide)
end

---@return boolean
function AuraTracker:GetHideDuringPetBattles()
    return self.db.hideDuringPetBattles ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringPetBattles(hide)
    SetHideFlag(self, "hideDuringPetBattles", hide)
end

---@return boolean
function AuraTracker:GetHideDuringCinematics()
    return self.db.hideDuringCinematics ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringCinematics(hide)
    SetHideFlag(self, "hideDuringCinematics", hide)
end

---Whether any enabled module-level auto-hide condition is currently active.
---Does not change per-tracker enablement or activation scope.
---@return boolean
function AuraTracker:ShouldHideAuraBars()
    return (self:GetHideDuringSkyriding() and Activity.IsSkyriding())
        or (self:GetHideDuringPetBattles() and Activity.IsInPetBattle())
        or (self:GetHideDuringCinematics() and Activity.IsInCinematic())
end

-- ---------------------------------------------------------------------------
-- Tracker collection
-- ---------------------------------------------------------------------------

---@return integer[]
function AuraTracker:GetTrackerIds()
    local ids = {}
    for _, tracker in ipairs(self.db.trackers) do
        ids[#ids + 1] = tracker.id
    end
    return ids
end

---@param trackerId integer
---@return boolean
function AuraTracker:HasTracker(trackerId)
    return FindTracker(self.db.trackers, trackerId) ~= nil
end

---Creates a new tracker with defaults and a fresh stable id.
---@return integer trackerId
function AuraTracker:AddTracker()
    local id = math.floor(self.db.nextTrackerId or 1)
    if id < 1 then
        id = 1
    end
    self.db.nextTrackerId = id + 1

    local tracker = NewTrackerDefaults()
    tracker.id = id
    local stackIndex = #self.db.trackers
    tracker.position.y = DEFAULT_POSITION_Y - POSITION_STACK_STEP * stackIndex
    NormalizeTracker(tracker)
    self.db.trackers[#self.db.trackers + 1] = tracker

    NotifyTrackerListChanged()
    NotifyTrackerChanged(id)
    return id
end

---@param trackerId integer
function AuraTracker:RemoveTracker(trackerId)
    local _, index = FindTracker(self.db.trackers, trackerId)
    assert(index ~= nil, "Unknown tracker: " .. tostring(trackerId))
    table.remove(self.db.trackers, index)
    NotifyTrackerListChanged()
    NotifyTrackerChanged(trackerId)
end

---Deep-copies a tracker (settings only), assigns a fresh id, and inserts it immediately after the source.
---@param trackerId integer
---@return integer trackerId
function AuraTracker:DuplicateTracker(trackerId)
    local source, index = FindTracker(self.db.trackers, trackerId)
    assert(index ~= nil and source ~= nil, "Unknown tracker: " .. tostring(trackerId))

    local id = math.floor(self.db.nextTrackerId or 1)
    if id < 1 then
        id = 1
    end
    self.db.nextTrackerId = id + 1

    local tracker = Util.DeepCopy(source)
    tracker.id = id
    NormalizeTracker(tracker)
    table.insert(self.db.trackers, index + 1, tracker)

    NotifyTrackerListChanged()
    NotifyTrackerChanged(id)
    return id
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
    if settings.trackingMode ~= nil then
        self:SetTrackingMode(trackerId, settings.trackingMode)
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
    if settings.showTime ~= nil then
        self:SetShowTime(trackerId, settings.showTime)
    end
    if settings.timeFont ~= nil then
        self:SetTimeFont(trackerId, settings.timeFont)
    end
    if settings.timeFontSize ~= nil then
        self:SetTimeFontSize(trackerId, settings.timeFontSize)
    end
    if settings.timePosition ~= nil then
        self:SetTimePosition(trackerId, settings.timePosition)
    end
    if settings.position ~= nil then
        self:SetPosition(trackerId, settings.position)
    end
end

---@param trackerId integer
---@return boolean
function AuraTracker:IsTrackerEnabled(trackerId)
    return RequireTracker(self, trackerId).enabled == true
end

---@param trackerId integer
---@param enabled boolean
function AuraTracker:SetTrackerEnabled(trackerId, enabled)
    local tracker = RequireTracker(self, trackerId)
    enabled = enabled == true
    if tracker.enabled == enabled then
        return
    end
    tracker.enabled = enabled
    NotifyTrackerChanged(trackerId)
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
    local normalizedScope = NormalizeActivationScope(scope)
    assert(normalizedScope ~= nil, "Bad activation scope")
    local normalizedTarget = NormalizeActivationTarget(normalizedScope, target)
    if normalizedScope == SCOPE_SPECIALIZATION then
        assert(normalizedTarget ~= nil, "Bad specialization ID")
    elseif normalizedScope == SCOPE_CLASS then
        assert(normalizedTarget ~= nil, "Bad class file")
    elseif normalizedScope == SCOPE_ROLE then
        assert(normalizedTarget ~= nil, "Bad role")
    end

    local tracker = RequireTracker(self, trackerId)
    if tracker.activationScope == normalizedScope and tracker.activationTarget == normalizedTarget then
        return
    end
    tracker.activationScope = normalizedScope
    tracker.activationTarget = normalizedTarget
    NotifyTrackerChanged(trackerId)
end

---Whether this tracker's activation scope matches the current player.
---@param trackerId integer
---@return boolean
function AuraTracker:IsActivationActive(trackerId)
    return AuraTracker.AppliesToPlayer(RequireTracker(self, trackerId), Player.GetActivationContext())
end

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

---Short label for a tracker's activation scope (e.g. "Always", "Frost", "Mage", "Healer").
---@param trackerId integer
---@return string
function AuraTracker:GetActivationScopeLabel(trackerId)
    local scope, target = self:GetActivationScope(trackerId)
    if scope == SCOPE_ALWAYS then
        return L.AURA_TRACKER_SCOPE_ALWAYS
    end
    if scope == SCOPE_SPECIALIZATION then
        return Player.GetSpecializationName(target) or tostring(target)
    end
    if scope == SCOPE_CLASS then
        return Player.GetClassName(target) or tostring(target)
    end
    if scope == SCOPE_ROLE then
        return ROLE_LABELS[target] or tostring(target)
    end
    return L.AURA_TRACKER_SCOPE_ALWAYS
end

---Options for configuring activation scope on the current character (for the settings UI).
---@return { classFile: string|nil, specializations: PlayerSpecialization[], roles: PlayerRole[] }
function AuraTracker.GetActivationOptions()
    return {
        classFile = Player.GetClassFile(),
        specializations = Player.ListSpecializations(),
        roles = Player.ListRoles(),
    }
end

---`duration` (SetDurationBar) or `stacks` (SetApplicationBar). Independent per tracker.
---@param trackerId integer
---@return string
function AuraTracker:GetTrackingMode(trackerId)
    return NormalizeTrackingMode(RequireTracker(self, trackerId).trackingMode)
end

---@param trackerId integer
---@return boolean
function AuraTracker:IsStacksMode(trackerId)
    return self:GetTrackingMode(trackerId) == TRACKING_MODE_STACKS
end

---Switches native bar/value binding; appearance-only notify so combat can defer safely.
---@param trackerId integer
---@param mode string
function AuraTracker:SetTrackingMode(trackerId, mode)
    assert(mode == TRACKING_MODE_DURATION or mode == TRACKING_MODE_STACKS, "Bad tracking mode")
    local tracker = RequireTracker(self, trackerId)
    local next = NormalizeTrackingMode(mode)
    if tracker.trackingMode == next then
        return
    end
    tracker.trackingMode = next
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@return integer
function AuraTracker:GetMaxStacks(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "maxStacks",
        DEFAULT_MAX_STACKS,
        MAX_STACKS_MIN,
        MAX_STACKS_MAX,
        MAX_STACKS_STEP
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
        MAX_STACKS_MIN,
        MAX_STACKS_MAX,
        MAX_STACKS_STEP,
        "Bad max stacks"
    )
end

---Display label: resolved spell name, else spell ID, else a generic untitled label.
---@param trackerId integer
---@return string
function AuraTracker:GetDisplayName(trackerId)
    local spellId = self:GetSpellId(trackerId)
    if spellId > 0 then
        local name = Spell.GetName(spellId)
        if name then
            return name
        end
        return tostring(spellId)
    end
    return L.AURA_TRACKER_UNTITLED
end

---@param trackerId integer
---@return number
function AuraTracker:GetWidth(trackerId)
    return GetSnapped(self, trackerId, "width", 200, WIDTH_MIN, WIDTH_MAX, WIDTH_STEP)
end

---@param trackerId integer
---@param width number
function AuraTracker:SetWidth(trackerId, width)
    SetSnapped(self, trackerId, "width", width, WIDTH_MIN, WIDTH_MAX, WIDTH_STEP, "Bad width")
end

---@param trackerId integer
---@return number
function AuraTracker:GetHeight(trackerId)
    return GetSnapped(self, trackerId, "height", 18, HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP)
end

---@param trackerId integer
---@param height number
function AuraTracker:SetHeight(trackerId, height)
    SetSnapped(self, trackerId, "height", height, HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP, "Bad height")
end

---@param trackerId integer
---@return AuraTrackerColor
function AuraTracker:GetFillColor(trackerId)
    return Color.Normalize(RequireTracker(self, trackerId).fillColor) or {
        r = DEFAULT_FILL.r,
        g = DEFAULT_FILL.g,
        b = DEFAULT_FILL.b,
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
    return Media.IsKnownTexture(textureId) and textureId or DEFAULT_TEXTURE
end

---File path for the selected fill texture; independent of fill color tinting.
---@param trackerId integer
---@return string
function AuraTracker:GetTexturePath(trackerId)
    return Media.ResolveTexturePath(self:GetTexture(trackerId))
end

---@return string[]
function AuraTracker:ListTextureIds()
    return Media.ListTextureIds()
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
    return Color.Normalize(RequireTracker(self, trackerId).backgroundColor) or {
        r = DEFAULT_BACKGROUND.r,
        g = DEFAULT_BACKGROUND.g,
        b = DEFAULT_BACKGROUND.b,
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
    return GetSnapped(self, trackerId, "backgroundOpacity", 1, OPACITY_MIN, OPACITY_MAX, OPACITY_STEP)
end

---@param trackerId integer
---@param opacity number
function AuraTracker:SetBackgroundOpacity(trackerId, opacity)
    SetSnapped(
        self,
        trackerId,
        "backgroundOpacity",
        opacity,
        OPACITY_MIN,
        OPACITY_MAX,
        OPACITY_STEP,
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
    local tracker = RequireTracker(self, trackerId)
    vertical = vertical == true
    if tracker.vertical == vertical then
        return
    end
    tracker.vertical = vertical
    -- Remap the stored edge so left/right stay the analogous top/bottom ends.
    tracker.timePosition = NormalizeTimePosition(tracker.timePosition, vertical)
    NotifyAppearanceChanged(trackerId)
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
    return Color.Normalize(RequireTracker(self, trackerId).lineColor) or {
        r = DEFAULT_LINE.r,
        g = DEFAULT_LINE.g,
        b = DEFAULT_LINE.b,
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
        DEFAULT_LINE_THICKNESS,
        LINE_THICKNESS_MIN,
        LINE_THICKNESS_MAX,
        LINE_THICKNESS_STEP
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
        LINE_THICKNESS_MIN,
        LINE_THICKNESS_MAX,
        LINE_THICKNESS_STEP,
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
---@return boolean
function AuraTracker:GetShowTime(trackerId)
    return RequireTracker(self, trackerId).showTime == true
end

---@param trackerId integer
---@param show boolean
function AuraTracker:SetShowTime(trackerId, show)
    SetFlag(self, trackerId, "showTime", show)
end

---Formats remaining seconds for the bar preview: <10 → one decimal, <60 → whole seconds, else m:ss.
---Live duration text uses the matching engine formatter from Api.Aura.GetDurationTextOptions.
---@param seconds number
---@return string
function AuraTracker:FormatRemainingTime(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
        seconds = 0
    end
    if seconds < 10 then
        -- Floor to 0.1s so countdowns never round up into the next band.
        return string.format("%.1f", math.floor(seconds * 10 + 1e-6) / 10)
    end
    if seconds < 60 then
        return string.format("%d", math.floor(seconds))
    end
    local whole = math.floor(seconds)
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

---Stable font id (`default` or an LSM font handle). Falls back when the saved id is unavailable.
---@param trackerId integer
---@return string
function AuraTracker:GetTimeFont(trackerId)
    local fontId = RequireTracker(self, trackerId).timeFont
    return Media.IsKnownFont(fontId) and fontId or DEFAULT_TIME_FONT
end

---File path for the selected time font, or nil to use the game's locale font in UI code.
---@param trackerId integer
---@return string|nil
function AuraTracker:GetTimeFontPath(trackerId)
    return Media.ResolveFontPath(self:GetTimeFont(trackerId))
end

---@return string[]
function AuraTracker:ListTimeFontIds()
    return Media.ListTimeFontIds()
end

---@param trackerId integer
---@param fontId string
function AuraTracker:SetTimeFont(trackerId, fontId)
    assert(Media.IsKnownFont(fontId), "Unknown font: " .. tostring(fontId))
    local tracker = RequireTracker(self, trackerId)
    if tracker.timeFont == fontId then
        return
    end
    tracker.timeFont = fontId
    NotifyAppearanceChanged(trackerId)
end

---@param trackerId integer
---@return number
function AuraTracker:GetTimeFontSize(trackerId)
    return GetSnapped(
        self,
        trackerId,
        "timeFontSize",
        DEFAULT_FONT_SIZE,
        FONT_SIZE_MIN,
        FONT_SIZE_MAX,
        FONT_SIZE_STEP
    )
end

---@param trackerId integer
---@param size number
function AuraTracker:SetTimeFontSize(trackerId, size)
    SetSnapped(
        self,
        trackerId,
        "timeFontSize",
        size,
        FONT_SIZE_MIN,
        FONT_SIZE_MAX,
        FONT_SIZE_STEP,
        "Bad font size"
    )
end

---Anchor for the time text on the bar (`left`/`center`/`right`, or `top`/`center`/`bottom` when vertical).
---@param trackerId integer
---@return string
function AuraTracker:GetTimePosition(trackerId)
    local tracker = RequireTracker(self, trackerId)
    return NormalizeTimePosition(tracker.timePosition, tracker.vertical == true)
end

---@param trackerId integer
---@param position string
function AuraTracker:SetTimePosition(trackerId, position)
    local tracker = RequireTracker(self, trackerId)
    local next = NormalizeTimePosition(position, tracker.vertical == true)
    assert(
        type(position) == "string" and (TIME_POSITION_HORIZONTAL[position] or TIME_POSITION_VERTICAL[position]),
        "Bad time position"
    )
    if tracker.timePosition == next then
        return
    end
    tracker.timePosition = next
    NotifyAppearanceChanged(trackerId)
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

---Whether settings say this tracker should be active (API support is checked in the UI).
---Independent of situational global auto-hide (`ShouldHideAuraBars`).
---@param trackerId integer
---@return boolean
function AuraTracker:ShouldTrack(trackerId)
    return self:IsEnabled()
        and self:IsTrackerEnabled(trackerId)
        and self:GetSpellId(trackerId) > 0
        and self:IsActivationActive(trackerId)
end

---Registers combat-leave so the UI can flush deferred AuraContainer updates.
function AuraTracker:ListenForCombat()
    Combat.OnLeave(function()
        if AuraTracker.OnTrackerChanged then
            AuraTracker:OnTrackerChanged(nil)
        end
    end)
end

---Refreshes tracking when specialization/role changes or becomes available after login/reload.
---Never rewrites saved scopes. Spec-scoped trackers often see nil specialization at ADDON_LOADED;
---PLAYER_ENTERING_WORLD (plus a same-frame defer) rebuilds containers once context is ready.
function AuraTracker:ListenForPlayerContext()
    Player.OnChanged(function()
        NotifyTrackerChanged(nil)
    end)
    Instance.OnEnteringWorld(function()
        NotifyTrackerChanged(nil)
        Timer.After(0, function()
            NotifyTrackerChanged(nil)
        end)
    end)
end

---Refreshes bar visibility when skyriding, pet battles, or cinematics change.
function AuraTracker:ListenForVisibilityContext()
    Activity.OnContextChanged(function()
        NotifyTrackerChanged(nil)
    end)
end

function AuraTracker:OnInit()
    if type(self.db.trackers) ~= "table" then
        self.db.trackers = {}
    end

    local maxId = 0
    local normalized = {}
    for _, tracker in ipairs(self.db.trackers) do
        if type(tracker) == "table" then
            if type(tracker.id) ~= "number" or tracker.id < 1 or tracker.id ~= math.floor(tracker.id) then
                local id = math.floor(self.db.nextTrackerId or (maxId + 1))
                if id < 1 then
                    id = 1
                end
                if id <= maxId then
                    id = maxId + 1
                end
                tracker.id = id
                self.db.nextTrackerId = id + 1
            end
            NormalizeTracker(tracker)
            if tracker.id > maxId then
                maxId = tracker.id
            end
            normalized[#normalized + 1] = tracker
        end
    end
    self.db.trackers = normalized

    local nextId = math.floor(self.db.nextTrackerId or 1)
    if nextId <= maxId then
        nextId = maxId + 1
    end
    self.db.nextTrackerId = nextId
end

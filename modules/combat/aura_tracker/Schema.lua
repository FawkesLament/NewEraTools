local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Media = Internals.Media

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

---Independent FontString settings for duration or stacks text.
---@class AuraTrackerTextDisplay
---@field enabled boolean
---@field font string
---@field fontSize number
---@field offsetX number  Pixels from bar center; positive moves right.
---@field offsetY number  Pixels from bar center; positive moves up.

---@class AuraTrackerInstance
---@field id integer  Stable tracker id; never reused after deletion.
---@field enabled boolean
---@field spellId integer
---@field unit string  `player`, `target`, or `focus`.
---@field auraType string  `HELPFUL` or `HARMFUL`.
---@field activationScope string  `always`, `specialization`, `class`, or `role`.
---@field activationTarget integer|string|nil  Spec ID, class file, or role; nil for `always`.
---@field progressMode string  Progress-bar fill source: `duration` or `stacks`.
---@field maxStacks integer  StatusBar scale for stacks progress (`current / maxStacks`).
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
---@field showStackDividers boolean  Stack-progress segment separators; ignored in duration progress.
---@field textDisplays { duration: AuraTrackerTextDisplay, stacks: AuraTrackerTextDisplay }
---@field position AuraTrackerPosition

local DURATION = "duration"
local STACKS = "stacks"
local UNIT_PLAYER = "player"
local UNIT_TARGET = "target"
local UNIT_FOCUS = "focus"
local HELPFUL = "HELPFUL"
local HARMFUL = "HARMFUL"

---Saved-tracker vocabulary, defaults, and clamps shared by the module and the settings UI.
local Schema = {
    PROGRESS_MODE_DURATION = DURATION,
    PROGRESS_MODE_STACKS = STACKS,
    TEXT_DURATION = DURATION,
    TEXT_STACKS = STACKS,
    TEXT_KINDS = {
        [DURATION] = true,
        [STACKS] = true,
    },

    UNIT_PLAYER = UNIT_PLAYER,
    UNIT_TARGET = UNIT_TARGET,
    UNIT_FOCUS = UNIT_FOCUS,
    UNITS = {
        [UNIT_PLAYER] = true,
        [UNIT_TARGET] = true,
        [UNIT_FOCUS] = true,
    },

    AURA_HELPFUL = HELPFUL,
    AURA_HARMFUL = HARMFUL,
    AURA_TYPES = {
        [HELPFUL] = true,
        [HARMFUL] = true,
    },

    -- Match Assets.Colors.ACCENT / SURFACE / BORDER at the time the bar was first shipped.
    DEFAULT_FILL = { r = 0.310, g = 0.765, b = 0.710 },
    DEFAULT_BACKGROUND = { r = 0.102, g = 0.110, b = 0.133 },
    DEFAULT_LINE = { r = 0.180, g = 0.196, b = 0.231 },
    DEFAULT_TEXTURE = Media.DEFAULT_TEXTURE,
    TEXT_FONT_DEFAULT = Media.DEFAULT_TIME_FONT,

    DEFAULT_FONT_SIZE = 12,
    DEFAULT_LINE_THICKNESS = 1,
    DEFAULT_MAX_STACKS = 10,
    DEFAULT_BAR_WIDTH = 200,
    DEFAULT_BAR_HEIGHT = 18,
    DEFAULT_POSITION_Y = -80,
    POSITION_STACK_STEP = 24,

    WIDTH_MIN = 40,
    WIDTH_MAX = 400,
    WIDTH_STEP = 1,
    HEIGHT_MIN = 4,
    HEIGHT_MAX = 64,
    HEIGHT_STEP = 1,
    OPACITY_MIN = 0,
    OPACITY_MAX = 1,
    OPACITY_STEP = 0.05,
    FONT_SIZE_MIN = 8,
    FONT_SIZE_MAX = 32,
    FONT_SIZE_STEP = 1,
    LINE_THICKNESS_MIN = 1,
    LINE_THICKNESS_MAX = 4,
    LINE_THICKNESS_STEP = 1,
    MAX_STACKS_MIN = 1,
    MAX_STACKS_MAX = 999,
    MAX_STACKS_STEP = 1,
    TEXT_OFFSET_MIN = -200,
    TEXT_OFFSET_MAX = 200,
    TEXT_OFFSET_STEP = 1,
}
Internals.Schema = Schema

---A new tracker record. Omits activation scope so ApplyDefaults cannot stamp the live specialization onto `always`.
---Returns a fresh table, including new color and text-display tables, on every call.
---@return AuraTrackerInstance
function Schema.NewTracker()
    return {
        enabled = true,
        spellId = 0,
        unit = Schema.UNIT_PLAYER,
        auraType = Schema.AURA_HELPFUL,
        progressMode = Schema.PROGRESS_MODE_DURATION,
        maxStacks = Schema.DEFAULT_MAX_STACKS,
        width = Schema.DEFAULT_BAR_WIDTH,
        height = Schema.DEFAULT_BAR_HEIGHT,
        fillColor = { r = Schema.DEFAULT_FILL.r, g = Schema.DEFAULT_FILL.g, b = Schema.DEFAULT_FILL.b },
        backgroundColor = {
            r = Schema.DEFAULT_BACKGROUND.r,
            g = Schema.DEFAULT_BACKGROUND.g,
            b = Schema.DEFAULT_BACKGROUND.b,
        },
        texture = Schema.DEFAULT_TEXTURE,
        backgroundOpacity = 1,
        reverseFill = false,
        vertical = false,
        showBorder = false,
        lineColor = { r = Schema.DEFAULT_LINE.r, g = Schema.DEFAULT_LINE.g, b = Schema.DEFAULT_LINE.b },
        lineThickness = Schema.DEFAULT_LINE_THICKNESS,
        showStackDividers = true,
        textDisplays = {
            [Schema.TEXT_DURATION] = {
                enabled = true,
                font = Schema.TEXT_FONT_DEFAULT,
                fontSize = Schema.DEFAULT_FONT_SIZE,
                offsetX = 0,
                offsetY = 0,
            },
            [Schema.TEXT_STACKS] = {
                enabled = false,
                font = Schema.TEXT_FONT_DEFAULT,
                fontSize = Schema.DEFAULT_FONT_SIZE,
                offsetX = 0,
                offsetY = 0,
            },
        },
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = Schema.DEFAULT_POSITION_Y },
    }
end

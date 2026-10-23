local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")

---@class TwinFangsSoakReminder
---@field enabled boolean
---@field group "left"|"middle"|"right"

---@class TwinFangsInterruptPlayer
---@field name string  "Name-Realm" identity and display.

---@class TwinFangsInterruptChainRegion
---@field group number|nil
---@field players TwinFangsInterruptPlayer[]
---@field backup TwinFangsInterruptPlayer|nil

---@class TwinFangsInterruptChainSettings
---@field front_left TwinFangsInterruptChainRegion
---@field front_right TwinFangsInterruptChainRegion
---@field back_left TwinFangsInterruptChainRegion
---@field back_right TwinFangsInterruptChainRegion

---@class TwinFangsReminder
---@field enabled boolean
---@field chain TwinFangsInterruptChainSettings

---@class TwinFangsNameplateHint
---@field enabled boolean
---@field side "left"|"right"|"top"|"bottom"
---@field size number
---@field offsetX number
---@field offsetY number
---@field opacity number
---@field font string
---@field fontSize number
---@field fontColor RgbColor

---@class TwinFangsSettings
---@field soakReminder TwinFangsSoakReminder
---@field interruptReminder TwinFangsReminder
---@field nameplateHint TwinFangsNameplateHint
---@field interruptStatusHudPosition FloatingWindowPosition

local GROUP_LEFT = "left"
local GROUP_MIDDLE = "middle"
local GROUP_RIGHT = "right"

local SIDE_LEFT = "left"
local SIDE_RIGHT = "right"
local SIDE_TOP = "top"
local SIDE_BOTTOM = "bottom"

---Saved-settings vocabulary, defaults, and clamps shared by the module and the settings UI.
local Schema = {
    GROUP_LEFT = GROUP_LEFT,
    GROUP_MIDDLE = GROUP_MIDDLE,
    GROUP_RIGHT = GROUP_RIGHT,
    GROUPS = {
        [GROUP_LEFT] = true,
        [GROUP_MIDDLE] = true,
        [GROUP_RIGHT] = true,
    },

    SIDE_LEFT = SIDE_LEFT,
    SIDE_RIGHT = SIDE_RIGHT,
    SIDE_TOP = SIDE_TOP,
    SIDE_BOTTOM = SIDE_BOTTOM,
    SIDES = {
        [SIDE_LEFT] = true,
        [SIDE_RIGHT] = true,
        [SIDE_TOP] = true,
        [SIDE_BOTTOM] = true,
    },

    SIZE_DEFAULT = 36,
    SIZE_MIN = 24,
    SIZE_MAX = 64,
    SIZE_STEP = 1,
    OFFSET_MIN = -100,
    OFFSET_MAX = 100,
    OFFSET_STEP = 1,
    OPACITY_DEFAULT = 1,
    OPACITY_MIN = 0.3,
    OPACITY_MAX = 1,
    OPACITY_STEP = 0.01,
    FONT_DEFAULT = ns.SharedMedia.FONT_DEFAULT,
    FONT_SIZE_DEFAULT = 20,
    FONT_SIZE_MIN = 8,
    FONT_SIZE_MAX = 32,
    FONT_SIZE_STEP = 1,
    -- Ice-blue number fill (#7DD6FF).
    FONT_COLOR_DEFAULT = { r = 125 / 255, g = 214 / 255, b = 1 },
}
Internals.Schema = Schema

---A fresh region assignment. Nested player lists are new tables on every call.
---@return TwinFangsInterruptChainRegion
function Schema.NewInterruptRegion()
    return {
        group = nil,
        players = {},
        backup = nil,
    }
end

---A fresh four-region interrupt-chain table. Nested tables are new on every call.
---@return TwinFangsInterruptChainSettings
function Schema.NewInterruptChain()
    return {
        front_left = Schema.NewInterruptRegion(),
        front_right = Schema.NewInterruptRegion(),
        back_left = Schema.NewInterruptRegion(),
        back_right = Schema.NewInterruptRegion(),
    }
end

---A fresh nameplate-hint record, including a new color table, on every call.
---@return TwinFangsNameplateHint
function Schema.NewNameplateHint()
    local color = Schema.FONT_COLOR_DEFAULT
    return {
        enabled = false,
        side = Schema.SIDE_LEFT,
        size = Schema.SIZE_DEFAULT,
        offsetX = 0,
        offsetY = 0,
        opacity = Schema.OPACITY_DEFAULT,
        font = Schema.FONT_DEFAULT,
        fontSize = Schema.FONT_SIZE_DEFAULT,
        fontColor = { r = color.r, g = color.g, b = color.b },
    }
end

---Factory interrupt-status HUD anchor. A new table, so callers can store it without aliasing.
---@return FloatingWindowPosition
function Schema.DefaultInterruptStatusHudPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }
end

---A fresh module saved-variables table. Returns new nested tables on every call.
---@return TwinFangsSettings
function Schema.NewSettings()
    return {
        soakReminder = {
            enabled = false,
            group = Schema.GROUP_LEFT,
        },
        interruptReminder = {
            enabled = false,
            chain = Schema.NewInterruptChain(),
        },
        nameplateHint = Schema.NewNameplateHint(),
        interruptStatusHudPosition = Schema.DefaultInterruptStatusHudPosition(),
    }
end

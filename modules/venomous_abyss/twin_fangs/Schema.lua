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
---@field channel TwinFangsInterruptChannel

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

local CHANNEL_PARTY = "party"
local CHANNEL_SAY = "say"
local CHANNEL_YELL = "yell"
local CHANNEL_EMOTE = "emote"
local CHANNEL_NOD = "nod"
local CHANNEL_MARKER = "marker"

---@alias TwinFangsInterruptChannel "party"|"say"|"yell"|"emote"|"nod"|"marker"

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

    CHANNEL_PARTY = CHANNEL_PARTY,
    CHANNEL_SAY = CHANNEL_SAY,
    CHANNEL_YELL = CHANNEL_YELL,
    CHANNEL_EMOTE = CHANNEL_EMOTE,
    CHANNEL_NOD = CHANNEL_NOD,
    CHANNEL_MARKER = CHANNEL_MARKER,
    CHANNEL_DEFAULT = CHANNEL_PARTY,
    CHANNEL_IDS = { CHANNEL_PARTY, CHANNEL_SAY, CHANNEL_YELL, CHANNEL_EMOTE, CHANNEL_NOD, CHANNEL_MARKER },
    CHANNELS = {
        [CHANNEL_PARTY] = true,
        [CHANNEL_SAY] = true,
        [CHANNEL_YELL] = true,
        [CHANNEL_EMOTE] = true,
        [CHANNEL_NOD] = true,
        [CHANNEL_MARKER] = true,
    },
    CHANNEL_ALLOWS_BACKUP = {
        [CHANNEL_PARTY] = false,
        [CHANNEL_SAY] = true,
        [CHANNEL_YELL] = true,
        [CHANNEL_EMOTE] = true,
        [CHANNEL_NOD] = true,
        [CHANNEL_MARKER] = true,
    },
    -- Channels that share a group cannot be used by two regions. party is omitted
    -- (reusable). say/yell/emote each have their own group so two regions cannot
    -- share the same spoken channel; mixing them is allowed until in-game tests
    -- prove they cannot be distinguished. Assign the same group id to merge them.
    CHANNEL_CONFLICT_GROUP = {
        [CHANNEL_SAY] = "say",
        [CHANNEL_YELL] = "yell",
        [CHANNEL_EMOTE] = "emote",
        [CHANNEL_NOD] = "nod",
        [CHANNEL_MARKER] = "marker",
    },
    CHANNEL_LABELS = {
        [CHANNEL_PARTY] = "TWIN_FANGS_INTERRUPT_CHANNEL_PARTY",
        [CHANNEL_SAY] = "TWIN_FANGS_INTERRUPT_CHANNEL_SAY",
        [CHANNEL_YELL] = "TWIN_FANGS_INTERRUPT_CHANNEL_YELL",
        [CHANNEL_EMOTE] = "TWIN_FANGS_INTERRUPT_CHANNEL_EMOTE",
        [CHANNEL_NOD] = "TWIN_FANGS_INTERRUPT_CHANNEL_NOD",
        [CHANNEL_MARKER] = "TWIN_FANGS_INTERRUPT_CHANNEL_MARKER",
    },
    -- One-letter sync / AddonCheck codes. Keep stable; legacy payloads omit them.
    CHANNEL_WIRE = {
        [CHANNEL_PARTY] = "p",
        [CHANNEL_SAY] = "s",
        [CHANNEL_YELL] = "y",
        [CHANNEL_EMOTE] = "e",
        [CHANNEL_NOD] = "n",
        [CHANNEL_MARKER] = "m",
    },
    CHANNEL_FROM_WIRE = {
        p = CHANNEL_PARTY,
        s = CHANNEL_SAY,
        y = CHANNEL_YELL,
        e = CHANNEL_EMOTE,
        n = CHANNEL_NOD,
        m = CHANNEL_MARKER,
    },
    -- Interrupt-macro communication line. appendReport adds the localized "已打断" text.
    CHANNEL_MACRO = {
        [CHANNEL_PARTY] = { command = "/p", appendReport = true },
        [CHANNEL_SAY] = { command = "/s", appendReport = true },
        [CHANNEL_YELL] = { command = "/y", appendReport = true },
        [CHANNEL_EMOTE] = { command = "/e", appendReport = true },
        [CHANNEL_NOD] = { command = "/nod", appendReport = false },
        -- /tm 8 toggles skull. Each successful toggle is one RAID_TARGET_UPDATE.
        [CHANNEL_MARKER] = { command = "/tm [@player] 8", appendReport = false },
    },
}
Internals.Schema = Schema

---@param channel any
---@return boolean
function Schema.IsChannel(channel)
    return Schema.CHANNELS[channel] == true
end

---Missing or unknown values become the default party channel.
---@param channel any
---@return TwinFangsInterruptChannel
function Schema.CoerceChannel(channel)
    if Schema.IsChannel(channel) then
        return channel
    end
    return Schema.CHANNEL_DEFAULT
end

---@param channel any
---@return boolean
function Schema.ChannelAllowsBackup(channel)
    return Schema.CHANNEL_ALLOWS_BACKUP[Schema.CoerceChannel(channel)] == true
end

---Shared conflict key, or nil when the channel may be reused across regions.
---@param channel any
---@return string|nil
function Schema.ChannelConflictGroup(channel)
    return Schema.CHANNEL_CONFLICT_GROUP[Schema.CoerceChannel(channel)]
end

---@param channel any
---@return string
function Schema.EncodeChannelWire(channel)
    return Schema.CHANNEL_WIRE[Schema.CoerceChannel(channel)]
end

---One-letter wire code to a channel id, or nil when the code is unknown.
---@param code any
---@return TwinFangsInterruptChannel|nil
function Schema.DecodeChannelWire(code)
    if type(code) ~= "string" then
        return nil
    end
    return Schema.CHANNEL_FROM_WIRE[code]
end

---Leading slash token for compact UI (`/y`), or nil when the value is not a channel.
---@param channel any
---@return string|nil
function Schema.ChannelSlash(channel)
    if not Schema.IsChannel(channel) then
        return nil
    end
    return Schema.CHANNEL_MACRO[channel].command:match("^(%S+)")
end

---Communication line for the interrupt macro. `reportText` is appended only for chat channels.
---@param channel any
---@param reportText string
---@return string
function Schema.ChannelMacroLine(channel, reportText)
    local spec = Schema.CHANNEL_MACRO[Schema.CoerceChannel(channel)]
    if spec.appendReport then
        return spec.command .. " " .. reportText
    end
    return spec.command
end

---A fresh region assignment. Nested player lists are new tables on every call.
---@return TwinFangsInterruptChainRegion
function Schema.NewInterruptRegion()
    return {
        group = nil,
        players = {},
        backup = nil,
        channel = Schema.CHANNEL_DEFAULT,
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

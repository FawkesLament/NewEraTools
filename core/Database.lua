local _, ns = ...

local Database = {}
ns.Database = Database

local SCHEMA_VERSION = 10

-- migrations[n] upgrades saved data from version n - 1 to version n, in place.
local migrations = {}

-- Sszorak's left/right flag used to flip the map 180°. Keep that view, then store the side on its own.
migrations[7] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.Sszorak or nil
    if type(settings) ~= "table" then
        return
    end
    if settings.mapRotation == nil and settings.mapRotated == true then
        settings.mapRotation = 180
    end
    if settings.playerSide == nil then
        if settings.mapRotated == true then
            settings.playerSide = "right"
        elseif settings.mapRotated == false then
            settings.playerSide = "left"
        end
    end
    settings.mapRotated = nil
end

local function IsCalloutPosition(position)
    return type(position) == "table"
        and type(position.point) == "string"
        and type(position.relativePoint) == "string"
        and type(position.x) == "number"
        and type(position.y) == "number"
end

local function CalloutPositionOf(settings)
    if type(settings) ~= "table" or not IsCalloutPosition(settings.calloutPosition) then
        return nil
    end
    return settings.calloutPosition
end

-- One shared on-screen callout anchor. Sszorak's anchor wins when it is valid; otherwise The Lost Explorers.
migrations[8] = function(saved)
    local modules = saved.modules
    if type(modules) ~= "table" then
        return
    end
    local chosen = CalloutPositionOf(modules.Sszorak) or CalloutPositionOf(modules.TheLostExplorers)
    if chosen then
        saved.calloutPosition = {
            point = chosen.point,
            relativePoint = chosen.relativePoint,
            x = chosen.x,
            y = chosen.y,
        }
    end
    if type(modules.Sszorak) == "table" then
        modules.Sszorak.calloutPosition = nil
    end
    if type(modules.TheLostExplorers) == "table" then
        modules.TheLostExplorers.calloutPosition = nil
    end
end

-- Twin Fangs interrupt voice alerts were removed.
migrations[9] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.TwinFangs or nil
    local reminder = type(settings) == "table" and settings.interruptReminder or nil
    if type(reminder) == "table" then
        reminder.voice = nil
    end
end

-- Interrupt Claim was unlaunched; drop leftover user settings.
migrations[10] = function(saved)
    local modules = saved.modules
    if type(modules) == "table" then
        modules.InterruptClaim = nil
    end
end

---Upgrades saved variables to the current schema, creating them if missing.
---@param saved table|nil
---@return table
function Database.Load(saved)
    saved = saved or {}
    local version = saved.schemaVersion or SCHEMA_VERSION
    for target = version + 1, SCHEMA_VERSION do
        migrations[target](saved)
    end
    saved.schemaVersion = SCHEMA_VERSION
    saved.modules = saved.modules or {}
    return saved
end

---Returns the settings table for one module, filling in its defaults.
---@param saved table  Result of Database.Load.
---@param moduleName string
---@param defaults table|nil
---@return table
function Database.GetModuleSettings(saved, moduleName, defaults)
    saved.modules[moduleName] = saved.modules[moduleName] or {}
    local settings = saved.modules[moduleName]
    if defaults then
        ns.Util.ApplyDefaults(settings, defaults)
    end
    return settings
end

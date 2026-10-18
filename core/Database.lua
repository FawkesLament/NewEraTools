local _, ns = ...

local Database = {}
ns.Database = Database

local SCHEMA_VERSION = 7

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

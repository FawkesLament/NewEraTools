local _, ns = ...

local Database = {}
ns.Database = Database

local SCHEMA_VERSION = 6

-- migrations[n] upgrades saved data from version n - 1 to version n, in place.
local migrations = {
    -- BuffTracker was renamed to AuraTracker; carry settings forward once.
    [2] = function(saved)
        local modules = saved.modules
        if type(modules) ~= "table" then
            return
        end
        if modules.AuraTracker == nil and type(modules.BuffTracker) == "table" then
            modules.AuraTracker = modules.BuffTracker
        end
        modules.BuffTracker = nil
    end,
    -- Single-tracker AuraTracker settings become a trackers collection.
    [3] = function(saved)
        local modules = saved.modules
        if type(modules) ~= "table" then
            return
        end
        local auraTracker = modules.AuraTracker
        if type(auraTracker) ~= "table" or type(auraTracker.trackers) == "table" then
            return
        end

        local tracker = {
            id = 1,
            enabled = true,
            spellId = auraTracker.spellId,
            width = auraTracker.width,
            height = auraTracker.height,
            fillColor = auraTracker.fillColor,
            backgroundColor = auraTracker.backgroundColor,
            texture = auraTracker.texture,
            backgroundOpacity = auraTracker.backgroundOpacity,
            reverseFill = auraTracker.reverseFill,
            vertical = auraTracker.vertical,
            showBorder = auraTracker.showBorder,
            showTime = auraTracker.showTime,
            timeFont = auraTracker.timeFont,
            timeFontSize = auraTracker.timeFontSize,
            timePosition = auraTracker.timePosition,
            position = auraTracker.position,
        }
        auraTracker.trackers = { tracker }
        auraTracker.nextTrackerId = 2

        auraTracker.spellId = nil
        auraTracker.width = nil
        auraTracker.height = nil
        auraTracker.fillColor = nil
        auraTracker.backgroundColor = nil
        auraTracker.texture = nil
        auraTracker.backgroundOpacity = nil
        auraTracker.reverseFill = nil
        auraTracker.vertical = nil
        auraTracker.showBorder = nil
        auraTracker.showTime = nil
        auraTracker.timeFont = nil
        auraTracker.timeFontSize = nil
        auraTracker.timePosition = nil
        auraTracker.position = nil
    end,
    -- CombatLogReminder was renamed to CombatLog; remap location toggles.
    [4] = function(saved)
        local modules = saved.modules
        if type(modules) ~= "table" then
            return
        end
        if modules.CombatLog == nil and type(modules.CombatLogReminder) == "table" then
            local old = modules.CombatLogReminder
            if old.enableRaids == nil and old.remindRaids ~= nil then
                old.enableRaids = old.remindRaids
            end
            if old.enableMythicDungeons == nil and old.remindMythicDungeons ~= nil then
                old.enableMythicDungeons = old.remindMythicDungeons
            end
            old.remindRaids = nil
            old.remindMythicDungeons = nil
            -- Warning-window scale/position are no longer module settings.
            old.scale = nil
            old.position = nil
            modules.CombatLog = old
        end
        modules.CombatLogReminder = nil
    end,
    -- CombatLog location checkboxes become a single three-way locations setting.
    [5] = function(saved)
        local modules = saved.modules
        if type(modules) ~= "table" then
            return
        end
        local combatLog = modules.CombatLog
        if type(combatLog) ~= "table" or combatLog.locations ~= nil then
            return
        end
        local raids = combatLog.enableRaids ~= false
        local dungeons = combatLog.enableMythicDungeons ~= false
        if raids and not dungeons then
            combatLog.locations = "RAIDS"
        elseif dungeons and not raids then
            combatLog.locations = "DUNGEONS"
        else
            combatLog.locations = "ALL"
        end
        combatLog.enableRaids = nil
        combatLog.enableMythicDungeons = nil
    end,
    -- Sszorak raid role is derived from raid leadership; drop the saved toggle.
    [6] = function(saved)
        local modules = saved.modules
        if type(modules) ~= "table" then
            return
        end
        local sszorak = modules.Sszorak
        if type(sszorak) == "table" then
            sszorak.raidRole = nil
        end
    end,
}

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

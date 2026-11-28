local _, ns = ...

local Database = {}
ns.Database = Database

local SCHEMA_VERSION = 18
-- SavedVariables at or below this version skip retired 7–12 transforms and continue from 13.
local MIN_MIGRATED_VERSION = 12

-- migrations[n] upgrades saved data from version n - 1 to version n, in place.
local migrations = {}

-- Coiled Altar mechanic reminders are always on; drop the leftover section toggle.
migrations[13] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.CoiledAltar or nil
    local reminder = type(settings) == "table" and settings.mechanicReminder or nil
    if type(reminder) == "table" then
        reminder.enabled = nil
    end
end

-- Boss Alert fontSize used to size the alert body; the countdown was 1.2x that. Store countdown size.
migrations[14] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.BossAlert or nil
    local callout = type(settings) == "table" and settings.callout or nil
    if type(callout) ~= "table" then
        return
    end
    local size = tonumber(callout.fontSize)
    if not size then
        return
    end
    callout.fontSize = math.floor(size * 1.2 + 0.5)
end

local function RenameCalloutKey(callout, from, to)
    if callout[to] == nil and callout[from] ~= nil then
        callout[to] = callout[from]
    end
    callout[from] = nil
end

-- Boss Alert callout keys: alert body face/color vs countdown size.
migrations[15] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.BossAlert or nil
    local callout = type(settings) == "table" and settings.callout or nil
    if type(callout) ~= "table" then
        return
    end
    RenameCalloutKey(callout, "font", "alertFont")
    RenameCalloutKey(callout, "fontSize", "countdownFontSize")
    RenameCalloutKey(callout, "fontColor", "alertFontColor")
end

local function ChainHasEntries(chain)
    if type(chain) ~= "table" then
        return false
    end
    for index = 1, 6 do
        local slot = chain[index]
        if type(slot) == "table" and (slot.type == "player" or slot.type == "text") then
            return true
        end
    end
    return false
end

-- Coiled Altar now has 1 unmarked shadow per wave: keep the single rotation in RANGED with markedChain = MELEE
-- so v1 Sync payloads remain compatible with older clients.
migrations[16] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.CoiledAltar or nil
    if type(settings) ~= "table" then
        return
    end
    local assignments = settings.assignments
    if type(assignments) == "table" then
        local meleeHas = ChainHasEntries(assignments.MELEE)
        local rangedHas = ChainHasEntries(assignments.RANGED)
        if (not rangedHas and meleeHas) or (rangedHas and meleeHas and settings.markedChain == "RANGED") then
            assignments.RANGED = assignments.MELEE
        end
        assignments.MELEE = {}
    end
    settings.markedChain = "MELEE"
end

local function RenameSavedKey(tbl, from, to)
    if tbl[to] == nil and tbl[from] ~= nil then
        tbl[to] = tbl[from]
    end
    tbl[from] = nil
end

-- Twin Fangs venom roster: rowSpacing was row height; columnSpacing was the gap between columns.
migrations[17] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.TwinFangs or nil
    local roster = type(settings) == "table" and settings.venomRoster or nil
    if type(roster) ~= "table" then
        return
    end
    RenameSavedKey(roster, "rowSpacing", "rowHeight")
    RenameSavedKey(roster, "columnSpacing", "columnGap")
end

-- Ulatek Wretch AoE reminder was stored as addSoak.
migrations[18] = function(saved)
    local modules = saved.modules
    local settings = type(modules) == "table" and modules.Ulatek or nil
    local reminder = type(settings) == "table" and settings.mechanicReminder or nil
    if type(reminder) == "table" then
        RenameSavedKey(reminder, "addSoak", "wretchAoe")
    end
end

---Upgrades saved variables to the current schema, creating them if missing.
---@param saved table|nil
---@return table
function Database.Load(saved)
    saved = saved or {}
    local version = saved.schemaVersion or SCHEMA_VERSION
    if version < MIN_MIGRATED_VERSION then
        version = MIN_MIGRATED_VERSION
    end
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

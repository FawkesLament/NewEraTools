local _, ns = ...

local Aura = {}
ns.Api.Aura = Aura

Aura.UNIT_PLAYER = "player"
Aura.UNIT_TARGET = "target"
Aura.UNIT_FOCUS = "focus"
Aura.FILTER_HELPFUL = "HELPFUL"
Aura.FILTER_HARMFUL = "HARMFUL"

local SUPPORTED_SOURCES = {
    [Aura.UNIT_PLAYER] = { [Aura.FILTER_HELPFUL] = true },
    [Aura.UNIT_TARGET] = { [Aura.FILTER_HARMFUL] = true },
    [Aura.UNIT_FOCUS] = { [Aura.FILTER_HARMFUL] = true },
}

---Player buffs, target debuffs, and focus debuffs. Other pairs are not tracked yet.
---@param unit string
---@param auraType string
---@return boolean
function Aura.IsSupportedSource(unit, auraType)
    local auraTypes = SUPPORTED_SOURCES[unit]
    return auraTypes ~= nil and auraTypes[auraType] == true
end

---Whether includeSpellIDs may be left active for this unit without admitting other auras.
---WoW 12.1.0 skips spell-ID matching for harmful auras on assistable units and then keeps
---every other debuff. Later builds reject those auras instead. Either way, a friendly
---target/focus must not keep a HARMFUL slot enabled.
---@param unit string
---@param auraType string
---@return boolean
function Aura.CanApplyIncludeSpellFilter(unit, auraType)
    if not Aura.IsSupportedSource(unit, auraType) then
        return false
    end
    if not ns.Api.Unit.Exists(unit) then
        return false
    end
    if auraType == Aura.FILTER_HARMFUL then
        return ns.Api.Unit.CanPlayerAssist(unit) == false
    end
    return true
end

---Target, focus, and reaction changes. AuraContainer already consumes UNIT_AURA for the bound
---token; it does not rebuild when the same token points at a new unit.
---The callback receives the event name and, for unit events, the registered unit token.
---@param callback fun(event: string, unit: string|nil)
function Aura.OnUnitContextChanged(callback)
    local GameEvents = ns.Api.GameEvents
    GameEvents.Listen("PLAYER_TARGET_CHANGED", function()
        callback("PLAYER_TARGET_CHANGED")
    end)
    GameEvents.Listen("PLAYER_FOCUS_CHANGED", function()
        callback("PLAYER_FOCUS_CHANGED")
    end)
    for _, unit in ipairs({ Aura.UNIT_PLAYER, Aura.UNIT_TARGET, Aura.UNIT_FOCUS }) do
        GameEvents.ListenUnit("UNIT_FACTION", unit, function()
            callback("UNIT_FACTION", unit)
        end)
        GameEvents.ListenUnit("UNIT_FLAGS", unit, function()
            callback("UNIT_FLAGS", unit)
        end)
    end
end

local ADDON_NAME = "Blizzard_AuraContainer"

---@param value any
---@return boolean
local function IsSecret(value)
    if issecretvalue and issecretvalue(value) then
        return true
    end
    if issecret and issecret(value) then
        return true
    end
    return false
end

---Whether tainted code may call methods on this widget.
---AuraContainer applies `DenyTaintedAccessWhenAurasAreSecret` after `initializeFrame`, so a
---later tainted `SetSize` on the slot button errors while aura data is secret. Untainted
---callers (and frames that do not deny access) still pass.
---@param object table|nil
---@return boolean
function Aura.CanAccessObject(object)
    if type(object) ~= "table" then
        return false
    end
    if type(object.CanBeAccessedInContext) == "function" then
        local ok, canAccess = pcall(object.CanBeAccessedInContext, object)
        if not ok or IsSecret(canAccess) or canAccess ~= true then
            return false
        end
        return true
    end
    if type(object.IsForbidden) == "function" then
        local ok, forbidden = pcall(object.IsForbidden, object)
        if not ok or IsSecret(forbidden) or forbidden == true then
            return false
        end
    end
    -- Slot buttons on older builds may omit CanBeAccessedInContext. The same secrecy
    -- rule still blocks tainted geometry once the container has restricted the frame.
    if not (issecure and issecure()) and C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(secret) or secret == true then
            return false
        end
    end
    return true
end

-- Cached text options; rebuilt only if formatter creation fails on first try.
local durationTextOptions
local applicationCountOptions

---Loads Blizzard's AuraContainer UI package when needed.
---@return boolean
function Aura.EnsureLoaded()
    if not C_AddOns then
        return false
    end
    if C_AddOns.IsAddOnLoaded(ADDON_NAME) then
        return true
    end
    local loaded = C_AddOns.LoadAddOn(ADDON_NAME)
    return loaded == true
end

---Whether the 12.1 AuraContainer sorting globals are available after loading.
---@return boolean
function Aura.IsSupported()
    if not Aura.EnsureLoaded() then
        return false
    end
    return type(AuraContainerSortMethod) == "table"
        and AuraContainerSortMethod.Expiration ~= nil
        and type(AuraContainerSortDirection) == "table"
        and AuraContainerSortDirection.Normal ~= nil
        and Enum ~= nil
        and Enum.StatusBarTimerDirection ~= nil
        and Enum.StatusBarTimerDirection.RemainingTime ~= nil
end

---Fresh candidateFilters table keyed by spell ID (engine may mutate the map).
---@param spellId integer
---@return table
function Aura.BuildIncludeSpellFilters(spellId)
    return {
        includeSpellIDs = { [spellId] = true },
    }
end

---@return unknown sortMethod
---@return unknown sortDirection
function Aura.GetExpirationSort()
    return AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal
end

---Options for AuraButton:SetDurationBar so the bar drains with remaining time.
---@return table
function Aura.GetDurationBarOptions()
    local options = {
        direction = Enum.StatusBarTimerDirection.RemainingTime,
    }
    if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
        options.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
    end
    return options
end

---Options for AuraButton:SetApplicationBar (`currentStacks / maxApplications`).
---@param maxApplications integer
---@return table
function Aura.GetApplicationBarOptions(maxApplications)
    local options = {
        maxApplications = maxApplications,
    }
    if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
        options.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
    end
    return options
end

---Engine-side formatter for Aura Tracker's remaining-time bands (secret-safe SetDurationText).
---Bands: <10s → one decimal; <60s → whole seconds; else m:ss. Matches AuraTracker:FormatRemainingTime.
---@return table|nil
local function BuildDurationTextFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil
    end
    if not (Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down) then
        return nil
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local down = Enum.NumericRuleFormatRounding.Down
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%.1f", step = 0.1, rounding = down },
        { threshold = 10, format = "%d", step = 1, rounding = down },
        {
            threshold = 60,
            format = "%d:%02d",
            step = 1,
            rounding = down,
            components = { { div = 60 }, { mod = 60 } },
        },
    })
    if not ok then
        return nil
    end
    return formatter
end

---Options for AuraButton:SetDurationText (banded remaining-time formatter when available).
---@return table
function Aura.GetDurationTextOptions()
    if durationTextOptions == nil then
        local formatter = BuildDurationTextFormatter()
        durationTextOptions = formatter and { textFormatter = formatter } or {}
    end
    return durationTextOptions
end

---Always-show integer formatter so stack count 1 is visible (native default hides ≤1).
---`auraData.applications` is 0 for a single stack (and for non-stacking auras). An unclamped
---`%d` formatter therefore prints "0"; `min` raises that to 1 without changing 2+.
---@return table|nil
local function BuildApplicationCountFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%d", step = 1, min = 1 },
    })
    if not ok then
        return nil
    end
    return formatter
end

---Options for AuraButton:SetApplicationCount (integer stack display when available).
---@return table
function Aura.GetApplicationCountOptions()
    if applicationCountOptions == nil then
        local formatter = BuildApplicationCountFormatter()
        applicationCountOptions = formatter and { formatter = formatter } or {}
    end
    return applicationCountOptions
end

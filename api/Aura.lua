local _, ns = ...

local Aura = {}
ns.Api.Aura = Aura

Aura.UNIT_PLAYER = "player"
Aura.FILTER_HELPFUL = "HELPFUL"

local ADDON_NAME = "Blizzard_AuraContainer"

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
    if Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
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
    if Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
        options.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
    end
    return options
end

---Engine-side formatter for Aura Tracker's remaining-time bands (secret-safe SetDurationText).
---Bands: <10s → one decimal; <60s → whole seconds; else m:ss. Matches AuraTracker.FormatRemainingTime.
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
---@return table|nil
local function BuildApplicationCountFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%d", step = 1 },
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

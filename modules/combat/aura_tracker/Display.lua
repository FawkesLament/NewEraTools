local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Player = ns.Api.Player
local Spell = ns.Api.Spell
local Activation = Internals.Activation
local L = ns.L

local AuraTracker = ns.Modules.Get("AuraTracker")

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

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

---Short label for a tracker's activation scope (e.g. "Always", "Frost", "Mage", "Healer").
---@param trackerId integer
---@return string
function AuraTracker:GetActivationScopeLabel(trackerId)
    local scope, target = self:GetActivationScope(trackerId)
    if scope == Activation.ALWAYS then
        return L.AURA_TRACKER_SCOPE_ALWAYS
    end
    if scope == Activation.SPECIALIZATION then
        return Player.GetSpecializationName(target) or tostring(target)
    end
    if scope == Activation.CLASS then
        return Player.GetClassName(target) or tostring(target)
    end
    if scope == Activation.ROLE then
        return ROLE_LABELS[target] or tostring(target)
    end
    return L.AURA_TRACKER_SCOPE_ALWAYS
end

---Options for configuring activation scope on the current character.
---@return { classFile: string|nil, specializations: PlayerSpecialization[], roles: PlayerRole[] }
function AuraTracker.GetActivationOptions()
    return {
        classFile = Player.GetClassFile(),
        specializations = Player.ListSpecializations(),
        roles = Player.ListRoles(),
    }
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

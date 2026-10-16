local _, ns = ...
local Player = ns.Api.Player

local ALWAYS = "always"
local SPECIALIZATION = "specialization"
local CLASS = "class"
local ROLE = "role"
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local Activation = {
    ALWAYS = ALWAYS,
    SPECIALIZATION = SPECIALIZATION,
    CLASS = CLASS,
    ROLE = ROLE,
}
ns.AuraTrackerActivation = Activation

---@param scope any
---@return string|nil
function Activation.NormalizeScope(scope)
    if scope == ALWAYS or scope == SPECIALIZATION or scope == CLASS or scope == ROLE then
        return scope
    end
    return nil
end

---@param scope string
---@param target any
---@return integer|string|nil
function Activation.NormalizeTarget(scope, target)
    if scope == ALWAYS then
        return nil
    end
    if scope == SPECIALIZATION then
        if type(target) ~= "number" then
            return nil
        end
        local id = math.floor(target)
        if id < 1 or id ~= target then
            return nil
        end
        return id
    end
    if scope == CLASS then
        if type(target) == "string" and target ~= "" then
            return target
        end
        return nil
    end
    if scope == ROLE and ROLES[target] then
        return target
    end
    return nil
end

---Current specialization ID when available, otherwise class, otherwise always.
---@return string scope
---@return integer|string|nil target
function Activation.Default()
    local specializationId = Player.GetSpecializationId()
    if specializationId then
        return SPECIALIZATION, specializationId
    end
    local classFile = Player.GetClassFile()
    if classFile then
        return CLASS, classFile
    end
    return ALWAYS, nil
end

---Repairs `activationScope` / `activationTarget` on a saved tracker.
---Unknown scopes become `Default`. A specialization or class scope with no target uses the live player.
---@param tracker { activationScope: string|nil, activationTarget: integer|string|nil }
function Activation.Normalize(tracker)
    local scope = Activation.NormalizeScope(tracker.activationScope)
    if not scope then
        scope, tracker.activationTarget = Activation.Default()
    end
    tracker.activationScope = scope
    tracker.activationTarget = Activation.NormalizeTarget(scope, tracker.activationTarget)
    if scope == SPECIALIZATION and tracker.activationTarget == nil then
        tracker.activationTarget = Player.GetSpecializationId()
    elseif scope == CLASS and tracker.activationTarget == nil then
        tracker.activationTarget = Player.GetClassFile()
    end
end

---Validates a scope/target pair for persistence. Raises on an unknown scope or a missing required target.
---@param scope any
---@param target any
---@return string normalizedScope
---@return integer|string|nil normalizedTarget
function Activation.Require(scope, target)
    local normalizedScope = Activation.NormalizeScope(scope)
    assert(normalizedScope ~= nil, "Bad activation scope")
    local normalizedTarget = Activation.NormalizeTarget(normalizedScope, target)
    if normalizedScope == SPECIALIZATION then
        assert(normalizedTarget ~= nil, "Bad specialization ID")
    elseif normalizedScope == CLASS then
        assert(normalizedTarget ~= nil, "Bad class file")
    elseif normalizedScope == ROLE then
        assert(normalizedTarget ~= nil, "Bad role")
    end
    return normalizedScope, normalizedTarget
end

---Whether a tracker's saved activation scope applies to the given player context.
---Pure matching helper: does not read saved settings or the live player.
---@param tracker { activationScope: string|nil, activationTarget: integer|string|nil }
---@param context PlayerActivationContext
---@return boolean
function Activation.AppliesToPlayer(tracker, context)
    local scope = Activation.NormalizeScope(tracker.activationScope) or ALWAYS
    local target = Activation.NormalizeTarget(scope, tracker.activationTarget)
    if scope == ALWAYS then
        return true
    end
    if not context then
        return false
    end
    if scope == SPECIALIZATION then
        return target ~= nil and context.specializationId == target
    end
    if scope == CLASS then
        return target ~= nil and context.classFile == target
    end
    if scope == ROLE then
        return target ~= nil and context.role == target
    end
    return false
end

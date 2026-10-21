local _, ns = ...

local Spell = {}
ns.Api.Spell = Spell

---Calls `callback` when any unit starts a spellcast.
---@param callback fun(unitTarget: string, castGUID: string, spellID: number)
---@return fun()  Unsubscribe.
function Spell.OnCastStart(callback)
    return ns.Api.GameEvents.Listen("UNIT_SPELLCAST_START", callback)
end

---Calls `callback` when any unit stops a spellcast.
---@param callback fun(unitTarget: string, castGUID: string, spellID: number)
---@return fun()  Unsubscribe.
function Spell.OnCastStop(callback)
    return ns.Api.GameEvents.Listen("UNIT_SPELLCAST_STOP", callback)
end

---Calls `callback` when `unit` starts channeling.
---@param unit string
---@param callback fun(unitTarget: string, castGUID: string, spellID: number, castBarID: number|nil)
---@return fun()  Unsubscribe.
function Spell.OnUnitChannelStart(unit, callback)
    return ns.Api.GameEvents.ListenUnit("UNIT_SPELLCAST_CHANNEL_START", unit, function(unitTarget, ...)
        if unitTarget == unit then
            callback(unitTarget, ...)
        end
    end)
end

---Calls `callback` when `unit` stops channeling.
---@param unit string
---@param callback fun(unitTarget: string, castGUID: string, spellID: number, interruptedBy: string|nil, castBarID: number|nil)
---@return fun()  Unsubscribe.
function Spell.OnUnitChannelStop(unit, callback)
    return ns.Api.GameEvents.ListenUnit("UNIT_SPELLCAST_CHANNEL_STOP", unit, function(unitTarget, ...)
        if unitTarget == unit then
            callback(unitTarget, ...)
        end
    end)
end

-- spellId -> texture path/file id, or false when looked up and missing.
local textureCache = {}

---@param spellId any
---@return integer|nil
local function NormalizeSpellId(spellId)
    if type(spellId) ~= "number" or spellId <= 0 then
        return nil
    end
    local id = math.floor(spellId)
    if id ~= spellId then
        return nil
    end
    return id
end

---Localized spell name, or nil when the ID is unknown / unavailable.
---@param spellId integer
---@return string|nil
function Spell.GetName(spellId)
    local id = NormalizeSpellId(spellId)
    if not id then
        return nil
    end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
        return nil
    end
    if GetSpellInfo then
        local name = GetSpellInfo(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

---Spell icon texture (file id or path), or nil when the ID is unknown / unavailable.
---Results are cached so list/header refreshes do not repeat game lookups.
---@param spellId integer
---@return integer|string|nil
function Spell.GetTexture(spellId)
    local id = NormalizeSpellId(spellId)
    if not id then
        return nil
    end

    local cached = textureCache[id]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(id)
    elseif GetSpellInfo then
        local _, _, icon = GetSpellInfo(id)
        texture = icon
    end

    if (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
        textureCache[id] = texture
        return texture
    end

    textureCache[id] = false
    return nil
end

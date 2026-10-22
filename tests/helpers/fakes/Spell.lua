return function()
    local Spell = {}
    local names = {}
    local textures = {}
    local castStartCallbacks = {}
    local castStopCallbacks = {}
    local channelStartCallbacks = {}
    local channelStopCallbacks = {}

    local function AddUnitCallback(bucket, unit, callback)
        bucket[unit] = bucket[unit] or {}
        table.insert(bucket[unit], callback)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            local list = bucket[unit]
            if not list then
                return
            end
            for index, candidate in ipairs(list) do
                if candidate == callback then
                    table.remove(list, index)
                    break
                end
            end
            if #list == 0 then
                bucket[unit] = nil
            end
        end
    end

    local interruptName
    local knownByPlayerOrPet = {}

    ---Whether the player or their pet knows `spellId`. Unset IDs are unknown in tests.
    ---@param spellId integer
    ---@return boolean
    function Spell.IsKnownByPlayerOrPet(spellId)
        return knownByPlayerOrPet[spellId] == true
    end

    ---Test helper: mark a spell as known by the player or pet.
    ---@param spellId integer
    ---@param known boolean|nil
    function Spell.SetKnownByPlayerOrPetForTests(spellId, known)
        knownByPlayerOrPet[spellId] = known == true
    end

    ---Localized name of the player's interrupt spell, or nil when unset in tests.
    ---@return string|nil
    function Spell.GetInterruptName()
        return interruptName
    end

    ---Test helper: set the name returned by GetInterruptName.
    ---@param name string|nil
    function Spell.SetInterruptNameForTests(name)
        interruptName = name
    end

    ---@param spellId integer
    ---@return string|nil
    function Spell.GetName(spellId)
        if type(spellId) ~= "number" or spellId <= 0 then
            return nil
        end
        return names[spellId]
    end

    ---Test helper: register a name for a spell ID.
    ---@param spellId integer
    ---@param name string|nil
    function Spell.SetNameForTests(spellId, name)
        names[spellId] = name
    end

    ---Spell icon texture (path or file id), or nil when unset in tests.
    ---@param spellId integer
    ---@return integer|string|nil
    function Spell.GetTexture(spellId)
        if type(spellId) ~= "number" or spellId <= 0 then
            return nil
        end
        return textures[spellId]
    end

    ---Test helper: register a texture for a spell ID.
    ---@param spellId integer
    ---@param texture integer|string|nil
    function Spell.SetTextureForTests(spellId, texture)
        textures[spellId] = texture
    end

    local function AddCallback(list, callback)
        table.insert(list, callback)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            for index, candidate in ipairs(list) do
                if candidate == callback then
                    table.remove(list, index)
                    break
                end
            end
        end
    end

    local function FireCallbacks(list, ...)
        local snapshot = {}
        for i = 1, #list do
            snapshot[i] = list[i]
        end
        for i = 1, #snapshot do
            local callback = snapshot[i]
            if callback then
                callback(...)
            end
        end
    end

    ---@param callback fun(unitTarget: string, castGUID: string, spellID: number)
    ---@return fun()
    function Spell.OnCastStart(callback)
        return AddCallback(castStartCallbacks, callback)
    end

    ---@param callback fun(unitTarget: string, castGUID: string, spellID: number)
    ---@return fun()
    function Spell.OnCastStop(callback)
        return AddCallback(castStopCallbacks, callback)
    end

    ---Test helper: whether any UNIT_SPELLCAST_START listeners remain.
    function Spell.HasCastStartListener()
        return #castStartCallbacks > 0
    end

    ---Test helper: whether any UNIT_SPELLCAST_STOP listeners remain.
    function Spell.HasCastStopListener()
        return #castStopCallbacks > 0
    end

    ---Test helper: fire UNIT_SPELLCAST_START.
    function Spell.FireCastStart(unit, castGUID, spellID)
        FireCallbacks(castStartCallbacks, unit, castGUID, spellID)
    end

    ---Test helper: fire UNIT_SPELLCAST_STOP.
    function Spell.FireCastStop(unit, castGUID, spellID)
        FireCallbacks(castStopCallbacks, unit, castGUID, spellID)
    end

    ---@param unit string
    ---@param callback fun(unitTarget: string, castGUID: string, spellID: number, castBarID: number|nil)
    ---@return fun()
    function Spell.OnUnitChannelStart(unit, callback)
        return AddUnitCallback(channelStartCallbacks, unit, callback)
    end

    ---@param unit string
    ---@param callback fun(unitTarget: string, castGUID: string, spellID: number, interruptedBy: string|nil, castBarID: number|nil)
    ---@return fun()
    function Spell.OnUnitChannelStop(unit, callback)
        return AddUnitCallback(channelStopCallbacks, unit, callback)
    end

    ---Test helper: whether any channel-start listeners remain for `unit`.
    function Spell.HasChannelStartListener(unit)
        local list = channelStartCallbacks[unit]
        return list ~= nil and #list > 0
    end

    ---Test helper: whether any channel-stop listeners remain for `unit`.
    function Spell.HasChannelStopListener(unit)
        local list = channelStopCallbacks[unit]
        return list ~= nil and #list > 0
    end

    ---Test helper: fire UNIT_SPELLCAST_CHANNEL_START for a unit.
    function Spell.FireChannelStart(unit, castGUID, spellID, castBarID)
        local list = channelStartCallbacks[unit] or {}
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(unit, castGUID, spellID, castBarID)
            end
        end
    end

    ---Test helper: fire UNIT_SPELLCAST_CHANNEL_STOP for a unit.
    function Spell.FireChannelStop(unit, castGUID, spellID, interruptedBy, castBarID)
        local list = channelStopCallbacks[unit] or {}
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(unit, castGUID, spellID, interruptedBy, castBarID)
            end
        end
    end

    return Spell
end

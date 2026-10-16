return function()
    local Aura = {
        UNIT_PLAYER = "player",
        UNIT_TARGET = "target",
        UNIT_FOCUS = "focus",
        FILTER_HELPFUL = "HELPFUL",
        FILTER_HARMFUL = "HARMFUL",
        supported = true,
    }

    local supported = {
        player = { HELPFUL = true },
        target = { HARMFUL = true },
        focus = { HARMFUL = true },
    }

    function Aura.IsSupportedSource(unit, auraType)
        local auraTypes = supported[unit]
        return auraTypes ~= nil and auraTypes[auraType] == true
    end

    -- Tests load api/Aura.lua (see REAL_API_FILES). These stay so the fake file still defines the API.
    function Aura.CanApplyIncludeSpellFilter(unit, auraType)
        return Aura.IsSupportedSource(unit, auraType) and unit == Aura.UNIT_PLAYER
    end

    function Aura.OnUnitContextChanged(_callback) end

    function Aura.EnsureLoaded()
        return true
    end

    function Aura.IsSupported()
        return Aura.supported == true
    end

    ---@param spellId integer
    ---@return table
    function Aura.BuildIncludeSpellFilters(spellId)
        return {
            includeSpellIDs = { [spellId] = true },
        }
    end

    function Aura.GetExpirationSort()
        return "Expiration", "Normal"
    end

    function Aura.GetDurationBarOptions()
        return { direction = 1 }
    end

    ---@param maxApplications integer
    ---@return table
    function Aura.GetApplicationBarOptions(maxApplications)
        return { maxApplications = maxApplications }
    end

    function Aura.GetDurationTextOptions()
        return { textFormatter = "fake" }
    end

    function Aura.GetApplicationCountOptions()
        return { formatter = "fake" }
    end

    return Aura
end

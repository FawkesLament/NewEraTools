return function()
    local Aura = {
        UNIT_PLAYER = "player",
        FILTER_HELPFUL = "HELPFUL",
        supported = true,
    }

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

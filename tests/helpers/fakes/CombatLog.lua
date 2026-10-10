return function()
    local CombatLog = {
        -- nil means unknown (rate-limited); true/false are definitive.
        logging = false,
        -- When true, SetLogging returns nil without changing state (API rate limit).
        setRateLimited = false,
    }

    function CombatLog.IsLogging()
        return CombatLog.logging
    end

    ---@param enabled boolean
    ---@return boolean|nil
    function CombatLog.SetLogging(enabled)
        if CombatLog.setRateLimited then
            return nil
        end
        CombatLog.logging = enabled == true
        return CombatLog.logging
    end

    return CombatLog
end

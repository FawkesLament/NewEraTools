local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Player = ns.Api.Player
local Spell = ns.Api.Spell

local TwinFangs = ns.Modules.Get("TwinFangs")
local Chain = Internals.InterruptChain

local REPORT_TEXT = L.TWIN_FANGS_INTERRUPT_MACRO_REPORT
local BACKUP_REPORT_TEXT = L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT

---@return TwinFangsInterruptChainSettings|nil
local function SavedChain()
    return TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
end

---@return TwinFangsInterruptMemberAssignment|nil
local function PrimaryAssignment()
    return Chain.GetMemberView(SavedChain(), Chain.ResolveLocalPlayerName()).primary
end

---Same-realm whispers omit the realm; cross-realm keeps the cached suffix.
---@param name string
---@return string
local function WhisperTarget(name)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if not short then
        return name
    end
    local playerName = Player.GetFullName()
    local playerRealm = playerName and playerName:match("%-(.+)$")
    if playerRealm and realm == playerRealm then
        return short
    end
    return name
end

---@return string
local function SpellName()
    local spell = Spell.GetInterruptName()
    if type(spell) == "string" and spell ~= "" then
        return spell
    end
    return L.TWIN_FANGS_INTERRUPT_MACRO_SPELL_PLACEHOLDER
end

---Expected body for the current player's primary assignment, or nil.
---@return string|nil
---@return string|nil reason
function TwinFangs:GetInterruptMacroBody()
    local assignment = PrimaryAssignment()
    if not assignment then
        return nil, "unassigned"
    end

    local lines = {
        "#showtooltip",
        "/cast " .. SpellName(),
        "/p " .. REPORT_TEXT,
    }
    local chain = SavedChain()
    local region = chain and chain[assignment.regionId]
    if region and region.backup ~= nil then
        local name = Chain.PlayerName(region.backup)
        if name then
            lines[#lines + 1] = "/w " .. WhisperTarget(name) .. " " .. BACKUP_REPORT_TEXT
        end
    end

    return table.concat(lines, "\n")
end

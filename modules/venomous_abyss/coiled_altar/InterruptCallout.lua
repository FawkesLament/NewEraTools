local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local CalloutManager = ns.CalloutManager

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local CALLOUT_SOURCE = "CoiledAltar"

CoiledAltar.INTERRUPT_CALLOUT_DURATION = 10

---@class CoiledAltarInterruptCalloutTask
---@field wave CoiledAltarWave
---@field chainId CoiledAltarInterruptChainId
---@field round integer

---@class CoiledAltarPresentedInterruptCallout
---@field wave CoiledAltarWave
---@field chainId CoiledAltarInterruptChainId
---@field round integer
---@field handle CalloutManagerHandle|nil

---@type CoiledAltarPresentedInterruptCallout|nil
local presented = nil

---@param firstIsMelee boolean
---@param memberIndex integer
---@return CoiledAltarInterruptChainId|nil
local function SideInWorld(firstIsMelee, memberIndex)
    local Assignments = Internals.InterruptAssignments
    if memberIndex == 1 then
        if firstIsMelee then
            return Assignments.MELEE
        end
        return Assignments.RANGED
    end
    if memberIndex == 2 then
        if firstIsMelee then
            return Assignments.RANGED
        end
        return Assignments.MELEE
    end
    return nil
end

---Read-only Callout task when the local player is definitely assigned the current interrupt.
---@param state CoiledAltarInterruptState|nil
---@param assignment CoiledAltarInterruptAssignment|nil
---@return CoiledAltarInterruptCalloutTask|nil
function Internals.ResolveInterruptCallout(state, assignment)
    if not state or state.disposed or not state.curWave then
        return nil
    end
    if type(assignment) ~= "table" or type(assignment.indices) ~= "table" or #assignment.indices == 0 then
        return nil
    end
    local Assignments = Internals.InterruptAssignments
    local States = Internals.InterruptStates
    local chainId = assignment.chainId
    if not Assignments.IsChain(chainId) then
        return nil
    end
    local wave = state.curWave
    if type(wave) ~= "table" or type(wave.members) ~= "table" then
        return nil
    end
    local memberCount = #wave.members
    if memberCount ~= 1 and memberCount ~= 2 then
        return nil
    end

    local assignedRounds = {}
    for index = 1, #assignment.indices do
        assignedRounds[assignment.indices[index]] = true
    end

        local firstMelee, secondMelee = States.GetPossibleWorlds(wave)
    local worlds = {}
    if firstMelee then
        worlds[#worlds + 1] = true
    end
    if secondMelee then
        worlds[#worlds + 1] = false
    end
    if #worlds == 0 then
        return nil
    end

    local round
    for worldIndex = 1, #worlds do
        local firstIsMelee = worlds[worldIndex]
        local foundRound
        for memberIndex = 1, memberCount do
            local shadow = wave.members[memberIndex]
            if shadow and States.IsLive(state, shadow) and shadow.casting == true then
                local side = SideInWorld(firstIsMelee, memberIndex)
                local candidate = (shadow.kicks or 0) + 1
                if side == chainId and assignedRounds[candidate] then
                    foundRound = candidate
                    break
                end
            end
        end
        if not foundRound then
            return nil
        end
        if round and round ~= foundRound then
            return nil
        end
        round = foundRound
    end

    return {
        wave = wave,
        chainId = chainId,
        round = round,
    }
end

---@param task CoiledAltarInterruptCalloutTask
---@return boolean
local function IsPresentedTask(task)
    return presented ~= nil
        and presented.wave == task.wave
        and presented.chainId == task.chainId
        and presented.round == task.round
end

local function HidePresented()
    if presented and presented.handle then
        presented.handle:Dismiss()
    end
    presented = nil
end

---Shows or hides the interrupt Callout from the current combat state.
function Internals.SyncInterruptCallout()
    if not CoiledAltar:IsInterruptReminderEnabled() then
        HidePresented()
        return
    end

    local task = Internals.ResolveInterruptCallout(
        Internals.InterruptStates.Get(),
        Internals.LocalInterruptAssignment()
    )
    if not task then
        HidePresented()
        return
    end
    if IsPresentedTask(task) then
        return
    end

    presented = {
        wave = task.wave,
        chainId = task.chainId,
        round = task.round,
        handle = CalloutManager.Show({
            source = CALLOUT_SOURCE,
            text = L.COILED_ALTAR_INTERRUPT_CALLOUT,
            duration = CoiledAltar.INTERRUPT_CALLOUT_DURATION,
            appendTimer = true,
        }),
    }
end

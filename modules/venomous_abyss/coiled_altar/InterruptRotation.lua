local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")

local CoiledAltar = ns.Modules.Get("CoiledAltar")

---@class CoiledAltarRotationTrackerView
---@field mode "hidden"|"normal"|"pending"
---@field chainId CoiledAltarInterruptChainId|nil
---@field indices integer[]|nil
---@field kicks integer|nil
---@field casting boolean|nil

---@param indices integer[]
---@return integer[]
local function CopyIndices(indices)
    local copy = {}
    for index = 1, #indices do
        copy[index] = indices[index]
    end
    return copy
end

---@param indices integer[]
---@return integer
local function ConsecutiveEnd(indices)
    local last = indices[1]
    for index = 2, #indices do
        if indices[index] ~= last + 1 then
            break
        end
        last = indices[index]
    end
    return last
end

---Read-only RotationTracker view for the local player's assignment.
---@param state CoiledAltarInterruptState|nil
---@param assignment CoiledAltarInterruptAssignment|nil
---@return CoiledAltarRotationTrackerView
function Internals.ResolveRotationTrackerView(state, assignment)
    if not state or state.disposed or not state.curWave then
        return { mode = "hidden" }
    end
    if type(assignment) ~= "table" or type(assignment.indices) ~= "table" or #assignment.indices == 0 then
        return { mode = "hidden" }
    end
    local Assignments = Internals.InterruptAssignments
    local States = Internals.InterruptStates
    local chainId = assignment.chainId
    if not Assignments.IsChain(chainId) then
        return { mode = "hidden" }
    end
    local wave = state.curWave
    if type(wave) ~= "table" or type(wave.members) ~= "table" then
        return { mode = "hidden" }
    end
    local memberCount = #wave.members
    if memberCount ~= 1 and memberCount ~= 2 then
        return { mode = "hidden" }
    end

    local firstMelee, secondMelee = States.GetPossibleWorlds(wave)
    local candidates = {}
    local function Consider(index)
        local shadow = wave.members[index]
        if shadow then
            candidates[#candidates + 1] = shadow
        end
    end
    if chainId == Assignments.MELEE then
        if firstMelee then
            Consider(1)
        end
        if secondMelee then
            Consider(2)
        end
    else
        if firstMelee then
            Consider(2)
        end
        if secondMelee then
            Consider(1)
        end
    end
    if #candidates == 0 then
        return { mode = "hidden" }
    end

    local indices = CopyIndices(assignment.indices)
    if #candidates == 1 then
        local shadow = candidates[1]
        if not States.IsLive(state, shadow) then
            return { mode = "hidden" }
        end
        return {
            mode = "normal",
            chainId = chainId,
            indices = indices,
            kicks = shadow.kicks,
            casting = shadow.casting == true,
        }
    end

    local kicks = candidates[1].kicks
    for index = 2, #candidates do
        if candidates[index].kicks ~= kicks then
            return {
                mode = "pending",
                chainId = chainId,
                indices = indices,
            }
        end
    end
    return {
        mode = "normal",
        chainId = chainId,
        indices = indices,
        kicks = kicks,
        casting = false,
    }
end

---@class CoiledAltarInterruptStatus
---@field chainId CoiledAltarInterruptChainId
---@field indices integer[]
---@field index integer
---@field indexEnd integer
---@field kicks integer|nil
---@field pending boolean
---@field chainLength integer
---@field casting boolean

---Local player's interrupt HUD snapshot for the current wave, or nil when it cannot be shown.
---@return CoiledAltarInterruptStatus|nil
function CoiledAltar:GetInterruptStatus()
    local Assignments = Internals.InterruptAssignments
    local view = Internals.ResolveRotationTrackerView(
        Internals.InterruptStates.Get(),
        Internals.LocalInterruptAssignment()
    )
    if view.mode == "hidden" then
        return nil
    end
    return {
        chainId = view.chainId,
        indices = view.indices,
        index = view.indices[1],
        indexEnd = ConsecutiveEnd(view.indices),
        kicks = view.kicks,
        pending = view.mode == "pending",
        chainLength = Assignments.SLOT_COUNT,
        casting = view.casting == true,
    }
end

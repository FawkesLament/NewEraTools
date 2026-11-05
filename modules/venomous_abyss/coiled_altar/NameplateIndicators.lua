local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Colors = ns.Assets.Colors
local Group = ns.Api.Group
local Player = ns.Api.Player

local CoiledAltar = ns.Modules.Get("CoiledAltar")

---@class CoiledAltarNameplateIndicatorView
---@field number integer
---@field name string
---@field classFile string|nil
---@field nameColor { r: number, g: number, b: number }|nil
---@field scheme "gold"|"pale_green"

local SCHEME_GOLD = "gold"
local SCHEME_PALE_GREEN = "pale_green"

---@param name string
---@return string
local function ShortName(name)
    return name:match("^([^-]+)") or name
end

---@param state CoiledAltarInterruptState
---@return boolean
local function HasLiveExpired(state)
    for i = 1, #state.list do
        if state.list[i].expired == true then
            return true
        end
    end
    return false
end

---@param wave CoiledAltarWave
---@param shadow CoiledAltarShadow
---@return integer|nil
local function MemberIndex(wave, shadow)
    local members = wave.members
    if type(members) ~= "table" then
        return nil
    end
    for i = 1, #members do
        if members[i] == shadow then
            return i
        end
    end
    return nil
end

---@param w1 boolean
---@param w2 boolean
---@param memberIndex integer
---@return CoiledAltarInterruptChainId|nil
local function UniqueSide(w1, w2, memberIndex)
    if w1 == w2 then
        return nil
    end
    local Assignments = Internals.InterruptAssignments
    if memberIndex == 1 then
        if w1 then
            return Assignments.MELEE
        end
        return Assignments.RANGED
    end
    if memberIndex == 2 then
        if w1 then
            return Assignments.RANGED
        end
        return Assignments.MELEE
    end
    return nil
end

---@return table<string, string>
local function ClassByPlayerName()
    local byName = {}
    local roster = Group.GetRaidMembers()
    for i = 1, #roster do
        local member = roster[i]
        if type(member.classFile) == "string" and member.classFile ~= "" then
            local qualified = Internals.InterruptAssignments.QualifyName(member.fullName or member.name)
            if qualified then
                byName[qualified] = member.classFile
            end
        end
    end
    local selfClass = Player.GetClassFile()
    if type(selfClass) == "string" and selfClass ~= "" then
        local qualified = Internals.InterruptAssignments.QualifyName(Player.GetFullName())
        if qualified and not byName[qualified] then
            byName[qualified] = selfClass
        end
    end
    return byName
end

---@param chains CoiledAltarInterruptAssignments|nil
---@param chainId CoiledAltarInterruptChainId
---@param round integer
---@param classByName table<string, string>
---@return string
---@return string|nil
---@return { r: number, g: number, b: number }|nil
local function AssignedDisplay(chains, chainId, round, classByName)
    local Assignments = Internals.InterruptAssignments
    local slot = Assignments.GetSlot(chains, chainId, round)
    if not slot then
        return "", nil, nil
    end
    if slot.type == Assignments.TYPE_TEXT then
        return slot.value or "", nil, Colors.TEXT_GOLD
    end
    if slot.type == Assignments.TYPE_PLAYER and type(slot.value) == "string" then
        return ShortName(slot.value), classByName[slot.value], nil
    end
    return "", nil, nil
end

---@param side CoiledAltarInterruptChainId|nil
---@return "gold"|"pale_green"
local function SchemeForSide(side)
    if side == Internals.InterruptAssignments.MELEE then
        return SCHEME_PALE_GREEN
    end
    return SCHEME_GOLD
end

---@param views table<string, CoiledAltarNameplateIndicatorView>
---@param unit string
---@param number integer
---@param name string
---@param classFile string|nil
---@param scheme "gold"|"pale_green"
---@param nameColor { r: number, g: number, b: number }|nil
local function Put(views, unit, number, name, classFile, scheme, nameColor)
    views[unit] = {
        number = number,
        name = name,
        classFile = classFile,
        nameColor = nameColor,
        scheme = scheme,
    }
end

---Read-only nameplate interrupt presentation derived from confirmed bindings and candidates.
---@param state CoiledAltarInterruptState|nil
---@param chains CoiledAltarInterruptAssignments|nil
---@return table<string, CoiledAltarNameplateIndicatorView>
function Internals.ResolveNameplateIndicators(state, chains)
    local views = {}
    if not state or state.disposed or not state.curWave then
        return views
    end
    local States = Internals.InterruptStates
    local wave = state.curWave
    if type(wave) ~= "table" or type(wave.members) ~= "table" then
        return views
    end

    local pendingName = L.COILED_ALTAR_INTERRUPT_INDICATOR_PENDING
    local overlapping = HasLiveExpired(state)
    local classByName = ClassByPlayerName()

    for plate, owner in pairs(state.plateOwner) do
        if owner and owner.wave == wave and States.IsLive(state, owner) and owner.expired ~= true then
            local round = (owner.kicks or 0) + 1
            local w1, w2 = States.GetPossibleWorlds(owner.wave)
            local index = MemberIndex(owner.wave, owner)
            local side = index and UniqueSide(w1, w2, index)
            if side then
                local name, classFile, nameColor = AssignedDisplay(chains, side, round, classByName)
                Put(views, plate, round, name, classFile, SchemeForSide(side), nameColor)
            else
                Put(views, plate, round, pendingName, nil, SCHEME_GOLD)
            end
        end
    end

    if overlapping then
        return views
    end

    local members = wave.members
    local memberCount = #members
    if memberCount ~= 1 and memberCount ~= 2 then
        return views
    end
    for i = 1, memberCount do
        if not States.IsLive(state, members[i]) then
            return views
        end
    end
    local kicks = members[1].kicks
    for i = 2, memberCount do
        if members[i].kicks ~= kicks then
            return views
        end
    end

    local unboundMembers = 0
    for i = 1, memberCount do
        if members[i].plate == nil then
            unboundMembers = unboundMembers + 1
        end
    end
    if unboundMembers == 0 then
        return views
    end

    local candidates = state.candidates
    if type(candidates) ~= "table" then
        return views
    end

    local unboundPlates = {}
    local markedPlates = 0
    for plate, marked in pairs(candidates) do
        if not state.plateOwner[plate] then
            unboundPlates[#unboundPlates + 1] = plate
            if marked == true then
                markedPlates = markedPlates + 1
            end
        end
    end

    local ambiguous = #unboundPlates > unboundMembers
    local bothMembersMarked = memberCount == 2
        and members[1].marked == true
        and members[2].marked == true
    local anyMemberMarked = false
    for i = 1, memberCount do
        if members[i].marked == true then
            anyMemberMarked = true
            break
        end
    end
    local round = (kicks or 0) + 1
    local markedSide = Internals.MarkedChain()
    local unmarkedSide = Internals.InterruptAssignments.OppositeChain(markedSide)
    local singleSide
    if memberCount == 1 then
        local w1, w2 = States.GetPossibleWorlds(wave)
        singleSide = UniqueSide(w1, w2, 1)
    end

    for i = 1, #unboundPlates do
        local plate = unboundPlates[i]
        local marked = candidates[plate] == true
        local side
        if not ambiguous then
            if memberCount == 1 then
                side = singleSide
            elseif markedPlates >= 2 or bothMembersMarked then
                side = nil
            elseif marked then
                side = markedSide
            elseif markedPlates == 1 or anyMemberMarked then
                side = unmarkedSide
            end
        end
        if side then
            local name, classFile, nameColor = AssignedDisplay(chains, side, round, classByName)
            Put(views, plate, round, name, classFile, SchemeForSide(side), nameColor)
        else
            Put(views, plate, round, pendingName, nil, SCHEME_GOLD)
        end
    end
    return views
end

---Pushes the current combat indicator views to the nameplate UI, if it is loaded.
function Internals.SyncNameplateIndicators()
    local desired = {}
    if CoiledAltar:IsNameplateHintEnabled() then
        local state = Internals.InterruptStates.Get()
        if state and not state.disposed then
            desired = Internals.ResolveNameplateIndicators(state, CoiledAltar:GetInterruptAssignments())
        end
    end
    if CoiledAltar.OnNameplateHintApply then
        CoiledAltar:OnNameplateHintApply(desired)
    end
end

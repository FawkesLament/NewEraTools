local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Encounter = ns.Api.Encounter
local Nameplate = ns.Api.Nameplate
local RaidTarget = ns.Api.RaidTarget
local Secrets = ns.Api.Secrets
local Spell = ns.Api.Spell
local Timer = ns.Api.Timer
local Unit = ns.Api.Unit

-- Shadows occupy consecutive boss tokens starting here. boss1/boss2 are the main bosses.
local FIRST_SHADOW_BOSS = 3
local SHADOW_LEVEL = 92
local START = "START"
local INTERRUPTED = "INTERRUPTED"
local STOP = "STOP"
local SUCCEEDED = "SUCCEEDED"

---@class CoiledAltarShadow
---@field wave CoiledAltarWave
---@field expired boolean
---@field marked boolean
---@field kicks integer
---@field casting boolean
---@field plate string|nil

---@class CoiledAltarWave
---@field members CoiledAltarShadow[]

---@class CoiledAltarInterruptBatch
---@field engage boolean
---@field bossEvents { kind: string, unit: string, hasCastGUID: boolean }[]
---@field plateEvents { kind: string, unit: string, hasCastGUID: boolean }[]
---@field deathSignals CoiledAltarShadow[]
---@field removedOwners CoiledAltarShadow[]
---@field removedPlates table<string, boolean>

---@class CoiledAltarInterruptState
---@field list CoiledAltarShadow[]
---@field plateOwner table<string, CoiledAltarShadow>
---@field candidates table<string, boolean>  Unbound level-92 nameplates; value is whether the plate currently has a raid marker.
---@field curWave CoiledAltarWave|nil
---@field batch CoiledAltarInterruptBatch|nil
---@field requestFlush fun()|nil
---@field flushScheduled boolean|nil
---@field disposed boolean|nil
---@field onStateChanged fun(state: CoiledAltarInterruptState)|nil

local States = {}
Internals.InterruptStates = States

---@type CoiledAltarInterruptState|nil
local current = nil

---@return CoiledAltarInterruptState|nil
function States.Get()
    return current
end

---@return CoiledAltarInterruptState
function States.New()
    return {
        list = {},
        plateOwner = {},
        candidates = {},
        curWave = nil,
        batch = nil,
    }
end

---@param wave CoiledAltarWave|nil
---@return boolean w1  First member may be melee when marked shadows use the melee chain.
---@return boolean w2  Second member may be melee when marked shadows use the melee chain.
local function PossibleWorldsForMarkedMelee(wave)
    if type(wave) ~= "table" or type(wave.members) ~= "table" then
        return true, true
    end
    local first = wave.members[1]
    local second = wave.members[2]
    if not first then
        return true, true
    end
    -- A 1-add wave has no pair; the marked chain takes the add when it is marked.
    if not second then
        if first.marked == true then
            return true, false
        end
        return false, true
    end
    local aMarked = first.marked == true
    local bMarked = second.marked == true
    if aMarked and not bMarked then
        return true, false
    end
    if bMarked and not aMarked then
        return false, true
    end
    return true, true
end

---@param wave CoiledAltarWave|nil
---@return boolean w1  First member may be melee.
---@return boolean w2  Second member may be melee.
function States.GetPossibleWorlds(wave)
    local w1, w2 = PossibleWorldsForMarkedMelee(wave)
    if Internals.MarkedChain() == Internals.InterruptAssignments.RANGED then
        return w2, w1
    end
    return w1, w2
end

---@param unit any
---@return integer|nil
local function ShadowBossIndex(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = tonumber(unit:match("^boss(%d+)$"))
    if not index or index < FIRST_SHADOW_BOSS then
        return nil
    end
    return index
end

---@param unit any
---@return integer|nil
local function ListIndexForUnit(unit)
    local bossIndex = ShadowBossIndex(unit)
    if not bossIndex then
        return nil
    end
    return bossIndex - FIRST_SHADOW_BOSS + 1
end

---@param listIndex integer
---@return string
local function BossTokenForListIndex(listIndex)
    return "boss" .. (listIndex + FIRST_SHADOW_BOSS - 1)
end

---@return integer
local function CountShadowBosses()
    local n = 0
    local bossIndex = FIRST_SHADOW_BOSS
    while Unit.Exists("boss" .. bossIndex) do
        n = n + 1
        bossIndex = bossIndex + 1
    end
    return n
end

---@param unit any
---@return boolean
local function IsShadowPlate(unit)
    return Nameplate.IsUnitToken(unit) and Unit.GetLevel(unit) == SHADOW_LEVEL
end

---@param wave CoiledAltarWave
---@return CoiledAltarShadow
local function NewShadow(wave)
    return {
        wave = wave,
        expired = false,
        marked = false,
        kicks = 0,
        casting = false,
        plate = nil,
    }
end

---@return CoiledAltarInterruptBatch
local function NewBatch()
    return {
        engage = false,
        bossEvents = {},
        plateEvents = {},
        deathSignals = {},
        removedOwners = {},
        removedPlates = {},
    }
end

---@param state CoiledAltarInterruptState
local function NotifyStateChanged(state)
    if state.disposed then
        return
    end
    local callback = state.onStateChanged
    if callback then
        callback(state)
    end
end

---@param state CoiledAltarInterruptState
---@return CoiledAltarInterruptBatch|nil
local function EnsureBatch(state)
    if state.disposed then
        return nil
    end
    if state.batch then
        return state.batch
    end
    local batch = NewBatch()
    state.batch = batch
    if state.requestFlush then
        state.requestFlush()
    end
    return batch
end

---@param state CoiledAltarInterruptState
---@param plate string
local function UnbindPlate(state, plate)
    local owner = state.plateOwner[plate]
    if not owner then
        return
    end
    state.plateOwner[plate] = nil
    if owner.plate == plate then
        owner.plate = nil
    end
    assert(state.plateOwner[plate] == nil)
    assert(owner.plate ~= plate)
end

---@param state CoiledAltarInterruptState
---@param object CoiledAltarShadow
---@param plate string
local function BindPlate(state, object, plate)
    if object.plate == plate and state.plateOwner[plate] == object then
        return
    end
    if object.plate then
        UnbindPlate(state, object.plate)
    end
    if state.plateOwner[plate] then
        UnbindPlate(state, plate)
    end
    object.plate = plate
    state.plateOwner[plate] = object
    state.candidates[plate] = nil
    assert(state.plateOwner[plate] == object)
    assert(object.plate == plate)
    assert(state.candidates[plate] == nil)
end

---@param state CoiledAltarInterruptState
local function RefreshLiveMarks(state)
    for i = 1, #state.list do
        state.list[i].marked = RaidTarget.GetIndex(BossTokenForListIndex(i)) ~= nil
    end
end

---@param state CoiledAltarInterruptState
local function RefreshCandidateMarks(state)
    for plate in pairs(state.candidates) do
        state.candidates[plate] = RaidTarget.GetIndex(plate) ~= nil
    end
end

---@param state CoiledAltarInterruptState
---@param object CoiledAltarShadow
---@return boolean
local function IsLive(state, object)
    for i = 1, #state.list do
        if state.list[i] == object then
            return true
        end
    end
    return false
end

---@param state CoiledAltarInterruptState
---@param object CoiledAltarShadow|nil
---@return boolean
function States.IsLive(state, object)
    return object ~= nil and IsLive(state, object)
end

---@param state CoiledAltarInterruptState
---@param objects CoiledAltarShadow[]
---@return CoiledAltarShadow|nil
local function UniqueLive(state, objects)
    local unique
    local count = 0
    local seen = {}
    for i = 1, #objects do
        local object = objects[i]
        if object and not seen[object] and IsLive(state, object) then
            seen[object] = true
            unique = object
            count = count + 1
        end
    end
    if count == 1 then
        return unique
    end
    return nil
end

---@param flags boolean[]
---@param index integer
---@return boolean[]
local function RemoveAt(flags, index)
    local out = {}
    for i = 1, #flags do
        if i ~= index then
            out[#out + 1] = flags[i]
        end
    end
    return out
end

---@param left boolean[]
---@param right boolean[]
---@return boolean
local function SameFlags(left, right)
    if #left ~= #right then
        return false
    end
    for i = 1, #left do
        if left[i] ~= right[i] then
            return false
        end
    end
    return true
end

---@param candidates CoiledAltarShadow[]
---@return CoiledAltarShadow|nil
local function FallbackDead(candidates)
    local lastExpired
    local last
    for i = 1, #candidates do
        local object = candidates[i]
        last = object
        if object.expired then
            lastExpired = object
        end
    end
    return lastExpired or last
end

---@param state CoiledAltarInterruptState
---@param n integer
---@return CoiledAltarShadow[]
local function MarkerMatches(state, n)
    local cached = {}
    for i = 1, #state.list do
        cached[i] = state.list[i].marked == true
    end
    local observed = {}
    for i = 1, n do
        observed[i] = RaidTarget.GetIndex(BossTokenForListIndex(i)) ~= nil
    end
    local matches = {}
    for i = 1, #state.list do
        if SameFlags(RemoveAt(cached, i), observed) then
            matches[#matches + 1] = state.list[i]
        end
    end
    return matches
end

---@param state CoiledAltarInterruptState
---@param n integer
---@param batch CoiledAltarInterruptBatch
---@return CoiledAltarShadow|nil
local function IdentifyDead(state, n, batch)
    local unique = UniqueLive(state, batch.deathSignals)
    if unique then
        return unique
    end
    unique = UniqueLive(state, batch.removedOwners)
    if unique then
        return unique
    end
    local matches = MarkerMatches(state, n)
    if #matches == 1 then
        return matches[1]
    end
    if #matches > 1 then
        return FallbackDead(matches)
    end
    return FallbackDead(state.list)
end

---@param state CoiledAltarInterruptState
---@param dead CoiledAltarShadow
local function RemoveDead(state, dead)
    for i = 1, #state.list do
        if state.list[i] == dead then
            table.remove(state.list, i)
            break
        end
    end
    if dead.plate then
        UnbindPlate(state, dead.plate)
    end
    local wave = dead.wave
    local found = false
    if wave then
        for i = 1, #wave.members do
            if wave.members[i] == dead then
                found = true
                break
            end
        end
    end
    assert(found, "dead shadow missing from wave.members")
end

---@param state CoiledAltarInterruptState
---@param added integer
local function SpawnWave(state, added)
    for i = 1, #state.list do
        state.list[i].expired = true
    end
    local wave = { members = {} }
    for _ = 1, added do
        local object = NewShadow(wave)
        wave.members[#wave.members + 1] = object
        state.list[#state.list + 1] = object
    end
    state.curWave = wave
end

---@param state CoiledAltarInterruptState
---@param batch CoiledAltarInterruptBatch
local function Reconcile(state, batch)
    local n = CountShadowBosses()
    local count = #state.list
    if n > count then
        SpawnWave(state, n - count)
    elseif n < count then
        local dead = IdentifyDead(state, n, batch)
        if dead then
            RemoveDead(state, dead)
        end
    end
    RefreshLiveMarks(state)
    RefreshCandidateMarks(state)
end

---@param events { kind: string, unit: string, hasCastGUID: boolean }[]
---@param kind string
---@return { kind: string, unit: string, hasCastGUID: boolean }[]
local function EligibleEvents(events, kind)
    local list = {}
    for i = 1, #events do
        local event = events[i]
        if event.kind == kind and (kind ~= START or event.hasCastGUID) then
            list[#list + 1] = event
        end
    end
    return list
end

---@param state CoiledAltarInterruptState
---@param batch CoiledAltarInterruptBatch
---@param kind string
local function PairEvents(state, batch, kind)
    local bosses = EligibleEvents(batch.bossEvents, kind)
    local plates = EligibleEvents(batch.plateEvents, kind)
    local usedBoss = {}
    local usedPlate = {}
    for i = 1, #bosses do
        local listIndex = ListIndexForUnit(bosses[i].unit)
        local object = listIndex and state.list[listIndex]
        local plate = object and object.plate
        if plate then
            for j = 1, #plates do
                if not usedPlate[j] and plates[j].unit == plate then
                    usedBoss[i] = true
                    usedPlate[j] = true
                    break
                end
            end
        end
    end
    local unmatchedBosses = {}
    local unmatchedPlates = {}
    for i = 1, #bosses do
        if not usedBoss[i] then
            unmatchedBosses[#unmatchedBosses + 1] = bosses[i]
        end
    end
    for j = 1, #plates do
        if not usedPlate[j] then
            unmatchedPlates[#unmatchedPlates + 1] = plates[j]
        end
    end
    if #unmatchedBosses ~= 1 or #unmatchedPlates ~= 1 then
        return
    end
    local plate = unmatchedPlates[1].unit
    if batch.removedPlates[plate] then
        return
    end
    local listIndex = ListIndexForUnit(unmatchedBosses[1].unit)
    local object = listIndex and state.list[listIndex]
    if object then
        BindPlate(state, object, plate)
    end
end

---@param state CoiledAltarInterruptState
---@param event { kind: string, unit: string, hasCastGUID: boolean }
local function ApplyBossEvent(state, event)
    local listIndex = ListIndexForUnit(event.unit)
    local object = listIndex and state.list[listIndex]
    if not object then
        return
    end
    if event.kind == START then
        object.casting = true
    elseif event.kind == INTERRUPTED then
        object.casting = false
        object.kicks = object.kicks + 1
    elseif event.kind == STOP or event.kind == SUCCEEDED then
        object.casting = false
    end
end

function States.Flush(state)
    local batch = state.batch
    if not batch then
        return
    end
    state.batch = nil
    if batch.engage then
        Reconcile(state, batch)
    end
    PairEvents(state, batch, START)
    PairEvents(state, batch, INTERRUPTED)
    for i = 1, #batch.bossEvents do
        ApplyBossEvent(state, batch.bossEvents[i])
    end
    NotifyStateChanged(state)
end

function States.OnEngage(state)
    local batch = EnsureBatch(state)
    if batch then
        batch.engage = true
    end
end

---@param state CoiledAltarInterruptState
---@param kind string
---@param unit any
---@param hasCastGUID boolean
---@param hasArg3 boolean
function States.OnCast(state, kind, unit, hasCastGUID, hasArg3)
    if Secrets.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    if ShadowBossIndex(unit) then
        local batch = EnsureBatch(state)
        if not batch then
            return
        end
        batch.bossEvents[#batch.bossEvents + 1] = {
            kind = kind,
            unit = unit,
            hasCastGUID = hasCastGUID == true,
        }
        return
    end
    if not IsShadowPlate(unit) then
        return
    end
    if kind == INTERRUPTED and not hasArg3 then
        local owner = state.plateOwner[unit]
        if owner then
            local batch = EnsureBatch(state)
            if batch then
                batch.deathSignals[#batch.deathSignals + 1] = owner
            end
        end
        return
    end
    if kind ~= START and kind ~= INTERRUPTED then
        return
    end
    if kind == START and not hasCastGUID then
        return
    end
    local batch = EnsureBatch(state)
    if not batch then
        return
    end
    batch.plateEvents[#batch.plateEvents + 1] = {
        kind = kind,
        unit = unit,
        hasCastGUID = hasCastGUID == true,
    }
end

---@param state CoiledAltarInterruptState
---@param unit any
function States.OnNameplateAdded(state, unit)
    if Secrets.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    if not Nameplate.IsUnitToken(unit) then
        return
    end
    local hadOwner = state.plateOwner[unit] ~= nil
    local wasCandidate = state.candidates[unit] ~= nil
    UnbindPlate(state, unit)
    state.candidates[unit] = nil
    local added = false
    if IsShadowPlate(unit) then
        state.candidates[unit] = RaidTarget.GetIndex(unit) ~= nil
        added = true
    end
    if hadOwner or wasCandidate or added then
        NotifyStateChanged(state)
    end
end

function States.OnNameplateRemoved(state, unit)
    if Secrets.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    local owner = state.plateOwner[unit]
    if owner then
        local batch = EnsureBatch(state)
        if batch then
            batch.removedOwners[#batch.removedOwners + 1] = owner
            batch.removedPlates[unit] = true
        end
        UnbindPlate(state, unit)
    end
    local wasCandidate = state.candidates[unit] ~= nil
    state.candidates[unit] = nil
    if owner or wasCandidate then
        NotifyStateChanged(state)
    end
end

function States.OnRaidTargetChanged(state)
    if state.batch and state.batch.engage then
        return
    end
    RefreshLiveMarks(state)
    RefreshCandidateMarks(state)
    NotifyStateChanged(state)
end

---@param scope ResourceScope
---@param onStateChanged fun(state: CoiledAltarInterruptState)|{ onStateChanged: fun(state: CoiledAltarInterruptState) }|nil
---@return CoiledAltarInterruptState
function States.Start(scope, onStateChanged)
    local state = States.New()
    state.disposed = false
    state.flushScheduled = false
    if type(onStateChanged) == "function" then
        state.onStateChanged = onStateChanged
    elseif type(onStateChanged) == "table" and type(onStateChanged.onStateChanged) == "function" then
        state.onStateChanged = onStateChanged.onStateChanged
    end

    local function RequestFlush()
        if state.flushScheduled or state.disposed then
            return
        end
        state.flushScheduled = true
        Timer.After(0, function()
            state.flushScheduled = false
            if state.disposed then
                return
            end
            States.Flush(state)
        end)
    end

    state.requestFlush = RequestFlush

    local function OnCast(kind)
        return function(unit, castGUID, spellID)
            States.OnCast(state, kind, unit, castGUID ~= nil, spellID ~= nil)
        end
    end

    scope:Subscribe(Encounter.OnEngageUnit, function()
        States.OnEngage(state)
    end)
    scope:Subscribe(Spell.OnCastStart, OnCast(START))
    scope:Subscribe(Spell.OnCastInterrupted, OnCast(INTERRUPTED))
    scope:Subscribe(Spell.OnCastStop, OnCast(STOP))
    scope:Subscribe(Spell.OnCastSucceeded, OnCast(SUCCEEDED))
    scope:Subscribe(RaidTarget.OnChanged, function()
        States.OnRaidTargetChanged(state)
    end)
    scope:Subscribe(Nameplate.OnAdded, function(unit)
        States.OnNameplateAdded(state, unit)
    end)
    scope:Subscribe(Nameplate.OnRemoved, function(unit)
        States.OnNameplateRemoved(state, unit)
    end)
    current = state
    scope:Add(function()
        state.disposed = true
        state.batch = nil
        state.onStateChanged = nil
        if current == state then
            current = nil
        end
    end)

    return state
end

local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local InterruptChain = Internals.InterruptChain

---Only the raid leader can edit the chain; everyone else is member-view only.
---@return boolean
function InterruptChain.CanEdit()
    return ns.Api.Group.IsPlayerRaidLeader()
end

---Picks the settings chain view. Only the raid leader sees the Editor and the view switch.
---@param canEdit boolean
---@param preferMemberView boolean
---@return boolean showEditor
---@return boolean preferMemberView
function InterruptChain.ResolveSettingsView(canEdit, preferMemberView)
    if not canEdit then
        return false, false
    end
    return not preferMemberView, preferMemberView
end

---@param state TwinFangsInterruptChainState
---@param region TwinFangsInterruptChainRegion
---@param group number|nil
local function ApplyGroup(state, region, group)
    region.group = group
    local kept = {}
    if InterruptChain.IsRaidGroup(group) then
        for _, player in ipairs(region.players) do
            local member = InterruptChain.FindMemberByName(state, player.name)
            if member and member.subgroup == group then
                kept[#kept + 1] = player
            end
        end
    end
    region.players = kept
    if region.backup then
        local backup = InterruptChain.FindMemberByName(state, region.backup.name)
        if not backup or (InterruptChain.IsRaidGroup(group) and backup.subgroup == group) then
            region.backup = nil
        end
    end
end

---@param left TwinFangsInterruptChainRegion
---@param right TwinFangsInterruptChainRegion
local function SwapRegions(left, right)
    left.group, right.group = right.group, left.group
    left.players, right.players = right.players, left.players
    left.backup, right.backup = right.backup, left.backup
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param group number
---@return boolean
function InterruptChain.SetGroup(state, regionId, group)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    if not InterruptChain.IsRaidGroup(group) or region.group == group then
        return false
    end
    for _, otherId in ipairs(InterruptChain.REGION_IDS) do
        if otherId ~= regionId and state.regions[otherId].group == group then
            SwapRegions(region, state.regions[otherId])
            state.dirty = true
            return true
        end
    end
    ApplyGroup(state, region, group)
    state.dirty = true
    return true
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@return RaidMember[]
function InterruptChain.GetAddablePlayers(state, regionId)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local addable = {}
    for _, member in ipairs(state.roster) do
        if
            member.subgroup == region.group
            and type(member.guid) == "string"
            and not InterruptChain.PrimaryRegionOf(state, member.fullName or member.name)
        then
            addable[#addable + 1] = member
        end
    end
    return addable
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@return RaidMember[]
function InterruptChain.GetBackupCandidates(state, regionId)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local candidates = {}
    for _, member in ipairs(state.roster) do
        if member.subgroup ~= region.group and type(member.guid) == "string" then
            local usedBy = InterruptChain.BackupRegionOf(state, member.fullName or member.name)
            if not usedBy or usedBy == regionId then
                candidates[#candidates + 1] = member
            end
        end
    end
    return candidates
end

---@param state TwinFangsInterruptChainState
---@return number[]
function InterruptChain.GetPresentGroups(state)
    local seen = {}
    local groups = {}
    for _, member in ipairs(state.roster) do
        local group = member.subgroup
        if InterruptChain.IsRaidGroup(group) and not seen[group] then
            seen[group] = true
            groups[#groups + 1] = group
        end
    end
    table.sort(groups)
    return groups
end

---Raid groups that exist in the roster, plus this region's current assignment so the dropdown can show it.
---@param state TwinFangsInterruptChainState
---@param regionId string
---@return number[]
function InterruptChain.GetAssignableGroups(state, regionId)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local seen = {}
    local groups = {}
    for _, group in ipairs(InterruptChain.GetPresentGroups(state)) do
        seen[group] = true
        groups[#groups + 1] = group
    end
    if InterruptChain.IsRaidGroup(region.group) and not seen[region.group] then
        groups[#groups + 1] = region.group
        table.sort(groups)
    end
    return groups
end

---@param state TwinFangsInterruptChainState
---@param group number
---@return string|nil
function InterruptChain.AssignedRegion(state, group)
    if not InterruptChain.IsRaidGroup(group) then
        return nil
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        if state.regions[regionId].group == group then
            return regionId
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param group number
---@return boolean
function InterruptChain.IsGroupAssignedElsewhere(state, regionId, group)
    local owner = InterruptChain.AssignedRegion(state, group)
    return owner ~= nil and owner ~= regionId
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@return number[]
function InterruptChain.GetBackupGroups(state, regionId)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local groups = {}
    for _, group in ipairs(InterruptChain.GetPresentGroups(state)) do
        if group ~= region.group then
            groups[#groups + 1] = group
        end
    end
    return groups
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param group number
---@return RaidMember[]
function InterruptChain.GetBackupPlayers(state, regionId, group)
    if not InterruptChain.IsRaidGroup(group) then
        return {}
    end
    local players = {}
    for _, member in ipairs(InterruptChain.GetBackupCandidates(state, regionId)) do
        if member.subgroup == group then
            players[#players + 1] = member
        end
    end
    return players
end

---@class TwinFangsInterruptBackupPicker
---@field region string
---@field committed string|nil
---@field group number|nil
---@field player string|false

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param member RaidMember|nil
---@return number|nil, string|false
local function DraftFromBackup(state, regionId, member)
    local groups = InterruptChain.GetBackupGroups(state, regionId)
    if member then
        for _, group in ipairs(groups) do
            if group == member.subgroup then
                return member.subgroup, member.guid
            end
        end
    end
    return groups[1], InterruptChain.BACKUP_NONE
end

---Builds or repairs the two-level backup selector. Re-inits when the region or
---committed backup changes; browsing another group does not clear the assignment.
---@param state TwinFangsInterruptChainState
---@param regionId string
---@param picker TwinFangsInterruptBackupPicker|nil
---@return TwinFangsInterruptBackupPicker
function InterruptChain.SyncBackupPicker(state, regionId, picker)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local member = region.backup and InterruptChain.FindMemberByName(state, region.backup.name) or nil
    local committed = member and member.guid or nil
    if not picker or picker.region ~= regionId or picker.committed ~= committed then
        local group, player = DraftFromBackup(state, regionId, member)
        return {
            region = regionId,
            committed = committed,
            group = group,
            player = player,
        }
    end
    local groups = InterruptChain.GetBackupGroups(state, regionId)
    local groupOk
    for _, group in ipairs(groups) do
        if group == picker.group then
            groupOk = true
            break
        end
    end
    if not groupOk then
        picker.group, picker.player = DraftFromBackup(state, regionId, member)
    end
    return picker
end

---@param picker TwinFangsInterruptBackupPicker
---@param group number
function InterruptChain.PickBackupGroup(picker, group)
    picker.group = group
    picker.player = InterruptChain.BACKUP_NONE
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param guid string
---@return boolean
function InterruptChain.AddPlayer(state, regionId, guid)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    if type(guid) ~= "string" or guid == "" then
        return false
    end
    local member = InterruptChain.FindMember(state, guid)
    if not member or member.subgroup ~= region.group then
        return false
    end
    if InterruptChain.PrimaryRegionOf(state, member.fullName or member.name) then
        return false
    end
    local record = InterruptChain.RecordFromMember(member)
    if not record then
        return false
    end
    region.players[#region.players + 1] = record
    state.dirty = true
    return true
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param index integer
---@return boolean
function InterruptChain.RemovePlayer(state, regionId, index)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    if type(index) ~= "number" or index < 1 or index > #region.players then
        return false
    end
    table.remove(region.players, index)
    state.dirty = true
    return true
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param index integer
---@param delta integer
---@return boolean
function InterruptChain.MovePlayer(state, regionId, index, delta)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    local target = index + delta
    if index < 1 or index > #region.players or target < 1 or target > #region.players then
        return false
    end
    region.players[index], region.players[target] = region.players[target], region.players[index]
    state.dirty = true
    return true
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param guid string|nil|false
---@return boolean
function InterruptChain.SetBackup(state, regionId, guid)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    if guid == nil or guid == InterruptChain.BACKUP_NONE then
        if region.backup == nil then
            return false
        end
        region.backup = nil
        state.dirty = true
        return true
    end
    if type(guid) ~= "string" then
        return false
    end
    local member = InterruptChain.FindMember(state, guid)
    if not member or member.subgroup == region.group then
        return false
    end
    local usedBy = InterruptChain.BackupRegionOf(state, member.fullName or member.name)
    if usedBy and usedBy ~= regionId then
        return false
    end
    if
        region.backup
        and InterruptChain.PlayerName(region.backup) == InterruptChain.PlayerName(member.fullName or member.name)
    then
        return false
    end
    local record = InterruptChain.RecordFromMember(member)
    if not record then
        return false
    end
    region.backup = record
    state.dirty = true
    return true
end

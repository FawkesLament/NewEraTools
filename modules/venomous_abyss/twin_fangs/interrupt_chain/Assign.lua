local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Schema = Internals.Schema
local InterruptChain = Internals.InterruptChain

---@param name string
---@return string
local function ShortName(name)
    return name:match("^([^-]+)") or name
end

---@param roster RaidMember[]
---@param player TwinFangsInterruptPlayer|string|nil
---@return string
local function IssueDisplayName(roster, player)
    if player == nil then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    local name = InterruptChain.PlayerName(player)
    if not name then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    for _, member in ipairs(roster) do
        if InterruptChain.PlayerName(member.fullName or member.name) == name then
            return ShortName(member.name)
        end
    end
    return ShortName(name)
end

---@param regionId string
---@return string
local function IssueRegionLabel(regionId)
    if regionId == InterruptChain.FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    elseif regionId == InterruptChain.FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    elseif regionId == InterruptChain.BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    elseif regionId == InterruptChain.BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

---@class TwinFangsInterruptChainIssue
---@field code string
---@field severity "error"|"warning"
---@field region string
---@field player string|nil
---@field text string

---@param state TwinFangsInterruptChainState
---@return TwinFangsInterruptChainIssue[]
function InterruptChain.Validate(state)
    local issues = {}
    local roster = {}
    for _, member in ipairs(state.roster) do
        local name = InterruptChain.PlayerName(member.fullName or member.name)
        if name then
            roster[name] = member
        end
    end
    local primaryCount = {}
    local backupCount = {}
    local groupCount = {}

    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = state.regions[regionId]
        for _, player in ipairs(region.players) do
            local name = InterruptChain.PlayerName(player)
            if name then
                primaryCount[name] = (primaryCount[name] or 0) + 1
            end
        end
        local backupName = InterruptChain.PlayerName(region.backup)
        if backupName then
            backupCount[backupName] = (backupCount[backupName] or 0) + 1
        end
        if InterruptChain.IsRaidGroup(region.group) then
            groupCount[region.group] = (groupCount[region.group] or 0) + 1
        end
    end

    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = state.regions[regionId]
        local label = IssueRegionLabel(regionId)
        if InterruptChain.IsRaidGroup(region.group) and (groupCount[region.group] or 0) > 1 then
            issues[#issues + 1] = {
                code = "duplicate_group",
                severity = "error",
                region = regionId,
                text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_DUPLICATE_GROUP, region.group),
            }
        end
        if #region.players == 0 then
            issues[#issues + 1] = {
                code = "empty_chain",
                severity = "warning",
                region = regionId,
                text = string.format(L.TWIN_FANGS_INTERRUPT_WARN_EMPTY, label),
            }
        end
        for _, player in ipairs(region.players) do
            local display = IssueDisplayName(state.roster, player)
            local name = InterruptChain.PlayerName(player)
            local member = name and roster[name]
            if not member then
                issues[#issues + 1] = {
                    code = "player_missing",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_MISSING, display),
                }
            elseif member.subgroup ~= region.group then
                issues[#issues + 1] = {
                    code = "primary_wrong_group",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_WRONG_GROUP, display),
                }
            end
            if name and (primaryCount[name] or 0) > 1 then
                issues[#issues + 1] = {
                    code = "duplicate_primary",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_DUPLICATE, display),
                }
            end
        end
        if region.backup then
            local display = IssueDisplayName(state.roster, region.backup)
            local name = InterruptChain.PlayerName(region.backup)
            local backup = name and roster[name]
            if not backup then
                issues[#issues + 1] = {
                    code = "player_missing",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_MISSING, display),
                }
            elseif backup.subgroup == region.group then
                issues[#issues + 1] = {
                    code = "backup_same_group",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = L.TWIN_FANGS_INTERRUPT_ERR_BACKUP_SAME_GROUP,
                }
            end
            if name and (backupCount[name] or 0) > 1 then
                issues[#issues + 1] = {
                    code = "backup_shared",
                    severity = "error",
                    region = regionId,
                    player = name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_BACKUP_SHARED, display),
                }
            end
            if not Schema.ChannelAllowsBackup(region.channel) then
                issues[#issues + 1] = {
                    code = "backup_channel",
                    severity = "error",
                    region = regionId,
                    text = L.TWIN_FANGS_INTERRUPT_ERR_BACKUP_CHANNEL,
                }
            end
        end
    end

    local conflictGroups = {}
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local group = Schema.ChannelConflictGroup(state.regions[regionId].channel)
        if group then
            local owners = conflictGroups[group]
            if not owners then
                owners = {}
                conflictGroups[group] = owners
            end
            owners[#owners + 1] = regionId
        end
    end
    for _, owners in pairs(conflictGroups) do
        if #owners > 1 then
            for _, regionId in ipairs(owners) do
                issues[#issues + 1] = {
                    code = "channel_conflict",
                    severity = "error",
                    region = regionId,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_CHANNEL_CONFLICT, IssueRegionLabel(regionId)),
                }
            end
        end
    end

    return issues
end

---@param issues TwinFangsInterruptChainIssue[]
---@param regionId string|nil
---@return TwinFangsInterruptChainIssue[]
function InterruptChain.IssuesFor(issues, regionId)
    if not regionId then
        return issues
    end
    local matched = {}
    for _, issue in ipairs(issues) do
        if issue.region == regionId then
            matched[#matched + 1] = issue
        end
    end
    return matched
end

---@class TwinFangsInterruptChainStatus
---@field level "error"|"warning"|"unsynced"|"valid"
---@field errors integer
---@field warnings integer
---@field dirty boolean
---@field text string
---@field issues TwinFangsInterruptChainIssue[]

---@param state TwinFangsInterruptChainState
---@return TwinFangsInterruptChainStatus
function InterruptChain.GetStatus(state)
    local issues = InterruptChain.Validate(state)
    local errors, warnings = 0, 0
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            errors = errors + 1
        else
            warnings = warnings + 1
        end
    end
    local level, text
    if errors > 0 then
        level = "error"
        text = string.format(L.TWIN_FANGS_INTERRUPT_STATUS_ERRORS, errors)
    elseif warnings > 0 then
        level = "warning"
        text = string.format(L.TWIN_FANGS_INTERRUPT_STATUS_WARNINGS, warnings)
    elseif state.dirty then
        level = "unsynced"
        text = L.TWIN_FANGS_INTERRUPT_STATUS_UNSYNCED
    else
        level = "valid"
        text = L.TWIN_FANGS_INTERRUPT_STATUS_VALID
    end
    return {
        level = level,
        errors = errors,
        warnings = warnings,
        dirty = state.dirty == true,
        text = text,
        issues = issues,
    }
end

---@param roster RaidMember[]
---@return RaidMember[]
local function RosterInApiOrder(roster)
    local ordered = {}
    local allIndexed = true
    for index, member in ipairs(roster) do
        ordered[index] = member
        if type(member.index) ~= "number" then
            allIndexed = false
        end
    end
    if allIndexed then
        table.sort(ordered, function(a, b)
            return a.index < b.index
        end)
    end
    return ordered
end

---@param roster RaidMember[]|nil
---@param inRaid boolean
---@param rosterComplete boolean|nil  false when the live roster is missing members
---@return string|nil
function InterruptChain.GetAutoAssignBlockReason(roster, inRaid, rosterComplete)
    if not inRaid then
        return "not_in_raid"
    end
    if rosterComplete == false then
        return "roster_unavailable"
    end
    if type(roster) ~= "table" then
        return "roster_unavailable"
    end
    if #roster == 0 then
        return "roster_unavailable"
    end
    for _, member in ipairs(roster) do
        local group = member.subgroup
        if type(group) == "number" and group >= 1 and group <= 4 then
            return nil
        end
    end
    return "groups_empty"
end

---Builds a full four-region assignment from roster order. Groups 5–8 are ignored.
---@param roster RaidMember[]
---@return table<string, TwinFangsInterruptChainRegion>
function InterruptChain.BuildAutoAssignment(roster)
    local playersByGroup = { {}, {}, {}, {} }
    for _, member in ipairs(RosterInApiOrder(roster)) do
        local group = member.subgroup
        if type(group) == "number" and group >= 1 and group <= 4 then
            local record = InterruptChain.RecordFromMember(member)
            if record then
                local list = playersByGroup[group]
                list[#list + 1] = record
            end
        end
    end
    local assignment = {}
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local group = InterruptChain.AUTO_GROUP[regionId]
        local players = playersByGroup[group]
        assignment[regionId] = {
            group = #players > 0 and group or nil,
            players = InterruptChain.CopyPlayers(players),
            backup = nil,
        }
    end
    return assignment
end

---Replaces the four-region configuration from the current roster. Leaves state
---unchanged when the operation is blocked.
---@param state TwinFangsInterruptChainState
---@param roster RaidMember[]|nil
---@param inRaid boolean
---@param rosterComplete boolean|nil
---@return boolean, string|nil
function InterruptChain.AutoAssign(state, roster, inRaid, rosterComplete)
    local reason = InterruptChain.GetAutoAssignBlockReason(roster, inRaid, rosterComplete)
    if reason then
        return false, reason
    end
    local assignment = InterruptChain.BuildAutoAssignment(roster)
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = state.regions[regionId]
        local next = assignment[regionId]
        region.group = next.group
        region.players = InterruptChain.CopyPlayers(next.players)
        region.backup = nil
    end
    state.dirty = true
    return true
end

---@param issues TwinFangsInterruptChainIssue[]
---@return TwinFangsInterruptChainIssue|nil
function InterruptChain.PrimaryIssue(issues)
    local warning
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            return issue
        end
        if not warning then
            warning = issue
        end
    end
    return warning
end

local _, ns = ...
local L = ns.L
local Schema = ns.TwinFangsSchema
local Unit = ns.Api.Unit

local FRONT_LEFT = "front_left"
local FRONT_RIGHT = "front_right"
local BACK_LEFT = "back_left"
local BACK_RIGHT = "back_right"

---Interrupt-chain assignment for the Twin Fangs commander menu.
---Regions persist on TwinFangs settings; the roster is session-only.
local InterruptChain = {
    FRONT_LEFT = FRONT_LEFT,
    FRONT_RIGHT = FRONT_RIGHT,
    BACK_LEFT = BACK_LEFT,
    BACK_RIGHT = BACK_RIGHT,
    ---2×2 battlefield order: left-front, right-front, left-back, right-back.
    REGION_IDS = { FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT },
    GROUP_MIN = 1,
    GROUP_MAX = 8,
    ADD_NONE = false,
    BACKUP_NONE = false,
    ---Raid groups 1–4 map onto the four battlefield regions.
    AUTO_GROUP = {
        [FRONT_LEFT] = 1,
        [FRONT_RIGHT] = 2,
        [BACK_LEFT] = 3,
        [BACK_RIGHT] = 4,
    },
}
ns.TwinFangsInterruptChain = InterruptChain

local MOCK_REALM = "MockRealm"

---@param name string
---@param subgroup number
---@param classFile string
---@param role GroupRole
---@param index number
---@return RaidMember
local function MockMember(name, subgroup, classFile, role, index)
    return {
        name = name,
        fullName = name .. "-" .. MOCK_REALM,
        guid = "Player-MOCK-" .. name,
        index = index,
        subgroup = subgroup,
        classFile = classFile,
        role = role,
    }
end

---Fixed roster used by unit tests. The UI reads the live raid instead.
---@return RaidMember[]
function InterruptChain.MockRoster()
    return {
        MockMember("清风", 1, "MAGE", "DAMAGER", 1),
        MockMember("夜雨", 1, "ROGUE", "DAMAGER", 2),
        MockMember("石川", 1, "WARRIOR", "DAMAGER", 3),
        MockMember("流火", 2, "SHAMAN", "DAMAGER", 4),
        MockMember("霜华", 2, "HUNTER", "DAMAGER", 5),
        MockMember("远山", 2, "DEMONHUNTER", "DAMAGER", 6),
        MockMember("南枝", 3, "PRIEST", "DAMAGER", 7),
        MockMember("白露", 3, "MONK", "DAMAGER", 8),
        MockMember("青禾", 3, "WARLOCK", "DAMAGER", 9),
        MockMember("朔风", 4, "PALADIN", "DAMAGER", 10),
        MockMember("凌川", 4, "DEATHKNIGHT", "DAMAGER", 11),
        MockMember("暮雪", 4, "EVOKER", "DAMAGER", 12),
        MockMember("余烬", 5, "DRUID", "DAMAGER", 13),
        MockMember("栖梧", 5, "MAGE", "DAMAGER", 14),
    }
end

---@param group number
---@return boolean
local function IsRaidGroup(group)
    return type(group) == "number" and group >= InterruptChain.GROUP_MIN and group <= InterruptChain.GROUP_MAX
end

---@param name string|nil
---@return string|nil
local function QualifiedName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return Unit.GetFullName(name)
end

---@param name string
---@return string
local function ShortName(name)
    return name:match("^([^-]+)") or name
end

---@param player TwinFangsInterruptPlayer|nil
---@return boolean
function InterruptChain.IsResolved(player)
    return type(player) == "table" and type(player.guid) == "string" and player.guid ~= ""
end

---@param player TwinFangsInterruptPlayer|string|nil
---@return string|nil
function InterruptChain.PlayerGuid(player)
    if type(player) == "table" then
        if type(player.guid) == "string" and player.guid ~= "" then
            return player.guid
        end
        return nil
    end
    if type(player) == "string" and player ~= "" then
        return player
    end
end

---@param player TwinFangsInterruptPlayer|nil
---@return TwinFangsInterruptPlayer|nil
local function CopyPlayer(player)
    if type(player) ~= "table" then
        return nil
    end
    return {
        guid = player.guid,
        name = player.name,
    }
end

---@param players TwinFangsInterruptPlayer[]|nil
---@return TwinFangsInterruptPlayer[]
local function CopyPlayers(players)
    local copy = {}
    if type(players) ~= "table" then
        return copy
    end
    for index, player in ipairs(players) do
        copy[index] = CopyPlayer(player)
    end
    return copy
end

---@param member RaidMember
---@return TwinFangsInterruptPlayer|nil
local function RecordFromMember(member)
    if type(member) ~= "table" or type(member.guid) ~= "string" or member.guid == "" then
        return nil
    end
    local name = QualifiedName(member.fullName or member.name)
    if not name then
        return nil
    end
    return { guid = member.guid, name = name }
end

---@param entry any
---@return TwinFangsInterruptPlayer|nil
local function CoercePlayer(entry)
    if type(entry) == "string" then
        local name = QualifiedName(entry)
        if not name then
            return nil
        end
        return { name = name }
    end
    if type(entry) ~= "table" then
        return nil
    end
    local name = QualifiedName(entry.name)
    local guid
    if type(entry.guid) == "string" and entry.guid ~= "" then
        guid = entry.guid
    end
    if not name and not guid then
        return nil
    end
    return { guid = guid, name = name or guid }
end

---@param region any
---@return TwinFangsInterruptChainRegion
local function SanitizeRegion(region)
    local sanitized = Schema.NewInterruptRegion()
    if type(region) ~= "table" then
        return sanitized
    end
    if IsRaidGroup(region.group) then
        sanitized.group = region.group
    end
    if type(region.players) == "table" then
        for _, entry in ipairs(region.players) do
            local player = CoercePlayer(entry)
            if player then
                sanitized.players[#sanitized.players + 1] = player
            end
        end
    end
    sanitized.backup = CoercePlayer(region.backup)
    return sanitized
end

---Repairs a saved four-region table in place. Safe for missing or malformed data.
---@param chain table|nil
---@return TwinFangsInterruptChainSettings
function InterruptChain.SanitizeSaved(chain)
    if type(chain) ~= "table" then
        chain = Schema.NewInterruptChain()
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        chain[regionId] = SanitizeRegion(chain[regionId])
    end
    return chain
end

---@param members RaidMember[]
---@return table<string, RaidMember>
local function IndexRosterByGuid(members)
    local byGuid = {}
    for _, member in ipairs(members) do
        if type(member.guid) == "string" and member.guid ~= "" then
            byGuid[member.guid] = member
        end
    end
    return byGuid
end

---Resolves a legacy name to a roster member only when the match is unique.
---@param roster RaidMember[]
---@param raw string
---@return RaidMember|nil
function InterruptChain.ResolveLegacyName(roster, raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local qualified = QualifiedName(raw)
    local exact = {}
    local short = {}
    local rawShort = ShortName(raw)
    for _, member in ipairs(roster) do
        local fullName = member.fullName
        local display = member.name
        if fullName == raw or (qualified and fullName == qualified) then
            exact[#exact + 1] = member
        elseif
            display == raw
            or display == rawShort
            or (type(fullName) == "string" and ShortName(fullName) == rawShort)
        then
            short[#short + 1] = member
        end
    end
    if #exact == 1 then
        return exact[1]
    end
    if #exact > 1 then
        return nil
    end
    if raw:find("-", 1, true) then
        return nil
    end
    if #short == 1 then
        return short[1]
    end
    return nil
end

---@param player TwinFangsInterruptPlayer
---@param roster RaidMember[]
---@param byGuid table<string, RaidMember>
---@return boolean
local function RefreshOrMigratePlayer(player, roster, byGuid)
    if InterruptChain.IsResolved(player) then
        local member = byGuid[player.guid]
        if member then
            local name = QualifiedName(member.fullName or member.name)
            if name and name ~= player.name then
                player.name = name
                return true
            end
        end
        return false
    end
    local member = InterruptChain.ResolveLegacyName(roster, player.name)
    local record = member and RecordFromMember(member)
    if not record then
        local qualified = QualifiedName(player.name)
        if qualified and qualified ~= player.name then
            player.name = qualified
            return true
        end
        return false
    end
    player.guid = record.guid
    player.name = record.name
    return true
end

---Fills GUIDs for uniquely matched legacy names and refreshes cached names.
---Does not add, remove, or reorder assignments.
---@param chain TwinFangsInterruptChainSettings
---@param roster RaidMember[]
---@return boolean
function InterruptChain.MigrateAssignments(chain, roster)
    if type(chain) ~= "table" or type(roster) ~= "table" then
        return false
    end
    local changed = false
    local byGuid = IndexRosterByGuid(roster)
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = chain[regionId]
        if type(region) == "table" then
            for _, player in ipairs(region.players or {}) do
                if RefreshOrMigratePlayer(player, roster, byGuid) then
                    changed = true
                end
            end
            if region.backup and RefreshOrMigratePlayer(region.backup, roster, byGuid) then
                changed = true
            end
        end
    end
    return changed
end

---@return string
function InterruptChain.RegionLabel(regionId)
    if regionId == FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    elseif regionId == FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    elseif regionId == BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    elseif regionId == BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

---@param group number|nil
---@return string
function InterruptChain.GroupLabel(group)
    if IsRaidGroup(group) then
        return string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP, group)
    end
    return L.TWIN_FANGS_INTERRUPT_RAID_GROUP_NONE
end

---@param roster RaidMember[]
---@param player TwinFangsInterruptPlayer|string|nil
---@return string
function InterruptChain.DisplayName(roster, player)
    if player == nil then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    local guid = InterruptChain.PlayerGuid(player)
    if guid then
        for _, member in ipairs(roster) do
            if member.guid == guid then
                return ShortName(member.name)
            end
        end
    end
    local cached
    if type(player) == "table" then
        cached = player.name
    elseif type(player) == "string" then
        cached = player
    end
    if type(cached) ~= "string" or cached == "" then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    return ShortName(cached)
end

---@param saved TwinFangsInterruptChainSettings|nil
---@return TwinFangsInterruptChainState
function InterruptChain.NewState(saved)
    ---@class TwinFangsInterruptChainState
    ---@field regions TwinFangsInterruptChainSettings
    ---@field roster RaidMember[]
    ---@field dirty boolean  Always true until real sync exists.

    local regions
    if type(saved) == "table" then
        regions = InterruptChain.SanitizeSaved(saved)
    else
        regions = Schema.NewInterruptChain()
    end
    return {
        regions = regions,
        roster = {},
        dirty = true,
    }
end

---@param state TwinFangsInterruptChainState
---@param members RaidMember[]
function InterruptChain.SetRoster(state, members)
    state.roster = members or {}
    InterruptChain.MigrateAssignments(state.regions, state.roster)
end

---Replaces the session roster with the current raid. Empty when not in a raid.
---Does not add or remove saved assignments.
---@param state TwinFangsInterruptChainState
function InterruptChain.UseRaidRoster(state)
    InterruptChain.SetRoster(state, ns.Api.Group.GetRaidMembers())
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@return TwinFangsInterruptChainRegion
function InterruptChain.GetRegion(state, regionId)
    local region = state.regions[regionId]
    assert(region, "Unknown interrupt region")
    return {
        group = region.group,
        players = CopyPlayers(region.players),
        backup = CopyPlayer(region.backup),
    }
end

---@param state TwinFangsInterruptChainState
---@param guid string|nil
---@return RaidMember|nil
local function FindMember(state, guid)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    for _, member in ipairs(state.roster) do
        if member.guid == guid then
            return member
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param identity TwinFangsInterruptPlayer|string|nil
---@return RaidMember|nil
function InterruptChain.GetMember(state, identity)
    return FindMember(state, InterruptChain.PlayerGuid(identity))
end

---@param state TwinFangsInterruptChainState
---@param guid string
---@return string|nil
local function PrimaryRegionOf(state, guid)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        for _, player in ipairs(state.regions[regionId].players) do
            if player.guid == guid then
                return regionId
            end
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param guid string
---@return string|nil
local function BackupRegionOf(state, guid)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local backup = state.regions[regionId].backup
        if backup and backup.guid == guid then
            return regionId
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param region TwinFangsInterruptChainRegion
---@param group number|nil
local function ApplyGroup(state, region, group)
    region.group = group
    local kept = {}
    if IsRaidGroup(group) then
        for _, player in ipairs(region.players) do
            local member = FindMember(state, player.guid)
            if member and member.subgroup == group then
                kept[#kept + 1] = player
            end
        end
    end
    region.players = kept
    if region.backup then
        local backup = FindMember(state, region.backup.guid)
        if not backup or (IsRaidGroup(group) and backup.subgroup == group) then
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
    if not IsRaidGroup(group) or region.group == group then
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
            and not PrimaryRegionOf(state, member.guid)
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
            local usedBy = BackupRegionOf(state, member.guid)
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
        if IsRaidGroup(group) and not seen[group] then
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
    if IsRaidGroup(region.group) and not seen[region.group] then
        groups[#groups + 1] = region.group
        table.sort(groups)
    end
    return groups
end

---@param state TwinFangsInterruptChainState
---@param group number
---@return string|nil
function InterruptChain.AssignedRegion(state, group)
    if not IsRaidGroup(group) then
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
---@param group number
---@return string
function InterruptChain.GroupChoiceLabel(state, regionId, group)
    local label = InterruptChain.GroupLabel(group)
    if InterruptChain.IsGroupAssignedElsewhere(state, regionId, group) then
        return string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP_ASSIGNED, group)
    end
    return label
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
    if not IsRaidGroup(group) then
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
    local committed = region.backup and region.backup.guid or nil
    local member = committed and FindMember(state, committed) or nil
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
    local member = FindMember(state, guid)
    if not member or member.subgroup ~= region.group then
        return false
    end
    if PrimaryRegionOf(state, guid) then
        return false
    end
    local record = RecordFromMember(member)
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
    local member = FindMember(state, guid)
    if not member or member.subgroup == region.group then
        return false
    end
    local usedBy = BackupRegionOf(state, guid)
    if usedBy and usedBy ~= regionId then
        return false
    end
    if region.backup and region.backup.guid == guid then
        return false
    end
    local record = RecordFromMember(member)
    if not record then
        return false
    end
    region.backup = record
    state.dirty = true
    return true
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
    local roster = IndexRosterByGuid(state.roster)
    local primaryCount = {}
    local backupCount = {}
    local groupCount = {}

    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = state.regions[regionId]
        for _, player in ipairs(region.players) do
            if player.guid then
                primaryCount[player.guid] = (primaryCount[player.guid] or 0) + 1
            end
        end
        if region.backup and region.backup.guid then
            backupCount[region.backup.guid] = (backupCount[region.backup.guid] or 0) + 1
        end
        if IsRaidGroup(region.group) then
            groupCount[region.group] = (groupCount[region.group] or 0) + 1
        end
    end

    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = state.regions[regionId]
        local label = InterruptChain.RegionLabel(regionId)
        if IsRaidGroup(region.group) and (groupCount[region.group] or 0) > 1 then
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
            local display = InterruptChain.DisplayName(state.roster, player)
            if not InterruptChain.IsResolved(player) then
                issues[#issues + 1] = {
                    code = "unresolved_player",
                    severity = "error",
                    region = regionId,
                    player = player.name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_UNRESOLVED, display),
                }
            else
                local member = roster[player.guid]
                if not member then
                    issues[#issues + 1] = {
                        code = "player_missing",
                        severity = "error",
                        region = regionId,
                        player = player.guid,
                        text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_MISSING, display),
                    }
                elseif member.subgroup ~= region.group then
                    issues[#issues + 1] = {
                        code = "primary_wrong_group",
                        severity = "error",
                        region = regionId,
                        player = player.guid,
                        text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_WRONG_GROUP, display),
                    }
                end
                if (primaryCount[player.guid] or 0) > 1 then
                    issues[#issues + 1] = {
                        code = "duplicate_primary",
                        severity = "error",
                        region = regionId,
                        player = player.guid,
                        text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_DUPLICATE, display),
                    }
                end
            end
        end
        if region.backup then
            local display = InterruptChain.DisplayName(state.roster, region.backup)
            if not InterruptChain.IsResolved(region.backup) then
                issues[#issues + 1] = {
                    code = "unresolved_player",
                    severity = "error",
                    region = regionId,
                    player = region.backup.name,
                    text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_UNRESOLVED, display),
                }
            else
                local backup = roster[region.backup.guid]
                if not backup then
                    issues[#issues + 1] = {
                        code = "player_missing",
                        severity = "error",
                        region = regionId,
                        player = region.backup.guid,
                        text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_MISSING, display),
                    }
                elseif backup.subgroup == region.group then
                    issues[#issues + 1] = {
                        code = "backup_same_group",
                        severity = "error",
                        region = regionId,
                        player = region.backup.guid,
                        text = L.TWIN_FANGS_INTERRUPT_ERR_BACKUP_SAME_GROUP,
                    }
                end
                if (backupCount[region.backup.guid] or 0) > 1 then
                    issues[#issues + 1] = {
                        code = "backup_shared",
                        severity = "error",
                        region = regionId,
                        player = region.backup.guid,
                        text = string.format(L.TWIN_FANGS_INTERRUPT_ERR_BACKUP_SHARED, display),
                    }
                end
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
            local record = RecordFromMember(member)
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
            players = CopyPlayers(players),
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
        region.players = CopyPlayers(next.players)
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

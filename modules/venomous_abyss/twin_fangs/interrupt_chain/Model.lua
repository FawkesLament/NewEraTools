local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local Schema = Internals.Schema
local Group = ns.Api.Group
local Player = ns.Api.Player
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
    POSITION_MIN = 1,
    POSITION_MAX = 5,
    ---Unique primaries per region match a raid subgroup.
    REPEAT_MIN = 1,
    REPEAT_MAX = 3,
    ---Expanded interrupt turns: up to five players, each repeating at most three times.
    TURN_MAX = 15,
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
Internals.InterruptChain = InterruptChain

---@param group number
---@return boolean
function InterruptChain.IsRaidGroup(group)
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

---@param player TwinFangsInterruptPlayer|string|nil
---@return string|nil
function InterruptChain.PlayerName(player)
    local raw
    if type(player) == "table" then
        raw = player.name
    elseif type(player) == "string" then
        raw = player
    end
    return QualifiedName(raw)
end

---@param player TwinFangsInterruptPlayer|nil
---@return TwinFangsInterruptPlayer|nil
function InterruptChain.CopyPlayer(player)
    local name = InterruptChain.PlayerName(player)
    if not name then
        return nil
    end
    return { name = name }
end

---@param players TwinFangsInterruptPlayer[]|nil
---@return TwinFangsInterruptPlayer[]
function InterruptChain.CopyPlayers(players)
    local copy = {}
    if type(players) ~= "table" then
        return copy
    end
    for index, player in ipairs(players) do
        copy[index] = InterruptChain.CopyPlayer(player)
    end
    return copy
end

---@param value any
---@return integer
function InterruptChain.ClampRepeat(value)
    if type(value) ~= "number" then
        return InterruptChain.REPEAT_MIN
    end
    local count = math.floor(value)
    if count < InterruptChain.REPEAT_MIN then
        return InterruptChain.REPEAT_MIN
    end
    if count > InterruptChain.REPEAT_MAX then
        return InterruptChain.REPEAT_MAX
    end
    return count
end

---Groups consecutive identical names into one logical assignment.
---@param players TwinFangsInterruptPlayer[]|nil
---@return TwinFangsInterruptBlock[]
function InterruptChain.Blocks(players)
    ---@class TwinFangsInterruptBlock
    ---@field player TwinFangsInterruptPlayer
    ---@field name string|nil
    ---@field count integer
    ---@field first integer
    ---@field last integer
    local blocks = {}
    if type(players) ~= "table" then
        return blocks
    end
    for index, player in ipairs(players) do
        local name = InterruptChain.PlayerName(player)
        local last = blocks[#blocks]
        if name and last and last.name == name then
            last.count = last.count + 1
            last.last = index
        else
            blocks[#blocks + 1] = {
                player = InterruptChain.CopyPlayer(player) or player,
                name = name,
                count = 1,
                first = index,
                last = index,
            }
        end
    end
    return blocks
end

---@param blocks TwinFangsInterruptBlock[]
---@return TwinFangsInterruptPlayer[]
function InterruptChain.ExpandBlocks(blocks)
    local players = {}
    for _, block in ipairs(blocks) do
        local record = InterruptChain.CopyPlayer(block.player)
        if record then
            local count = InterruptChain.ClampRepeat(block.count)
            for _ = 1, count do
                players[#players + 1] = InterruptChain.CopyPlayer(record)
            end
        end
    end
    return players
end

---First and last 1-based turns for `identity` in an expanded sequence.
---@param players TwinFangsInterruptPlayer[]|nil
---@param identity TwinFangsInterruptPlayer|string|nil
---@return integer|nil first
---@return integer|nil last
function InterruptChain.AssignmentRange(players, identity)
    local name = InterruptChain.PlayerName(identity)
    if not name or type(players) ~= "table" then
        return nil
    end
    local first
    local last
    for index, player in ipairs(players) do
        if InterruptChain.PlayerName(player) == name then
            if not first then
                first = index
            end
            last = index
        elseif first then
            break
        end
    end
    return first, last
end

---@param member RaidMember
---@return TwinFangsInterruptPlayer|nil
function InterruptChain.RecordFromMember(member)
    if type(member) ~= "table" then
        return nil
    end
    local name = InterruptChain.PlayerName(member.fullName or member.name)
    if not name then
        return nil
    end
    return { name = name }
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
    if not name then
        return nil
    end
    return { name = name }
end

---@param region any
---@return TwinFangsInterruptChainRegion
local function SanitizeRegion(region)
    local sanitized = Schema.NewInterruptRegion()
    if type(region) ~= "table" then
        return sanitized
    end
    if InterruptChain.IsRaidGroup(region.group) then
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
    sanitized.channel = Schema.CoerceChannel(region.channel)
    if sanitized.backup and not Schema.ChannelAllowsBackup(sanitized.channel) then
        sanitized.backup = nil
    end
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

---Whether any region has a group, interrupt player, or backup.
---@param chain TwinFangsInterruptChainSettings|nil
---@return boolean
function InterruptChain.HasAssignments(chain)
    if type(chain) ~= "table" then
        return false
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = chain[regionId]
        if type(region) == "table" then
            if InterruptChain.IsRaidGroup(region.group) then
                return true
            end
            if type(region.players) == "table" and #region.players > 0 then
                return true
            end
            if region.backup ~= nil then
                return true
            end
        end
    end
    return false
end

---Replaces all four regions on `target` from `source`. Nested tables are new copies.
---@param target TwinFangsInterruptChainSettings
---@param source TwinFangsInterruptChainSettings
function InterruptChain.ReplaceChain(target, source)
    local incoming = InterruptChain.SanitizeSaved({
        [FRONT_LEFT] = source[FRONT_LEFT],
        [FRONT_RIGHT] = source[FRONT_RIGHT],
        [BACK_LEFT] = source[BACK_LEFT],
        [BACK_RIGHT] = source[BACK_RIGHT],
    })
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        target[regionId] = incoming[regionId]
    end
end

---@param saved TwinFangsInterruptChainSettings|nil
---@return TwinFangsInterruptChainState
function InterruptChain.NewState(saved)
    ---@class TwinFangsInterruptChainState
    ---@field regions TwinFangsInterruptChainSettings
    ---@field roster RaidMember[]
    ---@field dirty boolean  True until a publication is accepted by the transport.

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
        players = InterruptChain.CopyPlayers(region.players),
        backup = InterruptChain.CopyPlayer(region.backup),
        channel = Schema.CoerceChannel(region.channel),
    }
end

---@param state TwinFangsInterruptChainState
---@param guid string|nil
---@return RaidMember|nil
function InterruptChain.FindMember(state, guid)
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
---@param name string|nil
---@return RaidMember|nil
function InterruptChain.FindMemberByName(state, name)
    name = QualifiedName(name)
    if not name then
        return nil
    end
    for _, member in ipairs(state.roster) do
        if InterruptChain.PlayerName(member.fullName or member.name) == name then
            return member
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param identity TwinFangsInterruptPlayer|string|nil
---@return RaidMember|nil
function InterruptChain.GetMember(state, identity)
    if type(identity) == "string" then
        return InterruptChain.FindMember(state, identity) or InterruptChain.FindMemberByName(state, identity)
    end
    return InterruptChain.FindMemberByName(state, InterruptChain.PlayerName(identity))
end

---@param state TwinFangsInterruptChainState
---@param name string|nil
---@return string|nil
function InterruptChain.PrimaryRegionOf(state, name)
    name = QualifiedName(name)
    if not name then
        return nil
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        for _, player in ipairs(state.regions[regionId].players) do
            if InterruptChain.PlayerName(player) == name then
                return regionId
            end
        end
    end
end

---@param state TwinFangsInterruptChainState
---@param name string|nil
---@return string|nil
function InterruptChain.BackupRegionOf(state, name)
    name = QualifiedName(name)
    if not name then
        return nil
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        if InterruptChain.PlayerName(state.regions[regionId].backup) == name then
            return regionId
        end
    end
end

---@param entry TwinFangsInterruptPlayer|string|nil
---@return TwinFangsInterruptPlayer|nil
local function CopyStoredPlayer(entry)
    if type(entry) == "table" then
        return InterruptChain.CopyPlayer(entry)
    end
    return InterruptChain.CopyPlayer({ name = entry })
end

---@param players TwinFangsInterruptPlayer[]|nil
---@return TwinFangsInterruptPlayer[]
local function CopyStoredPlayers(players)
    local copy = {}
    if type(players) ~= "table" then
        return copy
    end
    for _, entry in ipairs(players) do
        local player = CopyStoredPlayer(entry)
        if player then
            copy[#copy + 1] = player
        end
    end
    return copy
end

---@param regionId string
---@param region table
---@return TwinFangsInterruptMemberAssignment
local function CopyAssignment(regionId, region)
---@class TwinFangsInterruptMemberAssignment
---@field regionId string
---@field group number|nil
---@field players TwinFangsInterruptPlayer[]
---@field backup TwinFangsInterruptPlayer|nil
---@field channel TwinFangsInterruptChannel
    return {
        regionId = regionId,
        group = InterruptChain.IsRaidGroup(region.group) and region.group or nil,
        players = CopyStoredPlayers(region.players),
        backup = CopyStoredPlayer(region.backup),
        channel = Schema.CoerceChannel(region.channel),
    }
end

---Current character's persisted Name-Realm, resolved from the live GUID when in a raid.
---Does not mutate saved assignments. Falls back to `Player.GetFullName` when the GUID is unknown.
---@return string|nil
function InterruptChain.ResolveLocalPlayerName()
    local guid = Player.GetGUID()
    if type(guid) == "string" and guid ~= "" then
        for _, member in ipairs(Group.GetRaidMembers()) do
            if member.guid == guid then
                local name = InterruptChain.PlayerName(member.fullName or member.name)
                if name then
                    return name
                end
            end
        end
    end
    return Player.GetFullName()
end

---This player's primary region/index and backup region from a persisted chain.
---Matches stored names only; does not mutate `chain`.
---@param chain TwinFangsInterruptChainSettings|nil
---@param identity string|nil
---@return TwinFangsInterruptResponsibilities
function InterruptChain.GetPlayerResponsibilities(chain, identity)
    ---@class TwinFangsInterruptResponsibilities
    ---@field region string|nil
    ---@field index number|nil
    ---@field indexEnd number|nil
    ---@field backup string|nil
    local responsibilities = {}
    local view = InterruptChain.GetMemberView(chain, identity)
    local name = InterruptChain.PlayerName(identity)
    if view.primary then
        responsibilities.region = view.primary.regionId
        local first, last = InterruptChain.AssignmentRange(view.primary.players, name)
        responsibilities.index = first
        responsibilities.indexEnd = last
    end
    local firstBackup = view.backups[1]
    if firstBackup then
        responsibilities.backup = firstBackup.regionId
    end
    return responsibilities
end

---Read-only assignments for one player. Matches stored names only; does not mutate `chain`.
---@param chain TwinFangsInterruptChainSettings|nil
---@param identity string|nil
---@return TwinFangsInterruptMemberView
function InterruptChain.GetMemberView(chain, identity)
    ---@class TwinFangsInterruptMemberView
    ---@field primary TwinFangsInterruptMemberAssignment|nil
    ---@field backups TwinFangsInterruptMemberAssignment[]
    local view = { backups = {} }
    local name = InterruptChain.PlayerName(identity)
    if not name or type(chain) ~= "table" then
        return view
    end
    local seen = {}
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region = chain[regionId]
        if type(region) == "table" and type(region.players) == "table" then
            for _, player in ipairs(region.players) do
                if InterruptChain.PlayerName(player) == name then
                    view.primary = CopyAssignment(regionId, region)
                    seen[regionId] = true
                    break
                end
            end
        end
        if view.primary then
            break
        end
    end
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        if not seen[regionId] then
            local region = chain[regionId]
            if type(region) == "table" and InterruptChain.PlayerName(region.backup) == name then
                view.backups[#view.backups + 1] = CopyAssignment(regionId, region)
                seen[regionId] = true
            end
        end
    end
    return view
end

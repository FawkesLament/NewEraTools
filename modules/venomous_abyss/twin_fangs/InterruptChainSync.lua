local _, ns = ...
local L = ns.L
local Util = ns.Util
local Schema = ns.TwinFangsSchema
local Group = ns.Api.Group
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm

local InterruptChain = ns.TwinFangsInterruptChain

---MessageProtocol topic. Payload schema is owned by this feature, not the envelope.
InterruptChain.SYNC_TOPIC = "twin_fangs.interrupts"
InterruptChain.SYNC_PAYLOAD_VERSION = "1"

local POSITION_MIN = InterruptChain.POSITION_MIN
local POSITION_MAX = InterruptChain.POSITION_MAX

local publishing = false

---@param group number|nil
---@return boolean
local function IsRaidGroup(group)
    return type(group) == "number" and group >= InterruptChain.GROUP_MIN and group <= InterruptChain.GROUP_MAX
end

---@param position number|nil
---@return boolean
local function IsSubgroupPosition(position)
    return type(position) == "number" and position >= POSITION_MIN and position <= POSITION_MAX
end

---Same roster-index sort Auto Assign uses for subgroup slot order.
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

---Maps each roster GUID to its raid subgroup and 1–5 slot. Slot order matches Auto Assign.
---@param roster RaidMember[]
---@return table<string, { group: number, position: number }>
function InterruptChain.SubgroupPositions(roster)
    local positions = {}
    local nextSlot = {}
    for _, member in ipairs(RosterInApiOrder(roster or {})) do
        local guid = member.guid
        local group = member.subgroup
        if type(guid) == "string" and guid ~= "" and IsRaidGroup(group) then
            local position = (nextSlot[group] or 0) + 1
            nextSlot[group] = position
            positions[guid] = { group = group, position = position }
        end
    end
    return positions
end

---@param region TwinFangsInterruptChainRegion
---@param positions table<string, { group: number, position: number }>
---@return string|nil
---@return string|nil
local function EncodeRegion(region, positions)
    local groupText = ""
    if region.group ~= nil then
        if not IsRaidGroup(region.group) then
            return nil, "invalid_group"
        end
        groupText = tostring(region.group)
    end

    local order = {}
    local usedSlots = {}
    for _, player in ipairs(region.players) do
        local guid = InterruptChain.PlayerGuid(player)
        if type(guid) ~= "string" then
            return nil, "unresolved_player"
        end
        local slot = positions[guid]
        if not slot then
            return nil, "player_missing"
        end
        if not IsRaidGroup(slot.group) or not IsSubgroupPosition(slot.position) then
            return nil, "invalid_position"
        end
        if region.group ~= nil and slot.group ~= region.group then
            return nil, "primary_wrong_group"
        end
        if usedSlots[slot.position] then
            return nil, "duplicate_position"
        end
        usedSlots[slot.position] = true
        order[#order + 1] = tostring(slot.position)
    end
    if #order > POSITION_MAX then
        return nil, "invalid_position"
    end

    local backupText = ""
    if region.backup then
        local guid = InterruptChain.PlayerGuid(region.backup)
        if type(guid) ~= "string" then
            return nil, "unresolved_player"
        end
        local slot = positions[guid]
        if not slot then
            return nil, "player_missing"
        end
        if not IsRaidGroup(slot.group) or not IsSubgroupPosition(slot.position) then
            return nil, "invalid_position"
        end
        if region.group ~= nil and slot.group == region.group then
            return nil, "backup_same_group"
        end
        backupText = tostring(slot.group) .. tostring(slot.position)
    end

    return groupText .. ":" .. table.concat(order) .. ":" .. backupText
end

---Encodes the four regions into one payload. Does not send and does not mutate `state`.
---@param state TwinFangsInterruptChainState
---@return string|nil payload
---@return string|nil reason
function InterruptChain.EncodePublication(state)
    local positions = InterruptChain.SubgroupPositions(state.roster)
    local parts = { InterruptChain.SYNC_PAYLOAD_VERSION }
    for _, regionId in ipairs(InterruptChain.REGION_IDS) do
        local encoded, reason = EncodeRegion(state.regions[regionId], positions)
        if not encoded then
            return nil, reason
        end
        parts[#parts + 1] = encoded
    end
    local payload = table.concat(parts, "|")
    local wire, encodeReason = MessageProtocol.Encode(
        MessageProtocol.TYPE_EVENT,
        InterruptChain.SYNC_TOPIC,
        MessageProtocol.EVENT_CORRELATION_ID,
        payload
    )
    if not wire then
        return nil, encodeReason
    end
    return payload
end

---@return string|nil
function InterruptChain.GetPublishBlockReason()
    if Group.GetRaidChatType() == nil then
        return "not_in_raid"
    end
    if publishing then
        return "in_progress"
    end
end

---@param reason string|nil
---@param detail string|nil
---@return string
local function FailureText(reason, detail)
    if type(detail) == "string" and detail ~= "" then
        return detail
    end
    if reason == "not_in_raid" then
        return L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_NOT_IN_RAID
    end
    if reason == "in_progress" then
        return L.TWIN_FANGS_INTERRUPT_SYNC_IN_PROGRESS
    end
    if reason == "too_large" then
        return L.TWIN_FANGS_INTERRUPT_SYNC_TOO_LARGE
    end
    if reason == "invalid_position" or reason == "duplicate_position" or reason == "invalid_group" then
        return L.TWIN_FANGS_INTERRUPT_SYNC_INVALID_POSITION
    end
    if type(reason) == "string" and reason ~= "" then
        return string.format(L.TWIN_FANGS_INTERRUPT_SYNC_FAILED, reason)
    end
    return L.TWIN_FANGS_INTERRUPT_SYNC_FAILED_GENERIC
end

---Publishes the current four-region assignment as one CONTROL event. Sender only.
---@param state TwinFangsInterruptChainState
---@return boolean
---@return string|nil
function InterruptChain.Publish(state)
    local block = InterruptChain.GetPublishBlockReason()
    if block then
        if block ~= "in_progress" then
            Util.Print(FailureText(block))
        end
        return false, block
    end

    local issues = InterruptChain.Validate(state)
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            Util.Print(issue.text)
            return false, issue.code
        end
    end

    local payload, encodeReason = InterruptChain.EncodePublication(state)
    if not payload then
        Util.Print(FailureText(encodeReason))
        return false, encodeReason
    end

    publishing = true
    local ok, sendReason = MessageProtocolComm.Send(
        MessageProtocol.TYPE_EVENT,
        InterruptChain.SYNC_TOPIC,
        MessageProtocol.EVENT_CORRELATION_ID,
        payload,
        Group.GetRaidChatType(),
        { trafficClass = MessageProtocolComm.TrafficClass.CONTROL }
    )
    publishing = false

    if not ok then
        Util.Print(FailureText(sendReason))
        return false, sendReason
    end

    state.dirty = false
    Util.Print(string.format(L.TWIN_FANGS_INTERRUPT_SYNC_SENT, L.TWIN_FANGS_TITLE))
    return true
end

local listening = false

---@param text string
---@param sep string
---@return string[]
local function SplitExact(text, sep)
    local parts = {}
    local start = 1
    while true do
        local index = text:find(sep, start, true)
        if not index then
            parts[#parts + 1] = text:sub(start)
            break
        end
        parts[#parts + 1] = text:sub(start, index - 1)
        start = index + 1
    end
    return parts
end

---Slot map using the same roster-index order as SubgroupPositions.
---@param roster RaidMember[]
---@return table<number, table<number, RaidMember>>
function InterruptChain.SubgroupSlotMembers(roster)
    local byGroup = {}
    local nextSlot = {}
    for _, member in ipairs(RosterInApiOrder(roster or {})) do
        local guid = member.guid
        local group = member.subgroup
        if type(guid) == "string" and guid ~= "" and IsRaidGroup(group) then
            local position = (nextSlot[group] or 0) + 1
            nextSlot[group] = position
            local slots = byGroup[group]
            if not slots then
                slots = {}
                byGroup[group] = slots
            end
            if slots[position] then
                slots[position] = false
            else
                slots[position] = member
            end
        end
    end
    return byGroup
end

---@param member RaidMember
---@return TwinFangsInterruptPlayer|nil
local function PlayerFromMember(member)
    if type(member) ~= "table" or type(member.guid) ~= "string" or member.guid == "" then
        return nil
    end
    local name = member.fullName or member.name
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return { guid = member.guid, name = ns.Api.Unit.GetFullName(name) }
end

---@param slots table<number, RaidMember|false>|nil
---@param position number
---@return TwinFangsInterruptPlayer|nil
---@return string|nil
---@return table|nil
local function ResolveSlot(slots, group, position)
    if type(slots) ~= "table" then
        return nil, "player_missing", { group = group, position = position }
    end
    local member = slots[position]
    if member == false then
        return nil, "ambiguous_position", { group = group, position = position }
    end
    local player = member and PlayerFromMember(member)
    if not player then
        return nil, "player_missing", { group = group, position = position }
    end
    return player
end

---@param text string
---@param slotsByGroup table<number, table<number, RaidMember|false>>
---@return TwinFangsInterruptChainRegion|nil
---@return string|nil
---@return table|nil
local function DecodeRegion(text, slotsByGroup)
    if type(text) ~= "string" then
        return nil, "malformed"
    end
    local groupText, orderText, backupText = text:match("^([^:]*):([^:]*):([^:]*)$")
    if not groupText then
        return nil, "malformed"
    end

    local group
    if groupText ~= "" then
        group = tonumber(groupText)
        if tostring(group) ~= groupText or not IsRaidGroup(group) then
            return nil, "invalid_group"
        end
    end

    local players = {}
    local usedSlots = {}
    if orderText ~= "" then
        if group == nil or not orderText:find("^[1-5]+$") or #orderText > POSITION_MAX then
            return nil, "invalid_position"
        end
        local slots = slotsByGroup[group]
        for index = 1, #orderText do
            local position = tonumber(orderText:sub(index, index))
            if usedSlots[position] then
                return nil, "duplicate_position"
            end
            usedSlots[position] = true
            local player, reason, detail = ResolveSlot(slots, group, position)
            if not player then
                return nil, reason, detail
            end
            players[#players + 1] = player
        end
    end

    local backup
    if backupText ~= "" then
        local backupGroup = tonumber(backupText:sub(1, 1))
        local backupPosition = tonumber(backupText:sub(2, 2))
        if #backupText ~= 2 or not IsRaidGroup(backupGroup) or not IsSubgroupPosition(backupPosition) then
            return nil, "invalid_position"
        end
        local player, reason, detail = ResolveSlot(slotsByGroup[backupGroup], backupGroup, backupPosition)
        if not player then
            return nil, reason, detail
        end
        backup = player
    end

    return {
        group = group,
        players = players,
        backup = backup,
    }
end

---Decodes a publication payload against one roster snapshot. Does not persist.
---@param payload string
---@param roster RaidMember[]
---@return TwinFangsInterruptChainSettings|nil
---@return string|nil
---@return table|nil
function InterruptChain.DecodePublication(payload, roster)
    if type(payload) ~= "string" then
        return nil, "malformed"
    end
    local parts = SplitExact(payload, "|")
    if #parts ~= 5 then
        return nil, "malformed"
    end
    if parts[1] ~= InterruptChain.SYNC_PAYLOAD_VERSION then
        return nil, "unsupported_version"
    end
    local slotsByGroup = InterruptChain.SubgroupSlotMembers(roster)
    local regions = Schema.NewInterruptChain()
    for index, regionId in ipairs(InterruptChain.REGION_IDS) do
        local region, reason, detail = DecodeRegion(parts[index + 1], slotsByGroup)
        if not region then
            return nil, reason, detail
        end
        regions[regionId] = region
    end
    return regions
end

---Decodes, resolves, and validates a payload. Does not persist.
---@param payload string
---@param roster RaidMember[]
---@return TwinFangsInterruptChainSettings|nil
---@return string|nil
---@return string|nil
function InterruptChain.ResolvePublication(payload, roster)
    local regions, reason, detail = InterruptChain.DecodePublication(payload, roster)
    if not regions then
        return nil, reason, detail
    end
    local issues = InterruptChain.Validate({
        regions = regions,
        roster = roster or {},
        dirty = false,
    })
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            return nil, issue.code, issue.text
        end
    end
    return regions
end

---@param reason string|nil
---@param detail string|table|nil
---@return string
local function ReceiveFailureText(reason, detail)
    if type(detail) == "string" and detail ~= "" then
        return detail
    end
    if reason == "player_missing" or reason == "ambiguous_position" then
        local group = type(detail) == "table" and detail.group
        local position = type(detail) == "table" and detail.position
        if type(group) == "number" and type(position) == "number" then
            return string.format(L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_MISSING, group, position)
        end
        return L.TWIN_FANGS_INTERRUPT_SYNC_INVALID_POSITION
    end
    if reason == "unsupported_version" then
        return L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_VERSION
    end
    if reason == "malformed" or reason == "invalid_group" or reason == "invalid_position" or reason == "duplicate_position" then
        return L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_MALFORMED
    end
    if type(reason) == "string" and reason ~= "" then
        return reason
    end
    return L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_MALFORMED
end

---@return TwinFangsInterruptChainSettings|nil
local function SavedChain()
    local TwinFangs = ns.Modules.Get("TwinFangs")
    return TwinFangs and TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
end

---@param msg MessageProtocolMessage
---@return boolean
local function IsOwnEcho(msg)
    return msg.sender == ns.Api.Player.GetFullName()
end

---@param msg MessageProtocolMessage
---@return boolean
local function IsAuthorizedSender(msg)
    local leader = Group.GetRaidLeaderFullName()
    return type(leader) == "string" and leader ~= "" and msg.sender == leader
end

---@param msg MessageProtocolMessage
local function OnPublicationMessage(msg)
    if msg.type ~= MessageProtocol.TYPE_EVENT then
        return
    end
    if msg.channel ~= Group.GetRaidChatType() then
        return
    end
    if IsOwnEcho(msg) or not IsAuthorizedSender(msg) then
        return
    end

    local chain = SavedChain()
    if type(chain) ~= "table" then
        return
    end

    local regions, reason, detail = InterruptChain.ResolvePublication(msg.payload, Group.GetRaidMembers())
    if not regions then
        Util.Print(
            string.format(L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_FAILED, L.TWIN_FANGS_TITLE, ReceiveFailureText(reason, detail))
        )
        return
    end

    InterruptChain.ReplaceChain(chain, regions)
    local TwinFangs = ns.Modules.Get("TwinFangs")
    if TwinFangs and TwinFangs.OnInterruptChainChanged then
        TwinFangs:OnInterruptChainChanged()
    end
    Util.Print(string.format(L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVED, L.TWIN_FANGS_TITLE))
end

---Starts adopting publications. Safe to call more than once.
function InterruptChain.Listen()
    if listening then
        return
    end
    MessageProtocol.RegisterHandler(InterruptChain.SYNC_TOPIC, OnPublicationMessage)
    listening = true
end

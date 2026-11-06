---Coiled Altar interrupt-assignment raid sync: validate, serialize, multipart, apply.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Util = ns.Util
local Group = ns.Api.Group
local Player = ns.Api.Player
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm
local Timer = ns.Api.Timer

local CoiledAltar = ns.Modules.Get("CoiledAltar")
local Assignments = Internals.InterruptAssignments

local Sync = {}
Internals.InterruptSync = Sync

Sync.TOPIC = "coiled_altar.interrupts"
Sync.PAYLOAD_VERSION = "1"
Sync.REASSEMBLY_TIMEOUT = 10
Sync.MAX_PENDING_SENDERS = 8
Sync.RAID_INDEX_MAX = 40

local SID_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
local SLOT_COUNT = Assignments.SLOT_COUNT
local TYPE_EMPTY = Assignments.TYPE_EMPTY
local TYPE_PLAYER = Assignments.TYPE_PLAYER
local TYPE_TEXT = Assignments.TYPE_TEXT

local publishing = false
local listening = false
local nextSid = 0
---@type table<string, CoiledAltarInterruptSyncPending>
local pendingBySender = {}
local pendingOrder = {}

---@class CoiledAltarInterruptSyncIssue
---@field code string
---@field chainId CoiledAltarInterruptChainId|nil
---@field index integer|nil

---@class CoiledAltarInterruptSyncSnapshot
---@field assignments CoiledAltarInterruptAssignments
---@field markedChain CoiledAltarInterruptChainId

---@class CoiledAltarInterruptSyncPart
---@field sid string
---@field part integer
---@field total integer
---@field chunk string

---@class CoiledAltarInterruptSyncPending
---@field sid string
---@field total integer
---@field chunks table<integer, string>
---@field received integer
---@field timer { Cancel: fun(self: unknown) }|nil

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

---@param chainId CoiledAltarInterruptChainId|nil
---@return string
local function ChainLabel(chainId)
    if chainId == Assignments.RANGED then
        return L.COILED_ALTAR_INTERRUPT_CHAIN_RANGED
    end
    return L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE
end

---@param issue CoiledAltarInterruptSyncIssue
---@return string
local function IssueText(issue)
    local chain = ChainLabel(issue.chainId)
    local index = issue.index or 0
    if issue.code == "player_missing" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_PLAYER_MISSING, chain, index)
    end
    if issue.code == "CROSS_CHAIN" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_CROSS_CHAIN, chain, index)
    end
    if issue.code == "text_too_long" or issue.code == "invalid_text" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_TEXT_TOO_LONG, chain, index, Assignments.TEXT_MAX_CHARS)
    end
    if issue.code == "invalid_slot" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_INVALID_SLOT, chain, index)
    end
    if issue.code == "invalid_marked" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_INVALID_MARKED
    end
    if issue.code == "not_in_raid" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_NOT_IN_RAID
    end
    if issue.code == "in_progress" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_IN_PROGRESS
    end
    if type(issue.code) == "string" and issue.code ~= "" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_FAILED, issue.code)
    end
    return L.COILED_ALTAR_INTERRUPT_SYNC_FAILED_GENERIC
end

---Localized status for the Sync button. Independent of widgets.
---@param ok boolean
---@param reason string|nil
---@param issue CoiledAltarInterruptSyncIssue|nil
---@return string
---@return "success"|"error"
function Sync.StatusText(ok, reason, issue)
    if ok then
        return L.COILED_ALTAR_INTERRUPT_SYNC_SENT, "success"
    end
    if type(issue) == "table" then
        return IssueText(issue), "error"
    end
    if reason == "not_in_raid" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_NOT_IN_RAID, "error"
    end
    if reason == "in_progress" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_IN_PROGRESS, "error"
    end
    if type(reason) == "string" and reason ~= "" then
        return string.format(L.COILED_ALTAR_INTERRUPT_SYNC_FAILED, reason), "error"
    end
    return L.COILED_ALTAR_INTERRUPT_SYNC_FAILED_GENERIC, "error"
end

---@param roster RaidMember[]|nil
---@return table<string, RaidMember>
---@return table<integer, RaidMember|false>
local function RosterMaps(roster)
    local byName = {}
    local byIndex = {}
    for _, member in ipairs(roster or {}) do
        local name = Assignments.QualifyName(member.fullName or member.name)
        local index = member.index
        if name then
            byName[name] = member
        end
        if type(index) == "number" then
            if byIndex[index] then
                byIndex[index] = false
            else
                byIndex[index] = member
            end
        end
    end
    return byName, byIndex
end

---@param assignments CoiledAltarInterruptAssignments|nil
---@param markedChain any
---@param roster RaidMember[]|nil
---@return CoiledAltarInterruptSyncIssue[]
function Sync.Validate(assignments, markedChain, roster)
    local issues = {}
    if not Assignments.IsChain(markedChain) then
        issues[#issues + 1] = { code = "invalid_marked" }
    end
    if type(assignments) ~= "table" then
        issues[#issues + 1] = { code = "malformed" }
        return issues
    end

    local byName = RosterMaps(roster)
    local seen = {}
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local chain = assignments[chainId]
        if type(chain) ~= "table" then
            issues[#issues + 1] = { code = "malformed", chainId = chainId }
        else
            for index = 1, SLOT_COUNT do
                local slot = chain[index]
                if type(slot) ~= "table" then
                    issues[#issues + 1] = { code = "invalid_slot", chainId = chainId, index = index }
                elseif slot.type == TYPE_EMPTY then
                    -- Empty slots are valid.
                elseif slot.type == TYPE_TEXT then
                    if not Assignments.IsValidCustomText(slot.value) then
                        local code = "invalid_text"
                        if
                            type(slot.value) == "string"
                            and Assignments.Utf8Len(slot.value) > Assignments.TEXT_MAX_CHARS
                        then
                            code = "text_too_long"
                        end
                        issues[#issues + 1] = { code = code, chainId = chainId, index = index }
                    end
                elseif slot.type == TYPE_PLAYER then
                    local name = Assignments.QualifyName(slot.value)
                    if not name or not byName[name] then
                        issues[#issues + 1] = { code = "player_missing", chainId = chainId, index = index }
                    elseif seen[name] and seen[name] ~= chainId then
                        issues[#issues + 1] = { code = "CROSS_CHAIN", chainId = chainId, index = index }
                    else
                        seen[name] = chainId
                    end
                else
                    issues[#issues + 1] = { code = "invalid_slot", chainId = chainId, index = index }
                end
            end
        end
    end
    return issues
end

---@return string|nil
function Sync.GetPublishBlockReason()
    if Group.GetRaidChatType() == nil then
        return "not_in_raid"
    end
    if publishing then
        return "in_progress"
    end
end

---@param slot CoiledAltarInterruptSlot
---@param byName table<string, RaidMember>
---@return string|nil
---@return CoiledAltarInterruptSyncIssue|nil
local function EncodeSlot(slot, byName)
    if type(slot) ~= "table" or slot.type == TYPE_EMPTY then
        return "."
    end
    if slot.type == TYPE_PLAYER then
        local name = Assignments.QualifyName(slot.value)
        local member = name and byName[name]
        local index = member and member.index
        if type(index) ~= "number" or index < 1 or index > Sync.RAID_INDEX_MAX then
            return nil, { code = "player_missing" }
        end
        return "p" .. string.format("%02d", index)
    end
    if slot.type == TYPE_TEXT then
        if not Assignments.IsValidCustomText(slot.value) then
            return nil, { code = "invalid_text" }
        end
        local bytes = slot.value
        if #bytes > 99 then
            return nil, { code = "text_too_long" }
        end
        return "t" .. string.format("%02d", #bytes) .. bytes
    end
    return nil, { code = "invalid_slot" }
end

---Encodes one snapshot body. Does not wrap, send, or mutate saved settings.
---@param assignments CoiledAltarInterruptAssignments
---@param markedChain CoiledAltarInterruptChainId
---@param roster RaidMember[]
---@return string|nil
---@return CoiledAltarInterruptSyncIssue|nil
function Sync.EncodeSnapshot(assignments, markedChain, roster)
    if not Assignments.IsChain(markedChain) then
        return nil, { code = "invalid_marked" }
    end
    local byName = RosterMaps(roster)
    local parts = { markedChain == Assignments.RANGED and "R" or "M" }
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local chain = assignments and assignments[chainId]
        for index = 1, SLOT_COUNT do
            local encoded, issue = EncodeSlot(chain and chain[index], byName)
            if not encoded then
                if issue then
                    issue.chainId = chainId
                    issue.index = index
                end
                return nil, issue
            end
            parts[#parts + 1] = encoded
        end
    end
    return table.concat(parts)
end

---@param body string
---@param pos integer
---@param byIndex table<integer, RaidMember|false>
---@return CoiledAltarInterruptSlot|nil
---@return integer|nil
---@return string|nil
local function DecodeSlot(body, pos, byIndex)
    local kind = body:sub(pos, pos)
    if kind == "" then
        return nil, nil, "malformed"
    end
    if kind == "." then
        return { type = TYPE_EMPTY }, pos + 1
    end
    if kind == "p" then
        local digits = body:sub(pos + 1, pos + 2)
        if not digits:find("^%d%d$") then
            return nil, nil, "invalid_index"
        end
        local index = tonumber(digits)
        if not index or index < 1 or index > Sync.RAID_INDEX_MAX then
            return nil, nil, "invalid_index"
        end
        local member = byIndex[index]
        if member == false then
            return nil, nil, "ambiguous_index", index
        end
        if type(member) ~= "table" then
            return nil, nil, "player_missing", index
        end
        local name = Assignments.QualifyName(member.fullName or member.name)
        if not name then
            return nil, nil, "player_missing", index
        end
        return { type = TYPE_PLAYER, value = name }, pos + 3
    end
    if kind == "t" then
        local digits = body:sub(pos + 1, pos + 2)
        if not digits:find("^%d%d$") then
            return nil, nil, "malformed"
        end
        local length = tonumber(digits)
        if not length or length < 1 then
            return nil, nil, "malformed"
        end
        local start = pos + 3
        local finish = start + length - 1
        if finish > #body then
            return nil, nil, "malformed"
        end
        local text = body:sub(start, finish)
        if not Assignments.IsValidCustomText(text) then
            local code = "invalid_text"
            if Assignments.Utf8Len(text) > Assignments.TEXT_MAX_CHARS then
                code = "text_too_long"
            end
            return nil, nil, code
        end
        return { type = TYPE_TEXT, value = text }, finish + 1
    end
    return nil, nil, "malformed"
end

---Decodes a snapshot body against one roster. Does not persist.
---@param body string
---@param roster RaidMember[]
---@return CoiledAltarInterruptSyncSnapshot|nil
---@return string|nil
---@return table|nil
function Sync.DecodeSnapshot(body, roster)
    if type(body) ~= "string" or body == "" then
        return nil, "malformed"
    end
    local markedByte = body:sub(1, 1)
    local markedChain
    if markedByte == "M" then
        markedChain = Assignments.MELEE
    elseif markedByte == "R" then
        markedChain = Assignments.RANGED
    else
        return nil, "invalid_marked"
    end

    local _, byIndex = RosterMaps(roster)
    local assignments = {
        [Assignments.MELEE] = {},
        [Assignments.RANGED] = {},
    }
    local pos = 2
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        for index = 1, SLOT_COUNT do
            local slot, nextPos, reason, detail = DecodeSlot(body, pos, byIndex)
            if not slot then
                return nil, reason, { chainId = chainId, index = index, raidIndex = detail }
            end
            assignments[chainId][index] = slot
            pos = nextPos
        end
    end
    if pos ~= #body + 1 then
        return nil, "malformed"
    end
    return {
        assignments = assignments,
        markedChain = markedChain,
    }
end

---@param payload string
---@param roster RaidMember[]
---@return CoiledAltarInterruptSyncSnapshot|nil
---@return string|nil
---@return CoiledAltarInterruptSyncIssue|nil
function Sync.ResolveSnapshot(payloadBody, roster)
    local snapshot, reason, detail = Sync.DecodeSnapshot(payloadBody, roster)
    if not snapshot then
        local issue
        if type(detail) == "table" then
            issue = {
                code = reason,
                chainId = detail.chainId,
                index = detail.index,
            }
        end
        return nil, reason, issue
    end
    local issues = Sync.Validate(snapshot.assignments, snapshot.markedChain, roster)
    if #issues > 0 then
        return nil, issues[1].code, issues[1]
    end
    return snapshot
end

---@param sid string
---@param part integer
---@param total integer
---@return string
local function PartHeader(sid, part, total)
    return table.concat({ Sync.PAYLOAD_VERSION, sid, tostring(part), tostring(total), "" }, "|")
end

local function NextSid()
    nextSid = (nextSid % 1296) + 1
    local n = nextSid - 1
    local high = math.floor(n / 36)
    local low = n % 36
    return SID_ALPHABET:sub(high + 1, high + 1) .. SID_ALPHABET:sub(low + 1, low + 1)
end

---@param payload string
---@return boolean
local function PayloadFits(payload)
    return MessageProtocol.Encode(
        MessageProtocol.TYPE_EVENT,
        Sync.TOPIC,
        MessageProtocol.EVENT_CORRELATION_ID,
        payload
    ) ~= nil
end

---Wraps a snapshot body into one or more feature payloads. Splits only at slot boundaries.
---@param body string
---@param sid string|nil
---@return string[]|nil
---@return string|nil
function Sync.WrapSnapshot(body, sid)
    if type(body) ~= "string" or body == "" then
        return nil, "malformed"
    end
    sid = sid or NextSid()
    if type(sid) ~= "string" or #sid ~= 2 or not sid:find("^[0-9a-z]+$") then
        return nil, "malformed"
    end

    local units = { body:sub(1, 1) }
    local pos = 2
    while pos <= #body do
        local kind = body:sub(pos, pos)
        if kind == "." then
            units[#units + 1] = "."
            pos = pos + 1
        elseif kind == "p" then
            if pos + 2 > #body then
                return nil, "malformed"
            end
            units[#units + 1] = body:sub(pos, pos + 2)
            pos = pos + 3
        elseif kind == "t" then
            local digits = body:sub(pos + 1, pos + 2)
            local length = tonumber(digits)
            if not digits:find("^%d%d$") or not length then
                return nil, "malformed"
            end
            local finish = pos + 2 + length
            if finish > #body then
                return nil, "malformed"
            end
            units[#units + 1] = body:sub(pos, finish)
            pos = finish + 1
        else
            return nil, "malformed"
        end
    end

    local maxTotal = #units
    local chunks = { "" }
    for _, unit in ipairs(units) do
        local candidate = chunks[#chunks] .. unit
        local header = PartHeader(sid, maxTotal, maxTotal)
        if not PayloadFits(header .. candidate) then
            if chunks[#chunks] == "" then
                return nil, "too_large"
            end
            chunks[#chunks + 1] = unit
            if not PayloadFits(PartHeader(sid, maxTotal, maxTotal) .. unit) then
                return nil, "too_large"
            end
        else
            chunks[#chunks] = candidate
        end
    end

    local total = #chunks
    local payloads = {}
    for part, chunk in ipairs(chunks) do
        local payload = PartHeader(sid, part, total) .. chunk
        if not PayloadFits(payload) then
            return nil, "too_large"
        end
        payloads[part] = payload
    end
    return payloads
end

---@param payload string
---@return CoiledAltarInterruptSyncPart|nil
---@return string|nil
function Sync.ParsePart(payload)
    if type(payload) ~= "string" then
        return nil, "malformed"
    end
    local fields = SplitExact(payload, "|")
    if #fields < 5 then
        return nil, "malformed"
    end
    local version, sid, partText, totalText = fields[1], fields[2], fields[3], fields[4]
    if version ~= Sync.PAYLOAD_VERSION then
        return nil, "unsupported_version"
    end
    if type(sid) ~= "string" or #sid ~= 2 or not sid:find("^[0-9a-z]+$") then
        return nil, "malformed"
    end
    if not partText:find("^%d+$") or not totalText:find("^%d+$") then
        return nil, "malformed"
    end
    local part = tonumber(partText)
    local total = tonumber(totalText)
    if not part or not total or part < 1 or total < 1 or part > total or total > 99 then
        return nil, "malformed"
    end
    local header = PartHeader(sid, part, total)
    if payload:sub(1, #header) ~= header then
        return nil, "malformed"
    end
    return {
        sid = sid,
        part = part,
        total = total,
        chunk = payload:sub(#header + 1),
    }
end

local function CancelPending(entry)
    if entry and entry.timer then
        entry.timer:Cancel()
        entry.timer = nil
    end
end

local function DropSender(sender)
    local entry = pendingBySender[sender]
    if not entry then
        return
    end
    CancelPending(entry)
    pendingBySender[sender] = nil
    for index, name in ipairs(pendingOrder) do
        if name == sender then
            table.remove(pendingOrder, index)
            break
        end
    end
end

local function TouchSender(sender)
    for index, name in ipairs(pendingOrder) do
        if name == sender then
            table.remove(pendingOrder, index)
            break
        end
    end
    pendingOrder[#pendingOrder + 1] = sender
    while #pendingOrder > Sync.MAX_PENDING_SENDERS do
        DropSender(pendingOrder[1])
    end
end

---Feeds one feature payload into reassembly. Returns the body only when every part is present.
---@param sender string
---@param payload string
---@return string|nil body
---@return string|nil reason
function Sync.Collect(sender, payload)
    local part, parseReason = Sync.ParsePart(payload)
    if not part then
        return nil, parseReason
    end
    if type(sender) ~= "string" or sender == "" then
        return nil, "malformed"
    end

    local existing = pendingBySender[sender]
    if existing and existing.sid ~= part.sid then
        DropSender(sender)
        existing = nil
    end

    if part.total == 1 then
        if existing then
            DropSender(sender)
        end
        if part.part ~= 1 then
            return nil, "malformed"
        end
        return part.chunk
    end

    if not existing then
        existing = {
            sid = part.sid,
            total = part.total,
            chunks = {},
            received = 0,
        }
        pendingBySender[sender] = existing
        TouchSender(sender)
        existing.timer = Timer.NewTimer(Sync.REASSEMBLY_TIMEOUT, function()
            DropSender(sender)
        end)
    elseif existing.total ~= part.total then
        DropSender(sender)
        return nil, "malformed"
    else
        TouchSender(sender)
    end

    local previous = existing.chunks[part.part]
    if previous then
        if previous ~= part.chunk then
            DropSender(sender)
            return nil, "malformed"
        end
        return nil
    end

    existing.chunks[part.part] = part.chunk
    existing.received = existing.received + 1
    if existing.received < existing.total then
        return nil
    end

    local pieces = {}
    for index = 1, existing.total do
        local chunk = existing.chunks[index]
        if type(chunk) ~= "string" then
            DropSender(sender)
            return nil, "malformed"
        end
        pieces[index] = chunk
    end
    DropSender(sender)
    return table.concat(pieces)
end

---Clears incomplete reassembly state. Used by tests.
function Sync.ResetPending()
    while #pendingOrder > 0 do
        DropSender(pendingOrder[1])
    end
end

---@param assignments CoiledAltarInterruptAssignments
---@param markedChain CoiledAltarInterruptChainId
---@param roster RaidMember[]
---@return string[]|nil
---@return string|nil
---@return CoiledAltarInterruptSyncIssue|nil
function Sync.EncodePublication(assignments, markedChain, roster)
    local issues = Sync.Validate(assignments, markedChain, roster)
    if #issues > 0 then
        return nil, issues[1].code, issues[1]
    end
    local body, encodeIssue = Sync.EncodeSnapshot(assignments, markedChain, roster)
    if not body then
        return nil, encodeIssue and encodeIssue.code, encodeIssue
    end
    local payloads, wrapReason = Sync.WrapSnapshot(body)
    if not payloads then
        return nil, wrapReason
    end
    return payloads
end

---Publishes the current interrupt snapshot as CONTROL event(s). Sender only.
---@return boolean
---@return string|nil
---@return CoiledAltarInterruptSyncIssue|nil
function Sync.Publish()
    local block = Sync.GetPublishBlockReason()
    if block then
        return false, block, { code = block }
    end

    local assignments = CoiledAltar.db.assignments
    local markedChain = CoiledAltar:GetMarkedChain()
    local roster = Group.GetRaidMembers()
    local payloads, reason, issue = Sync.EncodePublication(assignments, markedChain, roster)
    if not payloads then
        return false, reason, issue
    end

    local channel = Group.GetRaidChatType()
    publishing = true
    local ok, sendReason
    for _, payload in ipairs(payloads) do
        ok, sendReason = MessageProtocolComm.Send(
            MessageProtocol.TYPE_EVENT,
            Sync.TOPIC,
            MessageProtocol.EVENT_CORRELATION_ID,
            payload,
            channel,
            { trafficClass = MessageProtocolComm.TrafficClass.CONTROL }
        )
        if not ok then
            publishing = false
            return false, sendReason
        end
    end
    publishing = false
    return true
end

local function ReceiveFailureText(reason, issue)
    if type(issue) == "table" then
        return IssueText(issue)
    end
    if reason == "unsupported_version" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_VERSION
    end
    if reason == "player_missing" or reason == "ambiguous_index" or reason == "invalid_index" then
        return L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_MISSING
    end
    if type(reason) == "string" and reason ~= "" then
        if
            reason == "malformed"
            or reason == "invalid_marked"
            or reason == "invalid_slot"
            or reason == "invalid_text"
            or reason == "text_too_long"
            or reason == "CROSS_CHAIN"
        then
            return L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_MALFORMED
        end
        return reason
    end
    return L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_MALFORMED
end

---@param msg MessageProtocolMessage
---@return boolean
local function IsOwnEcho(msg)
    return msg.sender == Player.GetFullName()
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

    local body, collectReason = Sync.Collect(msg.sender, msg.payload)
    if collectReason then
        Util.Print(string.format(L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_FAILED, ReceiveFailureText(collectReason)))
        return
    end
    if not body then
        return
    end

    local snapshot, reason, issue = Sync.ResolveSnapshot(body, Group.GetRaidMembers())
    if not snapshot then
        Util.Print(string.format(L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVE_FAILED, ReceiveFailureText(reason, issue)))
        return
    end

    CoiledAltar:ReplaceInterruptSnapshot(snapshot.assignments, snapshot.markedChain)
    Util.Print(L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVED)
end

---Starts adopting publications. Safe to call more than once.
function Sync.Listen()
    if listening then
        return
    end
    MessageProtocol.RegisterHandler(Sync.TOPIC, OnPublicationMessage)
    listening = true
end

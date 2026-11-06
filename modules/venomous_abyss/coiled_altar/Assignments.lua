local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Player = ns.Api.Player
local Unit = ns.Api.Unit

local CoiledAltar = ns.Modules.Get("CoiledAltar")

local MELEE = "MELEE"
local RANGED = "RANGED"
local SLOT_COUNT = 6
local TEXT_MAX_CHARS = 12
local TYPE_EMPTY = "empty"
local TYPE_PLAYER = "player"
local TYPE_TEXT = "text"

---@alias CoiledAltarInterruptChainId "MELEE"|"RANGED"
---@alias CoiledAltarInterruptSlotType "empty"|"player"|"text"

---@class CoiledAltarInterruptSlot
---@field type CoiledAltarInterruptSlotType
---@field value string|nil  Player Name-Realm, or custom display text.

---@class CoiledAltarInterruptAssignments
---@field MELEE CoiledAltarInterruptSlot[]
---@field RANGED CoiledAltarInterruptSlot[]

local Assignments = {
    MELEE = MELEE,
    RANGED = RANGED,
    CHAIN_IDS = { MELEE, RANGED },
    SLOT_COUNT = SLOT_COUNT,
    TEXT_MAX_CHARS = TEXT_MAX_CHARS,
    TYPE_EMPTY = TYPE_EMPTY,
    TYPE_PLAYER = TYPE_PLAYER,
    TYPE_TEXT = TYPE_TEXT,
}
Internals.InterruptAssignments = Assignments

---Only the raid leader can edit assignments; everyone else is member-view only.
---@return boolean
function Assignments.CanEdit()
    return ns.Api.Group.IsPlayerRaidLeader()
end

---Picks the settings chain view. Same rules as Twin Fangs.
---@param canEdit boolean
---@param preferMemberView boolean
---@return boolean showEditor
---@return boolean preferMemberView
function Assignments.ResolveSettingsView(canEdit, preferMemberView)
    if not canEdit then
        return false, false
    end
    return not preferMemberView, preferMemberView
end

---@param chainId any
---@return boolean
function Assignments.IsChain(chainId)
    return chainId == MELEE or chainId == RANGED
end

---@param chainId any
---@return CoiledAltarInterruptChainId|nil
function Assignments.OppositeChain(chainId)
    if chainId == MELEE then
        return RANGED
    end
    if chainId == RANGED then
        return MELEE
    end
    return nil
end

---@return CoiledAltarInterruptSlot
local function EmptySlot()
    return { type = TYPE_EMPTY }
end

---@param slot CoiledAltarInterruptSlot|nil
---@return CoiledAltarInterruptSlot
function Assignments.CopySlot(slot)
    if type(slot) ~= "table" then
        return EmptySlot()
    end
    if slot.type == TYPE_PLAYER or slot.type == TYPE_TEXT then
        if type(slot.value) == "string" and slot.value ~= "" then
            return { type = slot.type, value = slot.value }
        end
        return EmptySlot()
    end
    return EmptySlot()
end

---@param text string
---@param index integer
---@return integer
local function Utf8Next(text, index)
    local byte = string.byte(text, index)
    if not byte then
        return index + 1
    end
    if byte >= 240 then
        return index + 4
    elseif byte >= 224 then
        return index + 3
    elseif byte >= 192 then
        return index + 2
    end
    return index + 1
end

---@param text string
---@return integer
function Assignments.Utf8Len(text)
    local count = 0
    local index = 1
    while index <= #text do
        count = count + 1
        index = Utf8Next(text, index)
    end
    return count
end

---Trims and qualifies a roster identity. Empty input is rejected.
---@param name any
---@return string|nil
function Assignments.QualifyName(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return nil
    end
    return Unit.GetFullName(name)
end

---Strips WoW escapes and control characters. Rejects empty or over-long text instead of truncating.
---@param text any
---@return string|nil
function Assignments.SanitizeText(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("|", "")
    text = text:gsub("[%z\1-\31\127]", "")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then
        return nil
    end
    if Assignments.Utf8Len(text) > TEXT_MAX_CHARS then
        return nil
    end
    return text
end

---@param slot any
---@return CoiledAltarInterruptSlot
local function SanitizeSlot(slot)
    if type(slot) ~= "table" then
        return EmptySlot()
    end
    if slot.type == TYPE_PLAYER then
        local name = Assignments.QualifyName(slot.value)
        if name then
            return { type = TYPE_PLAYER, value = name }
        end
        return EmptySlot()
    end
    if slot.type == TYPE_TEXT then
        local text = Assignments.SanitizeText(slot.value)
        if text then
            return { type = TYPE_TEXT, value = text }
        end
        return EmptySlot()
    end
    return EmptySlot()
end

---@param chain any
---@return CoiledAltarInterruptSlot[]
local function SanitizeChain(chain)
    local slots = {}
    if type(chain) == "table" then
        for index = 1, SLOT_COUNT do
            slots[index] = SanitizeSlot(chain[index])
        end
    else
        for index = 1, SLOT_COUNT do
            slots[index] = EmptySlot()
        end
    end
    return slots
end

---Repairs a saved two-chain table. Always six slots per chain; unknown keys are dropped.
---@param saved any
---@return CoiledAltarInterruptAssignments
function Assignments.SanitizeSaved(saved)
    if type(saved) ~= "table" then
        saved = {}
    end
    return {
        [MELEE] = SanitizeChain(saved[MELEE]),
        [RANGED] = SanitizeChain(saved[RANGED]),
    }
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@return CoiledAltarInterruptSlot[]|nil
local function GetChain(assignments, chainId)
    if type(assignments) ~= "table" or not Assignments.IsChain(chainId) then
        return nil
    end
    return assignments[chainId]
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@return CoiledAltarInterruptSlot|nil
function Assignments.GetSlot(assignments, chainId, index)
    local chain = GetChain(assignments, chainId)
    if not chain or type(index) ~= "number" or index < 1 or index > SLOT_COUNT then
        return nil
    end
    return chain[index]
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@param slot CoiledAltarInterruptSlot
---@return boolean
local function WriteSlot(assignments, chainId, index, slot)
    local chain = GetChain(assignments, chainId)
    if not chain or type(index) ~= "number" or index < 1 or index > SLOT_COUNT then
        return false
    end
    local current = chain[index]
    if current.type == slot.type and current.value == slot.value then
        return false
    end
    chain[index] = slot
    return true
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param identity any
---@return boolean
function Assignments.ChainHasPlayer(assignments, chainId, identity)
    local name = Assignments.QualifyName(identity)
    if not name then
        return false
    end
    local chain = GetChain(assignments, chainId)
    if not chain then
        return false
    end
    for index = 1, SLOT_COUNT do
        local slot = chain[index]
        if type(slot) == "table" and slot.type == TYPE_PLAYER and slot.value == name then
            return true
        end
    end
    return false
end

---Qualified names that occupy at least one player slot in both chains. Text slots are ignored.
---@param assignments CoiledAltarInterruptAssignments|nil
---@return string[]
function Assignments.CrossChainPlayers(assignments)
    local names = {}
    if type(assignments) ~= "table" then
        return names
    end
    local seen = {}
    local melee = assignments[MELEE]
    if type(melee) ~= "table" then
        return names
    end
    for index = 1, SLOT_COUNT do
        local slot = melee[index]
        if type(slot) == "table" and slot.type == TYPE_PLAYER then
            local name = Assignments.QualifyName(slot.value)
            if name and not seen[name] and Assignments.ChainHasPlayer(assignments, RANGED, name) then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@param name any
---@return boolean
---@return "CROSS_CHAIN"|nil
---@return CoiledAltarInterruptChainId|nil
function Assignments.SetPlayer(assignments, chainId, index, name)
    local qualified = Assignments.QualifyName(name)
    if not qualified then
        return false
    end
    local current = Assignments.GetSlot(assignments, chainId, index)
    if current and current.type == TYPE_PLAYER and current.value == qualified then
        return false
    end
    local opposite = Assignments.OppositeChain(chainId)
    if opposite and Assignments.ChainHasPlayer(assignments, opposite, qualified) then
        return false, "CROSS_CHAIN", opposite
    end
    return WriteSlot(assignments, chainId, index, { type = TYPE_PLAYER, value = qualified })
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@param text any
---@return boolean
function Assignments.SetText(assignments, chainId, index, text)
    local sanitized = Assignments.SanitizeText(text)
    if not sanitized then
        return false
    end
    return WriteSlot(assignments, chainId, index, { type = TYPE_TEXT, value = sanitized })
end

---@param assignments CoiledAltarInterruptAssignments
---@param chainId any
---@param index any
---@return boolean
function Assignments.ClearSlot(assignments, chainId, index)
    return WriteSlot(assignments, chainId, index, EmptySlot())
end

---Slots in one chain that belong to this player. Both chains occupied is treated as unset.
---@param assignments CoiledAltarInterruptAssignments|nil
---@param identity any
---@return CoiledAltarInterruptChainId|nil
---@return integer[]
function Assignments.PlayerPositions(assignments, identity)
    local indices = {}
    if type(assignments) ~= "table" then
        return nil, indices
    end
    local name = Assignments.QualifyName(identity)
    if not name then
        return nil, indices
    end
    local foundId
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local chain = assignments[chainId]
        if type(chain) == "table" then
            local chainIndices = {}
            for index = 1, SLOT_COUNT do
                local slot = chain[index]
                if type(slot) == "table" and slot.type == TYPE_PLAYER and slot.value == name then
                    chainIndices[#chainIndices + 1] = index
                end
            end
            if #chainIndices > 0 then
                if foundId then
                    return nil, {}
                end
                foundId = chainId
                indices = chainIndices
            end
        end
    end
    return foundId, indices
end

---@class CoiledAltarInterruptAssignment
---@field chainId CoiledAltarInterruptChainId
---@field indices integer[]

---Local player's interrupt-chain assignment for the current saved config, or nil.
---@return CoiledAltarInterruptAssignment|nil
function Internals.LocalInterruptAssignment()
    local chainId, indices = Assignments.PlayerPositions(CoiledAltar.db.assignments, Player.GetFullName())
    if chainId and #indices > 0 then
        return { chainId = chainId, indices = indices }
    end
    return nil
end

---@param assignments CoiledAltarInterruptAssignments|nil
---@return boolean
function Assignments.HasAssignments(assignments)
    if type(assignments) ~= "table" then
        return false
    end
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local chain = assignments[chainId]
        if type(chain) == "table" then
            for index = 1, SLOT_COUNT do
                local slot = chain[index]
                if type(slot) == "table" and (slot.type == TYPE_PLAYER or slot.type == TYPE_TEXT) then
                    return true
                end
            end
        end
    end
    return false
end

---Whether `text` is acceptable custom slot content, including protocol delimiters.
---Unlike SanitizeText, this does not strip `|` or rewrite the value.
---@param text any
---@return boolean
function Assignments.IsValidCustomText(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    if text:find("[%z\1-\31\127]") then
        return false
    end
    return Assignments.Utf8Len(text) <= TEXT_MAX_CHARS
end

---Replaces both chains in `target` from `source`. Does not notify.
---@param target CoiledAltarInterruptAssignments
---@param source CoiledAltarInterruptAssignments
function Assignments.Replace(target, source)
    local incoming = Assignments.SanitizeSaved(source)
    if type(source) == "table" then
        for _, chainId in ipairs(Assignments.CHAIN_IDS) do
            local chain = source[chainId]
            if type(chain) == "table" then
                for index = 1, SLOT_COUNT do
                    local slot = chain[index]
                    if type(slot) == "table" and slot.type == TYPE_TEXT and Assignments.IsValidCustomText(slot.value) then
                        incoming[chainId][index] = { type = TYPE_TEXT, value = slot.value }
                    end
                end
            end
        end
    end
    target[MELEE] = incoming[MELEE]
    target[RANGED] = incoming[RANGED]
end

---Empties every slot in both chains. Returns true if anything changed.
---@param assignments CoiledAltarInterruptAssignments
---@return boolean
function Assignments.ClearAll(assignments)
    if type(assignments) ~= "table" then
        return false
    end
    local changed = false
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        for index = 1, SLOT_COUNT do
            if Assignments.ClearSlot(assignments, chainId, index) then
                changed = true
            end
        end
    end
    return changed
end

local function Notify()
    if CoiledAltar.OnInterruptAssignmentsChanged then
        CoiledAltar:OnInterruptAssignmentsChanged()
    end
    Internals.NotifyEncounterState()
end

---@param chainId CoiledAltarInterruptChainId
---@param index integer
---@return CoiledAltarInterruptSlot|nil
function CoiledAltar:GetInterruptSlot(chainId, index)
    local slot = Assignments.GetSlot(self.db.assignments, chainId, index)
    if not slot then
        return nil
    end
    return Assignments.CopySlot(slot)
end

---@return CoiledAltarInterruptAssignments
function CoiledAltar:GetInterruptAssignments()
    return self.db.assignments
end

---@param chainId CoiledAltarInterruptChainId
---@param index integer
---@param name string
---@return boolean
---@return "CROSS_CHAIN"|nil
---@return CoiledAltarInterruptChainId|nil
function CoiledAltar:AssignInterruptPlayer(chainId, index, name)
    local changed, err, occupiedChain = Assignments.SetPlayer(self.db.assignments, chainId, index, name)
    if not changed then
        return false, err, occupiedChain
    end
    Notify()
    return true
end

---@param chainId CoiledAltarInterruptChainId
---@param index integer
---@param text string
---@return boolean
function CoiledAltar:AssignInterruptText(chainId, index, text)
    if not Assignments.SetText(self.db.assignments, chainId, index, text) then
        return false
    end
    Notify()
    return true
end

---@param chainId CoiledAltarInterruptChainId
---@param index integer
---@return boolean
function CoiledAltar:ClearInterruptAssignment(chainId, index)
    if not Assignments.ClearSlot(self.db.assignments, chainId, index) then
        return false
    end
    Notify()
    return true
end

---@return boolean
function CoiledAltar:HasInterruptAssignments()
    return Assignments.HasAssignments(self.db.assignments)
end

---@return boolean
function CoiledAltar:ClearAllInterruptAssignments()
    if not Assignments.ClearAll(self.db.assignments) then
        return false
    end
    Notify()
    return true
end

---Atomically replaces both interrupt chains and the marked-enemy side, then notifies.
---@param assignments CoiledAltarInterruptAssignments
---@param markedChain CoiledAltarInterruptChainId
function CoiledAltar:ReplaceInterruptSnapshot(assignments, markedChain)
    Assignments.Replace(self.db.assignments, assignments)
    if Assignments.IsChain(markedChain) then
        self.db.markedChain = markedChain
    else
        self.db.markedChain = MELEE
    end
    Notify()
end

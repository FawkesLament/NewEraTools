local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Chain = Internals.InterruptChain

---Presentation helpers for consecutive-interrupt rows in the Raid Leader Editor.
local Preview = {}
Internals.InterruptChainPreview = Preview

Preview.MIN_COUNT = Chain.REPEAT_MIN
Preview.MAX_COUNT = Chain.REPEAT_MAX

---@param count integer
---@return string
function Preview.FormatCount(count)
    return string.format(L.TWIN_FANGS_INTERRUPT_COUNT_OPTION, Chain.ClampRepeat(count))
end

---@param first integer
---@param last integer
---@return string
function Preview.FormatSequence(first, last)
    if first == last then
        return string.format(L.TWIN_FANGS_INTERRUPT_SEQUENCE, first)
    end
    return string.format(L.TWIN_FANGS_INTERRUPT_SEQUENCE_RANGE, first, last)
end

---@return DropdownItem[]
function Preview.CountItems()
    local items = {}
    for count = Preview.MIN_COUNT, Preview.MAX_COUNT do
        items[#items + 1] = { value = count, text = Preview.FormatCount(count) }
    end
    return items
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@return TwinFangsInterruptPreviewEntry[]
function Preview.RegionEntries(state, regionId)
    ---@class TwinFangsInterruptPreviewEntry
    ---@field player TwinFangsInterruptPlayer
    ---@field guid string|nil
    ---@field count integer
    ---@field first integer
    ---@field last integer
    ---@field sequence string

    local region = Chain.GetRegion(state, regionId)
    local entries = {}
    for _, block in ipairs(Chain.Blocks(region.players)) do
        local member = Chain.GetMember(state, block.player)
        entries[#entries + 1] = {
            player = block.player,
            guid = member and member.guid,
            count = block.count,
            first = block.first,
            last = block.last,
            sequence = Preview.FormatSequence(block.first, block.last),
        }
    end
    return entries
end

---@param entries TwinFangsInterruptPreviewEntry[]
---@return integer
function Preview.TotalTurns(entries)
    if #entries == 0 then
        return 0
    end
    return entries[#entries].last
end

---@param displayName string
---@param entry TwinFangsInterruptPreviewEntry
---@return string
function Preview.OverviewLine(displayName, entry)
    if entry.count > Preview.MIN_COUNT then
        return string.format("%s  %s  %s", entry.sequence, displayName, Preview.FormatCount(entry.count))
    end
    return string.format("%s  %s", entry.sequence, displayName)
end

---@param entries TwinFangsInterruptPreviewEntry[]
---@return string|nil
function Preview.OverviewSummary(entries)
    if #entries == 0 then
        return nil
    end
    return string.format(L.TWIN_FANGS_INTERRUPT_CHAIN_SUMMARY, #entries, Preview.TotalTurns(entries))
end

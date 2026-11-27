---Pure column planner for DebuffMonitor: members and layout config to column data. No frames.
local _, ns = ...
local L = ns.L

local Columns = {}
ns.DebuffMonitorColumns = Columns

local LAYOUT_SINGLE = "single"
local LAYOUT_SPLIT = "split"
local LAYOUT_ROSTER = "roster"
local DEFAULT_MAX_GROUPS = 8
local DEFAULT_MAX_GROUP_SIZE = 5

---@param subgroups number[]
---@param explicit string|nil
---@return string|nil
local function GroupLabel(subgroups, explicit)
    if type(explicit) == "string" and explicit ~= "" then
        return explicit
    end
    if type(subgroups) ~= "table" or #subgroups == 0 then
        return nil
    end
    if #subgroups == 1 then
        return string.format(L.DEBUFF_MONITOR_GROUP, subgroups[1])
    end
    return string.format(L.DEBUFF_MONITOR_GROUP_RANGE, subgroups[1], subgroups[#subgroups])
end

---@param members DebuffMonitorMember[]|nil
---@return DebuffMonitorMember[]
local function OrderedMembers(members)
    local ordered = {}
    if type(members) ~= "table" then
        return ordered
    end
    local allIndexed = true
    for index, member in ipairs(members) do
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

---@param members DebuffMonitorMember[]
---@param maxGroups number
---@param maxGroupSize number
---@param omitEmpty boolean
---@param collapse boolean
---@return DebuffMonitorColumnData[]
local function OrganizeBySubgroup(members, maxGroups, maxGroupSize, omitEmpty, collapse)
    local buckets = {}
    for group = 1, maxGroups do
        buckets[group] = {}
    end
    for _, member in ipairs(OrderedMembers(members)) do
        local group = member.subgroup
        if type(group) == "number" and group >= 1 and group <= maxGroups then
            local list = buckets[group]
            if #list < maxGroupSize then
                list[#list + 1] = member
            end
        end
    end
    local columns = {}
    for group = 1, maxGroups do
        local list = buckets[group]
        if not omitEmpty or #list > 0 then
            columns[#columns + 1] = {
                group = group,
                label = GroupLabel({ group }),
                members = list,
                collapse = collapse,
            }
        end
    end
    return columns
end

---@param members DebuffMonitorMember[]
---@param columnCount number
---@param rowsPerColumn number|nil
---@param collapse boolean
---@return DebuffMonitorColumnData[]
local function OrganizeGrid(members, columnCount, rowsPerColumn, collapse)
    local ordered = OrderedMembers(members)
    local cols = math.max(1, columnCount)
    local rows = rowsPerColumn
    if type(rows) ~= "number" or rows < 1 then
        rows = math.max(1, math.ceil(math.max(#ordered, 1) / cols))
    end
    local columns = {}
    for slot = 1, cols do
        columns[slot] = {
            group = slot,
            label = nil,
            members = {},
            collapse = collapse,
        }
    end
    for index, member in ipairs(ordered) do
        local col = math.floor((index - 1) / rows) + 1
        if col >= 1 and col <= cols then
            local list = columns[col].members
            list[#list + 1] = member
        end
    end
    return columns
end

---@param config DebuffMonitorConfig
---@param members DebuffMonitorMember[]|nil
---@return DebuffMonitorColumnData[]
function Columns.BuildColumns(config, members)
    members = members or {}
    local layoutMode = config.layoutMode or LAYOUT_ROSTER
    local maxGroups = config.maxGroups or DEFAULT_MAX_GROUPS
    local maxGroupSize = config.maxGroupSize or DEFAULT_MAX_GROUP_SIZE
    local omitEmpty = config.omitEmptyGroups ~= false
    if layoutMode == LAYOUT_SINGLE then
        return {
            {
                group = 1,
                label = nil,
                members = OrderedMembers(members),
                collapse = true,
            },
        }
    end
    if layoutMode == LAYOUT_SPLIT then
        local splitGroups = config.splitGroups
        if type(splitGroups) ~= "table" or #splitGroups == 0 then
            splitGroups = {
                { subgroups = { 1, 2 } },
                { subgroups = { 3, 4 } },
            }
        end
        local wanted = {}
        for slot, spec in ipairs(splitGroups) do
            wanted[slot] = {}
            for _, group in ipairs(spec.subgroups or {}) do
                wanted[slot][group] = true
            end
        end
        local columns = {}
        for slot, spec in ipairs(splitGroups) do
            columns[slot] = {
                group = spec.subgroups and spec.subgroups[1] or slot,
                label = GroupLabel(spec.subgroups or {}, spec.label),
                members = {},
                collapse = true,
            }
        end
        for _, member in ipairs(OrderedMembers(members)) do
            for slot, spec in ipairs(splitGroups) do
                if wanted[slot][member.subgroup] then
                    local list = columns[slot].members
                    if #list < maxGroupSize * #(spec.subgroups or {}) then
                        list[#list + 1] = member
                    end
                    break
                end
            end
        end
        return columns
    end
    if type(config.columnCount) == "number" and config.columnCount > 0 and config.groupBy ~= "subgroup" then
        return OrganizeGrid(members, config.columnCount, config.rowsPerColumn, false)
    end
    return OrganizeBySubgroup(members, maxGroups, maxGroupSize, omitEmpty, false)
end

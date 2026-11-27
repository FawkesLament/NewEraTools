---Pure column planner for DebuffMonitor: members and layout config to column data. No frames.
local _, ns = ...

local Columns = {}
ns.DebuffMonitorColumns = Columns

local SPLIT_PLAYER = "player"
local SPLIT_SUBGROUP = "subgroup"

---@param subgroups number[]
---@return string|nil
local function SubgroupHeader(subgroups)
    if type(subgroups) ~= "table" or #subgroups == 0 then
        return nil
    end
    if #subgroups == 1 then
        return tostring(subgroups[1])
    end
    local consecutive = true
    for index = 2, #subgroups do
        if subgroups[index] ~= subgroups[index - 1] + 1 then
            consecutive = false
            break
        end
    end
    if consecutive then
        return string.format("%d-%d", subgroups[1], subgroups[#subgroups])
    end
    local parts = {}
    for index, group in ipairs(subgroups) do
        parts[index] = tostring(group)
    end
    return table.concat(parts, ",")
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

---@param n number
---@param columnCount number
---@return number[]
local function LeftHeavySizes(n, columnCount)
    local sizes = {}
    if n <= 0 then
        return sizes
    end
    local cols = math.max(1, math.min(math.floor(columnCount), n))
    local base = math.floor(n / cols)
    local extra = n % cols
    for slot = 1, cols do
        sizes[slot] = base + (slot <= extra and 1 or 0)
    end
    return sizes
end

---@param members DebuffMonitorMember[]
---@param columnCount number
---@param collapse boolean
---@return DebuffMonitorColumnData[]
local function OrganizeByPlayer(members, columnCount, collapse)
    local ordered = OrderedMembers(members)
    local cols = columnCount
    if type(cols) ~= "number" or cols < 1 then
        cols = 1
    end
    local sizes = LeftHeavySizes(#ordered, cols)
    if #sizes == 0 then
        return {
            {
                group = 1,
                label = nil,
                members = {},
                collapse = collapse,
            },
        }
    end
    local columns = {}
    local cursor = 1
    for slot, size in ipairs(sizes) do
        local list = {}
        for offset = 1, size do
            list[offset] = ordered[cursor]
            cursor = cursor + 1
        end
        columns[slot] = {
            group = slot,
            label = nil,
            members = list,
            collapse = collapse,
        }
    end
    return columns
end

---@param members DebuffMonitorMember[]
---@param maxGroups number|nil
---@return number[]
---@return table<number, DebuffMonitorMember[]>
local function ActiveSubgroupBuckets(members, maxGroups, maxGroupSize)
    local buckets = {}
    local groups = {}
    for _, member in ipairs(OrderedMembers(members)) do
        local group = member.subgroup
        if type(group) == "number" and group >= 1 then
            if maxGroups == nil or group <= maxGroups then
                local list = buckets[group]
                if not list then
                    list = {}
                    buckets[group] = list
                    groups[#groups + 1] = group
                end
                if type(maxGroupSize) ~= "number" or maxGroupSize < 1 or #list < maxGroupSize then
                    list[#list + 1] = member
                end
            end
        end
    end
    table.sort(groups)
    return groups, buckets
end

---@param config DebuffMonitorConfig
---@param members DebuffMonitorMember[]
---@param collapse boolean
---@return DebuffMonitorColumnData[]
local function OrganizeBySubgroup(config, members, collapse)
    local groups, buckets = ActiveSubgroupBuckets(members, config.maxGroups, config.maxGroupSize)
    local columnCount = config.columns
    if type(columnCount) ~= "number" or columnCount < 1 then
        columnCount = math.max(#groups, 1)
    end
    local sizes = LeftHeavySizes(#groups, columnCount)
    if #sizes == 0 then
        return {}
    end
    local columns = {}
    local cursor = 1
    for slot, size in ipairs(sizes) do
        local subgroups = {}
        local list = {}
        for offset = 1, size do
            local group = groups[cursor]
            subgroups[offset] = group
            local bucket = buckets[group]
            for _, member in ipairs(bucket) do
                list[#list + 1] = member
            end
            cursor = cursor + 1
        end
        columns[slot] = {
            group = subgroups[1] or slot,
            label = SubgroupHeader(subgroups),
            members = list,
            collapse = collapse,
            subgroups = subgroups,
        }
    end
    return columns
end

---@param config DebuffMonitorConfig
---@param members DebuffMonitorMember[]|nil
---@return DebuffMonitorColumnData[]
function Columns.BuildColumns(config, members)
    members = members or {}
    if type(config.organize) == "function" then
        local custom = config.organize(members)
        if type(custom) == "table" then
            for _, column in ipairs(custom) do
                if column.collapse == nil then
                    column.collapse = config.collapseEmpty == true
                end
            end
            return custom
        end
    end
    local collapse = config.collapseEmpty == true
    if config.splitBy == SPLIT_SUBGROUP then
        return OrganizeBySubgroup(config, members, collapse)
    end
    return OrganizeByPlayer(members, config.columns, collapse)
end

local Loader = require("helpers.loader")

describe("DebuffMonitorColumns", function()
    local ns

    before_each(function()
        ns = Loader.Load()
        assert(loadfile("ui/DebuffMonitorColumns.lua"))("NewEraTools", ns)
    end)

    local function MembersForGroups(groupCount, groupSize)
        groupSize = groupSize or 5
        local members = {}
        for group = 1, groupCount do
            for slot = 1, groupSize do
                local index = (group - 1) * groupSize + slot
                members[index] = {
                    name = "Player" .. index,
                    index = index,
                    subgroup = group,
                }
            end
        end
        return members
    end

    local function SubgroupsOf(column)
        local seen = {}
        local groups = {}
        for _, member in ipairs(column.members) do
            local group = member.subgroup
            if not seen[group] then
                seen[group] = true
                groups[#groups + 1] = group
            end
        end
        return groups
    end

    it("gives each active subgroup its own column by default", function()
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
        }, MembersForGroups(4))
        assert.equals(4, #columns)
        for slot = 1, 4 do
            assert.same({ slot }, SubgroupsOf(columns[slot]))
            assert.equals(tostring(slot), columns[slot].label)
            assert.equals(5, #columns[slot].members)
            assert.is_false(columns[slot].collapse)
        end
    end)

    it("splits four active subgroups into two left-heavy columns", function()
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
            columns = 2,
        }, MembersForGroups(4))
        assert.equals(2, #columns)
        assert.same({ 1, 2 }, SubgroupsOf(columns[1]))
        assert.same({ 3, 4 }, SubgroupsOf(columns[2]))
        assert.equals("1-2", columns[1].label)
        assert.equals("3-4", columns[2].label)
        assert.equals(10, #columns[1].members)
        assert.equals(10, #columns[2].members)
    end)

    it("splits five active subgroups into two left-heavy columns", function()
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
            columns = 2,
        }, MembersForGroups(5))
        assert.equals(2, #columns)
        assert.same({ 1, 2, 3 }, SubgroupsOf(columns[1]))
        assert.same({ 4, 5 }, SubgroupsOf(columns[2]))
        assert.equals("1-3", columns[1].label)
        assert.equals("4-5", columns[2].label)
        assert.equals(15, #columns[1].members)
        assert.equals(10, #columns[2].members)
    end)

    it("splits six active subgroups into two equal columns", function()
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
            columns = 2,
        }, MembersForGroups(6))
        assert.equals(2, #columns)
        assert.same({ 1, 2, 3 }, SubgroupsOf(columns[1]))
        assert.same({ 4, 5, 6 }, SubgroupsOf(columns[2]))
        assert.equals("1-3", columns[1].label)
        assert.equals("4-6", columns[2].label)
        assert.equals(15, #columns[1].members)
        assert.equals(15, #columns[2].members)
    end)

    it("joins non-consecutive subgroups with commas in the header", function()
        local members = {
            { name = "A", index = 1, subgroup = 1 },
            { name = "B", index = 2, subgroup = 3 },
            { name = "C", index = 3, subgroup = 5 },
        }
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
            columns = 2,
        }, members)
        assert.equals(2, #columns)
        assert.equals("1,3", columns[1].label)
        assert.equals("5", columns[2].label)
    end)

    it("uses a custom organize function when provided", function()
        local members = MembersForGroups(2)
        local columns = ns.DebuffMonitorColumns.BuildColumns({
            splitBy = "subgroup",
            columns = 2,
            collapseEmpty = true,
            organize = function(roster)
                assert.equals(10, #roster)
                return {
                    {
                        group = 9,
                        label = "custom",
                        members = { roster[1] },
                    },
                }
            end,
        }, members)
        assert.equals(1, #columns)
        assert.equals("custom", columns[1].label)
        assert.is_true(columns[1].collapse)
        assert.equals(members[1], columns[1].members[1])
    end)
end)

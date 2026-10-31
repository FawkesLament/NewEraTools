local Loader = require("helpers.loader")

local function Names(column)
    local names = {}
    for index, member in ipairs(column.members) do
        names[index] = member.name
    end
    return names
end

local function Groups(columns)
    local groups = {}
    for index, column in ipairs(columns) do
        groups[index] = column.group
    end
    return groups
end

local function Member(name, subgroup, index, extras)
    local member = {
        name = name,
        subgroup = subgroup,
        index = index,
        classFile = "MAGE",
        unit = "raid" .. index,
    }
    if extras then
        for key, value in pairs(extras) do
            member[key] = value
        end
    end
    return member
end

describe("TwinFangs venom roster", function()
    local ns, Module, Schema, VenomRoster

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Schema = ns.Modules.Internals("TwinFangs").Schema
        VenomRoster = ns.Modules.Internals("TwinFangs").VenomRoster
    end)

    it("places a single player in one group-1 column", function()
        local columns = VenomRoster.Organize({ Member("A", 1, 1) })
        assert.equals(1, #columns)
        assert.equals(1, columns[1].group)
        assert.same({ "A" }, Names(columns[1]))
    end)

    it("maps raid sizes 1 through 30 onto populated subgroups", function()
        for size = 1, 30 do
            local members = VenomRoster.BuildPreviewMembers(size)
            assert.equals(size, #members)
            local columns = VenomRoster.Organize(members)
            local expectedGroups = math.ceil(size / VenomRoster.MAX_GROUP_SIZE)
            assert.equals(expectedGroups, #columns, "size " .. size)
            local counted = 0
            for slot, column in ipairs(columns) do
                assert.equals(slot, column.group)
                counted = counted + #column.members
                if slot < expectedGroups then
                    assert.equals(VenomRoster.MAX_GROUP_SIZE, #column.members)
                else
                    local remainder = size % VenomRoster.MAX_GROUP_SIZE
                    if remainder == 0 then
                        remainder = VenomRoster.MAX_GROUP_SIZE
                    end
                    assert.equals(remainder, #column.members)
                end
            end
            assert.equals(size, counted)
        end
    end)

    it("uses subgroup membership rather than raid token order", function()
        local columns = VenomRoster.Organize({
            Member("LateGroup1", 1, 12),
            Member("Group3", 3, 2),
            Member("EarlyGroup1", 1, 4),
            Member("Group2", 2, 7),
        })
        assert.same({ 1, 2, 3 }, Groups(columns))
        assert.same({ "EarlyGroup1", "LateGroup1" }, Names(columns[1]))
        assert.same({ "Group2" }, Names(columns[2]))
        assert.same({ "Group3" }, Names(columns[3]))
    end)

    it("keeps uneven subgroup sizes and omits empty groups", function()
        local columns = VenomRoster.Organize({
            Member("G1a", 1, 1),
            Member("G3a", 3, 2),
            Member("G3b", 3, 3),
            Member("G3c", 3, 4),
            Member("G5a", 5, 5),
            Member("G5b", 5, 6),
        })
        assert.same({ 1, 3, 5 }, Groups(columns))
        assert.equals(1, #columns[1].members)
        assert.equals(3, #columns[2].members)
        assert.equals(2, #columns[3].members)
    end)

    it("ignores empty subgroups even when later groups are filled", function()
        local columns = VenomRoster.Organize({
            Member("G1", 1, 1),
            Member("G6", 6, 2),
        })
        assert.same({ 1, 6 }, Groups(columns))
        assert.equals(2, #columns)
    end)

    it("orders members by roster index, not input order or stack counts", function()
        local columns = VenomRoster.Organize({
            Member("Third", 1, 30, { stacks = 9 }),
            Member("First", 1, 2, { stacks = 1 }),
            Member("Second", 1, 11, { stacks = 0 }),
        })
        assert.same({ "First", "Second", "Third" }, Names(columns[1]))
    end)

    it("reassigns a player when their subgroup changes", function()
        local alpha = Member("Alpha", 1, 1)
        local beta = Member("Beta", 1, 2)
        local gamma = Member("Gamma", 2, 3)
        local before = VenomRoster.Organize({ alpha, beta, gamma })
        assert.same({ 1, 2 }, Groups(before))
        assert.same({ "Alpha", "Beta" }, Names(before[1]))
        assert.same({ "Gamma" }, Names(before[2]))

        beta.subgroup = 3
        local after = VenomRoster.Organize({ alpha, beta, gamma })
        assert.same({ 1, 2, 3 }, Groups(after))
        assert.same({ "Alpha" }, Names(after[1]))
        assert.same({ "Gamma" }, Names(after[2]))
        assert.same({ "Beta" }, Names(after[3]))
    end)

    it("drops members outside groups 1-6 and caps a group at five", function()
        local members = {}
        for index = 1, 7 do
            members[index] = Member("G1-" .. index, 1, index)
        end
        members[8] = Member("G7", 7, 8)
        members[9] = Member("G8", 8, 9)
        local columns = VenomRoster.Organize(members)
        assert.equals(1, #columns)
        assert.equals(5, #columns[1].members)
        assert.same({ "G1-1", "G1-2", "G1-3", "G1-4", "G1-5" }, Names(columns[1]))
    end)

    it("keeps mock stacks on a side channel instead of reordering the roster", function()
        local members = VenomRoster.BuildPreviewMembers(10)
        local stacks = VenomRoster.PreviewStacksByIndex(members)
        members[5].subgroup = 2
        local shuffled = { members[10], members[1], members[5], members[2] }
        local columns = VenomRoster.Organize(shuffled)
        assert.same({ "Player1", "Player2" }, Names(columns[1]))
        assert.same({ "Player5", "Player10" }, Names(columns[2]))
        assert.equals(0, stacks[1])
        assert.equals(9, stacks[10])
        assert.equals(4, stacks[5])
    end)

    it("builds named preview sizes and gapped/uneven group layouts", function()
        assert.equals(1, #VenomRoster.BuildPreviewMembers(1))
        assert.equals(5, #VenomRoster.BuildPreviewMembers("5"))
        assert.equals(20, #VenomRoster.BuildPreviewMembers(nil))
        local gaps = VenomRoster.Organize(VenomRoster.BuildPreviewMembers("gaps"))
        assert.same({ 1, 3, 5 }, Groups(gaps))
        local uneven = VenomRoster.Organize(VenomRoster.BuildPreviewMembers("uneven"))
        assert.same({ 1, 2, 4 }, Groups(uneven))
        assert.equals(5, #uneven[1].members)
        assert.equals(1, #uneven[2].members)
        assert.equals(3, #uneven[3].members)
        local custom = VenomRoster.Organize(VenomRoster.BuildPreviewMembers({ groups = { 6, 6, 1 } }))
        assert.same({ 1, 6 }, Groups(custom))
        assert.equals(1, #custom[1].members)
        assert.equals(2, #custom[2].members)
    end)

    it("defaults the venom roster on and restores appearance from SavedVariables", function()
        assert.is_true(Module:IsVenomRosterEnabled())
        assert.equals(20, Module:GetVenomRosterRowSpacing())
        assert.equals(12, Module:GetVenomRosterColumnSpacing())
        assert.equals(12, Module:GetVenomRosterNameFontSize())
        assert.equals(16, Module:GetVenomRosterStackFontSize())
        assert.equals(120, Module:GetVenomRosterNameColumnWidth())
        assert.same(Schema.DefaultVenomRosterPosition(), Module:GetVenomRosterPosition())

        Module:SetVenomRosterEnabled(false)
        Module:SetVenomRosterRowSpacing(24)
        Module:SetVenomRosterColumnSpacing(8)
        Module:SetVenomRosterNameColumnWidth(80)
        Module:SetVenomRosterNameFontSize(14)
        Module:SetVenomRosterStackFontSize(18)
        local position = { point = "TOP", relativePoint = "TOP", x = 12, y = -8 }
        Module:SetVenomRosterPosition(position)

        local reloaded = Loader.Load()
        reloaded.Modules.Start(reloaded.Database.Load({
            modules = {
                TwinFangs = {
                    venomRoster = {
                        enabled = false,
                        rowSpacing = 24,
                        columnSpacing = 8,
                        nameColumnWidth = 80,
                        nameFontSize = 14,
                        stackFontSize = 18,
                    },
                    venomRosterPosition = position,
                },
            },
        }))
        local loaded = reloaded.Modules.Get("TwinFangs")
        assert.is_false(loaded:IsVenomRosterEnabled())
        assert.equals(24, loaded:GetVenomRosterRowSpacing())
        assert.equals(8, loaded:GetVenomRosterColumnSpacing())
        assert.equals(80, loaded:GetVenomRosterNameColumnWidth())
        assert.equals(14, loaded:GetVenomRosterNameFontSize())
        assert.equals(18, loaded:GetVenomRosterStackFontSize())
        assert.same(position, loaded:GetVenomRosterPosition())
    end)

    it("clamps invalid venom roster saved values without a migration", function()
        local fresh = Loader.Load()
        fresh.Modules.Start(fresh.Database.Load({
            modules = {
                TwinFangs = {
                    venomRoster = {
                        rowSpacing = 1,
                        columnSpacing = 99,
                        nameColumnWidth = 1,
                        nameFontSize = 0,
                        stackFontSize = 100,
                    },
                    venomRosterPosition = { point = "CENTER", relativePoint = "CENTER", x = "bad", y = 0 },
                },
            },
        }))
        local loaded = fresh.Modules.Get("TwinFangs")
        local loadedSchema = fresh.Modules.Internals("TwinFangs").Schema
        assert.is_true(loaded:IsVenomRosterEnabled())
        assert.is_nil(loaded.db.venomRoster.scale)
        assert.equals(loadedSchema.VENOM_ROSTER_ROW_SPACING_MIN, loaded:GetVenomRosterRowSpacing())
        assert.equals(loadedSchema.VENOM_ROSTER_COLUMN_SPACING_MAX, loaded:GetVenomRosterColumnSpacing())
        assert.equals(loadedSchema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MIN, loaded:GetVenomRosterNameColumnWidth())
        assert.equals(loadedSchema.VENOM_ROSTER_NAME_FONT_SIZE_MIN, loaded:GetVenomRosterNameFontSize())
        assert.equals(loadedSchema.VENOM_ROSTER_STACK_FONT_SIZE_MAX, loaded:GetVenomRosterStackFontSize())
        assert.same(loadedSchema.DefaultVenomRosterPosition(), loaded:GetVenomRosterPosition())
    end)
end)

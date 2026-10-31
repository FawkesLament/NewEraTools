local Loader = require("helpers.loader")
local InterruptChainHelper = require("helpers.interrupt_chain")

describe("TwinFangs interrupt chain editor", function()
    local ns, Chain, Labels, Schema, state

    local function FullName(name)
        return name .. "-" .. InterruptChainHelper.REALM
    end

    local function Guid(name)
        return "Player-MOCK-" .. name
    end

    local function Player(name)
        return { name = FullName(name) }
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Labels = InterruptChainHelper.LoadLabels(ns)
        Schema = ns.Modules.Internals("TwinFangs").Schema
        state = Chain.NewState()
        Chain.SetRoster(state, InterruptChainHelper.MockRoster())
    end)

    it("reads player identity from the current raid roster", function()
        local Group = ns.Api.Group
        Group.members = {
            {
                name = "Aric",
                fullName = "Aric-TestRealm",
                guid = "Player-1-ARIC",
                subgroup = 1,
                classFile = "MAGE",
                role = "DAMAGER",
            },
        }
        Chain.UseRaidRoster(state)
        assert.equals(1, #state.roster)
        assert.equals("Aric", state.roster[1].name)
        assert.equals("MAGE", Chain.GetMember(state, "Player-1-ARIC").classFile)
    end)

    local function EnableBackup(regionId, channel)
        assert.is_true(Chain.SetChannel(state, regionId, channel or Schema.CHANNEL_SAY))
    end

    it("starts each region with no party, party chat, and an empty chain", function()
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_RIGHT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.BACK_LEFT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.BACK_RIGHT).group)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_RAID_GROUP_NONE, Labels.GroupLabel(nil))
        assert.equals(0, #Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        assert.equals(Schema.CHANNEL_PARTY, Chain.GetRegion(state, Chain.FRONT_LEFT).channel)
        assert.equals(Schema.CHANNEL_PARTY, Chain.GetRegion(state, Chain.FRONT_RIGHT).channel)
        assert.is_true(state.dirty)
    end)

    it("adds, reorders, and removes interrupt players within a region", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("夜雨")))
        assert.is_false(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.is_false(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("流火")))

        assert.is_true(Chain.MovePlayer(state, Chain.FRONT_LEFT, 2, -1))
        local region = Chain.GetRegion(state, Chain.FRONT_LEFT)
        assert.same({ Player("夜雨"), Player("清风") }, region.players)

        assert.is_true(Chain.RemovePlayer(state, Chain.FRONT_LEFT, 1))
        assert.same({ Player("清风") }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
    end)

    it("identifies players by display name", function()
        local aliceA = {
            name = "Alice-RealmA",
            fullName = "Alice-RealmA",
            guid = "Player-A",
            subgroup = 1,
            classFile = "MAGE",
            role = "DAMAGER",
        }
        local aliceB = {
            name = "Alice-RealmB",
            fullName = "Alice-RealmB",
            guid = "Player-B",
            subgroup = 1,
            classFile = "ROGUE",
            role = "DAMAGER",
        }
        Chain.SetRoster(state, { aliceA, aliceB })
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, "Player-A"))
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, "Player-B"))
        local region = Chain.GetRegion(state, Chain.FRONT_LEFT)
        assert.equals("Alice-RealmA", region.players[1].name)
        assert.equals("Alice-RealmB", region.players[2].name)
        assert.is_nil(region.players[1].guid)
        assert.equals("Alice", Labels.DisplayName(state.roster, region.players[1]))
        assert.is_false(Chain.AddPlayer(state, Chain.FRONT_LEFT, "Player-A"))
    end)

    it("keeps addable players inside the selected group and unused as primaries", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        local names = {}
        for _, member in ipairs(Chain.GetAddablePlayers(state, Chain.FRONT_LEFT)) do
            names[#names + 1] = member.name
        end
        assert.same({ "夜雨", "石川" }, names)
    end)

    it("swaps party assignments when the selected party belongs to another region", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        EnableBackup(Chain.FRONT_LEFT, Schema.CHANNEL_SAY)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("南枝"))
        Chain.SetGroup(state, Chain.FRONT_RIGHT, 2)
        Chain.AddPlayer(state, Chain.FRONT_RIGHT, Guid("流火"))
        EnableBackup(Chain.FRONT_RIGHT, Schema.CHANNEL_YELL)
        Chain.SetBackup(state, Chain.FRONT_RIGHT, Guid("余烬"))

        assert.is_true(Chain.SetGroup(state, Chain.FRONT_LEFT, 2))
        local left = Chain.GetRegion(state, Chain.FRONT_LEFT)
        local right = Chain.GetRegion(state, Chain.FRONT_RIGHT)
        assert.equals(2, left.group)
        assert.same({ Player("流火") }, left.players)
        assert.same(Player("余烬"), left.backup)
        assert.equals(1, right.group)
        assert.same({ Player("清风") }, right.players)
        assert.same(Player("南枝"), right.backup)
        local issues = Chain.Validate(state)
        for _, issue in ipairs(issues) do
            assert.is_true(issue.code ~= "duplicate_group")
        end
    end)

    it("reports a party assigned to two regions as an error", function()
        state.regions[Chain.FRONT_LEFT].group = 2
        state.regions[Chain.FRONT_RIGHT].group = 2
        local codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            if issue.code == "duplicate_group" then
                codes[issue.region] = true
            end
        end
        assert.is_true(codes[Chain.FRONT_LEFT])
        assert.is_true(codes[Chain.FRONT_RIGHT])
        assert.equals("error", Chain.GetStatus(state).level)
    end)

    it("drops leftover primaries and same-group backups when the raid group changes", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
        assert.is_true(Chain.SetGroup(state, Chain.FRONT_LEFT, 2))
        local region = Chain.GetRegion(state, Chain.FRONT_LEFT)
        assert.equals(2, region.group)
        assert.equals(0, #region.players)
        assert.is_nil(region.backup)
    end)

    it("lists only raid groups that exist in the roster", function()
        assert.same({ 1, 2, 3, 4, 5 }, Chain.GetPresentGroups(state))
        assert.same({ 1, 2, 3, 4, 5 }, Chain.GetAssignableGroups(state, Chain.FRONT_LEFT))
        assert.same({ 1, 2, 3, 4, 5 }, Chain.GetBackupGroups(state, Chain.FRONT_LEFT))
        Chain.SetGroup(state, Chain.FRONT_LEFT, 5)
        assert.same({ 1, 2, 3, 4 }, Chain.GetBackupGroups(state, Chain.FRONT_LEFT))
        -- An assigned group with nobody in it stays listed so the dropdown can show it.
        Chain.SetGroup(state, Chain.FRONT_LEFT, 7)
        assert.same({ 1, 2, 3, 4, 5, 7 }, Chain.GetAssignableGroups(state, Chain.FRONT_LEFT))
        assert.same({ 1, 2, 3, 4, 5 }, Chain.GetBackupGroups(state, Chain.FRONT_LEFT))
    end)

    it("marks a party as assigned when another region already selected it", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 2)
        assert.is_true(Chain.IsGroupAssignedElsewhere(state, Chain.FRONT_RIGHT, 2))
        assert.is_false(Chain.IsGroupAssignedElsewhere(state, Chain.FRONT_LEFT, 2))
        assert.is_false(Chain.IsGroupAssignedElsewhere(state, Chain.FRONT_RIGHT, 3))
        assert.equals(
            ns.L.TWIN_FANGS_INTERRUPT_RAID_GROUP_ASSIGNED:format(2),
            Labels.GroupChoiceLabel(state, Chain.FRONT_RIGHT, 2)
        )
        assert.equals(Labels.GroupLabel(2), Labels.GroupChoiceLabel(state, Chain.FRONT_LEFT, 2))
    end)

    it("lists backup players in one group and skips backups used elsewhere", function()
        local names = {}
        for _, member in ipairs(Chain.GetBackupPlayers(state, Chain.FRONT_LEFT, 2)) do
            names[#names + 1] = member.name
        end
        assert.same({ "流火", "霜华", "远山" }, names)

        EnableBackup(Chain.BACK_LEFT)
        Chain.SetBackup(state, Chain.BACK_LEFT, Guid("流火"))
        names = {}
        for _, member in ipairs(Chain.GetBackupPlayers(state, Chain.FRONT_LEFT, 2)) do
            names[#names + 1] = member.name
        end
        assert.same({ "霜华", "远山" }, names)
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        assert.equals(0, #Chain.GetBackupPlayers(state, Chain.FRONT_LEFT, 1))
    end)

    it("initializes the backup picker from a committed assignment", function()
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("余烬"))
        local picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, nil)
        assert.equals(5, picker.group)
        assert.equals(Guid("余烬"), picker.player)
        assert.equals(Guid("余烬"), picker.committed)
    end)

    it("keeps the committed backup when only the picker group changes", function()
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
        local picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, nil)
        Chain.PickBackupGroup(picker, 5)
        assert.equals(5, picker.group)
        assert.equals(Chain.BACKUP_NONE, picker.player)
        assert.same(Player("流火"), Chain.GetRegion(state, Chain.FRONT_LEFT).backup)

        picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, picker)
        assert.equals(5, picker.group)
        assert.equals(Chain.BACKUP_NONE, picker.player)
        assert.equals(Guid("流火"), picker.committed)
    end)

    it("reinitializes the backup picker when the region's group makes the backup ineligible", function()
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
        local picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, nil)
        Chain.SetGroup(state, Chain.FRONT_LEFT, 2)
        picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, picker)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        assert.is_nil(picker.committed)
        assert.equals(1, picker.group)
        assert.equals(Chain.BACKUP_NONE, picker.player)
    end)

    it("rejects a backup from the same group or already used by another region", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        EnableBackup(Chain.FRONT_LEFT)
        EnableBackup(Chain.FRONT_RIGHT, Schema.CHANNEL_YELL)
        assert.is_false(Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.is_true(Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火")))
        assert.is_false(Chain.SetBackup(state, Chain.FRONT_RIGHT, Guid("流火")))
        local names = {}
        for _, member in ipairs(Chain.GetBackupCandidates(state, Chain.FRONT_RIGHT)) do
            if member.name == "流火" then
                names[#names + 1] = member.name
            end
        end
        assert.equals(0, #names)
    end)

    it("warns about empty interrupt chains", function()
        local status = Chain.GetStatus(state)
        assert.equals("warning", status.level)
        assert.equals(0, status.errors)
        assert.equals(4, status.warnings)
        local codes = {}
        for _, issue in ipairs(status.issues) do
            codes[issue.code] = (codes[issue.code] or 0) + 1
        end
        assert.equals(4, codes.empty_chain)
        assert.is_nil(codes.missing_backup)
    end)

    it("reports stale duplicate and out-of-group primaries as errors", function()
        state.regions[Chain.FRONT_LEFT].players = { Player("流火") }
        state.regions[Chain.FRONT_RIGHT].players = { Player("流火") }
        local issues = Chain.Validate(state)
        local codes = {}
        for _, issue in ipairs(issues) do
            if issue.severity == "error" then
                codes[issue.code] = true
            end
        end
        assert.is_true(codes.duplicate_primary)
        assert.is_true(codes.primary_wrong_group)
        assert.equals("error", Chain.GetStatus(state).level)
    end)

    it("reports a shared or same-group backup as an error", function()
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].channel = Schema.CHANNEL_SAY
        state.regions[Chain.FRONT_LEFT].backup = Player("清风")
        state.regions[Chain.FRONT_RIGHT].channel = Schema.CHANNEL_YELL
        state.regions[Chain.FRONT_RIGHT].backup = Player("清风")
        local issues = Chain.Validate(state)
        local codes = {}
        for _, issue in ipairs(issues) do
            if issue.severity == "error" then
                codes[issue.code] = true
            end
        end
        assert.is_true(codes.backup_same_group)
        assert.is_true(codes.backup_shared)
    end)

    it("marks a complete unpublished assignment as unsynced", function()
        local assignments = {
            [Chain.FRONT_LEFT] = { Guid("清风"), Guid("余烬") },
            [Chain.FRONT_RIGHT] = { Guid("流火"), Guid("栖梧") },
            [Chain.BACK_LEFT] = { Guid("南枝"), Guid("夜雨") },
            [Chain.BACK_RIGHT] = { Guid("朔风"), Guid("霜华") },
        }
        local groups = {
            [Chain.FRONT_LEFT] = 1,
            [Chain.FRONT_RIGHT] = 2,
            [Chain.BACK_LEFT] = 3,
            [Chain.BACK_RIGHT] = 4,
        }
        local channels = {
            [Chain.FRONT_LEFT] = Schema.CHANNEL_SAY,
            [Chain.FRONT_RIGHT] = Schema.CHANNEL_YELL,
            [Chain.BACK_LEFT] = Schema.CHANNEL_EMOTE,
            [Chain.BACK_RIGHT] = Schema.CHANNEL_NOD,
        }
        for regionId, pair in pairs(assignments) do
            Chain.SetChannel(state, regionId, channels[regionId])
            Chain.SetGroup(state, regionId, groups[regionId])
            Chain.AddPlayer(state, regionId, pair[1])
            Chain.SetBackup(state, regionId, pair[2])
        end
        local status = Chain.GetStatus(state)
        assert.equals(0, status.errors)
        assert.equals(0, status.warnings)
        assert.equals("unsynced", status.level)
        assert.is_true(status.dirty)
    end)

    local function SnapshotRegions(current)
        local copy = {}
        for _, regionId in ipairs(Chain.REGION_IDS) do
            local region = Chain.GetRegion(current, regionId)
            copy[regionId] = {
                group = region.group,
                players = region.players,
                backup = region.backup,
                channel = region.channel,
            }
        end
        return copy
    end

    it("maps raid groups 1–4 onto the four regions in roster-index order", function()
        local assignment = Chain.BuildAutoAssignment(InterruptChainHelper.MockRoster())
        assert.equals(1, assignment[Chain.FRONT_LEFT].group)
        assert.equals(2, assignment[Chain.FRONT_RIGHT].group)
        assert.equals(3, assignment[Chain.BACK_LEFT].group)
        assert.equals(4, assignment[Chain.BACK_RIGHT].group)
        assert.same({ Player("清风"), Player("夜雨"), Player("石川") }, assignment[Chain.FRONT_LEFT].players)
        assert.same({ Player("流火"), Player("霜华"), Player("远山") }, assignment[Chain.FRONT_RIGHT].players)
        assert.same({ Player("南枝"), Player("白露"), Player("青禾") }, assignment[Chain.BACK_LEFT].players)
        assert.same({ Player("朔风"), Player("凌川"), Player("暮雪") }, assignment[Chain.BACK_RIGHT].players)
        assert.is_nil(assignment[Chain.FRONT_LEFT].backup)
    end)

    it("sorts a shuffled roster by raid index instead of table order", function()
        local roster = InterruptChainHelper.MockRoster()
        local reversed = {}
        for index = #roster, 1, -1 do
            reversed[#reversed + 1] = roster[index]
        end
        local assignment = Chain.BuildAutoAssignment(reversed)
        assert.same({ Player("清风"), Player("夜雨"), Player("石川") }, assignment[Chain.FRONT_LEFT].players)
    end)

    it("ignores raid groups 5–8 and does not assign missing groups 1–4", function()
        local assignment = Chain.BuildAutoAssignment({
            {
                name = "余烬",
                fullName = FullName("余烬"),
                guid = Guid("余烬"),
                index = 1,
                subgroup = 5,
                classFile = "DRUID",
                role = "DAMAGER",
            },
            {
                name = "清风",
                fullName = FullName("清风"),
                guid = Guid("清风"),
                index = 2,
                subgroup = 1,
                classFile = "MAGE",
                role = "DAMAGER",
            },
            {
                name = "栖梧",
                fullName = FullName("栖梧"),
                guid = Guid("栖梧"),
                index = 3,
                subgroup = 8,
                classFile = "MAGE",
                role = "DAMAGER",
            },
        })
        assert.equals(1, assignment[Chain.FRONT_LEFT].group)
        assert.same({ Player("清风") }, assignment[Chain.FRONT_LEFT].players)
        assert.is_nil(assignment[Chain.FRONT_RIGHT].group)
        assert.is_nil(assignment[Chain.BACK_LEFT].group)
        assert.is_nil(assignment[Chain.BACK_RIGHT].group)
        assert.same({}, assignment[Chain.FRONT_RIGHT].players)
        assert.same({}, assignment[Chain.BACK_LEFT].players)
        assert.same({}, assignment[Chain.BACK_RIGHT].players)
    end)

    it("replaces every previous assignment and backup", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 2)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("流火"))
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("南枝"))
        Chain.SetGroup(state, Chain.BACK_RIGHT, 4)
        Chain.AddPlayer(state, Chain.BACK_RIGHT, Guid("朔风"))
        EnableBackup(Chain.BACK_RIGHT, Schema.CHANNEL_YELL)
        Chain.SetBackup(state, Chain.BACK_RIGHT, Guid("余烬"))
        assert.is_true(Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), true, true))
        assert.equals(1, Chain.GetRegion(state, Chain.FRONT_LEFT).group)
        assert.same({
            Player("清风"),
            Player("夜雨"),
            Player("石川"),
        }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        assert.is_nil(Chain.GetRegion(state, Chain.BACK_RIGHT).backup)
        assert.equals(4, Chain.GetRegion(state, Chain.BACK_RIGHT).group)
        assert.is_true(state.dirty)
        local issues = Chain.Validate(state)
        for _, issue in ipairs(issues) do
            assert.is_true(issue.code ~= "duplicate_group")
            assert.is_true(issue.code ~= "backup_shared")
        end
    end)

    it("returns the same assignment for the same roster", function()
        local first = Chain.BuildAutoAssignment(InterruptChainHelper.MockRoster())
        local second = Chain.BuildAutoAssignment(InterruptChainHelper.MockRoster())
        assert.same(first, second)
        assert.is_true(Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), true, true))
        local once = SnapshotRegions(state)
        assert.is_true(Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), true, true))
        assert.same(once, SnapshotRegions(state))
    end)

    it("leaves the configuration unchanged when auto-assign is blocked", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        EnableBackup(Chain.FRONT_LEFT)
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
        local before = SnapshotRegions(state)

        local ok, reason = Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), false, true)
        assert.is_false(ok)
        assert.equals("not_in_raid", reason)
        assert.same(before, SnapshotRegions(state))

        ok, reason = Chain.AutoAssign(state, {}, true, true)
        assert.is_false(ok)
        assert.equals("roster_unavailable", reason)
        assert.same(before, SnapshotRegions(state))

        ok, reason = Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), true, false)
        assert.is_false(ok)
        assert.equals("roster_unavailable", reason)
        assert.same(before, SnapshotRegions(state))

        ok, reason = Chain.AutoAssign(state, {
            {
                name = "余烬",
                fullName = FullName("余烬"),
                guid = Guid("余烬"),
                index = 1,
                subgroup = 5,
                classFile = "DRUID",
                role = "DAMAGER",
            },
        }, true, true)
        assert.is_false(ok)
        assert.equals("groups_empty", reason)
        assert.same(before, SnapshotRegions(state))
    end)

    it("treats a stored display name as the assigned player", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        state.regions[Chain.FRONT_LEFT].players = { Player("清风") }
        assert.is_false(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.same({ Player("清风") }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
    end)

    it("keeps saved assignments when a player leaves or switches groups", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("夜雨"))
        local remaining = {}
        for _, member in ipairs(InterruptChainHelper.MockRoster()) do
            if member.name == "夜雨" then
                member = {
                    name = member.name,
                    fullName = member.fullName,
                    guid = member.guid,
                    index = member.index,
                    subgroup = 3,
                    classFile = member.classFile,
                    role = member.role,
                }
            end
            if member.name ~= "清风" then
                remaining[#remaining + 1] = member
            end
        end
        Chain.SetRoster(state, remaining)
        local region = Chain.GetRegion(state, Chain.FRONT_LEFT)
        assert.same({ Player("清风"), Player("夜雨") }, region.players)
        local codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            if issue.region == Chain.FRONT_LEFT then
                codes[issue.code] = true
            end
        end
        assert.is_true(codes.player_missing)
        assert.is_true(codes.primary_wrong_group)
    end)

    it("sanitizes missing or malformed saved configuration", function()
        local chain = Chain.SanitizeSaved({
            front_left = { group = 1, players = { "清风", { guid = Guid("夜雨"), name = "夜雨" }, 12 } },
            front_right = "nope",
        })
        assert.equals(1, chain.front_left.group)
        assert.equals(2, #chain.front_left.players)
        assert.is_nil(chain.front_left.players[1].guid)
        assert.equals(ns.Api.Unit.GetFullName("清风"), chain.front_left.players[1].name)
        assert.is_nil(chain.front_left.players[2].guid)
        assert.equals(ns.Api.Unit.GetFullName("夜雨"), chain.front_left.players[2].name)
        assert.equals(Schema.CHANNEL_PARTY, chain.front_left.channel)
        assert.equals(Schema.CHANNEL_PARTY, chain.front_right.channel)
        assert.equals(0, #chain.front_right.players)
        assert.is_nil(chain.back_left.group)
        assert.equals(Schema.CHANNEL_PARTY, chain.back_left.channel)
        assert.equals(0, #chain.back_right.players)
    end)

    it("persists assignments on TwinFangs settings across a simulated reload", function()
        ns.Modules.Start(ns.Database.Load(nil))
        local module = ns.Modules.Get("TwinFangs")
        local bound = Chain.NewState(module.db.interruptReminder.chain)
        Chain.SetRoster(bound, InterruptChainHelper.MockRoster())
        Chain.SetGroup(bound, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(bound, Chain.FRONT_LEFT, Guid("清风"))
        Chain.AddPlayer(bound, Chain.FRONT_LEFT, Guid("夜雨"))
        assert.is_true(Chain.SetChannel(bound, Chain.FRONT_LEFT, Schema.CHANNEL_SAY))
        Chain.SetBackup(bound, Chain.FRONT_LEFT, Guid("流火"))
        assert.is_true(Chain.AutoAssign(bound, InterruptChainHelper.MockRoster(), true, true))
        local saved = ns.Util.DeepCopy(module.db)

        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        ns.Modules.Start(ns.Database.Load({ modules = { TwinFangs = saved } }))
        local restored = ns.Modules.Get("TwinFangs")
        local chain = restored.db.interruptReminder.chain
        assert.same({ Player("清风"), Player("夜雨"), Player("石川") }, chain.front_left.players)
        assert.equals(1, chain.front_left.group)
        assert.equals(Schema.CHANNEL_SAY, chain.front_left.channel)
        assert.is_nil(chain.front_left.backup)
        assert.equals(2, chain.front_right.group)
        assert.equals(Schema.CHANNEL_PARTY, chain.front_right.channel)
        assert.same(Player("流火"), chain.front_right.players[1])

        local reloaded = Chain.NewState(chain)
        Chain.SetRoster(reloaded, {})
        assert.same({ Player("清风"), Player("夜雨"), Player("石川") }, reloaded.regions.front_left.players)
    end)

    it("does not share interrupt-chain default tables across settings instances", function()
        local first = Schema.NewSettings()
        local second = Schema.NewSettings()
        first.interruptReminder.chain.front_left.players[1] = Player("清风")
        assert.equals(0, #second.interruptReminder.chain.front_left.players)
        assert.is_false(first.interruptReminder.chain == second.interruptReminder.chain)
    end)

    describe("communication channels", function()
        local function IssueCodes(issues)
            local codes = {}
            for _, issue in ipairs(issues) do
                codes[issue.code] = (codes[issue.code] or 0) + 1
            end
            return codes
        end

        it("defaults missing and invalid persisted channels to party and drops party backups", function()
            local chain = Chain.SanitizeSaved({
                front_left = { group = 1, channel = "nope", backup = Player("流火") },
                front_right = { channel = Schema.CHANNEL_NOD, backup = Player("霜华") },
                back_left = { channel = Schema.CHANNEL_PARTY, backup = Player("栖梧") },
            })
            assert.equals(Schema.CHANNEL_PARTY, chain.front_left.channel)
            assert.is_nil(chain.front_left.backup)
            assert.equals(Schema.CHANNEL_NOD, chain.front_right.channel)
            assert.same(Player("霜华"), chain.front_right.backup)
            assert.equals(Schema.CHANNEL_PARTY, chain.back_left.channel)
            assert.is_nil(chain.back_left.backup)
            assert.equals(Schema.CHANNEL_PARTY, Schema.NewInterruptRegion().channel)
        end)

        it("rejects a backup on party while applying a complete snapshot", function()
            Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
            Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
            state.regions[Chain.FRONT_LEFT].backup = Player("流火")
            local codes = IssueCodes(Chain.Validate(state))
            assert.equals(1, codes.backup_channel)
            assert.equals("error", Chain.GetStatus(state).level)
            assert.same(Player("流火"), Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        end)

        it("persists a chosen channel across a simulated reload", function()
            ns.Modules.Start(ns.Database.Load(nil))
            local module = ns.Modules.Get("TwinFangs")
            local bound = Chain.NewState(module.db.interruptReminder.chain)
            assert.is_true(Chain.SetChannel(bound, Chain.FRONT_LEFT, Schema.CHANNEL_YELL))
            assert.is_true(Chain.SetChannel(bound, Chain.BACK_RIGHT, Schema.CHANNEL_MARKER))
            local saved = ns.Util.DeepCopy(module.db)

            ns = Loader.Load()
            Chain = ns.Modules.Internals("TwinFangs").InterruptChain
            Schema = ns.Modules.Internals("TwinFangs").Schema
            ns.Modules.Start(ns.Database.Load({ modules = { TwinFangs = saved } }))
            local chain = ns.Modules.Get("TwinFangs").db.interruptReminder.chain
            assert.equals(Schema.CHANNEL_YELL, chain.front_left.channel)
            assert.equals(Schema.CHANNEL_PARTY, chain.front_right.channel)
            assert.equals(Schema.CHANNEL_MARKER, chain.back_right.channel)
        end)

        it("marks the working configuration dirty when the channel changes", function()
            state.dirty = false
            assert.is_false(Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_PARTY))
            assert.is_false(state.dirty)
            assert.is_false(Chain.SetChannel(state, Chain.FRONT_LEFT, "nope"))
            assert.is_true(Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_SAY))
            assert.is_true(state.dirty)
            assert.equals(Schema.CHANNEL_SAY, Chain.GetRegion(state, Chain.FRONT_LEFT).channel)
            state.dirty = false
            assert.is_false(Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_SAY))
            assert.is_false(state.dirty)
        end)

        it("clears a backup when switching to party and does not restore it later", function()
            Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
            Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
            EnableBackup(Chain.FRONT_LEFT)
            assert.is_true(Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火")))
            assert.is_true(Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_PARTY))
            local region = Chain.GetRegion(state, Chain.FRONT_LEFT)
            assert.equals(Schema.CHANNEL_PARTY, region.channel)
            assert.is_nil(region.backup)
            assert.same({ Player("清风") }, region.players)
            assert.is_true(Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_YELL))
            assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
            assert.same({ Player("清风") }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        end)

        it("rejects a new backup on party and allows one on other channels", function()
            Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
            assert.is_false(Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火")))
            assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
            EnableBackup(Chain.FRONT_LEFT)
            assert.is_true(Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火")))
            assert.same(Player("流火"), Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        end)

        it("drops a backup that lands on party during a group swap", function()
            EnableBackup(Chain.FRONT_LEFT, Schema.CHANNEL_SAY)
            Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
            Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
            Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
            Chain.SetGroup(state, Chain.FRONT_RIGHT, 2)
            Chain.AddPlayer(state, Chain.FRONT_RIGHT, Guid("霜华"))
            assert.is_true(Chain.SetGroup(state, Chain.FRONT_RIGHT, 1))
            local left = Chain.GetRegion(state, Chain.FRONT_LEFT)
            local right = Chain.GetRegion(state, Chain.FRONT_RIGHT)
            assert.equals(2, left.group)
            assert.same({ Player("霜华") }, left.players)
            assert.equals(Schema.CHANNEL_SAY, left.channel)
            assert.is_nil(left.backup)
            assert.equals(1, right.group)
            assert.same({ Player("清风") }, right.players)
            assert.equals(Schema.CHANNEL_PARTY, right.channel)
            assert.is_nil(right.backup)
        end)

        it("lets Auto Assign keep existing channels while clearing backups", function()
            EnableBackup(Chain.FRONT_LEFT, Schema.CHANNEL_NOD)
            EnableBackup(Chain.BACK_RIGHT, Schema.CHANNEL_MARKER)
            Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
            assert.is_true(Chain.AutoAssign(state, InterruptChainHelper.MockRoster(), true, true))
            assert.equals(Schema.CHANNEL_NOD, Chain.GetRegion(state, Chain.FRONT_LEFT).channel)
            assert.equals(Schema.CHANNEL_MARKER, Chain.GetRegion(state, Chain.BACK_RIGHT).channel)
            assert.equals(Schema.CHANNEL_PARTY, Chain.GetRegion(state, Chain.FRONT_RIGHT).channel)
            assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
        end)

        it("allows every region to use party and treats raid, nod, and marker as exclusive", function()
            local codes = IssueCodes(Chain.Validate(state))
            assert.is_nil(codes.channel_conflict)

            Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_RAID)
            Chain.SetChannel(state, Chain.FRONT_RIGHT, Schema.CHANNEL_RAID)
            codes = IssueCodes(Chain.Validate(state))
            assert.equals(2, codes.channel_conflict)
            assert.equals("error", Chain.GetStatus(state).level)

            Chain.SetChannel(state, Chain.FRONT_RIGHT, Schema.CHANNEL_NOD)
            Chain.SetChannel(state, Chain.BACK_LEFT, Schema.CHANNEL_NOD)
            codes = IssueCodes(Chain.Validate(state))
            assert.equals(2, codes.channel_conflict)

            Chain.SetChannel(state, Chain.BACK_LEFT, Schema.CHANNEL_MARKER)
            Chain.SetChannel(state, Chain.BACK_RIGHT, Schema.CHANNEL_MARKER)
            codes = IssueCodes(Chain.Validate(state))
            assert.equals(2, codes.channel_conflict)
        end)

        it("flags two regions that share say, but not mixed spoken channels", function()
            Chain.SetChannel(state, Chain.FRONT_LEFT, Schema.CHANNEL_SAY)
            Chain.SetChannel(state, Chain.FRONT_RIGHT, Schema.CHANNEL_SAY)
            local codes = IssueCodes(Chain.Validate(state))
            assert.equals(2, codes.channel_conflict)

            Chain.SetChannel(state, Chain.FRONT_RIGHT, Schema.CHANNEL_YELL)
            Chain.SetChannel(state, Chain.BACK_LEFT, Schema.CHANNEL_EMOTE)
            codes = IssueCodes(Chain.Validate(state))
            assert.is_nil(codes.channel_conflict)
        end)

        it("exposes slash-command labels from the shared channel list", function()
            assert.equals(ns.L.TWIN_FANGS_INTERRUPT_CHANNEL_PARTY, Labels.ChannelLabel(Schema.CHANNEL_PARTY))
            assert.equals(ns.L.TWIN_FANGS_INTERRUPT_CHANNEL_PARTY, Labels.ChannelLabel("nope"))
            local items = Labels.ChannelItems()
            assert.equals(#Schema.CHANNEL_IDS, #items)
            assert.equals(Schema.CHANNEL_PARTY, items[1].value)
            assert.equals(ns.L.TWIN_FANGS_INTERRUPT_CHANNEL_PARTY, items[1].text)
        end)
    end)
end)

local Loader = require("helpers.loader")

describe("TwinFangs interrupt chain editor", function()
    local ns, Chain, Schema, state

    local function FullName(name)
        return name .. "-MockRealm"
    end

    local function Guid(name)
        return "Player-MOCK-" .. name
    end

    local function Player(name)
        return { guid = Guid(name), name = FullName(name) }
    end

    local function Unresolved(name)
        return { name = FullName(name) }
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.TwinFangsInterruptChain
        Schema = ns.TwinFangsSchema
        state = Chain.NewState()
        Chain.SetRoster(state, Chain.MockRoster())
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

    it("starts each region with no party and an empty chain", function()
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_RIGHT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.BACK_LEFT).group)
        assert.is_nil(Chain.GetRegion(state, Chain.BACK_RIGHT).group)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_RAID_GROUP_NONE, Chain.GroupLabel(nil))
        assert.equals(0, #Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        assert.is_nil(Chain.GetRegion(state, Chain.FRONT_LEFT).backup)
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

    it("identifies players by GUID, not by name", function()
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
        assert.equals("Player-A", region.players[1].guid)
        assert.equals("Player-B", region.players[2].guid)
        assert.equals("Alice", Chain.DisplayName(state.roster, region.players[1]))
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
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("南枝"))
        Chain.SetGroup(state, Chain.FRONT_RIGHT, 2)
        Chain.AddPlayer(state, Chain.FRONT_RIGHT, Guid("流火"))
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
            Chain.GroupChoiceLabel(state, Chain.FRONT_RIGHT, 2)
        )
        assert.equals(Chain.GroupLabel(2), Chain.GroupChoiceLabel(state, Chain.FRONT_LEFT, 2))
    end)

    it("lists backup players in one group and skips backups used elsewhere", function()
        local names = {}
        for _, member in ipairs(Chain.GetBackupPlayers(state, Chain.FRONT_LEFT, 2)) do
            names[#names + 1] = member.name
        end
        assert.same({ "流火", "霜华", "远山" }, names)

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
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("余烬"))
        local picker = Chain.SyncBackupPicker(state, Chain.FRONT_LEFT, nil)
        assert.equals(5, picker.group)
        assert.equals(Guid("余烬"), picker.player)
        assert.equals(Guid("余烬"), picker.committed)
    end)

    it("keeps the committed backup when only the picker group changes", function()
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
        state.regions[Chain.FRONT_LEFT].backup = Player("清风")
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
        for regionId, pair in pairs(assignments) do
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
            }
        end
        return copy
    end

    it("maps raid groups 1–4 onto the four regions in roster-index order", function()
        local assignment = Chain.BuildAutoAssignment(Chain.MockRoster())
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
        local roster = Chain.MockRoster()
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
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("南枝"))
        Chain.SetGroup(state, Chain.BACK_RIGHT, 4)
        Chain.AddPlayer(state, Chain.BACK_RIGHT, Guid("朔风"))
        Chain.SetBackup(state, Chain.BACK_RIGHT, Guid("余烬"))
        assert.is_true(Chain.AutoAssign(state, Chain.MockRoster(), true, true))
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
        local first = Chain.BuildAutoAssignment(Chain.MockRoster())
        local second = Chain.BuildAutoAssignment(Chain.MockRoster())
        assert.same(first, second)
        assert.is_true(Chain.AutoAssign(state, Chain.MockRoster(), true, true))
        local once = SnapshotRegions(state)
        assert.is_true(Chain.AutoAssign(state, Chain.MockRoster(), true, true))
        assert.same(once, SnapshotRegions(state))
    end)

    it("leaves the configuration unchanged when auto-assign is blocked", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        Chain.SetBackup(state, Chain.FRONT_LEFT, Guid("流火"))
        local before = SnapshotRegions(state)

        local ok, reason = Chain.AutoAssign(state, Chain.MockRoster(), false, true)
        assert.is_false(ok)
        assert.equals("not_in_raid", reason)
        assert.same(before, SnapshotRegions(state))

        ok, reason = Chain.AutoAssign(state, {}, true, true)
        assert.is_false(ok)
        assert.equals("roster_unavailable", reason)
        assert.same(before, SnapshotRegions(state))

        ok, reason = Chain.AutoAssign(state, Chain.MockRoster(), true, false)
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

    it("migrates a unique same-realm or qualified legacy name to a GUID record", function()
        state.regions[Chain.FRONT_LEFT].players = { { name = "清风" }, { name = FullName("夜雨") } }
        state.regions[Chain.FRONT_LEFT].backup = { name = FullName("流火") }
        Chain.SetRoster(state, Chain.MockRoster())
        assert.same(Player("清风"), state.regions[Chain.FRONT_LEFT].players[1])
        assert.same(Player("夜雨"), state.regions[Chain.FRONT_LEFT].players[2])
        assert.same(Player("流火"), state.regions[Chain.FRONT_LEFT].backup)
        Chain.SetRoster(state, Chain.MockRoster())
        assert.same(Player("清风"), state.regions[Chain.FRONT_LEFT].players[1])
    end)

    it("leaves ambiguous or missing legacy names unresolved", function()
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
        state.regions[Chain.FRONT_LEFT].players = {
            { name = "Alice" },
            { name = "Ghost-Nowhere" },
        }
        Chain.SetRoster(state, { aliceA, aliceB })
        local players = state.regions[Chain.FRONT_LEFT].players
        assert.is_nil(players[1].guid)
        assert.equals(ns.Api.Unit.GetFullName("Alice"), players[1].name)
        assert.is_nil(players[2].guid)
        assert.equals("Ghost-Nowhere", players[2].name)
        local codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            codes[issue.code] = (codes[issue.code] or 0) + 1
        end
        assert.equals(2, codes.unresolved_player)
        assert.is_nil(codes.duplicate_primary)
    end)

    it("does not treat an unresolved record as a valid assigned player", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        state.regions[Chain.FRONT_LEFT].players = { Unresolved("清风") }
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.same({ Unresolved("清风"), Player("清风") }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        local codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            codes[issue.code] = true
        end
        assert.is_true(codes.unresolved_player)
        assert.is_nil(codes.duplicate_primary)
    end)

    it("keeps saved assignments when a player leaves or switches groups", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("夜雨"))
        local remaining = {}
        for _, member in ipairs(Chain.MockRoster()) do
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

    it("refreshes a cached name from the roster without changing identity", function()
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风"))
        state.regions[Chain.FRONT_LEFT].players[1].name = "OldName-MockRealm"
        local roster = Chain.MockRoster()
        Chain.SetRoster(state, roster)
        local player = state.regions[Chain.FRONT_LEFT].players[1]
        assert.equals(Guid("清风"), player.guid)
        assert.equals(FullName("清风"), player.name)
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
        assert.equals(Guid("夜雨"), chain.front_left.players[2].guid)
        assert.equals(0, #chain.front_right.players)
        assert.is_nil(chain.back_left.group)
        assert.equals(0, #chain.back_right.players)
    end)

    it("persists assignments on TwinFangs settings across a simulated reload", function()
        ns.Modules.Start(ns.Database.Load(nil))
        local module = ns.Modules.Get("TwinFangs")
        local bound = Chain.NewState(module.db.interruptReminder.chain)
        Chain.SetRoster(bound, Chain.MockRoster())
        Chain.SetGroup(bound, Chain.FRONT_LEFT, 1)
        Chain.AddPlayer(bound, Chain.FRONT_LEFT, Guid("清风"))
        Chain.AddPlayer(bound, Chain.FRONT_LEFT, Guid("夜雨"))
        Chain.SetBackup(bound, Chain.FRONT_LEFT, Guid("流火"))
        assert.is_true(Chain.AutoAssign(bound, Chain.MockRoster(), true, true))
        local saved = ns.Util.DeepCopy(module.db)

        ns = Loader.Load()
        Chain = ns.TwinFangsInterruptChain
        ns.Modules.Start(ns.Database.Load({ modules = { TwinFangs = saved } }))
        local restored = ns.Modules.Get("TwinFangs")
        local chain = restored.db.interruptReminder.chain
        assert.same({ Player("清风"), Player("夜雨"), Player("石川") }, chain.front_left.players)
        assert.equals(1, chain.front_left.group)
        assert.is_nil(chain.front_left.backup)
        assert.equals(2, chain.front_right.group)
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
end)

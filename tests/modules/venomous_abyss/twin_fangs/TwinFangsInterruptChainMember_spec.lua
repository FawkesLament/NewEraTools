local Loader = require("helpers.loader")
local InterruptChainHelper = require("helpers.interrupt_chain")

describe("TwinFangs interrupt chain member view", function()
    local ns, Chain, Labels, Schema

    local function FullName(name)
        return name .. "-MockRealm"
    end

    local function Player(name)
        return { name = FullName(name) }
    end

    local function CopyList(list)
        local copy = {}
        for index, value in ipairs(list) do
            copy[index] = value
        end
        return copy
    end

    local function Snapshot(chain)
        return {
            front_left = {
                group = chain.front_left.group,
                players = CopyList(chain.front_left.players),
                backup = chain.front_left.backup,
            },
            front_right = {
                group = chain.front_right.group,
                players = CopyList(chain.front_right.players),
                backup = chain.front_right.backup,
            },
            back_left = {
                group = chain.back_left.group,
                players = CopyList(chain.back_left.players),
                backup = chain.back_left.backup,
            },
            back_right = {
                group = chain.back_right.group,
                players = CopyList(chain.back_right.players),
                backup = chain.back_right.backup,
            },
        }
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Labels = InterruptChainHelper.LoadLabels(ns)
        Schema = ns.Modules.Internals("TwinFangs").Schema
    end)

    describe("assignments", function()
        local chain

        before_each(function()
            chain = Schema.NewInterruptChain()
            chain.front_left.group = 1
            chain.front_left.players = { Player("清风"), Player("夜雨"), Player("石川") }
            chain.front_left.backup = Player("余烬")
            chain.front_right.group = 2
            chain.front_right.players = { Player("流火"), Player("霜华") }
            chain.front_right.backup = Player("栖梧")
        end)

        it("groups consecutive repeated primaries into one sequence range", function()
            chain.front_left.players = {
                Player("清风"),
                Player("夜雨"),
                Player("夜雨"),
                Player("夜雨"),
                Player("石川"),
            }
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            assert.equals(5, #view.primary.players)
            local blocks = Chain.Blocks(view.primary.players)
            assert.equals(3, #blocks)
            assert.equals(1, blocks[1].count)
            assert.equals(3, blocks[2].count)
            assert.equals(5, blocks[3].last)
            local duties = Chain.GetPlayerResponsibilities(chain, FullName("夜雨"))
            assert.equals(2, duties.index)
            assert.equals(4, duties.indexEnd)
            local Preview = InterruptChainHelper.LoadPreview(ns)
            assert.equals("#2–4", Preview.FormatSequence(duties.index, duties.indexEnd))
            assert.equals("#1", Preview.FormatSequence(1, 1))
        end)

        it("returns the primary chain for a member, in stored order", function()
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            assert.equals(Chain.FRONT_LEFT, view.primary.regionId)
            assert.equals(1, view.primary.group)
            assert.equals(3, #view.primary.players)
            assert.equals(FullName("清风"), view.primary.players[1].name)
            assert.equals(FullName("夜雨"), view.primary.players[2].name)
            assert.equals(FullName("石川"), view.primary.players[3].name)
            assert.equals(FullName("余烬"), view.primary.backup.name)
            assert.equals(Schema.CHANNEL_PARTY, view.primary.channel)
            assert.equals(0, #view.backups)
            assert.equals("夜雨", Labels.DisplayName({}, view.primary.players[2]))
        end)

        it("exposes each assignment's communication channel in the title", function()
            chain.front_left.channel = Schema.CHANNEL_YELL
            chain.front_right.channel = Schema.CHANNEL_NOD
            local primary = Chain.GetMemberView(chain, FullName("夜雨")).primary
            local backup = Chain.GetMemberView(chain, FullName("栖梧")).backups[1]
            assert.equals(Schema.CHANNEL_YELL, primary.channel)
            assert.equals(Schema.CHANNEL_NOD, backup.channel)
            assert.equals(
                Labels.AssignmentTitle(Chain.FRONT_LEFT, 1, Schema.CHANNEL_YELL),
                string.format(
                    "%s  ·  %s  ·  %s",
                    Labels.RegionLabel(Chain.FRONT_LEFT),
                    Labels.GroupLabel(1),
                    Labels.ChannelLabel(Schema.CHANNEL_YELL)
                )
            )
        end)

        it("returns a backup-only assignment without inventing a primary", function()
            local view = Chain.GetMemberView(chain, FullName("栖梧"))
            assert.is_nil(view.primary)
            assert.equals(1, #view.backups)
            assert.equals(Chain.FRONT_RIGHT, view.backups[1].regionId)
            assert.equals(2, view.backups[1].group)
            assert.equals(FullName("流火"), view.backups[1].players[1].name)
            assert.equals(FullName("栖梧"), view.backups[1].backup.name)
        end)

        it("keeps an extra backup region separate from the primary assignment", function()
            chain.front_right.backup = Player("夜雨")
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            assert.equals(Chain.FRONT_LEFT, view.primary.regionId)
            assert.equals(1, #view.backups)
            assert.equals(Chain.FRONT_RIGHT, view.backups[1].regionId)
            assert.equals(FullName("夜雨"), view.backups[1].backup.name)
        end)

        it("does not list the same region twice when the player is also its backup", function()
            chain.front_left.backup = Player("夜雨")
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            assert.equals(Chain.FRONT_LEFT, view.primary.regionId)
            assert.equals(0, #view.backups)
        end)

        it("shows the empty state when the player is not assigned", function()
            local view = Chain.GetMemberView(chain, FullName("南枝"))
            assert.is_nil(view.primary)
            assert.equals(0, #view.backups)
        end)

        it("matches stored display names and ignores GUIDs", function()
            chain.back_left.players = {
                { name = "Alice-RealmA" },
                { name = "Alice-RealmB" },
            }
            local byGuid = Chain.GetMemberView(chain, "Player-B")
            assert.is_nil(byGuid.primary)
            local view = Chain.GetMemberView(chain, "Alice-RealmB")
            assert.equals(Chain.BACK_LEFT, view.primary.regionId)
            assert.equals("Alice-RealmB", view.primary.players[2].name)
            assert.equals("Alice", Labels.DisplayName({}, view.primary.players[2]))
        end)

        it("keeps missing records in the stored sequence", function()
            chain.front_left.players = {
                { name = FullName("清风") },
                Player("夜雨"),
                { name = FullName("石川") },
            }
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            assert.equals(3, #view.primary.players)
            assert.equals("清风", Labels.DisplayName({}, view.primary.players[1]))
            assert.equals(FullName("夜雨"), view.primary.players[2].name)
            assert.equals(FullName("石川"), view.primary.players[3].name)
        end)

        it("does not mutate the saved configuration", function()
            local before = Snapshot(chain)
            local leftPlayers = chain.front_left.players
            Chain.GetMemberView(chain, FullName("夜雨"))
            Chain.GetMemberView(chain, FullName("栖梧"))
            Chain.GetMemberView(nil, FullName("夜雨"))
            Chain.GetMemberView(chain, nil)
            assert.same(before, Snapshot(chain))
            assert.equals(leftPlayers, chain.front_left.players)
            assert.equals(leftPlayers[2], chain.front_left.players[2])
        end)

        it("returns copies so the caller cannot edit the saved chain through the view", function()
            local view = Chain.GetMemberView(chain, FullName("夜雨"))
            view.primary.players[2].name = "Changed"
            view.primary.players[1] = Player("朔风")
            assert.equals(FullName("夜雨"), chain.front_left.players[2].name)
            assert.equals(FullName("清风"), chain.front_left.players[1].name)
        end)

        it("shows the not-in-raid empty state without clearing saved assignments", function()
            local before = Snapshot(chain)
            assert.equals(ns.L.TWIN_FANGS_INTERRUPT_NOT_IN_RAID, Labels.MemberViewEmptyText(chain, false))
            assert.equals(ns.L.TWIN_FANGS_INTERRUPT_NO_ASSIGNMENT, Labels.MemberViewEmptyText(chain, true))
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_SYNC_NONE,
                Labels.MemberViewEmptyText(Schema.NewInterruptChain(), true)
            )
            assert.same(before, Snapshot(chain))
        end)

        it("handles a missing or empty identity without assigning anyone", function()
            assert.is_nil(Chain.GetMemberView(chain, "").primary)
            assert.is_nil(Chain.GetMemberView(nil, FullName("夜雨")).primary)
            assert.is_nil(Chain.GetMemberView({}, FullName("夜雨")).primary)
        end)
    end)

    describe("view selection", function()
        it("lets only the raid leader edit", function()
            local Group = ns.Api.Group
            assert.is_false(Chain.CanEdit())

            Group.isRaidLeader = true
            assert.is_true(Chain.CanEdit())

            Group.isRaidLeader = false
            Group.isLeaderOrAssistant = true
            assert.is_false(Chain.CanEdit())
        end)

        it("shows Member View when the player cannot edit", function()
            local showEditor, preferMemberView = Chain.ResolveSettingsView(false, true)
            assert.is_false(showEditor)
            assert.is_false(preferMemberView)

            showEditor, preferMemberView = Chain.ResolveSettingsView(true, false)
            assert.is_true(showEditor)
            assert.is_false(preferMemberView)

            showEditor, preferMemberView = Chain.ResolveSettingsView(true, true)
            assert.is_false(showEditor)
            assert.is_true(preferMemberView)
        end)
    end)
end)

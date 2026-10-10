local Loader = require("helpers.loader")

local function Member(name, role, subgroup)
    return {
        name = name,
        fullName = name .. "-TestRealm",
        subgroup = subgroup,
        classFile = "WARRIOR",
        role = role,
    }
end

describe("RaidLottery", function()
    local ns, RaidLottery, Group, Chat, Timer, printed
    local originalRandom = math.random

    before_each(function()
        -- Always picking the lowest index keeps the shuffle in roster order.
        math.random = function(min)
            return min
        end

        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        RaidLottery = ns.Modules.Get("RaidLottery")
        Group = ns.Api.Group
        Chat = ns.Api.Chat
        Timer = ns.Api.Timer

        printed = {}
        ns.Util.Print = function(message)
            table.insert(printed, message)
        end

        Group.raidChatType = "RAID"
        Group.isLeaderOrAssistant = true
        Group.members = {
            Member("Dps", "DAMAGER", 1),
            Member("Healer", "HEALER", 2),
            Member("Tank", "TANK", 3),
            Member("Alpha", "DAMAGER", 1),
        }
    end)

    after_each(function()
        math.random = originalRandom
    end)

    it("sorts members by role, then subgroup, then name", function()
        local names = {}
        for _, member in ipairs(RaidLottery:GetMembers()) do
            table.insert(names, member.name)
        end
        assert.same({ "Tank", "Healer", "Alpha", "Dps" }, names)
    end)

    it("leaves excluded members out of the eligible pool", function()
        local members = RaidLottery:GetMembers()
        RaidLottery:SetExcluded(members[1], true)
        assert.is_true(RaidLottery:IsExcluded(members[1]))
        assert.equals(3, #RaidLottery:GetEligible(members))

        RaidLottery:ClearExcluded()
        assert.equals(4, #RaidLottery:GetEligible(members))
    end)

    it("filters the eligible pool by role", function()
        local members = RaidLottery:GetMembers()
        assert.equals("ALL", RaidLottery:GetRole())

        RaidLottery:SetRole("DAMAGER")
        local names = {}
        for _, member in ipairs(RaidLottery:GetEligible(members)) do
            table.insert(names, member.name)
        end
        assert.same({ "Alpha", "Dps" }, names)

        RaidLottery:SetRole("HEALER")
        assert.equals(1, #RaidLottery:GetEligible(members))
    end)

    it("leaves members without an assigned role out of role filters only", function()
        table.insert(Group.members, Member("Nobody", "NONE", 4))
        local members = RaidLottery:GetMembers()
        assert.equals(5, #RaidLottery:GetEligible(members))
        RaidLottery:SetRole("TANK")
        assert.equals(1, #RaidLottery:GetEligible(members))
    end)

    it("applies exclusions on top of the role filter", function()
        local members = RaidLottery:GetMembers()
        RaidLottery:SetExcluded(members[3], true) -- Alpha
        RaidLottery:SetRole("DAMAGER")
        assert.equals(1, #RaidLottery:GetEligible(members))
        assert.equals(1, RaidLottery:GetExcludedCount(members))
    end)

    it("falls back to all roles when the saved role is unknown", function()
        RaidLottery.db.role = "BOGUS"
        assert.equals("ALL", RaidLottery:GetRole())
        assert.is_false(pcall(RaidLottery.SetRole, RaidLottery, "BOGUS"))
    end)

    it("forgets exclusions of players who left the raid", function()
        local dps = table.remove(Group.members, 1)
        local tank = Group.members[2]
        RaidLottery:SetExcluded(dps, true)
        RaidLottery:SetExcluded(tank, true)

        RaidLottery:PruneExcluded(RaidLottery:GetMembers())

        assert.is_false(RaidLottery:IsExcluded(dps))
        assert.is_true(RaidLottery:IsExcluded(tank))
    end)

    it("keeps exclusions while the roster is empty", function()
        local members = RaidLottery:GetMembers()
        RaidLottery:SetExcluded(members[1], true)
        RaidLottery:PruneExcluded({})
        assert.is_true(RaidLottery:IsExcluded(members[1]))
    end)

    it("fits the draw count to the eligible pool", function()
        RaidLottery:SetCount(3)
        RaidLottery:FitCount(2)
        assert.equals(2, RaidLottery:GetCount())
        RaidLottery:FitCount(0)
        assert.equals(2, RaidLottery:GetCount())
        assert.equals(1, RaidLottery:GetMaxCount(0))
        assert.equals(4, RaidLottery:GetMaxCount(4))
        assert.equals(40, RaidLottery:GetMaxCount(50))
    end)

    it("draws only from the selected role", function()
        RaidLottery:SetRole("DAMAGER")
        RaidLottery:SetCount(2)
        RaidLottery:Draw()
        Timer.RunPending()
        local header = string.format(ns.L.RAID_LOTTERY_RESULT_HEADER, ns.L.RAID_LOTTERY_ROLE_DAMAGER)
        assert.same({ header, "Alpha", "Dps" }, {
            Chat.sent[1].message,
            Chat.sent[2].message,
            Chat.sent[3].message,
        })
    end)

    it("announces only the exclusions that narrowed the selected role", function()
        local members = RaidLottery:GetMembers()
        RaidLottery:SetExcluded(members[1], true) -- Tank
        RaidLottery:SetExcluded(members[3], true) -- Alpha
        RaidLottery:SetRole("DAMAGER")
        RaidLottery:Draw()
        Timer.RunPending()
        assert.equals(
            string.format(ns.L.RAID_LOTTERY_RESULT_HEADER_EXCLUDED, ns.L.RAID_LOTTERY_ROLE_DAMAGER, 1),
            Chat.sent[1].message
        )

        Chat.sent = {}
        RaidLottery:SetRole("ALL")
        RaidLottery:Draw()
        Timer.RunPending()
        assert.equals(
            string.format(ns.L.RAID_LOTTERY_RESULT_HEADER_EXCLUDED, ns.L.RAID_LOTTERY_ROLE_ALL, 2),
            Chat.sent[1].message
        )
    end)

    it("clamps and rounds the draw count", function()
        RaidLottery:SetCount(0)
        assert.equals(1, RaidLottery:GetCount())
        RaidLottery:SetCount(99)
        assert.equals(40, RaidLottery:GetCount())
        RaidLottery:SetCount(3.7)
        assert.equals(3, RaidLottery:GetCount())
    end)

    it("explains why a draw is blocked", function()
        assert.is_nil(RaidLottery:GetAccessBlockedReason())
        assert.is_nil(RaidLottery:GetBlockedReason())
        RaidLottery:SetCount(2)
        assert.is_nil(RaidLottery:GetAccessBlockedReason())
        assert.equals(string.format(ns.L.RAID_LOTTERY_NOT_ENOUGH, 2, 1), RaidLottery:GetBlockedReason(1))
        Group.isLeaderOrAssistant = false
        assert.equals(ns.L.RAID_LOTTERY_BLOCKED_NOT_LEADER, RaidLottery:GetAccessBlockedReason())
        assert.equals(ns.L.RAID_LOTTERY_BLOCKED_NOT_LEADER, RaidLottery:GetBlockedReason())
        Group.raidChatType = nil
        assert.equals(ns.L.RAID_LOTTERY_BLOCKED_NOT_IN_RAID, RaidLottery:GetAccessBlockedReason())
        assert.equals(ns.L.RAID_LOTTERY_BLOCKED_NOT_IN_RAID, RaidLottery:GetBlockedReason())
    end)

    it("announces the header and each winner in raid chat", function()
        RaidLottery:SetCount(2)
        RaidLottery:Draw()
        assert.is_true(RaidLottery:IsSending())
        Timer.RunPending()

        assert.same({
            {
                message = string.format(ns.L.RAID_LOTTERY_RESULT_HEADER, ns.L.RAID_LOTTERY_ROLE_ALL),
                chatType = "RAID",
            },
            { message = "Tank", chatType = "RAID" },
            { message = "Healer", chatType = "RAID" },
        }, Chat.sent)
        assert.is_false(RaidLottery:IsSending())
    end)

    it("refuses to draw more members than are eligible", function()
        RaidLottery:SetCount(5)
        RaidLottery:Draw()
        assert.same({}, Chat.sent)
        assert.same({ string.format(ns.L.RAID_LOTTERY_NOT_ENOUGH, 5, 4) }, printed)
    end)

    it("stops announcing after the player leaves the raid", function()
        RaidLottery:SetCount(2)
        RaidLottery:Draw()
        Group.raidChatType = nil
        Timer.RunPending()

        assert.equals(1, #Chat.sent)
        assert.same({ ns.L.RAID_LOTTERY_LEFT_RAID }, printed)
        assert.is_false(RaidLottery:IsSending())
    end)
end)

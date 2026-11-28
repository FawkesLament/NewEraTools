local Loader = require("helpers.loader")

describe("UlatekMacros", function()
    local Ulatek
    local Macro
    local Combat
    local Group

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Ulatek = ns.Modules.Get("Ulatek")
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
        Group = ns.Api.Group
    end)

    it("names macros for NewEraTools within the 16-character limit", function()
        for index = 1, Ulatek.SIGNAL_MACRO_COUNT do
            local name = Ulatek:GetSignalMacroName(index)
            assert.equals("NETUlatek" .. index, name)
            assert.is_true(#name <= 16)
        end
    end)

    it("posts yell, raid warning, and raid for the three signal macros", function()
        assert.equals("/yell .", Ulatek:GetSignalMacroBody(1))
        assert.equals("/rw .", Ulatek:GetSignalMacroBody(2))
        assert.equals("/raid .", Ulatek:GetSignalMacroBody(3))
    end)

    it("treats the raid leader as commander and creates macros on request", function()
        assert.equals(Ulatek.RAID_ROLE_MEMBER, Ulatek:GetRaidRole())
        assert.is_false(Ulatek:IsRaidCommander())
        assert.is_false(Ulatek:HasAllSignalMacros())
        Group.isRaidLeader = true
        assert.equals(Ulatek.RAID_ROLE_COMMANDER, Ulatek:GetRaidRole())
        assert.is_true(Ulatek:IsRaidCommander())
        local ok, reason = Ulatek:CreateSignalMacros()
        assert.is_true(ok)
        assert.equals(nil, reason)
        for index = 1, Ulatek.SIGNAL_MACRO_COUNT do
            assert.is_true(Ulatek:HasSignalMacro(index))
            local stored = Macro.Get(Ulatek:GetSignalMacroName(index))
            assert.equals(Ulatek:GetSignalMacroBody(index), stored.body)
        end
        assert.is_true(Ulatek:HasAllSignalMacros())
    end)

    it("refuses to create macros during combat", function()
        Group.isRaidLeader = true
        Combat.FireEnter()
        local ok, reason = Ulatek:CreateSignalMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Ulatek:HasSignalMacro(1))
        Combat.FireLeave()
    end)

    it("does not defer macro create when still a member after a blocked create", function()
        Ulatek:ListenForMacroSync()
        Combat.FireEnter()
        local ok, reason = Ulatek:CreateSignalMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        Combat.FireLeave()
        assert.equals(Ulatek.RAID_ROLE_MEMBER, Ulatek:GetRaidRole())
        assert.is_false(Ulatek:HasSignalMacro(1))
    end)

    it("defers macro create when combat ends for an existing commander", function()
        Group.isRaidLeader = true
        Ulatek:ListenForMacroSync()
        Combat.FireEnter()
        local ok, reason = Ulatek:CreateSignalMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Ulatek:HasSignalMacro(1))
        Combat.FireLeave()
        assert.is_true(Ulatek:HasAllSignalMacros())
    end)

    it("does not rewrite an existing macro whose name, icon, and body already match", function()
        Group.isRaidLeader = true
        Ulatek:CreateSignalMacros()
        local edits = Macro.editCount
        Ulatek:SyncSignalMacros()
        assert.equals(edits, Macro.editCount)
    end)

    it("restores a stale signal macro when the game reports a macro change", function()
        Group.isRaidLeader = true
        Ulatek:CreateSignalMacros()
        Ulatek:ListenForMacroSync()
        local name = Ulatek:GetSignalMacroName(1)
        local index = Macro.GetIndexByName(name)
        Macro.Edit(index, nil, nil, "/say edited")
        local notified = 0
        Ulatek.OnMacrosChanged = function()
            notified = notified + 1
        end
        Macro.FireChanged()
        assert.equals(Ulatek:GetSignalMacroBody(1), Macro.Get(name).body)
        assert.equals(1, notified)
    end)

    it("returns failed when the game refuses to create a macro", function()
        Group.isRaidLeader = true
        Macro.failNextCreate = true
        local ok, reason = Ulatek:CreateSignalMacros()
        assert.is_false(ok)
        assert.equals("failed", reason)
    end)
end)

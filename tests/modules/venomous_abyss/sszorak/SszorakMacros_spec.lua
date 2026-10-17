local Harness = require("helpers.sszorak")

describe("SszorakMacros", function()
    local Sszorak
    local Macro
    local Combat
    local Group

    before_each(function()
        local ns
        ns, Sszorak = Harness.Start()
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
        Group = ns.Api.Group
    end)

    it("names macros for NewEraTools within the 16-character limit", function()
        for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
            local name = Sszorak:GetEdgeMacroName(edge)
            assert.equals("NewEraToolsSsz" .. edge, name)
            assert.is_true(#name <= 16)
        end
    end)

    it("posts the opposite edge's raid target in /raid under normal mode", function()
        assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        -- Default: edge 2 is STAR, opposite edge 6 is TRIANGLE ({rt4}).
        assert.equals("/raid {rt4}", Sszorak:GetEdgeMacroBody(2))
        assert.equals("/raid {rt1}", Sszorak:GetEdgeMacroBody(6))
    end)

    it("uses the triggering edge's marker FileID as the macro icon", function()
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"),
            Sszorak:GetEdgeMacroIcon(2)
        )
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_4"),
            Sszorak:GetEdgeMacroIcon(6)
        )
    end)

    it("treats the raid leader as commander and creates macros on request", function()
        assert.equals(Sszorak.RAID_ROLE_MEMBER, Sszorak:GetRaidRole())
        assert.is_false(Sszorak:IsRaidCommander())
        assert.is_false(Sszorak:HasAllEdgeMacros())
        Group.isRaidLeader = true
        assert.equals(Sszorak.RAID_ROLE_COMMANDER, Sszorak:GetRaidRole())
        assert.is_true(Sszorak:IsRaidCommander())
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_true(ok)
        assert.equals(nil, reason)
        for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
            assert.is_true(Sszorak:HasEdgeMacro(edge))
            local stored = Macro.Get(Sszorak:GetEdgeMacroName(edge))
            assert.equals(Sszorak:GetEdgeMacroBody(edge), stored.body)
            assert.equals(Sszorak:GetEdgeMacroIcon(edge), stored.icon)
        end
        assert.is_true(Sszorak:HasAllEdgeMacros())
    end)

    it("refuses to create macros during combat", function()
        Group.isRaidLeader = true
        Combat.FireEnter()
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Sszorak:HasEdgeMacro(2))
        Combat.FireLeave()
    end)

    it("updates existing macros when the marker assignment changes in commander mode", function()
        Group.isRaidLeader = true
        Sszorak:CreateEdgeMacros()
        Sszorak:SetEdgeMarker(2, "SKULL")
        local edge2 = Macro.Get(Sszorak:GetEdgeMacroName(2))
        local edge6 = Macro.Get(Sszorak:GetEdgeMacroName(6))
        assert.equals(Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"), edge2.icon)
        assert.equals("/raid {rt4}", edge2.body)
        assert.equals("/raid {rt8}", edge6.body)
    end)

    it("does not update macros on assignment change when not commander", function()
        Group.isRaidLeader = true
        Sszorak:CreateEdgeMacros()
        Group.isRaidLeader = false
        Sszorak:SetEdgeMarker(2, "SKULL")
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"),
            Macro.Get(Sszorak:GetEdgeMacroName(2)).icon
        )
        assert.equals("/raid {rt1}", Macro.Get(Sszorak:GetEdgeMacroName(6)).body)
    end)

    it("does not create macros on assignment change when they are missing", function()
        -- Default member role gates sync; SyncEdgeMacros also never creates missing macros.
        Sszorak:SetEdgeMarker(2, "SKULL")
        assert.is_false(Sszorak:HasEdgeMacro(2))
    end)

    it("does not defer macro create when still a member after a blocked create", function()
        -- Create during combat as a member must not write macros when combat ends.
        Sszorak:ListenForMacroSync()
        Combat.FireEnter()
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        Combat.FireLeave()
        assert.equals(Sszorak.RAID_ROLE_MEMBER, Sszorak:GetRaidRole())
        assert.is_false(Sszorak:HasEdgeMacro(2))
    end)

    it("defers macro create when combat ends for an existing commander", function()
        Group.isRaidLeader = true
        Sszorak:ListenForMacroSync()
        Combat.FireEnter()
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Sszorak:HasEdgeMacro(2))
        Combat.FireLeave()
        assert.is_true(Sszorak:HasAllEdgeMacros())
    end)

    it("defers macro updates until combat ends", function()
        Group.isRaidLeader = true
        Sszorak:CreateEdgeMacros()
        Sszorak:ListenForMacroSync()
        Combat.FireEnter()
        Sszorak:SetEdgeMarker(2, "SKULL")
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"),
            Macro.Get(Sszorak:GetEdgeMacroName(2)).icon
        )
        Combat.FireLeave()
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"),
            Macro.Get(Sszorak:GetEdgeMacroName(2)).icon
        )
        assert.equals("/raid {rt8}", Macro.Get(Sszorak:GetEdgeMacroName(6)).body)
    end)
end)

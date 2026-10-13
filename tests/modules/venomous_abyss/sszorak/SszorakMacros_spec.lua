local Loader = require("helpers.loader")

describe("SszorakMacros", function()
    local ns, Sszorak
    local Macro
    local Combat

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Sszorak = ns.Modules.Get("Sszorak")
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
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

    it("defaults to member and creates macros when switching to commander", function()
        assert.equals(Sszorak.RAID_ROLE_MEMBER, Sszorak:GetRaidRole())
        assert.is_false(Sszorak:IsRaidCommander())
        assert.is_false(Sszorak:HasAllEdgeMacros())
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_COMMANDER)
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_true(ok)
        assert.equals(nil, reason)
        assert.is_true(Sszorak:IsRaidCommander())
        for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
            assert.is_true(Sszorak:HasEdgeMacro(edge))
            local stored = Macro.Get(Sszorak:GetEdgeMacroName(edge))
            assert.equals(Sszorak:GetEdgeMacroBody(edge), stored.body)
            assert.equals(Sszorak:GetEdgeMacroIcon(edge), stored.icon)
        end
        assert.is_true(Sszorak:HasAllEdgeMacros())
    end)

    it("refuses to create macros during combat", function()
        Combat.FireEnter()
        local ok, reason = Sszorak:CreateEdgeMacros()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Sszorak:HasEdgeMacro(2))
        -- Role stays member until create succeeds (UI only switches after ok).
        assert.equals(Sszorak.RAID_ROLE_MEMBER, Sszorak:GetRaidRole())
        Combat.FireLeave()
    end)

    it("updates existing macros when the marker assignment changes in commander mode", function()
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_COMMANDER)
        Sszorak:CreateEdgeMacros()
        Sszorak:SetEdgeMarker(2, "SKULL")
        local edge2 = Macro.Get(Sszorak:GetEdgeMacroName(2))
        local edge6 = Macro.Get(Sszorak:GetEdgeMacroName(6))
        assert.equals(
            Macro.GetFileIDFromPath("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"),
            edge2.icon
        )
        assert.equals("/raid {rt4}", edge2.body)
        assert.equals("/raid {rt8}", edge6.body)
    end)

    it("does not update macros on assignment change when not commander", function()
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_COMMANDER)
        Sszorak:CreateEdgeMacros()
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_MEMBER)
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
        -- Failed commander switch leaves role as member; combat-leave must not create macros alone.
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
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_COMMANDER)
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
        Sszorak:SetRaidRole(Sszorak.RAID_ROLE_COMMANDER)
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

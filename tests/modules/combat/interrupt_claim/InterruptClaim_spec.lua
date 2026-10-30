local Loader = require("helpers.loader")

describe("InterruptClaim", function()
    local ns, InterruptClaim

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        InterruptClaim = ns.Modules.Get("InterruptClaim")
    end)

    it("is registered off with Shift+left-click", function()
        assert.is_false(InterruptClaim == nil)
        assert.equals("table", type(InterruptClaim.db))
        assert.is_false(InterruptClaim:IsEnabled())
        assert.equals(InterruptClaim.MODIFIER_SHIFT, InterruptClaim:GetModifier())
        assert.equals(InterruptClaim.MOUSE_LEFT, InterruptClaim:GetMouseButton())
        assert.equals("SHIFT-BUTTON1", InterruptClaim:GetBindingKey())
        assert.equals("shift-type1", InterruptClaim:GetUnitFrameTypeAttribute())
        assert.equals("shift-macrotext1", InterruptClaim:GetUnitFrameMacroAttribute())
        assert.is_true(InterruptClaim:IsClearFocusEnabled())
        assert.is_false(InterruptClaim:IsMarkEnabled())
        assert.equals(1, InterruptClaim:GetMarkIndex())
        assert.is_false(InterruptClaim:IsPreventOverwrite())
        assert.equals(InterruptClaim.ANNOUNCE_OFF, InterruptClaim:GetAnnounceChannel())
        assert.is_false(InterruptClaim:IsAnnounceEnabled())
        assert.is_nil(InterruptClaim:GetAnnounceSlash())
        assert.equals(ns.L.INTERRUPT_CLAIM_ANNOUNCE_DEFAULT, InterruptClaim:GetAnnounceMessage())
        assert.equals("我断{marker}%f", InterruptClaim:GetAnnounceMessage())
        assert.is_nil(InterruptClaim:GetAnnounceLine())
        assert.equals("/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]", InterruptClaim:GetMacroText())
    end)

    it("toggles and notifies the UI hook", function()
        local seen = {}
        function InterruptClaim:OnEnabledChanged()
            table.insert(seen, self:IsEnabled())
        end
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetEnabled(false)
        assert.same({ true, false }, seen)
        assert.is_false(InterruptClaim:IsEnabled())
    end)

    it("stores a modifier and mouse button as a binding key", function()
        local seen = {}
        function InterruptClaim:OnClickChanged()
            table.insert(seen, InterruptClaim:GetBindingKey())
        end
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_CTRL)
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_CTRL)
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_RIGHT)
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_ALT)
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_FORWARD)
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_BACK)
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_MIDDLE)
        assert.same({
            "CTRL-BUTTON1",
            "CTRL-BUTTON2",
            "ALT-BUTTON2",
            "ALT-BUTTON5",
            "ALT-BUTTON4",
            "ALT-BUTTON3",
        }, seen)
        assert.equals("ALT-BUTTON3", InterruptClaim:GetBindingKey())
        assert.equals("alt-type3", InterruptClaim:GetUnitFrameTypeAttribute())
        assert.equals("alt-macrotext3", InterruptClaim:GetUnitFrameMacroAttribute())
    end)

    it("rejects unknown click parts", function()
        assert.is_false(pcall(InterruptClaim.SetModifier, InterruptClaim, "meta"))
        assert.is_false(pcall(InterruptClaim.SetMouseButton, InterruptClaim, "wheel"))
        assert.is_false(pcall(InterruptClaim.SetMarkIndex, InterruptClaim, 0))
        assert.equals("SHIFT-BUTTON1", InterruptClaim:GetBindingKey())
        assert.equals(1, InterruptClaim:GetMarkIndex())
    end)

    it("falls back to Shift+left-click when saved values are unknown", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = { InterruptClaim = { modifier = "nope", mouseButton = "x", markIndex = 99 } },
        }))
        InterruptClaim = ns.Modules.Get("InterruptClaim")
        assert.equals(InterruptClaim.MODIFIER_SHIFT, InterruptClaim:GetModifier())
        assert.equals(InterruptClaim.MOUSE_LEFT, InterruptClaim:GetMouseButton())
        assert.equals("SHIFT-BUTTON1", InterruptClaim:GetBindingKey())
        assert.equals(1, InterruptClaim:GetMarkIndex())
    end)

    it("omits /clearfocus from the macro when that option is off", function()
        local seen = {}
        function InterruptClaim:OnClickChanged()
            table.insert(seen, InterruptClaim:GetMacroText())
        end
        InterruptClaim:SetClearFocusEnabled(false)
        InterruptClaim:SetClearFocusEnabled(false)
        assert.same({ "/focus [@mouseover,exists]" }, seen)
        InterruptClaim:SetMarkEnabled(true)
        assert.equals("/focus [@mouseover,exists]\n/tm [@focus]1", InterruptClaim:GetMacroText())
        InterruptClaim:SetClearFocusEnabled(true)
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1",
            InterruptClaim:GetMacroText()
        )
    end)

    it("appends the raid-target macro when marking is on", function()
        local focus = "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]"
        local seen = {}
        function InterruptClaim:OnMarkChanged()
            table.insert(seen, InterruptClaim:GetMacroText())
        end
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetMarkIndex(1)
        InterruptClaim:SetMarkIndex(8)
        InterruptClaim:SetPreventOverwrite(true)
        InterruptClaim:SetPreventOverwrite(true)
        InterruptClaim:SetMarkIndex(1)
        InterruptClaim:SetPreventOverwrite(false)
        InterruptClaim:SetMarkEnabled(false)
        assert.same({
            focus .. "\n/tm [@focus]1",
            focus .. "\n/tm [@focus]8",
            focus .. "\n/tm [@focus]~8",
            focus .. "\n/tm [@focus]~1",
            focus .. "\n/tm [@focus]1",
            focus,
        }, seen)
    end)

    it("keeps the previous mark-only macro when older saved settings have no announce fields", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = {
                InterruptClaim = {
                    enabled = true,
                    markEnabled = true,
                    markIndex = 3,
                    preventOverwrite = true,
                },
            },
        }))
        InterruptClaim = ns.Modules.Get("InterruptClaim")
        assert.equals(InterruptClaim.ANNOUNCE_OFF, InterruptClaim:GetAnnounceChannel())
        assert.equals("我断{marker}%f", InterruptClaim:GetAnnounceMessage())
        assert.is_nil(InterruptClaim:GetAnnounceLine())
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]~3",
            InterruptClaim:GetMacroText()
        )
    end)

    it("appends the announcement on party, emote, and say", function()
        local mark = "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1"
        local partyStop = "\n/stopmacro [nogroup:party][@focus,noexists][group:raid]\n"
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        InterruptClaim:SetAnnounceMessage("我断{marker}")
        assert.equals(mark .. partyStop .. "/p 我断{rt1}", InterruptClaim:GetMacroText())
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_EMOTE)
        assert.equals("/e", InterruptClaim:GetAnnounceSlash())
        assert.equals(mark .. partyStop .. "/e 我断{rt1}", InterruptClaim:GetMacroText())
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_SAY)
        assert.equals(mark .. partyStop .. "/s 我断{rt1}", InterruptClaim:GetMacroText())
        InterruptClaim:SetMarkIndex(8)
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]8"
                .. partyStop
                .. "/s 我断{rt8}",
            InterruptClaim:GetMacroText()
        )
    end)

    it("keeps a fixed announcement when the placeholder is omitted", function()
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        InterruptClaim:SetAnnounceMessage("我来打断")
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1"
                .. "\n/stopmacro [nogroup:party][@focus,noexists][group:raid]\n/p 我来打断",
            InterruptClaim:GetMacroText()
        )
    end)

    it("omits the announcement when the message is empty", function()
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        InterruptClaim:SetAnnounceMessage("认领")
        InterruptClaim:SetAnnounceMessage("")
        InterruptClaim:SetAnnounceMessage("   ")
        assert.is_nil(InterruptClaim:GetAnnounceLine())
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1",
            InterruptClaim:GetMacroText()
        )
    end)

    it("limits the announcement to 30 UTF-8 characters, including Chinese", function()
        local thirty = string.rep("断", 30)
        InterruptClaim:SetAnnounceMessage(thirty .. "领")
        assert.equals(thirty, InterruptClaim:GetAnnounceMessage())
        assert.equals(30, InterruptClaim:GetAnnounceCharCount())
        assert.equals(90, #InterruptClaim:GetAnnounceMessage())
        InterruptClaim:SetAnnounceMessage("{marker}" .. string.rep("啊", 30))
        assert.equals("{marker}" .. string.rep("啊", 22), InterruptClaim:GetAnnounceMessage())
        assert.equals(30, InterruptClaim:GetAnnounceCharCount())
    end)

    it("strips newlines and pipe escapes that could inject extra macro commands", function()
        InterruptClaim:SetMarkEnabled(true)
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        InterruptClaim:SetAnnounceMessage("认领\n/cast 寒冰箭")
        assert.equals("认领/cast 寒冰箭", InterruptClaim:GetAnnounceMessage())
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1"
                .. "\n/stopmacro [nogroup:party][@focus,noexists][group:raid]\n/p 认领/cast 寒冰箭",
            InterruptClaim:GetMacroText()
        )
        InterruptClaim:SetAnnounceMessage("认领|n/script JumpOrAscendStart()")
        assert.equals("认领n/script JumpOrAscendStart()", InterruptClaim:GetAnnounceMessage())
        assert.is_nil(InterruptClaim:GetMacroText():find("\n/script", 1, true))
        assert.is_true(#InterruptClaim:GetMacroText() <= ns.Api.Macro.MAX_BODY_LENGTH)
    end)

    it("falls back to off when the saved channel is unknown", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = { InterruptClaim = { announceChannel = "raid", announceMessage = "hello\n/p x" } },
        }))
        InterruptClaim = ns.Modules.Get("InterruptClaim")
        assert.equals(InterruptClaim.ANNOUNCE_OFF, InterruptClaim:GetAnnounceChannel())
        assert.equals("hello/p x", InterruptClaim:GetAnnounceMessage())
        assert.is_nil(InterruptClaim:GetAnnounceLine())
    end)

    it("keeps the default template until a channel is chosen", function()
        InterruptClaim:SetMarkEnabled(true)
        assert.is_nil(InterruptClaim:GetAnnounceLine())
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        assert.equals(
            "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]\n/tm [@focus]1"
                .. "\n/stopmacro [nogroup:party][@focus,noexists][group:raid]\n/p 我断{rt1}%f",
            InterruptClaim:GetMacroText()
        )
    end)
end)

local Loader = require("helpers.loader")

describe("InterruptClaim", function()
    local ns, Module, Macro, Combat

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("InterruptClaim")
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
    end)

    it("names the focus macro within the 16-character limit", function()
        local name = Module.GetFocusMacroName()
        assert.equals("NETFocus", name)
        assert.is_true(#name <= 16)
        assert.equals("/focus", Module.GetFocusMacroBody())
    end)

    it("reports the focus macro as missing until it is created", function()
        assert.is_false(Module:HasFocusMacro())
        local ok, reason = Module:CreateFocusMacro()
        assert.is_true(ok)
        assert.equals(nil, reason)
        assert.is_true(Module:HasFocusMacro())
        local stored = Macro.Get(Module.GetFocusMacroName())
        assert.equals("/focus", stored.body)
        assert.is_false(Macro.IsCharacterSlot(Macro.GetIndexByName(Module.GetFocusMacroName())))
    end)

    it("does not create a second focus macro when one already exists", function()
        assert.is_true(Module:CreateFocusMacro())
        local creates = Macro.createCount
        assert.is_true(Module:CreateFocusMacro())
        assert.equals(creates, Macro.createCount)
    end)

    it("ignores a character-only macro with the same name", function()
        Macro.Create(Module.GetFocusMacroName(), 1, "/focus", true)
        assert.is_false(Module:HasFocusMacro())
        assert.is_true(Module:CreateFocusMacro())
        assert.is_true(Module:HasFocusMacro())
        assert.is_false(Macro.IsCharacterSlot(Macro.GetIndexByName(Module.GetFocusMacroName())))
    end)

    it("refuses to create the focus macro when general slots are full", function()
        Macro.FillAccountSlotsForTests()
        local ok, reason = Module:CreateFocusMacro()
        assert.is_false(ok)
        assert.equals("no_slot", reason)
        assert.is_false(Module:HasFocusMacro())
    end)

    it("refuses to create the focus macro during combat", function()
        Combat.FireEnter()
        local ok, reason = Module:CreateFocusMacro()
        assert.is_false(ok)
        assert.equals("combat", reason)
        assert.is_false(Module:HasFocusMacro())
    end)

    it("defaults to Shift+Left, no Target Frame bind, and no optional claim actions", function()
        assert.equals(Module.MODIFIER_SHIFT, Module:GetModifier())
        assert.equals(Module.MOUSE_LEFT, Module:GetMouseButton())
        assert.is_false(Module:IsTargetFrameBound())
        assert.is_false(Module:ShouldSetMarker())
        assert.equals(8, Module:GetMarker())
        assert.equals(Module.ANNOUNCE_OFF, Module:GetAnnounce())
        assert.is_false(Module:ShouldAnnounce())
        assert.equals("/focus", Module.GetFocusMacroBody())
        assert.equals(Module.MACRO_STATUS_MISSING, Module:GetFocusMacroStatus())
        local binding = Module:GetClickBinding()
        assert.equals("shift-type1", binding.typeAttribute)
        assert.equals("shift-macro1", binding.macroAttribute)
        assert.equals("LeftButtonDown", binding.click)
    end)

    it("keeps optional marker and announcement settings when marking is turned off", function()
        Module:SetSetMarker(true)
        Module:SetMarker(7)
        Module:SetAnnounce(Module.CHANNEL_SAY)
        Module:SetSetMarker(false)
        assert.is_false(Module:ShouldSetMarker())
        assert.equals(7, Module:GetMarker())
        assert.equals(Module.CHANNEL_SAY, Module:GetAnnounce())
        assert.is_false(Module:ShouldAnnounce())
        assert.equals("/focus", Module.GetFocusMacroBody())
    end)

    it("generates marker and announcement lines with the raid-group guard", function()
        Module:SetSetMarker(true)
        Module:SetMarker(7)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 7", Module.GetFocusMacroBody())
        Module:SetAnnounce(Module.CHANNEL_PARTY)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 7\n/p 我断{rt7}", Module.GetFocusMacroBody())
        Module:SetAnnounce(Module.CHANNEL_SAY)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 7\n/s 我断{rt7}", Module.GetFocusMacroBody())
        Module:SetAnnounce(Module.CHANNEL_EMOTE)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 7\n/e 我断{rt7}", Module.GetFocusMacroBody())
    end)

    it("does not emit the raid-group guard when only /focus is generated", function()
        assert.equals(nil, Module.GetFocusMacroBody():find("stopmacro", 1, true))
    end)

    it("does not create a missing macro when optional claim settings change", function()
        Module:SetSetMarker(true)
        Module:SetAnnounce(Module.CHANNEL_PARTY)
        assert.is_false(Module:HasFocusMacro())
        assert.equals(0, Macro.createCount)
        assert.equals(Module.MACRO_STATUS_MISSING, Module:GetFocusMacroStatus())
    end)

    it("updates an existing managed macro when optional claim settings change", function()
        assert.is_true(Module:CreateFocusMacro())
        assert.equals("/focus", Macro.Get(Module.GetFocusMacroName()).body)
        Module:SetSetMarker(true)
        Module:SetMarker(3)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 3", Macro.Get(Module.GetFocusMacroName()).body)
        Module:SetAnnounce(Module.CHANNEL_PARTY)
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 3\n/p 我断{rt3}", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_READY, Module:GetFocusMacroStatus())
    end)

    it("does not rewrite the managed macro when only the shortcut changes", function()
        assert.is_true(Module:CreateFocusMacro())
        local edits = Macro.editCount
        Module:SetModifier(Module.MODIFIER_CTRL)
        Module:SetMouseButton(Module.MOUSE_RIGHT)
        Module:SetBindTargetFrame(true)
        assert.equals(edits, Macro.editCount)
        assert.equals("/focus", Macro.Get(Module.GetFocusMacroName()).body)
        local binding = Module:GetClickBinding()
        assert.equals("ctrl-type2", binding.typeAttribute)
        assert.equals("ctrl-macro2", binding.macroAttribute)
        assert.equals("RightButtonDown", binding.click)
    end)

    it("does not overwrite an unrelated macro that already uses the focus name", function()
        Macro.Create(Module.GetFocusMacroName(), 1, "/say custom", false)
        Module:SetSetMarker(true)
        assert.equals("/say custom", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_CONFLICT, Module:GetFocusMacroStatus())
        local ok, reason = Module:CreateFocusMacro()
        assert.is_false(ok)
        assert.equals("conflict", reason)
        assert.equals("/say custom", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_CONFLICT, Module:GetFocusMacroStatus())
    end)

    it("treats a stored body as matching when only line endings differ", function()
        Module:SetSetMarker(true)
        Module:SetMarker(7)
        Module:SetAnnounce(Module.CHANNEL_PARTY)
        local expected = Module.GetFocusMacroBody()
        Macro.Create(Module.GetFocusMacroName(), 1, expected:gsub("\n", "\r\n") .. "\r\n", false)
        assert.equals(Module.MACRO_STATUS_READY, Module:GetFocusMacroStatus())
        local edits = Macro.editCount
        assert.is_true(Module:CreateFocusMacro())
        assert.equals(edits, Macro.editCount)
    end)

    it("treats a previous generated body as managed and syncs it", function()
        Module:SetSetMarker(true)
        Module:SetMarker(8)
        Macro.Create(Module.GetFocusMacroName(), 1, "/focus", false)
        assert.equals(Module.MACRO_STATUS_CONFLICT, Module:GetFocusMacroStatus())
        assert.is_true(Module:SyncFocusMacro())
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 8", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_READY, Module:GetFocusMacroStatus())
    end)

    it("rewrites a stale managed macro when the game reports a macro change", function()
        Module:SetSetMarker(true)
        Module:SetMarker(3)
        assert.is_true(Module:CreateFocusMacro())
        Module:ListenForMacros()
        local index = Macro.GetIndexByName(Module.GetFocusMacroName())
        Macro.Edit(index, nil, nil, "/focus")
        Macro.FireChanged()
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 3", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_READY, Module:GetFocusMacroStatus())
    end)

    it("does not rewrite a custom macro when the game reports a macro change", function()
        Macro.Create(Module.GetFocusMacroName(), 1, "/say custom", false)
        Module:ListenForMacros()
        Macro.FireChanged()
        assert.equals("/say custom", Macro.Get(Module.GetFocusMacroName()).body)
        assert.equals(Module.MACRO_STATUS_CONFLICT, Module:GetFocusMacroStatus())
    end)

    it("defers managed macro updates until combat ends", function()
        assert.is_true(Module:CreateFocusMacro())
        Module:ListenForMacros()
        Combat.FireEnter()
        Module:SetSetMarker(true)
        assert.equals("/focus", Macro.Get(Module.GetFocusMacroName()).body)
        Combat.FireLeave()
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 8", Macro.Get(Module.GetFocusMacroName()).body)
    end)

    it("keeps Target Frame clicks off until coverage is enabled", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.is_true(Module:ShouldBindNameplateClicks())
        assert.is_false(Module:ShouldBindTargetFrameClicks())
        Module:SetBindTargetFrame(true)
        assert.is_true(Module:ShouldBindTargetFrameClicks())
        Module:SetBindTargetFrame(false)
        assert.is_false(Module:ShouldBindTargetFrameClicks())
    end)

    it("exposes all six modifier and mouse combinations", function()
        for _, modifier in ipairs(Module.MODIFIERS) do
            for _, mouseButton in ipairs(Module.MOUSE_BUTTONS) do
                Module:SetModifier(modifier)
                Module:SetMouseButton(mouseButton)
                local binding = Module:GetClickBinding()
                local buttonIndex = mouseButton == Module.MOUSE_RIGHT and 2 or 1
                assert.equals(modifier .. "-type" .. buttonIndex, binding.typeAttribute)
                assert.equals(modifier .. "-macro" .. buttonIndex, binding.macroAttribute)
                assert.equals(mouseButton .. "Down", binding.click)
            end
        end
    end)

    it("restores saved Interrupt Claim settings", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = {
                InterruptClaim = {
                    enabled = true,
                    modifier = "alt",
                    mouseButton = "RightButton",
                    bindTargetFrame = true,
                    setMarker = true,
                    marker = 2,
                    announce = "emote",
                },
            },
        }))
        Module = ns.Modules.Get("InterruptClaim")
        assert.is_true(Module:IsEnabled())
        assert.equals("alt", Module:GetModifier())
        assert.equals("RightButton", Module:GetMouseButton())
        assert.is_true(Module:IsTargetFrameBound())
        assert.is_true(Module:ShouldSetMarker())
        assert.equals(2, Module:GetMarker())
        assert.equals("emote", Module:GetAnnounce())
        assert.is_true(Module:ShouldAnnounce())
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 2\n/e 我断{rt2}", Module.GetFocusMacroBody())
    end)

    it("reads a legacy boolean announce setting with announceChannel", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = {
                InterruptClaim = {
                    setMarker = true,
                    announce = true,
                    announceChannel = "say",
                },
            },
        }))
        Module = ns.Modules.Get("InterruptClaim")
        assert.equals(Module.CHANNEL_SAY, Module:GetAnnounce())
        assert.is_true(Module:ShouldAnnounce())
        Module:SetAnnounce(Module.ANNOUNCE_OFF)
        assert.equals(Module.ANNOUNCE_OFF, Module:GetAnnounce())
        assert.is_false(Module:ShouldAnnounce())
        assert.equals("/focus\n/stopmacro [group:raid]\n/tm 8", Module.GetFocusMacroBody())
    end)
end)

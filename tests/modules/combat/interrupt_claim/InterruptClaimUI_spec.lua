local Loader = require("helpers.loader")

local UI_PATH = "modules/combat/interrupt_claim/InterruptClaimUI.lua"
local MACRO = "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]"

describe("InterruptClaim UI", function()
    local ns, InterruptClaim, Binding, Combat, UnitFrame, originalCreateFrame
    local created
    local createCount
    local section

    local function FakeButton(name)
        local frame = {
            name = name,
            parent = true,
            shown = true,
            attributes = {},
            clicks = nil,
            mouseEnabled = true,
        }
        function frame:RegisterForClicks(...)
            self.clicks = { ... }
        end
        function frame:SetAttribute(key, value)
            self.attributes[key] = value
        end
        function frame:GetAttribute(key)
            return self.attributes[key]
        end
        function frame:EnableMouse(enabled)
            self.mouseEnabled = enabled == true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:SetParent(parent)
            self.parent = parent
        end
        function frame:GetName()
            return self.name
        end
        return frame
    end

    local function AttachUi()
        created = nil
        createCount = 0
        section = nil
        ns.MainPanel = {
            RegisterSection = function(_, def)
                section = def
            end,
        }
        CreateFrame = function(frameType, name, _, template)
            createCount = createCount + 1
            created = FakeButton(name)
            created.frameType = frameType
            created.template = template
            return created
        end
        assert(loadfile(UI_PATH))(Loader.ADDON_NAME, ns)
        InterruptClaim:OnEnable()
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        InterruptClaim = ns.Modules.Get("InterruptClaim")
        Binding = ns.Api.Binding
        Combat = ns.Api.Combat
        UnitFrame = ns.Api.UnitFrame
        AttachUi()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("registers a combat page with a header toggle", function()
        assert.equals(ns.L.INTERRUPT_CLAIM_TITLE, section.title)
        assert.equals(ns.PanelGroups.COMBAT, section.group)
        assert.equals(ns.L.INTERRUPT_CLAIM_HINT, section.tooltip)
        assert.is_false(section.enabled)
        assert.equals("function", type(section.onEnabledChanged))
        assert.equals("function", type(section.build))
    end)

    it("does not create a click button while disabled", function()
        assert.equals(0, createCount)
        assert.is_nil(next(Binding.overrides))
    end)

    it("binds Shift+left-click to a hidden secure focus macro when enabled", function()
        InterruptClaim:SetEnabled(true)
        assert.equals(1, createCount)
        assert.equals("Button", created.frameType)
        assert.equals("SecureActionButtonTemplate", created.template)
        assert.equals(Loader.ADDON_NAME .. "InterruptClaim", created.name)
        assert.same({ "AnyDown", "AnyUp" }, created.clicks)
        assert.is_true(created.attributes.useOnKeyDown)
        assert.equals("macro", created.attributes.type)
        assert.equals(MACRO, created.attributes.macrotext)
        assert.is_false(created.mouseEnabled)
        assert.is_false(created.shown)
        local overrides = Binding.overrides[created]
        assert.equals(1, #overrides)
        assert.is_true(overrides[1].isPriority)
        assert.equals("SHIFT-BUTTON1", overrides[1].key)
        assert.equals(created.name, overrides[1].buttonName)
    end)

    it("removes the override and button when disabled", function()
        InterruptClaim:SetEnabled(true)
        local frame = created
        InterruptClaim:SetEnabled(false)
        assert.is_nil(Binding.overrides[frame])
        assert.is_false(frame.shown)
        assert.is_nil(frame.parent)
    end)

    it("reuses one named button across enable cycles", function()
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetEnabled(false)
        InterruptClaim:SetEnabled(true)
        assert.equals(1, createCount)
        assert.equals(1, #Binding.overrides[created])
    end)

    it("defers binding changes until combat lockdown ends", function()
        Combat.FireEnter()
        InterruptClaim:SetEnabled(true)
        assert.equals(0, createCount)
        Combat.FireLeave()
        assert.equals(1, createCount)
        assert.equals(1, #Binding.overrides[created])

        Combat.FireEnter()
        InterruptClaim:SetEnabled(false)
        assert.equals(1, #Binding.overrides[created])
        Combat.FireLeave()
        assert.is_nil(Binding.overrides[created])
    end)

    it("rebinds when the chosen click changes", function()
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_CTRL)
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_RIGHT)
        local overrides = Binding.overrides[created]
        assert.equals(1, #overrides)
        assert.equals("CTRL-BUTTON2", overrides[1].key)
    end)

    it("defers a click change until combat lockdown ends", function()
        InterruptClaim:SetEnabled(true)
        Combat.FireEnter()
        InterruptClaim:SetMouseButton(InterruptClaim.MOUSE_FORWARD)
        assert.equals("SHIFT-BUTTON1", Binding.overrides[created][1].key)
        Combat.FireLeave()
        assert.equals("SHIFT-BUTTON5", Binding.overrides[created][1].key)
    end)

    it("rewrites the macro when clear-focus is turned off", function()
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetClearFocusEnabled(false)
        assert.equals("/focus [@mouseover,exists]", created.attributes.macrotext)
        InterruptClaim:SetMarkEnabled(true)
        assert.equals("/focus [@mouseover,exists]\n/tm [@focus]1", created.attributes.macrotext)
        InterruptClaim:SetClearFocusEnabled(true)
        assert.equals(MACRO .. "\n/tm [@focus]1", created.attributes.macrotext)
    end)

    it("rewrites the macro when marking is turned on", function()
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetMarkEnabled(true)
        assert.equals(MACRO .. "\n/tm [@focus]1", created.attributes.macrotext)
        InterruptClaim:SetMarkIndex(3)
        assert.equals(MACRO .. "\n/tm [@focus]3", created.attributes.macrotext)
        InterruptClaim:SetPreventOverwrite(true)
        assert.equals(MACRO .. "\n/tm [@focus]~3", created.attributes.macrotext)
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_PARTY)
        assert.equals(
            MACRO .. "\n/tm [@focus]~3\n/stopmacro [nogroup:party][@focus,noexists]\n/p 我断{rt3}%f",
            created.attributes.macrotext
        )
        InterruptClaim:SetAnnounceMessage("我断{marker}")
        assert.equals(
            MACRO .. "\n/tm [@focus]~3\n/stopmacro [nogroup:party][@focus,noexists]\n/p 我断{rt3}",
            created.attributes.macrotext
        )
        InterruptClaim:SetAnnounceChannel(InterruptClaim.CHANNEL_SAY)
        assert.equals(
            MACRO .. "\n/tm [@focus]~3\n/stopmacro [nogroup:party][@focus,noexists]\n/s 我断{rt3}",
            created.attributes.macrotext
        )
        InterruptClaim:SetAnnounceMessage("")
        assert.equals(MACRO .. "\n/tm [@focus]~3", created.attributes.macrotext)
        assert.equals(1, #Binding.overrides[created])
    end)

    it("defers a marker change until combat lockdown ends", function()
        InterruptClaim:SetEnabled(true)
        Combat.FireEnter()
        InterruptClaim:SetMarkEnabled(true)
        assert.equals(MACRO, created.attributes.macrotext)
        Combat.FireLeave()
        assert.equals(MACRO .. "\n/tm [@focus]1", created.attributes.macrotext)
    end)

    local function UnitButton(name)
        local frame = FakeButton(name)
        frame.protected = true
        return frame
    end

    it("sets shift-left-click to focus on unit frames without changing unmodified targeting", function()
        local player = UnitButton("PlayerFrame")
        player.attributes["*type1"] = "target"
        player.attributes.type1 = "target"
        UnitFrame.frames[1] = player
        InterruptClaim:SetEnabled(true)
        assert.equals("focus", player.attributes["shift-type1"])
        assert.is_nil(player.attributes["shift-macrotext1"])
        assert.equals("shift-type1", player.attributes["neweratools-interruptclaim"])
        assert.equals("target", player.attributes.type1)
        assert.equals("target", player.attributes["*type1"])
        assert.equals(1, #Binding.overrides[created])
        assert.equals("SHIFT-BUTTON1", Binding.overrides[created][1].key)
    end)

    it("skips a unit frame that already has that modified click", function()
        local player = UnitButton("PlayerFrame")
        player.attributes["shift-type1"] = "spell"
        UnitFrame.frames[1] = player
        InterruptClaim:SetEnabled(true)
        assert.equals("spell", player.attributes["shift-type1"])
        assert.is_nil(player.attributes["neweratools-interruptclaim"])
    end)

    it("configures ClickCastFrames and compact frames that appear after login", function()
        local elv = UnitButton("ElvUF_PartyGroup1UnitButton1")
        UnitFrame.frames[1] = elv
        InterruptClaim:SetEnabled(true)
        assert.equals("focus", elv.attributes["shift-type1"])

        local raid = UnitButton("CompactRaidFrame1")
        UnitFrame.FireCreated(raid)
        assert.equals("focus", raid.attributes["shift-type1"])
        assert.equals("shift-type1", raid.attributes["neweratools-interruptclaim"])
    end)

    it("does not configure nameplates or unprotected frames", function()
        local plate = UnitButton("NamePlate1")
        plate.nameplate = true
        local insecure = UnitButton("SomeFrame")
        insecure.protected = false
        UnitFrame.frames[1] = plate
        UnitFrame.frames[2] = insecure
        InterruptClaim:SetEnabled(true)
        UnitFrame.FireCreated(plate)
        UnitFrame.FireCreated(insecure)
        assert.is_nil(plate.attributes["shift-type1"])
        assert.is_nil(insecure.attributes["shift-type1"])
    end)

    it("defers unit-frame attributes until combat lockdown ends", function()
        local player = UnitButton("PlayerFrame")
        UnitFrame.frames[1] = player
        Combat.FireEnter()
        InterruptClaim:SetEnabled(true)
        assert.is_nil(player.attributes["shift-type1"])
        local raid = UnitButton("CompactRaidFrame1")
        UnitFrame.FireCreated(raid)
        assert.is_nil(raid.attributes["shift-type1"])
        Combat.FireLeave()
        assert.equals("focus", player.attributes["shift-type1"])
        assert.equals("focus", raid.attributes["shift-type1"])
    end)

    it("clears unit-frame attributes when disabled and when the click changes", function()
        local player = UnitButton("PlayerFrame")
        UnitFrame.frames[1] = player
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_CTRL)
        assert.is_nil(player.attributes["shift-type1"])
        assert.equals("focus", player.attributes["ctrl-type1"])
        InterruptClaim:SetEnabled(false)
        assert.is_nil(player.attributes["ctrl-type1"])
        assert.is_nil(player.attributes["neweratools-interruptclaim"])
    end)

    it("does not take over another addon's binding when the click changes", function()
        local player = UnitButton("PlayerFrame")
        player.attributes["ctrl-type1"] = "spell"
        UnitFrame.frames[1] = player
        InterruptClaim:SetEnabled(true)
        assert.equals("focus", player.attributes["shift-type1"])
        InterruptClaim:SetModifier(InterruptClaim.MODIFIER_CTRL)
        assert.is_nil(player.attributes["shift-type1"])
        assert.equals("spell", player.attributes["ctrl-type1"])
        assert.is_nil(player.attributes["neweratools-interruptclaim"])
    end)

    it("picks up frames registered without notification on the frame after a roster change", function()
        local Group = ns.Api.Group
        local Timer = ns.Api.Timer
        InterruptClaim:SetEnabled(true)
        local cell = UnitButton("DFPartyFrame1")
        UnitFrame.frames[1] = cell
        Group.FireChanged()
        Group.FireChanged()
        assert.is_nil(cell.attributes["shift-type1"])
        assert.equals(1, #Timer.pending)
        Timer.RunPending()
        assert.equals("focus", cell.attributes["shift-type1"])
    end)

    it("skips the roster rescan while disabled", function()
        local Timer = ns.Api.Timer
        ns.Api.Group.FireChanged()
        assert.equals(0, #Timer.pending)
    end)

    it("releases a frame once the walk stops reporting it", function()
        local Timer = ns.Api.Timer
        local cell = UnitButton("ElvUF_Party1")
        UnitFrame.frames[1] = cell
        InterruptClaim:SetEnabled(true)
        assert.equals("focus", cell.attributes["shift-type1"])
        UnitFrame.frames[1] = nil
        ns.Api.Group.FireChanged()
        Timer.RunPending()
        assert.is_nil(cell.attributes["shift-type1"])
        assert.is_nil(cell.attributes["neweratools-interruptclaim"])
    end)

    -- Mirrors DandersFrames' ClearBlizzardClickCastFromFrame suppression pass.
    local function BlankModifierClicks(frame)
        frame:SetAttribute("type1", "")
        for _, mod in ipairs({ "shift-", "ctrl-", "alt-", "shift-ctrl-" }) do
            frame:SetAttribute(mod .. "type1", "")
            frame:SetAttribute(mod .. "type2", "")
        end
    end

    it("restores its click when a click-casting addon blanks it", function()
        local target = UnitButton("EQOLUFTargetFrame")
        UnitFrame.frames[1] = target
        InterruptClaim:SetEnabled(true)
        BlankModifierClicks(target)
        assert.equals("focus", target.attributes["shift-type1"])
        assert.equals("", target.attributes["ctrl-type1"])

        InterruptClaim:SetMarkEnabled(true)
        BlankModifierClicks(target)
        target:SetAttribute("shift-macrotext1", nil)
        assert.equals("macro", target.attributes["shift-type1"])
        assert.equals(MACRO .. "\n/tm [@focus]1", target.attributes["shift-macrotext1"])
    end)

    it("yields to a real binding another addon writes later and does not reclaim it", function()
        local target = UnitButton("TargetFrame")
        UnitFrame.frames[1] = target
        InterruptClaim:SetEnabled(true)
        target:SetAttribute("shift-type1", "spell")
        assert.equals("spell", target.attributes["shift-type1"])
        assert.is_nil(target.attributes["neweratools-interruptclaim"])
        ns.Api.Group.FireChanged()
        ns.Api.Timer.RunPending()
        assert.equals("spell", target.attributes["shift-type1"])
    end)

    it("leaves blanked clicks alone once disabled", function()
        local target = UnitButton("TargetFrame")
        UnitFrame.frames[1] = target
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetEnabled(false)
        assert.is_nil(target.attributes["shift-type1"])
        BlankModifierClicks(target)
        assert.equals("", target.attributes["shift-type1"])
    end)

    it("restores a click blanked during combat once lockdown ends", function()
        local target = UnitButton("TargetFrame")
        UnitFrame.frames[1] = target
        InterruptClaim:SetEnabled(true)
        Combat.FireEnter()
        target:SetAttribute("shift-type1", "")
        assert.equals("", target.attributes["shift-type1"])
        Combat.FireLeave()
        assert.equals("focus", target.attributes["shift-type1"])
    end)

    it("writes the mark macro onto unit frames when marking is on", function()
        local player = UnitButton("PlayerFrame")
        UnitFrame.frames[1] = player
        InterruptClaim:SetEnabled(true)
        InterruptClaim:SetMarkEnabled(true)
        assert.equals("macro", player.attributes["shift-type1"])
        assert.equals(MACRO .. "\n/tm [@focus]1", player.attributes["shift-macrotext1"])
    end)
end)

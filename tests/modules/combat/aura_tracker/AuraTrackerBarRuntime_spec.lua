local Harness = require("helpers.aura_tracker")

local GLOBAL_NAMES = {
    "CreateFrame",
    "UIParent",
    "C_AddOns",
    "AuraContainerSortMethod",
    "AuraContainerSortDirection",
    "Enum",
}

describe("AuraTracker bar runtime", function()
    local ns, AuraTracker, Activation, Schema, Bar
    local containers, hosts, statusBars, flushed, paints
    local savedGlobals

    local function Calls(frame, name)
        return frame.calls[name] or 0
    end

    local function NewFrame(kind)
        local frame = { kind = kind, calls = {}, shown = false, enabled = false }

        local function Mark(name)
            frame.calls[name] = (frame.calls[name] or 0) + 1
        end

        function frame:SetFrameStrata()
            Mark("SetFrameStrata")
        end
        function frame:EnableMouse()
            Mark("EnableMouse")
        end
        function frame:SetMovable()
            Mark("SetMovable")
        end
        function frame:SetClampedToScreen()
            Mark("SetClampedToScreen")
        end
        function frame:SetSize()
            Mark("SetSize")
        end
        function frame:SetAllPoints()
            Mark("SetAllPoints")
        end
        function frame:ClearAllPoints()
            Mark("ClearAllPoints")
        end
        function frame:SetPoint()
            Mark("SetPoint")
        end
        function frame:Raise()
            Mark("Raise")
        end
        function frame:SetFrameLevel()
            Mark("SetFrameLevel")
        end
        function frame:GetFrameLevel()
            return 1
        end
        function frame:SetBackdrop()
            Mark("SetBackdrop")
        end
        function frame:SetBackdropColor()
            Mark("SetBackdropColor")
        end
        function frame:SetMinMaxValues()
            Mark("SetMinMaxValues")
        end
        function frame:SetStatusBarTexture()
            Mark("SetStatusBarTexture")
        end
        function frame:SetWordWrap()
            Mark("SetWordWrap")
        end
        function frame:Hide()
            Mark("Hide")
            self.shown = false
        end
        function frame:Show()
            Mark("Show")
            self.shown = true
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:SetEnabled(enabled)
            Mark("SetEnabled")
            self.enabled = enabled == true
        end
        function frame:IsEnabled()
            return self.enabled
        end
        function frame:CanChangeProtectedState()
            return true
        end
        function frame:CreateTexture()
            Mark("CreateTexture")
            return NewFrame("Texture")
        end
        function frame:CreateFontString()
            Mark("CreateFontString")
            return NewFrame("FontString")
        end
        function frame:AddAuraSlot(_, _, options)
            Mark("AddAuraSlot")
            local button = NewFrame("AuraButton")
            self.slotButton = button
            if options and options.initializeFrame then
                options.initializeFrame(button)
            end
            return button
        end
        function frame:SetUnit()
            Mark("SetUnit")
        end
        function frame:SetAuraSlotEnabled(_, enabled)
            Mark("SetAuraSlotEnabled")
            self.slotEnabled = enabled == true
        end
        function frame:SetAuraSlotFilterString()
            Mark("SetAuraSlotFilterString")
        end
        function frame:SetAuraSlotCandidateFilters()
            Mark("SetAuraSlotCandidateFilters")
        end
        function frame:UpdateAllAuras()
            Mark("UpdateAllAuras")
        end

        return setmetatable(frame, {
            __index = function(self, key)
                -- Absent access probes must stay nil. A synthesized function would look like a denial.
                if key == "CanBeAccessedInContext" or key == "IsForbidden" then
                    return nil
                end
                return function()
                    self.calls[key] = (self.calls[key] or 0) + 1
                end
            end,
        })
    end

    local function InstallFrameStub()
        savedGlobals = {}
        for _, name in ipairs(GLOBAL_NAMES) do
            savedGlobals[name] = _G[name]
        end
        containers = {}
        hosts = {}
        statusBars = {}
        CreateFrame = function(kind, name)
            local frame = NewFrame(kind)
            if kind == "AuraContainer" then
                containers[#containers + 1] = frame
            elseif kind == "StatusBar" then
                statusBars[#statusBars + 1] = frame
            elseif type(name) == "string" and name:find("Layout", 1, true) then
                hosts[#hosts + 1] = frame
            end
            return frame
        end
        UIParent = {}
        C_AddOns = {
            IsAddOnLoaded = function()
                return true
            end,
            LoadAddOn = function()
                return true
            end,
        }
        AuraContainerSortMethod = { Expiration = "Expiration" }
        AuraContainerSortDirection = { Normal = "Normal" }
        Enum = { StatusBarTimerDirection = { RemainingTime = 1 } }
    end

    local function RestoreGlobals()
        if not savedGlobals then
            return
        end
        for _, name in ipairs(GLOBAL_NAMES) do
            _G[name] = savedGlobals[name]
        end
        savedGlobals = nil
    end

    local function Deny(frame)
        function frame:CanBeAccessedInContext()
            return false
        end
    end

    local function Allow(frame)
        frame.CanBeAccessedInContext = nil
    end

    local function Prepare(id)
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.ALWAYS, nil)
    end

    local function Hostile(guid)
        ns.Api.Unit.SetForTests("target", {
            exists = true,
            guid = guid,
            canAssist = false,
        })
    end

    before_each(function()
        ns, AuraTracker, Activation, Schema = Harness.Start()
        flushed = {}
        paints = { count = 0 }
        InstallFrameStub()
        ns.LayoutEditor = {
            unregistered = 0,
            Register = function() end,
            Unregister = function()
                ns.LayoutEditor.unregistered = ns.LayoutEditor.unregistered + 1
            end,
            ApplyPosition = function() end,
            IsEditing = function()
                return false
            end,
            Refresh = function() end,
        }
        ns.AuraTrackerBarChromeUI = {
            BarSize = function()
                return 200, 18
            end,
            LineBackdrop = function()
                return {}
            end,
            ApplyBarChrome = function()
                paints.count = paints.count + 1
            end,
            EnsureStackDividerHost = function(_, existing)
                return existing or NewFrame("Divider")
            end,
            ApplyStackDividers = function() end,
            ApplyTextDisplayAppearance = function() end,
        }
        ns.AuraTrackerBarPreviewUI = {
            Hide = function() end,
            Show = function() end,
            StartAnimation = function() end,
            ApplyAppearance = function() end,
        }
        ns.AuraTrackerProfileReport = {
            Show = function() end,
            RefreshIfShown = function() end,
        }
        assert(loadfile("modules/combat/aura_tracker/ui/bar/Appearance.lua"))("NewEraTools", ns)
        assert(loadfile("modules/combat/aura_tracker/ui/bar/Bar.lua"))("NewEraTools", ns)
        Bar = ns.AuraTrackerBarUI
        local flush = ns.AuraTrackerBarAppearanceUI.Flush
        function ns.AuraTrackerBarAppearanceUI.Flush(inst)
            flushed[#flushed + 1] = inst and inst.trackerId
            return flush(inst)
        end
    end)

    after_each(function()
        RestoreGlobals()
    end)

    describe("container lifecycle", function()
        it("creates one container and slot, then reuses them", function()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Bar.Update(id)
            assert.equals(1, #containers)
            assert.equals(1, Calls(containers[1], "AddAuraSlot"))
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))

            local container = containers[1]
            Bar.Update(id)
            assert.equals(1, #containers)
            assert.is_true(containers[1] == container)
            assert.equals(1, Calls(container, "AddAuraSlot"))
            assert.equals(1, Calls(container, "UpdateAllAuras"))
        end)

        it("retargets the existing slot when the source changes", function()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Bar.Update(id)
            local container = containers[1]
            local slots = Calls(container, "AddAuraSlot")

            Hostile("Creature-A")
            AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
            Bar.Update(id)

            assert.equals(1, #containers)
            assert.is_true(containers[1] == container)
            assert.equals(slots, Calls(container, "AddAuraSlot"))
            assert.is_true(Calls(container, "SetUnit") > 0)
            assert.is_true(Calls(container, "SetAuraSlotFilterString") > 0)
        end)

        it("hides a removed tracker and does not keep updating its container", function()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Hostile("Creature-A")
            AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
            Bar.Update(id)
            local container = containers[1]
            local host = hosts[1]
            assert.is_true(container.shown)
            assert.is_true(host.shown)

            AuraTracker:RemoveTracker(id)
            Bar.Update(nil)
            assert.is_false(host.shown)
            assert.is_false(container.shown)
            assert.is_false(container.slotEnabled)
            assert.is_false(container.enabled)
            assert.equals(1, ns.LayoutEditor.unregistered)
            local scans = Calls(container, "UpdateAllAuras")
            local slots = Calls(container, "AddAuraSlot")

            Bar.Update(nil)
            Bar.Update(id)
            assert.equals(scans, Calls(container, "UpdateAllAuras"))
            assert.equals(slots, Calls(container, "AddAuraSlot"))
            assert.equals(1, #containers)
            assert.is_false(host.shown)
            assert.is_false(container.shown)
            assert.is_false(container.slotEnabled)
            assert.equals(1, ns.LayoutEditor.unregistered)
        end)

        it("leaves another tracker's container alone", function()
            local first = AuraTracker:AddTracker()
            local second = AuraTracker:AddTracker()
            Prepare(first)
            Prepare(second)
            Bar.Update(first)
            Bar.Update(second)
            local firstContainer = containers[1]
            local scans = Calls(firstContainer, "UpdateAllAuras")
            local slots = Calls(firstContainer, "AddAuraSlot")
            local units = Calls(firstContainer, "SetUnit")

            Bar.Update(second)
            assert.is_true(containers[1] == firstContainer)
            assert.equals(2, #containers)
            assert.equals(scans, Calls(firstContainer, "UpdateAllAuras"))
            assert.equals(slots, Calls(firstContainer, "AddAuraSlot"))
            assert.equals(units, Calls(firstContainer, "SetUnit"))
        end)
    end)

    describe("retarget rescan", function()
        it("scans on show, then ignores the same plain guid and a later serial change", function()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Hostile("Creature-A")
            AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
            AuraTracker:ListenForUnitContext()

            Bar.Update(id)
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))

            Bar.Update(id)
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))

            ns.Api.GameEvents.Fire("PLAYER_TARGET_CHANGED")
            Bar.Update(id)
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))
            assert.equals(1, Calls(containers[1], "AddAuraSlot"))
            assert.equals(1, #containers)
        end)

        it("scans an unproven guid when the retarget serial changes, once", function()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Hostile(nil)
            AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
            AuraTracker:ListenForUnitContext()

            Bar.Update(id)
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))
            Bar.Update(id)
            assert.equals(1, Calls(containers[1], "UpdateAllAuras"))

            ns.Api.GameEvents.Fire("PLAYER_TARGET_CHANGED")
            Bar.Update(id)
            assert.equals(2, Calls(containers[1], "UpdateAllAuras"))
            Bar.Update(id)
            assert.equals(2, Calls(containers[1], "UpdateAllAuras"))
            assert.equals(1, Calls(containers[1], "AddAuraSlot"))
            assert.equals(1, #containers)
        end)
    end)

    describe("tracking display cleanup", function()
        local function ShownTarget()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Hostile("Creature-A")
            AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
            Bar.Update(id)
            return id
        end

        local function AssertCleared(container, host, scans)
            assert.is_false(host.shown)
            assert.is_false(container.shown)
            assert.is_false(container.slotEnabled)
            assert.is_false(container.enabled)
            assert.equals(scans, Calls(container, "UpdateAllAuras"))
        end

        it("hides the host and disables the slot when the tracker is disabled", function()
            local id = ShownTarget()
            local scans = Calls(containers[1], "UpdateAllAuras")
            AuraTracker:SetTrackerEnabled(id, false)
            Bar.Update(id)
            AssertCleared(containers[1], hosts[1], scans)
        end)

        it("clears the live display when the module is disabled and keeps the saved tracker", function()
            local id = ShownTarget()
            local scans = Calls(containers[1], "UpdateAllAuras")
            AuraTracker:SetEnabled(false)
            Bar.Update(id)
            AssertCleared(containers[1], hosts[1], scans)
            assert.equals(774, AuraTracker:GetSpellId(id))
            assert.same({ id }, AuraTracker:GetTrackerIds())
            assert.equals(1, #containers)
        end)

        it("drops a hostile aura when the target becomes friendly or missing", function()
            local id = ShownTarget()
            local scans = Calls(containers[1], "UpdateAllAuras")
            ns.Api.Unit.SetForTests("target", {
                exists = true,
                guid = "Player-friend",
                canAssist = true,
            })
            Bar.Update(id)
            AssertCleared(containers[1], hosts[1], scans)

            Hostile("Creature-B")
            Bar.Update(id)
            assert.is_true(containers[1].shown)
            assert.is_true(containers[1].slotEnabled)
            scans = Calls(containers[1], "UpdateAllAuras")

            ns.Api.Unit.SetForTests("target", { exists = false })
            Bar.Update(id)
            AssertCleared(containers[1], hosts[1], scans)
        end)

        it("clears the live display while a global hide condition is active", function()
            local id = ShownTarget()
            local scans = Calls(containers[1], "UpdateAllAuras")
            ns.Api.Activity.SetStateForTests({ skyriding = true })
            Bar.Update(id)
            AssertCleared(containers[1], hosts[1], scans)
        end)
    end)

    describe("appearance flush", function()
        local function ShownPlayer()
            local id = AuraTracker:AddTracker()
            Prepare(id)
            Bar.Update(id)
            return id
        end

        it("flushes the updated instance and does not repaint a ready bar", function()
            local id = ShownPlayer()
            assert.equals(1, paints.count)
            assert.same({ id }, flushed)

            flushed = {}
            Bar.Update(id)
            assert.same({ id }, flushed)
            assert.equals(1, paints.count)
        end)

        it("flushes only the instances Update is responsible for", function()
            local first = ShownPlayer()
            local second = AuraTracker:AddTracker()
            Prepare(second)
            Bar.Update(second)

            flushed = {}
            Bar.Update(first)
            assert.same({ first }, flushed)

            flushed = {}
            Bar.Update(nil)
            local seen = {}
            for _, id in ipairs(flushed) do
                seen[id] = (seen[id] or 0) + 1
            end
            assert.equals(1, seen[first])
            assert.equals(1, seen[second])
        end)

        it("keeps a blocked appearance pending until a later update can paint it", function()
            local id = ShownPlayer()
            assert.equals(1, paints.count)
            AuraTracker:SetWidth(id, 240)
            Deny(containers[1].slotButton)
            Deny(statusBars[1])
            Bar.ApplyAppearance(id)
            assert.is_true(Bar.PendingAppearanceKeys(id).width)

            Bar.Update(id)
            assert.equals(1, paints.count)
            assert.is_true(Bar.PendingAppearanceKeys(id).width)

            Allow(containers[1].slotButton)
            Allow(statusBars[1])
            Bar.Update(id)
            assert.equals(2, paints.count)
            assert.is_nil(Bar.PendingAppearanceKeys(id).width)
        end)
    end)
end)

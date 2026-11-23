local Loader = require("helpers.loader")

local INTERRUPT_CHAIN_VIEW_PATH = "ui/InterruptChainView.lua"
local SHARED_INTERRUPT_CHAIN_HUD_PATH = "ui/InterruptChainHUD.lua"
local SHARED_INTERRUPT_ROTATION_TRACKER_PATH = "ui/InterruptRotationTracker.lua"
local LABELS_PATH = "modules/venomous_abyss/twin_fangs/ui/interrupt_chain/Labels.lua"
local INTERRUPT_ROTATION_TRACKER_PATH = "modules/venomous_abyss/twin_fangs/ui/InterruptRotationTracker.lua"
local PANEL_PATH = "modules/venomous_abyss/twin_fangs/ui/Panel.lua"

describe("TwinFangs InterruptRotationTracker", function()
    local ns, Module, L, originalCreateFrame
    local registered
    local scopes
    local editing
    local activeScopeId

    local function FakeLabel()
        local label = { shown = true }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint() end
        function label:ClearAllPoints() end
        function label:SetFont() end
        function label:SetShadowOffset() end
        function label:SetShadowColor() end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:SetTextColor() end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        function label:IsShown()
            return self.shown
        end
        return label
    end

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            scripts = {},
            fontStrings = {},
            textures = {},
            width = 0,
            height = 0,
            scale = 1,
        }
        function frame:SetScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale
        end
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:ClearAllPoints()
            self.anchor = nil
        end
        function frame:SetPoint(point, relative, relativePoint, x, y)
            self.anchor = { point, relative, relativePoint, x, y }
        end
        function frame:SetWidth(width)
            self.width = width
        end
        function frame:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function frame:GetWidth()
            return self.width
        end
        function frame:GetHeight()
            return self.height
        end
        function frame:SetBackdropBorderColor() end
        function frame:SetBackdropColor() end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:EnableMouse() end
        function frame:SetHeight(height)
            self.height = height
        end
        function frame:SetParent(parent)
            self.parent = parent
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:CreateFontString()
            local label = FakeLabel()
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        function frame:CreateTexture()
            local texture = { shown = true }
            function texture:SetTexture() end
            function texture:SetVertexColor() end
            function texture:ClearAllPoints() end
            function texture:SetPoint() end
            function texture:SetSize() end
            function texture:SetWidth() end
            function texture:SetHeight() end
            function texture:SetAllPoints() end
            function texture:SetGradient() end
            function texture:SetColorTexture() end
            function texture:SetAlpha() end
            function texture:Show()
                self.shown = true
            end
            function texture:Hide()
                self.shown = false
            end
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function frame:HookScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:Raise() end
        return frame
    end

    local function AttachUi(namespace)
        registered = {}
        scopes = {}
        editing = {}
        activeScopeId = nil
        namespace.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            CreateSurface = function(parent)
                return FakeFrame(parent)
            end,
            CreateLabel = function(parent)
                return parent:CreateFontString()
            end,
        }
        namespace.Layout = {
            Stack = function()
                return {
                    AddRow = function()
                        return FakeFrame()
                    end,
                    SetEntryHeight = function() end,
                    GetHeight = function()
                        return 64
                    end,
                }
            end,
        }
        namespace.LayoutEditor = {
            Register = function(def)
                registered[def.id] = def
            end,
            ApplyPosition = function(frame, position)
                frame.position = position
            end,
            RegisterScope = function(def)
                scopes[def.id] = def
            end,
            GetActiveScopeId = function()
                return activeScopeId
            end,
            BeginScope = function(scopeId)
                activeScopeId = scopeId
                if scopeId == namespace.LayoutEditor.COMMON_SCOPE_ID then
                    for _, def in pairs(registered) do
                        if def.global and def.isEnabled() then
                            editing[def.id] = true
                            def.onEditBegin()
                        end
                    end
                    return true
                end
                local scope = scopes[scopeId]
                if not scope then
                    return false
                end
                if scope.prepare then
                    scope.prepare()
                end
                for _, id in ipairs(scope.elementIds) do
                    local def = registered[id]
                    if def and def.isEnabled() then
                        editing[id] = true
                        def.onEditBegin()
                    end
                end
                return true
            end,
            End = function()
                activeScopeId = nil
                for id, def in pairs(registered) do
                    if editing[id] then
                        editing[id] = nil
                        def.onEditEnd()
                    end
                end
            end,
            IsEditing = function()
                return next(editing) ~= nil
            end,
            Refresh = function() end,
            COMMON_SCOPE_ID = "common",
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile(INTERRUPT_CHAIN_VIEW_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(SHARED_INTERRUPT_CHAIN_HUD_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(SHARED_INTERRUPT_ROTATION_TRACKER_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(LABELS_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(INTERRUPT_ROTATION_TRACKER_PATH))(Loader.ADDON_NAME, namespace)
    end

    local function LoadPanel()
        ns.Modules.Internals("TwinFangs").SoakTimelineUI = {
            LAYOUT_ID = "TwinFangs:soakTimeline",
            Ensure = function() end,
            Update = function() end,
        }
        ns.Modules.Internals("TwinFangs").VenomRosterUI = {
            LAYOUT_ID = "TwinFangs:venomRoster",
            Ensure = function() end,
            Update = function() end,
        }
        ns.Callout = {
            LAYOUT_ID = "Callout:1",
            Ensure = function() end,
            SetScopePreview = function() end,
        }
        ns.CollapsibleSection = {}
        ns.FeatureSection = {}
        ns.ColorSwatch = {}
        ns.Dropdown = {}
        ns.NumberStepper = {}
        ns.Slider = {}
        ns.Checkbox = {
            Create = function()
                return {
                    SetChecked = function() end,
                    GetChecked = function()
                        return false
                    end,
                    SetScript = function() end,
                    SetHitRectInsets = function() end,
                    SetPoint = function() end,
                    SetEnabled = function() end,
                }
            end,
        }
        ns.RaidRoleModeLabel = {}
        ns.AddonCheckPanel = {}
        ns.MainPanel = {
            RegisterSection = function() end,
        }
        assert(loadfile(PANEL_PATH))(Loader.ADDON_NAME, ns)
        Module:OnEnable()
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        L = ns.L
        AttachUi(ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function InterruptRotationTracker()
        return ns.Modules.Internals("TwinFangs").InterruptRotationTrackerUI
    end

    local function PreviewState()
        local state = {
            total = 5,
            completed = 0,
            myIndices = { 3 },
            label = L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT,
            theme = "cyan",
        }
        local players = Module.db.interruptReminder.chain.front_left.players
        local name = players and players[1] and players[1].name
        if type(name) == "string" then
            state.currentAssignee = name:match("^([^-]+)") or name
        end
        return state
    end

    it("creates one instance, registers it, and stays hidden in normal play", function()
        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        assert.equals("TwinFangs:interrupt", binding.LAYOUT_ID)
        assert.is_true(def.global)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TITLE, def.label)
        assert.is_true(def.isEnabled())
        assert.is_false(hud.shown)
        assert.same(Module:GetInterruptRotationTrackerPosition(), hud.position)
    end)

    it("uses the shared HUD preview in Common UI and the Twin Fangs mock in Twin Fangs Edit Mode", function()
        LoadPanel()
        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        Module:SetInterruptReminderEnabled(true)
        binding.Update()
        assert.is_false(hud.shown)

        ns.LayoutEditor.BeginScope("common")
        assert.is_true(hud.shown)
        assert.same(ns.InterruptRotationTracker.PreviewState(), hud:GetState())

        ns.LayoutEditor.BeginScope("twin_fangs")
        assert.is_false(Module:HasPrimaryInterruptAssignment())
        assert.is_true(hud.shown)
        assert.same(PreviewState(), hud:GetState())

        ns.LayoutEditor.End()
        assert.is_false(hud.shown)
        Module:SetInterruptReminderEnabled(false)
        binding.Update()
        assert.is_false(hud.shown)
    end)

    it("registers the interrupt rotation tracker in the Twin Fangs scope", function()
        LoadPanel()
        local scope = scopes.twin_fangs
        local binding = InterruptRotationTracker()
        assert.equals(L.TWIN_FANGS_LAYOUT_SCOPE, scope.label)
        assert.same({
            ns.Callout.LAYOUT_ID,
            binding.LAYOUT_ID,
            "TwinFangs:soakTimeline",
            "TwinFangs:venomRoster",
        }, scope.elementIds)
        assert.is_true(registered[binding.LAYOUT_ID].global)
    end)

    it("repositions through the Twin Fangs layout element and keeps the saved point", function()
        LoadPanel()
        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        local next = { point = "BOTTOM", relativePoint = "BOTTOM", x = 8, y = 16 }
        def.setPosition(next)
        assert.same(next, Module:GetInterruptRotationTrackerPosition())
        def.getPosition().x = 8
        assert.equals(8, ns.InterruptRotationTrackerAnchor.GetPosition().x)
        assert.is_nil(Module.db.interruptStatusHudPosition)

        ns.LayoutEditor.BeginScope("twin_fangs")
        assert.same(next, hud.position)
        ns.LayoutEditor.End()

        local reloaded = Loader.Load()
        reloaded.Modules.Start(ns.Database.Load({
            interruptRotationTrackerPosition = next,
        }))
        assert.same(next, reloaded.Modules.Get("TwinFangs"):GetInterruptRotationTrackerPosition())
        assert.same(next, reloaded.Modules.Get("CoiledAltar"):GetInterruptRotationTrackerPosition())
    end)

    it("does not treat interrupt-reminder enable as combat tracker activation", function()
        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        Module:SetInterruptReminderEnabled(true)
        binding.Update()
        assert.is_false(hud.shown)
        Module:SetSoakReminderEnabled(true)
        binding.Update()
        assert.is_false(hud.shown)
    end)

    it("paints the live assignment and reuses the frame as reports arrive", function()
        local Player = ns.Api.Player
        local chain = Module.db.interruptReminder.chain
        chain.front_left.players = {
            { name = "A-TestRealm" },
            { name = "B-TestRealm" },
            { name = Player.GetFullName() },
        }
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        ns.Api.Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Module:BeginInterruptStatusWindow()

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        assert.equals(hud, binding.Ensure())
        assert.is_true(hud.shown)
        assert.equals(L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, hud:GetState().label)
        assert.equals("cyan", hud:GetState().theme)
        assert.same({ 3 }, hud:GetState().myIndices)
        assert.equals(0, hud:GetState().completed)
        assert.equals(3, hud:GetState().total)
        assert.equals("A", hud:GetState().currentAssignee)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(hud, binding.Ensure())
        assert.equals(2, hud:GetState().completed)
        assert.equals(3, hud:GetState().total)
        assert.equals("Player", hud:GetState().currentAssignee)
        assert.equals(2, Module:GetInterruptCount())
    end)

    it("paints the live assignment in test mode without an encounter", function()
        local Player = ns.Api.Player
        local chain = Module.db.interruptReminder.chain
        chain.front_left.players = {
            { name = "A-TestRealm" },
            { name = Player.GetFullName() },
        }
        Module:SetInterruptReminderEnabled(true)
        ns.Api.Group.inRaid = true
        Module:SetInterruptStatusTestMode(true)

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        assert.is_true(hud.shown)
        assert.equals(L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, hud:GetState().label)
        assert.same({ 2 }, hud:GetState().myIndices)
        assert.equals(0, hud:GetState().completed)
        assert.equals(2, hud:GetState().total)
        assert.equals("A", hud:GetState().currentAssignee)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(1, hud:GetState().completed)
        assert.equals(2, hud:GetState().total)

        Module:SetInterruptStatusTestMode(false)
        assert.is_false(hud.shown)
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.is_false(hud.shown)
    end)

    it("shows the complete assigned range for consecutive interrupts", function()
        local Player = ns.Api.Player
        local name = Player.GetFullName()
        local chain = Module.db.interruptReminder.chain
        chain.front_left.players = {
            { name = "A-TestRealm" },
            { name = name },
            { name = name },
            { name = name },
        }
        Module:SetInterruptReminderEnabled(true)
        ns.Api.Group.inRaid = true
        Module:SetInterruptStatusTestMode(true)

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        assert.same({ 2, 3, 4 }, hud:GetState().myIndices)
        assert.equals(4, hud:GetState().total)
        Module:SetInterruptStatusTestMode(false)
    end)

    it("keeps Edit Mode preview from resetting an active encounter counter", function()
        local Player = ns.Api.Player
        Module.db.interruptReminder.chain.front_left.players = { { name = Player.GetFullName() } }
        Module:SetInterruptReminderEnabled(true)
        LoadPanel()
        ns.Api.Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Module:BeginInterruptStatusWindow()
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")

        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        def.onEditBegin()
        assert.same(PreviewState(), hud:GetState())
        assert.equals(1, Module:GetInterruptCount())
        assert.is_true(Module:IsInterruptStatusActive())

        def.onEditEnd()
        assert.equals(1, hud:GetState().completed)
        assert.equals(1, Module:GetInterruptCount())
        assert.is_true(hud.shown)
    end)

    it("paints a backup-only assignment at the saved point", function()
        local Player = ns.Api.Player
        local chain = Module.db.interruptReminder.chain
        chain.front_right.players = { { name = "A-TestRealm" }, { name = "B-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
        chain.front_right.channel = "say"
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        ns.Api.Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Module:BeginInterruptStatusWindow()

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        local backup = binding.EnsureBackup()
        assert.is_false(hud.shown)
        assert.is_true(backup.shown)
        assert.same(Module:GetInterruptRotationTrackerPosition(), backup.position)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP, backup:GetState().label)
        assert.equals(0, backup:GetState().completed)
        assert.equals(2, backup:GetState().total)
        assert.same({}, backup:GetState().myIndices)
        assert.equals("A", backup:GetState().currentAssignee)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(1, backup:GetState().completed)
        assert.equals("B", backup:GetState().currentAssignee)
        assert.equals(1, Module:GetBackupInterruptCount())
    end)

    it("stacks primary and backup HUDs and advances them independently", function()
        local Player = ns.Api.Player
        local chain = Module.db.interruptReminder.chain
        chain.front_left.players = { { name = Player.GetFullName() } }
        chain.front_right.players = { { name = "A-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
        chain.front_right.channel = "say"
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        ns.Api.Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Module:BeginInterruptStatusWindow()

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        local backup = binding.EnsureBackup()
        assert.is_true(hud.shown)
        assert.is_true(backup.shown)
        assert.equals(hud, backup.anchor[2])
        assert.equals("LEFT", backup.anchor[1])
        assert.equals("RIGHT", backup.anchor[3])
        assert.equals(ns.Assets.Spacing.SMALL, backup.anchor[4])
        assert.same({ 1 }, hud:GetState().myIndices)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP, backup:GetState().label)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(1, hud:GetState().completed)
        assert.equals(0, backup:GetState().completed)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(1, hud:GetState().completed)
        assert.same({ 1 }, backup:GetState().myIndices)
    end)

    it("paints backup progress in test mode from the backup zone channel", function()
        local Player = ns.Api.Player
        local chain = Module.db.interruptReminder.chain
        chain.front_right.players = { { name = "A-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
        chain.front_right.channel = "say"
        Module:SetInterruptReminderEnabled(true)
        ns.Api.Group.inRaid = true
        Module:SetInterruptStatusTestMode(true)

        local binding = InterruptRotationTracker()
        binding.Update()
        local backup = binding.EnsureBackup()
        assert.is_true(backup.shown)
        assert.equals(0, backup:GetState().completed)
        assert.equals(1, backup:GetState().total)
        assert.same({}, backup:GetState().myIndices)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(0, backup:GetState().completed)
        assert.same({ 1 }, backup:GetState().myIndices)
        assert.equals(1, backup:GetState().total)

        Module:SetInterruptStatusTestMode(false)
        assert.is_false(backup.shown)
    end)
end)

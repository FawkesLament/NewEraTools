local Loader = require("helpers.loader")

local STATUS_HUD_PATH = "ui/StatusHUD.lua"
local INTERRUPT_STATUS_HUD_PATH = "modules/venomous_abyss/twin_fangs/ui/InterruptStatusHUD.lua"
local PANEL_PATH = "modules/venomous_abyss/twin_fangs/ui/Panel.lua"

describe("TwinFangs InterruptStatusHUD", function()
    local ns, Module, L, originalCreateFrame
    local registered
    local scopes
    local editing

    local function FakeLabel()
        local label = { shown = true }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint() end
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
        }
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
            BeginScope = function(scopeId)
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
        assert(loadfile(STATUS_HUD_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(INTERRUPT_STATUS_HUD_PATH))(Loader.ADDON_NAME, namespace)
    end

    local function LoadPanel()
        ns.Callout = {
            LAYOUT_ID = "Callout:1",
            Ensure = function() end,
            SetScopePreview = function() end,
        }
        ns.ActionRow = { HEIGHT = 30 }
        ns.CollapsibleSection = {}
        ns.FeatureSection = {}
        ns.ColorSwatch = {}
        ns.Dropdown = {}
        ns.NumberStepper = {}
        ns.Slider = {}
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

    local function InterruptStatusHud()
        return ns.Modules.Internals("TwinFangs").InterruptStatusHudUI
    end

    local function PreviewState()
        return {
            title = L.TWIN_FANGS_INTERRUPT_STATUS_REGION_ROLE:format(
                L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT,
                L.TWIN_FANGS_INTERRUPT_STATUS_PRIMARY
            ),
            text = L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1),
            detail = L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(3),
            progress = 1,
            maxProgress = 5,
            severity = ns.StatusHUD.SEVERITY_NORMAL,
        }
    end

    local function PrimaryTitle(region)
        return L.TWIN_FANGS_INTERRUPT_STATUS_REGION_ROLE:format(region, L.TWIN_FANGS_INTERRUPT_STATUS_PRIMARY)
    end

    it("creates one instance, registers it, and stays hidden in normal play", function()
        local binding = InterruptStatusHud()
        binding.Update()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        assert.equals("TwinFangs:interrupt", binding.LAYOUT_ID)
        assert.is_false(def.global)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TITLE, def.label)
        assert.is_true(def.isEnabled())
        assert.is_false(hud.shown)
        assert.same(Module:GetInterruptStatusHudPosition(), hud.position)
    end)

    it("supplies the mock interrupt preview only while Twin Fangs Edit Mode is active", function()
        LoadPanel()
        local binding = InterruptStatusHud()
        local hud = binding.Ensure()
        Module:SetInterruptReminderEnabled(true)
        binding.Update()
        assert.is_false(hud.shown)

        ns.LayoutEditor.BeginScope("common")
        assert.is_false(hud.shown)
        assert.is_nil(editing[binding.LAYOUT_ID])

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

    it("registers the interrupt status HUD in the Twin Fangs scope", function()
        LoadPanel()
        local scope = scopes.twin_fangs
        local binding = InterruptStatusHud()
        assert.equals(L.TWIN_FANGS_LAYOUT_SCOPE, scope.label)
        assert.same({ ns.Callout.LAYOUT_ID, binding.LAYOUT_ID }, scope.elementIds)
        assert.equals("boolean", type(registered[binding.LAYOUT_ID].global))
        assert.is_false(registered[binding.LAYOUT_ID].global)
    end)

    it("repositions through the Twin Fangs layout element and keeps the saved point", function()
        LoadPanel()
        local binding = InterruptStatusHud()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        local next = { point = "BOTTOM", relativePoint = "BOTTOM", x = 8, y = 16 }
        def.setPosition(next)
        assert.same(next, Module:GetInterruptStatusHudPosition())
        def.getPosition().x = 8
        assert.equals(8, Module.db.interruptStatusHudPosition.x)

        ns.LayoutEditor.BeginScope("twin_fangs")
        assert.same(next, hud.position)
        ns.LayoutEditor.End()

        local reloaded = Loader.Load()
        reloaded.Modules.Start(ns.Database.Load({
            modules = {
                TwinFangs = { interruptStatusHudPosition = next },
            },
        }))
        assert.same(next, reloaded.Modules.Get("TwinFangs"):GetInterruptStatusHudPosition())
    end)

    it("does not treat interrupt-reminder enable as combat HUD activation", function()
        local binding = InterruptStatusHud()
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

        local binding = InterruptStatusHud()
        binding.Update()
        local hud = binding.Ensure()
        assert.equals(hud, binding.Ensure())
        assert.is_true(hud.shown)
        assert.equals(PrimaryTitle(L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT), hud:GetState().title)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1), hud:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(3), hud:GetState().detail)
        assert.equals(1, hud:GetState().progress)
        assert.equals(3, hud:GetState().maxProgress)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(hud, binding.Ensure())
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(3), hud:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(3), hud:GetState().detail)
        assert.equals(3, hud:GetState().progress)
        assert.equals(3, hud:GetState().maxProgress)
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

        local binding = InterruptStatusHud()
        binding.Update()
        local hud = binding.Ensure()
        assert.is_true(hud.shown)
        assert.equals(PrimaryTitle(L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT), hud:GetState().title)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1), hud:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(2), hud:GetState().detail)
        assert.equals(1, hud:GetState().progress)
        assert.equals(2, hud:GetState().maxProgress)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), hud:GetState().text)
        assert.equals(2, hud:GetState().progress)
        assert.equals(2, hud:GetState().maxProgress)

        Module:SetInterruptStatusTestMode(false)
        assert.is_false(hud.shown)
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.is_false(hud.shown)
    end)

    it("keeps Edit Mode preview from resetting an active encounter counter", function()
        local Player = ns.Api.Player
        Module.db.interruptReminder.chain.front_left.players = { { name = Player.GetFullName() } }
        Module:SetInterruptReminderEnabled(true)
        LoadPanel()
        ns.Api.Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Module:BeginInterruptStatusWindow()
        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")

        local binding = InterruptStatusHud()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        def.onEditBegin()
        assert.same(PreviewState(), hud:GetState())
        assert.equals(1, Module:GetInterruptCount())
        assert.is_true(Module:IsInterruptStatusActive())

        def.onEditEnd()
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), hud:GetState().text)
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

        local binding = InterruptStatusHud()
        binding.Update()
        local hud = binding.Ensure()
        local backup = binding.EnsureBackup()
        assert.is_false(hud.shown)
        assert.is_true(backup.shown)
        assert.same(Module:GetInterruptStatusHudPosition(), backup.position)
        assert.equals(L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT, backup:GetState().title)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1), backup:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP, backup:GetState().detail)
        assert.equals(1, backup:GetState().progress)
        assert.equals(2, backup:GetState().maxProgress)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), backup:GetState().text)
        assert.equals(2, backup:GetState().progress)
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

        local binding = InterruptStatusHud()
        binding.Update()
        local hud = binding.Ensure()
        local backup = binding.EnsureBackup()
        assert.is_true(hud.shown)
        assert.is_true(backup.shown)
        assert.equals(hud, backup.anchor[2])
        assert.equals("TOP", backup.anchor[1])
        assert.equals("BOTTOM", backup.anchor[3])
        assert.equals(-ns.Assets.Spacing.SMALL, backup.anchor[5])
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_TASK:format(1), hud:GetState().detail)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_BACKUP, backup:GetState().detail)

        ns.Api.GameEvents.Fire("CHAT_MSG_PARTY")
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), hud:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1), backup:GetState().text)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), hud:GetState().text)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), backup:GetState().text)
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

        local binding = InterruptStatusHud()
        binding.Update()
        local backup = binding.EnsureBackup()
        assert.is_true(backup.shown)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(1), backup:GetState().text)

        ns.Api.GameEvents.Fire("CHAT_MSG_SAY", L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
        assert.equals(L.TWIN_FANGS_INTERRUPT_STATUS_ROUND:format(2), backup:GetState().text)
        assert.equals(1, backup:GetState().progress)
        assert.equals(1, backup:GetState().maxProgress)

        Module:SetInterruptStatusTestMode(false)
        assert.is_false(backup.shown)
    end)
end)

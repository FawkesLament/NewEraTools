local Loader = require("helpers.loader")

local INTERRUPT_CHAIN_VIEW_PATH = "ui/InterruptChainView.lua"
local SHARED_INTERRUPT_CHAIN_HUD_PATH = "ui/InterruptChainHUD.lua"
local SHARED_INTERRUPT_ROTATION_TRACKER_PATH = "ui/InterruptRotationTracker.lua"
local INTERRUPT_ROTATION_TRACKER_PATH = "modules/venomous_abyss/coiled_altar/ui/InterruptRotationTracker.lua"
local PANEL_PATH = "modules/venomous_abyss/coiled_altar/CoiledAltarUI.lua"

describe("CoiledAltar InterruptRotationTracker", function()
    local ns, Module, L, originalCreateFrame
    local registered
    local scopes
    local editing

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
            function texture:SetAlpha() end
            function texture:SetTexCoord() end
            function texture:SetAllPoints() end
            function texture:SetGradient() end
            function texture:SetColorTexture() end
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
        assert(loadfile(INTERRUPT_CHAIN_VIEW_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(SHARED_INTERRUPT_CHAIN_HUD_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(SHARED_INTERRUPT_ROTATION_TRACKER_PATH))(Loader.ADDON_NAME, namespace)
        assert(loadfile(INTERRUPT_ROTATION_TRACKER_PATH))(Loader.ADDON_NAME, namespace)
        local module = namespace.Modules.Get("CoiledAltar")
        function module:OnInterruptStateChanged()
            namespace.Modules.Internals("CoiledAltar").InterruptRotationTrackerUI.Update()
        end
    end

    local function LoadPanel()
        ns.Callout = {
            LAYOUT_ID = "Callout:1",
            Ensure = function() end,
            SetScopePreview = function() end,
        }
        ns.FeatureSection = {}
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
        Module = ns.Modules.Get("CoiledAltar")
        L = ns.L
        AttachUi(ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function InterruptRotationTracker()
        return ns.Modules.Internals("CoiledAltar").InterruptRotationTrackerUI
    end

    local function PreviewState()
        return {
            total = 6,
            completed = 0,
            myIndices = { 3 },
            label = L.COILED_ALTAR_INTERRUPT_STATUS_TITLE,
        }
    end

    it("creates one instance, registers it as boss-scoped, and stays hidden in normal play", function()
        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        assert.equals("CoiledAltar:interrupt", binding.LAYOUT_ID)
        assert.is_false(def.global)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, def.label)
        assert.is_true(def.isEnabled())
        assert.is_false(hud.shown)
        assert.same(Module:GetInterruptRotationTrackerPosition(), hud.position)
    end)

    it("follows the interrupt checkbox", function()
        local binding = InterruptRotationTracker()
        binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        assert.is_true(def.isEnabled())
        Module:SetInterruptReminderEnabled(false)
        assert.is_false(def.isEnabled())
        Module:SetInterruptReminderEnabled(true)
        assert.is_true(def.isEnabled())
    end)

    it("supplies the mock interrupt preview only while Coiled Altar Edit Mode is active", function()
        LoadPanel()
        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        Module:SetInterruptReminderEnabled(true)
        binding.Update()
        assert.is_false(hud.shown)

        ns.LayoutEditor.BeginScope("common")
        assert.is_false(hud.shown)
        assert.is_nil(editing[binding.LAYOUT_ID])

        ns.LayoutEditor.BeginScope("coiled_altar")
        assert.is_true(hud.shown)
        assert.same(PreviewState(), hud:GetState())

        ns.LayoutEditor.End()
        assert.is_false(hud.shown)
        Module:SetInterruptReminderEnabled(false)
        binding.Update()
        assert.is_false(hud.shown)
    end)

    it("registers the interrupt rotation tracker in the Coiled Altar scope", function()
        LoadPanel()
        local scope = scopes.coiled_altar
        local binding = InterruptRotationTracker()
        assert.equals(L.COILED_ALTAR_LAYOUT_SCOPE, scope.label)
        assert.same({
            ns.Callout.LAYOUT_ID,
            binding.LAYOUT_ID,
        }, scope.elementIds)
        assert.is_false(registered[binding.LAYOUT_ID].global)
    end)

    it("paints the live assignment and advances the round when the tracked shadow is kicked", function()
        local Player = ns.Api.Player
        local Unit = ns.Api.Unit
        local RaidTarget = ns.Api.RaidTarget
        local Encounter = ns.Api.Encounter
        local Spell = ns.Api.Spell
        local Timer = ns.Api.Timer
        Module:AssignInterruptPlayer("MELEE", 3, Player.GetFullName())
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        RaidTarget.indices.boss3 = 1
        for i = 3, 5 do
            Unit.SetForTests("boss" .. i, { exists = i < 5 })
        end
        Encounter.FireEngageUnit()
        Timer.Advance(0)

        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        assert.is_true(hud.shown)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, hud:GetState().label)
        assert.same({ 3 }, hud:GetState().myIndices)
        assert.equals(0, hud:GetState().completed)
        assert.equals(6, hud:GetState().total)

        Spell.FireCastInterrupted("boss3", true, true)
        Timer.Advance(0)
        assert.equals(hud, binding.Ensure())
        assert.equals(1, hud:GetState().completed)
        assert.same({ 3 }, hud:GetState().myIndices)

        Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
        assert.is_false(hud.shown)
        Spell.FireCastInterrupted("boss3", true, true)
        Timer.Advance(0)
        assert.is_false(hud.shown)
        assert.equals(hud, binding.Ensure())
    end)

    it("stays pending until a marker resolves the assigned side", function()
        local Player = ns.Api.Player
        local Unit = ns.Api.Unit
        local Encounter = ns.Api.Encounter
        local Spell = ns.Api.Spell
        local Timer = ns.Api.Timer
        local RaidTarget = ns.Api.RaidTarget
        Module:AssignInterruptPlayer("MELEE", 1, Player.GetFullName())
        Module:AssignInterruptPlayer("MELEE", 3, Player.GetFullName())
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        for i = 3, 5 do
            Unit.SetForTests("boss" .. i, { exists = i < 5 })
        end
        Encounter.FireEngageUnit()
        Timer.Advance(0)

        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        assert.is_true(hud.shown)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, hud:GetState().label)
        assert.same({ 1, 3 }, hud:GetState().myIndices)
        assert.same({ 1, 3 }, Module:GetInterruptStatus().indices)
        assert.equals(0, hud:GetState().completed)

        Spell.FireCastInterrupted("boss3", true, true)
        Timer.Advance(0)
        assert.equals(hud, binding.Ensure())
        assert.equals(0, hud:GetState().completed)
        assert.same({ 1, 3 }, hud:GetState().myIndices)
        assert.equals(6, hud:GetState().total)

        RaidTarget.indices.boss3 = 1
        RaidTarget.FireChanged()
        assert.equals(hud, binding.Ensure())
        assert.equals(1, hud:GetState().completed)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, hud:GetState().label)
    end)

    it("shows a consecutive assignment range and stays hidden without a reminder", function()
        local Player = ns.Api.Player
        local Unit = ns.Api.Unit
        local RaidTarget = ns.Api.RaidTarget
        local Encounter = ns.Api.Encounter
        local Timer = ns.Api.Timer
        Module:AssignInterruptPlayer("RANGED", 2, Player.GetFullName())
        Module:AssignInterruptPlayer("RANGED", 3, Player.GetFullName())
        Module:SetInterruptReminderEnabled(false)
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        RaidTarget.indices.boss3 = 1
        for i = 3, 5 do
            Unit.SetForTests("boss" .. i, { exists = i < 5 })
        end
        Encounter.FireEngageUnit()
        Timer.Advance(0)

        local binding = InterruptRotationTracker()
        binding.Update()
        local hud = binding.Ensure()
        assert.is_false(hud.shown)

        Module:SetInterruptReminderEnabled(true)
        assert.is_true(hud.shown)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, hud:GetState().label)
        assert.same({ 2, 3 }, hud:GetState().myIndices)
        assert.equals(0, hud:GetState().completed)
        assert.equals(6, hud:GetState().total)
    end)

    it("lists every assigned interrupt when the slots are not consecutive", function()
        local Player = ns.Api.Player
        local Unit = ns.Api.Unit
        local RaidTarget = ns.Api.RaidTarget
        local Encounter = ns.Api.Encounter
        local Timer = ns.Api.Timer
        Module:AssignInterruptPlayer("RANGED", 1, Player.GetFullName())
        Module:AssignInterruptPlayer("RANGED", 3, Player.GetFullName())
        Module:AssignInterruptPlayer("RANGED", 5, Player.GetFullName())
        Module:SetInterruptReminderEnabled(true)
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        RaidTarget.indices.boss3 = 1
        for i = 3, 5 do
            Unit.SetForTests("boss" .. i, { exists = i < 5 })
        end
        Encounter.FireEngageUnit()
        Timer.Advance(0)

        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        assert.is_true(hud.shown)
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, hud:GetState().label)
        assert.same({ 1, 3, 5 }, hud:GetState().myIndices)
        assert.same({ 1, 3, 5 }, Module:GetInterruptStatus().indices)
        assert.equals(0, hud:GetState().completed)
        assert.equals(6, hud:GetState().total)
    end)

    it("repositions through the shared interrupt rotation tracker anchor", function()
        LoadPanel()
        local binding = InterruptRotationTracker()
        local hud = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        local next = { point = "BOTTOM", relativePoint = "BOTTOM", x = 8, y = 16 }
        def.setPosition(next)
        assert.same(next, Module:GetInterruptRotationTrackerPosition())
        assert.same(next, ns.Modules.Get("TwinFangs"):GetInterruptRotationTrackerPosition())
        assert.equals(8, ns.InterruptRotationTrackerAnchor.GetPosition().x)

        ns.LayoutEditor.BeginScope("coiled_altar")
        assert.same(next, hud.position)
        ns.LayoutEditor.End()
    end)
end)

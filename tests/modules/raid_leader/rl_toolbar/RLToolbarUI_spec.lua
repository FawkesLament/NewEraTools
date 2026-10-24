local Loader = require("helpers.loader")

local UI_PATH = "modules/raid_leader/rl_toolbar/RLToolbarUI.lua"

describe("RLToolbar UI", function()
    local ns, RLToolbar, Combat, Group, originalCreateFrame
    local window
    local buttons
    local registered
    local textures

    local function FakeTexture()
        local texture = { shown = false }
        function texture:SetSize() end
        function texture:SetPoint() end
        function texture:SetAllPoints() end
        function texture:SetTexture(path)
            self.path = path
        end
        function texture:SetTexCoord() end
        function texture:SetColorTexture() end
        function texture:SetVertexColor() end
        function texture:Show()
            self.shown = true
        end
        function texture:Hide()
            self.shown = false
        end
        textures[#textures + 1] = texture
        return texture
    end

    local function FakeLabel(text)
        local label = { text = text }
        function label:SetPoint() end
        function label:SetTextColor() end
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetWordWrap() end
        function label:SetText(value)
            self.text = value
        end
        return label
    end

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = false,
            enabled = true,
            alpha = 1,
            scripts = {},
            hooks = {},
            width = 0,
            height = 0,
        }
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:SetMovable() end
        function frame:EnableMouse() end
        function frame:RegisterForDrag() end
        function frame:ClearAllPoints() end
        function frame:SetPoint() end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetWidth(width)
            self.width = width
        end
        function frame:SetHeight(height)
            self.height = height
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
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        function frame:IsEnabled()
            return self.enabled ~= false
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:HookScript(name, handler)
            self.hooks[name] = handler
        end
        function frame:CreateTexture()
            return FakeTexture()
        end
        function frame:CreateFontString()
            return FakeLabel()
        end
        function frame:CreateLine()
            local line = FakeTexture()
            function line:SetThickness() end
            function line:SetSnapToPixelGrid() end
            function line:SetTexelSnappingBias() end
            function line:SetStartPoint() end
            function line:SetEndPoint() end
            return line
        end
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:SetShown(shown)
            self.shown = shown == true
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:Raise()
            self.raised = true
        end
        return frame
    end

    local function AttachUi()
        window = nil
        buttons = {}
        registered = nil
        textures = {}
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            ApplyBackdrop = function() end,
            AddHoverHighlight = function() end,
            AttachTooltip = function(frame, _, populate)
                frame.tooltip = populate
            end,
            CreateLabel = function(_, _, text)
                return FakeLabel(text)
            end,
            CreateFlatButton = function(parent, variant, onClick)
                local button = FakeFrame(parent)
                button.variant = variant
                button.onClick = onClick
                buttons[#buttons + 1] = button
                return button
            end,
        }
        ns.Layout = {
            Stack = function()
                return {
                    AddRow = function()
                        return FakeFrame()
                    end,
                    GetHeight = function()
                        return 36
                    end,
                }
            end,
            Row = function() end,
        }
        ns.FloatingWindow = {
            Create = function()
                window = FakeFrame()
                function window:SetWindowPosition() end
                function window:SetWindowScale() end
                function window:GetWindowPosition()
                    return ns.Modules.Get("RLToolbar"):GetPosition()
                end
                return window
            end,
        }
        ns.Slider = {
            Create = function()
                return FakeFrame()
            end,
        }
        ns.LayoutEditor = {
            Register = function(def)
                registered = def
            end,
        }
        ns.MainPanel = {
            RegisterSection = function() end,
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile(UI_PATH))(Loader.ADDON_NAME, ns)
        RLToolbar:OnEnable()
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        RLToolbar = ns.Modules.Get("RLToolbar")
        Combat = ns.Api.Combat
        Group = ns.Api.Group
        AttachUi()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("hides the optional 5s and 15s buttons", function()
        assert.is_true(buttons[2].shown)
        assert.is_true(buttons[4].shown)
        RLToolbar:SetCountdown5Shown(false)
        RLToolbar:SetCountdown15Shown(false)
        assert.is_false(buttons[2].shown)
        assert.is_true(buttons[1].shown)
        assert.is_true(buttons[3].shown)
        assert.is_false(buttons[4].shown)
        assert.is_true(buttons[5].shown)
    end)

    it("creates five action buttons and a layout element", function()
        assert.equals(5, #buttons)
        assert.equals("RLToolbar:1", registered.id)
        assert.is_true(registered.global)
        assert.equals(window, registered.frame)
        assert.is_false(registered.isEnabled())
        RLToolbar:SetEnabled(true)
        assert.is_true(registered.isEnabled())
    end)

    it("shows only when enabled, leading, and out of combat", function()
        assert.is_false(window.shown)
        RLToolbar:SetEnabled(true)
        assert.is_false(window.shown)
        Group.isRaidLeader = true
        Group.FireChanged()
        assert.is_true(window.shown)
        Combat.FireEnter()
        assert.is_false(window.shown)
        Combat.FireLeave()
        assert.is_true(window.shown)
        Group.isRaidLeader = false
        Group.FireChanged()
        assert.is_false(window.shown)
    end)

    it("previews in edit mode without leadership and restores afterward", function()
        RLToolbar:SetEnabled(true)
        assert.is_false(window.shown)
        registered.onEditBegin()
        assert.is_true(window.shown)
        registered.onEditEnd()
        assert.is_false(window.shown)

        Group.isRaidLeader = true
        Group.FireChanged()
        assert.is_true(window.shown)
        registered.onEditBegin()
        Combat.FireEnter()
        assert.is_false(window.shown)
        registered.onEditEnd()
        assert.is_false(window.shown)
    end)

    it("dispatches each button callback", function()
        local seen = {}
        function RLToolbar:OnAction(action)
            table.insert(seen, action)
        end
        RLToolbar:SetEnabled(true)
        Group.isRaidLeader = true
        for _, button in ipairs(buttons) do
            button.onClick()
        end
        assert.same(RLToolbar.ACTIONS, seen)
        assert.equals(1, Group.readyChecks)
        assert.same({ 5, 10, 15 }, Group.countdowns)
        assert.equals(1, Group.cancels)
    end)

    it("does not dispatch actions while editing", function()
        local seen = {}
        function RLToolbar:OnAction(action)
            table.insert(seen, action)
        end
        RLToolbar:SetEnabled(true)
        Group.isRaidLeader = true
        registered.onEditBegin()
        for _, button in ipairs(buttons) do
            button.onClick()
        end
        assert.same({}, seen)
        assert.equals(0, Group.readyChecks)
        registered.onEditEnd()
        buttons[1].onClick()
        assert.same({ "readyCheck" }, seen)
        assert.equals(1, Group.readyChecks)
    end)

    it("persists position through the layout element", function()
        local moved = { point = "BOTTOM", relativePoint = "BOTTOM", x = 8, y = 16 }
        registered.setPosition(moved)
        assert.same(moved, RLToolbar:GetPosition())
        assert.same(moved, registered.getPosition())
        assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 }, registered.getDefaultPosition())
    end)
end)

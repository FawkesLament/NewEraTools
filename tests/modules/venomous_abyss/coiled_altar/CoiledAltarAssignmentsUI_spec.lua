local Loader = require("helpers.loader")

local EDITOR_UI_PATH = "modules/venomous_abyss/coiled_altar/ui/Assignments.lua"

describe("CoiledAltar interrupt assignment editor", function()
    local ns, Module, Assignments, Editor, L, originalCreateFrame, labels, toggles, textButtons, host

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            enabled = true,
            alpha = 1,
            width = 400,
            height = 30,
            scripts = {},
            hooks = {},
            points = {},
            children = {},
        }
        function frame:SetFrameStrata() end
        function frame:SetFrameLevel() end
        function frame:GetFrameLevel()
            return 1
        end
        function frame:EnableMouse() end
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetPoint(point, ...)
            self.points[point] = { ... }
        end
        function frame:SetAllPoints(relative)
            local target = relative or self.parent
            self.points.ALL = { target }
            if target then
                self.width = target.width
                self.height = target.height
            end
        end
        function frame:GetSize()
            return self:GetWidth(), self:GetHeight()
        end
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
            return self.width or 0
        end
        function frame:GetHeight()
            return self.height or 0
        end
        function frame:Show()
            self.shown = true
            if self.scripts.OnShow then
                self.scripts.OnShow(self)
            end
            if self.hooks.OnShow then
                for _, handler in ipairs(self.hooks.OnShow) do
                    handler(self)
                end
            end
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:IsShown()
            return self.shown == true
        end
        function frame:SetShown(shown)
            self.shown = shown == true
        end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        function frame:Enable()
            self.enabled = true
        end
        function frame:Disable()
            self.enabled = false
        end
        function frame:SetParent(parentFrame)
            self.parent = parentFrame
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:HookScript(name, handler)
            self.hooks[name] = self.hooks[name] or {}
            self.hooks[name][#self.hooks[name] + 1] = handler
        end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetColorTexture() end
        function frame:SetAutoFocus() end
        function frame:SetMaxLetters() end
        function frame:SetJustifyH() end
        function frame:SetJustifyV() end
        function frame:SetWordWrap() end
        function frame:SetTextInsets() end
        function frame:SetFontObject() end
        function frame:SetNormalFontObject() end
        function frame:SetHighlightFontObject() end
        function frame:SetDisabledFontObject() end
        function frame:SetHitRectInsets() end
        function frame:ClearFocus() end
        function frame:HasFocus()
            return false
        end
        function frame:SetText(text)
            self.text = text
        end
        function frame:GetText()
            return self.text or ""
        end
        function frame:GetTextWidth()
            return 48
        end
        function frame:SetTextColor() end
        function frame:CreateTexture()
            local texture = FakeFrame(self)
            function texture:SetColorTexture() end
            return texture
        end
        function frame:CreateFontString()
            local label = FakeFrame(self)
            label.text = ""
            function label:SetText(text)
                self.text = text
            end
            function label:GetText()
                return self.text
            end
            function label:GetStringWidth()
                return #(self.text or "") * 6
            end
            function label:GetStringHeight()
                return 12
            end
            return label
        end
        function frame:Raise() end
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end
        ns = Loader.Load()
        ns.ADDON_NAME = ns.ADDON_NAME or Loader.ADDON_NAME
        L = ns.L
        labels = {}
        toggles = {}
        textButtons = {}
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            EnsureFonts = function() end,
            ApplyBackdrop = function() end,
            AddHoverHighlight = function() end,
            AttachTooltip = function() end,
            CreateSurface = function(parent)
                return FakeFrame(parent)
            end,
            LayoutSectionHeader = function(row, title)
                local label = row:CreateFontString()
                label:SetText(title)
                return label
            end,
            CreateLabel = function(parent, _, text)
                local label = parent:CreateFontString()
                if text then
                    label:SetText(text)
                end
                labels[#labels + 1] = label
                return label
            end,
            CreateTextButton = function(parent, text, onClick)
                local button = FakeFrame(parent)
                button.text = text
                button:SetScript("OnClick", onClick)
                textButtons[#textButtons + 1] = button
                return button
            end,
            CreateButton = function(parent, text, onClick)
                local button = FakeFrame(parent)
                button.text = text
                button:SetScript("OnClick", onClick)
                return button
            end,
            CreateSegmentedControl = function(parent, items, onSelect)
                local control = FakeFrame(parent)
                control.items = items
                control.onSelect = onSelect
                function control:SetSelected(value)
                    self.selected = value
                end
                toggles[#toggles + 1] = control
                return control
            end,
        }
        ns.WarningWindow = {
            Create = function()
                return FakeFrame()
            end,
        }
        ns.ActionFooter = {
            Create = function(parent, options)
                local footer = FakeFrame(parent)
                footer.button = ns.Widgets.CreateButton(footer, options.text, options.onClick)
                function footer:GetHeight()
                    return 30
                end
                function footer:SetMessage() end
                return footer
            end,
        }
        ns.InterruptChainView = {
            FormatSequence = function(first)
                return string.format("#%d", first)
            end,
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile(EDITOR_UI_PATH))(Loader.ADDON_NAME, ns)
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
        Editor = ns.Modules.Internals("CoiledAltar").InterruptAssignmentsUI
        host = FakeFrame()
        Editor.Mount(host, function() end)
        ns.Api.Timer.RunPending()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("renders a single interrupt rotation with no marked-chain toggle", function()
        -- Only the player/text mode segmented control exists.
        assert.equals(1, #toggles)
        assert.equals("player", toggles[1].selected)

        local titleCount = 0
        for _, label in ipairs(labels) do
            if label:GetText() == L.COILED_ALTAR_INTERRUPT_STATUS_TITLE then
                titleCount = titleCount + 1
            end
        end
        assert.equals(1, titleCount)
    end)

    it("clears slots on the active chain when clicking a slot clear button", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 1, "Player-TestRealm"))
        Editor.Refresh()
        -- Header "clear all" is created first; slot clear buttons follow.
        textButtons[2].scripts.OnClick()
        assert.equals(Assignments.TYPE_EMPTY, Module:GetInterruptSlot(Assignments.ACTIVE_CHAIN, 1).type)
    end)

    it("fills the host and recovers size after the host width is unresolved", function()
        local panel = host.children[1]
        assert.is_true(panel.points.TOPLEFT[1] == host)
        assert.is_true(panel.points.TOPRIGHT[1] == host)
        local width, height = panel:GetSize()
        assert.is_true(width > 0)
        assert.is_true(height > 1)

        host.width = 0
        host.height = 1
        panel.width = 0
        panel.height = 0
        for _, handler in ipairs(host.hooks.OnSizeChanged or {}) do
            handler(host, 0, 1)
        end
        assert.equals(0, panel:GetWidth())
        assert.is_true(panel:GetHeight() > 0)

        host.width = 462
        host.height = 410
        panel.width = 0
        for _, handler in ipairs(host.hooks.OnSizeChanged or {}) do
            handler(host, 462, 410)
        end
        width, height = panel:GetSize()
        assert.equals(462, width)
        assert.is_true(height > 1)
    end)
end)

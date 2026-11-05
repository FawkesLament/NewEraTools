local Loader = require("helpers.loader")

local EDITOR_UI_PATH = "modules/venomous_abyss/coiled_altar/ui/Assignments.lua"

describe("CoiledAltar interrupt assignment editor marked-chain row", function()
    local ns, Module, Editor, L, originalCreateFrame, markedToggle, markedLabel, labels, toggles, tooltips

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
        function frame:SetAllPoints() end
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
        tooltips = {}
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            EnsureFonts = function() end,
            ApplyBackdrop = function() end,
            AddHoverHighlight = function() end,
            AttachTooltip = function(frame, anchor, populate)
                tooltips[#tooltips + 1] = { frame = frame, anchor = anchor, populate = populate }
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
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile(EDITOR_UI_PATH))(Loader.ADDON_NAME, ns)
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Editor = ns.Modules.Internals("CoiledAltar").InterruptAssignmentsUI
        local host = FakeFrame()
        Editor.Mount(host, function() end)
        ns.Api.Timer.RunPending()
        markedToggle = toggles[1]
        markedLabel = nil
        for _, label in ipairs(labels) do
            if label:GetText() == L.COILED_ALTAR_MARKED_CORRESPONDS then
                markedLabel = label
                break
            end
        end
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("starts with the melee segment selected", function()
        assert.equals("MELEE", Module:GetMarkedChain())
        assert.equals("MELEE", markedToggle.selected)
        assert.equals(L.COILED_ALTAR_MARKED_CORRESPONDS, markedLabel:GetText())
        assert.equals(L.COILED_ALTAR_MARKED_SIDE_MELEE, markedToggle.items[1].text)
        assert.equals("MELEE", markedToggle.items[1].value)
        assert.equals(L.COILED_ALTAR_MARKED_SIDE_RANGED, markedToggle.items[2].text)
        assert.equals("RANGED", markedToggle.items[2].value)
        assert(markedLabel.points.LEFT[1] == markedToggle.parent)
        assert(markedToggle.points.RIGHT[1] == markedToggle.parent)
        assert.equals("RIGHT", markedToggle.points.RIGHT[2])
        local tooltip = { text = nil }
        function tooltip:SetText(text)
            self.text = text
        end
        tooltips[1].populate(tooltip)
        assert.equals("ANCHOR_TOP", tooltips[1].anchor)
        assert.equals(L.COILED_ALTAR_MARKED_CORRESPONDS_TOOLTIP, tooltip.text)
        assert(tooltips[1].frame.points.TOPLEFT[1] == markedLabel)
        assert(tooltips[1].frame.points.BOTTOMRIGHT[1] == markedLabel)
    end)

    it("writes the selected chain and keeps the toggle in sync", function()
        markedToggle.onSelect("RANGED")
        assert.equals("RANGED", Module:GetMarkedChain())
        assert.equals("RANGED", markedToggle.selected)

        markedToggle.onSelect("MELEE")
        assert.equals("MELEE", Module:GetMarkedChain())
        assert.equals("MELEE", markedToggle.selected)
    end)

    it("refreshes the toggle when markedChain is changed outside the editor", function()
        assert.is_true(Module:SetMarkedChain("RANGED"))
        Editor.Refresh()
        assert.equals("RANGED", markedToggle.selected)
        assert.equals(L.COILED_ALTAR_MARKED_CORRESPONDS, markedLabel:GetText())
    end)
end)

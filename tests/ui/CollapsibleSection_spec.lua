local Loader = require("helpers.loader")

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        points = {},
        children = {},
        shown = true,
        alpha = 1,
        height = 0,
        frameLevel = parent and ((parent.frameLevel or 0) + 1) or 1,
        scripts = {},
    }

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        if type(relativeTo) == "string" then
            relativePoint, x, y = relativeTo, relativePoint, x
            relativeTo = self.parent
        end
        self.points[point] = {
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetWidth(width)
        self.width = width
    end

    function frame:GetWidth()
        return self.width or 0
    end

    function frame:SetAlpha(alpha)
        self.alpha = alpha
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

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel
    end

    function frame:GetChildren()
        return unpack(self.children)
    end

    function frame:EnableMouse() end

    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end

    function frame:CreateTexture()
        local texture = FakeFrame(self)
        function texture:SetAllPoints() end
        function texture:SetColorTexture() end
        function texture:AddMaskTexture() end
        return texture
    end

    function frame:CreateMaskTexture()
        local mask = FakeFrame(self)
        function mask:SetAllPoints() end
        function mask:SetTexture() end
        return mask
    end

    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

local function FakeFontString(parent)
    local label = FakeFrame(parent)
    label.text = ""
    function label:SetText(text)
        self.text = text
    end
    function label:GetStringWidth()
        return #self.text * 6
    end
    function label:SetJustifyH() end
    return label
end

describe("CollapsibleSection", function()
    local CollapsibleSection, Layout, originalCreateFrame

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end

        local ns = {
            Assets = {
                Sizes = { CONTROL_ROW_HEIGHT = 32, CONTROL_HEIGHT = 24, EXPAND_ARROW = 10 },
                Spacing = { SMALL = 4, MEDIUM = 8 },
                Fonts = { BODY = "Body", TINY_MUTED = "TinyMuted" },
                Colors = {
                    SURFACE_RAISED = { r = 0.1, g = 0.1, b = 0.1, a = 1 },
                },
                Textures = { CIRCLE_MASK = "circle-mask" },
            },
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)

        local Widgets = {}
        ns.Widgets = Widgets
        function Widgets.UnpackColor(color)
            return color.r, color.g, color.b, color.a
        end
        function Widgets.CreateExpandButton(parent, onClick)
            local button = FakeFrame(parent)
            button.expanded = false
            button.label = ""
            button.onClick = onClick
            function button:SetExpanded(expanded)
                self.expanded = expanded == true
            end
            function button:SetLabel(text)
                self.label = text
                self:SetSize(#text * 6 + 20, 24)
            end
            function button:Click()
                if self.onClick then
                    self.onClick(self)
                end
            end
            return button
        end
        function Widgets.CreateLabel(parent, _, text)
            local label = FakeFontString(parent)
            if text then
                label:SetText(text)
            end
            return label
        end

        assert(loadfile("ui/CollapsibleSection.lua"))(Loader.ADDON_NAME, ns)
        CollapsibleSection = ns.CollapsibleSection
        Layout = ns.Layout
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    ---@return CollapsibleSection, LayoutStack, Frame
    local function CreateSection(overrides)
        local host = FakeFrame()
        local stack = Layout.Stack(host)
        local options = {
            title = "Tracking",
            expanded = true,
        }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        return CollapsibleSection.Create(stack, options), stack, host
    end

    it("starts with only the header height until content is measured", function()
        local section, stack = CreateSection()
        assert.equals(32, section:GetHeight())
        assert.equals(32, stack:GetHeight())
    end)

    it("parents to stack.container and keeps that entry in sync", function()
        local host = FakeFrame()
        local stack = Layout.Stack(host)
        local stackHeights = {}
        local section = CollapsibleSection.Create(stack, {
            title = "Tracking",
            onStackHeightChanged = function(height)
                table.insert(stackHeights, height)
            end,
        })

        assert.is_true(section.parent == host)
        assert.equals(32, stack:GetHeight())
        assert.equals(32, stackHeights[#stackHeights])

        section:SetContentHeight(100)
        assert.equals(132, section:GetHeight())
        assert.equals(132, stack:GetHeight())
        assert.equals(132, stackHeights[#stackHeights])
    end)

    it("hides content when collapsed without changing measured content height", function()
        local section, stack = CreateSection()
        section:SetContentHeight(100)
        assert.is_true(section:IsExpanded())
        assert.is_true(section.content.shown)
        assert.equals(132, stack:GetHeight())

        section:SetExpanded(false)
        assert.is_false(section:IsExpanded())
        assert.is_false(section.content.shown)
        assert.equals(32, section:GetHeight())
        assert.equals(32, stack:GetHeight())

        section:SetExpanded(true)
        assert.is_true(section.content.shown)
        assert.equals(132, section:GetHeight())
    end)

    it("defaults collapsed when expanded is false", function()
        local section = CreateSection({ expanded = false })
        section:SetContentHeight(80)
        assert.is_false(section:IsExpanded())
        assert.is_false(section.content.shown)
        assert.equals(32, section:GetHeight())
    end)

    it("toggles from the expand button click", function()
        local section = CreateSection()
        section:SetContentHeight(40)
        local header = section.children[1]
        local expandButton = header.children[1]
        expandButton:Click()
        assert.is_false(section:IsExpanded())
        expandButton:Click()
        assert.is_true(section:IsExpanded())
    end)

    it("notifies onExpandedChanged only when the state changes", function()
        local changes = {}
        local section = CreateSection({
            expanded = false,
            onExpandedChanged = function(expanded)
                table.insert(changes, expanded)
            end,
        })
        section:SetExpanded(false)
        assert.equals(0, #changes)
        section:SetExpanded(true)
        section:SetExpanded(true)
        section:SetExpanded(false)
        assert.same({ true, false }, changes)
    end)

    it("shows and hides a circular header badge", function()
        local section = CreateSection()
        local header = section.children[1]
        local badge = header.children[2]
        assert.is_false(badge.shown)
        section:SetBadge("3")
        assert.is_true(badge.shown)
        assert.equals(badge.width, badge.height)
        section:SetBadge(nil)
        assert.is_false(badge.shown)
        section:SetBadge("")
        assert.is_false(badge.shown)
    end)
end)

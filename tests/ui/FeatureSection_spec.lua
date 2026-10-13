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

    function frame:SetEnabled(enabled)
        self.enabled = enabled == true
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

describe("FeatureSection", function()
    local FeatureSection, Layout, originalCreateFrame

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end

        local ns = {
            L = { FEATURE_ON = "On", FEATURE_OFF = "Off" },
            Assets = {
                Sizes = { CONTROL_ROW_HEIGHT = 32, CONTROL_HEIGHT = 24, BORDER = 1 },
                Spacing = { SMALL = 4, MEDIUM = 8 },
                Fonts = { BODY = "Body" },
            },
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)

        local Widgets = {}
        ns.Widgets = Widgets
        function Widgets.CreateLabel(parent, _, text)
            local label = FakeFontString(parent)
            if text then
                label:SetText(text)
            end
            return label
        end
        function Widgets.CreateSegmentedControl(parent, items, onSelect)
            local control = FakeFrame(parent)
            control.items = items
            control.onSelect = onSelect
            function control:SetSelected(value)
                self.selected = value
            end
            function control:SetEnabled(enabled)
                self.enabled = enabled == true
            end
            control:SetSize(80, 24)
            return control
        end
        function Widgets.AttachTooltip() end

        assert(loadfile("ui/FeatureSection.lua"))(Loader.ADDON_NAME, ns)
        FeatureSection = ns.FeatureSection
        Layout = ns.Layout
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    ---@return FeatureSection, LayoutStack, Frame
    local function CreateSection(overrides)
        local host = FakeFrame()
        local stack = Layout.Stack(host)
        local options = {
            title = "Encounter Map",
            enabled = true,
        }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        return FeatureSection.Create(stack, options), stack, host
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
        local section = FeatureSection.Create(stack, {
            title = "Encounter Map",
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

    it("grows when content height is set", function()
        local section = CreateSection()
        section:SetContentHeight(100)
        assert.equals(132, section:GetHeight())
    end)

    it("dims and disables content when the feature is turned off", function()
        local section = CreateSection()
        local child = FakeFrame(section.content)
        function child:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        section:SetContentHeight(40)
        section:SetEnabled(false)
        assert.is_false(section:IsEnabled())
        assert.equals(0.4, section.content.alpha)
        assert.is_false(child.enabled)
        assert.equals(1, child.alpha)
    end)

    it("re-applies disabled fade for locked children when the feature turns back on", function()
        local section = CreateSection({ enabled = false })
        local locked = FakeFrame(section.content)
        local nested = FakeFrame(locked)
        -- Stays disabled while the feature is on (e.g. a feed-order slot waiting on an earlier one).
        function locked:SetEnabled()
            self.enabled = false
        end
        function locked:IsEnabled()
            return false
        end
        function nested:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        section:SetContentHeight(40)
        section:SetEnabled(false)
        assert.equals(1, locked.alpha)
        assert.equals(1, nested.alpha)

        section:SetEnabled(true)
        assert.is_false(locked.enabled)
        assert.equals(0.4, locked.alpha)
        -- Nested SetEnabled targets stay gated but opaque under the locked parent's fade.
        assert.is_false(nested.enabled)
        assert.equals(1, nested.alpha)
    end)

    it("keeps configuration callbacks for enable changes only", function()
        local enabledChanges = {}
        local section = CreateSection({
            enabled = false,
            onEnabledChanged = function(enabled)
                table.insert(enabledChanges, enabled)
            end,
        })
        section:SetEnabled(false)
        assert.equals(0, #enabledChanges)
        section:SetEnabled(true)
        assert.same({ true }, enabledChanges)
    end)

    it("accepts an optional title tooltip", function()
        local section = CreateSection({ tooltip = "Click the vents" })
        assert.equals(32, section:GetHeight())
    end)

    it("gates nested feature sections without overwriting their On/Off state", function()
        local nestedChanges = {}
        local parent = CreateSection()
        local nestedStack = Layout.Stack(parent.content)
        local nested = FeatureSection.Create(nestedStack, {
            title = "Show Remaining Time",
            enabled = false,
            onEnabledChanged = function(enabled)
                table.insert(nestedChanges, enabled)
            end,
        })
        local nestedChild = FakeFrame(nested.content)
        function nestedChild:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        nested:SetContentHeight(40)
        parent:SetContentHeight(nestedStack:GetHeight())

        parent:RefreshContentInteractive()
        assert.is_false(nested:IsEnabled())
        assert.equals(0, #nestedChanges)
        assert.is_false(nestedChild.enabled)

        nested:SetEnabled(true)
        assert.same({ true }, nestedChanges)
        assert.is_true(nestedChild.enabled)

        parent:SetEnabled(false)
        assert.is_true(nested:IsEnabled())
        assert.same({ true }, nestedChanges)
        assert.is_false(nestedChild.enabled)
    end)
end)

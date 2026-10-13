local Loader = require("helpers.loader")

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        points = {},
        children = {},
        shown = true,
        width = 0,
        height = 0,
        left = 100,
        top = 500,
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

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetWidth(width)
        self.width = width
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:GetWidth()
        return self.width
    end

    function frame:GetHeight()
        return self.height
    end

    function frame:GetLeft()
        return self.left
    end

    function frame:GetTop()
        return self.top
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

    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

describe("CollapsiblePanel", function()
    local CollapsiblePanel
    local UIParent

    before_each(function()
        UIParent = FakeFrame()
        _G.UIParent = UIParent

        local ns = {
            Assets = {
                Sizes = {
                    BORDER = 1,
                    HEADER_HEIGHT = 48,
                    COLLAPSED_PANEL_HEIGHT = 40,
                    COLLAPSED_PANEL_WIDTH = 300,
                },
            },
        }
        assert(loadfile("ui/CollapsiblePanel.lua"))(Loader.ADDON_NAME, ns)
        CollapsiblePanel = ns.CollapsiblePanel
    end)

    after_each(function()
        _G.UIParent = nil
    end)

    local function AttachFixture(overrides)
        local frame = FakeFrame(UIParent)
        frame:SetSize(700, 600)
        local body = FakeFrame(frame)
        local header = FakeFrame(frame)
        header:SetHeight(48)
        local welcome = FakeFrame(header)
        local scaleChrome = FakeFrame(header)

        local options = {
            frame = frame,
            body = body,
            header = header,
            expandedChrome = { welcome, scaleChrome },
            collapsedWidth = 300,
            collapsedHeight = 40,
        }
        if overrides then
            for key, value in pairs(overrides) do
                options[key] = value
            end
        end

        local controller = CollapsiblePanel.Attach(options)
        return {
            frame = frame,
            body = body,
            header = header,
            welcome = welcome,
            scaleChrome = scaleChrome,
            controller = controller,
        }
    end

    it("hides body and expanded chrome without changing cached size when collapsing", function()
        local changed
        local fixture = AttachFixture({
            onExpandedChanged = function(expanded)
                changed = expanded
            end,
        })

        fixture.controller:SetExpanded(false)

        assert.is_false(fixture.controller:IsExpanded())
        assert.is_false(fixture.body.shown)
        assert.is_false(fixture.welcome.shown)
        assert.is_false(fixture.scaleChrome.shown)
        assert.equals(300, fixture.frame.width)
        assert.equals(40, fixture.frame.height)
        assert.equals(38, fixture.header.height)
        assert.equals(false, changed)

        local width, height = fixture.controller:GetExpandedSize()
        assert.equals(700, width)
        assert.equals(600, height)
    end)

    it("restores expanded size and shows body on expand", function()
        local fixture = AttachFixture()
        fixture.controller:SetExpanded(false)
        fixture.frame.left = 120
        fixture.frame.top = 480
        fixture.controller:SetExpanded(true)

        assert.is_true(fixture.controller:IsExpanded())
        assert.is_true(fixture.body.shown)
        assert.is_true(fixture.welcome.shown)
        assert.equals(700, fixture.frame.width)
        assert.equals(600, fixture.frame.height)
        assert.equals(48, fixture.header.height)
    end)

    it("keeps the top-left anchor when collapsing", function()
        local fixture = AttachFixture()
        fixture.frame.left = 150
        fixture.frame.top = 420
        fixture.controller:SetExpanded(false)

        local point = fixture.frame.points.TOPLEFT
        assert.is_false(point == nil)
        -- Identity check: assert.equals formats tables and FakeFrame graphs are cyclic.
        assert(point.relativeTo == UIParent)
        assert.equals("BOTTOMLEFT", point.relativePoint)
        assert.equals(150, point.x)
        assert.equals(420, point.y)
    end)

    it("does not overwrite cached expanded size while already collapsed", function()
        local fixture = AttachFixture()
        fixture.controller:SetExpanded(false)
        fixture.frame:SetSize(999, 999)
        fixture.controller:SetExpanded(false)

        local width, height = fixture.controller:GetExpandedSize()
        assert.equals(700, width)
        assert.equals(600, height)
    end)

    it("toggles expanded state", function()
        local fixture = AttachFixture()
        fixture.controller:Toggle()
        assert.is_false(fixture.controller:IsExpanded())
        fixture.controller:Toggle()
        assert.is_true(fixture.controller:IsExpanded())
    end)
end)

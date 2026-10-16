local Loader = require("helpers.loader")

-- Records the anchors and height that Layout assigns.
local function FakeFrame()
    local frame = { points = {} }

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[point] = { relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    return frame
end

describe("Layout", function()
    local Layout, originalCreateFrame

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = FakeFrame
        local ns = {}
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)
        Layout = ns.Layout
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    describe("Stack", function()
        it("places entries below each other with padding and per-entry spacing", function()
            local container = FakeFrame()
            local stack = Layout.Stack(container, { paddingX = 4, paddingY = 8, spacing = 12 })
            local first = stack:AddRow(22)
            local second = stack:AddRow(22)
            local third = stack:AddRow(30, 4)

            assert.equals(8, stack:GetOffset(first))
            assert.equals(42, stack:GetOffset(second))
            assert.equals(68, stack:GetOffset(third))
            assert.equals(106, stack:GetHeight())
            assert.same({ relativeTo = container, relativePoint = "TOPLEFT", x = 4, y = -42 }, second.points.TOPLEFT)
            assert.same({ relativeTo = container, relativePoint = "TOPRIGHT", x = -4, y = -42 }, second.points.TOPRIGHT)
        end)

        it("moves later entries when an entry's height changes", function()
            local stack = Layout.Stack(FakeFrame(), { spacing = 10 })
            local first = stack:AddRow(20)
            local second = stack:AddRow(20)

            stack:SetEntryHeight(first, 50)

            assert.equals(60, stack:GetOffset(second))
            assert.equals(80, stack:GetHeight())
        end)

        it("inserts entries between existing ones", function()
            local stack = Layout.Stack(FakeFrame(), { spacing = 10 })
            local first = stack:AddRow(20)
            local last = stack:AddRow(20)
            local middle = stack:Insert(2, FakeFrame(), 30, 4)

            assert.equals(0, stack:GetOffset(first))
            assert.equals(24, stack:GetOffset(middle))
            assert.equals(64, stack:GetOffset(last))
            assert.equals(84, stack:GetHeight())
        end)

        it("keeps zero-height entries at least one pixel tall", function()
            local stack = Layout.Stack(FakeFrame())
            local row = stack:AddRow(0)
            assert.equals(1, row.height)
            assert.equals(0, stack:GetHeight())
        end)

        it("applies one relayout for a batched edit", function()
            local stack = Layout.Stack(FakeFrame(), { spacing = 10 })
            local first = FakeFrame()
            local second = FakeFrame()
            stack:BeginUpdate()
            stack:Add(first, 20)
            stack:Add(second, 20)
            assert.equals(0, stack:GetHeight())
            stack:EndUpdate()
            assert.equals(0, stack:GetOffset(first))
            assert.equals(30, stack:GetOffset(second))
            assert.equals(50, stack:GetHeight())
            assert.is_true(first.shown)

            stack:BeginUpdate()
            stack:Clear()
            assert.equals(50, stack:GetHeight())
            assert.is_true(first.shown)
            stack:EndUpdate()
            assert.equals(0, stack:GetHeight())
        end)

        it("rejects frames that are not in the stack", function()
            local stack = Layout.Stack(FakeFrame())
            assert.is_false(pcall(stack.GetOffset, stack, FakeFrame()))
        end)
    end)

    it("Row chains widgets left to right after the inset", function()
        local row = FakeFrame()
        local a, b = FakeFrame(), FakeFrame()
        Layout.Row(row, { a, b }, 12, 4)
        assert.same({ relativeTo = row, relativePoint = "LEFT", x = 4, y = 0 }, a.points.LEFT)
        assert.same({ relativeTo = a, relativePoint = "RIGHT", x = 12, y = 0 }, b.points.LEFT)
    end)

    it("SplitRow divides a row into equal cells with a gap", function()
        local row = FakeFrame()
        local left, right = Layout.SplitRow(row, 8)
        assert.same({ relativeTo = nil, relativePoint = nil, x = 0, y = 0 }, left.points.TOPLEFT)
        assert.same({ relativeTo = nil, relativePoint = nil, x = 0, y = 0 }, left.points.BOTTOMLEFT)
        assert.same({ relativeTo = row, relativePoint = "CENTER", x = -4, y = 0 }, left.points.RIGHT)
        assert.same({ relativeTo = nil, relativePoint = nil, x = 0, y = 0 }, right.points.TOPRIGHT)
        assert.same({ relativeTo = nil, relativePoint = nil, x = 0, y = 0 }, right.points.BOTTOMRIGHT)
        assert.same({ relativeTo = row, relativePoint = "CENTER", x = 4, y = 0 }, right.points.LEFT)
    end)

    it("GridCell and GridHeight fill rows left to right", function()
        assert.same({ 0, 0 }, { Layout.GridCell(1, 4, 120, 24) })
        assert.same({ 360, 0 }, { Layout.GridCell(4, 4, 120, 24) })
        assert.same({ 0, -24 }, { Layout.GridCell(5, 4, 120, 24) })
        assert.equals(24, Layout.GridHeight(0, 4, 24))
        assert.equals(48, Layout.GridHeight(5, 4, 24))
    end)
end)

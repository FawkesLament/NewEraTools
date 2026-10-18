describe("ActionRow", function()
    local ns, ActionRow, originalCreateFrame

    local function FakeRegion()
        local region = { points = {}, children = {} }
        function region:SetJustifyH() end
        function region:SetJustifyV() end
        function region:SetWordWrap() end
        function region:SetMaxLines() end
        function region:ClearAllPoints()
            self.points = {}
        end
        function region:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points[point] = { relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
        end
        function region:SetHeight(height)
            self.height = height
        end
        function region:GetStringHeight()
            return self.stringHeight
        end
        function region:GetHeight()
            return self.height
        end
        function region:HookScript(name, handler)
            self.hooks = self.hooks or {}
            self.hooks[name] = handler
        end
        return region
    end

    local function Track(parent, region)
        parent.children[#parent.children + 1] = region
        region.parent = parent
        return region
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = {
            Assets = {
                Fonts = { BODY = "Body", SMALL_MUTED = "SmallMuted" },
                FontStyles = { Body = { size = 12 }, SmallMuted = { size = 11 } },
                Sizes = { CONTROL_HEIGHT = 22 },
                Spacing = { TINY = 2, SMALL = 4, MEDIUM = 8, XLARGE = 16 },
            },
            Widgets = {},
        }
        CreateFrame = function(_, _, parent)
            return Track(parent, FakeRegion())
        end
        assert(loadfile("ui/Layout.lua"))("NewEraTools", ns)
        function ns.Widgets.CreateLabel(parent, font, text)
            local label = Track(parent, FakeRegion())
            label.font = font
            label.text = text
            return label
        end
        function ns.Widgets.CreateButton(parent, text, onClick, variant)
            local button = Track(parent, FakeRegion())
            button.text = text
            button.onClick = onClick
            button.variant = variant
            button.kind = "button"
            button.width = 72
            button.height = 22
            return button
        end
        function ns.Widgets.CreateLayoutEditButton(parent, text, onClick)
            local button = Track(parent, FakeRegion())
            button.text = text
            button.onClick = onClick
            button.kind = "layout"
            button.width = 96
            button.height = 22
            return button
        end
        assert(loadfile("ui/ActionRow.lua"))("NewEraTools", ns)
        ActionRow = ns.ActionRow
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function Apply(row, options)
        row.height = ActionRow.HEIGHT
        return ActionRow.Apply(row, options), row.children[1], row.children[2]
    end

    it("sizes the row for a title and two description lines", function()
        -- 12 + 2 + 11 * 2, plus a 4px inset on each side.
        assert.equals(44, ActionRow.HEIGHT)
    end)

    it("places a title and description on the left, centered against the buttons", function()
        local row = FakeRegion()
        local _, textCell = Apply(row, {
            title = "Preview and Layout",
            description = "Preview the map, or move it.",
            buttons = {
                { text = "Start Test", onClick = function() end },
            },
        })
        local title, description = textCell.children[1], textCell.children[2]
        title.stringHeight = 12
        description.stringHeight = 22
        row.hooks.OnSizeChanged()

        assert.equals("Body", title.font)
        assert.equals("Preview and Layout", title.text)
        assert.equals("SmallMuted", description.font)
        assert.equals("Preview the map, or move it.", description.text)
        -- (44 - (12 + 2 + 22)) / 2 = 4
        assert.is_true(title.points.TOPLEFT.relativeTo == textCell)
        assert.equals("TOPLEFT", title.points.TOPLEFT.relativePoint)
        assert.equals(0, title.points.TOPLEFT.x)
        assert.equals(-4, title.points.TOPLEFT.y)
        assert.is_true(description.points.TOPLEFT.relativeTo == title)
        assert.equals("BOTTOMLEFT", description.points.TOPLEFT.relativePoint)
        assert.equals(-2, description.points.TOPLEFT.y)
        assert.is_true(description.points.RIGHT.relativeTo == textCell)
    end)

    it("keeps buttons content-sized, equal height, and right-aligned in order", function()
        local startTest = function() end
        local editLayout = function() end
        local row = FakeRegion()
        local buttons, _, actionCell = Apply(row, {
            title = "Preview and Layout",
            description = "Preview the map, or move it.",
            buttons = {
                { text = "Start Test", onClick = startTest },
                { text = "Edit Layout", onClick = editLayout, layout = true },
            },
        })

        assert.is_true(buttons[1].onClick == startTest)
        assert.equals("button", buttons[1].kind)
        assert.is_nil(buttons[1].variant)
        assert.is_true(buttons[2].onClick == editLayout)
        assert.equals("layout", buttons[2].kind)
        assert.equals(22, buttons[1].height)
        assert.equals(22, buttons[2].height)
        assert.equals(72, buttons[1].width)
        assert.equals(96, buttons[2].width)
        assert.is_nil(buttons[1].points.LEFT)
        assert.is_nil(buttons[2].points.LEFT)
        assert.is_true(buttons[2].points.RIGHT.relativeTo == actionCell)
        assert.equals("RIGHT", buttons[2].points.RIGHT.relativePoint)
        assert.is_true(buttons[1].points.RIGHT.relativeTo == buttons[2])
        assert.equals("LEFT", buttons[1].points.RIGHT.relativePoint)
        assert.equals(-8, buttons[1].points.RIGHT.x)
    end)

    it("recenters the text when the description wraps to one line", function()
        local row = FakeRegion()
        local _, textCell = Apply(row, {
            title = "Reminder Layout",
            description = "Move the reminder.",
            buttons = {
                { text = "Edit Layout", onClick = function() end, layout = true },
            },
        })
        local title, description = textCell.children[1], textCell.children[2]
        title.stringHeight = 12
        description.stringHeight = 11
        row.hooks.OnSizeChanged()

        -- (44 - (12 + 2 + 11)) / 2 = 9.5
        assert.equals(-9.5, title.points.TOPLEFT.y)
    end)
end)

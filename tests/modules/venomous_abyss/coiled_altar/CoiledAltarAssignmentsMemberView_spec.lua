local Loader = require("helpers.loader")

local MEMBER_VIEW_PATH = "modules/venomous_abyss/coiled_altar/ui/MemberView.lua"

describe("CoiledAltar interrupt assignment member view", function()
    local ns, Module, Assignments, MemberView, L, Colors, originalCreateFrame, host

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            width = 400,
            height = 0,
            hooks = {},
            points = {},
            children = {},
            textures = {},
            fontStrings = {},
        }
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points[point] = { relativeTo, relativePoint, x, y }
        end
        function frame:SetAllPoints() end
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetWidth(width)
            self.width = width
        end
        function frame:SetHeight(height)
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
        function frame:SetParent(parentFrame)
            self.parent = parentFrame
        end
        function frame:HookScript(name, handler)
            self.hooks[name] = handler
        end
        function frame:EnableMouse() end
        function frame:CreateTexture()
            local texture = FakeFrame(self)
            function texture:SetColorTexture(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            self.textures[#self.textures + 1] = texture
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
            function label:SetJustifyH() end
            function label:SetWordWrap() end
            function label:SetTextColor(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        return frame
    end

    local function ColorEquals(actual, expected)
        return actual and actual.r == expected.r and actual.g == expected.g and actual.b == expected.b
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end
        ns = Loader.Load()
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            ApplyBackdrop = function() end,
            CreateSurface = function(parent)
                return FakeFrame(parent)
            end,
            CreateLabel = function(parent, _, text)
                local label = parent:CreateFontString()
                if text then
                    label:SetText(text)
                end
                return label
            end,
            AttachTooltip = function() end,
        }
        ns.InterruptChainView = {
            FormatSequence = function(first)
                return string.format("#%d", first)
            end,
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile(MEMBER_VIEW_PATH))(Loader.ADDON_NAME, ns)
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
        MemberView = ns.Modules.Internals("CoiledAltar").InterruptAssignmentsMemberView
        L = ns.L
        Colors = ns.Assets.Colors
        ns.Api.Group.inGroup = true
        ns.Api.Group.members = {
            {
                name = "Player",
                fullName = "Player-TestRealm",
                classFile = "DRUID",
            },
            {
                name = "Alice",
                fullName = "Alice-TestRealm",
                classFile = "MAGE",
            },
        }
        host = FakeFrame()
        MemberView.Mount(host, function() end)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function Panel()
        return host.children[1]
    end

    local function Title()
        return Panel().fontStrings[1]
    end

    local function Rows()
        local rows = {}
        for _, child in ipairs(Panel().children) do
            if child.height == ns.Assets.Sizes.CONTROL_ROW_HEIGHT then
                rows[#rows + 1] = child
            end
        end
        return rows
    end

    it("renders a single inset list with slot numbers, players, text, and empty slots", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 1, "Player-TestRealm"))
        assert.is_true(Module:AssignInterruptText(Assignments.ACTIVE_CHAIN, 2, "Kick first"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 3, "Alice-TestRealm"))

        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, Title().text)
        assert.equals(ns.Assets.Spacing.LARGE, Title().points.TOPLEFT[3])

        local rows = Rows()
        assert.equals(Assignments.SLOT_COUNT, #rows)
        assert.equals("#1", rows[1].fontStrings[1].text)
        assert.equals("Player", rows[1].fontStrings[3].text)
        assert.equals(L.COILED_ALTAR_INTERRUPT_YOU, rows[1].fontStrings[2].text)
        assert.is_true(rows[1].textures[1].shown)
        assert.is_true(rows[1].textures[2].shown)
        assert.equals("#2", rows[2].fontStrings[1].text)
        assert.equals("Kick first", rows[2].fontStrings[3].text)
        assert.is_true(ColorEquals(rows[2].fontStrings[3].color, Colors.TEXT_GOLD))
        assert.equals("#3", rows[3].fontStrings[1].text)
        assert.equals("Alice", rows[3].fontStrings[3].text)
        assert.equals("", rows[3].fontStrings[2].text)
        assert.is_false(rows[3].textures[1].shown)
        assert.is_false(rows[3].textures[2].shown)
        assert.equals(L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY, rows[4].fontStrings[3].text)
        assert.is_true(ColorEquals(rows[4].fontStrings[1].color, Colors.TEXT_MUTED))
        assert.is_true(ColorEquals(rows[4].fontStrings[3].color, Colors.TEXT_MUTED))
        assert.is_true(ColorEquals(rows[1].fontStrings[1].color, Colors.ACCENT))
        assert.equals(ns.Assets.Spacing.LARGE, rows[1].fontStrings[1].points.LEFT[3])
    end)

    it("uses a divider on every row except the last", function()
        local rows = Rows()
        for index = 1, Assignments.SLOT_COUNT - 1 do
            assert.equals(3, #rows[index].textures)
        end
        assert.equals(2, #rows[Assignments.SLOT_COUNT].textures)
    end)

    it("does not wrap the chain in a nested assignment card", function()
        local panel = Panel()
        assert.is_nil(panel.template)
        for _, child in ipairs(panel.children) do
            assert.is_nil(child.template)
        end
    end)

    it("keeps the same assignment table after a member-view refresh", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 4, "Alice"))
        local saved = Module:GetInterruptAssignments()
        MemberView.Refresh()
        assert(saved == Module:GetInterruptAssignments())
        assert.same(
            { type = Assignments.TYPE_PLAYER, value = "Alice-TestRealm" },
            Module:GetInterruptSlot(Assignments.ACTIVE_CHAIN, 4)
        )
    end)
end)

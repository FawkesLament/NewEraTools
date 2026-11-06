local Fs = require("helpers.fs")

describe("InterruptChainView", function()
    local ns, originalCreateFrame

    local function FakeLabel(parent)
        local label = {
            parent = parent,
            shown = true,
            text = "",
            points = {},
        }
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetWordWrap() end
        function label:SetHeight(height)
            self.height = height
        end
        function label:SetWidth(width)
            self.width = width
        end
        function label:ClearAllPoints()
            self.points = {}
        end
        function label:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points[point] = { relativeTo, relativePoint, x, y }
        end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        function label:IsShown()
            return self.shown
        end
        if parent and parent.children then
            parent.children[#parent.children + 1] = label
        end
        return label
    end

    local function FakeFrame(parent, template)
        local frame = {
            parent = parent,
            template = template,
            shown = true,
            children = {},
            textures = {},
            points = {},
            width = 400,
            height = 0,
            hooks = {},
        }
        function frame:SetAllPoints(relative)
            self.allPoints = relative or parent
        end
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points[point] = { relativeTo, relativePoint, x, y }
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
        function frame:SetParent(parentFrame)
            self.parent = parentFrame
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
        function frame:HookScript(name, handler)
            self.hooks[name] = handler
        end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:CreateTexture()
            local texture = FakeFrame(self)
            function texture:SetColorTexture(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function frame:CreateFontString()
            return FakeLabel(self)
        end
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        return frame
    end

    local function FindCards(root)
        local cards = {}
        local function Walk(node)
            if not node or not node.children then
                return
            end
            for _, child in ipairs(node.children) do
                if child.template == "BackdropTemplate" then
                    cards[#cards + 1] = child
                end
                Walk(child)
            end
        end
        Walk(root)
        return cards
    end

    local function VisibleCards(root)
        local visible = {}
        for _, card in ipairs(FindCards(root)) do
            if card.shown then
                visible[#visible + 1] = card
            end
        end
        return visible
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = {
            L = {
                INTERRUPT_SEQUENCE = "#%d",
                INTERRUPT_SEQUENCE_RANGE = "#%d–%d",
                INTERRUPT_SEQUENCE_JOIN = ", ",
            },
            Assets = {
                Templates = { BACKDROP = "BackdropTemplate" },
                Colors = {
                    SURFACE_RAISED = { r = 0.1, g = 0.1, b = 0.1 },
                    BORDER = { r = 0.2, g = 0.2, b = 0.2 },
                    ACCENT = { r = 0.31, g = 0.76, b = 0.71 },
                    TEXT = { r = 0.9, g = 0.9, b = 0.9 },
                    TEXT_MUTED = { r = 0.5, g = 0.5, b = 0.5 },
                },
                Fonts = {
                    BODY = "Body",
                    EMPHASIS = "Emphasis",
                    TINY_MUTED = "TinyMuted",
                    SMALL_MUTED = "SmallMuted",
                },
                Spacing = { TINY = 2, SMALL = 4, MEDIUM = 8 },
            },
            Widgets = {},
        }
        function ns.Widgets.UnpackColor(color)
            return color.r, color.g, color.b, color.a
        end
        function ns.Widgets.ApplyBackdrop() end
        function ns.Widgets.CreateLabel(parent, font, text)
            local label = FakeLabel(parent)
            label.font = font
            if text then
                label:SetText(text)
            end
            return label
        end
        CreateFrame = function(_, _, parent, template)
            return FakeFrame(parent, template)
        end
        assert(loadfile("ui/InterruptChainView.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local meleeAccent = { r = 0.31, g = 0.76, b = 0.71 }
    local rangedAccent = { r = 0.62, g = 0.50, b = 0.86 }

    local function SampleMelee()
        return {
            title = "Melee",
            accent = meleeAccent,
            emptyText = "No interrupt order yet.",
            entries = {
                { slot = "#1", text = "Alice", highlight = true, color = meleeAccent },
                { slot = "#2", text = "Bob", color = { r = 1, g = 0, b = 0 } },
            },
            footer = "Backup: Carol",
            footerHighlight = false,
        }
    end

    it("renders one chain full-width with slots, names, and local-player highlight", function()
        local host = FakeFrame()
        local view = ns.InterruptChainView.Create(host)
        view:SetData({
            youText = "You",
            chains = { SampleMelee() },
        })

        local cards = VisibleCards(view.frame)
        assert.equals(1, #cards)
        assert(view.frame.allPoints == host, "view fills the host")
        assert(cards[1].parent == view.frame, "single chain uses the full row")
        assert.equals("Melee", cards[1].title.text)
        assert.equals("#1", cards[1].playerRows[1].number.text)
        assert.equals("Alice", cards[1].playerRows[1].name.text)
        assert.equals("You", cards[1].playerRows[1].you.text)
        assert.is_true(cards[1].playerRows[1].highlight.shown)
        assert.equals("#2", cards[1].playerRows[2].number.text)
        assert.equals("Bob", cards[1].playerRows[2].name.text)
        assert.equals("", cards[1].playerRows[2].you.text)
        assert.is_false(cards[1].playerRows[2].highlight.shown)
        assert.equals("Backup: Carol", cards[1].backup.text)
        assert.is_false(cards[1].empty.shown)
        -- 8 + 18 + 2 + 32 + 2 + 16 + 4
        assert.equals(82, view:GetHeight())
    end)

    it("places two chains side by side and keeps a backup footer", function()
        local host = FakeFrame()
        local view = ns.InterruptChainView.Create(host)
        view:SetData({
            youText = "You",
            chains = {
                SampleMelee(),
                {
                    title = "Ranged",
                    accent = rangedAccent,
                    entries = {
                        { slot = "#1", text = "Dana" },
                    },
                    footer = "Backup: Unassigned",
                    footerHighlight = true,
                },
            },
        })

        local cards = VisibleCards(view.frame)
        assert.equals(2, #cards)
        assert.equals("Melee", cards[1].title.text)
        assert.equals("Ranged", cards[2].title.text)
        assert(cards[1].parent ~= view.frame, "first chain sits in a column")
        assert(cards[2].parent ~= view.frame, "second chain sits in a column")
        assert(cards[1].parent ~= cards[2].parent, "chains use separate columns")
        assert.equals("CENTER", cards[1].parent.points.RIGHT[2])
        assert.equals("CENTER", cards[2].parent.points.LEFT[2])
        assert.equals("You", cards[2].backupRow.you.text)
        assert.is_true(cards[2].backupRow.highlight.shown)
        assert.equals(82, view:GetHeight())
    end)

    it("shows unassigned and custom text entries, and hides unused rows on update", function()
        local host = FakeFrame()
        local view = ns.InterruptChainView.Create(host)
        view:SetData({
            youText = "You",
            chains = {
                {
                    title = "Melee",
                    accent = meleeAccent,
                    entries = {
                        { slot = "#1", text = "Unassigned", color = ns.Assets.Colors.TEXT_MUTED },
                        { slot = "#2", text = "Kick first", color = ns.Assets.Colors.TEXT },
                    },
                },
            },
        })

        local cards = VisibleCards(view.frame)
        assert.equals("Unassigned", cards[1].playerRows[1].name.text)
        assert.equals("Kick first", cards[1].playerRows[2].name.text)
        assert.is_false(cards[1].backupRow.shown)
        -- 8 + 18 + 2 + 32 + 4
        assert.equals(64, view:GetHeight())

        view:SetData({
            youText = "You",
            chains = {
                {
                    title = "Melee",
                    accent = meleeAccent,
                    emptyText = "No interrupt order yet.",
                    entries = {},
                    footer = "Backup: Unassigned",
                },
            },
        })
        cards = VisibleCards(view.frame)
        assert.equals(1, #cards)
        assert.is_true(cards[1].empty.shown)
        assert.equals("No interrupt order yet.", cards[1].empty.text)
        assert.is_false(cards[1].playerRows[1].shown)
        assert.is_false(cards[1].playerRows[2].shown)
        assert.is_true(cards[1].backupRow.shown)
    end)

    it("collapses to a one-pixel row when there are no chains", function()
        local host = FakeFrame()
        local view = ns.InterruptChainView.Create(host)
        view:SetData({
            youText = "You",
            chains = { SampleMelee() },
        })
        view:SetData({ youText = "You", chains = {} })
        local cards = VisibleCards(view.frame)
        assert.equals(0, #cards)
        assert.equals(1, view:GetHeight())
    end)

    it("collapses consecutive interrupt indices into compact sequences", function()
        local FormatSequence = ns.InterruptChainView.FormatSequence
        local FormatIndices = ns.InterruptChainView.FormatIndices
        assert.equals("#3", FormatSequence(3))
        assert.equals("#3", FormatSequence(3, 3))
        assert.equals("#2–4", FormatSequence(2, 4))
        assert.equals("#1", FormatIndices({ 1 }))
        assert.equals("#2–3", FormatIndices({ 2, 3 }))
        assert.equals("#1, #3, #5", FormatIndices({ 1, 3, 5 }))
        assert.equals("#1–2, #4–6", FormatIndices({ 1, 2, 4, 5, 6 }))
        assert.equals("", FormatIndices(nil))
        assert.equals("", FormatIndices({}))
    end)

    it("does not depend on Twin Fangs or Coiled Altar", function()
        local source = Fs.ReadFile("ui/InterruptChainView.lua")
        assert.is_nil(source:find("TwinFangs"))
        assert.is_nil(source:find("CoiledAltar"))
        assert.is_nil(source:find("Modules"))
        assert.is_nil(source:find("ns%.Api"))
    end)
end)

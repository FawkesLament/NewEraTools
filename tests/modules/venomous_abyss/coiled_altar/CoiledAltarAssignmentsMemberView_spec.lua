local Loader = require("helpers.loader")

local MEMBER_VIEW_PATH = "modules/venomous_abyss/coiled_altar/ui/MemberView.lua"

describe("CoiledAltar interrupt assignment member view", function()
    local ns, Module, Assignments, MemberView, L, originalCreateFrame, lastData, labels

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            width = 400,
            height = 0,
            hooks = {},
            points = {},
            children = {},
        }
        function frame:SetPoint() end
        function frame:SetAllPoints() end
        function frame:ClearAllPoints() end
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
            return label
        end
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
        lastData = nil
        labels = {}
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
                labels[#labels + 1] = label
                return label
            end,
            AttachTooltip = function() end,
        }
        ns.InterruptChainView = {
            FormatSequence = function(first)
                return string.format("#%d", first)
            end,
            Create = function()
                return {
                    SetData = function(_, data)
                        lastData = data
                    end,
                    GetHeight = function()
                        return 80
                    end,
                }
            end,
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile(MEMBER_VIEW_PATH))(Loader.ADDON_NAME, ns)
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
        MemberView = ns.Modules.Internals("CoiledAltar").InterruptAssignmentsMemberView
        L = ns.L
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
        MemberView.Mount(FakeFrame(), function() end)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("shows a single chain with slot numbers, players, text, and empty slots", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 1, "Player-TestRealm"))
        assert.is_true(Module:AssignInterruptText(Assignments.ACTIVE_CHAIN, 2, "Kick first"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.ACTIVE_CHAIN, 3, "Alice-TestRealm"))

        assert.equals(1, #lastData.chains)
        local chain = lastData.chains[1]
        assert.equals(L.COILED_ALTAR_INTERRUPT_STATUS_TITLE, chain.title)
        assert.equals(Assignments.SLOT_COUNT, #chain.entries)
        assert.equals("#1", chain.entries[1].slot)
        assert.equals("Player", chain.entries[1].text)
        assert.is_true(chain.entries[1].highlight)
        assert.equals(L.COILED_ALTAR_INTERRUPT_YOU, lastData.youText)
        assert.equals("#2", chain.entries[2].slot)
        assert.equals("Kick first", chain.entries[2].text)
        assert.equals(ns.Assets.Colors.TEXT_GOLD, chain.entries[2].color)
        assert.is_nil(chain.entries[2].highlight)
        assert.equals("#3", chain.entries[3].slot)
        assert.equals("Alice", chain.entries[3].text)
        assert.is_nil(chain.entries[3].highlight)
        assert.equals(L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY, chain.entries[4].text)
        assert.equals(ns.Assets.Colors.TEXT_MUTED, chain.entries[4].color)
    end)

    it("does not render a marked-chain row", function()
        assert.equals(0, #labels)
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

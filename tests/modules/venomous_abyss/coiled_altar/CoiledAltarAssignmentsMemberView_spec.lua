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

    it("shows melee and ranged chains with slot numbers, players, text, and empty slots", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 1, "Player-TestRealm"))
        assert.is_true(Module:AssignInterruptText(Assignments.MELEE, 2, "Kick first"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.RANGED, 3, "Alice-TestRealm"))

        local melee = lastData.chains[1]
        local ranged = lastData.chains[2]
        assert.equals(L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE, melee.title)
        assert.equals(L.COILED_ALTAR_INTERRUPT_CHAIN_RANGED, ranged.title)
        assert.equals(Assignments.SLOT_COUNT, #melee.entries)
        assert.equals(Assignments.SLOT_COUNT, #ranged.entries)
        assert.equals("#1", melee.entries[1].slot)
        assert.equals("Player", melee.entries[1].text)
        assert.is_true(melee.entries[1].highlight)
        assert.equals(L.COILED_ALTAR_INTERRUPT_YOU, lastData.youText)
        assert.equals("#2", melee.entries[2].slot)
        assert.equals("Kick first", melee.entries[2].text)
        assert.equals(ns.Assets.Colors.TEXT_GOLD, melee.entries[2].color)
        assert.is_nil(melee.entries[2].highlight)
        assert.equals(L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY, melee.entries[3].text)
        assert.equals(ns.Assets.Colors.TEXT_MUTED, melee.entries[3].color)
        assert.equals("#3", ranged.entries[3].slot)
        assert.equals("Alice", ranged.entries[3].text)
        assert.is_nil(ranged.entries[3].highlight)
    end)

    it("shows the current marked-chain setting as read-only text", function()
        local markedLabel
        local markedValue
        for _, label in ipairs(labels) do
            if label:GetText() == L.COILED_ALTAR_MARKED_CORRESPONDS then
                markedLabel = label
            elseif label:GetText() == L.COILED_ALTAR_MARKED_SIDE_MELEE then
                markedValue = label
            end
        end
        assert.equals(L.COILED_ALTAR_MARKED_CORRESPONDS, markedLabel:GetText())
        assert.equals("MELEE", Module:GetMarkedChain())
        assert.equals(L.COILED_ALTAR_MARKED_SIDE_MELEE, markedValue:GetText())

        assert.is_true(Module:SetMarkedChain("RANGED"))
        MemberView.Refresh()
        assert.equals("RANGED", Module:GetMarkedChain())
        assert.equals(L.COILED_ALTAR_MARKED_SIDE_RANGED, markedValue:GetText())
        assert.equals(L.COILED_ALTAR_MARKED_CORRESPONDS, markedLabel:GetText())
    end)

    it("keeps the same assignment table after a member-view refresh", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 4, "Alice"))
        local saved = Module:GetInterruptAssignments()
        MemberView.Refresh()
        assert(saved == Module:GetInterruptAssignments())
        assert.same({ type = Assignments.TYPE_PLAYER, value = "Alice-TestRealm" }, Module:GetInterruptSlot("MELEE", 4))
    end)
end)

local Loader = require("helpers.loader")
local InterruptChainHelper = require("helpers.interrupt_chain")

local EDITOR_UI_PATH = "modules/venomous_abyss/twin_fangs/ui/interrupt_chain/Editor.lua"

describe("TwinFangs interrupt chain consecutive assignments", function()
    local ns, Chain, Preview, state

    local function Guid(name)
        return "Player-MOCK-" .. name
    end

    local function Name(name)
        return { name = name .. "-" .. InterruptChainHelper.REALM }
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Preview = InterruptChainHelper.LoadPreview(ns)
        state = Chain.NewState()
        Chain.SetRoster(state, InterruptChainHelper.MockRoster())
        Chain.SetGroup(state, Chain.FRONT_LEFT, 1)
        Chain.SetGroup(state, Chain.FRONT_RIGHT, 2)
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("清风")))
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("夜雨")))
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("石川")))
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_RIGHT, Guid("流火")))
    end)

    it("defaults every assigned player to ×1", function()
        local entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals(3, #entries)
        assert.equals(1, entries[1].count)
        assert.equals("#1", entries[1].sequence)
        assert.equals("#2", entries[2].sequence)
        assert.equals("#3", entries[3].sequence)
        assert.equals(3, #Chain.GetRegion(state, Chain.FRONT_LEFT).players)
    end)

    it("expands consecutive GUID repeats for ×1, ×2, and ×3", function()
        assert.is_true(Chain.SetRepeatCount(state, Chain.FRONT_LEFT, 2, 3))
        local stored = Chain.GetRegion(state, Chain.FRONT_LEFT).players
        assert.same({ Name("清风"), Name("夜雨"), Name("夜雨"), Name("夜雨"), Name("石川") }, stored)
        local entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals("#1", entries[1].sequence)
        assert.equals("#2–4", entries[2].sequence)
        assert.equals("#5", entries[3].sequence)
        assert.equals(3, entries[2].count)
        assert.equals(5, Preview.TotalTurns(entries))
        assert.is_true(state.dirty)

        assert.is_true(Chain.SetRepeatCount(state, Chain.FRONT_LEFT, 2, 2))
        entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals("#2–3", entries[2].sequence)
        assert.equals("#4", entries[3].sequence)
        assert.equals(4, #Chain.GetRegion(state, Chain.FRONT_LEFT).players)
    end)

    it("reorders and removes whole consecutive blocks", function()
        Chain.SetRepeatCount(state, Chain.FRONT_LEFT, 2, 3)
        assert.is_true(Chain.MovePlayer(state, Chain.FRONT_LEFT, 2, -1))
        local entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals(Guid("夜雨"), entries[1].guid)
        assert.equals("#1–3", entries[1].sequence)
        assert.equals(Guid("清风"), entries[2].guid)
        assert.equals("#4", entries[2].sequence)
        assert.same({
            Name("夜雨"),
            Name("夜雨"),
            Name("夜雨"),
            Name("清风"),
            Name("石川"),
        }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)

        assert.is_true(Chain.RemovePlayer(state, Chain.FRONT_LEFT, 1))
        entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals(2, #entries)
        assert.equals("#1", entries[1].sequence)
        assert.equals("#2", entries[2].sequence)
        assert.same({ Name("清风"), Name("石川") }, Chain.GetRegion(state, Chain.FRONT_LEFT).players)
        assert.is_true(Chain.AddPlayer(state, Chain.FRONT_LEFT, Guid("夜雨")))
        entries = Preview.RegionEntries(state, Chain.FRONT_LEFT)
        assert.equals(1, entries[3].count)
    end)

    it("rejects nonconsecutive duplicates, over-repeats, and cross-region primaries", function()
        state.regions[Chain.FRONT_LEFT].players = { Name("清风"), Name("夜雨"), Name("清风") }
        local codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            if issue.severity == "error" then
                codes[issue.code] = true
            end
        end
        assert.is_true(codes.nonconsecutive_primary)

        state.regions[Chain.FRONT_LEFT].players = { Name("清风"), Name("清风"), Name("清风"), Name("清风") }
        codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            if issue.code == "repeat_limit" then
                codes.repeat_limit = true
            end
        end
        assert.is_true(codes.repeat_limit)

        Chain.SetRepeatCount(state, Chain.FRONT_LEFT, 1, 1)
        state.regions[Chain.FRONT_LEFT].players = { Name("流火") }
        codes = {}
        for _, issue in ipairs(Chain.Validate(state)) do
            if issue.severity == "error" then
                codes[issue.code] = true
            end
        end
        assert.is_true(codes.duplicate_primary)
    end)

    it("persists expanded repeats across a simulated reload", function()
        Chain.SetRepeatCount(state, Chain.FRONT_LEFT, 2, 3)
        ns.Modules.Start(ns.Database.Load(nil))
        local module = ns.Modules.Get("TwinFangs")
        Chain.ReplaceChain(module.db.interruptReminder.chain, state.regions)
        local saved = ns.Util.DeepCopy(module.db)

        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Preview = InterruptChainHelper.LoadPreview(ns)
        ns.Modules.Start(ns.Database.Load({ modules = { TwinFangs = saved } }))
        local restored = ns.Modules.Get("TwinFangs").db.interruptReminder.chain
        ns.Api.Group.members = InterruptChainHelper.MockRoster()
        local reloaded = Chain.NewState(restored)
        Chain.SetRoster(reloaded, InterruptChainHelper.MockRoster())
        local entries = Preview.RegionEntries(reloaded, Chain.FRONT_LEFT)
        assert.equals(3, #entries)
        assert.equals(3, entries[2].count)
        assert.equals("#2–4", entries[2].sequence)
        assert.equals(5, #restored.front_left.players)
        assert.equals("夜雨-" .. InterruptChainHelper.REALM, restored.front_left.players[2].name)
        assert.equals("夜雨-" .. InterruptChainHelper.REALM, restored.front_left.players[4].name)
    end)
end)

describe("TwinFangs interrupt chain editor UI", function()
    local ns, Chain, Preview, Editor, originalCreateFrame

    local function Guid(name)
        return "Player-MOCK-" .. name
    end

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            enabled = true,
            alpha = 1,
            width = 400,
            height = 0,
            scripts = {},
            hooks = {},
            points = {},
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
        function frame:CreateTexture()
            local texture = FakeFrame(self)
            function texture:SetColorTexture() end
            return texture
        end
        function frame:CreateFontString()
            return FakeLabel(self)
        end
        function frame:SetText(text)
            self.text = text
        end
        function frame:GetText()
            return self.text
        end
        function frame:GetTextWidth()
            return 48
        end
        function frame:SetNormalFontObject() end
        function frame:SetHighlightFontObject() end
        function frame:SetDisabledFontObject() end
        function frame:Raise() end
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        return frame
    end

    function FakeLabel(parent)
        local label = FakeFrame(parent)
        label.text = ""
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:SetTextColor(r, g, b)
            self.color = { r = r, g = g, b = b }
        end
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetWordWrap() end
        function label:GetStringWidth()
            return #(self.text or "") * 6
        end
        function label:GetStringHeight()
            return 12
        end
        return label
    end

    local function VisibleRows(ui)
        local visible = 0
        for _, row in ipairs(ui.editor.playerRows) do
            if row.shown then
                visible = visible + 1
            end
        end
        return visible
    end

    local function StubUi(namespace)
        namespace.Widgets = {}
        function namespace.Widgets.UnpackColor(color)
            return color.r, color.g, color.b, color.a
        end
        function namespace.Widgets.ApplyBackdrop() end
        function namespace.Widgets.AddHoverHighlight() end
        function namespace.Widgets.AttachTooltip() end
        function namespace.Widgets.LayoutSectionHeader(row, title)
            local label = FakeLabel(row)
            label:SetText(title)
            return label
        end
        function namespace.Widgets.CreateSurface(parent)
            return FakeFrame(parent)
        end
        function namespace.Widgets.CreateLabel(parent, _, text)
            local label = FakeLabel(parent)
            if text then
                label:SetText(text)
            end
            return label
        end
        function namespace.Widgets.CreateTextButton(parent, text, onClick)
            local button = FakeFrame(parent)
            button.text = text
            button.onClick = onClick
            button:SetScript("OnClick", onClick)
            return button
        end
        function namespace.Widgets.CreateButton(parent, text, onClick)
            local button = FakeFrame(parent)
            button.text = text
            button.onClick = onClick
            button:SetScript("OnClick", onClick)
            local raw = button.SetEnabled
            function button:SetEnabled(enabled)
                raw(self, enabled)
            end
            return button
        end
        function namespace.Widgets.CreateSegmentedControl(parent, items, onSelect)
            local control = FakeFrame(parent)
            control.items = items
            control.onSelect = onSelect
            function control:SetSelected(value)
                self.selected = value
            end
            return control
        end
        namespace.Dropdown = {
            Create = function(parent, items, onSelect)
                local dropdown = FakeFrame(parent)
                dropdown.items = items
                dropdown.onSelect = onSelect
                dropdown.selected = nil
                function dropdown:SetItems(nextItems)
                    self.items = nextItems
                end
                function dropdown:SetSelected(value)
                    self.selected = value
                end
                function dropdown:SetAutoWidth() end
                function dropdown:SetEnabled() end
                return dropdown
            end,
        }
        namespace.ActionFooter = {
            Create = function(parent)
                local footer = FakeFrame(parent)
                footer.button = FakeFrame(footer)
                function footer:SetMessage(message)
                    self.message = message
                end
                function footer:GetHeight()
                    return 40
                end
                return footer
            end,
        }
        namespace.WarningWindow = {
            Create = function()
                return FakeFrame()
            end,
        }
        assert(loadfile("ui/Layout.lua"))(Loader.ADDON_NAME, namespace)
    end

    local function AssignFrontLeft(chain)
        chain.front_left.group = 1
        chain.front_left.players = {
            { name = "清风-" .. InterruptChainHelper.REALM },
            { name = "夜雨-" .. InterruptChainHelper.REALM },
            { name = "石川-" .. InterruptChainHelper.REALM },
        }
        chain.front_left.backup = { name = "流火-" .. InterruptChainHelper.REALM }
        chain.front_right.group = 2
        chain.front_right.players = {
            { name = "霜华-" .. InterruptChainHelper.REALM },
        }
    end

    local function MountEditor()
        ns.Api.Group.isRaidLeader = true
        ns.Api.Group.inRaid = true
        ns.Api.Group.raidChatType = "RAID"
        ns.Api.Group.members = InterruptChainHelper.MockRoster()
        ns.Modules.Start(ns.Database.Load(nil))
        local TwinFangs = ns.Modules.Get("TwinFangs")
        AssignFrontLeft(TwinFangs.db.interruptReminder.chain)
        local host = FakeFrame()
        Editor.Mount(host, function() end)
        ns.Api.Timer.RunPending()
        return Editor.Mounted()
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        InterruptChainHelper.LoadLabels(ns)
        Preview = InterruptChainHelper.LoadPreview(ns)
        StubUi(ns)
        assert(loadfile(EDITOR_UI_PATH))(Loader.ADDON_NAME, ns)
        Editor = ns.Modules.Internals("TwinFangs").InterruptChainEditor
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function OpenRegion(ui, regionId)
        ui.overview.cards[regionId].scripts.OnClick()
        ns.Api.Timer.RunPending()
    end

    it("shows a ×1 count selector and single sequence number by default", function()
        local ui = MountEditor()
        OpenRegion(ui, Chain.FRONT_LEFT)
        local row = ui.editor.playerRows[1]
        assert.equals("#1", row.number.text)
        assert.equals(1, row.countDropdown.selected)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_COUNT, row.countLabel.text)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_COUNT_OPTION:format(1), row.countDropdown.items[1].text)
        assert.equals(3, #row.countDropdown.items)
    end)

    it("updates sequence ranges immediately when the count selector changes", function()
        local ui = MountEditor()
        OpenRegion(ui, Chain.FRONT_LEFT)
        ui.editor.playerRows[2].countDropdown.onSelect(3)
        ns.Api.Timer.RunPending()
        assert.equals("#1", ui.editor.playerRows[1].number.text)
        assert.equals("#2–4", ui.editor.playerRows[2].number.text)
        assert.equals("#5", ui.editor.playerRows[3].number.text)
        assert.equals(3, ui.editor.playerRows[2].countDropdown.selected)
        local stored = ns.Modules.Get("TwinFangs").db.interruptReminder.chain.front_left.players
        assert.equals(5, #stored)
        assert.equals(stored[2].name, stored[3].name)
        assert.equals(stored[3].name, stored[4].name)
        assert.is_nil(stored[2].guid)
    end)

    it("reorders and removes whole player rows without splitting interrupt turns", function()
        local ui = MountEditor()
        OpenRegion(ui, Chain.FRONT_LEFT)
        ui.editor.playerRows[2].countDropdown.onSelect(3)
        ui.editor.playerRows[2].up.onClick()
        ns.Api.Timer.RunPending()
        assert.equals(3, VisibleRows(ui))
        assert.equals(Guid("夜雨"), ui.editor.playerRows[1].guid)
        assert.equals("#1–3", ui.editor.playerRows[1].number.text)
        assert.equals(Guid("清风"), ui.editor.playerRows[2].guid)
        assert.equals("#4", ui.editor.playerRows[2].number.text)

        ui.editor.playerRows[1].remove.onClick()
        ns.Api.Timer.RunPending()
        assert.equals(2, VisibleRows(ui))
        assert.equals("#1", ui.editor.playerRows[1].number.text)
        assert.equals("#2", ui.editor.playerRows[2].number.text)
        assert.equals(1, ui.editor.playerRows[1].countDropdown.selected)
        ui.editor.addDropdown.onSelect(Guid("夜雨"))
        ui.editor.addButton.onClick()
        ns.Api.Timer.RunPending()
        assert.equals(3, VisibleRows(ui))
        assert.equals(1, ui.editor.playerRows[3].countDropdown.selected)
        assert.equals("#3", ui.editor.playerRows[3].number.text)
    end)

    it("keeps preview counts when switching regions and shows them on overview cards", function()
        local ui = MountEditor()
        OpenRegion(ui, Chain.FRONT_LEFT)
        ui.editor.playerRows[2].countDropdown.onSelect(3)
        ui.editor.nav.onSelect(Chain.FRONT_RIGHT)
        ns.Api.Timer.RunPending()
        assert.equals(1, VisibleRows(ui))
        assert.equals("#1", ui.editor.playerRows[1].number.text)
        assert.equals(1, ui.editor.playerRows[1].countDropdown.selected)
        ui.editor.nav.onSelect(Chain.FRONT_LEFT)
        ns.Api.Timer.RunPending()
        assert.equals("#2–4", ui.editor.playerRows[2].number.text)
        assert.equals(3, ui.editor.playerRows[2].countDropdown.selected)

        ui.editor.back.onClick()
        ns.Api.Timer.RunPending()
        local left = ui.overview.cards[Chain.FRONT_LEFT]
        assert.equals(true, left.players.text:find("#2–4", 1, true) ~= nil)
        assert.equals(true, left.players.text:find("×3", 1, true) ~= nil)
        assert.equals(true, left.summary.text:find("3", 1, true) ~= nil)
        assert.equals(true, left.summary.text:find("5", 1, true) ~= nil)
        local right = ui.overview.cards[Chain.FRONT_RIGHT]
        assert.equals(true, right.players.text:find("#1", 1, true) ~= nil)
        assert.equals(true, right.players.text:find("×3", 1, true) == nil)
        local stored = ns.Modules.Get("TwinFangs").db.interruptReminder.chain.front_left.players
        assert.is_nil(stored[1].guid)
        assert.equals(5, #stored)
        assert.equals(stored[2].name, stored[4].name)
    end)
end)

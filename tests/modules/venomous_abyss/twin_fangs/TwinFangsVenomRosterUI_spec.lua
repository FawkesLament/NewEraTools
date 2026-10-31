local Loader = require("helpers.loader")

local UI_PATH = "modules/venomous_abyss/twin_fangs/ui/VenomRoster.lua"

describe("TwinFangs venom roster UI", function()
    local ns, Module, originalCreateFrame, created, registered, editing, onScaleChanged

    local function FakeLabel(parent)
        local label = { parent = parent, text = "", shown = true, points = {} }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint(point, relative, relativePoint, x, y)
            self.points[#self.points + 1] = { point, relative, relativePoint, x, y }
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
        function label:SetFont(_, size)
            self.fontSize = size
        end
        function label:SetWidth(width)
            self.width = width
        end
        function label:GetWidth()
            return self.width or 0
        end
        function label:SetMaxLines() end
        function label:GetStringWidth()
            return #(self.text or "") * 8
        end
        return label
    end

    local function FakeFrame(parent, name)
        local frame = {
            parent = parent,
            name = name,
            shown = true,
            scripts = {},
            width = 0,
            height = 0,
            scale = 1,
            points = {},
            children = {},
        }
        created[#created + 1] = frame
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:SetMovable() end
        function frame:EnableMouse() end
        function frame:RegisterForDrag() end
        function frame:StartMoving() end
        function frame:StopMovingOrSizing() end
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
        function frame:SetScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale
        end
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetPoint(point, relative, relativePoint, x, y)
            self.points[#self.points + 1] = { point, relative, relativePoint, x, y }
        end
        function frame:SetAllPoints() end
        function frame:SetScript(script, handler)
            self.scripts[script] = handler
        end
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:Raise() end
        function frame:CreateFontString()
            return FakeLabel(self)
        end
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        created = {}
        registered = {}
        editing = {}
        onScaleChanged = nil
        CreateFrame = function(_, name, parent)
            return FakeFrame(parent, name)
        end
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            CreateLabel = function(parent, _, text)
                local label = FakeLabel(parent)
                if text then
                    label.text = text
                end
                return label
            end,
        }
        ns.LayoutEditor = {
            Register = function(def)
                registered[def.id] = def
            end,
            ApplyPosition = function(frame, position)
                frame.position = position
            end,
            IsEditing = function()
                return next(editing) ~= nil
            end,
            Refresh = function()
                local def = registered["TwinFangs:venomRoster"]
                if not def then
                    return
                end
                if def.isEnabled() then
                    if not editing[def.id] then
                        editing[def.id] = true
                        def.onEditBegin()
                    end
                elseif editing[def.id] then
                    editing[def.id] = nil
                    def.onEditEnd()
                end
            end,
        }
        local panelScale = 1
        ns.MainPanel = {
            GetScale = function()
                return panelScale
            end,
            OnScaleChanged = function(callback)
                onScaleChanged = function(scale)
                    panelScale = scale
                    callback(scale)
                end
            end,
        }
        assert(loadfile(UI_PATH))(Loader.ADDON_NAME, ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function UI()
        return ns.Modules.Internals("TwinFangs").VenomRosterUI
    end

    local function VisibleColumns(instance)
        local columns = {}
        for _, column in ipairs(instance.columns) do
            if column.frame.shown then
                columns[#columns + 1] = column
            end
        end
        return columns
    end

    local function VisibleRows(column)
        local rows = {}
        for _, row in ipairs(column.rows) do
            if row.frame.shown then
                rows[#rows + 1] = row
            end
        end
        return rows
    end

    it("sizes the root to populated columns and the tallest group", function()
        local ui = UI()
        ui.ShowPreview("uneven")
        local instance = ui.Ensure()
        assert.is_true(instance.root.shown)
        assert.equals(3, #VisibleColumns(instance))
        assert.equals(136 * 3 + 12 * 2, instance.root.width)
        assert.equals(5 * 20, instance.root.height)
        assert.equals(5, #VisibleRows(instance.columns[1]))
        assert.equals(1, #VisibleRows(instance.columns[2]))
        assert.equals(3, #VisibleRows(instance.columns[3]))
    end)

    it("skips empty subgroups in column order", function()
        local ui = UI()
        ui.ShowPreview("gaps")
        local instance = ui.Ensure()
        local columns = VisibleColumns(instance)
        assert.equals(3, #columns)
        assert.equals(2, #VisibleRows(columns[1]))
        assert.equals(4, #VisibleRows(columns[2]))
        assert.equals(3, #VisibleRows(columns[3]))
        assert.same({ 1, 3, 5 }, {
            instance.boundColumns[1].group,
            instance.boundColumns[2].group,
            instance.boundColumns[3].group,
        })
    end)

    it("reuses frames when the raid shrinks and grows", function()
        local ui = UI()
        ui.ShowPreview(30)
        local instance = ui.Ensure()
        local afterCreate = #created
        local firstRoot = instance.root
        local firstColumns = {}
        local firstRows = {}
        for slot, column in ipairs(instance.columns) do
            firstColumns[slot] = column.frame
            firstRows[slot] = {}
            for rowSlot, row in ipairs(column.rows) do
                firstRows[slot][rowSlot] = row.frame
            end
        end
        assert.equals(6, #instance.columns)
        assert.equals(5, #instance.columns[6].rows)

        ui.ShowPreview(1)
        assert.equals(firstRoot, instance.root)
        assert.equals(afterCreate, #created)
        assert.equals(1, #VisibleColumns(instance))
        assert.equals(1, #VisibleRows(instance.columns[1]))
        assert.is_false(instance.columns[2].frame.shown)
        assert.is_false(instance.columns[6].rows[5].frame.shown)
        assert.equals(20, instance.root.height)
        assert.equals(136, instance.root.width)

        ui.ShowPreview(30)
        assert.equals(afterCreate, #created)
        assert.equals(6, #VisibleColumns(instance))
        for slot, column in ipairs(instance.columns) do
            assert.equals(firstColumns[slot], column.frame)
            assert.is_true(column.frame.shown)
            for rowSlot, row in ipairs(column.rows) do
                assert.equals(firstRows[slot][rowSlot], row.frame)
                assert.is_true(row.frame.shown)
            end
        end
    end)

    it("keeps member order stable while mock stacks sit on StackText", function()
        local ui = UI()
        ui.ShowPreview(5)
        local rows = VisibleRows(ui.Ensure().columns[1])
        assert.equals("Player1", rows[1].nameText.text)
        assert.equals("Player5", rows[5].nameText.text)
        assert.equals("0", rows[1].stackText.text)
        assert.equals("4", rows[5].stackText.text)
        assert.equals(rows[1].stackHost, rows[1].stackText.parent)
        ui.HidePreview()
        assert.is_false(ui.Ensure().root.shown)
    end)

    it("exposes a development preview command without touching live roster APIs", function()
        local ui = UI()
        ns.Modules.Get("TwinFangs"):OnEnable()
        local command = ns.Api.Slash.registered.NEWERATOOLSTWINFANGSVENOM
        assert.same({ "/netvenom" }, command.commands)
        command.handler("10")
        local instance = ui.Ensure()
        assert.is_true(instance.root.shown)
        assert.equals(2, #VisibleColumns(instance))
        assert.equals(5, #VisibleRows(instance.columns[1]))
        assert.equals(5, #VisibleRows(instance.columns[2]))
        command.handler("hide")
        assert.is_false(instance.root.shown)
    end)

    it("registers a Twin Fangs Edit Mode element and stays hidden until preview", function()
        local ui = UI()
        local instance = ui.Ensure()
        local def = registered[ui.LAYOUT_ID]
        assert.equals("TwinFangs:venomRoster", ui.LAYOUT_ID)
        assert.equals(ns.L.TWIN_FANGS_VENOM_ROSTER, def.label)
        assert.is_false(def.global)
        assert.is_true(def.isEnabled())
        assert.is_false(instance.root.shown)
        assert.same(Module:GetVenomRosterPosition(), instance.root.position)
        Module:SetVenomRosterEnabled(false)
        assert.is_false(def.isEnabled())
    end)

    it("applies scale, spacing, and font sizes in place", function()
        local ui = UI()
        ui.ShowPreview(20)
        local instance = ui.Ensure()
        local afterCreate = #created
        local root = instance.root
        assert.equals(1, root.scale)
        assert.equals(5 * 20, root.height)
        assert.equals(136 * 4 + 12 * 3, root.width)
        assert.equals(12, instance.columns[1].rows[1].nameText.fontSize)
        assert.equals(16, instance.columns[1].rows[1].stackText.fontSize)

        onScaleChanged(1.25)
        Module:SetVenomRosterRowSpacing(24)
        Module:SetVenomRosterColumnSpacing(8)
        Module:SetVenomRosterNameFontSize(14)
        Module:SetVenomRosterStackFontSize(20)
        assert.equals(afterCreate, #created)
        assert.equals(root, instance.root)
        assert.equals(1.25, root.scale)
        assert.equals(5 * 24, root.height)
        assert.equals(136 * 4 + 8 * 3, root.width)
        assert.equals(14, instance.columns[1].rows[1].nameText.fontSize)
        assert.equals(20, instance.columns[1].rows[1].stackText.fontSize)
    end)

    it("sizes name columns from the name-width setting and truncates overflow", function()
        local ui = UI()
        ui.ShowPreview(20)
        local instance = ui.Ensure()
        local afterCreate = #created
        assert.equals(120, instance.columns[1].rows[1].nameText.width)
        assert.equals("Player1", instance.columns[1].rows[1].nameText.text)

        Module:SetVenomRosterNameColumnWidth(80)
        assert.equals(afterCreate, #created)
        assert.equals(80, instance.columns[1].rows[1].nameText.width)
        assert.equals((80 + 16) * 4 + 12 * 3, instance.root.width)
        assert.equals("Player1", instance.columns[1].rows[1].nameText.text)

        Module:SetVenomRosterNameColumnWidth(64)
        ui.Apply({
            {
                name = "VeryLongPlayerNameABCDEF",
                subgroup = 1,
                index = 1,
                classFile = "WARRIOR",
            },
        })
        assert.equals(64, instance.columns[1].rows[1].nameText.width)
        assert.equals(64 + 16, instance.root.width)
        assert.equals("VeryL…", instance.columns[1].rows[1].nameText.text)
    end)

    it("shows the default 20-player mock in Edit Mode and forgets it on exit", function()
        local ui = UI()
        local instance = ui.Ensure()
        local def = registered[ui.LAYOUT_ID]
        local whileInCalls = 0
        local originalWhileIn = ns.Api.Encounter.WhileIn
        ns.Api.Encounter.WhileIn = function(...)
            whileInCalls = whileInCalls + 1
            return originalWhileIn(...)
        end

        def.onEditBegin()
        assert.is_true(instance.root.shown)
        assert.equals(4, #VisibleColumns(instance))
        assert.equals(5, #VisibleRows(instance.columns[1]))
        assert.equals("Player1", instance.columns[1].rows[1].nameText.text)
        assert.equals("0", instance.columns[1].rows[1].stackText.text)
        assert.equals(0, whileInCalls)
        assert.is_false(ns.Api.Encounter.IsInProgress())

        def.onEditEnd()
        ns.Api.Encounter.WhileIn = originalWhileIn
        assert.is_false(instance.root.shown)
        assert.equals("", instance.columns[1].rows[1].nameText.text)
        assert.equals("", instance.columns[1].rows[1].stackText.text)
        assert.is_nil(instance.columns[1].rows[1].member)
    end)

    it("hides the roster when disabled and reuses the same instance when re-enabled", function()
        local ui = UI()
        ui.ShowPreview(10)
        local instance = ui.Ensure()
        local root = instance.root
        local afterCreate = #created
        assert.is_true(root.shown)

        Module:SetVenomRosterEnabled(false)
        assert.is_false(root.shown)
        assert.equals("", instance.columns[1].rows[1].nameText.text)
        Module:SetVenomRosterEnabled(true)
        assert.equals(root, ui.Ensure().root)
        assert.equals(afterCreate, #created)
        assert.is_false(root.shown)
        assert.is_true(registered[ui.LAYOUT_ID].isEnabled())
    end)
end)

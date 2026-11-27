local Loader = require("helpers.loader")
local Fs = require("helpers.fs")

describe("DebuffMonitor", function()
    local ns, originalCreateFrame, created

    local function FakeLabel(parent)
        local label = { parent = parent, text = "", shown = true, points = {} }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:ClearAllPoints()
            self.points = {}
        end
        function label:SetPoint(...)
            self.points[#self.points + 1] = { ... }
        end
        function label:SetText(text)
            self.text = text
        end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function label:SetFont() end
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
        function label:SetShadowOffset() end
        function label:SetShadowColor() end
        return label
    end

    local function FakeFrame(parent, name, kind)
        local frame = {
            parent = parent,
            name = name,
            kind = kind,
            shown = true,
            width = 0,
            height = 0,
            scale = 1,
            points = {},
        }
        created[#created + 1] = frame
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:EnableMouse() end
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
        function frame:SetPoint(...)
            self.points[#self.points + 1] = { ... }
        end
        function frame:SetAllPoints() end
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
        function frame:SetFrameLevel(level)
            self.frameLevel = level
        end
        function frame:GetFrameLevel()
            return self.frameLevel or 0
        end
        function frame:CreateFontString()
            return FakeLabel(self)
        end
        function frame:CreateTexture()
            local texture = { parent = self, shown = true, points = {} }
            function texture:SetColorTexture(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            function texture:SetTexture(path)
                self.texture = path
            end
            function texture:SetTexCoord(...)
                self.texCoord = { ... }
            end
            function texture:SetBlendMode(mode)
                self.blendMode = mode
            end
            function texture:SetVertexColor(r, g, b, a)
                self.vertexColor = { r = r, g = g, b = b, a = a }
            end
            function texture:SetAlpha(alpha)
                self.alpha = alpha
            end
            function texture:SetAllPoints() end
            function texture:SetPoint(...)
                self.points[#self.points + 1] = { ... }
            end
            function texture:ClearAllPoints()
                self.points = {}
            end
            function texture:SetWidth(width)
                self.width = width
            end
            function texture:SetHeight(height)
                self.height = height
            end
            function texture:Show()
                self.shown = true
            end
            function texture:Hide()
                self.shown = false
            end
            function texture:SetShown(shown)
                self.shown = shown and true or false
            end
            return texture
        end
        function frame:SetMinMaxValues(minValue, maxValue)
            self.minValue = minValue
            self.maxValue = maxValue
        end
        function frame:GetMinMaxValues()
            return self.minValue or 0, self.maxValue or 1
        end
        function frame:SetValue(value)
            self.value = value
        end
        function frame:GetValue()
            return self.value or 0
        end
        function frame:HookScript() end
        function frame:SetStatusBarTexture() end
        function frame:GetStatusBarTexture()
            if not self.statusBarTexture then
                self.statusBarTexture = { parent = self, points = {} }
                function self.statusBarTexture:ClearAllPoints()
                    self.points = {}
                end
                function self.statusBarTexture:SetPoint(...)
                    self.points[#self.points + 1] = { ... }
                end
            end
            return self.statusBarTexture
        end
        function frame:SetStatusBarColor(r, g, b, a)
            self.statusBarColor = { r = r, g = g, b = b, a = a }
        end
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        created = {}
        CreateFrame = function(kind, name, parent)
            return FakeFrame(parent, name, kind)
        end
        ns = Loader.Load()
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            CreateLabel = function(parent)
                return FakeLabel(parent)
            end,
        }
        ns.LayoutEditor = { ApplyPosition = function() end }
        ns.MainPanel = {
            GetScale = function()
                return 1
            end,
            OnScaleChanged = function() end,
        }
        assert(loadfile("ui/DebuffMonitorColumns.lua"))("NewEraTools", ns)
        assert(loadfile("ui/DebuffMonitor.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function VisibleRows(column)
        local rows = {}
        for _, row in ipairs(column.rows) do
            if row.frame.shown then
                rows[#rows + 1] = row
            end
        end
        return rows
    end

    local function Create(config)
        config.name = config.name or "NewEraToolsDebuffMonitorTest"
        config.slotKey = config.slotKey or "test"
        return ns.DebuffMonitor.Create(config)
    end

    it("packs roster columns by subgroup and keeps empty groups omitted", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_ROSTER,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
            groupBy = "subgroup",
            omitEmptyGroups = true,
            showGroupHeaders = false,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(20)
        monitor:Apply(members, { values = ns.DebuffMonitor.PreviewValues(members) })
        assert.equals(4, #monitor.boundColumns)
        assert.equals(5, #VisibleRows(monitor.columns[1]))
        assert.equals("Player1", monitor.columns[1].rows[1].nameText.text)
        assert.equals("0", monitor.columns[1].rows[1].stackText.text)
        assert.equals(4 * ns.DebuffMonitor.ColumnWidth() + 8 * 3, monitor.root.width)
        assert.equals(5 * 22, monitor.root.height)
        assert.is_false(monitor.columns[1].rows[1].spark.shown)
        local nameColor = monitor.columns[1].rows[1].nameText.color
        assert.equals(0.78, nameColor and nameColor.r)
        local layer = monitor.columns[1].rows[1].textLayer
        local bar = monitor.columns[1].rows[1].bar
        assert.is_true((layer.frameLevel or 0) >= (bar.frameLevel or 0) + 2)
    end)

    it("collapses empty mock rows in single layout", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_SINGLE,
            displayMode = ns.DebuffMonitor.DISPLAY_DURATION,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(5)
        monitor:Apply(members, { values = { [2] = 8, [5] = 3 } })
        local rows = VisibleRows(monitor.columns[1])
        assert.equals(1, #monitor.boundColumns)
        assert.equals(2, #rows)
        assert.equals("Player2", rows[1].nameText.text)
        assert.equals("8.0", rows[1].stackText.text)
        assert.equals("Player5", rows[2].nameText.text)
        assert.equals(2 * 22, monitor.columns[1].frame.height)
        assert.equals(ns.DebuffMonitor.ColumnWidth(), monitor.root.width)
    end)

    it("splits subgroups into two headed columns", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_SPLIT,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(20)
        monitor:Apply(members, { values = ns.DebuffMonitor.PreviewValues(members) })
        assert.equals(2, #monitor.boundColumns)
        assert.equals(ns.L.DEBUFF_MONITOR_GROUP_RANGE:format(1, 2), monitor.columns[1].headerText.text)
        assert.equals(ns.L.DEBUFF_MONITOR_GROUP_RANGE:format(3, 4), monitor.columns[2].headerText.text)
        assert.equals(10, #VisibleRows(monitor.columns[1]))
        assert.equals(10, #VisibleRows(monitor.columns[2]))
        assert.equals(16 + 10 * 22, monitor.root.height)
    end)

    it("fills a roster grid when columnCount is set", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_ROSTER,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
            columnCount = 2,
            rowsPerColumn = 10,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(20)
        monitor:Apply(members, { values = ns.DebuffMonitor.PreviewValues(members) })
        assert.equals(2, #monitor.boundColumns)
        assert.equals(10, #VisibleRows(monitor.columns[1]))
        assert.equals(10, #VisibleRows(monitor.columns[2]))
        assert.equals("Player11", monitor.columns[2].rows[1].nameText.text)
        assert.is_false(monitor.columns[1].header.shown)
        assert.equals(10 * 22, monitor.root.height)
    end)

    it("adds rowGap between stacked rows", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_ROSTER,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
            groupBy = "subgroup",
            omitEmptyGroups = true,
            showGroupHeaders = false,
            getAppearance = function()
                return { rowGap = 2 }
            end,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(20)
        monitor:Apply(members, { values = ns.DebuffMonitor.PreviewValues(members) })
        assert.equals(5 * 22 + 4 * 2, monitor.root.height)
        assert.equals(5 * 22 + 4 * 2, monitor.columns[1].frame.height)
    end)

    it("honors a zero column gap and background opacity", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_ROSTER,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
            groupBy = "subgroup",
            omitEmptyGroups = true,
            showGroupHeaders = false,
            getAppearance = function()
                return { columnGap = 0, backgroundOpacity = 0.4, barOpacity = 0.25, spark = true }
            end,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(20)
        monitor:Apply(members, { values = ns.DebuffMonitor.PreviewValues(members) })
        assert.equals(4 * ns.DebuffMonitor.ColumnWidth() + 0 * 3, monitor.root.width)
        assert.equals(5 * 22, monitor.root.height)
        assert.equals(0.4, monitor.columns[1].rows[1].bg.color.a)
        assert.equals(0.4, monitor.columns[1].headerBg.color.a)
        assert.equals(0.25, monitor.columns[1].rows[1].bar.statusBarColor.a)
        assert.is_false(monitor.columns[1].rows[1].spark.shown)
        assert.is_false(monitor.columns[1].rows[1].sparkGlow.shown)
        local lit = monitor.columns[1].rows[2]
        assert.is_true(lit.spark.shown)
        assert.is_true(lit.sparkGlow.shown)
        assert.equals("ADD", lit.spark.blendMode)
        assert.equals("ADD", lit.sparkGlow.blendMode)
        assert.equals(0.40, lit.spark.alpha)
        assert.equals(0.35, lit.sparkGlow.alpha)
        assert.is_true((lit.spark.vertexColor.r or 0) < 1)
        local layer = lit.textLayer
        local bar = lit.bar
        assert.is_true((layer.frameLevel or 0) >= (bar.frameLevel or 0) + 2)
    end)

    it("anchors live spark to the status bar fill even at zero", function()
        local monitor = Create({
            layoutMode = ns.DebuffMonitor.LAYOUT_SINGLE,
            displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
            getAppearance = function()
                return { spark = true }
            end,
        })
        local members = ns.DebuffMonitor.BuildPreviewMembers(1)
        monitor:Apply(members, { live = true, values = { [1] = 0 } })
        local row = monitor.columns[1].rows[1]
        local fill = row.bar:GetStatusBarTexture()
        assert.is_true(row.spark.shown)
        assert.is_true(row.sparkGlow.shown)
        local anchored
        for _, point in ipairs(row.spark.points) do
            if point[2] == fill then
                anchored = true
            end
        end
        assert.is_true(anchored)
    end)

    it("does not read secret aura fields from Lua", function()
        local source = Fs.ReadFile("ui/DebuffMonitor.lua")
        assert.is_nil(source:find("applications", 1, true))
        assert.is_nil(source:find("GetAuraData", 1, true))
        assert.is_nil(source:find("UNIT_AURA", 1, true))
        assert.is_nil(source:find("C_UnitAuras", 1, true))
    end)
end)

local Loader = require("helpers.loader")
local Fs = require("helpers.fs")

local UI_PATH = "modules/venomous_abyss/twin_fangs/ui/VenomRoster.lua"

describe("TwinFangs venom roster UI", function()
    local ns, Module, originalCreateFrame, created, registered, editing, onScaleChanged
    local auraContainers, savedAuraGlobals

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
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        function label:IsShown()
            return self.shown
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

    local function FakeFrame(parent, name, kind)
        local frame = {
            parent = parent,
            name = name,
            kind = kind,
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
        if kind == "AuraContainer" then
            auraContainers[#auraContainers + 1] = frame
            function frame:AddAuraSlot(key, filter, options)
                self.auraSlot = { key = key, filter = filter, options = options }
                local button = FakeFrame(self, "AuraButton", "AuraButton")
                function button:SetApplicationCount(fontString, countOptions)
                    self.applicationCount = { fontString = fontString, options = countOptions }
                end
                self.slotButton = button
                if options and options.initializeFrame then
                    options.initializeFrame(button)
                end
                return button
            end
            function frame:SetUnit(unit)
                self.unit = unit
                self.unitSets = (self.unitSets or 0) + 1
            end
            function frame:SetEnabled(enabled)
                self.enabled = enabled == true
            end
            function frame:SetAuraSlotEnabled(_, enabled)
                self.slotEnabled = enabled == true
            end
            function frame:CanChangeProtectedState()
                return true
            end
        end
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        created = {}
        auraContainers = {}
        registered = {}
        editing = {}
        onScaleChanged = nil
        savedAuraGlobals = {
            AuraContainerSortMethod = AuraContainerSortMethod,
            AuraContainerSortDirection = AuraContainerSortDirection,
            C_AddOns = C_AddOns,
        }
        AuraContainerSortMethod = { Expiration = "Expiration", ExpirationOnly = "ExpirationOnly" }
        AuraContainerSortDirection = { Normal = "Normal", Reverse = "Reverse" }
        C_AddOns = {
            IsAddOnLoaded = function()
                return true
            end,
            LoadAddOn = function()
                return true
            end,
        }
        CreateFrame = function(kind, name, parent)
            return FakeFrame(parent, name, kind)
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
        Module:SetVenomRosterEnabled(true)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        if savedAuraGlobals then
            AuraContainerSortMethod = savedAuraGlobals.AuraContainerSortMethod
            AuraContainerSortDirection = savedAuraGlobals.AuraContainerSortDirection
            C_AddOns = savedAuraGlobals.C_AddOns
        end
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

    local function RaidMember(name, subgroup, index, classFile)
        return {
            name = name,
            subgroup = subgroup,
            index = index,
            classFile = classFile or "MAGE",
            unit = "raid" .. index,
        }
    end

    local function SetRaid(members)
        ns.Api.Group.inRaid = true
        ns.Api.Group.members = members
    end

    it("configures one harmful AuraSlot per live row without spell-ID matching", function()
        local ui = UI()
        SetRaid({
            RaidMember("Alpha", 1, 4),
            RaidMember("Beta", 3, 12),
        })
        ui.SetLiveActive(true)
        local instance = ui.Ensure()
        local alpha = instance.columns[1].rows[1]
        local beta = instance.columns[2].rows[1]
        assert.equals(2, #auraContainers)
        assert.equals(alpha.stackHost, alpha.container.parent)
        assert.equals("raid4", alpha.container.unit)
        assert.equals("raid12", beta.container.unit)
        local slot = alpha.container.auraSlot
        assert.equals("venom", slot.key)
        assert.equals("HARMFUL", slot.filter)
        assert.equals("HARMFUL", slot.options.filterString)
        assert.equals(false, slot.options.candidateFilters.isFromPlayerOrPlayerPet)
        assert.equals(false, slot.options.candidateFilters.isBossOrRoleAura)
        assert.equals("ExpirationOnly", slot.options.sortMethod)
        assert.equals("Reverse", slot.options.sortDirection)
        assert.is_nil(slot.options.maxFrameCount)
        assert.is_nil(slot.options.includeSpellIDs)
        assert.is_nil(slot.options.candidateFilters.includeSpellIDs)
        local count = alpha.auraButton.applicationCount
        assert.equals(alpha.liveStackText, count.fontString)
        assert.same({}, count.options)
        assert.is_false(alpha.stackText.shown)
        assert.is_true(alpha.liveStackText.shown)
        assert.equals("", alpha.stackText.text)
    end)

    it("binds names and aura units to the same subgroup-ordered rows", function()
        local ui = UI()
        SetRaid({
            RaidMember("Late", 1, 12, "WARRIOR"),
            RaidMember("Mid", 2, 7, "PRIEST"),
            RaidMember("Early", 1, 4, "MAGE"),
        })
        ui.SetLiveActive(true)
        local instance = ui.Ensure()
        local group1 = VisibleRows(instance.columns[1])
        assert.equals("Early", group1[1].nameText.text)
        assert.equals("raid4", group1[1].container.unit)
        assert.equals("Late", group1[2].nameText.text)
        assert.equals("raid12", group1[2].container.unit)
        assert.equals("Mid", VisibleRows(instance.columns[2])[1].nameText.text)
        assert.equals("raid7", instance.columns[2].rows[1].container.unit)
    end)

    it("reuses live frames when the raid shrinks, grows, and changes subgroups", function()
        local ui = UI()
        local members = {}
        for index = 1, 30 do
            members[index] = RaidMember("P" .. index, math.ceil(index / 5), index)
        end
        SetRaid(members)
        ui.SetLiveActive(true)
        local instance = ui.Ensure()
        local afterCreate = #created
        local firstContainers = {}
        for slot, column in ipairs(instance.columns) do
            firstContainers[slot] = {}
            for rowSlot, row in ipairs(column.rows) do
                firstContainers[slot][rowSlot] = row.container
            end
        end
        assert.equals(30, #auraContainers)

        SetRaid({ RaidMember("P1", 1, 1) })
        ui.Update()
        assert.equals(afterCreate, #created)
        assert.equals(1, #VisibleColumns(instance))
        assert(firstContainers[1][1] == instance.columns[1].rows[1].container, "group 1 row 1 container was recreated")
        assert.equals("raid1", instance.columns[1].rows[1].container.unit)
        assert.is_false(instance.columns[6].rows[5].frame.shown)
        assert.is_false(instance.columns[6].rows[5].container.shown)

        SetRaid({
            RaidMember("Moved", 3, 1),
            RaidMember("Stay", 1, 4),
        })
        ns.Api.Group.FireRosterChanged()
        assert.equals(afterCreate, #created)
        assert.equals("Stay", instance.columns[1].rows[1].nameText.text)
        assert.equals("raid4", instance.columns[1].rows[1].container.unit)
        assert.equals("Moved", instance.columns[2].rows[1].nameText.text)
        assert.equals("raid1", instance.columns[2].rows[1].container.unit)
        assert(firstContainers[1][1] == instance.columns[1].rows[1].container, "group 1 row 1 container was recreated after move")
        assert(firstContainers[2][1] == instance.columns[2].rows[1].container, "group 2 row 1 container was recreated after move")
    end)

    it("keeps mock stacks off the native application-count FontString", function()
        local ui = UI()
        ui.ShowPreview(5)
        local instance = ui.Ensure()
        assert.equals(0, #auraContainers)
        assert.equals("0", instance.columns[1].rows[1].stackText.text)
        assert.is_true(instance.columns[1].rows[1].stackText.shown)

        SetRaid({ RaidMember("Live", 1, 2) })
        ui.SetLiveActive(true)
        local row = instance.columns[1].rows[1]
        assert.equals(1, #auraContainers)
        assert.equals("Live", row.nameText.text)
        assert.equals("raid2", row.container.unit)
        assert.equals("", row.stackText.text)
        assert.is_false(row.stackText.shown)
        assert.is_true(row.liveStackText.shown)
        row.liveStackText.text = "native"

        ui.ShowPreview(5)
        assert.equals(1, #auraContainers)
        assert.equals("Player1", row.nameText.text)
        assert.equals("0", row.stackText.text)
        assert.is_true(row.stackText.shown)
        assert.is_false(row.liveStackText.shown)
        assert.equals("native", row.liveStackText.text)
        assert.is_false(row.container.shown)
        assert.is_false(row.container.enabled)

        ui.HidePreview()
        assert.equals("Live", row.nameText.text)
        assert.equals("raid2", row.container.unit)
        assert.is_true(row.container.shown)
        assert.is_false(row.stackText.shown)
        assert.equals("native", row.liveStackText.text)
    end)

    it("uses mock Edit Mode data without live raid members", function()
        local ui = UI()
        SetRaid({ RaidMember("Live", 1, 1) })
        ui.SetLiveActive(true)
        local instance = ui.Ensure()
        local def = registered[ui.LAYOUT_ID]
        def.onEditBegin()
        assert.equals("Player1", instance.columns[1].rows[1].nameText.text)
        assert.equals("0", instance.columns[1].rows[1].stackText.text)
        assert.is_true(instance.columns[1].rows[1].stackText.shown)
        assert.is_false(instance.columns[1].rows[1].liveStackText.shown)
        assert.is_false(instance.columns[1].rows[1].container.shown)
        def.onEditEnd()
        assert.equals("Live", instance.columns[1].rows[1].nameText.text)
        assert.equals("raid1", instance.columns[1].rows[1].container.unit)
        assert.is_true(instance.columns[1].rows[1].container.shown)
    end)

    it("defers AuraContainer creation until combat lockdown ends", function()
        local ui = UI()
        ns.Modules.Get("TwinFangs"):OnEnable()
        SetRaid({ RaidMember("Live", 1, 1) })
        ns.Api.Combat.inCombat = true
        ui.SetLiveActive(true)
        local instance = ui.Ensure()
        local row = instance.columns[1].rows[1]
        assert.equals(0, #auraContainers)
        assert.equals("Live", row.nameText.text)
        assert.is_true(row.auraPending)

        ns.Api.Combat.FireLeave()
        assert.equals(1, #auraContainers)
        assert.equals("raid1", row.container.unit)
        assert.is_true(row.container.shown)
        assert.is_nil(row.auraPending)
    end)

    it("does not read aura application counts from Lua", function()
        local source = Fs.ReadFile(UI_PATH)
        assert.is_nil(source:find("applications", 1, true))
        assert.is_nil(source:find("GetAuraData", 1, true))
        assert.is_nil(source:find("UNIT_AURA", 1, true))
        assert.is_nil(source:find("C_UnitAuras", 1, true))
    end)

    it("exposes /netvenom live without encounter wiring", function()
        local ui = UI()
        ns.Modules.Get("TwinFangs"):OnEnable()
        SetRaid({ RaidMember("Live", 1, 8) })
        local command = ns.Api.Slash.registered.NEWERATOOLSTWINFANGSVENOM
        command.handler("live")
        local instance = ui.Ensure()
        assert.is_true(ui.IsLiveActive())
        assert.equals("Live", instance.columns[1].rows[1].nameText.text)
        assert.equals("raid8", instance.columns[1].rows[1].container.unit)
        command.handler("hide")
        assert.is_false(ui.IsLiveActive())
        assert.is_false(instance.root.shown)
    end)

    describe("lifecycle", function()
        local Encounter

        local function EnterPit(subZone)
            ns.Api.Instance.info.instanceID = 3004
            ns.Api.Instance.info.instanceType = "raid"
            ns.Api.Instance.subZoneText = subZone or "Pit of Fangs"
        end

        local function LeavePit()
            ns.Api.Instance.subZoneText = "The Venomous Abyss"
        end

        local function StartFight(difficultyID)
            Encounter.FireStart(
                Module.ENCOUNTER_ID,
                "Twin Fangs",
                difficultyID or ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
                20
            )
        end

        local function EndFight(difficultyID)
            Encounter.FireEnd(
                Module.ENCOUNTER_ID,
                "Twin Fangs",
                difficultyID or ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
                20,
                1
            )
        end

        before_each(function()
            Encounter = ns.Api.Encounter
            SetRaid({ RaidMember("Live", 1, 1) })
            ns.Modules.Get("TwinFangs"):OnEnable()
            Module:ListenForEncounter()
        end)

        it("prewarms in Pit of Fangs when the feature is on and stays hidden", function()
            local ui = UI()
            EnterPit()
            ns.Api.Instance.FireEnteringWorld()
            assert.is_true(ui.IsPrepared())
            local instance = ui.Ensure()
            assert.is_false(instance.root.shown)
            assert.is_false(ui.IsLiveActive())
            if instance.columns[1] and instance.columns[1].rows[1].container then
                assert.is_false(instance.columns[1].rows[1].container.shown)
                assert.is_false(instance.columns[1].rows[1].container.enabled)
            end
        end)

        it("prewarms for the Chinese Pit of Fangs subzone", function()
            local ui = UI()
            EnterPit("毒牙深渊")
            ns.Api.Instance.FireZoneChangedIndoors()
            assert.is_true(ui.IsPrepared())
            assert.is_false(ui.Ensure().root.shown)
        end)

        it("does not prewarm in the wrong instance or subzone", function()
            local ui = UI()
            ns.Api.Instance.info.instanceID = 3004
            ns.Api.Instance.subZoneText = "Altar of the Six Winds"
            ns.Api.Instance.FireZoneChangedIndoors()
            assert.is_false(ui.IsPrepared())

            ns.Api.Instance.info.instanceID = 0
            ns.Api.Instance.subZoneText = "Pit of Fangs"
            ns.Api.Instance.FireZoneChangedNewArea()
            assert.is_false(ui.IsPrepared())
        end)

        it("does not recreate the roster across repeated zone events", function()
            local ui = UI()
            EnterPit()
            ns.Api.Instance.FireEnteringWorld()
            local first = ui.Ensure().root
            local createdAfter = #created
            LeavePit()
            ns.Api.Instance.FireZoneChangedIndoors()
            EnterPit()
            ns.Api.Instance.FireZoneChangedIndoors()
            ns.Api.Instance.FireZoneChangedNewArea()
            ns.Api.Instance.FireEnteringWorld()
            assert.equals(first, ui.Ensure().root)
            assert.equals(createdAfter, #created)
            assert.is_false(ui.IsLiveActive())
        end)

        it("activates encounter 3421 on every raid difficulty and ignores other encounters", function()
            local ui = UI()
            for _, difficultyID in ipairs({ 14, 15, 16, 17 }) do
                StartFight(difficultyID)
                assert.is_true(ui.IsLiveActive())
                assert.is_true(ui.Ensure().root.shown)
                assert.equals("raid1", ui.Ensure().columns[1].rows[1].container.unit)
                EndFight(difficultyID)
                assert.is_false(ui.IsLiveActive())
                assert.is_false(ui.Ensure().root.shown)
            end

            Encounter.FireStart(1, "Other", ns.Api.Instance.DIFFICULTY_MYTHIC_RAID, 20)
            assert.is_false(ui.IsLiveActive())
            assert.is_false(ui.Ensure().root.shown)
        end)

        it("reuses the same instance across repeated pulls", function()
            local ui = UI()
            EnterPit()
            ns.Api.Instance.FireZoneChangedIndoors()
            local instance = ui.Ensure()
            local root = instance.root
            local createdAfter = #created
            StartFight()
            local container = instance.columns[1].rows[1].container
            EndFight()
            StartFight()
            assert.equals(root, ui.Ensure().root)
            assert.is_true(container == ui.Ensure().columns[1].rows[1].container)
            assert.equals(createdAfter, #created)
            assert.is_true(ui.IsLiveActive())
            EndFight()
        end)

        it("does not prewarm when the feature is disabled", function()
            local ui = UI()
            Module:SetVenomRosterEnabled(false)
            EnterPit()
            ns.Api.Instance.FireEnteringWorld()
            assert.is_false(ui.IsPrepared())
        end)

        it("prewarms after enabling the feature in Pit of Fangs and activates during the pull", function()
            local ui = UI()
            Module:SetVenomRosterEnabled(false)
            EnterPit()
            ns.Api.Instance.FireZoneChangedIndoors()
            assert.is_false(ui.IsPrepared())

            Module:SetVenomRosterEnabled(true)
            assert.is_true(ui.IsPrepared())
            assert.is_false(ui.IsLiveActive())

            StartFight()
            local instance = ui.Ensure()
            assert.is_true(ui.IsLiveActive())
            Module:SetVenomRosterEnabled(false)
            assert.is_false(ui.IsLiveActive())
            assert.is_false(instance.root.shown)
            local root = instance.root
            Module:SetVenomRosterEnabled(true)
            assert.is_true(ui.IsLiveActive())
            assert.equals(root, ui.Ensure().root)
            EndFight()
        end)

        it("activates on encounter entry even when prewarming was skipped", function()
            local ui = UI()
            assert.is_false(ui.IsPrepared())
            StartFight()
            assert.is_true(ui.IsPrepared())
            assert.is_true(ui.IsLiveActive())
            assert.is_true(ui.Ensure().root.shown)
            EndFight()
            assert.is_true(ui.IsPrepared())
            assert.is_false(ui.IsLiveActive())
        end)

        it("binds joiners without recreating existing AuraContainers", function()
            local ui = UI()
            EnterPit()
            ns.Api.Instance.FireZoneChangedIndoors()
            StartFight()
            local instance = ui.Ensure()
            local firstContainer = instance.columns[1].rows[1].container
            local root = instance.root
            SetRaid({
                RaidMember("Live", 1, 1),
                RaidMember("Joiner", 2, 2),
            })
            ns.Api.Group.FireRosterChanged()
            assert.equals(root, ui.Ensure().root)
            assert.is_true(firstContainer == instance.columns[1].rows[1].container)
            assert.equals("raid1", instance.columns[1].rows[1].container.unit)
            assert.equals("Joiner", instance.columns[2].rows[1].nameText.text)
            assert.equals("raid2", instance.columns[2].rows[1].container.unit)
            EndFight()
        end)

        it("lets encounter lifecycle take over from /netvenom live", function()
            local ui = UI()
            ns.Api.Slash.registered.NEWERATOOLSTWINFANGSVENOM.handler("live")
            assert.is_true(ui.IsLiveActive())
            local root = ui.Ensure().root
            StartFight()
            assert.is_true(ui.IsLiveActive())
            assert.equals(root, ui.Ensure().root)
            EndFight()
            assert.is_false(ui.IsLiveActive())
            assert.is_false(ui.Ensure().root.shown)
            assert.equals(root, ui.Ensure().root)
        end)
    end)
end)

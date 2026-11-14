local Loader = require("helpers.loader")

local UI_PATH = "modules/combat/gear_alert/GearAlertUI.lua"

describe("GearAlert UI", function()
    local ns, GearAlert, section, created, toast, shown, originalCreateFrame
    local actionRows, actionRow, statusLabel

    local function AttachUi()
        section = nil
        created = nil
        toast = nil
        shown = {}
        actionRows = {}
        actionRow = nil
        statusLabel = nil
        ns.MainPanel = {
            RegisterSection = function(_, def)
                section = def
            end,
        }
        ns.AlertToast = {
            Create = function(options)
                created = options
                toast = {
                    shown = false,
                    SetWindowPosition = function(self, position)
                        self.position = position
                    end,
                    SetRows = function(_, rows)
                        table.insert(shown, rows)
                    end,
                    Show = function(self)
                        self.shown = true
                    end,
                    Hide = function(self)
                        self.shown = false
                        shown.hidden = true
                    end,
                    Raise = function(self)
                        self.raised = true
                    end,
                }
                return toast
            end,
        }
        ns.Layout = {
            Stack = function(container)
                return {
                    container = container,
                    AddRow = function()
                        return {}
                    end,
                    GetHeight = function()
                        return 10
                    end,
                }
            end,
        }
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
        }
        ns.ActionRow = {
            HEIGHT = 44,
            Apply = function(_, options)
                table.insert(actionRows, options)
                actionRow = options
                local label = {
                    text = options.description,
                    SetText = function(self, text)
                        self.text = text
                    end,
                    SetTextColor = function(self, r, g, b, a)
                        self.color = { r = r, g = g, b = b, a = a }
                    end,
                }
                if not statusLabel then
                    statusLabel = label
                end
                return {}, label
            end,
        }
        assert(loadfile(UI_PATH))(Loader.ADDON_NAME, ns)
        GearAlert:OnEnable()
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        GearAlert = ns.Modules.Get("GearAlert")
        AttachUi()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("registers a combat page without a header toggle", function()
        assert.equals(ns.L.GEAR_ALERT_TITLE, section.title)
        assert.equals(ns.PanelGroups.COMBAT, section.group)
        assert.equals(ns.L.GEAR_ALERT_HINT, section.tooltip)
        assert.is_nil(section.onEnabledChanged)
        assert.equals("function", type(section.build))
    end)

    it("creates the toast at the saved position on enable", function()
        assert.equals(Loader.ADDON_NAME .. "GearAlert", created.name)
        assert.equals(ns.L.GEAR_ALERT_NOTIFICATION_TITLE, created.title)
        assert.equals(200, created.position.y)
        created.onPositionChanged({ point = "CENTER", relativePoint = "CENTER", x = 12, y = 8 })
        assert.equals(12, GearAlert:GetPosition().x)
        assert.equals(8, GearAlert:GetPosition().y)
    end)

    it("builds a missing-set row with history status and no preview", function()
        section.build({})
        local row = actionRows[1]
        assert.equals(ns.L.GEAR_ALERT_MISSING_SET, row.title)
        assert.equals(ns.L.GEAR_ALERT_HISTORY_NONE, row.description)
        assert.is_nil(row.buttons)
        assert.is_true(row.enabled)

        row.onEnabledChanged(false)
        assert.is_false(GearAlert:IsFourPieceCheckEnabled())
    end)

    it("builds a low-level item row", function()
        section.build({})
        local row = actionRows[2]
        assert.equals(ns.L.GEAR_ALERT_LOW_LEVEL, row.title)
        assert.equals(ns.L.GEAR_ALERT_LOW_LEVEL_DESC, row.description)
        assert.is_nil(row.buttons)
        assert.is_true(row.enabled)

        row.onEnabledChanged(false)
        assert.is_false(GearAlert:IsLowLevelCheckEnabled())
    end)

    it("shows a formatted toast when entering the world with a missing set", function()
        section.build({})
        local Internals = ns.Modules.Internals("GearAlert")
        ns.Api.Equipment.SetEquippedSetForTests(2057, 4)
        Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
        ns.Api.Equipment.SetEquippedSetForTests(2057, 3)
        ns.Api.Instance.currentRaidIds[1001] = true
        ns.Api.Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
            instanceID = 1001,
        }
        ns.Api.Instance.FireEnteringWorld()
        ns.Api.Timer.Advance(GearAlert.SCAN_DELAY)
        assert.equals(ns.L.GEAR_ALERT_MISSING_TIER_SET, shown[1][1].left)
        assert.equals(
            ns.L.GEAR_ALERT_MISSING_TIER_SET_DETAIL:format(ns.Color.Wrap(ns.Assets.Colors.WARNING, "3/4")),
            shown[1][1].right
        )
        assert.equals(1, #shown[1])
        assert.is_true(toast.shown)
        assert.is_true(toast.raised)
        assert.equals(ns.L.GEAR_ALERT_HISTORY_DONE, statusLabel.text)
        assert.same(ns.Assets.Colors.SUCCESS, {
            r = statusLabel.color.r,
            g = statusLabel.color.g,
            b = statusLabel.color.b,
        })
    end)

    it("shows a formatted toast when entering the world with a low-level item", function()
        section.build({})
        ns.Api.Equipment.averageItemLevel = 700
        ns.Api.Equipment.SetSlotForTests(1, {
            status = "ready",
            itemID = 11,
            itemLevel = 30,
            link = "|cffffffff|Hitem:11::::::::80:257::::::|h[Old Helm]|h|r",
        })
        ns.Api.Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 1 } })
        ns.Api.Instance.currentRaidIds[1001] = true
        ns.Api.Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
            instanceID = 1001,
        }
        ns.Api.Instance.FireEnteringWorld()
        ns.Api.Timer.Advance(GearAlert.SCAN_DELAY)
        assert.equals(ns.L.GEAR_ALERT_LOW_LEVEL_ITEM, shown[1][1].left)
        assert.equals("|cffffffff|Hitem:11::::::::80:257::::::|h[Old Helm]|h|r", shown[1][1].right)
        assert.equals(1, #shown[1])
        assert.is_true(toast.shown)
        assert.is_true(toast.raised)
    end)

    it("shows a formatted toast when entering the world with an empty slot", function()
        section.build({})
        ns.Api.Equipment.averageItemLevel = 700
        ns.Api.Equipment.SetSlotForTests(1, { status = "empty" })
        ns.Api.Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 1 } })
        ns.Api.Instance.currentRaidIds[1001] = true
        ns.Api.Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
            instanceID = 1001,
        }
        ns.Api.Instance.FireEnteringWorld()
        ns.Api.Timer.Advance(GearAlert.SCAN_DELAY)
        assert.equals(ns.L.GEAR_ALERT_EMPTY_SLOT, shown[1][1].left)
        assert.equals(
            ns.Color.Wrap(ns.Assets.Colors.WARNING, ns.Api.Equipment.GetSlotName(1)),
            shown[1][1].right
        )
        assert.equals(1, #shown[1])
        assert.is_true(toast.shown)
        assert.is_true(toast.raised)
    end)

    it("shows one toast row per finding when several alerts fire", function()
        section.build({})
        local Internals = ns.Modules.Internals("GearAlert")
        ns.Api.Equipment.SetEquippedSetForTests(2057, 4)
        Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
        ns.Api.Equipment.SetEquippedSetForTests(2057, 3)
        ns.Api.Equipment.averageItemLevel = 700
        ns.Api.Equipment.SetSlotForTests(2, { status = "empty" })
        ns.Api.Equipment.SetSlotForTests(6, {
            status = "ready",
            itemID = 11,
            itemLevel = 30,
            link = "|cffffffff|Hitem:11::::::::80:257::::::|h[Old Helm]|h|r",
        })
        ns.Api.Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 2 } })
        ns.Api.Equipment.SetBagItemForTests({ status = "ready", itemID = 33, itemLevel = 700, slots = { 6 } })
        ns.Api.Instance.currentRaidIds[1001] = true
        ns.Api.Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = ns.Api.Instance.DIFFICULTY_MYTHIC_RAID,
            instanceID = 1001,
        }
        ns.Api.Instance.FireEnteringWorld()
        ns.Api.Timer.Advance(GearAlert.SCAN_DELAY)
        assert.equals(3, #shown[1])
        assert.equals(ns.L.GEAR_ALERT_EMPTY_SLOT, shown[1][1].left)
        assert.equals(
            ns.Color.Wrap(ns.Assets.Colors.WARNING, ns.Api.Equipment.GetSlotName(2)),
            shown[1][1].right
        )
        assert.equals(ns.L.GEAR_ALERT_LOW_LEVEL_ITEM, shown[1][2].left)
        assert.equals("|cffffffff|Hitem:11::::::::80:257::::::|h[Old Helm]|h|r", shown[1][2].right)
        assert.equals(ns.L.GEAR_ALERT_MISSING_TIER_SET, shown[1][3].left)
        assert.equals(
            ns.L.GEAR_ALERT_MISSING_TIER_SET_DETAIL:format(ns.Color.Wrap(ns.Assets.Colors.WARNING, "3/4")),
            shown[1][3].right
        )
        assert.is_true(toast.shown)
        assert.is_true(toast.raised)
    end)
end)

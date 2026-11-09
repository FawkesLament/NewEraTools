local Loader = require("helpers.loader")

local UI_PATH = "modules/combat/gear_alert/GearAlertUI.lua"

describe("GearAlert UI", function()
    local ns, GearAlert, section, created, toast, shown, originalCreateFrame
    local actionRow, statusLabel

    local function AttachUi()
        section = nil
        created = nil
        toast = nil
        shown = {}
        actionRow = nil
        statusLabel = nil
        ns.MainPanel = {
            RegisterSection = function(_, def)
                section = def
            end,
        }
        ns.CountToast = {
            Create = function(options)
                created = options
                toast = {
                    shown = false,
                    SetWindowPosition = function(self, position)
                        self.position = position
                    end,
                    SetToastText = function(_, title, message, count)
                        table.insert(shown, { title = title, message = message, count = count })
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
                actionRow = options
                statusLabel = {
                    text = options.description,
                    SetText = function(self, text)
                        self.text = text
                    end,
                    SetTextColor = function(self, r, g, b, a)
                        self.color = { r = r, g = g, b = b, a = a }
                    end,
                }
                return {}, statusLabel
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
        assert.equals(ns.L.GEAR_ALERT_MISSING_SET, actionRow.title)
        assert.equals(ns.L.GEAR_ALERT_HISTORY_NONE, actionRow.description)
        assert.is_nil(actionRow.buttons)
        assert.is_true(actionRow.enabled)

        actionRow.onEnabledChanged(false)
        assert.is_false(GearAlert:IsFourPieceCheckEnabled())
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
        assert.same({
            {
                title = ns.L.GEAR_ALERT_NOTIFICATION_TITLE,
                message = ns.L.GEAR_ALERT_MISSING_TIER_SET,
                count = ns.L.GEAR_ALERT_COUNT:format(3, 4),
            },
        }, shown)
        assert.is_true(toast.shown)
        assert.is_true(toast.raised)
        assert.equals(ns.L.GEAR_ALERT_HISTORY_DONE, statusLabel.text)
        assert.same(ns.Assets.Colors.SUCCESS, {
            r = statusLabel.color.r,
            g = statusLabel.color.g,
            b = statusLabel.color.b,
        })
    end)
end)

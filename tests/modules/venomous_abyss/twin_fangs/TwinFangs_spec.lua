local Loader = require("helpers.loader")

describe("TwinFangs", function()
    local ns, Module, Schema

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Schema = ns.Modules.Internals("TwinFangs").Schema
    end)

    it("registers with both reminders off", function()
        assert.is_false(Module == nil)
        assert.equals("table", type(Module.db))
        assert.is_false(Module:IsSoakReminderEnabled())
        assert.is_false(Module.db.soakReminder.enabled)
        assert.is_false(Module:IsInterruptReminderEnabled())
        assert.is_false(Module.db.interruptReminder.enabled)
        assert.is_false(Module:IsNameplateHintEnabled())
        assert.is_false(Module.db.nameplateHint.enabled)
        assert.equals(Schema.GROUP_LEFT, Module:GetSoakGroup())
        assert.is_true(Module:IsSoakTimelineEnabled())
    end)

    describe("raid role", function()
        it("is member unless the player is the raid leader", function()
            local Group = ns.Api.Group
            assert.equals(Module.RAID_ROLE_MEMBER, Module:GetRaidRole())
            assert.is_false(Module:IsRaidCommander())
            Group.isRaidLeader = true
            assert.equals(Module.RAID_ROLE_COMMANDER, Module:GetRaidRole())
            assert.is_true(Module:IsRaidCommander())
            Group.isRaidLeader = false
            assert.equals(Module.RAID_ROLE_MEMBER, Module:GetRaidRole())
            assert.is_false(Module:IsRaidCommander())
        end)
    end)

    it("toggles each reminder independently", function()
        Module:SetSoakReminderEnabled(true)
        assert.is_true(Module:IsSoakReminderEnabled())
        assert.is_true(Module.db.soakReminder.enabled)
        assert.is_false(Module:IsInterruptReminderEnabled())

        Module:SetInterruptReminderEnabled(true)
        assert.is_true(Module:IsInterruptReminderEnabled())
        assert.is_true(Module.db.interruptReminder.enabled)
        assert.is_true(Module:IsSoakReminderEnabled())

        Module:SetSoakReminderEnabled(false)
        assert.is_false(Module:IsSoakReminderEnabled())
        assert.is_false(Module.db.soakReminder.enabled)
        assert.is_true(Module:IsInterruptReminderEnabled())

        Module:SetSoakTimelineEnabled(false)
        assert.is_false(Module:IsSoakTimelineEnabled())
        Module:SetSoakTimelineEnabled(true)
        assert.is_true(Module:IsSoakTimelineEnabled())
    end)

    describe("nameplate hint", function()
        it("toggles independently of the interrupt reminder", function()
            assert.is_false(Module:IsNameplateHintEnabled())
            Module:SetNameplateHintEnabled(true)
            assert.is_true(Module:IsNameplateHintEnabled())
            assert.is_true(Module.db.nameplateHint.enabled)
            assert.is_false(Module:IsInterruptReminderEnabled())

            Module:SetInterruptReminderEnabled(true)
            Module:SetNameplateHintEnabled(false)
            assert.is_false(Module:IsNameplateHintEnabled())
            assert.is_true(Module:IsInterruptReminderEnabled())
        end)

        it("notifies the UI when the hint turns on or off", function()
            local calls = 0
            Module.OnNameplateHintChanged = function()
                calls = calls + 1
            end
            Module:SetNameplateHintEnabled(true)
            Module:SetNameplateHintEnabled(true)
            Module:SetInterruptReminderEnabled(true)
            Module:SetNameplateHintEnabled(false)
            assert.equals(2, calls)
        end)

        it("does not start a nameplate preview when the hint turns on", function()
            local previewCalls = 0
            Module.OnNameplateHintPreviewChanged = function()
                previewCalls = previewCalls + 1
            end
            Module:SetNameplateHintEnabled(true)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(0, previewCalls)
        end)

        it("previews nameplates only while the hint is on", function()
            local calls = 0
            Module.OnNameplateHintPreviewChanged = function()
                calls = calls + 1
            end
            Module:SetNameplateHintPreviewing(true)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(0, calls)

            Module:SetNameplateHintEnabled(true)
            Module:SetNameplateHintPreviewing(true)
            assert.is_true(Module:IsNameplateHintPreviewing())
            Module:SetNameplateHintPreviewing(true)
            assert.equals(1, calls)

            Module:SetNameplateHintPreviewing(false)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(2, calls)

            Module:SetNameplateHintEnabled(false)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(2, calls)
        end)

        it("defaults to a left badge at the current size, with no offset and full opacity", function()
            assert.equals(Schema.SIDE_LEFT, Module:GetNameplateHintSide())
            assert.equals(Schema.SIZE_DEFAULT, Module:GetNameplateHintSize())
            assert.equals(0, Module:GetNameplateHintOffsetX())
            assert.equals(0, Module:GetNameplateHintOffsetY())
            assert.equals(Schema.OPACITY_DEFAULT, Module:GetNameplateHintOpacity())
            assert.equals(Schema.FONT_DEFAULT, Module:GetNameplateHintFont())
            assert.equals(Schema.FONT_SIZE_DEFAULT, Module:GetNameplateHintFontSize())
            local fontColor = Module:GetNameplateHintFontColor()
            assert.equals(125 / 255, fontColor.r)
            assert.equals(214 / 255, fontColor.g)
            assert.equals(1, fontColor.b)
        end)

        it("saves side, size, offsets, opacity, font, font size, and font color", function()
            Module:SetNameplateHintSide(Schema.SIDE_TOP)
            Module:SetNameplateHintSize(40)
            Module:SetNameplateHintOffsetX(-12)
            Module:SetNameplateHintOffsetY(8)
            Module:SetNameplateHintOpacity(0.5)
            Module:SetNameplateHintFont("Custom Font")
            Module:SetNameplateHintFontSize(20)
            Module:SetNameplateHintFontColor({ r = 0.2, g = 0.4, b = 0.8 })
            assert.equals(Schema.SIDE_TOP, Module.db.nameplateHint.side)
            assert.equals(40, Module.db.nameplateHint.size)
            assert.equals(-12, Module.db.nameplateHint.offsetX)
            assert.equals(8, Module.db.nameplateHint.offsetY)
            assert.equals(0.5, Module.db.nameplateHint.opacity)
            assert.equals("Custom Font", Module.db.nameplateHint.font)
            assert.equals(20, Module.db.nameplateHint.fontSize)
            assert.equals(0.2, Module.db.nameplateHint.fontColor.r)
            assert.equals(0.4, Module.db.nameplateHint.fontColor.g)
            assert.equals(0.8, Module.db.nameplateHint.fontColor.b)
        end)

        it("clamps size, offsets, opacity, font size, and font color to their ranges", function()
            Module:SetNameplateHintSize(12)
            assert.equals(Schema.SIZE_MIN, Module:GetNameplateHintSize())
            Module:SetNameplateHintSize(100)
            assert.equals(Schema.SIZE_MAX, Module:GetNameplateHintSize())
            Module:SetNameplateHintOffsetX(-200)
            assert.equals(Schema.OFFSET_MIN, Module:GetNameplateHintOffsetX())
            Module:SetNameplateHintOffsetY(250)
            assert.equals(Schema.OFFSET_MAX, Module:GetNameplateHintOffsetY())
            Module:SetNameplateHintOpacity(0.1)
            assert.equals(Schema.OPACITY_MIN, Module:GetNameplateHintOpacity())
            Module:SetNameplateHintOpacity(2)
            assert.equals(Schema.OPACITY_MAX, Module:GetNameplateHintOpacity())
            Module:SetNameplateHintFontSize(2)
            assert.equals(Schema.FONT_SIZE_MIN, Module:GetNameplateHintFontSize())
            Module:SetNameplateHintFontSize(80)
            assert.equals(Schema.FONT_SIZE_MAX, Module:GetNameplateHintFontSize())
            Module:SetNameplateHintFontColor({ r = 2, g = -1, b = 0.5 })
            local clamped = Module:GetNameplateHintFontColor()
            assert.equals(1, clamped.r)
            assert.equals(0, clamped.g)
            assert.equals(0.5, clamped.b)
        end)

        it("rejects an empty font id", function()
            assert.is_false(pcall(Module.SetNameplateHintFont, Module, ""))
            assert.equals(Schema.FONT_DEFAULT, Module:GetNameplateHintFont())
        end)

        it("rejects a color that is not RGB", function()
            assert.is_false(pcall(Module.SetNameplateHintFontColor, Module, nil))
            assert.is_false(pcall(Module.SetNameplateHintFontColor, Module, { r = 1, g = 1 }))
            local expected = Schema.FONT_COLOR_DEFAULT
            local color = Module:GetNameplateHintFontColor()
            assert.equals(expected.r, color.r)
            assert.equals(expected.g, color.g)
            assert.equals(expected.b, color.b)
        end)

        it("rejects an unknown display position", function()
            assert.is_false(pcall(Module.SetNameplateHintSide, Module, "center"))
            assert.equals(Schema.SIDE_LEFT, Module:GetNameplateHintSide())
        end)

        it("notifies the UI when appearance settings change", function()
            local calls = 0
            Module.OnNameplateHintAppearanceChanged = function()
                calls = calls + 1
            end
            Module:SetNameplateHintSide(Schema.SIDE_RIGHT)
            Module:SetNameplateHintSide(Schema.SIDE_RIGHT)
            Module:SetNameplateHintSize(32)
            Module:SetNameplateHintSize(32)
            Module:SetNameplateHintOffsetX(4)
            Module:SetNameplateHintOffsetY(-4)
            Module:SetNameplateHintOpacity(0.8)
            Module:SetNameplateHintFont("Custom Font")
            Module:SetNameplateHintFontSize(18)
            Module:SetNameplateHintFontColor({ r = 1, g = 0, b = 0 })
            Module:SetNameplateHintFontColor({ r = 1, g = 0, b = 0 })
            Module:SetNameplateHintEnabled(true)
            assert.equals(8, calls)
        end)

        it("restores appearance without turning the hint off", function()
            Module:SetNameplateHintEnabled(true)
            Module:SetNameplateHintSide(Schema.SIDE_BOTTOM)
            Module:SetNameplateHintSize(48)
            Module:SetNameplateHintOffsetX(20)
            Module:SetNameplateHintOffsetY(-15)
            Module:SetNameplateHintOpacity(0.4)
            Module:SetNameplateHintFont("Custom Font")
            Module:SetNameplateHintFontSize(22)
            Module:SetNameplateHintFontColor({ r = 0, g = 1, b = 0 })
            Module:ResetNameplateHintAppearance()
            assert.is_true(Module:IsNameplateHintEnabled())
            assert.equals(Schema.SIDE_LEFT, Module:GetNameplateHintSide())
            assert.equals(Schema.SIZE_DEFAULT, Module:GetNameplateHintSize())
            assert.equals(0, Module:GetNameplateHintOffsetX())
            assert.equals(0, Module:GetNameplateHintOffsetY())
            assert.equals(Schema.OPACITY_DEFAULT, Module:GetNameplateHintOpacity())
            assert.equals(Schema.FONT_DEFAULT, Module:GetNameplateHintFont())
            assert.equals(Schema.FONT_SIZE_DEFAULT, Module:GetNameplateHintFontSize())
            local resetColor = Module:GetNameplateHintFontColor()
            assert.equals(Schema.FONT_COLOR_DEFAULT.r, resetColor.r)
            assert.equals(Schema.FONT_COLOR_DEFAULT.g, resetColor.g)
            assert.equals(Schema.FONT_COLOR_DEFAULT.b, resetColor.b)
        end)

        it("sanitizes a saved appearance on load", function()
            local ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = {
                    TwinFangs = {
                        nameplateHint = {
                            enabled = true,
                            side = "center",
                            size = 12,
                            offsetX = -400,
                            offsetY = 400,
                            opacity = 0.05,
                            font = "",
                            fontSize = 2,
                            fontColor = { r = 5, g = -2, b = 0.3 },
                        },
                    },
                },
            })
            ns.Modules.Start(saved)
            Module = ns.Modules.Get("TwinFangs")
            Schema = ns.Modules.Internals("TwinFangs").Schema
            assert.is_true(Module:IsNameplateHintEnabled())
            assert.equals(Schema.SIDE_LEFT, Module:GetNameplateHintSide())
            assert.equals(Schema.SIZE_MIN, Module:GetNameplateHintSize())
            assert.equals(Schema.OFFSET_MIN, Module:GetNameplateHintOffsetX())
            assert.equals(Schema.OFFSET_MAX, Module:GetNameplateHintOffsetY())
            assert.equals(Schema.OPACITY_MIN, Module:GetNameplateHintOpacity())
            assert.equals(Schema.FONT_DEFAULT, Module:GetNameplateHintFont())
            assert.equals(Schema.FONT_SIZE_MIN, Module:GetNameplateHintFontSize())
            local sanitizedColor = Module:GetNameplateHintFontColor()
            assert.equals(1, sanitizedColor.r)
            assert.equals(0, sanitizedColor.g)
            assert.equals(0.3, sanitizedColor.b)
        end)

        it("fills missing appearance fields from defaults", function()
            local ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = {
                    TwinFangs = { nameplateHint = { enabled = true } },
                },
            })
            ns.Modules.Start(saved)
            Module = ns.Modules.Get("TwinFangs")
            Schema = ns.Modules.Internals("TwinFangs").Schema
            assert.is_true(Module:IsNameplateHintEnabled())
            assert.equals(Schema.SIDE_LEFT, Module:GetNameplateHintSide())
            assert.equals(Schema.SIZE_DEFAULT, Module:GetNameplateHintSize())
            assert.equals(0, Module:GetNameplateHintOffsetX())
            assert.equals(0, Module:GetNameplateHintOffsetY())
            assert.equals(Schema.OPACITY_DEFAULT, Module:GetNameplateHintOpacity())
            assert.equals(Schema.FONT_DEFAULT, Module:GetNameplateHintFont())
            assert.equals(Schema.FONT_SIZE_DEFAULT, Module:GetNameplateHintFontSize())
            local filledColor = Module:GetNameplateHintFontColor()
            assert.equals(Schema.FONT_COLOR_DEFAULT.r, filledColor.r)
            assert.equals(Schema.FONT_COLOR_DEFAULT.g, filledColor.g)
            assert.equals(Schema.FONT_COLOR_DEFAULT.b, filledColor.b)
        end)
    end)

    describe("soak group", function()
        it("saves left, middle, and right", function()
            Module:SetSoakGroup(Schema.GROUP_MIDDLE)
            assert.equals(Schema.GROUP_MIDDLE, Module:GetSoakGroup())
            assert.equals(Schema.GROUP_MIDDLE, Module.db.soakReminder.group)

            Module:SetSoakGroup(Schema.GROUP_RIGHT)
            assert.equals(Schema.GROUP_RIGHT, Module:GetSoakGroup())

            Module:SetSoakGroup(Schema.GROUP_LEFT)
            assert.equals(Schema.GROUP_LEFT, Module:GetSoakGroup())
        end)

        it("rejects an unknown group", function()
            assert.is_false(pcall(Module.SetSoakGroup, Module, "center"))
            assert.equals(Schema.GROUP_LEFT, Module:GetSoakGroup())
        end)

        it("replaces a saved unknown group with left", function()
            local ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = {
                    TwinFangs = { soakReminder = { group = "center" } },
                },
            })
            ns.Modules.Start(saved)
            Module = ns.Modules.Get("TwinFangs")
            assert.equals(Schema.GROUP_LEFT, Module:GetSoakGroup())
        end)

        it("turns a saved non-boolean soak timeline flag into on", function()
            local fresh = Loader.Load()
            fresh.Modules.Start(fresh.Database.Load({
                modules = {
                    TwinFangs = { soakReminder = { timeline = "yes" } },
                },
            }))
            assert.is_true(fresh.Modules.Get("TwinFangs"):IsSoakTimelineEnabled())
        end)
    end)

    describe("interrupt status HUD position", function()
        it("defaults below center and persists a moved anchor", function()
            assert.same(Schema.DefaultInterruptStatusHudPosition(), Module:GetInterruptStatusHudPosition())
            local position = { point = "TOP", relativePoint = "TOP", x = 12, y = -40 }
            Module:SetInterruptStatusHudPosition(position)
            assert.same(position, Module.db.interruptStatusHudPosition)
            assert.equals(Module.db.interruptStatusHudPosition, Module:GetInterruptStatusHudPosition())

            local reloaded = Loader.Load()
            reloaded.Modules.Start(ns.Database.Load({
                modules = {
                    TwinFangs = { interruptStatusHudPosition = position },
                },
            }))
            assert.same(position, reloaded.Modules.Get("TwinFangs"):GetInterruptStatusHudPosition())
        end)

        it("replaces an invalid saved position with the factory anchor", function()
            local fresh = Loader.Load()
            fresh.Modules.Start(fresh.Database.Load({
                modules = {
                    TwinFangs = {
                        interruptStatusHudPosition = {
                            point = "CENTER",
                            relativePoint = "CENTER",
                            x = "bad",
                            y = 0,
                        },
                    },
                },
            }))
            assert.same(
                fresh.Modules.Internals("TwinFangs").Schema.DefaultInterruptStatusHudPosition(),
                fresh.Modules.Get("TwinFangs"):GetInterruptStatusHudPosition()
            )
        end)

        it("adopts a leftover statusHudPosition key", function()
            local position = { point = "TOP", relativePoint = "TOP", x = 4, y = -8 }
            local fresh = Loader.Load()
            fresh.Modules.Start(fresh.Database.Load({
                modules = {
                    TwinFangs = { statusHudPosition = position },
                },
            }))
            local module = fresh.Modules.Get("TwinFangs")
            assert.same(position, module:GetInterruptStatusHudPosition())
            assert.is_nil(module.db.statusHudPosition)
        end)
    end)
end)

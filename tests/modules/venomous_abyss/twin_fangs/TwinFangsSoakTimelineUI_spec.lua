local Loader = require("helpers.loader")

local SOAK_TIMELINE_UI_PATH = "modules/venomous_abyss/twin_fangs/ui/SoakTimeline.lua"

describe("TwinFangs soak timeline UI", function()
    local ns, Module, L, originalCreateFrame, registered, onScaleChanged

    local function FakeLabel(parent)
        local label = { parent = parent, text = "", shown = true }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint() end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:SetTextColor() end
        function label:SetFont() end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        return label
    end

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            scripts = {},
            width = 0,
            height = 0,
            frameLevel = 1,
            scale = 1,
        }
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
        function frame:GetFrameLevel()
            return self.frameLevel
        end
        function frame:SetFrameLevel(level)
            self.frameLevel = level
        end
        function frame:SetScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale
        end
        function frame:ClearAllPoints() end
        function frame:SetPoint() end
        function frame:SetAllPoints() end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetTexture() end
        function frame:SetVertexColor(r, g, b, a)
            self.vertexColor = { r = r, g = g, b = b, a = a }
        end
        function frame:AddMaskTexture() end
        function frame:CreateFontString()
            return FakeLabel(self)
        end
        function frame:CreateTexture()
            return FakeFrame(self)
        end
        function frame:CreateMaskTexture()
            local mask = FakeFrame(self)
            function mask:SetTexture() end
            return mask
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
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
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        registered = {}
        onScaleChanged = nil
        CreateFrame = function()
            return FakeFrame()
        end
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        L = ns.L
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            CreateSurface = function(parent)
                return FakeFrame(parent)
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
        }
        ns.MainPanel = {
            GetScale = function()
                return 1
            end,
            OnScaleChanged = function(callback)
                onScaleChanged = callback
            end,
        }
        assert(loadfile(SOAK_TIMELINE_UI_PATH))(Loader.ADDON_NAME, ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function Binding()
        return ns.Modules.Internals("TwinFangs").SoakTimelineUI
    end

    it("registers a movable Twin Fangs element and stays hidden until Edit Mode", function()
        local binding = Binding()
        local frame = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        assert.equals("TwinFangs:soakTimeline", binding.LAYOUT_ID)
        assert.equals(L.TWIN_FANGS_SOAK_TIMELINE, def.label)
        assert.is_false(def.global)
        assert.is_false(def.isEnabled())
        Module:SetSoakReminderEnabled(true)
        assert.is_true(def.isEnabled())
        Module:SetSoakTimelineEnabled(false)
        assert.is_false(def.isEnabled())
        Module:SetSoakTimelineEnabled(true)
        assert.is_true(def.isEnabled())
        assert.is_false(frame.shown)
        assert.is_nil(frame.scripts.OnUpdate)
        assert.same(Module:GetSoakTimelinePosition(), frame.position)
    end)

    it("loops the preview while Twin Fangs Edit Mode is open and stops when it ends", function()
        local binding = Binding()
        local frame = binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        def.onEditBegin()
        assert.is_true(frame.shown)
        assert.equals("function", type(frame.scripts.OnUpdate))

        local SoakTimeline = ns.Modules.Internals("TwinFangs").SoakTimeline
        local Timer = ns.Api.Timer
        Timer.Advance(SoakTimeline.DURATION)
        frame.scripts.OnUpdate(frame)
        Timer.Advance(SoakTimeline.LOOP)
        frame.scripts.OnUpdate(frame)

        def.onEditEnd()
        assert.is_false(frame.shown)
        assert.is_nil(frame.scripts.OnUpdate)
    end)

    it("follows the addon UI scale", function()
        ns.MainPanel.GetScale = function()
            return 1.25
        end
        local frame = Binding().Ensure()
        assert.equals(1.25, frame.scale)
        assert.equals("function", type(onScaleChanged))
        onScaleChanged(0.8)
        assert.equals(0.8, frame.scale)
        assert.same(Module:GetSoakTimelinePosition(), frame.position)
    end)

    it("shows a live feast sequence and hides after hit 3", function()
        Module:SetSoakReminderEnabled(true)
        local Timer = ns.Api.Timer
        local SoakTimeline = ns.Modules.Internals("TwinFangs").SoakTimeline
        local frame = Binding().Ensure()
        local beginAt = Timer.GetTime()
        Module:StartSoakTimeline(beginAt)
        assert.is_true(frame.shown)
        assert.equals("function", type(frame.scripts.OnUpdate))

        Timer.Advance(SoakTimeline.DURATION - 0.01)
        frame.scripts.OnUpdate(frame)
        assert.is_true(frame.shown)

        Timer.Advance(0.01)
        frame.scripts.OnUpdate(frame)
        assert.is_false(frame.shown)
        assert.is_nil(frame.scripts.OnUpdate)
    end)

    it("rings the assigned hit from the player's soak group and keeps the numbered nodes", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        Module:SetSoakGroup(Schema.GROUP_MIDDLE)
        local frame = Binding().Ensure()
        local def = registered[Binding().LAYOUT_ID]
        def.onEditBegin()
        frame.scripts.OnUpdate(frame)

        local function Rings()
            local shown = {}
            for index = 1, 3 do
                local node = frame.hitNodes[index]
                shown[index] = node.ringFrame.shown == true
                assert.equals(node.ringFrame.shown == true, node.arrow.shown == true)
                assert.equals(ns.Assets.Glyphs.SORT_DESC, node.arrow:GetText())
                assert.equals(tostring(index), node.label:GetText())
            end
            return shown
        end

        assert.same({ false, false, true }, Rings())
        assert.equals(24, frame.hitNodes[3].nodeFrame.width)
        assert.equals(22, frame.hitNodes[1].nodeFrame.width)

        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        frame.scripts.OnUpdate(frame)
        assert.same({ true, false, false }, Rings())

        local SoakTimeline = ns.Modules.Internals("TwinFangs").SoakTimeline
        local Timer = ns.Api.Timer
        Timer.Advance(SoakTimeline.HIT_AT[1])
        frame.scripts.OnUpdate(frame)
        assert.same({ true, false, false }, Rings())
        assert.equals(0.95, frame.hitNodes[1].fill.vertexColor.r)
        assert.equals(0.93, frame.hitNodes[1].ring.vertexColor.r)
        Timer.Advance(SoakTimeline.FLASH)
        frame.scripts.OnUpdate(frame)
        assert.same({ true, false, false }, Rings())
        assert.equals(0.86, frame.hitNodes[1].fill.vertexColor.r)
        Timer.Advance(SoakTimeline.LOOP - SoakTimeline.HIT_AT[1] - SoakTimeline.FLASH)
        frame.scripts.OnUpdate(frame)
        assert.same({ true, false, false }, Rings())
        assert.equals(125 / 255, frame.hitNodes[1].fill.vertexColor.r)
    end)

    it("keeps the gold ring when the assigned hit is also the live boss hit", function()
        Module:SetSoakReminderEnabled(true)
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        local frame = Binding().Ensure()
        Module:StartSoakTimeline(ns.Api.Timer.GetTime(), 1)
        frame.scripts.OnUpdate(frame)
        assert.is_true(frame.hitNodes[1].ringFrame.shown)
        assert.is_true(frame.hitNodes[1].arrow.shown)
        assert.is_false(frame.hitNodes[2].ringFrame.shown)
        assert.is_false(frame.hitNodes[2].arrow.shown)
        local fill = frame.hitNodes[1].fill.vertexColor
        assert.equals(125 / 255, fill.r)
        assert.equals(214 / 255, fill.g)
        assert.equals(0.93, frame.hitNodes[1].ring.vertexColor.r)
    end)

    it("repositions through the Twin Fangs layout element", function()
        local binding = Binding()
        binding.Ensure()
        local def = registered[binding.LAYOUT_ID]
        local nextPosition = { point = "BOTTOM", relativePoint = "BOTTOM", x = 6, y = 18 }
        def.setPosition(nextPosition)
        assert.same(nextPosition, Module:GetSoakTimelinePosition())
        assert.same(
            ns.Modules.Internals("TwinFangs").Schema.DefaultSoakTimelinePosition(),
            def.getDefaultPosition()
        )
    end)
end)

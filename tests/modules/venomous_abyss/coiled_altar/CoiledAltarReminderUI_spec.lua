local Loader = require("helpers.loader")

local PANEL_PATH = "modules/venomous_abyss/coiled_altar/CoiledAltarUI.lua"
local LAYOUT_PATH = "ui/Layout.lua"

describe("CoiledAltar mechanic reminder layout", function()
    local ns, Module, L, originalCreateFrame, originalGameTooltip
    local section
    local sections
    local boxes
    local page

    local function LeftAnchor(region)
        return region.points and region.points.LEFT
    end

    local function FakeFrame(parent, frameType)
        local frame = {
            parent = parent,
            frameType = frameType or "Frame",
            shown = true,
            enabled = true,
            alpha = 1,
            width = 0,
            height = 0,
            points = {},
            children = {},
            textures = {},
            fontStrings = {},
            scripts = {},
            hooks = {},
        }

        function frame:RegisterForClicks() end
        function frame:EnableMouse() end
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            if type(relativeTo) == "string" then
                relativePoint, x, y = relativeTo, relativePoint, x
                relativeTo = self.parent
            end
            self.points[point] = {
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            }
        end
        function frame:SetAllPoints(relativeTo)
            self:SetPoint("TOPLEFT", relativeTo or self.parent, "TOPLEFT")
            self:SetPoint("BOTTOMRIGHT", relativeTo or self.parent, "BOTTOMRIGHT")
        end
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
        function frame:SetShown(shown)
            self.shown = shown == true
        end
        function frame:IsShown()
            return self.shown == true
        end
        function frame:IsVisible()
            return self.shown == true
        end
        function frame:SetParent(parentFrame)
            self.parent = parentFrame
        end
        function frame:GetParent()
            return self.parent
        end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        function frame:Enable()
            self.enabled = true
        end
        function frame:Disable()
            self.enabled = false
        end
        function frame:IsEnabled()
            return self.enabled == true
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:HookScript(name, handler)
            self.hooks[name] = self.hooks[name] or {}
            self.hooks[name][#self.hooks[name] + 1] = handler
        end
        function frame:SetText(text)
            self.text = text
        end
        function frame:GetText()
            return self.text or ""
        end
        function frame:GetTextWidth()
            return 48
        end
        function frame:SetTextColor() end
        function frame:SetJustifyH() end
        function frame:SetJustifyV() end
        function frame:SetWordWrap() end
        function frame:SetHitRectInsets(left, right, top, bottom)
            self.hitRect = { left, right, top, bottom }
        end
        function frame:SetContentHeight(height)
            self.contentHeight = height
        end
        function frame:SetHeaderAction(action)
            self.headerAction = action
        end
        function frame:CreateTexture()
            local texture = FakeFrame(self, "Texture")
            texture.parent = self
            self.textures[#self.textures + 1] = texture
            -- Textures must not appear in GetChildren.
            if self.children[#self.children] == texture then
                self.children[#self.children] = nil
            end
            function texture:SetTexture(path)
                self.texture = path
            end
            function texture:SetTexCoord(left, right, top, bottom)
                self.texCoord = { left, right, top, bottom }
            end
            function texture:SetVertexColor() end
            function texture:SetColorTexture() end
            return texture
        end
        function frame:CreateFontString()
            local label = FakeFrame(self, "FontString")
            if self.children[#self.children] == label then
                self.children[#self.children] = nil
            end
            self.fontStrings[#self.fontStrings + 1] = label
            label.text = ""
            function label:SetText(text)
                self.text = text
            end
            function label:GetText()
                return self.text
            end
            function label:GetStringWidth()
                return #(self.text or "") * 6
            end
            function label:GetStringHeight()
                return 12
            end
            return label
        end

        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        return frame
    end

    local function FakeButton(parent, text)
        local button = FakeFrame(parent, "Button")
        button.text = text
        function button:SetText(value)
            self.text = value
        end
        return button
    end

    local function FakeCheckbox(parent)
        local box = FakeFrame(parent, "CheckButton")
        box.checked = false
        function box:SetChecked(value)
            self.checked = value == true
        end
        function box:GetChecked()
            return self.checked == true
        end
        function box:Click()
            if not self.enabled then
                return
            end
            self.checked = not self.checked
            if self.scripts.OnClick then
                self.scripts.OnClick(self)
            end
        end
        boxes[#boxes + 1] = box
        return box
    end

    local function FindSection(title)
        for _, created in ipairs(sections) do
            if created.title == title then
                return created
            end
        end
    end

    local function AttachUi()
        section = nil
        sections = {}
        boxes = {}
        GameTooltip = {
            SetOwner = function() end,
            SetSpellByID = function() end,
            Show = function() end,
            Hide = function() end,
            SetText = function() end,
        }
        CreateFrame = function(frameType, _, parent)
            return FakeFrame(parent, frameType)
        end
        assert(loadfile(LAYOUT_PATH))(Loader.ADDON_NAME, ns)

        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a or 1
            end,
            CreateLabel = function(parent, _, text)
                local label = parent:CreateFontString()
                label:SetText(text or "")
                return label
            end,
            CreateButton = function(parent, text)
                return FakeButton(parent, text)
            end,
            CreateTextButton = function(parent, text)
                return FakeButton(parent, text)
            end,
            CreateLayoutEditButton = function(parent, text)
                return FakeButton(parent, text)
            end,
            AttachTooltip = function() end,
            CreateSegmentedControl = function(parent)
                local control = FakeFrame(parent)
                function control:SetSelected() end
                return control
            end,
        }
        ns.FeatureSection = {
            Create = function(stack, options)
                local created = FakeFrame(stack.container)
                created.title = options.title
                created.content = FakeFrame(created)
                function created:SetContentHeight(height)
                    self.contentHeight = height
                end
                function created:RefreshContentInteractive() end
                function created:SetHeaderAction() end
                stack:Add(created, 40)
                sections[#sections + 1] = created
                return created
            end,
        }
        ns.Checkbox = {
            Create = FakeCheckbox,
        }
        ns.Slider = {
            Create = function(parent)
                local slider = FakeFrame(parent)
                slider.valueBox = FakeFrame(slider)
                slider.valueSuffix = nil
                function slider:SetValue() end
                return slider
            end,
        }
        ns.NumberStepper = {
            Create = function(parent)
                local stepper = FakeFrame(parent)
                function stepper:SetValue() end
                return stepper
            end,
        }
        ns.RaidRoleModeLabel = {
            HEIGHT = 16,
            Create = function(parent)
                return FakeFrame(parent)
            end,
            Update = function() end,
        }
        ns.AddonCheckPanel = {
            Create = function()
                return {
                    Show = function() end,
                    Hide = function() end,
                }
            end,
        }
        ns.Callout = {
            LAYOUT_ID = "Callout:1",
            Ensure = function() end,
            SetScopePreview = function() end,
        }
        ns.LayoutEditor = {
            RegisterScope = function() end,
            BeginScope = function() end,
            IsEditing = function()
                return false
            end,
            Refresh = function() end,
        }
        ns.MainPanel = {
            RegisterSection = function(_, def)
                section = def
            end,
            GetFrame = function() end,
        }
        local internals = ns.Modules.Internals("CoiledAltar")
        internals.InterruptRotationTrackerUI = {
            LAYOUT_ID = "CoiledAltar:interrupt",
            Ensure = function() end,
            Update = function() end,
        }
        internals.InterruptAssignmentsUI = {
            Mount = function() end,
            Refresh = function() end,
            SetShown = function() end,
        }
        internals.InterruptAssignmentsMemberView = {
            Mount = function() end,
            Refresh = function() end,
            SetShown = function() end,
        }
        assert(loadfile(PANEL_PATH))(Loader.ADDON_NAME, ns)
        Module:OnEnable()
    end

    local function BuildPage()
        page = FakeFrame()
        page.header = FakeFrame(page)
        page.shown = false
        section.build(page)
        return FindSection(L.COILED_ALTAR_MECHANIC_REMINDER)
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalGameTooltip = GameTooltip
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        L = ns.L
        AttachUi()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        GameTooltip = originalGameTooltip
    end)

    it("places single-toggle checkboxes to the right of a fixed-width spell hint", function()
        local reminder = BuildPage()
        local reminderRow = reminder.content.children[1]
        local interruptCell, ghostCell = reminderRow.children[1], reminderRow.children[2]
        local interruptHint = interruptCell.children[2]
        local ghostHint = ghostCell.children[2]

        assert.equals(100, interruptHint.width)
        assert.equals(100, ghostHint.width)
        assert.equals(ns.Assets.Sizes.CONTROL_ROW_HEIGHT, interruptHint.height)

        local interruptBox = boxes[1]
        local ghostBox = boxes[2]
        local interruptAnchor = LeftAnchor(interruptBox)
        local ghostAnchor = LeftAnchor(ghostBox)
        assert(interruptAnchor, "interrupt checkbox is not LEFT-anchored")
        assert.equals("RIGHT", interruptAnchor.relativePoint)
        assert.equals(0, interruptAnchor.x)
        assert(
            interruptAnchor.relativeTo == interruptHint,
            "interrupt checkbox should sit to the right of the spell hint"
        )
        assert(ghostAnchor, "ghost checkbox is not LEFT-anchored")
        assert.equals("RIGHT", ghostAnchor.relativePoint)
        assert.equals(0, ghostAnchor.x)
        assert(ghostAnchor.relativeTo == ghostHint, "ghost checkbox should sit to the right of the spell hint")
    end)

    it("aligns the first-row second column with the nameplate card split", function()
        local reminder = BuildPage()
        local nameplate = FindSection(L.COILED_ALTAR_NAMEPLATE_HINT)
        local ghostCell = reminder.content.children[1].children[2]
        local scaleCell = nameplate.content.children[1].children[2]
        local ghostStart = ghostCell.points.LEFT
        local scaleStart = scaleCell.points.LEFT
        assert.equals("CENTER", ghostStart.relativePoint)
        assert.equals(scaleStart.relativePoint, ghostStart.relativePoint)
        assert.equals(scaleStart.x, ghostStart.x)
        assert.equals(ns.Assets.Spacing.MEDIUM / 2, ghostStart.x)
    end)

    it("keeps orb-carry phase checkboxes on the interrupt checkbox column with check-to-label clearance", function()
        local reminder = BuildPage()
        local orbRow = reminder.content.children[3]
        local orbHint = orbRow.children[1]
        local oddGroup = orbRow.children[2]
        local evenGroup = orbRow.children[3]
        local p3Group = orbRow.children[4]
        local oddAnchor = LeftAnchor(oddGroup)
        local evenAnchor = LeftAnchor(evenGroup)
        local p3Anchor = LeftAnchor(p3Group)

        assert.equals(100, orbHint.width)
        assert(oddAnchor, "odd-wave group is not LEFT-anchored")
        assert.equals("RIGHT", oddAnchor.relativePoint)
        assert.equals(0, oddAnchor.x)
        assert(oddAnchor.relativeTo == orbHint, "odd-wave checkbox should share the interrupt checkbox column")
        assert(evenAnchor.relativeTo == oddGroup, "even-wave group should follow the odd-wave group")
        assert.equals(20, evenAnchor.x)
        assert(p3Anchor.relativeTo == evenGroup, "P3 group should follow the even-wave group")
        assert.equals(20, p3Anchor.x)

        local oddBox = oddGroup.children[1]
        local oddLabel = oddGroup.fontStrings[1]
        local labelAnchor = LeftAnchor(oddLabel)
        assert(labelAnchor.relativeTo == oddBox, "phase label should sit to the right of its checkbox")
        assert.equals(10, labelAnchor.x)
        local labelWidth = oddLabel:GetStringWidth()
        assert.same({ 0, -(labelWidth + 10), 0, 0 }, oddBox.hitRect)
        assert.equals(ns.Assets.Sizes.CHECKBOX + 10 + labelWidth, oddGroup.width)
    end)

    it("crops spell icons to 20px with a dark 1px edge", function()
        local reminder = BuildPage()
        local interruptHint = reminder.content.children[1].children[1].children[2]
        local iconHolder = interruptHint.children[1]
        assert.equals(20, iconHolder.width)
        assert.equals(20, iconHolder.height)
        assert.same({ 0.08, 0.92, 0.08, 0.92 }, iconHolder.textures[1].texCoord)
        assert.equals(5, #iconHolder.textures)
        local nameAnchor = LeftAnchor(interruptHint.fontStrings[1])
        assert(nameAnchor.relativeTo == iconHolder, "mechanic name should sit to the right of the spell icon")
        assert.equals("RIGHT", nameAnchor.relativePoint)
        assert.equals(8, nameAnchor.x)
    end)

    it("preserves reminder saved-variable toggles from checkbox and spell-hint clicks", function()
        BuildPage()
        local interruptBox, ghostBox, vulnBox, oddBox = boxes[1], boxes[2], boxes[3], boxes[4]
        assert.equals(11, #boxes)
        assert.is_true(Module:IsInterruptReminderEnabled())
        assert.equals("function", type(interruptBox.scripts.OnClick))
        interruptBox:Click()
        assert.is_false(Module:IsInterruptReminderEnabled())
        local interruptHint = interruptBox.parent.children[2]
        interruptHint.scripts.OnClick(interruptHint)
        assert.is_true(Module:IsInterruptReminderEnabled())

        ghostBox:Click()
        assert.is_true(Module:IsGhostChaseReminderEnabled())
        vulnBox:Click()
        assert.is_true(Module:IsVulnerabilityReminderEnabled())
        oddBox:Click()
        assert.is_true(Module:IsOrbCarryOddReminderEnabled())
        boxes[5]:Click()
        assert.is_true(Module:IsOrbCarryEvenReminderEnabled())
        boxes[6]:Click()
        assert.is_true(Module:IsOrbCarryP3ReminderEnabled())
        boxes[7]:Click()
        assert.is_true(Module:IsSoakP1FirstReminderEnabled())
        boxes[8]:Click()
        assert.is_true(Module:IsSoakP1SecondReminderEnabled())
        boxes[9]:Click()
        assert.is_true(Module:IsSoakP3FirstReminderEnabled())
        boxes[10]:Click()
        assert.is_true(Module:IsSoakP3SecondReminderEnabled())
        boxes[11]:Click()
        assert.is_true(Module:IsSoakP3ThirdReminderEnabled())
    end)

    it("wraps soak phase checkboxes under the interrupt checkbox column", function()
        local reminder = BuildPage()
        local soakP1Row = reminder.content.children[4]
        local soakP3Row = reminder.content.children[5]
        local soakHint = soakP1Row.children[1]
        local p1First = soakP1Row.children[2]
        local p1Second = soakP1Row.children[3]
        local soakIndent = soakP3Row.children[1]
        local p3First = soakP3Row.children[2]
        local p3Second = soakP3Row.children[3]
        local p1FirstAnchor = LeftAnchor(p1First)
        local p1SecondAnchor = LeftAnchor(p1Second)
        local p3FirstAnchor = LeftAnchor(p3First)
        local p3SecondAnchor = LeftAnchor(p3Second)

        assert.equals(100, soakHint.width)
        assert.equals(100, soakIndent.width)
        assert.equals(3, #soakP1Row.children)
        assert.equals(4, #soakP3Row.children)
        assert(p1FirstAnchor.relativeTo == soakHint, "P1 soak checkboxes should share the interrupt checkbox column")
        assert.equals("RIGHT", p1FirstAnchor.relativePoint)
        assert.equals(0, p1FirstAnchor.x)
        assert(p1SecondAnchor.relativeTo == p1First, "P1 soak groups should follow one another")
        assert.equals(20, p1SecondAnchor.x)
        assert(p3FirstAnchor.relativeTo == soakIndent, "P3 soak checkboxes should line up under P1")
        assert.equals("RIGHT", p3FirstAnchor.relativePoint)
        assert.equals(0, p3FirstAnchor.x)
        assert(p3SecondAnchor.relativeTo == p3First, "P3 soak groups should follow one another")
        assert.equals(20, p3SecondAnchor.x)

        local firstBox = p1First.children[1]
        local firstLabel = p1First.fontStrings[1]
        local labelAnchor = LeftAnchor(firstLabel)
        assert(labelAnchor.relativeTo == firstBox, "phase label should sit to the right of its checkbox")
        assert.equals(10, labelAnchor.x)
        local labelWidth = firstLabel:GetStringWidth()
        assert.same({ 0, -(labelWidth + 10), 0, 0 }, firstBox.hitRect)
        assert.equals(ns.Assets.Sizes.CHECKBOX + 10 + labelWidth, p1First.width)
    end)

    it("sizes the reminder body to five compact form rows", function()
        local reminder = BuildPage()
        local rowHeight = ns.Assets.Sizes.CONTROL_ROW_HEIGHT
        local pad = ns.Assets.Spacing.SMALL
        assert.equals(
            pad + rowHeight + pad + rowHeight + pad + rowHeight + pad + rowHeight + pad + rowHeight + pad,
            reminder.contentHeight
        )
    end)
end)

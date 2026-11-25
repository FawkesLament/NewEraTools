describe("AlertToast", function()
    local ns, originalCreateFrame, created, lastWindow, scaleListener

    local function FakeTexture()
        local texture = { points = {}, shown = true }
        function texture:SetColorTexture(r, g, b, a)
            self.filled = true
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:SetHeight(height)
            self.height = height
        end
        function texture:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function texture:SetAllPoints()
            self.allPoints = true
        end
        function texture:SetPoint(...)
            self.points[#self.points + 1] = { ... }
        end
        function texture:ClearAllPoints()
            self.points = {}
        end
        function texture:Show()
            self.shown = true
        end
        function texture:Hide()
            self.shown = false
        end
        lastWindow.textures[#lastWindow.textures + 1] = texture
        return texture
    end

    local function FakeLabel()
        local label = { text = "", points = {}, font = {}, shown = true }
        function label:SetFont(path, size, flags)
            self.font = { path = path, size = size, flags = flags }
        end
        function label:SetText(value)
            self.text = value
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function label:SetShadowOffset() end
        function label:SetJustifyH(value)
            self.justifyH = value
        end
        function label:SetJustifyV() end
        function label:SetShadowColor() end
        function label:SetWordWrap() end
        function label:SetMaxLines(value)
            self.maxLines = value
        end
        function label:SetWidth(width)
            self.width = width
        end
        function label:GetStringWidth()
            return #self.text * 6
        end
        function label:SetPoint(...)
            self.points[#self.points + 1] = { ... }
        end
        function label:ClearAllPoints()
            self.points = {}
        end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        lastWindow.labels[#lastWindow.labels + 1] = label
        return label
    end

    local function FakeWindow(options)
        created = created + 1
        local frame = {
            shown = false,
            options = options,
            size = {},
            labels = {},
            textures = {},
            header = {
                SetHeight = function(self, height)
                    self.height = height
                end,
            },
        }
        function frame:CreateTexture()
            return FakeTexture()
        end
        function frame:CreateFontString()
            return FakeLabel()
        end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetSize(width, height)
            self.size = { width = width, height = height }
        end
        function frame:GetFrameLevel()
            return 1
        end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:CreateAnimationGroup()
            local group = { playing = false, animations = {}, scripts = {} }
            function group:CreateAnimation(kind)
                local anim = { kind = kind }
                function anim:SetFromAlpha(value)
                    self.fromAlpha = value
                end
                function anim:SetToAlpha(value)
                    self.toAlpha = value
                end
                function anim:SetDuration(value)
                    self.duration = value
                end
                function anim:SetSmoothing(value)
                    self.smoothing = value
                end
                function anim:SetOffset(x, y)
                    self.offsetX = x
                    self.offsetY = y
                end
                group.animations[#group.animations + 1] = anim
                return anim
            end
            function group:SetToFinalAlpha(enabled)
                self.toFinalAlpha = enabled
            end
            function group:SetScript(event, handler)
                self.scripts[event] = handler
            end
            function group:IsPlaying()
                return self.playing == true
            end
            function group:Stop()
                self.playing = false
            end
            function group:Play()
                self.playing = true
            end
            frame.animGroups[#frame.animGroups + 1] = group
            return group
        end
        function frame:SetWindowPosition(position)
            self.position = position
        end
        function frame:SetWindowScale(scale)
            self.scale = scale
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
        function frame:Raise()
            self.raised = true
        end
        frame.animGroups = {}
        lastWindow = frame
        return frame
    end

    local function CreateOptions(overrides)
        local options = {
            name = "NewEraToolsAlertToast",
            title = "Gear Alert",
        }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        return options
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        created = 0
        lastWindow = nil
        scaleListener = nil
        ns = {
            ADDON_NAME = "NewEraTools",
            Assets = {
                FontFiles = { EXPRESSWAY = "Interface\\AddOns\\NewEraTools\\media\\fonts\\Expressway.ttf" },
                Textures = { WHITE = "white" },
                Templates = { BACKDROP = "BackdropTemplate" },
                Colors = {
                    FEATURE_CARD_BG = { r = 0.125, g = 0.149, b = 0.192, a = 1 },
                    FEATURE_CARD_BORDER = { r = 0.220, g = 0.238, b = 0.280, a = 1 },
                    MENU_TITLE_BAR = { r = 0.055, g = 0.067, b = 0.086, a = 1 },
                    DIVIDER = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
                    TEXT = { r = 1, g = 1, b = 1 },
                    TEXT_MUTED = { r = 0.55, g = 0.57, b = 0.60 },
                    WARNING = { r = 0.95, g = 0.64, b = 0.27 },
                    DANGER = { r = 0.91, g = 0.44, b = 0.37 },
                },
                Sizes = { CLOSE_BUTTON = 22 },
                Spacing = { SMALL = 4, MEDIUM = 8, LARGE = 12 },
            },
            Widgets = {
                UnpackColor = function(color)
                    return color.r, color.g, color.b, color.a
                end,
                ApplyBackdrop = function() end,
                CreateCloseButton = function(_, onClick)
                    lastWindow.closeOnClick = onClick
                    lastWindow.closeButton = {
                        SetPoint = function() end,
                        ClearAllPoints = function() end,
                        SetFrameLevel = function() end,
                        SetSize = function(self, width, height)
                            self.size = { width = width, height = height }
                        end,
                        SetScript = function() end,
                        GetRegions = function()
                            return
                        end,
                    }
                    return lastWindow.closeButton
                end,
            },
            FloatingWindow = {
                Create = FakeWindow,
            },
            MainPanel = {
                GetScale = function()
                    return 1.25
                end,
                OnScaleChanged = function(callback)
                    scaleListener = callback
                end,
            },
        }
        assert(loadfile("ui/AlertToast.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("rejects incomplete Create options", function()
        assert.is_false(pcall(ns.AlertToast.Create))
        assert.is_false(pcall(ns.AlertToast.Create, {}))
        assert.is_false(pcall(ns.AlertToast.Create, { title = 1 }))
    end)

    it("sizes the card to the current row count", function()
        local toast = ns.AlertToast.Create(CreateOptions())
        assert.equals(1, created)
        assert.equals("Gear Alert", lastWindow.labels[1].text)
        assert.equals(260, lastWindow.size.width)
        assert.equals(39, lastWindow.size.height)
        assert.equals(26, lastWindow.header.height)
        assert.equals(16, lastWindow.closeButton.size.width)

        toast:SetRows({
            {
                label = "Set",
                detail = "Need Shoulder, Hands",
                status = "3/4",
                severity = "warning",
            },
        })
        assert.equals(1, created)
        assert.equals("Set", lastWindow.labels[2].text)
        assert.equals("Need Shoulder, Hands", lastWindow.labels[3].text)
        assert.equals("3/4", lastWindow.labels[4].text)
        assert.is_true(lastWindow.labels[3].shown)
        assert.equals(63, lastWindow.size.height)

        toast:SetRows({
            { label = "A", status = "1", severity = "danger" },
            { label = "B", detail = "Two", status = "2", severity = "warning" },
        })
        assert.equals("A", lastWindow.labels[2].text)
        assert.is_false(lastWindow.labels[3].shown)
        assert.equals("B", lastWindow.labels[5].text)
        assert.equals("Two", lastWindow.labels[6].text)
        assert.is_true(lastWindow.labels[6].shown)
        assert.equals(87, lastWindow.size.height)

        toast:SetRows({
            { label = "Only", status = "one", severity = "danger" },
        })
        assert.equals("Only", lastWindow.labels[2].text)
        assert.is_false(lastWindow.labels[5].shown)
        assert.equals(63, lastWindow.size.height)
    end)

    it("rejects non-string row text", function()
        local toast = ns.AlertToast.Create(CreateOptions())
        assert.is_false(pcall(toast.SetRows, toast, nil))
        assert.is_false(pcall(toast.SetRows, toast, { { status = "t" } }))
        assert.is_false(pcall(toast.SetRows, toast, { { label = "t", status = 3 } }))
        assert.is_false(pcall(toast.SetRows, toast, { { label = "t", status = "ok" } }))
        assert.is_false(pcall(toast.SetRows, toast, { { label = "t", status = "ok", severity = "info" } }))
    end)

    it("hides on close after the fade finishes and can be shown again", function()
        local toast = ns.AlertToast.Create(CreateOptions())
        toast:PlayIn()
        assert.is_true(lastWindow.shown)
        assert.is_true(lastWindow.animGroups[1].playing)
        lastWindow.closeOnClick()
        assert.is_false(lastWindow.animGroups[1].playing)
        assert.is_true(lastWindow.animGroups[2].playing)
        assert.is_true(lastWindow.shown)
        lastWindow.animGroups[2].playing = false
        lastWindow.animGroups[2].scripts.OnFinished()
        assert.is_false(lastWindow.shown)
        toast:PlayIn()
        assert.equals(1, created)
        assert.is_true(lastWindow.shown)
        assert.is_true(lastWindow.animGroups[1].playing)
        assert.is_false(lastWindow.animGroups[2].playing)
    end)

    it("notifies the caller after a drag", function()
        local saved
        ns.AlertToast.Create(CreateOptions({
            onPositionChanged = function(position)
                saved = position
            end,
        }))
        lastWindow.options.onPositionChanged({
            point = "CENTER",
            relativePoint = "CENTER",
            x = 40,
            y = -12,
        })
        assert.equals("CENTER", saved.point)
        assert.equals(40, saved.x)
        assert.equals(-12, saved.y)
    end)

    it("opens at the main panel scale and follows the slider", function()
        ns.AlertToast.Create(CreateOptions())
        assert.equals(1.25, lastWindow.options.scale)
        scaleListener(0.8)
        assert.equals(0.8, lastWindow.scale)
    end)

    it("keeps an explicit scale at create, then follows the slider", function()
        ns.AlertToast.Create(CreateOptions({ scale = 1.1 }))
        assert.equals(1.1, lastWindow.options.scale)
        scaleListener(0.9)
        assert.equals(0.9, lastWindow.scale)
    end)

    it("does not register with the layout editor", function()
        local registered = false
        ns.LayoutEditor = {
            Register = function()
                registered = true
            end,
            ApplyPosition = function() end,
        }
        ns.AlertToast.Create(CreateOptions())
        assert.is_false(registered)
    end)
end)

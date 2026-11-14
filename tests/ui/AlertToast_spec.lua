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
        function label:SetTextColor() end
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
                    BG = { r = 0.07, g = 0.08, b = 0.09, a = 0.95 },
                    BORDER_FAINT = { r = 1, g = 1, b = 1, a = 0.08 },
                    TEXT = { r = 1, g = 1, b = 1 },
                    TEXT_MUTED = { r = 0.55, g = 0.57, b = 0.60 },
                    WARNING = { r = 0.95, g = 0.64, b = 0.27 },
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
        assert.equals(320, lastWindow.size.width)
        assert.equals(41, lastWindow.size.height)
        assert.equals(28, lastWindow.header.height)
        assert.equals(20, lastWindow.closeButton.size.width)

        toast:SetRows({
            { left = "Four-piece incomplete", right = "Active 3/4 pieces" },
        })
        assert.equals(1, created)
        assert.equals("Four-piece incomplete", lastWindow.labels[2].text)
        assert.equals("Active 3/4 pieces", lastWindow.labels[3].text)
        assert.equals(65, lastWindow.size.height)

        toast:SetRows({
            { left = "A", right = "1" },
            { left = "B", right = "2" },
        })
        assert.equals("A", lastWindow.labels[2].text)
        assert.equals("B", lastWindow.labels[4].text)
        assert.equals(89, lastWindow.size.height)
        assert.is_true(lastWindow.labels[4].shown)

        toast:SetRows({
            { left = "Only", right = "one" },
        })
        assert.equals("Only", lastWindow.labels[2].text)
        assert.is_false(lastWindow.labels[4].shown)
        assert.equals(65, lastWindow.size.height)
    end)

    it("rejects non-string row text", function()
        local toast = ns.AlertToast.Create(CreateOptions())
        assert.is_false(pcall(toast.SetRows, toast, nil))
        assert.is_false(pcall(toast.SetRows, toast, { { left = "t" } }))
        assert.is_false(pcall(toast.SetRows, toast, { { left = "t", right = 3 } }))
    end)

    it("hides on close and can be shown again", function()
        local toast = ns.AlertToast.Create(CreateOptions())
        toast:Show()
        lastWindow.closeOnClick()
        assert.is_false(lastWindow.shown)
        toast:Show()
        assert.equals(1, created)
        assert.is_true(lastWindow.shown)
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

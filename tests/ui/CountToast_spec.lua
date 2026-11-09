describe("CountToast", function()
    local ns, originalCreateFrame, created, lastWindow, scaleListener

    local function FakeTexture()
        local texture = { points = {} }
        function texture:SetColorTexture()
            self.filled = true
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
        return texture
    end

    local function FakeLabel()
        local label = { text = "", points = {}, font = {} }
        function label:SetFont(path, size, flags)
            self.font = { path = path, size = size, flags = flags }
        end
        function label:SetText(value)
            self.text = value
        end
        function label:SetTextColor() end
        function label:SetShadowOffset() end
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetShadowColor() end
        function label:SetWordWrap() end
        function label:SetPoint(...)
            self.points[#self.points + 1] = { ... }
        end
        function label:ClearAllPoints()
            self.points = {}
        end
        if not lastWindow.title then
            lastWindow.title = label
        elseif not lastWindow.message then
            lastWindow.message = label
        else
            lastWindow.count = label
        end
        return label
    end

    local function FakeWindow(options)
        created = created + 1
        local frame = {
            shown = false,
            options = options,
            size = {},
            header = {
                SetHeight = function() end,
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
            name = "NewEraToolsCountToast",
            title = "Check",
            message = "Incomplete",
            count = "3/4",
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
                Colors = {},
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
        assert(loadfile("ui/CountToast.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("rejects incomplete Create options", function()
        assert.is_false(pcall(ns.CountToast.Create))
        assert.is_false(pcall(ns.CountToast.Create, { title = "x" }))
        assert.is_false(pcall(ns.CountToast.Create, { title = "x", message = "y" }))
    end)

    it("applies caller strings and updates them in place", function()
        local toast = ns.CountToast.Create(CreateOptions())
        assert.equals(1, created)
        assert.equals("Check", lastWindow.title.text)
        assert.equals("Incomplete", lastWindow.message.text)
        assert.equals("3/4", lastWindow.count.text)
        assert.is_true(lastWindow.options.draggable)
        assert.is_true(lastWindow.options.dragEntireFrame)
        assert.is_nil(lastWindow.options.closable)

        toast:SetToastText("Next", "Still incomplete", "2/4")
        assert.equals(1, created)
        assert.equals("Next", lastWindow.title.text)
        assert.equals("Still incomplete", lastWindow.message.text)
        assert.equals("2/4", lastWindow.count.text)
    end)

    it("rejects non-string toast text", function()
        local toast = ns.CountToast.Create(CreateOptions())
        assert.is_false(pcall(toast.SetToastText, toast, nil, "m", "c"))
        assert.is_false(pcall(toast.SetToastText, toast, "t", nil, "c"))
        assert.is_false(pcall(toast.SetToastText, toast, "t", "m", 3))
    end)

    it("hides on close and can be shown again", function()
        local toast = ns.CountToast.Create(CreateOptions())
        toast:Show()
        lastWindow.closeOnClick()
        assert.is_false(lastWindow.shown)
        toast:Show()
        assert.equals(1, created)
        assert.is_true(lastWindow.shown)
    end)

    it("notifies the caller after a drag", function()
        local saved
        ns.CountToast.Create(CreateOptions({
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
        ns.CountToast.Create(CreateOptions())
        assert.equals(1.25, lastWindow.options.scale)
        scaleListener(0.8)
        assert.equals(0.8, lastWindow.scale)
    end)

    it("keeps an explicit scale at create, then follows the slider", function()
        ns.CountToast.Create(CreateOptions({ scale = 1.1 }))
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
        ns.CountToast.Create(CreateOptions())
        assert.is_false(registered)
    end)
end)

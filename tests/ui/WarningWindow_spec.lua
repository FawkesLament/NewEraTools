describe("WarningWindow", function()
    local ns, originalCreateFrame, lastOptions, lastWindow, scaleListener

    local function FakeTexture()
        local texture = {}
        function texture:SetSize() end
        function texture:SetTexture() end
        function texture:SetPoint() end
        return texture
    end

    local function FakeLabel(text)
        local label = { text = text or "" }
        function label:SetTextColor() end
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint() end
        function label:SetText(value)
            self.text = value
        end
        function label:GetText()
            return self.text
        end
        function label:GetStringWidth()
            return #self.text
        end
        return label
    end

    local function FakeRow()
        local row = { shown = true }
        function row:CreateTexture()
            return FakeTexture()
        end
        function row:Show()
            self.shown = true
        end
        function row:Hide()
            self.shown = false
        end
        return row
    end

    local function FakeWindow()
        local frame = { scale = 1 }
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetSize() end
        function frame:SetWindowScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale
        end
        lastWindow = frame
        return frame
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        lastOptions = nil
        lastWindow = nil
        scaleListener = nil
        ns = {
            ADDON_NAME = "NewEraTools",
            Assets = {
                Textures = { WHITE = "white" },
                Icons = { WARNING = "warn" },
                Colors = {
                    BG_WARNING = { r = 0, g = 0, b = 0, a = 1 },
                    BORDER_WARNING = { r = 1, g = 1, b = 0, a = 1 },
                    WARNING = { r = 1, g = 1, b = 0, a = 1 },
                },
                Fonts = { BODY = "Body", TINY_MUTED = "Tiny" },
                Sizes = { CLOSE_BUTTON = 22, FLOATING_HEADER_PAD = 12, CONTROL_HEIGHT = 22 },
                Spacing = { SMALL = 4, LARGE = 12 },
            },
            Widgets = {
                UnpackColor = function(color)
                    return color.r, color.g, color.b, color.a
                end,
                CreateLabel = function(_, _, text)
                    return FakeLabel(text)
                end,
            },
            Layout = {
                Stack = function()
                    return {
                        AddRow = function()
                            return FakeRow()
                        end,
                        GetHeight = function()
                            return 40
                        end,
                        SetEntryHeight = function() end,
                    }
                end,
            },
            FloatingWindow = {
                Create = function(options)
                    lastOptions = options
                    local frame = FakeWindow()
                    frame.scale = options.scale or 1
                    return frame
                end,
            },
            MainPanel = {
                GetScale = function()
                    return 1.25
                end,
                OnScaleChanged = function(callback)
                    scaleListener = callback
                    return function() end
                end,
            },
        }
        assert(loadfile("ui/WarningWindow.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("is draggable by default", function()
        ns.WarningWindow.Create({ title = "Alert", hint = "Check gear" })
        assert.is_true(lastOptions.draggable)
        assert.is_true(lastOptions.dragEntireFrame)
    end)

    it("opens at the main panel scale and follows the slider", function()
        local window = ns.WarningWindow.Create({ title = "Alert", hint = "Check gear" })
        assert.equals(1.25, lastOptions.scale)
        assert.equals(1.25, window:GetScale())
        scaleListener(0.8)
        assert.equals(0.8, window:GetScale())
    end)

    it("keeps an explicit scale at create, then follows the slider", function()
        ns.WarningWindow.Create({ title = "Alert", hint = "Check gear", scale = 1.1 })
        assert.equals(1.1, lastOptions.scale)
        scaleListener(0.9)
        assert.equals(0.9, lastWindow.scale)
    end)
end)

describe("CalloutMessage", function()
    local ns, Timer, originalCreateFrame, lastLabel

    local function FakeFrame()
        local frame = { shown = false, scripts = {} }
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:SetSize() end
        function frame:Hide()
            self.shown = false
        end
        function frame:Show()
            self.shown = true
        end
        function frame:Raise() end
        function frame:IsShown()
            return self.shown
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        return frame
    end

    local function FakeLabel()
        local label = {}
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetWordWrap() end
        function label:SetPoint() end
        function label:SetText(text)
            self.text = text
        end
        return label
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        Timer = dofile("tests/helpers/fakes/Timer.lua")()
        lastLabel = nil
        ns = {
            Assets = { Fonts = { CALLOUT = "Callout" } },
            Api = { Timer = Timer },
            Widgets = {
                CreateLabel = function()
                    lastLabel = FakeLabel()
                    return lastLabel
                end,
            },
            LayoutEditor = {
                Register = function() end,
                ApplyPosition = function() end,
            },
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile("ui/CalloutMessage.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function NewCallout(overrides)
        local options = { parent = FakeFrame() }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        return ns.CalloutMessage.Create(options)
    end

    local function Tick(frame)
        frame.scripts.OnUpdate()
    end

    local function Position()
        return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 }
    end

    local function BindConfig(overrides)
        local config = {
            layoutId = "Feature:callout",
            label = "Callout",
            name = "NewEraToolsCallout",
            parent = FakeFrame(),
            isEnabled = function()
                return true
            end,
            getText = function()
                return nil
            end,
            getExpiresAt = function()
                return nil
            end,
            getPosition = Position,
            setPosition = function() end,
            getDefaultPosition = Position,
            previewText = "Preview",
            previewDuration = 4,
        }
        for key, value in pairs(overrides or {}) do
            config[key] = value
        end
        return config
    end

    it("rejects missing options or a non-string wrap", function()
        assert.is_false(pcall(ns.CalloutMessage.Create))
        assert.is_false(pcall(ns.CalloutMessage.Create, { wrap = 1, parent = FakeFrame() }))
    end)

    it("shows the message and hides it when the duration elapses", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 3 })
        assert.is_true(frame.shown)
        assert.equals("Soak", lastLabel.text)
        Timer.Advance(3)
        assert.is_false(frame.shown)
    end)

    it("clears on a nil message", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 5 })
        frame:SetMessage(nil)
        assert.is_false(frame.shown)
    end)

    it("replacing a message cancels the previous hide", function()
        local frame = NewCallout()
        frame:SetMessage("First", { duration = 5 })
        Timer.Advance(3)
        frame:SetMessage("Second", { duration = 5 })
        Timer.Advance(2)
        assert.is_true(frame.shown)
        assert.equals("Second", lastLabel.text)
        Timer.Advance(3)
        assert.is_false(frame.shown)
    end)

    it("does not append a countdown unless appendTimer is true", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 8, appendTimer = false })
        assert.equals("Soak", lastLabel.text)
        frame:SetMessage("Soak", { duration = 8, appendTimer = "yes" })
        assert.equals("Soak", lastLabel.text)
        Tick(frame)
        assert.equals("Soak", lastLabel.text)
    end)

    it("wraps the message body before appending the countdown", function()
        local frame = NewCallout({ wrap = "Go %s drop" })
        frame:SetMessage("X", { duration = 15, appendTimer = true })
        assert.equals("Go X drop (15)", lastLabel.text)
    end)

    it("uses whole seconds at 10 or more remaining and tenths below 10", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 10.2, appendTimer = true })
        assert.equals("Soak (11)", lastLabel.text)

        Timer.Advance(0.2)
        Tick(frame)
        assert.equals("Soak (10)", lastLabel.text)

        Timer.Advance(0.01)
        Tick(frame)
        assert.equals("Soak (9.9)", lastLabel.text)
    end)

    it("floors tenths so the countdown never rounds up", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 4.39, appendTimer = true })
        assert.equals("Soak (4.3)", lastLabel.text)

        Timer.Advance(0.1)
        Tick(frame)
        assert.equals("Soak (4.2)", lastLabel.text)
    end)

    it("counts down to the given expiry time instead of a rounded duration", function()
        Timer.Advance(10)
        local frame = NewCallout()
        frame:SetMessage("Soak", { expiresAt = 14.3, appendTimer = true })
        assert.equals("Soak (4.3)", lastLabel.text)

        Timer.Advance(4.3)
        assert.is_false(frame.shown)
    end)

    it("rejects a non-table SetMessage options argument", function()
        local frame = NewCallout()
        assert.is_false(pcall(function()
            frame:SetMessage("Soak", 4)
        end))
    end)

    it("preview requires a message", function()
        local frame = NewCallout()
        assert.is_false(pcall(function()
            frame:ShowPreview(nil, 2, true)
        end))
    end)

    it("preview loops the countdown instead of hiding", function()
        local frame = NewCallout()
        frame:ShowPreview("Soak", 2, true)
        assert.equals("Soak (2.0)", lastLabel.text)
        Timer.Advance(2)
        assert.is_true(frame.shown)
        Tick(frame)
        assert.is_true(frame.shown)
        assert.equals("Soak (2.0)", lastLabel.text)
    end)

    it("rejects incomplete Bind options", function()
        assert.is_false(pcall(ns.CalloutMessage.Bind))
        assert.is_false(pcall(ns.CalloutMessage.Bind, { layoutId = "x" }))
    end)

    it("Bind paints from the logic expiry time", function()
        Timer.Advance(10)
        local bound = ns.CalloutMessage.Bind(BindConfig({
            getText = function()
                return "Soak"
            end,
            getExpiresAt = function()
                return 14.3
            end,
        }))
        bound.Update()
        assert.equals("Soak (4.3)", lastLabel.text)

        Timer.Advance(4.3)
        assert.is_false(bound.Ensure().shown)
    end)

    it("Bind clears when logic has no callout", function()
        local text = "Soak"
        local expiresAt = Timer.GetTime() + 5
        local bound = ns.CalloutMessage.Bind(BindConfig({
            getText = function()
                return text
            end,
            getExpiresAt = function()
                return expiresAt
            end,
        }))
        bound.Update()
        assert.is_true(bound.Ensure().shown)

        text, expiresAt = nil, nil
        bound.Update()
        assert.is_false(bound.Ensure().shown)
    end)
end)

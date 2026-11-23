describe("CalloutMessage", function()
    local ns, Timer, originalCreateFrame, originalDamageTextFont, labels, messageLabel, timerLabel

    local function FakeTexture()
        local texture = { shown = true }
        function texture:SetColorTexture() end
        function texture:SetGradient() end
        function texture:SetGradientAlpha() end
        function texture:SetVertexColor() end
        function texture:ClearAllPoints() end
        function texture:SetPoint() end
        function texture:SetSize() end
        function texture:SetHeight() end
        function texture:SetWidth() end
        function texture:Hide()
            self.shown = false
        end
        function texture:Show()
            self.shown = true
        end
        return texture
    end

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
        function frame:SetScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale or 1
        end
        function frame:GetCenter()
            return self.centerX, self.centerY
        end
        function frame:ClearAllPoints()
            self.anchor = nil
        end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            self.anchor = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
        function frame:CreateTexture()
            return FakeTexture()
        end
        return frame
    end

    local function FakeLabel()
        local label = { shown = true }
        function label:SetJustifyH() end
        function label:SetJustifyV() end
        function label:SetWordWrap() end
        function label:ClearAllPoints() end
        function label:SetPoint() end
        function label:SetShadowColor() end
        function label:SetShadowOffset() end
        function label:Hide()
            self.shown = false
        end
        function label:Show()
            self.shown = true
        end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:GetStringWidth()
            if not self.text then
                return 0
            end
            return #self.text * 10
        end
        function label:SetFont(path, size, flags)
            self.font = { path = path, size = size, flags = flags }
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        return label
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalDamageTextFont = DAMAGE_TEXT_FONT
        DAMAGE_TEXT_FONT = "Fonts\\skurri.ttf"
        Timer = dofile("tests/helpers/fakes/Timer.lua")()
        labels = {}
        messageLabel = nil
        timerLabel = nil
        ns = {
            Assets = {
                Fonts = { CALLOUT = "Callout" },
                FontStyles = {
                    Callout = {
                        path = "Fonts\\ARHei.ttf",
                        size = 56,
                        color = { r = 0.945, g = 0.643, b = 0.267, a = 1 },
                        flags = "THICKOUTLINE",
                    },
                },
            },
            Api = { Timer = Timer },
            Widgets = {
                CreateLabel = function()
                    local label = FakeLabel()
                    labels[#labels + 1] = label
                    -- First pair is the primary slot; later rows are secondary.
                    if not messageLabel then
                        messageLabel = label
                    elseif not timerLabel then
                        timerLabel = label
                    end
                    return label
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
        DAMAGE_TEXT_FONT = originalDamageTextFont
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
        assert.equals("Soak", messageLabel.text)
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
        assert.equals("Second", messageLabel.text)
        Timer.Advance(3)
        assert.is_false(frame.shown)
    end)

    it("does not append a countdown unless appendTimer is true", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 8, appendTimer = false })
        assert.equals("Soak", messageLabel.text)
        frame:SetMessage("Soak", { duration = 8, appendTimer = "yes" })
        assert.equals("Soak", messageLabel.text)
        Tick(frame)
        assert.equals("Soak", messageLabel.text)
    end)

    it("wraps the message body and keeps the countdown on a separate label", function()
        local frame = NewCallout({ wrap = "Go %s drop" })
        frame:SetMessage("X", { duration = 15, appendTimer = true })
        assert.equals("Go X drop", messageLabel.text)
        assert.equals("15", timerLabel.text)
    end)

    it("uses whole seconds at 10 or more remaining and tenths below 10", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 10.2, appendTimer = true })
        assert.equals("Soak", messageLabel.text)
        assert.equals("11", timerLabel.text)

        Timer.Advance(0.2)
        Tick(frame)
        assert.equals("10", timerLabel.text)

        Timer.Advance(0.01)
        Tick(frame)
        assert.equals("9.9", timerLabel.text)
    end)

    it("floors tenths so the countdown never rounds up", function()
        local frame = NewCallout()
        frame:SetMessage("Soak", { duration = 2.39, appendTimer = true })
        assert.equals("Soak", messageLabel.text)
        assert.equals("2.3", timerLabel.text)

        Timer.Advance(0.1)
        Tick(frame)
        assert.equals("2.2", timerLabel.text)
    end)

    it("counts down to the given expiry time instead of a rounded duration", function()
        Timer.Advance(10)
        local frame = NewCallout()
        frame:SetMessage("Soak", { expiresAt = 12.3, appendTimer = true })
        assert.equals("Soak", messageLabel.text)
        assert.equals("2.3", timerLabel.text)

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

    it("sampled preview follows changing text and remaining time", function()
        local frame = NewCallout()
        local remaining = 4.25
        local message = "Prepare"
        frame:ShowSampledPreview(function()
            if remaining <= 0 then
                message = "Now"
                remaining = 2
            end
            return message, remaining
        end)
        assert.equals("Prepare", messageLabel.text)
        assert.equals("4.2", timerLabel.text)
        remaining = 0
        Tick(frame)
        assert.equals("Now", messageLabel.text)
        assert.equals("2.0", timerLabel.text)
        frame:ShowSampledPreview(function()
            return nil
        end)
        Tick(frame)
        assert.equals("", messageLabel.text)
        assert.is_true(frame.shown)
    end)

    it("Bind uses a sampled preview when the scope supplies a tick", function()
        local registered
        ns.LayoutEditor.Register = function(def)
            registered = def
        end
        ns.CalloutMessage
            .Bind(BindConfig({
                hasPreviewTick = function()
                    return true
                end,
                previewTick = function()
                    return "Enter", 4.25
                end,
            }))
            .Ensure()
        registered.onEditBegin()
        assert.equals("Enter", messageLabel.text)
        assert.equals("4.2", timerLabel.text)
    end)

    it("preview loops the countdown instead of hiding", function()
        local frame = NewCallout()
        frame:ShowPreview("Soak", 2, true)
        assert.equals("Soak", messageLabel.text)
        assert.equals("2.0", timerLabel.text)
        Timer.Advance(2)
        assert.is_true(frame.shown)
        Tick(frame)
        assert.is_true(frame.shown)
        assert.equals("Soak", messageLabel.text)
        assert.equals("2.0", timerLabel.text)
    end)

    it("rejects incomplete Bind options", function()
        assert.is_false(pcall(ns.CalloutMessage.Bind))
        assert.is_false(pcall(ns.CalloutMessage.Bind, { layoutId = "x" }))
    end)

    it("Bind can run before LayoutEditor exists and still register on Ensure", function()
        ns.LayoutEditor = nil
        local bound = ns.CalloutMessage.Bind(BindConfig())
        local registered
        ns.LayoutEditor = {
            Register = function(def)
                registered = def
            end,
            ApplyPosition = function() end,
        }
        bound.Ensure()
        assert.equals("Feature:callout", registered.id)
    end)

    it("Bind preview can come from functions", function()
        local registered
        ns.LayoutEditor.Register = function(def)
            registered = def
        end
        ns.CalloutMessage
            .Bind(BindConfig({
                previewText = function()
                    return "Boss"
                end,
                previewDuration = function()
                    return 7
                end,
            }))
            .Ensure()
        registered.onEditBegin()
        assert.equals("Boss", messageLabel.text)
        assert.equals("7.0", timerLabel.text)
    end)

    it("Bind registers as common-scope only when global is true", function()
        local registered
        ns.LayoutEditor.Register = function(def)
            registered = def
        end
        ns.CalloutMessage.Bind(BindConfig()):Ensure()
        assert.is_false(registered.global)
        ns.CalloutMessage.Bind(BindConfig({ global = true, name = "NewEraToolsCalloutGlobal" })):Ensure()
        assert.is_true(registered.global)
    end)

    it("Bind paints keyed entries as a stack", function()
        Timer.Advance(10)
        local bound = ns.CalloutMessage.Bind(BindConfig({
            getEntries = function()
                return {
                    { key = "soon", text = "Soon", expiresAt = 15, appendTimer = true },
                    { key = "later", text = "Later", expiresAt = 22, appendTimer = true },
                }
            end,
        }))
        bound.Update()
        assert.equals("Soon", labels[1].text)
        assert.equals("Later", labels[3].text)
        bound.Update()
        assert.equals("Soon", labels[1].text)
        assert.equals("Later", labels[3].text)
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
        assert.equals("Soak", messageLabel.text)
        assert.equals("4.3", timerLabel.text)

        Timer.Advance(4.3)
        assert.is_false(bound.Ensure().shown)
    end)

    it("uses the existing CALLOUT look when appearance is unset", function()
        local frame = NewCallout()
        assert.equals(1, frame:GetScale())
        assert.equals("Fonts\\ARHei.ttf", messageLabel.font.path)
        assert.equals(56, messageLabel.font.size)
        assert.equals("THICKOUTLINE", messageLabel.font.flags)
        assert.equals(0.945, messageLabel.color.r)
        assert.equals(0.643, messageLabel.color.g)
        assert.equals(0.267, messageLabel.color.b)
        assert.equals("Fonts\\skurri.ttf", timerLabel.font.path)
        assert.equals(67, timerLabel.font.size)
    end)

    it("SetAppearance updates live callouts and later creates", function()
        local first = NewCallout()
        ns.CalloutMessage.SetAppearance({
            scale = 1.2,
            fontPath = "Fonts\\FRIZQT__.TTF",
            fontSize = 40,
            fontColor = { r = 0, g = 1, b = 0 },
        })
        assert.equals(1.2, first.scale)
        assert.equals("Fonts\\FRIZQT__.TTF", messageLabel.font.path)
        assert.equals(56, messageLabel.font.size)
        assert.equals(0, messageLabel.color.r)
        assert.equals(1, messageLabel.color.g)
        assert.equals("Fonts\\skurri.ttf", timerLabel.font.path)
        assert.equals(40, timerLabel.font.size)

        local second = NewCallout()
        assert.equals(1.2, second.scale)
        assert.equals("Fonts\\FRIZQT__.TTF", messageLabel.font.path)
        assert.equals(56, messageLabel.font.size)
        assert.equals("Fonts\\skurri.ttf", timerLabel.font.path)
        assert.equals(40, timerLabel.font.size)
    end)

    it("keeps the visual center fixed when scale changes", function()
        local parent = FakeFrame()
        local frame = ns.CalloutMessage.Create({ parent = parent })
        frame.centerX, frame.centerY = 800, 400
        ns.CalloutMessage.SetAppearance({ scale = 2 })
        assert.equals(2, frame.scale)
        assert.equals("CENTER", frame.anchor.point)
        assert.equals("BOTTOMLEFT", frame.anchor.relativePoint)
        assert.equals(400, frame.anchor.x)
        assert.equals(200, frame.anchor.y)
    end)

    it("Bind saves the re-centered point after a scale change", function()
        local saved
        ns.FloatingWindow = {
            NormalizePosition = function(frame)
                return {
                    point = "CENTER",
                    relativePoint = "CENTER",
                    x = frame.anchor.x,
                    y = frame.anchor.y,
                }
            end,
        }
        local bound = ns.CalloutMessage.Bind(BindConfig({
            setPosition = function(position)
                saved = position
            end,
        }))
        local frame = bound.Ensure()
        frame.centerX, frame.centerY = 800, 400
        ns.CalloutMessage.SetAppearance({ scale = 2 })
        assert.equals(400, saved.x)
        assert.equals(200, saved.y)
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

    it("stacks a later keyed callout under the sooner primary", function()
        local frame = NewCallout()
        frame:SetMessage("Soon", { key = "a", duration = 5, appendTimer = true })
        frame:SetMessage("Later", { key = "b", duration = 12, appendTimer = true })
        assert.is_true(frame.shown)
        assert.equals("Soon", labels[1].text)
        assert.equals("5.0", labels[2].text)
        assert.equals("Later", labels[3].text)
        assert.equals("12", labels[4].text)
    end)

    it("promotes an earlier keyed callout into the primary slot", function()
        local frame = NewCallout()
        frame:SetMessage("Later", { key = "b", duration = 12, appendTimer = true })
        frame:SetMessage("Soon", { key = "a", duration = 4, appendTimer = true })
        assert.equals("Soon", labels[1].text)
        assert.equals("Later", labels[3].text)
    end)

    it("promotes the next callout when the primary expires", function()
        local frame = NewCallout()
        frame:SetMessage("Soon", { key = "a", duration = 2, appendTimer = true })
        frame:SetMessage("Later", { key = "b", duration = 10, appendTimer = true })
        Timer.Advance(2)
        assert.is_true(frame.shown)
        assert.equals("Later", labels[1].text)
    end)

    it("replaces the whole stack when SetMessage has no key", function()
        local frame = NewCallout()
        frame:SetMessage("A", { key = "a", duration = 5 })
        frame:SetMessage("B", { key = "b", duration = 8 })
        frame:SetMessage("Only")
        assert.equals("Only", labels[1].text)
        Timer.Advance(10)
        assert.is_false(frame.shown)
    end)

    it("clears a single keyed callout without dropping the rest", function()
        local frame = NewCallout()
        frame:SetMessage("A", { key = "a", duration = 5 })
        frame:SetMessage("B", { key = "b", duration = 8 })
        frame:Clear("a")
        assert.is_true(frame.shown)
        assert.equals("B", labels[1].text)
        frame:Clear()
        assert.is_false(frame.shown)
    end)

    it("upserts a keyed callout without dropping others", function()
        local frame = NewCallout()
        frame:SetMessage("A", { key = "a", duration = 5, appendTimer = true })
        frame:SetMessage("B", { key = "b", duration = 8, appendTimer = true })
        frame:SetMessage("A2", { key = "a", duration = 5, appendTimer = true })
        assert.equals("A2", labels[1].text)
        assert.equals("B", labels[3].text)
    end)
end)

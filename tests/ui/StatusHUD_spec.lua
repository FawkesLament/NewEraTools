describe("StatusHUD", function()
    local ns, originalCreateFrame, rows, createdTextures

    local function FakeLabel()
        local label = { shown = true }
        function label:SetJustifyH(justify)
            self.justifyH = justify
        end
        function label:SetWordWrap(enabled)
            self.wordWrap = enabled == true
        end
        function label:SetPoint() end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function label:Show()
            self.shown = true
        end
        function label:Hide()
            self.shown = false
        end
        function label:IsShown()
            return self.shown
        end
        return label
    end

    local function FakeTexture()
        createdTextures = createdTextures + 1
        local texture = { shown = true, createdIndex = createdTextures }
        function texture:SetTexture(path)
            self.texture = path
        end
        function texture:SetVertexColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:ClearAllPoints() end
        function texture:SetPoint() end
        function texture:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function texture:Show()
            self.shown = true
        end
        function texture:Hide()
            self.shown = false
        end
        function texture:IsShown()
            return self.shown
        end
        return texture
    end

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            scripts = {},
            fontStrings = {},
            textures = {},
            width = 0,
            height = 0,
        }
        function frame:SetFrameStrata(strata)
            self.strata = strata
        end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:SetWidth(width)
            self.width = width
        end
        function frame:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function frame:GetWidth()
            return self.width
        end
        function frame:GetHeight()
            return self.height
        end
        function frame:SetBackdropBorderColor(r, g, b, a)
            self.borderColor = { r = r, g = g, b = b, a = a }
        end
        function frame:CreateFontString()
            local label = FakeLabel()
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        function frame:CreateTexture()
            local texture = FakeTexture()
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function frame:HookScript(name, handler)
            local previous = self.scripts[name]
            self.scripts[name] = function(...)
                if previous then
                    previous(...)
                end
                handler(...)
            end
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
        return frame
    end

    local function Colors()
        return {
            BG_TRANSLUCENT = { r = 0.07, g = 0.07, b = 0.09, a = 0.6 },
            BORDER_SUBTLE = { r = 0.55, g = 0.58, b = 0.65, a = 0.55 },
            BORDER_WARNING = { r = 0.90, g = 0.70, b = 0.25, a = 0.75 },
            BORDER = { r = 0.18, g = 0.20, b = 0.23 },
            TEXT = { r = 0.90, g = 0.91, b = 0.92 },
            TEXT_GOLD = { r = 0.93, g = 0.82, b = 0.48 },
            ACCENT = { r = 0.31, g = 0.77, b = 0.71 },
            WARNING = { r = 0.95, g = 0.64, b = 0.27 },
        }
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        rows = {}
        createdTextures = 0
        local colors = Colors()
        ns = {
            Assets = {
                Fonts = { STATUS_HUD_TITLE = "StatusHudTitle", STATUS_HUD_TEXT = "StatusHudText" },
                Textures = { WHITE = "white" },
                Colors = colors,
                Spacing = { TINY = 2, SMALL = 4, MEDIUM = 8 },
            },
            Widgets = {
                UnpackColor = function(color)
                    return color.r, color.g, color.b, color.a
                end,
                CreateSurface = function(parent)
                    return FakeFrame(parent)
                end,
                CreateLabel = function(parent)
                    return parent:CreateFontString()
                end,
            },
            Layout = {
                Stack = function()
                    return {
                        AddRow = function(_, height)
                            local row = FakeFrame()
                            row.rowHeight = height
                            rows[#rows + 1] = row
                            return row
                        end,
                        SetEntryHeight = function(_, row, height)
                            row.rowHeight = height
                        end,
                        GetHeight = function()
                            return 64
                        end,
                    }
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
        assert(loadfile("ui/StatusHUD.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function Header()
        return rows[1]
    end

    local function Body()
        return rows[2]
    end

    local function Progress()
        return rows[3]
    end

    local function VisibleSegments()
        local visible = {}
        for _, texture in ipairs(Progress().textures) do
            if texture.shown then
                visible[#visible + 1] = texture
            end
        end
        return visible
    end

    local function SampleState(overrides)
        local state = {
            title = "Left Front",
            text = "2 remaining",
            detail = "3 / 5",
            progress = 3,
            maxProgress = 5,
            severity = "normal",
        }
        for key, value in pairs(overrides or {}) do
            state[key] = value
        end
        return state
    end

    it("rejects a missing or incomplete state table", function()
        local hud = ns.StatusHUD.Create()
        assert.is_false(pcall(function()
            hud:SetState()
        end))
        assert.is_false(pcall(function()
            hud:SetState({ text = "x" })
        end))
        assert.is_false(pcall(function()
            hud:SetState({ title = "x", text = "y", detail = 1 })
        end))
    end)

    it("renders the supplied title, text, detail, and progress", function()
        local hud = ns.StatusHUD.Create()
        assert.is_false(hud.shown)
        hud:SetState(SampleState())
        hud:Show()
        assert.is_true(hud.shown)
        assert.equals("Left Front", Header().fontStrings[1].text)
        assert.equals("3 / 5", Header().fontStrings[2].text)
        assert.is_true(Header().fontStrings[2].shown)
        assert.equals("2 remaining", Body().fontStrings[1].text)
        assert.equals(5, #VisibleSegments())
        assert.same(SampleState(), hud:GetState())
    end)

    it("updates title, text, and detail without rebuilding the card", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState())
        local title = Header().fontStrings[1]
        hud:SetState(SampleState({
            title = "Right Front",
            text = "Your turn",
            detail = "5 / 5",
            progress = 5,
        }))
        assert.equals(title, Header().fontStrings[1])
        assert.equals("Right Front", title.text)
        assert.equals("Your turn", Body().fontStrings[1].text)
        assert.equals("5 / 5", Header().fontStrings[2].text)
    end)

    it("hides optional detail when it is missing or empty", function()
        local hud = ns.StatusHUD.Create()
        local withoutDetail = SampleState()
        withoutDetail.detail = nil
        hud:SetState(withoutDetail)
        assert.is_false(Header().fontStrings[2].shown)
        assert.equals(nil, hud:GetState().detail)
        hud:SetState(SampleState({ detail = "" }))
        assert.is_false(Header().fontStrings[2].shown)
        hud:SetState(SampleState({ detail = "Back" }))
        assert.is_true(Header().fontStrings[2].shown)
        assert.equals("Back", Header().fontStrings[2].text)
    end)

    it("creates discrete segments and paints zero, partial, and full progress", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState({ progress = 0, maxProgress = 4 }))
        local segments = VisibleSegments()
        assert.equals(4, #segments)
        assert.equals(ns.Assets.Colors.BORDER.r, segments[1].color.r)
        hud:SetState(SampleState({ progress = 2, maxProgress = 4 }))
        assert.equals(ns.Assets.Colors.ACCENT.r, VisibleSegments()[1].color.r)
        assert.equals(ns.Assets.Colors.BORDER.r, VisibleSegments()[3].color.r)
        hud:SetState(SampleState({ progress = 4, maxProgress = 4 }))
        assert.equals(ns.Assets.Colors.ACCENT.r, VisibleSegments()[4].color.r)
    end)

    it("clamps invalid progress and hides the row when there is no maximum", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState({ progress = -3, maxProgress = 5 }))
        assert.equals(0, hud:GetState().progress)
        hud:SetState(SampleState({ progress = 9, maxProgress = 5 }))
        assert.equals(5, hud:GetState().progress)
        hud:SetState(SampleState({ progress = 2.8, maxProgress = 5.9 }))
        assert.equals(2, hud:GetState().progress)
        assert.equals(5, hud:GetState().maxProgress)
        hud:SetState(SampleState({ progress = 3, maxProgress = 0 }))
        assert.is_false(Progress().shown)
        assert.equals(0, Progress().rowHeight)
        assert.equals(nil, hud:GetState().maxProgress)
        local withoutMax = SampleState({ progress = 1 })
        withoutMax.maxProgress = nil
        hud:SetState(withoutMax)
        assert.is_false(Progress().shown)
    end)

    it("applies severity colors without flashing", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState({ severity = "normal" }))
        assert.equals(ns.Assets.Colors.TEXT.r, Body().fontStrings[1].color.r)
        assert.equals(ns.Assets.Colors.BORDER_SUBTLE.r, hud.borderColor.r)
        hud:SetState(SampleState({ severity = "warning" }))
        assert.equals(ns.Assets.Colors.TEXT_GOLD.r, Body().fontStrings[1].color.r)
        hud:SetState(SampleState({ severity = "urgent" }))
        assert.equals(ns.Assets.Colors.WARNING.r, Body().fontStrings[1].color.r)
        assert.equals(ns.Assets.Colors.BORDER_WARNING.r, hud.borderColor.r)
        hud:SetState(SampleState({ severity = "nope" }))
        assert.equals("normal", hud:GetState().severity)
    end)

    it("reuses segment textures across repeated updates", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState({ progress = 3, maxProgress = 5 }))
        local firstCount = createdTextures
        local first = Progress().textures[1]
        hud:SetState(SampleState({ progress = 4, maxProgress = 5 }))
        hud:SetState(SampleState({ progress = 1, maxProgress = 5 }))
        assert.equals(firstCount, createdTextures)
        assert.equals(first, Progress().textures[1])
        hud:SetState(SampleState({ progress = 2, maxProgress = 3 }))
        assert.equals(firstCount, createdTextures)
        assert.equals(3, #VisibleSegments())
        assert.is_false(Progress().textures[4].shown)
        hud:SetState(SampleState({ progress = 6, maxProgress = 6 }))
        assert.equals(firstCount + 1, createdTextures)
        assert.equals(6, #VisibleSegments())
    end)

    it("keeps independent state across instances", function()
        local first = ns.StatusHUD.Create()
        local firstRows = rows
        rows = {}
        local second = ns.StatusHUD.Create()
        first:SetState(SampleState({ title = "A", text = "One", progress = 1, maxProgress = 2 }))
        second:SetState(SampleState({
            title = "B",
            text = "Two",
            detail = nil,
            progress = 4,
            maxProgress = 4,
            severity = "urgent",
        }))
        assert.equals("A", first:GetState().title)
        assert.equals("B", second:GetState().title)
        assert.equals("normal", first:GetState().severity)
        assert.equals("urgent", second:GetState().severity)
        assert.equals(2, first:GetState().maxProgress)
        assert.equals(4, second:GetState().maxProgress)
        assert.equals("One", firstRows[2].fontStrings[1].text)
        assert.equals("Two", rows[2].fontStrings[1].text)
    end)

    it("shows and hides without changing the last state", function()
        local hud = ns.StatusHUD.Create()
        hud:SetState(SampleState())
        hud:Show()
        hud:Hide()
        assert.is_false(hud.shown)
        assert.equals("Left Front", hud:GetState().title)
        hud:Show()
        assert.is_true(hud.shown)
    end)

    describe("Bind", function()
        local registered

        local function Position()
            return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }
        end

        local function BindConfig(overrides)
            local config = {
                layoutId = "Feature:status",
                label = "Status",
                name = "NewEraToolsStatus",
                parent = FakeFrame(),
                isEnabled = function()
                    return true
                end,
                getPosition = Position,
                setPosition = function() end,
                getDefaultPosition = Position,
                previewState = SampleState(),
            }
            for key, value in pairs(overrides or {}) do
                config[key] = value
            end
            return config
        end

        before_each(function()
            registered = nil
            ns.LayoutEditor.Register = function(def)
                registered = def
            end
        end)

        it("rejects incomplete Bind options", function()
            assert.is_false(pcall(ns.StatusHUD.Bind))
            assert.is_false(pcall(ns.StatusHUD.Bind, { layoutId = "x" }))
        end)

        it("registers a non-global element and only shows preview while editing", function()
            local live = nil
            local bound = ns.StatusHUD.Bind(BindConfig({
                getState = function()
                    return live
                end,
            }))
            bound.Update()
            local hud = bound.Ensure()
            assert.equals("Feature:status", bound.LAYOUT_ID)
            assert.is_false(registered.global)
            assert.is_false(hud.shown)

            registered.onEditBegin()
            assert.is_true(hud.shown)
            assert.same(SampleState(), hud:GetState())

            registered.onEditEnd()
            assert.is_false(hud.shown)

            live = SampleState({ title = "Live", text = "Now", progress = 1, maxProgress = 2 })
            bound.Update()
            assert.is_true(hud.shown)
            assert.equals("Live", hud:GetState().title)
        end)

        it("does not apply live updates while layout editing", function()
            local live = SampleState({ title = "Live" })
            local bound = ns.StatusHUD.Bind(BindConfig({
                getState = function()
                    return live
                end,
            }))
            local hud = bound.Ensure()
            registered.onEditBegin()
            live = SampleState({ title = "Changed" })
            bound.Update()
            assert.equals("Left Front", hud:GetState().title)
        end)
    end)
end)

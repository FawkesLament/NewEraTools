describe("InterruptRotationTracker", function()
    local ns, originalCreateFrame, registered, scaleListeners, panelScale, createdFrames

    local function FakeLabel()
        local label = { shown = true }
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetPoint() end
        function label:ClearAllPoints() end
        function label:SetFont(path, size, flags)
            self.fontPath = path
            self.fontSize = size
            self.fontFlags = flags
        end
        function label:SetShadowOffset(x, y)
            self.shadowOffset = { x, y }
        end
        function label:SetShadowColor(r, g, b, a)
            self.shadowColor = { r, g, b, a }
        end
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

    local function FakeFrame(parent)
        local frame = {
            parent = parent,
            shown = true,
            scripts = {},
            fontStrings = {},
            textures = {},
            width = 0,
            height = 0,
            scale = 1,
        }
        function frame:SetScale(scale)
            self.scale = scale
        end
        function frame:GetScale()
            return self.scale
        end
        function frame:SetFrameStrata() end
        function frame:SetToplevel() end
        function frame:SetClampedToScreen() end
        function frame:ClearAllPoints()
            self.anchor = nil
        end
        function frame:SetPoint(point, relative, relativePoint, x, y)
            self.anchor = { point, relative, relativePoint, x, y }
        end
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
        function frame:SetBackdropBorderColor() end
        function frame:SetBackdropColor() end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:EnableMouse() end
        function frame:SetAllPoints() end
        function frame:GetFrameLevel()
            return self.frameLevel or 10
        end
        function frame:SetFrameLevel(level)
            self.frameLevel = level
        end
        function frame:CreateAnimationGroup()
            local group = { playing = false, animations = {} }
            function group:SetLooping(mode)
                self.looping = mode
            end
            function group:CreateAnimation(kind)
                local anim = { kind = kind }
                function anim:SetTarget(target)
                    self.target = target
                end
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
                self.animations[#self.animations + 1] = anim
                return anim
            end
            function group:Play()
                self.playing = true
            end
            function group:Stop()
                self.playing = false
            end
            function group:IsPlaying()
                return self.playing == true
            end
            return group
        end
        function frame:SetHeight(height)
            self.height = height
        end
        function frame:SetParent(parent)
            self.parent = parent
        end
        function frame:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function frame:CreateFontString()
            local label = FakeLabel()
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        function frame:CreateTexture(_, layer, _, sublevel)
            local texture = { shown = true, layer = layer, sublevel = sublevel }
            function texture:SetTexture(path, horizWrap, vertWrap, filter)
                self.texture = path
                self.horizWrap = horizWrap
                self.vertWrap = vertWrap
                self.filter = filter
            end
            function texture:SetVertexColor(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            function texture:ClearAllPoints()
                self.points = {}
            end
            function texture:SetPoint(point, _, relativePoint, x, y)
                self.points = self.points or {}
                self.points[#self.points + 1] = {
                    point = point,
                    relativePoint = relativePoint,
                    x = x,
                    y = y,
                }
            end
            function texture:SetSize(width, height)
                self.width = width
                self.height = height
            end
            function texture:SetWidth(width)
                self.width = width
            end
            function texture:SetHeight(height)
                self.height = height
            end
            function texture:SetAllPoints() end
            function texture:SetGradient() end
            function texture:SetColorTexture() end
            function texture:SetAlpha(alpha)
                self.alpha = alpha
            end
            function texture:Show()
                self.shown = true
            end
            function texture:Hide()
                self.shown = false
            end
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function frame:HookScript(name, handler)
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
        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    local function SampleState(overrides)
        local state = {
            total = 3,
            completed = 0,
            myIndices = {},
            label = "Primary",
            currentAssignee = "Task 1",
        }
        for key, value in pairs(overrides or {}) do
            state[key] = value
        end
        return state
    end

    local function BackupState()
        return SampleState({
            label = "Backup",
            currentAssignee = "Standby",
        })
    end

    local function Position()
        return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }
    end

    local function BindConfig(overrides)
        local config = {
            layoutId = "Feature:interrupt",
            label = "Interrupt",
            name = "NewEraToolsInterruptRotationTracker",
            backupName = "NewEraToolsInterruptRotationTrackerBackup",
            parent = FakeFrame(),
            isEnabled = function()
                return true
            end,
            getPosition = Position,
            setPosition = function() end,
            getDefaultPosition = Position,
            previewState = SampleState(),
            getState = function()
                return nil
            end,
            getBackupState = function()
                return nil
            end,
        }
        for key, value in pairs(overrides or {}) do
            config[key] = value
        end
        return config
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        registered = nil
        scaleListeners = {}
        panelScale = 1
        createdFrames = {}
        ns = {
            L = {
                INTERRUPT_CHAIN_HUD_PREVIEW_LABEL = "预览",
            },
            Api = {
                Player = {
                    GetFullName = function()
                        return "Fawkes-Realm"
                    end,
                    GetClassFile = function()
                        return "MAGE"
                    end,
                },
                Unit = {
                    GetClassColor = function(classFile)
                        if classFile == "MAGE" then
                            return { r = 0.25, g = 0.78, b = 0.92, a = 1 }
                        end
                    end,
                },
            },
            Assets = {
                Glyphs = {
                    SORT_DESC = "▼",
                },
                Fonts = {
                    STATUS_HUD_TITLE = "StatusHudTitle",
                    SMALL_MUTED = "SmallMuted",
                    TINY_MUTED = "TinyMuted",
                    OVERLAY_DIGIT = "OverlayDigit",
                    GLYPH = "Glyph",
                },
                FontStyles = {
                    OverlayDigit = {
                        path = "DAMAGE_TEXT_FONT",
                        size = 22,
                        flags = "OUTLINE",
                    },
                },
                Textures = { WHITE = "white", ARROW_DOWN = "arrow-down" },
                Colors = {
                    BG = { r = 0.07, g = 0.07, b = 0.09, a = 0.95 },
                    BG_TRANSLUCENT = { r = 0.07, g = 0.07, b = 0.09, a = 0.6 },
                    BORDER_SUBTLE = { r = 0.55, g = 0.58, b = 0.65, a = 0.55 },
                    BORDER_WARNING = { r = 0.90, g = 0.70, b = 0.25, a = 0.75 },
                    BORDER = { r = 0.18, g = 0.20, b = 0.23 },
                    BLACK = { r = 0, g = 0, b = 0, a = 1 },
                    WHITE = { r = 1, g = 1, b = 1, a = 1 },
                    TRANSPARENT = { r = 0, g = 0, b = 0, a = 0 },
                    MENU_CONTENT = { r = 0.09, g = 0.11, b = 0.14, a = 0.96 },
                    FEATURE_CARD_BG = { r = 0.13, g = 0.15, b = 0.19, a = 1 },
                    FEATURE_CARD_BORDER = { r = 0.22, g = 0.24, b = 0.28, a = 1 },
                    MENU_DIVIDER = { r = 1, g = 1, b = 1, a = 0.06 },
                    BORDER_FAINT = { r = 1, g = 1, b = 1, a = 0.08 },
                    SURFACE = { r = 0.10, g = 0.11, b = 0.13 },
                    SURFACE_RAISED = { r = 0.14, g = 0.15, b = 0.18 },
                    TEXT = { r = 0.90, g = 0.91, b = 0.92 },
                    TEXT_MUTED = { r = 0.55, g = 0.57, b = 0.60 },
                    TEXT_GOLD = { r = 0.93, g = 0.82, b = 0.48 },
                    TEXT_PRIMARY = { r = 0.96, g = 0.97, b = 0.98 },
                    TEXT_HEADING = { r = 0.88, g = 0.90, b = 0.94 },
                    TEXT_BODY = { r = 0.68, g = 0.72, b = 0.78 },
                    TEXT_ON_ACCENT = { r = 0.07, g = 0.07, b = 0.09 },
                    ACCENT = { r = 0.31, g = 0.77, b = 0.71 },
                    WARNING = { r = 0.95, g = 0.64, b = 0.27 },
                    ERROR = { r = 0.90, g = 0.28, b = 0.30 },
                    STATUS_HUD_EMPHASIS_BORDER = { r = 0.31, g = 0.77, b = 0.71, a = 0.72 },
                    STATUS_HUD_REGION = { r = 0.89, g = 0.91, b = 0.94 },
                    STATUS_HUD_EMPHASIS_ROLE = { r = 0.53, g = 0.85, b = 1 },
                },
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
                        AddRow = function()
                            return FakeFrame()
                        end,
                        SetEntryHeight = function() end,
                        GetHeight = function()
                            return 64
                        end,
                    }
                end,
            },
            LayoutEditor = {
                COMMON_SCOPE_ID = "common",
                GetActiveScopeId = function()
                    return nil
                end,
                Register = function(def)
                    registered = def
                end,
                ApplyPosition = function(frame, position)
                    frame.position = position
                end,
            },
            MainPanel = {
                GetScale = function()
                    return panelScale
                end,
                OnScaleChanged = function(callback)
                    scaleListeners[#scaleListeners + 1] = callback
                end,
            },
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile("ui/InterruptChainHUD.lua"))("NewEraTools", ns)
        assert(loadfile("ui/InterruptRotationTracker.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("rejects incomplete Bind options", function()
        assert.is_false(pcall(ns.InterruptRotationTracker.Bind))
        assert.is_false(pcall(ns.InterruptRotationTracker.Bind, { layoutId = "x" }))
        assert.is_false(pcall(ns.InterruptRotationTracker.Bind, {
            layoutId = "Feature:interrupt",
            label = "Interrupt",
            name = "NewEraToolsInterruptRotationTracker",
            isEnabled = function()
                return true
            end,
            getPosition = Position,
            setPosition = function() end,
            getDefaultPosition = Position,
            previewState = SampleState(),
            getState = function()
                return nil
            end,
        }))
    end)

    it("places backup beside a visible primary HUD", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = SampleState,
            getBackupState = BackupState,
        }))
        bound.Update()
        local primary = bound.Ensure()
        local backup = bound.EnsureBackup()
        assert.is_true(primary.shown)
        assert.is_true(backup.shown)
        assert.equals(primary, backup.anchor[2])
        assert.equals("LEFT", backup.anchor[1])
        assert.equals("RIGHT", backup.anchor[3])
        assert.equals(ns.Assets.Spacing.SMALL, backup.anchor[4])
        assert.equals("Backup", backup:GetState().label)
    end)

    it("dims waiting cards and restores alpha on the player's turn", function()
        local state = {
            total = 6,
            completed = 0,
            myIndices = { 3 },
        }
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return state
            end,
        }))
        bound.Update()
        local hud = bound.Ensure()
        assert.equals(0.88, hud.alpha)

        state.completed = 2
        bound.Update()
        assert.equals(1, hud.alpha)
        assert.same({ 3 }, hud:GetState().myIndices)
    end)

    it("keeps done cards readable without crushing frame alpha", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 4,
                    completed = 1,
                    myIndices = { 1 },
                }
            end,
        }))
        bound.Update()
        assert.equals(0.82, bound.Ensure().alpha)
    end)

    it("attaches OnUpdate only while a cast is running", function()
        local now = 10
        GetTime = function()
            return now
        end
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 4,
                    completed = 0,
                    myIndices = { 1 },
                    castSpellName = "Mind Flay",
                    castStartTime = 10,
                    castEndTime = 12,
                }
            end,
        }))
        bound.Update()
        local hud = bound.Ensure()
        assert.equals("function", type(hud.scripts.OnUpdate))
        now = 12
        hud.scripts.OnUpdate()
        assert.is_nil(hud.scripts.OnUpdate)
        GetTime = nil
    end)

    it("keeps backup at the saved point when primary is hidden", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getBackupState = BackupState,
        }))
        bound.Update()
        local primary = bound.Ensure()
        local backup = bound.EnsureBackup()
        assert.is_false(primary.shown)
        assert.is_true(backup.shown)
        assert.same(Position(), backup.position)
        assert.is_nil(backup.anchor)
    end)

    it("hides backup while the primary layout preview is active", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = SampleState,
            getBackupState = BackupState,
        }))
        bound.Update()
        local backup = bound.EnsureBackup()
        assert.is_true(backup.shown)

        registered.onEditBegin()
        assert.is_false(backup.shown)
        assert.is_true(bound.Ensure().shown)

        registered.onEditEnd()
        assert.is_true(backup.shown)
    end)

    it("applies main-panel scale to primary and backup cards", function()
        panelScale = 1.25
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = SampleState,
            getBackupState = BackupState,
        }))
        bound.Update()
        local primary = bound.Ensure()
        local backup = bound.EnsureBackup()
        assert.equals(1.25, primary:GetScale())
        assert.equals(1.25, backup:GetScale())

        for _, listener in ipairs(scaleListeners) do
            listener(0.8)
        end
        assert.equals(0.8, primary:GetScale())
        assert.equals(0.8, backup:GetScale())
    end)

    it("draws interrupt digits with the overlay damage font", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = SampleState,
        }))
        bound.Update()
        bound.Ensure()
        local digitCount = 0
        local digit
        for _, frame in ipairs(createdFrames) do
            for _, label in ipairs(frame.fontStrings) do
                if label.fontPath == "DAMAGE_TEXT_FONT" then
                    digitCount = digitCount + 1
                    digit = label
                end
            end
        end
        assert.equals(6, digitCount)
        assert.equals(14, digit.fontSize)
        assert.equals("", digit.fontFlags)
        assert.same({ 1, -1 }, digit.shadowOffset)
    end)

    local function FindLabelText(text)
        for _, frame in ipairs(createdFrames) do
            for _, label in ipairs(frame.fontStrings) do
                if label.text == text then
                    return label
                end
            end
        end
        return nil
    end

    it("uses the player's name and class color in Common UI preview", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            global = true,
            previewState = SampleState(),
        }))
        bound.Ensure()
        ns.LayoutEditor.GetActiveScopeId = function()
            return ns.LayoutEditor.COMMON_SCOPE_ID
        end
        registered.onEditBegin()
        local state = bound.Ensure():GetState()
        assert.same(ns.InterruptRotationTracker.PreviewState(), state)
        assert.equals("Fawkes", state.currentAssignee)
        assert.equals("MAGE", state.currentAssigneeClass)
        local assignee = FindLabelText("Fawkes")
        assert.equals(0.25, assignee.color.r)
        assert.equals(0.78, assignee.color.g)
        assert.equals(0.92, assignee.color.b)
    end)

    local function FindPlayhead()
        local hidden
        for _, frame in ipairs(createdFrames) do
            for _, texture in ipairs(frame.textures) do
                if texture.width == 12 and texture.height == 6 then
                    if texture.shown then
                        return texture
                    end
                    hidden = hidden or texture
                end
            end
        end
        return hidden
    end

    local function TgaPixel(pixels, width, height, x, y)
        -- Uncompressed TGA: bottom-up BGRA.
        local row = height - 1 - y
        local index = (row * width + x) * 4
        local b, g, r, a = pixels:byte(index + 1, index + 4)
        return r, g, b, a
    end

    it("ships an uncompressed 64x32 faceted dart TGA that points downward", function()
        local file = assert(io.open("media/icons/arrow_down.tga", "rb"))
        local header = file:read(18)
        local rest = file:read("*a")
        file:close()
        local width = header:byte(13) + header:byte(14) * 256
        local height = header:byte(15) + header:byte(16) * 256
        local pixels = rest:sub(1, width * height * 4)

        assert.equals(2, header:byte(3))
        assert.equals(64, width)
        assert.equals(32, height)
        assert.equals(32, header:byte(17))
        assert.equals(8, header:byte(18))
        assert.equals(64 * 32 * 4, #pixels)

        local function Alpha(x, y)
            local _, _, _, a = TgaPixel(pixels, width, height, x, y)
            return a
        end
        for x = 0, width - 1 do
            assert.equals(0, Alpha(x, 0))
            assert.equals(0, Alpha(x, height - 1))
        end
        for y = 1, height - 2 do
            assert.equals(0, Alpha(0, y))
            assert.equals(0, Alpha(width - 1, y))
        end

        local tipR, tipG, tipB, tipA = TgaPixel(pixels, width, height, 32, 26)
        local aboveA = Alpha(32, 6)
        local leftR, _, _, leftA = TgaPixel(pixels, width, height, 24, 16)
        local rightR, _, _, rightA = TgaPixel(pixels, width, height, 40, 16)
        local shadowR, shadowG, shadowB, shadowA = TgaPixel(pixels, width, height, 32, 28)
        assert.is_true(tipA > 80)
        assert.equals(0, aboveA)
        assert.equals(tipR, tipG)
        assert.equals(tipG, tipB)
        assert.is_true(leftA > 200)
        assert.is_true(rightA > 200)
        assert.is_true(leftR > rightR)
        assert.equals(0, shadowR)
        assert.equals(0, shadowG)
        assert.equals(0, shadowB)
        assert.is_true(shadowA > 0)
    end)

    it("shows a playhead glyph above the current slot", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 4,
                    completed = 1,
                    myIndices = { 4 },
                    label = "左前",
                }
            end,
        }))
        bound.Update()
        local pointer = FindPlayhead()
        assert.equals(true, pointer.shown)
        assert.equals(12, pointer.width)
        assert.equals(6, pointer.height)
        assert.equals("arrow-down", pointer.texture)
        assert.equals("CLAMP", pointer.horizWrap)
        assert.equals("CLAMP", pointer.vertWrap)
        assert.equals("TRILINEAR", pointer.filter)
        assert.equals("BOTTOM", pointer.points[1].point)
        assert.equals("TOP", pointer.points[1].relativePoint)
        assert.equals(0, pointer.points[1].x)
        assert.equals(2, pointer.points[1].y)
        assert.equals(ns.Assets.Colors.TEXT_PRIMARY.r, pointer.color.r)
        assert.equals(1, pointer.color.a)
    end)

    it("hides the playhead when the chain is complete", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 3,
                    completed = 3,
                    myIndices = { 1 },
                }
            end,
        }))
        bound.Update()
        local pointer = FindPlayhead()
        assert.equals(false, pointer.shown)
    end)

    it("uses the same waiting emphasis on every upcoming assigned slot", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 6,
                    completed = 0,
                    myIndices = { 4, 5, 6 },
                }
            end,
        }))
        bound.Update()
        local accent = ns.Assets.Colors.ACCENT
        for _, slot in ipairs({ "4", "5", "6" }) do
            local label = FindLabelText(slot)
            assert.equals(accent.r, label.color.r)
            assert.equals(accent.g, label.color.g)
            assert.equals(accent.b, label.color.b)
            assert.equals(0.85, label.color.a)
        end
    end)

    it("upgrades only the next assigned slot when on deck", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 6,
                    completed = 2,
                    myIndices = { 4, 5, 6 },
                }
            end,
        }))
        bound.Update()
        local accent = ns.Assets.Colors.ACCENT
        local primary = ns.Assets.Colors.TEXT_PRIMARY
        assert.equals(primary.r, FindLabelText("4").color.r)
        assert.equals(accent.r, FindLabelText("5").color.r)
        assert.equals(0.85, FindLabelText("5").color.a)
        assert.equals(accent.r, FindLabelText("6").color.r)
    end)

    local function FindWash()
        for _, frame in ipairs(createdFrames) do
            if frame.shown ~= false then
                for _, texture in ipairs(frame.textures) do
                    if texture.width == 75 then
                        return texture
                    end
                end
            end
        end
        return nil
    end

    local function FindAccentBar()
        for _, frame in ipairs(createdFrames) do
            if frame.shown ~= false then
                for _, texture in ipairs(frame.textures) do
                    if texture.width == 3 and texture.height ~= 1 then
                        return texture
                    end
                end
            end
        end
        return nil
    end

    it("defaults ThemeColor to cyan ACCENT and reuses Twin Fangs region hues", function()
        local Colors = ns.Assets.Colors
        assert.equals(Colors.ACCENT, ns.InterruptRotationTracker.ThemeColor())
        assert.equals(Colors.ACCENT, ns.InterruptRotationTracker.ThemeColor("cyan"))
        assert.equals(Colors.WARNING, ns.InterruptRotationTracker.ThemeColor("amber"))
        local blue = ns.InterruptRotationTracker.ThemeColor("blue")
        assert.equals(0.45, blue.r)
        assert.equals(0.62, blue.g)
        assert.equals(0.90, blue.b)
        local violet = ns.InterruptRotationTracker.ThemeColor("violet")
        assert.equals(0.62, violet.r)
        assert.equals(0.50, violet.g)
        assert.equals(0.86, violet.b)
        assert.equals(Colors.ACCENT, ns.InterruptRotationTracker.ThemeColor("unknown"))
    end)

    it("hides the wash on deck and uses the chain theme instead of warning amber", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 4,
                    completed = 1,
                    myIndices = { 3 },
                    theme = "cyan",
                }
            end,
        }))
        bound.Update()
        local accent = ns.Assets.Colors.ACCENT
        assert.equals(ns.Assets.Colors.TEXT_PRIMARY.r, FindLabelText("3").color.r)
        assert.equals(1, FindAccentBar().alpha)
        assert.equals(accent.r, FindAccentBar().color.r)
        assert.equals(false, FindWash().shown)
    end)

    it("paints amber from quiet outline to solid keycap without using warning as on-deck identity", function()
        local warning = ns.Assets.Colors.WARNING
        local onAccent = ns.Assets.Colors.TEXT_ON_ACCENT
        local primary = ns.Assets.Colors.TEXT_PRIMARY
        local state = {
            total = 4,
            completed = 0,
            myIndices = { 3 },
            theme = "amber",
        }
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return state
            end,
        }))
        bound.Update()
        assert.equals(warning.r, FindLabelText("3").color.r)
        assert.equals(0.85, FindLabelText("3").color.a)
        assert.equals(0.38, FindAccentBar().alpha)
        assert.equals(warning.r, FindAccentBar().color.r)
        assert.equals(false, FindWash().shown)

        state.completed = 1
        bound.Update()
        assert.equals(primary.r, FindLabelText("3").color.r)
        assert.equals(1, FindAccentBar().alpha)
        assert.equals(warning.r, FindAccentBar().color.r)
        assert.equals(false, FindWash().shown)

        state.completed = 2
        bound.Update()
        local digit = FindLabelText("3")
        assert.equals(onAccent.r, digit.color.r)
        assert.same({ 0, 0 }, digit.shadowOffset)
        assert.equals(warning.r, FindPlayhead().color.r)
        assert.equals(true, FindWash().shown)
        assert.equals("amber", bound.Ensure():GetState().theme)

        state.completed = 3
        bound.Update()
        assert.equals(0.38, FindAccentBar().alpha)
        assert.equals(warning.r, FindAccentBar().color.r)
        assert.equals(false, FindWash().shown)
        assert.equals(primary.r, FindPlayhead().color.r)
    end)

    it("accepts an explicit accentColor over the theme preset", function()
        local custom = { r = 0.2, g = 0.4, b = 0.8 }
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 3,
                    completed = 0,
                    myIndices = { 3 },
                    theme = "amber",
                    accentColor = custom,
                }
            end,
        }))
        bound.Update()
        local digit = FindLabelText("3")
        assert.equals(custom.r, digit.color.r)
        assert.equals(custom.g, digit.color.g)
        assert.equals(custom.b, digit.color.b)
        assert.same(custom, bound.Ensure():GetState().accentColor)
    end)

    local function PulseNodes()
        local found = {}
        for _, frame in ipairs(createdFrames) do
            if frame.pulseAnim then
                found[#found + 1] = frame
            end
        end
        return found
    end

    local function PlayingPulse()
        for _, node in ipairs(PulseNodes()) do
            if node.pulseAnim:IsPlaying() then
                return node
            end
        end
        return nil
    end

    it("breathes only the your-turn rim and halo, leaving the digit fill steady", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 4,
                    completed = 1,
                    myIndices = { 2 },
                }
            end,
        }))
        bound.Update()
        local node = PlayingPulse()
        assert(node)
        assert.equals("BOUNCE", node.pulseAnim.looping)
        assert.equals(true, node.pulseRim.shown)
        assert.equals(true, node.pulseHalo.shown)
        assert.equals("BACKGROUND", node.pulseHalo.layer)
        assert.equals(-1, node.pulseHalo.sublevel)
        assert.equals(12, node.frameLevel)

        local rimAnim = node.pulseAnim.animations[1]
        local haloAnim = node.pulseAnim.animations[2]
        assert.equals(node.pulseRim, rimAnim.target)
        assert.equals(0.30, rimAnim.fromAlpha)
        assert.equals(1, rimAnim.toAlpha)
        assert.equals(0.65, rimAnim.duration)
        assert.equals("IN_OUT", rimAnim.smoothing)
        assert.equals(node.pulseHalo, haloAnim.target)
        assert.equals(0.05, haloAnim.fromAlpha)
        assert.equals(0.42, haloAnim.toAlpha)
        assert.equals(0.65, haloAnim.duration)

        local accent = ns.Assets.Colors.ACCENT
        local rim = node.pulseBorders[1].color
        assert.equals(accent.r + (1 - accent.r) * 0.30, rim.r)
        assert.equals(accent.g + (1 - accent.g) * 0.30, rim.g)
        assert.equals(accent.b + (1 - accent.b) * 0.30, rim.b)
        assert.equals(accent.r, node.pulseHalo.color.r)
        assert.equals(accent.g, node.pulseHalo.color.g)
        assert.equals(accent.b, node.pulseHalo.color.b)

        local digit = FindLabelText("2")
        assert.equals(ns.Assets.Colors.TEXT_ON_ACCENT.r, digit.color.r)
        assert.equals(ns.Assets.Colors.TEXT_ON_ACCENT.g, digit.color.g)
        assert.equals(ns.Assets.Colors.TEXT_ON_ACCENT.b, digit.color.b)
        for _, anim in ipairs(node.pulseAnim.animations) do
            assert(anim.target ~= node)
        end

        local playing = 0
        for _, pulseNode in ipairs(PulseNodes()) do
            if pulseNode.pulseAnim:IsPlaying() then
                playing = playing + 1
            end
        end
        assert.equals(1, playing)
    end)

    it("keeps on-deck and waiting slots static", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 6,
                    completed = 2,
                    myIndices = { 4, 5 },
                }
            end,
        }))
        bound.Update()
        assert.is_nil(PlayingPulse())
        for _, node in ipairs(PulseNodes()) do
            assert.equals(false, node.pulseRim.shown)
            assert.equals(false, node.pulseHalo.shown)
            assert.equals(10, node.frameLevel)
        end
        assert.equals(ns.Assets.Colors.TEXT_PRIMARY.r, FindLabelText("4").color.r)
    end)

    it("stops the breath as soon as the HUD hides", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return {
                    total = 3,
                    completed = 0,
                    myIndices = { 1 },
                }
            end,
        }))
        bound.Update()
        local node = PlayingPulse()
        assert(node)
        bound.Ensure():Hide()
        assert.is_nil(PlayingPulse())
        assert.equals(false, node.pulseRim.shown)
        assert.equals(false, node.pulseHalo.shown)
        assert.equals(10, node.frameLevel)
    end)

    it("tints backup-alert breaths with ERROR instead of the region theme", function()
        local bound = ns.InterruptRotationTracker.Bind(BindConfig({
            getState = function()
                return nil
            end,
            getBackupState = function()
                return {
                    total = 2,
                    completed = 1,
                    myIndices = { 2 },
                    theme = "cyan",
                }
            end,
        }))
        bound.Update()
        local node = PlayingPulse()
        assert(node)
        local error = ns.Assets.Colors.ERROR
        local rim = node.pulseBorders[1].color
        assert.equals(error.r + (1 - error.r) * 0.15, rim.r)
        assert.equals(error.g + (1 - error.g) * 0.15, rim.g)
        assert.equals(error.b + (1 - error.b) * 0.15, rim.b)
        assert.equals(error.r, node.pulseHalo.color.r)
        assert.equals(error.g, node.pulseHalo.color.g)
        assert.equals(error.b, node.pulseHalo.color.b)
        assert.equals(1, FindAccentBar().alpha)
        assert.equals(error.r, FindAccentBar().color.r)
        assert.equals(true, FindWash().shown)
        local playhead = FindPlayhead()
        assert.equals(error.r, playhead.color.r)
        assert.equals(true, playhead.shown)
    end)
end)

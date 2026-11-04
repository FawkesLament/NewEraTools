describe("InterruptStatusHUD", function()
    local ns, originalCreateFrame, registered

    local function FakeLabel()
        local label = { shown = true }
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
        }
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
        function frame:CreateFontString()
            local label = FakeLabel()
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        function frame:CreateTexture()
            local texture = { shown = true }
            function texture:SetTexture() end
            function texture:SetVertexColor() end
            function texture:ClearAllPoints() end
            function texture:SetPoint() end
            function texture:SetSize() end
            function texture:SetWidth() end
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
        return frame
    end

    local function SampleState(overrides)
        local state = {
            title = "Primary",
            text = "Round 1",
            detail = "Task 1",
            progress = 1,
            maxProgress = 3,
            severity = "normal",
        }
        for key, value in pairs(overrides or {}) do
            state[key] = value
        end
        return state
    end

    local function BackupState()
        return SampleState({
            title = "Backup",
            detail = "Standby",
        })
    end

    local function Position()
        return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }
    end

    local function BindConfig(overrides)
        local config = {
            layoutId = "Feature:interrupt",
            label = "Interrupt",
            name = "NewEraToolsInterruptStatus",
            backupName = "NewEraToolsInterruptBackup",
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
        ns = {
            Assets = {
                Fonts = { STATUS_HUD_TITLE = "StatusHudTitle", STATUS_HUD_TEXT = "StatusHudText" },
                Textures = { WHITE = "white" },
                Colors = {
                    BG_TRANSLUCENT = { r = 0.07, g = 0.07, b = 0.09, a = 0.6 },
                    BORDER_SUBTLE = { r = 0.55, g = 0.58, b = 0.65, a = 0.55 },
                    BORDER_WARNING = { r = 0.90, g = 0.70, b = 0.25, a = 0.75 },
                    BORDER = { r = 0.18, g = 0.20, b = 0.23 },
                    TEXT = { r = 0.90, g = 0.91, b = 0.92 },
                    TEXT_MUTED = { r = 0.55, g = 0.57, b = 0.60 },
                    TEXT_GOLD = { r = 0.93, g = 0.82, b = 0.48 },
                    ACCENT = { r = 0.31, g = 0.77, b = 0.71 },
                    WARNING = { r = 0.95, g = 0.64, b = 0.27 },
                    STATUS_HUD_EMPHASIS_BORDER = { r = 0.31, g = 0.77, b = 0.71, a = 0.72 },
                    STATUS_HUD_REGION = { r = 0.89, g = 0.91, b = 0.94 },
                    STATUS_HUD_EMPHASIS_ROLE = { r = 0.53, g = 0.85, b = 1 },
                    STATUS_HUD_STANDBY_ROLE = { r = 0.77, g = 0.68, b = 0.96 },
                    STATUS_HUD_STANDBY = { r = 0.62, g = 0.50, b = 0.86 },
                    STATUS_HUD_STANDBY_BORDER = { r = 0.62, g = 0.50, b = 0.86, a = 0.40 },
                    STATUS_HUD_STANDBY_TEXT = { r = 0.78, g = 0.80, b = 0.84 },
                    STATUS_HUD_STANDBY_EMPTY = { r = 0.22, g = 0.20, b = 0.28 },
                    STATUS_HUD_STANDBY_BG = { r = 0.07, g = 0.07, b = 0.09, a = 0.48 },
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
                Register = function(def)
                    registered = def
                end,
                ApplyPosition = function(frame, position)
                    frame.position = position
                end,
            },
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile("ui/StatusHUD.lua"))("NewEraTools", ns)
        assert(loadfile("ui/InterruptStatusHUD.lua"))("NewEraTools", ns)
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("rejects incomplete Bind options", function()
        assert.is_false(pcall(ns.InterruptStatusHUD.Bind))
        assert.is_false(pcall(ns.InterruptStatusHUD.Bind, { layoutId = "x" }))
        assert.is_false(pcall(ns.InterruptStatusHUD.Bind, {
            layoutId = "Feature:interrupt",
            label = "Interrupt",
            name = "NewEraToolsInterruptStatus",
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

    it("stacks backup under a visible primary HUD", function()
        local bound = ns.InterruptStatusHUD.Bind(BindConfig({
            getState = SampleState,
            getBackupState = BackupState,
        }))
        bound.Update()
        local primary = bound.Ensure()
        local backup = bound.EnsureBackup()
        assert.is_true(primary.shown)
        assert.is_true(backup.shown)
        assert.equals(primary, backup.anchor[2])
        assert.equals("TOP", backup.anchor[1])
        assert.equals("BOTTOM", backup.anchor[3])
        assert.equals(-ns.Assets.Spacing.SMALL, backup.anchor[5])
        assert.equals("Backup", backup:GetState().title)
    end)

    it("keeps backup at the saved point when primary is hidden", function()
        local bound = ns.InterruptStatusHUD.Bind(BindConfig({
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
        local bound = ns.InterruptStatusHUD.Bind(BindConfig({
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
end)

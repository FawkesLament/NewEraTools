---Compact raid debuff HUD: named rows with secret-safe AuraContainer bars (duration or stacks).
local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets
local Columns = ns.DebuffMonitorColumns

local Colors = Assets.Colors
local Fonts = Assets.Fonts

local DebuffMonitor = {}
ns.DebuffMonitor = DebuffMonitor

DebuffMonitor.SPLIT_BY_PLAYER = "player"
DebuffMonitor.SPLIT_BY_SUBGROUP = "subgroup"
DebuffMonitor.DISPLAY_DURATION = "duration"
DebuffMonitor.DISPLAY_STACKS = "stacks"

local ACCENT_WIDTH = 3
local NAME_PAD = 6
local VALUE_GAP = 4
local VALUE_PAD = 5
local SPARK_CORE_WIDTH = 1
local SPARK_GLOW_WIDTH = 8
local SPARK_CORE_ALPHA = 0.40
local SPARK_GLOW_ALPHA = 0.35
local SPARK_BRIGHTEN = 0.45
local DEFAULT_VALUE_WIDTH = 20
local DEFAULT_ROW_HEIGHT = 22
local DEFAULT_COLUMN_GAP = 8
local DEFAULT_NAME_WIDTH = 120
local DEFAULT_NAME_FONT = 12
local DEFAULT_VALUE_FONT = 16
local DEFAULT_HEADER_HEIGHT = 16
local DEFAULT_TITLE_HEIGHT = 18
local DEFAULT_MAX_STACKS = 10
local DEFAULT_MAX_DURATION = 20
local DEFAULT_MAX_GROUP_SIZE = 5
local ELLIPSIS = "…"

local PREVIEW_CLASSES = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
}

local BAR_COLOR = { r = Colors.DANGER.r, g = Colors.DANGER.g, b = Colors.DANGER.b, a = 1 }
local ROW_BG = { r = Colors.BG.r, g = Colors.BG.g, b = Colors.BG.b, a = 0.82 }
local TITLE_COLOR = Colors.TEXT_PRIMARY
local HEADER_COLOR = Colors.TEXT_MUTED
local VALUE_COLOR = { r = 0.94, g = 0.96, b = 0.98, a = 1 }
local NAME_SHADOW_ALPHA = 0.9

---@class DebuffMonitorMember
---@field name string
---@field unit string|nil
---@field classFile string|nil
---@field subgroup number|nil
---@field index number|nil

---@class DebuffMonitorAppearance
---@field rowHeight number|nil
---@field rowGap number|nil
---@field columnGap number|nil
---@field nameColumnWidth number|nil
---@field valueColumnWidth number|nil
---@field nameFontSize number|nil
---@field valueFontSize number|nil
---@field headerHeight number|nil
---@field titleHeight number|nil
---@field barColor { r: number, g: number, b: number, a: number|nil }|nil
---@field valueColor { r: number, g: number, b: number, a: number|nil }|nil
---@field barTexture string|nil
---@field spark boolean|nil
---@field backgroundOpacity number|nil
---@field barOpacity number|nil
---@field maxStacks number|nil
---@field maxDuration number|nil

---@class DebuffMonitorApplyOptions
---@field live boolean|nil
---@field enableAuras boolean|nil
---@field values table<number|string, number>|nil

---@class DebuffMonitorConfig
---@field name string
---@field parent Frame|nil
---@field splitBy "player"|"subgroup"|nil
---@field columns number|nil
---@field collapseEmpty boolean|nil
---@field organize (fun(members: DebuffMonitorMember[]): DebuffMonitorColumnData[])|nil
---@field displayMode "duration"|"stacks"
---@field slotKey string
---@field spellId number|nil
---@field auraFilter string|nil
---@field candidateFilters table|nil
---@field title string|nil
---@field showTitle boolean|nil
---@field showSubgroupHeaders boolean|nil
---@field maxGroups number|nil
---@field maxGroupSize number|nil
---@field spark boolean|nil
---@field maxStacks number|nil
---@field barColor { r: number, g: number, b: number, a: number|nil }|nil
---@field getAppearance (fun(): DebuffMonitorAppearance)|nil
---@field getPosition (fun(): LayoutPosition|nil)|nil
---@field listenForScale boolean|nil

---@class DebuffMonitorColumnData
---@field group number|nil
---@field label string|nil
---@field members DebuffMonitorMember[]
---@field collapse boolean
---@field subgroups number[]|nil

---@class DebuffMonitorRow
---@field frame Frame
---@field bg Texture
---@field accent Texture
---@field bar StatusBar
---@field spark Texture|nil
---@field sparkGlow Texture|nil
---@field sparkEnabled boolean|nil
---@field sparkFollowFill boolean|nil
---@field textLayer Frame
---@field nameText FontString
---@field stackHost Frame
---@field stackText FontString
---@field liveStackText FontString|nil
---@field container Frame|nil
---@field auraButton Frame|nil
---@field boundUnit string|nil
---@field auraPending boolean|nil
---@field applicationCountBound boolean|nil
---@field durationTextBound boolean|nil
---@field barBoundMode string|nil
---@field collapseHooked boolean|nil
---@field engineShown boolean|nil
---@field member DebuffMonitorMember|nil
---@field collapseEmpty boolean|nil

---@class DebuffMonitorColumnFrame
---@field frame Frame
---@field bg Texture
---@field header Frame|nil
---@field headerBg Texture|nil
---@field headerText FontString|nil
---@field rows DebuffMonitorRow[]
---@field collapse boolean|nil

---@class DebuffMonitor
---@field root Frame
---@field titleHost Frame|nil
---@field titleBg Texture|nil
---@field titleText FontString|nil
---@field columns DebuffMonitorColumnFrame[]
---@field boundColumns DebuffMonitorColumnData[]|nil
---@field boundMembers DebuffMonitorMember[]|nil
---@field boundStacks table<number|string, number>|nil
---@field liveDisplay boolean|nil
---@field enableAuras boolean|nil
---@field config DebuffMonitorConfig
---@field Apply fun(self: DebuffMonitor, members: DebuffMonitorMember[]|nil, opts: DebuffMonitorApplyOptions|nil)
---@field DisableAllAuras fun(self: DebuffMonitor)
---@field ApplyScale fun(self: DebuffMonitor)
---@field Refresh fun(self: DebuffMonitor)

---@param appearance DebuffMonitorAppearance|nil
---@return number
function DebuffMonitor.ColumnWidth(appearance)
    appearance = appearance or {}
    local nameWidth = appearance.nameColumnWidth or DEFAULT_NAME_WIDTH
    local valueWidth = appearance.valueColumnWidth or DEFAULT_VALUE_WIDTH
    return ACCENT_WIDTH + NAME_PAD + nameWidth + VALUE_GAP + valueWidth + VALUE_PAD
end

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---@param frame Frame
---@param getPosition (fun(): LayoutPosition|nil)|nil
local function ApplyScale(frame, getPosition)
    local scale = MainPanelScale()
    local oldScale = frame:GetScale() or 1
    if math.abs(oldScale - scale) >= 0.001 then
        frame:SetScale(scale)
    end
    if getPosition and ns.LayoutEditor and ns.LayoutEditor.ApplyPosition then
        local position = getPosition()
        if position then
            ns.LayoutEditor.ApplyPosition(frame, position)
        end
    end
end

---@param frame Frame
---@param getPosition (fun(): LayoutPosition|nil)|nil
local function ListenForScale(frame, getPosition)
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    mainPanel.OnScaleChanged(function(scale)
        frame:SetScale(scale)
        if getPosition and ns.LayoutEditor and ns.LayoutEditor.ApplyPosition then
            local position = getPosition()
            if position then
                ns.LayoutEditor.ApplyPosition(frame, position)
            end
        end
    end)
end

---@param text string
---@return number
local function Utf8Len(text)
    local n = 0
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c < 192 then
            i = i + 1
        elseif c < 224 then
            i = i + 2
        elseif c < 240 then
            i = i + 3
        else
            i = i + 4
        end
        n = n + 1
    end
    return n
end

---@param text string
---@param charCount number
---@return string
local function Utf8Prefix(text, charCount)
    if charCount <= 0 then
        return ""
    end
    local i = 1
    local n = 0
    local len = #text
    while i <= len and n < charCount do
        local c = text:byte(i)
        if c < 192 then
            i = i + 1
        elseif c < 224 then
            i = i + 2
        elseif c < 240 then
            i = i + 3
        else
            i = i + 4
        end
        n = n + 1
    end
    return text:sub(1, i - 1)
end

---@param fontString FontString
---@param text string
local function SetTruncatedText(fontString, text)
    fontString:SetText(text)
    local maxWidth = fontString:GetWidth()
    if type(maxWidth) ~= "number" or maxWidth <= 0 or not fontString.GetStringWidth then
        return
    end
    if fontString:GetStringWidth() <= maxWidth then
        return
    end
    local low, high = 0, Utf8Len(text)
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        fontString:SetText(Utf8Prefix(text, mid) .. ELLIPSIS)
        if fontString:GetStringWidth() <= maxWidth then
            low = mid
        else
            high = mid - 1
        end
    end
    if low <= 0 then
        fontString:SetText(ELLIPSIS)
        return
    end
    fontString:SetText(Utf8Prefix(text, low) .. ELLIPSIS)
end

---@param value number|nil
---@param fallback number
---@return number
local function CoalesceNumber(value, fallback)
    if type(value) == "number" then
        return value
    end
    return fallback
end

---@param appearance DebuffMonitorAppearance
---@return DebuffMonitorAppearance
local function ResolveAppearance(config, appearance)
    appearance = appearance or {}
    local spark = appearance.spark
    if spark == nil then
        spark = config.spark
    end
    if spark == nil then
        spark = true
    end
    return {
        rowHeight = CoalesceNumber(appearance.rowHeight, DEFAULT_ROW_HEIGHT),
        rowGap = CoalesceNumber(appearance.rowGap, 0),
        columnGap = CoalesceNumber(appearance.columnGap, DEFAULT_COLUMN_GAP),
        nameColumnWidth = CoalesceNumber(appearance.nameColumnWidth, DEFAULT_NAME_WIDTH),
        valueColumnWidth = CoalesceNumber(appearance.valueColumnWidth, DEFAULT_VALUE_WIDTH),
        nameFontSize = CoalesceNumber(appearance.nameFontSize, DEFAULT_NAME_FONT),
        valueFontSize = CoalesceNumber(appearance.valueFontSize, DEFAULT_VALUE_FONT),
        headerHeight = CoalesceNumber(appearance.headerHeight, DEFAULT_HEADER_HEIGHT),
        titleHeight = CoalesceNumber(appearance.titleHeight, DEFAULT_TITLE_HEIGHT),
        barColor = appearance.barColor or config.barColor or BAR_COLOR,
        valueColor = appearance.valueColor or VALUE_COLOR,
        barTexture = appearance.barTexture or config.barTexture or Assets.Textures.WHITE,
        spark = spark,
        backgroundOpacity = CoalesceNumber(appearance.backgroundOpacity, ROW_BG.a),
        barOpacity = CoalesceNumber(appearance.barOpacity, 1),
        maxStacks = appearance.maxStacks or config.maxStacks or DEFAULT_MAX_STACKS,
        maxDuration = appearance.maxDuration or config.maxDuration or DEFAULT_MAX_DURATION,
    }
end

---@param config DebuffMonitorConfig
---@return DebuffMonitorAppearance
local function CurrentAppearance(config)
    if config.getAppearance then
        return ResolveAppearance(config, config.getAppearance())
    end
    return ResolveAppearance(config, {})
end

---@param parent Frame
---@param layer string
---@param color table
---@return Texture
local function ColorTex(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(Widgets.UnpackColor(color))
    return texture
end

---@param fontString FontString
local function ApplyTextShadow(fontString)
    if fontString.SetShadowOffset then
        fontString:SetShadowOffset(1, -1)
    end
    if fontString.SetShadowColor then
        fontString:SetShadowColor(0, 0, 0, NAME_SHADOW_ALPHA)
    end
end

---@param fontString FontString
---@param fontName string
---@param size number
---@param color table|nil
local function ApplyFont(fontString, fontName, size, color)
    local style = Assets.FontStyles[fontName]
    fontString:SetFont(style.path or STANDARD_TEXT_FONT, size, style.flags or "")
    if color then
        fontString:SetTextColor(Widgets.UnpackColor(color))
    end
    ApplyTextShadow(fontString)
end

---@param values table<number|string, number>|nil
---@param member DebuffMonitorMember|nil
---@return number|nil
local function MockValue(values, member)
    if type(values) ~= "table" or not member then
        return nil
    end
    if member.index ~= nil and values[member.index] ~= nil then
        return values[member.index]
    end
    if member.unit and values[member.unit] ~= nil then
        return values[member.unit]
    end
    return nil
end

---@param displayMode string
---@param value number
---@return string
local function FormatMockValue(displayMode, value)
    if displayMode == DebuffMonitor.DISPLAY_DURATION then
        if value >= 60 then
            local minutes = math.floor(value / 60)
            local seconds = math.floor(value % 60)
            return string.format("%d:%02d", minutes, seconds)
        end
        if value >= 10 then
            return tostring(math.floor(value))
        end
        return string.format("%.1f", value)
    end
    return tostring(math.floor(value))
end

---@param displayMode string
---@param value number
---@param appearance DebuffMonitorAppearance
---@return number
local function MockRatio(displayMode, value, appearance)
    local maxValue = appearance.maxStacks
    if displayMode == DebuffMonitor.DISPLAY_DURATION then
        maxValue = appearance.maxDuration
    end
    if type(maxValue) ~= "number" or maxValue <= 0 then
        return 0
    end
    local ratio = value / maxValue
    if ratio < 0 then
        return 0
    end
    if ratio > 1 then
        return 1
    end
    return ratio
end

---@param container Frame|nil
---@return boolean
local function CanConfigureAura(container)
    local Combat = ns.Api.Combat
    if Combat and Combat.IsLockedDown and Combat.IsLockedDown() then
        return false
    end
    if container and container.CanChangeProtectedState and not container:CanChangeProtectedState() then
        return false
    end
    return true
end

---@param config DebuffMonitorConfig
---@return boolean
local function CanCreateContainer(config)
    local Aura = ns.Api.Aura
    if not Aura then
        return false
    end
    if config.displayMode == DebuffMonitor.DISPLAY_DURATION then
        return Aura.IsSupported and Aura.IsSupported()
    end
    if Aura.HasExpirationOnlyReverseSort and Aura.HasExpirationOnlyReverseSort() then
        return true
    end
    return Aura.IsSupported and Aura.IsSupported()
end

---@param config DebuffMonitorConfig
---@return unknown|nil
---@return unknown|nil
local function SortPair(config)
    local Aura = ns.Api.Aura
    if config.displayMode == DebuffMonitor.DISPLAY_DURATION and Aura.GetExpirationSort then
        return Aura.GetExpirationSort()
    end
    if Aura.HasExpirationOnlyReverseSort and Aura.HasExpirationOnlyReverseSort() then
        return Aura.GetExpirationOnlyReverseSort()
    end
    if Aura.GetExpirationSort then
        return Aura.GetExpirationSort()
    end
    return nil, nil
end

---@param config DebuffMonitorConfig
---@return table
local function CandidateFilters(config)
    if type(config.candidateFilters) == "table" then
        return config.candidateFilters
    end
    local filters = {
        isFromPlayerOrPlayerPet = false,
        isBossOrRoleAura = false,
    }
    local Aura = ns.Api.Aura
    if config.spellId and Aura and Aura.BuildIncludeSpellFilters then
        local include = Aura.BuildIncludeSpellFilters(config.spellId)
        if include and include.includeSpellIDs then
            filters.includeSpellIDs = include.includeSpellIDs
        end
    end
    return filters
end

---@param row DebuffMonitorRow
---@param appearance DebuffMonitorAppearance
---@param displayMode string
---@param row DebuffMonitorRow
local function RaiseTextLayer(row)
    local layer = row.textLayer
    if not layer or not layer.SetFrameLevel then
        return
    end
    local level = 0
    if row.bar and row.bar.GetFrameLevel then
        level = row.bar:GetFrameLevel() or 0
    end
    if row.container and row.container.GetFrameLevel then
        level = math.max(level, row.container:GetFrameLevel() or 0)
    end
    if row.auraButton and row.auraButton.GetFrameLevel then
        level = math.max(level, row.auraButton:GetFrameLevel() or 0)
    end
    pcall(layer.SetFrameLevel, layer, level + 2)
end

local function ApplyRowFonts(row, appearance, displayMode)
    ApplyFont(row.nameText, Fonts.BODY, appearance.nameFontSize)
    local valueColor = appearance.valueColor or VALUE_COLOR
    ApplyFont(row.stackText, Fonts.OVERLAY_DIGIT, appearance.valueFontSize, valueColor)
    if row.liveStackText then
        ApplyFont(row.liveStackText, Fonts.OVERLAY_DIGIT, appearance.valueFontSize, valueColor)
    end
end

---@param color { r: number, g: number, b: number }
---@return number, number, number
local function SparkCoreColor(color)
    local lift = SPARK_BRIGHTEN
    return color.r + (1 - color.r) * lift, color.g + (1 - color.g) * lift, color.b + (1 - color.b) * lift
end

---@param texture Texture|nil
---@param shown boolean
local function SetTextureShown(texture, shown)
    if not texture then
        return
    end
    if shown then
        if texture.Show then
            texture:Show()
        end
        return
    end
    if texture.Hide then
        texture:Hide()
    end
end

---@param row DebuffMonitorRow
---@param shown boolean
local function SetSparkShown(row, shown)
    SetTextureShown(row.spark, shown)
    SetTextureShown(row.sparkGlow, shown)
end

---@param texture Texture
---@param relative Region
---@param width number
local function PinSparkToEdge(texture, relative, width)
    texture:ClearAllPoints()
    if texture.SetWidth then
        texture:SetWidth(width)
    end
    texture:SetPoint("TOP", relative, "TOPRIGHT", 0, 0)
    texture:SetPoint("BOTTOM", relative, "BOTTOMRIGHT", 0, 0)
end

---@param texture Texture
---@param bar StatusBar
---@param x number
---@param width number
local function PinSparkAtX(texture, bar, x, width)
    texture:ClearAllPoints()
    if texture.SetWidth then
        texture:SetWidth(width)
    end
    local left = x - width * 0.5
    texture:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
    texture:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, 0)
end

---@param row DebuffMonitorRow
local function PlaceSparkParts(row, relative, x)
    local spark = row.spark
    local glow = row.sparkGlow
    local bar = row.bar
    if relative then
        if glow then
            PinSparkToEdge(glow, relative, SPARK_GLOW_WIDTH)
        end
        if spark then
            PinSparkToEdge(spark, relative, SPARK_CORE_WIDTH)
        end
        return
    end
    if glow then
        PinSparkAtX(glow, bar, x, SPARK_GLOW_WIDTH)
    end
    if spark then
        PinSparkAtX(spark, bar, x, SPARK_CORE_WIDTH)
    end
end

---@param row DebuffMonitorRow
local function PlaceSpark(row)
    local spark = row.spark
    local bar = row.bar
    if not spark or not spark.ClearAllPoints or not bar then
        return
    end
    if not row.sparkEnabled then
        SetSparkShown(row, false)
        return
    end
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    -- Live bars are secret-driven; follow the fill instead of reading GetValue.
    -- Mock bars pin to the fill as well: GetWidth is 0 until the first layout pass
    -- (hidden until edit mode), and an offset from TOPLEFT would stick on the left.
    if row.sparkFollowFill then
        if not fill then
            SetSparkShown(row, false)
            return
        end
        SetSparkShown(row, true)
        PlaceSparkParts(row, fill)
        return
    end
    local minValue, maxValue = 0, 1
    if bar.GetMinMaxValues then
        minValue, maxValue = bar:GetMinMaxValues()
    end
    local value = 0
    if bar.GetValue then
        value = bar:GetValue() or 0
    end
    local range = (maxValue or 1) - (minValue or 0)
    local ratio = 0
    if range > 0 then
        ratio = (value - (minValue or 0)) / range
    end
    if ratio <= 0 then
        SetSparkShown(row, false)
        return
    end
    SetSparkShown(row, true)
    if fill then
        PlaceSparkParts(row, fill)
        return
    end
    local width = bar.GetWidth and bar:GetWidth() or 0
    PlaceSparkParts(row, nil, width * ratio)
end

---@param row DebuffMonitorRow
---@param appearance DebuffMonitorAppearance
local function PaintBar(row, appearance)
    local color = appearance.barColor or BAR_COLOR
    pcall(function()
        row.bar:SetStatusBarTexture(appearance.barTexture or Assets.Textures.WHITE)
        row.bar:SetStatusBarColor(color.r, color.g, color.b, appearance.barOpacity)
    end)
    row.sparkEnabled = appearance.spark == true
    if row.sparkEnabled then
        local coreR, coreG, coreB = SparkCoreColor(color)
        if row.sparkGlow then
            pcall(function()
                row.sparkGlow:SetTexture(Assets.Textures.CASTING_SPARK)
                row.sparkGlow:SetTexCoord(0.32, 0.68, 0, 1)
                row.sparkGlow:SetBlendMode("ADD")
                row.sparkGlow:SetVertexColor(color.r, color.g, color.b, 1)
                row.sparkGlow:SetAlpha(SPARK_GLOW_ALPHA)
            end)
        end
        if row.spark then
            pcall(function()
                row.spark:SetTexture(Assets.Textures.WHITE)
                row.spark:SetBlendMode("ADD")
                row.spark:SetVertexColor(coreR, coreG, coreB, 1)
                row.spark:SetAlpha(SPARK_CORE_ALPHA)
            end)
        end
        PlaceSpark(row)
    else
        SetSparkShown(row, false)
    end
    RaiseTextLayer(row)
end

---@param appearance DebuffMonitorAppearance
---@return { r: number, g: number, b: number, a: number }
local function PanelBackground(appearance)
    return {
        r = ROW_BG.r,
        g = ROW_BG.g,
        b = ROW_BG.b,
        a = appearance.backgroundOpacity,
    }
end

---@param texture Texture|nil
---@param appearance DebuffMonitorAppearance
local function PaintPanel(texture, appearance)
    if not texture or not texture.SetColorTexture then
        return
    end
    texture:SetColorTexture(Widgets.UnpackColor(PanelBackground(appearance)))
end

---@param row DebuffMonitorRow
---@param ratio number
local function SetMockBar(row, ratio)
    pcall(function()
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(ratio)
    end)
    PlaceSpark(row)
end

---@param row DebuffMonitorRow
---@return FontString
local function EnsureLiveStackText(row)
    if row.liveStackText then
        return row.liveStackText
    end
    local liveStackText = Widgets.CreateLabel(row.stackHost, Fonts.OVERLAY_DIGIT)
    liveStackText:SetJustifyH("RIGHT")
    liveStackText:SetPoint("RIGHT", row.stackHost, "RIGHT", 0, 0)
    if liveStackText.Hide then
        liveStackText:Hide()
    end
    row.liveStackText = liveStackText
    return liveStackText
end

---@param row DebuffMonitorRow
local function HideLiveStack(row)
    if row.liveStackText and row.liveStackText.Hide then
        row.liveStackText:Hide()
    end
    if row.stackText.Show then
        row.stackText:Show()
    end
end

---@param row DebuffMonitorRow
local function ShowLiveStack(row)
    if row.stackText.Hide then
        row.stackText:Hide()
    end
    row.stackText:SetText("")
    local liveStackText = row.liveStackText
    if liveStackText and liveStackText.Show then
        liveStackText:Show()
    end
end

---@param row DebuffMonitorRow
---@param config DebuffMonitorConfig
local function BindNativeProgress(row, config)
    local button = row.auraButton
    local Aura = ns.Api.Aura
    if not button or not Aura then
        return
    end
    local liveStackText = EnsureLiveStackText(row)
    if config.displayMode == DebuffMonitor.DISPLAY_DURATION then
        if not row.durationTextBound and button.SetDurationText then
            local bound = pcall(function()
                button:SetDurationText(
                    liveStackText,
                    Aura.GetDurationTextOptions and Aura.GetDurationTextOptions() or {}
                )
            end)
            if bound then
                row.durationTextBound = true
            end
        end
        if row.barBoundMode ~= DebuffMonitor.DISPLAY_DURATION and button.SetDurationBar then
            local bound = pcall(function()
                button:SetDurationBar(row.bar, Aura.GetDurationBarOptions and Aura.GetDurationBarOptions() or {})
            end)
            if bound then
                row.barBoundMode = DebuffMonitor.DISPLAY_DURATION
            end
        end
        return
    end
    if not row.applicationCountBound and button.SetApplicationCount then
        local options = Aura.GetApplicationCountOptions and Aura.GetApplicationCountOptions() or {}
        local bound = pcall(function()
            button:SetApplicationCount(liveStackText, options)
        end)
        if bound then
            row.applicationCountBound = true
        end
    end
    if row.barBoundMode ~= DebuffMonitor.DISPLAY_STACKS and button.SetApplicationBar then
        local maxStacks = config.maxStacks or DEFAULT_MAX_STACKS
        local bound = pcall(function()
            local barOptions = {}
            if Aura.GetApplicationBarOptions then
                barOptions = Aura.GetApplicationBarOptions(maxStacks)
            end
            button:SetApplicationBar(row.bar, barOptions)
        end)
        if bound then
            row.barBoundMode = DebuffMonitor.DISPLAY_STACKS
        end
    end
end

---@param row DebuffMonitorRow
---@param relayout fun()
local function HookCollapse(row, relayout)
    if row.collapseHooked or not row.collapseEmpty then
        return
    end
    local button = row.auraButton
    if not button or not button.HookScript then
        return
    end
    row.collapseHooked = true
    pcall(button.HookScript, button, "OnShow", function()
        row.engineShown = true
        relayout()
    end)
    pcall(button.HookScript, button, "OnHide", function()
        row.engineShown = false
        relayout()
    end)
end

---@param row DebuffMonitorRow
---@param config DebuffMonitorConfig
---@param relayout fun()
---@return Frame|nil
local function EnsureAuraContainer(row, config, relayout)
    if row.container then
        return row.container
    end
    if not CanCreateContainer(config) then
        return nil
    end
    if not CanConfigureAura() then
        row.auraPending = true
        return nil
    end
    local Aura = ns.Api.Aura
    local filter = config.auraFilter or Aura.FILTER_HARMFUL
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, row.frame, "CustomAuraContainerTemplate")
    if not ok or not container then
        row.auraPending = true
        return nil
    end
    container:SetAllPoints(row.frame)
    container:EnableMouse(false)
    if container.SetFrameLevel and row.bar and row.bar.GetFrameLevel then
        pcall(container.SetFrameLevel, container, (row.bar:GetFrameLevel() or 0) + 1)
    end
    local sortMethod, sortDirection = SortPair(config)
    local auraButton
    local configured = pcall(function()
        auraButton = container:AddAuraSlot(config.slotKey, filter, {
            filterString = filter,
            candidateFilters = CandidateFilters(config),
            sortMethod = sortMethod,
            sortDirection = sortDirection,
            initializeFrame = function(button)
                row.auraButton = button
                if button.EnableMouse then
                    button:EnableMouse(false)
                end
                local icon = button.Icon or button.icon
                if icon and icon.Hide then
                    icon:Hide()
                end
                EnsureLiveStackText(row)
                BindNativeProgress(row, config)
                HookCollapse(row, relayout)
            end,
        })
        if not auraButton then
            error("AddAuraSlot returned nil")
        end
        row.auraButton = auraButton
        BindNativeProgress(row, config)
        HookCollapse(row, relayout)
        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled(config.slotKey, false)
        end
        container:SetEnabled(false)
        container:Hide()
    end)
    if not configured then
        row.auraPending = true
        return nil
    end
    row.container = container
    row.auraPending = nil
    RaiseTextLayer(row)
    return container
end

---@param row DebuffMonitorRow
---@param config DebuffMonitorConfig
---@param clearBinding boolean|nil
local function DisableAuraContainer(row, config, clearBinding)
    local container = row.container
    if container then
        pcall(function()
            if container.SetAuraSlotEnabled then
                container:SetAuraSlotEnabled(config.slotKey, false)
            end
            if container.SetEnabled then
                container:SetEnabled(false)
            end
            container:Hide()
        end)
    end
    if clearBinding ~= false then
        row.boundUnit = nil
    end
    HideLiveStack(row)
end

---@param row DebuffMonitorRow
---@param unit string
---@param config DebuffMonitorConfig
---@param enable boolean|nil
---@param relayout fun()
local function BindAuraUnit(row, unit, config, enable, relayout)
    local container = EnsureAuraContainer(row, config, relayout)
    if not container then
        row.stackText:SetText("")
        HideLiveStack(row)
        return
    end
    if row.boundUnit ~= unit then
        pcall(function()
            container:SetUnit(unit)
        end)
        row.boundUnit = unit
    end
    if enable == false then
        DisableAuraContainer(row, config, false)
        return
    end
    if not CanConfigureAura(container) then
        ShowLiveStack(row)
        return
    end
    pcall(function()
        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled(config.slotKey, true)
        end
        container:SetEnabled(true)
        container:Show()
    end)
    RaiseTextLayer(row)
    ShowLiveStack(row)
end

---@param parent Frame
---@param appearance DebuffMonitorAppearance
---@param displayMode string
---@return DebuffMonitorRow
local function CreateRow(parent, appearance, displayMode)
    local rowHeight = appearance.rowHeight
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame:SetHeight(rowHeight)

    local bg = ColorTex(frame, "BACKGROUND", ROW_BG)
    bg:SetAllPoints()

    local accent = ColorTex(frame, "ARTWORK", Colors.TEXT)
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(ACCENT_WIDTH)

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", ACCENT_WIDTH, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    pcall(function()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture(appearance.barTexture or Assets.Textures.WHITE)
        local color = appearance.barColor or BAR_COLOR
        bar:SetStatusBarColor(color.r, color.g, color.b, CoalesceNumber(appearance.barOpacity, 1))
    end)
    if bar.EnableMouse then
        bar:EnableMouse(false)
    end

    local sparkGlow = bar:CreateTexture(nil, "OVERLAY", nil, 0)
    sparkGlow:SetWidth(SPARK_GLOW_WIDTH)
    sparkGlow:SetPoint("TOP", bar, "TOPLEFT", 0, 0)
    sparkGlow:SetPoint("BOTTOM", bar, "BOTTOMLEFT", 0, 0)
    sparkGlow:Hide()

    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetWidth(SPARK_CORE_WIDTH)
    spark:SetPoint("TOP", bar, "TOPLEFT", 0, 0)
    spark:SetPoint("BOTTOM", bar, "BOTTOMLEFT", 0, 0)
    spark:Hide()

    local textLayer = CreateFrame("Frame", nil, frame)
    textLayer:EnableMouse(false)
    textLayer:SetAllPoints(frame)

    local stackHost = CreateFrame("Frame", nil, textLayer)
    stackHost:EnableMouse(false)
    stackHost:SetSize(appearance.valueColumnWidth, rowHeight)
    stackHost:SetPoint("RIGHT", textLayer, "RIGHT", -VALUE_PAD, 0)

    local stackText = Widgets.CreateLabel(stackHost, Fonts.OVERLAY_DIGIT)
    stackText:SetJustifyH("RIGHT")
    stackText:SetPoint("RIGHT", stackHost, "RIGHT", 0, 0)

    local nameText = Widgets.CreateLabel(textLayer, Fonts.BODY)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    if nameText.SetMaxLines then
        nameText:SetMaxLines(1)
    end
    nameText:SetPoint("LEFT", textLayer, "LEFT", ACCENT_WIDTH + NAME_PAD, 0)
    nameText:SetWidth(appearance.nameColumnWidth)

    local row = {
        frame = frame,
        bg = bg,
        accent = accent,
        bar = bar,
        spark = spark,
        sparkGlow = sparkGlow,
        sparkEnabled = appearance.spark == true,
        sparkFollowFill = nil,
        textLayer = textLayer,
        nameText = nameText,
        stackHost = stackHost,
        stackText = stackText,
        liveStackText = nil,
        container = nil,
        auraButton = nil,
        boundUnit = nil,
        auraPending = nil,
        applicationCountBound = nil,
        durationTextBound = nil,
        barBoundMode = nil,
        collapseHooked = nil,
        engineShown = nil,
        member = nil,
        collapseEmpty = nil,
    }
    ApplyRowFonts(row, appearance, displayMode)
    RaiseTextLayer(row)
    pcall(function()
        bar:HookScript("OnValueChanged", function()
            PlaceSpark(row)
        end)
        bar:HookScript("OnMinMaxChanged", function()
            PlaceSpark(row)
        end)
        bar:HookScript("OnSizeChanged", function()
            PlaceSpark(row)
        end)
    end)
    return row
end

---@param parent Frame
---@return DebuffMonitorColumnFrame
local function CreateColumn(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    local bg = ColorTex(frame, "BACKGROUND", ROW_BG)
    bg:SetAllPoints()
    local header = CreateFrame("Frame", nil, frame)
    header:EnableMouse(false)
    local headerBg = ColorTex(header, "BACKGROUND", ROW_BG)
    headerBg:SetAllPoints()
    local headerText = Widgets.CreateLabel(header, Fonts.TINY_MUTED)
    headerText:SetJustifyH("LEFT")
    headerText:SetPoint("LEFT", header, "LEFT", ACCENT_WIDTH + NAME_PAD, 0)
    headerText:SetTextColor(Widgets.UnpackColor(HEADER_COLOR))
    ApplyTextShadow(headerText)
    header:Hide()
    return {
        frame = frame,
        bg = bg,
        header = header,
        headerBg = headerBg,
        headerText = headerText,
        rows = {},
        collapse = nil,
    }
end

---Layout-editable compact raid debuff monitor. Callers own encounter lifecycle and member lists.
---@param config DebuffMonitorConfig
---@return DebuffMonitor
function DebuffMonitor.Create(config)
    assert(type(config) == "table", "DebuffMonitor.Create requires config")
    assert(type(config.name) == "string", "DebuffMonitor.Create requires name")
    assert(type(config.slotKey) == "string", "DebuffMonitor.Create requires slotKey")
    local displayMode = config.displayMode or DebuffMonitor.DISPLAY_STACKS
    config.splitBy = config.splitBy or DebuffMonitor.SPLIT_BY_PLAYER
    config.displayMode = displayMode

    local parent = config.parent or UIParent
    local root = CreateFrame("Frame", config.name, parent)
    root:SetFrameStrata("MEDIUM")
    root:SetToplevel(true)
    root:SetClampedToScreen(true)
    root:EnableMouse(false)
    root:SetScale(MainPanelScale())
    if config.getPosition and ns.LayoutEditor and ns.LayoutEditor.ApplyPosition then
        ns.LayoutEditor.ApplyPosition(root, config.getPosition())
    end
    root:Hide()
    if config.listenForScale ~= false then
        ListenForScale(root, config.getPosition)
    end

    local titleHost = CreateFrame("Frame", nil, root)
    titleHost:EnableMouse(false)
    local titleBg = ColorTex(titleHost, "BACKGROUND", ROW_BG)
    titleBg:SetAllPoints()
    local titleText = Widgets.CreateLabel(titleHost, Fonts.SUBTITLE)
    titleText:SetJustifyH("LEFT")
    titleText:SetPoint("LEFT", titleHost, "LEFT", ACCENT_WIDTH + NAME_PAD, 0)
    titleText:SetTextColor(Widgets.UnpackColor(TITLE_COLOR))
    ApplyTextShadow(titleText)
    titleHost:Hide()

    ---@class DebuffMonitor
    local instance = {
        root = root,
        titleHost = titleHost,
        titleBg = titleBg,
        titleText = titleText,
        columns = {},
        boundColumns = nil,
        boundMembers = nil,
        boundStacks = nil,
        liveDisplay = nil,
        enableAuras = nil,
        config = config,
    }

    local applying = false

    local function Relayout()
        if applying or not instance.boundMembers then
            return
        end
        instance:Apply(instance.boundMembers, {
            live = instance.liveDisplay,
            enableAuras = instance.enableAuras,
            values = instance.boundStacks,
        })
    end

    ---@param slot number
    ---@return DebuffMonitorColumnFrame
    local function EnsureColumn(slot)
        local column = instance.columns[slot]
        if column then
            return column
        end
        column = CreateColumn(root)
        instance.columns[slot] = column
        return column
    end

    ---@param column DebuffMonitorColumnFrame
    ---@param slot number
    ---@param appearance DebuffMonitorAppearance
    ---@return DebuffMonitorRow
    local function EnsureRow(column, slot, appearance)
        local row = column.rows[slot]
        if row then
            return row
        end
        row = CreateRow(column.frame, appearance, displayMode)
        column.rows[slot] = row
        return row
    end

    ---@param row DebuffMonitorRow
    ---@param member DebuffMonitorMember|nil
    ---@param stack number|nil
    ---@param live boolean|nil
    ---@param enableAuras boolean|nil
    ---@param appearance DebuffMonitorAppearance
    ---@param collapse boolean|nil
    local function BindRow(row, member, stack, live, enableAuras, appearance, collapse)
        row.member = member
        row.collapseEmpty = collapse == true
        row.sparkFollowFill = live == true
        if not member then
            row.sparkFollowFill = false
            row.nameText:SetText("")
            row.stackText:SetText("")
            DisableAuraContainer(row, config)
            SetMockBar(row, 0)
            return
        end
        SetTruncatedText(row.nameText, member.name)
        local Unit = ns.Api.Unit
        local color = Colors.TEXT
        if Unit and Unit.GetClassColor then
            color = Unit.GetClassColor(member.classFile) or color
        end
        row.nameText:SetTextColor(Widgets.UnpackColor(color))
        ApplyTextShadow(row.nameText)
        row.accent:SetColorTexture(Widgets.UnpackColor(color))
        if live then
            local unit = member.unit
            if type(unit) == "string" and unit ~= "" then
                BindAuraUnit(row, unit, config, enableAuras, Relayout)
            else
                DisableAuraContainer(row, config)
                row.stackText:SetText("")
            end
            return
        end
        DisableAuraContainer(row, config, false)
        if stack ~= nil then
            row.stackText:SetText(FormatMockValue(displayMode, stack))
            SetMockBar(row, MockRatio(displayMode, stack, appearance))
        else
            row.stackText:SetText("")
            SetMockBar(row, 0)
        end
    end

    ---@param column DebuffMonitorColumnFrame
    ---@param row DebuffMonitorRow
    ---@param previous DebuffMonitorRow|nil
    ---@param headerHeight number
    ---@param rowHeight number
    ---@param rowGap number
    ---@param nameWidth number
    ---@param valueWidth number
    local function PlaceRow(column, row, previous, headerHeight, rowHeight, rowGap, nameWidth, valueWidth)
        row.frame:ClearAllPoints()
        row.frame:SetHeight(rowHeight)
        if previous then
            row.frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -rowGap)
            row.frame:SetPoint("TOPRIGHT", previous.frame, "BOTTOMRIGHT", 0, -rowGap)
        else
            row.frame:SetPoint("TOPLEFT", column.frame, "TOPLEFT", 0, -headerHeight)
            row.frame:SetPoint("TOPRIGHT", column.frame, "TOPRIGHT", 0, -headerHeight)
        end
        row.stackHost:SetHeight(rowHeight)
        row.stackHost:SetWidth(valueWidth)
        row.nameText:SetWidth(nameWidth)
        local textParent = row.textLayer or row.frame
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", textParent, "LEFT", ACCENT_WIDTH + NAME_PAD, 0)
        row.stackHost:ClearAllPoints()
        row.stackHost:SetPoint("RIGHT", textParent, "RIGHT", -VALUE_PAD, 0)
        RaiseTextLayer(row)
    end

    function instance:DisableAllAuras()
        for _, column in ipairs(self.columns) do
            for _, row in ipairs(column.rows) do
                DisableAuraContainer(row, config, false)
            end
        end
        self.liveDisplay = false
    end

    function instance:ApplyScale()
        ApplyScale(self.root, config.getPosition)
    end

    ---@param members DebuffMonitorMember[]|nil
    ---@param opts DebuffMonitorApplyOptions|nil
    function instance:Apply(members, opts)
        opts = opts or {}
        applying = true
        local appearance = CurrentAppearance(config)
        local columns = Columns.BuildColumns(config, members)
        self.boundMembers = members or {}
        self.boundColumns = columns
        self.boundStacks = opts.values
        self.liveDisplay = opts.live == true
        self.enableAuras = opts.enableAuras
        local live = self.liveDisplay
        local aurasOn = live and opts.enableAuras ~= false
        local values = opts.values
        PaintPanel(self.titleBg, appearance)
        local rowHeight = appearance.rowHeight
        local rowGap = appearance.rowGap
        local columnGap = appearance.columnGap
        local nameWidth = appearance.nameColumnWidth
        local valueWidth = appearance.valueColumnWidth
        local columnWidth = DebuffMonitor.ColumnWidth(appearance)
        local showTitle = config.showTitle == true
        local titleHeight = 0
        if showTitle then
            titleHeight = appearance.titleHeight
            self.titleHost:ClearAllPoints()
            self.titleHost:SetPoint("TOPLEFT", self.root, "TOPLEFT", 0, 0)
            self.titleHost:SetPoint("TOPRIGHT", self.root, "TOPRIGHT", 0, 0)
            self.titleHost:SetHeight(titleHeight)
            self.titleText:SetText(config.title or "")
            ApplyFont(self.titleText, Fonts.SUBTITLE, appearance.nameFontSize, TITLE_COLOR)
            self.titleHost:Show()
        else
            self.titleText:SetText("")
            self.titleHost:Hide()
        end
        local showHeaders = config.showSubgroupHeaders == true
        local populated = #columns
        local maxBody = 0
        for slot = 1, populated do
            local data = columns[slot]
            local column = EnsureColumn(slot)
            column.collapse = data.collapse
            PaintPanel(column.bg, appearance)
            PaintPanel(column.headerBg, appearance)
            column.frame:Show()
            column.frame:ClearAllPoints()
            column.frame:SetPoint("TOPLEFT", self.root, "TOPLEFT", (slot - 1) * (columnWidth + columnGap), -titleHeight)
            local headerHeight = 0
            if showHeaders and data.label then
                headerHeight = appearance.headerHeight
                column.header:ClearAllPoints()
                column.header:SetPoint("TOPLEFT", column.frame, "TOPLEFT", 0, 0)
                column.header:SetPoint("TOPRIGHT", column.frame, "TOPRIGHT", 0, 0)
                column.header:SetHeight(headerHeight)
                column.headerText:SetText(data.label)
                ApplyFont(column.headerText, Fonts.TINY_MUTED, appearance.nameFontSize, HEADER_COLOR)
                column.header:Show()
            else
                if column.headerText then
                    column.headerText:SetText("")
                end
                if column.header then
                    column.header:Hide()
                end
            end
            local visible = 0
            local previousRow
            for rowSlot = 1, #data.members do
                local member = data.members[rowSlot]
                local row = EnsureRow(column, rowSlot, appearance)
                local stack = MockValue(values, member)
                BindRow(row, member, stack, live, aurasOn, appearance, data.collapse)
                ApplyRowFonts(row, appearance, displayMode)
                PaintPanel(row.bg, appearance)
                PaintBar(row, appearance)
                local hideCollapsed = false
                if data.collapse then
                    if live then
                        hideCollapsed = row.engineShown == false
                    else
                        hideCollapsed = stack == nil
                    end
                end
                if hideCollapsed then
                    row.frame:Hide()
                else
                    PlaceRow(column, row, previousRow, headerHeight, rowHeight, rowGap, nameWidth, valueWidth)
                    row.frame:Show()
                    previousRow = row
                    visible = visible + 1
                end
            end
            for rowSlot = #data.members + 1, #column.rows do
                local row = column.rows[rowSlot]
                BindRow(row, nil, nil, false, false, appearance, false)
                row.frame:Hide()
            end
            local bodyHeight = headerHeight + visible * rowHeight + math.max(visible - 1, 0) * rowGap
            column.frame:SetSize(columnWidth, bodyHeight)
            if bodyHeight > maxBody then
                maxBody = bodyHeight
            end
        end
        for slot = populated + 1, #self.columns do
            local column = self.columns[slot]
            column.frame:Hide()
            for _, row in ipairs(column.rows) do
                BindRow(row, nil, nil, false, false, appearance, false)
                row.frame:Hide()
            end
        end
        self:ApplyScale()
        applying = false
        if populated == 0 then
            self.root:SetSize(0, titleHeight)
            return
        end
        self.root:SetSize(populated * columnWidth + (populated - 1) * columnGap, titleHeight + maxBody)
    end

    function instance:Refresh()
        if self.boundMembers then
            self:Apply(self.boundMembers, {
                live = self.liveDisplay,
                enableAuras = self.enableAuras,
                values = self.boundStacks,
            })
            return
        end
        self:ApplyScale()
    end

    return instance
end

---@param count number
---@param options { groupSize: number|nil }|nil
---@return DebuffMonitorMember[]
function DebuffMonitor.BuildPreviewMembers(count, options)
    options = options or {}
    local groupSize = options.groupSize or DEFAULT_MAX_GROUP_SIZE
    local members = {}
    local size = math.max(0, math.floor(count or 0))
    for index = 1, size do
        members[index] = {
            name = "Player" .. index,
            index = index,
            subgroup = math.ceil(index / groupSize),
            classFile = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1],
            unit = "raid" .. index,
        }
    end
    return members
end

---@param members DebuffMonitorMember[]
---@param displayMode string|nil
---@return table<number, number>
function DebuffMonitor.PreviewValues(members, displayMode)
    local values = {}
    displayMode = displayMode or DebuffMonitor.DISPLAY_STACKS
    for _, member in ipairs(members) do
        if displayMode == DebuffMonitor.DISPLAY_DURATION then
            values[member.index] = 4 + (member.index % 12)
        else
            values[member.index] = (member.index - 1) % 10
        end
    end
    return values
end

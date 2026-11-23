---Compact interrupt-chain HUD card that paints InterruptChainHUDState.
local _, ns = ...
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local InterruptChainHUD = {}
ns.InterruptChainHUD = InterruptChainHUD

local PAD_TOP = 7
local PAD_BOTTOM = 7
local PAD_LEFT = 10
local PAD_RIGHT = 9
local ROW_GAP = 8
local MAX_NODES = 6
local TOP_HEIGHT = 17
local NODE_HEIGHT = 20
local NODE_DIGIT_SIZE = 14
local NODE_GAP = 5
local NODE_MAX_WIDTH = 34
local CAST_HEIGHT = 11
local CAST_IDLE_HEIGHT = 2
local ACCENT_WIDTH = 3
local ACCENT_INSET = 1
local GLOW_WIDTH = 75
local ICON_SIZE = 12
local HEADER_SIZE = 12
local PLAYHEAD_WIDTH = 12
local PLAYHEAD_HEIGHT = 2
local PLAYHEAD_GAP = 3
local RIM_HEIGHT = 1
local TEXT_SHADOW_A = 0.85
local ALPHA_WAITING = 0.88
local ALPHA_ACTIVE = 1
local ALPHA_DONE = 0.82
local CARD_TOP_A = 0.78
local CARD_BOTTOM_A = 0.84
local CARD_DONE_TOP_A = 0.64
local CARD_DONE_BOTTOM_A = 0.70
local WASH_A = 0.14
local RIM_A = 0.08
local KEYCAP_RIM_A = 0.40
local FILL_WAITING = { r = Colors.TRANSPARENT.r, g = Colors.TRANSPARENT.g, b = Colors.TRANSPARENT.b, a = 0.30 }
local BORDER_UPCOMING = Colors.BORDER_FAINT
local FILL_DONE = { r = Colors.TRANSPARENT.r, g = Colors.TRANSPARENT.g, b = Colors.TRANSPARENT.b, a = 0.20 }
local BORDER_DONE = { r = Colors.BORDER_FAINT.r, g = Colors.BORDER_FAINT.g, b = Colors.BORDER_FAINT.b, a = 0.04 }
local TEXT_DONE = { r = Colors.TEXT_MUTED.r, g = Colors.TEXT_MUTED.g, b = Colors.TEXT_MUTED.b, a = 0.35 }
local FILL_CURRENT = {
    r = Colors.SURFACE_RAISED.r,
    g = Colors.SURFACE_RAISED.g,
    b = Colors.SURFACE_RAISED.b,
    a = 0.45,
}
local FILL_ON_DECK_A = 0.22
local BORDER_WAITING_A = 0.45
local TEXT_WAITING_A = 0.85
local CAST_TROUGH = { r = Colors.TRANSPARENT.r, g = Colors.TRANSPARENT.g, b = Colors.TRANSPARENT.b, a = 0.5 }
local CARD_BORDER = {
    r = Colors.FEATURE_CARD_BORDER.r,
    g = Colors.FEATURE_CARD_BORDER.g,
    b = Colors.FEATURE_CARD_BORDER.b,
    a = 0.75,
}
local KEYCAP_TOP_LIFT = 0.22
local KEYCAP_TOP_LIFT_DARK = 0.32
local KEYCAP_BASE_LIFT_DARK = 0.10
local KEYCAP_DARK_LUMA = 0.62
local RAID_TARGET_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local MODE_WAITING = "waiting"
local MODE_ON_DECK = "onDeck"
local MODE_YOUR_TURN = "yourTurn"
local MODE_DONE = "done"

---@alias InterruptChainHUDTheme "cyan"|"blue"|"violet"|"amber"

---@class InterruptChainHUDState
---@field total integer
---@field completed integer
---@field myIndices integer[]
---@field label string|nil
---@field icon string|number|nil
---@field currentAssignee string|nil
---@field currentAssigneeClass string|nil
---@field castSpellName string|nil
---@field castStartTime number|nil
---@field castEndTime number|nil
---@field theme InterruptChainHUDTheme|nil
---@field accentColor { r: number, g: number, b: number }|nil

---@class InterruptChainHUD: Frame
---@field SetState fun(self: InterruptChainHUD, state: InterruptChainHUDState)
---@field GetState fun(self: InterruptChainHUD): InterruptChainHUDState

---@param value any
---@return integer
local function WholeNumber(value)
    return math.floor(tonumber(value) or 0)
end

---@param total integer
---@return integer
local function ClampTotal(total)
    if total < 0 then
        return 0
    end
    if total > MAX_NODES then
        return MAX_NODES
    end
    return total
end

---@param completed integer
---@param total integer
---@return integer
local function ClampCompleted(completed, total)
    if completed < 0 then
        return 0
    end
    if completed > total then
        return total
    end
    return completed
end

---@return number
local function Now()
    local Timer = ns.Api and ns.Api.Timer
    if Timer and Timer.GetTime then
        return Timer.GetTime()
    end
    return GetTime()
end

---@param name string|nil
---@param classFile string|nil
---@return string|nil
local function ResolveClassFile(name, classFile)
    if type(classFile) == "string" and classFile ~= "" then
        return classFile
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local Group = ns.Api and ns.Api.Group
    if not Group or not Group.GetRaidMembers then
        return nil
    end
    local members = Group.GetRaidMembers()
    for index = 1, #members do
        local member = members[index]
        if member.name == name or member.fullName == name then
            return member.classFile
        end
        local short = member.fullName and member.fullName:match("^([^-]+)")
        if short == name then
            return member.classFile
        end
    end
    return nil
end

---@param classFile string|nil
---@return { r: number, g: number, b: number }
local function ClassColor(classFile)
    local Unit = ns.Api and ns.Api.Unit
    if classFile and Unit and Unit.GetClassColor then
        local color = Unit.GetClassColor(classFile)
        if color then
            return color
        end
    end
    return Colors.TEXT_PRIMARY
end

---@param count integer
---@param lockedWidth number|nil
---@return number
local function CardWidth(count, lockedWidth)
    if lockedWidth then
        return lockedWidth
    end
    local nodes = math.max(count, 1)
    return PAD_LEFT + nodes * NODE_MAX_WIDTH + math.max(nodes - 1, 0) * NODE_GAP + PAD_RIGHT
end

---@param tex Texture
---@param orientation "HORIZONTAL"|"VERTICAL"
---@param from { r: number, g: number, b: number }
---@param fromA number
---@param to { r: number, g: number, b: number }
---@param toA number
local function PaintGradient(tex, orientation, from, fromA, to, toA)
    tex:SetTexture(Assets.Textures.WHITE)
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orientation, CreateColor(from.r, from.g, from.b, fromA), CreateColor(to.r, to.g, to.b, toA))
        return
    end
    tex:SetVertexColor(from.r, from.g, from.b, (fromA + toA) * 0.5)
end

---@param tex Texture
---@param color { r: number, g: number, b: number, a: number|nil }
---@param alpha number|nil
local function PaintSolid(tex, color, alpha)
    local a = alpha or color.a or 1
    PaintGradient(tex, "VERTICAL", color, a, color, a)
end

---@param frame Frame
---@param border table|nil
local function PaintBorder(frame, border)
    frame:SetBackdropColor(0, 0, 0, 0)
    if border then
        frame:SetBackdropBorderColor(Widgets.UnpackColor(border))
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

-- Twin Fangs region cards (右前 / 左后). Not Assets tokens; HUD and panel share these values.
local THEME_BLUE = { r = 0.45, g = 0.62, b = 0.90, a = 1 }
local THEME_VIOLET = { r = 0.62, g = 0.50, b = 0.86, a = 1 }

local THEMES = {
    cyan = Colors.ACCENT,
    blue = THEME_BLUE,
    violet = THEME_VIOLET,
    amber = Colors.WARNING,
}

---@param theme string|nil
---@return { r: number, g: number, b: number }
function InterruptChainHUD.ThemeColor(theme)
    return THEMES[theme] or THEMES.cyan
end

---@param color any
---@return boolean
local function IsRgb(color)
    return type(color) == "table"
        and type(color.r) == "number"
        and type(color.g) == "number"
        and type(color.b) == "number"
end

---@param color { r: number, g: number, b: number }
---@param alpha number
---@return { r: number, g: number, b: number, a: number }
local function WithAlpha(color, alpha)
    return { r = color.r, g = color.g, b = color.b, a = alpha }
end

---@param color { r: number, g: number, b: number }
---@param amount number
---@return { r: number, g: number, b: number }
local function MixWhite(color, amount)
    return {
        r = color.r + (1 - color.r) * amount,
        g = color.g + (1 - color.g) * amount,
        b = color.b + (1 - color.b) * amount,
    }
end

---@param color { r: number, g: number, b: number }
---@return number
local function Luma(color)
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
end

---@param color { r: number, g: number, b: number }
---@return { r: number, g: number, b: number }
---@return { r: number, g: number, b: number }
local function KeycapFill(color)
    if Luma(color) < KEYCAP_DARK_LUMA then
        return MixWhite(color, KEYCAP_TOP_LIFT_DARK), MixWhite(color, KEYCAP_BASE_LIFT_DARK)
    end
    return MixWhite(color, KEYCAP_TOP_LIFT), color
end

---@param state InterruptChainHUDState|nil
---@param defaultTheme string|nil
---@param defaultAccent { r: number, g: number, b: number }|nil
---@return { r: number, g: number, b: number }
---@return string|nil
local function ResolveThemeColor(state, defaultTheme, defaultAccent)
    state = state or {}
    if IsRgb(state.accentColor) then
        local theme = state.theme
        if type(theme) ~= "string" or not THEMES[theme] then
            theme = nil
        end
        return state.accentColor, theme
    end
    local theme = state.theme
    if type(theme) == "string" and THEMES[theme] then
        return THEMES[theme], theme
    end
    if IsRgb(defaultAccent) then
        if type(defaultTheme) == "string" and THEMES[defaultTheme] then
            return defaultAccent, defaultTheme
        end
        return defaultAccent, nil
    end
    if type(defaultTheme) == "string" and THEMES[defaultTheme] then
        return THEMES[defaultTheme], defaultTheme
    end
    return THEMES.cyan, nil
end

---@param mode string
---@param themeColor { r: number, g: number, b: number }
---@return table
local function CastFillColor(mode, themeColor)
    if mode == MODE_YOUR_TURN then
        return themeColor
    end
    return Colors.BORDER_SUBTLE
end

---@param icon string|number|nil
---@return string|nil
local function IconTexture(icon)
    if type(icon) == "number" then
        local index = math.floor(icon)
        if index >= 1 and index <= 8 then
            return RAID_TARGET_ICON:format(index)
        end
        return nil
    end
    if type(icon) == "string" and icon ~= "" then
        return icon
    end
    return nil
end

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---@param label FontString
---@param size number
local function ApplyHudFont(label, path, size)
    if label.SetFont then
        label:SetFont(path, size, "")
    end
    if label.SetShadowColor then
        label:SetShadowColor(0, 0, 0, TEXT_SHADOW_A)
    end
    if label.SetShadowOffset then
        label:SetShadowOffset(1, -1)
    end
end

---@param label FontString
---@param onAccent boolean|nil
local function ApplyNodeDigitFont(label, onAccent)
    local digitStyle = Assets.FontStyles and Assets.FontStyles[Fonts.OVERLAY_DIGIT]
    local path = (digitStyle and digitStyle.path) or DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
    ApplyHudFont(label, path, NODE_DIGIT_SIZE)
    if onAccent then
        if label.SetShadowOffset then
            label:SetShadowOffset(0, 0)
        end
        if label.SetShadowColor then
            label:SetShadowColor(0, 0, 0, 0)
        end
    end
end

---@param label FontString
local function ApplyHeaderFont(label)
    local style = Assets.FontStyles and Assets.FontStyles[Fonts.STATUS_HUD_TITLE]
    local path = (style and style.path) or STANDARD_TEXT_FONT
    ApplyHudFont(label, path, HEADER_SIZE)
end

-- Nested Create captures one table instead of exceeding Lua 5.1's 60-upvalue limit.
local K = {
    MAX_NODES = MAX_NODES,
    MODE_WAITING = MODE_WAITING,
    MODE_ON_DECK = MODE_ON_DECK,
    MODE_YOUR_TURN = MODE_YOUR_TURN,
    MODE_DONE = MODE_DONE,
    TOP_HEIGHT = TOP_HEIGHT,
    ROW_GAP = ROW_GAP,
    CAST_HEIGHT = CAST_HEIGHT,
    CAST_IDLE_HEIGHT = CAST_IDLE_HEIGHT,
    ALPHA_DONE = ALPHA_DONE,
    ALPHA_WAITING = ALPHA_WAITING,
    ALPHA_ACTIVE = ALPHA_ACTIVE,
    CARD_TOP_A = CARD_TOP_A,
    CARD_BOTTOM_A = CARD_BOTTOM_A,
    CARD_DONE_TOP_A = CARD_DONE_TOP_A,
    CARD_DONE_BOTTOM_A = CARD_DONE_BOTTOM_A,
    WASH_A = WASH_A,
    ApplyNodeDigitFont = ApplyNodeDigitFont,
    WholeNumber = WholeNumber,
    ClampTotal = ClampTotal,
    ClampCompleted = ClampCompleted,
    Now = Now,
    IconTexture = IconTexture,
    CastFillColor = CastFillColor,
    PaintGradient = PaintGradient,
    ClassColor = ClassColor,
    ResolveClassFile = ResolveClassFile,
}

---@class InterruptChainHUDCreateOptions
---@field name string|nil
---@field parent Frame|nil
---@field width number|nil
---@field theme InterruptChainHUDTheme|nil
---@field accentColor { r: number, g: number, b: number }|nil

---@param options InterruptChainHUDCreateOptions|nil
---@return InterruptChainHUD
function InterruptChainHUD.Create(options)
    options = options or {}
    local parent = options.parent or UIParent
    local lockedWidth = options.width
    local defaultTheme = options.theme
    local defaultAccent = options.accentColor
    local width = CardWidth(4, lockedWidth)

    local frame = Widgets.CreateSurface(parent, Colors.TRANSPARENT, CARD_BORDER, options.name)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetWidth(width)
    frame:SetScale(MainPanelScale())
    frame:Hide()

    local cardFill = frame:CreateTexture(nil, "BACKGROUND")
    cardFill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    cardFill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    PaintGradient(cardFill, "VERTICAL", Colors.FEATURE_CARD_BG, CARD_TOP_A, Colors.MENU_CONTENT, CARD_BOTTOM_A)

    local topRim = frame:CreateTexture(nil, "ARTWORK")
    topRim:SetTexture(Assets.Textures.WHITE)
    topRim:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    topRim:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    topRim:SetHeight(RIM_HEIGHT)
    topRim:SetVertexColor(Colors.BORDER_FAINT.r, Colors.BORDER_FAINT.g, Colors.BORDER_FAINT.b, RIM_A)

    local wash = frame:CreateTexture(nil, "BACKGROUND")
    wash:SetPoint("TOPLEFT", frame, "TOPLEFT", ACCENT_WIDTH, -1)
    wash:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ACCENT_WIDTH, 1)
    wash:SetWidth(GLOW_WIDTH)
    wash:Hide()

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(Assets.Textures.WHITE)
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -ACCENT_INSET)
    accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, ACCENT_INSET)
    accent:SetWidth(ACCENT_WIDTH)
    accent:SetAlpha(0)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_LEFT, -PAD_TOP)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_RIGHT, PAD_BOTTOM)

    local stack = Layout.Stack(content, {
        paddingX = 0,
        paddingY = 0,
        spacing = 0,
    })
    local top = stack:AddRow(TOP_HEIGHT)
    local track = stack:AddRow(NODE_HEIGHT, ROW_GAP)
    local castRow = stack:AddRow(CAST_IDLE_HEIGHT, Spacing.TINY)

    local icon = top:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", top, "LEFT")
    icon:Hide()

    local label = Widgets.CreateLabel(top, Fonts.STATUS_HUD_TITLE)
    ApplyHeaderFont(label)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetPoint("LEFT", top, "LEFT")

    local assignee = Widgets.CreateLabel(top, Fonts.STATUS_HUD_TITLE)
    ApplyHeaderFont(assignee)
    assignee:SetJustifyH("RIGHT")
    assignee:SetWordWrap(false)
    assignee:SetPoint("RIGHT", top, "RIGHT")

    ---@type Frame[]
    local nodes = {}
    ---@type FontString[]
    local nodeLabels = {}
    ---@type Texture[]
    local nodeFills = {}
    ---@type Texture[]
    local nodeRims = {}
    for index = 1, MAX_NODES do
        local node = Widgets.CreateSurface(track, Colors.TRANSPARENT, BORDER_UPCOMING)
        node:Hide()
        nodes[index] = node
        local fill = node:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(node)
        nodeFills[index] = fill
        local rim = node:CreateTexture(nil, "ARTWORK")
        rim:SetTexture(Assets.Textures.WHITE)
        rim:SetPoint("TOPLEFT", node, "TOPLEFT", 1, -1)
        rim:SetPoint("TOPRIGHT", node, "TOPRIGHT", -1, -1)
        rim:SetHeight(RIM_HEIGHT)
        rim:SetVertexColor(Colors.BORDER_FAINT.r, Colors.BORDER_FAINT.g, Colors.BORDER_FAINT.b, KEYCAP_RIM_A)
        rim:Hide()
        nodeRims[index] = rim
        local nodeLabel = Widgets.CreateLabel(node, Fonts.OVERLAY_DIGIT)
        ApplyNodeDigitFont(nodeLabel)
        nodeLabel:SetJustifyH("CENTER")
        nodeLabel:SetWordWrap(false)
        nodeLabel:SetPoint("LEFT", node, "LEFT")
        nodeLabel:SetPoint("RIGHT", node, "RIGHT")
        nodeLabels[index] = nodeLabel
    end

    local playhead = content:CreateTexture(nil, "OVERLAY")
    playhead:SetTexture(Assets.Textures.WHITE)
    playhead:SetSize(PLAYHEAD_WIDTH, PLAYHEAD_HEIGHT)
    playhead:Hide()

    local castTrough = castRow:CreateTexture(nil, "BACKGROUND")
    castTrough:SetAllPoints(castRow)
    PaintSolid(castTrough, CAST_TROUGH)
    castTrough:Hide()

    local castFill = castRow:CreateTexture(nil, "ARTWORK")
    castFill:SetTexture(Assets.Textures.WHITE)
    castFill:SetPoint("TOPLEFT", castRow, "TOPLEFT")
    castFill:SetPoint("BOTTOMLEFT", castRow, "BOTTOMLEFT")
    castFill:SetWidth(1)
    castFill:Hide()

    local castFillRim = castRow:CreateTexture(nil, "OVERLAY")
    castFillRim:SetTexture(Assets.Textures.WHITE)
    castFillRim:SetPoint("TOPLEFT", castFill, "TOPLEFT")
    castFillRim:SetPoint("TOPRIGHT", castFill, "TOPRIGHT")
    castFillRim:SetHeight(RIM_HEIGHT)
    castFillRim:SetVertexColor(Colors.BORDER_FAINT.r, Colors.BORDER_FAINT.g, Colors.BORDER_FAINT.b, KEYCAP_RIM_A)
    castFillRim:Hide()

    local castName = Widgets.CreateLabel(castRow, Fonts.TINY_MUTED)
    castName:SetJustifyH("LEFT")
    castName:SetWordWrap(false)
    castName:SetPoint("LEFT", castRow, "LEFT", Spacing.TINY, 0)
    castName:SetPoint("RIGHT", castRow, "CENTER", -Spacing.TINY, 0)
    castName:Hide()

    local castTime = Widgets.CreateLabel(castRow, Fonts.TINY_MUTED)
    castTime:SetJustifyH("RIGHT")
    castTime:SetWordWrap(false)
    castTime:SetPoint("RIGHT", castRow, "RIGHT", -Spacing.TINY, 0)
    ApplyHudFont(castName, STANDARD_TEXT_FONT, 10)
    ApplyHudFont(castTime, STANDARD_TEXT_FONT, 10)
    castTime:Hide()

    local applied = {
        total = -1,
        completed = -1,
        mineCount = 0,
        label = "",
        icon = nil,
        assignee = "",
        classFile = nil,
        castName = nil,
        castStart = nil,
        castEnd = nil,
        mode = MODE_WAITING,
        showingTop = true,
        showingCast = false,
        remainingKey = "",
        theme = "",
        accentR = nil,
        accentG = nil,
        accentB = nil,
        accentFromState = false,
    }
    ---@type integer[]
    local appliedMine = {}
    ---@type integer[]
    local incomingMine = {}
    ---@type boolean[]
    local mineMask = { false, false, false, false, false, false }
    local ui = {
        frame = frame,
        cardFill = cardFill,
        wash = wash,
        accent = accent,
        stack = stack,
        top = top,
        track = track,
        castRow = castRow,
        icon = icon,
        label = label,
        assignee = assignee,
        playhead = playhead,
        nodes = nodes,
        nodeLabels = nodeLabels,
        nodeFills = nodeFills,
        nodeRims = nodeRims,
        castTrough = castTrough,
        castFill = castFill,
        castFillRim = castFillRim,
        castName = castName,
        castTime = castTime,
    }

    local function Resize()
        local count = applied.total > 0 and applied.total or 4
        width = CardWidth(count, lockedWidth)
        ui.frame:SetSize(width, ui.stack:GetHeight() + PAD_TOP + PAD_BOTTOM)
    end

    local function LayoutNodes(count)
        if count < 1 then
            return
        end
        local rowWidth = ui.track:GetWidth()
        if not rowWidth or rowWidth <= 0 then
            rowWidth = width - PAD_LEFT - PAD_RIGHT
        end
        local nodeWidth = NODE_MAX_WIDTH
        local used = count * nodeWidth + math.max(count - 1, 0) * NODE_GAP
        if used > rowWidth then
            nodeWidth = math.max((rowWidth - NODE_GAP * math.max(count - 1, 0)) / count, 1)
            used = rowWidth
        end
        local startX = math.max((rowWidth - used) / 2, 0)
        for index = 1, count do
            local node = ui.nodes[index]
            node:ClearAllPoints()
            node:SetPoint("LEFT", ui.track, "LEFT", startX + (index - 1) * (nodeWidth + NODE_GAP), 0)
            node:SetSize(nodeWidth, NODE_HEIGHT)
        end
    end

    local function ShowNodes(count)
        for index = 1, MAX_NODES do
            if index <= count then
                ui.nodes[index]:Show()
            else
                ui.nodes[index]:Hide()
            end
        end
        if count > 0 then
            LayoutNodes(count)
        end
    end

    local function StopCastUpdates()
        ui.frame:SetScript("OnUpdate", nil)
    end

    local function PaintCastProgress()
        local startTime = applied.castStart
        local endTime = applied.castEnd
        if not startTime or not endTime then
            return
        end
        local now = Now()
        if now >= endTime then
            StopCastUpdates()
            ui.stack:SetEntryHeight(ui.castRow, CAST_IDLE_HEIGHT)
            ui.castTrough:Hide()
            ui.castFill:Hide()
            ui.castFillRim:Hide()
            ui.castName:Hide()
            ui.castTime:Hide()
            applied.showingCast = false
            applied.remainingKey = ""
            Resize()
            return
        end
        local duration = endTime - startTime
        local progress = 0
        if duration > 0 then
            progress = (now - startTime) / duration
            if progress < 0 then
                progress = 0
            elseif progress > 1 then
                progress = 1
            end
        end
        local rowWidth = ui.castRow:GetWidth()
        if not rowWidth or rowWidth <= 0 then
            rowWidth = width - PAD_LEFT - PAD_RIGHT
        end
        ui.castFill:SetWidth(math.max(rowWidth * progress, 1))
        local remaining = endTime - now
        local key = string.format("%.1f", remaining)
        if key ~= applied.remainingKey then
            applied.remainingKey = key
            ui.castTime:SetText(key)
        end
    end

    local function StartCastUpdates()
        ui.frame:SetScript("OnUpdate", PaintCastProgress)
        PaintCastProgress()
    end

    ---@param mode string
    ---@param index integer
    ---@param currentIndex integer
    ---@param isMine boolean
    ---@param completed boolean
    ---@param themeColor { r: number, g: number, b: number }
    local function PaintNode(mode, index, currentIndex, isMine, completed, themeColor)
        local node = ui.nodes[index]
        local nodeLabel = ui.nodeLabels[index]
        local fill = ui.nodeFills[index]
        local rim = ui.nodeRims[index]
        local border = BORDER_UPCOMING
        local text = Colors.TEXT_BODY
        local showRim = false
        nodeLabel:SetText(tostring(index))
        if completed then
            PaintSolid(fill, FILL_DONE)
            border = BORDER_DONE
            text = TEXT_DONE
        elseif isMine and mode == MODE_YOUR_TURN and index == currentIndex then
            local topFill, base = KeycapFill(themeColor)
            PaintGradient(fill, "VERTICAL", topFill, 1, base, 1)
            border = nil
            text = Colors.TEXT_ON_ACCENT
            showRim = true
        elseif isMine and mode == MODE_ON_DECK and index == currentIndex + 1 then
            PaintSolid(fill, WithAlpha(themeColor, FILL_ON_DECK_A))
            border = WithAlpha(themeColor, 1)
            text = Colors.TEXT_PRIMARY
        elseif isMine then
            PaintSolid(fill, FILL_WAITING)
            border = WithAlpha(themeColor, BORDER_WAITING_A)
            text = WithAlpha(themeColor, TEXT_WAITING_A)
        elseif index == currentIndex then
            PaintSolid(fill, FILL_CURRENT)
            text = Colors.TEXT_PRIMARY
        else
            PaintSolid(fill, FILL_WAITING)
        end
        PaintBorder(node, border)
        if showRim then
            rim:Show()
        else
            rim:Hide()
        end
        K.ApplyNodeDigitFont(nodeLabel, showRim)
        nodeLabel:SetTextColor(Widgets.UnpackColor(text))
    end

    ---@param mode string
    ---@param currentIndex integer
    ---@param themeColor { r: number, g: number, b: number }
    local function PaintTrack(mode, currentIndex, themeColor)
        local total = applied.total
        for index = 1, total do
            PaintNode(mode, index, currentIndex, mineMask[index], index <= applied.completed, themeColor)
        end
        if currentIndex >= 1 and currentIndex <= total then
            local color = Colors.TEXT_PRIMARY
            if mode == MODE_YOUR_TURN then
                color = themeColor
            end
            ui.playhead:ClearAllPoints()
            ui.playhead:SetPoint("BOTTOM", ui.nodes[currentIndex], "TOP", 0, PLAYHEAD_GAP)
            ui.playhead:SetVertexColor(Widgets.UnpackColor(color))
            ui.playhead:Show()
        else
            ui.playhead:Hide()
        end
    end

    local function LayoutTop(showIcon, showLabel, showAssignee)
        ui.icon:ClearAllPoints()
        ui.label:ClearAllPoints()
        ui.assignee:ClearAllPoints()
        local labelAnchor = ui.top
        local labelRelative = "LEFT"
        if showIcon then
            ui.icon:SetPoint("LEFT", ui.top, "LEFT")
            ui.icon:Show()
            labelAnchor = ui.icon
            labelRelative = "RIGHT"
        else
            ui.icon:Hide()
        end
        if showLabel then
            ui.label:SetPoint("LEFT", labelAnchor, labelRelative, showIcon and Spacing.TINY or 0, 0)
            ui.label:Show()
        else
            ui.label:Hide()
        end
        ui.assignee:SetPoint("RIGHT", ui.top, "RIGHT")
        if showAssignee then
            ui.assignee:Show()
        else
            ui.assignee:Hide()
        end
    end

    ui.layoutTop = LayoutTop
    ui.showNodes = ShowNodes
    ui.paintTrack = PaintTrack
    ui.startCast = StartCastUpdates
    ui.stopCast = StopCastUpdates
    ui.paintCast = PaintCastProgress
    ui.resize = Resize

    ---@param state InterruptChainHUDState
    function frame:SetState(state)
        assert(type(state) == "table", "InterruptChainHUD SetState requires a state table")

        local total = K.ClampTotal(K.WholeNumber(state.total))
        local completed = K.ClampCompleted(K.WholeNumber(state.completed), total)
        local labelText = state.label
        local iconValue = state.icon
        local assigneeName = state.currentAssignee
        local classFile = state.currentAssigneeClass
        local spellName = state.castSpellName
        local castStart = state.castStartTime
        local castEnd = state.castEndTime
        local mineCount = 0
        local indices = state.myIndices
        if type(indices) == "table" then
            for i = 1, #indices do
                local slot = K.WholeNumber(indices[i])
                if slot >= 1 and slot <= K.MAX_NODES then
                    mineCount = mineCount + 1
                    incomingMine[mineCount] = slot
                end
            end
        end

        for i = mineCount + 1, #incomingMine do
            incomingMine[i] = nil
        end
        for i = 1, K.MAX_NODES do
            mineMask[i] = false
        end
        local nextMine
        local playerDone = mineCount > 0
        for i = 1, mineCount do
            local slot = incomingMine[i]
            mineMask[slot] = true
            if slot > completed then
                playerDone = false
                if not nextMine or slot < nextMine then
                    nextMine = slot
                end
            end
        end

        local currentIndex = completed + 1
        local mode = K.MODE_WAITING
        if playerDone then
            mode = K.MODE_DONE
        elseif nextMine then
            local stepsAway = nextMine - currentIndex
            if stepsAway <= 0 then
                mode = K.MODE_YOUR_TURN
            elseif stepsAway == 1 then
                mode = K.MODE_ON_DECK
            else
                mode = K.MODE_WAITING
            end
        end

        if type(labelText) ~= "string" or labelText == "" then
            labelText = nil
        end
        if type(assigneeName) ~= "string" or assigneeName == "" then
            assigneeName = nil
        end
        if type(spellName) ~= "string" or spellName == "" then
            spellName = nil
        end
        if type(castStart) ~= "number" or type(castEnd) ~= "number" then
            castStart = nil
            castEnd = nil
        end

        local showTop = labelText ~= nil or iconValue ~= nil or assigneeName ~= nil
        local casting = castEnd ~= nil and castEnd > K.Now()
        local iconPath = K.IconTexture(iconValue)
        local themeColor, themeName = ResolveThemeColor(state, defaultTheme, defaultAccent)
        local accentFromState = IsRgb(state.accentColor)

        local sameMine = mineCount == applied.mineCount
        if sameMine then
            for i = 1, mineCount do
                if incomingMine[i] ~= appliedMine[i] then
                    sameMine = false
                    break
                end
            end
        end

        if
            sameMine
            and applied.total == total
            and applied.completed == completed
            and applied.label == (labelText or "")
            and applied.icon == iconValue
            and applied.assignee == (assigneeName or "")
            and applied.classFile == classFile
            and applied.castName == spellName
            and applied.castStart == castStart
            and applied.castEnd == castEnd
            and applied.mode == mode
            and applied.showingTop == showTop
            and applied.showingCast == casting
            and applied.theme == (themeName or "")
            and applied.accentR == themeColor.r
            and applied.accentG == themeColor.g
            and applied.accentB == themeColor.b
            and applied.accentFromState == accentFromState
        then
            if casting then
                ui.paintCast()
            end
            return
        end

        for i = 1, mineCount do
            appliedMine[i] = incomingMine[i]
        end
        for i = mineCount + 1, applied.mineCount do
            appliedMine[i] = nil
        end

        applied.total = total
        applied.completed = completed
        applied.mineCount = mineCount
        applied.label = labelText or ""
        applied.icon = iconValue
        applied.assignee = assigneeName or ""
        applied.classFile = classFile
        applied.castName = spellName
        applied.castStart = castStart
        applied.castEnd = castEnd
        applied.mode = mode
        applied.showingTop = showTop
        applied.showingCast = casting
        applied.theme = themeName or ""
        applied.accentR = themeColor.r
        applied.accentG = themeColor.g
        applied.accentB = themeColor.b
        applied.accentFromState = accentFromState

        if mode == K.MODE_DONE then
            self:SetAlpha(K.ALPHA_DONE)
        elseif mode == K.MODE_WAITING then
            self:SetAlpha(K.ALPHA_WAITING)
        else
            self:SetAlpha(K.ALPHA_ACTIVE)
        end

        local showAccent = mode == K.MODE_ON_DECK or mode == K.MODE_YOUR_TURN
        local showWash = mode == K.MODE_YOUR_TURN
        local glow = themeColor
        ui.accent:SetVertexColor(Widgets.UnpackColor(glow))
        ui.accent:SetAlpha(showAccent and 1 or 0)
        if showWash then
            K.PaintGradient(ui.wash, "HORIZONTAL", glow, K.WASH_A, glow, 0)
            ui.wash:Show()
        else
            ui.wash:Hide()
        end
        if mode == K.MODE_DONE then
            K.PaintGradient(
                ui.cardFill,
                "VERTICAL",
                Colors.FEATURE_CARD_BG,
                K.CARD_DONE_TOP_A,
                Colors.MENU_CONTENT,
                K.CARD_DONE_BOTTOM_A
            )
        else
            K.PaintGradient(
                ui.cardFill,
                "VERTICAL",
                Colors.FEATURE_CARD_BG,
                K.CARD_TOP_A,
                Colors.MENU_CONTENT,
                K.CARD_BOTTOM_A
            )
        end

        if iconPath then
            ui.icon:SetTexture(iconPath)
        end
        ui.label:SetText(labelText or "")
        ui.label:SetTextColor(Widgets.UnpackColor(Colors.STATUS_HUD_REGION))

        local assigneeText = assigneeName
        local assigneeColor = K.ClassColor(K.ResolveClassFile(assigneeName, classFile))
        ui.assignee:SetText(assigneeText or "")
        ui.assignee:SetTextColor(Widgets.UnpackColor(assigneeColor))
        ui.layoutTop(iconPath ~= nil, labelText ~= nil, assigneeText ~= nil)

        if showTop then
            ui.top:Show()
            ui.stack:SetEntryHeight(ui.top, K.TOP_HEIGHT)
        else
            ui.top:Hide()
            ui.stack:SetEntryHeight(ui.top, 0)
        end

        ui.showNodes(total)
        ui.paintTrack(mode, currentIndex, themeColor)

        local fillColor = K.CastFillColor(mode, themeColor)
        ui.castFill:SetVertexColor(Widgets.UnpackColor(fillColor))
        if casting then
            ui.stack:SetEntryHeight(ui.castRow, K.CAST_HEIGHT)
            ui.castRow:Show()
            ui.castTrough:Show()
            ui.castFill:Show()
            ui.castFillRim:Show()
            ui.castName:SetText(spellName or "")
            if spellName then
                ui.castName:Show()
            else
                ui.castName:Hide()
            end
            ui.castTime:Show()
            applied.remainingKey = ""
            ui.startCast()
        else
            ui.stopCast()
            ui.stack:SetEntryHeight(ui.castRow, K.CAST_IDLE_HEIGHT)
            ui.castTrough:Hide()
            ui.castFill:Hide()
            ui.castFillRim:Hide()
            ui.castName:Hide()
            ui.castTime:Hide()
            applied.remainingKey = ""
        end

        ui.resize()
    end

    ---@return InterruptChainHUDState
    function frame:GetState()
        local indices = {}
        for i = 1, applied.mineCount do
            indices[i] = appliedMine[i]
        end
        local state = {
            total = math.max(applied.total, 0),
            completed = math.max(applied.completed, 0),
            myIndices = indices,
        }
        if applied.label ~= "" then
            state.label = applied.label
        end
        if applied.icon ~= nil then
            state.icon = applied.icon
        end
        if applied.assignee ~= "" then
            state.currentAssignee = applied.assignee
        end
        if applied.classFile ~= nil then
            state.currentAssigneeClass = applied.classFile
        end
        if applied.castName then
            state.castSpellName = applied.castName
        end
        if applied.castStart then
            state.castStartTime = applied.castStart
        end
        if applied.castEnd then
            state.castEndTime = applied.castEnd
        end
        if applied.theme ~= "" then
            state.theme = applied.theme
        end
        if applied.accentFromState then
            state.accentColor = {
                r = applied.accentR,
                g = applied.accentG,
                b = applied.accentB,
            }
        end
        return state
    end

    local hide = frame.Hide
    function frame:Hide()
        StopCastUpdates()
        hide(self)
    end

    ui.track:HookScript("OnSizeChanged", function()
        if applied.total > 0 then
            LayoutNodes(applied.total)
        end
    end)

    Resize()
    return frame --[[@as InterruptChainHUD]]
end

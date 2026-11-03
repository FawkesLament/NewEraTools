local _, ns = ...
local Assets = ns.Assets
local Timer = ns.Api.Timer
local Unit = ns.Api.Unit

local FontFiles = Assets.FontFiles
local Textures = Assets.Textures

-- Cropped 3-slice art (media/icons/interrupt_indicator_*.tga), height 64.
-- Gold is the default scheme; pale-green variants keep the same slice sizes.
local TEXTURE_HEIGHT = 64
local LEFT_TEXTURE_WIDTH = 94
local RIGHT_TEXTURE_WIDTH = 34
-- Compact nameplate size; caps keep their texture aspect at this height.
local HEIGHT = 24
-- Gap from the nameplate (or its cast bar) before saved offsets.
local GAP = 1
-- Sequence number on the left cap. Names stay on the locale UI face for CJK.
local NUMBER_FONT_SIZE = 14
local NAME_FONT_SIZE = 11
local NAME_PAD = 5
local MIN_NAME_WIDTH = 8
local MAX_NAME_WIDTH = 96
local ELLIPSIS = "…"
local WHITE = { r = 1, g = 1, b = 1 }
local NUMBER_COLOR = { r = 0.22, g = 0.24, b = 0.27 }

local SIDE_TOP = "top"
local SIDE_BOTTOM = "bottom"
local SCHEME_GOLD = "gold"
local SCHEME_PALE_GREEN = "pale_green"

local SCHEME_TEXTURES = {
    [SCHEME_GOLD] = {
        left = Textures.INTERRUPT_INDICATOR_LEFT_GOLD,
        center = Textures.INTERRUPT_INDICATOR_CENTER_GOLD,
        right = Textures.INTERRUPT_INDICATOR_RIGHT_GOLD,
    },
    [SCHEME_PALE_GREEN] = {
        left = Textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN,
        center = Textures.INTERRUPT_INDICATOR_CENTER_PALE_GREEN,
        right = Textures.INTERRUPT_INDICATOR_RIGHT_PALE_GREEN,
    },
}

---@param scheme string|nil
---@return string
local function ResolveScheme(scheme)
    if SCHEME_TEXTURES[scheme] then
        return scheme
    end
    return SCHEME_GOLD
end

---@class InterruptIndicator: Frame
---@field SetAssignment fun(self: InterruptIndicator, sequenceNumber: number, playerName: string|nil, classFile: string|nil)
---@field SetScale fun(self: InterruptIndicator, scale: number)
---@field SetNumberFontSize fun(self: InterruptIndicator, size: number)
---@field SetNameFontSize fun(self: InterruptIndicator, size: number)
---@field SetOffset fun(self: InterruptIndicator, x: number, y: number)
---@field SetSide fun(self: InterruptIndicator, side: "top"|"bottom")
---@field SetColorScheme fun(self: InterruptIndicator, scheme: "gold"|"pale_green")
---@field Attach fun(self: InterruptIndicator, nameplate: Frame)

local InterruptIndicator = {}
ns.InterruptIndicator = InterruptIndicator

-- Visible for testing:
InterruptIndicator.HEIGHT = HEIGHT
InterruptIndicator.GAP = GAP
InterruptIndicator.NUMBER_FONT_SIZE = NUMBER_FONT_SIZE
InterruptIndicator.NAME_FONT_SIZE = NAME_FONT_SIZE
InterruptIndicator.NUMBER_COLOR = NUMBER_COLOR
InterruptIndicator.MAX_NAME_WIDTH = MAX_NAME_WIDTH
InterruptIndicator.SIDE_TOP = SIDE_TOP
InterruptIndicator.SIDE_BOTTOM = SIDE_BOTTOM
InterruptIndicator.SCHEME_GOLD = SCHEME_GOLD
InterruptIndicator.SCHEME_PALE_GREEN = SCHEME_PALE_GREEN

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
---@return number
local function MeasureTextWidth(fontString)
    if fontString.GetUnboundedStringWidth then
        local width = fontString:GetUnboundedStringWidth()
        if type(width) == "number" and width > 0 then
            return width
        end
    end
    if fontString.GetStringWidth then
        local width = fontString:GetStringWidth()
        if type(width) == "number" and width > 0 then
            return width
        end
    end
    return 0
end

---@param text string
---@param fontSize number
---@return number
local function EstimateNameWidth(text, fontSize)
    return Utf8Len(text) * fontSize
end

-- Reject leftover constrained widths (too small) and unready font metrics (too large).
---@param width number
---@param text string
---@param fontSize number
---@return boolean
local function IsPlausibleWidth(width, text, fontSize)
    if width <= 0 then
        return false
    end
    local n = Utf8Len(text)
    if n <= 0 then
        return false
    end
    return width >= n * 3 and width <= n * fontSize * 2 + 8
end

---@param fontString FontString
---@param text string
---@param maxWidth number
---@param fontSize number
---@return number
local function FitName(fontString, text, maxWidth, fontSize)
    fontString:SetText(text)
    if text == "" or type(maxWidth) ~= "number" or maxWidth <= 0 then
        return 0
    end
    local width = MeasureTextWidth(fontString)
    if not IsPlausibleWidth(width, text, fontSize) then
        width = EstimateNameWidth(text, fontSize)
        if width > maxWidth then
            return maxWidth
        end
        return width
    end
    if width <= maxWidth then
        return width
    end
    local low, high = 0, Utf8Len(text)
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        fontString:SetText(Utf8Prefix(text, mid) .. ELLIPSIS)
        width = MeasureTextWidth(fontString)
        if IsPlausibleWidth(width, Utf8Prefix(text, mid) .. ELLIPSIS, fontSize) and width <= maxWidth then
            low = mid
        else
            high = mid - 1
        end
    end
    if low <= 0 then
        fontString:SetText(ELLIPSIS)
        width = MeasureTextWidth(fontString)
        if not IsPlausibleWidth(width, ELLIPSIS, fontSize) then
            return maxWidth
        end
        return width
    end
    fontString:SetText(Utf8Prefix(text, low) .. ELLIPSIS)
    width = MeasureTextWidth(fontString)
    if not IsPlausibleWidth(width, Utf8Prefix(text, low) .. ELLIPSIS, fontSize) then
        return maxWidth
    end
    return width
end

---@param texture Texture
local function PrepareSlice(texture)
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

---Compact three-slice interrupt assignment chip. Does not receive mouse input.
---@param parent Frame|nil
---@param scheme "gold"|"pale_green"|nil
---@return InterruptIndicator
function InterruptIndicator.Create(parent, scheme)
    local frame = CreateFrame("Frame", nil, parent) --[[@as InterruptIndicator]]
    frame:EnableMouse(false)
    scheme = ResolveScheme(scheme)

    local left = frame:CreateTexture(nil, "ARTWORK")
    PrepareSlice(left)

    local center = frame:CreateTexture(nil, "ARTWORK")
    PrepareSlice(center)

    local right = frame:CreateTexture(nil, "ARTWORK")
    PrepareSlice(right)

    local function ApplyScheme()
        local textures = SCHEME_TEXTURES[scheme]
        left:SetTexture(textures.left)
        center:SetTexture(textures.center)
        right:SetTexture(textures.right)
    end

    ApplyScheme()

    local numberLabel = frame:CreateFontString(nil, "OVERLAY")
    numberLabel:SetJustifyH("CENTER")
    numberLabel:SetJustifyV("MIDDLE")
    numberLabel:SetWordWrap(false)

    local nameLabel = frame:CreateFontString(nil, "OVERLAY")
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetJustifyV("MIDDLE")
    nameLabel:SetWordWrap(false)
    nameLabel:SetShadowOffset(0, 0)
    nameLabel:SetShadowColor(0, 0, 0, 0)

    local scale = 1
    local numberFontSize = NUMBER_FONT_SIZE
    local nameFontSize = NAME_FONT_SIZE
    local offsetX = 0
    local offsetY = 0
    local side = SIDE_BOTTOM
    local classFile
    local playerName = ""
    local pointsReady = false
    local layoutGen = 0
    ---@type Frame|nil
    local anchor

    local function ApplyNameColor()
        local color = classFile and Unit.GetClassColor(classFile) or WHITE
        nameLabel:SetTextColor(color.r, color.g, color.b, 1)
    end

    local function ApplyNumberFont()
        local size = numberFontSize * scale
        numberLabel:SetFont(FontFiles.EXPRESSWAY, size, "")
        numberLabel:SetTextColor(NUMBER_COLOR.r, NUMBER_COLOR.g, NUMBER_COLOR.b, 1)
    end

    local function EnsurePoints()
        if pointsReady then
            return
        end
        pointsReady = true
        left:SetPoint("TOPLEFT", frame, "TOPLEFT")
        center:SetPoint("TOPLEFT", left, "TOPRIGHT")
        right:SetPoint("TOPLEFT", center, "TOPRIGHT")
        numberLabel:SetAllPoints(left)
    end

    local function Relayout()
        EnsurePoints()
        local height = HEIGHT * scale
        local leftWidth = LEFT_TEXTURE_WIDTH * height / TEXTURE_HEIGHT
        local rightWidth = RIGHT_TEXTURE_WIDTH * height / TEXTURE_HEIGHT
        local pad = NAME_PAD * scale
        local maxNameWidth = MAX_NAME_WIDTH * scale
        ApplyNumberFont()
        local fontSize = nameFontSize * scale
        nameLabel:ClearAllPoints()
        if nameLabel.SetWidth then
            -- Anchored FontStrings keep a width after ClearAllPoints; force an unbounded measure.
            nameLabel:SetWidth(2048)
        end
        nameLabel:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        local nameWidth = FitName(nameLabel, playerName, maxNameWidth, fontSize)
        if nameWidth < MIN_NAME_WIDTH * scale then
            nameWidth = MIN_NAME_WIDTH * scale
        end
        local centerWidth = nameWidth + pad * 2
        left:SetSize(leftWidth, height)
        center:SetSize(centerWidth, height)
        right:SetSize(rightWidth, height)
        nameLabel:ClearAllPoints()
        -- One horizontal anchor only: a LEFT+RIGHT pair makes retail ellipsize the name.
        nameLabel:SetPoint("LEFT", center, "LEFT", pad, 0)
        nameLabel:SetPoint("TOP", center, "TOP")
        nameLabel:SetPoint("BOTTOM", center, "BOTTOM")
        frame:SetSize(leftWidth + centerWidth + rightWidth, height)
        ApplyNameColor()
    end

    local function RequestRelayout()
        Relayout()
        if not anchor then
            return
        end
        layoutGen = layoutGen + 1
        local gen = layoutGen
        Timer.After(0, function()
            if gen ~= layoutGen then
                return
            end
            Relayout()
        end)
    end

    local function ApplyAnchor()
        if not anchor then
            return
        end
        local relativeTo = anchor
        local point, relativePoint, x, y
        if side == SIDE_TOP then
            point, relativePoint, x, y = "BOTTOM", "TOP", offsetX, GAP + offsetY
        else
            local unitFrame = anchor.UnitFrame
            if type(unitFrame) == "table" and type(unitFrame.castBar) == "table" then
                relativeTo = unitFrame.castBar
            end
            point, relativePoint, x, y = "TOP", "BOTTOM", offsetX, -GAP + offsetY
        end
        frame:ClearAllPoints()
        frame:SetPoint(point, relativeTo, relativePoint, x, y)
    end

    function frame:SetAssignment(sequenceNumber, nextName, nextClassFile)
        numberLabel:SetText(tostring(sequenceNumber))
        playerName = type(nextName) == "string" and nextName or ""
        classFile = nextClassFile
        RequestRelayout()
    end

    function frame:SetScale(nextScale)
        scale = nextScale
        RequestRelayout()
    end

    function frame:SetNumberFontSize(size)
        if numberFontSize == size then
            return
        end
        numberFontSize = size
        RequestRelayout()
    end

    function frame:SetNameFontSize(size)
        if nameFontSize == size then
            return
        end
        nameFontSize = size
        RequestRelayout()
    end

    function frame:SetOffset(x, y)
        offsetX = x
        offsetY = y
        ApplyAnchor()
    end

    function frame:SetSide(nextSide)
        if nextSide == SIDE_TOP then
            side = SIDE_TOP
        else
            side = SIDE_BOTTOM
        end
        ApplyAnchor()
    end

    ---Swaps the three-slice art. Unknown values fall back to gold.
    ---@param nextScheme "gold"|"pale_green"|nil
    function frame:SetColorScheme(nextScheme)
        nextScheme = ResolveScheme(nextScheme)
        if scheme == nextScheme then
            return
        end
        scheme = nextScheme
        ApplyScheme()
    end

    ---Parents the chip to `nameplate`. Bottom uses the cast bar when that child exists.
    ---@param nameplate Frame
    function frame:Attach(nameplate)
        anchor = nameplate
        self:SetParent(nameplate)
        ApplyAnchor()
        self:Show()
        RequestRelayout()
    end

    local rawHide = frame.Hide
    function frame:Hide()
        layoutGen = layoutGen + 1
        anchor = nil
        rawHide(self)
    end

    Relayout()
    return frame
end

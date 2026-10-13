local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

local TIME_OUTLINE = "OUTLINE"

local Chrome = {}
ns.AuraTrackerBarChromeUI = Chrome

---@param thickness number
---@return table
function Chrome.LineBackdrop(thickness)
    return {
        edgeFile = Assets.Textures.WHITE,
        edgeSize = thickness,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
end

---@param trackerId integer
---@return number width, number height
function Chrome.BarSize(trackerId)
    local width = AuraTracker:GetWidth(trackerId)
    local height = AuraTracker:GetHeight(trackerId)
    if AuraTracker:GetVertical(trackerId) then
        width, height = height, width
    end
    return width, height
end

---@param trackerId integer
---@return string
local function TimeFontPath(trackerId)
    return AuraTracker:GetTimeFontPath(trackerId) or STANDARD_TEXT_FONT
end

---Anchors a duration FontString from the saved time position.
---@param trackerId integer
---@param fontString FontString
local function ApplyTimeTextLayout(trackerId, fontString)
    local inset = Spacing.SMALL
    local position = AuraTracker:GetTimePosition(trackerId)
    fontString:ClearAllPoints()
    fontString:SetJustifyH("CENTER")
    fontString:SetJustifyV("MIDDLE")
    if position == "left" then
        fontString:SetPoint("LEFT", inset, 0)
        fontString:SetJustifyH("LEFT")
    elseif position == "right" then
        fontString:SetPoint("RIGHT", -inset, 0)
        fontString:SetJustifyH("RIGHT")
    elseif position == "top" then
        fontString:SetPoint("TOP", 0, -inset)
        fontString:SetJustifyV("TOP")
    elseif position == "bottom" then
        fontString:SetPoint("BOTTOM", 0, inset)
        fontString:SetJustifyV("BOTTOM")
    else
        fontString:SetPoint("CENTER", 0, 0)
    end
end

---@param trackerId integer
---@param fontString FontString
local function ApplyTimeTextFont(trackerId, fontString)
    fontString:SetFont(TimeFontPath(trackerId), AuraTracker:GetTimeFontSize(trackerId), TIME_OUTLINE)
    fontString:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
end

---@param trackerId integer
---@param fontString FontString
function Chrome.ApplyTimeTextAppearance(trackerId, fontString)
    ApplyTimeTextFont(trackerId, fontString)
    ApplyTimeTextLayout(trackerId, fontString)
end

---Ensures a host above the fill for fixed stack-boundary separators.
---@param parent Frame
---@param existing Frame|nil
---@return Frame
function Chrome.EnsureStackDividerHost(parent, existing)
    if existing then
        return existing
    end
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:EnableMouse(false)
    return host
end

---Shows maxStacks-1 separators (no outer edges); hides the pool when off or in duration mode.
---@param trackerId integer
---@param host Frame
---@param pool Texture[]
---@param bar StatusBar
---@return Texture[]
function Chrome.ApplyStackDividers(trackerId, host, pool, bar)
    host:SetFrameLevel(bar:GetFrameLevel() + 1)
    if not AuraTracker:IsStacksMode(trackerId) or not AuraTracker:GetShowStackDividers(trackerId) then
        for i = 1, #pool do
            pool[i]:Hide()
        end
        return pool
    end

    local maxStacks = AuraTracker:GetMaxStacks(trackerId)
    local needed = maxStacks - 1
    if needed < 1 then
        for i = 1, #pool do
            pool[i]:Hide()
        end
        return pool
    end

    local width, height = Chrome.BarSize(trackerId)
    local vertical = AuraTracker:GetVertical(trackerId)
    local lineColor = AuraTracker:GetLineColor(trackerId)
    local thickness = AuraTracker:GetLineThickness(trackerId)
    for i = 1, needed do
        local tex = pool[i]
        if not tex then
            tex = host:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(Assets.Textures.WHITE)
            pool[i] = tex
        end
        tex:SetVertexColor(lineColor.r, lineColor.g, lineColor.b, 1)
        tex:ClearAllPoints()
        if vertical then
            -- Equal segments along the bar height; line spans the full width.
            local y = height * i / maxStacks
            tex:SetSize(width, thickness)
            tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, y)
        else
            local x = width * i / maxStacks
            tex:SetSize(thickness, height)
            tex:SetPoint("TOPLEFT", host, "TOPLEFT", x, 0)
        end
        tex:Show()
    end
    for i = needed + 1, #pool do
        pool[i]:Hide()
    end
    return pool
end

---Paints shared StatusBar chrome for preview and live bars.
---@param trackerId integer
---@param bar StatusBar
---@param background Texture
---@param border Frame
---@param timeText FontString|nil  When set (preview), show/hide directly; live binds via ApplyValueText.
function Chrome.ApplyBarChrome(trackerId, bar, background, border, timeText)
    local fill = AuraTracker:GetFillColor(trackerId)
    local vertical = AuraTracker:GetVertical(trackerId)
    -- Texture first, then color, so tint applies to whatever fill is selected.
    bar:SetStatusBarTexture(AuraTracker:GetTexturePath(trackerId))
    bar:SetStatusBarColor(fill.r, fill.g, fill.b, 1)
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    -- Rotate the fill texture with the bar; otherwise vertical bars stretch the texture sideways.
    bar:SetRotatesTexture(vertical)
    bar:SetReverseFill(AuraTracker:GetReverseFill(trackerId))

    local backgroundColor = AuraTracker:GetBackgroundColor(trackerId)
    background:SetColorTexture(
        backgroundColor.r,
        backgroundColor.g,
        backgroundColor.b,
        AuraTracker:GetBackgroundOpacity(trackerId)
    )

    border:SetFrameLevel(bar:GetFrameLevel() + 1)
    if AuraTracker:GetShowBorder(trackerId) then
        local lineColor = AuraTracker:GetLineColor(trackerId)
        -- Fresh backdrop table: BackdropTemplate ignores in-place edgeSize edits.
        border:SetBackdrop(Chrome.LineBackdrop(AuraTracker:GetLineThickness(trackerId)))
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(lineColor.r, lineColor.g, lineColor.b, 1)
        border:Show()
    else
        border:Hide()
    end

    if timeText then
        Chrome.ApplyTimeTextAppearance(trackerId, timeText)
        if AuraTracker:GetShowTime(trackerId) then
            timeText:Show()
        else
            timeText:Hide()
        end
    end
end

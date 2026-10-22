local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local Assets = ns.Assets

local Schema = Internals.Schema
local SIZE = Schema.SIZE_DEFAULT
local FONT_SIZE = Schema.FONT_SIZE_DEFAULT
local FONT_COLOR = Schema.FONT_COLOR_DEFAULT

---@class TwinFangsInterruptBadge: Frame
---@field SetNumber fun(self: TwinFangsInterruptBadge, number: number)
---@field ApplyAppearance fun(self: TwinFangsInterruptBadge, size: number|nil, opacity: number|nil, fontPath: string|nil, fontSize: number|nil, fontColor: RgbColor|nil)

local InterruptBadge = {}
Internals.InterruptBadge = InterruptBadge

---Compact ice-blue HUD badge. Does not receive mouse input.
---@param parent Frame|nil
---@return TwinFangsInterruptBadge
function InterruptBadge.Create(parent)
    local frame = CreateFrame("Frame", nil, parent) --[[@as TwinFangsInterruptBadge]]
    frame:SetSize(SIZE, SIZE)
    frame:EnableMouse(false)

    local background = frame:CreateTexture(nil, "ARTWORK")
    background:SetAllPoints()
    background:SetTexture(Assets.Textures.ROUNDED_SQUARE)

    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetAllPoints(frame)
    label:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
    label:SetTextColor(FONT_COLOR.r, FONT_COLOR.g, FONT_COLOR.b, 1)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetShadowOffset(0, 0)
    label:SetShadowColor(0, 0, 0, 0)

    function frame:SetNumber(number)
        label:SetText(tostring(number))
    end

    ---Resizes the ice-blue texture and applies the saved number font.
    ---@param size number|nil  Edge length in pixels. Defaults to the saved size default.
    ---@param opacity number|nil  Frame alpha in `[0, 1]`. Defaults to 1.
    ---@param fontPath string|nil  Font file. Defaults to `STANDARD_TEXT_FONT`.
    ---@param fontSize number|nil  Number size in pixels. Defaults to the saved font size default.
    ---@param fontColor RgbColor|nil  Number RGB. Defaults to the ice-blue fill.
    function frame:ApplyAppearance(size, opacity, fontPath, fontSize, fontColor)
        size = size or SIZE
        opacity = opacity or 1
        fontPath = fontPath or STANDARD_TEXT_FONT
        fontSize = fontSize or FONT_SIZE
        local r, g, b = FONT_COLOR.r, FONT_COLOR.g, FONT_COLOR.b
        if type(fontColor) == "table" then
            r = fontColor.r or r
            g = fontColor.g or g
            b = fontColor.b or b
        end
        self:SetSize(size, size)
        label:SetFont(fontPath, fontSize, "OUTLINE")
        label:SetTextColor(r, g, b, 1)
        self:SetAlpha(opacity)
    end

    return frame
end

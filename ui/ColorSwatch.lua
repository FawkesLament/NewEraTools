local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Sizes = Assets.Sizes

local ColorSwatch = {}
ns.ColorSwatch = ColorSwatch

---@class ColorRGB
---@field r number
---@field g number
---@field b number

---@class ColorSwatch: Button
---@field SetColor fun(self: ColorSwatch, color: ColorRGB)  Updates the swatch fill.
---@field GetColor fun(self: ColorSwatch): ColorRGB  Copy of the current RGB.

---Creates a square swatch that opens ColorPickerFrame on click (RGB only, no opacity).
---@param parent Frame
---@param color ColorRGB  Initial fill color.
---@param onColorChanged fun(color: ColorRGB)  Called for live edits and cancel restore.
---@return ColorSwatch
function ColorSwatch.Create(parent, color, onColorChanged)
    local swatch = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP) --[[@as ColorSwatch]]
    swatch:SetSize(Sizes.COLOR_SWATCH, Sizes.COLOR_SWATCH)
    Widgets.ApplyBackdrop(swatch, color, Colors.BORDER)
    Widgets.AddHoverHighlight(swatch)

    ---@type ColorRGB
    swatch.color = { r = color.r, g = color.g, b = color.b }

    function swatch:SetColor(next)
        self.color.r, self.color.g, self.color.b = next.r, next.g, next.b
        self:SetBackdropColor(next.r, next.g, next.b, 1)
    end

    function swatch:GetColor()
        local current = self.color
        return { r = current.r, g = current.g, b = current.b }
    end

    -- FeatureSection (and callers) use SetEnabled; Button Enable/Disable is native but unnamed.
    function swatch:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end

    swatch:SetScript("OnClick", function(self)
        local current = self:GetColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = current.r,
            g = current.g,
            b = current.b,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local next = { r = r, g = g, b = b }
                self:SetColor(next)
                onColorChanged(next)
            end,
            cancelFunc = function()
                local r, g, b = ColorPickerFrame:GetPreviousValues()
                local next = { r = r, g = g, b = b }
                self:SetColor(next)
                onColorChanged(next)
            end,
        })
    end)
    return swatch
end

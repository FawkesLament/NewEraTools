-- Settings-panel checkbox: muted well, handwritten checkmark, and FeatureSection enable gating.
local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Sizes = Assets.Sizes

local Checkbox = {}
ns.Checkbox = Checkbox

local DISABLED_ALPHA = 0.4
local CHECKBOX_GLOW_ALPHA = 0.18
local CHECKBOX_BORDER_ALPHA = 0.72
local CHECKMARK_SCALE = 1.45
local CHECKMARK_LIFT = 0.28
local CHECKMARK_OFFSET_X = 2
local CHECKMARK_OFFSET_Y = 2

local function ColorWithAlpha(color, alpha)
    return { r = color.r, g = color.g, b = color.b, a = alpha }
end

local function OverlayColor(base, overlay, alpha)
    local keep = 1 - alpha
    return {
        r = base.r * keep + overlay.r * alpha,
        g = base.g * keep + overlay.g * alpha,
        b = base.b * keep + overlay.b * alpha,
        a = 1,
    }
end

local function LiftTowardWhite(color, amount)
    return {
        r = color.r + (1 - color.r) * amount,
        g = color.g + (1 - color.g) * amount,
        b = color.b + (1 - color.b) * amount,
        a = color.a or 1,
    }
end

---Creates a flat square checkbox with a muted accent well and a tinted checkmark when checked.
---@param parent Frame
---@return CheckButton
function Checkbox.Create(parent)
    local box = CreateFrame("CheckButton", nil, parent, Assets.Templates.BACKDROP)
    box:SetSize(Sizes.CHECKBOX, Sizes.CHECKBOX)
    box:SetClipsChildren(false)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    -- ARTWORK stays under the OVERLAY checkmark; HIGHLIGHT would wash the mark.
    local hover = box:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints()
    hover:SetColorTexture(Widgets.UnpackColor(Colors.HOVER))
    hover:Hide()
    -- SetCheckedTexture requires an asset; a fully transparent texture suppresses the default tick.
    local nativeChecked = box:CreateTexture(nil, "ARTWORK")
    nativeChecked:SetAllPoints()
    nativeChecked:SetColorTexture(0, 0, 0, 0)
    box:SetCheckedTexture(nativeChecked)

    local markSize = Sizes.CHECKBOX * CHECKMARK_SCALE
    local checkColor = LiftTowardWhite(Colors.MENU_ACCENT, CHECKMARK_LIFT)
    local checkmark = box:CreateTexture(nil, "OVERLAY", nil, 2)
    checkmark:SetTexture(Assets.Textures.CHECKMARK)
    checkmark:SetVertexColor(Widgets.UnpackColor(checkColor))
    checkmark:SetSize(markSize, markSize)
    checkmark:SetPoint("CENTER", box, "CENTER", CHECKMARK_OFFSET_X, CHECKMARK_OFFSET_Y)

    local checkmarkShadow = box:CreateTexture(nil, "OVERLAY", nil, 1)
    checkmarkShadow:SetTexture(Assets.Textures.CHECKMARK)
    checkmarkShadow:SetVertexColor(0, 0, 0, 0.55)
    checkmarkShadow:SetSize(markSize, markSize)
    checkmarkShadow:SetPoint("CENTER", checkmark, "CENTER", 1, -1)

    local hovered = false
    local checkedFill = OverlayColor(Colors.SURFACE, Colors.MENU_ACCENT, CHECKBOX_GLOW_ALPHA)
    local checkedBorder = ColorWithAlpha(Colors.MENU_ACCENT, CHECKBOX_BORDER_ALPHA)

    local function UpdateVisuals()
        if box:GetChecked() then
            Widgets.ApplyBackdrop(box, checkedFill, checkedBorder)
            checkmark:Show()
            checkmarkShadow:Show()
        else
            Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
            checkmark:Hide()
            checkmarkShadow:Hide()
        end
        if hovered and box:IsEnabled() then
            hover:Show()
        else
            hover:Hide()
        end
        box:SetAlpha(box:IsEnabled() and 1 or DISABLED_ALPHA)
    end

    hooksecurefunc(box, "SetChecked", UpdateVisuals)
    box:HookScript("OnClick", UpdateVisuals)
    box:HookScript("OnEnter", function()
        hovered = true
        UpdateVisuals()
    end)
    box:HookScript("OnLeave", function()
        hovered = false
        UpdateVisuals()
    end)
    -- FeatureSection uses SetEnabled; CheckButton only has Enable/Disable natively.
    function box:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        UpdateVisuals()
    end
    UpdateVisuals()
    return box
end

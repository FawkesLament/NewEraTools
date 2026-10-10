local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets

local MinimapButton = ns.Modules.New("MinimapButton", {
    defaults = {
        angle = 225,
    },
})

local button

local function UpdatePosition()
    local angle = math.rad(MinimapButton.db.angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    MinimapButton.db.angle = math.deg(math.atan2(cy - my, cx - mx))
    UpdatePosition()
end

local function CreateButton()
    button = CreateFrame("Button", ns.ADDON_NAME .. "MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(Assets.Textures.MINIMAP_HIGHLIGHT)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(Assets.Textures.MINIMAP_BACKGROUND)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(Assets.MINI_LOGO)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture(Assets.Textures.MINIMAP_BORDER)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        ns.MainPanel:Toggle()
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    Widgets.AttachTooltip(button, "ANCHOR_LEFT", function(tooltip)
        tooltip:AddLine(ns.ADDON_NAME)
        tooltip:AddLine(L.MINIMAP_TOOLTIP_CLICK, Widgets.UnpackColor(Assets.Colors.TEXT))
        tooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, Widgets.UnpackColor(Assets.Colors.TEXT))
    end)

    UpdatePosition()
end

function MinimapButton:OnEnable()
    CreateButton()
end

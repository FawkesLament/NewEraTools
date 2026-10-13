local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CombatLog = ns.Modules.Get("CombatLog")

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local locationsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)

    local locationsLabel = Widgets.CreateLabel(locationsRow, Fonts.BODY, L.COMBAT_LOG_LOCATIONS)
    locationsLabel:SetJustifyH("LEFT")
    -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
    local locationsHit = CreateFrame("Frame", nil, locationsRow)
    locationsHit:SetPoint("TOPLEFT", locationsLabel, "TOPLEFT")
    locationsHit:SetPoint("BOTTOMRIGHT", locationsLabel, "BOTTOMRIGHT")
    locationsHit:EnableMouse(true)
    Widgets.AttachTooltip(locationsHit, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.COMBAT_LOG_LOCATIONS_TOOLTIP)
    end)

    local locationsControl
    locationsControl = Widgets.CreateSegmentedControl(locationsRow, {
        { value = CombatLog.LOCATION_ALL, text = L.COMBAT_LOG_LOCATIONS_ALL },
        { value = CombatLog.LOCATION_RAIDS, text = L.COMBAT_LOG_LOCATIONS_RAIDS },
        { value = CombatLog.LOCATION_DUNGEONS, text = L.COMBAT_LOG_LOCATIONS_DUNGEONS },
    }, function(locations)
        if not CombatLog:IsEnabled() then
            return
        end
        CombatLog:SetLocations(locations)
        locationsControl:SetSelected(locations)
    end)
    locationsControl:SetSelected(CombatLog:GetLocations())
    Layout.Row(locationsRow, { locationsLabel, locationsControl }, Spacing.LARGE)

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    local section = FeatureSection.Create(stack, {
        title = L.COMBAT_LOG_ENABLED,
        tooltip = L.COMBAT_LOG_HINT,
        enabled = CombatLog:IsEnabled(),
        onEnabledChanged = function(enabled)
            CombatLog:SetEnabled(enabled)
        end,
    })

    section:SetContentHeight(BuildContent(section.content))
    section:RefreshContentInteractive()

    return stack:GetHeight()
end

function CombatLog:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.COMBAT_LOG_TITLE,
        group = ns.PanelGroups.COMBAT,
        build = Build,
    })
    self:StartMonitoring()
end

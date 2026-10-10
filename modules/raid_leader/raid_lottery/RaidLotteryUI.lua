local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Widgets = ns.Widgets
local Unit = ns.Api.Unit

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

-- Matches FeatureSection / Widgets disabled fade.
local DISABLED_ALPHA = 0.4

local RaidLottery = ns.Modules.Get("RaidLottery")

local COLUMN_WIDTH = 120
local GRID_ROW_HEIGHT = 20

local ui
-- Session-only: the member list starts collapsed every time the panel opens.
local expanded = false
local Refresh

local function UpdateDrawButton(eligibleCount)
    local reason = not RaidLottery:IsSending() and RaidLottery:GetBlockedReason(eligibleCount)
    ui.drawButton:SetEnabled(not RaidLottery:IsSending() and not reason)
    ui.blockedReason:SetText(reason or "")
end

---Dims and locks the whole feature when the player isn't a raid leader or assistant in a raid.
---Call after building/updating controls so newly created widgets are included.
---@param eligibleCount integer
local function ApplyAccessInteractive(eligibleCount)
    local accessBlocked = RaidLottery:GetAccessBlockedReason()
    local canUse = not accessBlocked
    ui.container:SetAlpha(canUse and 1 or DISABLED_ALPHA)
    if canUse then
        FeatureSection.SetSubtreeInteractive(ui.container, true)
    end
    -- After enabling the tree so stepper limits and the draw button keep their own disables.
    ui.stepper:SetValue(RaidLottery:GetCount(), 1, RaidLottery:GetMaxCount(eligibleCount))
    UpdateDrawButton(eligibleCount)
    if not canUse then
        FeatureSection.SetSubtreeInteractive(ui.container, false)
        ui.blockedReason:SetText(accessBlocked)
    end
end

local function SetExpanded(value)
    expanded = value
    Refresh()
end

local function CreateMemberCheckbox(index)
    local box = Widgets.CreateCheckbox(ui.grid)
    -- Extends the clickable area over the role icon and name label.
    box:SetHitRectInsets(0, -(COLUMN_WIDTH - Sizes.CHECKBOX - Spacing.SMALL), 0, 0)

    local roleIcon = box:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(Sizes.ROLE_ICON, Sizes.ROLE_ICON)
    roleIcon:SetPoint("LEFT", box, "RIGHT", Spacing.SMALL, 0)
    box.roleIcon = roleIcon

    local label = Widgets.CreateLabel(box, Fonts.BODY)
    label:SetPoint("LEFT", roleIcon, "RIGHT", Spacing.SMALL, 0)
    label:SetWidth(COLUMN_WIDTH - Sizes.CHECKBOX - Sizes.ROLE_ICON - 3 * Spacing.SMALL)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    box.label = label

    box:SetScript("OnClick", function(self)
        RaidLottery:SetExcluded(self.member, self:GetChecked())
        Refresh()
    end)

    ui.checkboxes[index] = box
    return box
end

local function GetColumnCount()
    return math.max(math.floor(ui.grid:GetWidth() / COLUMN_WIDTH), 1)
end

local function LayoutGrid()
    local gridHeight = 0
    if expanded then
        local columns = GetColumnCount()
        for index = 1, ui.memberCount do
            local box = ui.checkboxes[index]
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", ui.grid, "TOPLEFT", Layout.GridCell(index, columns, COLUMN_WIDTH, GRID_ROW_HEIGHT))
        end
        ui.columns = columns
        gridHeight = Layout.GridHeight(ui.memberCount, columns, GRID_ROW_HEIGHT)
    end
    ui.grid:SetShown(expanded)

    ui.stack:SetEntryHeight(ui.grid, gridHeight)
    local height = ui.stack:GetHeight()
    ui.container:SetContentHeight(height)
    return height
end

local function PopulateGrid(members)
    for index, member in ipairs(members) do
        local box = ui.checkboxes[index] or CreateMemberCheckbox(index)
        box.member = member
        box.label:SetText(member.name)
        box.label:SetTextColor(Widgets.UnpackColor(Unit.GetClassColor(member.classFile) or Colors.TEXT))

        local roleAtlas = Assets.ROLE_ATLASES[member.role]
        if roleAtlas then
            box.roleIcon:SetAtlas(roleAtlas)
            box.roleIcon:Show()
        else
            box.roleIcon:Hide()
        end
        box:SetChecked(RaidLottery:IsExcluded(member))
        box:Show()
    end
    for index = #members + 1, #ui.checkboxes do
        ui.checkboxes[index]:Hide()
    end
    ui.emptyRoster:SetShown(#members == 0)
    ui.memberCount = #members
end

function Refresh()
    local members = RaidLottery:GetMembers()
    local eligibleCount = #RaidLottery:GetEligible(members)
    RaidLottery:FitCount(eligibleCount)

    ui.roles:SetSelected(RaidLottery:GetRole())
    ui.summary:SetFormattedText(L.RAID_LOTTERY_SUMMARY, eligibleCount, #members)

    local excludedCount = RaidLottery:GetExcludedCount(members)
    ui.expandButton:SetLabel(string.format(L.RAID_LOTTERY_EXCLUDED_HEADER, excludedCount))
    ui.expandButton:SetExpanded(expanded)
    ui.clearButton:SetShown(excludedCount > 0)

    if expanded then
        PopulateGrid(members)
    end
    -- After PopulateGrid so newly created checkboxes are included in the disable pass.
    ApplyAccessInteractive(eligibleCount)
    return LayoutGrid()
end

local function BuildRoleRow(row)
    local items = {}
    for index, role in ipairs(RaidLottery.ROLES) do
        items[index] = { value = role, text = RaidLottery:GetRoleLabel(role) }
    end
    local roles = Widgets.CreateSegmentedControl(row, items, function(role)
        RaidLottery:SetRole(role)
        Refresh()
    end)
    ui.roles = roles

    local summary = Widgets.CreateLabel(row, Fonts.SMALL_MUTED)
    ui.summary = summary

    Layout.Row(row, { roles, summary }, Spacing.LARGE)
end

---@return number  Width of the count controls, so the rows around them can line up with it.
local function BuildCountRow(row)
    local countLabel = Widgets.CreateLabel(row, Fonts.BODY, L.RAID_LOTTERY_COUNT_LABEL)
    countLabel:SetPoint("LEFT", row, "LEFT")

    local stepper = Widgets.CreateStepper(row, function(delta)
        RaidLottery:SetCount(RaidLottery:GetCount() + delta)
        Refresh()
    end)
    ui.stepper = stepper

    local width = math.max(ui.roles:GetWidth(), countLabel:GetStringWidth() + Spacing.LARGE + stepper:GetWidth())
    stepper:SetPoint("RIGHT", row, "LEFT", width, 0)
    return width
end

local function BuildExcludedRow(row)
    local expandButton = Widgets.CreateExpandButton(row, function()
        SetExpanded(not expanded)
    end)
    ui.expandButton = expandButton

    local clearButton = Widgets.CreateTextButton(row, L.RAID_LOTTERY_CLEAR_EXCLUDED, function()
        RaidLottery:ClearExcluded()
        Refresh()
    end)
    ui.clearButton = clearButton

    Layout.Row(row, { expandButton, clearButton }, Spacing.MEDIUM)
end

local function BuildDrawRow(row, width)
    local drawButton = Widgets.CreateButton(row, L.RAID_LOTTERY_DRAW, function()
        RaidLottery:Draw()
        -- Exclusions are usually set once per draw, so the list folds away until it's needed again.
        if expanded then
            SetExpanded(false)
        end
    end, "primary")
    drawButton:SetWidth(math.max(drawButton:GetWidth(), width))
    ui.drawButton = drawButton

    local blockedReason = Widgets.CreateLabel(row, Fonts.SMALL_MUTED)
    blockedReason:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
    blockedReason:SetJustifyH("LEFT")
    blockedReason:SetWordWrap(false)
    ui.blockedReason = blockedReason

    Layout.Row(row, { drawButton, blockedReason }, Spacing.MEDIUM)
    blockedReason:SetPoint("RIGHT", row, "RIGHT")
end

local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })
    local roleRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local countRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local excludedRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local grid = stack:AddRow(0)
    local drawRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.SMALL)
    ui = { container = container, stack = stack, grid = grid, checkboxes = {}, memberCount = 0 }

    BuildRoleRow(roleRow)
    local controlsWidth = BuildCountRow(countRow)
    BuildExcludedRow(excludedRow)
    BuildDrawRow(drawRow, controlsWidth)

    local emptyRoster = Widgets.CreateLabel(grid, Fonts.MUTED, L.RAID_LOTTERY_EMPTY_ROSTER)
    emptyRoster:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -Spacing.TINY)
    ui.emptyRoster = emptyRoster

    -- The panel's width is only known once it is shown, and may change later.
    grid:SetScript("OnSizeChanged", function()
        if expanded and GetColumnCount() ~= ui.columns then
            LayoutGrid()
        end
    end)

    container:HookScript("OnShow", Refresh)
    container:HookScript("OnHide", function()
        expanded = false
    end)

    return Refresh()
end

function RaidLottery:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.RAID_LOTTERY_TITLE,
        group = ns.PanelGroups.RAID_LEADER,
        build = Build,
    })
    ns.Api.Group.OnChanged(function()
        RaidLottery:PruneExcluded(RaidLottery:GetMembers())
        if ui and ui.container:IsVisible() then
            Refresh()
        end
    end)
end

function RaidLottery:OnSendingChanged()
    if ui and ui.container:IsVisible() then
        ApplyAccessInteractive(#RaidLottery:GetEligible(RaidLottery:GetMembers()))
    end
end

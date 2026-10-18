local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CollapsibleSection = ns.CollapsibleSection
local Layout = ns.Layout
local Widgets = ns.Widgets
local Unit = ns.Api.Unit

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local RaidLottery = ns.Modules.Get("RaidLottery")

local COLUMN_WIDTH = 120
local GRID_ROW_HEIGHT = 20

local ui
local Refresh

---Locks only the draw button when access/pool/sending blocks a draw; other controls stay usable.
---A blocked draw explains why beside the button. Sending disables the button without that message.
---@param eligibleCount integer
local function SyncControls(eligibleCount)
    ui.stepper:SetValue(RaidLottery:GetCount())
    -- + stops at the eligible pool. The stored count can still sit above that while the roster loads.
    ui.stepper:SetIncreaseLimit(RaidLottery:GetMaxCount(eligibleCount))
    local reason = not RaidLottery:IsSending() and RaidLottery:GetBlockedReason(eligibleCount)
    ui.drawButton:SetEnabled(not RaidLottery:IsSending() and not reason)
    ui.blockedReason:SetText(reason or "")
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

local function LayoutExcludedContent()
    local gridHeight = 0
    if ui.excludedSection:IsExpanded() then
        local columns = GetColumnCount()
        for index = 1, ui.memberCount do
            local box = ui.checkboxes[index]
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", ui.grid, "TOPLEFT", Layout.GridCell(index, columns, COLUMN_WIDTH, GRID_ROW_HEIGHT))
        end
        ui.columns = columns
        gridHeight = Layout.GridHeight(ui.memberCount, columns, GRID_ROW_HEIGHT)
    end
    ui.excludedBody:SetEntryHeight(ui.grid, gridHeight)
    ui.excludedSection:SetContentHeight(ui.excludedBody:GetHeight())
    return ui.stack:GetHeight()
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

---Role-matched count and how many of those are excluded (so Matching − Excluded = Eligible).
---@param members RaidMember[]
---@return integer matchingCount
---@return integer excludedMatchingCount
local function CountMatching(members)
    local matchingCount = 0
    local excludedMatchingCount = 0
    for _, member in ipairs(members) do
        if RaidLottery:MatchesRole(member) then
            matchingCount = matchingCount + 1
            if RaidLottery:IsExcluded(member) then
                excludedMatchingCount = excludedMatchingCount + 1
            end
        end
    end
    return matchingCount, excludedMatchingCount
end

function Refresh()
    local members = RaidLottery:GetMembers()
    local eligibleCount = #RaidLottery:GetEligible(members)
    local matchingCount, excludedMatchingCount = CountMatching(members)
    local excludedCount = RaidLottery:GetExcludedCount(members)
    RaidLottery:FitCount(eligibleCount)

    ui.roles:SetSelected(RaidLottery:GetRole())
    ui.summary:SetFormattedText(L.RAID_LOTTERY_SUMMARY, matchingCount, excludedMatchingCount, eligibleCount)
    ui.excludedSection:SetBadge(excludedCount > 0 and tostring(excludedCount) or nil)

    if ui.excludedSection:IsExpanded() then
        PopulateGrid(members)
    end
    SyncControls(eligibleCount)
    ui.clearButton:SetEnabled(excludedCount > 0)
    return LayoutExcludedContent()
end

---Row 1: role filter.
local function BuildRoleRow(row)
    local items = {}
    for index, role in ipairs(RaidLottery.ROLES) do
        items[index] = { value = role, text = RaidLottery:GetRoleLabel(role) }
    end
    local roles = Widgets.CreateSegmentedControl(row, items, function(role)
        RaidLottery:SetRole(role)
        Refresh()
    end)
    roles:SetPoint("LEFT", row, "LEFT")
    ui.roles = roles
end

---Row 2: draw count stepper + matching / excluded / eligible summary.
local function BuildCountRow(row)
    local countCell, summaryCell = Layout.SplitRow(row, Spacing.MEDIUM)

    local countLabel = Widgets.CreateLabel(countCell, Fonts.BODY, L.RAID_LOTTERY_COUNT_LABEL)
    -- A large pool makes GetMaxCount return the module maximum, which sizes the box.
    local stepper = Widgets.CreateNumberStepper(countCell, 1, RaidLottery:GetMaxCount(1000), 1, function(value)
        RaidLottery:SetCount(value)
        Refresh()
    end)
    ui.stepper = stepper
    Layout.Row(countCell, { countLabel, stepper }, Spacing.LARGE)

    local summary = Widgets.CreateLabel(summaryCell, Fonts.SMALL_MUTED)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetPoint("LEFT", summaryCell, "LEFT")
    summary:SetPoint("RIGHT", summaryCell, "RIGHT")
    ui.summary = summary
end

---Clear control + member grid inside the excluded collapsible.
---@param content Frame
local function BuildExcludedContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })
    ui.excludedBody = body

    local actions = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local clearButton = Widgets.CreateButton(actions, L.RAID_LOTTERY_CLEAR_EXCLUDED, function()
        RaidLottery:ClearExcluded()
        Refresh()
    end)
    clearButton:SetPoint("LEFT", actions, "LEFT")
    ui.clearButton = clearButton

    ui.grid = body:Add(CreateFrame("Frame", nil, content), 0)

    local emptyRoster = Widgets.CreateLabel(ui.grid, Fonts.MUTED, L.RAID_LOTTERY_EMPTY_ROSTER)
    emptyRoster:SetPoint("TOPLEFT", ui.grid, "TOPLEFT", 0, -Spacing.TINY)
    ui.emptyRoster = emptyRoster
end

local function BuildDrawRow(row)
    local drawButton = Widgets.CreateButton(row, L.RAID_LOTTERY_DRAW, function()
        RaidLottery:Draw()
        -- Exclusions are usually set once per draw, so the list folds away until it's needed again.
        if ui.excludedSection:IsExpanded() then
            ui.excludedSection:SetExpanded(false)
        end
    end, "accent")
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
        spacing = Spacing.SMALL,
    })
    ui = { container = container, stack = stack, checkboxes = {}, memberCount = 0 }

    local roleRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local countRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    BuildRoleRow(roleRow)
    BuildCountRow(countRow)

    -- Session-only: the member list starts collapsed every time the panel opens.
    ui.excludedSection = CollapsibleSection.Create(stack, {
        title = L.RAID_LOTTERY_EXCLUDED_HEADER,
        expanded = false,
        onStackHeightChanged = function(height)
            container:SetContentHeight(height)
        end,
        onExpandedChanged = function()
            Refresh()
        end,
    })
    BuildExcludedContent(ui.excludedSection.content)
    ui.excludedSection:SetContentHeight(ui.excludedBody:GetHeight())

    local drawRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    BuildDrawRow(drawRow)

    -- The panel's width is only known once it is shown, and may change later.
    ui.grid:SetScript("OnSizeChanged", function()
        if ui.excludedSection:IsExpanded() and GetColumnCount() ~= ui.columns then
            LayoutExcludedContent()
        end
    end)

    container:HookScript("OnShow", Refresh)
    container:HookScript("OnHide", function()
        ui.excludedSection:SetExpanded(false)
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
        SyncControls(#RaidLottery:GetEligible(RaidLottery:GetMembers()))
    end
end

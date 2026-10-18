local _, ns = ...
local L = ns.L
local ActionFooter = ns.ActionFooter
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
local NAME_WIDTH = COLUMN_WIDTH - Sizes.CHECKBOX - Sizes.ROLE_ICON - 3 * Spacing.SMALL
local ROW_PAD_Y = (GRID_ROW_HEIGHT - Sizes.CHECKBOX) / 2
local ELLIPSIS = "…"

local ui
local Refresh

---Next byte after the UTF-8 sequence that starts at `index`.
---@param text string
---@param index integer
---@return integer
local function Utf8Next(text, index)
    local byte = string.byte(text, index)
    if not byte then
        return index + 1
    end
    if byte >= 240 then
        return index + 4
    elseif byte >= 224 then
        return index + 3
    elseif byte >= 192 then
        return index + 2
    end
    return index + 1
end

---Shortens `text` with an ellipsis so it stays inside `maxWidth`.
---@param label FontString
---@param text string
---@param maxWidth number
local function SetTruncatedText(label, text, maxWidth)
    label:SetText(text)
    if maxWidth <= 0 or label:GetStringWidth() <= maxWidth then
        return
    end
    local lastFit = ELLIPSIS
    local index = 1
    while index <= #text do
        local nextIndex = Utf8Next(text, index)
        local candidate = string.sub(text, 1, nextIndex - 1) .. ELLIPSIS
        label:SetText(candidate)
        if label:GetStringWidth() > maxWidth then
            label:SetText(lastFit)
            return
        end
        lastFit = candidate
        index = nextIndex
    end
end

---The parent decides when a draw is blocked. Sending disables the button without a message.
---@param eligibleCount integer
local function SyncControls(eligibleCount)
    ui.stepper:SetValue(RaidLottery:GetCount())
    -- + stops at the eligible pool. The stored count can still sit above that while the roster loads.
    ui.stepper:SetIncreaseLimit(RaidLottery:GetMaxCount(eligibleCount))
    local reason = not RaidLottery:IsSending() and RaidLottery:GetBlockedReason(eligibleCount)
    ui.footer.button:SetEnabled(not RaidLottery:IsSending() and not reason)
    if type(reason) == "string" then
        ui.footer:SetMessage({ text = reason, severity = "warning" })
    else
        ui.footer:SetMessage(nil)
    end
end

local function CreateMemberCheckbox(index)
    local box = Widgets.CreateCheckbox(ui.grid)
    -- The whole cell toggles the box, including the icon, the name, and the row's padding.
    box:SetHitRectInsets(0, -(COLUMN_WIDTH - Sizes.CHECKBOX), -ROW_PAD_Y, -ROW_PAD_Y)

    local roleIcon = box:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(Sizes.ROLE_ICON, Sizes.ROLE_ICON)
    roleIcon:SetPoint("LEFT", box, "RIGHT", Spacing.SMALL, 0)
    box.roleIcon = roleIcon

    local label = Widgets.CreateLabel(box, Fonts.BODY)
    label:SetPoint("LEFT", roleIcon, "RIGHT", Spacing.SMALL, 0)
    label:SetWidth(NAME_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
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
            local x, y = Layout.GridCell(index, columns, COLUMN_WIDTH, GRID_ROW_HEIGHT)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", ui.grid, "TOPLEFT", x, y - ROW_PAD_Y)
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
        SetTruncatedText(box.label, member.name, NAME_WIDTH)
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

---How many role-matched members are excluded (matching − excluded = eligible).
---@param members RaidMember[]
---@return integer
local function CountExcludedMatching(members)
    local excludedMatchingCount = 0
    for _, member in ipairs(members) do
        if RaidLottery:MatchesRole(member) and RaidLottery:IsExcluded(member) then
            excludedMatchingCount = excludedMatchingCount + 1
        end
    end
    return excludedMatchingCount
end

function Refresh()
    local members = RaidLottery:GetMembers()
    local eligibleCount = #RaidLottery:GetEligible(members)
    local excludedCount = RaidLottery:GetExcludedCount(members)
    RaidLottery:FitCount(eligibleCount)

    ui.roles:SetSelected(RaidLottery:GetRole())
    ui.summary:SetFormattedText(L.RAID_LOTTERY_SUMMARY, eligibleCount, CountExcludedMatching(members))
    ui.excludedSection:SetBadge(excludedCount > 0 and tostring(excludedCount) or nil)

    if ui.excludedSection:IsExpanded() then
        PopulateGrid(members)
    end
    SyncControls(eligibleCount)
    ui.clearButton:SetEnabled(excludedCount > 0)
    return LayoutExcludedContent()
end

---Draw count in the left half, role filter in the right half. Controls stay as wide as their contents.
---@param row Frame
local function BuildConfigRow(row)
    local countCell, roleCell = Layout.SplitRow(row, Spacing.MEDIUM)

    local countLabel = Widgets.CreateLabel(countCell, Fonts.BODY, L.RAID_LOTTERY_COUNT_LABEL)
    -- A large pool makes GetMaxCount return the module maximum, which sizes the box.
    local stepper = Widgets.CreateNumberStepper(countCell, 1, RaidLottery:GetMaxCount(1000), 1, function(value)
        RaidLottery:SetCount(value)
        Refresh()
    end)
    ui.stepper = stepper
    Layout.Row(countCell, { countLabel, stepper }, Spacing.LARGE)

    local items = {}
    for index, role in ipairs(RaidLottery.ROLES) do
        items[index] = { value = role, text = RaidLottery:GetRoleLabel(role) }
    end
    local roles = Widgets.CreateSegmentedControl(roleCell, items, function(role)
        RaidLottery:SetRole(role)
        Refresh()
    end)
    roles:SetPoint("LEFT", roleCell, "LEFT")
    ui.roles = roles
end

---Eligible / excluded summary, right-aligned on the page title row.
---@param container Frame
local function BuildSummary(container)
    local summary = Widgets.CreateLabel(container.header, Fonts.SMALL_MUTED)
    summary:SetJustifyH("RIGHT")
    summary:SetJustifyV("MIDDLE")
    summary:SetWordWrap(false)
    summary:SetMaxLines(1)
    summary:SetPoint("TOP", container.titleLabel, "TOP")
    summary:SetPoint("BOTTOM", container.titleLabel, "BOTTOM")
    summary:SetPoint("LEFT", container.titleLabel, "RIGHT", Spacing.LARGE, 0)
    summary:SetPoint("RIGHT", container.header, "RIGHT")
    ui.summary = summary
end

---Member grid inside the excluded collapsible. The clear action lives on the header.
---@param content Frame
local function BuildExcludedContent(content)
    local body = Layout.Stack(content, { paddingY = Spacing.SMALL })
    ui.excludedBody = body
    ui.grid = body:Add(CreateFrame("Frame", nil, content), 0)

    local emptyRoster = Widgets.CreateLabel(ui.grid, Fonts.MUTED, L.RAID_LOTTERY_EMPTY_ROSTER)
    emptyRoster:SetPoint("TOPLEFT", ui.grid, "TOPLEFT", 0, -Spacing.TINY)
    ui.emptyRoster = emptyRoster
end

local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })
    ui = { container = container, stack = stack, checkboxes = {}, memberCount = 0 }
    BuildSummary(container)

    BuildConfigRow(stack:AddRow(Sizes.CONTROL_ROW_HEIGHT))

    -- Session-only: the member list starts collapsed every time the panel opens.
    ui.excludedSection = CollapsibleSection.Create(stack, {
        title = L.RAID_LOTTERY_EXCLUDED_HEADER,
        expanded = false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = function(height)
            container:SetContentHeight(height)
        end,
        onExpandedChanged = function()
            Refresh()
        end,
    })
    BuildExcludedContent(ui.excludedSection.content)
    ui.excludedSection:SetContentHeight(ui.excludedBody:GetHeight())

    local clearButton = Widgets.CreateTextButton(ui.excludedSection, L.RAID_LOTTERY_CLEAR_EXCLUDED, function()
        RaidLottery:ClearExcluded()
        Refresh()
    end)
    ui.excludedSection:SetHeaderAction(clearButton)
    ui.clearButton = clearButton

    ui.footer = ActionFooter.Create(stack.container, {
        text = L.RAID_LOTTERY_DRAW,
        onClick = function()
            RaidLottery:Draw()
            -- Exclusions are usually set once per draw, so the list folds away until it's needed again.
            if ui.excludedSection:IsExpanded() then
                ui.excludedSection:SetExpanded(false)
            end
        end,
        onHeightChanged = function(height)
            stack:SetEntryHeight(ui.footer, height)
            container:SetContentHeight(stack:GetHeight())
        end,
    })
    stack:Add(ui.footer, ui.footer:GetHeight(), Spacing.MEDIUM)

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

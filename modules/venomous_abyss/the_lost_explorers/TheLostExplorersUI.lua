local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CalloutMessage = ns.CalloutMessage
local Combat = ns.Api.Combat
local ActionRow = ns.ActionRow
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Util = ns.Util
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local TheLostExplorers = ns.Modules.Get("TheLostExplorers")

local LAYOUT_ID_CALLOUT = "TheLostExplorers:callout"
local LAYOUT_SCOPE_ID = "the_lost_explorers"
local CALLOUT_WIDTH = 420
local CALLOUT_HEIGHT = 72
-- Dropdown sentinel for an empty feed-order slot (distinct from boss id strings).
local FEED_ORDER_NONE = false

local calloutWindow
local calloutLayoutRegistered = false
local layoutEditing = false
local CreateCalloutWindow
local UpdateCalloutWindow
local RegisterCalloutLayoutElement

function CreateCalloutWindow()
    local frame = CalloutMessage.Create({
        name = ns.ADDON_NAME .. "TheLostExplorersCallout",
        width = CALLOUT_WIDTH,
        height = CALLOUT_HEIGHT,
    })
    LayoutEditor.ApplyPosition(frame, TheLostExplorers:GetCalloutPosition())
    RegisterCalloutLayoutElement(frame)
    return frame
end

function UpdateCalloutWindow()
    if layoutEditing then
        return
    end
    calloutWindow = calloutWindow or CreateCalloutWindow()
    LayoutEditor.ApplyPosition(calloutWindow, TheLostExplorers:GetCalloutPosition())
    local text = TheLostExplorers:GetDisplayedCallout()
    if text == nil then
        calloutWindow:Clear()
        return
    end
    local remaining = TheLostExplorers:GetCalloutRemainingSeconds()
    if remaining == nil then
        calloutWindow:Clear()
        return
    end
    calloutWindow:SetMessage(text, remaining, true)
end

function RegisterCalloutLayoutElement(frame)
    if calloutLayoutRegistered then
        return
    end
    calloutLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID_CALLOUT,
        label = L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_TITLE,
        frame = frame,
        global = false,
        isEnabled = function()
            return TheLostExplorers:IsEnabled()
        end,
        getPosition = function()
            return TheLostExplorers:GetCalloutPosition()
        end,
        setPosition = function(position)
            TheLostExplorers:SetCalloutPosition(position)
        end,
        getDefaultPosition = function()
            return ns.CalloutPosition.DefaultPosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            local win = calloutWindow or CreateCalloutWindow()
            win:ShowPreview(L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, TheLostExplorers.CALLOUT_DURATION, true)
        end,
        onEditEnd = function()
            layoutEditing = false
            UpdateCalloutWindow()
        end,
    })
end

local function BeginEditPosition()
    if Combat.IsInCombat() or Combat.IsLockedDown() then
        Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
        return
    end
    if not TheLostExplorers:IsEnabled() then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return
    end
    LayoutEditor.BeginScope(LAYOUT_SCOPE_ID)
end

local FEED_ORDER_CHOICE_SLOTS = TheLostExplorers.FEED_ORDER_SIZE - 1

---Boss choices for one editable slot, excluding bosses already picked in earlier slots.
---@param slot integer
---@return DropdownItem[]
local function BuildFeedOrderItems(slot)
    local used = {}
    for earlier = 1, slot - 1 do
        local bossId = TheLostExplorers:GetFeedOrderSlot(earlier)
        if bossId then
            used[bossId] = true
        end
    end
    local items = {
        { value = FEED_ORDER_NONE, text = L.THE_LOST_EXPLORERS_FEED_ORDER_UNSPECIFIED },
    }
    for _, bossId in ipairs(TheLostExplorers.FEED_BOSSES) do
        if not used[bossId] then
            items[#items + 1] = {
                value = bossId,
                text = TheLostExplorers:GetFeedBossLabel(bossId),
            }
        end
    end
    return items
end

---@return string
local function FeedOrderResolvedText()
    local bossId = TheLostExplorers:GetFeedOrderSlot(TheLostExplorers.FEED_ORDER_SIZE)
    if bossId then
        return TheLostExplorers:GetFeedBossLabel(bossId)
    end
    return L.THE_LOST_EXPLORERS_FEED_ORDER_UNSPECIFIED
end

---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local toolsRow = body:AddRow(ActionRow.HEIGHT)
    ActionRow.Apply(toolsRow, {
        title = L.THE_LOST_EXPLORERS_TOOLS_LAYOUT,
        description = L.THE_LOST_EXPLORERS_TOOLS_LAYOUT_DESC,
        buttons = {
            { text = L.THE_LOST_EXPLORERS_EDIT_POSITION, onClick = BeginEditPosition, layout = true },
        },
    })

    local orderHeader = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local orderLabel = Widgets.CreateLabel(orderHeader, Fonts.BODY, L.THE_LOST_EXPLORERS_FEED_ORDER)
    orderLabel:SetJustifyH("LEFT")
    orderLabel:SetPoint("LEFT", orderHeader, "LEFT")

    ---@type Dropdown[]
    local orderDropdowns = {}
    ---@type FontString|nil
    local resolvedLabel

    local function RefreshFeedOrderControls()
        for slot = 1, FEED_ORDER_CHOICE_SLOTS do
            local dropdown = orderDropdowns[slot]
            dropdown:SetItems(BuildFeedOrderItems(slot))
            dropdown:SetSelected(TheLostExplorers:GetFeedOrderSlot(slot) or FEED_ORDER_NONE)
            -- Re-apply so later slots stay locked when the page re-enables the tree.
            dropdown:SetEnabled(TheLostExplorers:IsEnabled())
        end
        if resolvedLabel then
            resolvedLabel:SetText(FeedOrderResolvedText())
        end
    end

    local resetOrder = Widgets.CreateTextButton(orderHeader, L.THE_LOST_EXPLORERS_FEED_ORDER_RESET, function()
        TheLostExplorers:ClearFeedOrder()
        RefreshFeedOrderControls()
    end)
    resetOrder:SetPoint("RIGHT", orderHeader, "RIGHT")

    local orderRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    -- Gap holds the arrow centered between equal columns.
    local columns = Layout.Columns(orderRow, TheLostExplorers.FEED_ORDER_SIZE, Spacing.XLARGE)
    for slot, column in ipairs(columns) do
        local slotLabel =
            Widgets.CreateLabel(column, Fonts.BODY, string.format(L.THE_LOST_EXPLORERS_FEED_ORDER_SLOT, slot))
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetPoint("LEFT", column, "LEFT")

        ---@type Region
        local control
        if slot <= FEED_ORDER_CHOICE_SLOTS then
            local dropdown
            dropdown = Widgets.CreateDropdown(column, BuildFeedOrderItems(slot), function(value)
                TheLostExplorers:SetFeedOrderSlot(slot, value)
                RefreshFeedOrderControls()
            end)
            dropdown:SetAutoWidth(false)
            local rawSetEnabled = dropdown.SetEnabled
            ---Later slots stay locked until every earlier slot has a boss.
            function dropdown:SetEnabled(enabled)
                local unlocked = slot == 1 or TheLostExplorers:GetFeedOrderSlot(slot - 1) ~= nil
                rawSetEnabled(self, enabled == true and unlocked)
            end
            dropdown:SetSelected(TheLostExplorers:GetFeedOrderSlot(slot) or FEED_ORDER_NONE)
            dropdown:SetEnabled(TheLostExplorers:IsEnabled())
            orderDropdowns[slot] = dropdown
            control = dropdown
        else
            -- Slot 3 is derived from the first two choices; show as plain text in the same column.
            resolvedLabel = Widgets.CreateLabel(column, Fonts.BODY, FeedOrderResolvedText())
            resolvedLabel:SetJustifyH("CENTER")
            resolvedLabel:SetWordWrap(false)
            control = resolvedLabel
        end

        control:SetPoint("LEFT", slotLabel, "RIGHT", Spacing.SMALL, 0)
        local function SyncControlWidth(_, columnWidth)
            if not columnWidth or columnWidth <= 0 then
                return
            end
            control:SetWidth(math.max(columnWidth - slotLabel:GetStringWidth() - Spacing.SMALL, 1))
        end
        column:HookScript("OnSizeChanged", SyncControlWidth)
        SyncControlWidth(column, column:GetWidth())

        local nextColumn = columns[slot + 1]
        if nextColumn then
            local arrow = Widgets.CreateLabel(orderRow, Fonts.SMALL_MUTED, L.THE_LOST_EXPLORERS_FEED_ORDER_ARROW)
            arrow:SetJustifyH("CENTER")
            arrow:SetPoint("LEFT", column, "RIGHT")
            arrow:SetPoint("RIGHT", nextColumn, "LEFT")
        end
    end

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    container:RefreshContentInteractive()
    return height
end

function TheLostExplorers:OnEnable()
    LayoutEditor.RegisterScope({
        id = LAYOUT_SCOPE_ID,
        label = L.THE_LOST_EXPLORERS_LAYOUT_SCOPE,
        order = 3,
        elementIds = { LAYOUT_ID_CALLOUT },
        prepare = function()
            calloutWindow = calloutWindow or CreateCalloutWindow()
        end,
    })
    ns.MainPanel:RegisterSection({
        title = L.THE_LOST_EXPLORERS_TITLE,
        headerTitle = L.THE_LOST_EXPLORERS_FEED_FISH,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        enabled = TheLostExplorers:IsEnabled(),
        onEnabledChanged = function(enabled)
            TheLostExplorers:SetEnabled(enabled)
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
        build = Build,
    })
    self:ListenForFeedFish()
    calloutWindow = calloutWindow or CreateCalloutWindow()
    UpdateCalloutWindow()
end

function TheLostExplorers:OnCalloutChanged()
    UpdateCalloutWindow()
end

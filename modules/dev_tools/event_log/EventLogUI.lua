local _, ns = ...
local Internals = ns.Modules.Internals("EventLog")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Slider = ns.Slider
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local EventLog = ns.Modules.Get("EventLog")

---@class EventLogRow
---@field frame Frame
---@field label FontString
---@field button Button
---@field logID integer|nil

---@type Frame|nil
local contentFrame
---@type LayoutStack|nil
local bodyStack
---@type Frame|nil
local listFrame
---@type LayoutStack|nil
local listStack
---@type Frame|nil
local emptyRow
---@type EventLogRow[]
local rows = {}
---@type integer|nil
local shownLogID

---@param seconds number
---@return string
local function FormatDuration(seconds)
    local total = math.floor(seconds + 0.5)
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

---@param saved EventLogSaved
---@return string
local function FormatTitle(saved)
    local name = saved.encounterName or L.EVENT_LOG_ENCOUNTER_FALLBACK:format(saved.encounterID)
    local duration = saved.duration and L.EVENT_LOG_DURATION:format(FormatDuration(saved.duration))
        or L.EVENT_LOG_RECORDING
    return L.EVENT_LOG_ENTRY_TITLE:format(name, saved.startedAt, duration)
end

---@param row Frame
---@param label FontString
---@param slider SliderControl
local function PlaceSlider(row, label, slider)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT")
    local box = slider.valueBox
    box:ClearAllPoints()
    box:SetPoint("RIGHT", row, "RIGHT")
    slider:ClearAllPoints()
    slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -Spacing.MEDIUM, 0)
end

---@param index integer
---@return EventLogRow row, boolean created
local function EnsureRow(index)
    local row = rows[index]
    if row then
        return row, false
    end
    local frame = CreateFrame("Frame", nil, listFrame)
    row = { frame = frame }
    row.button = Widgets.CreateTextButton(frame, L.EVENT_LOG_VIEW, function()
        local text = row.logID and EventLog:GetLogText(row.logID)
        if text then
            shownLogID = row.logID
            Internals.LogPopup.Show(text)
        end
    end)
    row.button:SetPoint("RIGHT", frame, "RIGHT")
    row.label = Widgets.CreateLabel(frame, Fonts.BODY, "")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("LEFT", frame, "LEFT")
    row.label:SetPoint("RIGHT", row.button, "LEFT", -Spacing.LARGE, 0)
    rows[index] = row
    return row, true
end

local function RefreshList()
    if not contentFrame or not bodyStack or not listStack or not emptyRow then
        return
    end
    local saved = EventLog:GetSavedLogs()
    local createdRows = false
    listStack:BeginUpdate()
    listStack:Clear()
    if #saved == 0 then
        listStack:Add(emptyRow, Sizes.CONTROL_ROW_HEIGHT)
    else
        emptyRow:Hide()
    end
    for i = 1, #saved do
        local row, created = EnsureRow(i)
        createdRows = createdRows or created
        row.logID = saved[i].id
        row.label:SetText(FormatTitle(saved[i]))
        listStack:Add(row.frame, Sizes.CONTROL_ROW_HEIGHT)
    end
    for i = #saved + 1, #rows do
        rows[i].logID = nil
        rows[i].frame:Hide()
    end
    listStack:EndUpdate()

    bodyStack:SetEntryHeight(listFrame, listStack:GetHeight())
    contentFrame:SetContentHeight(bodyStack:GetHeight())
    if createdRows and contentFrame.RefreshContentInteractive then
        contentFrame:RefreshContentInteractive()
    end

    local text = shownLogID and EventLog:GetLogText(shownLogID)
    if text then
        Internals.LogPopup.RefreshIfShown(text)
    end
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    contentFrame = content
    bodyStack = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local maxRow = bodyStack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local maxLabel = Widgets.CreateLabel(maxRow, Fonts.BODY, L.EVENT_LOG_MAX_LOGS)
    local maxSlider = Slider.Create(maxRow, EventLog.MAX_LOGS_MIN, EventLog.MAX_LOGS_MAX, EventLog.MAX_LOGS_STEP)
    Widgets.AttachTooltip(maxSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.EVENT_LOG_MAX_LOGS_TOOLTIP)
    end)
    maxSlider:SetValue(EventLog:GetMaxLogs())
    maxSlider:SetScript("OnValueChanged", function(_, rawValue)
        EventLog:SetMaxLogs(rawValue)
    end)
    PlaceSlider(maxRow, maxLabel, maxSlider)

    listFrame = bodyStack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    listStack = Layout.Stack(listFrame, { spacing = Spacing.SMALL })

    emptyRow = CreateFrame("Frame", nil, listFrame)
    local emptyLabel = Widgets.CreateLabel(emptyRow, Fonts.BODY, L.EVENT_LOG_STATUS_EMPTY)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:SetWordWrap(false)
    emptyLabel:SetPoint("LEFT", emptyRow, "LEFT")
    emptyLabel:SetPoint("RIGHT", emptyRow, "RIGHT")

    RefreshList()
    return bodyStack:GetHeight()
end

function EventLog:OnSavedLogChanged()
    RefreshList()
end

function EventLog:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.EVENT_LOG_TITLE,
        group = ns.PanelGroups.DEV_TOOLS,
        subtitle = L.EVENT_LOG_SUBTITLE,
        enabled = EventLog:IsEnabled(),
        onEnabledChanged = function(enabled)
            EventLog:SetEnabled(enabled)
        end,
        build = BuildContent,
    })
    self:StartListening()
end

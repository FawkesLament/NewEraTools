local _, ns = ...
local Internals = ns.Modules.Internals("EventLog")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local EventLog = ns.Modules.Get("EventLog")

---@type FontString|nil
local statusLabel
---@type Button|nil
local viewButton
---@type Frame|nil
local contentFrame

local function ApplyStatus()
    if not statusLabel or not viewButton then
        return
    end
    local saved = EventLog:GetSavedLog()
    if not saved then
        statusLabel:SetText(L.EVENT_LOG_STATUS_EMPTY)
        viewButton:Hide()
        return
    end
    statusLabel:SetText(L.EVENT_LOG_STATUS_SAVED:format(saved.encounterID, saved.startedAt))
    viewButton:Show()
    viewButton:SetEnabled(true)
    viewButton:SetAlpha(1)
end

local function RefreshStatus()
    if contentFrame and contentFrame.RefreshContentInteractive then
        contentFrame:RefreshContentInteractive()
    end
    ApplyStatus()
    Internals.LogPopup.RefreshIfShown(EventLog:GetLogText())
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    contentFrame = content
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local statusRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    viewButton = Widgets.CreateTextButton(statusRow, L.EVENT_LOG_VIEW, function()
        Internals.LogPopup.Show(EventLog:GetLogText())
    end)
    viewButton:SetPoint("RIGHT", statusRow, "RIGHT")

    statusLabel = Widgets.CreateLabel(statusRow, Fonts.BODY, L.EVENT_LOG_STATUS_EMPTY)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetWordWrap(false)
    statusLabel:SetPoint("LEFT", statusRow, "LEFT")
    statusLabel:SetPoint("RIGHT", viewButton, "LEFT", -Spacing.LARGE, 0)

    ApplyStatus()
    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    RefreshStatus()
    return height
end

function EventLog:OnSavedLogChanged()
    RefreshStatus()
end

function EventLog:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.EVENT_LOG_TITLE,
        group = ns.PanelGroups.DEV_TOOLS,
        tooltip = L.EVENT_LOG_HINT,
        enabled = EventLog:IsEnabled(),
        onEnabledChanged = function(enabled)
            EventLog:SetEnabled(enabled)
            RefreshStatus()
        end,
        build = Build,
    })
    self:StartListening()
end

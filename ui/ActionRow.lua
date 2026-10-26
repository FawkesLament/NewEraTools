local _, ns = ...
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local ActionRow = {}
ns.ActionRow = ActionRow

local TITLE_SIZE = Assets.FontStyles[Fonts.BODY].size
local DESCRIPTION_SIZE = Assets.FontStyles[Fonts.SMALL_MUTED].size
-- A wrapped sentence stays inside the row. Panel scale changes the window, not this text width.
local DESCRIPTION_LINES = 2

local TEXT_HEIGHT = TITLE_SIZE + Spacing.TINY + DESCRIPTION_SIZE * DESCRIPTION_LINES

---Fits the control height and a title plus two description lines.
ActionRow.HEIGHT = math.max(Sizes.CONTROL_HEIGHT, TEXT_HEIGHT) + 2 * Spacing.SMALL

---@class ActionRowButton
---@field text string
---@field onClick fun()
---@field variant ButtonVariant|nil  Passed to CreateButton. Defaults to secondary.
---@field layout boolean|nil  When true, uses the layout-edit button instead.

---@class ActionRowOptions
---@field title string
---@field description string
---@field buttons ActionRowButton[]  Left to right. Each stays as wide as its label.

---@param label FontString
---@param fallback number
---@return number
local function StringHeight(label, fallback)
    local height = label:GetStringHeight()
    if type(height) == "number" and height > 0 then
        return height
    end
    return fallback
end

---Title and description on the left, content-sized buttons on the right.
---`row` should be `ActionRow.HEIGHT` tall (for example `stack:AddRow(ActionRow.HEIGHT)`).
---@param row Frame
---@param options ActionRowOptions
---@return Button[]
function ActionRow.Apply(row, options)
    assert(type(options) == "table" and type(options.title) == "string", "ActionRow requires a title")
    assert(type(options.description) == "string", "ActionRow requires a description")
    assert(type(options.buttons) == "table" and #options.buttons > 0, "ActionRow requires buttons")

    local textCell, actionCell = Layout.SplitRow(row, Spacing.XLARGE)

    local title = Widgets.CreateLabel(textCell, Fonts.BODY, options.title)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    local description = Widgets.CreateLabel(textCell, Fonts.SMALL_MUTED, options.description)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)
    description:SetMaxLines(DESCRIPTION_LINES)

    local function PlaceText()
        local block = StringHeight(title, TITLE_SIZE) + Spacing.TINY + StringHeight(description, DESCRIPTION_SIZE)
        local rowHeight = row:GetHeight()
        if type(rowHeight) ~= "number" or rowHeight < ActionRow.HEIGHT then
            rowHeight = ActionRow.HEIGHT
        end
        local offset = math.max(0, (rowHeight - block) / 2)
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", textCell, "TOPLEFT", 0, -offset)
        title:SetPoint("TOPRIGHT", textCell, "TOPRIGHT", 0, -offset)
        description:ClearAllPoints()
        description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Spacing.TINY)
        description:SetPoint("RIGHT", textCell, "RIGHT")
    end

    PlaceText()
    row:HookScript("OnSizeChanged", PlaceText)

    ---@param text string
    ---@param color table|nil  Assets color; defaults to TEXT_MUTED.
    function row:SetDescription(text, color)
        description:SetText(text or "")
        description:SetTextColor(Widgets.UnpackColor(color or Colors.TEXT_MUTED))
        PlaceText()
    end

    ---@type Button[]
    local buttons = {}
    for index, spec in ipairs(options.buttons) do
        assert(type(spec.text) == "string" and type(spec.onClick) == "function", "ActionRow button is incomplete")
        local button
        if spec.layout then
            button = Widgets.CreateLayoutEditButton(actionCell, spec.text, spec.onClick)
        else
            button = Widgets.CreateButton(actionCell, spec.text, spec.onClick, spec.variant)
        end
        button:SetHeight(Sizes.CONTROL_HEIGHT)
        buttons[index] = button
    end

    -- Right-align the group so the labels keep the width CreateButton measured.
    local nextButton
    for index = #buttons, 1, -1 do
        local button = buttons[index]
        button:ClearAllPoints()
        if nextButton then
            button:SetPoint("RIGHT", nextButton, "LEFT", -Spacing.MEDIUM, 0)
        else
            button:SetPoint("RIGHT", actionCell, "RIGHT")
        end
        nextButton = button
    end

    return buttons
end

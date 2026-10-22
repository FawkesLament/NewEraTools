local _, ns = ...
local Assets = ns.Assets
local L = ns.L
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Dropdown = {}
ns.Dropdown = Dropdown

local DISABLED_ALPHA = 0.4
-- Flatter down-chevron for dropdown triggers (wider tip angle than the expand-button chevron).
local DROPDOWN_CARET = { { 1, 3 }, { 5, 5 }, { 9, 3 } }
-- Above MainPanel (DIALOG) and layout-edit chrome (FULLSCREEN_DIALOG) so popups are never covered.
local DROPDOWN_MENU_STRATA = "TOOLTIP"

---@class DropdownItem
---@field value any
---@field text string

---@class Dropdown: Frame
---@field SetSelected fun(self: Dropdown, value: any)  Updates the trigger label for `value`.
---@field SetItems fun(self: Dropdown, items: DropdownItem[])  Replaces the choice list; recreates the popup on next open.
---@field SetAutoWidth fun(self: Dropdown, enabled: boolean)  When false, width comes from anchors/SetWidth; popup still matches.
---@field SetJustifyH fun(self: Dropdown, justifyH: string)  Horizontal alignment of the selected-value label. Defaults to CENTER.
---@field SetEnabled fun(self: Dropdown, enabled: boolean)
---@field IsEnabled fun(self: Dropdown): boolean
---@field Close fun(self: Dropdown)  Hides the popup and its outside-click catcher.

---Creates a compact dropdown: a trigger button and a popup list of choices.
---Selecting an item calls `onSelect`; the caller then calls SetSelected to show the new choice.
---@param parent Frame
---@param items DropdownItem[]
---@param onSelect fun(value: any)
---@return Dropdown
function Dropdown.Create(parent, items, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent) --[[@as Dropdown]]
    local currentItems = items
    local textByValue = {}
    local selectedValue
    local autoWidth = true
    local menu
    local catcher
    local label
    Widgets.EnsureFonts()
    local measure = dropdown:CreateFontString(nil, "OVERLAY", Fonts.BODY)
    measure:SetFontObject(Fonts.BODY)
    measure:Hide()

    local function CloseMenu()
        if menu then
            menu:Hide()
        end
        if catcher then
            catcher:Hide()
        end
    end

    local function DiscardMenu()
        CloseMenu()
        if menu then
            menu:SetParent(nil)
            menu = nil
        end
    end

    ---Keeps the popup above the settings panel and any later sibling sections.
    local function RaiseMenu()
        if catcher then
            catcher:SetFrameStrata(DROPDOWN_MENU_STRATA)
            catcher:Raise()
        end
        if menu then
            menu:SetFrameStrata(DROPDOWN_MENU_STRATA)
            -- Raise after the catcher so the list stays clickable above the outside-click shield.
            menu:Raise()
        end
    end

    local function ApplyItems(nextItems)
        currentItems = nextItems
        for key in pairs(textByValue) do
            textByValue[key] = nil
        end
        local maxTextWidth = 0
        for _, item in ipairs(currentItems) do
            textByValue[item.value] = item.text
            measure:SetText(item.text)
            maxTextWidth = math.max(maxTextWidth, measure:GetStringWidth())
        end
        if autoWidth then
            local width = math.max(maxTextWidth + Sizes.DROPDOWN_TEXT_PADDING, Sizes.DROPDOWN_MIN_WIDTH)
            dropdown:SetSize(width, Sizes.CONTROL_HEIGHT)
        else
            dropdown:SetHeight(Sizes.CONTROL_HEIGHT)
        end
        DiscardMenu()
        if label and selectedValue ~= nil then
            label:SetText(textByValue[selectedValue] or selectedValue or "")
        end
    end

    local function EnsureMenu()
        if menu then
            return
        end
        -- Full-screen catcher closes the menu on an outside click without eating other input while hidden.
        if not catcher then
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetFrameStrata(DROPDOWN_MENU_STRATA)
            catcher:SetAllPoints()
            catcher:EnableMouse(true)
            -- Swallow wheel so the open menu cannot scroll the panel underneath.
            catcher:EnableMouseWheel(true)
            catcher:SetScript("OnMouseWheel", function() end)
            catcher:SetScript("OnClick", CloseMenu)
            catcher:Hide()
        end

        local optionHeight = Sizes.CONTROL_HEIGHT
        local contentHeight = math.max(#currentItems, 1) * optionHeight
        local viewHeight = math.min(contentHeight, Sizes.DROPDOWN_MAX_VISIBLE * optionHeight)
        local needsScroll = contentHeight > viewHeight
        local scrollGutter = needsScroll and (Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL) or 0
        local options = {}

        -- Height only: width is locked to the trigger via TOPLEFT+TOPRIGHT in ToggleMenu.
        menu = Widgets.CreateSurface(UIParent, Colors.SURFACE_RAISED, Colors.BORDER)
        menu:SetFrameStrata(DROPDOWN_MENU_STRATA)
        menu:SetFrameLevel(catcher:GetFrameLevel() + 1)
        menu:SetHeight(viewHeight + 2 * Sizes.BORDER)
        menu:EnableMouse(true)
        menu:Hide()

        local scrollFrame = CreateFrame("ScrollFrame", nil, menu)
        scrollFrame:SetPoint("TOPLEFT", Sizes.BORDER, -Sizes.BORDER)
        scrollFrame:SetPoint("BOTTOMRIGHT", -(Sizes.BORDER + scrollGutter), Sizes.BORDER)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetHeight(contentHeight)
        scrollFrame:SetScrollChild(content)

        ---@param _ Frame
        ---@param delta number
        local function OnMenuMouseWheel(_, delta)
            local range = scrollFrame:GetVerticalScrollRange()
            if range <= 0 then
                return
            end
            local next = scrollFrame:GetVerticalScroll() - delta * optionHeight
            scrollFrame:SetVerticalScroll(math.min(math.max(next, 0), range))
        end

        -- Wheel over options hits the button, not the ScrollFrame; bind all layers so the
        -- main panel underneath never receives the event while the menu is open.
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", OnMenuMouseWheel)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", OnMenuMouseWheel)
        content:EnableMouse(true)
        content:EnableMouseWheel(true)
        content:SetScript("OnMouseWheel", OnMenuMouseWheel)

        if needsScroll then
            local scrollBar = CreateFrame("EventFrame", nil, menu, Assets.Templates.SCROLL_BAR)
            scrollBar:SetPoint("TOPRIGHT", -Sizes.BORDER, -Sizes.BORDER)
            scrollBar:SetPoint("BOTTOMRIGHT", -Sizes.BORDER, Sizes.BORDER)
            ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
        end

        for index, item in ipairs(currentItems) do
            local option = Widgets.CreateFlatButton(content, "secondary", function()
                CloseMenu()
                onSelect(item.value)
            end)
            option:SetText(item.text)
            option:SetHeight(optionHeight)
            option:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * optionHeight))
            option:EnableMouseWheel(true)
            option:SetScript("OnMouseWheel", OnMenuMouseWheel)
            options[index] = option
        end

        -- Runs after TOPLEFT+TOPRIGHT pin the menu to the trigger's real laid-out width.
        menu:HookScript("OnSizeChanged", function(self, menuWidth)
            if menuWidth <= 0 then
                return
            end
            local innerWidth = math.max(menuWidth - 2 * Sizes.BORDER - scrollGutter, 1)
            content:SetWidth(innerWidth)
            for _, option in ipairs(options) do
                option:SetWidth(innerWidth)
            end
        end)
    end

    local function ToggleMenu()
        EnsureMenu()
        if menu:IsShown() then
            CloseMenu()
            return
        end
        menu:ClearAllPoints()
        -- Match the trigger when it lives on a scaled panel (the edit toolbar, or the main panel).
        local uiScale = UIParent:GetEffectiveScale()
        if uiScale and uiScale > 0 then
            menu:SetScale(dropdown:GetEffectiveScale() / uiScale)
        end
        -- Pin both corners so the popup width always matches the trigger, including anchor-stretched triggers.
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -Spacing.TINY)
        menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -Spacing.TINY)
        catcher:Show()
        menu:Show()
        RaiseMenu()
    end

    local trigger = Widgets.CreateFlatButton(dropdown, "secondary", ToggleMenu)
    trigger:SetAllPoints(dropdown)
    -- FeatureSection walks SetEnabled on descendants after the dropdown; keep the trigger
    -- gated by this flag so a locked/disabled dropdown cannot be re-enabled underneath.
    local dropdownEnabled = true
    local rawTriggerSetEnabled = trigger.SetEnabled
    function trigger:SetEnabled(enabled)
        rawTriggerSetEnabled(self, enabled == true and dropdownEnabled)
    end

    label = Widgets.CreateLabel(trigger, Fonts.BODY)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetPoint("LEFT", Spacing.MEDIUM, 0)
    label:SetPoint("RIGHT", trigger, "RIGHT", -(Spacing.MEDIUM + Spacing.LARGE), 0)

    -- Line-drawn caret (locale fonts often lack wide-angle Unicode glyphs like ⌵).
    local caret = CreateFrame("Frame", nil, trigger)
    caret:SetSize(Sizes.DROPDOWN_CARET, Sizes.DROPDOWN_CARET)
    caret:SetPoint("RIGHT", -Spacing.MEDIUM, 0)
    local caretTip = DROPDOWN_CARET[2]
    for index = 1, 2 do
        local stroke = caret:CreateLine(nil, "ARTWORK")
        stroke:SetThickness(Sizes.DROPDOWN_CARET_THICKNESS)
        stroke:SetColorTexture(Widgets.UnpackColor(Colors.TEXT_MUTED))
        stroke:SetSnapToPixelGrid(false)
        stroke:SetTexelSnappingBias(0)
        local outer = DROPDOWN_CARET[index == 1 and 1 or 3]
        local dx, dy = caretTip[1] - outer[1], caretTip[2] - outer[2]
        local extend = Sizes.DROPDOWN_CARET_THICKNESS / 2 / math.sqrt(dx * dx + dy * dy)
        stroke:SetStartPoint("TOPLEFT", caret, outer[1], -outer[2])
        stroke:SetEndPoint("TOPLEFT", caret, caretTip[1] + dx * extend, -(caretTip[2] + dy * extend))
    end

    function dropdown:SetSelected(value)
        selectedValue = value
        label:SetText(textByValue[value] or value or "")
    end

    function dropdown:SetItems(nextItems)
        ApplyItems(nextItems)
    end

    ---When false, callers size the trigger with anchors or SetWidth; the popup still matches that width.
    ---@param enabled boolean
    function dropdown:SetAutoWidth(enabled)
        autoWidth = enabled == true
        ApplyItems(currentItems)
    end

    ---@param justifyH string  "LEFT", "CENTER", or "RIGHT".
    function dropdown:SetJustifyH(justifyH)
        label:SetJustifyH(justifyH)
    end

    function dropdown:SetEnabled(enabled)
        dropdownEnabled = enabled == true
        trigger:SetEnabled(dropdownEnabled)
        -- Fade the outer frame; keep the trigger opaque so FeatureSection (or this call) does
        -- not stack DISABLED_ALPHA on both. Callers that unlock without RefreshContentInteractive
        -- still restore opacity here.
        trigger:SetAlpha(1)
        self:SetAlpha(dropdownEnabled and 1 or DISABLED_ALPHA)
        if not dropdownEnabled then
            CloseMenu()
        end
    end

    function dropdown:IsEnabled()
        return dropdownEnabled
    end

    ---Hides the popup. Safe when the menu has never been opened.
    function dropdown:Close()
        CloseMenu()
    end

    ApplyItems(items)
    return dropdown
end

---@class FontDropdown: Dropdown
---@field label FontString  Caption to the left of the trigger; callers may attach a pending clock.
---@field RefreshItems fun(self: FontDropdown)  Rebuilds the list from SharedMedia.

---Labeled dropdown of `default` plus LibSharedMedia fonts. Stretches to fill `parent`.
---@param parent Frame
---@param labelText string
---@param onSelect fun(fontId: string)
---@return FontDropdown
function Dropdown.CreateFont(parent, labelText, onSelect)
    local SharedMedia = ns.SharedMedia
    local nameLabel = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetPoint("LEFT", parent, "LEFT")

    local function BuildItems()
        local items = {}
        for _, fontId in ipairs(SharedMedia.ListFontIds()) do
            items[#items + 1] = {
                value = fontId,
                text = fontId == SharedMedia.FONT_DEFAULT and L.FONT_DEFAULT or fontId,
            }
        end
        return items
    end

    local dropdown = Dropdown.Create(parent, BuildItems(), onSelect) --[[@as FontDropdown]]
    dropdown.label = nameLabel
    dropdown:SetAutoWidth(false)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("LEFT", nameLabel, "RIGHT", Spacing.LARGE, 0)
    dropdown:SetHeight(Sizes.CONTROL_HEIGHT)

    local function SyncWidth()
        local parentWidth = parent:GetWidth()
        if parentWidth <= 0 then
            return
        end
        local width = parentWidth - nameLabel:GetStringWidth() - Spacing.LARGE
        dropdown:SetWidth(math.max(width, Sizes.DROPDOWN_MIN_WIDTH))
    end
    parent:HookScript("OnSizeChanged", SyncWidth)
    SyncWidth()

    function dropdown:RefreshItems()
        self:SetItems(BuildItems())
    end

    SharedMedia.OnFontsRegistered(function()
        dropdown:RefreshItems()
    end)
    return dropdown
end

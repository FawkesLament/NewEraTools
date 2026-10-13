local _, ns = ...
local Assets = ns.Assets

local Sizes = Assets.Sizes

local CollapsiblePanel = {}
ns.CollapsiblePanel = CollapsiblePanel

---@class CollapsiblePanelOptions
---@field frame Frame  Outer panel frame to resize; scale is never changed.
---@field body Frame  Settings content container; hidden while collapsed (not destroyed).
---@field header Frame|nil  Title bar whose height shrinks in collapsed mode.
---@field expandedChrome Frame[]|nil  Extra header widgets shown only while expanded.
---@field collapsedWidth number  Compact width for the title bar.
---@field collapsedHeight number|nil  Outer frame height while collapsed. Defaults to Sizes.COLLAPSED_PANEL_HEIGHT.
---@field expandedHeaderHeight number|nil  Defaults to Sizes.HEADER_HEIGHT.
---@field onExpandedChanged fun(expanded: boolean)|nil

---@class CollapsiblePanelController
---@field SetExpanded fun(self: CollapsiblePanelController, expanded: boolean)
---@field IsExpanded fun(self: CollapsiblePanelController): boolean
---@field Toggle fun(self: CollapsiblePanelController)
---@field GetExpandedSize fun(self: CollapsiblePanelController): number, number  Cached expanded width/height.

---Keeps the frame's top-left corner on screen while resizing so the title bar does not jump.
---@param frame Frame
---@param apply fun()
local function PreserveTopLeft(frame, apply)
    local left, top = frame:GetLeft(), frame:GetTop()
    apply()
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

---Attaches collapse/expand behavior to an existing panel. Hides `body` instead of rebuilding it.
---Expanded size is cached only when leaving the expanded state, so collapsing never overwrites it.
---@param options CollapsiblePanelOptions
---@return CollapsiblePanelController
function CollapsiblePanel.Attach(options)
    assert(type(options) == "table", "CollapsiblePanel.Attach requires options")
    assert(options.frame ~= nil, "CollapsiblePanel.Attach requires frame")
    assert(options.body ~= nil, "CollapsiblePanel.Attach requires body")
    assert(type(options.collapsedWidth) == "number" and options.collapsedWidth > 0, "collapsedWidth required")

    local frame = options.frame
    local body = options.body
    local header = options.header
    local expandedChrome = options.expandedChrome or {}
    local collapsedWidth = options.collapsedWidth
    local collapsedHeight = options.collapsedHeight or Sizes.COLLAPSED_PANEL_HEIGHT
    local expandedHeaderHeight = options.expandedHeaderHeight or Sizes.HEADER_HEIGHT
    local collapsedHeaderHeight = collapsedHeight - 2 * Sizes.BORDER

    local expanded = true
    -- Seeded from the frame's current size; refreshed only on expanded → collapsed.
    local cachedWidth = frame:GetWidth()
    local cachedHeight = frame:GetHeight()

    local controller = {}

    local function ApplyChrome()
        body:SetShown(expanded)
        for _, chrome in ipairs(expandedChrome) do
            chrome:SetShown(expanded)
        end
        if header then
            header:SetHeight(expanded and expandedHeaderHeight or collapsedHeaderHeight)
        end
    end

    local function ApplySize()
        if expanded then
            frame:SetSize(cachedWidth, cachedHeight)
        else
            frame:SetSize(collapsedWidth, collapsedHeight)
        end
    end

    function controller:IsExpanded()
        return expanded
    end

    function controller:GetExpandedSize()
        return cachedWidth, cachedHeight
    end

    function controller:SetExpanded(value)
        value = value == true
        if expanded == value then
            ApplyChrome()
            ApplySize()
            return
        end

        PreserveTopLeft(frame, function()
            if expanded and not value then
                -- Capture while still expanded so a collapsed size never overwrites the cache.
                cachedWidth = frame:GetWidth()
                cachedHeight = frame:GetHeight()
            end
            expanded = value
            ApplyChrome()
            ApplySize()
        end)

        if options.onExpandedChanged then
            options.onExpandedChanged(expanded)
        end
    end

    function controller:Toggle()
        self:SetExpanded(not expanded)
    end

    ApplyChrome()
    return controller
end

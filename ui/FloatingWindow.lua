local _, ns = ...
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Sizes = Assets.Sizes

local FloatingWindow = {}
ns.FloatingWindow = FloatingWindow

---@class FloatingWindowPosition
---@field point string  e.g. "CENTER".
---@field relativePoint string
---@field x number
---@field y number

---@class FloatingWindowOptions
---@field name string|nil  Global frame name; must start with the addon name.
---@field scale number|nil  Initial scale. Defaults to 1.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field onClick fun()|nil  Left-click when the press was not a drag.
---@field dragEntireFrame boolean|nil  When true, the whole window can be dragged, not only the header strip.
---@field draggable boolean|nil  Whether dragging starts enabled. Defaults to true.
---@field closable boolean|nil  When true, a close button is created in the header.
---@field onClose fun()|nil  Called when the close button is clicked.

---@class FloatingWindow: Frame
---@field header Frame  Drag strip along the top edge; overlays content like the Sszorak map window.
---@field closeButton Button|nil
---@field SetWindowPosition fun(self: FloatingWindow, position: FloatingWindowPosition)
---@field GetWindowPosition fun(self: FloatingWindow): FloatingWindowPosition
---@field SetWindowScale fun(self: FloatingWindow, scale: number)  Keeps the window's center on screen.
---@field SetDragEnabled fun(self: FloatingWindow, enabled: boolean)  Enables or disables dragging (and mouse capture).
---@field SetClickEnabled fun(self: FloatingWindow, enabled: boolean)  Enables or disables the optional click handler.

FloatingWindow.IsValidPosition = ns.Position.IsValid

---@param frame Frame
---@param position FloatingWindowPosition
function FloatingWindow.ApplyPosition(frame, position)
    frame:ClearAllPoints()
    frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

---@param frame Frame
---@return FloatingWindowPosition
function FloatingWindow.ReadPosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    return {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

---Creates a translucent, draggable window matching the Sszorak encounter-map look.
---Uses MEDIUM strata so Blizzard DIALOG/TOOLTIP menus stay above it.
---@param options FloatingWindowOptions|nil
---@return FloatingWindow
function FloatingWindow.Create(options)
    options = options or {}

    local frame = Widgets.CreateSurface(UIParent, Colors.BG_TRANSLUCENT, Colors.BORDER, options.name) --[[@as FloatingWindow]]
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetScale(options.scale or 1)
    if options.position then
        FloatingWindow.ApplyPosition(frame, options.position)
    else
        frame:SetPoint("CENTER")
    end
    frame:Hide()

    local dragEntireFrame = options.dragEntireFrame == true
    local dragEnabled = options.draggable ~= false
    local wantsClick = options.onClick ~= nil
    local clickEnabled = wantsClick
    -- Set in OnDragStart so OnMouseUp can ignore presses that became a drag.
    local didDrag = false

    local function BeginDrag()
        if not dragEnabled then
            return
        end
        didDrag = true
        frame:StartMoving()
    end

    local function EndDrag()
        frame:StopMovingOrSizing()
        if options.onPositionChanged then
            options.onPositionChanged(FloatingWindow.ReadPosition(frame))
        end
    end

    local function OnMouseDown(_, button)
        if button == "LeftButton" then
            didDrag = false
        end
    end

    local function OnMouseUp(_, button)
        if button ~= "LeftButton" or didDrag or not clickEnabled then
            didDrag = false
            return
        end
        options.onClick()
    end

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", Sizes.BORDER, -Sizes.BORDER)
    header:SetPoint("TOPRIGHT", -Sizes.BORDER, -Sizes.BORDER)
    header:SetHeight(Sizes.CLOSE_BUTTON)
    header:SetFrameLevel(frame:GetFrameLevel() + 2)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", BeginDrag)
    header:SetScript("OnDragStop", EndDrag)
    frame.header = header

    if dragEntireFrame then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", BeginDrag)
        frame:SetScript("OnDragStop", EndDrag)
    end

    if wantsClick then
        header:SetScript("OnMouseDown", OnMouseDown)
        header:SetScript("OnMouseUp", OnMouseUp)
        frame:SetScript("OnMouseDown", OnMouseDown)
        frame:SetScript("OnMouseUp", OnMouseUp)
    end

    local function ApplyInteractionEnabled()
        -- Keep mouse capture when click handling is needed, even if dragging is off.
        local mouseEnabled = dragEnabled or (wantsClick and clickEnabled)
        header:EnableMouse(mouseEnabled)
        if dragEntireFrame or wantsClick then
            frame:EnableMouse(mouseEnabled)
        elseif not mouseEnabled then
            frame:EnableMouse(false)
        end
    end

    ApplyInteractionEnabled()

    if options.closable then
        local closeButton = Widgets.CreateCloseButton(header, function()
            if options.onClose then
                options.onClose()
            end
        end)
        closeButton:SetPoint("RIGHT")
        frame.closeButton = closeButton
    end

    function frame:SetWindowPosition(position)
        FloatingWindow.ApplyPosition(self, position)
    end

    function frame:GetWindowPosition()
        return FloatingWindow.ReadPosition(self)
    end

    -- Keeps the window's center where it is on screen; anchor offsets are in the frame's own scale.
    function frame:SetWindowScale(scale)
        local oldScale = self:GetScale()
        if math.abs(oldScale - scale) < 0.001 then
            return
        end
        local x, y = self:GetCenter()
        self:SetScale(scale)
        if x then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * oldScale / scale, y * oldScale / scale)
            if options.onPositionChanged then
                options.onPositionChanged(FloatingWindow.ReadPosition(self))
            end
        end
    end

    function frame:SetDragEnabled(enabled)
        dragEnabled = enabled == true
        ApplyInteractionEnabled()
    end

    ---Enables or disables the optional left-click handler without affecting drag.
    function frame:SetClickEnabled(enabled)
        clickEnabled = wantsClick and enabled == true
        ApplyInteractionEnabled()
    end

    return frame
end

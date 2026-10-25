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
---@field fill table|nil  Backdrop fill color from Assets.Colors. Defaults to BG_TRANSLUCENT.
---@field position FloatingWindowPosition|nil  Initial anchor on the screen.
---@field onPositionChanged fun(position: FloatingWindowPosition)|nil  After the player finishes dragging.
---@field onClick fun()|nil  Left-click when the press was not a drag.
---@field dragEntireFrame boolean|nil  When true, the whole window can be dragged, not only the header strip.
---@field draggable boolean|nil  Whether dragging starts enabled. Defaults to true.
---@field closable boolean|nil  When true, a close button is created in the header.
---@field onClose fun()|nil  Called when the close button is clicked.

---@class FloatingWindow: Frame
---@field header Frame  Padded drag strip along the top edge; overlays content like the Sszorak map window.
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

---Converts the frame's current visual center into a CENTER/CENTER UIParent offset and re-anchors it.
---StartMoving leaves arbitrary anchors (e.g. TOPLEFT); this keeps drag and numeric edits in one space.
---@param frame Frame
---@return FloatingWindowPosition
function FloatingWindow.NormalizePosition(frame)
    local cx, cy = frame:GetCenter()
    if not cx or not cy then
        local position = FloatingWindow.ReadPosition(frame)
        FloatingWindow.ApplyPosition(frame, {
            point = "CENTER",
            relativePoint = "CENTER",
            x = position.x,
            y = position.y,
        })
        return {
            point = "CENTER",
            relativePoint = "CENTER",
            x = position.x,
            y = position.y,
        }
    end

    local frameScale = frame:GetEffectiveScale()
    local parentScale = UIParent:GetEffectiveScale()
    if not frameScale or frameScale == 0 then
        frameScale = 1
    end
    if not parentScale or parentScale == 0 then
        parentScale = 1
    end
    local toFrame = parentScale / frameScale

    local pcx, pcy = UIParent:GetCenter()
    if not pcx or not pcy then
        pcx = (UIParent:GetLeft() or 0) + UIParent:GetWidth() / 2
        pcy = (UIParent:GetBottom() or 0) + UIParent:GetHeight() / 2
    end
    pcx = pcx * toFrame
    pcy = pcy * toFrame

    local position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = cx - pcx,
        y = cy - pcy,
    }
    FloatingWindow.ApplyPosition(frame, position)
    return position
end

---Applies a CENTER/CENTER position, then shifts x/y so every edge stays on screen.
---`preferredPosition.x`/`y` are CENTER/CENTER offsets. Engine clamp stays off during SetPoint so
---anchors are not rewritten; drag already keeps frames on-screen via SetClampedToScreen.
---@param frame Frame
---@param preferredPosition FloatingWindowPosition|nil  Nil normalizes the frame's current visual center.
---@return FloatingWindowPosition
function FloatingWindow.ClampToScreen(frame, preferredPosition)
    local position = preferredPosition
            and {
                point = "CENTER",
                relativePoint = "CENTER",
                x = preferredPosition.x or 0,
                y = preferredPosition.y or 0,
            }
        or FloatingWindow.NormalizePosition(frame)

    frame:SetClampedToScreen(false)
    FloatingWindow.ApplyPosition(frame, position)

    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not left or not bottom or not width or not height or width <= 0 or height <= 0 then
        frame:SetClampedToScreen(true)
        return position
    end

    local frameScale = frame:GetEffectiveScale()
    local parentScale = UIParent:GetEffectiveScale()
    if not frameScale or frameScale == 0 or not parentScale or parentScale == 0 then
        frame:SetClampedToScreen(true)
        return position
    end
    local toFrame = parentScale / frameScale
    local parentLeft = (UIParent:GetLeft() or 0) * toFrame
    local parentBottom = (UIParent:GetBottom() or 0) * toFrame
    local parentRight = parentLeft + UIParent:GetWidth() * toFrame
    local parentTop = parentBottom + UIParent:GetHeight() * toFrame
    local right = left + width
    local top = bottom + height

    local dx, dy = 0, 0
    if left < parentLeft then
        dx = parentLeft - left
    elseif right > parentRight then
        dx = parentRight - right
    end
    if bottom < parentBottom then
        dy = parentBottom - bottom
    elseif top > parentTop then
        dy = parentTop - top
    end

    if dx ~= 0 or dy ~= 0 then
        position.x = position.x + dx
        position.y = position.y + dy
        FloatingWindow.ApplyPosition(frame, position)
    end

    frame:SetClampedToScreen(true)
    return position
end

---Creates a translucent, draggable window matching the Sszorak encounter-map look.
---Uses MEDIUM strata so Blizzard DIALOG/TOOLTIP menus stay above it.
---@param options FloatingWindowOptions|nil
---@return FloatingWindow
function FloatingWindow.Create(options)
    options = options or {}

    local frame = Widgets.CreateSurface(UIParent, options.fill or Colors.BG_TRANSLUCENT, Colors.BORDER, options.name) --[[@as FloatingWindow]]
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
        -- StartMoving rewrites anchors; normalize so saved x/y stay CENTER/CENTER offsets.
        local position = FloatingWindow.NormalizePosition(frame)
        if options.onPositionChanged then
            options.onPositionChanged(position)
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
    header:SetHeight(Sizes.FLOATING_HEADER_HEIGHT)
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
        closeButton:SetPoint("RIGHT", -Sizes.FLOATING_HEADER_PAD, 0)
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

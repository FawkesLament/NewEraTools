local _, ns = ...

local Layout = {}
ns.Layout = Layout

---@class LayoutStackOptions
---@field paddingX number|nil  Left and right inset. Defaults to 0.
---@field paddingY number|nil  Top and bottom inset. Defaults to 0.
---@field spacing number|nil  Default gap between entries. Defaults to 0.

---@class LayoutStack
local Stack = {}
Stack.__index = Stack

local function Relayout(stack)
    local offset = stack.paddingY
    for index, entry in ipairs(stack.entries) do
        if index > 1 then
            offset = offset + entry.spacingBefore
        end
        entry.offset = offset
        local frame = entry.frame
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", stack.container, "TOPLEFT", stack.paddingX, -offset)
        frame:SetPoint("TOPRIGHT", stack.container, "TOPRIGHT", -stack.paddingX, -offset)
        -- Zero-height frames can leave anchored children unplaced, so keep at least one pixel.
        frame:SetHeight(math.max(entry.height, 1))
        offset = offset + entry.height
    end
    stack.height = offset + stack.paddingY
end

local function FindEntry(stack, frame)
    for _, entry in ipairs(stack.entries) do
        if entry.frame == frame then
            return entry
        end
    end
    error("Frame is not in this stack", 3)
end

---Stacks frames top to bottom inside `container`, stretching each to the container's width.
---@param container Frame
---@param options LayoutStackOptions|nil
---@return LayoutStack
function Layout.Stack(container, options)
    options = options or {}
    local stack = setmetatable({
        container = container,
        paddingX = options.paddingX or 0,
        paddingY = options.paddingY or 0,
        spacing = options.spacing or 0,
        entries = {},
    }, Stack)
    Relayout(stack)
    return stack
end

---Runs `Relayout` immediately, or waits until the matching `EndUpdate`.
---@param stack LayoutStack
local function FinishUpdate(stack)
    if (stack.updates or 0) == 0 then
        Relayout(stack)
    end
end

---Groups several inserts, removals, and height changes into one relayout.
function Stack:BeginUpdate()
    self.updates = (self.updates or 0) + 1
end

---Applies the deferred relayout. Extra calls with no matching `BeginUpdate` are ignored.
function Stack:EndUpdate()
    local updates = self.updates or 0
    if updates <= 0 then
        return
    end
    self.updates = updates - 1
    if self.updates == 0 then
        Relayout(self)
    end
end

---Drops every entry and leaves the frames shown. Callers hide frames they do not add back,
---so a frame can move into another stack during the same update.
function Stack:Clear()
    self.entries = {}
    FinishUpdate(self)
end

---Inserts `frame` as entry number `index`, moving that entry and the ones below it down.
---@generic T: Frame
---@param index integer  1-based; `#entries + 1` appends.
---@param frame T
---@param height number
---@param spacingBefore number|nil  Gap above this entry; defaults to the stack's spacing.
---@return T
function Stack:Insert(index, frame, height, spacingBefore)
    table.insert(self.entries, index, {
        frame = frame,
        height = height,
        spacingBefore = spacingBefore or self.spacing,
    })
    frame:Show()
    FinishUpdate(self)
    return frame
end

---Appends `frame` below the previous entry.
---@generic T: Frame
---@param frame T
---@param height number
---@param spacingBefore number|nil  Gap above this entry; defaults to the stack's spacing.
---@return T
function Stack:Add(frame, height, spacingBefore)
    return self:Insert(#self.entries + 1, frame, height, spacingBefore)
end

---Appends a new empty frame, parented to the container, for other widgets to sit in.
---@param height number
---@param spacingBefore number|nil  Gap above this entry; defaults to the stack's spacing.
---@return Frame
function Stack:AddRow(height, spacingBefore)
    return self:Add(CreateFrame("Frame", nil, self.container), height, spacingBefore)
end

---Changes an entry's height and moves the entries below it.
---@param frame Frame
---@param height number
function Stack:SetEntryHeight(frame, height)
    FindEntry(self, frame).height = height
    FinishUpdate(self)
end

---@param frame Frame
---@return number  Distance from the container's top to the entry's top.
function Stack:GetOffset(frame)
    return FindEntry(self, frame).offset
end

---@return number  Total height of all entries, spacing and padding.
function Stack:GetHeight()
    return self.height
end

---Lines up `widgets` left to right, vertically centered in `row`.
---@param row Frame
---@param widgets Region[]
---@param spacing number  Gap between neighboring widgets.
---@param inset number|nil  Gap before the first widget. Defaults to 0.
function Layout.Row(row, widgets, spacing, inset)
    local previous
    for _, widget in ipairs(widgets) do
        widget:ClearAllPoints()
        if previous then
            widget:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
        else
            widget:SetPoint("LEFT", row, "LEFT", inset or 0, 0)
        end
        previous = widget
    end
end

---Splits `row` into `count` equal-width cells with `gap` between neighbors.
---Widths follow the row; a row that has no width yet is laid out on its first resize.
---@param row Frame
---@param count integer
---@param gap number  Space between neighboring cells.
---@return Frame[]
function Layout.Columns(row, count, gap)
    ---@type Frame[]
    local cells = {}
    for index = 1, count do
        cells[index] = CreateFrame("Frame", nil, row)
    end

    local function Apply(width)
        if not width or width <= 0 or count < 1 then
            return
        end
        local cellWidth = math.max((width - gap * (count - 1)) / count, 1)
        for index, cell in ipairs(cells) do
            local x = (index - 1) * (cellWidth + gap)
            cell:ClearAllPoints()
            cell:SetWidth(cellWidth)
            cell:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            cell:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
        end
    end

    row:HookScript("OnSizeChanged", function(_, width)
        Apply(width)
    end)
    Apply(row:GetWidth())
    return cells
end

---Splits `row` into two equal-width cells with `gap` between them.
---@param row Frame
---@param gap number  Space between the cells.
---@return Frame left, Frame right
function Layout.SplitRow(row, gap)
    local halfGap = gap / 2
    local left = CreateFrame("Frame", nil, row)
    local right = CreateFrame("Frame", nil, row)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetPoint("RIGHT", row, "CENTER", -halfGap, 0)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetPoint("LEFT", row, "CENTER", halfGap, 0)
    return left, right
end

---@param index integer  1-based cell index, filled left to right, then top to bottom.
---@param columns integer
---@param cellWidth number
---@param cellHeight number
---@return number x, number y  Offset of the cell's top-left corner from the grid's top-left corner.
function Layout.GridCell(index, columns, cellWidth, cellHeight)
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    return column * cellWidth, -row * cellHeight
end

---@param count integer  Number of cells.
---@param columns integer
---@param cellHeight number
---@return number  Height of the grid; always at least one row.
function Layout.GridHeight(count, columns, cellHeight)
    return math.max(math.ceil(count / columns), 1) * cellHeight
end

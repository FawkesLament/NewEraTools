local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")

---Pure decisions for the tracker list: when the row order changed, and how to keep the
---viewport on the same content after a height change above it.
---@class AuraTrackerListPlan
local ListPlan = {}
Internals.ListPlan = ListPlan

---True when both arrays hold the same ids in the same order.
---@param left integer[]|nil
---@param right integer[]|nil
---@return boolean
function ListPlan.SameIds(left, right)
    if left == nil or right == nil or #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

---Scroll offset that keeps the same content pixel at the top of the viewport.
---A height change at `anchor` shifts content below it. The offset moves only when that
---whole region sits above the viewport. `rangeAfter` clamps to the new scroll range.
---@param scroll number
---@param anchor number
---@param oldHeight number
---@param newHeight number
---@param rangeAfter number|nil
---@return number
function ListPlan.AdjustScroll(scroll, anchor, oldHeight, newHeight, rangeAfter)
    local nextScroll = scroll
    if scroll >= anchor + oldHeight then
        nextScroll = scroll + (newHeight - oldHeight)
    end
    if nextScroll < 0 then
        nextScroll = 0
    end
    if type(rangeAfter) == "number" and nextScroll > rangeAfter then
        nextScroll = rangeAfter
    end
    return nextScroll
end

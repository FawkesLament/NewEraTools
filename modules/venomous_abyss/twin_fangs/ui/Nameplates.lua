local _, ns = ...
local Nameplate = ns.Api.Nameplate
local Unit = ns.Api.Unit
local SharedMedia = ns.SharedMedia
local TwinFangs = ns.Modules.Get("TwinFangs")
local InterruptBadge = ns.TwinFangsInterruptBadge
local Hint = ns.TwinFangsHintUI

local GAP = Hint.GAP
local PLACEHOLDER_NUMBER = Hint.PLACEHOLDER_NUMBER

local ANCHORS = {
    left = { point = "RIGHT", relativePoint = "LEFT", x = -GAP, y = 0 },
    right = { point = "LEFT", relativePoint = "RIGHT", x = GAP, y = 0 },
    top = { point = "BOTTOM", relativePoint = "TOP", x = 0, y = GAP },
    bottom = { point = "TOP", relativePoint = "BOTTOM", x = 0, y = -GAP },
}

local Nameplates = {}
ns.TwinFangsNameplates = Nameplates

local holder
local pool = {}
---@type table<string, TwinFangsInterruptBadge>
local active = {}
local unsubscribes = {}
local running = false

local function EnsureHolder()
    if holder then
        return
    end
    holder = CreateFrame("Frame")
    holder:Hide()
end

---@return TwinFangsInterruptBadge
local function Acquire()
    local badge = table.remove(pool)
    if badge then
        return badge
    end
    EnsureHolder()
    return InterruptBadge.Create(holder)
end

---@param badge TwinFangsInterruptBadge
local function Release(badge)
    badge:Hide()
    badge:ClearAllPoints()
    badge:SetParent(holder)
    pool[#pool + 1] = badge
end

---@param badge TwinFangsInterruptBadge
---@param nameplate Frame
local function Attach(badge, nameplate)
    local anchor = ANCHORS[TwinFangs:GetNameplateHintSide()] or ANCHORS.left
    badge:ApplyAppearance(
        TwinFangs:GetNameplateHintSize(),
        TwinFangs:GetNameplateHintOpacity(),
        SharedMedia.ResolveFontPath(TwinFangs:GetNameplateHintFont()) or STANDARD_TEXT_FONT,
        TwinFangs:GetNameplateHintFontSize(),
        TwinFangs:GetNameplateHintFontColor()
    )
    badge:SetParent(nameplate)
    badge:ClearAllPoints()
    badge:SetPoint(
        anchor.point,
        nameplate,
        anchor.relativePoint,
        anchor.x + TwinFangs:GetNameplateHintOffsetX(),
        anchor.y + TwinFangs:GetNameplateHintOffsetY()
    )
    badge:Show()
end

---@param unit string
---@return boolean
local function IsEnemy(unit)
    return Unit.CanPlayerAttack(unit) == true
end

---@param unit string
local function HideForUnit(unit)
    local badge = active[unit]
    if not badge then
        return
    end
    active[unit] = nil
    Release(badge)
end

---@param unit string
---@param frame Frame
local function ShowForUnit(unit, frame)
    if not IsEnemy(unit) then
        HideForUnit(unit)
        return
    end
    local badge = active[unit]
    if not badge then
        badge = Acquire()
        active[unit] = badge
    end
    badge:SetNumber(PLACEHOLDER_NUMBER)
    Attach(badge, frame)
end

local function Stop()
    for i = #unsubscribes, 1, -1 do
        unsubscribes[i]()
        unsubscribes[i] = nil
    end
    local units = {}
    for unit in pairs(active) do
        units[#units + 1] = unit
    end
    for i = 1, #units do
        HideForUnit(units[i])
    end
end

local function Start()
    EnsureHolder()
    unsubscribes[#unsubscribes + 1] = Nameplate.OnAdded(ShowForUnit)
    unsubscribes[#unsubscribes + 1] = Nameplate.OnRemoved(HideForUnit)
    Nameplate.ForEachVisible(ShowForUnit)
end

---Attaches badges to visible Blizzard nameplates while `enabled`, and hides them otherwise.
---@param enabled boolean
function Nameplates.SetActive(enabled)
    enabled = enabled == true
    if running == enabled then
        return
    end
    running = enabled
    if enabled then
        Start()
    else
        Stop()
    end
end

---Reapplies saved size, side, offsets, opacity, font, and color to every visible badge.
function Nameplates.Refresh()
    if not running then
        return
    end
    local units = {}
    for unit in pairs(active) do
        units[#units + 1] = unit
    end
    for i = 1, #units do
        local unit = units[i]
        local frame = Nameplate.GetFrame(unit)
        if frame then
            ShowForUnit(unit, frame)
        else
            HideForUnit(unit)
        end
    end
end

function TwinFangs:OnNameplateHintPreviewChanged()
    Nameplates.SetActive(self:IsNameplateHintPreviewing())
end

function TwinFangs:OnNameplateHintAppearanceChanged()
    Nameplates.Refresh()
end

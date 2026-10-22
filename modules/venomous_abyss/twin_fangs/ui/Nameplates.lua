local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local Nameplate = ns.Api.Nameplate
local Unit = ns.Api.Unit
local SharedMedia = ns.SharedMedia
local TwinFangs = ns.Modules.Get("TwinFangs")
local InterruptBadge = Internals.InterruptBadge
local Hint = Internals.HintUI

local GAP = Hint.GAP
local PLACEHOLDER_NUMBER = Hint.PLACEHOLDER_NUMBER

local ANCHORS = {
    left = { point = "RIGHT", relativePoint = "LEFT", x = -GAP, y = 0 },
    right = { point = "LEFT", relativePoint = "RIGHT", x = GAP, y = 0 },
    top = { point = "BOTTOM", relativePoint = "TOP", x = 0, y = GAP },
    bottom = { point = "TOP", relativePoint = "BOTTOM", x = 0, y = -GAP },
}

local Nameplates = {}
Internals.Nameplates = Nameplates

local holder
local pool = {}
---@type table<string, TwinFangsInterruptBadge>
local active = {}
---@type table<string, integer>
local numbers = {}
local previewUnsubscribes = {}
local liveUnsubscribes = {}
local previewing = false
local watchingLive = false

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
    numbers[unit] = nil
    local badge = active[unit]
    if not badge then
        return
    end
    active[unit] = nil
    Release(badge)
end

---@param unit string
---@param frame Frame
---@param number integer
local function ShowNumber(unit, frame, number)
    local badge = active[unit]
    if not badge then
        badge = Acquire()
        active[unit] = badge
    end
    numbers[unit] = number
    badge:SetNumber(number)
    Attach(badge, frame)
end

---@param unit string
---@param frame Frame
local function ShowPreviewForUnit(unit, frame)
    if not IsEnemy(unit) then
        HideForUnit(unit)
        return
    end
    ShowNumber(unit, frame, PLACEHOLDER_NUMBER)
end

local function StopUnsubscribes(list)
    for i = #list, 1, -1 do
        list[i]()
        list[i] = nil
    end
end

local function HideAll()
    local units = {}
    for unit in pairs(active) do
        units[#units + 1] = unit
    end
    for i = 1, #units do
        HideForUnit(units[i])
    end
end

local function StopLiveWatch()
    if not watchingLive then
        return
    end
    watchingLive = false
    StopUnsubscribes(liveUnsubscribes)
end

local function EnsureLiveWatch()
    if watchingLive or previewing then
        return
    end
    watchingLive = true
    liveUnsubscribes[#liveUnsubscribes + 1] = Nameplate.OnRemoved(HideForUnit)
end

local function StopPreview()
    StopUnsubscribes(previewUnsubscribes)
    HideAll()
end

local function StartPreview()
    StopLiveWatch()
    EnsureHolder()
    previewUnsubscribes[#previewUnsubscribes + 1] = Nameplate.OnAdded(ShowPreviewForUnit)
    previewUnsubscribes[#previewUnsubscribes + 1] = Nameplate.OnRemoved(HideForUnit)
    Nameplate.ForEachVisible(ShowPreviewForUnit)
end

---Attaches badges to visible Blizzard nameplates while `enabled`, and hides them otherwise.
---@param enabled boolean
function Nameplates.SetActive(enabled)
    enabled = enabled == true
    if previewing == enabled then
        return
    end
    previewing = enabled
    if enabled then
        StartPreview()
    else
        StopPreview()
    end
end

---Attaches a numbered badge to `unit`'s nameplate. No-op while a preview is showing.
---@param unit string
---@param number integer
function Nameplates.Show(unit, number)
    if previewing then
        return
    end
    local frame = Nameplate.GetFrame(unit)
    if not frame then
        return
    end
    EnsureLiveWatch()
    ShowNumber(unit, frame, number)
end

---Hides the badge on `unit`. No-op while a preview is showing.
---@param unit string
function Nameplates.Hide(unit)
    if previewing then
        return
    end
    HideForUnit(unit)
end

---Hides every live badge. No-op while a preview is showing.
function Nameplates.Clear()
    if previewing then
        return
    end
    HideAll()
    StopLiveWatch()
end

---Reapplies saved size, side, offsets, opacity, font, and color to every visible badge.
function Nameplates.Refresh()
    local units = {}
    for unit in pairs(active) do
        units[#units + 1] = unit
    end
    for i = 1, #units do
        local unit = units[i]
        local frame = Nameplate.GetFrame(unit)
        if not frame then
            HideForUnit(unit)
        elseif previewing then
            ShowPreviewForUnit(unit, frame)
        else
            ShowNumber(unit, frame, numbers[unit] or PLACEHOLDER_NUMBER)
        end
    end
end

function TwinFangs:OnNameplateHintShow(unit, number)
    Nameplates.Show(unit, number)
end

function TwinFangs:OnNameplateHintHide(unit)
    Nameplates.Hide(unit)
end

function TwinFangs:OnNameplateHintCleared()
    Nameplates.Clear()
end

function TwinFangs:OnNameplateHintPreviewChanged()
    Nameplates.SetActive(self:IsNameplateHintPreviewing())
    if not self:IsNameplateHintPreviewing() then
        self:ReplayNameplateHints()
    end
end

function TwinFangs:OnNameplateHintAppearanceChanged()
    Nameplates.Refresh()
end

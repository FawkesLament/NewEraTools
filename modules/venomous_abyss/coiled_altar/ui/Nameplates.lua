local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Nameplate = ns.Api.Nameplate
local Player = ns.Api.Player
local Unit = ns.Api.Unit
local CoiledAltar = ns.Modules.Get("CoiledAltar")
local InterruptIndicator = ns.InterruptIndicator

-- Preview-only sequence. Live encounter logic will supply real assignments later.
local PLACEHOLDER_NUMBER = 24
local PREVIEW_SCHEMES = {
    InterruptIndicator.SCHEME_GOLD,
    InterruptIndicator.SCHEME_PALE_GREEN,
}

local Nameplates = {}
Internals.Nameplates = Nameplates

local holder
local pool = {}
---@type table<string, InterruptIndicator>
local active = {}
---@type table<string, { number: integer, name: string, classFile: string|nil }>
local assignments = {}
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

---@return InterruptIndicator
local function Acquire()
    local indicator = table.remove(pool)
    if indicator then
        return indicator
    end
    EnsureHolder()
    return InterruptIndicator.Create(holder)
end

---@param indicator InterruptIndicator
local function Release(indicator)
    indicator:Hide()
    indicator:ClearAllPoints()
    indicator:SetParent(holder)
    pool[#pool + 1] = indicator
end

---@param indicator InterruptIndicator
---@param nameplate Frame
---@param number integer
---@param playerName string
---@param classFile string|nil
local function Attach(indicator, nameplate, number, playerName, classFile)
    indicator:Attach(nameplate)
    indicator:SetScale(CoiledAltar:GetNameplateHintScale())
    indicator:SetNumberFontSize(CoiledAltar:GetNameplateHintNumberFontSize())
    indicator:SetNameFontSize(CoiledAltar:GetNameplateHintNameFontSize())
    indicator:SetOffset(CoiledAltar:GetNameplateHintOffsetX(), CoiledAltar:GetNameplateHintOffsetY())
    indicator:SetSide(CoiledAltar:GetNameplateHintSide())
    indicator:SetAssignment(number, playerName, classFile)
end

---@param unit string
---@return boolean
local function IsEnemy(unit)
    return Unit.CanPlayerAttack(unit) == true
end

---@param unit string
local function HideForUnit(unit)
    assignments[unit] = nil
    local indicator = active[unit]
    if not indicator then
        return
    end
    active[unit] = nil
    Release(indicator)
end

---@param unit string
---@param frame Frame
---@param number integer
---@param playerName string
---@param classFile string|nil
---@param scheme string|nil
local function ShowAssignment(unit, frame, number, playerName, classFile, scheme)
    local indicator = active[unit]
    if not indicator then
        indicator = Acquire()
        active[unit] = indicator
        indicator:SetColorScheme(scheme or InterruptIndicator.SCHEME_GOLD)
    end
    assignments[unit] = { number = number, name = playerName, classFile = classFile }
    Attach(indicator, frame, number, playerName, classFile)
end

local function PreviewIdentity()
    return PLACEHOLDER_NUMBER, Unit.GetName("player") or "", Player.GetClassFile()
end

---@param unit string
---@param frame Frame
local function ShowPreviewForUnit(unit, frame)
    if not IsEnemy(unit) then
        HideForUnit(unit)
        return
    end
    local number, playerName, classFile = PreviewIdentity()
    local scheme
    if not active[unit] then
        scheme = PREVIEW_SCHEMES[math.random(#PREVIEW_SCHEMES)]
    end
    ShowAssignment(unit, frame, number, playerName, classFile, scheme)
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

---Attaches preview indicators to visible enemy nameplates while `enabled`.
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

---Attaches an assignment to `unit`'s nameplate. No-op while a preview is showing.
---@param unit string
---@param number integer
---@param playerName string
---@param classFile string|nil
function Nameplates.Show(unit, number, playerName, classFile)
    if previewing then
        return
    end
    local frame = Nameplate.GetFrame(unit)
    if not frame then
        return
    end
    EnsureLiveWatch()
    ShowAssignment(unit, frame, number, playerName, classFile)
end

---Hides the indicator on `unit`. No-op while a preview is showing.
---@param unit string
function Nameplates.Hide(unit)
    if previewing then
        return
    end
    HideForUnit(unit)
end

---Hides every live indicator. No-op while a preview is showing.
function Nameplates.Clear()
    if previewing then
        return
    end
    HideAll()
    StopLiveWatch()
end

---Reapplies saved scale, font sizes, side, and offsets to every visible indicator.
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
            local assignment = assignments[unit]
            if assignment then
                ShowAssignment(unit, frame, assignment.number, assignment.name, assignment.classFile)
            else
                HideForUnit(unit)
            end
        end
    end
end

function CoiledAltar:OnNameplateHintShow(unit, number, playerName, classFile)
    Nameplates.Show(unit, number, playerName, classFile)
end

function CoiledAltar:OnNameplateHintHide(unit)
    Nameplates.Hide(unit)
end

function CoiledAltar:OnNameplateHintCleared()
    Nameplates.Clear()
end

function CoiledAltar:OnNameplateHintPreviewChanged()
    Nameplates.SetActive(self:IsNameplateHintPreviewing())
end

function CoiledAltar:OnNameplateHintAppearanceChanged()
    Nameplates.Refresh()
end

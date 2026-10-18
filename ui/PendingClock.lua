local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local Widgets = ns.Widgets

local Colors = Assets.Colors

-- Same size as the aura-tracker pending mark. Sits in the gap after a setting label.
local CLOCK_SIZE = 10

local PendingClock = {}
ns.PendingClock = PendingClock

---@class PendingClockFrame: Frame
---@field pending boolean

local queue = {}
local listening = false

local function Flush()
    local batch = queue
    queue = {}
    local callbacks = {}
    for _, item in ipairs(batch) do
        item.apply()
        if item.onFlushed then
            callbacks[item.onFlushed] = true
        end
    end
    for callback in pairs(callbacks) do
        callback()
    end
end

local function EnsureListener()
    if listening then
        return
    end
    listening = true
    Combat.OnLeave(Flush)
end

---Small clock just to the right of `label`. Hidden until a change is deferred.
---@param label FontString
---@param tooltip string|nil  Defaults to the shared combat-pending sentence.
---@return PendingClockFrame
function PendingClock.Attach(label, tooltip)
    local clock = CreateFrame("Frame", nil, label:GetParent()) --[[@as PendingClockFrame]]
    clock:SetSize(CLOCK_SIZE, CLOCK_SIZE)
    clock:SetPoint("LEFT", label, "RIGHT", 1, 0)
    clock:EnableMouse(true)
    local icon = clock:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas(Assets.Icons.CLOCK)
    local muted = Colors.TEXT_MUTED
    icon:SetVertexColor(muted.r, muted.g, muted.b, 1)
    Widgets.AttachTooltip(clock, "ANCHOR_RIGHT", function(tip)
        tip:SetText(tooltip or L.SETTINGS_PENDING_COMBAT)
    end)
    clock:Hide()
    return clock
end

---@param clock PendingClockFrame
---@return boolean
function PendingClock.IsPending(clock)
    return clock.pending == true
end

---Runs `apply` now, or after combat when the client is in combat.
---While waiting, `clock` is shown. The setting stays editable; `apply` should read the saved value when it runs.
---`onFlushed` runs once per function after every deferred apply from this leave-combat.
---@param clock PendingClockFrame
---@param apply fun()
---@param onFlushed fun()|nil
---@return boolean deferred
function PendingClock.Defer(clock, apply, onFlushed)
    if not Combat.IsInCombat() and not Combat.IsLockedDown() then
        apply()
        return false
    end
    if clock.pending then
        return true
    end
    clock.pending = true
    clock:Show()
    queue[#queue + 1] = { apply = apply, onFlushed = onFlushed }
    EnsureListener()
    return true
end

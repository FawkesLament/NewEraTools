local _, ns = ...
local Assets = ns.Assets
local Combat = ns.Api.Combat
local Nameplate = ns.Api.Nameplate
local Internals = ns.Modules.Internals("InterruptClaim")
local InterruptClaim = ns.Modules.Get("InterruptClaim")

-- Midnight routes default nameplate targeting through a C++ HitTestFrame on the unit frame.
-- A plate-local SecureActionButton over Nameplate.GetHost intercepts the configured
-- modifier+button only. Plater hides Blizzard's UnitFrame and remaps hit-testing onto
-- its own host; GetHost already selects that frame.
-- The named NETFocus macro uses [@mouseover]: type=macro ignores the button `unit`,
-- and `/focus` would otherwise focus the current target. Mouse motion and clicks
-- propagate so the C++ hit-test still owns mouseover under Plater's non-unit host.
-- A global modifier override would also fire off nameplates and is not used.
-- Other mouse buttons pass through so unrelated clicks stay on the underlying host.

local UNIT_ATTR = "unit"

local NameplateClicks = {}
Internals.NameplateClicks = NameplateClicks

local holder
---@type table<Frame, Button>
local overlays = {}
---@type Button[]
local pool = {}

local function EnsureHolder()
    if holder then
        return
    end
    holder = CreateFrame("Frame")
    holder:Hide()
end

---@param button Button
local function ClearBinding(button)
    if button.claimTypeAttr then
        button:SetAttribute(button.claimTypeAttr, nil)
        button:SetAttribute(button.claimMacroAttr, nil)
        button:SetAttribute(button.claimFallbackAttr, nil)
    end
    button:SetAttribute(UNIT_ATTR, nil)
    button.claimModifier = nil
    button.claimMouseButton = nil
    button.claimTypeAttr = nil
    button.claimMacroAttr = nil
    button.claimFallbackAttr = nil
end

---@param button Button
---@param binding InterruptClaimClickBinding
local function ApplyClickRegistration(button, binding)
    if button.claimMouseButton == binding.mouseButton then
        return
    end
    button:RegisterForClicks(binding.click)
    button:SetAttribute("useOnKeyDown", true)
    local pass = binding.passThrough
    button:SetPassThroughButtons(pass[1], pass[2], pass[3], pass[4])
end

---@param button Button
local function ApplyOverlayBinding(button)
    local binding = InterruptClaim:GetClickBinding()
    local macroName = InterruptClaim.GetFocusMacroName()
    if button.claimModifier ~= binding.modifier or button.claimMouseButton ~= binding.mouseButton then
        if button.claimTypeAttr then
            button:SetAttribute(button.claimTypeAttr, nil)
            button:SetAttribute(button.claimMacroAttr, nil)
            button:SetAttribute(button.claimFallbackAttr, nil)
        end
        ApplyClickRegistration(button, binding)
        button.claimModifier = binding.modifier
        button.claimMouseButton = binding.mouseButton
        button.claimTypeAttr = binding.typeAttribute
        button.claimMacroAttr = binding.macroAttribute
        button.claimFallbackAttr = binding.fallbackAttribute
    end
    if button:GetAttribute(binding.fallbackAttribute) ~= binding.fallbackType then
        button:SetAttribute(binding.fallbackAttribute, binding.fallbackType)
    end
    if button:GetAttribute(binding.typeAttribute) ~= "macro" then
        button:SetAttribute(binding.typeAttribute, "macro")
    end
    if button:GetAttribute(binding.macroAttribute) ~= macroName then
        button:SetAttribute(binding.macroAttribute, macroName)
    end
end

---@return Button
local function CreateOverlay()
    EnsureHolder()
    local button = CreateFrame("Button", nil, holder, Assets.Templates.SECURE_ACTION_BUTTON)
    -- Down only: an up click would run the named macro a second time.
    button:EnableMouse(true)
    if button.SetPropagateMouseClicks then
        button:SetPropagateMouseClicks(true)
    end
    if button.SetPropagateMouseMotion then
        button:SetPropagateMouseMotion(true)
    end
    button:Hide()
    return button
end

---@return Button|nil
local function Acquire()
    if Combat.IsLockedDown() then
        return nil
    end
    local button = table.remove(pool)
    if button then
        return button
    end
    return CreateOverlay()
end

---@param button Button
local function Release(button)
    ClearBinding(button)
    button:Hide()
    button:ClearAllPoints()
    button:SetParent(holder)
    pool[#pool + 1] = button
end

---@param frame Frame
local function Detach(frame)
    local button = overlays[frame]
    if not button then
        return
    end
    overlays[frame] = nil
    Release(button)
end

---@param frame Frame
local function Attach(frame)
    if Nameplate.IsForbidden(frame) then
        Detach(frame)
        return
    end
    local host = Nameplate.GetHost(frame)
    if not host or Nameplate.IsForbidden(host) then
        Detach(frame)
        return
    end
    local button = overlays[frame]
    if not button then
        button = Acquire()
        if not button then
            return
        end
        overlays[frame] = button
    end
    button:SetParent(host)
    button:SetAllPoints(host)
    if host.GetFrameLevel then
        button:SetFrameLevel(host:GetFrameLevel() + 10)
    end
    -- Named macro only. Do not set macrotext; Midnight rejects that attribute.
    -- Unit may be secret; SetAttribute accepts it and comparisons here would throw.
    button:SetAttribute(UNIT_ATTR, Nameplate.GetUnit(frame))
    ApplyOverlayBinding(button)
    button:Show()
end

function NameplateClicks.ApplyAll()
    if Combat.IsLockedDown() then
        return
    end
    if not InterruptClaim:ShouldBindNameplateClicks() then
        for frame in pairs(overlays) do
            Detach(frame)
        end
        return
    end
    local keep = {}
    Nameplate.ForEachPlate(function(frame)
        if Nameplate.UnitCanAttack(frame) and not Nameplate.IsForbidden(frame) then
            keep[frame] = true
            Attach(frame)
        end
    end)
    for frame in pairs(overlays) do
        if not keep[frame] then
            Detach(frame)
        end
    end
end

---@param frame Frame|nil
function NameplateClicks.ApplyAdded(frame)
    if Combat.IsLockedDown() or type(frame) ~= "table" then
        return
    end
    if not InterruptClaim:ShouldBindNameplateClicks() then
        return
    end
    if Nameplate.UnitCanAttack(frame) and not Nameplate.IsForbidden(frame) then
        Attach(frame)
    else
        Detach(frame)
    end
end

function NameplateClicks.ApplyRemoved()
    if Combat.IsLockedDown() or not next(overlays) then
        return
    end
    local keep = {}
    Nameplate.ForEachPlate(function(frame)
        keep[frame] = true
    end)
    for frame in pairs(overlays) do
        if not keep[frame] then
            Detach(frame)
        end
    end
end

function InterruptClaim:ApplyNameplateClicks()
    NameplateClicks.ApplyAll()
end

function InterruptClaim:ApplyNameplateAdded(frame)
    NameplateClicks.ApplyAdded(frame)
end

function InterruptClaim:ApplyNameplateRemoved()
    NameplateClicks.ApplyRemoved()
end

function NameplateClicks.Start()
    InterruptClaim:ListenForNameplateClicks()
    InterruptClaim:SyncNameplateClicks()
end

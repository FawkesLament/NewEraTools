local _, ns = ...
local Assets = ns.Assets
local Combat = ns.Api.Combat
local WorldFrame = ns.Api.WorldFrame
local Internals = ns.Modules.Internals("InterruptClaim")
local InterruptClaim = ns.Modules.Get("InterruptClaim")

-- Covers WorldFrame so a modifier-click with no mouseover runs NETFocus, which
-- then `/clearfocus`. Nameplates and unit frames sit above this host and keep
-- their own overlays. Unmodified clicks propagate so 3D targeting still works.
-- Other mouse buttons pass through to WorldFrame (camera look, etc.).

local WorldClicks = {}
Internals.WorldClicks = WorldClicks

local holder
---@type Button|nil
local overlay

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
    end
    button.claimModifier = nil
    button.claimMouseButton = nil
    button.claimTypeAttr = nil
    button.claimMacroAttr = nil
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
        end
        ApplyClickRegistration(button, binding)
        button.claimModifier = binding.modifier
        button.claimMouseButton = binding.mouseButton
        button.claimTypeAttr = binding.typeAttribute
        button.claimMacroAttr = binding.macroAttribute
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

local function Release()
    if not overlay then
        return
    end
    ClearBinding(overlay)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetParent(holder)
end

function WorldClicks.Apply()
    if Combat.IsLockedDown() then
        return
    end
    if not InterruptClaim:ShouldBindWorldClicks() then
        Release()
        return
    end
    local host = WorldFrame.GetFrame()
    if not host then
        Release()
        return
    end
    if not overlay then
        overlay = CreateOverlay()
    end
    overlay:SetParent(host)
    overlay:SetAllPoints(host)
    if host.GetFrameLevel and overlay.SetFrameLevel then
        overlay:SetFrameLevel(host:GetFrameLevel() + 1)
    end
    ApplyOverlayBinding(overlay)
    overlay:Show()
end

function InterruptClaim:ApplyWorldClicks()
    WorldClicks.Apply()
end

function WorldClicks.Start()
    WorldClicks.Apply()
end

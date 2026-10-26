local _, ns = ...
local Combat = ns.Api.Combat
local TargetFrame = ns.Api.TargetFrame
local Internals = ns.Modules.Internals("InterruptClaim")
local InterruptClaim = ns.Modules.Get("InterruptClaim")

-- TargetFrame (Blizzard or EllesmereUI) is a SecureUnitButton (*type1 = target).
-- The configured modifier+button uses that pair on this frame only; it is not a
-- global override and does not use an overlay or macrotext.

local TargetFrameClicks = {}
Internals.TargetFrameClicks = TargetFrameClicks

---@type table<Frame, { values: table<string, any>, captured: table<string, boolean> }>
local savedByFrame = {}
---@type Frame|nil
local boundFrame
---@type string|nil
local boundTypeAttr
---@type string|nil
local boundMacroAttr

---@param frame Frame
---@param typeAttr string
---@param macroAttr string
local function Snapshot(frame, typeAttr, macroAttr)
    local saved = savedByFrame[frame]
    if not saved then
        saved = { values = {}, captured = {} }
        savedByFrame[frame] = saved
    end
    if not saved.captured[typeAttr] then
        saved.values[typeAttr] = frame:GetAttribute(typeAttr)
        saved.captured[typeAttr] = true
    end
    if not saved.captured[macroAttr] then
        saved.values[macroAttr] = frame:GetAttribute(macroAttr)
        saved.captured[macroAttr] = true
    end
end

---@param frame Frame
---@param typeAttr string
---@param typeValue any
---@param macroAttr string
---@param macroValue any
---@return boolean
local function HasAttributes(frame, typeAttr, typeValue, macroAttr, macroValue)
    return frame:GetAttribute(typeAttr) == typeValue and frame:GetAttribute(macroAttr) == macroValue
end

---@param frame Frame
---@param typeAttr string
---@param macroAttr string
local function RestoreAttrs(frame, typeAttr, macroAttr)
    local saved = savedByFrame[frame]
    local typeValue = saved and saved.captured[typeAttr] and saved.values[typeAttr] or nil
    local macroValue = saved and saved.captured[macroAttr] and saved.values[macroAttr] or nil
    if HasAttributes(frame, typeAttr, typeValue, macroAttr, macroValue) then
        return
    end
    frame:SetAttribute(typeAttr, typeValue)
    frame:SetAttribute(macroAttr, macroValue)
end

---@param frame Frame
local function Restore(frame)
    if not boundTypeAttr or not boundMacroAttr then
        if boundFrame == frame then
            boundFrame = nil
        end
        return
    end
    RestoreAttrs(frame, boundTypeAttr, boundMacroAttr)
    if boundFrame == frame then
        boundFrame = nil
        boundTypeAttr = nil
        boundMacroAttr = nil
    end
end

---@param frame Frame
local function Bind(frame)
    local binding = InterruptClaim:GetClickBinding()
    local typeAttr = binding.typeAttribute
    local macroAttr = binding.macroAttribute
    if boundFrame and (boundFrame ~= frame or boundTypeAttr ~= typeAttr or boundMacroAttr ~= macroAttr) then
        Restore(boundFrame)
    end
    Snapshot(frame, typeAttr, macroAttr)
    local macroName = InterruptClaim.GetFocusMacroName()
    if not HasAttributes(frame, typeAttr, "macro", macroAttr, macroName) then
        frame:SetAttribute(typeAttr, "macro")
        frame:SetAttribute(macroAttr, macroName)
    end
    boundFrame = frame
    boundTypeAttr = typeAttr
    boundMacroAttr = macroAttr
end

function TargetFrameClicks.Apply()
    if Combat.IsLockedDown() then
        return
    end
    local frame = TargetFrame.GetFrame()
    if boundFrame and boundFrame ~= frame then
        Restore(boundFrame)
    end
    if boundFrame and not InterruptClaim:ShouldBindTargetFrameClicks() then
        Restore(boundFrame)
    end
    if not frame then
        return
    end
    if InterruptClaim:ShouldBindTargetFrameClicks() then
        Bind(frame)
    elseif boundFrame == frame then
        Restore(frame)
    end
end

function InterruptClaim:ApplyTargetFrameClicks()
    TargetFrameClicks.Apply()
end

function TargetFrameClicks.Start()
    TargetFrameClicks.Apply()
end

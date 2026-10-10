local _, ns = ...
local Combat = ns.Api.Combat
local Timer = ns.Api.Timer

-- Same range as the main panel and Sszorak map scale controls.
local SCALE_MIN = 0.8
local SCALE_MAX = 1.5
local SCALE_STEP = 0.05

---@alias CombatTimerFormat "MMSS"|"SECONDS"

local FORMAT_MMSS = "MMSS"
local FORMAT_SECONDS = "SECONDS"

---Where the timer window sits, as an anchor on the screen.
---@class CombatTimerPosition
---@field point string  e.g. "CENTER".
---@field relativePoint string
---@field x number
---@field y number

---@class CombatTimer: Module
---@field OnEnabledChanged fun(self: CombatTimer)|nil  Defined by the UI file; called when the feature toggles.
---@field OnCombatChanged fun(self: CombatTimer)|nil  Defined by the UI file; called when combat starts or ends.
local CombatTimer = ns.Modules.New("CombatTimer", {
    defaults = {
        -- When true, the combat timer window is shown.
        enabled = false,
        -- Scale of the floating timer window.
        scale = 1,
        ---@type CombatTimerFormat
        format = FORMAT_MMSS,
        ---@type CombatTimerPosition
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
    },
})

CombatTimer.SCALE_MIN = SCALE_MIN
CombatTimer.SCALE_MAX = SCALE_MAX
CombatTimer.SCALE_STEP = SCALE_STEP
CombatTimer.FORMAT_MMSS = FORMAT_MMSS
CombatTimer.FORMAT_SECONDS = FORMAT_SECONDS

---@type CombatTimerFormat[]
CombatTimer.FORMATS = { FORMAT_MMSS, FORMAT_SECONDS }

-- Session-only: GetTime() when the current combat started; nil while out of combat.
local combatStart = nil
-- Duration of the most recent fight; shown after combat until the next pull.
local lastElapsed = 0

---@param position CombatTimerPosition
local function IsValidPosition(position)
    return type(position) == "table"
        and type(position.point) == "string"
        and type(position.relativePoint) == "string"
        and type(position.x) == "number"
        and type(position.y) == "number"
end

local function NotifyCombatChanged()
    if CombatTimer.OnCombatChanged then
        CombatTimer:OnCombatChanged()
    end
end

local function SetCombatStart(startTime)
    if combatStart == startTime then
        return
    end
    combatStart = startTime
    NotifyCombatChanged()
end

---@return boolean
function CombatTimer:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function CombatTimer:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    if self.OnEnabledChanged then
        self:OnEnabledChanged()
    end
end

local function ClampScale(scale)
    local rounded = math.floor(scale / SCALE_STEP + 0.5) * SCALE_STEP
    return math.min(math.max(rounded, SCALE_MIN), SCALE_MAX)
end

---@return number
function CombatTimer:GetScale()
    return ClampScale(self.db.scale)
end

---@param scale number
function CombatTimer:SetScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.scale = ClampScale(scale)
end

local function IsKnownFormat(format)
    for _, known in ipairs(CombatTimer.FORMATS) do
        if known == format then
            return true
        end
    end
    return false
end

---@return CombatTimerFormat
function CombatTimer:GetFormat()
    local format = self.db.format
    return IsKnownFormat(format) and format or FORMAT_MMSS
end

---@param format CombatTimerFormat
function CombatTimer:SetFormat(format)
    assert(IsKnownFormat(format), "Unknown format: " .. tostring(format))
    self.db.format = format
end

---@return CombatTimerPosition
function CombatTimer:GetPosition()
    return self.db.position
end

---@param position CombatTimerPosition
function CombatTimer:SetPosition(position)
    assert(IsValidPosition(position), "Bad window position")
    local saved = self.db.position
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return boolean
function CombatTimer:IsInCombat()
    return combatStart ~= nil
end

---Elapsed seconds of the current combat, or 0 when not in combat.
---@return number
function CombatTimer:GetElapsed()
    if not combatStart then
        return 0
    end
    return Timer.GetTime() - combatStart
end

---Seconds to show on the window: live elapsed in combat, otherwise the last fight's duration.
---@return number
function CombatTimer:GetDisplayElapsed()
    if combatStart then
        return Timer.GetTime() - combatStart
    end
    return lastElapsed
end

---Formats elapsed combat time using the saved format setting.
---@param seconds number
---@return string
function CombatTimer:FormatElapsed(seconds)
    local total = math.max(0, math.floor(seconds))
    if self:GetFormat() == FORMAT_SECONDS then
        return total .. " s"
    end
    return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

---Starts watching combat enter/leave. Called from OnEnable.
function CombatTimer:ListenForCombat()
    Combat.OnEnter(function()
        SetCombatStart(Timer.GetTime())
    end)
    Combat.OnLeave(function()
        if combatStart then
            lastElapsed = Timer.GetTime() - combatStart
        end
        SetCombatStart(nil)
    end)
    -- Already fighting when the addon loads or the listener starts.
    if Combat.IsInCombat() then
        SetCombatStart(Timer.GetTime())
    end
end

function CombatTimer:OnInit()
    self.db.scale = ClampScale(self.db.scale)
    self.db.format = self:GetFormat()
end

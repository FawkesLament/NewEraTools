local _, ns = ...
local Combat = ns.Api.Combat
local Group = ns.Api.Group
local Position = ns.Position
local Util = ns.Util

-- Same range as the combat timer window.
local SCALE_MIN = 0.8
local SCALE_MAX = 1.5
local SCALE_STEP = 0.05

---@alias RLToolbarAction "readyCheck"|"countdown5"|"countdown10"|"countdown15"|"cancelCountdown"

local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 }

local ACTIONS = {
    readyCheck = true,
    countdown5 = true,
    countdown10 = true,
    countdown15 = true,
    cancelCountdown = true,
}

local COUNTDOWN_SECONDS = {
    countdown5 = 5,
    countdown10 = 10,
    countdown15 = 15,
}

---@class RLToolbar: Module
---@field OnVisibilityChanged fun(self: RLToolbar)|nil  Defined by the UI file; show/hide the toolbar.
---@field OnLayoutChanged fun(self: RLToolbar)|nil  Defined by the UI file; scale or optional buttons changed.
---@field OnAction fun(self: RLToolbar, action: RLToolbarAction)|nil  After a live action is sent.
local RLToolbar = ns.Modules.New("RLToolbar", {
    defaults = {
        -- When true, the raid leader toolbar may be shown.
        enabled = false,
        scale = 1,
        -- Optional countdown buttons; ready check, 10s, and cancel stay visible.
        showCountdown5 = true,
        showCountdown15 = true,
        ---@type FloatingWindowPosition
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 },
    },
})

RLToolbar.SCALE_MIN = SCALE_MIN
RLToolbar.SCALE_MAX = SCALE_MAX
RLToolbar.SCALE_STEP = SCALE_STEP

RLToolbar.ACTIONS = {
    "readyCheck",
    "countdown5",
    "countdown10",
    "countdown15",
    "cancelCountdown",
}

local listening = false

local function NotifyVisibilityChanged()
    if RLToolbar.OnVisibilityChanged then
        RLToolbar:OnVisibilityChanged()
    end
end

---@return boolean
function RLToolbar:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function RLToolbar:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    NotifyVisibilityChanged()
end

---@return boolean  Whether the player leads the current raid.
function RLToolbar:IsLeader()
    return Group.IsPlayerRaidLeader()
end

---Visible when the feature is on, the player is raid leader, and combat has not started.
---`previewing` is layout-edit preview: leadership is ignored, combat still hides the bar.
---@param previewing boolean|nil
---@return boolean
function RLToolbar:ShouldShow(previewing)
    if not self:IsEnabled() then
        return false
    end
    if Combat.IsInCombat() then
        return false
    end
    if previewing then
        return true
    end
    return self:IsLeader()
end

---@return number
function RLToolbar:GetScale()
    return Util.Snap(self.db.scale, SCALE_MIN, SCALE_MAX, SCALE_STEP)
end

---@param scale number
function RLToolbar:SetScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.scale = Util.Snap(scale, SCALE_MIN, SCALE_MAX, SCALE_STEP)
end

---@return boolean
function RLToolbar:IsCountdown5Shown()
    return self.db.showCountdown5 ~= false
end

---@param shown boolean
function RLToolbar:SetCountdown5Shown(shown)
    shown = shown == true
    if self.db.showCountdown5 == shown then
        return
    end
    self.db.showCountdown5 = shown
    if self.OnLayoutChanged then
        self:OnLayoutChanged()
    end
end

---@return boolean
function RLToolbar:IsCountdown15Shown()
    return self.db.showCountdown15 ~= false
end

---@param shown boolean
function RLToolbar:SetCountdown15Shown(shown)
    shown = shown == true
    if self.db.showCountdown15 == shown then
        return
    end
    self.db.showCountdown15 = shown
    if self.OnLayoutChanged then
        self:OnLayoutChanged()
    end
end

---Ready check, 10s, and cancel are always on the bar; 5s and 15s follow their toggles.
---@param action RLToolbarAction
---@return boolean
function RLToolbar:IsButtonShown(action)
    if action == "countdown5" then
        return self:IsCountdown5Shown()
    end
    if action == "countdown15" then
        return self:IsCountdown15Shown()
    end
    return ACTIONS[action] == true
end

---@return FloatingWindowPosition
function RLToolbar:GetPosition()
    return self.db.position
end

---@param position FloatingWindowPosition
function RLToolbar:SetPosition(position)
    assert(Position.IsValid(position), "Bad toolbar position")
    local saved = self.db.position
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return FloatingWindowPosition
function RLToolbar:GetDefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

---Sends the matching ready-check or countdown command when the toolbar is live.
---@param action RLToolbarAction
function RLToolbar:RunAction(action)
    assert(ACTIONS[action], "Unknown toolbar action: " .. tostring(action))
    if not self:ShouldShow() then
        return
    end
    if action == "readyCheck" then
        Group.DoReadyCheck()
    elseif action == "cancelCountdown" then
        Group.CancelCountdown()
    else
        Group.DoCountdown(COUNTDOWN_SECONDS[action])
    end
    if self.OnAction then
        self:OnAction(action)
    end
end

function RLToolbar:OnInit()
    self.db.scale = Util.Snap(self.db.scale, SCALE_MIN, SCALE_MAX, SCALE_STEP)
end

---Starts watching leadership and combat. Called from OnEnable.
function RLToolbar:ListenForVisibility()
    if listening then
        return
    end
    listening = true
    Group.OnChanged(NotifyVisibilityChanged)
    Combat.OnEnter(NotifyVisibilityChanged)
    Combat.OnLeave(NotifyVisibilityChanged)
end

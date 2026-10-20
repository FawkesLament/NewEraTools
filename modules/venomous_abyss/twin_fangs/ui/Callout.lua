local _, ns = ...
local L = ns.L
local CalloutMessage = ns.CalloutMessage
local LayoutEditor = ns.LayoutEditor

local TwinFangs = ns.Modules.Get("TwinFangs")

-- Large enough for the callout font plus a short timer.
local CALLOUT_WIDTH = 420
local CALLOUT_HEIGHT = 72

local LAYOUT_ID = "TwinFangs:soak"

local Callout = {
    LAYOUT_ID = LAYOUT_ID,
}
ns.TwinFangsCalloutUI = Callout

local calloutWindow
local calloutLayoutRegistered = false
local layoutEditing = false

local function RegisterLayoutElement(frame)
    if calloutLayoutRegistered then
        return
    end
    calloutLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.TWIN_FANGS_SOAK_CALLOUT_TITLE,
        frame = frame,
        global = false,
        isEnabled = function()
            return TwinFangs:IsSoakReminderEnabled()
        end,
        getPosition = function()
            return TwinFangs:GetCalloutPosition()
        end,
        setPosition = function(position)
            TwinFangs:SetCalloutPosition(position)
        end,
        getDefaultPosition = function()
            return ns.CalloutPosition.DefaultPosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            local win = calloutWindow or Callout.Create()
            win:ShowPreview(L.TWIN_FANGS_SOAK_ENTER, TwinFangs.HIT1_LEAD, true)
        end,
        onEditEnd = function()
            layoutEditing = false
            Callout.Update()
        end,
    })
end

function Callout.Create()
    local frame = CalloutMessage.Create({
        name = ns.ADDON_NAME .. "TwinFangsSoakCallout",
        width = CALLOUT_WIDTH,
        height = CALLOUT_HEIGHT,
    })
    LayoutEditor.ApplyPosition(frame, TwinFangs:GetCalloutPosition())
    RegisterLayoutElement(frame)
    return frame
end

function Callout.Ensure()
    calloutWindow = calloutWindow or Callout.Create()
    return calloutWindow
end

---Paints the current soak reminder. The timer itself lives with encounter state, not this frame.
function Callout.Update()
    if layoutEditing then
        return
    end
    calloutWindow = calloutWindow or Callout.Create()
    LayoutEditor.ApplyPosition(calloutWindow, TwinFangs:GetCalloutPosition())
    local text = TwinFangs:GetDisplayedCallout()
    if text == nil then
        calloutWindow:Clear()
        return
    end
    local remaining = TwinFangs:GetCalloutRemainingSeconds()
    if remaining == nil then
        calloutWindow:Clear()
        return
    end
    calloutWindow:SetMessage(text, remaining, true)
end

function TwinFangs:OnCalloutChanged()
    Callout.Update()
end

local _, ns = ...
local L = ns.L
local Chat = ns.Api.Chat
local CalloutMessage = ns.CalloutMessage
local LayoutEditor = ns.LayoutEditor

local Sszorak = ns.Modules.Get("Sszorak")
local Window = ns.SszorakWindow

-- Large enough for the callout font plus a short raid-marker message.
local CALLOUT_WIDTH = 420
local CALLOUT_HEIGHT = 72

local LAYOUT_ID = "Sszorak:callout"

local Callout = {
    LAYOUT_ID = LAYOUT_ID,
}
ns.SszorakCalloutUI = Callout

local calloutWindow
local calloutLayoutRegistered = false

local function RegisterCalloutLayoutElement(frame)
    if calloutLayoutRegistered then
        return
    end
    calloutLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.SSZORAK_CALLOUT_TITLE,
        frame = frame,
        global = false,
        isEnabled = function()
            return Sszorak:IsMapEnabled()
        end,
        getPosition = function()
            return Sszorak:GetCalloutPosition()
        end,
        setPosition = function(position)
            Sszorak:SetCalloutPosition(position)
        end,
        getDefaultPosition = function()
            return ns.CalloutPosition.DefaultPosition()
        end,
        onEditBegin = function()
            Window.BeginLayoutEdit()
            local win = calloutWindow or Callout.Create()
            win:ShowPreview(
                Chat.ReplaceIconAndGroupExpressions(L.SSZORAK_CALLOUT_PREVIEW),
                Sszorak.CALLOUT_DURATION_ENCOUNTER,
                true
            )
        end,
        onEditEnd = function()
            Window.EndLayoutEdit()
        end,
    })
end

function Callout.Create()
    -- Plain host: text only (no backdrop). LayoutEditor moves this frame in Edit Position.
    local frame = CalloutMessage.Create({
        name = ns.ADDON_NAME .. "SszorakCallout",
        width = CALLOUT_WIDTH,
        height = CALLOUT_HEIGHT,
        wrap = L.SSZORAK_CALLOUT_WRAP,
    })
    LayoutEditor.ApplyPosition(frame, Sszorak:GetCalloutPosition())
    RegisterCalloutLayoutElement(frame)
    return frame
end

function Callout.Ensure()
    calloutWindow = calloutWindow or Callout.Create()
    return calloutWindow
end

---Paints the current guidance text. The timer itself lives with the guidance state, not this frame.
function Callout.Update()
    if Window.IsLayoutEditing() then
        return
    end
    calloutWindow = calloutWindow or Callout.Create()
    LayoutEditor.ApplyPosition(calloutWindow, Sszorak:GetCalloutPosition())
    local text = Sszorak:GetDisplayedCallout()
    if text == nil then
        calloutWindow:Clear()
        return
    end
    local remaining = Sszorak:GetCalloutRemainingSeconds()
    if remaining == nil then
        calloutWindow:Clear()
        return
    end
    -- Remaining seconds come from callout logic so edits mid-callout do not reset the countdown.
    calloutWindow:SetMessage(text, remaining, Sszorak:GetCalloutAppendTimer())
end

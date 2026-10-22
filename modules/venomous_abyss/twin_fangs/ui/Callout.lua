local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L

local TwinFangs = ns.Modules.Get("TwinFangs")

local Callout = ns.CalloutMessage.Bind({
    layoutId = "TwinFangs:soak",
    name = ns.ADDON_NAME .. "TwinFangsSoakCallout",
    label = L.TWIN_FANGS_SOAK_CALLOUT_TITLE,
    isEnabled = function()
        return TwinFangs:IsSoakReminderEnabled()
    end,
    getText = function()
        return TwinFangs:GetDisplayedCallout()
    end,
    getExpiresAt = function()
        return TwinFangs:GetCalloutExpiresAt()
    end,
    getPosition = function()
        return TwinFangs:GetCalloutPosition()
    end,
    setPosition = function(position)
        TwinFangs:SetCalloutPosition(position)
    end,
    getDefaultPosition = function()
        return ns.CalloutAnchor.DefaultPosition()
    end,
    previewText = L.TWIN_FANGS_SOAK_ENTER,
    previewDuration = TwinFangs.HIT1_LEAD,
})
Internals.CalloutUI = Callout

function TwinFangs:OnCalloutChanged()
    Callout.Update()
end

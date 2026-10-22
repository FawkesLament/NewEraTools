local _, ns = ...
local Internals = ns.Modules.Internals("Sszorak")
local L = ns.L
local Chat = ns.Api.Chat

local Sszorak = ns.Modules.Get("Sszorak")
local Window = Internals.Window

local Callout = ns.CalloutMessage.Bind({
    layoutId = "Sszorak:callout",
    name = ns.ADDON_NAME .. "SszorakCallout",
    label = L.SSZORAK_CALLOUT_TITLE,
    wrap = L.SSZORAK_CALLOUT_WRAP,
    isEnabled = function()
        return Sszorak:IsMapEnabled()
    end,
    getText = function()
        return Sszorak:GetDisplayedCallout()
    end,
    getExpiresAt = function()
        return Sszorak:GetCalloutExpiresAt()
    end,
    getAppendTimer = function()
        return Sszorak:GetCalloutAppendTimer()
    end,
    getPosition = function()
        return Sszorak:GetCalloutPosition()
    end,
    setPosition = function(position)
        Sszorak:SetCalloutPosition(position)
    end,
    getDefaultPosition = function()
        return ns.CalloutAnchor.DefaultPosition()
    end,
    previewText = function()
        return Chat.ReplaceIconAndGroupExpressions(L.SSZORAK_CALLOUT_PREVIEW)
    end,
    previewDuration = Sszorak.CALLOUT_DURATION_ENCOUNTER,
    onEditBegin = function()
        Window.BeginLayoutEdit()
    end,
    onEditEnd = function()
        Window.EndLayoutEdit()
    end,
})
Internals.CalloutUI = Callout

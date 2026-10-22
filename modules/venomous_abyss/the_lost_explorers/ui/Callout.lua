local _, ns = ...
local Internals = ns.Modules.Internals("TheLostExplorers")
local L = ns.L

local TheLostExplorers = ns.Modules.Get("TheLostExplorers")

local Callout = ns.CalloutMessage.Bind({
    layoutId = "TheLostExplorers:callout",
    name = ns.ADDON_NAME .. "TheLostExplorersCallout",
    label = L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_TITLE,
    isEnabled = function()
        return TheLostExplorers:IsEnabled()
    end,
    getText = function()
        return TheLostExplorers:GetDisplayedCallout()
    end,
    getExpiresAt = function()
        return TheLostExplorers:GetCalloutExpiresAt()
    end,
    getPosition = function()
        return TheLostExplorers:GetCalloutPosition()
    end,
    setPosition = function(position)
        TheLostExplorers:SetCalloutPosition(position)
    end,
    getDefaultPosition = function()
        return ns.CalloutAnchor.DefaultPosition()
    end,
    previewText = L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT,
    previewDuration = TheLostExplorers.CALLOUT_DURATION,
})
Internals.CalloutUI = Callout

function TheLostExplorers:OnCalloutChanged()
    Callout.Update()
end

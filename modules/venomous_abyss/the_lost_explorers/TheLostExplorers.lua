local _, ns = ...
local L = ns.L
local CalloutManager = ns.CalloutManager
local Combat = ns.Api.Combat
local Encounter = ns.Api.Encounter
local EncounterTimeline = ns.Api.EncounterTimeline
local Spell = ns.Api.Spell
local Timer = ns.Api.Timer

local CALLOUT_SOURCE = "TheLostExplorers"

local ENCOUNTER_ID = 3497 -- The Lost Explorers
local BOSS_UNIT = "boss2" -- Mor'zahi
-- Timeline bars that round to 60s are Mor'zahi's Command or Final Ascension (no stable spell ID filter).
local TIMELINE_DURATION = 60
-- Warn halfway through those ~60s bars: show at 30s remaining, for 30s.
local CALLOUT_DELAY = 30
local CALLOUT_DURATION = 30
local FEED_ORDER_SIZE = 3

-- Stable ids for the three interactable explorers (saved in feedOrder).
local BOSS_FIRST_MATE = "first_mate"
local BOSS_SCROLLAGE = "scrollage"
local BOSS_TRADER = "trader"
local FEED_BOSSES = { BOSS_FIRST_MATE, BOSS_SCROLLAGE, BOSS_TRADER }

---@class TheLostExplorers: Module
local TheLostExplorers = ns.Modules.New("TheLostExplorers", {
    defaults = {
        -- When true, the feed-fish assistant listens during this boss fight.
        enabled = false,
        -- Optional boss ids for slots 1–2; slot 3 is derived when both are set.
        -- Custom callout text applies only when the order is complete.
        ---@type string[]
        feedOrder = {},
    },
})

TheLostExplorers.ENCOUNTER_ID = ENCOUNTER_ID
TheLostExplorers.BOSS_UNIT = BOSS_UNIT
TheLostExplorers.TIMELINE_DURATION = TIMELINE_DURATION
TheLostExplorers.CALLOUT_DELAY = CALLOUT_DELAY
TheLostExplorers.CALLOUT_DURATION = CALLOUT_DURATION
TheLostExplorers.FEED_ORDER_SIZE = FEED_ORDER_SIZE
TheLostExplorers.BOSS_FIRST_MATE = BOSS_FIRST_MATE
TheLostExplorers.BOSS_SCROLLAGE = BOSS_SCROLLAGE
TheLostExplorers.BOSS_TRADER = BOSS_TRADER
TheLostExplorers.FEED_BOSSES = FEED_BOSSES

-- Session-only: castGUID of Mor'zahi's (boss2)'s channeling of Final Ascension.
-- The feed-fish callout is cancelled when this channeling ends.
local bossChannelGuid = nil
-- Session-only: matching ~60s timeline bars seen this pull; resets on each new encounter.
local matchedTimelineCount = 0
-- Cancels a pending callout delay without touching an active callout.
local scheduleToken = 0
---@type EncounterWhileIn|nil
local fight = nil

local function CurrentCallout()
    local current = CalloutManager.GetCurrent()
    if current and current.source == CALLOUT_SOURCE then
        return current
    end
    return nil
end

local function ClearActiveCallout()
    CalloutManager.ClearSource(CALLOUT_SOURCE)
end

local function CancelPendingSchedule()
    scheduleToken = scheduleToken + 1
end

---Drops pending and active feed-fish callouts and clears the tracked channel.
local function ResetFeedFishState()
    CancelPendingSchedule()
    ClearActiveCallout()
    bossChannelGuid = nil
end

---@param bossId string|nil
---@return boolean
local function IsKnownFeedBoss(bossId)
    return bossId == BOSS_FIRST_MATE or bossId == BOSS_SCROLLAGE or bossId == BOSS_TRADER
end

---@param bossId string
---@return string
local function FeedBossLabel(bossId)
    if bossId == BOSS_FIRST_MATE then
        return L.THE_LOST_EXPLORERS_BOSS_FIRST_MATE
    end
    if bossId == BOSS_SCROLLAGE then
        return L.THE_LOST_EXPLORERS_BOSS_SCROLLAGE
    end
    return L.THE_LOST_EXPLORERS_BOSS_TRADER
end

---Fills slot 3 with the unused boss when slots 1 and 2 are set; clears it otherwise.
local function ResolveThirdFeedOrderSlot()
    local order = TheLostExplorers.db.feedOrder
    local first = order[1]
    local second = order[2]
    if not IsKnownFeedBoss(first) or not IsKnownFeedBoss(second) or first == second then
        order[3] = nil
        return
    end
    for _, bossId in ipairs(FEED_BOSSES) do
        if bossId ~= first and bossId ~= second then
            order[3] = bossId
            return
        end
    end
    order[3] = nil
end

---Normalizes `feedOrder` to at most three known, unique boss ids (no gaps until the first unset).
---Slot 3 is derived from slots 1 and 2 when both are set.
local function NormalizeFeedOrder()
    local saved = TheLostExplorers.db.feedOrder
    if type(saved) ~= "table" then
        TheLostExplorers.db.feedOrder = {}
        return
    end
    local seen = {}
    local normalized = {}
    -- Only user-chosen slots (1–2) are read from saved data; slot 3 is resolved below.
    for index = 1, FEED_ORDER_SIZE - 1 do
        local bossId = saved[index]
        if not IsKnownFeedBoss(bossId) or seen[bossId] then
            break
        end
        seen[bossId] = true
        normalized[index] = bossId
    end
    for index = 1, FEED_ORDER_SIZE do
        saved[index] = normalized[index]
    end
    ResolveThirdFeedOrderSlot()
end

---@param feedIndex integer  1-based feed-fish interaction this pull (1st / 2nd / 3rd).
---@return string
local function ResolveCalloutText(feedIndex)
    if TheLostExplorers:HasCompleteFeedOrder() then
        local bossId = TheLostExplorers.db.feedOrder[feedIndex]
        if IsKnownFeedBoss(bossId) then
            return string.format(L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_ORDERED, FeedBossLabel(bossId))
        end
    end
    return L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT
end

---@param feedIndex integer
local function ShowCallout(feedIndex)
    CalloutManager.Show({
        source = CALLOUT_SOURCE,
        text = ResolveCalloutText(feedIndex),
        duration = CALLOUT_DURATION,
        appendTimer = true,
    })
end

---@param feedIndex integer
local function ScheduleCallout(feedIndex)
    scheduleToken = scheduleToken + 1
    local token = scheduleToken
    Timer.After(CALLOUT_DELAY, function()
        if token ~= scheduleToken then
            return
        end
        if not TheLostExplorers:IsEnabled() or not TheLostExplorers:IsInEncounter() then
            return
        end
        ShowCallout(feedIndex)
    end)
end

---Whether `duration` matches Mor'zahi's Command / Final Ascension timeline bars (~60s).
---@param duration number|nil
---@return boolean
local function IsTimelineDurationMatch(duration)
    if type(duration) ~= "number" then
        return false
    end
    return math.floor(duration + 0.5) == TIMELINE_DURATION
end

---@param eventInfo table  Active encounter-sourced bar; OnEventAdded already filtered source and state.
local function OnTimelineEventAdded(eventInfo)
    -- ~60s active bars ≈ Mor'zahi's Command or Final Ascension.
    if not IsTimelineDurationMatch(eventInfo.duration) then
        return
    end
    matchedTimelineCount = matchedTimelineCount + 1

    -- The 1st, 3rd, and 5th events are for Final Ascension (feed interactions 1–3).
    if matchedTimelineCount % 2 == 1 then
        ScheduleCallout((matchedTimelineCount + 1) / 2)
    end
end

-- boss2 channel start/stop are scoped to Mor'zahi; Final Ascension ending clears the feed-fish warn.
---@param _unitTarget string
---@param castGUID string
local function OnBossChannelStart(_unitTarget, castGUID)
    bossChannelGuid = castGUID
end

---@param _unitTarget string
---@param castGUID string
local function OnBossChannelStop(_unitTarget, castGUID)
    if bossChannelGuid == nil or castGUID ~= bossChannelGuid then
        return
    end
    bossChannelGuid = nil
    CancelPendingSchedule()
    ClearActiveCallout()
end

---@return boolean
function TheLostExplorers:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function TheLostExplorers:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    if not enabled then
        ResetFeedFishState()
    end
    if fight then
        fight:SetEnabled(enabled)
    end
end

---@return boolean
function TheLostExplorers:IsInEncounter()
    return fight ~= nil and fight:IsInside()
end

---@return boolean
function TheLostExplorers:IsListeningForFight()
    return fight ~= nil and fight:IsActive()
end

---@return any|nil
function TheLostExplorers:GetDisplayedCallout()
    local current = CurrentCallout()
    return current and current.text
end

---@return number|nil
function TheLostExplorers:GetCalloutExpiresAt()
    local current = CurrentCallout()
    return current and current.expiresAt
end

---@return CalloutAnchor
function TheLostExplorers:GetCalloutPosition()
    return ns.CalloutAnchor.GetPosition()
end

---@param position CalloutAnchor
function TheLostExplorers:SetCalloutPosition(position)
    ns.CalloutAnchor.SetPosition(position)
end

---@return string[]
function TheLostExplorers:GetFeedOrder()
    NormalizeFeedOrder()
    return self.db.feedOrder
end

---Whether all three feed slots are filled with known bosses.
---@return boolean
function TheLostExplorers:HasCompleteFeedOrder()
    NormalizeFeedOrder()
    local order = self.db.feedOrder
    for index = 1, FEED_ORDER_SIZE do
        if not IsKnownFeedBoss(order[index]) then
            return false
        end
    end
    return true
end

---@param slot integer  1..FEED_ORDER_SIZE
---@return string|nil
function TheLostExplorers:GetFeedOrderSlot(slot)
    assert(slot >= 1 and slot <= FEED_ORDER_SIZE, "Bad feed order slot")
    NormalizeFeedOrder()
    return self.db.feedOrder[slot]
end

---Sets slot 1 or 2; clears every later user slot. Pass nil/false to clear this slot and the rest.
---Slot 3 is always derived from slots 1 and 2 (remaining boss, or unset).
---Earlier slots must already be filled before a boss can be assigned here.
---@param slot integer  1..FEED_ORDER_SIZE-1
---@param bossId string|nil|false
function TheLostExplorers:SetFeedOrderSlot(slot, bossId)
    assert(slot >= 1 and slot <= FEED_ORDER_SIZE - 1, "Bad feed order slot")
    NormalizeFeedOrder()
    if bossId == false or bossId == nil or bossId == "" then
        bossId = nil
    else
        assert(IsKnownFeedBoss(bossId), "Unknown feed boss: " .. tostring(bossId))
        for earlier = 1, slot - 1 do
            local earlierBoss = self.db.feedOrder[earlier]
            if not IsKnownFeedBoss(earlierBoss) then
                return
            end
            if earlierBoss == bossId then
                return
            end
        end
    end
    self.db.feedOrder[slot] = bossId
    for later = slot + 1, FEED_ORDER_SIZE do
        self.db.feedOrder[later] = nil
    end
    ResolveThirdFeedOrderSlot()
end

function TheLostExplorers:ClearFeedOrder()
    local order = self.db.feedOrder
    if type(order) ~= "table" then
        self.db.feedOrder = {}
        return
    end
    for index = 1, FEED_ORDER_SIZE do
        order[index] = nil
    end
end

---@param bossId string
---@return string
function TheLostExplorers:GetFeedBossLabel(bossId)
    assert(IsKnownFeedBoss(bossId), "Unknown feed boss: " .. tostring(bossId))
    return FeedBossLabel(bossId)
end

---Starts watching this boss fight; timeline/channel listeners bind only while inside the pull.
---Called from OnEnable.
function TheLostExplorers:ListenForFeedFish()
    -- Reset before WhileIn's setup so a mid-fight toggle does not wipe the pull's match count.
    Encounter.OnStart(function(encounterID)
        if encounterID == ENCOUNTER_ID then
            matchedTimelineCount = 0
        end
    end)

    fight = Encounter.WhileIn(ENCOUNTER_ID, function()
        local unsubTimeline = EncounterTimeline.OnEventAdded(OnTimelineEventAdded)
        -- Mor'zahi (boss2) Final Ascension channel: cancel the feed-fish warn when it ends.
        local unsubChannelStart = Spell.OnUnitChannelStart(BOSS_UNIT, OnBossChannelStart)
        local unsubChannelStop = Spell.OnUnitChannelStop(BOSS_UNIT, OnBossChannelStop)
        return function()
            unsubTimeline()
            unsubChannelStart()
            unsubChannelStop()
            -- Pending work is encounter-scoped; an on-screen callout clears when combat ends.
            CancelPendingSchedule()
            bossChannelGuid = nil
        end
    end)
    fight:SetEnabled(self:IsEnabled())

    Combat.OnLeave(function()
        CancelPendingSchedule()
        ClearActiveCallout()
    end)
end

function TheLostExplorers:OnInit()
    NormalizeFeedOrder()
end

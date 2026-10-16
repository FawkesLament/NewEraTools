local _, ns = ...
local Util = ns.Util
local Schema = ns.AuraTrackerSchema

---@class AuraTracker: Module
---@field OnTrackerListChanged fun(self: AuraTracker)|nil  Add/remove; rebuild instance UIs.
---@field OnTrackerChanged fun(self: AuraTracker, trackerId: integer|nil)|nil  Enable/spell; nil = all.
---@field OnTrackingRefresh fun(self: AuraTracker)|nil  Live bar only; does not rebuild settings.
---@field OnAppearanceChanged fun(self: AuraTracker, trackerId: integer)|nil  Appearance-only; no frame recreate.
local AuraTracker = ns.Modules.New("AuraTracker", {
    defaults = {
        enabled = false,
        -- Module-level auto-hide; independent of per-tracker enablement / activation scope.
        hideDuringSkyriding = true,
        hideDuringPetBattles = true,
        hideDuringCinematics = true,
        nextTrackerId = 1,
        ---@type AuraTrackerInstance[]
        trackers = {},
    },
})

---@param trackerId integer|nil
local function NotifyTrackerChanged(trackerId)
    if AuraTracker.OnTrackerChanged then
        AuraTracker:OnTrackerChanged(trackerId)
    end
end

---@param trackerId integer
local function NotifyAppearanceChanged(trackerId)
    if AuraTracker.OnAppearanceChanged then
        AuraTracker:OnAppearanceChanged(trackerId)
    end
end

local function NotifyTrackerListChanged()
    if AuraTracker.OnTrackerListChanged then
        AuraTracker:OnTrackerListChanged()
    end
end

---@param trackers AuraTrackerInstance[]
---@param trackerId integer
---@return AuraTrackerInstance|nil
---@return integer|nil
local function FindTracker(trackers, trackerId)
    for index, tracker in ipairs(trackers) do
        if tracker.id == trackerId then
            return tracker, index
        end
    end
    return nil
end

---@param self AuraTracker
---@param trackerId integer
---@return AuraTrackerInstance
local function RequireTracker(self, trackerId)
    local tracker = FindTracker(self.db.trackers, trackerId)
    assert(tracker ~= nil, "Unknown tracker: " .. tostring(trackerId))
    return tracker
end

-- ---------------------------------------------------------------------------
-- Module enable
-- ---------------------------------------------------------------------------

---@return boolean
function AuraTracker:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function AuraTracker:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    -- Module toggle suppresses every instance without changing per-tracker enabled flags.
    NotifyTrackerChanged(nil)
end

-- ---------------------------------------------------------------------------
-- Global visibility (module-level auto-hide)
-- ---------------------------------------------------------------------------

---@param key "hideDuringSkyriding"|"hideDuringPetBattles"|"hideDuringCinematics"
---@param hide boolean
local function SetHideFlag(self, key, hide)
    hide = hide == true
    if self.db[key] == hide then
        return
    end
    self.db[key] = hide
    NotifyTrackerChanged(nil)
end

---@return boolean
function AuraTracker:GetHideDuringSkyriding()
    return self.db.hideDuringSkyriding ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringSkyriding(hide)
    SetHideFlag(self, "hideDuringSkyriding", hide)
end

---@return boolean
function AuraTracker:GetHideDuringPetBattles()
    return self.db.hideDuringPetBattles ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringPetBattles(hide)
    SetHideFlag(self, "hideDuringPetBattles", hide)
end

---@return boolean
function AuraTracker:GetHideDuringCinematics()
    return self.db.hideDuringCinematics ~= false
end

---@param hide boolean
function AuraTracker:SetHideDuringCinematics(hide)
    SetHideFlag(self, "hideDuringCinematics", hide)
end

-- ---------------------------------------------------------------------------
-- Tracker collection
-- ---------------------------------------------------------------------------

---@return integer[]
function AuraTracker:GetTrackerIds()
    local ids = {}
    for _, tracker in ipairs(self.db.trackers) do
        ids[#ids + 1] = tracker.id
    end
    return ids
end

---@param trackerId integer
---@return boolean
function AuraTracker:HasTracker(trackerId)
    return FindTracker(self.db.trackers, trackerId) ~= nil
end

---Creates a new tracker with defaults and a fresh stable id.
---@return integer trackerId
function AuraTracker:AddTracker()
    local id = math.floor(self.db.nextTrackerId or 1)
    if id < 1 then
        id = 1
    end
    self.db.nextTrackerId = id + 1

    local tracker = Schema.NewTracker()
    tracker.id = id
    local stackIndex = #self.db.trackers
    tracker.position.y = Schema.DEFAULT_POSITION_Y - Schema.POSITION_STACK_STEP * stackIndex
    ns.AuraTrackerSettings.Normalize(tracker)
    self.db.trackers[#self.db.trackers + 1] = tracker

    NotifyTrackerListChanged()
    NotifyTrackerChanged(id)
    return id
end

---@param trackerId integer
function AuraTracker:RemoveTracker(trackerId)
    local _, index = FindTracker(self.db.trackers, trackerId)
    assert(index ~= nil, "Unknown tracker: " .. tostring(trackerId))
    table.remove(self.db.trackers, index)
    NotifyTrackerListChanged()
    NotifyTrackerChanged(trackerId)
end

---Deep-copies a tracker (settings only), assigns a fresh id, and inserts it immediately after the source.
---@param trackerId integer
---@return integer trackerId
function AuraTracker:DuplicateTracker(trackerId)
    local source, index = FindTracker(self.db.trackers, trackerId)
    assert(index ~= nil and source ~= nil, "Unknown tracker: " .. tostring(trackerId))

    local id = math.floor(self.db.nextTrackerId or 1)
    if id < 1 then
        id = 1
    end
    self.db.nextTrackerId = id + 1

    local tracker = Util.DeepCopy(source)
    tracker.id = id
    ns.AuraTrackerSettings.Normalize(tracker)
    table.insert(self.db.trackers, index + 1, tracker)

    NotifyTrackerListChanged()
    NotifyTrackerChanged(id)
    return id
end

---@param trackerId integer
---@return boolean
function AuraTracker:IsTrackerEnabled(trackerId)
    return RequireTracker(self, trackerId).enabled == true
end

---@param trackerId integer
---@param enabled boolean
function AuraTracker:SetTrackerEnabled(trackerId, enabled)
    local tracker = RequireTracker(self, trackerId)
    enabled = enabled == true
    if tracker.enabled == enabled then
        return
    end
    tracker.enabled = enabled
    NotifyTrackerChanged(trackerId)
end

function AuraTracker:OnInit()
    if type(self.db.trackers) ~= "table" then
        self.db.trackers = {}
    end

    local maxId = 0
    local normalized = {}
    for _, tracker in ipairs(self.db.trackers) do
        if type(tracker) == "table" then
            if type(tracker.id) ~= "number" or tracker.id < 1 or tracker.id ~= math.floor(tracker.id) then
                local id = math.floor(self.db.nextTrackerId or (maxId + 1))
                if id < 1 then
                    id = 1
                end
                if id <= maxId then
                    id = maxId + 1
                end
                tracker.id = id
                self.db.nextTrackerId = id + 1
            end
            ns.AuraTrackerSettings.Normalize(tracker)
            if tracker.id > maxId then
                maxId = tracker.id
            end
            normalized[#normalized + 1] = tracker
        end
    end
    self.db.trackers = normalized

    local nextId = math.floor(self.db.nextTrackerId or 1)
    if nextId <= maxId then
        nextId = maxId + 1
    end
    self.db.nextTrackerId = nextId
end

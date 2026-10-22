local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Activity = ns.Api.Activity
local Aura = ns.Api.Aura
local Combat = ns.Api.Combat
local Instance = ns.Api.Instance
local Player = ns.Api.Player
local Unit = ns.Api.Unit
local Timer = ns.Api.Timer
local Activation = Internals.Activation
local Profile = Internals.Profile
local Schema = Internals.Schema

local AuraTracker = ns.Modules.Get("AuraTracker")

---@param trackerId integer|nil
local function NotifyTrackerChanged(trackerId)
    if AuraTracker.OnTrackerChanged then
        AuraTracker:OnTrackerChanged(trackerId)
    end
end

---Bar show/hide and unit identity. Settings UI is not involved.
local function NotifyTrackingRefresh()
    local started = Profile.Start()
    if AuraTracker.OnTrackingRefresh then
        AuraTracker:OnTrackingRefresh()
    end
    Profile.Stop("ui.trackingRefresh", started)
end

---@param trackers AuraTrackerInstance[]
---@param trackerId integer
---@return AuraTrackerInstance|nil
local function FindTracker(trackers, trackerId)
    for _, tracker in ipairs(trackers) do
        if tracker.id == trackerId then
            return tracker
        end
    end
    return nil
end

---Whether any enabled module-level auto-hide condition is currently active.
---Does not change per-tracker enablement or activation scope.
---@return boolean
function AuraTracker:ShouldHideAuraBars()
    return (self:GetHideDuringSkyriding() and Activity.IsSkyriding())
        or (self:GetHideDuringPetBattles() and Activity.IsInPetBattle())
        or (self:GetHideDuringCinematics() and Activity.IsInCinematic())
end

---Whether this tracker's unit and aura type are a combination the tracker implements.
---@param trackerId integer
---@return boolean
function AuraTracker:IsSourceSupported(trackerId)
    return Aura.IsSupportedSource(self:GetUnit(trackerId), self:GetAuraType(trackerId))
end

---Whether this tracker's activation scope matches the current player.
---@param trackerId integer
---@return boolean
function AuraTracker:IsActivationActive(trackerId)
    local tracker = FindTracker(self.db.trackers, trackerId)
    assert(tracker ~= nil, "Unknown tracker: " .. tostring(trackerId))
    return Activation.AppliesToPlayer(tracker, Player.GetActivationContext())
end

---First saved tracker that is enabled and whose activation matches the current player.
---@return integer|nil
function AuraTracker:GetFirstTrackerEnabledForCurrentPlayer()
    for _, trackerId in ipairs(self:GetTrackerIds()) do
        if self:IsTrackerEnabled(trackerId) and self:IsActivationActive(trackerId) then
            return trackerId
        end
    end
    return nil
end

---Whether settings say this tracker should be active.
---Independent of situational global auto-hide (`ShouldHideAuraBars`) and of whether the
---current target/focus can safely take a spell-ID filter (`CanDisplayAura`).
---@param trackerId integer
---@return boolean
function AuraTracker:ShouldTrack(trackerId)
    return self:IsEnabled()
        and self:IsTrackerEnabled(trackerId)
        and self:GetSpellId(trackerId) > 0
        and self:IsActivationActive(trackerId)
        and self:IsSourceSupported(trackerId)
end

---Whether the current unit can be spell-filtered. False for a missing or assistable
---target/focus, so the bar must not stay up and show every debuff.
---@param trackerId integer
---@return boolean
function AuraTracker:CanDisplayAura(trackerId)
    if not self:ShouldTrack(trackerId) then
        return false
    end
    return Aura.CanApplyIncludeSpellFilter(self:GetUnit(trackerId), self:GetAuraType(trackerId))
end

---Unit GUID while `CanDisplayAura` is true. Nil clears any aura previously shown for another unit.
---@param trackerId integer
---@return string|nil
function AuraTracker:GetDisplayedUnitGUID(trackerId)
    if not self:CanDisplayAura(trackerId) then
        return nil
    end
    return Unit.GetGUID(self:GetUnit(trackerId))
end

---True when an enabled tracker follows target or focus, so unit-token changes must refresh it.
---@return boolean
function AuraTracker:WatchesExternalUnit()
    if not self:IsEnabled() then
        return false
    end
    for _, tracker in ipairs(self.db.trackers) do
        if tracker.enabled and (tracker.unit == Schema.UNIT_TARGET or tracker.unit == Schema.UNIT_FOCUS) then
            return true
        end
    end
    return false
end

---Registers combat-leave so the UI can flush deferred AuraContainer updates.
function AuraTracker:ListenForCombat()
    Combat.OnLeave(function()
        local started = Profile.Start()
        NotifyTrackerChanged(nil)
        Profile.Stop("combatLeave", started)
    end)
end

---Refreshes tracking when specialization/role changes or becomes available after login/reload.
---Never rewrites saved scopes. Spec-scoped trackers often see nil specialization at ADDON_LOADED;
---PLAYER_ENTERING_WORLD (plus a same-frame defer) rebuilds containers once context is ready.
function AuraTracker:ListenForPlayerContext()
    Player.OnChanged(function()
        NotifyTrackerChanged(nil)
    end)
    Instance.OnEnteringWorld(function()
        NotifyTrackerChanged(nil)
        Timer.After(0, function()
            NotifyTrackerChanged(nil)
        end)
    end)
end

---Bumps the generation for one token so that bar rescans once.
---SetUnit ignores a GUID change behind the same token, and a secret GUID cannot be compared.
---@param event string
local function NoteExternalRetarget(event)
    if event == "PLAYER_TARGET_CHANGED" then
        AuraTracker.targetRescanSerial = (AuraTracker.targetRescanSerial or 0) + 1
    elseif event == "PLAYER_FOCUS_CHANGED" then
        AuraTracker.focusRescanSerial = (AuraTracker.focusRescanSerial or 0) + 1
    end
end

---Refreshes target/focus bars when that unit, or its assist relationship, changes.
---Several events in one frame share one refresh, plus one pass next frame when the event
---frame can still report the previous unit. This does not rebuild the settings UI.
---UNIT_AURA follows the token, so later aura changes on whoever is targeted still arrive.
---A swap does not: SetUnit compares the token string only, and the new unit's existing
---auras may never emit UNIT_AURA. Target and focus events bump separate serials so the
---bar reads the unit again next frame, when this frame can still report the previous one.
---The bar scans only if that read shows a new GUID, or the GUID cannot be compared.
---UNIT_FLAGS / UNIT_FACTION do not bump the serials.
function AuraTracker:ListenForUnitContext()
    local refreshPending = false
    local targetRetarget = false
    local focusRetarget = false
    Aura.OnUnitContextChanged(function(event, unit)
        local started = Profile.Start()
        Profile.Inc(Profile.EventKey(event, unit))
        if not AuraTracker:WatchesExternalUnit() then
            Profile.Stop("event.ignored", started)
            return
        end
        if event == "PLAYER_TARGET_CHANGED" and not targetRetarget then
            targetRetarget = true
            NoteExternalRetarget(event)
        elseif event == "PLAYER_FOCUS_CHANGED" and not focusRetarget then
            focusRetarget = true
            NoteExternalRetarget(event)
        end
        if refreshPending then
            Profile.Stop("event.handled", started)
            return
        end
        refreshPending = true
        NotifyTrackingRefresh()
        Timer.After(0, function()
            refreshPending = false
            local deferred = Profile.Start()
            if AuraTracker:WatchesExternalUnit() then
                if targetRetarget then
                    NoteExternalRetarget("PLAYER_TARGET_CHANGED")
                end
                if focusRetarget then
                    NoteExternalRetarget("PLAYER_FOCUS_CHANGED")
                end
                NotifyTrackingRefresh()
            end
            targetRetarget = false
            focusRetarget = false
            Profile.Stop("event.deferred", deferred)
        end)
        Profile.Stop("event.handled", started)
    end)
end

---Refreshes bar visibility when skyriding, pet battles, or cinematics change.
function AuraTracker:ListenForVisibilityContext()
    Activity.OnContextChanged(function()
        NotifyTrackerChanged(nil)
    end)
end

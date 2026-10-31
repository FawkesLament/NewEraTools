local _, ns = ...

---@class LazyEncounterUIOptions
---@field create fun(): any  Builds the UI instance. Called at most once.
---@field activate fun(instance: any)  Applies the inactive-to-active transition.
---@field deactivate fun(instance: any)  Applies the active-to-inactive transition.

---Create-once cache for expensive encounter UI. Callers own prewarming, encounter
---start/end, settings, and what activate/deactivate do; this only sequences those callbacks.
---@class LazyEncounterUI
---@field private create fun(): any
---@field private activateInstance fun(instance: any)
---@field private deactivateInstance fun(instance: any)
---@field private instance any
---@field private active boolean
local LazyEncounterUI = {}
LazyEncounterUI.__index = LazyEncounterUI
ns.LazyEncounterUI = LazyEncounterUI

---@param options LazyEncounterUIOptions
---@return LazyEncounterUI
function LazyEncounterUI.Create(options)
    return setmetatable({
        create = options.create,
        activateInstance = options.activate,
        deactivateInstance = options.deactivate,
        instance = nil,
        active = false,
    }, LazyEncounterUI)
end

function LazyEncounterUI:Prepare()
    if self.instance ~= nil then
        return
    end
    self.instance = self.create()
end

---@return boolean
function LazyEncounterUI:IsPrepared()
    return self.instance ~= nil
end

---@return boolean
function LazyEncounterUI:IsActive()
    return self.active == true
end

---@param active boolean
function LazyEncounterUI:SetActive(active)
    if active then
        self:Prepare()
        if self.active then
            return
        end
        self.active = true
        self.activateInstance(self.instance)
        return
    end
    if not self.active then
        return
    end
    self.active = false
    self.deactivateInstance(self.instance)
end

local _, ns = ...
local Combat = ns.Api.Combat
local Macro = ns.Api.Macro

local Sszorak = ns.Modules.Get("Sszorak")

-- Macro UI names are capped at 16 characters; prefix + edge digit stays within that.
local MACRO_NAME_PREFIX = "NewEraToolsSsz"

-- True when a marker change couldn't rewrite macros because of combat lockdown.
local macrosDirty = false
-- True when switching to commander couldn't create macros because of combat lockdown.
local macrosNeedCreate = false

local function RaidTargetIconPath(raidTarget)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. raidTarget
end

local function IsMarkableEdge(edge)
    return type(edge) == "number"
        and edge >= 1
        and edge <= Sszorak.ARENA_SIDES
        and edge % 1 == 0
        and edge ~= Sszorak.ENTRANCE_EDGE
        and edge ~= Sszorak.EXIT_EDGE
end

---Account-wide macro name for the callout bound to `edge`. At most 16 characters.
---@param edge integer
---@return string
function Sszorak:GetEdgeMacroName(edge)
    assert(IsMarkableEdge(edge), "Edge has no callout macro: " .. tostring(edge))
    return MACRO_NAME_PREFIX .. edge
end

---Macro body from the active callout mode (normal posts the opposite edge's raid target).
---@param edge integer
---@return string
function Sszorak:GetEdgeMacroBody(edge)
    assert(IsMarkableEdge(edge), "Edge has no callout macro: " .. tostring(edge))
    return self:GetActiveCalloutMode():GetEdgeMacroBody(edge, self.db.edgeMarkers)
end

---FileID for the macro icon: the marker on the triggering edge.
---CreateMacro/EditMacro need a FileID; the TargetingFrame path string does not render.
---@param edge integer
---@return number
function Sszorak:GetEdgeMacroIcon(edge)
    assert(IsMarkableEdge(edge), "Edge has no callout macro: " .. tostring(edge))
    local marker = assert(self.db.edgeMarkers[edge], "Missing edge marker")
    local raidTarget = assert(Sszorak.MARKER_RAID_TARGET[marker], "Unknown marker: " .. tostring(marker))
    return Macro.GetFileIDFromPath(RaidTargetIconPath(raidTarget))
end

---@param edge integer
---@return boolean
function Sszorak:HasEdgeMacro(edge)
    return Macro.GetIndexByName(self:GetEdgeMacroName(edge)) > 0
end

---True when every markable-edge callout macro already exists (queried live from the macro API).
---@return boolean
function Sszorak:HasAllEdgeMacros()
    for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
        if not self:HasEdgeMacro(edge) then
            return false
        end
    end
    return true
end

---@param edge integer
---@param createIfMissing boolean
---@return boolean  Whether a macro was written.
local function WriteEdgeMacro(self, edge, createIfMissing)
    local name = self:GetEdgeMacroName(edge)
    local icon = self:GetEdgeMacroIcon(edge)
    local body = self:GetEdgeMacroBody(edge)
    local index = Macro.GetIndexByName(name)
    if index > 0 then
        Macro.Edit(index, name, icon, body)
        return true
    end
    if createIfMissing then
        Macro.Create(name, icon, body)
        return true
    end
    return false
end

---Rewrites existing callout macros to match the current marker assignment.
---Defers until combat ends when lockdown blocks EditMacro.
---@return boolean  Whether any macro was updated immediately.
function Sszorak:SyncEdgeMacros()
    if Combat.IsLockedDown() then
        macrosDirty = true
        return false
    end
    macrosDirty = false
    local updated = false
    for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
        if WriteEdgeMacro(self, edge, false) then
            updated = true
        end
    end
    return updated
end

---Creates missing callout macros and refreshes existing ones. Blocked in combat.
---@return boolean ok
---@return "combat"|"failed"|nil reason
function Sszorak:CreateEdgeMacros()
    if Combat.IsLockedDown() then
        macrosNeedCreate = true
        return false, "combat"
    end
    macrosDirty = false
    macrosNeedCreate = false
    for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
        local ok = pcall(WriteEdgeMacro, self, edge, true)
        if not ok then
            return false, "failed"
        end
    end
    return true
end

---Applies deferred macro create/rewrite when combat lockdown ends. Called from OnEnable.
function Sszorak:ListenForMacroSync()
    Combat.OnLeave(function()
        if not Sszorak:IsRaidCommander() then
            macrosDirty = false
            macrosNeedCreate = false
            return
        end
        if macrosNeedCreate then
            Sszorak:CreateEdgeMacros()
        elseif macrosDirty then
            Sszorak:SyncEdgeMacros()
        end
    end)
end

Sszorak.BindMacroSync(function()
    Sszorak:SyncEdgeMacros()
end)

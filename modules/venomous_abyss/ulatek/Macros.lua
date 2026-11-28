-- Account-wide signal macros the commander places on the action bar.
local _, ns = ...
local Combat = ns.Api.Combat
local Macro = ns.Api.Macro

local Ulatek = ns.Modules.Get("Ulatek")

-- Macro UI names are capped at 16 characters; prefix + digit stays within that.
local MACRO_NAME_PREFIX = "NETUlatek"
local DEFAULT_ICON_PATH = "Interface\\Icons\\INV_Misc_QuestionMark"

local SIGNAL_MACROS = {
    { name = MACRO_NAME_PREFIX .. "1", body = "/yell ." },
    { name = MACRO_NAME_PREFIX .. "2", body = "/rw ." },
    { name = MACRO_NAME_PREFIX .. "3", body = "/raid ." },
}

Ulatek.SIGNAL_MACRO_COUNT = #SIGNAL_MACROS

-- True when creating signal macros was blocked by combat lockdown.
local macrosNeedCreate = false
local listening = false

local function DefaultIcon()
    return Macro.GetFileIDFromPath(DEFAULT_ICON_PATH)
end

---@param index integer
---@return { name: string, body: string }
local function MacroSpec(index)
    local spec = SIGNAL_MACROS[index]
    assert(spec, "Unknown signal macro: " .. tostring(index))
    return spec
end

---Account-wide macro name for signal `index` (1–3). At most 16 characters.
---@param index integer
---@return string
function Ulatek:GetSignalMacroName(index)
    return MacroSpec(index).name
end

---@param index integer
---@return string
function Ulatek:GetSignalMacroBody(index)
    return MacroSpec(index).body
end

---@param index integer
---@return boolean
function Ulatek:HasSignalMacro(index)
    return Macro.GetIndexByName(self:GetSignalMacroName(index)) > 0
end

---True when every signal macro already exists (queried live from the macro API).
---@return boolean
function Ulatek:HasAllSignalMacros()
    for index = 1, Ulatek.SIGNAL_MACRO_COUNT do
        if not self:HasSignalMacro(index) then
            return false
        end
    end
    return true
end

---@param index integer
---@param createIfMissing boolean
---@return boolean  Whether a macro was written.
local function WriteSignalMacro(index, createIfMissing)
    local spec = MacroSpec(index)
    local icon = DefaultIcon()
    local slot = Macro.GetIndexByName(spec.name)
    if slot > 0 then
        if Macro.Matches(slot, spec.name, icon, spec.body) then
            return false
        end
        Macro.Edit(slot, spec.name, icon, spec.body)
        return true
    end
    if createIfMissing then
        local created = Macro.Create(spec.name, icon, spec.body)
        if not created then
            error("CreateMacro failed")
        end
        return true
    end
    return false
end

---Rewrites existing signal macros to the expected name, icon, and body.
---Does not create missing macros.
---@return boolean  Whether any macro was updated immediately.
function Ulatek:SyncSignalMacros()
    if Combat.IsLockedDown() then
        return false
    end
    local updated = false
    for index = 1, Ulatek.SIGNAL_MACRO_COUNT do
        if WriteSignalMacro(index, false) then
            updated = true
        end
    end
    return updated
end

---Creates missing signal macros and refreshes existing ones. Blocked in combat.
---@return boolean ok
---@return "combat"|"failed"|nil reason
function Ulatek:CreateSignalMacros()
    if Combat.IsLockedDown() then
        macrosNeedCreate = true
        return false, "combat"
    end
    macrosNeedCreate = false
    for index = 1, Ulatek.SIGNAL_MACRO_COUNT do
        local ok = pcall(WriteSignalMacro, index, true)
        if not ok then
            return false, "failed"
        end
    end
    return true
end

---Applies deferred macro create when combat lockdown ends. Called from OnEnable.
function Ulatek:ListenForMacroSync()
    if listening then
        return
    end
    listening = true
    Combat.OnLeave(function()
        if not Ulatek:IsRaidCommander() then
            macrosNeedCreate = false
            return
        end
        if macrosNeedCreate then
            Ulatek:CreateSignalMacros()
        end
    end)
    Macro.OnChanged(function()
        if Ulatek:IsRaidCommander() then
            Ulatek:SyncSignalMacros()
        end
        if Ulatek.OnMacrosChanged then
            Ulatek:OnMacrosChanged()
        end
    end)
end

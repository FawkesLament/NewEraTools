local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Colors = ns.Assets.Colors
local Combat = ns.Api.Combat
local Macro = ns.Api.Macro
local Player = ns.Api.Player
local Spell = ns.Api.Spell

local TwinFangs = ns.Modules.Get("TwinFangs")
local Chain = Internals.InterruptChain

-- Macro UI names are capped at 16 characters.
local MACRO_NAME = "NETTwinFangInt"
local REPORT_TEXT = L.TWIN_FANGS_INTERRUPT_MACRO_REPORT

local listening = false
local pending = false
local leaveUnsub
local lastError
local lastErrorMessage

---@return TwinFangsInterruptChainSettings|nil
local function SavedChain()
    return TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
end

---@return TwinFangsInterruptMemberAssignment|nil
local function PrimaryAssignment()
    return Chain.GetMemberView(SavedChain(), Chain.ResolveLocalPlayerName()).primary
end

TwinFangs.ADDON_CHECK_MACRO_READY = "ready"
TwinFangs.ADDON_CHECK_MACRO_NOT_READY = "not_ready"
TwinFangs.ADDON_CHECK_MACRO_NA = "na"
TwinFangs.ADDON_CHECK_MACRO_UNKNOWN = "unknown"

---Same-realm whispers omit the realm; cross-realm keeps the cached suffix.
---@param name string
---@return string
local function WhisperTarget(name)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if not short then
        return name
    end
    local playerName = Player.GetFullName()
    local playerRealm = playerName and playerName:match("%-(.+)$")
    if playerRealm and realm == playerRealm then
        return short
    end
    return name
end

---@return number
local function CharacterCount()
    local _, count = Macro.GetNum()
    return count or 0
end

---Character-specific slot for this feature's macro, or 0.
---Ignores an account-wide macro that only shares the name.
---@return number
local function FindManagedIndex()
    local index = Macro.GetIndexByName(MACRO_NAME)
    if Macro.IsCharacterSlot(index) then
        return index
    end
    local first = Macro.ACCOUNT_SLOTS + 1
    local last = Macro.ACCOUNT_SLOTS + Macro.CHARACTER_SLOTS
    for slot = first, last do
        local name = Macro.GetInfo(slot)
        if name == MACRO_NAME then
            return slot
        end
    end
    return 0
end

---@return string|nil
---@return string|nil
local function BuildBody()
    local assignment = PrimaryAssignment()
    if not assignment then
        return nil, "unassigned"
    end

    local spell = Spell.GetInterruptName()
    if type(spell) ~= "string" or spell == "" then
        return nil, "no_spell"
    end

    local lines = {
        "#showtooltip",
        "/cast " .. spell,
        "/p " .. REPORT_TEXT,
    }
    local chain = SavedChain()
    local region = chain and chain[assignment.regionId]
    if region and region.backup ~= nil then
        local name = Chain.PlayerName(region.backup)
        if not name then
            return nil, "no_backup"
        end
        lines[#lines + 1] = "/w " .. WhisperTarget(name) .. " " .. REPORT_TEXT
    end

    local body = table.concat(lines, "\n")
    if #body > Macro.MAX_BODY_LENGTH then
        return nil, "too_long"
    end
    return body
end

---@return number
local function MacroIcon()
    return Macro.GetFileIDFromPath(ns.Assets.Icons.QUESTION_MARK)
end

local function ClearLeaveListener()
    if leaveUnsub then
        leaveUnsub()
        leaveUnsub = nil
    end
end

local function NotifyChanged()
    if TwinFangs.OnInterruptMacroChanged then
        TwinFangs:OnInterruptMacroChanged()
    end
end

local function SetError(reason, message)
    lastError = reason
    lastErrorMessage = message
end

local function ClearError()
    lastError = nil
    lastErrorMessage = nil
end

local function DeferUntilLeave()
    pending = true
    if leaveUnsub then
        return
    end
    leaveUnsub = Combat.OnLeave(function()
        ClearLeaveListener()
        if not pending then
            return
        end
        pending = false
        TwinFangs:MaintainInterruptMacro()
    end)
end

---@param index number
---@param body string
---@return boolean
local function EditManaged(index, body)
    local icon = MacroIcon()
    if Macro.Matches(index, MACRO_NAME, icon, body) then
        return true
    end
    local ok = pcall(Macro.Edit, index, MACRO_NAME, icon, body)
    return ok
end

---@param body string
---@return boolean
---@return string|nil
local function CreateManaged(body)
    if CharacterCount() >= Macro.CHARACTER_SLOTS then
        return false, "no_slots"
    end
    if Macro.GetIndexByName(MACRO_NAME) > 0 then
        -- Name is taken by an account-wide (or otherwise unmanaged) macro.
        return false, "failed"
    end
    local ok, index = pcall(Macro.Create, MACRO_NAME, MacroIcon(), body, true)
    if not ok or type(index) ~= "number" or index <= 0 then
        return false, "failed"
    end
    if index <= Macro.ACCOUNT_SLOTS then
        return false, "failed"
    end
    return true
end

---Stable character-macro name for this feature. At most 16 characters.
---@return string
function TwinFangs:GetInterruptMacroName()
    return MACRO_NAME
end

---Expected body for the current player's primary assignment, or nil.
---@return string|nil
---@return string|nil reason
function TwinFangs:GetInterruptMacroBody()
    return BuildBody()
end

---Read-only AddonCheck status. Does not create, edit, or repair the managed macro.
---@return "ready"|"not_ready"|"na"|"unknown"
function TwinFangs:InspectInterruptMacroReadiness()
    if not PrimaryAssignment() then
        return TwinFangs.ADDON_CHECK_MACRO_NA
    end
    local body = BuildBody()
    if not body then
        return TwinFangs.ADDON_CHECK_MACRO_UNKNOWN
    end
    local index = FindManagedIndex()
    if index == 0 then
        return TwinFangs.ADDON_CHECK_MACRO_NOT_READY
    end
    local _, _, current = Macro.GetInfo(index)
    if current == body then
        return TwinFangs.ADDON_CHECK_MACRO_READY
    end
    return TwinFangs.ADDON_CHECK_MACRO_NOT_READY
end

---@return boolean
function TwinFangs:HasInterruptMacro()
    return FindManagedIndex() > 0
end

---Creates the character-specific interrupt macro, or repairs it in place.
---@return boolean ok
---@return string|nil reason
function TwinFangs:CreateInterruptMacro()
    if Combat.IsLockedDown() then
        SetError("combat")
        NotifyChanged()
        return false, "combat"
    end
    pending = false
    ClearLeaveListener()

    local body, reason = BuildBody()
    if not body then
        SetError(reason)
        NotifyChanged()
        return false, reason
    end

    local index = FindManagedIndex()
    if index > 0 then
        if not EditManaged(index, body) then
            SetError("failed")
            NotifyChanged()
            return false, "failed"
        end
        ClearError()
        NotifyChanged()
        return true
    end

    local created, createReason = CreateManaged(body)
    if not created then
        SetError(createReason)
        NotifyChanged()
        return false, createReason
    end
    ClearError()
    NotifyChanged()
    return true
end

---Rewrites the existing character-specific interrupt macro when its body is stale.
---Does not create a missing macro. Defers during combat lockdown.
---@return boolean  Whether a macro was updated immediately.
function TwinFangs:MaintainInterruptMacro()
    if Combat.IsLockedDown() then
        DeferUntilLeave()
        NotifyChanged()
        return false
    end
    pending = false
    ClearLeaveListener()

    local body, reason = BuildBody()
    if not body then
        if reason ~= "unassigned" then
            SetError(reason)
        else
            ClearError()
        end
        NotifyChanged()
        return false
    end

    local index = FindManagedIndex()
    if index == 0 then
        ClearError()
        NotifyChanged()
        return false
    end

    local _, _, current = Macro.GetInfo(index)
    if current == body then
        ClearError()
        NotifyChanged()
        return false
    end

    if not EditManaged(index, body) then
        SetError("failed")
        NotifyChanged()
        return false
    end
    ClearError()
    NotifyChanged()
    return true
end

---@class TwinFangsInterruptChainMacroStatus
---@field shown boolean
---@field exists boolean
---@field buttonText string
---@field message string
---@field color table
---@field reason string

---@return TwinFangsInterruptChainMacroStatus
function TwinFangs:GetInterruptMacroStatus()
    if not ns.Api.Group.IsInRaid() then
        return {
            shown = false,
            exists = FindManagedIndex() > 0,
            buttonText = "",
            message = "",
            color = Colors.TEXT_MUTED,
            reason = "not_in_raid",
        }
    end
    if PrimaryAssignment() == nil then
        return {
            shown = false,
            exists = FindManagedIndex() > 0,
            buttonText = "",
            message = "",
            color = Colors.TEXT_MUTED,
            reason = "unassigned",
        }
    end

    local exists = FindManagedIndex() > 0
    local buttonText = exists and L.TWIN_FANGS_INTERRUPT_MACRO_REGENERATE or L.TWIN_FANGS_INTERRUPT_MACRO_CREATE
    local function Status(reason, message, color)
        return {
            shown = true,
            exists = exists,
            buttonText = buttonText,
            message = message,
            color = color,
            reason = reason,
        }
    end

    if Combat.IsLockedDown() and lastError == "combat" then
        return Status("combat", L.TWIN_FANGS_INTERRUPT_MACRO_IN_COMBAT, Colors.WARNING)
    end
    if lastError == "combat" then
        ClearError()
    end
    if pending then
        return Status("combat_pending", L.TWIN_FANGS_INTERRUPT_MACRO_PENDING, Colors.WARNING)
    end

    local body, reason = BuildBody()
    if reason == "no_spell" then
        return Status("no_spell", L.TWIN_FANGS_INTERRUPT_MACRO_NO_SPELL, Colors.ERROR)
    end
    if reason == "no_backup" then
        return Status("no_backup", L.TWIN_FANGS_INTERRUPT_MACRO_NO_BACKUP, Colors.ERROR)
    end
    if reason == "too_long" then
        return Status("too_long", L.TWIN_FANGS_INTERRUPT_MACRO_TOO_LONG, Colors.ERROR)
    end

    if lastError == "no_slots" then
        return Status("no_slots", L.TWIN_FANGS_INTERRUPT_MACRO_NO_SLOTS, Colors.ERROR)
    end
    if lastError == "failed" then
        return Status("failed", lastErrorMessage or L.TWIN_FANGS_INTERRUPT_MACRO_FAILED, Colors.ERROR)
    end

    if not exists then
        if CharacterCount() >= Macro.CHARACTER_SLOTS then
            return Status("no_slots", L.TWIN_FANGS_INTERRUPT_MACRO_NO_SLOTS, Colors.ERROR)
        end
        return Status("needed", L.TWIN_FANGS_INTERRUPT_MACRO_NEEDED, Colors.WARNING)
    end

    local index = FindManagedIndex()
    local _, _, current = Macro.GetInfo(index)
    if body and current == body then
        return Status("ready", L.TWIN_FANGS_INTERRUPT_MACRO_READY, Colors.SUCCESS)
    end
    return Status("failed", L.TWIN_FANGS_INTERRUPT_MACRO_FAILED, Colors.ERROR)
end

---Checks the existing macro after login/reload and when the interrupt spell may change.
function TwinFangs:ListenForInterruptMacro()
    if not listening then
        listening = true
        Player.OnChanged(function()
            TwinFangs:MaintainInterruptMacro()
        end)
        Macro.OnChanged(function()
            TwinFangs:MaintainInterruptMacro()
        end)
    end
    TwinFangs:MaintainInterruptMacro()
end

local _, ns = ...

local Macro = {}
ns.Api.Macro = Macro

---Account-wide slots occupy 1..ACCOUNT_SLOTS; character slots follow immediately after.
Macro.ACCOUNT_SLOTS = MAX_ACCOUNT_MACROS or 120
Macro.CHARACTER_SLOTS = MAX_CHARACTER_MACROS or 30
---CreateMacro/EditMacro reject bodies longer than this.
Macro.MAX_BODY_LENGTH = 255

---Creates a new macro. Protected during combat lockdown.
---`icon` should be a FileID; string paths often fail to render in the macro UI.
---`perCharacter` writes into the character-specific section.
---@type fun(name: string, icon: string|number, body: string|nil, perCharacter: boolean|nil): number|nil
Macro.Create = CreateMacro

---Edits an existing macro by index or name. Protected during combat lockdown.
---@type fun(macroInfo: string|number, name: string|nil, icon: string|number|nil, body: string|nil): number|nil
Macro.Edit = EditMacro

---Returns the macro slot for `name`, or 0 when no macro uses that name.
---May return an account-wide slot; prefer scanning character slots when the feature owns those only.
---@type fun(name: string): number
Macro.GetIndexByName = GetMacroIndexByName

---name, iconTexture, body, isLocal. `index` is a global slot (account then character).
---@type fun(index: number): string|nil, string|number|nil, string|nil, boolean|nil
Macro.GetInfo = GetMacroInfo

---Account-wide count, then character-specific count.
---@type fun(): number, number
Macro.GetNum = GetNumMacros

---FileID for an `Interface\\...` texture path. Prefer this over the path when calling Create/Edit.
---@type fun(filePath: string): number
Macro.GetFileIDFromPath = GetFileIDFromPath

---Calls `callback` when the player's macros change (create, edit, or delete).
---@param callback fun()
---@return fun()  Unsubscribe.
function Macro.OnChanged(callback)
    return ns.Api.GameEvents.Listen("UPDATE_MACROS", callback)
end

---@param index number
---@return boolean
function Macro.IsCharacterSlot(index)
    return type(index) == "number"
        and index > Macro.ACCOUNT_SLOTS
        and index <= Macro.ACCOUNT_SLOTS + Macro.CHARACTER_SLOTS
end

---True when slot `index` already has this name, icon, and body.
---@param index number
---@param name string
---@param icon string|number
---@param body string
---@return boolean
function Macro.Matches(index, name, icon, body)
    local currentName, currentIcon, currentBody = Macro.GetInfo(index)
    return currentName == name and currentIcon == icon and currentBody == body
end

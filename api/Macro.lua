local _, ns = ...

local Macro = {}
ns.Api.Macro = Macro

---Creates a new macro. Protected during combat lockdown.
---`icon` should be a FileID; string paths often fail to render in the macro UI.
---@type fun(name: string, icon: string|number, body: string|nil, perCharacter: boolean|nil): number|nil
Macro.Create = CreateMacro

---Edits an existing macro by index or name. Protected during combat lockdown.
---@type fun(macroInfo: string|number, name: string|nil, icon: string|number|nil, body: string|nil): number|nil
Macro.Edit = EditMacro

---Returns the macro slot for `name`, or 0 when no macro uses that name.
---@type fun(name: string): number
Macro.GetIndexByName = GetMacroIndexByName

---FileID for an `Interface\\...` texture path. Prefer this over the path when calling Create/Edit.
---@type fun(filePath: string): number
Macro.GetFileIDFromPath = GetFileIDFromPath

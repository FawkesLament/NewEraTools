local _, ns = ...

local Binding = {}
ns.Api.Binding = Binding

---Binds a key or click to a named button. Protected during combat lockdown.
---`key` uses binding syntax, e.g. "SHIFT-BUTTON1".
---@type fun(owner: Frame, isPriority: boolean, key: string, buttonName: string, mouseButton: string|nil)
Binding.SetOverrideClick = SetOverrideBindingClick

---Removes override bindings owned by `owner`. Protected during combat lockdown.
---@type fun(owner: Frame)
Binding.ClearOverrides = ClearOverrideBindings

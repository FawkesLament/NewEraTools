local addonName, ns = ...

local Client = {}
ns.Api.Client = Client

---Returns the client locale, e.g. "zhCN" or "enUS".
---@type fun(): string
Client.GetLocale = GetLocale

---Calls `callback` once this addon's files and saved variables have loaded.
---@param callback fun()
function Client.OnAddonLoaded(callback)
    ns.Api.GameEvents.Listen("ADDON_LOADED", function(loadedName)
        if loadedName == addonName then
            callback()
        end
    end)
end

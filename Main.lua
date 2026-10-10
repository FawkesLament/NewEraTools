local _, ns = ...

ns.Api.Client.OnAddonLoaded(function()
    NewEraToolsDB = ns.Database.Load(NewEraToolsDB)
    ns.Modules.Start(NewEraToolsDB)
end)

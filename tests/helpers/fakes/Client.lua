return function()
    local Client = { locale = "zhCN", loadedCallbacks = {} }

    function Client.GetLocale()
        return Client.locale
    end

    -- Same source as C_AddOns.GetAddOnMetadata(..., "Version"): the TOC field.
    function Client.GetAddonVersion()
        local file = assert(io.open("NewEraTools.toc", "r"))
        local version
        for line in file:lines() do
            version = line:gsub("\r$", ""):match("^## Version:%s*(%S+)")
            if version then
                break
            end
        end
        file:close()
        return version
    end

    function Client.OnAddonLoaded(callback)
        table.insert(Client.loadedCallbacks, callback)
    end

    return Client
end

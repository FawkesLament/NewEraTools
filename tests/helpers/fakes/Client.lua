return function()
    local Client = { locale = "zhCN", loadedCallbacks = {} }

    function Client.GetLocale()
        return Client.locale
    end

    function Client.OnAddonLoaded(callback)
        table.insert(Client.loadedCallbacks, callback)
    end

    return Client
end

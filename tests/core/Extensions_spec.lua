local Loader = require("helpers.loader")

describe("Extensions", function()
    local ns

    before_each(function()
        ns = Loader.Load()
    end)

    after_each(function()
        NewEraToolsAPI = nil
    end)

    local function ErrorText(ok, err)
        assert.is_false(ok)
        assert.equals("string", type(err))
        return err
    end

    it("registers a provider and returns it", function()
        local provider = { label = "alpha" }
        NewEraToolsAPI.RegisterExtension("example.notes", "alpha", provider)
        assert.equals(provider, ns.Extensions.Get("example.notes", "alpha"))
        assert.equals(provider, ns.Extensions.GetAll("example.notes").alpha)
        local dashed = {}
        NewEraToolsAPI.RegisterExtension("example.notes", "my-provider", dashed)
        assert.equals(dashed, ns.Extensions.Get("example.notes", "my-provider"))
        local limit = "a" .. string.rep("b", 63)
        NewEraToolsAPI.RegisterExtension(limit, "alpha", {})
        assert.equals("table", type(ns.Extensions.Get(limit, "alpha")))
    end)

    it("keeps extension types independent", function()
        local seen = {}
        ns.Extensions.OnRegistered("example.one", function(_, providerId)
            table.insert(seen, "one:" .. providerId)
        end)
        ns.Extensions.OnRegistered("example.two", function(_, providerId)
            table.insert(seen, "two:" .. providerId)
        end)

        local first = { kind = "one" }
        local second = { kind = "two" }
        NewEraToolsAPI.RegisterExtension("example.one", "alpha", first)
        ns.Extensions.Register("example.two", "alpha", second)

        assert.same({ "one:alpha", "two:alpha" }, seen)
        assert.equals(first, ns.Extensions.Get("example.one", "alpha"))
        assert.equals(second, ns.Extensions.Get("example.two", "alpha"))
        assert.is_nil(ns.Extensions.Get("example.one", "beta"))
        assert.same({}, ns.Extensions.GetAll("example.missing"))
    end)

    it("rejects a duplicate provider id without replacing the first", function()
        local calls = 0
        ns.Extensions.OnRegistered("example.notes", function()
            calls = calls + 1
        end)
        local original = { n = 1 }
        NewEraToolsAPI.RegisterExtension("example.notes", "alpha", original)
        local ok, err = pcall(NewEraToolsAPI.RegisterExtension, "example.notes", "alpha", { n = 2 })
        assert.is_true(ErrorText(ok, err):find("duplicate provider 'alpha' for 'example.notes'", 1, true) ~= nil)
        assert.equals(1, calls)
        assert.equals(original, ns.Extensions.Get("example.notes", "alpha"))
    end)

    it("rejects invalid registration arguments", function()
        local badTokens = { "", " ", "1abc", ".hidden", "has space", string.rep("a", 65) }
        for _, token in ipairs(badTokens) do
            local okType, errType = pcall(NewEraToolsAPI.RegisterExtension, token, "alpha", {})
            assert.is_true(ErrorText(okType, errType):find("valid extension type", 1, true) ~= nil)
            local okId, errId = pcall(NewEraToolsAPI.RegisterExtension, "example.notes", token, {})
            assert.is_true(ErrorText(okId, errId):find("valid provider id", 1, true) ~= nil)
        end
        for _, value in ipairs({ false, true, 0, "provider", function() end }) do
            local ok, err = pcall(NewEraToolsAPI.RegisterExtension, "example.notes", "alpha", value)
            assert.is_true(ErrorText(ok, err):find("provider table", 1, true) ~= nil)
        end
        local missingProvider, missingProviderErr =
            pcall(NewEraToolsAPI.RegisterExtension, "example.notes", "alpha", nil)
        assert.is_true(ErrorText(missingProvider, missingProviderErr):find("provider table", 1, true) ~= nil)
        local missingType, missingTypeErr = pcall(NewEraToolsAPI.RegisterExtension, nil, "alpha", {})
        assert.is_true(ErrorText(missingType, missingTypeErr):find("valid extension type", 1, true) ~= nil)
        local missingId, missingIdErr = pcall(NewEraToolsAPI.RegisterExtension, "example.notes", nil, {})
        assert.is_true(ErrorText(missingId, missingIdErr):find("valid provider id", 1, true) ~= nil)
        assert.is_nil(ns.Extensions.Get("example.notes", "alpha"))
    end)

    it("returns nil for an optional extension that was not registered", function()
        assert.is_nil(ns.Extensions.Get("example.notes", "alpha"))
        assert.same({}, ns.Extensions.GetAll("example.notes"))
    end)

    it("notifies listeners after the provider is stored and stops after unsubscribe", function()
        local calls = {}
        local stop = ns.Extensions.OnRegistered("example.notes", function(extensionType, providerId, provider)
            table.insert(calls, extensionType .. ":" .. providerId)
            assert.equals(provider, ns.Extensions.Get(extensionType, providerId))
        end)
        local provider = {}
        NewEraToolsAPI.RegisterExtension("example.notes", "alpha", provider)
        stop()
        stop()
        NewEraToolsAPI.RegisterExtension("example.notes", "beta", {})
        assert.same({ "example.notes:alpha" }, calls)
        assert.equals("table", type(ns.Extensions.Get("example.notes", "beta")))
    end)

    it("drops a registration when a listener rejects it", function()
        local stop = ns.Extensions.OnRegistered("example.guard", function()
            error("rejected")
        end)
        local ok, err = pcall(NewEraToolsAPI.RegisterExtension, "example.guard", "alpha", { n = 1 })
        assert.is_true(ErrorText(ok, err):find("rejected", 1, true) ~= nil)
        assert.is_nil(ns.Extensions.Get("example.guard", "alpha"))
        assert.same({}, ns.Extensions.GetAll("example.guard"))
        stop()
        local provider = { n = 2 }
        NewEraToolsAPI.RegisterExtension("example.guard", "alpha", provider)
        assert.equals(provider, ns.Extensions.Get("example.guard", "alpha"))
    end)

    it("does not read or call into the provider while registering", function()
        local provider = setmetatable({}, {
            __index = function()
                error("provider indexed")
            end,
            __newindex = function()
                error("provider written")
            end,
        })
        NewEraToolsAPI.RegisterExtension("example.opaque", "alpha", provider)
        assert.equals(provider, ns.Extensions.Get("example.opaque", "alpha"))
    end)

    it("accepts a registration after the host has initialized", function()
        ns.Modules.Start(ns.Database.Load(nil))
        local seen = false
        ns.Extensions.OnRegistered("example.notes", function(_, _, provider)
            seen = provider.ready
        end)
        local provider = { ready = true }
        NewEraToolsAPI.RegisterExtension("example.notes", "alpha", provider)
        assert.is_true(seen)
        assert.equals(provider, ns.Extensions.Get("example.notes", "alpha"))
        assert.same({}, ns.Extensions.GetAll("example.other"))
    end)

    it("keeps a provider registered before host initialization", function()
        local provider = { ready = true }
        NewEraToolsAPI.RegisterExtension("example.notes", "early", provider)
        ns.Modules.Start(ns.Database.Load(nil))
        assert.equals(provider, ns.Extensions.Get("example.notes", "early"))
    end)

    it("publishes one capability object per extension type", function()
        local capabilities = { apiVersion = 1 }
        ns.Extensions.SetCapabilities("example.notes", capabilities)
        assert.equals(capabilities, NewEraToolsAPI.GetCapabilities("example.notes"))
        assert.equals(capabilities, ns.Extensions.GetCapabilities("example.notes"))
        local duplicateOk, duplicateErr = pcall(ns.Extensions.SetCapabilities, "example.notes", {})
        assert.is_true(ErrorText(duplicateOk, duplicateErr):find("duplicate capabilities", 1, true) ~= nil)
        local missingOk, missingErr = pcall(NewEraToolsAPI.GetCapabilities, "example.missing")
        assert.is_true(ErrorText(missingOk, missingErr):find("unknown extension type", 1, true) ~= nil)
        local badOk, badErr = pcall(NewEraToolsAPI.GetCapabilities, "")
        assert.is_true(ErrorText(badOk, badErr):find("valid extension type", 1, true) ~= nil)
    end)

    it("exposes registration and capability lookup on the public table", function()
        local names = {}
        for key in pairs(NewEraToolsAPI) do
            table.insert(names, key)
        end
        table.sort(names)
        assert.same({ "GetCapabilities", "RegisterExtension" }, names)
        assert.equals("function", type(NewEraToolsAPI.RegisterExtension))
        assert.equals("function", type(NewEraToolsAPI.GetCapabilities))
        assert.is_false(NewEraToolsAPI == ns)
        assert.is_nil(NewEraToolsAPI.ns)
        assert.is_nil(NewEraToolsAPI.Modules)
        assert.is_nil(NewEraToolsAPI.Extensions)
        assert.is_nil(_G.ns)
        assert.is_nil(_G.Extensions)
        assert.is_nil(_G.Sszorak)
        assert.equals(NewEraToolsAPI, _G.NewEraToolsAPI)
    end)

    it("rejects invalid lookup and subscription arguments", function()
        local okGet, errGet = pcall(ns.Extensions.Get, "example.notes", "")
        assert.is_true(ErrorText(okGet, errGet):find("valid extension type and provider id", 1, true) ~= nil)
        local okAll, errAll = pcall(ns.Extensions.GetAll, "")
        assert.is_true(ErrorText(okAll, errAll):find("valid extension type", 1, true) ~= nil)
        local okCallback, errCallback = pcall(ns.Extensions.OnRegistered, "example.notes", nil)
        assert.is_true(ErrorText(okCallback, errCallback):find("requires a callback", 1, true) ~= nil)
    end)

    it("returns a copy of the provider map", function()
        local provider = { n = 1 }
        NewEraToolsAPI.RegisterExtension("example.notes", "alpha", provider)
        local all = ns.Extensions.GetAll("example.notes")
        all.beta = {}
        all.alpha = nil
        assert.is_nil(ns.Extensions.Get("example.notes", "beta"))
        assert.equals(provider, ns.Extensions.Get("example.notes", "alpha"))
    end)
end)

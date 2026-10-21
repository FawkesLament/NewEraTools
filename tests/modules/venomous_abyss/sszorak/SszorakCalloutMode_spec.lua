local Harness = require("helpers.sszorak")
local Loader = require("helpers.loader")

describe("SszorakCallout", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    describe("callout mode", function()
        it("defaults to normal", function()
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("starts with normal and without jailbreak", function()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("keeps a saved jailbreak preference while that provider is absent", function()
            ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetPreferredCalloutMode())
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
            Sszorak:ListenForCalloutMode()
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("rejects unknown modes", function()
            assert.is_false(pcall(Sszorak.SetCalloutMode, Sszorak, "banana"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("requires Listen and OnViscousCystWarning on registered modes", function()
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
            }))
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return function() end
                end,
            }))
        end)
    end)

    describe("external communication extensions", function()
        after_each(function()
            NewEraToolsAPI = nil
        end)

        local function StubMode(id)
            return {
                id = id,
                listened = false,
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function(self)
                    self.listened = true
                    return function() end
                end,
                OnViscousCystWarning = function()
                    return nil
                end,
            }
        end

        local function ErrorText(ok, err)
            assert.is_false(ok)
            assert.equals("string", type(err))
            return err
        end

        it("keeps normal available when nothing external is registered", function()
            assert.equals("sszorak.communication", Sszorak.COMMUNICATION_EXTENSION)
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.is_nil(ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_nil(ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK))
        end)

        it("adopts a new provider after initialization without activating it", function()
            Sszorak:ListenForCalloutMode()
            local provider = StubMode("relay")
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, "relay", provider)

            assert.equals(provider, ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, "relay"))
            assert.is_true(Sszorak.IsCalloutModeAvailable("relay"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
            assert.is_false(provider.listened)
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))

            Sszorak:SetCalloutMode("relay")
            assert.is_true(provider.listened)
            assert.equals("relay", Sszorak:GetActiveCalloutMode().id)
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_NORMAL)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("does not adopt providers for other extension types", function()
            NewEraToolsAPI.RegisterExtension("example.notes", "relay", StubMode("relay"))
            assert.is_false(Sszorak.IsCalloutModeAvailable("relay"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("rejects a second provider with the same id", function()
            local first = StubMode("relay")
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, "relay", first)
            local second = StubMode("relay")
            local ok, err = pcall(NewEraToolsAPI.RegisterExtension, Sszorak.COMMUNICATION_EXTENSION, "relay", second)
            assert.is_true(ErrorText(ok, err):find("duplicate provider 'relay'", 1, true) ~= nil)
            assert.equals(first, ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, "relay"))
            assert.equals(first, Sszorak.GetRegisteredCalloutMode("relay"))
            assert.is_false(second.listened)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("activates a saved jailbreak preference when that provider registers", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            }))
            Sszorak = ns.Modules.Get("Sszorak")
            Sszorak:ListenForCalloutMode()
            local changes = 0
            function Sszorak:OnCalloutModesChanged()
                changes = changes + 1
            end
            local provider = StubMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK, provider)
            assert.is_true(provider.listened)
            assert.is_true(changes >= 1)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetPreferredCalloutMode())
            assert.equals(provider, Sszorak:GetActiveCalloutMode())
            assert.equals(provider, ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK))
        end)

        it("defers a saved jailbreak preference until the current pull ends", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            }))
            Sszorak = ns.Modules.Get("Sszorak")
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForEncounter()
            ns.Api.Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            local provider = StubMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK, provider)
            assert.is_false(provider.listened)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetPreferredCalloutMode())
            ns.Api.Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_true(provider.listened)
            assert.equals(provider, Sszorak:GetActiveCalloutMode())
        end)

        it("defers a saved jailbreak preference until map-test capture ends", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            }))
            Sszorak = ns.Modules.Get("Sszorak")
            Sszorak:ListenForCalloutMode()
            Sszorak:StartMapTest()
            local provider = StubMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK, provider)
            assert.is_false(provider.listened)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            Sszorak:EndMapTest()
            assert.is_true(provider.listened)
            assert.equals(provider, Sszorak:GetActiveCalloutMode())
        end)

        it("rewrites commander macros when a late provider becomes active, after combat ends", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            }))
            Sszorak = ns.Modules.Get("Sszorak")
            ns.Api.Group.isRaidLeader = true
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForMacroSync()
            assert.is_true(Sszorak:CreateEdgeMacros())
            local name = Sszorak:GetEdgeMacroName(2)
            assert.equals("/raid {rt4}", ns.Api.Macro.Get(name).body)

            ns.Api.Combat.FireEnter()
            local provider = StubMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            provider.GetEdgeMacroBody = function()
                return "/raid switched"
            end
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK, provider)
            assert.is_true(provider.listened)
            assert.equals("/raid {rt4}", ns.Api.Macro.Get(name).body)
            ns.Api.Combat.FireLeave()
            assert.equals("/raid switched", ns.Api.Macro.Get(name).body)
        end)

        it("rejects an external provider that reuses the built-in normal id", function()
            local builtin = Sszorak:GetActiveCalloutMode()
            local external = StubMode(Sszorak.CALLOUT_MODE_NORMAL)
            local ok, err = pcall(
                NewEraToolsAPI.RegisterExtension,
                Sszorak.COMMUNICATION_EXTENSION,
                Sszorak.CALLOUT_MODE_NORMAL,
                external
            )
            assert.is_true(ErrorText(ok, err):find("already registered: normal", 1, true) ~= nil)
            assert.equals(builtin, Sszorak:GetActiveCalloutMode())
            assert.is_nil(ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_false(external.listened)
        end)

        it("rejects a communication provider that breaks the callout mode contract", function()
            local mismatched = StubMode("other")
            local okId, errId =
                pcall(NewEraToolsAPI.RegisterExtension, Sszorak.COMMUNICATION_EXTENSION, "relay", mismatched)
            assert.is_true(ErrorText(okId, errId):find("must match the provider id", 1, true) ~= nil)
            assert.is_false(Sszorak.IsCalloutModeAvailable("relay"))
            assert.is_false(Sszorak.IsCalloutModeAvailable("other"))

            local incomplete = {
                id = "relay",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return function() end
                end,
            }
            local okContract, errContract =
                pcall(NewEraToolsAPI.RegisterExtension, Sszorak.COMMUNICATION_EXTENSION, "relay", incomplete)
            assert.is_true(ErrorText(okContract, errContract):find("callout mode contract", 1, true) ~= nil)
            assert.is_nil(ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, "relay"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
        end)
    end)
end)

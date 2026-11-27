local Loader = require("helpers.loader")

describe("SharedMedia fonts", function()
    local ns
    local previousLibStub

    before_each(function()
        previousLibStub = rawget(_G, "LibStub")
        _G.LibStub = nil
        ns = Loader.Load()
    end)

    after_each(function()
        _G.LibStub = previousLibStub
    end)

    it("lists only the built-in default when LibSharedMedia is absent", function()
        assert.same({ ns.SharedMedia.FONT_DEFAULT }, ns.SharedMedia.ListFontIds())
        assert.is_true(ns.SharedMedia.IsKnownFont(ns.SharedMedia.FONT_DEFAULT))
        assert.is_false(ns.SharedMedia.IsKnownFont("Friz"))
        assert.is_nil(ns.SharedMedia.ResolveFontPath(ns.SharedMedia.FONT_DEFAULT))
        assert.is_nil(ns.SharedMedia.ResolveFontPath("Friz"))
    end)

    it("lists built-in status-bar textures when LibSharedMedia is absent", function()
        assert.same({ "flat", "default", "raid" }, ns.SharedMedia.ListStatusBarTextureIds())
        assert.is_true(ns.SharedMedia.IsKnownStatusBarTexture("flat"))
        assert.is_false(ns.SharedMedia.IsKnownStatusBarTexture("Smooth"))
        assert.equals(ns.Assets.Textures.WHITE, ns.SharedMedia.ResolveStatusBarTexturePath("flat"))
        assert.equals(ns.Assets.Textures.WHITE, ns.SharedMedia.ResolveStatusBarTexturePath("missing"))
    end)
end)

describe("SharedMedia LibSharedMedia fonts", function()
    local ns
    local previousLibStub
    local fakeLSM
    local registeredCallbacks

    before_each(function()
        previousLibStub = rawget(_G, "LibStub")
        registeredCallbacks = {}
        fakeLSM = {
            media = {
                font = {
                    Friz = "Fonts\\FRIZQT__.TTF",
                },
            },
        }
        function fakeLSM:List(mediaType)
            local names = {}
            for name in pairs(self.media[mediaType] or {}) do
                names[#names + 1] = name
            end
            table.sort(names)
            return names
        end
        function fakeLSM:Fetch(mediaType, key, noDefault)
            local path = self.media[mediaType] and self.media[mediaType][key]
            if path then
                return path
            end
            if not noDefault then
                return "Fonts\\ARIALN.TTF"
            end
            return nil
        end
        function fakeLSM.RegisterCallback(_, event, handler)
            registeredCallbacks[#registeredCallbacks + 1] = { event = event, handler = handler }
        end
        _G.LibStub = function(name, silent)
            if name == "LibSharedMedia-3.0" then
                return fakeLSM
            end
            if silent then
                return nil
            end
            error("library not found: " .. tostring(name))
        end
        ns = Loader.Load()
    end)

    after_each(function()
        _G.LibStub = previousLibStub
    end)

    it("lists default first, then LSM font handles", function()
        assert.same({ ns.SharedMedia.FONT_DEFAULT, "Friz" }, ns.SharedMedia.ListFontIds())
        assert.is_true(ns.SharedMedia.IsKnownFont("Friz"))
        assert.equals("Fonts\\FRIZQT__.TTF", ns.SharedMedia.ResolveFontPath("Friz"))
        assert.is_nil(ns.SharedMedia.ResolveFontPath(ns.SharedMedia.FONT_DEFAULT))
    end)

    it("lists built-in status bars and LSM handles without duplicating paths", function()
        fakeLSM.media.statusbar = {
            Smooth = "Interface\\Buttons\\YELLOWORANGE64",
            Blizzard = ns.Assets.Textures.STATUS_BAR,
        }
        local ids = ns.SharedMedia.ListStatusBarTextureIds()
        assert.equals("flat", ids[1])
        assert.equals("default", ids[2])
        assert.equals("raid", ids[3])
        local foundSmooth = false
        local foundBlizzard = false
        for _, id in ipairs(ids) do
            if id == "Smooth" then
                foundSmooth = true
            end
            if id == "Blizzard" then
                foundBlizzard = true
            end
        end
        assert.is_true(foundSmooth)
        assert.is_false(foundBlizzard)
        assert.equals("Interface\\Buttons\\YELLOWORANGE64", ns.SharedMedia.ResolveStatusBarTexturePath("Smooth"))
    end)

    it("notifies listeners when a font is registered", function()
        local calls = 0
        ns.SharedMedia.OnFontsRegistered(function()
            calls = calls + 1
        end)
        assert.equals(1, #registeredCallbacks)
        assert.equals("LibSharedMedia_Registered", registeredCallbacks[1].event)
        registeredCallbacks[1].handler(nil, "font")
        registeredCallbacks[1].handler(nil, "statusbar")
        assert.equals(1, calls)
    end)

    it("notifies listeners when a status bar is registered", function()
        local calls = 0
        ns.SharedMedia.OnStatusBarsRegistered(function()
            calls = calls + 1
        end)
        registeredCallbacks[1].handler(nil, "statusbar")
        registeredCallbacks[1].handler(nil, "font")
        assert.equals(1, calls)
    end)
end)

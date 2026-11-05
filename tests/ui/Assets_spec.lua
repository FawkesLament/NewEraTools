local Loader = require("helpers.loader")

describe("Assets.PrewarmFontFiles", function()
    local originalUIParent

    local function FakeParent()
        local parent = { fontStrings = {} }
        function parent:CreateFontString()
            local label = {}
            function label:SetFont(path, size, flags)
                self.fonts = self.fonts or {}
                self.fonts[#self.fonts + 1] = { path = path, size = size, flags = flags }
            end
            function label:SetPoint() end
            function label:SetAlpha() end
            function label:SetText(text)
                self.text = text
            end
            self.fontStrings[#self.fontStrings + 1] = label
            return label
        end
        return parent
    end

    before_each(function()
        originalUIParent = UIParent
        UIParent = nil
    end)

    after_each(function()
        UIParent = originalUIParent
    end)

    it("does nothing when UIParent is missing", function()
        local ns = Loader.Load()
        ns.Assets.PrewarmFontFiles()
    end)

    it("loads each bundled font file onto a hidden FontString", function()
        UIParent = FakeParent()
        local ns = { ADDON_NAME = Loader.ADDON_NAME }
        assert(loadfile("ui/Assets.lua"))(Loader.ADDON_NAME, ns)

        assert.equals(1, #UIParent.fontStrings)
        local warm = UIParent.fontStrings[1]
        local warmed = {}
        for i = 1, #warm.fonts do
            warmed[warm.fonts[i].path] = true
        end
        for _, path in pairs(ns.Assets.FontFiles) do
            assert.equals(true, warmed[path])
        end
        assert.equals("0123456789", warm.text)

        ns.Assets.PrewarmFontFiles()
        assert.equals(1, #UIParent.fontStrings)
    end)
end)


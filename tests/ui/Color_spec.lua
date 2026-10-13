local Loader = require("helpers.loader")

describe("Color", function()
    local Color

    before_each(function()
        Color = Loader.Load().Color
    end)

    it("Normalize clamps channels and rejects bad input", function()
        assert.same({ r = 0, g = 1, b = 0.5 }, Color.Normalize({ r = -1, g = 2, b = 0.5 }))
        assert.is_nil(Color.Normalize(nil))
        assert.is_nil(Color.Normalize({ r = 1, g = 1 }))
    end)

    it("Equal compares channels", function()
        assert.is_true(Color.Equal({ r = 0.1, g = 0.2, b = 0.3 }, { r = 0.1, g = 0.2, b = 0.3 }))
        assert.is_false(Color.Equal({ r = 0.1, g = 0.2, b = 0.3 }, { r = 0.1, g = 0.2, b = 0.4 }))
    end)

    it("Copy mutates the destination in place", function()
        local saved = { r = 0, g = 0, b = 0 }
        Color.Copy(saved, { r = 0.5, g = 0.25, b = 1 })
        assert.same({ r = 0.5, g = 0.25, b = 1 }, saved)
    end)
end)

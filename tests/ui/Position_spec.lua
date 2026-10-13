local Loader = require("helpers.loader")

describe("Position", function()
    local Position

    before_each(function()
        Position = Loader.Load().Position
    end)

    it("accepts a complete anchor table", function()
        assert.is_true(Position.IsValid({
            point = "CENTER",
            relativePoint = "TOPLEFT",
            x = 1,
            y = -2,
        }))
    end)

    it("rejects incomplete or wrong-typed tables", function()
        assert.is_false(Position.IsValid(nil))
        assert.is_false(Position.IsValid({ point = "CENTER", relativePoint = "CENTER", x = 0 }))
        assert.is_false(Position.IsValid({
            point = "CENTER",
            relativePoint = "CENTER",
            x = "0",
            y = 0,
        }))
    end)
end)

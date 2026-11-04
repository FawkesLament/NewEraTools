describe("pending example", function()
    pending("is skipped", "real-log fixture is absent: tests/example.lua")

    it("still runs", function()
        assert.is_true(true)
    end)
end)

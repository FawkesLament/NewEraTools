describe("teardown", function()
    after_each(function()
        error("teardown-boom")
    end)

    it("fails in the body", function()
        error("body-boom")
    end)
end)

local log = {}

describe("single", function()
    before_each(function()
        table.insert(log, "before")
    end)
    after_each(function()
        table.insert(log, "after")
    end)

    it("runs the only hooks", function()
        table.insert(log, "body")
    end)
end)

assert.same({ "before", "body", "after" }, log)

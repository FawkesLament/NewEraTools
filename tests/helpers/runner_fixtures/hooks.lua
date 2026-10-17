local log = {}

local function Mark(name)
    return function()
        table.insert(log, name)
    end
end

describe("outer", function()
    before_each(Mark("outer-before-1"))
    before_each(Mark("outer-before-2"))
    after_each(Mark("outer-after-1"))
    after_each(Mark("outer-after-2"))

    describe("inner", function()
        before_each(Mark("inner-before-1"))
        before_each(Mark("inner-before-2"))
        after_each(Mark("inner-after-1"))
        after_each(Mark("inner-after-2"))

        it("runs every hook", function()
            table.insert(log, "body")
        end)
    end)
end)

-- it() has already finished, including after hooks, because examples run immediately.
assert.same({
    "outer-before-1",
    "outer-before-2",
    "inner-before-1",
    "inner-before-2",
    "body",
    "inner-after-2",
    "inner-after-1",
    "outer-after-2",
    "outer-after-1",
}, log)

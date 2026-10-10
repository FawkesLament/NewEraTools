local Loader = require("helpers.loader")

describe("Database", function()
    local Database

    before_each(function()
        Database = Loader.Load().Database
    end)

    it("creates missing saved variables at the current schema", function()
        local saved = Database.Load(nil)
        assert.equals("number", type(saved.schemaVersion))
        assert.same({}, saved.modules)
    end)

    it("keeps existing module settings and fills in defaults", function()
        local saved = Database.Load({ modules = { Test = { count = 3 } } })
        local settings = Database.GetModuleSettings(saved, "Test", { count = 1, excluded = {} })
        assert.same({ count = 3, excluded = {} }, settings)
        assert.equals(settings, saved.modules.Test)
    end)
end)

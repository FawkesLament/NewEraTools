local Fs = require("helpers.fs")
local Loader = require("helpers.loader")

describe("Load order", function()
    local entries = Loader.ReadLoadOrder()
    local listed = {}
    for _, entry in ipairs(entries) do
        listed[entry.path] = true
    end

    it("references only files that exist", function()
        for _, entry in ipairs(entries) do
            assert(Fs.Exists(entry.path), entry.listedBy .. " references a missing file: " .. entry.path)
        end
    end)

    it("loads every addon Lua file and XML manifest", function()
        for _, path in ipairs(Fs.ListFiles()) do
            if (path:find("%.lua$") or path:find("%.xml$")) and not path:find("^tests/") then
                assert(listed[path], "Not loaded by the TOC or any manifest: " .. path)
            end
        end
    end)

    it("loads each file once", function()
        local seen = {}
        for _, entry in ipairs(entries) do
            assert(not seen[entry.path], entry.path .. " is listed twice")
            seen[entry.path] = true
        end
    end)

    it("has a test fake for every api file", function()
        for _, path in ipairs(Loader.ReadLuaFiles()) do
            local name = path:match("^api/(.+)%.lua$")
            if name then
                assert(Fs.Exists("tests/helpers/fakes/" .. name .. ".lua"), "Missing fake for " .. path)
            end
        end
    end)
end)
